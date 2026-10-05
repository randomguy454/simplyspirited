-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.1 — CLOSURE INSPECTOR
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  When captured calls carry FUNCTION args, this module opens
--  them up: source lineage, upvalues (the captured variables),
--  constants (the strings it references). A function confesses
--  what it was built to do.
--
--  Executor-dependent: debug.getupvalue / debug.getconstants /
--  debug.getinfo. Every access pcall-guarded — degrades to
--  "blocked" gracefully, never crashes the suite.
-- ════════════════════════════════════════════════════════════

print("[SS2-closure] loading inspector...")

local SS2 = getgenv().SS2
if not SS2 then
    warn("[SS2-closure] core.lua must load first")
    return
end

-- ═══════════ capability probe ═══════════
local CAPS = {
    info = false,
    upvalue = false,
    constants = false,
}
pcall(function()
    if debug and debug.getinfo then
        local test = function() return 1 end
        if debug.getinfo(test, "S") then CAPS.info = true end
    end
end)
pcall(function()
    if debug and debug.getupvalue then
        local x = 5
        local test = function() return x end
        if debug.getupvalue(test, 1) then CAPS.upvalue = true end
    end
end)
pcall(function()
    if debug and debug.getconstants then
        local test = function() return "probe" end
        local c = debug.getconstants(test)
        if c then CAPS.constants = true end
    end
end)

print(("[SS2-closure] capabilities: info=%s upvalues=%s constants=%s"):format(
    tostring(CAPS.info), tostring(CAPS.upvalue), tostring(CAPS.constants)))

-- ═══════════ value previewer (shared by autopsy) ═══════════
local function preview(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "number" or t == "boolean" or t == "nil" then
        return tostring(v)
    elseif t == "string" then
        return '"' .. v:sub(1, 40) .. '"' .. (#v > 40 and "..." or "")
    elseif t == "table" then
        if depth >= 1 then return "table" end
        -- one level of keys: table shapes reveal config intent
        local keys = {}
        for k in pairs(v) do
            keys[#keys + 1] = tostring(k)
            if #keys >= 6 then break end
        end
        if #keys > 0 then
            return "table {" .. table.concat(keys, ",") .. "}"
        end
        return "table(empty)"
    elseif t == "Instance" then
        return v.ClassName .. ":" .. v.Name
    elseif t == "function" then
        return "function(nested)"
    else
        return t
    end
end

-- ═══════════ THE AUTOPSY ═══════════
function SS2.inspectClosure(fn, depth)
    if type(fn) ~= "function" then
        return "not a function (" .. typeof(fn) .. ")"
    end
    depth = depth or 0
    if depth > 2 then return "… (nested too deep)" end

    local out = { "closure {" }

    -- SECTION 1: lineage — where does this function live
    if CAPS.info then
        pcall(function()
            local info = debug.getinfo(fn, "Su")
            if info then
                out[#out + 1] = ("  source:   %s"):format(tostring(info.source):sub(1, 70))
                out[#out + 1] = ("  line:     %s"):format(tostring(info.linedefined or "?"))
                out[#out + 1] = ("  params:   %s | upvalue slots: %s"):format(
                    tostring(info.nparams or "?"), tostring(info.nups or "?"))
                if info.what then
                    out[#out + 1] = ("  what:     %s"):format(info.what)
                end
            end
        end)
    else
        out[#out + 1] = "  lineage: (debug.getinfo unavailable)"
    end

    -- SECTION 2: upvalues — what this closure captured
    if CAPS.upvalue then
        local gotAny = false
        pcall(function()
            local i = 1
            while i <= 25 do
                local name, value = debug.getupvalue(fn, i)
                if not name then break end
                gotAny = true
                out[#out + 1] = ("  up[%d] %s = %s"):format(
                    i, name, preview(value, depth + 1))
                i = i + 1
            end
        end)
        if not gotAny then
            out[#out + 1] = "  upvalues: (none)"
        end
    else
        out[#out + 1] = "  upvalues: (debug.getupvalue unavailable)"
    end

    -- SECTION 3: constants — what strings/numbers it references
    if CAPS.constants then
        pcall(function()
            local consts = debug.getconstants(fn)
            local strings, numbers = {}, {}
            for _, c in ipairs(consts or {}) do
                if type(c) == "string" and #c >= 3 then
                    strings[#strings + 1] = c
                elseif type(c) == "number" then
                    numbers[#numbers + 1] = c
                end
            end
            if #strings > 0 then
                out[#out + 1] = "  constants (" .. #strings .. " strings):"
                for k = 1, math.min(10, #strings) do
                    out[#out + 1] = ('    "%s"'):format(strings[k]:sub(1, 60))
                end
                if #strings > 10 then
                    out[#out + 1] = ("    … +%d more"):format(#strings - 10)
                end
            end
            if #numbers > 0 then
                local numStrs = {}
                for k = 1, math.min(8, #numbers) do
                    numStrs[#numStrs + 1] = tostring(numbers[k])
                end
                out[#out + 1] = "  numbers: " .. table.concat(numStrs, ", ")
            end
        end)
    else
        out[#out + 1] = "  constants: (debug.getconstants unavailable)"
    end

    out[#out + 1] = "}"
    return table.concat(out, "\n")
end
SS2.inspectClosure = SS2.inspectClosure

-- ═══════════ PATCH THE RECORDER ═══════════
-- function args in captured calls now get a one-line autopsy summary
local realDescribe = SS2.describe
if realDescribe then
    SS2.describe = function(v, depth)
        depth = depth or 0
        if typeof(v) == "function" and depth == 0 then
            local autopsy = SS2.inspectClosure(v, 1)
            -- compress to single line for the log feed: pull upvalue + constant count
            local ups = autopsy:match("up%[1%][^\n]*")
            local nConsts = select(2, autopsy:gsub('constants %(%d+', ""))
            local srcLine = autopsy:match("source:%s+([^\n]+)")
            local summary = "function<" .. (srcLine or "?") .. ">"
            if ups then summary = summary .. " up: " .. ups:sub(1, 60) end
            return summary
        end
        return realDescribe(v, depth)
    end
    print("[SS2-closure] recorder patched — function args now autopsied in feed")
end

-- ═══════════ MANUAL COMMANDS ═══════════
function SS2.inspectLast()
    local rec = SS2.log[#SS2.log]
    if not rec then
        print("[closure] no calls captured yet")
        return
    end
    print("═══ CLOSURE INSPECTION: call #" .. rec.id .. " — " .. rec.name .. " ═══")
    local found = 0
    for i, raw in ipairs(rec.raw or {}) do
        if type(raw) == "function" then
            found = found + 1
            print(("── arg[%d] ──"):format(i))
            print(SS2.inspectClosure(raw, 0))
        end
    end
    if found == 0 then
        print("  (no function args in this call)")
    end
end

function SS2.inspectAll(depth)
    -- autopsy every function-arg across the whole session log
    local found = 0
    print("═══ FULL CLOSURE SWEEP ═══")
    for _, rec in ipairs(SS2.log) do
        for i, raw in ipairs(rec.raw or {}) do
            if type(raw) == "function" then
                found = found + 1
                print(("── #%d %s arg[%d] ──"):format(rec.id, rec.name, i))
                print(SS2.inspectClosure(raw, depth or 0))
                if found > 20 then
                    print("… (sweep truncated at 20 — use SS2.inspectLast for specific calls)")
                    return
                end
            end
        end
    end
    print("  total function args found: " .. found)
end

print("[SS2-closure] inspector LIVE")
print("[closure] commands:")
print("  SS2.inspectLast()            — autopsy last call's function args")
print("  SS2.inspectAll()             — sweep whole session log")
print("  SS2.inspectClosure(fn)       — autopsy any function you have")
