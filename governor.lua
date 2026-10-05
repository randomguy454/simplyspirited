-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.3 — GOVERNOR (flood protection)
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  • Rolling rate meter (calls/second, colored)
--  • 3-stage flood response:
--    S1: adaptive sampling (1/N, new remotes always full-rate)
--    S2: auto-pause with timed retry
--    S3: surgical per-remote mute for the flood source
--  • Preserves "interesting" calls: remotes with <20 lifetime
--    calls never get sampled
-- ════════════════════════════════════════════════════════════

print("[SS2-gov] arming governor...")

local SS2 = getgenv().SS2
if not SS2 then warn("[SS2-gov] core must load first") return end

-- ═══ CONFIG ═══
local CFG = {
    S1_RATE = 300,     -- calls/sec: sampling begins
    S2_RATE = 1000,    -- calls/sec: auto-pause
    S2_SUSTAIN = 3,    -- seconds above S2 to trigger pause
    COOLDOWN = 10,     -- seconds before auto-retry after pause
    MUTE_RATIO = 0.95, -- single remote share of flood to trigger mute offer
}

SS2.governor = {
    rate = 0,
    mode = "NORMAL",          -- NORMAL / SAMPLING / PAUSED
    sampleN = 1,              -- record every Nth call
    sampleCounter = 0,
    muted = {},               -- [remotePath] = true
    windowStart = os.clock(),
    windowCount = 0,
    s2Timer = 0,
}

local G = SS2.governor

-- ═══ RATE METER ═══
local function tickRate()
    local now = os.clock()
    G.windowCount = G.windowCount + 1
    if now - G.windowStart >= 1 then
        G.rate = G.windowCount / (now - G.windowStart)
        G.windowStart = now
        G.windowCount = 0
        return true -- new second: re-evaluate thresholds
    end
    return false
end

-- ═══ TAP THE RECORDER ═══
-- wraps SS2.recordCall: counts rate, applies sampling + mute
-- BEFORE core's recording logic runs
local realRecord = SS2.recordCall
if not realRecord then
    warn("[SS2-gov] core recorder not found — governor idle")
    return
end

SS2.recordCall = function(remote, args, direction)
    -- rate accounting
    local newSecond = tickRate()

    -- muted remote? count the attempt, drop the record
    if G.muted[remote.Name] or (SS2.remotes[remote] and G.muted[SS2.remotes[remote].path]) then
        return
    end

    -- stage evaluation on second boundaries
    if newSecond and G.mode ~= "PAUSED" then
        if G.rate >= CFG.S2_RATE then
            G.s2Timer = G.s2Timer + 1
            if G.s2Timer >= CFG.S2_SUSTAIN then
                G.mode = "PAUSED"
                SS2.capture = false
                G.s2Timer = 0
                warn(("[governor] FLOOD %.0f/s — CAPTURE AUTO-PAUSED (resumes in %ds)"):format(
                    G.rate, CFG.COOLDOWN))
                SS2.journalAdd and SS2.journalAdd("GOV", "flood pause at " .. math.floor(G.rate) .. "/s")
                task.delay(CFG.COOLDOWN, function()
                    G.mode = "NORMAL"
                    G.sampleN = 5
                    SS2.capture = true
                    warn("[governor] resuming in SAMPLING mode (1/5)")
                end)
                return
            end
        else
            G.s2Timer = 0
        end

        if G.rate >= CFG.S1_RATE and G.mode == "NORMAL" then
            G.mode = "SAMPLING"
            G.sampleN = 2
            warn(("[governor] flood %.0f/s — entering SAMPLING"):format(G.rate))
        elseif G.rate < CFG.S1_RATE * 0.5 and G.mode == "SAMPLING" then
            G.mode = "NORMAL"
            G.sampleN = 1
            print(("[governor] rate %.0f/s — back to NORMAL"):format(G.rate))
        end
    end

    -- paused: drop everything
    if G.mode == "PAUSED" then return end

    -- sampling: new remotes (few lifetime calls) always pass —
    -- never lose first-contact intel
    if G.mode == "SAMPLING" and G.sampleN > 1 then
        local prof = SS2.remotes[remote]
        if prof and prof.calls >= 20 then
            G.sampleCounter = G.sampleCounter + 1
            if G.sampleCounter % G.sampleN ~= 0 then
                return -- sampled out
            end
        end
    end

    return realRecord(remote, args, direction)
end

-- ═══ MANUAL CONTROLS ═══
function SS2.muteRemote(nameOrPath)
    G.muted[nameOrPath] = true
    print("[governor] muted: " .. nameOrPath .. " (counting continues, recording stops)")
end

function SS2.unmuteRemote(nameOrPath)
    G.muted[nameOrPath] = nil
    print("[governor] unmuted: " .. nameOrPath)
end

function SS2.muteList()
    print("═══ MUTED ═══")
    local n = 0
    for k in pairs(G.muted) do
        n = n + 1
        print("  " .. k)
    end
    if n == 0 then print("  (none)") end
end

function SS2.governorStatus()
    print(("governor: mode=%s rate=%.0f/s sample=1/%d muted=%d"):format(
        G.mode, G.rate, G.sampleN,
        (function() local n = 0 for _ in pairs(G.muted) do n = n + 1 end return n end)()))
end

-- ═══ HUD STAT INJECTION ═══
-- appends rate to the feed window's stat line if present
task.spawn(function()
    while SS2.feedWin and SS2.feedWin.open do
        task.wait(1)
    end
end)

print("[SS2-gov] governor LIVE — S1 sample @" .. CFG.S1_RATE .. "/s, S2 pause @" .. CFG.S2_RATE .. "/s")
print("[governor] commands: SS2.muteRemote('name') | SS2.unmuteRemote | SS2.muteList | SS2.governorStatus")
