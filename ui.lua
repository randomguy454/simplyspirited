--=====================================================================
--  PROJECT   : SimplySpy
--  FILE      : ui.lua (INTERFACE)
--  VERSION   : 0.3.1
--  PURPOSE   : CoreGui interface with container fallback ladder
--              and console-only degradation.
--  LICENSE   : MIT
--=====================================================================

local UI = {}
local log = function() end
local Hook
local Format
local ctx

local gui
local mainWindow
local listFrame
local statusLabel
local filterBox
local isShown = false
local uiTier = 0
local connectionPool = {}
local MAX_ROWS = 100
local detailFrame = nil

------------------------------------------------------------------
-- THEME
------------------------------------------------------------------

local T

local function resolveTheme()
    T = (ctx and ctx.theme) or {
        Background    = Color3.fromRGB(16, 16, 22),
        Card          = Color3.fromRGB(28, 28, 36),
        CardBorder    = Color3.fromRGB(46, 46, 58),
        Accent        = Color3.fromRGB(88, 140, 255),
        AccentSoft    = Color3.fromRGB(124, 168, 255),
        Success       = Color3.fromRGB(88, 200, 132),
        Error         = Color3.fromRGB(232, 92, 92),
        TextPrimary   = Color3.fromRGB(238, 238, 242),
        TextSecondary = Color3.fromRGB(156, 156, 170),
        TextFaint     = Color3.fromRGB(104, 104, 118),
        BarTrack      = Color3.fromRGB(38, 38, 48),
    }
end

------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------

local function new(className, props)
    local inst = Instance.new(className)
    local parent = nil
    for k, v in pairs(props or {}) do
        if k == "Parent" then
            parent = v
        else
            inst[k] = v
        end
    end
    if parent then inst.Parent = parent end
    return inst
end

local function corner(parent, r)
    new("UICorner", { CornerRadius = UDim.new(0, r or 8), Parent = parent })
end

local function stroke(parent, color, thickness)
    new("UIStroke", { Color = color, Thickness = thickness or 1, Parent = parent })
end

local function makeDraggable(handle, target)
    local ok = pcall(function()
        handle.Active = true
        handle.Draggable = true
    end)
    if ok then return end

    -- Manual drag fallback for executors without .Draggable
    local dragging = false
    local dragStart, startPos

    local b = handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = target.Position
        end
    end)

    local c = handle.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    local e = handle.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    table.insert(connectionPool, b)
    table.insert(connectionPool, c)
    table.insert(connectionPool, e)
end

------------------------------------------------------------------
-- CONTAINER RESOLUTION (tier ladder)
------------------------------------------------------------------

local function resolveContainer()
    local ok = pcall(function()
        local test = Instance.new("ScreenGui")
        test.Name = "SimplySpy_Probe"
        test.Parent = game:GetService("CoreGui")
        test:Destroy()
    end)
    if ok then
        return game:GetService("CoreGui"), 1
    end

    if type(gethui) == "function" then
        local ok2, container = pcall(gethui)
        if ok2 and container then
            return container, 2
        end
    end

    local player = game:GetService("Players").LocalPlayer
    if player then
        local pg = player:FindFirstChild("PlayerGui")
        if pg then
            return pg, 3
        end
    end

    return nil, 4
end

------------------------------------------------------------------
-- ROWS (pooled)
------------------------------------------------------------------

local function makeRow()
    local row = new("TextButton", {
        Name = "Row",
        Size = UDim2.new(1, -8, 0, 26),
        BackgroundColor3 = T.Card,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Parent = listFrame,
    })
    corner(row, 4)

    local label = new("TextLabel", {
        Name = "Label",
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.new(0, 8, 0, 0),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = T.TextSecondary,
        TextSize = 12,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = row,
    })

    row.Label = label
    return row
end

------------------------------------------------------------------
-- LIST REFRESH
------------------------------------------------------------------

local function refreshList()
    if not isShown or not listFrame then return end

    local captures = Hook.getRecent(MAX_ROWS)

    for _, child in ipairs(listFrame:GetChildren()) do
        if child.Name == "Row" then
            child.Visible = false
        end
    end

    local visible = 0
    for i = #captures, 1, -1 do
        local capture = captures[i]
        local row = listFrame:FindFirstChild("Row" .. capture.id)
        if not row then
            if visible >= MAX_ROWS then break end
            row = makeRow()
            row.Name = "Row" .. capture.id
            row.MouseButton1Click:Connect(function()
                UI.showDetail(capture.id)
            end)
        end
        row.Visible = true
        row.LayoutOrder = capture.id
        row.Label.Text = string.format("[%d] %s",
            capture.id, Format.callToLine(capture))
        visible = visible + 1
    end

    listFrame.CanvasSize = UDim2.new(0, 0, 0, visible * 28)

    statusLabel.Text = string.format("%d captured | tier %d",
        Hook.count(), uiTier)
end

------------------------------------------------------------------
-- DETAIL VIEW
------------------------------------------------------------------

function UI.showDetail(id)
    local capture = Hook.getById(id)
    if not capture then return end

    if detailFrame then
        detailFrame:Destroy()
        detailFrame = nil
    end

    detailFrame = new("Frame", {
        Name = "DetailWindow",
        Size = UDim2.fromOffset(480, 420),
        Position = UDim2.new(0.5, 250, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = T.Card,
        BorderSizePixel = 0,
        Parent = gui,
    })
    corner(detailFrame, 10)
    stroke(detailFrame, T.CardBorder)

    new("TextLabel", {
        Size = UDim2.new(1, -90, 0, 32),
        Position = UDim2.new(0, 14, 0, 14),
        BackgroundTransparency = 1,
        Text = string.format("Capture #%d", capture.id),
        TextColor3 = T.TextPrimary,
        TextSize = 16,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = detailFrame,
    })

    local closeBtn = new("TextButton", {
        Size = UDim2.fromOffset(70, 26),
        Position = UDim2.new(1, -84, 0, 14),
        BackgroundColor3 = T.Error,
        BorderSizePixel = 0,
        Text = "Close",
        TextColor3 = T.TextPrimary,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        Parent = detailFrame,
    })
    corner(closeBtn, 6)
    closeBtn.MouseButton1Click:Connect(function()
        detailFrame:Destroy()
        detailFrame = nil
    end)

    local copyBtn = new("TextButton", {
        Size = UDim2.fromOffset(70, 26),
        Position = UDim2.new(1, -84, 0, 48),
        BackgroundColor3 = T.Accent,
        BorderSizePixel = 0,
        Text = "Copy",
        TextColor3 = T.TextPrimary,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        Parent = detailFrame,
    })
    corner(copyBtn, 6)
    copyBtn.MouseButton1Click:Connect(function()
        Hook.copy(capture.id)
    end)

    local argsList = new("ScrollingFrame", {
        Size = UDim2.new(1, -28, 1, -120),
        Position = UDim2.new(0, 14, 0, 88),
        BackgroundColor3 = T.Background,
        BorderSizePixel = 0,
        ScrollBarThickness = 6,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        Parent = detailFrame,
    })
    corner(argsList, 6)

    new("UIListLayout", {
        Padding = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = argsList,
    })

    local yOffset = 0
    for i, arg in ipairs(capture.args) do
        local text = string.format("[%d] %s", i, Format.display(arg))
        local height = 20
        if #text > 60 then
            height = 20 + math.floor(#text / 60) * 16
        end

        local argLabel = new("TextLabel", {
            Size = UDim2.new(1, -12, 0, height),
            BackgroundTransparency = 1,
            Text = text,
            TextColor3 = Format.colorFor and Format.colorFor(arg)
                or T.TextSecondary,
            TextSize = 12,
            Font = Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = #text > 60,
            LayoutOrder = i,
            Parent = argsList,
        })
        yOffset = yOffset + height + 2
    end

    argsList.CanvasSize = UDim2.new(0, 0, 0, yOffset + 8)

    new("TextLabel", {
        Size = UDim2.new(1, -28, 0, 30),
        Position = UDim2.new(0, 14, 1, -44),
        BackgroundTransparency = 1,
        Text = capture.remotePath,
        TextColor3 = T.TextFaint,
        TextSize = 11,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = detailFrame,
    })
end

------------------------------------------------------------------
-- MAIN WINDOW
------------------------------------------------------------------

local function buildMainWindow()
    mainWindow = new("Frame", {
        Name = "SimplySpyMainWindow",
        Size = UDim2.fromOffset(440, 480),
        Position = UDim2.new(0.5, -220, 0.5, -240),
        BackgroundColor3 = T.Card,
        BorderSizePixel = 0,
        Visible = false,
        Parent = gui,
    })
    corner(mainWindow, 10)
    stroke(mainWindow, T.CardBorder)

    -- Title bar
    local titleBar = new("Frame", {
        Name = "TitleBar",
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = T.Background,
        BorderSizePixel = 0,
        Parent = mainWindow,
    })
    corner(titleBar, 10)

    new("TextLabel", {
        Size = UDim2.new(1, -60, 1, 0),
        Position = UDim2.new(0, 14, 0, 0),
        BackgroundTransparency = 1,
        Text = "SimplySpy",
        TextColor3 = T.TextPrimary,
        TextSize = 16,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = titleBar,
    })

    new("TextLabel", {
        Size = UDim2.new(0, 60, 1, 0),
        Position = UDim2.new(1, -60, 0, 0),
        BackgroundTransparency = 1,
        Text = "v" .. tostring(ctx and ctx.version or "?"),
        TextColor3 = T.TextFaint,
        TextSize = 11,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = titleBar,
    })

    makeDraggable(titleBar, mainWindow)

    -- Toolbar
    local toolbar = new("Frame", {
        Name = "Toolbar",
        Size = UDim2.new(1, 0, 0, 36),
        Position = UDim2.new(0, 0, 0, 40),
        BackgroundColor3 = T.Background,
        BorderSizePixel = 0,
        Parent = mainWindow,
    })

    filterBox = new("TextBox", {
        Size = UDim2.new(0.6, -10, 0, 24),
        Position = UDim2.new(0, 10, 0.5, -12),
        BackgroundColor3 = T.BarTrack,
        BorderSizePixel = 0,
        Text = "",
        PlaceholderText = "Filter remote name...",
        TextColor3 = T.TextPrimary,
        PlaceholderColor3 = T.TextFaint,
        TextSize = 12,
        Font = Enum.Font.Gotham,
        ClearTextOnFocus = false,
        Parent = toolbar,
    })
    corner(filterBox, 4)

    filterBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            if filterBox.Text == "" then
                Hook.setFilter(nil)
            else
                Hook.setFilter(filterBox.Text)
            end
            refreshList()
        end
    end)

    local btnClear = new("TextButton", {
        Size = UDim2.fromOffset(60, 24),
        Position = UDim2.new(1, -70, 0.5, -12),
        BackgroundColor3 = T.Error,
        BorderSizePixel = 0,
        Text = "Clear",
        TextColor3 = T.TextPrimary,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        Parent = toolbar,
    })
    corner(btnClear, 4)
    btnClear.MouseButton1Click:Connect(function()
        Hook.clear()
        refreshList()
    end)

    -- Capture list
    listFrame = new("ScrollingFrame", {
        Name = "CaptureList",
        Size = UDim2.new(1, -20, 1, -140),
        Position = UDim2.new(0, 10, 0, 84),
        BackgroundColor3 = T.Background,
        BorderSizePixel = 0,
        ScrollBarThickness = 6,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        Parent = mainWindow,
    })
    corner(listFrame, 6)

    new("UIListLayout", {
        Padding = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = listFrame,
    })

    -- Status bar
    statusLabel = new("TextLabel", {
        Name = "Status",
        Size = UDim2.new(1, -20, 0, 20),
        Position = UDim2.new(0, 10, 1, -26),
        BackgroundTransparency = 1,
        Text = "initializing...",
        TextColor3 = T.TextFaint,
        TextSize = 11,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = mainWindow,
    })
end

------------------------------------------------------------------
-- REAL-TIME UPDATES (throttled)
------------------------------------------------------------------

local refreshQueued = false
local lastRefresh = 0

local function onCapture()
    if not isShown then return end
    local now = os.clock()
    if now - lastRefresh < 0.1 then
        if not refreshQueued then
            refreshQueued = true
            task.delay(0.1, function()
                refreshQueued = false
                lastRefresh = os.clock()
                refreshList()
            end)
        end
        return
    end
    lastRefresh = now
    refreshList()
end

------------------------------------------------------------------
-- PUBLIC API
------------------------------------------------------------------

function UI.init(deps)
    log = (deps and deps.log) or log
    Hook = deps and deps.hook
    Format = deps and deps.format
    ctx = deps and deps.ctx

    if not Hook or not Format then
        return false, "missing dependencies"
    end

    resolveTheme()

    local container, tier = resolveContainer()
    uiTier = tier

    if tier == 4 then
        log("WARN", "no GUI container; console mode only")
        return true
    end

    gui = Instance.new("ScreenGui")
    gui.Name = "SimplySpy_" .. tostring(math.floor(os.clock() * 1000))
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 998
    gui.IgnoreGuiInset = true
    gui.Parent = container

    buildMainWindow()

    Hook.onCapture = onCapture

    log("INFO", "ui online (tier " .. tier .. ")")
    return true
end

function UI.show()
    if gui and mainWindow then
        mainWindow.Visible = true
        isShown = true
        refreshList()
    end
end

function UI.hide()
    if mainWindow then
        mainWindow.Visible = false
        isShown = false
    end
end

function UI.refresh()
    refreshList()
end

function UI.toggle()
    if isShown then
        UI.hide()
    else
        UI.show()
    end
end

function UI.shutdown()
    for _, conn in ipairs(connectionPool) do
        pcall(function() conn:Disconnect() end)
    end
    connectionPool = {}
    if gui then
        gui:Destroy()
        gui = nil
    end
    if Hook then
        Hook.onCapture = nil
    end
    isShown = false
end

------------------------------------------------------------------
-- MODULE CONTRACT
------------------------------------------------------------------

return function(deps)
    local ok, result = pcall(UI.init, deps)
    if not ok then
        error("ui init crashed: " .. tostring(result))
    end
    if result == false then
        error("ui init failed: " .. tostring((deps and deps.log) and "see logs" or result))
    end
    return UI
end
