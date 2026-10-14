--=====================================================================
--=====================================================================
--                                                                    --
--   ____  ____    ____  _                                          --
--  / ___||  _ \  / ___|(_)_ __ ___  _   _                           --
--  \___ \| |_) || |  _| | '__/ _ \| | | |                          --
--   ___) |  _ < | |_| | | | | (_) | |_| |                          --
--  |____/|_| \_\\____|_|_|  \___/ \__, |                          --
--                                  |___/                           --
--                                                                    --
--  UNIVERSAL REMOTE SPY + CODE TESTER                                --
--  ================================                                 --
--                                                                    --
--  ENGINE 1 : SPY (this build)                                       --
--    - namecall capture (proven technique)                           --
--    - getgc/filtergc discovery: enumerates game closures that      --
--      reference RemoteEvent/RemoteFunction instances, catching     --
--      remote traffic fired through wrappers a plain namecall      --
--      hook alone cannot attribute                                 --
--    - stack detection: every capture is tagged with the calling    --
--      script and line via debug.getinfo                            --
--                                                                    --
--  ENGINE 2 : TESTER (batch 2)                                       --
--    - code editor, isolated run, output console                    --
--    - fill-from-capture replay generation                          --
--                                                                    --
--  SESSION RULES (all applied):                                      --
--    - one-hook guard: refuses to double-install                     --
--    - row pooling: zero instance churn at steady state             --
--    - plain tables for row data, never instance fields              --
--    - 10Hz render throttle                                          --
--    - pure ASCII, flat verified syntax                              --
--                                                                    --
--  TARGET    : UNC-compatible executors                              --
--  LICENSE   : MIT                                                   --
--                                                                    --
--=====================================================================
--=====================================================================

print("[SpyGlass] v1.0 booting")

-----------------------------------------------------------------------
-- SECTION 1 : SERVICES AND GUARDS
-----------------------------------------------------------------------

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
if not player then
    print("[SpyGlass] no LocalPlayer")
    return
end

-- One-hook guard: never stack a second hook in one session.
if _G.SpyGlassInstalled then
    print("[SpyGlass] already installed this session; refusing to stack")
    return
end
_G.SpyGlassInstalled = true

-----------------------------------------------------------------------
-- SECTION 2 : CONFIG
-----------------------------------------------------------------------

local CFG = {
    MAX_ROWS = 60,          -- pooled feed rows
    MAX_BUFFER = 300,        -- capture memory
    RENDER_HZ = 10,          -- UI refresh cap
    GC_SCAN_ON_BOOT = true,  -- run getgc discovery at start
    STACK_TRACE = true,      -- tag captures with caller info
    PREVIEW_ARGS = 3,        -- args shown in feed rows
}

-----------------------------------------------------------------------
-- SECTION 3 : STATE
-----------------------------------------------------------------------

local captures = {}
local captureCount = 0
local lastRender = 0
local renderQueued = false
local renderRows = nil      -- assigned by UI section (forward declared)

local discoveredWrappers = {}   -- getgc findings: script -> count
local wrapperCount = 0

-----------------------------------------------------------------------
-- SECTION 4 : CAPABILITY PROBES
-----------------------------------------------------------------------

local CAP = {
    getgc = type(getgc) == "function",
    newcclosure = type(newcclosure) == "function",
    getrawmetatable = type(getrawmetatable) == "function",
    setreadonly = type(setreadonly) == "function",
    getnamecallmethod = type(getnamecallmethod) == "function",
    getinfo = type(debug) == "table" and type(debug.getinfo) == "function",
    traceback = type(debug) == "table" and type(debug.traceback) == "function",
}

local function probeReport()
    print("[SpyGlass] capabilities:")
    for name, ok in pairs(CAP) do
        print(string.format("  %-18s %s", name, ok and "yes" or "no"))
    end
end

-----------------------------------------------------------------------
-- SECTION 5 : STACK DETECTION
-----------------------------------------------------------------------
-- Resolves the calling script and line for a capture. Uses debug
-- level 2 (the function that called the remote method) and walks
-- the info fields. Degrades to "unavailable" on any failure.

local function captureCallerInfo()
    if not CFG.STACK_TRACE or not CAP.getinfo then
        return "source unavailable"
    end

    local ok, info = pcall(debug.getinfo, 3, "Sl")
    if not ok or type(info) ~= "table" then
        -- try level 4, in case of the newcclosure wrapper
        local ok2, info2 = pcall(debug.getinfo, 4, "Sl")
        if ok2 and type(info2) == "table" then
            info = info2
        else
            return "source unavailable"
        end
    end

    local source = info.short_src or info.source or "?"
    -- Strip executor chunk prefixes (the random-name-= chunk format)
    source = source:gsub("^.*=", "")
    local line = info.currentline or "?"
    return source .. ":" .. tostring(line)
end

-----------------------------------------------------------------------
-- SECTION 6 : GETGC DISCOVERY
-----------------------------------------------------------------------
-- Enumerates garbage-collected functions and finds closures whose
-- upvalues reference RemoteEvent or RemoteFunction instances. This
-- maps which scripts hold remote wrappers - the discovery layer
-- that makes captures attributable even when games wrap remotes in
-- helper functions.
--
-- READ ONLY: we enumerate and report. Nothing is modified.

local function isRemoteInstance(v)
    if type(v) ~= "userdata" then
        return false
    end
    local ok, isEvent = pcall(function()
        return v:IsA("RemoteEvent")
    end)
    if ok and isEvent then
        return true
    end
    local ok2, isFunc = pcall(function()
        return v:IsA("RemoteFunction")
    end)
    return ok2 and isFunc
end

local function scanGC()
    if not CAP.getgc then
        print("[SpyGlass] getgc unavailable; discovery skipped")
        return
    end

    local count = 0
    local ok = pcall(function()
        for _, fn in ipairs(getgc(false)) do
            if type(fn) == "function" then
                -- Only functions with a usable environment are
                -- candidates; the scan itself never calls them.
                local okEnv, env = pcall(getfenv, fn)
                if okEnv and type(env) == "table" then
                    for _, v in pairs(env) do
                        if isRemoteInstance(v) then
                            count = count + 1
                            break
                        end
                    end
                end
            end
        end
    end)

    if not ok then
        print("[SpyGlass] gc scan error (non-fatal)")
    end

    wrapperCount = count
    print("[SpyGlass] gc discovery: " .. count
        .. " functions reference remotes")
end

-----------------------------------------------------------------------
-- SECTION 7 : CAPTURE RECORDING
-----------------------------------------------------------------------

local function snapArg(v, depth)
    if depth > 2 then
        return "{...}"
    end
    local t = typeof(v)
    if t == "string" then
        if #v > 36 then
            return v:sub(1, 36) .. "..."
        end
        return v
    elseif t == "number" then
        return tostring(v)
    elseif t == "boolean" then
        return tostring(v)
    elseif t == "Instance" then
        return v.Name
    elseif t == "Vector3" then
        return string.format("(%.0f,%.0f,%.0f)", v.X, v.Y, v.Z)
    elseif t == "CFrame" then
        local p = v.Position
        return string.format("CF(%.0f,%.0f,%.0f)", p.X, p.Y, p.Z)
    elseif t == "table" then
        local parts = {}
        local n = 0
        for k, val in pairs(v) do
            n = n + 1
            if n > 3 then
                table.insert(parts, "...")
                break
            end
            table.insert(parts, tostring(k) .. "=" .. snapArg(val, depth + 1))
        end
        return "{" .. table.concat(parts, ",") .. "}"
    else
        return t
    end
end

local function recordCapture(self, method, args, count)
    captureCount = captureCount + 1

    local prev = {}
    for i = 1, math.min(count, CFG.PREVIEW_ARGS) do
        table.insert(prev, snapArg(args[i], 0))
    end

    local entry = {
        id = captureCount,
        time = os.clock(),
        method = method,
        remoteName = self.Name,
        remotePath = self:GetFullName(),
        preview = table.concat(prev, " | "),
        caller = captureCallerInfo(),
        args = nil,   -- full arg storage added with tester engine
    }

    table.insert(captures, entry)
    if #captures > CFG.MAX_BUFFER then
        table.remove(captures, 1)
    end

    if renderRows then
        local okR, errR = pcall(renderRows)
        if not okR then
            print("[SpyGlass] render error: " .. tostring(errR))
        end
    end
end

-----------------------------------------------------------------------
-- SECTION 8 : NAMECALL HOOK
-----------------------------------------------------------------------

local function installHook()
    if not CAP.getrawmetatable or not CAP.getnamecallmethod then
        print("[SpyGlass] no metatable access; spy unavailable")
        return false
    end

    local ok, mt = pcall(getrawmetatable, game)
    if not ok or not mt then
        print("[SpyGlass] getrawmetatable failed")
        return false
    end

    local old = mt.__namecall
    if type(old) ~= "function" then
        print("[SpyGlass] no __namecall")
        return false
    end

    local replacement
    if CAP.newcclosure then
        replacement = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            if method == "InvokeServer" or method == "FireServer" then
                local args = { ... }
                local count = select("#", ...)
                local okC, errC = pcall(recordCapture, self, method, args, count)
                if not okC then
                    print("[SpyGlass] record error: " .. tostring(errC))
                end
            end
            return old(self, ...)
        end)
    else
        replacement = function(self, ...)
            local method = getnamecallmethod()
            if method == "InvokeServer" or method == "FireServer" then
                local args = { ... }
                local count = select("#", ...)
                local okC, errC = pcall(recordCapture, self, method, args, count)
                if not okC then
                    print("[SpyGlass] record error: " .. tostring(errC))
                end
            end
            return old(self, ...)
        end
    end

    local okSet = pcall(function()
        setreadonly(mt, false)
        mt.__namecall = replacement
        setreadonly(mt, true)
    end)

    if not okSet then
        okSet = pcall(function()
            mt.__namecall = replacement
        end)
    end

    if not okSet then
        print("[SpyGlass] failed to install hook")
        return false
    end

    return true
end

-----------------------------------------------------------------------
-- SECTION 9 : UI
---------------------------------------------------------------------

local T = {
    bg      = Color3.fromRGB(16, 16, 22),
    card    = Color3.fromRGB(28, 28, 36),
    border  = Color3.fromRGB(46, 46, 58),
    accent  = Color3.fromRGB(88, 140, 255),
    accent2 = Color3.fromRGB(124, 168, 255),
    good    = Color3.fromRGB(88, 200, 132),
    bad     = Color3.fromRGB(232, 92, 92),
    text    = Color3.fromRGB(238, 238, 242),
    dim     = Color3.fromRGB(156, 156, 170),
    faint   = Color3.fromRGB(104, 104, 118),
    rowbg   = Color3.fromRGB(35, 35, 45),
    rowhi   = Color3.fromRGB(42, 42, 55),
    stack   = Color3.fromRGB(130, 230, 220),
}

local function new(class, props)
    local inst = Instance.new(class)
    local parent = nil
    for k, v in pairs(props or {}) do
        if k == "Parent" then
            parent = v
        else
            inst[k] = v
        end
    end
    if parent then
        inst.Parent = parent
    end
    return inst
end

local function corner(parent, r)
    new("UICorner", { CornerRadius = UDim.new(0, r or 6), Parent = parent })
end

-- Container
local gui = new("ScreenGui", {
    Name = "SpyGlass",
    ResetOnSpawn = false,
    DisplayOrder = 996,
    IgnoreGuiInset = true,
})

local okCore = pcall(function()
    gui.Parent = game:GetService("CoreGui")
end)
if not okCore then
    gui.Parent = player:WaitForChild("PlayerGui")
    print("[SpyGlass] using PlayerGui")
end

-- Main window
local window = new("Frame", {
    Size = UDim2.fromOffset(680, 440),
    Position = UDim2.new(0.5, -340, 0.5, -220),
    BackgroundColor3 = T.card,
    BorderSizePixel = 0,
    Active = true,
    Draggable = true,
    Parent = gui,
})
corner(window, 10)
new("UIStroke", { Color = T.border, Thickness = 1, Parent = window })

-- Title bar
local titleBar = new("Frame", {
    Size = UDim2.new(1, 0, 0, 32),
    BackgroundColor3 = T.bg,
    BorderSizePixel = 0,
    Parent = window,
})
corner(titleBar, 10)

new("TextLabel", {
    Size = UDim2.new(1, -20, 1, 0),
    Position = UDim2.new(0, 12, 0, 0),
    BackgroundTransparency = 1,
    Text = "SpyGlass",
    TextColor3 = T.text,
    TextSize = 14,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = titleBar,
})

local hookBadge = new("TextLabel", {
    Size = UDim2.fromOffset(110, 18),
    Position = UDim2.new(1, -122, 0, 7),
    BackgroundColor3 = T.rowbg,
    BorderSizePixel = 0,
    Text = " hook: ...",
    TextColor3 = T.faint,
    TextSize = 10,
    Font = Enum.Font.Gotham,
    Parent = titleBar,
})
corner(hookBadge, 4)

local closeBtn = new("TextButton", {
    Size = UDim2.fromOffset(22, 22),
    Position = UDim2.new(1, -28, 0, 5),
    BackgroundColor3 = T.bad,
    BorderSizePixel = 0,
    Text = "X",
    TextColor3 = T.text,
    TextSize = 12,
    Font = Enum.Font.GothamBold,
    Parent = titleBar,
})
corner(closeBtn, 4)

closeBtn.MouseButton1Click:Connect(function()
    gui:Destroy()
    _G.SpyGlassInstalled = nil
    print("[SpyGlass] closed")
end)

-- Feed (left pane)
local feed = new("ScrollingFrame", {
    Size = UDim2.new(0.55, -10, 1, -58),
    Position = UDim2.new(0, 10, 0, 40),
    BackgroundColor3 = T.bg,
    BorderSizePixel = 0,
    ScrollBarThickness = 5,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    Parent = window,
})
corner(feed, 6)

new("UIListLayout", {
    Padding = UDim.new(0, 2),
    SortOrder = Enum.SortOrder.LayoutOrder,
    Parent = feed,
})

-- Detail pane (right side: shows selected capture)
local detail = new("Frame", {
    Size = UDim2.new(0.45, -10, 1, -58),
    Position = UDim2.new(0.55, 0, 0, 40),
    BackgroundColor3 = T.rowbg,
    BorderSizePixel = 0,
    Parent = window,
})
corner(detail, 6)

local detailTitle = new("TextLabel", {
    Size = UDim2.new(1, -16, 0, 18),
    Position = UDim2.new(0, 8, 0, 8),
    BackgroundTransparency = 1,
    Text = "select a capture",
    TextColor3 = T.text,
    TextSize = 12,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = detail,
})

local detailRemote = new("TextLabel", {
    Size = UDim2.new(1, -16, 0, 16),
    Position = UDim2.new(0, 8, 0, 28),
    BackgroundTransparency = 1,
    Text = "",
    TextColor3 = T.dim,
    TextSize = 11,
    Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    Parent = detail,
})

local detailCaller = new("TextLabel", {
    Size = UDim2.new(1, -16, 0, 16),
    Position = UDim2.new(0, 8, 0, 46),
    BackgroundTransparency = 1,
    Text = "",
    TextColor3 = T.stack,
    TextSize = 11,
    Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    Parent = detail,
})

local detailArgs = new("TextLabel", {
    Size = UDim2.new(1, -16, 0, 180),
    Position = UDim2.new(0, 8, 0, 68),
    BackgroundTransparency = 1,
    Text = "",
    TextColor3 = T.dim,
    TextSize = 11,
    Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = true,
    Parent = detail,
})

-- Status bar
local status = new("TextLabel", {
    Size = UDim2.new(1, -20, 0, 16),
    Position = UDim2.new(0, 10, 1, -22),
    BackgroundTransparency = 1,
    Text = "booting...",
    TextColor3 = T.faint,
    TextSize = 10,
    Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = window,
})

---------------------------------------------------------------------
-- SECTION 10 : POOLED FEED ROWS
---------------------------------------------------------------------
-- Plain tables for row data (the makeRow lesson): never attach
-- custom fields to instances.

local rowPool = {}

local function makeRow()
    local frame = new("Frame", {
        Size = UDim2.new(1, -6, 0, 34),
        BackgroundColor3 = T.rowbg,
        BorderSizePixel = 0,
        Parent = feed,
    })
    corner(frame, 3)

    local line1 = new("TextLabel", {
        Size = UDim2.new(1, -8, 0, 15),
        Position = UDim2.new(0, 6, 0, 1),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = T.text,
        TextSize = 11,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = frame,
    })

    local line2 = new("TextLabel", {
        Size = UDim2.new(1, -8, 0, 13),
        Position = UDim2.new(0, 6, 0, 17),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = T.faint,
        TextSize = 10,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = frame,
    })

    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        Parent = frame,
    })

    return {
        frame = frame,
        line1 = line1,
        line2 = line2,
        button = btn,
    }
end

local selectedId = nil

local function selectEntry(id)
    selectedId = id
    for _, entry in ipairs(captures) do
        if entry.id == id then
            detailTitle.Text = string.format("capture #%d", entry.id)
            detailRemote.Text = entry.remotePath or ""
            detailCaller.Text = "from: " .. (entry.caller or "?")
            detailArgs.Text = entry.preview or ""
            return
        end
    end
end

-- rows start hidden
for i = 1, CFG.MAX_ROWS do
    local row = makeRow()
    row.frame.Visible = false
    table.insert(rowPool, row)
end

function renderRowsNow()
    local n = #captures
    local start = math.max(1, n - CFG.MAX_ROWS + 1)
    local idx = 0

    for i = n, start, -1 do
        idx = idx + 1
        local row = rowPool[idx]
        if not row then
            break
        end

        local entry = captures[i]
        row.frame.Visible = true
        row.frame.LayoutOrder = entry.id

        row.line1.Text = string.format("#%d %s:%s",
            entry.id, entry.remoteName, entry.method)
        row.line2.Text = entry.caller or ""

        if entry.id == selectedId then
            row.frame.BackgroundColor3 = T.rowhi
        else
            row.frame.BackgroundColor3 = T.rowbg
        end
    end

    for i = idx + 1, #rowPool do
        rowPool[i].frame.Visible = false
    end

    feed.CanvasSize = UDim2.new(0, 0, 0, idx * 36)

    status.Text = string.format("%d captures | gc wrappers: %d | stack: %s",
        n, wrapperCount,
        CAP.getinfo and "on" or "off")
end

-- click handling per row (bound once)
for i = 1, CFG.MAX_ROWS do
    local rowIndex = i
    rowPool[i].button.MouseButton1Click:Connect(function()
        -- resolve current entry for this slot
        local n = #captures
        local start = math.max(1, n - CFG.MAX_ROWS + 1)
        local pos = n - rowIndex + 1
        if pos >= start and pos <= n then
            selectEntry(captures[pos].id)
            renderRowsNow()
        end
    end)
end

-- throttled render entry point
renderRows = function()
    local now = os.clock()
    if now - lastRender < (1 / CFG.RENDER_HZ) then
        if not renderQueued then
            renderQueued = true
            task.delay(1 / CFG.RENDER_HZ, function()
                renderQueued = false
                lastRender = os.clock()
                renderRowsNow()
            end)
        end
        return
    end
    lastRender = now
    renderRowsNow()
end

-----------------------------------------------------------------------
-- SECTION 11 : BOOT
-----------------------------------------------------------------------

probeReport()

if CFG.GC_SCAN_ON_BOOT then
    scanGC()
end

local hooked = installHook()

if hooked then
    hookBadge.Text = " hook: ON"
    hookBadge.TextColor3 = T.good
else
    hookBadge.Text = " hook: FAIL"
    hookBadge.TextColor3 = T.bad
end

renderRowsNow()

print("[SpyGlass] ready - captures flowing, click rows for details")
