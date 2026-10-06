--=====================================================================
--  PROJECT   : SimplySpy
--  FILE      : hook.lua (CAPTURE ENGINE) - UNIVERSAL BUILD
--  VERSION   : 0.2.0
--
--  PURPOSE   :
--    Captures every InvokeServer/FireServer call. Three hook tiers:
--      Tier 1 : newcclosure + getrawmetatable (modern UNC)
--      Tier 2 : plain closure + getrawmetatable (older executors)
--      Tier 3 : connection-scan fallback (no metatable access)
--    Falls back automatically at boot based on capabilities.
--
--  UNIVERSALITY CONTRACT :
--    Probes executor capabilities once. Degrades Tier 3 -> Tier 2
--    -> Tier 1 as available. All three tiers expose identical
--    behavior through the same module table.
--
--  RESPONSIBILITIES :
--    - Snapshot args immediately (before mutation by later code)
--    - Ring buffer of last N captures (default 200)
--    - Filters (include/exclude by remote name)
--    - Block list (suppress remotes entirely)
--    - Preview generation for list rows
--    - Call counting
--
--  MODULE CONTRACT :
--    Receives (deps). Returns this module's public table.
--    deps.format (required)  : format module
--    deps.ctx (required)     : loader context
--    deps.log (required)     : logger
--
--  TARGET    : universal (executors + Studio via adapter)
--  LICENSE   : MIT
--=====================================================================

-----------------------------------------------------------------------
-- SECTION 1 : MODULE BOOTSTRAP
-----------------------------------------------------------------------

local Hook = {}

local log = function() end
local Format -- injected via deps

-----------------------------------------------------------------------
-- SECTION 2 : STATE
-----------------------------------------------------------------------

local MAX_BUFFER = 200
local buffer = {}          -- ring buffer
local bufferCount = 0
local captureId = 0

local includeFilter = nil  -- string: only capture remotes matching this name
local excludeSet = {}      -- set of remote names to never capture
local blockSet = {}        -- set of remotes to suppress entirely

local hooked = false
local hookTier = 0         -- 1, 2, or 3
local originalNamecall = nil

-----------------------------------------------------------------------
-- SECTION 3 : CAPABILITY PROBING
-----------------------------------------------------------------------

local CAPABILITIES = {
    newcclosure = false,
    getrawmetatable = false,
    setreadonly = false,
    getnamecallmethod = false,
}

local function probeCapabilities()
    CAPABILITIES.newcclosure = type(newcclosure) == "function"
    CAPABILITIES.getrawmetatable = type(getrawmetatable) == "function"
    CAPABILITIES.setreadonly = type(setreadonly) == "function"
    CAPABILITIES.getnamecallmethod = type(getnamecallmethod) == "function"

    -- getnamecallmethod is essential for all metatable tiers.
    if not CAPABILITIES.getnamecallmethod then
        log("WARN", "getnamecallmethod unavailable; Tier 3 only")
        return
    end

    if CAPABILITIES.getrawmetatable and CAPABILITIES.setreadonly then
        if CAPABILITIES.newcclosure then
            hookTier = 1
            log("INFO", "hook tier 1: newcclosure + metatable")
        else
            hookTier = 2
            log("INFO", "hook tier 2: plain closure + metatable")
        end
    else
        hookTier = 3
        log("WARN", "hook tier 3: connection-scan fallback")
    end
end

-----------------------------------------------------------------------
-- SECTION 4 : SNAPSHOT LOGIC
-----------------------------------------------------------------------
-- Args must be snapshotted immediately. Remote args are frequently
-- tables that the game mutates (clearing, inserting, reparenting)
-- after the call. We deep-copy tables and record userdata types
-- by reference (Instances cannot be meaningfully copied).

local function snapshotValue(v, depth, seen)
    depth = depth or 0
    seen = seen or {}

    local t = typeof(v)

    if t == "table" then
        if seen[v] then
            return { __circular = true }
        end
        seen[v] = true
        if depth > 6 then
            return { __depth = true }
        end

        local copy = {}
        for k, val in pairs(v) do
            local keyCopy
            local kt = typeof(k)
            if kt == "table" then
                keyCopy = snapshotValue(k, depth + 1, seen)
            else
                keyCopy = k
            end
            copy[keyCopy] = snapshotValue(val, depth + 1, seen)
        end
        seen[v] = nil
        return copy
    elseif t == "Instance" then
        -- Record Instances by reference; Format renders their path.
        return v
    elseif t == "CFrame" then
        return { __type = "CFrame", components = { v:GetComponents() } }
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
-- SECTION 5 : FILTER EVALUATION
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
-- SECTION 6 : BUFFER MANAGEMENT
-----------------------------------------------------------------------

local function pushCapture(capture)
    captureId = captureId + 1
    capture.id = captureId

    bufferCount = bufferCount + 1
    table.insert(buffer, capture)

    if #buffer > MAX_BUFFER then
        table.remove(buffer, 1)
    end
end

-----------------------------------------------------------------------
-- SECTION 7 : PREVIEW GENERATION
-----------------------------------------------------------------------
-- Builds the compact preview string for list rows without full
-- formatting cost. Only called on the first argument.

local function buildPreview(args, count)
    if count == 0 then
        return ""
    end
    local first = args[1]
    local t = typeof(first)
    if t == "string" then
        local s = first
        if #s > 24 then
            s = s:sub(1, 24) .. "..."
        end
        return s
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
-- SECTION 8 : CAPTURE RECORDING
-----------------------------------------------------------------------

local function recordCapture(remote, method, args, count)
    if not shouldCapture(remote) then
        return
    end

    local snapshot = snapshotArgs(args, count)

    local capture = {
        id = 0, -- assigned in pushCapture
        remote = remote,
        remoteName = remote.Name,
        remotePath = Format.instancePath(remote),
        method = method,
        args = snapshot,
        argCount = count,
        timestamp = os.clock(),
        preview = buildPreview(args, count),
    }

    pushCapture(capture)

    -- UI notification hook (called if UI module is loaded).
    if Hook.onCapture then
        local ok, err = pcall(Hook.onCapture, capture)
        if not ok then
            log("WARN", "onCapture handler error: " .. tostring(err))
        end
    end
end

-----------------------------------------------------------------------
-- SECTION 9 : HOOK IMPLEMENTATIONS
-----------------------------------------------------------------------

--////////////////////////////////////////////////////////////////////
-- TIER 1/2 : METATABLE HOOK
--////////////////////////////////////////////////////////////////////
-- newcclosure protects against coroutine-related detection.
-- Plain closures work on most executors but are riskier.

local function installMetatableHook(useNewcclosure)
    local mt = getrawmetatable(game)
    if not mt then
        return false, "getrawmetatable(game) returned nil"
    end

    originalNamecall = mt.__namecall
    if not originalNamecall then
        return false, "__namecall not found"
    end

    local replacement
    if useNewcclosure and CAPABILITIES.newcclosure then
        replacement = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            if method == "InvokeServer" or method == "FireServer" then
                local args = { ... }
                recordCapture(self, method, args, #args)
            end
            return originalNamecall(self, ...)
        end)
    else
        replacement = function(self, ...)
            local method = getnamecallmethod()
            if method == "InvokeServer" or method == "FireServer" then
                local args = { ... }
                recordCapture(self, method, args, #args)
            end
            return originalNamecall(self, ...)
        end
    end

    local ok = pcall(function()
        setreadonly(mt, false)
        mt.__namecall = replacement
        setreadonly(mt, true)
    end)

    if not ok then
        return false, "failed to set __namecall"
    end

    return true
end

--////////////////////////////////////////////////////////////////////
-- TIER 3 : CONNECTION-SCAN FALLBACK
--////////////////////////////////////////////////////////////////////
-- No metatable access. Scans for RemoteEvent/RemoteFunction
-- instances and hooks their OnClientEvent/OnClientInvoke instead.
-- This captures INCOMING traffic (server -> client) only, and
-- cannot see outgoing client -> server calls via :InvokeServer.
-- It is a last resort that provides partial visibility.

local function scanForRemotes()
    local found = 0
    local function scan(parent)
        for _, inst in ipairs(parent:GetDescendants()) do
            if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") then
                found = found + 1
                local remote = inst
                if inst:IsA("RemoteEvent") then
                    -- Capture incoming fires.
                    inst.OnClientEvent:Connect(function(...)
                        recordCapture(remote, "OnClientEvent", { ... }, select("#", ...))
                    end)
                else
                    -- Capture incoming invokes. The client cannot
                    -- return a value from a hooked OnClientInvoke.
                    -- We record the call but cannot forward it.
                    inst.OnClientInvoke = function(...)
                        recordCapture(remote, "OnClientInvoke", { ... }, select("#", ...))
                        -- Return nothing; the server will receive nil.
                        -- This is intentionally not a full replacement.
                    end
                end
            end
        end
    end

    pcall(scan, game:GetService("ReplicatedStorage"))
    pcall(scan, game:GetService("Workspace"))
    -- Add more services as needed.

    return found
end

local function installConnectionScan()
    local found = scanForRemotes()
    if found == 0 then
        return false, "no remotes found to scan"
    end
    log("INFO", "tier 3: hooked " .. found .. " remote connections")
    return true
end

-----------------------------------------------------------------------
-- SECTION 10 : PUBLIC API
-----------------------------------------------------------------------

function Hook.init(deps)
    log = deps.log or log
    Format = deps.format

    if not Format then
        return false, "format module missing"
    end

    probeCapabilities()

    if hookTier == 1 then
        local ok, err = installMetatableHook(true)
        if not ok then
            log("WARN", "tier 1 failed (" .. tostring(err) .. "); trying tier 2")
            hookTier = 2
        else
            hooked = true
        end
    end

    if hookTier == 2 then
        local ok, err = installMetatableHook(false)
        if not ok then
            log("WARN", "tier 2 failed (" .. tostring(err) .. "); trying tier 3")
            hookTier = 3
        else
            hooked = true
        end
    end

    if hookTier == 3 then
        local ok, err = installConnectionScan()
        if not ok then
            return false, "all hook tiers failed: " .. tostring(err)
        end
        hooked = true
    end

    log("INFO", "hook engine online (tier " .. hookTier .. ")")
    return true
end

function Hook.shutdown()
    if hooked and hookTier <= 2 and originalNamecall then
        local mt = getrawmetatable(game)
        if mt then
            pcall(function()
                setreadonly(mt, false)
                mt.__namecall = originalNamecall
                setreadonly(mt, true)
            end)
        end
    end
    -- Tier 3 connections are not cleanly reversible; they remain
    -- until the game session ends.
    hooked = false
    log("INFO", "hook engine offline")
end

function Hook.count()
    return #buffer
end

function Hook.getRecent(n)
    n = n or 10
    local out = {}
    local start = math.max(1, #buffer - n + 1)
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

function Hook.setFilter(name)
    includeFilter = name
    log("INFO", "filter set to: " .. tostring(name))
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

function Hook.clear()
    buffer = {}
    bufferCount = 0
    log("INFO", "buffer cleared")
end

function Hook.list(n)
    local recent = Hook.getRecent(n or 10)
    print("\n=== SimplySpy Captures ===")
    if #recent == 0 then
        print("(none)")
    else
        for _, capture in ipairs(recent) do
            print(string.format("[%d] %s",
                capture.id, Format.callToLine(capture)))
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

    print("\n=== SimplySpy Capture #" .. id .. " ===")
    print("Remote: " .. capture.remotePath)
    print("Method: " .. capture.method)
    print("Time:   " .. string.format("%.3f", capture.timestamp))
    print("Args:")
    for i, arg in ipairs(capture.args) do
        print("  [" .. i .. "] " .. Format.display(arg))
    end
    print("===========================\n")
end

function Hook.copy(id)
    local capture = Hook.getById(id)
    if not capture then
        print("SimplySpy: capture not found: " .. tostring(id))
        return
    end

    local script = Format.callToScript(capture)
    print("\n=== SimplySpy Generated Script ===")
    print(script)
    print("=================================\n")

    if type(setclipboard) == "function" then
        setclipboard(script)
        print("Copied to clipboard.")
    else
        print("(setclipboard not available; copy manually)")
    end
end

-----------------------------------------------------------------------
-- SECTION 11 : MODULE CONTRACT
-----------------------------------------------------------------------
-- Executor path: main.lua executes this file and passes (deps).
-- Studio adapter path: the file is also a valid ModuleScript if
-- the return function is called manually.

return function(deps)
    local ok, result = pcall(Hook.init, deps)
    if not ok then
        error("SimplySpy hook init failed: " .. tostring(result))
    end
    if result == false then
        error("SimplySpy hook init returned false (see logs)")
    end
    return Hook
end
