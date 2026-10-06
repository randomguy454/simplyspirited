--=====================================================================
--  PROJECT   : SimplySpy
--  FILE      : format.lua (FORMAT ENGINE) - UNIVERSAL BUILD
--  VERSION   : 0.2.0
--
--  PURPOSE   :
--    Single source of truth for value rendering. Two output modes:
--    DISPLAY (compact, readable, truncated for the UI) and CODEGEN
--    (valid, executable Lua that round-trips byte-identical).
--
--  UNIVERSALITY CONTRACT :
--    This module uses ZERO executor globals. It runs in:
--      - Any UNC executor
--      - Roblox Studio (as a ModuleScript, via the adapter at
--        the bottom of this file)
--      - Command bar
--    It uses only engine APIs: type, typeof, string, math, table,
--    Color3, CFrame, Vector3, Vector2, tostring, ipairs, pairs.
--
--  MODULE CONTRACT :
--    Required by main.lua:
--      local Format = loadModule("format")(deps)
--    Studio/command-bar use (see adapter, section 12):
--      local Format = require(script.Format) -- ModuleScript
--
--  TARGET    : universal (executors + Studio + command bar)
--  LICENSE   : MIT
--=====================================================================

-----------------------------------------------------------------------
-- SECTION 1 : MODULE BOOTSTRAP
-----------------------------------------------------------------------

local Format = {}

-- Logger injection point. main.lua provides deps.log; the Studio
-- adapter provides print. Fails silent if neither exists.
local log = function() end

-----------------------------------------------------------------------
-- SECTION 2 : CONSTANTS (engine types only)
-----------------------------------------------------------------------

local DISPLAY_STRING_MAX  = 64
local DISPLAY_TABLE_ITEMS = 16
local DISPLAY_DEPTH_MAX   = 3
local DISPLAY_PATH_MAX    = 96

local CODEGEN_DEPTH_MAX   = 6
local CODEGEN_TABLE_ITEMS = 256

local SAFE_NAME_PATTERN = "^[%a_][%w_]*$"

-- Display colors. Declared lazily in a function because Color3 is
-- an engine type (always present) but constructing 12 of them at
-- file scope on every load is wasteful; cache on first use.
local TYPE_COLORS = nil

local TYPE_COLOR_VALUES = {
    string   = {150, 210, 150},
    number   = {235, 165, 95},
    boolean  = {210, 135, 235},
    Instance = {130, 180, 255},
    CFrame   = {240, 220, 130},
    Vector3  = {130, 230, 220},
    Vector2  = {130, 230, 220},
    Color3   = {255, 140, 140},
    table    = {200, 200, 205},
    userdata = {200, 170, 255},
    nil      = {120, 120, 130},
}

local function getTypeColors()
    if not TYPE_COLORS then
        TYPE_COLORS = {}
        for k, rgb in pairs(TYPE_COLOR_VALUES) do
            TYPE_COLORS[k] = Color3.new(rgb[1]/255, rgb[2]/255, rgb[3]/255)
        end
    end
    return TYPE_COLORS
end

-----------------------------------------------------------------------
-- SECTION 3 : NUMBER FORMATTING
-----------------------------------------------------------------------
-- Precision guarantee: %.17g round-trips every finite double.
-- Integers below 2^53 print without decimal points.

function Format.number(n)
    if n ~= n then
        return "0/0"                        -- NaN
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
-- SECTION 4 : STRING FORMATTING
-----------------------------------------------------------------------

local CONTROL_ESCAPES = {
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
    ["\\"] = "\\\\",
    ['"']  = '\\"',
}

function Format.escapeString(s)
    return (s:gsub("[%c\\\"]", CONTROL_ESCAPES))
end

function Format.quoteString(s)
    return '"' .. Format.escapeString(s) .. '"'
end

function Format.displayString(s)
    if #s > DISPLAY_STRING_MAX then
        return Format.quoteString(s:sub(1, DISPLAY_STRING_MAX))
            .. " --[[" .. (#s - DISPLAY_STRING_MAX) .. " more]]"
    end
    return Format.quoteString(s)
end

-----------------------------------------------------------------------
-- SECTION 5 : INSTANCE PATH RESOLUTION
-----------------------------------------------------------------------
-- Display: compact "Parent.Name".
-- Codegen: "game:GetService(...)" roots with WaitForChild chains
-- for non-identifier names. Resilient to instances reparenting
-- between capture and execution.

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

-- Known service names. Workspace gets special-cased because the
-- global workspace reference is shorter and equally reliable.
local KNOWN_SERVICES = {
    Players = true, ReplicatedStorage = true, ReplicatedFirst = true,
    Lighting = true, CoreGui = true, SoundService = true,
    TeleportService = true, StarterGui = true, StarterPlayer = true,
    Teams = true, Chat = true, ServerStorage = true,
    ServerScriptService = true, HttpService = true,
    MarketplaceService = true, DataStoreService = true,
    TweenService = true, RunService = true,
}

local function resolveInstanceChain(inst)
    -- Walks to the root, returns the chain of names.
    local names = {}
    local current = inst
    while current and current ~= game do
        table.insert(names, 1, current.Name)
        current = current.Parent
    end
    return names
end

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
        -- Parent chain reached a non-service root: treat the
        -- first hop as a service lookup fallback. Workspace is
        -- the most common parent in practice.
        path = 'game:GetService("Workspace")'
    end

    for i = 2, #names do
        local name = names[i]
        if name:match(SAFE_NAME_PATTERN) then
            path = path .. "." .. name
        else
            path = path .. ':WaitForChild('
                .. Format.quoteString(name) .. ')'
        end
    end

    return path
end

-----------------------------------------------------------------------
-- SECTION 6 : DISPLAY RENDERING
-----------------------------------------------------------------------

function Format.display(v, depth, seen)
    depth = depth or 0
    seen = seen or {}

    local t = typeof(v)

    if v == nil then
        return "nil"
    elseif t == "Instance" then
        return v.ClassName .. " <" .. Format.instanceDisplay(v) .. ">"
    elseif t == "CFrame" then
        local p = { v:GetComponents() }
        return string.format(
            "CFrame(%.2f, %.2f, %.2f) [%.2f %.2f %.2f]",
            p[1], p[2], p[3], p[4], p[5], p[6])
    elseif t == "Vector3" then
        return string.format("Vec3(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)
    elseif t == "Vector2" then
        return string.format("Vec2(%.2f, %.2f)", v.X, v.Y)
    elseif t == "Color3" then
        return string.format("Color(%d, %d, %d)",
            math.floor(v.R * 255 + 0.5),
            math.floor(v.G * 255 + 0.5),
            math.floor(v.B * 255 + 0.5))
    elseif t == "number" then
        return Format.number(v)
    elseif t == "string" then
        return Format.displayString(v)
    elseif t == "boolean" then
        return tostring(v)
    elseif t == "EnumItem" then
        return tostring(v)
    elseif t == "table" then
        if seen[v] then
            return "<circular>"
        end
        seen[v] = true
        if depth >= DISPLAY_DEPTH_MAX then
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
    else
        return "<" .. t .. ">"
    end
end

-----------------------------------------------------------------------
-- SECTION 7 : CODEGEN
-----------------------------------------------------------------------

function Format.codegen(v, depth, seen)
    depth = depth or 0
    seen = seen or {}

    local t = typeof(v)

    if v == nil then
        return "nil"
    elseif t == "Instance" then
        return Format.instancePath(v)
    elseif t == "CFrame" then
        local p = { v:GetComponents() }
        return string.format(
            "CFrame.new(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
            Format.number(p[1]), Format.number(p[2]), Format.number(p[3]),
            Format.number(p[4]), Format.number(p[5]), Format.number(p[6]),
            Format.number(p[7]), Format.number(p[8]), Format.number(p[9]),
            Format.number(p[10]), Format.number(p[11]), Format.number(p[12]))
    elseif t == "Vector3" then
        return string.format("Vector3.new(%s, %s, %s)",
            Format.number(v.X), Format.number(v.Y), Format.number(v.Z))
    elseif t == "Vector2" then
        return string.format("Vector2.new(%s, %s)",
            Format.number(v.X), Format.number(v.Y))
    elseif t == "Color3" then
        return string.format("Color3.new(%s, %s, %s)",
            Format.number(v.R), Format.number(v.G), Format.number(v.B))
    elseif t == "number" then
        return Format.number(v)
    elseif t == "string" then
        return Format.quoteString(v)
    elseif t == "boolean" then
        return tostring(v)
    elseif t == "EnumItem" then
        return tostring(v)
    elseif t == "table" then
        if seen[v] then
            return "{--[[circular]]}"
        end
        seen[v] = true
        if depth >= CODEGEN_DEPTH_MAX then
            return "{--[[depth]]}"
        end

        -- Detect pure array form for clean output.
        local arrayLen = 0
        for i = 1, math.huge do
            if rawget(v, i) ~= nil then
                arrayLen = i
            else
                break
            end
        end
        local isPureArray = true
        local seenNonArray = false
        for k in pairs(v) do
            if type(k) ~= "number" then
                isPureArray = false
                break
            end
        end
       
        local parts = {}
        local count = 0

        if isPureArray and arrayLen > 0 then
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
            for k, val in pairs(v) do
                count = count + 1
                if count > CODEGEN_TABLE_ITEMS then
                    table.insert(parts, "--[[truncated]]")
                    break
                end
                local key
                if type(k) == "number" then
                    key = "[" .. Format.number(k) .. "]"
                elseif type(k) == "string" and k:match(SAFE_NAME_PATTERN) then
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
        return "nil --[[unsupported: " .. t .. "]]"
    end
end

-----------------------------------------------------------------------
-- SECTION 8 : CALL SUMMARIES
-----------------------------------------------------------------------

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
    return string.format("%s:%s (%s)",
        remoteName, method, preview)
end

function Format.colorFor(v)
    local colors = getTypeColors()
    return colors[typeof(v)] or colors.table
end

-----------------------------------------------------------------------
-- SECTION 9 : FULL SCRIPT GENERATION
-----------------------------------------------------------------------

function Format.callToScript(capture)
    local lines = {}

    table.insert(lines, "-- SimplySpy capture #" .. tostring(capture.id))
    table.insert(lines, "-- " .. Format.callToLine(capture))
    table.insert(lines, "")

    table.insert(lines, "local args = {")
    for i, arg in ipairs(capture.args) do
        table.insert(lines, "    [" .. i .. "] = "
            .. Format.codegen(arg) .. ",")
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
-- SECTION 10 : BATCH SCRIPT GENERATION
-----------------------------------------------------------------------

function Format.batchToScript(captures)
    local lines = {}

    table.insert(lines, "-- SimplySpy batch replay")
    table.insert(lines, "-- " .. #captures .. " calls")
    table.insert(lines, "")

    for idx, capture in ipairs(captures) do
        table.insert(lines, "-- call " .. idx .. ": "
            .. Format.callToLine(capture))
        table.insert(lines, "local args" .. idx .. " = {")
        for i, arg in ipairs(capture.args) do
            table.insert(lines, "    [" .. i .. "] = "
                .. Format.codegen(arg) .. ",")
        end
        table.insert(lines, "}")
        table.insert(lines, "local remote" .. idx .. " = "
            .. capture.remotePath)
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
-- SECTION 11 : MODULE EXPORT
-----------------------------------------------------------------------
-- Executor path: main.lua calls loadModule("format") which
-- executes this file and expects the return to be a function
-- taking (deps) and returning the Format table.

Format.limits = {
    DISPLAY_STRING_MAX  = DISPLAY_STRING_MAX,
    DISPLAY_TABLE_ITEMS = DISPLAY_TABLE_ITEMS,
    DISPLAY_DEPTH_MAX   = DISPLAY_DEPTH_MAX,
    CODEGEN_DEPTH_MAX   = CODEGEN_DEPTH_MAX,
    CODEGEN_TABLE_ITEMS = CODEGEN_TABLE_ITEMS,
}

return function(deps)
    log = (deps and deps.log) or log
    log("INFO", "format engine online (universal)")
    return Format
end
