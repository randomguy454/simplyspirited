-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.6 — SG+ (click-to-act feed)
--  For SHADOWMILESC (computerizedcarrier2)
--  Feed lines become clickable: full detail card with buttons
--  [REPLAY] [COPY] [PRESET] [INSPECT] — touch friendly.
--  Requires screengui.lua + engine.
-- ════════════════════════════════════════════════════════════

print("[SS2-sgp] wiring click-to-act feed...")

local SS2 = getgenv().SS2
if not SS2 or not SS2.gui then warn("[SS2-sgp] screengui.lua must load first") return end

local Players = game:GetService("Players")
local P = Players.LocalPlayer

-- patch the FEED renderer to make lines clickable buttons
local oldSwitch = SS2.switchTab
local selectedIndex = nil

SS2.switchTab = function(i)
    oldSwitch(i)
    -- convert FEED lines to buttons (post-render pass)
    if i == 1 then
        for _, c in ipairs(SS2.scroll:GetChildren()) do
            if c:IsA("TextLabel") then
                local idMatch = c.Text:match("^#(%d+)")
                if idMatch then
                    local btn = Instance.new("TextButton")
                    btn.Size = c.Size
                    btn.BackgroundTransparency = 1
                    btn.Font = Enum.Font.Code
                    btn.TextSize = 12
                    btn.TextColor3 = c.TextColor3
                    btn.TextXAlignment = Enum.TextXAlignment.Left
                    btn.Text = c.Text
                    btn.LayoutOrder = c.LayoutOrder
                    btn.TextTruncate = Enum.TextTruncate.AtEnd
                    btn.Parent = SS2.scroll
                    local recId = tonumber(idMatch)
                    btn.MouseButton1Click:Connect(function()
                        showDetail(recId)
                    end)
                    c:Destroy()
                end
            end
        end
    end
end

-- detail card
local card = Instance.new("Frame")
card.Size = UDim2.new(0, 340, 0, 240)
card.Position = UDim2.new(0, 580, 0, 60)
card.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
card.BorderSizePixel = 0
card.Visible = false
card.Active = true
card.Parent = SS2.gui
local cardCorner = Instance.new("UICorner")
cardCorner.CornerRadius = UDim.new(0, 10)
cardCorner.Parent = card
local cardStroke = Instance.new("UIStroke")
cardStroke.Color = SS2.theme.ACCENT
cardStroke.Thickness = 1.5
cardStroke.Parent = card

local cardTitle = Instance.new("TextLabel")
cardTitle.Size = UDim2.new(1, -60, 0, 24)
cardTitle.Position = UDim2.new(0, 10, 0, 6)
cardTitle.BackgroundTransparency = 1
cardTitle.Font = Enum.Font.GothamBold
cardTitle.TextSize = 13
cardTitle.TextColor3 = SS2.theme.ACCENT
cardTitle.TextXAlignment = Enum.TextXAlignment.Left
cardTitle.Text = ""
cardTitle.Parent = card

local cardClose = Instance.new("TextButton")
cardClose.Size = UDim2.new(0, 24, 0, 22)
cardClose.Position = UDim2.new(1, -30, 0, 5)
cardClose.BackgroundColor3 = SS2.theme.RED
cardClose.Text = "X"
cardClose.Font = Enum.Font.GothamBold
cardClose.TextSize = 12
cardClose.TextColor3 = Color3.new(1, 1, 1)
cardClose.Parent = card

local cardScroll = Instance.new("ScrollingFrame")
cardScroll.Size = UDim2.new(1, -16, 1, -92)
cardScroll.Position = UDim2.new(0, 8, 0, 32)
cardScroll.BackgroundTransparency = 1
cardScroll.BorderSizePixel = 0
cardScroll.ScrollBarThickness = 4
cardScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
cardScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
cardScroll.Parent = card
local cardLayout = Instance.new("UIListLayout")
cardLayout.Padding = UDim.new(0, 2)
cardLayout.Parent = cardScroll

local cardBody = Instance.new("TextLabel")
cardBody.Size = UDim2.new(1, 0, 0, 0)
cardBody.AutomaticSize = Enum.AutomaticSize.Y
cardBody.BackgroundTransparency = 1
cardBody.Font = Enum.Font.Code
cardBody.TextSize = 11
cardBody.TextColor3 = SS2.theme.TEXT
cardBody.TextXAlignment = Enum.TextXAlignment.Left
cardBody.TextYAlignment = Enum.TextYAlignment.Top
cardBody.TextWrapped = true
cardBody.Text = ""
cardBody.Parent = cardScroll

local btnRow = Instance.new("Frame")
btnRow.Size = UDim2.new(1, -16, 0, 30)
btnRow.Position = UDim2.new(0, 8, 1, -38)
btnRow.BackgroundTransparency = 1
btnRow.Parent = card
local btnLayout = Instance.new("UIListLayout")
btnLayout.FillDirection = Enum.FillDirection.Horizontal
btnLayout.Padding = UDim.new(0, 6)
btnLayout.Parent = btnRow

local function mkBtn(txt, color, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 72, 1, 0)
    b.BackgroundColor3 = color
    b.Text = txt
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.TextColor3 = Color3.new(1, 1, 1)
    local cc = Instance.new("UICorner")
    cc.CornerRadius = UDim.new(0, 6)
    cc.Parent = b
    b.MouseButton1Click:Connect(cb)
    b.Parent = btnRow
    return b
end

local currentRec = nil

function showDetail(recId)
    for _, rec in ipairs(SS2.log) do
        if rec.id == recId then
            currentRec = rec
            cardTitle.Text = ("CALL #%d — %s"):format(rec.id, rec.name)
            cardBody.Text = ("class: %s\npath: %s\ndir: %s\n\nARGS:\n%s"):format(
                rec.class, rec.path, rec.dir, table.concat(rec.args, "\n"))
            card.Visible = true
            return
        end
    end
end
SS2.showDetail = showDetail

cardClose.MouseButton1Click:Connect(function() card.Visible = false end)

mkBtn("REPLAY", SS2.theme.ACCENT, function()
    if currentRec then SS2.replayId(currentRec.id) end
end)
mkBtn("COPY", SS2.theme.GREEN, function()
    if currentRec and setclipboard then
        setclipboard(table.concat(currentRec.args, ", "))
    end
end)
mkBtn("PRESET", SS2.theme.YELL or Color3.fromRGB(240,190,90), function()
    if currentRec then SS2.savePreset("sgp_" .. currentRec.id, currentRec.id) end
end)
mkBtn("INSPECT", Color3.fromRGB(170, 130, 255), function()
    SS2.inspectLast()
end)

print("[SS2-sgp] click-to-act LIVE — click any feed line")
