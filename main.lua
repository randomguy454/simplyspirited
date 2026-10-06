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
--  RUNTIME ORCHESTRATOR                                             --
--  ====================                                             --
--                                                                    --
--  The conductor of SimplySpy. The loader hands control to this     --
--  file with a context table; this file fetches, boots, and wires    --
--  the three subsystem modules, then exposes the console API.       --
--                                                                    --
--  HARDENING PHILOSOPHY (learned the hard way):                     --
--    1. NO METATABLES. A metatable stub caused a silent bug that     --
--       survived three rewrites. Every lookup in this file is       --
--       explicit. Nothing is implicit, nothing is magic.            --
--    2. EVERY EXTERNAL CALL IS PCALLED. Module fetch, compile,       --
--       execution, init, show - if it can fail, it is caught and     --
--       reported by name.                                           --
--    3. FAILURES ISOLATE. A broken module degrades the tool; it     --
--       never kills the boot. The boot report says exactly what      --
--       failed and why.                                              --
--    4. THE CONSOLE API IS ALWAYS PUBLISHED. Even a fully failed     --
--       boot leaves SPY.report() available to diagnose itself.       --
--    5. FIXED CALL SIGNATURES. Every module chunk is invoked with     --
--       exactly one table argument. Argument count bugs are          --
--       structurally impossible.                                     --
--    6. STATE IS FLAT AND EXPLICIT. No nested closures over mutable  --
--       upvalues where avoidable; no clever indirection.             --
--                                                                    --
--  MODULE WIRING ORDER (dependencies flow downward):                 --
--    format.lua   - no dependencies (pure functions)                 --
--    hook.lua     - requires format                                  --
--    ui.lua       - requires format and hook                        --
--                                                                    --
--  MODULE CONTRACT (every module file follows this):                 --
--    - The file returns a function: function(deps) -> module table   --
--    - deps always contains: ctx, state, log, and every already-     --
--      loaded module as a direct reference                           --
--    - The returned table exposes public functions                   --
--    - init(deps) is optional and called after all modules load      --
--                                                                    --
--  BOOT REPORT:                                                      --
--    Every stage appends to a report table. SPY.report() prints      --
--    the full history: which modules loaded, which failed, the      --
--    exact error for each failure. The report survives even a       --
--    fatal boot error.                                               --
--                                                                    --
--  DEGRADED MODES:                                                   --
--    - UI failed      : hook + format still run; console only        --
--    - Hook failed    : UI shows but captures nothing; report says   --
--    - Format failed  : hook skips (hard dependency); UI still shows  --
--    - Everything OK  : full tool                                   --
--                                                                    --
--  TARGET    : UNC-compatible Roblox script executors                --
--  LICENSE   : MIT                                                   --
--                                                                    --
--=====================================================================
--=====================================================================

-----------------------------------------------------------------------
-- SECTION 1 : ENVIRONMENT AND CONTEXT VALIDATION
-----------------------------------------------------------------------
-- The loader hands us a context through the shared environment.
-- Every field is validated before use. A missing field becomes a
-- safe default instead of a crash. This file trusts nothing.

local genv = (type(getgenv) == "function") and getgenv() or _G
local rawCtx = genv.SimplySpy_Context

if not rawCtx then
    -- No context at all. This happens when main.lua is executed
    -- directly instead of through the loader. Fail loudly with
    -- instructions rather than mysteriously.
    error("SimplySpy: no loader context found. "
        .. "Execute loader.lua, not main.lua.")
end

-- Build the validated context. Each accessor degrades safely.
local CTX = {}

-- Logger: use the loader's if present, else print.
CTX.log = function(level, message)
    if type(rawCtx.log) == "function" then
        local ok = pcall(rawCtx.log, level, message)
        if ok then
            return
        end
    end
    print("[SimplySpy] [" .. tostring(level) .. "] "
        .. tostring(message))
end

CTX.gui = rawCtx.gui
CTX.reveal = rawCtx.reveal
CTX.destroy = rawCtx.destroy
CTX.version = tostring(rawCtx.version or "unknown")

-- Theme: shallow-validate the table.
if type(rawCtx.theme) == "table" then
    CTX.theme = rawCtx.theme
else
    CTX.theme = nil
    CTX.log("WARN", "context theme missing; UI uses defaults")
end

-- Capabilities: shallow-validate.
if type(rawCtx.capabilities) == "table" then
    CTX.capabilities = rawCtx.capabilities
else
    CTX.capabilities = {}
end

local VERSION = "0.4.0"
local REPO = "randomguy454/simplyspirited"
local BRANCH = "main"

-----------------------------------------------------------------------
-- SECTION 2 : SHARED STATE (flat, explicit)
-----------------------------------------------------------------------

local STATE = {
    running = false,
    booted = false,
    startTime = os.clock(),
}

-- Module registry. Values are:
--   nil       : not yet attempted
--   table     : loaded successfully
--   false     : attempted and failed (errors has the reason)
local modules = {}

-- Failure reasons by module name.
local moduleErrors = {}

-----------------------------------------------------------------------
-- SECTION 3 : BOOT REPORT
-----------------------------------------------------------------------
-- Append-only history of every boot stage and its outcome.

local reportLines = {}

local function report(stage, ok, detail)
    reportLines[#reportLines + 1] = {
        stage = stage,
        ok = ok,
        detail = detail or "",
    }
    CTX.log(ok and "INFO" or "WARN",
        string.format("%s: %s", stage,
            ok and "ok" or ("FAILED - " .. tostring(detail))))
end

-----------------------------------------------------------------------
-- SECTION 4 : SAFE WRAPPERS
-----------------------------------------------------------------------
-- Small primitives that make every later section impossible to
-- crash. These are the only places raw operations happen.

local function safeCall(fn, ...)
    if type(fn) ~= "function" then
        return false, "not a function"
    end
    return pcall(fn, ...)
end

local function safeYield(t)
    if task and task.wait then
        task.wait(t)
    else
        wait(t)
    end
end

-----------------------------------------------------------------------
-- SECTION 5 : MODULE LOADER
-----------------------------------------------------------------------
-- Fetches, compiles, and executes a module file. Every step
-- reports its own failure with the module name attached, so any
-- error in the log is immediately attributable.
--
-- INVOCATION RULE: modules are called with exactly one argument,
-- the deps table. Always. No exceptions. This is the rule that
-- makes argument-count bugs structurally impossible.

local MODULE_ORDER = { "format", "hook", "ui" }

-- Hard dependencies by module name. A module whose hard deps
-- failed is skipped entirely (reported, not booted).
local MODULE_DEPENDENCIES = {
    format = {},
    hook = { "format" },
    ui = { "format", "hook" },
}

local function buildModuleUrl(name)
    return string.format(
        "https://raw.githubusercontent.com/%s/%s/%s.lua",
        REPO, BRANCH, name)
end

local function fetchModuleSource(name)
    local url = buildModuleUrl(name)
    local ok, body = pcall(function()
        return game:HttpGet(url, true)
    end)

    if not ok then
        return nil, "http failed: " .. tostring(body)
    end
    if type(body) ~= "string" then
        return nil, "http returned " .. type(body)
    end
    if #body == 0 then
        return nil, "empty response"
    end
    if body:sub(1, 4) == "404:" then
        return nil, "file not found in repository"
    end
    return body
end

local function compileModuleChunk(name, source)
    local chunk, err = loadstring(source, "=SimplySpy/" .. name)
    if not chunk then
        return nil, "syntax error: " .. tostring(err)
    end
    return chunk
end

local function buildDeps(name)
    -- Fixed shape. No metatables. Only already-loaded modules are
    -- attached, as direct references. A module that wants another
    -- module checks for nil itself (they are documented to exist).
    local deps = {
        ctx = CTX,
        state = STATE,
        log = CTX.log,
        name = name,
    }

    -- Attach every successfully loaded module as a direct field.
    for _, modName in ipairs(MODULE_ORDER) do
        if type(modules[modName]) == "table" then
            deps[modName] = modules[modName]
        end
    end

    return deps
end

local function loadModule(name)
    -- Already loaded or already failed: report consistently.
    if type(modules[name]) == "table" then
        return modules[name], nil
    end
    if modules[name] == false then
        return nil, moduleErrors[name] or "previously failed"
    end

    -- Check hard dependencies first.
    for _, depName in ipairs(MODULE_DEPENDENCIES[name] or {}) do
        if type(modules[depName]) ~= "table" then
            local reason = "dependency '" .. depName
        .. "' did not load"
            modules[name] = false
            moduleErrors[name] = reason
            return nil, reason
        end
    end

    -- Fetch.
    local source, fetchErr = fetchModuleSource(name)
    if not source then
        modules[name] = false
        moduleErrors[name] = fetchErr
        return nil, fetchErr
    end

    -- Compile.
    local chunk, compileErr = compileModuleChunk(name, source)
    if not chunk then
        modules[name] = false
        moduleErrors[name] = compileErr
        return nil, compileErr
    end

    -- Execute with the fixed single-argument contract.
    local deps = buildDeps(name)
    local ok, result = pcall(chunk, deps)

    if not ok then
        local reason = "runtime error: " .. tostring(result)
        modules[name] = false
        moduleErrors[name] = reason
        return nil, reason
    end

    if type(result) ~= "table" then
        local reason = "module returned " .. type(result)
            .. ", expected table"
        modules[name] = false
        moduleErrors[name] = reason
        return nil, reason
    end

    modules[name] = result
    return result, nil
end

-----------------------------------------------------------------------
-- SECTION 6 : WIRING AND INIT
-----------------------------------------------------------------------

local function wireModules()
    for _, name in ipairs(MODULE_ORDER) do
        local mod, err = loadModule(name)
        if mod then
            report(name, true)
        else
            report(name, false, err)
        end
    end
end

local function initModules()
    -- Second pass: init only after everything has loaded, so
    -- cross-module wiring inside init is safe.
    for _, name in ipairs(MODULE_ORDER) do
        local mod = modules[name]
        if type(mod) == "table" and type(mod.init) == "function" then
            local deps = buildDeps(name)
            local ok, err = pcall(mod.init, deps)
            if ok then
                report("init:" .. name, true)
            else
                report("init:" .. name, false, tostring(err))
                -- An init failure marks the module as failed so
                -- later stages do not use a half-initialized module.
                modules[name] = false
                moduleErrors[name] = "init failed: " .. tostring(err)
            end
        end
    end
end

-----------------------------------------------------------------------
-- SECTION 7 : CONSOLE API
-----------------------------------------------------------------------
-- Published even when boot fails. SPY.report() is the diagnostic
-- entry point that always exists. Every API function checks its
-- module before touching it and pcalls every call.

local function apiCallModule(modName, funcName, ...)
    local mod = modules[modName]
    if type(mod) ~= "table" then
        print("SimplySpy: " .. modName .. "." .. funcName
            .. " unavailable (module not loaded)")
        return nil
    end
    if type(mod[funcName]) ~= "function" then
        print("SimplySpy: " .. modName .. "." .. funcName
            .. " is not a function")
        return nil
    end
    local ok, err = pcall(mod[funcName], ...)
    if not ok then
        print("SimplySpy: " .. modName .. "." .. funcName
            .. " error: " .. tostring(err))
        return nil
    end
    return true
end

local function buildApi()
    local spy = {}

    function spy.version()
        return VERSION
    end

    function spy.report()
        print("=== SimplySpy Boot Report ===")
        for _, line in ipairs(reportLines) do
            print(string.format("  %-14s %s %s",
                line.stage,
                line.ok and "ok    " or "FAILED",
                line.detail))
        end
        print("=============================")
    end

    function spy.count()
        local mod = modules.hook
        if type(mod) == "table" and type(mod.count) == "function" then
            return mod.count()
        end
        return 0
    end

    function spy.clear()
        apiCallModule("hook", "clear")
        apiCallModule("ui", "refresh")
    end

    function spy.filter(name)
        apiCallModule("hook", "setFilter", name)
    end

    function spy.block(name)
        apiCallModule("hook", "setBlocked", name, true)
    end

    function spy.unblock(name)
        apiCallModule("hook", "setBlocked", name, false)
    end

    function spy.list(n)
        apiCallModule("hook", "list", n or 10)
    end

    function spy.dump(n)
        apiCallModule("hook", "dump", n)
    end

    function spy.copy(n)
        apiCallModule("hook", "copy", n)
    end

    function spy.toggle()
        apiCallModule("ui", "toggle")
    end

    function spy.hide()
        apiCallModule("ui", "hide")
    end

    function spy.show()
        apiCallModule("ui", "show")
    end

    -- Self-tests pass through to modules that have them.
    function spy.selftest()
        local allPassed = true
        local formatMod = modules.format
        if type(formatMod) == "table"
            and type(formatMod.selfTest) == "function" then
            local ok = pcall(formatMod.selfTest)
            if not ok then
                allPassed = false
            end
        else
            print("format selftest unavailable")
            allPassed = false
        end

        local hookMod = modules.hook
        if type(hookMod) == "table"
            and type(hookMod.selfTest) == "function" then
            local ok = pcall(hookMod.selfTest)
            if not ok then
                allPassed = false
            end
        else
            print("hook selftest unavailable")
            allPassed = false
        end

        return allPassed
    end

    return spy
end

-----------------------------------------------------------------------
-- SECTION 8 : BOOT SEQUENCE
-----------------------------------------------------------------------

local function boot()
    CTX.log("INFO", "runtime v" .. VERSION .. " booting")

    -- Load and wire modules.
    wireModules()
    initModules()

    -- Show the UI if it loaded. Everything about this call is
    -- defensive: module presence, function presence, pcall.
    local uiMod = modules.ui
    if type(uiMod) == "table" and type(uiMod.show) == "function" then
        local ok, err = pcall(uiMod.show)
        report("ui:show", ok, not ok and tostring(err) or nil)
    else
        report("ui:show", false, "ui module unavailable; console mode")
    end

    STATE.running = true
    STATE.booted = true

    -- Summarize failures.
    local failed = 0
    for _, name in ipairs(MODULE_ORDER) do
        if modules[name] == false then
            failed = failed + 1
        end
    end

    if failed == 0 then
        CTX.log("INFO", "all modules online")
    else
        CTX.log("WARN", failed .. " module(s) failed; "
            .. "run SPY.report() for details")
    end

    -- Publish the console API. This line runs even when modules
    -- failed: SPY.report() is the self-diagnosis entry point.
    genv.SPY = buildApi()

    -- Reveal the loader transition. The loader's own failsafe
    -- covers the case where this call errors.
    if type(CTX.reveal) == "function" then
        pcall(CTX.reveal)
    end
end

-----------------------------------------------------------------------
-- SECTION 9 : ENTRY
-----------------------------------------------------------------------
-- The entry pcall is the outermost barrier. Even a fatal error in
-- boot leaves the report intact and surfaces a clear message to
-- the loader's error card.

local ok, err = pcall(boot)
if not ok then
    CTX.log("ERROR", "fatal boot error: " .. tostring(err))

    -- Publish the API anyway so the report is reachable.
    genv.SPY = buildApi()

    -- Report the fatal error through the report history too.
    reportLines[#reportLines + 1] = {
        stage = "boot",
        ok = false,
        detail = tostring(err),
    }

    -- Let the loader's error card display it.
    error("SimplySpy: " .. tostring(err))
end
