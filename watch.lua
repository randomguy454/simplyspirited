-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.0 — SURVEILLANCE TIER
--  For SHADOWMILESC (computerizedcarrier2)
--  • Enhanced live feed with pause + copy-ready output
--  • Remote profiles: click-free console deep-dive per remote
--  • Arg presets: save/replay named call libraries
--  • Auto-doc: remote API documentation generator v2
-- ════════════════════════════════════════════════════════════

print("[SS2-watch] loading surveillance tier...")

local SS2 = getgenv().SS2
if not SS2 then warn("[SS2-watch] core must load first") return end

-- ═══════════ PAUSE / RESUME CAPTURE ═══════════
SS2.paused = false
SS2.togglePause = function()
    SS2.paused = not SS2.paused
    SS2.capture = not SS2.paused
    print("[watch] capture " .. (SS2.paused and "PAUSED" or "RESUMED"))
    return SS2.paused
end

-- ═══════════ REMOTE DEEP-DIVE ═══════════
-- full profile of one remote: every arg signature it's ever used
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
        print("  first: " .. prof.firstSeen .. " | last: " .. prof.lastSeen)
        -- rank signatures
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

-- ═══════════ ARG PRESETS ═══════════
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
    print("[watch] preset '" .. name .. "' saved: " .. target.name .. " (" .. #target.raw .. " args)")
end

function SS2.playPreset(name, count, delay)
    count = count or 1
    delay = delay or 0.15
    local p = SS2.presets[name]
    if not p then print("[watch] no preset '" .. tostring(name) .. "'") return end
    -- find the live remote by path
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

-- ═══════════ AUTO-DOC v2 ═══════════
function SS2.generateAPIDoc()
    local out = {}
    out[#out + 1] = "╔══════════════════════════════════════╗"
    out[#out + 1] = "  SIMPLYSPIRITED v2.0 — API DOCUMENT"
    out[#out + 1] = "  game: " .. SS2.game .. " | place: " .. SS2.placeId
    out[#out + 1] = "  generated: " .. os.date()
    out[#out + 1] = "  operator: SHADOWMILESC (computerizedcarrier2)"
    out[#out + 1] = "╚══════════════════════════════════════╝"
    out[#out + 1] = ""

    -- rank remotes by activity
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
        out[#out + 1] = ("CALLS:  %d (out %d / in %d) | seen %s -> %s"):format(
            prof.calls, prof.out, prof.inn, prof.firstSeen, prof.lastSeen)
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
    print("[watch] API doc saved: " .. #ranked .. " remotes, " .. #text .. " chars -> SimplySpirited/api_doc_v2.txt")
    return text
end
SS2.apiDoc = SS2.generateAPIDoc

-- ═══════════ LIVE FEED WINDOW (second Draw window) ═══════════
local THEME = SS2.theme
local UIS = game:GetService("UserInputService")

local fw = { x = 600, y = 60, w = 460, h = 320, headerH = 26, dragging = false, open = true }
SS2.feedWin = fw

local drawObjects = {}
local function newD(class, props)
    local ok, obj = pcall(function()
        local d = Drawing.new(class)
        for k, v in pairs(props) do d[k] = v end
        return d
    end)
    if ok and obj then drawObjects[#drawObjects + 1] = obj return obj end
end

-- chrome
local bg = newD("Square", { Size = Vector2.new(fw.w, fw.h), Position = Vector2.new(fw.x, fw.y), Color = Color3.fromRGB(12, 12, 16), Filled = true, Visible = true })
local hdr = newD("Square", { Size = Vector2.new(fw.w, fw.headerH), Position = Vector2.new(fw.x, fw.y), Color = THEME.PANEL, Filled = true, Visible = true })
local border = newD("Square", { Size = Vector2.new(fw.w, fw.h), Position = Vector2.new(fw.x, fw.y), Color = THEME.GREEN, Filled = false, Transparency = 0.6, Visible = true })
local title = newD("Text", { Text = "SURVEILLANCE FEED — " .. SS2.game:sub(1, 24), Size = 13, Position = Vector2.new(fw.x + 8, fw.y + 6), Color = THEME.GREEN, Visible = true, Outline = true })
local closeT = newD("Text", { Text = "X", Size = 13, Position = Vector2.new(fw.x + fw.w - 18, fw.y + 5), Color = THEME.RED, Visible = true, Outline = true })
local statT = newD("Text", { Text = "", Size = 12, Position = Vector2.new(fw.x + 8, fw.y + fw.h - 20), Color = THEME.DIM, Visible = true, Outline = true })

local feedTexts = {}
local FEED_ROWS = 13
for i = 1, FEED_ROWS do
    feedTexts[i] = newD("Text", {
        Text = "", Size = 12,
        Position = Vector2.new(fw.x + 8, fw.y + fw.headerH + 4 + (i - 1) * 17),
        Color = THEME.TEXT, Visible = true, Outline = true,
    })
end

-- pause button region
local pauseBtn = newD("Text", { Text = "[PAUSE]", Size = 12, Position = Vector2.new(fw.x + fw.w - 90, fw.y + 5), Color = THEME.ACCENT, Visible = true, Outline = true })

-- ═══ FEED REFRESH ═══
local function refreshFeed()
    local shown = 0
    for i = #SS2.log, 1, -1 do
        local rec = SS2.log[i]
        if rec.dir == "OUT" or rec.dir == "IN" then
            shown = shown + 1
            local idx = FEED_ROWS - shown + 1
            if idx >= 1 and feedTexts[idx] then
                local col = rec.dir == "OUT" and THEME.GREEN or THEME.TEXT
                feedTexts[idx].Text = ("#%d %s %s | %s"):format(
                    rec.id, rec.dir, rec.name:sub(1, 18),
                    (rec.args[1] and tostring(rec.args[1]):sub(1, 40)) or "")
                feedTexts[idx].Color = col
            end
            if shown >= FEED_ROWS then break end
        end
    end
    for i = 1, FEED_ROWS - shown do
        if feedTexts[i] then feedTexts[i].Text = "" end
    end
    local rc = 0
    for _ in pairs(SS2.remotes) do rc = rc + 1 end
    statT.Text = ("remotes: %d | captured: %d | %s"):format(rc, #SS2.log, SS2.paused and "PAUSED" or "LIVE")
end

-- ═══ DRAG + BUTTONS ═══
UIS.InputBegan:Connect(function(input, processed)
    if processed or not fw.open then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        local m = UIS:GetMouseLocation()
        local px, py = m.X, m.Y
        if px >= fw.x + fw.w - 26 and px <= fw.x + fw.w - 6 and py >= fw.y and py <= fw.y + fw.headerH then
            fw.open = false
            for _, d in ipairs(drawObjects) do d.Visible = false end
            print("[watch] feed window closed (engine still running)")
            return
        end
        if px >= fw.x + fw.w - 100 and px <= fw.x + fw.w - 30 and py >= fw.y and py <= fw.y + fw.headerH then
            SS2.togglePause()
            pauseBtn.Text = SS2.paused and "[RESUME]" or "[PAUSE]"
            return
        end
        if px >= fw.x and px <= fw.x + fw.w and py >= fw.y and py <= fw.y + fw.headerH then
            fw.dragging = true
            fw.off = { x = px - fw.x, y = py - fw.y }
        end
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        fw.dragging = false
    end
end)

-- ═══ MAIN LOOP ═══
local lastRefresh = 0
task.spawn(function()
    while fw.open do
        if fw.dragging then
            local m = UIS:GetMouseLocation()
            local nx, ny = m.X - fw.off.x, m.Y - fw.off.y
            local dx, dy = nx - fw.x, ny - fw.y
            fw.x, fw.y = nx, ny
            for _, d in ipairs(drawObjects) do
                pcall(function()
                    d.Position = d.Position + Vector2.new(dx, dy)
                end)
            end
        end
        if os.clock() - lastRefresh > 0.4 then
            lastRefresh = os.clock()
            refreshFeed()
        end
        task.wait(0.03)
    end
end)



print("[SS2-watch] surveillance tier LIVE")
print("[watch] console commands:")
print("  SS2.profileRemote('name')  — deep-dive any remote")
print("  SS2.savePreset('name')     — save last call as preset")
print("  SS2.playPreset('name', n)  — replay a preset n times")
print("  SS2.listPresets()          — your call library")
print("  SS2.generateAPIDoc()       — full API documentation -> file")
print("  SS2.togglePause()          — pause/resume capture")
