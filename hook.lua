--=====================================================================
--=====================================================================
--                                                                    --
--   ____  _                   _____         _                        --
--  / ___|(_)_ __ ___  _   _|  ___|_  ___ | |_                      --
--  \___ \| | '_ ` _ \| | | | |_  \ \/ / '| __|                     --
--   ___) | | | | | | | |_| |  _| | >  <| | |_                      --
--  |____/|_|_| |_| |_|\__, |_|  \_/_/\_\  \__|                     --
--                      |___/                                        --
--                                                                    --
--  CAPTURE ENGINE                                                   --
--  ==============                                                   --
--                                                                    --
--  Intercepts every remote call the client makes and records a      --
--  snapshot of the invocation. The snapshot is immutable: the       --
--  game cannot mutate it after the fact, so what you inspect is    --
--  exactly what crossed the wire at capture time.                   --
--                                                                    --
--  HOOK TIERS:                                                      --
--    Tier 1 : newcclosure + getrawmetatable + setreadonly           --
--             Full outgoing capture. Lowest detection risk.        --
--    Tier 2 : plain closure + getrawmetatable + setreadonly          --
--             Full outgoing capture. Slightly higher risk on       --
--             some games.                                            --
--    Tier 3 : connection scan (engine APIs only)                    --
--             Incoming traffic only. Zero detection risk.           --
--             Falls back automatically when no metatable access.   --
--                                                                    --
--  CAPTURE RECORD:                                                  --
--    id          sequential number, stable within a session          --
--    remote      live instance reference (may go stale; paths        --
--                are snapshotted separately)                        --
--    remoteName  remote .Name at capture time                       --
--    remotePath  resolved codegen path at capture time              --
--    method      "InvokeServer" or "FireServer" (or tier 3:          --
--                "OnClientEvent" / "OnClientInvoke")                 --
--    args        deep-snapshotted argument table                     --
--    argCount    number of arguments                                 --
--    timestamp   os.clock() at capture                               --
--    preview     compact first-arg summary for list rows            --
--                                                                    --
--  SNAPSHOT POLICY:                                                 --
--    Arguments are deep-copied immediately inside the hook,         --
--    before the game's own code runs. Games routinely mutate       --
--    argument tables after the call; without snapshotting the       --
--    recorded data would be corrupted by the time it is viewed.     --
--    Instances are kept as live references because they cannot      --
--    be meaningfully copied, and their paths are resolved to        --
--    strings at capture time.                                       --
--                                                                    --
--  FILTERING:                                                       --
--    includeFilter : if set, only remotes with exactly this name     --
--                    are captured                                   --
--    excludeSet    : remotes with these names are never captured     --
--    blockSet      : remotes with these names are suppressed from    --
--                    the game entirely (the call does not pass       --
--                    through)                                       --
--                                                                    --
--  BUFFER:                                                          --
--    Ring buffer of the most recent N captures. Default 200.        --
--    When full, the oldest capture is discarded. IDs keep           --
--    counting so gaps indicate discarded entries.                   --
--                                                                    --
--  MODULE CONTRACT:                                                 --
--    main.lua executes this file with a deps table containing       --
--    ctx, state, log, and format (the loaded format module).        --
--    The file returns a function accepting deps and returning       --
--    the Hook table.                                                --
--                                                                    --
--  TARGET    : universal (executors + Studio via adapter)            --
--  LICENSE   : MIT                                                   --
--                                                                    --
--=====================================================================
--=====================================================================

-----------------------------------------------------------------------
-- SECTION 1 : MODULE BOOTSTRAP
-----------------------------------------------------------------------

local Hook = {}

local log = function() end
local Format = nil

-----------------------------------------------------------------------
-- SECTION 2 : CONFIGURATION CONSTANTS
-----------------------------------------------------------------------

local MAX_BUFFER = 200         -- ring buffer capacity
local SNAPSHOT_DEPTH_MAX = 6   -- max table nesting in snapshots
local PREVIEW_STRING_MAX = 24  -- max chars in preview strings

-----------------------------------------------------------------------
-- SECTION 3 : STATE
-----------------------------------------------------------------------

local buffer = {}        -- ordered capture records
local captureId = 0      -- ever-increasing counter

local includeFilter = nil -- string or nil
local excludeSet = {}     -- set: name -> true
local blockSet = {}       -- set: name -> true

local hooked = false
local hookTier = 0        -- 1, 2, or 3 after init
local originalNamecall = nil
local scanConnections = {} -- tier 3 connections

-----------------------------------------------------------------------
-- SECTION 4 : CAPABILITY PROBING
-----------------------------------------------------------------------
-- Probed once at init. The results decide the hook tier. All
-- probes are wrapped so a missing global is simply false.

local capabilities = {
    newcclosure       = false,
    getrawmetatable   = false,
    setreadonly       = false,
    getnamecallmethod = false,
}

local function probeCapabilities()
    capabilities.newcclosure = (type(newcclosure) == "function")
    capabilities.getrawmetatable = (type(getrawmetatable) == "function")
    capabilities.setreadonly = (type(setreadonly) == "function")
    capabilities.getnamecallmethod = (type(getnamecallmethod) == "function")
end

-----------------------------------------------------------------------
-- SECTION 5 : SNAPSHOT ENGINE
-----------------------------------------------------------------------
-- Deep-copies values for immutable storage. Each datatype gets a
-- strategy matched to how games mutate them:
--
--   table   -> recursive copy, circular-protected
--   Instance-> kept live (cannot copy); path resolved at capture
--   CFrame  -> flattened to 12 numbers
--   Vector3 -> plain table {x, y, z}
--   Vector2 -> plain table {x, y}
--   Color3  -> plain table {r, g, b}
--   other   -> passed through by value (strings, numbers,
--              booleans, nil are already immutable)

local function snapshotValue(v, depth, seen)
    depth = depth or 0
    seen = seen or {}

    local t = typeof(v)

    if t == "table" then
        if seen[v] then
            return { __circular = true }
        end
        seen[v] = true

        if depth >= SNAPSHOT_DEPTH_MAX then
            seen[v] = nil
            return { __depth = true }
        end

        local copy = {}
        for k, val in pairs(v) do
            local keyCopy
            if type(k) == "table" then
                keyCopy = snapshotValue(k, depth + 1, seen)
            else
                keyCopy = k
            end
            copy[keyCopy] = snapshotValue(val, depth + 1, seen)
        end

        seen[v] = nil
        return copy

    elseif t == "Instance" then
        return v

    elseif t == "CFrame" then
        local p = { v:GetComponents() }
        return {
            __type = "CFrame",
            c = {
                p[1],  p[2],  p[3],  p[4],
                p[5],  p[6],  p[7],  p[8],
                p[9],  p[10], p[11], p[12],
            },
        }

    elseif t == "Vector3" then
        return { __type = "Vector3", x = v.X, y = v.Y, z = v.Z }

    elseif t == "Vector2" then
        return { __type = "Vector2", x = v.X, y = v.Y }

    elseif t == "Color3" then
        return { __type = "Color3", r = v.R, g = v.G, b = v.B }

    else
        return v
    end
end

local function snapshotArgs(args, count)
    local out = {}
    for i = 1, count do
        out[i] = snapshotValue(args[i])
    end
    return out
end

-----------------------------------------------------------------------
-- SECTION 6 : SNAPSHOT RECONSTRUCTION
-----------------------------------------------------------------------
-- Converts a snapshot back into a live value for codegen. The
-- format module consumes live values, so tagged snapshots (from
-- the snapshot engine above) are converted back into real
-- CFrame/Vector3/Color3 userdata before formatting.
--
-- This is what keeps the hook engine and the format engine
-- decoupled: snapshots are pure data, reconstruction happens only
-- when generating output.

function Hook.reconstruct(v, depth, seen)
    depth = depth or 0
    seen = seen or {}

    if type(v) ~= "table" then
        return v
    end
    if seen[v] then
        return v
    end
    seen[v] = true

    -- Tagged snapshots reconstruct to their userdata type.
    if v.__type == "CFrame" and type(v.c) == "table" then
        seen[v] = nil
        return CFrame.new(
            v.c[1],  v.c[2],  v.c[3],
            v.c[4],  v.c[5],  v.c[6],
            v.c[7],  v.c[8],  v.c[9],
            v.c[10], v.c[11], v.c[12]
        )
    elseif v.__type == "Vector3" then
        seen[v] = nil
        return Vector3.new(v.x, v.y, v.z)
    elseif v.__type == "Vector2" then
        seen[v] = nil
        return Vector2.new(v.x, v.y)
    elseif v.__type == "Color3" then
        seen[v] = nil
        return Color3.new(v.r, v.g, v.b)
    end

    -- Plain tables reconstruct recursively. Note: snapshot keys
    -- that were tables are already copies, so reconstruction of
    -- keys is not needed in the common case.
    local out = {}
    for k, val in pairs(v) do
        out[k] = Hook.reconstruct(val, depth + 1, seen)
    end

    seen[v] = nil
    return out
end

-----------------------------------------------------------------------
-- SECTION 7 : FILTER EVALUATION
-----------------------------------------------------------------------

local function shouldCapture(remote)
    local name = remote.Name

    if blockSet[name] then
        return false
    end
    if excludeSet[name] then
        return false
    end
    if includeFilter then
        return name == includeFilter
    end
    return true
end

-----------------------------------------------------------------------
-- SECTION 8 : BUFFER MANAGEMENT
-----------------------------------------------------------------------

local function pushCapture(capture)
    captureId = captureId + 1
    capture.id = captureId

    table.insert(buffer, capture)

    while #buffer > MAX_BUFFER do
        table.remove(buffer, 1)
    end
end

-----------------------------------------------------------------------
-- SECTION 9 : PREVIEW GENERATION
-----------------------------------------------------------------------
-- Builds a compact summary of the first argument for list rows.
-- Deliberately cheap: no recursion, no full formatting. Type name
-- or short string only.

local function buildPreview(args, count)
    if count == 0 then
        return ""
    end

    local first = args[1]
    local t = typeof(first)

    if t == "string" then
        if #first > PREVIEW_STRING_MAX then
            return first:sub(1, PREVIEW_STRING_MAX) .. "..."
        end
        return first
    elseif t == "number" then
        return tostring(first)
    elseif t == "boolean" then
        return tostring(first)
    elseif t == "Instance" then
        return first.Name
    elseif t == "table" then
        return "table"
    else
        return t
    end
end

-----------------------------------------------------------------------
-- SECTION 10 : CAPTURE RECORDING
-----------------------------------------------------------------------
-- The single funnel for all tiers. Snapshots arguments, builds the
-- record, pushes to the buffer, and notifies the UI callback if
-- one is attached.

local function recordCapture(remote, method, args, count)
    if not shouldCapture(remote) then
        return
    end

    local capture = {
        id = 0, -- assigned by pushCapture
        remote = remote,
        remoteName = remote.Name,
        remotePath = Format.instancePath(remote),
        method = method,
        args = snapshotArgs(args, count),
        argCount = count,
        timestamp = os.clock(),
        preview = buildPreview(args, count),
    }

    pushCapture(capture)

    -- UI notification hook. Attached by the ui module after load.
    -- Wrapped so a UI error never breaks the hook itself.
    if type(Hook.onCapture) == "function" then
        local ok, err = pcall(Hook.onCapture, capture)
        if not ok then
            log("WARN", "onCapture handler error: " .. tostring(err))
        end
    end
end

-----------------------------------------------------------------------
-- SECTION 11 : TIER 1/2 : METATABLE HOOK
-----------------------------------------------------------------------
-- Replaces the __namecall metamethod on the game metatable. Every
-- subsequent namecall in the client passes through the replacement.
-- Captured calls are recorded, then forwarded to the original
-- unchanged. The game never observes a difference.
--
-- Tier 1 wraps the replacement in newcclosure, which prevents
-- coroutine-based detection of executor closures. Tier 2 uses a
-- plain Lua closure, which works on nearly all executors but is
-- theoretically detectable.

local function installMetatableHook(useNewcclosure)
    local ok, mt = pcall(getrawmetatable, game)
    if not ok or not mt then
        return false, "getrawmetatable(game) failed"
    end

    if type(mt.__namecall) ~= "function" then
        return false, "__namecall not present on metatable"
    end

    originalNamecall = mt.__namecall

    local replacement
    if useNewcclosure and capabilities.newcclosure then
        replacement = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            if method == "InvokeServer" or method == "FireServer" then
                local args = { ... }
                recordCapture(self, method, args, select("#", ...))
            end
            return originalNamecall(self, ...)
        end)
    else
        replacement = function(self, ...)
            local method = getnamecallmethod()
            if method == "InvokeServer" or method == "FireServer" then
                local args = { ... }
                recordCapture(self, method, args, select("#", ...))
            end
            return originalNamecall(self, ...)
        end
    end

    local setOk = pcall(function()
        setreadonly(mt, false)
        mt.__namecall = replacement
        setreadonly(mt, true)
    end)

    if not setOk then
        -- One more attempt without the readonly restore, for
        -- executors whose setreadonly behaves differently.
        setOk = pcall(function()
            mt.__namecall = replacement
        end)
        if not setOk then
            return false, "failed to replace __namecall"
        end
    end

    return true
end

-----------------------------------------------------------------------
-- SECTION 12 : TIER 3 : CONNECTION SCAN
-----------------------------------------------------------------------
-- Engine-APIs-only fallback for environments without metatable
-- access. Scans for RemoteEvent and RemoteFunction instances and
-- attaches to their incoming-traffic signals.
--
-- Limitations (documented honestly):
--   1. Only incoming (server-to-client) traffic is visible.
--      Outgoing client calls cannot be seen without the
--      metatable hook.
--   2. The OnClientInvoke hook records the call but returns nil
--      to the server, which may break game functionality that
--      expects a return value. This is a deliberate trade-off:
--      visibility at the cost of potential breakage.
--   3. Remotes created after the scan will not be captured until
--      the scan runs again (Hook.rescan()).

local function scanForRemotes()
    local found = 0
    scanConnections = {}

    local function attachRemote(remote)
        if remote:IsA("RemoteEvent") then
            local conn = remote.OnClientEvent:Connect(function(...)
                recordCapture(remote, "OnClientEvent",
                    { ... }, select("#", ...))
            end)
            table.insert(scanConnections, conn)
            found = found + 1
        elseif remote:IsA("RemoteFunction") then
   
            remote.OnClientInvoke = function(...)
                recordCapture(remote, "OnClientInvoke",
                    { ... }, select("#", ...))
                return nil
            end
            found = found + 1
        end
    end

    local function scanService(service)
        local ok, err = pcall(function()
            for _, inst in ipairs(service:GetDescendants()) do
                if inst:IsA("RemoteEvent")
                    or inst:IsA("RemoteFunction") then
                    attachRemote(inst)
                end
            end
        end)
        if not ok then
            log("WARN", "scan failed on service: " .. tostring(err))
        end
    end

    scanService(game:GetService("ReplicatedStorage"))
    scanService(game:GetService("Workspace"))

    return found
end

function Hook.rescan()
    if hookTier ~= 3 then
        log("WARN", "rescan only applies to tier 3")
        return 0
    end
    local found = scanForRemotes()
    log("INFO", "rescan found " .. found .. " remotes")
    return found
end

local function installConnectionScan()
    local found = scanForRemotes()
    if found == 0 then
        return false, "no remotes found to scan"
    end
    log("INFO", "tier 3: attached to " .. found .. " remote signals")
    return true
end

-----------------------------------------------------------------------
-- SECTION 13 : PUBLIC API
-----------------------------------------------------------------------
-- INIT
-- Wires the module and installs the best available hook tier.
-- Returns true on success, false + reason on total failure.

function Hook.init(deps)
    log = (deps and deps.log) or log
    Format = deps and deps.format

    if not Format then
        return false, "format module missing from deps"
    end

    probeCapabilities()

    -- Try tiers in order of preference.
    local attempts = {
        { tier = 1, install = function()
            return installMetatableHook(true)
        end },
        { tier = 2, install = function()
            return installMetatableHook(false)
        end },
        { tier = 3, install = installConnectionScan },
    }

    for _, attempt in ipairs(attempts) do
        -- Tier 1 requires newcclosure; skip if unavailable.
        if attempt.tier == 1 and not capabilities.newcclosure then
            -- fall through to tier 2
        else
            -- Tier 1 and 2 both require the metatable stack.
            if attempt.tier <= 2
                and (not capabilities.getrawmetatable
                    or not capabilities.getnamecallmethod) then
                -- fall through to tier 3
            else
                local ok, err = attempt.install()
                if ok then
                    hookTier = attempt.tier
                    hooked = true
                    log("INFO", "hook engine online (tier "
                        .. hookTier .. ")")
                    return true
                else
                    log("WARN", "tier " .. attempt.tier
                        .. " failed: " .. tostring(err))
                end
            end
        end
    end

    return false, "all hook tiers failed"
end

-- SHUTDOWN
-- Restores the original __namecall for tiers 1 and 2. Tier 3
-- connections are disconnected where possible.

function Hook.shutdown()
    if hooked and hookTier <= 2 and originalNamecall then
        local ok, mt = pcall(getrawmetatable, game)
        if ok and mt then
            pcall(function()
                setreadonly(mt, false)
                mt.__namecall = originalNamecall
                setreadonly(mt, true)
            end)
        end
    end

    for _, conn in ipairs(scanConnections) do
        pcall(function() conn:Disconnect() end)
    end
    scanConnections = {}

    hooked = false
    hookTier = 0
    log("INFO", "hook engine offline")
end

-- QUERIES

function Hook.count()
    return #buffer
end

function Hook.getTier()
    return hookTier
end

function Hook.getFilterName()
    return includeFilter
end

function Hook.getRecent(n)
    n = n or 10
    if n > #buffer then
        n = #buffer
    end
    local out = {}
    local start = #buffer - n + 1
    for i = start, #buffer do
        table.insert(out, buffer[i])
    end
    return out
end

function Hook.getById(id)
    for _, capture in ipairs(buffer) do
        if capture.id == id then
            return capture
        end
    end
    return nil
end

function Hook.getAll()
    local out = {}
    for _, capture in ipairs(buffer) do
        table.insert(out, capture)
    end
    return out
end

-- FILTERS

function Hook.setFilter(name)
    if name == "" then
        name = nil
    end
    includeFilter = name
    if name then
        log("INFO", "filter set to: " .. name)
    else
        log("INFO", "filter cleared")
    end
end

function Hook.setExcluded(name, excluded)
    if excluded then
        excludeSet[name] = true
        log("INFO", "excluded: " .. name)
    else
        excludeSet[name] = nil
        log("INFO", "unexcluded: " .. name)
    end
end

function Hook.setBlocked(name, blocked)
    if blocked then
        blockSet[name] = true
        log("INFO", "blocked: " .. name)
    else
        blockSet[name] = nil
        log("INFO", "unblocked: " .. name)
    end
end

function Hook.clearFilters()
    includeFilter = nil
    excludeSet = {}
    log("INFO", "all filters cleared")
end

-- BUFFER

function Hook.clear()
    buffer = {}
    log("INFO", "buffer cleared")
end

-----------------------------------------------------------------------
-- SECTION 14 : CONSOLE OUTPUT
-----------------------------------------------------------------------
-- These functions print directly. The UI renders the same data
-- through the format module; these are the console equivalents.

local function reconstructedCapture(capture)
    -- Format module works on live values; snapshots hold plain
    -- tables. Reconstruct before formatting.
    local out = {}
    for i, arg in ipairs(capture.args) do
        out[i] = Hook.reconstruct(arg)
    end
    return out
end

function Hook.list(n)
    local recent = Hook.getRecent(n or 10)

    print("\n=== SimplySpy Captures ===")
    if #recent == 0 then
        print("(none)")
    else
        for _, capture in ipairs(recent) do
            print(string.format("[%d] %s:%s (%s)",
                capture.id,
                capture.remoteName or "?",
                capture.method or "?",
                capture.preview or (capture.argCount .. " args")))
        end
    end
    print("=========================\n")
end

function Hook.dump(id)
    local capture = Hook.getById(id)
    if not capture then
        print("SimplySpy: capture not found: " .. tostring(id))
        return
    end

    local args = reconstructedCapture(capture)

    print("\n=== SimplySpy Capture #" .. tostring(id) .. " ===")
    print("Remote: " .. tostring(capture.remotePath))
    print("Method: " .. tostring(capture.method))
    print("Time:   " .. string.format("%.3f", capture.timestamp or 0))
    print("Args:")
    for i, arg in ipairs(args) do
        print("  [" .. i .. "] " .. Format.display(arg))
    end
    print("=============================\n")
end

function Hook.copy(id)
    local capture = Hook.getById(id)
    if not capture then
        print("SimplySpy: capture not found: " .. tostring(id))
        return
    end

    -- Build a display copy with reconstructed args so codegen
    -- emits proper CFrame/Vector3 constructors.
    local liveCapture = {
        id = capture.id,
        remoteName = capture.remoteName,
        remotePath = capture.remotePath,
        method = capture.method,
        argCount = capture.argCount,
        preview = capture.preview,
        args = reconstructedCapture(capture),
    }

    local scriptText = Format.callToScript(liveCapture)

    print("\n=== SimplySpy Generated Script ===")
    print(scriptText)
    print("==================================\n")

    if type(setclipboard) == "function" then
        setclipboard(scriptText)
        print("Copied to clipboard.")
    else
        print("(setclipboard not available; copy from console)")
    end
end

-----------------------------------------------------------------------
-- SECTION 15 : SELF-TEST
-----------------------------------------------------------------------
-- Verifies the snapshot engine in isolation. Does not install
-- any hooks (that requires a live game environment). Call
-- Hook.selfTest() from the console to run.

function Hook.selfTest()
    local failures = 0
    local total = 0

    local function check(desc, condition)
        total = total + 1
        if not condition then
            failures = failures + 1
            print("[SELFTEST FAIL] " .. desc)
        end
    end

    -- Snapshot round-trip: CFrame
    do
        local cf = CFrame.new(1.5, 2.5, 3.5, 4, 5, 6, 7, 8, 9, 10, 11, 12)
        local snap = snapshotValue(cf)
        local back = Hook.reconstruct(snap)
        check("CFrame roundtrip",
            back:GetComponents() == cf:GetComponents()
            or tostring(back) == tostring(cf))
        local p1 = { cf:GetComponents() }
        local p2 = { back:GetComponents() }
        local match = true
        for i = 1, 12 do
            if p1[i] ~= p2[i] then
                match = false
            end
        end
        check("CFrame components exact", match)
    end

    -- Snapshot round-trip: Vector3
    do
        local v = Vector3.new(1.25, -2.5, 3.75)
        local snap = snapshotValue(v)
        local back = Hook.reconstruct(snap)
        check("Vector3 roundtrip",
            back.X == v.X and back.Y == v.Y and back.Z == v.Z)
    end

    -- Snapshot: table deep copy and mutation isolation
    do
        local t = { a = 1, b = { c = 2 } }
        local snap = snapshotValue(t)
        t.a = 999
        t.b.c = 999
        check("snapshot isolates mutations",
            snap.a == 1 and snap.b.c == 2)
    end

    -- Snapshot: circular reference protection
    do
        local t = {}
        t.self = t
        local ok = pcall(snapshotValue, t)
        check("circular table snapshotted without error", ok)
    end

    -- Snapshot: depth limit
    do
        local t = {}
        local cur = t
        for i = 1, 20 do
            cur.next = {}
            cur = cur.next
        end
        local ok = pcall(snapshotValue, t)
        check("deep table snapshotted without error", ok)
    end

    -- Preview generation
    do
        check("preview string",
            buildPreview({ "hello" }, 1) == "hello")
        check("preview long string",
            buildPreview({ string.rep("x", 40) }, 1)
                == string.rep("x", 24) .. "...")
        check("preview number",
            buildPreview({ 42 }, 1) == "42")
        check("preview empty",
            buildPreview({}, 0) == "")
    end

    -- Buffer: overflow discards oldest
    do
        local savedBuffer = buffer
        buffer = {}
        local savedId = captureId
        captureId = 0
        for i = 1, MAX_BUFFER + 10 do
            pushCapture({ remoteName = "test", method = "test",
                args = {}, argCount = 0, preview = "",
                timestamp = 0, remotePath = "test" })
        end
        check("buffer capped", #buffer == MAX_BUFFER)
        check("ids kept counting",
            buffer[#buffer].id == MAX_BUFFER + 10)
        buffer = savedBuffer
        captureId = savedId
    end

    -- Filter evaluation
    do
        local savedFilter = includeFilter
        local savedExclude = excludeSet
        local savedBlock = blockSet

        local fakeRemote = { Name = "TestRemote" }

        includeFilter = nil
        excludeSet = {}
        blockSet = {}
        check("no filter captures all", shouldCapture(fakeRemote))

        includeFilter = "TestRemote"
        check("matching filter captures",
            shouldCapture(fakeRemote))
        includeFilter = "OtherRemote"
        check("mismatching filter skips",
            not shouldCapture(fakeRemote))

        includeFilter = nil
        excludeSet = { TestRemote = true }
        check("excluded remote skipped",
            not shouldCapture(fakeRemote))

        excludeSet = {}
        blockSet = { TestRemote = true }
        check("blocked remote skipped",
            not shouldCapture(fakeRemote))

        includeFilter = savedFilter
        excludeSet = savedExclude
        blockSet = savedBlock
    end

    print(string.format("[SELFTEST] %d/%d passed",
        total - failures, total))
    return failures == 0
end

-----------------------------------------------------------------------
-- SECTION 16 : MODULE CONTRACT
-----------------------------------------------------------------------

Hook.VERSION = "1.0.0"
Hook.MAX_BUFFER = MAX_BUFFER

return function(deps)
    local ok, result = pcall(Hook.init, deps)
    if not ok then
        error("hook init crashed: " .. tostring(result))
    end
    if result == false then
        -- Init failed on all tiers. Surface the reason through the
        -- error so main.lua's wiring reports it.
        error("hook init failed: " .. tostring(select(2, Hook.init)))
    end
    return Hook
end
