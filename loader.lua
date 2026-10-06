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
--  BOOTSTRAP LOADER                                                 --
--  ================                                                 --
--                                                                    --
--  The single public entry point of SimplySpy. Users execute one    --
--  line:                                                             --
--                                                                    --
--    loadstring(game:HttpGet(                                        --
--      "https://raw.githubusercontent.com/randomguy454/"             --
--      .. "simplyspirited/main/loader.lua"))()                       --
--                                                                    --
--  BOOT SEQUENCE:                                                   --
--    1. Render the loading interface (CoreGui with fallback)        --
--    2. Animate the intro                                           --
--    3. Fetch the runtime payload with retry and backoff            --
--    4. Validate the payload without executing it                   --
--    5. Execute the runtime with a context table                    --
--    6. Hand off via the reveal transition                           --
--                                                                    --
--  RUNTIME CONTRACT (context passed to main.lua):                   --
--    ctx.version      string                                        --
--    ctx.theme        color palette table                           --
--    ctx.capabilities probed executor features                      --
--    ctx.gui          ScreenGui container for runtime UI            --
--    ctx.reveal()     runtime calls this when its window is built   --
--    ctx.destroy()    emergency loader teardown                     --
--    ctx.log(level, message)  shared logger                         --
--                                                                    --
--  FAILURE MODES (all surface in the error card):                   --
--    - Network failure after retries                                 --
--    - Repository 404 (bad ref or path)                              --
--    - Payload syntax error (compile check before run)               --
--    - Runtime error during execution                                 --
--    Every failure offers Retry (re-runs boot without re-executing   --
--    the one-liner) and Copy error (if clipboard is available).     --
--                                                                    --
--  FAILSAFE:                                                        --
--    If the runtime succeeds but never calls ctx.reveal() within    --
--    AUTO_REVEAL seconds, the loader forces the transition anyway   --
--    so the user is never stuck on a loading screen.                 --
--                                                                    --
--  DESIGN RULES:                                                    --
--    - Pure ASCII throughout                                         --
--    - Flat syntax: no metatables, no nested closure tricks         --
--    - Every stage logs its status                                  --
--    - The indeterminate progress animation runs on the render     --
--      thread and survives blocking HTTP calls                      --
--                                                                    --
--  TARGET    : UNC-compatible Roblox script executors                --
--  LICENSE   : MIT                                                   --
--                                                                    --
--=====================================================================
--=====================================================================

-----------------------------------------------------------------------
-- SECTION 1 : SERVICES AND ENVIRONMENT
-----------------------------------------------------------------------

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    print("[SimplySpy] fatal: LocalPlayer unavailable")
    return
end

-- Cross-executor safe yield. Uses the task library when present
-- and falls back to the legacy global.
local function yield(t)
    if task and task.wait then
        task.wait(t)
    else
        wait(t)
    end
end

-- Safe spawn for fire-and-forget work.
local function async(fn)
    if task and task.spawn then
        task.spawn(fn)
    else
        spawn(fn)
    end
end

-- Safe delayed call.
local function later(t, fn)
    if task and task.delay then
        return task.delay(t, fn)
    else
        return delay(t, fn)
    end
end

-----------------------------------------------------------------------
-- SECTION 2 : CONFIGURATION
-----------------------------------------------------------------------

local CONFIG = {
    REPO       = "randomguy454/simplyspirited",
    BRANCH     = "main",
    ENTRY      = "main.lua",
    VERSION    = "0.4.0",

    MAX_RETRIES = 3,
    RETRY_BASE  = 0.5,   -- seconds; doubles each retry

    CONTEXT_KEY = "SimplySpy_Context",
    AUTO_REVEAL = 10,    -- seconds before forced transition

    DEBUG = false,
}

-- User overrides from the shared environment.
local genv = (type(getgenv) == "function") and getgenv() or _G
if type(genv.SIMPLYSPY_CONFIG) == "table" then
    for key, value in pairs(genv.SIMPLYSPY_CONFIG) do
        CONFIG[key] = value
    end
end

-----------------------------------------------------------------------
-- SECTION 3 : LOGGING
-----------------------------------------------------------------------

local TAG = "[SimplySpy]"

local function log(level, message)
    print(string.format("%s [%s] %s", TAG, level, tostring(message)))
end

local function debugLog(message)
    if CONFIG.DEBUG then
        log("DEBUG", message)
    end
end

-----------------------------------------------------------------------
-- SECTION 4 : CAPABILITY DETECTION
-----------------------------------------------------------------------
-- Probed once. Results are passed to the runtime through the
-- context so modules can branch without re-probing.

local CAPABILITIES = {}

local function detectCapabilities()
    CAPABILITIES.gethui = (type(gethui) == "function")
    CAPABILITIES.clipboard = (type(setclipboard) == "function")
    CAPABILITIES.filesystem = (type(writefile) == "function")
        and (type(readfile) == "function")
    CAPABILITIES.newcclosure = (type(newcclosure) == "function")
    CAPABILITIES.getrawmetatable = (type(getrawmetatable) == "function")
    CAPABILITIES.getgenv = (type(getgenv) == "function")

    if CONFIG.DEBUG then
        for name, supported in pairs(CAPABILITIES) do
            debugLog(string.format("capability %-16s %s",
                name, supported and "yes" or "no"))
        end
    end
end

-----------------------------------------------------------------------
-- SECTION 5 : HTTP AND VALIDATION
-----------------------------------------------------------------------

local function buildUrl()
    return string.format(
        "https://raw.githubusercontent.com/%s/%s/%s",
        CONFIG.REPO, CONFIG.BRANCH, CONFIG.ENTRY)
end

-- Returns (source, nil) on success or (nil, error) on failure.
local function fetchSource(url)
    local waitTime = CONFIG.RETRY_BASE

    for attempt = 1, CONFIG.MAX_RETRIES do
        local ok, body = pcall(function()
            return game:HttpGet(url, true)
        end)

        if ok and type(body) == "string" and #body > 0 then
            if body:sub(1, 4) == "404:" then
                return nil,
                    "repository returned 404 (check REPO/BRANCH/ENTRY)"
            end
            return body
        end

        log("WARN", string.format("fetch attempt %d/%d failed: %s",
            attempt, CONFIG.MAX_RETRIES, tostring(body)))

        if attempt < CONFIG.MAX_RETRIES then
            yield(waitTime)
            waitTime = waitTime * 2
        end
    end

    return nil,
        "network failed after " .. CONFIG.MAX_RETRIES .. " attempts"
end

-- Compiles without executing. Returns (chunk, nil) or (nil, error).
local function validateSource(source)
    if type(source) ~= "string" or #source == 0 then
        return nil, "payload is empty"
    end

    local chunk, err = (loadstring or load)(source,
        "=SimplySpy/Runtime")
    if not chunk then
        return nil, "syntax error in payload: " .. tostring(err)
    end

    return chunk
end

-----------------------------------------------------------------------
-- SECTION 6 : THEME
-----------------------------------------------------------------------

local THEME = {
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

-----------------------------------------------------------------------
-- SECTION 7 : TWEEN HELPER
-----------------------------------------------------------------------

local function tween(instance, duration, properties, style, direction)
    local info = TweenInfo.new(
        duration,
        style or Enum.EasingStyle.Quart,
        direction or Enum.EasingDirection.Out
    )
    local t = TweenService:Create(instance, info, properties)
    t:Play()
    return t
end

-----------------------------------------------------------------------
-- SECTION 8 : LOADER INTERFACE
-----------------------------------------------------------------------
-- Layout:
--   ScreenGui
--     Dim        full screen veil
--     Card       centered, draggable
--       Logo     accent rounded square, "SS"
--       Title    "SimplySpy"
--       Subtitle "remote inspection suite"
--       Status   stage text
--       Percent  right-aligned percentage
--       Track    progress bar container
--         Fill   gradient fill
--       Footer   version and repository
--
-- Error elements (hidden until a failure):
--   ErrorMessage   wrapped text
--   RetryButton    re-runs boot
--   CopyButton     copies error text

local gui
local card
local dim
local statusLabel
local percentLabel
local fill
local errorMessage
local retryButton
local copyButton

local fadeables = {}

local function registerFadeable(label)
    table.insert(fadeables, label)
end

local function setFade(transparency)
    for _, label in ipairs(fadeables) do
        label.TextTransparency = transparency
    end
end

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

local function buildInterface()
    gui = new("ScreenGui", {
        Name = "SimplySpy_Loader",
        ResetOnSpawn = false,
        DisplayOrder = 999,
        IgnoreGuiInset = true,
    })

    -- CoreGui first, PlayerGui fallback.
    local ok = pcall(function()
        gui.Parent = game:GetService("CoreGui")
    end)
    if not ok then
        gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
        log("INFO", "CoreGui unavailable, using PlayerGui")
    else
        debugLog("parented to CoreGui")
    end

    dim = new("Frame", {
        Name = "Dim",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = THEME.Background,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 1,
        Parent = gui,
    })

    card = new("Frame", {
        Name = "Card",
        Size = UDim2.fromOffset(380, 240),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = THEME.Card,
        BorderSizePixel = 0,
        Active = true,
        Draggable = true,
        ZIndex = 2,
        Parent = gui,
    })

    new("UICorner", {
        CornerRadius = UDim.new(0, 10),
        Parent = card,
    })

    new("UIStroke", {
        Color = THEME.CardBorder,
        Thickness = 1,
        Parent = card,
    })

    local scale = new("UIScale", {
        Name = "Scale",
        Scale = 0.92,
        Parent = card,
    })

    -- Logo mark.
    local logo = new("Frame", {
        Name = "Logo",
        Size = UDim2.fromOffset(44, 44),
        Position = UDim2.new(0, 24, 0, 24),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        ZIndex = 3,
        Parent = card,
    })

    new("UICorner", {
        CornerRadius = UDim.new(0, 10),
        Parent = logo,
    })

    local logoText = new("TextLabel", {
        Name = "LogoText",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "SS",
        TextColor3 = THEME.Background,
        TextSize = 18,
        Font = Enum.Font.GothamBold,
        ZIndex = 4,
        Parent = logo,
    })
    registerFadeable(logoText)

    -- Title.
    local title = new("TextLabel", {
        Name = "Title",
        Size = UDim2.new(1, -160, 0, 26),
        Position = UDim2.new(0, 82, 0, 24),
        BackgroundTransparency = 1,
        Text = "SimplySpy",
        TextColor3 = THEME.TextPrimary,
        TextSize = 20,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 3,
        Parent = card,
    })
    registerFadeable(title)

    -- Subtitle.
    local subtitle = new("TextLabel", {
        Name = "Subtitle",
        Size = UDim2.new(1, -160, 0, 16),
        Position = UDim2.new(0, 82, 0, 50),
        BackgroundTransparency = 1,
        Text = "remote inspection suite",
        TextColor3 = THEME.TextSecondary,
        TextSize = 12,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 3,
        Parent = card,
    })
    registerFadeable(subtitle)

    -- Status text.
    statusLabel = new("TextLabel", {
        Name = "Status",
        Size = UDim2.new(1, -110, 0, 14),
        Position = UDim2.new(0, 24, 1, -78),
        BackgroundTransparency = 1,
        Text = "initializing",
        TextColor3 = THEME.TextSecondary,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 3,
        Parent = card,
    })
    registerFadeable(statusLabel)

    -- Percentage text.
    percentLabel = new("TextLabel", {
        Name = "Percent",
        Size = UDim2.new(0, 80, 0, 14),
        Position = UDim2.new(1, -104, 1, -78),
        BackgroundTransparency = 1,
        Text = "0%",
        TextColor3 = THEME.TextFaint,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 3,
        Parent = card,
    })
    registerFadeable(percentLabel)

    -- Progress track.
    local track = new("Frame", {
        Name = "Track",
        Size = UDim2.new(1, -48, 0, 6),
        Position = UDim2.new(0, 24, 1, -56),
        BackgroundColor3 = THEME.BarTrack,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 3,
        Parent = card,
    })

    new("UICorner", {
        CornerRadius = UDim.new(1, 0),
        Parent = track,
    })

    fill = new("Frame", {
        Name = "Fill",
        Size = UDim2.fromScale(0, 1),
        Position = UDim2.fromScale(0, 0),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        ZIndex = 4,
        Parent = track,
    })

    new("UICorner", {
        CornerRadius = UDim.new(1, 0),
        Parent = fill,
    })

    new("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, THEME.Accent),
            ColorSequenceKeypoint.new(1, THEME.AccentSoft),
        }),
        Parent = fill,
    })

    -- Footer.
    local footer = new("TextLabel", {
        Name = "Footer",
        Size = UDim2.new(1, -48, 0, 12),
        Position = UDim2.new(0, 24, 1, -30),
        BackgroundTransparency = 1,
        Text = "v" .. CONFIG.VERSION .. "  -  " .. CONFIG.REPO,
        TextColor3 = THEME.TextFaint,
        TextSize = 10,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 3,
        Parent = card,
    })
    registerFadeable(footer)

    -- Error message (hidden until failure).
    errorMessage = new("TextLabel", {
        Name = "ErrorMessage",
        Size = UDim2.new(1, -48, 0, 30),
        Position = UDim2.new(0, 24, 0, 86),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = THEME.Error,
        TextSize = 11,
        Font = Enum.Font.Gotham,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextTransparency = 1,
        ZIndex = 3,
        Parent = card,
    })

    -- Retry button (hidden until failure).
    retryButton = new("TextButton", {
        Name = "RetryButton",
        Size = UDim2.fromOffset(90, 26),
        Position = UDim2.new(1, -120, 1, -40),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        Text = "Retry",
        TextColor3 = THEME.TextPrimary,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        Visible = false,
        ZIndex = 3,
        Parent = card,
    })

    new("UICorner", {
        CornerRadius = UDim.new(0, 6),
        Parent = retryButton,
    })

    -- Copy error button (hidden until failure).
    copyButton = new("TextButton", {
        Name = "CopyButton",
        Size = UDim2.fromOffset(90, 26),
        Position = UDim2.new(1, -222, 1, -40),
        BackgroundColor3 = THEME.BarTrack,
        BorderSizePixel = 0,
        Text = "Copy error",
        TextColor3 = THEME.TextSecondary,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        Visible = false,
        ZIndex = 3,
        Parent = card,
    })

    new("UICorner", {
        CornerRadius = UDim.new(0, 6),
        Parent = copyButton,
    })

    return scale
end

-----------------------------------------------------------------------
-- SECTION 9 : INTERFACE STATE CONTROL
-----------------------------------------------------------------------

local function setStatus(text, color)
    statusLabel.Text = text
    statusLabel.TextColor3 = color or THEME.TextSecondary
end

local function setProgress(alpha)
    alpha = math.clamp(alpha, 0, 1)
    fill.Size = UDim2.fromScale(alpha, 1)
    percentLabel.Text = string.format("%d%%",
        math.floor(alpha * 100 + 0.5))
end

-- Indeterminate mode: the fill slides across the track in a loop
-- while a blocking operation runs. The tween lives on the render
-- thread, so the animation continues during HttpGet.
local indeterminateTween = nil

local function startIndeterminate()
    fill.Size = UDim2.fromScale(0.35, 1)
    fill.Position = UDim2.fromScale(-0.35, 0)
    local info = TweenInfo.new(
        0.9,
        Enum.EasingStyle.Linear,
        Enum.EasingDirection.Out,
        -1,
        false,
        0
    )
    indeterminateTween = TweenService:Create(fill, info, {
        Position = UDim2.fromScale(1, 0),
    })
    indeterminateTween:Play()
end

local function stopIndeterminate()
    if indeterminateTween then
        indeterminateTween:Cancel()
        indeterminateTween = nil
    end
    fill.Position = UDim2.fromScale(0, 0)
end

local function showError(message)
    stopIndeterminate()
    setStatus("failed", THEME.Error)
    setProgress(1)

    fill.BackgroundColor3 = THEME.Error
    local gradient = fill:FindFirstChildOfClass("UIGradient")
    if gradient then
        gradient.Color = ColorSequence.new(THEME.Error)
    end

    errorMessage.Text = tostring(message)
    tween(errorMessage, 0.2, { TextTransparency = 0 })
    retryButton.Visible = true
    copyButton.Visible = CAPABILITIES.clipboard

    log("ERROR", tostring(message))
end

local function resetAfterError()
    errorMessage.TextTransparency = 1
    retryButton.Visible = false
    copyButton.Visible = false

    local gradient = fill:FindFirstChildOfClass("UIGradient")
    if gradient then
        gradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, THEME.Accent),
            ColorSequenceKeypoint.new(1, THEME.AccentSoft),
        })
    end
    fill.BackgroundColor3 = THEME.Accent
    setProgress(0)
end

-----------------------------------------------------------------------
-- SECTION 10 : TRANSITION AND HANDOFF
-----------------------------------------------------------------------

local revealCalled = false
local failsafeHandle = nil

local function destroyLoader()
    if gui then
        gui:Destroy()
        gui = nil
    end
    genv[CONFIG.CONTEXT_KEY] = nil
end

local function reveal()
    if revealCalled or not gui then
        return
    end
    revealCalled = true

    if failsafeHandle then
        -- task.delay returns a thread, not a connection; cancel
        -- what can be cancelled and clear the reference either way.
        pcall(function()
            if type(failsafeHandle) == "userdata" then
                failsafeHandle:Disconnect()
            end
        end)
        failsafeHandle = nil
    end

    -- Outro: veil fades, card lifts and dissolves. The runtime
    -- window fades in simultaneously for one seamless transform.
    tween(dim, 0.45, { BackgroundTransparency = 1 })

    local scale = card:FindFirstChild("Scale")
    if scale then
        tween(scale, 0.45, { Scale = 1.04 }, Enum.EasingStyle.Back)
    end

    tween(card, 0.45, { BackgroundTransparency = 1 })
    setFade(1)

    local stroke = card:FindFirstChildOfClass("UIStroke")
    if stroke then
        tween(stroke, 0.45, { Transparency = 1 })
    end

    later(0.5, destroyLoader)
    debugLog("reveal complete, loader visuals released")
end

-----------------------------------------------------------------------
-- SECTION 11 : BOOT SEQUENCE
-----------------------------------------------------------------------

local function runBoot()
    -- Stage 1: environment.
    setStatus("initializing")
    setProgress(0.05)
    detectCapabilities()
    yield(0.1)

    -- Stage 2: contact.
    setStatus("contacting repository")
    setProgress(0.15)
    local url = buildUrl()
    debugLog("fetching " .. url)
    yield(0.1)

    -- Stage 3: download (blocking; indeterminate bar covers it).
    setStatus("downloading payload")
    startIndeterminate()
    local source, fetchError = fetchSource(url)
    stopIndeterminate()

    if not source then
        showError(fetchError)
        return
    end

    local sizeKb = #source / 1024
    setStatus(string.format("downloaded %.1f KB", sizeKb),
        THEME.Success)
    setProgress(0.6)
    yield(0.15)

    -- Stage 4: validate.
    setStatus("validating payload")
    setProgress(0.75)
    local chunk, validateError = validateSource(source)

    if not chunk then
        showError(validateError)
        return
    end

    setProgress(0.85)
    yield(0.1)

    -- Stage 5: handoff. Build the context and execute the runtime.
    setStatus("starting runtime")
    setProgress(0.95)

    local context = {
        version = CONFIG.VERSION,
        theme = THEME,
        capabilities = CAPABILITIES,
        gui = gui,
        reveal = reveal,
        destroy = destroyLoader,
        log = log,
    }
    genv[CONFIG.CONTEXT_KEY] = context

    local ok, runtimeError = pcall(chunk)

    if not ok then
        genv[CONFIG.CONTEXT_KEY] = nil
        showError("runtime error: " .. tostring(runtimeError))
        return
    end

    -- Stage 6: ready. The runtime calls reveal() when its window
    -- is built. The failsafe forces the transition if it stalls.
    setStatus("ready", THEME.Success)
    setProgress(1)

    failsafeHandle = later(CONFIG.AUTO_REVEAL, function()
        if not revealCalled then
            log("WARN", "runtime did not call reveal, forcing it")
            reveal()
        end
    end)
end

-----------------------------------------------------------------------
-- SECTION 12 : INTRO SEQUENCE
-----------------------------------------------------------------------

local function playIntro()
    -- Everything starts invisible and slightly scaled down, then
    -- resolves into place. The veil dims behind the card.
    card.BackgroundTransparency = 1
    setFade(1)

    local stroke = card:FindFirstChildOfClass("UIStroke")
    if stroke then
        stroke.Transparency = 1
    end

    local scale = card:FindFirstChild("Scale")

    tween(dim, 0.4, { BackgroundTransparency = 0.5 })
    tween(card, 0.4, { BackgroundTransparency = 0 })
    setFade(0)

    if stroke then
        tween(stroke, 0.4, { Transparency = 0 })
    end

    if scale then
        tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
    end

    -- Start the boot sequence shortly after the intro begins so
    -- both are visible together.
    later(0.25, runBoot)
end

-----------------------------------------------------------------------
-- SECTION 13 : ENTRY POINT
-----------------------------------------------------------------------

local scale = buildInterface()
playIntro()

log("INFO", string.format("loader v%s active (%s/%s)",
    CONFIG.VERSION, CONFIG.REPO, CONFIG.BRANCH))

-- Error UI wiring. Retry re-runs the boot sequence without
-- requiring the one-liner to be executed again.
retryButton.MouseButton1Click:Connect(function()
    resetAfterError()
    async(runBoot)
end)

copyButton.MouseButton1Click:Connect(function()
    if type(setclipboard) == "function" then
        setclipboard(errorMessage.Text)
        copyButton.Text = "Copied"
        later(1.5, function()
            if copyButton then
                copyButton.Text = "Copy error"
            end
        end)
    end
end)
