--=====================================================================
--=====================================================================
--                                                                    --
--   ____  _                   _____         _                        --
--  / ___|(_)_ __ ___  _   _|  ___|_  ___ | |_                      --
--  \___ \| | '_ ` _ \| | | | |_  \ \/ / '| __|                     --
--   ___) | | | | | | | |_| |  _| | >  <| | |_                      --
--  |____/|_|_| |_| |_|\__, |_|  \_/_/\_\  \__|                     --
--                      |___/                                        --
--                                                                    --
--  INTERFACE MODULE                                                 --
--  =================                                                --
--                                                                    --
--  LAYOUT (PeopleSpy-inspired):                                     --
--                                                                    --
--    +----------------------------------+                            --
--    |  SimplySpy          [_] [X]     |   <- title bar             --
--    +----------------------------------+                            --
--    |                                  |                            --
--    |   LOG DISPLAY AREA               |   <- captures listed      --
--    |   (dark, scrollable)              |      here, click to       --
--    |                                  |      select               --
--    |   [1] RF:InvokeServer (arg...)   |                            --
--    |   [2] Event:FireServer (...)     |                            --
--    |                                  |                            --
--    +----------------------------------+                            --
--    |  Copy Code  | Copy Remote       |   <- button grid           --
--    |  Run Code    | Get Script        |                            --
--    |  Function Info | Clr Logs       |                            --
--    |  Exclude (i) | Exclude (n)       |                            --
--    |  Clr Blacklist | Block (i)      |                            --
--    |  Block (n)   | Clr Blocklist     |                            --
--    +----------------------------------+                            --
--    |  status bar                      |   <- bottom               --
--    +----------------------------------+                            --
--                                                                    --
--  CONTAINER LADDER:                                                 --
--    Tier 1 : CoreGui (survives respawns, hidden from game)         --
--    Tier 2 : gethui() (executor-protected container)                --
--    Tier 3 : PlayerGui (always works, game can clean it)            --
--    Tier 4 : console only (no GUI; SPY.* commands only)             --
--                                                                    --
--  BUTTON ACTIONS:                                                   --
--    Copy Code    : copies the selected capture as executable Lua    --
--    Copy Remote  : copies the remote instance path only             --
--    Run Code     : generates and immediately executes the code      --
--    Get Script   : prints the full generated script to console     --
--    Function Info: prints detailed info about the remote            --
--    Clr Logs     : clears the capture buffer                        --
--    Exclude (i)  : excludes THIS instance from capture             --
--    Exclude (n)  : excludes all remotes with this NAME              --
--    Clr Blacklist: clears all exclusions                           --
--    Block (i)    : blocks THIS instance from reaching the server   --
--    Block (n)    : blocks all remotes with this NAME                --
--    Clr Blocklist: clears all blocks                                --
--                                                                    --
--  REAL-TIME UPDATES:                                                --
--    New captures appear in the log area immediately (throttled      --
--    to 10 refreshes per second to handle remote-heavy games).       --
--                                                                    --
--  MODULE CONTRACT:                                                 --
--    Receives (deps) with ctx, state, log, hook, format. Returns     --
--    this module's public table.                                     --
--                                                                    --
--  TARGET    : universal (executors + Studio via adapter)             --
--  LICENSE   : MIT                                                   --
--                                                                    --
--=====================================================================
--=====================================================================

-----------------------------------------------------------------------
-- SECTION 1 : MODULE BOOTSTRAP
-----------------------------------------------------------------------

local UI = {}
UI.VERSION = "1.0.0"

local log = function() end
local Hook = nil
local Format = nil
local ctx = nil

-----------------------------------------------------------------------
-- SECTION 2 : STATE
-----------------------------------------------------------------------

local gui = nil
local mainWindow = nil
local listFrame = nil
local statusLabel = nil
local isShown = false
local uiTier = 0
local connectionPool = {}
local selectedCaptureId = nil
local detailFrame = nil

local MAX_ROWS = 200
local lastRefreshTime = 0
local refreshQueued = false

-----------------------------------------------------------------------
-- SECTION 3 : THEME
-----------------------------------------------------------------------

local T = nil

local DEFAULT_THEME = {
    Background    = Color3.fromRGB(16, 16, 22),
    Card          = Color3.fromRGB(28, 28, 36),
    CardBorder    = Color3.fromRGB(46, 46, 58),
    Accent        = Color3.fromRGB(88, 140, 255),
    AccentSoft    = Color3.fromRGB(124, 168, 255),
    Success       = Color3.fromRGB(88, 200, 132),
    Warning       = Color3.fromRGB(230, 200, 60),
    Error         = Color3.fromRGB(232, 92, 92),
    TextPrimary   = Color3.fromRGB(238, 238, 242),
    TextSecondary = Color3.fromRGB(156, 156, 170),
    TextFaint     = Color3.fromRGB(104, 104, 118),
    BarTrack      = Color3.fromRGB(38, 38, 48),
    RowSelected   = Color3.fromRGB(50, 60, 90),
    RowNormal     = Color3.fromRGB(35, 35, 45),
    RowHover      = Color3.fromRGB(42, 42, 55),
}

local function resolveTheme()
    T = (ctx and ctx.theme) or DEFAULT_THEME
    -- Fill any missing keys from defaults.
    for key, value in pairs(DEFAULT_THEME) do
        if T[key] == nil then
            T[key] = value
        end
    end
end

-----------------------------------------------------------------------
-- SECTION 4 : CONSTRUCTION HELPERS
-----------------------------------------------------------------------

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
    if parent then
        inst.Parent = parent
    end
    return inst
end

local function corner(parent, r)
    new("UICorner", {
        CornerRadius = UDim.new(0, r or 8),
        Parent = parent,
    })
end

local function stroke(parent, color, thickness)
    new("UIStroke", {
        Color = color,
        Thickness = thickness or 1,
        Parent = parent,
    })
end

local function makeDraggable(handle, target)
    local ok = pcall(function()
        handle.Active = true
        handle.Draggable = true
    end)
    if ok then
        return
    end

    local dragging = false
    local dragStart = nil
    local startPos = nil

    local b = handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = target.Position
        end
    end)

    local c = handle.InputChanged:Connect(function(input)
        if dragging
            and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
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

-----------------------------------------------------------------------
-- SECTION 5 : CONTAINER RESOLUTION
-----------------------------------------------------------------------

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

-----------------------------------------------------------------------
-- SECTION 6 : ROW CONSTRUCTION
-----------------------------------------------------------------------

local function makeCaptureRow(capture)
    local row = new("TextButton", {
        Name = "Row_" .. tostring(capture.id),
        Size = UDim2.new(1, -8, 0, 24),
        BackgroundColor3 = T.RowNormal,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Parent = listFrame,
    })
    corner(row, 4)

    local label = new("TextLabel", {
        Name = "Label",
        Size = UDim2.new(1, -12, 1, 0),
        Position = UDim2.new(0, 6, 0, 0),
        BackgroundTransparency = 1,
        Text = string.format("[%d] %s:%s (%s)",
            capture.id,
            capture.remoteName or "?",
            capture.method or "?",
            capture.preview or (capture.argCount .. " args")),
        TextColor3 = T.TextSecondary,
        TextSize = 12,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = row,
    })

    row.Label = label

    row.MouseEnter:Connect(function()
        if selectedCaptureId ~= capture.id then
            row.BackgroundColor3 = T.RowHover
        end
    end)

    row.MouseLeave:Connect(function()
        if selectedCaptureId ~= capture.id then
            row.BackgroundColor3 = T.RowNormal
        end
    end)

    row.MouseButton1Click:Connect(function()
        selectedCaptureId = capture.id
        UI.refresh()
    end)

    return row
end

-----------------------------------------------------------------------
-- SECTION 7 : LIST REFRESH
-----------------------------------------------------------------------

local function refreshList()
    if not isShown or not listFrame then
        return
    end

    -- Clear old rows.
    for _, child in ipairs(listFrame:GetChildren()) do
        if child.Name:match("^Row_") then
            child:Destroy()
        end
    end

    -- Populate with the most recent captures, newest at top.
    local captures = Hook.getRecent(MAX_ROWS)

    for i = #captures, 1, -1 do
        local capture = captures[i]
        local row = makeCaptureRow(capture)
        if capture.id == selectedCaptureId then
            row.BackgroundColor3 = T.RowSelected
        end
    end

    local count = Hook.count()
    statusLabel.Text = string.format(
        " %d captured | tier %d | %s",
        count,
        uiTier,
        selectedCaptureId
            and ("selected: #" .. tostring(selectedCaptureId))
            or "click a row to select"
    )
end

-----------------------------------------------------------------------
-- SECTION 8 : SELECTED CAPTURE HELPERS
-----------------------------------------------------------------------

local function getSelectedCapture()
    if not selectedCaptureId then
        return nil
    end
    return Hook.getById(selectedCaptureId)
end

local function reconstructArgs(capture)
    local out = {}
    for i, arg in ipairs(capture.args) do
        out[i] = Hook.reconstruct(arg)
    end
    return out
end

local function buildLiveCapture(capture)
    return {
        id = capture.id,
        remoteName = capture.remoteName,
        remotePath = capture.remotePath,
        method = capture.method,
        argCount = capture.argCount,
        preview = capture.preview,
        args = reconstructArgs(capture),
    }
end

-----------------------------------------------------------------------
-- SECTION 9 : DETAIL WINDOW
-----------------------------------------------------------------------

function UI.showDetail(id)
    local capture = Hook.getById(id)
    if not capture then
        return
    end

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
        Name = "Title",
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
        Name = "Close",
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

    -- Args list.
    local argsList = new("ScrollingFrame", {
        Name = "ArgsList",
        Size = UDim2.new(1, -28, 1, -120),
        Position = UDim2.new(0, 14, 0, 54),
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

    local liveCapture = buildLiveCapture(capture)
    local yOffset = 0

    for i, arg in ipairs(liveCapture.args) do
        local text = string.format("[%d] %s", i,
            Format.display(arg))
        local height = 20
        if #text > 60 then
            height = 20 + math.floor(#text / 60) * 16
        end

        new("TextLabel", {
            Size = UDim2.new(1, -12, 0, height),
            BackgroundTransparency = 1,
            Text = text,
            TextColor3 = Format.colorFor(arg),
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
        Name = "PathLabel",
        Size = UDim2.new(1, -28, 0, 30),
        Position = UDim2.new(0, 14, 1, -40),
        BackgroundTransparency = 1,
        Text = capture.remotePath or "",
        TextColor3 = T.TextFaint,
        TextSize = 11,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = detailFrame,
    })
end

-----------------------------------------------------------------------
-- SECTION 10 : BUTTON GRID CONSTRUCTION
-----------------------------------------------------------------------
-- Builds the PeopleSpy-style button grid. Each button gets its
-- own handler with full error isolation.

local function makeButton(text, row, col, parent, color, handler)
    local COLS = 2
    local W = 195
    local H = 26
    local GAP_X = 6
    local GAP_Y = 4
    local START_Y = 0

    local x = (col - 1) * (W + GAP_X)
    local y = START_Y + (row - 1) * (H + GAP_Y)

    local btn = new("TextButton", {
        Name = "Btn_" .. text:gsub("%s+", "_"),
        Size = UDim2.fromOffset(W, H),
        Position = UDim2.fromOffset(x, y),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = T.TextPrimary,
        TextSize = 11,
        Font = Enum.Font.GothamMedium,
        AutoButtonColor = true,
        Parent = parent,
    })
    corner(btn, 4)

    btn.MouseButton1Click:Connect(function()
        local ok, err = pcall(handler)
        if not ok then
            log("WARN", "button '" .. text .. "' error: "
                .. tostring(err))
        end
    end)

    return btn
end

local function buildButtonGrid(parent)
    local grid = new("Frame", {
        Name = "ButtonGrid",
        Size = UDim2.new(1, -20, 0, 200),
        Position = UDim2.new(0, 10, 1, -230),
        BackgroundTransparency = 1,
        Parent = parent,
    })

    -- Row 1: the two primary copy actions.
    makeButton("Copy Code", 1, 1, grid, T.Accent, function()
        local capture = getSelectedCapture()
        if not capture then
            statusLabel.Text = " no capture selected"
            return
        end
        Hook.copy(capture.id)
    end)

    makeButton("Copy Remote", 1, 2, grid, T.Accent, function()
        local capture = getSelectedCapture()
        if not capture then
            statusLabel.Text = " no capture selected"
            return
        end
        local path = capture.remotePath or ""
        if type(setclipboard) == "function" then
            setclipboard(path)
            statusLabel.Text = " remote path copied"
        else
            print(path)
            statusLabel.Text = " printed to console"
        end
    end)

    -- Row 2: execution and script generation.
    makeButton("Run Code", 2, 1, grid, T.Warning, function()
        local capture = getSelectedCapture()
        if not capture then
            statusLabel.Text = " no capture selected"
            return
        end
        local live = buildLiveCapture(capture)
        local scriptText = Format.callToScript(live)
        local chunk, err = loadstring(scriptText,
            "=SimplySpy/Replay")
        if not chunk then
            statusLabel.Text = " replay compile failed"
            log("ERROR", "replay compile: " .. tostring(err))
            return
        end
        local ok, runErr = pcall(chunk)
        if ok then
            statusLabel.Text = " replay executed"
        else
            statusLabel.Text = " replay failed"
            log("ERROR", "replay run: " .. tostring(runErr))
        end
    end)

    makeButton("Get Script", 2, 2, grid, T.Accent, function()
        local capture = getSelectedCapture()
        if not capture then
            statusLabel.Text = " no capture selected"
            return
        end
        local live = buildLiveCapture(capture)
        local scriptText = Format.callToScript(live)
        print("\n=== SimplySpy Script ===")
        print(scriptText)
        print("=======================\n")
        statusLabel.Text = " script printed to console"
    end)

    -- Row 3: info and log clearing.
    makeButton("Function Info", 3, 1, grid, T.Accent, function()
        local capture = getSelectedCapture()
        if not capture then
            statusLabel.Text = " no capture selected"
            return
        end
        Hook.dump(capture.id)
    end)

    makeButton("Clr Logs", 3, 2, grid, T.Error, function()
        Hook.clear()
        selectedCaptureId = nil
        UI.refresh()
        statusLabel.Text = " logs cleared"
    end)

    -- Row 4: exclude by instance and by name.
    makeButton("Exclude (i)", 4, 1, grid, T.BarTrack, function()
        local capture = getSelectedCapture()
        if not capture then
            statusLabel.Text = " no capture selected"
            return
        end
        Hook.setBlocked(capture.remoteName, true)
        statusLabel.Text = " excluded: " .. capture.remoteName
    end)

    makeButton("Exclude (n)", 4, 2, grid, T.BarTrack, function()
        local capture = getSelectedCapture()
        if not capture then
            statusLabel.Text = " no capture selected"
            return
        end
        -- Exclude by name: all remotes sharing this name.
        Hook.setExcluded(capture.remoteName, true)
        statusLabel.Text = " excluded by name: "
            .. capture.remoteName
    end)

    -- Row 5: clear blacklist, block by instance.
    makeButton("Clr Blacklist", 5, 1, grid, T.Error, function()
        Hook.clearFilters()
        statusLabel.Text = " blacklist cleared"
    end)

    makeButton("Block (i)", 5, 2, grid, T.Error, function()
        local capture = getSelectedCapture()
        if not capture then
            statusLabel.Text = " no capture selected"
            return
        end
        Hook.setBlocked(capture.remoteName, true)
        statusLabel.Text = " blocked: " .. capture.remoteName
    end)

    -- Row 6: block by name, clear blocklist.
    makeButton("Block (n)", 6, 1, grid, T.Error, function()
        local capture = getSelectedCapture()
        if not capture then
            statusLabel.Text = " no capture selected"
            return
        end
        Hook.setBlocked(capture.remoteName, true)
        statusLabel.Text = " blocked by name: "
            .. capture.remoteName
    end)

    makeButton("Clr Blocklist", 6, 2, grid, T.Error, function()
        Hook.clearFilters()
        statusLabel.Text = " blocklist cleared"
    end)

    return grid
end

-----------------------------------------------------------------------
-- SECTION 11 : MAIN WINDOW CONSTRUCTION
-----------------------------------------------------------------------

local function buildMainWindow()
    mainWindow = new("Frame", {
        Name = "SimplySpyMainWindow",
        Size = UDim2.fromOffset(440, 560),
        Position = UDim2.new(0.5, -220, 0.5, -280),
        BackgroundColor3 = T.Card,
        BorderSizePixel = 0,
        Visible = false,
        Parent = gui,
    })
    corner(mainWindow, 10)
    stroke(mainWindow, T.CardBorder)

    -- Title bar.
    local titleBar = new("Frame", {
        Name = "TitleBar",
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = T.Background,
        BorderSizePixel = 0,
        Parent = mainWindow,
    })

    new("TextLabel", {
        Name = "Title",
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
        Name = "Version",
        Size = UDim2.new(0, 50, 1, 0),
        Position = UDim2.new(1, -50, 0, 0),
        BackgroundTransparency = 1,
        Text = "v" .. UI.VERSION,
        TextColor3 = T.TextFaint,
        TextSize = 10,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = titleBar,
    })

    makeDraggable(titleBar, mainWindow)

    -- Log display area (the big dark area).
    listFrame = new("ScrollingFrame", {
        Name = "LogDisplay",
        Size = UDim2.new(1, -20, 1, -290),
        Position = UDim2.new(0, 10, 0, 44),
        BackgroundColor3 = T.Background,
        BorderSizePixel = 0,
        ScrollBarThickness = 6,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        Parent = mainWindow,
    })
    corner(listFrame, 6)

    new("UIListLayout", {
        Name = "ListLayout",
        Padding = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = listFrame,
    })

    -- Button grid.
    buildButtonGrid(mainWindow)

    -- Status bar.
    statusLabel = new("TextLabel", {
        Name = "Status",
        Size = UDim2.new(1, -20, 0, 20),
        Position = UDim2.new(0, 10, 1, -24),
        BackgroundColor3 = T.Background,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        Text = " initializing...",
        TextColor3 = T.TextFaint,
        TextSize = 11,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = mainWindow,
    })
    corner(statusLabel, 4)
end

-----------------------------------------------------------------------
-- SECTION 12 : REAL-TIME UPDATES (THROTTLED)
-----------------------------------------------------------------------

local function onCapture()
    if not isShown then
        return
    end

    local now = os.clock()
    if now - lastRefreshTime < 0.1 then
        if not refreshQueued then
            refreshQueued = true
            if task and task.delay then
                task.delay(0.1, function()
                    refreshQueued = false
                    lastRefreshTime = os.clock()
                    refreshList()
                end)
            end
        end
        return
    end

    lastRefreshTime = now
    refreshList()
end

-----------------------------------------------------------------------
-- SECTION 13 : PUBLIC API
-----------------------------------------------------------------------

function UI.init(deps)
    log = (deps and deps.log) or log
    Hook = deps and deps.hook
    Format = deps and deps.format
    ctx = deps and deps.ctx

    if not Hook then
        return false, "missing hook module"
    end
    if not Format then
        return false, "missing format module"
    end

    resolveTheme()

    local container, tier = resolveContainer()
    uiTier = tier

    if tier == 4 then
        log("WARN", "no GUI container; console mode only")
        return true
    end

    gui = Instance.new("ScreenGui")
    gui.Name = "SimplySpy_"
        .. tostring(math.floor(os.clock() * 1000))
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 998
    gui.IgnoreGuiInset = true
    gui.Parent = container

    buildMainWindow()

    -- Wire the capture callback.
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
        pcall(function()
            conn:Disconnect()
        end)
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

function UI.getTier()
    return uiTier
end

function UI.getSelectedId()
    return selectedCaptureId
end

-----------------------------------------------------------------------
-- SECTION 14 : MODULE CONTRACT
-----------------------------------------------------------------------

return function(deps)
    local ok, result = pcall(UI.init, deps)
    if not ok then
        error("ui init crashed: " .. tostring(result))
    end
    if result == false then
        error("ui init failed: " .. tostring(result))
    end
    return UI
end
