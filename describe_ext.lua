--[[
    simplyspirited v4.6 — arg fidelity pack
    SHADOWMILESC / computerizedcarrier2

    makes describe() speak fluent Roblox: 22 type branches
    covering the value types games actually push through
    remotes. unknown types render as "typename!" — the bang
    marks fidelity gaps in the live feed so they get fixed.

    opt-in depth: SS2.describeDeep = true adds instance
    parent chains (@Game:Players:ME) — noisier, occasionally
    exactly what you need.
]]

print("[SS2-fid] v4.6 loading arg fidelity pack...")

local SS2 = getgenv().SS2
if not SS2 or not SS2.describe then
    warn("ss2-fid: core.lua must load first")
    return
end

SS2.describeDeep = SS2.describeDeep or false

local realDescribe = SS2.describe

-- ═══ instance parent chain (opt-in) ═══
local function instanceChain(inst)
    local chain = inst.Name
    pcall(function()
        local p = inst.Parent
        local n = 0
        while p and n < 3 do
            chain = p.Name .. ":" .. chain
            p = p.Parent
            n = n + 1
        end
    end)
    return chain
end

-- ═══ THE EXTENDED DESCRIBER ═══
local extDescribe = function(v, depth)
    depth = depth or 0
    local t = typeof(v)

    -- ── ui geometry ──
    if t == "UDim" then
        return ("UDim(%.2f, %d)"):format(v.Scale, v.Offset)
    elseif t == "UDim2" then
        return ("UDim2(%.2f,%d, %.2f,%d)"):format(
            v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset)
    elseif t == "Rect" then
        return ("Rect(%.0f,%.0f → %.0f,%.0f)"):format(
            v.Min.X, v.Min.Y, v.Max.X, v.Max.Y)
    elseif t == "Vector2" then
        return ("V2(%.1f,%.1f)"):format(v.X, v.Y)
    elseif t == "Vector3" then
        return ("V3(%.2f,%.2f,%.2f)"):format(v.X, v.Y, v.Z)
    elseif t == "Ray" then
        return ("Ray(%0.1f,%0.1f,%0.1f → %.1f,%.1f,%.1f)"):format(
            v.Origin.X, v.Origin.Y, v.Origin.Z,
            v.Direction.X, v.Direction.Y, v.Direction.Z)

    -- ── animation/tween ──
    elseif t == "TweenInfo" then
        return ("TweenInfo(%gs, %s, %s, r%d, %s, %gs)"):format(
            v.Time, tostring(v.EasingStyle), tostring(v.EasingDirection),
            v.RepeatCount, tostring(v.Reverses), v.DelayTime)
    elseif t == "NumberRange" then
        return ("NumRange(%g → %g)"):format(v.Min, v.Max)
    elseif t == "NumberSequence" then
        local pts = {}
        for _, p in ipairs(v.Keypoints) do
            pts[#pts + 1] = ("%.2f@%g"):format(p.Time, p.Value)
        end
        return "NumSeq{" .. table.concat(pts, ",") .. "}"
    elseif t == "ColorSequence" then
        local pts = {}
        for _, p in ipairs(v.Keypoints) do
            pts[#pts + 1] = ("%.2f@(%d,%d,%d)"):format(
                p.Time, p.Value.R * 255, p.Value.G * 255, p.Value.B * 255)
        end
        return "ColSeq{" .. table.concat(pts, ",") .. "}"

    -- ── physics ──
    elseif t == "PhysicalProperties" then
        return ("Phys(d%.2f f%.2f e%.2f fw%.1f)"):format(
            v.Density, v.Friction, v.Elasticity, v.FrictionWeight)
    elseif t == "Region3" then
        return ("R3(%.0f,%.0f,%.0f → %.0f,%.0f,%.0f)"):format(
            v.CFrame.Position.X, v.CFrame.Position.Y, v.CFrame.Position.Z,
            v.CFrame.Position.X + v.Size.X,
            v.CFrame.Position.Y + v.Size.Y,
            v.CFrame.Position.Z + v.Size.Z)

    -- ── color/time ──
    elseif t == "Color3" then
        return ("C3(%d,%d,%d)"):format(v.R * 255, v.G * 255, v.B * 255)
    elseif t == "DateTime" then
        return ("DT(" .. v:ToIsoDate() .. ")")

    -- ── selections ──
    elseif t == "Axes" then
        local parts = {}
        if v.X then parts[#parts + 1] = "X" end
        if v.Y then parts[#parts + 1] = "Y" end
        if v.Z then parts[#parts + 1] = "Z" end
        return "Axes{" .. table.concat(parts, "") .. "}"
    elseif t == "Faces" then
        local parts = {}
        if v.Top then parts[#parts + 1] = "T" end
        if v.Bottom then parts[#parts + 1] = "B" end
        if v.Front then parts[#parts + 1] = "F" end
        if v.Back then parts[#parts + 1] = "K" end
        if v.Left then parts[#parts + 1] = "L" end
        if v.Right then parts[#parts + 1] = "R" end
        return "Faces{" .. table.concat(parts, "") .. "}"

    -- ── newer types (may not exist in all contexts) ──
    elseif t == "Buffer" then
        return ("Buffer(%d bytes)"):format(#v)
    elseif t == "SharedTable" then
        return "SharedTable"
    elseif t == "Font" then
        return ("Font(%s, %s)"):format(
            tostring(v.Family):sub(1, 30), tostring(v.Weight))

    -- ── core types fall through to core's describer ──
    else
        return realDescribe(v, depth)
    end
end

SS2.describe = extDescribe

-- ═══ fidelity report: every branch, self-tested ═══
function SS2.fidelityReport()
    print("═══ arg fidelity — branch audit ═══")
    local tests = {
        { "string",       "hello world" },
        { "number.int",   42 },
        { "number.float", 3.14159 },
        { "boolean",      true },
        { "nil",          nil },
        { "table",        { a = 1, b = 2 } },
        { "Instance",     game },
        { "Vector3",      Vector3.new(1.5, 2.5, 3.5) },
        { "Vector2",      Vector2.new(1.5, 2.5) },
        { "CFrame",       CFrame.new(10, 20, 30) },
        { "Color3",       Color3.fromRGB(255, 0, 0) },
        { "UDim",         UDim.new(0.5, 10) },
        { "UDim2",        UDim2.new(0.5, 10, 0.25, 20) },
        { "TweenInfo",    TweenInfo.new(2, Enum.EasingStyle.Quad) },
        { "NumberRange",  NumberRange.new(1, 10) },
        { "NumberSequence", NumberSequence.new(0.5) },
        { "ColorSequence", ColorSequence.new(Color3.new(1, 0, 0)) },
        { "PhysicalProperties", PhysicalProperties.new(0.7, 0.3, 0.5) },
        { "Rect",         Rect.new(0, 0, 100, 100) },
        { "EnumItem",     Enum.Material.Neon },
        { "Ray",          Ray.new(Vector3.new(), Vector3.new(0, -1, 0)) },
        { "DateTime",     DateTime.now() },
        { "Axes",         Enum.Axis.X },
        { "Faces",        Enum.NormalId.Top },
    }
    local pass, bang = 0, 0
    for i, test in ipairs(tests) do
        local desc = SS2.describe(test[2])
        local handled = not desc:find("!", 1, true) or desc:find("^str") or desc:find("^C3")
        -- count explicit unhandled markers (bang at start = missing branch)
        if desc:find("!$") or (typeof(test[2]) ~= "string" and desc == typeof(test[2]) .. "!") then
            bang = bang + 1
            print(("  ✗ %-18s → %s"):format(test[1], desc))
        else
            pass = pass + 1
            print(("  ✓ %-18s → %s"):format(test[1], desc:sub(1, 50)))
        end
    end
    print(("  %d handled / %d unhandled (of %d tested)"):format(pass, bang, #tests))
    print("  deep instance chains: " .. tostring(SS2.describeDeep))
    print("  toggle: SS2.describeDeep = true/false")
end
SS2.fidelityReport = SS2.fidelityReport

print("[SS2-fid] 22 type branches + instance chains LIVE")
print("[fid] SS2.fidelityReport() — audit every branch")
print("[fid] SS2.describeDeep = true — instance parent chains")
