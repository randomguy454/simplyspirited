-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.5 — CALLER ATTRIBUTION
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  Walks the call stack at remote-fire time and records WHICH
--  script fired it (path + line). Each remote profile builds a
--  caller map: "SomeGame.BuyUI:142 -> 417 calls"
--  • Hooks into the recorder pipeline (chains with governor)
--  • Console: SS2.callers('RemoteName') — who fires it
--  • Export: SS2.exportCallers() — full attribution file
--  Note: stack frames vary by executor — multi-strategy parse.
-- ════════════════════════════════════════════════════════════

print("[SS2-callers] loading caller attribution...")

local SS2 = getgenv().SS2
if not SS2 then warn("[SS2-callers] core must load first") return end

local CAPS = { traceback = false, getinfo = false }
pcall(function()
    if debug and debug.traceback then
        local t = debug.traceback("probe")
        if type(t) == "string" and #t > 0 then CAPS.traceback = true end
    end
end)
pcall(function()
    if debug and debug.getinfo then
        if debug.getinfo(2, "S") then CAPS.getinfo = true end
    end
end)
print(("[SS2-callers] capabilities: traceback=%s getinfo=%s"):format(
    tostring(CAPS.traceback), tostring(CAPS.getinfo)))

-- ═══ THE STACK WALKER ═══
-- finds the first script-looking frame above the hook layers.
-- Hook layers to skip: this file's functions, governor wrapper,
-- core recorder. We walk up to 12 frames and take the best
-- candidate: a frame whose source looks like a game script
-- (not our suite, not [C], not engine internals).
local SUITE_MARKERS = { "simplyspirited", "SS2", "hookmeta", "governor",
    "callers", "core.lua", "watch.lua", "uiplus" }

local function looksLikeSuite(source)
    if not source then return true end
    local s = source:lower()
    for _, m in ipairs(SUITE_MARKERS) do
        if s:find(m, 1, true) then return true end
    end
    return false
end

local function getCaller()
    -- strategy 1: debug.getinfo walk (structured)
    if CAPS.getinfo then
        for level = 2, 12 do
            local ok, info = pcall(debug.getinfo, level, "Sn")
            if not ok or not info then break end
            local src = info.source
            if src and src ~= "=[C]" and src ~= "" then
                if not looksLikeSuite(src) then
                    local name = src:gsub("^@", ""):gsub("^=", "")
                    local line = info.currentline or 0
                    return name .. ":" .. line
                end
            end
        end
    end

    -- strategy 2: traceback text parse
    if CAPS.traceback then
        local tb = debug.traceback("probe", 2)
        if type(tb) == "string" then
            for line in tb:gmatch("[^\r\n]+") do
                local src, ln = line:match('Script "([^"]+)", Line (%d+)')
                    or line:match('(%S+%.lua):(%d+)')
                    or line:match('([%w%._]+):(%d+)')
                if src then
                    if src:find("MessageOutput") or src:find("%[C%]") then
                        -- skip engine noise
                    elseif not looksLikeSuite(src) then
                        return src .. ":" .. ln
                    end
                end
            end
        end
    end

    return "unknown"
end
SS2.getCaller = getCaller

-- ═══ PATCH THE RECORDER ═══
-- sits OUTERMOST in the wrapper chain (governor -> core underneath)
local realRecord = SS2.recordCall
if not realRecord then
    warn("[SS2-callers] core recorder not found")
    return
end

SS2.recordCall = function(remote, args, direction)
    -- only attribute OUTBOUND calls — inbound fire from the server
    -- has no meaningful local stack
    if direction == "OUT" then
        local prof = SS2.remotes[remote]
        if prof then
            local caller = getCaller()
            prof.callers = prof.callers or {}
            prof.callers[caller] = (prof.callers[caller] or 0) + 1
            -- also stamp the call record itself
            -- (record already built by inner layers; we can't reach it
            --  without re-architecting, so profile-level is the store)
        end
    end
    return realRecord(remote, args, direction)
end

print("[SS2-callers] recorder patched — OUT calls now attributed")

-- ═══ QUERY: who fires a given remote? ═══
function SS2.callers(nameOrPath)
    local matches = {}
    for r, prof in pairs(SS2.remotes) do
        if r.Name == nameOrPath or (prof.path and prof.path:find(nameOrPath, 1, true)) then
            matches[#matches + 1] = { r = r, prof = prof }
        end
    end
    if #matches == 0 then
        print("[callers] no remote matches '" .. tostring(nameOrPath) .. "'")
        return nil
    end
    for _, m in ipairs(matches) do
        print("═══ CALLER MAP: " .. m.r.Name .. " ═══")
        local prof = m.prof
        if not prof.callers or next(prof.callers) == nil then
            print("  (no caller data — remote never fired OUT this session)")
        else
            local sorted = {}
            for caller, cnt in pairs(prof.callers) do
                sorted[#sorted + 1] = { c = caller, n = cnt }
            end
            table.sort(sorted, function(a, b) return a.n > b.n end)
            for k = 1, math.min(15, #sorted) do
                print(("  [%5dx] %s"):format(sorted[k].n, sorted[k].c))
            end
        end
    end
    return matches
end

-- ═══ TOP CALLERS ACROSS THE WHOLE GAME ═══
function SS2.topCallers(topN)
    topN = topN or 20
    local agg = {}
    for r, prof in pairs(SS2.remotes) do
        for caller, cnt in pairs(prof.callers or {}) do
            agg[caller] = (agg[caller] or 0) + cnt
        end
    end
    local sorted = {}
    for c, n in pairs(agg) do
        sorted[#sorted + 1] = { c = c, n = n }
    end
    table.sort(sorted, function(a, b) return a.n > b.n end)
    print("═══ TOP CALLING SCRIPTS (whole game) ═══")
    for k = 1, math.min(topN, #sorted) do
        print(("  [%6dx] %s"):format(sorted[k].n, sorted[k].c))
    end
    return sorted
end

print("[SS2-callers] caller attribution LIVE")
print("[callers] SS2.callers('RemoteName')   — who fires it")
print("[callers] SS2.topCallers(20)          — the whole game's busiest scripts")
print("[callers] SS2.exportCallers()         — attribution file (vault2)")
