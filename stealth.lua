-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.4 — STEALTH TIER
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  Honest scope: defeats CASUAL observation only. Never a real
--  anti-cheat bypass. Print buffering, window hiding, state alias.
-- ════════════════════════════════════════════════════════════

print("[SS2-stealth] loading quiet tier...")

local SS2 = getgenv().SS2
if not SS2 then warn("[SS2-stealth] core must load first") return end

SS2.stealth = {
    active = false,
    buffer = {},
    alias = nil,
    oldPrint = nil,
}

local S = SS2.stealth

local realPrint = print
local function stealthPrint(...)
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

    S.oldPrint = print
    print = stealthPrint

    if SS2.feedWin then
        SS2.feedWin.open = false
    end
    SS2.capture = true

    if SS2.journalAdd then SS2.journalAdd("STEALTH", "engaged") end
    realPrint("[SS2-stealth] ENGAGED — silent operation, capture continues")
end

SS2.stealthOff = function()
    if not S.active then return end
    S.active = false
    print = S.oldPrint or print

    local content = table.concat(S.buffer, "\n")
    pcall(function()
        makefolder("SimplySpirited")
        writefile("SimplySpirited/vault/stealth_log.txt", content)
    end)

    if SS2.journalAdd then SS2.journalAdd("STEALTH", "disengaged — " .. #S.buffer .. " lines flushed") end
    print("[SS2-stealth] OFF — " .. #S.buffer .. " buffered lines -> vault/stealth_log.txt")
    S.buffer = {}
end
SS2.stealthOff = SS2.stealthOff

SS2.stealthFromBoot = function()
    SS2.stealthOn()
    realPrint("[SS2-stealth] headless session — nothing visible until SS2.stealthOff()")
end

SS2.jitter = function(base)
    return base * (0.7 + math.random() * 0.6)
end

SS2.setAlias = function(aliasName)
    if not aliasName or #aliasName < 2 then
        print("[stealth] alias too short")
        return
    end
    getgenv()[aliasName] = SS2
    getgenv().SS2 = nil
    getgenv()[aliasName .. "_READY"] = getgenv().SS2_READY
    getgenv().SS2_READY = nil
    S.alias = aliasName
    if SS2.journalAdd then SS2.journalAdd("STEALTH", "state aliased to '" .. aliasName .. "'") end
    print("[stealth] state now at getgenv()." .. aliasName)
end

SS2.clearAlias = function()
    if S.alias then
        getgenv().SS2 = getgenv()[S.alias]
        getgenv()[S.alias] = nil
        getgenv().SS2_READY = getgenv()[S.alias .. "_READY"]
        getgenv()[S.alias .. "_READY"] = nil
        S.alias = nil
        print("[stealth] alias cleared — back to SS2")
    end
end

SS2.scanSelf = function()
    print("═══ SELF-SCAN: exposure audit ═══")
    for k, v in pairs(getgenv()) do
        local kl = tostring(k):lower()
        if kl:find("ss") or kl:find("simply") or kl:find("spirit") then
            print("  " .. tostring(k) .. " = " .. typeof(v))
        end
    end
    print("hint: SS2.setAlias('cfg') + SS2.stealthOn() = minimal surface")
end

if SS2.journalAdd then SS2.journalAdd("STEALTH", "tier loaded") end

print("[SS2-stealth] quiet tier LIVE")
print("[stealth] SS2.stealthOn / stealthOff / stealthFromBoot / setAlias / clearAlias / scanSelf")
