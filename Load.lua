--[[
    simplyspirited v4.6 loader
    SHADOWMILESC / computerizedcarrier2

    one line, any game:
    loadstring(game:HttpGet(".../Load.lua?nocache=" .. os.time()))()

    the loading screen doubles as the boot report: every part
    prints a line as it loads, failures are named in red, and
    the window hands off to the ui when done.
]]

-- ═══ boot splash (instant, before anything fetches) ═══
local Players = game:GetService("Players")
local P = Players.LocalPlayer
local UIS = game:GetService("UserInputService")

local gui = Instance.new("ScreenGui")
gui.Name = "SS2_Loader"
gui.ResetOnSpawn = false
gui.DisplayOrder = 99999
local okRoot = pcall(function()
    gui.Parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
end)
if not okRoot then gui.Parent = P:WaitForChild("PlayerGui") end

local T = {
    BG   = Color3.fromRGB(9, 9, 9),
    RAIL = Color3.fromRGB(14, 14, 14),
    TEXT = Color3.fromRGB(210, 210, 210),
    DIM  = Color3.fromRGB(98, 98, 98),
    RED  = Color3.fromRGB(198, 38, 48),
}

local win = Instance.new("Frame")
win.Size = UDim2.fromOffset(360, 240)
win.Position = UDim2.new(0.5, -180, 0.5, -120)
win.BackgroundColor3 = T.BG
win.BorderSizePixel = 0
win.Active = true
win.Parent = gui

-- drag for the splash too (it might sit on the loading screen a while)
local dragging, dStart, dPos = false, nil, nil
local hdr = Instance.new("Frame")
hdr.Size = UDim2.new(1, 0, 0, 22)
hdr.BackgroundColor3 = T.RAIL
hdr.BorderSizePixel = 0
hdr.Parent = win
local hT = Instance.new("TextLabel")
hT.Size = UDim2.new(1, -12, 1, 0)
hT.Position = UDim2.fromOffset(8, 0)
hT.BackgroundTransparency = 1
hT.Font = Enum.Font.Code
hT.TextSize = 11
hT.TextColor3 = T.TEXT
hT.TextXAlignment = Enum.TextXAlignment.Left
hT.Text = "simplyspirited — v4.6"
hT.Parent = hdr
hdr.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dStart = i.Position
        dPos = win.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dStart
        win.Position = UDim2.new(dPos.X.Scale, dPos.X.Offset + d.X,
            dPos.Y.Scale, dPos.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function()
    dragging = false
end)

-- status lines
local logFrame = Instance.new("Frame")
logFrame.Size = UDim2.new(1, -16, 1, -66)
logFrame.Position = UDim2.fromOffset(8, 30)
logFrame.BackgroundTransparency = 1
logFrame.Parent = win
local logLayout = Instance.new("UIListLayout")
logLayout.Padding = UDim.new(0, 2)
logLayout.SortOrder = Enum.SortOrder.LayoutOrder
logLayout.Parent = logFrame

local lineCount = 0
local function addLine(text, color)
    lineCount = lineCount + 1
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, 0, 0, 14)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Code
    l.TextSize = 10
    l.TextColor3 = color or T.DIM
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Text = text
    l.LayoutOrder = lineCount
    l.Parent = logFrame
    -- keep last 12 lines visible
    if lineCount > 12 then
        for _, c in ipairs(logFrame:GetChildren()) do
            if c:IsA("TextLabel") and c.LayoutOrder <= lineCount - 12 then
                c:Destroy()
            end
        end
    end
end

-- progress bar
local barBG = Instance.new("Frame")
barBG.Size = UDim2.new(1, -16, 0, 4)
barBG.Position = UDim2.new(0, 8, 1, -24)
barBG.BackgroundColor3 = T.RAIL
barBG.BorderSizePixel = 0
barBG.Parent = win
local barFill = Instance.new("Frame")
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = T.RED
barFill.BorderSizePixel = 0
barFill.Parent = barBG

local pctLabel = Instance.new("TextLabel")
pctLabel.Size = UDim2.new(0, 60, 0, 14)
pctLabel.Position = UDim2.new(1, -68, 1, -32)
pctLabel.BackgroundTransparency = 1
pctLabel.Font = Enum.Font.Code
pctLabel.TextSize = 10
pctLabel.TextColor3 = T.DIM
pctLabel.TextXAlignment = Enum.TextXAlignment.Right
pctLabel.Text = "0%"
pctLabel.Parent = win

addLine("ss2 :: simplyspirited v4.6", T.TEXT)
addLine("operator: " .. P.Name, T.DIM)

-- ═══ CONFIG ═══
local REPO = "https://raw.githubusercontent.com/randomguy454/simplyspirited/refs/heads/main/"

local PARTS = {
    { file = "core.lua",         name = "ENGINE",       required = true  },
    { file = "closure.lua",      name = "CLOSURE",      required = false },
    { file = "callers.lua",      name = "CALLERS",      required = false },
    { file = "watch.lua",        name = "SURVEILLANCE", required = false },
    { file = "ui.lua",           name = "INTERFACE",    required = true  },
    { file = "output.lua",       name = "OUTPUT",       required = false },
    { file = "governor.lua",     name = "GOVERNOR",     required = false },
    { file = "stealth.lua",      name = "STEALTH",      required = false },
    { file = "describe_ext.lua", name = "ARG FIDELITY", required = false },
    { file = "decomp.lua",       name = "DECOMPILER",   required = false },
    { file = "export.lua",       name = "VAULT",        required = false },
    { file = "vault2.lua",       name = "VAULT 2",      required = false },
    { file = "ss_dump.lua",      name = "GAME DUMP",    required = false },
}

-- ═══ CLEAN STATE WIPE ═══
getgenv().SS2 = nil
getgenv().SS2_READY = nil
getgenv().SS2_UI = nil

-- ═══ LOAD SEQUENCE (with live splash updates) ═══
local loaded, failed = 0, {}
local results = {}

for i, part in ipairs(PARTS) do
    local pct = math.floor((i - 1) / #PARTS * 100)
    pctLabel.Text = pct .. "%"
    barFill.Size = UDim2.new(pct / 100, 0, 1, 0)

    local url = REPO .. part.file .. "?nocache=" .. os.time() .. i
    local src

    local okFetch = pcall(function()
        src = game:HttpGet(url)
    end)

    if not okFetch or type(src) ~= "string" or #src < 10 then
        failed[#failed + 1] = part.name .. " (fetch)"
        results[#results + 1] = { name = part.name, ok = false, why = "fetch" }
        addLine("  ✗ " .. part.name .. " — fetch failed", T.RED)
        if part.required then
            addLine("!! boot halted — " .. part.file .. " is required", T.RED)
            task.wait(3)
            gui:Destroy()
            return
        end
    else
        local fn, compileErr = loadstring(src)
        if not fn then
            failed[#failed + 1] = part.name .. " (compile)"
            results[#results + 1] = { name = part.name, ok = false, why = "compile" }
            addLine("  ✗ " .. part.name .. " — COMPILE: " .. tostring(compileErr), T.RED)
            if part.required then
                addLine("!! boot halted — required part broken", T.RED)
                task.wait(3)
                gui:Destroy()
                return
            end
        else
            local okRun, runErr = pcall(fn)
            if okRun then
                loaded = loaded + 1
                results[#results + 1] = { name = part.name, ok = true }
                addLine("  ✓ " .. part.name, T.TEXT)
            else
                failed[#failed + 1] = part.name .. " (runtime)"
                results[#results + 1] = { name = part.name, ok = false, why = "runtime" }
                addLine("  ✗ " .. part.name .. " — runtime: " .. tostring(runErr), T.RED)
                if part.required then
                    addLine("!! boot halted — required part broken", T.RED)
                    task.wait(3)
                    gui:Destroy()
                    return
                end
            end
        end
    end
    task.wait(0.05)
end

-- ═══ FINAL REPORT ═══
local finalPct = 100
pctLabel.Text = "100%"
barFill.Size = UDim2.new(1, 0, 1, 0)

if #failed == 0 then
    addLine("── 13/13 online ──", T.TEXT)
elseif loaded > 0 then
    addLine("── partial: " .. loaded .. "/" .. #PARTS .. " ──", T.RED)
    for _, f in ipairs(failed) do
        addLine("  failed: " .. f, T.RED)
    end
else
    addLine("── TOTAL BOOT FAILURE ──", T.RED)
    task.wait(3)
    gui:Destroy()
    return
end

-- ═══ HANDOFF: destroy splash, let the suite's UI take over ═══
task.wait(1.2)
gui:Destroy()
print("[loader] complete — " .. loaded .. "/" .. #PARTS .. " | simplyspirited by SHADOWMILESC")

getgenv().SIMPLYSPIRITED_V2 = loaded
