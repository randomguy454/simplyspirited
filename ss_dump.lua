--[[
    simplyspirited v4.6 — game dump
    SHADOWMILESC / computerizedcarrier2

    the diagnostic tier. where export.lua files the session's
    intelligence, the dump answers the question underneath it:
    is capture COMPLETE, and if not, what are we missing?

    artifacts:
    - audit: discovered vs hooked vs silent, with age ranking
      and delta-vs-last-audit (what changed since the last check)
    - coverage map: which remotes came from boot-scan vs rescan
      vs descendant-added (the capture pipeline's own health)
    - per-remote dossiers: priority-ordered, active first, full
      call histories with caller maps inline

    v4.6 scope change: master session intel moved to export.lua's
    vault (it does it better now). the dump specializes in
    diagnostics the vault doesn't cover.
]]

print("[SS2-dump] v4.6 loading...")

local SS2 = getgenv().SS2
if not SS2 then
    warn("ss2-dump: core.lua must load first")
    return
end

local Players = game:GetService("Players")
local P = Players.LocalPlayer

SS2.dumpState = SS2.dumpState or {
    lastAudit = nil,       -- {discovered, hooked, silent, silentList}
    auditsRun = 0,
}

local function ensureDump()
    pcall(function() makefolder("SimplySpirited") end)
    pcall(function() makefolder("SimplySpirited/dump") end)
end
SS2.dumpEnsure = ensureDump

-- ════════════════════════════════════════════════════════════
-- rescan-recovery awareness: which remotes did the core's
-- adaptive rescan recover? cross-reference journal entries
-- (the journal is the honest source — core logs recoveries)
-- ════════════════════════════════════════════════════════════
local function getRescanRecovered()
    local recovered = {}
    for _, e in ipairs(SS2.journal) do
        if e.tag == "RESCAN" and e.text:find("recovered") then
            recovered[#recovered + 1] = e
        end
    end
    return recovered
end

-- ════════════════════════════════════════════════════════════
-- THE AUDIT — completeness diagnostic
-- ════════════════════════════════════════════════════════════
function SS2.dumpAudit()
    local out = {
        "╔══════════════════════════════════════╗",
        "  DISCOVERY AUDIT",
        "  game: " .. SS2.game .. " | " .. os.date(),
        "╚══════════════════════════════════════╝",
        "",
    }

    local total, hooked, silent, metaOnly = 0, 0, 0, 0
    local silentList = {}   -- {path, firstSeen, ageRank}
    for r, prof in pairs(SS2.remotes) do
        total = total + 1
        if prof.hooked then hooked = hooked + 1 end
        if (prof.metaCaught or 0) > 0 then metaOnly = metaOnly + 1 end
        if prof.calls == 0 then
            silent = silent + 1
            silentList[#silentList + 1] = prof.path
        end
    end

    out[#out + 1] = ("discovered: %d | hooked: %d | never fired: %d | net-caught calls: %d"):format(
        total, hooked, silent, metaOnly)
    out[#out + 1] = ""

    -- delta vs last audit (what changed)
    local prev = SS2.dumpState.lastAudit
    if prev then
        out[#out + 1] = "── SINCE LAST AUDIT ──"
        local dTotal = total - prev.discovered
        local dSilent = silent - prev.silent
        if dTotal ~= 0 then
            out[#out + 1] = ("  discovered: %+d (%d → %d)"):format(dTotal, prev.discovered, total)
        else
            out[#out + 1] = ("  discovered: unchanged (%d)"):format(total)
        end
        if dSilent ~= 0 then
            out[#out + 1] = ("  silent:     %+d (%d → %d)"):format(dSilent, prev.silent, silent)
            if dSilent < 0 then
                out[#out + 1] = "  (silent remotes went ACTIVE — check the feed for what woke them)"
            end
        else
            out[#out + 1] = ("  silent:     unchanged (%d)"):format(silent)
        end
    else
        out[#out + 1] = "  (first audit — baseline recorded)"
    end
    out[#out + 1] = ""

    -- silent remotes, oldest-first (candidates for manual triggering)
    if silent > 0 then
        out[#out + 1] = ("SILENT REMOTES (%d) — oldest discovery first:"):format(silent)
        local sorted = {}
        for r, prof in pairs(SS2.remotes) do
            if prof.calls == 0 then
                sorted[#sorted + 1] = { path = prof.path, seen = prof.firstSeen }
            end
        end
        table.sort(sorted, function(a, b) return a.seen < b.seen end)
        for k, e in ipairs(sorted) do
            out[#out + 1] = ("  [%s] %s"):format(e.seen, e.path)
        end
        out[#out + 1] = ""
        out[#out + 1] = "(silent = discovered but never fired. these are candidates for"
        out[#out + 1] = " manual triggering — find what wakes them in the game's UI)"
    end

    -- rescan recoveries
    local recovered = getRescanRecovered()
    if #recovered > 0 then
        out[#out + 1] = ""
        out[#out + 1] = ("RESCAN RECOVERIES: %d events"):format(#recovered)
        for _, e in ipairs(recovered) do
            out[#out + 1] = ("  [%s] %s"):format(e.t, e.text)
        end
    end

    -- store for delta
    SS2.dumpState.lastAudit = {
        discovered = total, hooked = hooked, silent = silent,
        silentList = silentList,
    }
    SS2.dumpState.auditsRun = SS2.dumpState.auditsRun + 1

    local text = table.concat(out, "\n")
    ensureDump()
    writefile("SimplySpirited/dump/audit.txt", text)
    print("[dump] audit #" .. SS2.dumpState.auditsRun .. " — " .. total .. " discovered, "
        .. hooked .. " hooked, " .. silent .. " silent -> dump/audit.txt")
    return text
end
SS2.dumpAudit = SS2.dumpAudit

-- ════════════════════════════════════════════════════════════
-- COVERAGE MAP — where did each remote come from?
-- boot-scan vs rescan vs descendant-added. the capture
-- pipeline's own health report.
-- ════════════════════════════════════════════════════════════
function SS2.dumpCoverage()
    -- honest limitation: core doesn't tag provenance per remote yet.
    -- we approximate: remotes present at boot = boot-scan; journal
    -- RESCAN entries tell us how many came later but not which.
    -- v4.7 recommendation: core tags prof.source = "boot"/"rescan"/"added"
    local out = {
        "CAPTURE COVERAGE MAP — " .. os.date(),
        "",
        "NOTE: per-remote provenance arrives in v4.7 (core will tag",
        "prof.source at hook time). current coverage by numbers:",
        "",
    }
    local total, hooked = 0, 0
    for r, prof in pairs(SS2.remotes) do
        total = total + 1
        if prof.hooked then hooked = hooked + 1 end
    end
    out[#out + 1] = ("discovered: %d | inbound-hooked: %d | net coverage: %s"):format(
        total, hooked, tostring(SS2.metaHooked))
    out[#out + 1] = ("outbound path: namecall net (%s) — total by architecture"):format(
        tostring(SS2.metaHooked))
    out[#out + 1] = ("inbound path: OnClientEvent — hooked %d/%d"):format(hooked, total)
    out[#out + 1] = ""
    out[#out + 1] = "rescan recoveries this session: "
    local rec = getRescanRecovered()
    out[#out + 1] = "  " .. #rec .. " events (see audit for details)"
    print(table.concat(out, "\n"))
    return table.concat(out, "\n")
end
SS2.dumpCoverage = SS2.dumpCoverage

-- ════════════════════════════════════════════════════════════
-- PER-REMOTE DOSSIERS (priority: active first, richest data)
-- ════════════════════════════════════════════════════════════
function SS2.dumpPerRemote(maxDossiers)
    maxDossiers = maxDossiers or 50
    task.spawn(function()
        ensureDump()
        -- priority: active remotes (calls > 0) first, by call count
        local active, silent = {}, {}
        for r, prof in pairs(SS2.remotes) do
            if prof.calls > 0 then
                active[#active + 1] = { r = r, prof = prof }
            else
                silent[#silent + 1] = { r = r, prof = prof }
            end
        end
        table.sort(active, function(a, b) return a.prof.calls > b.prof.calls end)

        local n = 0
        -- active remotes: full dossiers
        for _, e in ipairs(active) do
            if n >= maxDossiers then break end
            local r, prof = e.r, e.prof
            local clean = r:GetFullName():gsub("[^%w_]", "_"):sub(1, 100)
            local out = {}
            out[#out + 1] = "REMOTE DOSSIER: " .. (prof.path or "?")
            out[#out + 1] = ("class: %s | calls: %d (out %d / in %d) | net-caught: %s"):format(
                prof.class, prof.calls, prof.out, prof.inn, tostring(prof.metaCaught or 0))
            out[#out + 1] = ("first: %s | last: %s"):format(prof.firstSeen, prof.lastSeen)
            out[#out + 1] = ""

            -- callers inline
            if prof.callers and next(prof.callers) then
                out[#out + 1] = "CALLERS:"
                local cs = {}
                for c, cn in pairs(prof.callers) do cs[#cs + 1] = { c = c, n = cn } end
                table.sort(cs, function(a, b) return a.n > b.n end)
                for _, ce in ipairs(cs) do
                    out[#out + 1] = ("  [%dx] %s"):format(ce.n, ce.c)
                end
                out[#out + 1] = ""
            end

            -- signatures
            local sigs = {}
            for sig, cnt in pairs(prof.sigs) do
                sigs[#sigs + 1] = { s = sig, c = cnt }
            end
            table.sort(sigs, function(a, b) return a.c > b.c end)
            out[#out + 1] = ("SIGNATURES (%d unique):"):format(#sigs)
            for k, se in ipairs(sigs) do
                out[#out + 1] = ("  [%dx] %s"):format(se.c, se.s)
            end
            out[#out + 1] = ""

            -- full call history
            local calls = {}
            for _, rec in ipairs(SS2.log) do
                if rec.remote == r then
                    calls[#calls + 1] = ("#%d [%s] %s"):format(
                        rec.id, rec.dir, table.concat(rec.args, " | "))
                end
            end
            out[#out + 1] = ("FULL CALL HISTORY (%d in buffer):"):format(#calls)
            for _, c in ipairs(calls) do
                out[#out + 1] = "  " .. c
            end

            writefile("SimplySpirited/dump/remote_" .. clean .. ".txt",
                table.concat(out, "\n"))
            n = n + 1
            task.wait()
        end

        -- silent remotes: one summary file (they have no calls to dossier)
        if #silent > 0 then
            local out = { "SILENT REMOTES (" .. #silent .. ") — discovered, never fired", "" }
            for _, e in ipairs(silent) do
                out[#out + 1] = ("[%s] %s"):format(e.prof.firstSeen, e.prof.path or "?")
            end
            writefile("SimplySpirited/dump/silent_remotes.txt", table.concat(out, "\n"))
        end

        print(("[SS2-dump] %d active dossiers + %d silent listed -> dump/"):format(
            n, #silent))
        if SS2.journalAdd then
            SS2.journalAdd("DUMP", ("per-remote: %d dossiers, %d silent"):format(n, #silent))
        end
    end)
end
SS2.dumpPerRemote = SS2.dumpPerRemote

print("[SS2-dump] v4.6 LIVE — audit deltas, coverage map, priority dossiers")
print("[dump] SS2.dumpAudit()      — completeness diagnostic (delta-aware)")
print("[dump] SS2.dumpCoverage()   — pipeline health map")
print("[dump] SS2.dumpPerRemote()  — priority dossiers (50 default)")
