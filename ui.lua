-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v3.1 — UI
--  Two tabs. Click anything. Know name/path/args.
--  LIVE CALLS: every call, newest first, searchable
--  REMOTES: ranked list, click for full dossier
--  Requires core.lua.
-- ════════════════════════════════════════════════════════════

print("[SS2-ui] building interface...")

local SS2 = getgenv().SS2
if not SS2 then warn("[SS2-ui] core must load first") return end

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local P = Players.LocalPlayer

-- teardown previous UI generations
pcall(function()
    local root = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
    for _, n in ipairs({ "SS2_Interface", "SS2_Notify" }) do
        local o = root:FindFirstChild(n)
        if o then o:Destroy() end
    end
end)

local T = {
    BG     = Color3.fromRGB(15, 15, 20),
    PANEL  = Color3.fromRGB(24, 24, 32),
    CARD   = Color3.fromRGB(32, 32, 42),
    ACCENT = Color3.fromRGB(88, 140, 255),
    GREEN  = Color3.fromRGB(60, 220, 120),
    RED    = Color3.fromRGB(255, 80, 80),
    YELL   = Color3.fromRGB(240, 190, 90),
    PURP   = Color3.fromRGB(170, 130, 255),
    TEXT   = Color3.fromRGB(235, 235, 240),
    DIM    = Color3.fromRGB(150, 150, 165),
}

local function corner(o, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = o
end
local function stroke(o, col)
    local s = Instance.new("UIStroke")
    s.Color = col or T.ACCENT
    s.Thickness = 1
    s.Parent = o
end

local gui = Instance.new("ScreenGui")
gui.Name = "SS2_Interface"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9999
local okP = pcall(function()
    gui.Parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
end)
if not okP then gui.Parent = P:WaitForChild("PlayerGui") end

-- ═══ MAIN WINDOW ═══
local win = Instance.new("Frame")
win.Size = UDim2.new(0, 480, 0, 380)
win.Position = UDim2.new(0, 30, 0, 50)
win.BackgroundColor3 = T.BG
win.BorderSizePixel = 0
win.Active = true
corner(win, 10)
stroke(win, T.ACCENT)
win.Parent = gui

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 30)
header.BackgroundColor3 = T.PANEL
header.BorderSizePixel = 0
corner(header, 10)
header.Parent = win
local hFill = Instance.new("Frame")
hFill.Size = UDim2.new(1, 0, 0, 12)
hFill.Position = UDim2.new(0, 0, 1, -12)
hFill.BackgroundColor3 = T.PANEL
hFill.BorderSizePixel = 0
hFill.Parent = header

local hTitle = Instance.new("TextLabel")
hTitle.Size = UDim2.new(0, 320, 1, 0)
hTitle.Position = UDim2.new(0, 12, 0, 0)
hTitle.BackgroundTransparency = 1
hTitle.Text = "SIMPLYSPIRITED — " .. SS2.game:sub(1, 18)
hTitle.Font = Enum.Font.GothamBold
hTitle.TextSize = 14
hTitle.TextColor3 = T.TEXT
hTitle.TextXAlignment = Enum.TextXAlignment.Left
hTitle.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 26, 0, 22)
closeBtn.Position = UDim2.new(1, -32, 0, 4)
closeBtn.BackgroundColor3 = T.RED
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.TextColor3 = Color3.new(1, 1, 1)
corner(closeBtn, 6)
closeBtn.Parent = header

-- drag
local dragging, dStart, dPos = false, nil, nil
header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dStart = input.Position
        dPos = win.Position
    end
end)
UIS.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
    or input.UserInputType == Enum.UserInputType.Touch) then
        local d = input.Position - dStart
        win.Position = UDim2.new(dPos.X.Scale, dPos.X.Offset + d.X,
            dPos.Y.Scale, dPos.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function()
    dragging = false
end)
closeBtn.MouseButton1Click:Connect(function()
    gui:Destroy()
    print("[SS2-ui] closed — engine remains")
end)

-- ═══ TABS ═══
local TABS = { "LIVE CALLS", "REMOTES" }
local tabStrip = Instance.new("Frame")
tabStrip.Size = UDim2.new(1, 0, 0, 28)
tabStrip.Position = UDim2.new(0, 0, 0, 30)
tabStrip.BackgroundColor3 = T.PANEL
tabStrip.BorderSizePixel = 0
tabStrip.Parent = win

local tabBtns = {}
local currentTab = 1

-- search bar (LIVE CALLS only)
local searchBar = Instance.new("TextBox")
searchBar.Size = UDim2.new(1, -16, 0, 24)
searchBar.Position = UDim2.new(0, 8, 0, 62)
searchBar.BackgroundColor3 = T.CARD
searchBar.PlaceholderText = "search…"
searchBar.Text = ""
searchBar.Font = Enum.Font.Code
searchBar.TextSize = 12
searchBar.TextColor3 = T.TEXT
searchBar.ClearTextOnFocus = false
corner(searchBar, 6)
searchBar.Parent = win

local content = Instance.new("ScrollingFrame")
content.Size = UDim2.new(1, -16, 1, -96)
content.Position = UDim2.new(0, 8, 0, 90)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ScrollBarThickness = 5
content.ScrollBarImageColor3 = T.ACCENT
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.CanvasSize = UDim2.new(0, 0, 0, 0)
content.Parent = win
local cLayout = Instance.new("UIListLayout")
cLayout.Padding = UDim.new(0, 3)
cLayout.SortOrder = Enum.SortOrder.LayoutOrder
cLayout.Parent = content

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -16, 0, 18)
status.Position = UDim2.new(0, 8, 1, -22)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Code
status.TextSize = 11
status.TextColor3 = T.DIM
status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = ""
status.Parent = win

-- ═══ DETAIL CARD ═══
local card = Instance.new("Frame")
card.Size = UDim2.new(0, 360, 0, 250)
card.Position = UDim2.new(0, 520, 0, 50)
card.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
card.BorderSizePixel = 0
card.Visible = false
card.Active = true
card.Parent = gui
corner(card, 10)
stroke(card, T.ACCENT, 1.5)

local cTitle = Instance.new("TextLabel")
cTitle.Size = UDim2.new(1, -60, 0, 24)
cTitle.Position = UDim2.new(0, 10, 0, 6)
cTitle.BackgroundTransparency = 1
cTitle.Font = Enum.Font.GothamBold
cTitle.TextSize = 13
cTitle.TextColor3 = T.ACCENT
cTitle.TextXAlignment = Enum.TextXAlignment.Left
cTitle.Text = ""
cTitle.Parent = card

local cClose = Instance.new("TextButton")
cClose.Size = UDim2.new(0, 24, 0, 22)
cClose.Position = UDim2.new(1, -30, 0, 5)
cClose.BackgroundColor3 = T.RED
cClose.Text = "X"
cClose.Font = Enum.Font.GothamBold
cClose.TextSize = 12
cClose.TextColor3 = Color3.new(1, 1, 1)
cClose.Parent = card

local cScroll = Instance.new("ScrollingFrame")
cScroll.Size = UDim2.new(1, -16, 1, -94)
cScroll.Position = UDim2.new(0, 8, 0, 32)
cScroll.BackgroundTransparency = 1
cScroll.BorderSizePixel = 0
cScroll.ScrollBarThickness = 4
cScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
cScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
cScroll.Parent = card
local cLayout2 = Instance.new("UIListLayout")
cLayout2.Padding = UDim.new(0, 2)
cLayout2.Parent = cScroll

local cBody = Instance.new("TextLabel")
cBody.Size = UDim2.new(1, 0, 0, 0)
cBody.AutomaticSize = Enum.AutomaticSize.Y
cBody.BackgroundTransparency = 1
cBody.Font = Enum.Font.Code
cBody.TextSize = 11
cBody.TextColor3 = T.TEXT
cBody.TextXAlignment = Enum.TextXAlignment.Left
cBody.TextYAlignment = Enum.TextYAlignment.Top
cBody.TextWrapped = true
cBody.Text = ""
cBody.Parent = cScroll

local cBtnRow = Instance.new("Frame")
cBtnRow.Size = UDim2.new(1, -16, 0, 30)
cBtnRow.Position = UDim2.new(0, 8, 1, -38)
cBtnRow.BackgroundTransparency = 1
cBtnRow.Parent = card
local cBtnLayout = Instance.new("UIListLayout")
cBtnLayout.FillDirection = Enum.FillDirection.Horizontal
cBtnLayout.Padding = UDim.new(0, 6)
cBtnLayout.Parent = cBtnRow

local function cBtn(txt, color, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 78, 1, 0)
    b.BackgroundColor3 = color
    b.Text = txt
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.TextColor3 = Color3.new(1, 1, 1)
    corner(b, 6)
    b.MouseButton1Click:Connect(cb)
    b.Parent = cBtnRow
end

local currentRec = nil
local currentRemote = nil

local function showCallDetail(recId)
    for _, rec in ipairs(SS2.log) do
        if rec.id == recId then
            currentRec = rec
            currentRemote = rec.remote
            cTitle.Text = ("CALL #%d — %s"):format(rec.id, rec.name)
            local body = ("name: %s\nclass: %s\npath: %s\ndir: %s\n\nARGS:\n%s"):format(
                rec.name, rec.class, rec.path, rec.dir, table.concat(rec.args, "\n"))
            -- caller data if available
            local prof = SS2.remotes[rec.remote]
            if prof and prof.callers and next(prof.callers) then
                local cs = {}
                for c, n in pairs(prof.callers) do
                    cs[#cs + 1] = c .. " (" .. n .. "x)"
                end
                body = body .. "\n\nCALLERS:\n  " .. table.concat(cs, "\n  ")
            end
            cBody.Text = body
            card.Visible = true
            return
        end
    end
end

local function showRemoteDetail(r, prof)
    currentRemote = r
    cTitle.Text = "REMOTE — " .. r.Name
    local body = ("name: %s\nclass: %s\npath: %s\ncalls: %d (out %d / in %d)\nhooked: %s | metaCaught: %s"):format(
        r.Name, prof.class, prof.path, prof.calls, prof.out, prof.inn,
        tostring(prof.hooked), tostring(prof.metaCaught or 0))
    local sigs = {}
    for sig, cnt in pairs(prof.sigs) do
        sigs[#sigs + 1] = { s = sig, c = cnt }
    end
    table.sort(sigs, function(a, b) return a.c > b.c end)
    if #sigs > 0 then
        body = body .. "\n\nSIGNATURES (by frequency):"
        for k = 1, math.min(12, #sigs) do
            body = body .. ("\n  [%dx] %s"):format(sigs[k].c, sigs[k].s)
        end
    end
    if prof.callers and next(prof.callers) then
        local cs = {}
        for c, n in pairs(prof.callers) do
            cs[#cs + 1] = c .. " (" .. n .. "x)"
        end
        body = body .. "\n\nCALLERS:\n  " .. table.concat(cs, "\n  ")
    end
    cBody.Text = body
    card.Visible = true
end

cClose.MouseButton1Click:Connect(function() card.Visible = false end)

cBtn("REPLAY", T.ACCENT, function()
    if currentRec then
        SS2.replayId(currentRec.id)
    end
end)
cBtn("COPY", T.GREEN, function()
    if currentRec and setclipboard then
        setclipboard(table.concat(currentRec.args, ", "))
    elseif currentRemote and setclipboard then
        setclipboard(currentRemote:GetFullName())
    end
end)

-- ═══ TAB RENDERERS ═══
local function renderCalls()
    for _, c in ipairs(content:GetChildren()) do
        if c:IsA("TextLabel") or c:IsA("TextButton") then c:Destroy() end
    end
    local term = searchBar.Text:lower()
    local n = 0
    for i = #SS2.log, 1, -1 do
        local rec = SS2.log[i]
        local hay = (rec.name .. " " .. table.concat(rec.args, " ")):lower()
        if term == "" or hay:find(term, 1, true) then
            n = n + 1
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(1, -6, 0, 20)
            b.BackgroundColor3 = T.CARD
            b.BackgroundTransparency = 0.35
            b.Font = Enum.Font.Code
            b.TextSize = 12
            b.TextColor3 = rec.dir == "OUT" and T.GREEN or T.TEXT
            b.TextXAlignment = Enum.TextXAlignment.Left
            b.TextTruncate = Enum.TextTruncate.AtEnd
            b.Text = ("#%d %s %s | %s"):format(
                rec.id, rec.dir, rec.name,
                (rec.args[1] and tostring(rec.args[1]):sub(1, 45)) or "")
            b.LayoutOrder = n
            local pad = Instance.new("UIPadding")
            pad.PaddingLeft = UDim.new(0, 6)
            pad.Parent = b
            local id = rec.id
            b.MouseButton1Click:Connect(function()
                showCallDetail(id)
            end)
            b.Parent = content
            if n > 150 then
                local t = Instance.new("TextLabel")
                t.Size = UDim2.new(1, -6, 0, 18)
                t.BackgroundTransparency = 1
                t.Font = Enum.Font.Code
                t.TextSize = 11
                t.TextColor3 = T.DIM
                t.TextXAlignment = Enum.TextXAlignment.Left
                t.Text = "… (150+ shown — search to narrow)"
                t.LayoutOrder = n + 1
                t.Parent = content
                break
            end
        end
    end
    if n == 0 then
        local t = Instance.new("TextLabel")
        t.Size = UDim2.new(1, -6, 0, 20)
        t.BackgroundTransparency = 1
        t.Font = Enum.Font.Code
        t.TextSize = 12
        t.TextColor3 = T.DIM
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.Text = term ~= "" and ("no matches for '" .. term .. "'") or "(no calls yet — play the game)"
        t.LayoutOrder = 1
        t.Parent = content
    end
end

local function renderRemotes()
    for _, c in ipairs(content:GetChildren()) do
        if c:IsA("TextLabel") or c:IsA("TextButton") then c:Destroy() end
    end
    local ranked = {}
    for r, prof in pairs(SS2.remotes) do
        ranked[#ranked + 1] = { r = r, prof = prof }
    end
    table.sort(ranked, function(a, b) return a.prof.calls > b.prof.calls end)
    for k = 1, math.min(150, #ranked) do
        local e = ranked[k]
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -6, 0, 20)
        b.BackgroundColor3 = T.CARD
        b.BackgroundTransparency = e.prof.calls > 0 and 0.35 or 1
        b.Font = Enum.Font.Code
        b.TextSize = 12
        b.TextColor3 = e.prof.calls > 0 and T.TEXT or T.DIM
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.TextTruncate = Enum.TextTruncate.AtEnd
        b.Text = ("%4d  %-6s %s"):format(e.prof.calls, e.prof.class:sub(1, 6), e.prof.path)
        b.LayoutOrder = k
        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 6)
        pad.Parent = b
        local rr, pp = e.r, e.prof
        b.MouseButton1Click:Connect(function()
            showRemoteDetail(rr, pp)
        end)
        b.Parent = content
    end
end

local renderers = { renderCalls, renderRemotes }

local function switchTab(i)
    currentTab = i
    for j, b in ipairs(tabBtns) do
        b.TextColor3 = (j == i) and T.ACCENT or T.DIM
    end
    searchBar.Visible = (i == 1)
    renderers[i]()
end

for i, name in ipairs(TABS) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 100, 1, 0)
    b.Position = UDim2.new(0, 8 + (i - 1) * 105, 0, 0)
    b.BackgroundTransparency = 1
    b.Text = name
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.TextColor3 = (i == 1) and T.ACCENT or T.DIM
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Parent = tabStrip
    b.MouseButton1Click:Connect(function()
        switchTab(i)
    end)
    tabBtns[i] = b
end

searchBar:GetPropertyChangedSignal("Text"):Connect(function()
    if currentTab == 1 then renderCalls() end
end)

-- refresh loop: LIVE CALLS auto-updates when search is empty
task.spawn(function()
    while gui.Parent do
        if currentTab == 1 and searchBar.Text == "" then
            pcall(renderCalls)
        end
        local rc = 0
        for _ in pairs(SS2.remotes) do rc = rc + 1 end
        status.Text = ("remotes: %d · calls: %d · net: %s"):format(
            rc, #SS2.log, tostring(SS2.metaHooked))
        task.wait(1)
    end
end)

switchTab(1)

SS2.gui = gui
print("[SS2-ui] interface LIVE — click any call or remote")
