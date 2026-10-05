-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.0 — DRAW UI FRAMEWORK
--  Native Drawing library. No Instance UI. No external deps.
--  • Window with draggable header, close button
--  • Tabs, buttons, toggles, labels, textboxes, scroll feed
--  • All state: SS2.ui — works on core.lua state
-- ════════════════════════════════════════════════════════════

print("[SS2-draw] building interface...")

local SS2 = getgenv().SS2
if not SS2 then warn("[SS2-draw] core.lua must load first") return end

local Players = game:GetService("Players")
local P = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local UIS = game:GetService("UserInputService")

-- ═══ DRAW HELPERS ═══
local drawObjects = {}
local function newDraw(class, props)
    local ok, obj = pcall(function()
        local d = Drawing.new(class)
        for k, v in pairs(props) do
            d[k] = v
        end
        return d
    end)
    if ok and obj then
        drawObjects[#drawObjects + 1] = obj
        return obj
    end
    return nil
end

SS2.unloadUI = function()
    for _, d in ipairs(drawObjects) do
        pcall(function() d:Remove() end)
    end
    drawObjects = {}
    SS2.ui = nil
    print("[SS2-draw] UI unloaded")
end

-- ═══ THEME ═══
local THEME = {
    BG      = Color3.fromRGB(16, 16, 22),
    PANEL   = Color3.fromRGB(24, 24, 32),
    ACCENT  = Color3.fromRGB(88, 140, 255),
    GREEN   = Color3.fromRGB(60, 255, 120),
    RED     = Color3.fromRGB(255, 70, 70),
    TEXT    = Color3.fromRGB(235, 235, 240),
    DIM     = Color3.fromRGB(140, 140, 155),
}
SS2.theme = THEME

-- ═══ WINDOW GEOMETRY ═══
local win = {
    x = 60, y = 60,
    w = 520, h = 380,
    headerH = 30,
    tabH = 26,
    dragging = false,
    dragOff = { x = 0, y = 0 },
    open = true,
}
SS2.ui = { win = win, tabs = {}, activeTab = 1 }

-- ═══ DRAW PRIMITIVES (re-created each frame? NO — static chrome + dynamic text) ═══
-- strategy: static chrome drawn once, repositioned on drag;
-- dynamic content (labels/feed) refreshed via update loop

local chrome = {}

local function rect(x, y, w, h, color, filled, transparency)
    local d = newDraw("Square", {
        Size = Vector2.new(w, h),
        Position = Vector2.new(x, y),
        Color = color,
        Filled = filled or false,
        Thickness = 1,
        Transparency = transparency or 1,
        Visible = true,
    })
    table.insert(chrome, { obj = d, dx = x - win.x, dy = y - win.y })
    return d
end

local function line(x1, y1, x2, y2, color, thickness)
    local d = newDraw("Line", {
        From = Vector2.new(x1, y1),
        To = Vector2.new(x2, y2),
        Color = color,
        Thickness = thickness or 1,
        Visible = true,
    })
    table.insert(chrome, { obj = d, dx = x1 - win.x, dy = y1 - win.y, dx2 = x2 - win.x, dy2 = y2 - win.y })
    return d
end

local function text(x, y, str, size, color, centered)
    local d = newDraw("Text", {
        Text = str,
        Size = size or 14,
        Position = Vector2.new(x, y),
        Color = color or THEME.TEXT,
        Centered = centered or false,
        Visible = true,
        Outline = true,
    })
    table.insert(chrome, { obj = d, dx = x - win.x, dy = y - win.y, isText = true })
    return d
end

-- ═══ STATIC CHROME: window shell ═══
rect(win.x, win.y, win.w, win.h, THEME.BG, true)                    -- bg
rect(win.x, win.y, win.w, win.headerH, THEME.PANEL, true)           -- header
rect(win.x, win.y, win.w, win.h, THEME.ACCENT, false, 0.7)          -- border
text(win.x + 10, win.y + 8, "SIMPLYSPIRITED v2.0", 14, THEME.ACCENT)
text(win.x + win.w - 90, win.y + 8, "SHADOWMILESC", 12, THEME.DIM)
local closeBtn = text(win.x + win.w - 22, win.y + 6, "X", 14, THEME.RED)

-- tab strip
rect(win.x, win.y + win.headerH, win.w, win.tabH, THEME.PANEL, true)
line(win.x, win.y + win.headerH + win.tabH, win.x + win.w, win.y + win.headerH + win.tabH, THEME.ACCENT, 1)

-- ═══ TABS ═══
local TAB_NAMES = { "FEED", "REMOTES", "VALUES", "REPLAY" }
SS2.ui.tabRects = {}
for i, name in ipairs(TAB_NAMES) do
    local tx = win.x + 10 + (i - 1) * 80
    local t = text(tx, win.y + win.headerH + 6, name, 13, i == 1 and THEME.ACCENT or THEME.DIM)
    SS2.ui.tabRects[i] = { x = tx - 6, y = win.y + win.headerH, w = 76, h = win.tabH, label = t }
end

-- ═══ CONTENT AREA (dynamic, per-tab, rebuilt on tab switch) ═══
local contentObjects = {}
local contentX = win.x + 10
local contentY = win.y + win.headerH + win.tabH + 8
local contentW = win.w - 20

local function clearContent()
    for _, d in ipairs(contentObjects) do
        pcall(function() d:Remove() end)
    end
    contentObjects = {}
end

local function cText(y, str, size, color)
    local d = text(contentX, y, str, size or 13, color)
    table.insert(contentObjects, d)
    return d
end

-- ═══ TAB CONTENT BUILDERS ═══
local function buildFeed()
    cText(contentY, "LIVE FEED (engine console has full detail)", 13, THEME.DIM)
    local feed = {}
    for i = #SS2.log, math.max(1, #SS2.log - 12), -1 do
        local rec = SS2.log[i]
        feed[#feed + 1] = ("#%d %s %s | %s"):format(
            rec.id, rec.dir, rec.name,
            (rec.args[1] and tostring(rec.args[1]):sub(1, 45)) or "")
    end
    if #feed == 0 then
        feed[1] = "(no calls captured yet — play the game)"
    end
    for i, line in ipairs(feed) do
        local rec = SS2.log[#SS2.log - i + 1]
        local col = rec and rec.dir == "OUT" and THEME.GREEN or THEME.TEXT
        cText(contentY + 20 * i, line, 12, col)
    end
end

local function buildRemotes()
    local list = {}
    for r, prof in pairs(SS2.remotes) do
        list[#list + 1] = { prof = prof, name = r.Name }
    end
    table.sort(list, function(a, b) return a.prof.calls > b.prof.calls end)
    cText(contentY, "REMOTES BY ACTIVITY (top 14)", 13, THEME.DIM)
    for i = 1, math.min(14, #list) do
        local e = list[i]
        cText(contentY + 20 * i, ("%4d  %s %s"):format(e.prof.calls, e.prof.class:sub(1, 6), e.prof.path:sub(1, 55)),
            12, e.prof.calls > 0 and THEME.TEXT or THEME.DIM)
    end
    if #list == 0 then cText(contentY + 20, "(none)", 12) end
end

local function buildValues()
    cText(contentY, "TRACKED VALUES", 13, THEME.DIM)
    local n = 0
    for obj, v in pairs(SS2.values) do
        if obj.Parent then
            n = n + 1
            cText(contentY + 20 * n, obj.Name .. " = " .. tostring(v), 12, THEME.GREEN)
        end
    end
    if n == 0 then cText(contentY + 20, "(none tracked yet)", 12) end
end

local function buildReplay()
    cText(contentY, "REPLAY (console-driven in v2.0 core)", 13, THEME.DIM)
    cText(contentY + 22, "SS2.replayLast() — re-fires most recent OUT call", 12)
    cText(contentY + 42, "SS2.replayId(n) — re-fires call #n", 12)
    cText(contentY + 62, "SS2.replayCount — set repeat count (default 1)", 12, THEME.DIM)
    if SS2.log[#SS2.log] then
        local last = SS2.log[#SS2.log]
        cText(contentY + 92, "last: #" .. last.id .. " " .. last.name, 12, THEME.ACCENT)
        cText(contentY + 112, table.concat(last.args, " | "):sub(1, 70), 11, THEME.DIM)
    end
end

local BUILDERS = { buildFeed, buildRemotes, buildValues, buildReplay }

local function rebuild()
    clearContent()
    BUILDERS[SS2.ui.activeTab]()
end
SS2.ui.rebuild = rebuild

-- ═══ REPLAY FUNCTIONS (engine-side, console-usable now) ═══
SS2.replayCount = 1
function SS2.replayLast()
    local rec = SS2.log[#SS2.log]
    if not rec then return false, "no calls" end
    return SS2.replayId(rec.id)
end
function SS2.replayId(id)
    local target
    for _, rec in ipairs(SS2.log) do
        if rec.id == id then target = rec break end
    end
    if not target then return false, "call #" .. id .. " not found" end
    local r = target.remote
    if not r or not r.Parent then return false, "remote destroyed" end
    task.spawn(function()
        for k = 1, SS2.replayCount do
            if target.class == "RemoteEvent" then
                pcall(function() r:FireServer(unpack(target.raw)) end)
            elseif target.class == "RemoteFunction" then
                pcall(function() r:InvokeServer(unpack(target.raw)) end)
            end
            if k < SS2.replayCount then task.wait(0.1) end
        end
    end)
    return true, ("firing #%d x%d"):format(id, SS2.replayCount)
end

-- ═══ DRAG + CLICK HANDLING ═══
local function inRect(px, py, rx, ry, rw, rh)
    return px >= rx and px <= rx + rw and py >= ry and py <= ry + rh
end

UIS.InputBegan:Connect(function(input, processed)
    if processed or not win.open then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        local px, py = UIS:GetMouseLocation().X, UIS:GetMouseLocation().Y
        -- close button
        if inRect(px, py, win.x + win.w - 30, win.y, 30, win.headerH) then
            SS2.unloadUI()
            return
        end
        -- tab click
        for i, tr in ipairs(SS2.ui.tabRects) do
            if inRect(px, py, tr.x, tr.y, tr.w, tr.h) then
                SS2.ui.activeTab = i
                for j, t2 in ipairs(SS2.ui.tabRects) do
                    t2.label.Color = (j == i) and THEME.ACCENT or THEME.DIM
                end
                rebuild()
                return
            end
        end
        -- header drag start
        if inRect(px, py, win.x, win.y, win.w, win.headerH) then
            win.dragging = true
            win.dragOff.x = px - win.x
            win.dragOff.y = py - win.y
        end
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        win.dragging = false
    end
end)

-- ═══ RENDER LOOP: drag chrome + refresh dynamic text ═══
local lastRefresh = 0
task.spawn(function()
    while SS2.ui do
        if win.dragging then
            local m = UIS:GetMouseLocation()
            local nx, ny = m.X - win.dragOff.x, m.Y - win.dragOff.y
            local dx, dy = nx - win.x, ny - win.y
            win.x, win.y = nx, ny
            for _, c in ipairs(chrome) do
                pcall(function()
                    c.obj.Position = Vector2.new(c.dx + win.x, c.dy + win.y)
                end)
            end
        end
        -- live refresh feed tab every 0.5s
        if os.clock() - lastRefresh > 0.5 and SS2.ui.activeTab == 1 then
            lastRefresh = os.clock()
            rebuild()
        end
        task.wait(0.03)
    end
end)

rebuild()

SS2.uiReady = true

print("[SS2-draw] UI LIVE — window top-left, tabs: FEED/REMOTES/VALUES/REPLAY")
print("[SS2-draw] replay: SS2.replayLast() / SS2.replayId(n) / SS2.replayCount = x")
