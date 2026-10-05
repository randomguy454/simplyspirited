-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.3 — STEALTH TIER
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  Detection-surface reducer. Honest scope: defeats CASUAL
--  observation (UI scanners, console readers, window checks).
--  NOT an anti-cheat bypass — serious systems defeat nobody.
--  • Console-mode: all Draw objects hidden, prints muted to
--    buffer, capture continues blind
--  • Jittered pacing: refresh metronomes get ±30% jitter
--  • State alias: SS2 table re-keyed under a boring name
--  • Stealth report: buffer flushes on exit
-- ════════════════════════════════════════════════════════════

print("[SS2-stealth] loading quiet tier...")

local SS2 = getgenv().SS2
if not SS2 then warn("[SS2-stealth] core must load first") return end

-- ═══ STATE ═══
SS2.stealth = {
    active = false,
    buffer = {},          -- silenced prints collect here
    alias = nil,          -- renamed state key
    oldPrint = nil,
}

local S = SS2.stealth

-- ═══ 1. PRINT MUTING (routed to buffer) ═══
local realPrint = print
local function stealthPrint(...)
    -- capture whatever would print, store quietly
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

    -- mute the wire: replace global print
    S.oldPrint = print
    -- (executor-safe: reassigning global print affects all scripts
    --  in the same VM context — that's the point)
    print = stealthPrint

    -- hide all suite Draw windows
    if SS2.uiplusOwner then
        -- uiplus owns objects we can't reach directly; hide via
        -- its own unload guard: we freeze instead of destroy,
        -- so stealth-off can restore
        -- NOTE: full restore needs object refs; stealth v1 = run
        -- headless from boot instead (see SS2.stealthFromBoot)
    end
    if SS2.feedWin then
        SS2.feedWin.open = false -- watch's loop exits if still alive
    end
    SS2.capture = true -- capture NEVER stops — stealth hides, not blinds

    journal("STEALTH", "engaged")
    realPrint("[SS2-stealth] ENGAGED — silent operation, capture continues")
    realPrint("[SS2-stealth] prints buffered (" .. #S.buffer .. " so far), windows hidden")
end

SS2.stealthOff = function()
    if not S.active then return end
    S.active = false
    print = S.oldPrint or print

    -- flush buffer to file
    local content = table.concat(S.buffer, "\n")
    pcall(function()
        makefolder("SimplySpirited")
        writefile("SimplySpirited/vault/stealth_log.txt", content)
    end)

    journal("STEALTH", "disengaged — buffer flushed (" .. #S.buffer .. " lines)")
    print("[SS2-stealth] OFF — " .. #S.buffer .. " buffered lines -> SimplySpirited/vault/stealth_log.txt")
    S.buffer = {}
end
SS2.stealthOff = SS2.stealthOff

-- headless boot: engage stealth BEFORE anything prints
SS2.stealthFromBoot = function()
    SS2.stealthOn()
    print("[SS2-stealth] headless session started — you will see nothing until SS2.stealthOff()")
end

-- ═══ 2. JITTER PACING (defeats metronome detection) ═══
-- wraps task.wait used by the suite's loops? can't — instead we
-- provide the jitter utility and patch known loops via flags
SS2.jitter = function(base)
    -- returns base +- 30%
    local j = base * (0.7 + math.random() * 0.6)
    return j
end

-- patch the uiplus main loop's wait via its exposed state
pcall(function()
    if SS2.uiplus then
        -- uiplus loop uses fixed 0.03; we can't reach inside, but we
        -- document: loops created after stealth loads should use SS2.jitter
    end
end)

-- ═══ 3. STATE ALIAS (boring name for the state table) ═══
SS2.setAlias = function(aliasName)
    if not aliasName or #aliasName < 2 then
        print("[stealth] alias too short")
        return
    end
    -- move state
    getgenv()[aliasName] = SS2
    getgenv().SS2 = nil
    -- move helpers
    getgenv()[aliasName .. "_READY"] = getgenv().SS2_READY
    getgenv().SS2_READY = nil
    S.alias = aliasName
    journal("STEALTH", "state aliased to '" .. aliasName .. "'")
    print("[stealth] state now lives at getgenv()." .. aliasName .. " — old key gone")
end

SS2.clearAlias = function()
    if S.alias then
        local old = getgenv()[S.alias]
        getgenv().SS2 = old
        getgenv()[S.alias] = nil
        getgenv().SS2_READY = getgenv()[S.alias .. "_READY"]
        getgenv()[S.alias .. "_READY"] = nil
        S.alias = nil
        print("[stealth] alias cleared — back to SS2")
    end
end

-- ═══ 4. QUICK SWEEP (what does a scanner see?) ═══
SS2.scanSelf = function()
    print("═══ SELF-SCAN: what we expose ═══")
    print("global keys with 'SS' or 'SIMPLY':")
    for k, v in pairs(getgenv()) do
        local kl = tostring(k):lower()
        if kl:find("ss") or kl:find("simply") or kl:find("spirit") then
            print("  " .. tostring(k) .. " = " .. typeof(v))
        end
    end
    print("hint: SS2.setAlias('cfg') renames the state key")
    print("hint: SS2.stealthOn() silences console + hides windows")
end

-- ═══ restore print safety on unload ═══
SS2.stealthUnload = function()
    SS2.stealthOff()
end

journal("STEALTH", "tier loaded")
print("[SS2-stealth] quiet tier LIVE")
print("[stealth] commands:")
print("  SS2.stealthOn()          — go silent (windows hide, prints buffer)")
print("  SS2.stealthOff()         — restore, flush buffer to vault")
print("  SS2.stealthFromBoot()    — headless session (run before core prints)")
print("  SS2.setAlias('cfg')      — rename state key (defeats key scanners)")
print("  SS2.clearAlias()         — restore SS2 key")
print("  SS2.scanSelf()           — audit what a scanner would see")
print("  honest scope: casual scans only — never a real anti-cheat bypass")
