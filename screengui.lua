-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.6 — SCREENGUI UI LAYER
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  Replaces Drawing-based UI (broken on Delta) with ScreenGui.
--  Main window: tabs FEED / REMOTES / VALUES / REPLAY
--  Draggable, touch-friendly, always renders.
--  Replaces draw.lua in the loader. Engine untouched.
-- ════════════════════════════════════════════════════════════

print("[SS2-gui] building ScreenGui interface...")

local SS2 = getgenv().SS2
if not SS2 then warn("[SS2-gui] core must load first") return end

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local P = Players.LocalPlayer

-- ═══ CLEANUP OLD DRAW UI IF PRESENT ═══
if SS2.unloadUI then pcall(SS2.unloadUI) end
SS2.uiplusOwner = false

-- ═══ ROOT ═══
local gui = Instance.new("ScreenGui")
gui.Name = "SS2_Interface"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9999
local parented = pcall(function()
    gui.Parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
end)
if not parented then
    gui.Parent = P:WaitForChild("PlayerGui")
end

local THEME = {
    BG     = Color3.fromRGB(16, 16, 22),
    PANEL  = Color3.fromRGB(24, 24, 32),
    CARD   = Color3.fromRGB(32, 32, 42),
    ACCENT = Color3.fromRGB(88, 140, 255),
    GREEN  = Color3.fromRGB(60, 220, 120),
    RED    = Color3.fromRGB(255, 80, 80),
    YELL   = Color3.fromRGB(240, 190, 90),
    TEXT   = Color3.fromRGB(235, 235, 240),
    DIM    = Color3.fromRGB(150, 150, 165),
}
SS2.theme = THEME

local function corner(o, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = o
end

local function stroke(o, col)
    local s = Instance.new("UIStroke")
    s.Color = col or THEME.ACCENT
    s.Thickness = 1
    s.Parent = o
    return s
end

-- ═══ WINDOW ═══
local win = Instance.new("Frame")
win.Size = UDim2.new(0, 520, 0, 340)
win.Position = UDim2.new(0, 40, 0, 60)
win.BackgroundColor3 = THEME.BG
win.BorderSizePixel = 0
win.Active = true
corner(win, 10)
stroke(win, THEME.ACCENT)
win.Parent = gui

-- header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 32)
header.BackgroundColor3 = THEME.PANEL
header.BorderSizePixel = 0
corner(header, 10)
header.Parent = win
local hdrCover = Instance.new("Frame")
hdrCover.Size = UDim2.new(1, 0, 0, 12)
hdrCover.Position = UDim2.new(0, 0, 1, -12)
hdrCover.BackgroundColor3 = THEME.PANEL
hdrCover.BorderSizePixel = 0
hdrCover.Parent = header

local icon = Instance.new("TextLabel")
icon.Size = UDim2.new(0, 40, 0, 22)
icon.Position = UDim2.new(0, 8, 0, 5)
icon.BackgroundColor3 = THEME.ACCENT
icon.Text = "SS2"
icon.Font = Enum.Font.GothamBold
icon.TextSize = 12
icon.TextColor3 = Color3.new(1, 1, 1)
corner(icon, 6)
icon.Parent = header

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0, 260, 1, 0)
title.Position = UDim2.new(0, 56, 0, 0)
title.BackgroundTransparency = 1
title.Text = "SIMPLYSPIRITED v2.6 — " .. SS2.game:sub(1, 20)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = THEME.TEXT
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 26, 0, 22)
closeBtn.Position = UDim2.new(1, -32, 0, 5)
closeBtn.BackgroundColor3 = THEME.RED
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.TextColor3 = Color3.new(1, 1, 1)
corner(closeBtn, 6)
closeBtn.Parent = header

-- ═══ DRAG ═══
local dragging = false
local dragStart, startPos
header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = win.Position
    end
end)
UIS.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
    or input.UserInputType == Enum.UserInputType.Touch) then
        local d = input.Position - dragStart
        win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
            startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)
closeBtn.MouseButton1Click:Connect(function()
    gui:Destroy()
    SS2.uiGone = true
    print("[SS2-gui] interface closed — engine functions remain")
end)

-- ═══ TAB STRIP ═══
local TAB_NAMES = { "FEED", "REMOTES", "VALUES", "REPLAY" }
local tabStrip = Instance.new("Frame")
tabStrip.Size = UDim2.new(1, 0, 0, 28)
tabStrip.Position = UDim2.new(0, 0, 0, 32)
tabStrip.BackgroundColor3 = THEME.PANEL
tabStrip.BorderSizePixel = 0
tabStrip.Parent = win

local tabButtons = {}
local contentFrame = Instance.new("Frame")
contentFrame.Size = UDim2.new(1, -16, 1, -76)
contentFrame.Position = UDim2.new(0, 8, 0, 66)
contentFrame.BackgroundTransparency = 1
contentFrame.Parent = win

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, 0, 1, 0)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = THEME.ACCENT
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = contentFrame
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 3)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = scroll

local currentTab = 1
local tabRenderers = {}

local function switchTab(i)
    currentTab = i
    for j, b in ipairs(tabButtons) do
        b.TextColor3 = (j == i) and THEME.ACCENT or THEME.DIM
    end
    for _, c in ipairs(scroll:GetChildren()) do
        if c:IsA("TextLabel") or c:IsA("TextButton") then c:Destroy() end
    end
    tabRenderers[i]()
end

for i, name in ipairs(TAB_NAMES) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 90, 1, 0)
    b.Position = UDim2.new(0, 8 + (i - 1) * 95, 0, 0)
    b.BackgroundTransparency = 1
    b.Text = name
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.TextColor3 = (i == 1) and THEME.ACCENT or THEME.DIM
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Parent = tabStrip
    b.MouseButton1Click:Connect(function() switchTab(i) end)
    tabButtons[i] = b
end

local function addLine(txt, color, order)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, 0, 0, 18)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Code
    l.TextSize = 12
    l.TextColor3 = color or THEME.TEXT
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = txt
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.LayoutOrder = order or 0
    l.Parent = scroll
    return l
end
SS2.addLine = addLine
SS2.scroll = scroll
SS2.switchTab = switchTab

-- ═══ TAB RENDERERS ═══
tabRenderers[1] = function() -- FEED
    local n = 0
    for i = #SS2.log, math.max(1, #SS2.log - 40), -1 do
        local rec = SS2.log[i]
        n = n + 1
        local col = rec.dir == "OUT" and THEME.GREEN or THEME.TEXT
        addLine(("#%d %s %s | %s"):format(
            rec.id, rec.dir, rec.name,
            (rec.args[1] and tostring(rec.args[1]):sub(1, 50)) or ""),
            col, n)
    end
    if n == 0 then addLine("(no calls yet — play the game)", THEME.DIM, 1) end
end

tabRenderers[2] = function() -- REMOTES
    local ranked = {}
    for r, prof in pairs(SS2.remotes) do
        ranked[#ranked + 1] = { r = r, prof = prof }
    end
    table.sort(ranked, function(a, b) return a.prof.calls > b.prof.calls end)
    for k = 1, math.min(60, #ranked) do
        local e = ranked[k]
        addLine(("%4d  %s %s"):format(e.prof.calls, e.prof.class:sub(1, 6), e.prof.path:sub(1, 60)),
            e.prof.calls > 0 and THEME.TEXT or THEME.DIM, k)
    end
    if #ranked == 0 then addLine("(none)", THEME.DIM, 1) end
end

tabRenderers[3] = function() -- VALUES
    local n = 0
    for obj, v in pairs(SS2.values) do
        if obj.Parent then
            n = n + 1
            addLine(obj.Name .. " = " .. tostring(v), THEME.GREEN, n)
        end
    end
    if n == 0 then addLine("(none tracked)", THEME.DIM, 1) end
end

tabRenderers[4] = function() -- REPLAY
    addLine("REPLAY — console powered", THEME.DIM, 1)
    addLine("SS2.replayLast()  /  SS2.replayId(n)", THEME.TEXT, 2)
    addLine("SS2.replayCount = x   (repeat count)", THEME.DIM, 3)
    if SS2.log[#SS2.log] then
        local last = SS2.log[#SS2.log]
        addLine("last: #" .. last.id .. " " .. last.name, THEME.ACCENT, 4)
    end
end

switchTab(1)

-- auto-refresh FEED tab every second when visible
task.spawn(function()
    while gui.Parent do
        if currentTab == 1 and not SS2.uiGone then
            pcall(switchTab, 1)
        end
        task.wait(1)
    end
end)

SS2.gui = gui
SS2.uiReadySG = true
print("[SS2-gui] ScreenGui interface LIVE — FEED/REMOTES/VALUES/REPLAY")
