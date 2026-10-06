-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v4.5 — MINIMAL BLACK, FINAL
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  Black. Text. One red marker. Zero decoration.
--  Tabs: calls / remotes / decomp / tools
-- ════════════════════════════════════════════════════════════

print("[SS2-ui] v4.5 loading...")

local SS2 = getgenv().SS2
if not SS2 then warn("[SS2-ui] core must load first") return end

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local P = Players.LocalPlayer

pcall(function()
    local root = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
    for _, n in ipairs({ "SS2_Interface", "SS2_Notify" }) do
        local o = root:FindFirstChild(n)
        if o then o:Destroy() end
    end
end)

local T = {
    BG   = Color3.fromRGB(8, 8, 8),
    RAIL = Color3.fromRGB(13, 13, 13),
    TEXT = Color3.fromRGB(215, 215, 215),
    DIM  = Color3.fromRGB(100, 100, 100),
    RED  = Color3.fromRGB(200, 40, 50),
}
SS2.theme = T

local gui = Instance.new("ScreenGui")
gui.Name = "SS2_Interface"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9999
local okP = pcall(function()
    gui.Parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
end)
if not okP then gui.Parent = P:WaitForChild("PlayerGui") end

-- ═══ detail functions first ═══
local clearMain, mainLine

local function showCallDetail(recId)
    for _, rec in ipairs(SS2.log) do
        if rec.id == recId then
            clearMain()
            mainLine("call #" .. rec.id .. " — " .. rec.name, T.TEXT, 1)
            mainLine(rec.path, T.DIM, 2)
            mainLine("", T.DIM, 3)
            for i, a in ipairs(rec.args) do
                mainLine("  " .. i .. "  " .. a, T.TEXT, 3 + i)
            end
            local prof = SS2.remotes[rec.remote]
            if prof and prof.callers and next(prof.callers) then
                local cs, n = {}, 0
                for c, cnt in pairs(prof.callers) do cs[#cs + 1] = { c = c, n = cnt } end
                table.sort(cs, function(a, b) return a.n > b.n end)
                mainLine("", T.DIM, 30)
                mainLine("callers", T.DIM, 31)
                for k, e in ipairs(cs) do
                    mainLine("  " .. e.c .. " x" .. e.n, T.DIM, 31 + k)
                end
            end
            return
        end
    end
end

local function showRemoteDetail(r, prof)
    clearMain()
    mainLine("remote — " .. r.Name, T.TEXT, 1)
    mainLine(prof.path or "?", T.DIM, 2)
    mainLine("calls " .. prof.calls .. " · out " .. prof.out .. " · in " .. prof.inn, T.DIM, 3)
    mainLine("net-caught " .. tostring(prof.metaCaught or 0), T.DIM, 4)
    local sigs = {}
    for sig, cnt in pairs(prof.sigs) do
        sigs[#sigs + 1] = { s = sig, c = cnt }
    end
    table.sort(sigs, function(a, b) return a.c > b.c end)
    if #sigs > 0 then
        mainLine("", T.DIM, 5)
        mainLine("signatures", T.DIM, 6)
        for k = 1, math.min(24, #sigs) do
            mainLine("  " .. sigs[k].c .. "x  " .. sigs[k].s, T.TEXT, 6 + k)
        end
    end
    if prof.callers and next(prof.callers) then
        local cs = {}
        for c, n in pairs(prof.callers) do cs[#cs + 1] = { c = c, n = n } end
        table.sort(cs, function(a, b) return a.n > b.n end)
        mainLine("", T.DIM, 32)
        mainLine("callers", T.DIM, 33)
        for k, e in ipairs(cs) do
            mainLine("  " .. e.c .. " x" .. e.n, T.DIM, 33 + k)
        end
    end
end

-- ═══ WINDOW ═══
local win = Instance.new("Frame")
win.Size = UDim2.new(0, 420, 0, 280)
win.Position = UDim2.new(0, 30, 0, 40)
win.BackgroundColor3 = T.BG
win.BorderSizePixel = 0
win.Active = true
win.Parent = gui

-- ═══ HEADER ═══
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 22)
header.BackgroundColor3 = T.RAIL
header.BorderSizePixel = 0
header.Parent = win

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0, 200, 1, 0)
title.Position = UDim2.new(0, 8, 0, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.Code
title.TextSize = 11
title.TextColor3 = T.TEXT
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "simplyspirited"
title.Parent = header

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 18, 1, 0)
minBtn.Position = UDim2.new(1, -40, 0, 0)
minBtn.BackgroundTransparency = 1
minBtn.Text = "_"
minBtn.Font = Enum.Font.Code
minBtn.TextSize = 12
minBtn.TextColor3 = T.DIM
minBtn.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 18, 1, 0)
closeBtn.Position = UDim2.new(1, -22, 0, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "x"
closeBtn.Font = Enum.Font.Code
closeBtn.TextSize = 12
closeBtn.TextColor3 = T.DIM
closeBtn.Parent = header

local fullSize = UDim2.new(0, 420, 0, 280)
local minSize = UDim2.new(0, 420, 0, 22)
local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    win.Size = minimized and minSize or fullSize
end)
closeBtn.MouseButton1Click:Connect(function()
    gui:Destroy()
end)

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

-- ═══ TABS + PERSISTENT UNDERLINE ═══
local TABS = { "calls", "remotes", "decomp", "tools" }
local tabStrip = Instance.new("Frame")
tabStrip.Size = UDim2.new(1, 0, 0, 20)
tabStrip.Position = UDim2.new(0, 0, 0, 22)
tabStrip.BackgroundColor3 = T.BG
tabStrip.BorderSizePixel = 0
tabStrip.Parent = win

local tabBtns = {}
local currentTab = 1
local tabRenderers

local underline = Instance.new("Frame")
underline.BackgroundColor3 = T.RED
underline.BorderSizePixel = 0
underline.Size = UDim2.new(0, 52, 0, 2)
underline.Position = UDim2.new(0, 4, 1, -2)
underline.Parent = tabStrip

local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(1, -270, 0, 15)
searchBox.Position = UDim2.new(0, 260, 0, 2)
searchBox.BackgroundTransparency = 1
searchBox.PlaceholderText = "grep"
searchBox.Text = ""
searchBox.Font = Enum.Font.Code
searchBox.TextSize = 10
searchBox.TextColor3 = T.TEXT
searchBox.PlaceholderColor3 = T.DIM
searchBox.ClearTextOnFocus = false
searchBox.TextXAlignment = Enum.TextXAlignment.Left
searchBox.Parent = tabStrip

-- ═══ SIDEBAR (with depth-padding) ═══
local sidebar = Instance.new("ScrollingFrame")
sidebar.Size = UDim2.new(0, 150, 1, -42)
sidebar.Position = UDim2.new(0, 0, 0, 42)
sidebar.BackgroundColor3 = T.RAIL
sidebar.BorderSizePixel = 0
sidebar.ScrollBarThickness = 2
sidebar.ScrollBarImageColor3 = T.DIM
sidebar.AutomaticCanvasSize = Enum.AutomaticSize.Y
sidebar.CanvasSize = UDim2.new(0, 0, 0, 0)
sidebar.Parent = win
local sbLayout = Instance.new("UIListLayout")
sbLayout.SortOrder = Enum.SortOrder.LayoutOrder
sbLayout.Parent = sidebar

-- ═══ MAIN PANE ═══
local mainPanel = Instance.new("ScrollingFrame")
mainPanel.Size = UDim2.new(1, -156, 1, -58)
mainPanel.Position = UDim2.new(0, 156, 0, 42)
mainPanel.BackgroundColor3 = T.BG
mainPanel.BorderSizePixel = 0
mainPanel.ScrollBarThickness = 2
mainPanel.ScrollBarImageColor3 = T.DIM
mainPanel.AutomaticCanvasSize = Enum.AutomaticSize.Y
mainPanel.CanvasSize = UDim2.new(0, 0, 0, 0)
mainPanel.Parent = win
local mpLayout = Instance.new("UIListLayout")
mpLayout.Padding = UDim.new(0, 1)
mpLayout.SortOrder = Enum.SortOrder.LayoutOrder
mpLayout.Parent = mainPanel

function clearMain()
    for _, c in ipairs(mainPanel:GetChildren()) do
        if c:IsA("TextLabel") or c:IsA("TextButton") then c:Destroy() end
    end
end

function mainLine(txt, color, order)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -8, 0, 14)
    l.Position = UDim2.new(0, 5, 0, 0)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Code
    l.TextSize = 11
    l.TextColor3 = color or T.TEXT
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Text = txt
    l.LayoutOrder = order
    l.Parent = mainPanel
    return l
end

-- ═══ SIDEBAR ROWS (depth-aware padding) ═══
local sideRows = {}
local selectedRow = nil
local function sideRow(txt, color, order, recId, remoteRef, profRef, depth)
    depth = depth or 0
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 15)
    b.BackgroundColor3 = T.RAIL
    b.BorderSizePixel = 0
    b.Font = Enum.Font.Code
    b.TextSize = 10
    b.TextColor3 = color or T.TEXT
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.TextTruncate = Enum.TextTruncate.AtEnd
    b.Text = string.rep("  ", depth) .. txt
    b.LayoutOrder = order
    b.MouseButton1Click:Connect(function()
        if selectedRow then
            selectedRow.TextColor3 = selectedRow:GetAttribute("base")
        end
        selectedRow = b
        b:SetAttribute("base", color)
        b.TextColor3 = T.RED
        if recId then
            showCallDetail(recId)
        elseif remoteRef and profRef then
            showRemoteDetail(remoteRef, profRef)
        end
    end)
    b.Parent = sidebar
    sideRows[#sideRows + 1] = b
    return b
end

local function clearSidebar()
    for _, r in ipairs(sideRows) do
        pcall(function() r:Destroy() end)
    end
    sideRows = {}
    selectedRow = nil
end

-- ═══ ACTION RAIL: clickable verb strip ═══
local btnRail = Instance.new("Frame")
btnRail.Size = UDim2.new(0, 150, 0, 24)
btnRail.Position = UDim2.new(0, 0, 1, -24)
btnRail.BackgroundColor3 = T.RAIL
btnRail.BorderSizePixel = 0
btnRail.Parent = win

local railText = Instance.new("TextLabel")
railText.Size = UDim2.new(1, -8, 1, 0)
railText.Position = UDim2.new(0, 4, 0, 0)
railText.BackgroundTransparency = 1
railText.Font = Enum.Font.Code
railText.TextSize = 9
railText.TextColor3 = T.DIM
railText.TextXAlignment = Enum.TextXAlignment.Left
railText.Text = "replay copy preset inspect | apidoc dump export clear"
railText.TextTruncate = Enum.TextTruncate.AtEnd
railText.Parent = btnRail

-- click zones over the verb words
local verbs = {
    { w = 34, fn = function()
        if selectedCallId then SS2.replayId(selectedCallId) end
    end },
    { w = 28, fn = function()
        if selectedCallId and setclipboard then
            for _, rec in ipairs(SS2.log) do
                if rec.id == selectedCallId then
                    setclipboard(table.concat(rec.args, ", "))
                end
            end
        end
    end },
    { w = 36, fn = function()
        if selectedCallId then SS2.savePreset("t_" .. selectedCallId, selectedCallId) end
    end },
    { w = 42, fn = function() SS2.inspectLast() end },
    { w = 40, fn = function() SS2.generateAPIDoc() end },
    { w = 32, fn = function() SS2.dumpAll() end },
    { w = 40, fn = function() SS2.exportAll() end },
    { w = 34, fn = function()
        SS2.log = {}
        switchTab(currentTab)
    end },
}
local vx = 4
for _, v in ipairs(verbs) do
    local z = Instance.new("TextButton")
    z.Size = UDim2.new(0, v.w, 1, 0)
    z.Position = UDim2.new(0, vx, 0, 0)
    z.BackgroundTransparency = 1
    z.Text = ""
    z.Parent = btnRail
    z.MouseButton1Click:Connect(v.fn)
    vx = vx + v.w + 2
end

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -156, 0, 14)
status.Position = UDim2.new(0, 162, 1, -14)
status.BackgroundColor3 = T.BG
status.BorderSizePixel = 0
status.Font = Enum.Font.Code
status.TextSize = 10
status.TextColor3 = T.DIM
status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = "v4.5"
status.Parent = win

-- ═══ RENDERERS ═══
local searchCtx = ""

local function renderCalls()
    clearSidebar()
    local n = 0
    for i = #SS2.log, 1, -1 do
        local rec = SS2.log[i]
        local hay = (rec.name .. " " .. table.concat(rec.args, " ")):lower()
        if searchCtx == "" or hay:find(searchCtx, 1, true) then
            n = n + 1
            sideRow(("#%d %s %s"):format(rec.id, rec.dir, rec.name):sub(1, 26),
                rec.dir == "OUT" and T.TEXT or T.DIM, n, rec.id, nil, nil)
            if n > 90 then break end
        end
    end
    if selectedCallId then
        showCallDetail(selectedCallId)
    elseif #SS2.log > 0 then
        showCallDetail(SS2.log[#SS2.log].id)
    else
        clearMain()
        mainLine("no traffic", T.DIM, 1)
    end
end

local function renderRemotes()
    clearSidebar()
    local ranked = {}
    for r, prof in pairs(SS2.remotes) do
        ranked[#ranked + 1] = { r = r, prof = prof }
    end
    table.sort(ranked, function(a, b) return a.prof.calls > b.prof.calls end)
    for k = 1, math.min(120, #ranked) do
        local e = ranked[k]
        sideRow(("x%-4d %s"):format(e.prof.calls, e.r.Name:sub(1, 16)),
            e.prof.calls > 0 and T.TEXT or T.DIM, k, nil, e.r, e.prof)
    end
end

local decompSel = nil
local function renderDecomp()
    clearSidebar()
    -- containers at depth 0
    local containers = { "ReplicatedStorage", "StarterPlayer", "Players", "workspace" }
    for i, cname in ipairs(containers) do
        local b = sideRow((decompSel == cname and "+ " or "  ") .. cname:sub(1, 16),
            decompSel == cname and T.RED or T.TEXT, i)
        b.MouseButton1Click:Connect(function()
            decompSel = cname
            renderDecomp()
        end)
    end
    clearMain()
    mainLine("decompiler — 6 layers", T.TEXT, 1)
    mainLine("source / bytecode / constants", T.DIM, 2)
    mainLine("structure / cross-ref / report", T.DIM, 3)
    mainLine("", T.DIM, 4)
    mainLine("target: " .. (decompSel or "(select in rail)"), T.TEXT, 5)
    mainLine("caps: src=" .. tostring(SS2.decomp.caps and SS2.decomp.caps.source)
        .. " bc=" .. tostring(SS2.decomp.caps and SS2.decomp.caps.bytecode), T.DIM, 6)
    mainLine("", T.DIM, 7)
    -- decomp verbs as depth-1 rows
    local i = 8
    local function dAction(txt, cb)
        i = i + 1
        local b = sideRow("  " .. txt, T.DIM, i)
        b.MouseButton1Click:Connect(function()
            cb()
            b.TextColor3 = T.TEXT
            task.delay(0.3, function()
                if b.Parent then b.TextColor3 = T.DIM end
            end)
        end)
    end
    dAction("quick pass (config/main/init)", function()
        if SS2.decomp.quick then SS2.decomp.quick() end
    end)
    dAction("bulk dump — selected (200)", function()
        if decompSel and SS2.decomp.bulk then
            SS2.decomp.bulk(decompSel, 200)
            mainLine("bulk dumping " .. decompSel .. " — console has progress", T.TEXT, 9)
        end
    end)
    dAction("script tree (console)", function()
        if SS2.decomp.tree then SS2.decomp.tree(decompSel or "ReplicatedStorage") end
    end)
    mainLine("", T.DIM, i + 1)
    mainLine("output: SimplySpirited/decomp/", T.DIM, i + 2)
end

local function renderTools()
    clearSidebar()
    local i = 0
    local function sBtn(txt, cb)
        i = i + 1
        local b = sideRow("  " .. txt, T.DIM, i)
        b.MouseButton1Click:Connect(cb)
    end
    sideRow("tools", T.TEXT, 0)
    sBtn("api doc", function() SS2.generateAPIDoc() end)
    sBtn("master dump", function() SS2.dumpAll() end)
    sBtn("audit", function() SS2.dumpAudit() end)
    sBtn("dossiers", function() SS2.dumpPerRemote() end)
    sBtn("export all", function() SS2.exportAll() end)
    sBtn("manifest", function() SS2.vaultManifest() end)
    sBtn("stealth on/off", function()
        if SS2.stealth.active then SS2.stealthOff() else SS2.stealthOn() end
    end)
    sBtn("summary", function() print(SS2.vaultSummary()) end)
    clearMain()
    mainLine("tools — select from rail", T.DIM, 1)
end

tabRenderers = { renderCalls, renderRemotes, renderDecomp, renderTools }
local function switchTab(i)
    currentTab = i
    for j, b in ipairs(tabBtns) do
        b.TextColor3 = (j == i) and T.TEXT or T.DIM
    end
    underline.Position = UDim2.new(0, 4 + (i - 1) * 56, 1, -2)
    searchBox.Visible = (i == 1)
    tabRenderers[i]()
end

for i, name in ipairs(TABS) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 52, 1, 0)
    b.Position = UDim2.new(0, 4 + (i - 1) * 56, 0, 0)
    b.BackgroundTransparency = 1
    b.Text = name
    b.Font = Enum.Font.Code
    b.TextSize = 10
    b.TextColor3 = (i == 1) and T.TEXT or T.DIM
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Parent = tabStrip
    b.MouseButton1Click:Connect(function()
        switchTab(i)
    end)
    tabBtns[i] = b
end

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    searchCtx = searchBox.Text:lower()
    if currentTab == 1 then renderCalls() end
end)

task.spawn(function()
    while gui.Parent do
        if currentTab == 1 and searchCtx == "" and not minimized then
            renderCalls()
        end
        local rc = 0
        for _ in pairs(SS2.remotes) do rc = rc + 1 end
        status.Text = "v4.5 · " .. rc .. " remotes · " .. #SS2.log .. " calls · net " .. tostring(SS2.metaHooked)
        task.wait(1)
    end
end)

switchTab(1)

SS2.gui = gui
print("[SS2-ui] v4.5 minimal — live")
