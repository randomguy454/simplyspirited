--=====================================================================
--  PROJECT   : SimplySpy
--  FILE      : main.lua (ORCHESTRATOR)
--  VERSION   : 0.1.0
--
--  PURPOSE   :
--    Runtime entry point. Receives the loader context, fetches and
--    boots the three subsystem modules in dependency order, wires
--    them together, and manages the tool lifecycle.
--
--  MODULES   :
--    format.lua  - value rendering and executable codegen
--    hook.lua    - namecall capture engine and ring buffer
--    ui.lua      - CoreGui interface
--
--  CONTRACT  (set by loader.lua):
--    ctx.gui       ScreenGui container for all runtime UI
--    ctx.reveal()  call when ready; loader performs its outro
--    ctx.theme     shared color palette
--    ctx.capabilities  executor feature detection
--    ctx.log(level, msg)  shared logger
--
--  TARGET    : UNC-compatible Roblox script executors
--  LICENSE   : MIT
--=====================================================================

-----------------------------------------------------------------------
-- SECTION 1 : CONTEXT AND CONSTANTS
-----------------------------------------------------------------------

local genv = (typeof(getgenv) == "function") and getgenv() or _G
local ctx = genv.SimplySpy_Context

if not ctx then
    error("SimplySpy: loader context missing")
end

local VERSION = "0.1.0"
local REPO    = "randomguy454/simplyspirited"
local BRANCH  = "main"

-- Boot order. Format has no dependencies. Hook needs Format for
-- arg snapshotting. UI needs everything. Order is enforced.
local MODULE_ORDER = { "format", "hook", "ui" }

-- Registry filled during boot: MODULES.format, MODULES.hook, ...
local MODULES = {}

-- Central application state, shared by all modules.
local STATE = {
    running     = false,
    captures    = 0,      -- total seen since boot
    version     = VERSION,
}

-----------------------------------------------------------------------
-- SECTION 2 : MODULE LOADER
-----------------------------------------------------------------------
-- Executors cannot use require() for remote sources. Each module
-- is fetched, validated, and executed with a private environment
-- that receives this file's exports. A module returns its table.

local function buildUrl(name)
    return string.format(
        "https://raw.githubusercontent.com/%s/%s/%s/%s.lua",
        REPO, BRANCH, name
    )
end

local function fetchModule(name)
    local url = buildUrl(name)
    local ok, body = pcall(function()
        return game:HttpGet(url, true)
    end)

    if not ok or type(body) ~= "string" or #body == 0 then
        return nil, "fetch failed for " .. name
    end
    if body:sub(1, 4) == "404:" then
        return nil, name .. ".lua not found in repository"
    end
    return body
end

local function loadModule(name)
    local source, err = fetchModule(name)
    if not source then
        return nil, err
    end

    -- Compile first: syntax errors surface with a real message
    -- instead of a silent executor death.
    local chunk, synErr = loadstring(source, "=SimplySpy/" .. name)
    if not chunk then
        return nil, name .. " syntax error: " .. tostring(synErr)
    end

    -- Execute with the exports table as the single argument.
    -- This is the module contract: every module receives (deps)
    -- and returns its public table.
    local exports = {
        ctx         = ctx,
        state       = STATE,
        log         = ctx.log,
        -- Modules populated during boot, injected before use:
        -- format, hook, ui are added as they come online.
    }

    local ok, result = pcall(chunk, exports)
    if not ok then
        return nil, name .. " runtime error: " .. tostring(result)
    end
    if type(result) ~= "table" then
        return nil, name .. " did not return a module table"
    end

    return result
end

-----------------------------------------------------------------------
-- SECTION 3 : BOOT SEQUENCE
-----------------------------------------------------------------------

local function boot()
    ctx.log("INFO", "runtime " .. VERSION .. " booting")

    -- Load modules in dependency order, wiring each into exports
    -- so later modules can consume earlier ones.
    for _, name in ipairs(MODULE_ORDER) do
        local module, err = loadModule(name)
        if not module then
            ctx.log("ERROR", err)
            error("SimplySpy boot failed: " .. tostring(err))
        end

        MODULES[name] = module

        -- Publish to shared state for subsequent modules.
        STATE[name] = module

        ctx.log("INFO", "module " .. name .. " online")
    end

    -- Post-load init pass: modules with an :init() get called
    -- after ALL modules exist, so cross-module wiring is safe.
    for _, name in ipairs(MODULE_ORDER) do
        local module = MODULES[name]
        if typeof(module.init) == "function" then
            local ok, err = pcall(module.init)
            if not ok then
                ctx.log("WARN", "init " .. name .. ": " .. tostring(err))
            end
        end
    end

    STATE.running = true
    ctx.log("INFO", "SimplySpy fully operational")

    -- Build the interface last, then perform the loader reveal
    -- transition so the user sees one continuous animation.
    if MODULES.ui and typeof(MODULES.ui.show) == "function" then
        MODULES.ui.show()
    end

    ctx.reveal()
end

-----------------------------------------------------------------------
-- SECTION 4 : GLOBAL API
-----------------------------------------------------------------------
-- Console commands available without the UI. Registered after
-- boot so they can never reference a half-initialized module.

local function setupGlobalApi()
    local spy = {}

    function spy.version()
        return VERSION
    end

    function spy.count()
        return MODULES.hook and MODULES.hook.count() or 0
    end

    function spy.clear()
        if MODULES.hook then MODULES.hook.clear() end
        if MODULES.ui then MODULES.ui.refresh() end
    end

    function spy.filter(name)
        if MODULES.hook then MODULES.hook.setFilter(name) end
    end

    function spy.block(name)
        if MODULES.hook then MODULES.hook.setBlocked(name, true) end
    end

    function spy.unblock(name)
        if MODULES.hook then MODULES.hook.setBlocked(name, false) end
    end

    function spy.list(n)
        if MODULES.hook then MODULES.hook.list(n or 10) end
    end

    function spy.dump(n)
        if MODULES.hook then MODULES.hook.dump(n) end
    end

    function spy.copy(n)
        if MODULES.hook then MODULES.hook.copy(n) end
    end

    genv.SPY = spy
    ctx.log("INFO", "console API ready (SPY.*)")
end

-----------------------------------------------------------------------
-- SECTION 5 : ENTRY
-----------------------------------------------------------------------

local ok, err = pcall(boot)
if not ok then
    ctx.log("ERROR", "fatal: " .. tostring(err))
    -- Keep the loader UI alive to display the failure instead of
    -- dying silently. The loader error card handles the rest.
    error("SimplySpy: " .. tostring(err))
end

setupGlobalApi()
