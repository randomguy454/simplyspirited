--[[
    simplyspirited v4.6 — closure inspector
    SHADOWMILESC / computerizedcarrier2

    function forensics. when a captured call carries a function
    argument, this module opens it: lineage, upvalues, constants,
    parameter shape, and (v4.6) the closure graph — functions
    referencing functions, mapped recursively.

    design rules:
    - every debug.* access pcall'd; degradation is reported per
      layer, never silent
    - recursion bounded (depth 3, 40 nodes) — a hostile closure
      graph can't stall the suite
    - the probe runs at boot AND at autopsy time (executors
      unlock capabilities dynamically; boot-time probing lies)
]]

print("[SS2-closure] v4.6 loading...")

local SS2 = getgenv().SS2
if not SS2 then
    warn("ss2-closure: core.lua must load first")
    return
end

SS2.closure = {
    autopsies = 0,     -- total functions opened this session
    nodesVisited = 0,  -- closure-graph nodes
    graphs = {},       -- [scriptName] = last autopsy report
}

-- ════════════════════════════════════════════════════════════
-- capability probe — cheap, safe, runs on a dummy each time
-- it's needed (executors can unlock mid-session)
-- ════════════════════════════════════════════════════════════
local capsCache = nil
local function caps()
    if capsCache then return capsCache end
    local c = { info = false, upvalue = false, constants = false, registry = false }

    pcall(function()
        if debug and debug.getinfo then
            local probe = function() return 1 end
            if debug.getinfo(probe, "Su") then c.info = true end
        end
    end)
    pcall(function()
        if debug and debug.getupvalue then
            local secret = 42
            local probe = function() return secret end
            local name, val = debug.getupvalue(probe, 1)
            if name == "secret" and val == 42 then c.upvalue = true end
        end
    end)
    pcall(function()
        if debug and debug.getconstants then
            local probe = function() return "probe_const" end
            local consts = debug.getconstants(probe)
            if type(consts) == "table" then c.constants = true end
        end
    end)
    pcall(function()
        if debug and debug.getregistry then c.registry = true end
    end)

    capsCache = c
    return c
end

-- probe immediately so boot log reports reality
do
    local c = caps()
    print(("[SS2-closure] caps: info=%s upvalues=%s constants=%s"):format(
        tostring(c.info), tostring(c.upvalue), tostring(c.constants)))
    if not c.upvalue then
        print("[SS2-closure] note: upvalues blocked — autopsies degrade to")
        print("[SS2-closure] constants + lineage. re-exec may unlock later.")
    end
end

-- ════════════════════════════════════════════════════════════
-- value previewer: safe, bounded, typed
-- ════════════════════════════════════════════════════════════
local function preview(v, depth)
    depth = depth or 0
    local t = typeof(v)

    if t == "number" or t == "boolean" or t == "nil" then
        return tostring(v)
    elseif t == "string" then
        if #v <= 50 then return '"' .. v .. '"' end
        return ('str(%d):"%s…"'):format(#v, v:sub(1, 35))
    elseif t == "table" then
        if depth >= 1 then return "table" end
        -- one level of keys: table shapes reveal config intent
        local keys, n = {}, 0
        for k in pairs(v) do
            n = n + 1
            keys[#keys + 1] = typeof(k) == "string" and k or ("[" .. typeof(k) .. "]")
            if n >= 6 then break end
        end
        if #keys == 0 then return "table{}" end
        return "table {" .. table.concat(keys, ",") .. (#keys >= 6 and ",…" or "") .. "}"
    elseif t == "Instance" then
        return v.ClassName .. ":" .. v.Name
    elseif t == "function" then
        return "function(nested)"
    elseif t == "CFrame" then
        local p = v.Position
        return ("CF(%.1f,%.1f,%.1f)"):format(p.X, p.Y, p.Z)
    elseif t == "Vector3" then
        return ("V3(%.1f,%.1f,%.1f)"):format(v.X, v.Y, v.Z)
    elseif t == "EnumItem" then
        return tostring(v)
    else
        return t
    end
end

-- ════════════════════════════════════════════════════════════
-- THE AUTOPSY — one function, all layers, bounded recursion
-- returns report string + structured result
-- ════════════════════════════════════════════════════════════
local function autopsy(fn, depth, nodeCount)
    depth = depth or 0
    nodeCount = nodeCount or { n = 0 }

    if type(fn) ~= "function" then
        return "not a function (" .. typeof(fn) .. ")", {}
    end
    if depth > 3 or nodeCount.n > 40 then
        return "… (graph truncated — depth/size bound)", {}
    end
    nodeCount.n = nodeCount.n + 1
    SS2.closure.nodesVisited = SS2.closure.nodesVisited + 1

    local c = caps()
    local out = { ("closure @depth%d {"):format(depth) }
    local result = { upvalues = {}, constants = {}, lineage = nil }

    -- ── layer 1: lineage ──
    if c.info then
        pcall(function()
            local info = debug.getinfo(fn, "Su")
            if info then
                result.lineage = {
                    source = info.source,
                    line = info.linedefined,
                    nparams = info.nparams,
                    nups = info.nups,
                    what = info.what,
                }
                out[#out + 1] = ("  source:   %s"):format(
                    tostring(info.source):sub(1, 70))
                out[#out + 1] = ("  line:     %s  | what: %s"):format(
                    tostring(info.linedefined or "?"), tostring(info.what or "?"))
                out[#out + 1] = ("  params:   %s | upvalue slots: %s"):format(
                    tostring(info.nparams or "?"), tostring(info.nups or "?"))
            end
        end)
    else
        out[#out + 1] = "  lineage: (getinfo unavailable)"
    end

    -- ── layer 2: upvalues — the captured world ──
    if c.upvalue then
        local got = 0
        pcall(function()
            local i = 1
            while i <= 25 do
                local name, value = debug.getupvalue(fn, i)
                if not name then break end
                got = got + 1
                result.upvalues[i] = { name = name, value = value, preview = preview(value, depth + 1) }
                out[#out + 1] = ("  up[%d] %s = %s"):format(i, name, result.upvalues[i].preview)
                -- v4.6: nested function upvalues get recursed (graph mapping)
                if typeof(value) == "function" and depth < 2 then
                    local nestedReport = autopsy(value, depth + 1, nodeCount)
                    out[#out + 1] = "  └─ nested:"
                    for line in nestedReport:gmatch("[^\n]+") do
                        out[#out + 1] = "      " .. line
                    end
                end
                i = i + 1
            end
        end)
        if not got then
            out[#out + 1] = "  upvalues: (none)"
        end
    else
        out[#out + 1] = "  upvalues: (blocked by executor)"
    end

    -- ── layer 3: constants — what it references ──
    if c.constants then
        pcall(function()
            local consts = debug.getconstants(fn)
            local strs, nums = {}, {}
            for _, k in ipairs(consts or {}) do
                if type(k) == "string" and #k >= 3 then
                    strings = strings or {}
                    strs[#strs + 1] = k
                elseif type(k) == "number" then
                    nums[#nums + 1] = k
                end
            end
            result.constants = strs
            if #strs > 0 then
                out[#out + 1] = ("  constants (%d strings):"):format(#strs)
                for k = 1, math.min(10, #strs) do
                    out[#out + 1] = ('    "%s"'):format(strs[k]:sub(1, 55))
                end
                if #strs > 10 then
                    out[#out + 1] = ("    … +%d more"):format(#strs - 10)
                end
            end
            if #nums > 0 then
                local numStrs = {}
                for k = 1, math.min(8, #nums) do
                    numStrs[#numStrs + 1] = tostring(nums[k])
                end
                out[#out + 1] = "  numbers: " .. table.concat(numStrs, ", ")
            end
        end)
    else
        out[#out + 1] = "  constants: (blocked by executor)"
    end

    out[#out + 1] = "}"
    return table.concat(out, "\n"), result
end
SS2.closure.autopsy = autopsy

-- ════════════════════════════════════════════════════════════
-- public: inspect any function
-- ════════════════════════════════════════════════════════════
function SS2.inspectClosure(fn, depth)
    local report, data = autopsy(fn, depth or 0)
    print(report)
    SS2.closure.autopsies = SS2.closure.autopsies + 1
    return report, data
end

-- inspect the last captured call's function args
function SS2.inspectLast()
    local rec = SS2.log[#SS2.log]
    if not rec then
        print("[closure] no calls captured yet")
        return
    end
    print("═══ closure inspection: call #" .. rec.id .. " — " .. rec.name .. " ═══")
    local found = 0
    for i, raw in ipairs(rec.raw or {}) do
        if type(raw) == "function" then
            found = found + 1
            print(("── arg[%d] ──"):format(i))
            local report = autopsy(raw, 0)
            print(report)
        end
    end
    if found == 0 then
        print("  (no function args in this call)")
    else
        SS2.closure.autopsies = SS2.closure.autopsies + found
    end
end

-- full sweep: every function arg in the entire session log
function SS2.inspectAll()
    print("═══ full closure sweep ═══")
    local found = 0
    for _, rec in ipairs(SS2.log) do
        for i, raw in ipairs(rec.raw or {}) do
            if type(raw) == "function" then
                found = found + 1
                print(("── #%d %s arg[%d] ──"):format(rec.id, rec.name, i))
                print(autopsy(raw, 0))
                if found >= 20 then
                    print("… (sweep capped at 20 — the log is big)")
                    print(("total found so far: %d"):format(found))
                    return
                end
            end
        end
    end
    print("  function args in log: " .. found)
end
SS2.inspectAll = SS2.inspectAll

-- ════════════════════════════════════════════════════════════
-- recorder patch: function args in the FEED get one-line
-- summaries with lineage — the feed shows *what* a function is
-- without running the full autopsy
-- ════════════════════════════════════════════════════════════
local realDescribe = SS2.describe
if realDescribe then
    local function summarize(fn)
        local c = caps()
        local src = "?"
        if c.info then
            pcall(function()
                local info = debug.getinfo(fn, "S")
                if info and info.source then
                    src = info.source:gsub("^@", ""):gsub("^=", ""):sub(1, 40)
                end
            end)
        end
        return "function<" .. src .. ">"
    end
    SS2.describe = function(v, depth)
        depth = depth or 0
        if typeof(v) == "function" and depth == 0 then
            return summarize(v)
        end
        return realDescribe(v, depth)
    end
    print("[SS2-closure] recorder patched — function args show lineage in feed")
end

-- ════════════════════════════════════════════════════════════
-- closure-graph export: the full session's function findings
-- ════════════════════════════════════════════════════════════
function SS2.exportClosures()
    local out = {}
    out[#out + 1] = "╔══════════════════════════════════════╗"
    out[#out + 1] = "  CLOSURE GRAPH — SESSION EXPORT"
    out[#out + 1] = "  game: " .. SS2.game .. " | " .. os.date()
    out[#out + 1] = "  autopsies: " .. SS2.closure.autopsies
    out[#out + 1] = "  graph nodes visited: " .. SS2.closure.nodesVisited
    out[#out + 1] = "╚══════════════════════════════════════╝"
    out[#out + 1] = ""
    local found = 0
    for _, rec in ipairs(SS2.log) do
        for i, raw in ipairs(rec.raw or {}) do
            if type(raw) == "function" then
                found = found + 1
                out[#out + 1] = ("── call #%d %s arg[%d] ──"):format(rec.id, rec.name, i)
                out[#out + 1] = autopsy(raw, 0)
                if found > 100 then break end
            end
        end
        if found > 100 then break end
    end
    out[#out + 1] = ""
    out[#out + 1] = "total function args exported: " .. found
    pcall(function()
        makefolder("SimplySpirited")
        writefile("SimplySpirited/vault/closure_graph.txt", table.concat(out, "\n"))
    end)
    print("[closure] graph exported -> vault/closure_graph.txt (" .. found .. " functions)")
end
SS2.exportClosures = SS2.exportClosures

-- ═══ stats command ═══
function SS2.closureStats()
    local c = caps()
    print("═══ closure module stats ═══")
    print(("  autopsies this session: %d"):format(SS2.closure.autopsies))
    print(("  graph nodes visited:    %d"):format(SS2.closure.nodesVisited))
    print(("  caps: info=%s upvalues=%s constants=%s"):format(
        tostring(c.info), tostring(c.upvalue), tostring(c.constants)))
end
SS2.closureStats = SS2.closureStats

print("[SS2-closure] v4.6 LIVE — forensics lab armed")
print("[closure] SS2.inspectLast()      — autopsy last call's functions")
print("[closure] SS2.inspectAll()       — sweep entire session log")
print("[closure] SS2.inspectClosure(fn) — autopsy any function")
print("[closure] SS2.exportClosures()   — closure graph -> vault file")
print("[closure] SS2.closureStats()     — module stats")
