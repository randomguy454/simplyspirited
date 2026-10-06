--[[
    simplyspirited v4.6 — universal remote surveillance
    SHADOWMILESC / computerizedcarrier2

    design notes, for whoever reads this (probably me):
    - everything is monospace because this is a terminal, not a dashboard
    - red is used for exactly one thing: what you have selected. nothing
      else in the ui is allowed to be red. this was a fight. it won.
    - feed freezes when you select something. click it again to go live.
      people kept losing their selection to the autorefresh and blamed
      the tool. they were right.
    - the verb rail at the bottom is deliberately text, not buttons.
      buttons invite buttons. words invite reading.
]]

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local P = Players.LocalPlayer

local SS2 = getgenv().SS2
if not SS2 then
    warn("ss2: core.lua must load before ui")
    return
end

-- kill previous ui instances (re-exec support)
pcall(function()
    local root = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
    local old = root:FindFirstChild("SS2_Interface")
    if old then old:Destroy() end
end)

-- ────────────────────────────────────────────────────────────
-- palette. four colors. arguing with myself about a fifth.
-- ────────────────────────────────────────────────────────────
local C_bg    = Color3.fromRGB(9, 9, 9)
local C_rail  = Color3.fromRGB(14, 14, 14)
local C_text  = Color3.fromRGB(210, 210, 210)
local C_dim   = Color3.fromRGB(98, 98, 98)
local C_red   = Color3.fromRGB(198, 38, 48)

-- ═══ root ═══
local gui = Instance.new("ScreenGui")
gui.Name = "SS2_Interface"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9999
do
    local ok = pcall(function()
        gui.Parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
    end)
    if not ok then gui.Parent = P:WaitForChild("PlayerGui") end
end

local win = Instance.new("Frame")
win.Size = UDim2.fromOffset(420, 280)
win.Position = UDim2.fromOffset(30, 40)
win.BackgroundColor3 = C_bg
win.BorderSizePixel = 0
win.Active = true
win.Parent = gui

-- ═══ header: the drag handle, doubles as identity ═══
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 20)
header.BackgroundColor3 = C_rail
header.BorderSizePixel = 0
header.Parent = win

local hTitle = Instance.new("TextLabel")
hTitle.Size = UDim2.new(0, 200, 1, 0)
hTitle.Position = UDim2.fromOffset(7, 0)
hTitle.BackgroundTransparency = 1
hTitle.Font = Enum.Font.Code
hTitle.TextSize = 11
hTitle.TextColor3 = C_text
hTitle.TextXAlignment = Enum.TextXAlignment.Left
hTitle.Text = "simplyspirited"
hTitle.Parent = header

local hGame = Instance.new("TextLabel")
hGame.Size = UDim2.new(0, 140, 1, 0)
hGame.Position = UDim2.new(0, 130, 0, 0)
hGame.BackgroundTransparency = 1
hGame.Font = Enum.Font.Code
hGame.TextSize = 10
hGame.TextColor3 = C_dim
hGame.TextXAlignment = Enum.TextXAlignment.Left
hGame.TextTruncate = Enum.TextTruncate.AtEnd
hGame.Text = SS2.game:sub(1, 22)
hGame.Parent = header

local hMin = Instance.new("TextButton")
hMin.Size = UDim2.fromOffset(16, 20)
hMin.Position = UDim2.new(1, -38, 0, 0)
hMin.BackgroundTransparency = 1
hMin.Font = Enum.Font.Code
hMin.TextSize = 12
hMin.TextColor3 = C_dim
hMin.Text = "_"
hMin.Parent = header

local hClose = Instance.new("TextButton")
hClose.Size = UDim2.fromOffset(16, 20)
hClose.Position = UDim2.new(1, -20, 0, 0)
hClose.BackgroundTransparency = 1
hClose.Font = Enum.Font.Code
hClose.TextSize = 12
hClose.TextColor3 = C_dim
hClose.Text = "x"
hClose.Parent = header

-- drag impl. standard. works on touch. moving on.
local dragOn, dragStart, dragPos
header.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        dragOn = true
        dragStart = i.Position
        dragPos = win.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragOn and (i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dragStart
        win.Position = UDim2.new(dragPos.X.Scale, dragPos.X.Offset + d.X,
            dragPos.Y.Scale, dragPos.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function()
    dragOn = false
end)

local wFull, wMin = UDim2.fromOffset(420, 280), UDim2.fromOffset(420, 20)
local minimized = false
hMin.MouseButton1Click:Connect(function()
    minimized = not minimized
    win.Size = minimized and wMin or wFull
end)
hClose.MouseButton1Click:Connect(function()
    gui:Destroy()
end)

-- ═══ detail pane functions.
-- declared before the sidebar uses them (learned this the hard
-- way — v4.2 had a nil-call here that ate remote clicks)
-- ═══
local clearMain, tLine -- forward decls, defined after mainPanel

local function showCallDetail(id)
    for _, rec in ipairs(SS2.log) do
        if rec.id == id then
            clearMain()
            tLine(("call #%d  %s"):format(id, rec.name), C_text, 1)
            tLine(rec.path, C_dim, 2)
            tLine("", C_dim, 3)
            for i, a in ipairs(rec.args) do
                tLine(("  %d  %s"):format(i, a), C_text, 3 + i)
            end
            local prof = SS2.remotes[rec.remote]
            if prof and prof.callers and next(prof.callers) then
                local cs = {}
                for c, n in pairs(prof.callers) do cs[#cs+1] = { c=c, n=n } end
                table.sort(cs, function(a,b) return a.n > b.n end)
                tLine("", C_dim, 29)
                tLine("callers", C_dim, 30)
                for k, e in ipairs(cs) do
                    tLine(("  %s x%d"):format(e.c, e.n), C_dim, 30 + k)
                end
            end
            return
        end
    end
end

local function showRemoteDetail(r, prof)
    clearMain()
    tLine("remote  " .. r.Name, C_text, 1)
    tLine(prof.path or "?", C_dim, 2)
    tLine(("calls %d  out %d  in %d"):format(prof.calls, prof.out, prof.inn), C_dim, 3)
    if (prof.metaCaught or 0) > 0 then
        tLine("net-caught " .. prof.metaCaught, C_dim, 4)
    end
    local sigs = {}
    for s, n in pairs(prof.sigs) do sigs[#sigs+1] = { s=s, n=n } end
    table.sort(sigs, function(a,b) return a.n > b.n end)
    if #sigs > 0 then
        tLine("", C_dim, 5)
        tLine("signatures", C_dim, 6)
        for k = 1, math.min(24, #sigs) do
            tLine(("  x%d  %s"):format(sigs[k].n, sigs[k].s), C_text, 6 + k)
        end
    end
    if prof.callers and next(prof.callers) then
        local cs = {}
        for c, n in pairs(prof.callers) do cs[#cs+1] = { c=c, n=n } end
        table.sort(cs, function(a,b) return a.n > b.n end)
        tLine("", C_dim, 32)
        tLine("callers", C_dim, 33)
        for k, e in ipairs(cs) do
            tLine(("  %s x%d"):format(e.c, e.n), C_dim, 33 + k)
        end
    end
end

-- ═══ tabs. underline is the only red in the whole ui. ═══
local TABS = { "calls", "remotes", "decomp", "tools" }
local tabStrip = Instance.new("Frame")
tabStrip.Size = UDim2.new(1, 0, 0, 18)
tabStrip.Position = UDim2.new(0, 0, 0, 20)
tabStrip.BackgroundColor3 = C_rail
tabStrip.BorderSizePixel = 0
tabStrip.Parent = win

local tabBtns = {}
local curTab = 1
local renderers

local underline = Instance.new("Frame")
underline.BackgroundColor3 = C_red
underline.BorderSizePixel = 0
underline.Size = UDim2.fromOffset(48, 2)
underline.Position = UDim2.fromOffset(4, 16)
underline.Parent = tabStrip

-- grep box lives in the tab strip, right-aligned. it's only
-- relevant on calls; hidden elsewhere.
local grepBox = Instance.new("TextBox")
grepBox.Size = UDim2.new(0, 130, 0, 14)
grepBox.Position = UDim2.new(1, -136, 0, 2)
grepBox.BackgroundTransparency = 1
grepBox.Font = Enum.Font.Code
grepBox.TextSize = 10
grepBox.TextColor3 = C_text
grepBox.PlaceholderColor3 = C_dim
grepBox.PlaceholderText = "grep"
grepBox.Text = ""
grepBox.ClearTextOnFocus = false
grepBox.TextXAlignment = Enum.TextXAlignment.Left
grepBox.Parent = tabStrip

-- ═══ sidebar (130px) ═══
local sidebar = Instance.new("ScrollingFrame")
sidebar.Size = UDim2.new(0, 130, 1, -52)
sidebar.Position = UDim2.fromOffset(0, 38)
sidebar.BackgroundColor3 = C_rail
sidebar.BorderSizePixel = 0
sidebar.ScrollBarThickness = 2
sidebar.ScrollBarImageColor3 = C_dim
sidebar.AutomaticCanvasSize = Enum.AutomaticSize.Y
sidebar.CanvasSize = UDim2.new(0, 0, 0, 0)
sidebar.Parent = win
Instance.new("UIListLayout", sidebar).SortOrder = Enum.SortOrder.LayoutOrder

-- ═══ main pane ═══
local mainPanel = Instance.new("ScrollingFrame")
mainPanel.Size = UDim2.new(1, -136, 1, -52)
mainPanel.Position = UDim2.fromOffset(136, 38)
mainPanel.BackgroundColor3 = C_bg
mainPanel.BorderSizePixel = 0
mainPanel.ScrollBarThickness = 2
mainPanel.ScrollBarImageColor3 = C_dim
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

function tLine(txt, col, order, depth)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -8, 0, 13)
    l.Position = UDim2.fromOffset(5 + (depth or 0) * 10, 0)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Code
    l.TextSize = 10
    l.TextColor3 = col or C_text
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Text = txt
    l.LayoutOrder = order
    l.Parent = mainPanel
    return l
end

-- ═══ verb rail: words, not buttons ═══
local rail = Instance.new("Frame")
rail.Size = UDim2.new(0, 130, 0, 14)
rail.Position = UDim2.new(0, 0, 1, -14)
rail.BackgroundColor3 = C_rail
rail.BorderSizePixel = 0
rail.Parent = win

local railTxt = Instance.new("TextLabel")
railTxt.Size = UDim2.new(1, -6, 1, 0)
railTxt.Position = UDim2.fromOffset(3, 0)
railTxt.BackgroundTransparency = 1
railTxt.Font = Enum.Font.Code
railTxt.TextSize = 8
railTxt.TextColor3 = C_dim
railTxt.TextXAlignment = Enum.TextXAlignment.Left
railTxt.TextTruncate = Enum.TextTruncate.AtEnd
railTxt.Text = "replay copy preset inspect apidoc dump export clear"
railTxt.Parent = rail

-- hit zones over the words (measured against the string above)
local verbs = {
    { x = 3,  w = 24, fn = function()
        local last = SS2.log[#SS2.log]
        -- replay what you most recently SELECTED, not the newest —
        -- nothing is selected after the clear in Clr Logs, so this
        -- falls back to newest. deliberate.
        if selectedCallId then SS2.replayId(selectedCallId)
        elseif last then SS2.replayId(last.id) end
    end },
    { x = 29, w = 22, fn = function()
        local rec = selectedCallId and (function()
            for _, r in ipairs(SS2.log) do if r.id == selectedCallId then return r end end
        end)()
        if rec and setclipboard then setclipboard(table.concat(rec.args, ", ")) end
    end },
    { x = 53, w = 26, fn = function()
        if selectedCallId then SS2.savePreset("u" .. selectedCallId, selectedCallId) end
    end },
    { x = 81, w = 30, fn = function() if SS2.inspectLast then SS2.inspectLast() end end },
    { x = 113, w = 24, fn = function() if SS2.generateAPIDoc then SS2.generateAPIDoc() end end },
    { x = 3,  w = 22, fn = function() if SS2.dumpAll then SS2.dumpAll() end end, y = 0 },
}
-- note: rail shows one line; dump/export/clear live in the TOOLS
-- tab instead to keep the rail honest. the two unused zones above
-- are kept for hit-testing only if width allows. acceptable.

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -136, 0, 14)
status.Position = UDim2.fromOffset(136, 0)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Code
status.TextSize = 9
status.TextColor3 = C_dim
status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = ""
status.Parent = rail

-- ═══ selection state ═══
-- pinned = feed follows newest. any selection unpins. clicking
-- the selected row again re-pins. this is the whole UX contract.
local pinned = true
local selectedCallId = nil
local selectedRemote = nil
local selRow = nil

local sideRows = {}
local function sideRow(txt, col, order, onPick, depth)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 14)
    b.BackgroundColor3 = C_rail
    b.BorderSizePixel = 0
    b.Font = Enum.Font.Code
    b.TextSize = 10
    b.TextColor3 = col or C_text
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.TextTruncate = Enum.TextTruncate.AtEnd
    b.Text = string.rep(" ", (depth or 0) * 2) .. txt
    b.LayoutOrder = order
    b.MouseButton1Click:Connect(function()
        if selRow == b then
            -- re-click = release, go live
            b.TextColor3 = b:GetAttribute("base") or C_text
            selRow = nil
            selectedCallId = nil
            selectedRemote = nil
            pinned = true
            return
        end
        if selRow then selRow.TextColor3 = selRow:GetAttribute("base") or C_text end
        selRow = b
        b:SetAttribute("base", col)
        b.TextColor3 = C_red
        pinned = false
        if onPick then onPick() end
    end)
    b.Parent = sidebar
    sideRows[#sideRows + 1] = b
    return b
end

local function clearSidebar()
    for _, r in ipairs(sideRows) do pcall(function() r:Destroy() end) end
    sideRows = {}
    selRow = nil
end

-- ═══ renderers ═══
local grepCtx = ""

local function renderCalls()
    clearSidebar()
    local n = 0
    for i = #SS2.log, 1, -1 do
        local rec = SS2.log[i]
        local hay = (rec.name .. " " .. table.concat(rec.args, " ")):lower()
        if grepCtx == "" or hay:find(grepCtx, 1, true) then
            n = n + 1
            local id = rec.id
            sideRow(("#%d %s %s"):format(id, rec.dir, rec.name):sub(1, 26),
                rec.dir == "OUT" and C_text or C_dim, n, function()
                selectedCallId = id
                showCallDetail(id)
            end)
            if n > 90 then break end
        end
    end
    if selectedCallId then
        showCallDetail(selectedCallId)
    elseif #SS2.log > 0 then
        showCallDetail(SS2.log[#SS2.log].id)
    else
        clearMain()
        tLine("-- no traffic. play the game.", C_dim, 1)
    end
end

local function renderRemotes()
    clearSidebar()
    local ranked = {}
    for r, prof in pairs(SS2.remotes) do
        ranked[#ranked+1] = { r=r, p=prof }
    end
    table.sort(ranked, function(a,b) return a.p.calls > b.p.calls end)
    for k = 1, math.min(120, #ranked) do
        local e = ranked[k]
        local rr, pp = e.r, e.p
        sideRow(("x%-4d %s"):format(pp.calls, rr.Name:sub(1, 15)),
            pp.calls > 0 and C_text or C_dim, k, function()
            selectedRemote = rr
            showRemoteDetail(rr, pp)
        end)
    end
end

local function renderDecomp()
    clearSidebar()
    if not (SS2.decomp and SS2.decomp.caps) then
        tLine("decomp.lua not loaded", C_dim, 1)
        return
    end
    local sel = SS2._dcontainer or "ReplicatedStorage"
    -- containers
    local containers = { "ReplicatedStorage", "StarterPlayer", "Players", "workspace" }
    for i, cname in ipairs(containers) do
        local mark = (sel == cname) and "x " or "  "
        local b = sideRow(mark .. cname, sel == cname and C_red or C_dim, i, function()
            SS2._dcontainer = cname
            renderDecomp()
        end)
    end
    clearMain()
    tLine("decompiler — 6 layers", C_text, 1)
    tLine(("caps: source=%s bytecode=%s"):format(
        tostring(SS2.decomp.caps.source), tostring(SS2.decomp.caps.bytecode)), C_dim, 2)
    tLine("target: " .. sel, C_dim, 3)
    tLine("", C_dim, 4)
    local i = 5
    local function act(txt, fn)
        i = i + 1
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -8, 0, 13)
        b.Position = UDim2.fromOffset(5, 0)
        b.BackgroundTransparency = 1
        b.Font = Enum.Font.Code
        b.TextSize = 10
        b.TextColor3 = C_dim
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.Text = "  " .. txt
        b.LayoutOrder = i
        b.MouseButton1Click:Connect(function()
            fn()
            b.TextColor3 = C_text
            task.delay(0.25, function()
                if b.Parent then b.TextColor3 = C_dim end
            end)
        end)
        b.Parent = mainPanel
    end
    act("quick — config/main/init scripts", function()
        if SS2.decomp.quick then SS2.decomp.quick() end
    end)
    act("bulk dump (200 scripts)", function()
        if SS2.decomp.bulk then SS2.decomp.bulk(sel, 200) end
    end)
    act("script tree", function()
        if SS2.decomp.tree then SS2.decomp.tree(sel) end
    end)
    tLine("", C_dim, i + 2)
    tLine("out: SimplySpirited/decomp/", C_dim, i + 3)
    tLine("xrf = script references a remote we saw fire", C_dim, i + 4)
end

local function renderTools()
    clearSidebar()
    tLine("tools", C_text, 1)
    tLine("", C_dim, 2)
    local i = 3
    local function act(txt, fn)
        i = i + 1
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -8, 0, 13)
        b.Position = UDim2.fromOffset(5, 0)
        b.BackgroundTransparency = 1
        b.Font = Enum.Font.Code
        b.TextSize = 10
        b.TextColor3 = C_dim
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.Text = "  " .. txt
        b.LayoutOrder = i
        b.MouseButton1Click:Connect(function()
            fn()
            b.TextColor3 = C_text
            task.delay(0.25, function()
                if b.Parent then b.TextColor3 = C_dim end
            end)
        end)
        b.Parent = mainPanel
    end
    act("api documentation", function() if SS2.generateAPIDoc then SS2.generateAPIDoc() end end)
    act("master dump", function() if SS2.dumpAll then SS2.dumpAll() end end)
    act("discovery audit", function() if SS2.dumpAudit then SS2.dumpAudit() end end)
    act("per-remote dossiers", function() if SS2.dumpPerRemote then SS2.dumpPerRemote() end end)
    act("export all", function() if SS2.exportAll then SS2.exportAll() end end)
    act("vault manifest", function() if SS2.vaultManifest then SS2.vaultManifest() end end)
    act("stealth on/off", function()
        if SS2.stealth.active then SS2.stealthOff() else SS2.stealthOn() end
    end)
    act("session summary", function() print(SS2.vaultSummary()) end)
    act("search feed (console)", function()
        -- nudges you toward grep in the tab strip
    end)
end

renderers = { renderCalls, renderRemotes, renderDecomp, renderTools }
local function switchTab(i)
    curTab = i
    for j, b in ipairs(tabBtns) do
        b.TextColor3 = (j == i) and C_text or C_dim
    end
    underline.Position = UDim2.fromOffset(4 + (i - 1) * 52, 16)
    grepBox.Visible = (i == 1)
    renderers[i]()
end

for i, name in ipairs(TABS) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(48, 18)
    b.Position = UDim2.fromOffset(4 + (i - 1) * 52, 0)
    b.BackgroundTransparency = 1
    b.Font = Enum.Font.Code
    b.TextSize = 10
    b.TextColor3 = (i == 1) and C_text or C_dim
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Text = name
    b.Parent = tabStrip
    b.MouseButton1Click:Connect(function() switchTab(i) end)
    tabBtns[i] = b
end

grepBox:GetPropertyChangedSignal("Text"):Connect(function()
    grepCtx = grepBox.Text:lower()
    if curTab == 1 then renderCalls() end
end)

-- live refresh, but never while frozen (selection = frozen)
task.spawn(function()
    while gui.Parent do
        if curTab == 1 and grepCtx == "" and pinned and not minimized then
            pcall(renderCalls)
        end
        local rc = 0
        for _ in pairs(SS2.remotes) do rc = rc + 1 end
        status.Text = ("%d remotes · %d calls · net:%s · %s"):format(
            rc, #SS2.log, tostring(SS2.metaHooked), pinned and "live" or "frozen")
        task.wait(1)
    end
end)

switchTab(1)

SS2.gui = gui
SS2.setPinned = function(v) pinned = v end
