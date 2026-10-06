--=====================================================================
--  PROJECT   : SimplySpy
--  FILE      : loader.lua
--  VERSION   : 0.1.0
--  REPO      : randomguy454/simplyspirited
--
--  PURPOSE   :
--    Bootstrap entry point. Renders a CoreGui loading interface,
--    fetches the remote payload with retry and backoff, validates
--    it without executing, then hands control to the runtime with
--    an animated transition.
--
--  USAGE     :
--    loadstring(game:HttpGet(
--      "https://raw.githubusercontent.com/randomguy454/simplyspirited/main/loader.lua"
--    ))()
--
--  TARGET    : UNC-compatible Roblox script executors
--  LICENSE   : MIT
--=====================================================================

-----------------------------------------------------------------------
-- SECTION 1 : SERVICES AND ENVIRONMENT
-----------------------------------------------------------------------

local TweenService = game:GetService("TweenService")
local Players      = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    print("[SimplySpy] fatal: LocalPlayer unavailable")
    return
end

-- Cross-executor safe yield primitive.
local function yield(t)
    if task and task.wait then
        task.wait(t)
    else
        wait(t)
    end
end

-----------------------------------------------------------------------
-- SECTION 2 : CONFIGURATION
-----------------------------------------------------------------------

local CONFIG = {
    -- Source of truth for the payload.
    REPO     = "randomguy454/simplyspirited",
    BRANCH   = "main",
    ENTRY    = "main.lua",
    VERSION  = "0.1.0",

    -- Networking.
    MAX_RETRIES = 3,
    RETRY_BASE  = 0.5,   -- seconds; doubles on each retry

    -- Contract name used to pass the context to the runtime.
    CONTEXT_KEY = "SimplySpy_Context",

    -- Failsafe: force the transition if the runtime never calls
    -- reveal() within this many seconds after successful boot.
    AUTO_REVEAL = 10,

    -- Verbose logging.
    DEBUG = false,
}

-- Optional overrides from the user environment.
local genv = (typeof(getgenv) == "function") and getgenv() or _G
if typeof(genv.SIMPLYSPY_CONFIG) == "table" then
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

local CAPABILITIES = {}

local function detectCapabilities()
    CAPABILITIES.gethui = typeof(gethui) == "function"
    CAPABILITIES.clipboard = typeof(setclipboard) == "function"
    CAPABILITIES.filesystem = (typeof(writefile) == "function")
        and (typeof(readfile) == "function")
    CAPABILITIES.newcclosure = typeof(newcclosure) == "function"
    CAPABILITIES.getrawmetatable = typeof(getrawmetatable) == "function"
    CAPABILITIES.getgenv = typeof(getgenv) == "function"

    for name, supported in pairs(CAPABILITIES) do
        debugLog(string.format("capability %-16s %s",
            name, supported and "yes" or "no"))
    end
end

-----------------------------------------------------------------------
-- SECTION 5 : HTTP AND VALIDATION
-----------------------------------------------------------------------

local function buildUrl()
    return string.format(
        "https://raw.githubusercontent.com/%s/%s/%s",
        CONFIG.REPO, CONFIG.BRANCH, CONFIG.ENTRY
    )
end

-- Fetches raw source. Returns (source, nil) or (nil, error).
local function fetchSource(url)
    local delay = CONFIG.RETRY_BASE

    for attempt = 1, CONFIG.MAX_RETRIES do
        local ok, body = pcall(function()
            -- Second argument bypasses the executor HTTP cache.
            return game:HttpGet(url, true)
        end)

        if ok and type(body) == "string" and #body > 0 then
            -- GitHub serves this prefix when the ref or path is bad.
            if body:sub(1, 4) == "404:" then
                return nil, "repository returned 404 (check REPO/BRANCH/ENTRY)"
            end
            return body
        end

        log("WARN", string.format("fetch attempt %d/%d failed: %s",
            attempt, CONFIG.MAX_RETRIES, tostring(body)))

        if attempt < CONFIG.MAX_RETRIES then
            yield(delay)
            delay = delay * 2
        end
    end

    return nil, "network failed after " .. CONFIG.MAX_RETRIES .. " attempts"
end

-- Compiles without executing. Returns (chunk, nil) or (nil, error).
local function validateSource(source)
    if type(source) ~= "string" or #source == 0 then
        return nil, "payload is empty"
    end

    local chunk, err = (loadstring or load)(source, "=SimplySpy/Runtime")
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
--     Dim        (full screen, fades in, subtle dark veil)
--     Card       (centered, draggable)
--       Logo     (accent rounded square, "SS")
--       Title    ("SimplySpy")
--       Subtitle ("remote inspection suite")
--       Status   (stage text)
--       Percent  (right aligned)
--       Track
--         Fill   (accent gradient)
--       Footer   (version and repository)

local gui
local card
local dim
local statusLabel
local percentLabel
local fill
local track
local errorButtonRetry
local errorButtonCopy
local errorMessage

-- Collected for group fade operations.
local fadeables = {}

local function registerFadeable(label)
    table.insert(fadeables, label)
end

local function setFade(transparency)
    for _, label in ipairs(fadeables) do
        label.TextTransparency = transparency
    end
end

local function buildInterface()
    gui = Instance.new("ScreenGui")
    gui.Name = "SimplySpy_Loader"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 999
    gui.IgnoreGuiInset = true

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

    -- Full screen veil.
    dim = Instance.new("Frame")
    dim.Size = UDim2.fromScale(1, 1)
    dim.BackgroundColor3 = THEME.Background
    dim.BackgroundTransparency = 1
    dim.BorderSizePixel = 0
    dim.ZIndex = 1
    dim.Parent = gui

    -- Card container.
    card = Instance.new("Frame")
    card.Size = UDim2.fromOffset(380, 240)
    card.Position = UDim2.new(0.5, 0, 0.5, 0)
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.BackgroundColor3 = THEME.Card
    card.BorderSizePixel = 0
    card.Active = true
    card.Draggable = true
    card.ZIndex = 2
    card.Parent = gui

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 10)
    cardCorner.Parent = card

    local cardStroke = Instance.new("UIStroke")
    cardStroke.Color = THEME.CardBorder
    cardStroke.Thickness = 1
    cardStroke.Parent = card

    -- Scale handle for the intro and outro transforms.
    local scale = Instance.new("UIScale")
    scale.Name = "Scale"
    scale.Scale = 0.92
    scale.Parent = card

    -- Logo mark.
    local logo = Instance.new("Frame")
    logo.Size = UDim2.fromOffset(44, 44)
    logo.Position = UDim2.new(0, 24, 0, 24)
    logo.BackgroundColor3 = THEME.Accent
    logo.BorderSizePixel = 0
    logo.ZIndex = 3
    logo.Parent = card

    local logoCorner = Instance.new("UICorner")
    logoCorner.CornerRadius = UDim.new(0, 10)
    logoCorner.Parent = logo

    local logoText = Instance.new("TextLabel")
    logoText.Size = UDim2.fromScale(1, 1)
    logoText.BackgroundTransparency = 1
    logoText.Text = "SS"
    logoText.TextColor3 = THEME.Background
    logoText.TextSize = 18
    logoText.Font = Enum.Font.GothamBold
    logoText.ZIndex = 4
    logoText.Parent = logo
    registerFadeable(logoText)

    -- Title.
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -160, 0, 26)
    title.Position = UDim2.new(0, 82, 0, 24)
    title.BackgroundTransparency = 1
    title.Text = "SimplySpy"
    title.TextColor3 = THEME.TextPrimary
    title.TextSize = 20
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 3
    title.Parent = card
    registerFadeable(title)

    -- Subtitle.
    local subtitle = Instance.new("TextLabel")
    subtitle.Size = UDim2.new(1, -160, 0, 16)
    subtitle.Position = UDim2.new(0, 82, 0, 50)
    subtitle.BackgroundTransparency = 1
    subtitle.Text = "remote inspection suite"
    subtitle.TextColor3 = THEME.TextSecondary
    subtitle.TextSize = 12
    subtitle.Font = Enum.Font.Gotham
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.ZIndex = 3
    subtitle.Parent = card
    registerFadeable(subtitle)

    -- Status (left) and percent (right) sit above the progress bar.
    statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -110, 0, 14)
    statusLabel.Position = UDim2.new(0, 24, 1, -78)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "initializing"
    statusLabel.TextColor3 = THEME.TextSecondary
    statusLabel.TextSize = 12
    statusLabel.Font = Enum.Font.GothamMedium
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.ZIndex = 3
    statusLabel.Parent = card
    registerFadeable(statusLabel)

    percentLabel = Instance.new("TextLabel")
    percentLabel.Size = UDim2.new(0, 80, 0, 14)
    percentLabel.Position = UDim2.new(1, -104, 1, -78)
    percentLabel.BackgroundTransparency = 1
    percentLabel.Text = "0%"
    percentLabel.TextColor3 = THEME.TextFaint
    percentLabel.TextSize = 12
    percentLabel.Font = Enum.Font.GothamMedium
    percentLabel.TextXAlignment = Enum.TextXAlignment.Right
    percentLabel.ZIndex = 3
    percentLabel.Parent = card
    registerFadeable(percentLabel)

    -- Progress track.
    track = Instance.new("Frame")
    track.Size = UDim2.new(1, -48, 0, 6)
    track.Position = UDim2.new(0, 24, 1, -56)
    track.BackgroundColor3 = THEME.BarTrack
    track.BorderSizePixel = 0
    track.ClipsDescendants = true
    track.ZIndex = 3
    track.Parent = card

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(1, 0)
    trackCorner.Parent = track

    fill = Instance.new("Frame")
    fill.Size = UDim2.fromScale(0, 1)
    fill.Position = UDim2.fromScale(0, 0)
    fill.BackgroundColor3 = THEME.Accent
    fill.BorderSizePixel = 0
    fill.ZIndex = 4
    fill.Parent = track

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    local fillGradient = Instance.new("UIGradient")
    fillGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, THEME.Accent),
        ColorSequenceKeypoint.new(1, THEME.AccentSoft),
    })
    fillGradient.Parent = fill

    -- Footer.
    local footer = Instance.new("TextLabel")
    footer.Size = UDim2.new(1, -48, 0, 12)
    footer.Position = UDim2.new(0, 24, 1, -30)
    footer.BackgroundTransparency = 1
    footer.Text = "v" .. CONFIG.VERSION .. "  -  " .. CONFIG.REPO
    footer.TextColor3 = THEME.TextFaint
    footer.TextSize = 10
    footer.Font = Enum.Font.Gotham
    footer.TextXAlignment = Enum.TextXAlignment.Left
    footer.ZIndex = 3
    footer.Parent = card
    registerFadeable(footer)

    -- Error elements (hidden until an error occurs).
    errorMessage = Instance.new("TextLabel")
    errorMessage.Size = UDim2.new(1, -48, 0, 30)
    errorMessage.Position = UDim2.new(0, 24, 0, 86)
    errorMessage.BackgroundTransparency = 1
    errorMessage.Text = ""
    errorMessage.TextColor3 = THEME.Error
    errorMessage.TextSize = 11
    errorMessage.Font = Enum.Font.Gotham
    errorMessage.TextWrapped = true
    errorMessage.TextXAlignment = Enum.TextXAlignment.Left
    errorMessage.TextYAlignment = Enum.TextYAlignment.Top
    errorMessage.TextTransparency = 1
    errorMessage.ZIndex = 3
    errorMessage.Parent = card

    errorButtonRetry = Instance.new("TextButton")
    errorButtonRetry.Size = UDim2.fromOffset(90, 26)
    errorButtonRetry.Position = UDim2.new(1, -120, 1, -40)
    errorButtonRetry.BackgroundColor3 = THEME.Accent
    errorButtonRetry.BorderSizePixel = 0
    errorButtonRetry.Text = "Retry"
    errorButtonRetry.TextColor3 = THEME.TextPrimary
    errorButtonRetry.TextSize = 12
    errorButtonRetry.Font = Enum.Font.GothamMedium
    errorButtonRetry.Visible = false
    errorButtonRetry.ZIndex = 3
    errorButtonRetry.Parent = card

    local retryCorner = Instance.new("UICorner")
    retryCorner.CornerRadius = UDim.new(0, 6)
    retryCorner.Parent = errorButtonRetry

    errorButtonCopy = Instance.new("TextButton")
    errorButtonCopy.Size = UDim2.fromOffset(90, 26)
    errorButtonCopy.Position = UDim2.new(1, -222, 1, -40)
    errorButtonCopy.BackgroundColor3 = THEME.BarTrack
    errorButtonCopy.BorderSizePixel = 0
    errorButtonCopy.Text = "Copy error"
    errorButtonCopy.TextColor3 = THEME.TextSecondary
    errorButtonCopy.TextSize = 12
    errorButtonCopy.Font = Enum.Font.GothamMedium
    errorButtonCopy.Visible = false
    errorButtonCopy.ZIndex = 3
    errorButtonCopy.Parent = card

    local copyCorner = Instance.new("UICorner")
    copyCorner.CornerRadius = UDim.new(0, 6)
    copyCorner.Parent = errorButtonCopy

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
    percentLabel.Text = string.format("%d%%", math.floor(alpha * 100 + 0.5))
end

-- Indeterminate mode: the fill slides across the track on a loop
-- while a blocking operation (the HTTP fetch) is in flight. The
-- tween runs on the render thread and survives script yields.
local indeterminateTween = nil

local function startIndeterminate()
    fill.Size = UDim2.fromScale(0.35, 1)
    fill.Position = UDim2.fromScale(-0.35, 0)
    local info = TweenInfo.new(
        0.9,
        Enum.EasingStyle.Linear,
        Enum.EasingDirection.Out,
        -1,   -- repeat forever
        false,
        0
    )
    indeterminateTween = TweenService:Create(fill, info, {
        Position = UDim2.fromScale(1, 0)
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
    errorButtonRetry.Visible = true
    errorButtonCopy.Visible = CAPABILITIES.clipboard

    log("ERROR", tostring(message))
end

local function resetAfterError()
    errorMessage.TextTransparency = 1
    errorButtonRetry.Visible = false
    errorButtonCopy.Visible = false

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
-- Contract with the runtime (main.lua):
--   ctx.gui       : ScreenGui to parent runtime UI into
--   ctx.reveal()  : runtime calls this once its window is built;
--                   the loader performs the outro transform
--   ctx.destroy() : emergency teardown of loader visuals
--   ctx.theme, ctx.capabilities, ctx.log : shared utilities

local revealCalled = false
local autoRevealConnection = nil

local function destroyLoader()
    if gui then
        gui:Destroy()
        gui = nil
    end
    local genv = CAPABILITIES.getgenv and getgenv() or _G
    genv[CONFIG.CONTEXT_KEY] = nil
end

local function reveal()
    if revealCalled or not gui then
        return
    end
    revealCalled = true

    if autoRevealConnection then
        autoRevealConnection:Disconnect()
        autoRevealConnection = nil
    end

    -- Outro: veil fades, card lifts and dissolves. The runtime
    -- window should begin its own fade-in at the same moment.
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

    task.delay(0.5, destroyLoader)
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
    setStatus(string.format("downloaded %.1f KB", sizeKb), THEME.Success)
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

    -- Stage 5: handoff.
    setStatus("starting runtime")
    setProgress(0.95)

    local genv = CAPABILITIES.getgenv and getgenv() or _G
    local context = {
        version      = CONFIG.VERSION,
        theme        = THEME,
        capabilities = CAPABILITIES,
        gui          = gui,
        reveal       = reveal,
        destroy      = destroyLoader,
        log          = log,
    }
    genv[CONFIG.CONTEXT_KEY] = context

    local ok, runtimeError = pcall(chunk)
    if not ok then
        genv[CONFIG.CONTEXT_KEY] = nil
        showError("runtime error: " .. tostring(runtimeError))
        return
    end

    -- Stage 6: ready. Runtime will call reveal() when its window
    -- is built. The failsafe forces the transition if it stalls.
    setStatus("ready", THEME.Success)
    setProgress(1)

    autoRevealConnection = task.delay(CONFIG.AUTO_REVEAL, function()
        if not revealCalled then
            log("WARN", "runtime did not call reveal, forcing transition")
            reveal()
        end
    end)
end

-----------------------------------------------------------------------
-- SECTION 12 : INTRO SEQUENCE AND ENTRY
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

    -- Start the boot sequence slightly after the intro begins so
    -- both are visible together.
    task.delay(0.25, runBoot)
end

-----------------------------------------------------------------------
-- ENTRY POINT
-----------------------------------------------------------------------

local scale = buildInterface()
playIntro()

log("INFO", string.format("loader v%s active (%s/%s)",
    CONFIG.VERSION, CONFIG.REPO, CONFIG.BRANCH))

-- Error UI wiring (retry and copy-error).
errorButtonRetry.MouseButton1Click:Connect(function()
    resetAfterError()
    task.spawn(runBoot)
end)

errorButtonCopy.MouseButton1Click:Connect(function()
    if setclipboard then
        setclipboard(errorMessage.Text)
        errorButtonCopy.Text = "Copied"
        task.delay(1.5, function()
            if errorButtonCopy then
                errorButtonCopy.Text = "Copy error"
            end
        end)
    end
end)
