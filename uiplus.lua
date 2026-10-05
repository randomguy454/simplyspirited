-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.3 — UI PLUS (SOLE FEED OWNER)
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  TAKES OWNERSHIP of the feed window:
--   • destroys watch.lua's feed draw objects (engine functions
--     in watch.lua remain fully functional)
--   • rebuilds: scrollable feed (wheel + scrollbar + LIVE-pin),
--     click-to-expand detail panel, clipboard actions
--   • keyboard while panel open: R=replay C=copy P=preset I=inspect
--  watch.lua: add "if SS2.uiplusOwner then return end" to the top
--  of its render loop (see loader notes) OR let this file handle
--  the handoff automatically below.
-- ════════════════════════════════════════════════════════════

print("[SS2-uiplus] taking feed ownership...")

local SS2 = getgenv().SS2
if not SS2 then warn("[SS2-uiplus] core must load first") return end
if not SS2.feedWin then warn("[SS2-uiplus] watch.lua feed window not found") return end

local UIS = game:GetService("UserInputService")
local THEME = SS2.theme
local fw = SS2.feedWin

-- ═══ SIGNAL WATCH.LUI HANDOFF ═══
SS2.uiplusOwner = true

-- ═══ DESTROY WATCH'S FEED OBJECTS ═══
-- watch.lua stored its objects in a local table we can't reach,
-- so we track and remove ALL current Drawing objects in the feed
-- region by re-creating clean. Simplest safe approach: watch.lua's
-- objects are its own GC — we set its loop's exit flag instead.
fw.open = false -- watch.lua's render loop exits on this

-- ═══ OUR STATE ═══
local UP = {
    scrollOffset = 0,
    pinned = true,
    selected = nil,
    panelOpen = false,
}
SS2.uiplus = UP

local FEED_ROWS = 13
local ROW_H = 17
local PANEL_H = 110

-- ═══ DRAW REGISTRY ═══
local objs = {}
local function newD(class, props)
    local ok, obj = pcall(function()
        local d = Drawing.new(class)
        for k, v in pairs(props) do d[k] = v end
        return d
    end)
    if ok and obj then objs[#objs + 1] = obj return obj end
end

local function unloadAll()
    for _, d in ipairs(objs) do
        pcall(function() d:Remove() end)
    end
    objs = {}
    SS2.uiplusOwner = false
    print("[SS2-uiplus] window destroyed — engine functions still live")
end

-- ═══ WINDOW SHELL ═══
local W = {
    x = fw.x, y = fw.y,
    w = fw.w, h = fw.h + PANEL_H, -- room for the expandable panel
    headerH = 26,
    dragging = false,
    off = { x = 0, y = 0 },
}

local function refreshPositions()
    local dx = W.x - fw.x
    local dy = W.y - fw.y
    for _, d in ipairs(objs) do
        pcall(function()
            d.Position = d.Position + Vector2.new(dx, dy)
        end)
    end
    fw.x, fw.y = W.x, W.y
end

-- chrome
newD("Square", { Size = Vector2.new(W.w, W.h), Position = Vector2.new(W.x, W.y), Color = Color3.fromRGB(12, 12, 16), Filled = true, Visible = true })
newD("Square", { Size = Vector2.new(W.w, W.headerH), Position = Vector2.new(W.x, W.y), Color = THEME.PANEL, Filled = true, Visible = true })
newD("Square", { Size = Vector2.new(W.w, W.h), Position = Vector2.new(W.x, W.y), Color = THEME.GREEN, Filled = false, Transparency = 0.6, Visible = true })
newD("Text", { Text = "SURVEILLANCE+ — " .. SS2.game:sub(1, 22), Size = 13, Position = Vector2.new(W.x + 8, W.y + 6), Color = THEME.GREEN, Visible = true, Outline = true })
newD("Text", { Text = "X", Size = 13, Position = Vector2.new(W.x + W.w - 18, W.y + 5), Color = THEME.RED, Visible = true, Outline = true })
newD("Text", { Text = "[PAUSE]", Size = 12, Position = Vector2.new(W.x + W.w - 90, W.y + 5), Color = THEME.ACCENT, Visible = true, Outline = true })

-- scrollbar strip
newD("Square", { Size = Vector2.new(6, W.h - W.headerH - 26), Position = Vector2.new(W.x + W.w - 9, W.y + W.headerH + 4), Color = Color3.fromRGB(40, 40, 50), Filled = true, Visible = true })
local sbThumb = newD("Square", { Size = Vector2.new(6, 40), Position = Vector2.new(W.x + W.w - 9, W.y + W.headerH + 4), Color = THEME.ACCENT, Filled = true, Visible = true })

-- live indicator
local liveDot = newD("Text", { Text = "● LIVE", Size = 11, Position = Vector2.new(W.x + W.w - 150, W.y + W.h - 18), Color = THEME.GREEN, Visible = true, Outline = true })

-- stat line
local statT = newD("Text", { Text = "", Size = 12, Position = Vector2.new(W.x + 8, W.y + W.h - 18), Color = THEME.DIM, Visible = true, Outline = true })

-- feed rows
local feedTexts = {}
for i = 1, FEED_ROWS do
    feedTexts[i] = newD("Text", {
        Text = "", Size = 12,
        Position = Vector2.new(W.x + 8, W.y + W.headerH + 4 + (i - 1) * ROW_H),
        Color = THEME.TEXT, Visible = true, Outline = true,
    })
end

-- panel (bottom section, hidden by default)
local pH = PANEL_H - 20
local panelBG = newD("Square", { Size = Vector2.new(W.w - 16, pH), Position = Vector2.new(W.x + 8, W.y + W.h - pH - 24), Color = Color3.fromRGB(20, 20, 30), Filled = true, Visible = false })
local panelBorder = newD("Square", { Size = Vector2.new(W.w - 16, pH), Position = Vector2.new(W.x + 8, W.y + W.h - pH - 24), Color = THEME.ACCENT, Filled = false, Transparency = 0.4, Visible = false })
local panelTitle = newD("Text", { Text = "", Size = 12, Position = Vector2.new(W.x + 14, W.y + W.h - pH - 20), Color = THEME.ACCENT, Visible = false, Outline = true })
local panelBody = newD("Text", { Text = "", Size = 11, Position = Vector2.new(W.x + 14, W.y + W.h - pH - 4), Color = THEME.TEXT, Visible = false, Outline = true })
local panelHint = newD("Text", { Text = "[R] replay  [C] copy  [P] preset  [I] inspect  |  [X] close panel", Size = 11, Position = Vector2.new(W.x + 14, W.y + W.h - 24), Color = THEME.DIM, Visible = false, Outline = true })

-- ═══ PANEL LOGIC ═══
local function panelShow(rec)
    UP.selected = rec
    UP.panelOpen = true
    local argsText = table.concat(rec.args, "\n    ")
    panelTitle.Text = ("CALL #%d — %s (%s)"):format(rec.id, rec.name, rec.class)
    panelBody.Text = ("path: %s\ndir: %s | time: %.1f\nargs:\n    %s"):format(
        rec.path, rec.dir, rec.t, argsText:sub(1, 400))
    for _, d in ipairs({ panelBG, panelBorder, panelTitle, panelBody, panelHint }) do
        d.Visible = true
    end
end

local function panelHide()
    UP.panelOpen = false
    for _, d in ipairs({ panelBG, panelBorder, panelTitle, panelBody, panelHint }) do
        d.Visible = false
    end
end

local function panelAction(key)
    local rec = UP.selected
    if not rec then return end
    if key == "R" then
        SS2.replayId(rec.id)
        print("[uiplus] replay fired for #" .. rec.id)
    elseif key == "C" then
        if setclipboard then
            setclipboard(table.concat(rec.args, ", "))
            print("[uiplus] args copied to clipboard")
        else
            print("[uiplus] setclipboard unavailable in this executor")
        end
    elseif key == "P" then
        SS2.savePreset("uiplus_" .. rec.id, rec.id)
    elseif key == "I" then
        SS2.inspectLast()
    end
end

-- ═══ SCROLL ═══
local function maxScroll()
    local m = #SS2.log - FEED_ROWS
    return (m > 0) and m or 0
end

local function updateScrollbar()
    local total = #SS2.log
    local trackH = W.h - W.headerH - 26
    if total <= FEED_ROWS then
        sbThumb.Size = Vector2.new(6, trackH)
        sbThumb.Position = Vector2.new(W.x + W.w - 9, W.y + W.headerH + 4)
        liveDot.Text = "● LIVE"
        liveDot.Color = THEME.GREEN
        return
    end
    local thumbH = math.max(18, math.floor(trackH * FEED_ROWS / total))
    local maxS = maxScroll()
    local frac = UP.pinned and 1 or (1 - UP.scrollOffset / maxS)
    local ty = (W.y + W.headerH + 4) + math.floor((trackH - thumbH) * frac)
    sbThumb.Size = Vector2.new(6, thumbH)
    sbThumb.Position = Vector2.new(W.x + W.w - 9, ty)
    if UP.pinned then
        liveDot.Text = "● LIVE"
        liveDot.Color = THEME.GREEN
    else
        liveDot.Text = "▲ " .. UP.scrollOffset .. " from live"
        liveDot.Color = Color3.fromRGB(240, 190, 90)
    end
end

local function scrollBy(delta)
    local maxS = maxScroll()
    if maxS == 0 then return end
    if UP.pinned and delta < 0 then
        UP.pinned = false
        UP.scrollOffset = math.min(-delta, maxS)
        return
    end
    UP.scrollOffset = UP.scrollOffset + delta
    if UP.scrollOffset <= 0 then
        UP.scrollOffset = 0
        UP.pinned = true
    end
    if UP.scrollOffset > maxS then
        UP.scrollOffset = maxS
    end
end

-- ═══ FEED RENDER ═══
local function renderFeed()
    local startIdx
    if UP.pinned then
        startIdx = math.max(1, #SS2.log - FEED_ROWS + 1)
    else
        startIdx = math.max(1, #SS2.log - UP.scrollOffset - FEED_ROWS + 1)
    end
    for i = 1, FEED_ROWS do
        local rec = SS2.log[startIdx + i - 1]
        local t = feedTexts[i]
        if rec then
            t.Text = ("#%d %s %s | %s"):format(
                rec.id, rec.dir, rec.name:sub(1, 16),
                (rec.args[1] and tostring(rec.args[1]):sub(1, 42)) or "")
            t.Color = (UP.selected and rec.id == UP.selected.id) and THEME.ACCENT
                or (rec.dir == "OUT" and THEME.GREEN or THEME.TEXT)
        else
            t.Text = ""
        end
    end
    updateScrollbar()
end

-- ═══ INPUT ═══
UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        local m = UIS:GetMouseLocation()
        local px, py = m.X, m.Y
        if px < W.x or px > W.x + W.w or py < W.y or py > W.y + W.h then return end

        -- close button
        if px >= W.x + W.w - 26 and py <= W.y + W.headerH then
            unloadAll()
            return
        end
        -- pause button
        if px >= W.x + W.w - 100 and px <= W.x + W.w - 40 and py <= W.y + W.headerH then
            SS2.togglePause()
            return
        end
        -- header drag
        if py <= W.y + W.headerH then
            W.dragging = true
            W.off = { x = px - W.x, y = py - W.y }
            return
        end
        -- panel close (click anywhere in panel region when open)
        if UP.panelOpen and py >= W.y + W.h - PANEL_H then
            panelHide()
            return
        end
        -- feed row click → expand
        if not UP.panelOpen then
            for i = 1, FEED_ROWS do
                local ry0 = W.y + W.headerH + 4 + (i - 1) * ROW_H
                local ry1 = ry0 + ROW_H
                if py >= ry0 and py < ry1 then
                    local startIdx = UP.pinned
                        and math.max(1, #SS2.log - FEED_ROWS + 1)
                        or math.max(1, #SS2.log - UP.scrollOffset - FEED_ROWS + 1)
                    local rec = SS2.log[startIdx + i - 1]
                    if rec then
                        panelShow(rec)
                    end
                    return
                end
            end
        end
    end
end)

UIS.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseWheel then
        scrollBy(input.Position.Z > 0 and -3 or 3)
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        W.dragging = false
    end
end)

-- keyboard shortcuts while panel open
UIS.InputBegan:Connect(function(input, processed)
    if processed or not UP.panelOpen then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    local key = input.KeyCode
    if key == Enum.KeyCode.R then panelAction("R")
    elseif key == Enum.KeyCode.C then panelAction("C")
    elseif key == Enum.KeyCode.P then panelAction("P")
    elseif key == Enum.KeyCode.I then panelAction("I")
    elseif key == Enum.KeyCode.X then panelHide()
    end
end)

-- ═══ MAIN LOOP ═══
local lastRender = 0
task.spawn(function()
    while SS2.uiplusOwner do
        if W.dragging then
            local m = UIS:GetMouseLocation()
            local nx, ny = m.X - W.off.x, m.Y - W.off.y
            local dx, dy = nx - W.x, ny - W.y
            W.x, W.y = nx, ny
            for _, d in ipairs(objs) do
                pcall(function() d.Position = d.Position + Vector2.new(dx, dy) end)
            end
        end
        -- feed render: pinned refreshes live; scrolled view refreshes on demand only
        if UP.pinned and os.clock() - lastRender > 0.35 then
            lastRender = os.clock()
            renderFeed()
        end
        task.wait(0.03)
    end
end)

renderFeed()

print("[SS2-uiplus] UI+ LIVE — scroll (wheel/scrollbar) | click rows to expand")
print("[SS2-uiplus] panel keys: R replay | C copy | P preset | I inspect | X close")
SS2.journalAdd and SS2.journalAdd("UIPLUS", "feed window upgraded — sole owner")
