--=====================================================================
--  PROJECT   : SimplySpy
--  FILE      : main.lua (ORCHESTRATOR) - BULLETPROOF BUILD
--  VERSION   : 0.3.0
--
--  PURPOSE   :
--    Runtime entry point. Fetches and boots the three subsystem
--    modules (format, hook, ui) with full error isolation. A
--    failure in any single module is reported cleanly and never
--    takes down the boot.
--
--  HARDENING (vs 0.1.0):
--    - Module chunks called with explicit, always-valid arguments
--    - pcall around every module call including the contract return
--    - Missing dependencies become no-ops instead of nil crashes
--    - Boot report printed at the end showing every module status
--    - Loader context validated field by field before use
--    - Caches loaded module tables so re-boots do not re-fetch
--
--  MODULE FILES (repo root):
--    format.lua  - value rendering and executable codegen
--    hook.lua    - namecall capture engine
--    ui.lua      - CoreGui interface
--
--  TARGET    : UNC-compatible Roblox script executors
--  LICENSE   : MIT
--=====================================================================

-----------------------------------------------------------------------
-- SECTION 1 : ENVIRONMENT AND CONTEXT VALIDATION
-----------------------------------------------------------------------

local genv = (type(getgenv) == "function") and getgenv() or _G
local ctx = genv.SimplySpy_Context

if not ctx then
    error("SimplySpy: loader context missing - run loader.lua first")
end

-- Validate every context field we depend on. Each getter degrades
-- safely if the field is missing so a partial context from an
-- older loader version cannot crash the runtime.

local function safeContext()
    local safe = {}

    function safe.log(level, message)
        if type(ctx.log) == "function" then
            pcall(ctx.log, level, message)
        else
            print("[SimplySpy] [" .. tostring(level) .. "] "
                .. tostring(message))
        end
    end

    safe.gui = ctx.gui
    safe.reveal = ctx.reveal
    safe.destroy = ctx.destroy
    safe.version = ctx.version or "?"
    safe.theme = (type(ctx.theme) == "table") and ctx.theme or nil

    return safe
end

local CTX = safeContext()

local VERSION = "0.3.0"
local REPO    = "randomguy454/simplyspirited"
local BRANCH  = "main"

-----------------------------------------------------------------------
-- SECTION 2 : SHARED STATE
-----------------------------------------------------------------------

local STATE = {
    running   = false,
    booted    = false,
    startTime = os.clock(),
    modules   = {},   -- name -> module table or false (failed)
    errors    = {},   -- name -> error string for failed modules
}

-----------------------------------------------------------------------
-- SECTION 3 : BOOT REPORT
-----------------------------------------------------------------------

local REPORT = {}

local function report(stage, ok, detail)
    REPORT[#REPORT + 1] = {
        stage = stage,
        ok = ok,
        detail = detail or "",
    }
    CTX.log(ok and "INFO" or (stage == "boot" and "ERROR" or "WARN"),
        string.format("%s: %s", stage, ok and "ok"
            or ("FAILED - " .. tostring(detail))))
end

-----------------------------------------------------------------------
-- SECTION 4 : MODULE LOADER (HARDENED)
-----------------------------------------------------------------------
-- Every interaction with remote module code is wrapped. The call
-- signature is FIXED: every module chunk is invoked with exactly
-- one argument, the deps table. Modules that expect a different
-- signature fail inside their own pcall, not ours.

local function buildUrl(name)
    return string.format(
        "https://raw.githubusercontent.com/%s/%s/%s/%s.lua",
        REPO, BRANCH, name)
end

local function fetchSource(name)
    local url = buildUrl(name)
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
        return nil, "not found in repository"
    end
    return body
end

local function compileModule(name, source)
    local chunk, err = loadstring(source, "=SimplySpy/" .. name)
    if not chunk then
        return nil, "syntax error: " .. tostring(err)
    end
    return chunk
end

-- The fixed, single-argument deps contract. Fields are populated
-- as modules come online; a field not yet loaded is a no-op stub
-- so cross-module references never dereference nil.
local function makeDeps(name)
    local deps = {
        ctx     = CTX,
        state   = STATE,
        log     = CTX.log,
        name    = name,
    }

    -- Late-bound module access. deps.hook resolves to the real
    -- module once loaded, or a safe stub before that.
    local modulesMeta = {
        __index = function(_, key)
            local mod = STATE.modules[key]
            if mod then
                return mod
            end
            -- Safe stub for a not-yet-loaded or failed module.
            return setmetatable({}, {
                __index = function()
                    return function() end
            end
            })
        end,
    }

    return setmetatable(deps, modulesMeta)
end

local function loadModule(name)
    if STATE.modules[name] then
        return STATE.modules[name], nil
    end
    if STATE.modules[name] == false then
        return nil, STATE.errors[name] or "previously failed"
    end

    local source, fetchErr = fetchSource(name)
    if not source then
        STATE.modules[name] = false
        STATE.errors[name] = fetchErr
        return nil, fetchErr
    end

    local chunk, compileErr = compileModule(name, source)
    if not chunk then
        STATE.modules[name] = false
        STATE.errors[name] = compileErr
        return nil, compileErr
    end

    -- Fixed call signature: exactly one argument, always a table.
    local deps = makeDeps(name)
    local ok, result = pcall(chunk, deps)

    if not ok then
        local err = "runtime error: " .. tostring(result)
        STATE.modules[name] = false
        STATE.errors[name] = err
        return nil, err
    end

    if type(result) ~= "table" then
        local err = "module did not return a table (got "
            .. type(result) .. ")"
        STATE.modules[name] = false
        STATE.errors[name] = err
        return nil, err
    end

    STATE.modules[name] = result
    return result, nil
end

-----------------------------------------------------------------------
-- SECTION 5 : WIRING
-----------------------------------------------------------------------

local WIRING = {
    { name = "format", requires = {} },
    { name = "hook",   requires = { "format" } },
    { name = "ui",     requires = { "format", "hook" } },
}

local function wireModules()
    for _, wire in ipairs(WIRING) do
        local mod, err = loadModule(wire.name)

        if not mod then
            report(wire.name, false, err)
        else
            -- Verify required dependencies actually loaded.
            local missing = {}
            for _, req in ipairs(wire.requires) do
                if STATE.modules[req] == false or STATE.modules[req] == nil then
                    missing[#missing + 1] = req
                end
            end

            if #missing > 0 then
                report(wire.name, false,
                    "skipped, missing deps: " .. table.concat(missing, ", "))
            else
                report(wire.name, true)
            end
        end
    end
end

-----------------------------------------------------------------------
-- SECTION 6 : INIT PASS
-----------------------------------------------------------------------

local function initModules()
    for _, wire in ipairs(WIRING) do
        local mod = STATE.modules[wire.name]
        if mod and type(mod.init) == "function" then
            local ok, err = pcall(mod.init, makeDeps(wire.name))
            if ok then
                report("init:" .. wire.name, true)
            else
                report("init:" .. wire.name, false, tostring(err))
            end
        end
    end
end

-----------------------------------------------------------------------
-- SECTION 7 : CONSOLE API
-----------------------------------------------------------------------

local function buildApi()
    local spy = {}

    function spy.version()
        return VERSION
    end

    function spy.report()
        print("=== SimplySpy Boot Report ===")
        for _, line in ipairs(REPORT) do
            print(string.format("  %-14s %s %s",
                line.stage,
                line.ok and "ok    " or "FAILED",
                line.detail))
        end
        print("=============================")
    end

    -- Safe accessors: every API function checks the module exists
    -- before calling, and pcalls the call itself.
    local function callModule(modName, funcName, ...)
        local mod = STATE.modules[modName]
        if not mod or type(mod[funcName]) ~= "function" then
            print("SimplySpy: " .. modName .. "." .. funcName
                .. " unavailable (module failed to load)")
            return
        end
        local ok, err = pcall(mod[funcName], ...)
        if not ok then
            print("SimplySpy: " .. modName .. "." .. funcName
                .. " error: " .. tostring(err))
        end
    end

    function spy.count()
        local mod = STATE.modules.hook
        if mod and type(mod.count) == "function" then
            return mod.count()
        end
        return 0
    end

    function spy.clear()
        callModule("hook", "clear")
        callModule("ui", "refresh")
    end

    function spy.filter(name)
        callModule("hook", "setFilter", name)
    end

    function spy.block(name)
        callModule("hook", "setBlocked", name, true)
    end

    function spy.unblock(name)
        callModule("hook", "setBlocked", name, false)
    end

    function spy.list(n)
        callModule("hook", "list", n or 10)
    end

    function spy.dump(n)
        callModule("hook", "dump", n)
    end

    function spy.copy(n)
        callModule("hook", "copy", n)
    end

    function spy.toggle()
        callModule("ui", "toggle")
    end

    function spy.hide()
        callModule("ui", "hide")
    end

    function spy.show()
        callModule("ui", "show")
    end

    return spy
end

-----------------------------------------------------------------------
-- SECTION 8 : BOOT SEQUENCE
-----------------------------------------------------------------------

local function boot()
    CTX.log("INFO", "runtime v" .. VERSION .. " booting")

    wireModules()
    initModules()

    -- UI is optional: if it loaded, show it. If not, console mode.
    local ui = STATE.modules.ui
    if ui and type(ui.show) == "function" then
        local ok, err = pcall(ui.show)
        report("ui:show", ok, not ok and tostring(err) or nil)
    else
        report("ui:show", false, "console mode")
    end

    STATE.running = true
    STATE.booted = true

    -- Boot summary to the console.
    local failed = 0
    for _, wire in ipairs(WIRING) do
        if STATE.modules[wire.name] == false then
            failed = failed + 1
        end
    end

    if failed == 0 then
        CTX.log("INFO", "all modules online")
    else
        CTX.log("WARN", failed .. " module(s) failed; run SPY.report()")
    end

    -- Publish the console API even in degraded states.
    genv.SPY = buildApi()

    -- Reveal the loader transition only when everything that could
    -- show UI has had its chance.
    if type(CTX.reveal) == "function" then
        pcall(CTX.reveal)
    end
end

-----------------------------------------------------------------------
-- SECTION 9 : ENTRY
-----------------------------------------------------------------------

local ok, err = pcall(boot)
if not ok then
    CTX.log("ERROR", "fatal: " .. tostring(err))
    -- The loader error card takes over from here.
    error("SimplySpy: " .. tostring(err))
end
