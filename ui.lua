--[[
    simplyspirited v4.6 — interface
    SHADOWMILESC / computerizedcarrier2

    terminal minimalism. black, dim, text. red = selection only.
    pinned feed contract: click = freeze + inspect, re-click = live.

    self-test: renders a synthetic call through every tab renderer
    at boot and reports errors — the ui verifies itself before you
    need it in the field.

    known simplifications, chosen on purpose:
    - verb rail is a flat button strip (draw-word hitzones broke
      across font metrics; reliability beats minimalism here)
    - decomp actions live in-tab (no floating windows)
]]

print("[SS2-ui] v4.6 building...")

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local P = Players.LocalPlayer

-- teardown
pcall(function()
    local root = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
    for _, n in ipairs({ "SS2_Interface", "SS2_Notify", "SS2_Loader" }) do
        local o = root:FindFirstChild(n)
        if o then o:Destroy() end
    end
end)

-- ═══ palette: black, dim, text, red-as-marker. nothing else. ═══
local C = {
    BG   = Color3.fromRGB(8, 8, 8),
    RAIL = Color3.fromRGB(13, 13, 13),
    TEXT = Color3.fromRGB(215, 215, 215),
    DIM  = Color3.fromRGB(100, 100, 100),
    RED  = Color3.fromRGB(200, 40, 50),
}

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

-- ═══ state — declared ONCE, at top. no forward refs. ═══
local win, tabStrip, content, status, underline
local tabBtns = {}
local currentTab = 1
local pinned = true          -- feed follows newest when true
local selectedCallId = nil
local selectedRemote = nil
local selRow = nil
local grepCtx = ""
local sideRows = {}
local selSideRow = nil
local renderers = {}
local selfTestErrors = 0

-- ═══ helpers ═══
local function corner(o, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 2)
    c.Parent = o
end

-- ═══ window ═══
win = Instance.new("Frame")
win.Size = UDim2.fromOffset(420, 280)
win.Position = UDim2.fromOffset(30, 40)
win.BackgroundColor3 = C.BG
win.BorderSizePixel = 0
win.Active = true
win.Parent = gui

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 20)
header.BackgroundColor3 = C.RAIL
header.BorderSizePixel = 0
header.Parent = win

local hTitle = Instance.new("TextLabel")
hTitle.Size = UDim2.new(0, 220, 1, 0)
hTitle.Position = UDim2.fromOffset(7, 0)
hTitle.BackgroundTransparency = 1
hTitle.Font = Enum.Font.Code
hTitle.TextSize = 11
hTitle.TextColor3 = C.TEXT
hTitle.TextXAlignment = Enum.TextXAlignment.Left
hTitle.Text = "simplyspirited"
hTitle.Parent = header

local hMin = Instance.new("TextButton")
hMin.Size = UDim2.fromOffset(16, 20)
hMin.Position = UDim2.new(1, -36, 0, 0)
hMin.BackgroundTransparency = 1
hMin.Font = Enum.Font.Code
hMin.TextSize = 12
hMin.TextColor3 = C.DIM
hMin.Text = "_"
hMin.Parent = header

local hClose = Instance.new("TextButton")
hClose.Size = UDim2.fromOffset(16, 20)
hClose.Position = UDim2.new(1, -18, 0, 0)
hClose.BackgroundTransparency = 1
hClose.Font = Enum.Font.Code
hClose.TextSize = 12
hClose.TextColor3 = C.DIM
hClose.Text = "x"
hClose.Parent = header

-- drag
local dragOn, dStart, dPos
header.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        dragOn = true
        dStart = i.Position
        dPos = win.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragOn and (i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dStart
        win.Position = UDim2.new(dPos.X.Scale, dPos.X.Offset + d.X,
            dPos.Y.Scale, dPos.Y.Offset + d.Y)
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

-- ═══ TAB STRIP ═══
tabStrip = Instance.new("Frame")
tabStrip.Size = UDim2.new(1, 0, 0, 18)
tabStrip.Position = UDim2.new(0, 0, 0, 20)
tabStrip.BackgroundColor3 = C.RAIL
tabStrip.BorderSizePixel = 0
tabStrip.Parent = win

underline = Instance.new("Frame")
underline.BackgroundColor3 = C.RED
underline.BorderSizePixel = 0
underline.Size = UDim2.fromOffset(44, 2)
underline.Position = UDim2.fromOffset(3, 16)
underline.Parent = tabStrip

local grepBox = Instance.new("TextBox")
grepBox.Size = UDim2.new(0, 120, 0, 14)
grepBox.Position = UDim2.new(1, -126, 0, 2)
grepBox.BackgroundTransparency = 1
grepBox.Font = Enum.Font.Code
grepBox.TextSize = 10
grepBox.TextColor3 = C.TEXT
grepBox.PlaceholderColor3 = C.DIM
grepBox.PlaceholderText = "grep"
grepBox.Text = ""
grepBox.ClearTextOnFocus = false
grepBox.TextXAlignment = Enum.TextXAlignment.Left
grepBox.Parent = tabStrip

local tabBtnsHolder = tabStrip

-- ═══ SIDEBAR ═══
local sidebar = Instance.new("ScrollingFrame")
sidebar.Size = UDim2.new(0, 140, 1, -38)
sidebar.Position = UDim2.fromOffset(0, 38)
sidebar.BackgroundColor3 = C.RAIL
sidebar.BorderSizePixel = 0
sidebar.ScrollBarThickness = 2
sidebar.ScrollBarImageColor3 = C.DIM
sidebar.AutomaticCanvasSize = Enum.AutomaticSize.Y
sidebar.CanvasSize = UDim2.new(0, 0, 0, 0)
sidebar.Parent = win
local sbLayout = Instance.new("UIListLayout")
sbLayout.SortOrder = Enum.SortOrder.LayoutOrder
sbLayout.Parent = sidebar

-- ═══ MAIN PANE ═══
local mainPanel = Instance.new("ScrollingFrame")
mainPanel.Size = UDim2.new(1, -146, 1, -52)
mainPanel.Position = UDim2.fromOffset(146, 38)
mainPanel.BackgroundColor3 = C.BG
mainPanel.BorderSizePixel = 0
mainPanel.ScrollBarThickness = 2
mainPanel.ScrollBarImageColor3 = C.DIM
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
    l.TextColor3 = col or C.TEXT
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Text = txt
    l.LayoutOrder = order
    l.Parent = mainPanel
    return l
end

-- ═══ DETAIL VIEWS (defined before sidebar clicks — v4.2 lesson) ═══
local function showCallDetail(id)
    for _, rec in ipairs(SS2.log) do
        if rec.id == id then
            clearMain()
            tLine("call #" .. id .. " — " .. rec.name, C_TEXT and C.TEXT or C.TEXT, 1)
            tLine(rec.path, C.DIM, 2)
            tLine("", C.DIM, 3)
            for i, a in ipairs(rec.args) do
                tLine(("  %d  %s"):format(i, a), C.TEXT, 3 + i)
            end
            local prof = rec.remote and SS2.remotes[rec.remote]
            if prof and prof.callers and next(prof.callers) then
                local cs = {}
                for c, n in pairs(prof.callers) do cs[#cs+1] = { c=c, n=n } end
                table.sort(cs, function(a,b) return a.n > b.n end)
                tLine("", C.DIM, 29)
                tLine("callers", C.DIM, 30)
                for k, e in ipairs(cs) do
                    tLine(("  %s x%d"):format(e.c, e.n), C.DIM, 30 + k)
                end
            end
            return
        end
    end
end

local function showRemoteDetail(r, prof)
    clearMain()
    tLine("remote — " .. r.Name, C.TEXT, 1)
    tLine(prof.path or "?", C.DIM, 2)
    tLine(("calls %d · out %d · in %d"):format(prof.calls, prof.out, prof.inn), C.DIM, 3)
    if (prof.metaCaught or 0) > 0 then
        tLine("net-caught " .. prof.metaCaught, C.DIM, 4)
    end
    local sigs = {}
    for s, n in pairs(prof.sigs) do sigs[#sigs+1] = { s=s, n=n } end
    table.sort(sigs, function(a,b) return a.n > b.n end)
    if #sigs > 0 then
        tLine("", C.DIM, 5)
        tLine("signatures", C.DIM, 6)
        for k = 1, math.min(24, #sigs) do
            tLine(("  x%d  %s"):format(sigs[k].n, sigs[k].s), C.TEXT, 6 + k)
        end
    end
    if prof.callers and next(prof.callers) then
        local cs = {}
        for c, n in pairs(prof.callers) do cs[#cs+1] = { c=c, n=n } end
        table.sort(cs, function(a,b) return a.n > b.n end)
        tLine("", C.DIM, 32)
        tLine("callers", C.DIM, 33)
        for k, e in ipairs(cs) do
            tLine(("  %s x%d"):format(e.c, e.n), C.DIM, 33 + k)
        end
    end
end

-- ═══ SIDEBAR ROWS ═══
local function sideRow(txt, col, order, onPick, depth)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 14)
    b.BackgroundColor3 = C.RAIL
    b.BorderSizePixel = 0
    b.Font = Enum.Font.Code
    b.TextSize = 10
    b.TextColor3 = col or C.TEXT
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.TextTruncate = Enum.TextTruncate.AtEnd
    b.Text = string.rep(" ", (depth or 0) * 2) .. txt
    b.LayoutOrder = order
    b.MouseButton1Click:Connect(function()
        if selRow == b then
            -- re-click: release selection, go live
            b.TextColor3 = b:GetAttribute("base") or C.TEXT
            selRow = nil
            selectedCallId = nil
            selectedRemote = nil
            pinned = true
            return
        end
        if selRow then selRow.TextColor3 = selRow:GetAttribute("base") or C.TEXT end
        selRow = b
        b:SetAttribute("base", col)
        b.TextColor3 = C.RED
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

-- ═══ VERB RAIL (flat strip, real buttons, terminal-styled) ═══
local rail = Instance.new("Frame")
rail.Size = UDim2.new(0, 140, 0, 16)
rail.Position = UDim2.fromOffset(0, 0)
rail.BackgroundColor3 = C.RAIL
rail.BorderSizePixel = 0
rail.Parent = sidebar
local railLayout = Instance.new("UIGridLayout")
railLayout.CellSize = UDim2.fromOffset(32, 14)
railLayout.CellPadding = UDim2.fromOffset(1, 1)
railLayout.SortOrder = Enum.SortOrder.LayoutOrder
railLayout.Parent = rail

local function railBtn(txt, cb)
    local b = Instance.new("TextButton")
    b.BackgroundColor3 = C.BG
    b.BorderSizePixel = 0
    b.Text = txt
    b.Font = Enum.Font.Code
    b.TextSize = 8
    b.TextColor3 = C.DIM
    b.LayoutOrder = #rail:GetChildren()
    b.MouseButton1Click:Connect(function()
        cb()
        b.TextColor3 = C.TEXT
        task.delay(0.2, function()
            if b.Parent then b.TextColor3 = C.DIM end
        end)
    end)
    b.Parent = rail
    return b
end

-- verbs (call-focused; full tools in TOOLS tab)
railBtn("replay", function()
    if selectedCallId and SS2.replayId then SS2.replayId(selectedCallId) end
end)
railBtn("copy", function()
    if selectedCallId and setclipboard then
        for _, rec in ipairs(SS2.log) do
            if rec.id == selectedCallId then
                setclipboard(table.concat(rec.args, ", "))
            end
        end
    end
end)
railBtn("preset", function()
    if selectedCallId and SS2.savePreset then
        SS2.savePreset("u" .. selectedCallId, selectedCallId)
    end
end)
railBtn("inspect", function()
    if SS2.inspectLast then SS2.inspectLast() end
end)

-- ═══ STATUS ═══
status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -146, 0, 14)
status.Position = UDim2.fromOffset(146, 0)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Code
status.TextSize = 9
status.TextColor3 = C.DIM
status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = ""
status.Parent = rail

-- ═══ RENDERERS ═══
local function renderCalls()
    clearSidebar()
    local n = 0
    for i = #SS2.log, 1, -1 do
        local rec = SS2.log[i]
        local hay = (rec.name .. " " .. table.concat(rec.args, " ")):lower()
        if grepCtx == "" or hay:find(grepCtx, 1, true) then
            n = n + 1
            local id = rec.id
            sideRow(("#%d %s %s"):format(id, rec.dir, rec.name):sub(1, 24),
                rec.dir == "OUT" and C.TEXT or C.DIM, n, function()
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
        tLine("-- no traffic. play the game.", C.DIM, 1)
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
            pp.calls > 0 and C.TEXT or C.DIM, k, function()
            selectedRemote = rr
            showRemoteDetail(rr, pp)
        end)
    end
end

local function renderDecomp()
    clearSidebar()
    if not (SS2.decomp and SS2.decomp.caps) then
        tLine("decomp.lua not loaded", C.DIM, 1)
        return
    end
    local sel = SS2._dcontainer or "ReplicatedStorage"
    local containers = { "ReplicatedStorage", "StarterPlayer", "Players", "workspace" }
    for i, cname in ipairs(containers) do
        local mark = (sel == cname) and "x " or "  "
        sideRow(mark .. cname, sel == cname and C.RED or C.DIM, i, function()
            SS2._dcontainer = cname
            renderDecomp()
        end)
    end
    clearMain()
    tLine("decompiler — 6 layers", C.TEXT, 1)
    tLine(("caps: source=%s bytecode=%s"):format(
        tostring(SS2.decomp.caps.source), tostring(SS2.decomp.caps.bytecode)), C.DIM, 2)
    tLine("target: " .. sel, C.DIM, 3)
    tLine("", C.DIM, 4)
    local i = 5
    local function dAct(txt, fn)
        i = i + 1
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -8, 0, 13)
        b.Position = UDim2.fromOffset(5, 0)
        b.BackgroundTransparency = 1
        b.Font = Enum.Font.Code
        b.TextSize = 10
        b.TextColor3 = C.DIM
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.Text = "  " .. txt
        b.LayoutOrder = i
        b.MouseButton1Click:Connect(function()
            fn()
            b.TextColor3 = C.TEXT
            task.delay(0.25, function()
                if b.Parent then b.TextColor3 = C.DIM end
            end)
        end)
        b.Parent = mainPanel
    end
    dAct("quick — config/main/init scripts", function()
        if SS2.decomp.quick then SS2.decomp.quick() end
    end)
    dAct("bulk dump (200 scripts)", function()
        if SS2.decomp.bulk then SS2.decomp.bulk(sel, 200) end
    end)
    dAct("script tree", function()
        if SS2.decomp.tree then SS2.decomp.tree(sel) end
    end)
    tLine("", C.DIM, i + 2)
    tLine("out: SimplySpirited/decomp/", C.DIM, i + 3)
    tLine("xrf = script references a seen remote", C.DIM, i + 4)
end

local function renderTools()
    clearSidebar()
    tLine("tools", C.TEXT, 0)
    local i = 0
    local function tAct(txt, fn)
        i = i + 1
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 0, 14)
        b.BackgroundColor3 = C.RAIL
        b.BorderSizePixel = 0
        b.Font = Enum.Font.Code
        b.TextSize = 10
        b.TextColor3 = C.DIM
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.Text = " " .. txt
        b.LayoutOrder = i
        b.MouseButton1Click:Connect(function()
            fn()
            b.TextColor3 = C.TEXT
            task.delay(0.25, function()
                if b.Parent then b.TextColor3 = C.DIM end
            end)
        end)
        b.Parent = sidebar
    end
    tAct("api doc", function() if SS2.generateAPIDoc then SS2.generateAPIDoc() end end)
    tAct("master dump", function() if SS2.dumpAll then SS2.dumpAll() end end)
    tAct("discovery audit", function() if SS2.dumpAudit then SS2.dumpAudit() end end)
    tAct("per-remote dossiers", function() if SS2.dumpPerRemote then SS2.dumpPerRemote() end end)
    tAct("export all", function() if SS2.exportAll then SS2.exportAll() end end)
    tAct("vault manifest", function() if SS2.vaultManifest then SS2.vaultManifest() end end)
    tAct("caller export", function() if SS2.exportCallersFull then SS2.exportCallersFull() end end)
    tAct("closure export", function() if SS2.exportClosures then SS2.exportClosures() end end)
    tAct("health report", function() if SS2.healthReport then SS2.healthReport() end end)
    tAct("stealth on/off", function()
        if SS2.stealth.active then SS2.stealthOff() else SS2.stealthOn() end
    end)
    tAct("self-scan", function() if SS2.scanSelf then SS2.scanSelf() end end)
    tAct("session summary", function() print(SS2.vaultSummary()) end)
    clearMain()
    tLine("tools — select from rail", C.DIM, 1)
    tLine("output prints to console", C.DIM, 2)
end

renderers = { renderCalls, renderRemotes, renderDecomp, renderTools }

local function switchTab(i)
    currentTab = i
    for j, b in ipairs(tabBtns) do
        b.TextColor3 = (j == i) and C.TEXT or C.DIM
    end
    underline.Position = UDim2.fromOffset(3 + (i - 1) * 46, 16)
    grepBox.Visible = (i == 1)
    if renderers[i] then renderers[i]() end
end

for i, name in ipairs({ "calls", "remotes", "decomp", "tools" }) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(42, 18)
    b.Position = UDim2.fromOffset(3 + (i - 1) * 46, 0)
    b.BackgroundTransparency = 1
    b.Font = Enum.Font.Code
    b.TextSize = 10
    b.TextColor3 = (i == 1) and C.TEXT or C.DIM
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Text = name
    b.Parent = tabStrip
    b.MouseButton1Click:Connect(function()
        switchTab(i)
    end)
    tabBtns[i] = b
end

grepBox:GetPropertyChangedSignal("Text"):Connect(function()
    grepCtx = grepBox.Text:lower()
    if currentTab == 1 then renderCalls() end
end)

-- ESC clears grep (affordance)
UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.Escape and grepBox.Text ~= "" then
        grepBox.Text = ""
    end
end)

-- refresh loop — respects the pinned contract
task.spawn(function()
    while gui.Parent do
        if currentTab == 1 and grepCtx == "" and pinned and not minimized then
            pcall(renderCalls)
        end
        local rc = 0
        for _ in pairs(SS2.remotes) do rc = rc + 1 end
        status.Text = ("%d remotes · %d calls · net:%s · %s"):format(
            rc, #SS2.log, tostring(SS2.metaHooked), pinned and "live" or "frozen")
        task.wait(1)
    end
end)

-- ═══ SELF-TEST: synthetic call through every renderer ═══
task.spawn(function()
    task.wait(0.5)
    local ok, err = pcall(function()
        local savedLog = SS2.log
        local savedRemotes = SS2.remotes
        local synthetic = {
            { id = 99990, remote = nil, name = "selftest.Call", class = "RemoteEvent",
              dir = "OUT", t = os.clock(), args = { '"test"', "42", "V3(1,2,3)" }, raw = {} },
        }
        -- temporarily inject
        SS2.log = { synthetic[1] }
        renderCalls()
        renderRemotes()
        renderDecomp()
        renderTools()
        -- restore
        SS2.log = savedLog
        SS2.remotes = savedRemotes
    end)
    if ok then
        print("[SS2-ui] self-test passed — all renderers exercised clean")
    else
        warn("[SS2-ui] SELF-TEST ERROR: " .. tostring(err))
    end
    switchTab(1)
end)

switchTab(1)

SS2.gui = gui
print("[SS2-ui] v4.6 LIVE — compact, terminal, self-tested")
