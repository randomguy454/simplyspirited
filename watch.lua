-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v3.1 — SURVEILLANCE ENGINE
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  Engine functions only — display owned by ui.lua.
--  • pause/resume • remote deep-dives • replay engine (absorbed
--    from draw.lua) • arg presets • API docs • feed search
-- ════════════════════════════════════════════════════════════

print("[SS2-watch] loading surveillance engine...")

local SS2 = getgenv().SS2
if not SS2 then warn("[SS2-watch] core must load first") return end

-- ═══ PAUSE / RESUME ═══
SS2.paused = false
SS2.togglePause = function()
    SS2.paused = not SS2.paused
    SS2.capture = not SS2.paused
    print("[watch] capture " .. (SS2.paused and "PAUSED" or "RESUMED"))
    return SS2.paused
end

-- ═══ REMOTE DEEP-DIVE ═══
function SS2.profileRemote(nameOrPath)
    local matches = {}
    for r, prof in pairs(SS2.remotes) do
        if r.Name == nameOrPath or (prof.path and prof.path:find(nameOrPath, 1, true)) then
            matches[#matches + 1] = { r = r, prof = prof }
        end
    end
    if #matches == 0 then
        print("[watch] no remote matches '" .. tostring(nameOrPath) .. "'")
        return nil
    end
    for _, m in ipairs(matches) do
        local prof = m.prof
        print("═══ REMOTE PROFILE ═══")
        print("  name:  " .. m.r.Name)
        print("  class: " .. m.r.ClassName)
        print("  path:  " .. (prof.path or "?"))
        print("  calls: " .. prof.calls .. " (out " .. prof.out .. " / in " .. prof.inn .. ")")
        if prof.metaCaught and prof.metaCaught > 0 then
            print("  meta-net caught: " .. prof.metaCaught)
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

-- ═══ REPLAY ENGINE (absorbed from draw.lua) ═══
SS2.replayCount = 1

function SS2.replayId(id)
    local target
    for _, rec in ipairs(SS2.log) do
        if rec.id == id then target = rec break end
    end
    if not target then
        print("[watch] call #" .. tostring(id) .. " not found")
        return false
    end
    local r = target.remote
    if not r or not r.Parent then
        print("[watch] remote no longer exists")
        return false
    end
    task.spawn(function()
        for k = 1, SS2.replayCount do
            if target.class == "RemoteEvent" then
                pcall(function() r:FireServer(unpack(target.raw)) end)
            elseif target.class == "RemoteFunction" then
                pcall(function() r:InvokeServer(unpack(target.raw)) end)
            end
            if k < SS2.replayCount then task.wait(0.1) end
        end
        print("[watch] replayed #" .. id .. " x" .. SS2.replayCount)
    end)
    return true
end

function SS2.replayLast()
    local rec = SS2.log[#SS2.log]
    if not rec then print("[watch] no calls") return false end
    return SS2.replayId(rec.id)
end

-- ═══ ARG PRESETS ═══
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
    if not target then print("[watch] no call to save") return end
    SS2.presets[name] = {
        remoteName = target.name,
        path = target.path,
        class = target.class,
        raw = target.raw,
        args = target.args,
        saved = os.date("%H:%M:%S"),
    }
    print("[watch] preset '" .. name .. "' saved: " .. target.name)
end

function SS2.playPreset(name, count, delay)
    count = count or 1
    delay = delay or 0.15
    local p = SS2.presets[name]
    if not p then print("[watch] no preset '" .. tostring(name) .. "'") return end
    local live = nil
    for r, prof in pairs(SS2.remotes) do
        if prof.path == p.path then live = r break end
    end
    if not live then print("[watch] remote no longer exists: " .. p.path) return end
    task.spawn(function()
        for k = 1, count do
            if p.class == "RemoteEvent" then
                pcall(function() live:FireServer(unpack(p.raw)) end)
            else
                pcall(function() live:InvokeServer(unpack(p.raw)) end)
            end
            if k < count then task.wait(delay) end
        end
        print("[watch] preset '" .. name .. "' fired x" .. count)
    end)
end

function SS2.listPresets()
    print("═══ PRESETS ═══")
    local n = 0
    for name, p in pairs(SS2.presets) do
        n = n + 1
        print(("  %s | %s %s | %d args | saved %s"):format(
            name, p.class, p.remoteName, #p.raw, p.saved))
    end
    if n == 0 then print("  (empty)") end
end

-- ═══ API DOC ═══
function SS2.generateAPIDoc()
    local out = {}
    out[#out + 1] = "╔══════════════════════════════════════╗"
    out[#out + 1] = "  SIMPLYSPIRITED v3.1 — API DOCUMENT"
    out[#out + 1] = "  game: " .. SS2.game .. " | place: " .. SS2.placeId
    out[#out + 1] = "  generated: " .. os.date()
    out[#out + 1] = "  operator: SHADOWMILESC (computerizedcarrier2)"
    out[#out + 1] = "╚══════════════════════════════════════╝"
    out[#out + 1] = ""

    local ranked = {}
    for r, prof in pairs(SS2.remotes) do
        ranked[#ranked + 1] = { r = r, prof = prof }
    end
    table.sort(ranked, function(a, b) return a.prof.calls > b.prof.calls end)

    out[#out + 1] = "TOTAL REMOTES: " .. #ranked
    out[#out + 1] = "TOTAL CALLS CAPTURED: " .. #SS2.log
    out[#out + 1] = ""

    for _, e in ipairs(ranked) do
        local prof = e.prof
        out[#out + 1] = "──────────────────────────────────────"
        out[#out + 1] = ("REMOTE: %s (%s)"):format(e.r.Name, prof.class)
        out[#out + 1] = ("PATH:   %s"):format(prof.path)
        out[#out + 1] = ("CALLS:  %d (out %d / in %d)"):format(prof.calls, prof.out, prof.inn)
        if prof.metaCaught and prof.metaCaught > 0 then
            out[#out + 1] = ("  (meta-net caught %d)"):format(prof.metaCaught)
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

-- ═══ FEED SEARCH ═══
function SS2.searchFeed(term)
    print('═══ FEED SEARCH: "' .. tostring(term) .. '" ═══')
    local n = 0
    for _, rec in ipairs(SS2.log) do
        local hay = rec.name .. " " .. table.concat(rec.args, " ")
        if hay:lower():find(tostring(term):lower(), 1, true) then
            n = n + 1
            print(("#%d [%s] %s :: %s"):format(rec.id, rec.dir, rec.name, table.concat(rec.args, " | ")))
            if n > 30 then
                print("... (30+ shown — refine term)")
                break
            end
        end
    end
    if n == 0 then print("  (no matches)") end
    return n
end

print("[SS2-watch] surveillance engine LIVE (display = ui.lua)")
