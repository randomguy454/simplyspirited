-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.4 — GOVERNOR (flood protection)
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  • Rolling rate meter • 3-stage flood response
--  • Sampling never touches young remotes (<20 calls)
-- ════════════════════════════════════════════════════════════

print("[SS2-gov] arming governor...")

local SS2 = getgenv().SS2
if not SS2 then warn("[SS2-gov] core must load first") return end

local CFG = {
    S1_RATE = 300,
    S2_RATE = 1000,
    S2_SUSTAIN = 3,
    COOLDOWN = 10,
}

SS2.governor = {
    rate = 0,
    mode = "NORMAL",
    sampleN = 1,
    sampleCounter = 0,
    muted = {},
    windowStart = os.clock(),
    windowCount = 0,
    s2Timer = 0,
}

local G = SS2.governor

local function tickRate()
    local now = os.clock()
    G.windowCount = G.windowCount + 1
    if now - G.windowStart >= 1 then
        G.rate = G.windowCount / (now - G.windowStart)
        G.windowStart = now
        G.windowCount = 0
        return true
    end
    return false
end

local realRecord = SS2.recordCall
if not realRecord then
    warn("[SS2-gov] core recorder not found — governor idle")
    return
end

SS2.recordCall = function(remote, args, direction)
    local newSecond = tickRate()

    if G.muted[remote.Name] or (SS2.remotes[remote] and G.muted[SS2.remotes[remote].path]) then
        return
    end

    if newSecond and G.mode ~= "PAUSED" then
        if G.rate >= CFG.S2_RATE then
            G.s2Timer = G.s2Timer + 1
            if G.s2Timer >= CFG.S2_SUSTAIN then
                G.mode = "PAUSED"
                SS2.capture = false
                G.s2Timer = 0
                warn(("[governor] FLOOD %.0f/s — CAPTURE AUTO-PAUSED (resumes in %ds)"):format(
                    G.rate, CFG.COOLDOWN))
                if SS2.journalAdd then SS2.journalAdd("GOV", "flood pause at " .. math.floor(G.rate) .. "/s") end
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

    if G.mode == "PAUSED" then return end

    if G.mode == "SAMPLING" and G.sampleN > 1 then
        local prof = SS2.remotes[remote]
        if prof and prof.calls >= 20 then
            G.sampleCounter = G.sampleCounter + 1
            if G.sampleCounter % G.sampleN ~= 0 then
                return
            end
        end
    end

    return realRecord(remote, args, direction)
end

function SS2.muteRemote(nameOrPath)
    G.muted[nameOrPath] = true
    print("[governor] muted: " .. nameOrPath)
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

print("[SS2-gov] governor LIVE — S1 @" .. CFG.S1_RATE .. "/s, S2 @" .. CFG.S2_RATE .. "/s")
print("[governor] SS2.muteRemote / unmuteRemote / muteList / governorStatus")
