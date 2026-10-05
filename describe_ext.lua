-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.3 — ARG FIDELITY PACK
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  Extends describe() with 10 missing Roblox types:
--  UDim, UDim2, TweenInfo, PhysicalProperties, NumberRange,
--  NumberSequence, ColorSequence, Rect, DateTime, Ray
--  + optional instance parent-chain depth
--  Layers cleanly: wraps existing SS2.describe, never replaces
-- ════════════════════════════════════════════════════════════

print("[SS2-fid] extending arg fidelity...")

local SS2 = getgenv().SS2
if not SS2 or not SS2.describe then
    warn("[SS2-fid] core must load first")
    return
end

SS2.describeDeep = false -- set true for instance parent chains

local realDescribe = SS2.describe

local extDescribe = function(v, depth)
    depth = depth or 0
    local t = typeof(v)

    if t == "UDim" then
        return ("UDim(%.2f, %d)"):format(v.Scale, v.Offset)
    elseif t == "UDim2" then
        return ("UDim2(%.2f,%d, %.2f,%d)"):format(
            v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset)
    elseif t == "TweenInfo" then
        return ("TweenInfo(%gs, %s, %s, %d, %s, %gs)"):format(
            v.Time, tostring(v.EasingStyle), tostring(v.EasingDirection),
            v.RepeatCount, tostring(v.Reverses), v.DelayTime)
    elseif t == "PhysicalProperties" then
        return ("PhysProp(%.2f,%.2f,%.2f,%.2f)"):format(
            v.Density, v.Friction, v.Elasticity, v.FrictionWeight)
    elseif t == "NumberRange" then
        return ("NumRange(%g, %g)"):format(v.Min, v.Max)
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
    elseif t == "Rect" then
        return ("Rect(%.0f,%.0f,%.0f,%.0f)"):format(
            v.Min.X, v.Min.Y, v.Max.X, v.Max.Y)
    elseif t == "DateTime" then
        return ("DT(%s)"):format(v:ToIsoDate())
    elseif t == "Ray" then
        local o, d = v.Origin, v.Direction
        return ("Ray(%.0f,%.0f,%.0f -> %.1f,%.1f,%.1f)"):format(
            o.X, o.Y, o.Z, d.X, d.Y, d.Z)
    elseif t == "Instance" and SS2.describeDeep then
        -- parent chain: A:B:C (2 levels up)
        local chain = v.Name
        pcall(function()
            local p = v.Parent
            local n = 0
            while p and n < 2 do
                chain = p.Name .. ":" .. chain
                p = p.Parent
                n = n + 1
            end
        end)
        return v.ClassName .. "@" .. chain
    else
        -- fall through to the original describer for everything else
        return realDescribe(v, depth)
    end
end

SS2.describe = extDescribe

print("[SS2-fid] 10 type branches + instance chains LIVE")
print("[fid] toggle deep instances: SS2.describeDeep = true")
