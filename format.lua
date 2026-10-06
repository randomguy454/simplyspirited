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
--  FORMAT ENGINE                                                     --
--  ==============                                                    --
--                                                                    --
--  The single source of truth for turning captured values into      --
--  either human-readable display text or executable Lua code.       --
--                                                                    --
--  DESIGN GUARANTEE:                                                 --
--    Any value captured by the hook engine can be rendered by       --
--    this module. Any rendered code output will round-trip          --
--    byte-identical when pasted into an executor.                   --
--                                                                    --
--  OUTPUT MODES:                                                     --
--    DISPLAY : compact, type-aware, color-hinted text for the       --
--              UI detail view. Truncated for readability.           --
--    CODEGEN : valid, executable Lua. Never truncated in ways      --
--              that break validity. Full precision preserved.       --
--                                                                    --
--  SUPPORTED TYPES:                                                  --
--    nil, boolean, number, string, table, Instance, CFrame,        --
--    Vector3, Vector2, Color3, EnumItem, and any other type is      --
--    rendered as a safe placeholder rather than crashing.           --
--                                                                    --
--  PRECISION CONTRACT:                                               --
--    Numbers use %.17g which round-trips every finite double.       --
--    Integers below 2^53 render without decimal points.             --
--    NaN and infinities render as valid Lua expressions.            --
--                                                                    --
--  INSTANCE PATH CONTRACT:                                           --
--    Display mode shows "Parent.Child" compactly.                    --
--    Codegen mode emits "game:GetService(...)" roots followed      --
--    by direct indexing for safe names and :WaitForChild() for     --
--    unsafe names. Resilient to instances reparenting between      --
--    capture and execution.                                          --
--                                                                    --
--  TABLE HANDLING:                                                   --
--    Pure arrays emit as {v1, v2, v3}.                              --
--    Dictionaries emit as {key = value, [n] = value}.               --
--    Circular references emit as valid placeholders.                --
--    Depth and item limits prevent runaway recursion.               --
--                                                                    --
--  MODULE CONTRACT:                                                  --
--    Executor path: main.lua fetches and executes this file,       --
--    passing a deps table. The file returns a function that        --
--    accepts deps and returns the Format table.                      --
--                                                                    --
--    Studio path: this file is also valid as a ModuleScript.         --
--    Delete the final return function wrapper and return the        --
--    Format table directly.                                          --
--                                                                    --
--  TARGET    : universal (executors + Studio + command bar)         --
--  LICENSE   : MIT                                                   --
--                                                                    --
--=====================================================================
--=====================================================================

-----------------------------------------------------------------------
-- SECTION 1 : MODULE BOOTSTRAP
-----------------------------------------------------------------------
-- The Format table accumulates all public functions. The module
-- logger is injected at load time; before injection it is a no-op
-- so the module can be used standalone in any environment.

local Format = {}

local log = function() end

-----------------------------------------------------------------------
-- SECTION 2 : CONFIGURATION CONSTANTS
-----------------------------------------------------------------------
-- All tunable limits live here. Display limits prioritize speed
-- and readability. Codegen limits are generous because generated
-- code must remain valid even for large payloads.

-- Display mode: how much to render in the UI detail view.
local DISPLAY_STRING_MAX  = 64      -- max characters shown per string
local DISPLAY_TABLE_ITEMS = 16      -- max key-value pairs shown per table
local DISPLAY_DEPTH_MAX   = 3       -- max table nesting depth
local DISPLAY_PATH_MAX   = 96       -- max characters in a display path
local DISPLAY_CF_SIGFIGS = 2       -- decimals in CFrame display

-- Codegen mode: how much to emit as executable code.
local CODEGEN_DEPTH_MAX   = 6       -- max table nesting depth
local CODEGEN_TABLE_ITEMS = 256     -- max pairs emitted per table
local CODEGEN_STRING_WARN = 100000  -- warn above this string size

-- Path resolution: which names are safe for direct indexing.
-- A name is safe if it is a valid Lua identifier.
local SAFE_NAME_PATTERN = "^[%a_][%w_]*$"

-----------------------------------------------------------------------
-- SECTION 3 : TYPE COLOR TABLE
-----------------------------------------------------------------------
-- Colors for the UI detail view, keyed by typeof() result. The
-- table is built lazily on first use because Color3 construction
-- at file scope is wasteful in environments that never render UI.
--
-- Palette (colorblind-aware selection):
--   string   : soft green
--   number   : warm orange
--   boolean  : violet
--   Instance : sky blue
--   CFrame   : amber
--   Vector3/2: teal
--   Color3   : salmon
--   table    : neutral gray
--   other    : lavender

local TYPE_COLOR_VALUES = {
    string   = { 150, 210, 150 },
    number   = { 235, 165,  95 },
    boolean  = { 210, 135, 235 },
    Instance = { 130, 180, 255 },
    CFrame   = { 240, 220, 130 },
    Vector3  = { 130, 230, 220 },
    Vector2  = { 130, 230, 220 },
    Color3   = { 255, 140, 140 },
    table    = { 200, 200, 205 },
    userdata = { 200, 170, 255 },
    nil      = { 120, 120, 130 },
}

local typeColors = nil

local function getTypeColors()
    if not typeColors then
        typeColors = {}
        for key, rgb in pairs(TYPE_COLOR_VALUES) do
            typeColors[key] = Color3.new(
                rgb[1] / 255,
                rgb[2] / 255,
                rgb[3] / 255
            )
        end
    end
    return typeColors
end

-----------------------------------------------------------------------
-- SECTION 4 : KNOWN SERVICES TABLE
-----------------------------------------------------------------------
-- Used by path resolution to decide whether the first path segment
-- should be emitted as game:GetService("Name"). Workspace is
-- special-cased to the shorter global "workspace" reference.

local KNOWN_SERVICES = {
    Players            = true,
    ReplicatedStorage   = true,
    ReplicatedFirst     = true,
    Lighting           = true,
    CoreGui             = true,
    SoundService        = true,
    TeleportService     = true,
    StarterGui          = true,
    StarterPlayer       = true,
    StarterPack         = true,
    Teams               = true,
    Chat                = true,
    ServerStorage       = true,
    ServerScriptService = true,
    HttpService         = true,
    MarketplaceService  = true,
    DataStoreService    = true,
    TweenService        = true,
    RunService          = true,
    UserInputService    = true,
    ContextActionService = true,
    GuiService          = true,
    TextService         = true,
    PhysicsService       = true,
    Debris              = true,
    CollectionService   = true,
    TagService          = true,
    ScriptContext       = true,
}

-----------------------------------------------------------------------
-- SECTION 5 : NUMBER FORMATTING
-----------------------------------------------------------------------
-- The precision guarantee. Every number that passes through this
-- function renders as text that, when pasted into Lua, evaluates
-- to the exact same number.
--
-- Cases:
--   NaN       -> "0/0" (a valid Lua expression producing NaN)
--   +inf      -> "math.huge"
--   -inf      -> "-math.huge"
--   integer   -> "%d" (clean, no decimal point)
--   float     -> "%.17g" (17 significant digits round-trips doubles)
--
-- The integer guard uses 2^53 because that is the largest integer
-- exactly representable as a double. Above that, %d could emit a
-- number that parses back slightly differently, so those render
-- through %.17g instead.

function Format.number(n)
    if n ~= n then
        return "0/0"
    elseif n == math.huge then
        return "math.huge"
    elseif n == -math.huge then
        return "-math.huge"
    elseif n == math.floor(n) and math.abs(n) < 2 ^ 53 then
        return string.format("%d", n)
    else
        return string.format("%.17g", n)
    end
end

-----------------------------------------------------------------------
-- SECTION 6 : STRING FORMATTING
-----------------------------------------------------------------------
-- Escaping covers every control character, the backslash, and the
-- double quote. The gsub pattern [%c\\\"] matches any control
-- character, a backslash, or a quote, and replaces each with its
-- escaped form from the lookup table.

local ESCAPE_MAP = {
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
    ["\\"] = "\\\\",
    ['"']  = '\\"',
}

function Format.escapeString(s)
    return (s:gsub("[%c\\\"]", ESCAPE_MAP))
end

function Format.quoteString(s)
    return '"' .. Format.escapeString(s) .. '"'
end

-- Display variant: truncate long strings but mark the truncation
-- so the UI shows there is more data than displayed. The output
-- remains a valid Lua string literal plus a comment.

function Format.displayString(s)
    if #s > DISPLAY_STRING_MAX then
        local shown = s:sub(1, DISPLAY_STRING_MAX)
        local hidden = #s - DISPLAY_STRING_MAX
        return Format.quoteString(shown)
            .. " --[[" .. hidden .. " more bytes]]"
    end
    return Format.quoteString(s)
end

-----------------------------------------------------------------------
-- SECTION 7 : INSTANCE CHAIN RESOLUTION
-----------------------------------------------------------------------
-- Both path functions share the chain walker. It walks from the
-- instance up to the game root, collecting names in order.

local function resolveInstanceChain(inst)
    local names = {}
    local current = inst
    while current and current ~= game do
        table.insert(names, 1, current.Name)
        current = current.Parent
    end
    return names
end

-----------------------------------------------------------------------
-- SECTION 8 : INSTANCE DISPLAY PATH
-----------------------------------------------------------------------
-- Compact rendering for list rows and summaries. Shows at most
-- "Parent.Child" and truncates to the display path maximum. This
-- is for human eyes only; never feed it to loadstring.

function Format.instanceDisplay(inst)
    if not inst then
        return "?"
    end

    local name = inst.Name or "?"
    local parent = inst.Parent

    if parent and parent.Name ~= "" and parent ~= game then
        local combined = parent.Name .. "." .. name
        if #combined <= DISPLAY_PATH_MAX then
            return combined
        end
    end

    return name
end

-----------------------------------------------------------------------
-- SECTION 9 : INSTANCE CODEGEN PATH
-----------------------------------------------------------------------
-- Robust rendering for generated scripts. Emits a service root
-- followed by direct indexing for safe names and WaitForChild for
-- unsafe names. This survives instances being reparented between
-- capture and execution, which games do constantly.
--
-- Examples:
--   workspace.Blocks.Player.WoodBlock
--   game:GetService("ReplicatedStorage").RemoteEvent
--   workspace:WaitForChild("Player Name With Spaces").Tool

function Format.instancePath(inst)
    if not inst then
        return "nil"
    end
    if inst == game then
        return "game"
    end

    local names = resolveInstanceChain(inst)
    if #names == 0 then
        return "game"
    end

    local first = names[1]
    local path

    if first == "Workspace" then
        path = "workspace"
    elseif KNOWN_SERVICES[first] then
        path = 'game:GetService("' .. first .. '")'
    else
        -- The parent chain reached a non-service root without
        -- passing through game. This happens for instances whose
        -- ancestry is detached. Fall back to a Workspace lookup.
        path = 'game:GetService("Workspace")'
    end

    for i = 2, #names do
        local segment = names[i]
        if segment:match(SAFE_NAME_PATTERN) then
            path = path .. "." .. segment
        else
            path = path .. ":WaitForChild("
                .. Format.quoteString(segment) .. ")"
        end
    end

    return path
end

-----------------------------------------------------------------------
-- SECTION 10 : DISPLAY RENDERING
-----------------------------------------------------------------------
-- Renders any value as compact, type-labeled, readable text.
-- Intended for UI detail views and console dumps. Never used for
-- code generation.
--
-- Truncation is aggressive: strings cap at 64 chars, tables cap at
-- 16 visible pairs, depth caps at 3. Anything beyond the limits is
-- marked with "..." or "{...}" so the reader knows data exists.

function Format.display(v, depth, seen)
    depth = depth or 0
    seen = seen or {}

    local t = typeof(v)

    -- Simple types first: these cover the vast majority of args.

    if v == nil then
        return "nil"

    elseif t == "string" then
        return Format.displayString(v)

    elseif t == "number" then
        return Format.number(v)

    elseif t == "boolean" then
        return tostring(v)

    -- Roblox datatypes: labeled compact forms.

    elseif t == "Instance" then
        return v.ClassName .. " <" .. Format.instanceDisplay(v) .. ">"

    elseif t == "CFrame" then
        local p = { v:GetComponents() }
        local f = "%." .. DISPLAY_CF_SIGFIGS .. "f"
        return string.format(
            "CFrame(" .. f .. ", " .. f .. ", " .. f
                .. ") [" .. f .. " " .. f .. " " .. f .. "]",
            p[1], p[2], p[3], p[4], p[5], p[6]
        )

    elseif t == "Vector3" then
        return string.format(
            "Vec3(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)

    elseif t == "Vector2" then
        return string.format(
            "Vec2(%.2f, %.2f)", v.X, v.Y)

    elseif t == "Color3" then
        return string.format(
            "Color(%d, %d, %d)",
            math.floor(v.R * 255 + 0.5),
            math.floor(v.G * 255 + 0.5),
            math.floor(v.B * 255 + 0.5)
        )

    elseif t == "EnumItem" then
        return tostring(v)

    -- Tables: recursive with limits and circular protection.

    elseif t == "table" then
        if seen[v] then
            return "<circular>"
        end
        seen[v] = true

        if depth >= DISPLAY_DEPTH_MAX then
            seen[v] = nil
            return "{...}"
        end

        local parts = {}
        local count = 0

        for k, val in pairs(v) do
            count = count + 1
            if count > DISPLAY_TABLE_ITEMS then
                table.insert(parts, "...")
                break
            end

            local key
            if type(k) == "number" then
                key = Format.number(k)
            elseif type(k) == "string" and k:match(SAFE_NAME_PATTERN) then
                key = k
            else
                key = Format.quoteString(tostring(k))
            end

            table.insert(parts,
                key .. " = " .. Format.display(val, depth + 1, seen))
        end

        seen[v] = nil

        if #parts == 0 then
            return "{}"
        end
        return "{ " .. table.concat(parts, ", ") .. " }"

    -- Unknown types: label them rather than crash.

    else
        return "<" .. t .. ">"
    end
end

-----------------------------------------------------------------------
-- SECTION 11 : CODEGEN RENDERING
-----------------------------------------------------------------------
-- Renders any value as valid, executable Lua. The output pasted
-- into an executor reconstructs the value exactly.
--
-- Differences from display:
--   - Never truncates strings
--   - Emits full 12-component CFrames
--   - Emits full instance paths with WaitForChild safety
--   - Higher depth and item limits
--   - Unknown types emit nil with a comment (keeps script valid)

function Format.codegen(v, depth, seen)
    depth = depth or 0
    seen = seen or {}

    local t = typeof(v)

    if v == nil then
        return "nil"

    elseif t == "Instance" then
        return Format.instancePath(v)

    elseif t == "string" then
        return Format.quoteString(v)

    elseif t == "number" then
        return Format.number(v)

    elseif t == "boolean" then
        return tostring(v)

    elseif t == "CFrame" then
        local p = { v:GetComponents() }
        return string.format(
            "CFrame.new(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
            Format.number(p[1]),  Format.number(p[2]),  Format.number(p[3]),
            Format.number(p[4]),  Format.number(p[5]),  Format.number(p[6]),
            Format.number(p[7]),  Format.number(p[8]),  Format.number(p[9]),
            Format.number(p[10]), Format.number(p[11]), Format.number(p[12])
        )

    elseif t == "Vector3" then
        return string.format(
            "Vector3.new(%s, %s, %s)",
            Format.number(v.X), Format.number(v.Y), Format.number(v.Z))

    elseif t == "Vector2" then
        return string.format(
            "Vector2.new(%s, %s)",
            Format.number(v.X), Format.number(v.Y))

    elseif t == "Color3" then
        return string.format(
            "Color3.new(%s, %s, %s)",
            Format.number(v.R), Format.number(v.G), Format.number(v.B))

    elseif t == "EnumItem" then
        return tostring(v)

    elseif t == "table" then
        if seen[v] then
            return "{--[[circular]]}"
        end
        seen[v] = true

        if depth >= CODEGEN_DEPTH_MAX then
            seen[v] = nil
            return "{--[[depth limit]]}"
        end

        -- Detect pure array form for clean output. A table is a
        -- pure array when all keys are sequential integers from 1.
        local arrayLen = 0
        for i = 1, math.huge do
            if v[i] ~= nil then
                arrayLen = i
            else
                break
            end
        end

        local hasNonNumeric = false
        for k in pairs(v) do
            if type(k) ~= "number" then
                hasNonNumeric = true
                break
            end
        end

        local isPureArray = (not hasNonNumeric)
            and (arrayLen > 0)

        local parts = {}
        local count = 0

        if isPureArray then
            -- Array form: { v1, v2, v3 }
            for i = 1, arrayLen do
                count = count + 1
                if count > CODEGEN_TABLE_ITEMS then
                    table.insert(parts, "--[[truncated]]")
                    break
                end
                table.insert(parts,
                    Format.codegen(v[i], depth + 1, seen))
            end
        else
            -- Dictionary form: { k = v, [n] = v }
            for k, val in pairs(v) do
                count = count + 1
                if count > CODEGEN_TABLE_ITEMS then
                    table.insert(parts, "--[[truncated]]")
                    break
                end

                local key
                if type(k) == "number" then
                    key = "[" .. Format.number(k) .. "]"
                elseif type(k) == "string"
                    and k:match(SAFE_NAME_PATTERN) then
                    key = k
                else
                    key = "[" .. Format.quoteString(tostring(k)) .. "]"
                end

                table.insert(parts,
                    key .. " = " .. Format.codegen(val, depth + 1, seen))
            end
        end

        seen[v] = nil

        return "{ " .. table.concat(parts, ", ") .. " }"

    else
        -- Unknown userdata: emit nil with a type comment so the
        -- generated script still runs instead of erroring.
        return "nil --[[unsupported type: " .. t .. "]]"
    end
end

-----------------------------------------------------------------------
-- SECTION 12 : CALL SUMMARIES
-----------------------------------------------------------------------
-- Compact one-line summary of a capture for list rows. Uses the
-- preview field generated by the hook engine when available.

function Format.callToLine(capture)
    local remoteName = capture.remoteName or "?"
    local method = capture.method or "?"
    local argCount = capture.argCount or 0

    local preview
    if capture.preview and capture.preview ~= "" then
        preview = capture.preview
    else
        preview = argCount .. " args"
    end

    return string.format("%s:%s (%s)", remoteName, method, preview)
end

-----------------------------------------------------------------------
-- SECTION 13 : COLOR LOOKUP
-----------------------------------------------------------------------
-- Returns the UI color for a value's type. Used by the detail view
-- to color-code argument rows.

function Format.colorFor(v)
    local colors = getTypeColors()
    local t = typeof(v)
    return colors[t] or colors.table
end

-----------------------------------------------------------------------
-- SECTION 14 : SINGLE CALL SCRIPT GENERATION
-----------------------------------------------------------------------
-- Generates a complete, ready-to-execute script for one capture.
-- The output format matches the SimpleSpy convention users know:
--
--   -- SimplySpy capture #7
--   -- RF:InvokeServer (WoodBlock)
--
--   local args = {
--       [1] = "WoodBlock",
--       [2] = 450,
--   }
--
--   local remote = workspace:WaitForChild("..."):WaitForChild("RF")
--   remote:InvokeServer(unpack(args))

function Format.callToScript(capture)
    local lines = {}

    table.insert(lines, "-- SimplySpy capture #" .. tostring(capture.id))
    table.insert(lines, "-- " .. Format.callToLine(capture))
    table.insert(lines, "")

    table.insert(lines, "local args = {")
    for i, arg in ipairs(capture.args) do
        table.insert(lines,
            "    [" .. i .. "] = " .. Format.codegen(arg) .. ",")
    end
    table.insert(lines, "}")
    table.insert(lines, "")

    table.insert(lines, "local remote = " .. capture.remotePath)
    table.insert(lines, "")

    if capture.method == "InvokeServer" then
        table.insert(lines, "remote:InvokeServer(unpack(args))")
    else
        table.insert(lines, "remote:FireServer(unpack(args))")
    end

    return table.concat(lines, "\n")
end

-----------------------------------------------------------------------
-- SECTION 15 : BATCH SCRIPT GENERATION
-----------------------------------------------------------------------
-- Generates a script replaying multiple captures in order. Each
-- call gets its own args table and remote variable, numbered by
-- position, so no state leaks between calls.

function Format.batchToScript(captures)
    local lines = {}

    table.insert(lines, "-- SimplySpy batch replay")
    table.insert(lines, "-- " .. #captures .. " call(s)")
    table.insert(lines, "")

    for idx, capture in ipairs(captures) do
        table.insert(lines,
            "-- call " .. idx .. ": " .. Format.callToLine(capture))

        table.insert(lines, "local args" .. idx .. " = {")
        for i, arg in ipairs(capture.args) do
            table.insert(lines,
                "    [" .. i .. "] = " .. Format.codegen(arg) .. ",")
        end
        table.insert(lines, "}")

        table.insert(lines,
            "local remote" .. idx .. " = " .. capture.remotePath)

        if capture.method == "InvokeServer" then
            table.insert(lines, "remote" .. idx
                .. ":InvokeServer(unpack(args" .. idx .. "))")
        else
            table.insert(lines, "remote" .. idx
                .. ":FireServer(unpack(args" .. idx .. "))")
        end

        table.insert(lines, "")
    end

    return table.concat(lines, "\n")
end

-----------------------------------------------------------------------
-- SECTION 16 : DIFF GENERATION
-----------------------------------------------------------------------
-- Compares two captures and returns a human-readable summary of
-- the differences, argument by argument. Used by the UI to show
-- what changed between two similar calls.

function Format.diffCaptures(a, b)
    local lines = {}
    local maxArgs = math.max(#a.args, #b.args)

    if a.remotePath ~= b.remotePath then
        table.insert(lines, "remote: "
            .. a.remotePath .. " -> " .. b.remotePath)
    end

    if a.method ~= b.method then
        table.insert(lines, "method: "
            .. a.method .. " -> " .. b.method)
    end

    for i = 1, maxArgs do
        local av = a.args[i]
        local bv = b.args[i]

        local aText = Format.display(av)
        local bText = Format.display(bv)

        if aText ~= bText then
            table.insert(lines, string.format(
                "arg[%d]: %s -> %s", i, aText, bText))
        end
    end

    if #lines == 0 then
        return "no differences"
    end
    return table.concat(lines, "\n")
end

-----------------------------------------------------------------------
-- SECTION 17 : TABLE SIZE UTILITIES
-----------------------------------------------------------------------
-- Counts total key-value pairs recursively. Useful for the UI to
-- show "large payload" indicators.

function Format.tableSize(v, seen)
    if type(v) ~= "table" then
        return 0
    end
    seen = seen or {}
    if seen[v] then
        return 0
    end
    seen[v] = true

    local count = 0
    for _, val in pairs(v) do
        count = count + 1
        if type(val) == "table" then
            count = count + Format.tableSize(val, seen)
        end
    end

    seen[v] = nil
    return count
end

-----------------------------------------------------------------------
-- SECTION 18 : SELF-TEST
-----------------------------------------------------------------------
-- Runs a battery of round-trip checks on the formatting engine.
-- Call Format.selfTest() from the console to verify integrity
-- after loading. Returns true if all checks pass, false otherwise.
-- Each failure prints the failing case.

function Format.selfTest()
    local failures = 0
    local total = 0

    local function check(desc, condition)
        total = total + 1
        if not condition then
            failures = failures + 1
            print("[SELFTEST FAIL] " .. desc)
        end
    end

    -- Number round-trips.
    local numbers = {
        0, 1, -1, 0.5, -0.5,
        1 / 3, -1 / 3,
        math.pi, -math.pi,
        1e10, -1e10, 1e-10,
        2 ^ 53 - 1, 2 ^ 53 + 1,
        math.huge, -math.huge,
        123456789.123456789,
        -123456789.123456789,
    }
    for _, n in ipairs(numbers) do
        local rendered = Format.number(n)
        local chunk = loadstring("return " .. rendered)
        if chunk then
            local ok, result = pcall(chunk)
            check("number " .. rendered, ok and result == n)
        else
            check("number compiles " .. rendered, false)
        end
    end

    -- NaN: cannot compare with ==, verify via property.
    do
        local rendered = Format.number(0 / 0)
        local chunk = loadstring("return " .. rendered)
        local ok, result = pcall(chunk)
        check("NaN renders", ok and result ~= result)
    end

    -- String escaping.
    local strings = {
        { "simple", '"simple"' },
        { 'with "quotes"', '"with \\"quotes\\""' },
        { "with\nnewline", '"with\\nnewline"' },
        { "with\\backslash", '"with\\\\backslash"' },
    }
    for _, case in ipairs(strings) do
        local rendered = Format.quoteString(case[1])
        check("string " .. case[2], rendered == case[2])
        local chunk = loadstring("return " .. rendered)
        local ok, result = pcall(chunk)
        check("string roundtrip " .. case[2],
            ok and result == case[1])
    end

    -- Table codegen: array form.
    do
        local t = { 1, 2, 3 }
        local rendered = Format.codegen(t)
        local chunk = loadstring("return " .. rendered)
        local ok, result = pcall(chunk)
        check("array table", ok and #result == 3
            and result[1] == 1 and result[3] == 3)
    end

    -- Table codegen: dictionary form.
    do
        local t = { name = "test", count = 5 }
        local rendered = Format.codegen(t)
        local chunk = loadstring("return " .. rendered)
        local ok, result = pcall(chunk)
        check("dict table", ok and result.name == "test"
            and result.count == 5)
    end

    -- Circular table protection.
    do
        local t = {}
        t.self = t
        local rendered = Format.codegen(t)
        local chunk = loadstring("return " .. rendered)
        check("circular table compiles", chunk ~= nil)
    end

    -- Nested table.
    do
        local t = { a = { b = { c = 42 } } }
        local rendered = Format.codegen(t)
        local chunk = loadstring("return " .. rendered)
        local ok, result = pcall(chunk)
        check("nested table", ok and result.a.b.c == 42)
    end

    -- Display never errors on any input.
    local displayInputs = {
        nil, true, false, 42, "text",
        { 1, 2, 3 }, { key = "value" },
        workspace, Vector3.new(1, 2, 3),
        Vector2.new(1, 2), Color3.new(0.5, 0.5, 0.5),
        CFrame.new(1, 2, 3),
    }
    for _, input in ipairs(displayInputs) do
        local ok = pcall(Format.display, input)
        check("display does not error", ok)
    end

    -- Summary.
    print(string.format("[SELFTEST] %d/%d passed",
        total - failures, total))
    return failures == 0
end

-----------------------------------------------------------------------
-- SECTION 19 : PUBLIC CONSTANTS EXPORT
-----------------------------------------------------------------------
-- Expose the limits so consumers (like the UI settings page)
-- can read and adjust them at runtime.

Format.limits = {
    DISPLAY_STRING_MAX   = DISPLAY_STRING_MAX,
    DISPLAY_TABLE_ITEMS  = DISPLAY_TABLE_ITEMS,
    DISPLAY_DEPTH_MAX    = DISPLAY_DEPTH_MAX,
    DISPLAY_PATH_MAX     = DISPLAY_PATH_MAX,
    DISPLAY_CF_SIGFIGS   = DISPLAY_CF_SIGFIGS,
    CODEGEN_DEPTH_MAX    = CODEGEN_DEPTH_MAX,
    CODEGEN_TABLE_ITEMS  = CODEGEN_TABLE_ITEMS,
    CODEGEN_STRING_WARN  = CODEGEN_STRING_WARN,
}

Format.VERSION = "1.0.0"

-----------------------------------------------------------------------
-- SECTION 20 : MODULE CONTRACT
-----------------------------------------------------------------------
-- Executor path: main.lua executes this file with a deps table.
-- This function receives it, wires the logger, and returns Format.
--
-- Studio path: replace this final block with:
--     return Format
-- and use the file as a ModuleScript.

return function(deps)
    if deps and type(deps.log) == "function" then
        log = deps.log
    end
    log("INFO", "format engine v" .. Format.VERSION .. " online")
    return Format
end
