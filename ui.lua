--[[
    simplyspirited v5.0 — interface
    SHADOWMILESC / computerizedcarrier2

    clean rebuild: single-declaration header, strict order,
    zero forward-reference hazards. five tabs:
      CALLS / REMOTES / DECOMPILER / EXPLORER / TOOLS

    explorer tab opens the dex-style browser window
    (explorer.lua) wired to the capture engine.
]]

print("[SS2-ui] v5.0 building...")

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local P = Players.LocalPlayer

local SS2 = getgenv().SS2
if not SS2 then
    warn("ss2-ui: core.lua must load first")
    return
end

-- ════════════════════════════════════════════════════════════
-- PALETTE
-- ════════════════════════════════════════════════════════════
local T = {
    BG     = Color3.fromRGB(12, 12, 14),
    RAIL   = Color3.fromRGB(19, 19, 23),
    CARD   = Color3.fromRGB(26, 26, 31),
    HI     = Color3.fromRGB(34, 34, 40),
    TEXT   = Color3.fromRGB(225, 225, 228),
    DIM    = Color3.fromRGB(115, 115, 122),
    FAINT  = Color3.fromRGB(70, 70, 76),
    ACCENT = Color3.fromRGB(90, 140, 250),
    RED    = Color3.fromRGB(210, 70, 80),
    GREEN  = Color3.fromRGB(70, 190, 120),
}

-- ════════════════════════════════════════════════════════════
-- STATE — all declarations first
-- ════════════════════════════════════════════════════════════
local gui = Instance.new("ScreenGui")
gui.Name = "SS2_Interface"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9999

local win
local status
local content
local grepBox
local tabBtns = {}
local currentTab = 1
local pinned = true
local lockedCallId = nil
local lockedRemote = nil
local lastRenderCount = -1
local lastGrep = ""
local minimized = false
local renderCallsSafe
local renderers = nil
local switchTab = nil

pcall(function()
    gui.Parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
end)
if not gui.Parent then
    gui.Parent = P:WaitForChild("PlayerGui")
end

local function addCorner(o)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 4)
    c.Parent = o
end

-- ════════════════════════════════════════════════════════════
-- WINDOW
-- ════════════════════════════════════════════════════════════
win = Instance.new("Frame")
win.Size = UDim2.fromOffset(520, 360)
win.Position = UDim2.fromOffset(30, 40)
win.BackgroundColor3 = T.BG
win.BorderSizePixel = 0
win.Active = true
win.Parent = gui

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 30)
header.BackgroundColor3 = T.RAIL
header.BorderSizePixel = 0
header.Parent = win

local dot = Instance.new("Frame")
dot.Size = UDim2.fromOffset(8, 8)
dot.Position = UDim2.fromOffset(10, 11)
dot.BackgroundColor3 = T.GREEN
dot.BorderSizePixel = 0
dot.Parent = header

local hTitle = Instance.new("TextLabel")
hTitle.Size = UDim2.new(0, 200, 1, 0)
hTitle.Position = UDim2.fromOffset(24, 0)
hTitle.BackgroundTransparency = 1
hTitle.Font = Enum.Font.GothamMedium
hTitle.TextSize = 12
hTitle.TextColor3 = T.TEXT
hTitle.TextXAlignment = Enum.TextXAlignment.Left
hTitle.Text = "SIMPLYSPIRITED"
hTitle.Parent = header

local hSub = Instance.new("TextLabel")
hSub.Size = UDim2.new(0, 80, 1, 0)
hSub.Position = UDim2.fromOffset(140, 0)
hSub.BackgroundTransparency = 1
hSub.Font = Enum.Font.Code
hSub.TextSize = 10
hSub.TextColor3 = T.FAINT
hSub.TextXAlignment = Enum.TextXAlignment.Left
hSub.Text = "v5.0"
hSub.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(24, 30)
closeBtn.Position = UDim2.new(1, -26, 0, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.Font = Enum.Font.Code
closeBtn.TextSize = 13
closeBtn.TextColor3 = T.DIM
closeBtn.Text = "✕"
closeBtn.Parent = header

local dragOn = false
local dragStart, dragPos
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
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        dragOn = false
    end
end)
closeBtn.MouseButton1Click:Connect(function()
    gui:Destroy()
end)

-- ════════════════════════════════════════════════════════════
-- TAB STRIP
-- ════════════════════════════════════════════════════════════
local TABS = { "CALLS", "REMOTES", "DECOMPILER", "EXPLORER", "TOOLS" }
local tabStrip = Instance.new("Frame")
tabStrip.Size = UDim2.new(1, 0, 0, 28)
tabStrip.Position = UDim2.new(0, 0, 0, 30)
tabStrip.BackgroundColor3 = T.RAIL
tabStrip.BorderSizePixel = 0
tabStrip.Parent = win

grepBox = Instance.new("TextBox")
grepBox.Size = UDim2.fromOffset(140, 22)
grepBox.Position = UDim2.new(1, -150, 0, 3)
grepBox.BackgroundColor3 = T.CARD
grepBox.PlaceholderText = "filter…"
grepBox.Text = ""
grepBox.Font = Enum.Font.Code
grepBox.TextSize = 11
grepBox.TextColor3 = T.TEXT
grepBox.PlaceholderColor3 = T.FAINT
grepBox.ClearTextOnFocus = false
addCorner(grepBox)
grepBox.Parent = tabStrip

-- ════════════════════════════════════════════════════════════
-- CONTENT + STATUS
-- ════════════════════════════════════════════════════════════
content = Instance.new("ScrollingFrame")
content.Size = UDim2.new(1, -16, 1, -96)
content.Position = UDim2.fromOffset(8, 66)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ScrollBarThickness = 4
content.ScrollBarImageColor3 = T.FAINT
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.CanvasSize = UDim2.new(0, 0, 0, 0)
content.Parent = win

local contentLayout = Instance.new("UIListLayout")
contentLayout.Padding = UDim.new(0, 2)
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Parent = content

status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -16, 0, 20)
status.Position = UDim2.new(0, 8, 1, -26)
status.BackgroundColor3 = T.RAIL
status.Font = Enum.Font.Code
status.TextSize = 10
status.TextColor3 = T.DIM
status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = ""
addCorner(status)
status.Parent = win

-- ════════════════════════════════════════════════════════════
-- CONTENT HELPERS
-- ════════════════════════════════════════════════════════════
local function clearContent()
    for _, c in ipairs(content:GetChildren()) do
        if c:IsA("TextLabel") or c:IsA("TextButton") or c:IsA("Frame") then
            c:Destroy()
        end
    end
end

local function tLine(txt, col, order)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -8, 0, 16)
    l.Position = UDim2.fromOffset(6, 0)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Code
    l.TextSize = 12
    l.TextColor3 = col or T.TEXT
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Text = txt
    l.LayoutOrder = order
    l.Parent = content
end

local function tSection(txt, order)
    local s = Instance.new("TextLabel")
    s.Size = UDim2.new(1, -8, 0, 22)
    s.Position = UDim2.fromOffset(6, 0)
    s.BackgroundColor3 = T.RAIL
    s.BorderSizePixel = 0
    s.Font = Enum.Font.GothamMedium
    s.TextSize = 11
    s.TextColor3 = T.DIM
    s.TextXAlignment = Enum.TextXAlignment.Left
    s.Text = "  " .. txt
    s.LayoutOrder = order
    addCorner(s)
    s.Parent = content
end

local function tBtn(txt, col, order, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -8, 0, 22)
    b.Position = UDim2.fromOffset(6, 0)
    b.BackgroundColor3 = T.CARD
    b.Font = Enum.Font.Code
    b.TextSize = 12
    b.TextColor3 = col or T.TEXT
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.TextTruncate = Enum.TextTruncate.AtEnd
    b.Text = "  " .. txt
    b.LayoutOrder = order
    addCorner(b)
    b.MouseButton1Click:Connect(cb)
    b.Parent = content
end

-- ════════════════════════════════════════════════════════════
-- DETAIL RENDERERS
-- ════════════════════════════════════════════════════════════
local function showCallDetail(id)
    for _, rec in ipairs(SS2.log) do
        if rec.id == id then
            clearContent()
            tSection("CALL #" .. id .. " — " .. rec.name, 1)
            tLine("path   " .. rec.path, T.DIM, 2)
            tLine("dir    " .. rec.dir, T.DIM, 3)
            tLine("", T.DIM, 4)
            tSection("ARGUMENTS", 5)
            for i, a in ipairs(rec.args) do
                tLine(("  %d  %s"):format(i, a), T.TEXT, 5 + i)
            end
            local prof = rec.remote and SS2.remotes[rec.remote]
            if prof and prof.callers and next(prof.callers) then
                tLine("", T.DIM, 29)
                tSection("CALLERS", 30)
                local cs = {}
                for c, n in pairs(prof.callers) do
                    cs[#cs + 1] = { c = c, n = n }
                end
                table.sort(cs, function(a, b) return a.n > b.n end)
                for k, e in ipairs(cs) do
                    tLine(("  %s  x%d"):format(e.c, e.n), T.DIM, 30 + k)
                end
            end
            tLine("", T.DIM, 59)
            tBtn("← BACK TO LIVE FEED", T.ACCENT, 60, function()
                lockedCallId = nil
                pinned = true
                lastRenderCount = -1
                if renderCallsSafe then renderCallsSafe() end
            end)
            return
        end
    end
end

local function showRemoteDetail(r, prof)
    clearContent()
    tSection("REMOTE — " .. r.Name .. " (" .. prof.class .. ")", 1)
    tLine("path   " .. (prof.path or "?"), T.DIM, 2)
    tLine("calls  " .. prof.calls .. " (out " .. prof.out .. " / in " .. prof.inn .. ")", T.TEXT, 3)
    tLine("net-caught  " .. tostring(prof.metaCaught or 0), T.DIM, 4)
    tLine("seen   " .. prof.firstSeen .. " -> " .. prof.lastSeen, T.DIM, 5)
    tLine("", T.DIM, 6)
    local sigCount = 0
    for _ in pairs(prof.sigs) do sigCount = sigCount + 1 end
    tSection("SIGNATURES — " .. sigCount .. " unique", 7)
    local sigs = {}
    for sig, cnt in pairs(prof.sigs) do
        sigs[#sigs + 1] = { s = sig, c = cnt }
    end
    table.sort(sigs, function(a, b) return a.c > b.c end)
    for k = 1, math.min(24, #sigs) do
        tLine(("  x%d  %s"):format(sigs[k].c, sigs[k].s), T.TEXT, 7 + k)
    end
    tLine("", T.DIM, 40)
    tBtn("← BACK TO LIVE FEED", T.ACCENT, 41, function()
        lockedRemote = nil
        pinned = true
        lastRenderCount = -1
        if renderCallsSafe then renderCallsSafe() end
    end)
end

-- ════════════════════════════════════════════════════════════
-- RENDERERS
-- ════════════════════════════════════════════════════════════
local function renderCalls(force)
    local rebuild = force
        or (lockedCallId ~= nil)
        or (#SS2.log - lastRenderCount >= 5)
        or (grepBox.Text ~= lastGrep)
    if not rebuild then return end
    lastRenderCount = #SS2.log
    lastGrep = grepBox.Text

    clearContent()
    local n = 0
    for i = #SS2.log, 1, -1 do
        local rec = SS2.log[i]
        local hay = (rec.name .. " " .. table.concat(rec.args, " ")):lower()
        if lastGrep == "" or hay:find(lastGrep, 1, true) then
            n = n + 1
            local id = rec.id
            local isLocked = (lockedCallId == id)
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(1, -8, 0, 24)
            b.Position = UDim2.fromOffset(6, 0)
            b.BackgroundColor3 = isLocked and T.HI or T.CARD
            b.Font = Enum.Font.Code
            b.TextSize = 12
            b.TextColor3 = rec.dir == "OUT" and T.GREEN or T.TEXT
            b.TextXAlignment = Enum.TextXAlignment.Left
            b.TextTruncate = Enum.TextTruncate.AtEnd
            b.Text = ("  #%d %s  %s"):format(id, rec.dir, rec.name)
            b.LayoutOrder = n
            addCorner(b)
            b.MouseButton1Click:Connect(function()
                lockedCallId = id
                pinned = false
                showCallDetail(id)
            end)
            b.Parent = content
            if n > 80 then
                tLine("  … (80+ — filter to narrow)", T.DIM, n + 1)
                break
            end
        end
    end
    if n == 0 then
        tLine(lastGrep ~= "" and ("no matches — " .. lastGrep)
            or "no calls yet — play the game", T.DIM, 1)
    end
end

renderCallsSafe = function()
    if currentTab == 1 then
        renderCalls(true)
    end
end

local function renderRemotes(force)
    if not force and lockedRemote then return end
    clearContent()
    local ranked = {}
    for r, prof in pairs(SS2.remotes) do
        ranked[#ranked + 1] = { r = r, p = prof }
    end
    table.sort(ranked, function(a, b) return a.p.calls > b.p.calls end)
    for k = 1, math.min(120, #ranked) do
        local e = ranked[k]
        local rr, pp = e.r, e.p
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -8, 0, 24)
        b.Position = UDim2.fromOffset(6, 0)
        b.BackgroundColor3 = T.CARD
        b.Font = Enum.Font.Code
        b.TextSize = 12
        b.TextColor3 = pp.calls > 0 and T.TEXT or T.FAINT
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.TextTruncate = Enum.TextTruncate.AtEnd
        b.Text = ("  %4d  %-6s %s"):format(pp.calls, pp.class:sub(1, 6), pp.path)
        b.LayoutOrder = k
        addCorner(b)
        b.MouseButton1Click:Connect(function()
            lockedRemote = rr
            showRemoteDetail(rr, pp)
        end)
        b.Parent = content
    end
end

local function renderDecompiler(force)
    clearContent()
    if not (SS2.decomp and SS2.decomp.caps) then
        tLine("decomp.lua not loaded", T.DIM, 1)
        return
    end
    local sel = SS2._dcontainer or "ReplicatedStorage"

    tSection("DECOMPILER v4.0 — 6-LAYER ANALYSIS", 1)
    tLine("capabilities: source=" .. tostring(SS2.decomp.caps.source)
        .. "  bytecode=" .. tostring(SS2.decomp.caps.bytecode), T.DIM, 2)
    tLine("container: " .. sel, T.TEXT, 3)
    tLine("", T.DIM, 4)

    local containers = { "ReplicatedStorage", "StarterPlayer", "Players", "workspace" }
    for i, cname in ipairs(containers) do
        tBtn((sel == cname and "● " or "○ ") .. cname,
            sel == cname and T.TEXT or T.DIM, 4 + i, function()
            SS2._dcontainer = cname
            renderDecompiler(true)
        end)
    end

    tLine("", T.DIM, 10)
    tBtn("QUICK — config/main/init/network scripts", T.TEXT, 11, function()
        if SS2.decomp.quick then SS2.decomp.quick() end
    end)
    tBtn("BULK DUMP — " .. sel .. " (200 scripts)", T.TEXT, 12, function()
        if SS2.decomp.bulk then SS2.decomp.bulk(sel, 200) end
    end)
    tBtn("SCRIPT TREE — console view", T.DIM, 13, function()
        if SS2.decomp.tree then SS2.decomp.tree(sel) end
    end)

    tLine("", T.DIM, 15)
    tSection("OUTPUT", 16)
    tLine("  SimplySpirited/decomp/ -> workspace", T.DIM, 17)
    tLine("  .src.lua / .bytecode / .constants.txt", T.DIM, 18)
    tLine("  xref = script references a seen remote", T.GREEN, 19)
end

local function renderExplorer(force)
    clearContent()
    if SS2.explorer and SS2.explorer.window and SS2.explorer.window.Parent then
        tSection("EXPLORER — RUNNING", 1)
        tLine("", T.DIM, 2)
        tLine("the explorer window is open alongside this panel.", T.TEXT, 3)
        tLine("drag it anywhere. navigate the game tree, click any", T.DIM, 4)
        tLine("instance to inspect it. remotes show capture profiles,", T.DIM, 5)
        tLine("values offer watch, scripts offer decompile.", T.DIM, 6)
        tLine("", T.DIM, 7)
        tBtn("RE-FOCUS (nothing to reload)", T.DIM, 8, function() end)
    else
        tSection("EXPLORER — DEX-STYLE BROWSER", 1)
        tLine("", T.DIM, 2)
        tLine("navigate the game's DataModel, inspect instances,", T.DIM, 3)
        tLine("search game-wide by name.", T.DIM, 4)
        tLine("", T.DIM, 5)
        tLine("suite integration (dex doesn't have):", T.TEXT, 6)
        tLine("  remotes → capture profiles inline", T.DIM, 7)
        tLine("  values  → one-click watch", T.DIM, 8)
        tLine("  scripts → one-click 6-layer decompile", T.DIM, 9)
        tLine("", T.DIM, 10)
        if explorer.lua_loaded then
            tBtn("OPEN EXPLORER WINDOW", T.GREEN, 11, function()
                if SS2.explorer and SS2.explorer.window then
                    SS2.explorer.window.Enabled = true
                end
            end)
        else
            tBtn("OPEN EXPLORER WINDOW", T.GREEN, 11, function()
                -- explorer.lua must be in PARTS; open its window
                if SS2.explorer and SS2.explorer.window then
                    SS2.explorer.window.Enabled = true
                else
                    tLine("explorer.lua not loaded — add to Load.lua PARTS", T.RED, 12)
                end
            end)
        end
    end
end

local function renderTools(force)
    clearContent()
    tSection("CAPTURE", 1)
    tBtn("pause / resume capture", T.TEXT, 2, function()
        if SS2.togglePause then SS2.togglePause() end
    end)
    tBtn("verbosity: " .. tostring(SS2.verbosity) .. " (cycle)", T.TEXT, 3, function()
        local map = { quiet = "smart", smart = "loud", loud = "quiet" }
        if SS2.setVerbosity then SS2.setVerbosity(map[SS2.verbosity] or "smart") end
        renderTools(true)
    end)
    tBtn("rescan remotes now", T.TEXT, 4, function()
        if SS2.scanRemotes then SS2.scanRemotes() end
    end)

    tSection("INTEL", 6)
    tBtn("generate API documentation", T.TEXT, 7, function()
        if SS2.generateAPIDoc then SS2.generateAPIDoc() end
    end)
    tBtn("master dump", T.TEXT, 8, function()
        if SS2.dumpAll then SS2.dumpAll() end
    end)
    tBtn("discovery audit", T.TEXT, 9, function() if SS2.dumpAudit then SS2.dumpAudit() end end)
    tBtn("per-remote dossiers", T.TEXT, 10, function() if SS2.dumpPerRemote then SS2.dumpPerRemote() end end)
    tBtn("top call sites (console)", T.TEXT, 11, function() if SS2.topCallers then SS2.topCallers(20) end end)

    tSection("VAULT", 13)
    tBtn("export everything", T.GREEN, 14, function()
        if SS2.exportAll then SS2.exportAll() end
    end)
    tBtn("vault manifest", T.TEXT, 15, function()
        if SS2.vaultManifest then SS2.vaultManifest() end
    end)
    tBtn("caller attribution file", T.TEXT, 16, function()
        if SS2.exportCallersFull then SS2.exportCallersFull() end
    end)
    tBtn("closure graph file", T.TEXT, 17, function()
        if SS2.exportClosures then SS2.exportClosures() end
    end)
    tBtn("session summary (console)", T.DIM, 18, function()
        if SS2.vaultSummary then print(SS2.vaultSummary()) end
    end)

    tSection("HEALTH", 20)
    tBtn("capture health report", T.TEXT, 21, function()
        if SS2.healthReport then SS2.healthReport() end
    end)
    tBtn("game vocabulary (console)", T.TEXT, 22, function()
        if SS2.decomp and SS2.decomp.topConstants then SS2.decomp.topConstants(30) end
    end)

    tSection("STEALTH", 24)
    tBtn("stealth on / off", T.RED, 25, function()
        if SS2.stealth and SS2.stealth.active then
            SS2.stealthOff()
        else
            SS2.stealthOn()
        end
    end)
    tBtn("self-scan (exposure audit)", T.DIM, 26, function()
        if SS2.scanSelf then SS2.scanSelf() end
    end)
end

renderers = { renderCalls, renderRemotes, renderDecompiler, renderExplorer, renderTools }

function switchTab(i)
    currentTab = i
    for j, b in ipairs(tabBtns) do
        b.BackgroundColor3 = (j == currentTab) and T.HI or T.CARD
        b.TextColor3 = (j == currentTab) and T.TEXT or T.DIM
    end
    grepBox.Visible = (i == 1)
    if renderers[i] then renderers[i](true) end
end

for i, name in ipairs(TABS) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(78, 22)
    b.Position = UDim2.fromOffset(6 + (i - 1) * 82, 3)
    b.BackgroundColor3 = T.CARD
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 11
    b.TextColor3 = (i == 1) and T.TEXT or T.DIM
    b.Text = name
    addCorner(b)
    b.Parent = tabStrip
    b.MouseButton1Click:Connect(function()
        switchTab(i)
    end)
    tabBtns[i] = b
end

grepBox:GetPropertyChangedSignal("Text"):Connect(function()
    if currentTab == 1 then renderCalls(true) end
end)

task.spawn(function()
    while gui.Parent do
        if currentTab == 1 and not lockedCallId and pinned and not minimized then
            pcall(renderCalls)
        end
        local rc = 0
        for _ in pairs(SS2.remotes) do rc = rc + 1 end
        status.Text = ("  %d remotes · %d calls · %.0f c/s · net:%s · %s"):format(
            rc, #SS2.log,
            SS2.health and SS2.health.callsEMA or 0,
            tostring(SS2.metaHooked),
            lockedCallId and "LOCKED" or (pinned and "LIVE" or ""))
        task.wait(2)
    end
end)

switchTab(1)

SS2.gui = gui
print("[SS2-ui] v5.0 LIVE — 5 tabs, explorer integrated, clean build")
