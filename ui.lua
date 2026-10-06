--[[
    simplyspirited v4.7 — interface
    SHADOWMILESC / computerizedcarrier2

    v4.7 fixes, in the author's words:
    - selection no longer snaps to newest. selecting = locking.
      a LIVE button returns you to the feed. explicit beats magic.
    - differential rendering. the sidebar updates in place;
      full rebuilds happen only when the log length changes.
      the every-second stutter on heavy games dies here.
    - layout: professional density. sections labeled. spacing
      that groups. still monospace, still dark, still ours.
]]

print("[SS2-ui] v4.7 building...")

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local P = Players.LocalPlayer

pcall(function()
    local root = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
    local o = root:FindFirstChild("SS2_Interface")
    if o then o:Destroy() end
end)

-- ═══ palette: professional dark. hierarchy by lightness. ═══
local T = {
    BG     = Color3.fromRGB(12, 12, 14),
    RAIL   = Color3.fromRGB(19, 19, 23),
    CARD   = Color3.fromRGB(26, 26, 31),
    HI     = Color3.fromRGB(34, 34, 40),     -- highlighted card
    TEXT   = Color3.fromRGB(225, 225, 228),
    DIM    = Color3.fromRGB(115, 115, 122),
    FAINT  = Color3.fromRGB(70, 70, 76),
    ACCENT = Color3.fromRGB(90, 140, 250),
    RED    = Color3.fromRGB(210, 70, 80),
    GREEN  = Color3.fromRGB(70, 190, 120),
}
SS2.theme = T

local function corner(o, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 4)
    c.Parent = o
end
local function stroke(o, col)
    local s = Instance.new("UIStroke")
    s.Color = col or T.HI
    s.Thickness = 1
    s.Parent = o
end

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

-- ═══ state — one section, complete ═══
local win, tabStrip, content, status
local tabBtns = {}
local currentTab = 1
local pinned = true            -- live mode follows newest
local lockedCallId = nil       -- selected call (locks the view)
local lockedRemote = nil       -- selected remote
local grepCtx = ""
local lastRenderCount = -1     -- differential render trigger
local lastGrep = ""
local renderers = {}

-- ═══ WINDOW: 520x360 professional density ═══
win = Instance.new("Frame")
win.Size = UDim2.fromOffset(520, 360)
win.Position = UDim2.fromOffset(30, 40)
win.BackgroundColor3 = T.BG
win.BorderSizePixel = 0
win.Active = true
corner(win, 6)
win.Parent = gui

-- header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 30)
header.BackgroundColor3 = T.RAIL
header.BorderSizePixel = 0
header.Parent = win

local hDot = Instance.new("Frame")
hDot.Size = UDim2.fromOffset(8, 8)
hDot.Position = UDim2.fromOffset(10, 11)
hDot.BackgroundColor3 = T.GREEN
hDot.BorderSizePixel = 0
corner(hDot, 4)
hDot.Parent = header

local hTitle = Instance.new("TextLabel")
hTitle.Size = UDim2.new(0, 250, 1, 0)
hTitle.Position = UDim2.fromOffset(24, 0)
hTitle.BackgroundTransparency = 1
hTitle.Font = Enum.Font.GothamMedium
hTitle.TextSize = 12
hTitle.TextColor3 = T.TEXT
hTitle.TextXAlignment = Enum.TextXAlignment.Left
hTitle.Text = "SIMPLYSPIRITED"
hTitle.Parent = header

local hSub = Instance.new("TextLabel")
hSub.Size = UDim2.new(0, 100, 1, 0)
hSub.Position = UDim2.new(0, 140, 0, 0)
hSub.BackgroundTransparency = 1
hSub.Font = Enum.Font.Code
hSub.TextSize = 10
hSub.TextColor3 = T.FAINT
hSub.TextXAlignment = Enum.TextXAlignment.Left
hSub.Text = "v4.7"
hSub.Parent = header

local hClose = Instance.new("TextButton")
hClose.Size = UDim2.fromOffset(24, 30)
hClose.Position = UDim2.new(1, -26, 0, 0)
hClose.BackgroundTransparency = 1
hClose.Font = Enum.Font.Code
hClose.TextSize = 13
hClose.TextColor3 = T.DIM
hClose.Text = "✕"
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
hClose.MouseButton1Click:Connect(function()
    gui:Destroy()
end)

-- ═══ TABS ═══
local TABS = { "CALLS", "REMOTES", "DECOMPILER", "TOOLS" }
tabStrip = Instance.new("Frame")
tabStrip.Size = UDim2.new(1, 0, 0, 28)
tabStrip.Position = UDim2.new(0, 0, 0, 30)
tabStrip.BackgroundColor3 = T.RAIL
tabStrip.BorderSizePixel = 0
tabStrip.Parent = win

local tabBtns = {}
local switchTab

for i, name in ipairs(TABS) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 86, 1, 0)
    b.Position = UDim2.new(0, 6 + (i - 1) * 90, 0, 0)
    b.BackgroundColor3 = T.CARD
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 11
    b.TextColor3 = (i == 1) and T.TEXT or T.DIM
    b.Text = name
    corner(b, 4)
    b.Parent = tabStrip
    b.MouseButton1Click:Connect(function()
        switchTab(i)
    end)
    tabBtns[i] = b
end

local function updateTabVisual()
    for j, b in ipairs(tabBtns) do
        b.BackgroundColor3 = (j == currentTab) and T.HI or T.CARD
        b.TextColor3 = (j == currentTab) and T.TEXT or T.DIM
    end
end

-- grep (calls tab)
local grepBox = Instance.new("TextBox")
grepBox.Size = UDim2.new(1, -190, 0, 24)
grepBox.Position = UDim2.new(0, 380, 0, 32)
grepBox.BackgroundColor3 = T.CARD
grepBox.PlaceholderText = "filter…"
grepBox.Text = ""
grepBox.Font = Enum.Font.Code
grepBox.TextSize = 11
grepBox.TextColor3 = T.TEXT
grepBox.PlaceholderColor3 = T.FAINT
grepBox.ClearTextOnFocus = false
corner(grepBox, 4)
grepBox.Parent = win

-- ═══ CONTENT ═══
content = Instance.new("ScrollingFrame")
content.Size = UDim2.new(1, -16, 1, -98)
content.Position = UDim2.fromOffset(8, 66)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ScrollBarThickness = 4
content.ScrollBarImageColor3 = T.FAINT
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.CanvasSize = UDim2.new(0, 0, 0, 0)
content.Parent = win
local cLayout = Instance.new("UIListLayout")
cLayout.Padding = UDim.new(0, 2)
cLayout.SortOrder = Enum.SortOrder.LayoutOrder
cLayout.Parent = content

-- status bar
status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -16, 0, 20)
status.Position = UDim2.new(0, 8, 1, -26)
status.BackgroundColor3 = T.RAIL
status.Font = Enum.Font.Code
status.TextSize = 10
status.TextColor3 = T.DIM
status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = ""
corner(status, 4)
status.Parent = win

-- ═══ MAIN PANEL HELPERS ═══
function clearMain()
    for _, c in ipairs(content:GetChildren()) do
        if c:IsA("TextLabel") or c:IsA("TextButton") or c:IsA("Frame") then c:Destroy() end
    end
end

local function tLine(txt, col, order, size, bold)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -8, 0, size or 16)
    l.Position = UDim2.fromOffset(6, 0)
    l.BackgroundTransparency = 1
    l.Font = bold and Enum.Font.GothamMedium or Enum.Font.Code
    l.TextSize = size or 12
    l.TextColor3 = col or T.TEXT
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Text = txt
    l.LayoutOrder = order
    l.Parent = content
    return l
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
    corner(s, 4)
    s.Parent = content
    return s
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
    corner(b, 4)
    b.MouseButton1Click:Connect(cb)
    b.Parent = content
    return b
end

-- ═══ DETAIL VIEWS (before click handlers — the v4.2 lesson, permanent) ═══
local function showCallDetail(id)
    for _, rec in ipairs(SS2.log) do
        if rec.id == id then
            clearMain()
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
                tLine("", T.DIM, 30)
                tSection("CALLERS", 31)
                local cs = {}
                for c, n in pairs(prof.callers) do cs[#cs+1] = { c=c, n=n } end
                table.sort(cs, function(a,b) return a.n > b.n end)
                for k, e in ipairs(cs) do
                    tLine(("  %s  x%d"):format(e.c, e.n), T.DIM, 31 + k)
                end
            end
            -- live button
            tLine("", T.DIM, 60)
            tBtn("← BACK TO LIVE FEED", T.ACCENT, 61, function()
                lockedCallId = nil
                lockedRemote = nil
                pinned = true
                lastRenderCount = -1
                switchTab(1)
            end)
            return
        end
    end
end

local function showRemoteDetail(r, prof)
    clearMain()
    tSection("REMOTE — " .. r.Name .. "  (" .. prof.class .. ")", 1)
    tLine("path    " .. (prof.path or "?"), T.DIM, 2)
    tLine("calls   " .. prof.calls .. "  (out " .. prof.out .. " / in " .. prof.inn .. ")", T.TEXT, 3)
    tLine("net     " .. tostring(prof.metaCaught or 0) .. " caught", T.DIM, 4)
    tLine("seen    " .. prof.firstSeen .. " → " .. prof.lastSeen, T.DIM, 5)
    local sigs = {}
    for s, n in pairs(prof.sigs) do sigs[#sigs+1] = { s=s, n=n } end
    table.sort(sigs, function(a,b) return a.n > b.n end)
    if #sigs > 0 then
        tLine("", T.DIM, 6)
        tSection("SIGNATURES — " .. #sigs .. " unique", 7)
        for k = 1, math.min(24, #sigs) do
            tLine(("  x%d  %s"):format(sigs[k].n, sigs[k].s), T.TEXT, 7 + k)
        end
    end
    if prof.callers and next(prof.callers) then
        tLine("", T.DIM, 40)
        tSection("CALLERS", 41)
        local cs = {}
        for c, n in pairs(prof.callers) do cs[#cs+1] = { c=c, n=n } end
        table.sort(cs, function(a,b) return a.n > b.n end)
        for k, e in ipairs(cs) do
            tLine(("  %s  x%d"):format(e.c, e.n), T.DIM, 41 + k)
        end
    end
    tLine("", T.DIM, 70)
    tBtn("← BACK TO LIVE FEED", T.ACCENT, 71, function()
        lockedRemote = nil
        pinned = true
        lastRenderCount = -1
        switchTab(1)
    end)
end

-- ═══ RENDERERS ═══
-- CALLS: differential. full rebuild only when log length changed
-- or grep changed. selection locks the view entirely.
local function renderCalls(force)
    local rebuild = force
        or (lockedCallId ~= nil)      -- locked view: rebuild on demand only
        or (#SS2.log ~= lastRenderCount)  -- new calls arrived
        or (grepCtx ~= lastGrep)          -- filter changed

    if not rebuild then return end
    lastRenderCount = #SS2.log
    lastGrep = grepCtx

    clearContent()
    local n = 0
    for i = #SS2.log, 1, -1 do
        local rec = SS2.log[i]
        local hay = (rec.name .. " " .. table.concat(rec.args, " ")):lower()
        if grepCtx == "" or hay:find(grepCtx, 1, true) then
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
            corner(b, 4)
            b.MouseButton1Click:Connect(function()
                lockedCallId = id
                pinned = false
                showCallDetail(id)
            end)
            b.Parent = content
            if n > 100 then
                tLine("  … (100+ — filter to narrow)", T.DIM, n + 1)
                break
            end
        end
    end
    if n == 0 then
        tLine(grepCtx ~= "" and ("no matches — " .. grepCtx) or "no calls yet — play the game", T.DIM, 1)
    end
end

local function renderRemotes(force)
    if not force and lockedRemote then return end -- locked view persists
    clearContent()
    local ranked = {}
    for r, prof in pairs(SS2.remotes) do
        ranked[#ranked+1] = { r=r, p=prof }
    end
    table.sort(ranked, function(a,b) return a.p.calls > b.p.calls end)
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
        corner(b, 4)
        b.MouseButton1Click:Connect(function()
            lockedRemote = rr
            showRemoteDetail(rr, pp)
        end)
        b.Parent = content
    end
end

local decompSel = nil
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
        tBtn((sel == cname and "● " or "○ ") .. cname, sel == cname and T.TEXT or T.DIM, 4 + i, function()
            SS2._dcontainer = cname
            renderDecompiler(true)
        end)
    end

    tLine("", T.DIM, 10)
    local base = 11
    tBtn("QUICK — config/main/init/network scripts", T.TEXT, base + 1, function()
        if SS2.decomp.quick then SS2.decomp.quick() end
    end)
    tBtn("BULK DUMP — " .. sel .. " (200 scripts)", T.TEXT, base + 2, function()
        if SS2.decomp.bulk then SS2.decomp.bulk(sel, 200) end
    end)
    tBtn("SCRIPT TREE — console view", T.DIM, base + 3, function()
        if SS2.decomp.tree then SS2.decomp.tree(sel) end
    end)

    tLine("", T.DIM, base + 5)
    tSection("OUTPUT", base + 6)
    tLine("  SimplySpirited/decomp/ → workspace", T.DIM, base + 7)
    tLine("  .src.lua · .bytecode · .constants.txt", T.DIM, base + 8)
    tLine("  ★ xref = script references a seen remote", T.GREEN, base + 9)
end

local function renderTools(force)
    clearContent()
    tSection("CAPTURE", 1)
    tBtn("pause / resume capture", T.TEXT, 2, function() SS2.togglePause() end)
    tBtn("verbosity: " .. tostring(SS2.verbosity) .. " (cycle)", T.TEXT, 3, function()
        local map = { quiet = "smart", smart = "loud", loud = "quiet" }
        SS2.setVerbosity and SS2.setVerbosity(map[SS2.verbosity] or "smart")
        renderTools(true)
    end)
    tBtn("rescan remotes now", T.TEXT, 4, function() SS2.scanRemotes() end)

    tSection("INTEL", 6)
    tBtn("generate API documentation", T.TEXT, 7, function() SS2.generateAPIDoc() end)
    tBtn("master dump", T.TEXT, 8, function() SS2.dumpAll() end)
    tBtn("discovery audit", T.TEXT, 9, function() SS2.dumpAudit() end)
    tBtn("per-remote dossiers", T.TEXT, 10, function() SS2.dumpPerRemote() end)
    tBtn("top call sites (console)", T.TEXT, 11, function() SS2.topCallers(20) end)

    tSection("VAULT", 13)
    tBtn("export everything", T.GREEN, 14, function() SS2.exportAll() end)
    tBtn("vault manifest", T.TEXT, 15, function() SS2.vaultManifest() end)
    tBtn("caller attribution file", T.TEXT, 16, function() SS2.exportCallersFull() end)
    tBtn("closure graph file", T.TEXT, 17, function() SS2.exportClosures() end)
    tBtn("session summary (console)", T.DIM, 18, function() print(SS2.vaultSummary()) end)

    tSection("HEALTH", 20)
    tBtn("capture health report", T.TEXT, 21, function() SS2.healthReport() end)
    tBtn("game vocabulary (console)", T.TEXT, 22, function() SS2.decomp.topConstants(30) end)

    tSection("STEALTH", 24)
    tBtn("stealth on / off", T.RED, 25, function()
        if SS2.stealth.active then SS2.stealthOff() else SS2.stealthOn() end
    end)
    tBtn("self-scan (exposure audit)", T.DIM, 26, function() SS2.scanSelf() end)
end

renderers = { renderCalls, renderRemotes, renderDecompiler, renderTools }

function switchTab(i)
    currentTab = i
    updateTabVisual()
    grepBox.Visible = (i == 1)
    if renderers[i] then renderers[i](true) end
end

-- grep live
grepBox:GetPropertyChangedSignal("Text"):Connect(function()
    grepCtx = grepBox.Text:lower()
    if currentTab == 1 then renderCalls(true) end
end)

-- ═══ REFRESH LOOP (v4.7: differential + selection-lock) ═══
task.spawn(function()
    while gui.Parent do
        -- calls tab: rebuild ONLY when new calls arrive
        if currentTab == 1 and not lockedCallId and not minimized then
            pcall(renderCalls)
        end
        local rc = 0
        for _ in pairs(SS2.remotes) do rc = rc + 1 end
        status.Text = ("  %d remotes · %d calls · %.0f c/s · net:%s · %s"):format(
            rc, #SS2.log,
            SS2.health and SS2.health.callsEMA or 0,
            tostring(SS2.metaHooked),
            lockedCallId and "LOCKED" or (pinned and "LIVE" or ""))
        task.wait(1)
    end
end)

switchTab(1)

SS2.gui = gui
print("[SS2-ui] v4.7 LIVE — selection locks, differential render, no stutter")
