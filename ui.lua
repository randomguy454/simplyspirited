-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v4.1 — SIMPLESPY-CLASS UI, RED EDITION
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  Layout: sidebar list + code panel + button grid (SimpleSpy
--  geometry), red theme, 4 tabs. All windows draggable.
--  Requires core.lua. Powers from callers/watch/decomp.
-- ════════════════════════════════════════════════════════════

print("[SS2-ui] v4.1 building RED interface...")

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

-- ═══ RED THEME ═══
local T = {
    BG      = Color3.fromRGB(24, 10, 12),
    PANEL   = Color3.fromRGB(38, 14, 18),
    CARD    = Color3.fromRGB(52, 18, 24),
    SIDEBAR = Color3.fromRGB(30, 11, 15),
    ACCENT  = Color3.fromRGB(220, 50, 60),
    ACCENT2 = Color3.fromRGB(255, 80, 90),
    GREEN   = Color3.fromRGB(60, 220, 120),
    YELL    = Color3.fromRGB(240, 190, 90),
    PURP    = Color3.fromRGB(190, 130, 255),
    TEXT    = Color3.fromRGB(245, 235, 238),
    DIM     = Color3.fromRGB(160, 120, 130),
    CODEBG  = Color3.fromRGB(18, 8, 10),
}
SS2.theme = T

local function corner(o, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 6)
    c.Parent = o
end
local function stroke(o, col, th)
    local s = Instance.new("UIStroke")
    s.Color = col or T.ACCENT
    s.Thickness = th or 1
    s.Parent = o
    return s
end

local gui = Instance.new("ScreenGui")
gui.Name = "SS2_Interface"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9999
local okP = pcall(function()
    gui.Parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
end)
if not okP then gui.Parent = P:WaitForChild("PlayerGui") end

-- ═══ MAIN WINDOW (SimpleSpy geometry: 680x430) ═══
local win = Instance.new("Frame")
win.Size = UDim2.new(0, 680, 0, 430)
win.Position = UDim2.new(0, 40, 0, 40)
win.BackgroundColor3 = T.BG
win.BorderSizePixel = 0
win.Active = true
corner(win, 8)
stroke(win, T.ACCENT, 1.5)
win.Parent = gui

-- ═══ DRAG ═══
local dragging, dStart, dPos = false, nil, nil
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 30)
header.BackgroundColor3 = T.PANEL
header.BorderSizePixel = 0
corner(header, 8)
header.Parent = win
local hFill = Instance.new("Frame")
hFill.Size = UDim2.new(1, 0, 0, 12)
hFill.Position = UDim2.new(0, 0, 1, -12)
hFill.BackgroundColor3 = T.PANEL
hFill.BorderSizePixel = 0
hFill.Parent = header

local logo = Instance.new("TextLabel")
logo.Size = UDim2.new(0, 200, 1, 0)
logo.Position = UDim2.new(0, 12, 0, 0)
logo.BackgroundTransparency = 1
logo.Text = "SIMPLYSPIRITED v4.1"
logo.Font = Enum.Font.GothamBold
logo.TextSize = 15
logo.TextColor3 = T.ACCENT2
logo.TextXAlignment = Enum.TextXAlignment.Left
logo.Parent = header

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 26, 0, 22)
minBtn.Position = UDim2.new(1, -62, 0, 4)
minBtn.BackgroundTransparency = 1
minBtn.Text = "—"
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 14
minBtn.TextColor3 = T.DIM
minBtn.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 26, 0, 22)
closeBtn.Position = UDim2.new(1, -32, 0, 4)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.TextColor3 = T.ACCENT2
closeBtn.Parent = header

local dragging2, d2Start, d2Pos = false, nil, nil
minBtn.MouseButton1Click:Connect(function()
    win.Size = UDim2.new(0, 680, 0, 30)
end)
-- restore via double click on header
header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dStart = input.Position
        dPos = win.Position
    end
end)
-- second drag context for the card handled separately
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
    dragging2 = false
end)
closeBtn.MouseButton1Click:Connect(function()
    gui:Destroy()
    print("[SS2-ui] closed — engine remains")
end)

-- ═══ TAB STRIP ═══
local TABS = { "CALLS", "REMOTES", "DECOMPILER", "TOOLS" }
local tabStrip = Instance.new("Frame")
tabStrip.Size = UDim2.new(1, 0, 0, 28)
tabStrip.Position = UDim2.new(0, 0, 0, 30)
tabStrip.BackgroundColor3 = T.PANEL
tabStrip.BorderSizePixel = 0
tabStrip.Parent = win

local tabBtns = {}
local currentTab = 1
local switchTab

for i, name in ipairs(TABS) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 100, 1, 0)
    b.Position = UDim2.new(0, 10 + (i - 1) * 105, 0, 0)
    b.BackgroundTransparency = 1
    b.Text = name
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.TextColor3 = (i == 1) and T.ACCENT2 or T.DIM
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Parent = tabStrip
    b.MouseButton1Click:Connect(function()
        switchTab(i)
    end)
    tabBtns[i] = b
end

-- ═══ CONTENT LAYOUT: sidebar (200px) + main panel ═══
local sidebar = Instance.new("ScrollingFrame")
sidebar.Size = UDim2.new(0, 200, 1, -68)
sidebar.Position = UDim2.new(0, 0, 0, 58)
sidebar.BackgroundColor3 = T.SIDEBAR
sidebar.BorderSizePixel = 0
sidebar.ScrollBarThickness = 4
sidebar.ScrollBarImageColor3 = T.ACCENT
sidebar.AutomaticCanvasSize = Enum.AutomaticSize.Y
sidebar.CanvasSize = UDim2.new(0, 0, 0, 0)
sidebar.Parent = win
local sbLayout = Instance.new("UIListLayout")
sbLayout.SortOrder = Enum.SortOrder.LayoutOrder
sbLayout.Parent = sidebar

local mainPanel = Instance.new("ScrollingFrame")
mainPanel.Size = UDim2.new(1, -216, 1, -68)
mainPanel.Position = UDim2.new(0, 208, 0, 58)
mainPanel.BackgroundColor3 = T.CODEBG
mainPanel.BorderSizePixel = 0
mainPanel.ScrollBarThickness = 5
mainPanel.ScrollBarImageColor3 = T.ACCENT
mainPanel.AutomaticCanvasSize = Enum.AutomaticSize.Y
mainPanel.CanvasSize = UDim2.new(0, 0, 0, 0)
mainPanel.Parent = win
local mpLayout = Instance.new("UIListLayout")
mpLayout.Padding = UDim.new(0, 2)
mpLayout.SortOrder = Enum.SortOrder.LayoutOrder
mpLayout.Parent = mainPanel

local function clearMain()
    for _, c in ipairs(mainPanel:GetChildren()) do
        if c:IsA("TextLabel") or c:IsA("TextButton") or c:IsA("Frame") then c:Destroy() end
    end
end

local function mainLine(txt, color, order, mono)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -12, 0, 18)
    l.Position = UDim2.new(0, 8, 0, 0)
    l.BackgroundTransparency = 1
    l.Font = mono and Enum.Font.Code or Enum.Font.Gotham
    l.TextSize = 12
    l.TextColor3 = color or T.TEXT
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextWrapped = false
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Text = txt
    l.LayoutOrder = order
    l.Parent = mainPanel
    return l
end

local function mainBlock(txt, color, order)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -12, 0, 0)
    l.AutomaticSize = Enum.AutomaticSize.Y
    l.Position = UDim2.new(0, 8, 0, 0)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Code
    l.TextSize = 12
    l.TextColor3 = color or T.TEXT
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Top
    l.TextWrapped = true
    l.Text = txt
    l.LayoutOrder = order
    l.Parent = mainPanel
    return l
end

-- ═══ BUTTON GRID (SimpleSpy style, bottom of window) ═══
local btnGrid = Instance.new("Frame")
btnGrid.Size = UDim2.new(1, -216, 0, 0)
btnGrid.Position = UDim2.new(0, 208, 1, -0)
btnGrid.BackgroundColor3 = T.PANEL
btnGrid.BorderSizePixel = 0
btnGrid.AutomaticSize = Enum.AutomaticSize.Y
btnGrid.Parent = win
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0, 140, 0, 30)
gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = btnGrid
local gridPad = Instance.new("UIPadding")
gridPad.PaddingLeft = UDim.new(0, 8)
gridPad.PaddingTop = UDim.new(0, 8)
gridPad.PaddingRight = UDim.new(0, 8)
gridPad.PaddingBottom = UDim.new(0, 8)
gridPad.Parent = btnGrid

local function gridBtn(txt, cb, col)
    local b = Instance.new("TextButton")
    b.BackgroundColor3 = T.CARD
    b.Text = txt
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.TextColor3 = T.TEXT
    b.AutoButtonColor = true
    corner(b, 4)
    stroke(b, col or T.ACCENT, 1)
    b.MouseButton1Click:Connect(cb)
    b.Parent = btnGrid
    return b
end

-- ═══ SIDEBAR ROWS ═══
local sideRows = {}
local function sideRow(txt, color, order, recId, remoteRef, profRef)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -8, 0, 22)
    b.BackgroundColor3 = T.CARD
    b.BackgroundTransparency = 0.3
    b.Font = Enum.Font.Code
    b.TextSize = 11
    b.TextColor3 = color or T.TEXT
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.TextTruncate = Enum.TextTruncate.AtEnd
    b.Text = " " .. txt
    b.LayoutOrder = order
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 4)
    pad.Parent = b
    b.MouseButton1Click:Connect(function()
        -- selection highlight
        for _, r in ipairs(sideRows) do
            r.BackgroundColor3 = T.CARD
        end
        b.BackgroundColor3 = T.ACCENT
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
end

-- ═══ DETAIL RENDERERS (into mainPanel) ═══
local selectedCallId = nil
local selectedRemote = nil

local function showCallDetail(recId)
    for _, rec in ipairs(SS2.log) do
        if rec.id == recId then
            selectedCallId = recId
            selectedRemote = rec.remote
            clearMain()
            mainLine("#" .. rec.id .. "  " .. rec.dir .. "  " .. rec.class .. "  " .. rec.name,
                T.ACCENT2, 1, true)
            mainLine("path: " .. rec.path, T.DIM, 2, true)
            mainLine("", T.DIM, 3)
            mainLine("ARGS:", T.ACCENT2, 4, true)
            for i, a in ipairs(rec.args) do
                mainLine("  [" .. i .. "] " .. a, T.TEXT, 4 + i, true)
            end
            local prof = SS2.remotes[rec.remote]
            if prof and prof.callers and next(prof.callers) then
                mainLine("", T.DIM, 20)
                mainLine("CALLERS:", T.ACCENT2, 21, true)
                local cs = {}
                for c, n in pairs(prof.callers) do cs[#cs + 1] = { c = c, n = n } end
                table.sort(cs, function(a, b) return a.n > b.n end)
                for k, e in ipairs(cs) do
                    mainLine("  " .. e.c .. " (" .. e.n .. "x)", T.DIM, 21 + k, true)
                end
            end
            return
        end
    end
end

local function showRemoteDetail(r, prof)
    selectedCallId = nil
    selectedRemote = r
    clearMain()
    mainLine("REMOTE: " .. r.Name .. "  (" .. prof.class .. ")", T.ACCENT2, 1, true)
    mainLine("path: " .. (prof.path or "?"), T.DIM, 2, true)
    mainLine("calls: " .. prof.calls .. " (out " .. prof.out .. " / in " .. prof.inn .. ")", T.TEXT, 3, true)
    mainLine("hooked: " .. tostring(prof.hooked) .. " | metaCaught: " .. tostring(prof.metaCaught or 0), T.DIM, 4, true)
    local sigs = {}
    for sig, cnt in pairs(prof.sigs) do
        sigs[#sigs + 1] = { s = sig, c = cnt }
    end
    table.sort(sigs, function(a, b) return a.c > b.c end)
    if #sigs > 0 then
        mainLine("", T.DIM, 5)
        mainLine("SIGNATURES (by frequency):", T.ACCENT2, 6, true)
        for k = 1, math.min(25, #sigs) do
            mainLine("  [" .. sigs[k].c .. "x] " .. sigs[k].s, T.TEXT, 6 + k, true)
        end
    end
    if prof.callers and next(prof.callers) then
        mainLine("", T.DIM, 40)
        mainLine("CALLERS:", T.ACCENT2, 41, true)
        local cs = {}
        for c, n in pairs(prof.callers) do cs[#cs + 1] = { c = c, n = n } end
        table.sort(cs, function(a, b) return a.n > b.n end)
        for k, e in ipairs(cs) do
            mainLine("  " .. e.c .. " (" .. e.n .. "x)", T.DIM, 41 + k, true)
        end
    end
end

-- ═══ TAB RENDERERS ═══
local searchCtx = ""

local function renderCalls()
    clearSidebar()
    local n = 0
    for i = #SS2.log, 1, -1 do
        local rec = SS2.log[i]
        local hay = (rec.name .. " " .. table.concat(rec.args, " ")):lower()
        if searchCtx == "" or hay:find(searchCtx, 1, true) then
            n = n + 1
            sideRow(("#%d %s %s"):format(rec.id, rec.dir, rec.name:sub(1, 20)),
                rec.dir == "OUT" and T.GREEN or T.TEXT, n, rec.id, nil, nil)
            if n > 100 then break end
        end
    end
    -- main panel: show selected or last
    if selectedCallId then
        showCallDetail(selectedCallId)
    elseif #SS2.log > 0 then
        showCallDetail(SS2.log[#SS2.log].id)
    else
        clearMain()
        mainLine("no calls yet — play the game", T.DIM, 1)
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
        sideRow(e.prof.calls .. "x  " .. e.r.Name:sub(1, 22),
            e.prof.calls > 0 and T.TEXT or T.DIM, k, nil, e.r, e.prof)
    end
    if selectedRemote then
        showRemoteDetail(selectedRemote, SS2.remotes[selectedRemote])
    else
        clearMain()
        mainLine("click a remote in the sidebar", T.DIM, 1)
    end
end

local function renderDecompiler()
    clearSidebar()
    -- sidebar: containers
    local containers = { "ReplicatedStorage", "StarterPlayer", "Players", "workspace", "StarterGui" }
    local sel = SS2._decompContainer or "ReplicatedStorage"
    for i, cname in ipairs(containers) do
        local b = sideRow((sel == cname and "▸ " or "  ") .. cname,
            sel == cname and T.ACCENT2 or T.TEXT, i)
        b.MouseButton1Click:Connect(function()
            SS2._decompContainer = cname
            renderDecompiler()
        end)
    end
    -- main: results
    clearMain()
    mainLine("DECOMPILER v4.0 — 6-layer analysis", T.ACCENT2, 1, true)
    mainLine("caps: source=" .. tostring(SS2.decomp.caps and SS2.decomp.caps.source)
        .. " bytecode=" .. tostring(SS2.decomp.caps and SS2.decomp.caps.bytecode), T.DIM, 2, true)
    mainLine("", T.DIM, 3)
    mainLine("container: " .. sel, T.TEXT, 4, true)
    mainLine("", T.DIM, 5)
    mainLine("use the buttons below: QUICK / BULK / TREE", T.DIM, 6, true)
    mainLine("results -> SimplySpirited/decomp/ (workspace -> PC)", T.DIM, 7, true)
    mainLine("", T.DIM, 8)
    -- show cross-ref hits from last bulk if any
    if SS2._lastXrefHits and SS2._lastXrefHits > 0 then
        mainLine("★ last bulk found " .. SS2._lastXrefHits .. " live-wire matches!", T.GREEN, 9, true)
    end
end

local function renderTools()
    clearSidebar()
    local i = 0
    local function sGroup(txt)
        i = i + 1
        sideRow("── " .. txt .. " ──", T.ACCENT2, i)
    end
    local function sBtn(txt, cb)
        i = i + 1
        local b = sideRow(txt, T.TEXT, i)
        b.MouseButton1Click:Connect(cb)
    end
    sGroup("CAPTURE")
    sBtn("pause/resume capture", function() SS2.togglePause() end)
    sBtn("verbosity: cycle", function()
        local map = { quiet = "smart", smart = "loud", loud = "quiet" }
        SS2.setVerbosity(map[SS2.verbosity] or "smart")
    end)
    sGroup("INTEL")
    sBtn("generate API documentation", function()
        SS2.generateAPIDoc()
    end)
    sBtn("master dump", function() SS2.dumpAll() end)
    sBtn("discovery audit", function() SS2.dumpAudit() end)
    sBtn("per-remote dossiers", function() SS2.dumpPerRemote() end)
    sGroup("VAULT")
    sBtn("export everything", function() SS2.exportAll() end)
    sBtn("vault manifest", function() SS2.vaultManifest() end)
    sGroup("STEALTH")
    sBtn("stealth ON", function() SS2.stealthOn() end)
    sBtn("stealth OFF", function() SS2.stealthOff() end)
    sBtn("self-scan", function() SS2.scanSelf() end)
    sGroup("SESSION")
    sBtn("session summary", function() print(SS2.vaultSummary()) end)
    clearMain()
    mainLine("TOOLS — pick from the sidebar", T.ACCENT2, 1, true)
    mainLine("all actions print to console", T.DIM, 2, true)
end

tabRenderers = { renderCalls, renderRemotes, renderDecompiler, renderTools }
switchTab = function(i)
    currentTab = i
    for j, b in ipairs(tabBtns) do
        b.TextColor3 = (j == i) and T.ACCENT2 or T.DIM
    end
    tabRenderers[i]()
end

-- ═══ BUTTON GRID WIRING (SimpleSpy verbs + ours) ═══
gridBtn("Copy Code", function()
    -- full arg script of selected call
    if selectedCallId then
        for _, rec in ipairs(SS2.log) do
            if rec.id == selectedCallId and setclipboard then
                setclipboard("-- " .. rec.name .. "\nlocal args = {" ..
                    table.concat(rec.args, ",\n    ") .. "\n}\n" ..
                    rec.class .. "(" .. rec.path .. "):FireServer(unpack(args))")
            end
        end
    end
end, T.GREEN)
gridBtn("Copy Remote", function()
    if selectedRemote and setclipboard then
        setclipboard(selectedRemote:GetFullName())
    end
end)
gridBtn("Run Code (replay)", function()
    if selectedCallId and SS2.replayId then
        SS2.replayId(selectedCallId)
    end
end, T.GREEN)
gridBtn("Get Script", function()
    -- decompile the script that owns the selected remote's caller
    if selectedRemote then
        local prof = SS2.remotes[selectedRemote]
        if prof and prof.callers then
            for caller, n in pairs(prof.callers) do
                print("[Get Script] top caller: " .. caller .. " (" .. n .. "x)")
                print("[Get Script] use DECOMPILER tab → bulk dump to capture it")
                break
            end
        end
    end
end)
gridBtn("Function Info", function()
    if SS2.inspectLast then SS2.inspectLast() end
end, T.PURP)
gridBtn("Clr Logs", function()
    SS2.log = {}
    selectedCallId = nil
    print("[SS2] log cleared")
    switchTab(currentTab)
end, T.RED)
gridBtn("Exclude (name)", function()
    -- mute the selected remote by name
    if selectedRemote then
        SS2.muteRemote(selectedRemote.Name)
    end
end, T.RED)
gridBtn("Clr Mutes", function()
    if SS2.governor then
        SS2.governor.muted = {}
        print("[SS2] mutes cleared")
    end
end)

-- ═══ SEARCH ═══
local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(1, -216, 0, 24)
searchBox.Position = UDim2.new(0, 208, 0, 32)
searchBox.BackgroundColor3 = T.CODEBG
searchBox.PlaceholderText = "search calls…"
searchBox.Text = ""
searchBox.Font = Enum.Font.Code
searchBox.TextSize = 12
searchBox.TextColor3 = T.TEXT
searchBox.ClearTextOnFocus = false
corner(searchBox, 4)
stroke(searchBox, T.ACCENT)
searchBox.Parent = win
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    searchCtx = searchBox.Text:lower()
    if currentTab == 1 then renderCalls() end
end)

-- ═══ STATUS BAR ═══
local stat = Instance.new("TextLabel")
stat.Size = UDim2.new(1, -216, 0, 18)
stat.Position = UDim2.new(0, 208, 1, -20)
stat.BackgroundTransparency = 1
stat.Font = Enum.Font.Code
stat.TextSize = 11
stat.TextColor3 = T.DIM
stat.TextXAlignment = Enum.TextXAlignment.Left
stat.Text = ""
stat.Parent = win

task.spawn(function()
    while gui.Parent do
        if currentTab == 1 and searchCtx == "" then
            renderCalls()
        end
        local rc = 0
        for _ in pairs(SS2.remotes) do rc = rc + 1 end
        stat.Text = ("remotes: %d · calls: %d · net: %s · gov: %s"):format(
            rc, #SS2.log, tostring(SS2.metaHooked),
            SS2.governor and SS2.governor.mode or "n/a")
        task.wait(1)
    end
end)

switchTab(1)

SS2.gui = gui
SS2.uiReadyV4 = true
print("[SS2-ui] v4.1 RED interface LIVE — SimpleSpy geometry, our engine")
