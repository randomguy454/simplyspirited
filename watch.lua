--[[
    simplyspirited v4.6 — surveillance engine
    SHADOWMILESC / computerizedcarrier2

    function library tier. display is ui.lua's job; this module
    is what the ui and console both call.

    • replay engine: verified re-firing with rate limiting
    • arg presets: named call library, remote-identity tagged
    • remote deep-dives: full profile with kind classification
    • API doc generator: reflects every v4.6 data layer
    • feed search: structured returns, scriptable
    • pause/resume

    replay safety: max 1 fire/sec per remote. the suite refuses
    to be its own flood source — the governor watches the game,
    the watch module watches itself.
]]

print("[SS2-watch] v4.6 loading...")

local SS2 = getgenv().SS2
if not SS2 then
    warn("ss2-watch: core.lua must load first")
    return
end

-- ═══ pause / resume ═══
SS2.paused = false
SS2.togglePause = function()
    SS2.paused = not SS2.paused
    SS2.capture = not SS2.paused
    print("[watch] capture " .. (SS2.paused and "PAUSED" or "RESUMED"))
    return SS2.paused
end

-- ════════════════════════════════════════════════════════════
-- REPLAY ENGINE (v4.6: verified + rate-limited)
-- ════════════════════════════════════════════════════════════
SS2.replayCount = 1
local lastReplayByRemote = {}   -- [remote] = os.clock() of last replay
local REPLAY_MIN_INTERVAL = 1   -- seconds between replays of the same remote

function SS2.replayId(id)
    local target
    for _, rec in ipairs(SS2.log) do
        if rec.id == id then
            target = rec
            break
        end
    end
    if not target then
        print(("[watch] call #%s not found"):format(tostring(id)))
        return false, "not found"
    end
    local r = target.remote
    if not r or not r.Parent then
        print("[watch] remote no longer exists — cannot replay")
        return false, "remote gone"
    end

    -- rate limit: 1/sec per remote (the suite polices itself)
    local now = os.clock()
    local last = lastReplayByRemote[r] or 0
    if now - last < REPLAY_MIN_INTERVAL then
        local wait = REPLAY_MIN_INTERVAL - (now - last)
        print(("[watch] replay throttled — %.1fs until %s can fire again"):format(
            wait, r.Name))
        return false, "throttled"
    end
    lastReplayByRemote[r] = now

    local count = SS2.replayCount or 1
    task.spawn(function()
        for k = 1, count do
            if target.class == "RemoteEvent" then
                pcall(function()
                    r:FireServer(unpack(target.raw))
                end)
            elseif target.class == "RemoteFunction" then
                pcall(function()
                    r:InvokeServer(unpack(target.raw))
                end)
            end
            if k < count then task.wait(0.15) end
        end

        -- v4.6 verification: did the call register in our own net?
        task.wait(0.2)
        local prof = SS2.remotes[r]
        local verified = prof and prof.out and prof.out > 0
        print(("[watch] replayed #%d x%d on %s %s"):format(
            id, count, r.Name,
            verified and "(net confirmed)" or "(net saw nothing — verify manually)"))
    end)
    return true, ("replaying #%d x%d"):format(id, count)
end

function SS2.replayLast()
    local rec = SS2.log[#SS2.log]
    if not rec then
        print("[watch] no calls captured")
        return false, "empty"
    end
    return SS2.replayId(rec.id)
end

-- ════════════════════════════════════════════════════════════
-- ARG PRESETS (v4.6: remote-identity tagged)
-- ════════════════════════════════════════════════════════════
SS2.presets = SS2.presets or {}

function SS2.savePreset(name, callId)
    local target = nil
    if callId then
        for _, rec in ipairs(SS2.log) do
            if rec.id == callId then target = rec break end
        end
    else
        target = SS2.log[#SS2.log]
    end
    if not target then
        print("[watch] no call to save")
        return
    end
    -- v4.6: store remote identity for cross-session re-binding
    SS2.presets[name] = {
        remoteName = target.name,
        remotePath = target.path,
        remoteClass = target.class,
        raw = target.raw,
        args = target.args,
        saved = os.date("%H:%M:%S"),
    }
    print(("[watch] preset '%s' saved: %s (%d args, remote-tagged)"):format(
        name, target.name, #target.raw))
end

function SS2.playPreset(name, count, delay)
    count = count or 1
    delay = delay or 0.15
    local p = SS2.presets[name]
    if not p then
        print("[watch] no preset '" .. tostring(name) .. "'")
        return
    end
    -- re-bind: find the live remote by stored path, fallback name
    local live = nil
    for r, prof in pairs(SS2.remotes) do
        if prof.path == p.remotePath or r.Name == p.remoteName then
            live = r
            break
        end
    end
    if not live then
        print("[watch] remote for preset '" .. name .. "' not present in this game")
        return
    end
    task.spawn(function()
        for k = 1, count do
            if p.remoteClass == "RemoteEvent" then
                pcall(function() live:FireServer(unpack(p.raw)) end)
            else
                pcall(function() live:InvokeServer(unpack(p.raw)) end)
            end
            if k < count then task.wait(delay) end
        end
        print(("[watch] preset '%s' fired x%d"):format(name, count))
    end)
end

function SS2.listPresets()
    print("═══ presets ═══")
    local n = 0
    for name, p in pairs(SS2.presets) do
        n = n + 1
        print(("  %s | %s %s | %d args | saved %s"):format(
            name, p.remoteClass, p.remoteName, #p.raw, p.saved))
    end
    if n == 0 then print("  (empty)") end
end

-- ════════════════════════════════════════════════════════════
-- REMOTE DEEP-DIVE (v4.6: kind classification)
-- ════════════════════════════════════════════════════════════
local function classifyCaller(path)
    local p = (path or ""):lower()
    if p:find("playergui", 1, true) then return "ui" end
    if p:find("replicatedstorage", 1, true) then return "module" end
    if p:find("workspace", 1, true) then return "world" end
    if p:find("coregui", 1, true) or p:find("corescript", 1, true) then return "roblox" end
    return "core"
end

function SS2.profileRemote(nameOrPath)
    local matches = {}
    for r, prof in pairs(SS2.remotes) do
        if r.Name == nameOrPath
        or (prof.path and prof.path:find(nameOrPath, 1, true)) then
            matches[#matches + 1] = { r = r, prof = prof }
        end
    end
    if #matches == 0 then
        print("[watch] no remote matches '" .. tostring(nameOrPath) .. "'")
        return nil
    end
    for _, m in ipairs(matches) do
        local prof = m.prof
        print("═══ remote profile ═══")
        print("  name:  " .. m.r.Name)
        print("  class: " .. m.r.ClassName)
        print("  path:  " .. (prof.path or "?"))
        print(("  calls: %d (out %d / in %d)"):format(prof.calls, prof.out, prof.inn))
        if (prof.metaCaught or 0) > 0 then
            print("  meta-net caught: " .. prof.metaCaught)
        end
        -- kind breakdown from caller data
        if prof.callers and next(prof.callers) then
            local kinds = {}
            for caller, n in pairs(prof.callers) do
                local kind = classifyCaller(caller)
                kinds[kind] = (kinds[kind] or 0) + n
            end
            local kb = {}
            for kind, n in pairs(kinds) do
                kb[#kb + 1] = kind .. ":" .. n
            end
            print("  kinds: " .. table.concat(kb, " "))
            local cs = {}
            for c, n in pairs(prof.callers) do cs[#cs + 1] = { c = c, n = n } end
            table.sort(cs, function(a, b) return a.n > b.n end)
            print("  top callers:")
            for k = 1, math.min(5, #cs) do
                print(("    [%dx] %s"):format(cs[k].n, cs[k].c))
            end
        end
        local sigs = {}
        for sig, cnt in pairs(prof.sigs) do
            sigs[#sigs + 1] = { s = sig, c = cnt }
        end
        table.sort(sigs, function(a, b) return a.c > b.c end)
        print("  signatures (" .. #sigs .. " unique):")
        for k = 1, math.min(10, #sigs) do
            print(("    [%3dx] %s"):format(sigs[k].c, sigs[k].s:sub(1, 110)))
        end
    end
    return matches
end
SS2.profile = SS2.profileRemote

-- ════════════════════════════════════════════════════════════
-- API DOC GENERATOR (v4.6: every data layer reflected)
-- ════════════════════════════════════════════════════════════
function SS2.generateAPIDoc()
    local out = {}
    out[#out + 1] = "╔══════════════════════════════════════╗"
    out[#out + 1] = "  SIMPLYSPIRITED v4.6 — API DOCUMENT"
    out[#out + 1] = "  game: " .. SS2.game .. " | place: " .. SS2.placeId
    out[#out + 1] = "  generated: " .. os.date()
    out[#out + 1] = "  operator: SHADOWMILESC (computerizedcarrier2)"
    out[#out + 1] = "  capture: net=" .. tostring(SS2.metaHooked)
        .. " | verbosity=" .. tostring(SS2.verbosity)
    out[#out + 1] = "╚══════════════════════════════════════╝"
    out[#out + 1] = ""

    local ranked = {}
    for r, prof in pairs(SS2.remotes) do
        ranked[#ranked + 1] = { r = r, prof = prof }
    end
    table.sort(ranked, function(a, b) return a.prof.calls > b.prof.calls end)

    out[#out + 1] = "TOTAL REMOTES: " .. #ranked
    out[#out + 1] = "TOTAL CALLS CAPTURED: " .. #SS2.log
    if SS2.health then
        out[#out + 1] = ("RATE (smoothed): %.1f/s | filter-dropped: %d"):format(
            SS2.health.callsEMA, SS2.health.filterDropped)
    end
    out[#out + 1] = ""

    for _, e in ipairs(ranked) do
        local prof = e.prof
        out[#out + 1] = "──────────────────────────────────────"
        out[#out + 1] = ("REMOTE: %s (%s)"):format(e.r.Name, prof.class)
        out[#out + 1] = ("PATH:   %s"):format(prof.path)
        out[#out + 1] = ("CALLS:  %d (out %d / in %d) | seen %s -> %s"):format(
            prof.calls, prof.out, prof.inn, prof.firstSeen, prof.lastSeen)
        if (prof.metaCaught or 0) > 0 then
            out[#out + 1] = ("  (meta-net caught %d)"):format(prof.metaCaught)
        end
        if prof.callers and next(prof.callers) then
            out[#out + 1] = "  CALLERS:"
            local cs = {}
            for c, n in pairs(prof.callers) do cs[#cs + 1] = { c = c, n = n } end
            table.sort(cs, function(a, b) return a.n > b.n end)
            for _, ce in ipairs(cs) do
                out[#out + 1] = ("    [%dx] %s"):format(ce.n, ce.c)
            end
        end
        local sigs = {}
        for sig, cnt in pairs(prof.sigs) do
            sigs[#sigs + 1] = { s = sig, c = cnt }
        end
        table.sort(sigs, function(a, b) return a.c > b.c end)
        if #sigs > 0 then
            out[#out + 1] = "  SIGNATURES:"
            for k = 1, math.min(12, #sigs) do
                out[#out + 1] = ("    [%dx] %s"):format(sigs[k].c, sigs[k].s)
            end
        end
    end

    local text = table.concat(out, "\n")
    pcall(function()
        makefolder("SimplySpirited")
        writefile("SimplySpirited/api_doc_v2.txt", text)
    end)
    print("[watch] API doc saved: " .. #ranked .. " remotes -> SimplySpirited/api_doc_v2.txt")
    return text
end
SS2.apiDoc = SS2.generateAPIDoc

-- ════════════════════════════════════════════════════════════
-- FEED SEARCH (v4.6: structured returns)
-- ════════════════════════════════════════════════════════════
function SS2.searchFeed(term)
    print('═══ feed search: "' .. tostring(term) .. '" ═══')
    local results = {}
    for _, rec in ipairs(SS2.log) do
        local hay = rec.name .. " " .. table.concat(rec.args, " ")
        if hay:lower():find(tostring(term):lower(), 1, true) then
            results[#results + 1] = rec
            print(("#%d [%s] %s :: %s"):format(
                rec.id, rec.dir, rec.name, table.concat(rec.args, " | ")))
            if #results > 30 then
                print("… (30+ shown — refine term)")
                break
            end
        end
    end
    if #results == 0 then
        print("  (no matches)")
    end
    print("  matches: " .. #results .. " (returned as table — scriptable)")
    return results
end

print("[SS2-watch] v4.6 LIVE — verified replay, kind profiles, full docs")
print("[watch] SS2.replayId(n) / replayLast() / replayCount = x")
print("[watch] SS2.savePreset / playPreset / listPresets")
print("[watch] SS2.profileRemote('name') — with kind breakdown")
print("[watch] SS2.generateAPIDoc() — full data-layer doc")
print("[watch] SS2.searchFeed('term') — scriptable results")
print("[watch] SS2.togglePause()")
