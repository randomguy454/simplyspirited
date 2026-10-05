-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.7 — FULL GAME DUMP
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  • MASTER DUMP: every remote, every call, everything -> one txt
--  • PER-REMOTE FILES: individual dossier for each remote
--  • DISCOVERY AUDIT: lists remotes found vs hooked vs silent
--  Output: workspace/SimplySpirited/dump/
-- ════════════════════════════════════════════════════════════

print("[SS2-dump] loading full game dump...")

local SS2 = getgenv().SS2
if not SS2 then warn("[SS2-dump] core must load first") return end

local function ensureDump()
    pcall(function() makefolder("SimplySpirited") end)
    pcall(function() makefolder("SimplySpirited/dump") end)
end

-- ═══ DISCOVERY AUDIT: found vs hooked vs silent ═══
function SS2.dumpAudit()
    local out = {
        "SIMPLYSPIRITED — DISCOVERY AUDIT",
        "game: " .. SS2.game .. " | " .. os.date(),
        "═══════════════════════════════════",
    }
    local total, hooked, silent, metaOnly = 0, 0, 0, 0
    local silentList = {}
    for r, prof in pairs(SS2.remotes) do
        total = total + 1
        if prof.hooked then hooked = hooked + 1 end
        if prof.calls == 0 then
            silent = silent + 1
            silentList[#silentList + 1] = prof.path
        end
        if (prof.metaCaught or 0) > 0 then metaOnly = metaOnly + 1 end
    end
    out[#out + 1] = ("discovered: %d | hooked: %d | never fired: %d | net-caught: %d"):format(
        total, hooked, silent, metaOnly)
    out[#out + 1] = ""
    out[#out + 1] = "REMOTES DISCOVERED BUT NEVER FIRED (candidates for triggering):"
    for _, p in ipairs(silentList) do
        out[#out + 1] = "  " .. p
    end
    local txt = table.concat(out, "\n")
    ensureDump()
    writefile("SimplySpirited/dump/audit.txt", txt)
    print("[dump] audit saved — " .. total .. " remotes, " .. silent .. " silent")
    return txt
end
SS2.dumpAudit = SS2.dumpAudit

-- ═══ MASTER DUMP ═══
function SS2.dumpAll()
    task.spawn(function()
        ensureDump()
        local out = {}
        out[#out + 1] = "╔══════════════════════════════════════════╗"
        out[#out + 1] = "  SIMPLYSPIRITED v2.7 — FULL GAME DUMP"
        out[#out + 1] = "  game: " .. SS2.game
        out[#out + 1] = "  place: " .. SS2.placeId
        out[#out + 1] = "  date: " .. os.date()
        out[#out + 1] = "  operator: SHADOWMILESC (computerizedcarrier2)"
        out[#out + 1] = "╚══════════════════════════════════════════╝"
        out[#out + 1] = ""

        -- SECTION 1: every remote, complete profile
        out[#out + 1] = "══════════ SECTION 1: ALL REMOTES (" ..
            (function() local n = 0 for _ in pairs(SS2.remotes) do n = n + 1 end return n end)() .. ") ══════════"
        local ranked = {}
        for r, prof in pairs(SS2.remotes) do
            ranked[#ranked + 1] = { r = r, prof = prof }
        end
        table.sort(ranked, function(a, b) return a.prof.calls > b.prof.calls end)
        for _, e in ipairs(ranked) do
            local prof = e.prof
            out[#out + 1] = "──────────────────────────────────────"
            out[#out + 1] = ("REMOTE: %s (%s)"):format(e.r.Name, prof.class)
            out[#out + 1] = ("PATH:   %s"):format(prof.path)
            out[#out + 1] = ("CALLS:  %d (out %d / in %d) | hooked: %s | metaCaught: %s"):format(
                prof.calls, prof.out, prof.inn, tostring(prof.hooked), tostring(prof.metaCaught or 0))
            -- caller map
            if prof.callers and next(prof.callers) then
                out[#out + 1] = "  CALLERS:"
                local cs = {}
                for c, n in pairs(prof.callers) do cs[#cs + 1] = { c = c, n = n } end
                table.sort(cs, function(a, b) return a.n > b.n end)
                for _, ce in ipairs(cs) do
                    out[#out + 1] = ("    [%dx] %s"):format(ce.n, ce.c)
                end
            end
            -- signatures
            local sigs = {}
            for sig, cnt in pairs(prof.sigs) do
                sigs[#sigs + 1] = { s = sig, c = cnt }
            end
            table.sort(sigs, function(a, b) return a.c > b.c end)
            if #sigs > 0 then
                out[#out + 1] = "  SIGNATURES:"
                for k = 1, math.min(15, #sigs) do
                    out[#out + 1] = ("    [%dx] %s"):format(sigs[k].c, sigs[k].s)
                end
            end
        end

        -- SECTION 2: complete call log
        out[#out + 1] = ""
        out[#out + 1] = ("══════════ SECTION 2: COMPLETE CALL LOG (%d) ══════════"):format(#SS2.log)
        for _, rec in ipairs(SS2.log) do
            out[#out + 1] = ("#%d [%s] %s %s :: %s"):format(
                rec.id, rec.dir, rec.class, rec.name, table.concat(rec.args, " | "))
        end

        -- SECTION 3: values
        out[#out + 1] = ""
        out[#out + 1] = "══════════ SECTION 3: ALL TRACKED VALUES ══════════"
        for obj, v in pairs(SS2.values) do
            if obj.Parent then
                local p = obj.Name
                pcall(function() p = obj:GetFullName() end)
                out[#out + 1] = p .. " = " .. tostring(v)
            end
        end

        -- SECTION 4: journal
        out[#out + 1] = ""
        out[#out + 1] = ("══════════ SECTION 4: JOURNAL (%d) ══════════"):format(#SS2.journal)
        for _, e in ipairs(SS2.journal) do
            out[#out + 1] = ("[%s] %s: %s"):format(e.t, e.tag, e.text)
        end

        writefile("SimplySpirited/dump/master_dump.txt", table.concat(out, "\n"))
        print("[dump] master_dump.txt written — the complete confession")
    end)
end
SS2.dumpAll = SS2.dumpAll

-- ═══ PER-REMOTE DOSSIERS ═══
function SS2.dumpPerRemote()
    task.spawn(function()
        ensureDump()
        local n = 0
        for r, prof in pairs(SS2.remotes) do
            if prof.calls > 0 then
                local clean = r:GetFullName():gsub("[^%w_]", "_"):sub(1, 100)
                local out = {}
                out[#out + 1] = "REMOTE DOSSIER: " .. prof.path
                out[#out + 1] = ("class: %s | calls: %d (out %d / in %d)"):format(
                    prof.class, prof.calls, prof.out, prof.inn)
                out[#out + 1] = ""
                local calls = {}
                for _, rec in ipairs(SS2.log) do
                    if rec.remote == r then
                        calls[#calls + 1] = ("#%d [%s] %s"):format(
                            rec.id, rec.dir, table.concat(rec.args, " | "))
                    end
                end
                out[#out + 1] = "FULL CALL HISTORY (" .. #calls .. "):"
                for _, c in ipairs(calls) do out[#out + 1] = "  " .. c end
                writefile("SimplySpirited/dump/remote_" .. clean .. ".txt",
                    table.concat(out, "\n"))
                n = n + 1
                task.wait()
            end
        end
        print("[dump] " .. n .. " per-remote dossiers written")
    end)
end
SS2.dumpPerRemote = SS2.dumpPerRemote

print("[SS2-dump] FULL GAME DUMP LIVE")
print("[dump] SS2.dumpAudit()      — found vs hooked vs silent")
print("[dump] SS2.dumpAll()        — master dump (everything, one file)")
print("[dump] SS2.dumpPerRemote()  — individual dossier per remote")
