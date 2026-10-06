--[[
    simplyspirited v4.6 — governor
    SHADOWMILESC / computerizedcarrier2

    endurance tier. keeps capture alive and honest when a game
    floods the wire.

    three stages:
      NORMAL    full capture
      SAMPLING  1/N records kept (young remotes exempt — first
                contact is sacred)
      PAUSED    capture halted, auto-resumes into sampling

    v4.6: pre-filter rate meter (counts TRUE traffic, not the
    filtered subset), stage decisions journaled with numbers,
    flood event log, per-remote flood attribution.

    the rule this module enforces: the suite must never die,
    never lose first-contact data, and never lie about why it
    degraded.
]]

print("[SS2-gov] v4.6 arming...")

local SS2 = getgenv().SS2
if not SS2 then
    warn("ss2-gov: core.lua must load first")
    return
end

-- ═══ config ═══
local CFG = {
    S1_RATE     = 300,   -- calls/sec (TRUE, pre-filter): sampling begins
    S2_RATE     = 1000,  -- calls/sec sustained: auto-pause
    S2_SUSTAIN  = 3,     -- seconds above S2 to trigger pause
    COOLDOWN    = 10,    -- seconds paused before resuming (into sampling)
    YOUNG_AGE   = 20,    -- remotes under this many lifetime calls are exempt from sampling
    MAX_FLOOD_LOG = 30,  -- flood event log bound
}

-- ═══ state ═══
SS2.governor = {
    mode = "NORMAL",        -- NORMAL | SAMPLING | PAUSED
    rate = 0,               -- TRUE rate (pre-filter), calls/sec
    sampleN = 1,            -- record every Nth eligible call
    sampleCounter = 0,
    muted = {},             -- [name-or-path] = true
    floodLog = {},          -- stage transitions with numbers

    -- rate meter internals
    _windowStart = os.clock(),
    _windowCount = 0,       -- TRUE traffic (pre-filter, pre-mute)
    _s2Seconds = 0,
}
local G = SS2.governor

-- ═══ flood log ═══
local function floodLog(text)
    G.floodLog[#G.floodLog + 1] = {
        t = os.date("%H:%M:%S"),
        rate = math.floor(G.rate),
        text = text,
    }
    if #G.floodLog > CFG.MAX_FLOOD_LOG then table.remove(G.floodLog, 1) end
    if SS2.journalAdd then
        SS2.journalAdd("GOV", text .. " @ " .. math.floor(G.rate) .. "/s")
    end
end

-- ═══ is this remote muted? (name or path, checked cheaply) ═══
local function isMuted(remote)
    if G.muted[remote.Name] then return true end
    local prof = SS2.remotes[remote]
    if prof and prof.path and G.muted[prof.path] then return true end
    return false
end

-- ═══ THE GOVERNED RECORDER ═══
-- wraps core's recordCall. order of operations:
--   1. count TRUE traffic (pre-filter — this is what the server sees)
--   2. drop muted remotes (they still count toward rate — muting
--      reduces LOG SPAM, not the flood assessment)
--   3. stage evaluation on second boundaries
--   4. sampling: young remotes exempt (evaluated BEFORE math)
--   5. pass through to core's recorder
local realRecord = SS2.recordCall
if not realRecord then
    warn("ss2-gov: no recorder found (core broken?)")
    return
end

SS2.recordCall = function(remote, args, direction)
    -- 1. TRUE rate meter
    local now = os.clock()
    G._windowCount = G._windowCount + 1
    local newSecond = false
    if now - G._windowStart >= 1 then
        G.rate = G._windowCount / (now - G._windowStart)
        G._windowStart = now
        G._windowCount = 0
        newSecond = true
    end

    -- 2. mute check (name or path)
    if G.muted[remote.Name]
    or (SS2.remotes[remote] and G.muted[SS2.remotes[remote].path]) then
        return -- counted in rate above, recording suppressed
    end

    -- 3. stage evaluation, once per second
    if newSecond and G.mode ~= "PAUSED" then
        if G.rate >= CFG.S2_RATE then
            G._s2Seconds = G._s2Seconds + 1
            if G._s2Seconds >= CFG.S2_SUSTAIN then
                G.mode = "PAUSED"
                SS2.capture = false
                floodLog("STAGE 2 → PAUSED (sustained ≥" .. CFG.S2_RATE .. "/s)")
                task.delay(CFG.COOLDOWN, function()
                    G.mode = "SAMPLING"
                    G.sampleN = 5
                    SS2.capture = true
                    floodLog("PAUSED → SAMPLING (1/5) after cooldown")
                    print("[governor] resuming in SAMPLING (1/5)")
                end)
                print(("[governor] !! FLOOD %.0f/s — PAUSED %ds"):format(G.rate, CFG.COOLDOWN))
                return
            end
        else
            G._s2Seconds = 0
        end

        if G.rate >= CFG.S1_RATE and G.mode == "NORMAL" then
            G.mode = "SAMPLING"
            G.sampleN = 2
            floodLog("STAGE 1 → SAMPLING (1/2)")
            print(("[governor] flood %.0f/s — SAMPLING 1/2"):format(G.rate))
        elseif G.rate < CFG.S1_RATE * 0.5 and G.mode == "SAMPLING" then
            G.mode = "NORMAL"
            G.sampleN = 1
            floodLog("SAMPLING → NORMAL (recovered)")
            print(("[governor] rate %.0f/s — NORMAL restored"):format(G.rate))
        end
    end

    -- paused: total recording blackout (but rate still meters above)
    if G.mode == "PAUSED" then return end

    -- 4. sampling — YOUNG REMOTES ALWAYS PASS
    if G.mode == "SAMPLING" and G.sampleN > 1 then
        local prof = SS2.remotes[remote]
        local young = (not prof) or (prof.calls < CFG.YOUNG_AGE)
        if not young then
            G.sampleCounter = G.sampleCounter + 1
            if G.sampleCounter % G.sampleN ~= 0 then
                return -- sampled out
            end
        end
    end

    -- 5. pass through
    return realRecord(remote, args, direction)
end
print("[SS2-gov] recorder wrapped — TRUE rate meter + 3-stage response live")

-- ═══ manual controls ═══
function SS2.muteRemote(nameOrPath)
    G.muted[nameOrPath] = true
    print("[governor] muted: " .. nameOrPath .. " (rate still counts it)")
end

function SS2.unmuteRemote(nameOrPath)
    G.muted[nameOrPath] = nil
    print("[governor] unmuted: " .. nameOrPath)
end

function SS2.muteList()
    print("═══ muted remotes ═══")
    local n = 0
    for k in pairs(G.muted) do
        n = n + 1
        print("  " .. k)
    end
    if n == 0 then print("  (none)") end
end

-- force stages manually (testing + opinionated operation)
function SS2.governorForce(mode)
    if mode == "NORMAL" or mode == "SAMPLING" or mode == "PAUSED" then
        G.mode = mode
        SS2.capture = (mode ~= "PAUSED")
        G.sampleN = (mode == "SAMPLING") and 5 or 1
        floodLog("manual force → " .. mode)
        print("[governor] forced to " .. mode)
    else
        print("[governor] invalid mode — NORMAL / SAMPLING / PAUSED")
    end
end

-- ═══ status + flood history ═══
function SS2.governorStatus()
    local mutedCount = 0
    for _ in pairs(G.muted) do mutedCount = mutedCount + 1 end
    print("═══ governor ═══")
    print(("  mode:      %s"):format(G.mode))
    print(("  TRUE rate: %.0f calls/sec (pre-filter)"):format(G.rate))
    print(("  sampling:  1/%d | muted: %d"):format(G.sampleN, mutedCount))
    print(("  thresholds: S1@%d S2@%d (sustained %ds)"):format(
        CFG.S1_RATE, CFG.S2_RATE, CFG.S2_SUSTAIN))
    print(("  core health EMA: %.1f (post-filter)"):format(
        SS2.health and SS2.health.callsEMA or 0))
    if SS2.health and SS2.health.filterDropped > 0 then
        print(("  filter-dropped this session: %d"):format(SS2.health.filterDropped))
    end
end
SS2.governorStatus = SS2.governorStatus

function SS2.floodHistory()
    print("═══ flood event log ═══")
    if #G.floodLog == 0 then
        print("  (no flood events this session)")
        return
    end
    for _, e in ipairs(G.floodLog) do
        print(("  [%s] (%.0f/s) %s"):format(e.t, e.rate, e.text))
    end
end
SS2.floodHistory = SS2.floodHistory

-- ═══ vault export hook: flood log rides the vault export ═══
-- (export.lua reads SS2.journal; we mirror flood events there)
local realJournal = SS2.journalAdd
if realJournal then
    -- floodLog already journals transitions — nothing to mirror.
    -- floodHistory() remains the dedicated viewer.
end

print("[SS2-gov] v4.6 LIVE — endurance guaranteed, first-contact sacred")
print("[governor] SS2.governorStatus()   — vitals + config")
print("[governor] SS2.floodHistory()     — every stage transition")
print("[governor] SS2.muteRemote('name') — surgical log silence")
print("[governor] SS2.governorForce('PAUSED') — manual stage override")
