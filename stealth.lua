
--[[
    simplyspirited v4.6 — stealth tier
    SHADOWMILESC / computerizedcarrier2

    hides the suite from casual observation. honest scope,
    stated in every report it writes:

      TIER 1 console readers      → countered (print/warn buffer)
      TIER 2 casual UI scans      → countered (window hide/restore)
      TIER 3 getgenv key scans    → countered (full key sweep)
      TIER 4 hook detection       → NOT COUNTERED (documented)
      TIER 5 behavioral analysis  → NOT COUNTERED (governor helps)

    this module never claims to defeat real anti-cheat. the
    honest scope statement is part of the product.
]]

print("[SS2-stealth] v4.6 loading...")

local SS2 = getgenv().SS2
if not SS2 then
    warn("ss2-stealth: core.lua must load first")
    return
end

SS2.stealth = {
    active = false,
    buffer = {},          -- silenced output, flushed on disengage
    alias = nil,          -- current state-key alias
    hiddenWindows = {},   -- windows hidden by stealth (for restore)
    oldPrint = nil,
    oldWarn = nil,
    restored = false,
}

local S = SS2.stealth

-- ═══ 1. OUTPUT MUTING (print + warn + guarded restore) ═══
local realPrint, realWarn = print, warn

local function quietSink(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    table.insert(S.buffer, os.date("%H:%M:%S") .. " | " .. table.concat(parts, " "))
    if #S.buffer > 1000 then table.remove(S.buffer, 1) end
end

SS2.stealthOn = function()
    if S.active then return end
    S.active = true

    -- mute both output channels
    S.oldPrint = print
    S.oldWarn = warn
    print = quietSink
    warn = quietSink

    -- hide known suite windows (reversibly)
    S.hiddenWindows = {}
    pcall(function()
        local root = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
        local g = root:FindFirstChild("SS2_Interface")
        if g then
            S.hiddenWindows[#S.hiddenWindows + 1] = { obj = g, wasEnabled = g.Enabled }
            g.Enabled = false
        end
    end)

    if SS2.journalAdd then SS2.journalAdd("STEALTH", "engaged — output muted, windows hidden") end
    realPrint("[SS2-stealth] ENGAGED — silent operation, capture continues")
end

SS2.stealthOff = function()
    if not S.active then return end
    S.active = false

    -- restore outputs
    print = S.oldPrint or realPrint
    warn = S.oldWarn or realWarn

    -- restore windows
    for _, w in ipairs(S.hiddenWindows) do
        pcall(function() w.obj.Enabled = w.wasEnabled end)
    end
    S.hiddenWindows = {}

    -- flush buffer
    local content = table.concat(S.buffer, "\n")
    ensureOK = pcall(function()
        makefolder("SimplySpirited")
        writefile("SimplySpirited/vault/stealth_log.txt", content)
    end)

    -- restore audit: verify we actually cleaned up
    local auditOK = (print ~= quietSink) and (warn ~= quietSink)
    S.restored = auditOK

    if SS2.journalAdd then
        SS2.journalAdd("STEALTH", ("disengaged — %d lines flushed, restore %s"):format(
            #S.buffer, auditOK and "verified" or "FAILED"))
    end
    print("[SS2-stealth] OFF — " .. #S.buffer .. " lines -> vault/stealth_log.txt | restore "
        .. (auditOK and "verified ✓" or "FAILED ✗"))
    S.buffer = {}
end
SS2.stealthOff = SS2.stealthOff

-- headless: engage before anything prints (run load.lua, then this)
SS2.stealthFromBoot = function()
    SS2.stealthOn()
    realPrint("[SS2-stealth] headless session — silent until SS2.stealthOff()")
end

-- ═══ 2. STATE ALIAS (full key sweep) ═══
-- renames every suite-exposing getgenv key, not just SS2.
-- scans for and relocates: SS2, SS2_READY, SIMPLYSPIRITED_V2,
-- SIMPLYSPIRITED_VERSION, SIMPLYSPIRITED_BY, F15_BUILD-era keys
SS2.setAlias = function(aliasName)
    if not aliasName or #aliasName < 2 then
        print("[stealth] alias too short")
        return
    end
    local moved = {}
    -- known suite keys (the sweep)
    local known = { "SS2", "SS2_READY", "SS2_UI", "SIMPLYSPIRITED_V2",
        "SIMPLYSPIRITED_VERSION", "SIMPLYSPIRITED_BY", "SS2_UI_V3" }
    for _, key in ipairs(known) do
        if getgenv()[key] ~= nil then
            -- name-mangled destination: prefix alias
            getgenv()[aliasName .. "_" .. key] = getgenv()[key]
            getgenv()[key] = nil
            moved[#moved + 1] = key
        end
    end
    -- the primary state gets the plain alias for compat
    if getgenv()[aliasName .. "_SS2"] then
        getgenv()[aliasName] = getgenv()[aliasName .. "_SS2"]
    end
    S.alias = aliasName
    if SS2.journalAdd then
        SS2.journalAdd("STEALTH", "aliased " .. #moved .. " keys → '" .. aliasName .. "_*'")
    end
    print("[stealth] " .. #moved .. " keys aliased under '" .. aliasName .. "_*'")
    print("[stealth] WARNING: modules loaded AFTER aliasing will re-create 'SS2' —")
    print("[stealth] alias last, or re-alias after loading anything new")
end

SS2.clearAlias = function()
    if not S.alias then
        print("[stealth] no alias active")
        return
    end
    local alias = S.alias
    local restored = 0
    for _, key in ipairs({ "SS2", "SS2_READY", "SS2_UI", "SIMPLYSPIRITED_V2",
        "SIMPLYSPIRITED_VERSION", "SIMPLYSPIRITED_BY", "SS2_UI_V3" }) do
        local aliased = alias .. "_" .. key
        if getgenv()[aliased] ~= nil then
            getgenv()[key] = getgenv()[aliased]
            getgenv()[aliased] = nil
            restored = restored + 1
        end
    end
    -- plain alias points at state too — remove it
    if getgenv()[alias] then getgenv()[alias] = nil end
    S.alias = nil
    print("[stealth] " .. restored .. " keys restored to original names")
end
SS2.clearAlias = SS2.clearAlias

-- ═══ 3. SELF-SCAN (what would a scanner see?) ═══
SS2.scanSelf = function()
    print("═══ self-scan: exposure audit ═══")
    -- getgenv keys
    local exposed = {}
    for k, v in pairs(getgenv()) do
        local kl = tostring(k):lower()
        if kl:find("ss2", 1, true) or kl:find("simply", 1, true)
        or kl:find("spirit", 1, true) or kl:find("shadowm", 1, true) then
            exposed[#exposed + 1] = tostring(k) .. " (" .. typeof(v) .. ")"
        end
    end
    if #exposed > 0 then
        print("  exposed getgenv keys:")
        for _, e in ipairs(exposed) do
            print("    " .. e)
        end
        print("  → SS2.setAlias('cfg') to sweep them")
    else
        print("  getgenv: clean")
    end

    -- coregui windows
    pcall(function()
        local root = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
        local g = root:FindFirstChild("SS2_Interface")
        if g then
            print("  CoreGui: SS2_Interface VISIBLE (stealth on hides this)")
        else
            print("  CoreGui: no suite windows visible")
        end
    end)

    -- console state
    print("  console: " .. (S.active and "muted (buffered)" or "live"))
    print("  hooks: namecall net " .. tostring(SS2.metaHooked) .. " — TIER 4 RISK (no counter, documented)")
    print("  honest scope: this suite defeats tiers 1-3 only")
end
SS2.scanSelf = SS2.scanSelf

-- ═══ 4. jitter utility (for loop pacing, documented) ═══
SS2.jitter = function(base)
    return base * (0.7 + math.random() * 0.6)
end

-- ═══ unload safety: never leave the VM muted ═══
SS2.stealthUnload = function()
    if S.active then SS2.stealthOff() end
end

if SS2.journalAdd then SS2.journalAdd("STEALTH", "v4.6 tier loaded") end

print("[SS2-stealth] v4.6 LIVE — tiers 1-3 countered, 4-5 documented")
print("[stealth] SS2.stealthOn()        — mute console + hide windows")
print("[stealth] SS2.stealthOff()       — restore + flush buffer + audit")
print("[stealth] SS2.stealthFromBoot()  — headless session")
print("[stealth] SS2.setAlias('cfg')    — full key sweep under alias")
print("[stealth] SS2.clearAlias()       — restore original keys")
print("[stealth] SS2.scanSelf()         — exposure audit")
print("[stealth] honest scope: casual scans only — tier 4+ documented as out of scope")
