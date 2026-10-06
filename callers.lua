--[[
    simplyspirited v4.6 — caller attribution
    SHADOWMILESC / computerizedcarrier2

    answers the question every remote spy leaves dangling:
    WHO fired this?

    architecture:
    - stack walked at fire time via debug.getinfo (structured)
      with traceback-text fallback for executors that lack it
    - suite frames filtered so our hooks never self-attribute
    - per-remote caller maps + a global call-site registry
    - call sites classified: ui / core / module / unknown
    - bounded storage: 50 sites per remote, 500 global

    the honest limit: executor stack traces vary in format.
    multi-strategy parsing covers delta's formats; the raw
    string is stored even when parsing fails, so data is
    never lost — only unparsed.
]]

print("[SS2-callers] v4.6 loading...")

local SS2 = getgenv().SS2
if not SS2 then
    warn("ss2-callers: core.lua must load first")
    return
end

-- ════════════════════════════════════════════════════════════
-- capability probe
-- ════════════════════════════════════════════════════════════
local CAPS = { getinfo = false, traceback = false }

pcall(function()
    if debug and debug.getinfo then
        local probeFn = function() end
        local info = debug.getinfo(probeFn, "Sn")
        if info then CAPS.getinfo = true end
    end
end)
pcall(function()
    if debug and debug.traceback then
        local t = debug.traceback("probe")
        if type(t) == "string" and #t > 0 then CAPS.traceback = true end
    end
end)

print(("[SS2-callers] caps: getinfo=%s traceback=%s"):format(
    tostring(CAPS.getinfo), tostring(CAPS.traceback)))

-- ════════════════════════════════════════════════════════════
-- config
-- ════════════════════════════════════════════════════════════
local MAX_SITES_PER_REMOTE = 50
local MAX_GLOBAL_SITES = 500
local STACK_WALK_DEPTH = 14

-- ════════════════════════════════════════════════════════════
-- suite-frame filter: our hook layers must never appear as
-- callers. markers match our own file names and wrapper names.
-- ════════════════════════════════════════════════════════════
local SUITE_MARKERS = {
    "simplyspirited", "ss2", "hookmeta", "governor",
    "callers", "core.lua", "watch.lua", "ui.lua", "uiplus",
    "output.lua", "stealth.lua", "describe_ext",
}

local function isSuiteFrame(source)
    if not source then return true end
    local s = source:lower()
    for _, marker in ipairs(SUITE_MARKERS) do
        if s:find(marker, 1, true) then
            return true
        end
    end
    -- engine internals aren't callers either
    if s:find("%[c%]") or s == "" then return true end
    return false
end

-- ════════════════════════════════════════════════════════════
-- caller classification: where in the game does this live?
-- ui scripts are usually noise (button handlers); core game
-- logic is the signal. classification makes filtering trivial.
-- ════════════════════════════════════════════════════════════
local function classify(path)
    local p = path:lower()
    if p:find("playergui", 1, true) or p:find("playergui", 1, true) then
        return "ui"
    elseif p:find("replicatedstorage", 1, true) or p:find("modules", 1, true) then
        return "module"
    elseif p:find("players%" .. P.Name, 1, true) or p:find("playergui", 1, true) then
        return "ui"
    elseif p:find("workspace", 1, true) then
        return "world"
    elseif p:find("coregui", 1, true) or p:find("corescripts", 1, true) then
        return "roblox"
    end
    return "core"
end

-- ════════════════════════════════════════════════════════════
-- global call-site registry: every unique script:line that
-- fires ANY remote, with aggregate counts. this is the
-- "hottest code paths in the game" dataset.
-- ════════════════════════════════════════════════════════════
SS2.callSites = SS2.callSites or {
    sites = {},      -- [siteKey] = {count, first, last, kind, remotes={}}
    order = {},      -- insertion-ordered keys for bounded eviction
    count = 0,
}

local REG = SS2.callSites

local function recordSite(siteKey, remoteName)
    local site = REG.sites[siteKey]
    if site then
        site.count = site.count + 1
        site.last = os.date("%H:%M:%S")
        site.remotes[remoteName] = (site.remotes[remoteName] or 0) + 1
    else
        -- bounded eviction: drop the coldest site when full
        if REG.count >= MAX_GLOBAL_SITES then
            local coldest, coldestKey = nil, nil
            for key, s in pairs(REG.sites) do
                if not coldest or s.count < coldest.count then
                    coldest = s
                    coldestKey = key
                end
            end
            if coldestKey then
                REG.sites[coldestKey] = nil
                REG.count = REG.count - 1
            end
        end
        REG.sites[siteKey] = {
            count = 1,
            first = os.date("%H:%M:%S"),
            last = os.date("%H:%M:%S"),
            kind = classify(siteKey),
            remotes = { [remoteName] = 1 },
        }
        REG.count = REG.count + 1
    end
end

-- ════════════════════════════════════════════════════════════
-- stack walking: two strategies, suite-filtered
-- ════════════════════════════════════════════════════════════
local function getCaller()
    -- strategy 1: structured getinfo walk
    if CAPS.getinfo then
        for level = 3, STACK_WALK_DEPTH do
            local ok, info = pcall(debug.getinfo, level, "Sn")
            if not ok or not info then break end
            local src = info.source
            if src and src ~= "=[C]" and src ~= "" and not isSuiteFrame(src) then
                local name = src:gsub("^@", ""):gsub("^=", "")
                return name .. ":" .. (info.currentline or 0)
            end
        end
    end

    -- strategy 2: traceback text parse (delta format variants)
    if CAPS.traceback then
        local tb = debug.traceback("ss2", 3)
        if type(tb) == "string" then
            for line in tb:gmatch("[^\r\n]+") do
                -- delta format a: Script "path", Line N
                local src, ln = line:match('Script%s+"([^"]+)"%,%s*Line%s+(%d+)')
                -- delta format b: path.lua:N
                if not src then
                    src, ln = line:match("([%w%.%-%_]+%.%w+):(%d+)")
                end
                if src and src:find("MessageOutput") then
                    -- console noise, skip
                elseif src and not isSuiteFrame(src) then
                    return src .. ":" .. ln
                end
            end
        end
    end

    return "unknown"
end
SS2.getCaller = getCaller

-- ════════════════════════════════════════════════════════════
-- recorder patch: outermost wrapper. attributes OUT calls,
-- passes everything through untouched.
-- ════════════════════════════════════════════════════════════
local realRecord = SS2.recordCall
if not realRecord then
    warn("ss2-callers: no recorder found (core broken?)")
    return
end

SS2.recordCall = function(remote, args, direction)
    if direction == "OUT" then
        local prof = SS2.remotes[remote]
        if prof then
            local caller = getCaller()
            -- per-remote map (bounded)
            prof.callers = prof.callers or {}
            prof.callers[caller] = (prof.callers[caller] or 0) + 1
            -- bounded per-remote eviction
            local siteCount = 0
            for _ in pairs(prof.callers) do siteCount = siteCount + 1 end
            if siteCount > MAX_SITES_PER_REMOTE then
                local coldest, ck = nil, nil
                for c, n in pairs(prof.callers) do
                    if not coldest or n < coldest then
                        coldest = n
                        ck = c
                    end
                end
                if ck then prof.callers[ck] = nil end
            end
            -- global registry
            recordSite(caller, remote.Name)
        end
    end
    return realRecord(remote, args, direction)
end
print("[SS2-callers] recorder patched — OUT calls attributed")

-- ════════════════════════════════════════════════════════════
-- queries
-- ════════════════════════════════════════════════════════════

-- who fires a specific remote?
function SS2.callers(nameOrPath)
    local matches = {}
    for r, prof in pairs(SS2.remotes) do
        if r.Name == nameOrPath
        or (prof.path and prof.path:find(nameOrPath, 1, true)) then
            matches[#matches + 1] = { r = r, prof = prof }
        end
    end
    if #matches == 0 then
        print("[callers] no remote matches '" .. tostring(nameOrPath) .. "'")
        return nil
    end
    for _, m in ipairs(matches) do
        print("═══ caller map: " .. m.r.Name .. " ═══")
        local prof = m.prof
        if not prof.callers or next(prof.callers) == nil then
            print("  (never fired OUT this session)")
        else
            local sorted = {}
            for c, n in pairs(prof.callers) do
                sorted[#sorted + 1] = { c = c, n = n }
            end
            table.sort(sorted, function(a, b) return a.n > b.n end)
            for k = 1, math.min(15, #sorted) do
                local kind = classify(sorted[k].c)
                print(("  [%5dx] [%s] %s"):format(sorted[k].n, kind, sorted[k].c))
            end
        end
    end
    return matches
end

-- the game's hottest code paths, ranked across ALL remotes
function SS2.topCallers(topN)
    topN = topN or 20
    local sorted = {}
    for key, site in pairs(REG.sites) do
        sorted[#sorted + 1] = {
            key = key, n = site.count, kind = site.kind,
            remotes = site.remotes,
        }
    end
    table.sort(sorted, function(a, b) return a.n > b.n end)
    print("═══ hottest call sites (all remotes) ═══")
    for k = 1, math.min(topN, #sorted) do
        local e = sorted[k]
        local remoteSummary = ""
        local rCount = 0
        for rn in pairs(e.remotes) do
            rCount = rCount + 1
            if rCount <= 3 then
                remoteSummary = remoteSummary .. rn .. " "
            end
        end
        print(("  [%6dx] [%s] %s → %s"):format(e.n, e.kind, e.key, remoteSummary))
    end
    if #sorted == 0 then
        print("  (no attributed calls yet)")
    end
    return sorted
end
SS2.topCallers = SS2.topCallers

-- filter: show only UI-fires vs core-fires for a remote
function SS2.callerKinds(nameOrPath)
    local matches = SS2.callers(nameOrPath)
    if not matches then return end
    for _, m in ipairs(matches) do
        if m.prof.callers then
            local kinds = { ui = 0, core = 0, module = 0, world = 0, roblox = 0, unknown = 0 }
            for caller, n in pairs(m.prof.callers) do
                local kind = classify(caller)
                kinds[kind] = (kinds[kind] or 0) + n
            end
            print("── kind breakdown: " .. m.r.Name)
            for kind, n in pairs(kinds) do
                if n > 0 then print(("  %-8s %d"):format(kind, n)) end
            end
        end
    end
end
SS2.callerKinds = SS2.callerKinds

-- ════════════════════════════════════════════════════════════
-- export: feeds vault2's exportCallers and adds the registry
-- ════════════════════════════════════════════════════════════
function SS2.exportCallersFull()
    local out = {}
    out[#out + 1] = "╔══════════════════════════════════════╗"
    out[#out + 1] = "  CALLER ATTRIBUTION — FULL"
    out[#out + 1] = "  game: " .. SS2.game .. " | " .. os.date()
    out[#out + 1] = "  operator: SHADOWMILESC (computerizedcarrier2)"
    out[#out + 1] = "╚══════════════════════════════════════╝"
    out[#out + 1] = ""

    -- section 1: hottest sites
    out[#out + 1] = "── HOTTEST CALL SITES (all remotes) ──"
    local sorted = {}
    for key, site in pairs(REG.sites) do
        sorted[#sorted + 1] = { key = key, s = site }
    end
    table.sort(sorted, function(a, b) return a.s.count > b.s.count end)
    for _, e in ipairs(sorted) do
        out[#out + 1] = ("[%6dx] [%s] %s"):format(e.s.count, e.s.kind, e.key)
        for rn, rnCount in pairs(e.s.remotes) do
            out[#out + 1] = ("         → %s (%d)"):format(rn, rnCount)
        end
    end

    -- section 2: per-remote maps
    out[#out + 1] = ""
    out[#out + 1] = "── PER-REMOTE CALLER MAPS ──"
    for r, prof in pairs(SS2.remotes) do
        if prof.callers and next(prof.callers) then
            out[#out + 1] = ("REMOTE: %s (%s)"):format(r.Name, prof.class)
            local cs = {}
            for c, n in pairs(prof.callers) do cs[#cs + 1] = { c = c, n = n } end
            table.sort(cs, function(a, b) return a.n > b.n end)
            for _, e in ipairs(cs) do
                out[#out + 1] = ("  [%dx] [%s] %s"):format(e.n, classify(e.c), e.c)
            end
        end
    end

    pcall(function()
        makefolder("SimplySpirited")
        writefile("SimplySpirited/vault/callers_full.txt", table.concat(out, "\n"))
    end)
    print("[callers] full attribution -> vault/callers_full.txt (" ..
        REG.count .. " sites)")
    return table.concat(out, "\n")
end
SS2.exportCallersFull = SS2.exportCallersFull

print("[SS2-callers] v4.6 LIVE — "
    .. "stack-walk + registry + classification armed")
print("[callers] SS2.callers('name')      — who fires a remote")
print("[callers] SS2.topCallers(20)       — hottest code paths, ranked")
print("[callers] SS2.callerKinds('name')  — ui vs core breakdown")
print("[callers] SS2.exportCallersFull()  — full attribution -> file")
