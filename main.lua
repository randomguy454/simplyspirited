--=====================================================================
--  PROJECT   : SimplySpy
--  FILE      : main.lua
--  VERSION   : 0.1.0
--
--  PURPOSE   :
--    Runtime stub. Called by the loader, receives the context,
--    builds a placeholder window, and hands control back via
--    reveal(). This file is the place to build the real interface.
--
--  TARGET    : UNC-compatible Roblox script executors
--  LICENSE   : MIT
--=====================================================================

local TweenService = game:GetService("TweenService")

local genv = (typeof(getgenv) == "function") and getgenv() or _G
local ctx = genv.SimplySpy_Context

if not ctx then
    error("SimplySpy runtime: loader context missing")
end

ctx.log("INFO", "runtime online v" .. tostring(ctx.version))

-- Mark: this is the stub to improve upon.
-- Replace the placeholder window below with the real interface.

local function buildPlaceholderWindow()
    local frame = Instance.new("Frame")
    frame.Name = "RuntimeWindow"
    frame.Size = UDim2.fromOffset(520, 600)
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.BackgroundColor3 = ctx.theme.Card
    frame.BorderSizePixel = 0
    frame.Parent = ctx.gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = ctx.theme.CardBorder
    stroke.Thickness = 1
    stroke.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0, 32)
    title.Position = UDim2.new(0, 10, 0, 10)
    title.BackgroundTransparency = 1
    title.Text = "SimplySpy Runtime"
    title.TextColor3 = ctx.theme.TextPrimary
    title.TextSize = 18
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local subtitle = Instance.new("TextLabel")
    subtitle.Size = UDim2.new(1, -20, 0, 18)
    subtitle.Position = UDim2.new(0, 10, 0, 42)
    subtitle.BackgroundTransparency = 1
    subtitle.Text = "batch 2 goes here"
    subtitle.TextColor3 = ctx.theme.TextSecondary
    subtitle.TextSize = 12
    subtitle.Font = Enum.Font.Gotham
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.Parent = frame

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -20, 0, 14)
    status.Position = UDim2.new(0, 10, 1, -24)
    status.BackgroundTransparency = 1
    status.Text = "runtime stub active"
    status.TextColor3 = ctx.theme.TextFaint
    status.TextSize = 10
    status.Font = Enum.Font.Gotham
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = frame

    -- Fade the runtime window in as the loader card fades out.
    frame.BackgroundTransparency = 1
    title.TextTransparency = 1
    subtitle.TextTransparency = 1
    status.TextTransparency = 1
    stroke.Transparency = 1

    TweenService:Create(frame, TweenInfo.new(0.45), {
        BackgroundTransparency = 0
    }):Play()
    TweenService:Create(title, TweenInfo.new(0.45), {
        TextTransparency = 0
    }):Play()
    TweenService:Create(subtitle, TweenInfo.new(0.45), {
        TextTransparency = 0
    }):Play()
    TweenService:Create(status, TweenInfo.new(0.45), {
        TextTransparency = 0
    }):Play()
    TweenService:Create(stroke, TweenInfo.new(0.45), {
        Transparency = 0
    }):Play()

    return frame
end

buildPlaceholderWindow()
ctx.reveal()
