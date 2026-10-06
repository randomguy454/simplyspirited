--=====================================================================
--  PROJECT   : SimplySpy
--  FILE      : format.lua (FORMAT ENGINE)
--  VERSION   : 0.3.1
--  PURPOSE   : Value rendering and executable codegen. Zero
--              executor globals; runs on any environment.
--  LICENSE   : MIT
--=====================================================================

local Format = {}
local log = function() end

local DISPLAY_STRING_MAX  = 64
local DISPLAY_TABLE_ITEMS = 16
local DISPLAY_DEPTH_MAX   = 3
local DISPLAY_PATH_MAX    = 96
local CODEGEN_DEPTH_MAX   = 6
local CODEGEN_TABLE_ITEMS = 256
local SAFE_NAME = "^[%a_][%w_]*$"

------------------------------------------------------------------
-- NUMBERS
------------------------------------------------------------------

function Format.number(n)
    if n ~= n then return "0/0" end
    if n == math.huge then return "math.huge" end
    if n == -math.huge then return "-math.huge" end
    if n == math.floor(n) and math.abs(n) < 2 ^ 53 then
        return string.format("%d", n)
    end
    return string.format("%.17g", n)
end

------------------------------------------------------------------
-- STRINGS
------------------------------------------------------------------

local ESCAPES = {
    ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
    ["\\"] = "\\\\", ['"'] = '\\"',
}

function Format.escapeString(s)
    return (s:gsub("[%c\\\"]", ESCAPES))
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

------------------------------------------------------------------
-- INSTANCE PATHS
------------------------------------------------------------------

local SERVICES = {
    Players = true, ReplicatedStorage = true, ReplicatedFirst = true,
    Lighting = true, CoreGui = true, SoundService = true,
    TeleportService = true, StarterGui = true, StarterPlayer = true,
    Teams = true, Chat = true, ServerStorage = true,
    ServerScriptService = true, HttpService = true,
    MarketplaceService = true, TweenService = true, RunService = true,
}

function Format.instanceDisplay(inst)
    if not inst then return "?" end
    local name = inst.Name or "?"
    local parent = inst.Parent
    if parent and parent.Name ~= "" and parent ~= game then
        local combined = parent.Name .. "." .. name
        if #combined <= DISPLAY_PATH_MAX then return combined end
    end
    return name
end

function Format.instancePath(inst)
    if not inst then return "nil" end
    if inst == game then return "game" end

    local names = {}
    local cur = inst
    while cur and cur ~= game do
        table.insert(names, 1, cur.Name)
        cur = cur.Parent
    end
    if #names == 0 then return "game" end

    local first = names[1]
    local path
    if first == "Workspace" then
        path = "workspace"
    elseif SERVICES[first] then
        path = 'game:GetService("' .. first .. '")'
    else
        path = 'game:GetService("Workspace")'
    end

    for i = 2, #names do
        local nm = names[i]
        if nm:match(SAFE_NAME) then
            path = path .. "." .. nm
        else
            path = path .. ':WaitForChild(' .. Format.quoteString(nm) .. ')'
        end
    end
    return path
end

------------------------------------------------------------------
-- DISPLAY
------------------------------------------------------------------

function Format.display(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local t = typeof(v)

    if v == nil then return "nil"
    elseif t == "Instance" then
        return v.ClassName .. " <" .. Format.instanceDisplay(v) .. ">"
    elseif t == "CFrame" then
        local p = { v:GetComponents() }
        return string.format("CFrame(%.2f, %.2f, %.2f) [%.2f %.2f %.2f]",
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
    elseif t == "number" then return Format.number(v)
    elseif t == "string" then return Format.displayString(v)
    elseif t == "boolean" then return tostring(v)
    elseif t == "EnumItem" then return tostring(v)
    elseif t == "table" then
        if seen[v] then return "<circular>" end
        seen[v] = true
        if depth >= DISPLAY_DEPTH_MAX then return "{...}" end
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
            elseif type(k) == "string" and k:match(SAFE_NAME) then
                key = k
            else
                key = Format.quoteString(tostring(k))
            end
            table.insert(parts, key .. " = "
                .. Format.display(val, depth + 1, seen))
        end
        seen[v] = nil
        if #parts == 0 then return "{}" end
        return "{ " .. table.concat(parts, ", ") .. " }"
    else
        return "<" .. t .. ">"
    end
end

------------------------------------------------------------------
-- CODEGEN
------------------------------------------------------------------

function Format.codegen(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local t = typeof(v)

    if v == nil then return "nil"
    elseif t == "Instance" then return Format.instancePath(v)
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
    elseif t == "number" then return Format.number(v)
    elseif t == "string" then return Format.quoteString(v)
    elseif t == "boolean" then return tostring(v)
    elseif t == "EnumItem" then return tostring(v)
    elseif t == "table" then
        if seen[v] then return "{--[[circular]]}" end
        seen[v] = true
        if depth >= CODEGEN_DEPTH_MAX then return "{--[[depth]]}" end

        -- Detect array form.
        local arrayLen = 0
        for i = 1, math.huge do
            if v[i] ~= nil then arrayLen = i else break end
        end
        local pureArray = true
        for k in pairs(v) do
            if type(k) ~= "number" then pureArray = false break end
        end

        local parts = {}
        local count = 0
        if pureArray and arrayLen > 0 then
            for i = 1, arrayLen do
                count = count + 1
                if count > CODEGEN_TABLE_ITEMS then
                    table.insert(parts, "--[[truncated]]")
                    break
                end
                table.insert(parts, Format.codegen(v[i], depth + 1, seen))
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
                elseif type(k) == "string" and k:match(SAFE_NAME) then
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

------------------------------------------------------------------
-- CALL SUMMARIES AND SCRIPT GENERATION
------------------------------------------------------------------

function Format.callToLine(capture)
    local remoteName = capture.remoteName or "?"
    local method = capture.method or "?"
    local preview = (capture.preview and capture.preview ~= "")
        and capture.preview
        or ((capture.argCount or 0) .. " args")
    return string.format("%s:%s (%s)", remoteName, method, preview)
end

function Format.callToScript(capture)
    local lines = {}
    table.insert(lines, "-- SimplySpy capture #" .. tostring(capture.id))
    table.insert(lines, "-- " .. Format.callToLine(capture))
    table.insert(lines, "")
    table.insert(lines, "local args = {")
    for i, arg in ipairs(capture.args) do
        table.insert(lines, "    [" .. i .. "] = " .. Format.codegen(arg) .. ",")
    end
    table.insert(lines, "}")
    table.insert(lines, "")
    table.insert(lines, "local remote = " .. capture.remotePath)
    if capture.method == "InvokeServer" then
        table.insert(lines, "remote:InvokeServer(unpack(args))")
    else
        table.insert(lines, "remote:FireServer(unpack(args))")
    end
    return table.concat(lines, "\n")
end

Format.limits = {
    DISPLAY_STRING_MAX = DISPLAY_STRING_MAX,
    DISPLAY_TABLE_ITEMS = DISPLAY_TABLE_ITEMS,
    DISPLAY_DEPTH_MAX = DISPLAY_DEPTH_MAX,
    CODEGEN_DEPTH_MAX = CODEGEN_DEPTH_MAX,
    CODEGEN_TABLE_ITEMS = CODEGEN_TABLE_ITEMS,
}

return function(deps)
    if deps and deps.log then log = deps.log end
    log("INFO", "format engine online")
    return Format
end
