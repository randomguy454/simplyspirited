--[[
    simplyspirited v4.7 — explorer
    SHADOWMILESC / computerizedcarrier2

    dex-style anatomy browser + script harvester.

    browse the DataModel, inspect instances (remotes show
    capture profiles, values offer watch, scripts offer
    decompile) — and the HARVEST feature:

      select a container (game root / ReplicatedStorage /
      Players / workspace) → detail pane shows
      "★ HARVEST ALL SCRIPTS" → one click walks the whole
      container, captures bytecode + source for every script,
      writes them to SimplySpirited/harvest/, and generates
      scripts_manifest.txt with every script name + path.

    harvest is bounded (500 default) with live progress.
]]

print("[SS2-explorer] v4.7 loading...")

local SS2 = getgenv().SS2
if not SS2 then
    warn("ss2-explorer: core.lua must load first")
    return
end

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local P = Players.LocalPlayer

pcall(function()
    local root = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
    local o = root:FindFirstChild("SS2_Explorer")
    if o then o:Destroy() end
end)

local T = {
    BG   = Color3.fromRGB(8, 8, 8),
    RAIL = Color3.fromRGB(13, 13, 13),
    TEXT = Color3.fromRGB(215, 215, 215),
    DIM  = Color3.fromRGB(100, 100, 100),
    RED  = Color3.fromRGB(200, 40, 50),
}

local gui = Instance.new("ScreenGui")
gui.Name = "SS2_Explorer"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9998
do
    local ok = pcall(function()
        gui.Parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
    end)
    if not ok then gui.Parent = P:WaitForChild("PlayerGui") end
end

-- ═══ window ═══
local win = Instance.new("Frame")
win.Size = UDim2.fromOffset(460, 340)
win.Position = UDim2.fromOffset(480, 40)
win.BackgroundColor3 = T.BG
win.BorderSizePixel = 0
win.Active = true
win.Parent = gui

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 20)
header.BackgroundColor3 = T.RAIL
header.BorderSizePixel = 0
header.Parent = win

local hTitle = Instance.new("TextLabel")
hTitle.Size = UDim2.new(0, 200, 1, 0)
hTitle.Position = UDim2.fromOffset(8, 0)
hTitle.BackgroundTransparency = 1
hTitle.Font = Enum.Font.Code
hTitle.TextSize = 11
hTitle.TextColor3 = T.TEXT
hTitle.TextXAlignment = Enum.TextXAlignment.Left
hTitle.Text = "ss2 explorer"
hTitle.Parent = header

local hClose = Instance.new("TextButton")
hClose.Size = UDim2.fromOffset(18, 20)
hClose.Position = UDim2.new(1, -22, 0, 0)
hClose.BackgroundTransparency = 1
hClose.Font = Enum.Font.Code
hClose.TextSize = 12
hClose.TextColor3 = T.DIM
hClose.Text = "x"
hClose.Parent = header
hClose.MouseButton1Click:Connect(function() gui:Destroy() end)

local dragging = false
local dStart, dPos
header.InputBegan:Connect(function(i)
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

-- ═══ nav bar ═══
local navBar = Instance.new("Frame")
navBar.Size = UDim2.new(1, 0, 0, 20)
navBar.Position = UDim2.new(0, 0, 0, 20)
navBar.BackgroundColor3 = T.RAIL
navBar.BorderSizePixel = 0
navBar.Parent = win

local upBtn = Instance.new("TextButton")
upBtn.Size = UDim2.fromOffset(28, 20)
upBtn.Position = UDim2.fromOffset(2, 0)
upBtn.BackgroundTransparency = 1
upBtn.Font = Enum.Font.Code
upBtn.TextSize = 11
upBtn.TextColor3 = T.TEXT
upBtn.Text = "↑"
upBtn.Parent = navBar

local crumb = Instance.new("TextLabel")
crumb.Size = UDim2.new(1, -40, 1, 0)
crumb.Position = UDim2.fromOffset(34, 0)
crumb.BackgroundTransparency = 1
crumb.Font = Enum.Font.Code
crumb.TextSize = 10
crumb.TextColor3 = T.DIM
crumb.TextXAlignment = Enum.TextXAlignment.Left
crumb.TextTruncate = Enum.TextTruncate.AtEnd
crumb.Text = "game"
crumb.Parent = navBar

-- ═══ search ═══
local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(1, -12, 0, 16)
searchBox.Position = UDim2.fromOffset(6, 42)
searchBox.BackgroundColor3 = T.RAIL
searchBox.BorderSizePixel = 0
searchBox.PlaceholderText = "search game by name…"
searchBox.Text = ""
searchBox.Font = Enum.Font.Code
searchBox.TextSize = 10
searchBox.TextColor3 = T.TEXT
searchBox.PlaceholderColor3 = T.DIM
searchBox.ClearTextOnFocus = false
searchBox.TextXAlignment = Enum.TextXAlignment.Left
searchBox.Parent = win

-- ═══ panes ═══
local treePane = Instance.new("ScrollingFrame")
treePane.Size = UDim2.new(0, 210, 1, -112)
treePane.Position = UDim2.fromOffset(0, 62)
treePane.BackgroundColor3 = T.RAIL
treePane.BorderSizePixel = 0
treePane.ScrollBarThickness = 2
treePane.ScrollBarImageColor3 = T.DIM
treePane.AutomaticCanvasSize = Enum.AutomaticSize.Y
treePane.CanvasSize = UDim2.new(0, 0, 0, 0)
treePane.Parent = win
do
    local l = Instance.new("UIListLayout")
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = treePane
end

local detailPane = Instance.new("ScrollingFrame")
detailPane.Size = UDim2.new(1, -218, 1, -112)
detailPane.Position = UDim2.fromOffset(218, 62)
detailPane.BackgroundColor3 = T.BG
detailPane.BorderSizePixel = 0
detailPane.ScrollBarThickness = 2
detailPane.ScrollBarImageColor3 = T.DIM
detailPane.AutomaticCanvasSize = Enum.AutomaticSize.Y
detailPane.CanvasSize = UDim2.new(0, 0, 0, 0)
detailPane.Parent = win
do
    local l = Instance.new("UIListLayout")
    l.Padding = UDim.new(0, 1)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = detailPane
end

-- ═══ status line (bottom) ═══
local statusLine = Instance.new("TextLabel")
statusLine.Size = UDim2.new(1, -8, 0, 14)
statusLine.Position = UDim2.new(0, 6, 1, -18)
statusLine.BackgroundColor3 = T.RAIL
statusLine.BorderSizePixel = 0
statusLine.Font = Enum.Font.Code
statusLine.TextSize = 10
statusLine.TextColor3 = T.DIM
statusLine.TextXAlignment = Enum.TextXAlignment.Left
statusLine.Text = "ready"
statusLine.Parent = win

-- ═══ navigation state ═══
local current = game
local history = {}
local harvestRunning = false

local function classTag(c)
    if c == "RemoteEvent" or c == "RemoteFunction" then return "[R]" end
    if c == "LocalScript" or c == "ModuleScript" or c == "Script" then return "[S]" end
    if c:find("Value") then return "[V]" end
    if c == "Model" or c == "Folder" then return "[F]" end
    return " · "
end

local function clearTree()
    for _, c in ipairs(treePane:GetChildren()) do
        if c:IsA("TextButton") or c:IsA("TextLabel") then c:Destroy() end
    end
end

local function clearDetail()
    for _, c in ipairs(detailPane:GetChildren()) do
        if c:IsA("TextLabel") or c:IsA("TextButton") then c:Destroy() end
    end
end

local function dLine(txt, col, order)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -8, 0, 14)
    l.Position = UDim2.fromOffset(5, 0)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Code
    l.TextSize = 10
    l.TextColor3 = col or T.TEXT
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Text = tostring(txt)
    l.LayoutOrder = order
    l.Parent = detailPane
    return l
end

local function dAction(txt, col, order, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -8, 0, 16)
    b.Position = UDim2.fromOffset(5, 0)
    b.BackgroundTransparency = 1
    b.Font = Enum.Font.Code
    b.TextSize = 10
    b.TextColor3 = col or T.TEXT
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Text = "> " .. tostring(txt)
    b.LayoutOrder = order
    b.MouseButton1Click:Connect(cb)
    b.Parent = detailPane
    return b
end

-- ═══ safe property collector ═══
local function collectProps(inst)
    local props = {}
    local readers = {
        { "position",  function() return tostring(inst.Position) end,  "BasePart" },
        { "size",      function() return tostring(inst.Size) end,      "BasePart" },
        { "anchored",  function() return tostring(inst.Anchored) end,  "BasePart" },
        { "material",  function() return tostring(inst.Material) end,  "BasePart" },
        { "health",    function() return tostring(inst.Health) end,    "Humanoid" },
        { "walkSpeed", function() return tostring(inst.WalkSpeed) end, "Humanoid" },
        { "userId",    function() return tostring(inst.UserId) end,    "Player" },
        { "team",      function() return tostring(inst.Team) end,      "Player" },
        { "meshId",    function() return tostring(inst.MeshId) end,    "MeshPart" },
        { "value",     function() return tostring(inst.Value) end,     "ValueBase" },
        { "text",      function() return tostring(inst.Text) end,      "TextLabel" },
    }
    for _, r in ipairs(readers) do
        if inst:IsA(r.cls) then
            local ok, val = pcall(r.read)
            if ok and val ~= nil then
                props[#props + 1] = { label = r.label, value = val }
            end
        end
    end
    return props
end

-- ═══ HARVEST ENGINE ═══
local function harvestScripts(containerName, maxScripts)
    if harvestRunning then
        print("[harvest] already running")
        return
    end
    harvestRunning = true
    containerName = containerName or "ReplicatedStorage"
    maxScripts = maxScripts or 500
    task.spawn(function()
        pcall(function()
            makefolder("SimplySpirited")
            makefolder("SimplySpirited/harvest")
        end)

        local root = containerName == "Players" and P or game:GetService(containerName)
        local nSrc, nBC, nFail = 0, 0, 0
        local manifest = {
            "SIMPLYSPIRITED SCRIPT HARVEST",
            "container: " .. containerName .. " | date: " .. os.date(),
            "operator: SHADOWMILESC (computerizedcarrier2)",
            "format: [type] name | path | size",
            "════════════════════════════════",
        }

        for _, d in ipairs(root:GetDescendants()) do
            if (nSrc + nBC + nFail) >= maxScripts then break end
            if d:IsA("LocalScript") or d:IsA("ModuleScript") then
                local clean = d:GetFullName():gsub("[^%w_]", "_"):sub(1, 130)
                local fullPath = d:GetFullName()
                local got = false

                local okS, src = pcall(function() return d.Source end)
                if okS and type(src) == "string" and #src > 0 then
                    pcall(function()
                        writefile("SimplySpirited/harvest/" .. clean .. ".src.lua",
                            "-- " .. fullPath .. "\n" .. src)
                    end)
                    nSrc = nSrc + 1
                    manifest[#manifest + 1] = ("[SRC] %s | %s | %d chars"):format(
                        d.Name, fullPath, #src)
                    got = true
                end

                local okB, bc = pcall(function() return getscriptbytecode(d) end)
                if okB and type(bc) == "string" and #bc > 0 then
                    pcall(function()
                        writefile("SimplySpirited/harvest/" .. clean .. ".bytecode", bc)
                    end)
                    nBC = nBC + 1
                    if got then
                        manifest[#manifest + 1] = ("[BC+] %s | %s | %d bytes"):format(
                            d.Name, fullPath, #bc)
                    else
                        manifest[#manifest + 1] = ("[BC ] %s | %s | %d bytes"):format(
                            d.Name, fullPath, #bc)
                    end
                    got = true
                end

                if not got then
                    nFail = nFail + 1
                    manifest[#manifest + 1] = ("[---] %s | %s | INACCESSIBLE"):format(
                        d.Name, fullPath)
                end

                statusLine.Text = "harvest: " .. (nSrc + nBC) .. " captured, " .. nFail .. " failed"
                task.wait()
            end
        end

        manifest[#manifest + 1] = "════════════════════════════════"
        manifest[#manifest + 1] = ("totals: %d source | %d bytecode | %d failed | %d total"):format(
            nSrc, nBC, nFail, nSrc + nBC + nFail)

        pcall(function()
            writefile("SimplySpirited/harvest/scripts_manifest.txt",
                table.concat(manifest, "\n"))
        end)

        harvestRunning = false
        statusLine.Text = "harvest done: " .. nSrc .. " src + " .. nBC .. " bc -> harvest/"
        print(("[harvest] DONE: %d source, %d bytecode, %d failed"):format(nSrc, nBC, nFail))
        print("[harvest] scripts_manifest.txt lists every script name + path")
    end)
end
SS2.harvestScripts = harvestScripts

-- ═══ DETAIL VIEW ═══
local function showDetail(inst)
    if not inst or not inst.Parent then
        clearDetail()
        dLine("(invalid instance)", T.DIM, 1)
        return
    end
    clearDetail()
    local n = 0

    dLine("name:  " .. tostring(inst.Name), T.TEXT, n + 1)
    n = n + 1
    dLine("class: " .. inst.ClassName, T.RED, n + 1)
    n = n + 1

    local okPar, parName = pcall(function() return inst.Parent and inst.Parent.Name end)
    if okPar and parName then
        dLine("parent: " .. parName, T.DIM, n + 1)
        n = n + 1
    end

    -- HARVEST: containers offer full script extraction
    local isHarvestable = (inst == game) or inst:IsA("ReplicatedStorage")
        or inst:IsA("Players") or inst:IsA("StarterPlayer") or inst == workspace
    if isHarvestable then
        dAction("★ HARVEST ALL SCRIPTS (bytecode + names)", T.RED, n + 1, function()
            local cName = "ReplicatedStorage"
            if inst == workspace then cName = "workspace"
            elseif inst:IsA("Players") then cName = "Players"
            elseif inst:IsA("StarterPlayer") then cName = "StarterPlayer" end
            harvestScripts(cName, 500)
        end)
        n = n + 1
    end

    -- remote capture profile
    if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") then
        local prof = SS2.remotes[inst]
        if prof then
            n = n + 1
            dLine("── capture profile ──", T.DIM, n)
            n = n + 1
            dLine("calls: " .. prof.calls .. " (out " .. prof.out .. " / in " .. prof.inn .. ")", T.TEXT, n)
            n = n + 1
            if (prof.metaCaught or 0) > 0 then
                dLine("net-caught: " .. prof.metaCaught, T.DIM, n)
                n = n + 1
            end
            local sigs = {}
            for sig, cnt in pairs(prof.sigs) do
                sigs[#sigs + 1] = { s = sig, c = cnt }
            end
            table.sort(sigs, function(a, b) return a.c > b.c end)
            for k = 1, math.min(5, #sigs) do
                dLine("  sig[" .. sigs[k].c .. "x] " .. tostring(sigs[k].s):sub(1, 60), T.DIM, n)
                n = n + 1
            end
            if SS2.profileRemote then
                dAction("full profile (console)", T.TEXT, n + 1, function()
                    SS2.profileRemote(inst.Name)
                end)
                n = n + 1
            end
        else
            dLine("(not captured yet — profiles on first fire)", T.DIM, n + 1)
            n = n + 1
        end
    end

    -- value
    if inst:IsA("ValueBase") then
        local okV, val = pcall(function() return inst.Value end)
        if okV then
            dLine("value: " .. tostring(val), T.TEXT, n + 1)
            n = n + 1
        end
        if SS2.watchValue then
            dAction("watch this value", T.RED, n + 1, function()
                SS2.watchValue(inst)
            end)
            n = n + 1
        end
    end

    -- script
    if inst:IsA("LocalScript") or inst:IsA("ModuleScript") then
        local okS, src = pcall(function() return inst.Source end)
        if okS and type(src) == "string" and #src > 0 then
            dLine("source: " .. #src .. " chars", T.TEXT, n + 1)
            n = n + 1
        else
            dLine("source: inaccessible", T.DIM, n + 1)
            n = n + 1
        end
        if SS2.decomp and SS2.decomp.script then
            dAction("decompile (6-layer)", T.RED, n + 1, function()
                SS2.decomp.script(inst)
            end)
            n = n + 1
        end
    end

    -- safe properties
    local props = collectProps(inst)
    if #props > 0 then
        dLine("── properties ──", T.DIM, n + 1)
        n = n + 1
        for _, p in ipairs(props) do
            dLine("  " .. p.label .. " = " .. tostring(p.value), T.TEXT, n)
            n = n + 1
        end
    end

    -- descendants
    local okC, census, total = pcall(function()
        local counts, tot = {}, 0
        for _, d in ipairs(inst:GetDescendants()) do
            tot = tot + 1
            counts[d.ClassName] = (counts[d.ClassName] or 0) + 1
        end
        return counts, tot
    end)
    if okC and total and total > 0 then
        dLine("── descendants (" .. total .. ") ──", T.DIM, n + 1)
        n = n + 1
        local sorted = {}
        for cls, cnt in pairs(census) do
            sorted[#sorted + 1] = { cls = cls, n = cnt }
        end
        table.sort(sorted, function(a, b) return a.n > b.n end)
        for k = 1, math.min(8, #sorted) do
            dLine("  " .. sorted[k].cls .. ": " .. sorted[k].n, T.DIM, n)
            n = n + 1
        end
    end

    dAction("copy full path", T.TEXT, n + 2, function()
        if setclipboard then setclipboard(inst:GetFullName()) end
    end)
    if inst:IsA("LocalScript") or inst:IsA("ModuleScript") then
        dAction("full decompile report", T.RED, n + 3, function()
            if SS2.decomp and SS2.decomp.script then SS2.decomp.script(inst) end
        end)
    end
end

-- ═══ TREE ═══
local function renderTree()
    clearTree()
    local ok, children = pcall(function() return current:GetChildren() end)
    if not ok then
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, -6, 0, 16)
        l.BackgroundTransparency = 1
        l.Font = Enum.Font.Code
        l.TextSize = 10
        l.TextColor3 = T.DIM
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Text = "(cannot read children)"
        l.Parent = treePane
        return
    end

    local sorted = {}
    for _, c in ipairs(children) do
        sorted[#sorted + 1] = c
    end
    table.sort(sorted, function(a, b)
        local ra = (a:IsA("RemoteEvent") or a:IsA("RemoteFunction")) and 0 or 1
        local rb = (b:IsA("RemoteEvent") or b:IsA("RemoteFunction")) and 0 or 1
        if ra ~= rb then return ra < rb end
        return a.Name < b.Name
    end)

    for i, c in ipairs(sorted) do
        if i > 150 then
            local l = Instance.new("TextLabel")
            l.Size = UDim2.new(1, -6, 0, 16)
            l.BackgroundTransparency = 1
            l.Font = Enum.Font.Code
            l.TextSize = 10
            l.TextColor3 = T.DIM
            l.TextXAlignment = Enum.TextXAlignment.Left
            l.Text = "… (150 shown)"
            l.Parent = treePane
            break
        end
        local inst = c
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -6, 0, 16)
        b.BackgroundColor3 = T.BG
        b.BorderSizePixel = 0
        b.Font = Enum.Font.Code
        b.TextSize = 10
        b.TextColor3 = (inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction")) and T.RED or T.TEXT
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.TextTruncate = Enum.TextTruncate.AtEnd
        b.Text = classTag(inst.ClassName) .. " " .. inst.Name
        b.LayoutOrder = i
        b.MouseButton1Click:Connect(function()
            showDetail(inst)
            local okDesc, canDescend = pcall(function()
                return (inst:IsA("Model") or inst:IsA("Folder") or inst:IsA("Player")
                    or inst:IsA("Workspace") or inst == game
                    or inst:IsA("ReplicatedStorage") or inst:IsA("Players"))
                    and true or false
            end)
            if okDesc and canDescend then
                table.insert(history, current)
                current = inst
                crumb.Text = current:GetFullName()
                renderTree()
            end
        end)
        b.Parent = treePane
    end
end

upBtn.MouseButton1Click:Connect(function()
    local parent = current.Parent
    if parent then
        table.insert(history, current)
        current = parent
        crumb.Text = current:GetFullName()
        renderTree()
    end
end)

-- ═══ SEARCH ═══
local searching = false
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    local term = searchBox.Text:lower()
    if #term < 3 then
        if not searching then renderTree() end
        return
    end
    if searching then return end
    searching = true
    task.spawn(function()
        clearTree()
        local n = 0
        for _, d in ipairs(game:GetDescendants()) do
            if d.Name:lower():find(term, 1, true) then
                n = n + 1
                local inst = d
                local b = Instance.new("TextButton")
                b.Size = UDim2.new(1, -6, 0, 16)
                b.BackgroundColor3 = T.BG
                b.BorderSizePixel = 0
                b.Font = Enum.Font.Code
                b.TextSize = 10
                b.TextColor3 = (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) and T.RED or T.TEXT
                b.TextXAlignment = Enum.TextXAlignment.Left
                b.TextTruncate = Enum.TextTruncate.AtEnd
                b.Text = classTag(d.ClassName) .. " " .. d:GetFullName():sub(1, 50)
                b.LayoutOrder = n
                b.MouseButton1Click:Connect(function()
                    showDetail(inst)
                end)
                b.Parent = treePane
                if n >= 80 then break end
            end
        end
        if n == 0 then
            local l = Instance.new("TextLabel")
            l.Size = UDim2.new(1, -6, 0, 16)
            l.BackgroundTransparency = 1
            l.Font = Enum.Font.Code
            l.TextSize = 10
            l.TextColor3 = T.DIM
            l.TextXAlignment = Enum.TextXAlignment.Left
            l.Text = "(no matches)"
            l.Parent = treePane
        end
        searching = false
    end)
end)

-- ═══ boot ═══
crumb.Text = "game"
renderTree()
showDetail(game)

SS2.explorer = {
    window = gui,
    harvest = harvestScripts,
    navigate = function(inst)
        table.insert(history, current)
        current = inst
        crumb.Text = current:GetFullName()
        renderTree()
        showDetail(inst)
    end,
}

print("[SS2-explorer] v4.7 LIVE — browser + nil-safe details + bytecode harvester")
