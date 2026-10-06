--=====================================================================
--  PROJECT   : SimplySpy
--  FILE      : ui.lua (INTERFACE) - UNIVERSAL BUILD
--  VERSION   : 0.2.0
--
--  PURPOSE   :
--    CoreGui interface for SimplySpy. Log list, detail view,
--    toolbar, status bar, notifications. Degrades gracefully:
--      Tier 1 : CoreGui (survives respawns, hidden from game)
--      Tier 2 : gethui() (executor-specific protected container)
--      Tier 3 : PlayerGui (visible to game code, always works)
--      Tier 4 : console-only (no GUI; SPY.* commands only)
--
--  UNIVERSALITY CONTRACT :
--    - No UI library dependency. Pure Instance construction.
--    - Draggable windows use the legacy .Draggable property with
--      a manual InputBegan/InputEnded fallback if unsupported.
--    - All colors from ctx.theme; no hardcoded palette.
--
--  RESPONSIBILITIES :
--    - Main window: toolbar, capture list, status bar
--    - Detail view: full arg inspection with type colors
--    - Copy button integration with hook.copy
--    - Real-time updates via hook.onCapture callback
--    - Filter and block controls in the toolbar
--
--  MODULE CONTRACT :
--    Receives (deps). Returns this module's public table.
--    deps.hook    (required) : hook module
--    deps.format  (required) : format module
--    deps.ctx     (required) : loader context (theme, gui)
--
--  TARGET    : universal (executors + Studio via adapter)
--  LICENSE   : MIT
--=====================================================================

-----------------------------------------------------------------------
-- SECTION 1 : MODULE BOOTSTRAP
-----------------------------------------------------------------------

local UI = {}

local log = function() end
local Hook
local Format
local ctx

-----------------------------------------------------------------------
-- SECTION 2 : STATE
-----------------------------------------------------------------------

local gui               -- ScreenGui container
local mainWindow        -- main window frame
local listFrame         -- ScrollingFrame holding capture rows
local listLayout        -- UIListLayout for listFrame
local statusLabel       -- bottom status bar text
local filterBox         -- toolbar TextBox
local isShown = false
local uiTier = 0        -- 1=CoreGui, 2=gethui, 3=PlayerGui, 4=console
local connectionPool = {} -- all connections, cleaned on shutdown

local MAX_ROWS = 100    -- max visible rows (perf cap)
local rowPool = {}      -- reused row frames

-----------------------------------------------------------------------
-- SECTION 3 : THEME RESOLUTION
-----------------------------------------------------------------------

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

-----------------------------------------------------------------------
-- SECTION 4 : CONSTRUCTION HELPERS
-----------------------------------------------------------------------

local function new(className, props, children)
    local inst = Instance.new(className)
    for k, v in pairs(props or {}) do
        if k ~= "Parent" then
            inst[k] = v
        end
    end
    for _, child in ipairs(children or {}) do
        child.Parent = inst
    end
    if props and props.Parent then
        inst.Parent = props.Parent
    end
    return inst
end

local function makeCorner(parent, radius)
    return new("UICorner", { CornerRadius = UDim.new(0, radius or 8), Parent = parent })
end

local function makeStroke(parent, color, thickness)
    return new("UIStroke", { Color = color, Thickness = thickness or 1, Parent = parent })
end

-- Cross-version drag support. Uses .Draggable when present, else
-- falls back to manual InputBegan tracking.
local function makeDraggable(handle, target)
    local ok = pcall(function()
        handle.Active = true
        handle.Draggable = true
    end)
    if ok then
        return
    end

    -- Manual fallback.
    local dragging = false
    local dragStart = nil
    local startPos = nil

    local inputBegan = handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = target.Position
        end
    end)

    local inputChanged = handle.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)

    local inputEnded = handle.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    table.insert(connectionPool, inputBegan)
    table.insert(connectionPool, inputChanged)
    table.insert(connectionPool, inputEnded)
end

-----------------------------------------------------------------------
-- SECTION 5 : CONTAINER RESOLUTION
-----------------------------------------------------------------------

local function resolveContainer()
    -- Tier 1: CoreGui.
    local ok = pcall(function()
        local core = game:GetService("CoreGui")
        local test = Instance.new("ScreenGui")
        test.Name = "SimplySpy_Probe"
        test.Parent = core
        test:Destroy()
    end)
    if ok then
        return game:GetService("CoreGui"), 1
    end

    -- Tier 2: gethui().
    if type(gethui) == "function" then
        local ok2, container = pcall(gethui)
        if ok2 and container then
            return container, 2
        end
    end

    -- Tier 3: PlayerGui.
    local player = game:GetService("Players").LocalPlayer
    if player then
        local pg = player:FindFirstChild("PlayerGui")
        if pg then
            return pg, 3
        end
    end

    return nil, 4
end

-----------------------------------------------------------------------
-- SECTION 6 : ROW CONSTRUCTION
-----------------------------------------------------------------------
-- Rows are pooled: a fixed set of row frames is created once and
-- recycled as captures arrive. This keeps the list at O(1) per
-- capture regardless of buffer size.

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
    makeCorner(row, 4)

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

local function getRow()
    local row = table.remove(rowPool)
    if not row then
        if #rowPool >= MAX_ROWS then
            return nil
        end
        row = makeRow()
    end
    return row
end

local function releaseRow(row)
    table.insert(rowPool, row)
end

-----------------------------------------------------------------------
-- SECTION 7 : LIST REFRESH
-----------------------------------------------------------------------

local function refreshList()
    if not isShown then
        return
    end

    -- Gather the most recent captures.
    local captures = Hook.getRecent(MAX_ROWS)

    -- Recycle rows.
    for _, row in ipairs(listFrame:GetChildren()) do
        if row.Name == "Row" then
            row.Visible = false
            row.Active = false
            row.BackgroundColor3 = T.Card
        end
    end

    -- Populate.
    for i, capture in ipairs(captures) do
        local row = getRow()
        if not row then
            break
        end

        row.Visible = true
        row.Active = true
        row.Label.Text = string.format("[%d] %s",
            capture.id, Format.callToLine(capture))
        row.Label.TextColor3 = T.TextSecondary

        row.LayoutOrder = capture.id

        -- Click behavior bound once at row creation.
        if not row._bound then
            row.MouseButton1Click:Connect(function()
                if row._captureId then
                    UI.showDetail(row._captureId)
                end
            end)
            row._bound = true
        end
        row._captureId = capture.id
    end

    -- Update the canvas size to fit content.
    local rowCount = 0
    for _, row in ipairs(listFrame:GetChildren()) do
        if row.Name == "Row" and row.Visible then
            rowCount = rowCount + 1
        end
    end
    listFrame.CanvasSize = UDim2.new(0, 0, 0, rowCount * 28)

    -- Status bar.
    statusLabel.Text = string.format("%d captured | filter: %s",
        Hook.count(), Hook.getFilterName and Hook.getFilterName() or "none")
end

-----------------------------------------------------------------------
-- SECTION 8 : DETAIL VIEW
-----------------------------------------------------------------------

local detailFrame = nil

function UI.showDetail(id)
    local capture = Hook.getById(id)
    if not capture then
        return
    end

    -- Destroy any previous detail window.
    if detailFrame then
        detailFrame:Destroy()
        detailFrame = nil
    end

    detailFrame = new("Frame", {
        Name = "DetailWindow",
        Size = UDim2.fromOffset(480, 420),
        Position = UDim2.new(0.5, 260, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = T.Card,
        BorderSizePixel = 0,
        Parent = gui,
    })
    makeCorner(detailFrame, 10)
    makeStroke(detailFrame, T.CardBorder)

    -- Title bar.
    local title = new("TextLabel", {
        Size = UDim2.new(1, -90, 0, 32),
        Position = UDim2.new(0, 14,  window = nil, 0, 14),
        BackgroundTransparency = 1,
Position = UDim2.new(0, 14, 0, 14),
        TextColor3 = T.TextPrimary,
        TextSize = 16,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = detailFrame,
    })

    -- Close button.
    local close = new("TextButton", {
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
    makeCorner(close, 6)
    close.MouseButton1Click:Connect(function()
        detailFrame:Destroy()
        detailFrame = nil
    end)

    -- Copy button.
    local copy = new("TextButton", {
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
    makeCorner(copy, 6)
    copy.MouseButton1Click:Connect(function()
        Hook.copy(capture.id)
    end)

    -- Args list.
    local argsList = new("ScrollingFrame", {
        Size = UDim2.new(1, -28, 1, -120),
        Position = UDim2.new(0, 14, 0, 88),
        BackgroundColor3 = T.Background,
        BorderSizePixel = 0,
        ScrollBarThickness = 6,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        Parent = detailFrame,
    })
    makeCorner(argsList, 6)

    local argsLayout = new("UIListLayout", {
        Padding = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = argsList,
    })

    local yOffset = 0
    for i, arg in ipairs(capture.args) do
        local argLabel = new("TextLabel", {
            Size = UDim2.new(1, -12, 0, 20),
            BackgroundTransparency = 1,
            Text = string.format("[%d] %s", i, Format.display(arg)),
            TextColor3 = Format.colorFor(arg),
            TextSize = 12,
            Font = Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            LayoutOrder = i,
            Parent = argsList,
        })

        -- Auto-expand rows with long text (text height estimation).
        local textLen = #argLabel.Text
        if textLen > 60 then
            argLabel.TextWrapped = true
            argLabel.Size = UDim2.new(1, -12, 0, 20 + math.floor(textLen / 60) * 16)
        end
        yOffset = yOffset + argLabel.Size.Y.Offset + 2
    end

    argsList.CanvasSize = UDim2.new(0, 0, 0, yOffset + 8)

    -- Remote path display.
    local pathLabel = new("TextLabel", {
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

-----------------------------------------------------------------------
-- SECTION 9 : MAIN WINDOW CONSTRUCTION
-----------------------------------------------------------------------

local function buildMainWindow()
    mainWindow = new("Frame", {
        Name = "SimplySpyMainWindow",
        Size = UDim2.fromOffset(440, 480),
        Position = UDim2.new(0.5, -220, 0.5, -240),
        BackgroundColor3 = T.Card,
        BorderSizePixel = 0,
        Parent = gui,
    })
    makeCorner(mainWindow, 10)
    makeStroke(mainWindow, T.CardBorder)

    -- Title bar.
    local titleBar = new("Frame", {
        Name = "TitleBar",
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = T.Background,
        BorderSizePixel = 0,
        Parent = mainWindow,
    })
    makeCorner(titleBar, 10)

    local title = new("TextLabel", {
        Size = UDim2.new(1, -60, 1, 0),
        Position = UDim2.new(0, 14, 0, 0),
        BackgroundTransparency = 1,
        Text = "SimplySpy",
        TextColor3 = T.TextPrimary,
        Text = "SimplySpy",
        TextSize = 16,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = titleBar,
    })

    local versionLabel = new("TextLabel", {
        Size = UDim2.new(0, 60, 1, 0),
        Position = UDim2.new(1, -60, 0, 0),
        BackgroundTransparency = 1,
        Tier = nil,
        Text = "v" .. tostring(ctx and ctx.version or "?"),
        TextColor3 = T.TextFaint,
        TextSize = 11,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = titleBar,
    })

    makeDraggable(titleBar, mainWindow)

    -- Toolbar.
    local toolbar = new("Frame", {
        Name = "Toolbar",
        Size = UDim2.new(1, 0, 0, 36),
        Position = UVertex2 = nil,
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
    makeCorner(filterBox, 4)

    filterBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            local text = filterBox.Text
            if text == "" then
                Hook.setFilter(nil)
            else
                Hook.setFilter(text)
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
        TextAsScale = nil,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        Parent = toolbar,
    })
    makeCorner(btnClear, 4)
    btnClear.MouseButton1Click:Connect(function()
        Hook.clear()
        refreshList()
    end)

    -- Capture list.
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
    makeCorner(listFrame, 6)

    listLayout = new("UIListLayout", {
        Padding = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = listFrame,
    })

    -- Status bar.
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

-----------------------------------------------------------------------
-- SECTION 10 : REAL-TIME UPDATES
-----------------------------------------------------------------------
-- The hook module calls UI.onCapture when a new capture arrives.
-- Refreshes are throttled to one per 0.1 seconds to avoid frame
-- drops during remote-heavy games.

local refreshQueued = false
local lastRefresh = 0

local function onCapture(capture)
    if not isShown then
        return
    end
    if os.clock() - lastRefresh < 0.1 then
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
    lastRefresh = os.clock()
    refreshList()
end

-----------------------------------------------------------------------
-- SECTION 11 : PUBLIC API
-----------------------------------------------------------------------

function UI.init(deps)
    log = deps.log or log
    Hook = deps.hook
    Format = deps.format
    ctx = deps.ctx

    if not Hook or not Format then
        return false, "missing dependencies (hook, format)"
    end

    resolveTheme()

    local container, tier = resolveContainer()
    uiTier = tier

    if tier == 4 then
        log("WARN", "no GUI container available; console mode only")
        return true -- UI init succeeds; show() is a no-op
    end

    gui = Instance.new("ScreenGui")
    gui.Name = "SimplySpy_" .. tostring(math.floor(os.clock() * 1000))
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 998
    gui.IgnoreGuiInset = true
    gui.Parent = container

    buildMainWindow()
    isShown = false -- show() must be called explicitly

    -- Wire the hook callback.
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
    log("INFO", "ui offline")
end

-----------------------------------------------------------------------
-- SECTION 12 : MODULE CONTRACT
-----------------------------------------------------------------------

return function(deps)
    local ok, result = pcall(UI.init, deps)
    if not ok then
        error("SimplySpy ui init failed: " .. tostring(result))
    end
    if result == false then
        error("SimplySpy ui init returned false (see logs)")
    end
    return UI
end
