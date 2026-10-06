--[[
    simplyspirited v4.7 — intel vault
    SHADOWMILESC / computerizedcarrier2

    GAME-SCOPED: exports land in
      SimplySpirited/<GameName>/vault/
    So NAT's intelligence never mixes with BABFT's.

    8 artifacts per export:
      1. master intel   2. raw call log   3. journal
      4. session summary  5. presets  6. values snapshot
      7. caller attribution  8. closure graph
    + versioned filenames, truncation hashes, history ledger,
      60s journal autosave, standalone manifest.
]]

print("[SS2-vault] v4.7 loading...")

local SS2 = getgenv().SS2
if not SS2 then
    warn("ss2-vault: core.lua must load first")
    return
end

local Players = game:GetService("Players")
local P = Players.LocalPlayer

-- ═══ game-scoped paths ═══
local function gf()
    return SS2.gameFolder and SS2.gameFolder() or "UnknownGame"
end

local function ensureVault()
    local folder = gf()
    pcall(function() makefolder("SimplySpirited") end)
    pcall(function() makefolder("SimplySpirited/" .. folder) end)
    pcall(function() makefolder("SimplySpirited/" .. folder .. "/vault") end)
end

SS2.vaultHistory = SS2.vaultHistory or {}

-- truncation detector
local function fingerprint(content)
    if type(content) ~= "string" then return "?" end
    local a = string.byte(content, 1) or 0
    local b = string.byte(content, -1) or 0
    return ("%d:%02x%02x"):format(#content, a, b)
end

local function stampName(base, ext)
    local d = os.date("*t")
    return ("%s_%s%02d%02d_%02d%02d%02d.%s"):format(
        base, d.year, d.month, d.day, d.hour, d.min, d.sec, ext)
end

local function header(title)
    return table.concat({
        "╔══════════════════════════════════════════╗",
        "  " .. title,
        "  game:    " .. SS2.game,
        "  place:   " .. SS2.placeId,
        "  job:     " .. SS2.jobId,
        "  date:    " .. os.date(),
        "  operator: SHADOWMILESC (computerizedcarrier2)",
        "  suite:   SIMPLYSPIRITED v" .. tostring(SS2.version),
        "╚══════════════════════════════════════════╝",
        "",
    }, "\n")
end

-- ═══ session summary ═══
function SS2.vaultSummary()
    local remoteCount, totalCalls = 0, 0
    for r, prof in pairs(SS2.remotes) do
        remoteCount = remoteCount + 1
        totalCalls = totalCalls + prof.calls
    end
    local valueCount = 0
    for _ in pairs(SS2.values) do valueCount = valueCount + 1 end
    local presetCount = 0
    for _ in pairs(SS2.presets or {}) do presetCount = presetCount + 1 end
    local siteCount = 0
    if SS2.callSites then
        for _ in pairs(SS2.callSites.sites or {}) do siteCount = siteCount + 1 end
    end

    local runtime = os.clock() - (SS2.startTime or os.clock())
    local mins = math.floor(runtime / 60)
    local secs = math.floor(runtime % 60)

    local lines = {
        "SESSION SUMMARY",
        "───────────────",
        ("runtime:            %dm %02ds"):format(mins, secs),
        ("remotes discovered: %d"):format(remoteCount),
        ("total calls seen:   %d"):format(totalCalls),
        ("calls in buffer:    %d"):format(#SS2.log),
        ("values tracked:     %d"):format(valueCount),
        ("presets saved:      %d"):format(presetCount),
        ("call sites mapped:  %d"):format(siteCount),
        ("journal entries:    %d"):format(#SS2.journal),
        ("capture health:     %.1f c/s smoothed | filter-dropped: %d"):format(
            SS2.health and SS2.health.callsEMA or 0,
            SS2.health and SS2.health.filterDropped or 0),
    }
    if SS2.decompDB then
        lines[#lines + 1] = ("constants mined:    %d"):format(SS2.decompDB.count or 0)
    end
    if SS2.closure then
        lines[#lines + 1] = ("closure autopsies:  %d"):format(SS2.closure.autopsies or 0)
    end
    lines[#lines + 1] = ("game folder:        SimplySpirited/%s/"):format(gf())
    lines[#lines + 1] = ""
    lines[#lines + 1] = "TOP 10 REMOTES BY ACTIVITY:"

    local ranked = {}
    for r, prof in pairs(SS2.remotes) do
        ranked[#ranked + 1] = { r = r, prof = prof }
    end
    table.sort(ranked, function(a, b) return a.prof.calls > b.prof.calls end)
    for k = 1, math.min(10, #ranked) do
        lines[#lines + 1] = ("  %3d. [%4d calls] %s %s"):format(
            k, ranked[k].prof.calls, ranked[k].prof.class, ranked[k].prof.path)
    end
    return table.concat(lines, "\n")
end
SS2.vaultSummary = SS2.vaultSummary

-- ═══ THE MASTER EXPORT — 8 ARTIFACTS ═══
function SS2.vaultExportAll()
    task.spawn(function()
        ensureVault()
        local written = {}

        local function emit(name, content)
            local ok = pcall(function()
                writefile("SimplySpirited/" .. gf() .. "/vault/" .. name, content)
            end)
            written[#written + 1] = {
                name = name, ok = ok,
                size = ok and #content or 0,
                hash = ok and fingerprint(content) or "—",
            }
            print(("[vault] %s %s (%s chars, %s)"):format(
                ok and "✓" or "✗", name,
                tostring(#content), ok and fingerprint(content) or "—"))
        end

        -- ── artifact 1: full intel (master) ──
        local out = {}
        out[#out + 1] = header("FULL INTELLIGENCE EXPORT")
        out[#out + 1] = SS2.vaultSummary()
        out[#out + 1] = ""

        out[#out + 1] = "══════ SECTION 1: REMOTE PROFILES ══════"
        local ranked = {}
        for r, prof in pairs(SS2.remotes) do
            ranked[#ranked + 1] = { r = r, prof = prof }
        end
        table.sort(ranked, function(a, b) return a.prof.calls > b.prof.calls end)
        for _, e in ipairs(ranked) do
            local prof = e.prof
            out[#out + 1] = "────────────────────────────────────"
            out[#out + 1] = ("REMOTE: %s (%s)"):format(e.r.Name, prof.class)
            out[#out + 1] = ("PATH:   %s"):format(prof.path)
            out[#out + 1] = ("CALLS:  %d (out %d / in %d) | %s -> %s"):format(
                prof.calls, prof.out, prof.inn, prof.firstSeen, prof.lastSeen)
            if (prof.metaCaught or 0) > 0 then
                out[#out + 1] = ("  meta-net caught: %d"):format(prof.metaCaught)
            end
            if prof.callers and next(prof.callers) then
                out[#out + 1] = "  CALLERS:"
                local cs = {}
                for c, n in pairs(prof.callers) do cs[#cs + 1] = { c = c, n = n } end
                table.sort(cs, function(a, b) return a.n > b.n end)
                for _, ce in ipairs(cs) do
                    out[#out + 1] = ("    [%dx] %s"):format(ce.n, ce.c)
                end
            end
            local sigs = {}
            for sig, cnt in pairs(prof.sigs) do
                sigs[#sigs + 1] = { s = sig, c = cnt }
            end
            table.sort(sigs, function(a, b) return a.c > b.c end)
            if #sigs > 0 then
                out[#out + 1] = "  SIGNATURES:"
                for k = 1, math.min(10, #sigs) do
                    out[#out + 1] = ("    [%dx] %s"):format(sigs[k].c, sigs[k].s)
                end
            end
        end

        out[#out + 1] = ""
        out[#out + 1] = ("══════ SECTION 2: CALL LOG (%d) ══════"):format(#SS2.log)
        for _, rec in ipairs(SS2.log) do
            out[#out + 1] = ("#%d [%s] %s %s :: %s"):format(
                rec.id, rec.dir, rec.class, rec.name, table.concat(rec.args, " | "))
        end

        out[#out + 1] = ""
        out[#out + 1] = "══════ SECTION 3: TRACKED VALUES ══════"
        for obj, v in pairs(SS2.values) do
            if obj.Parent then
                local path = obj.Name
                pcall(function()
                    path = obj:GetFullName():gsub("Players%." .. P.Name .. "%.", "ME.")
                end)
                out[#out + 1] = path .. " = " .. tostring(v)
            end
        end

        out[#out + 1] = ""
        local presetCount = 0
        for _ in pairs(SS2.presets or {}) do presetCount = presetCount + 1 end
        out[#out + 1] = ("══════ SECTION 4: PRESETS (%d) ══════"):format(presetCount)
        for name, p in pairs(SS2.presets or {}) do
            out[#out + 1] = ("PRESET: %s | %s %s | %s"):format(
                name, p.remoteClass or p.class, p.remoteName or p.remoteName, p.saved)
            out[#out + 1] = ("  path: %s"):format(p.remotePath or p.path or "?")
            out[#out + 1] = ("  args: %s"):format(table.concat(p.args, " | "))
        end

        out[#out + 1] = ""
        out[#out + 1] = ("══════ SECTION 5: JOURNAL (%d) ══════"):format(#SS2.journal)
        for _, e in ipairs(SS2.journal) do
            out[#out + 1] = ("[%s] %s: %s"):format(e.t, e.tag, e.text)
        end

        -- section 6: call sites
        if SS2.callSites and next(SS2.callSites.sites or {}) then
            out[#out + 1] = ""
            out[#out + 1] = "══════ SECTION 6: CALL SITES ══════"
            local sorted = {}
            for key, site in pairs(SS2.callSites.sites) do
                sorted[#sorted + 1] = { key = key, s = site }
            end
            table.sort(sorted, function(a, b) return a.s.count > b.s.count end)
            for _, e in ipairs(sorted) do
                out[#out + 1] = ("[%6dx] [%s] %s"):format(e.s.count, e.s.kind, e.key)
                for rn, rc in pairs(e.s.remotes) do
                    out[#out + 1] = ("         → %s (%d)"):format(rn, rc)
                end
            end
        end

        -- section 7: mined constants DB
        if SS2.decompDB and next(SS2.decompDB.constants or {}) then
            out[#out + 1] = ""
            out[#out + 1] = ("══════ SECTION 7: MINED CONSTANTS DB (%d unique) ══════"):format(
                SS2.decompDB.count or 0)
            local sorted = {}
            for c, e in pairs(SS2.decompDB.constants) do
                sorted[#sorted + 1] = { s = c, n = e.count }
            end
            table.sort(sorted, function(a, b) return a.n > b.n end)
            for k = 1, math.min(100, #sorted) do
                out[#out + 1] = ("  [%4dx] %s"):format(sorted[k].n, sorted[k].s:sub(1, 120))
            end
        end

        local master = table.concat(out, "\n")
        local masterName = stampName("intel_v" .. tostring(SS2.version):gsub("%.", ""), "txt")
        emit(masterName, master)

        -- ── artifact 2: raw machine-readable log ──
        local raw = {}
        for _, rec in ipairs(SS2.log) do
            raw[#raw + 1] = table.concat({
                "id=" .. rec.id, "dir=" .. rec.dir,
                "class=" .. rec.class, "name=" .. rec.name,
                "path=" .. rec.path, "nargs=" .. #(rec.raw or {}),
                "args=" .. table.concat(rec.args, "~|~"),
            }, "\t")
        end
        emit(stampName("calls_raw", "txt"), table.concat(raw, "\n"))

        -- ── artifact 3: journal ──
        local jr = {}
        for _, e in ipairs(SS2.journal) do
            jr[#jr + 1] = ("[%s] %s: %s"):format(e.t, e.tag, e.text)
        end
        emit(stampName("journal", "txt"), table.concat(jr, "\n"))

        -- ── artifact 4: session summary ──
        emit(stampName("summary", "txt"),
            header("SESSION SUMMARY") .. "\n" .. SS2.vaultSummary())

        -- ── artifact 5: presets (portable) ──
        local pl = { "SIMPLYSPIRITED PRESET LIBRARY — " .. os.date(), "" }
        for pname, p in pairs(SS2.presets or {}) do
            pl[#pl + 1] = ("PRESET: %s"):format(pname)
            pl[#pl + 1] = ("  remote: %s (%s)"):format(p.remoteName or "?", p.remoteClass or "?")
            pl[#pl + 1] = ("  path:   %s"):format(p.remotePath or "?")
            pl[#pl + 1] = ("  args:   %s"):format(table.concat(p.args, " | "))
            pl[#pl + 1] = ""
        end
        emit(stampName("presets", "txt"), table.concat(pl, "\n"))

        -- ── artifact 6: values snapshot ──
        local vs = { "VALUE SNAPSHOT — " .. os.date(), "" }
        for obj, v in pairs(SS2.values) do
            if obj.Parent then
                local path = obj.Name
                pcall(function()
                    path = obj:GetFullName():gsub("Players%." .. P.Name .. "%.", "ME.")
                end)
                vs[#vs + 1] = path .. " = " .. tostring(v)
            end
        end
        emit(stampName("values", "txt"), table.concat(vs, "\n"))

        -- ── artifact 7: caller attribution ──
        if SS2.callSites and next(SS2.callSites.sites or {}) then
            local ca = { "CALLER ATTRIBUTION — " .. os.date(), "" }
            local sorted = {}
            for key, site in pairs(SS2.callSites.sites) do
                sorted[#sorted + 1] = { key = key, s = site }
            end
            table.sort(sorted, function(a, b) return a.s.count > b.s.count end)
            for _, e in ipairs(sorted) do
                ca[#ca + 1] = ("[%6dx] [%s] %s"):format(e.s.count, e.s.kind, e.key)
                for rn, rc in pairs(e.s.remotes) do
                    ca[#ca + 1] = ("       → %s (%d)"):format(rn, rc)
                end
            end
            emit(stampName("callers", "txt"), table.concat(ca, "\n"))
        end

        -- ── artifact 8: closure graph ──
        if SS2.closure and (SS2.closure.autopsies or 0) > 0 then
            local cg = {
                "CLOSURE GRAPH — " .. os.date(),
                ("autopsies: %d | nodes visited: %d"):format(
                    SS2.closure.autopsies, SS2.closure.nodesVisited),
                "",
            }
            local found = 0
            for _, rec in ipairs(SS2.log) do
                for i, rawf in ipairs(rec.raw or {}) do
                    if type(rawf) == "function" then
                        found = found + 1
                        cg[#cg + 1] = ("── call #%d %s arg[%d] ──"):format(rec.id, rec.name, i)
                        if SS2.inspectClosure then
                            local rep = SS2.inspectClosure(rawf, 0)
                            if type(rep) == "string" then cg[#cg + 1] = rep end
                        end
                        if found > 100 then break end
                    end
                end
                if found > 100 then break end
            end
            cg[#cg + 1] = ""
            cg[#cg + 1] = "functions exported: " .. found
            emit(stampName("closure_graph", "txt"), table.concat(cg, "\n"))
        end

        -- ── manifest with hashes ──
        local man = {
            "VAULT EXPORT MANIFEST",
            "game: " .. SS2.game .. " | folder: " .. gf(),
            "date: " .. os.date(),
            "hash: length:firstlast-byte (truncation detector)",
            "────────────────────────────────",
        }
        for _, w in ipairs(written) do
            man[#man + 1] = ("[%s] %-38s %9d chars  %s"):format(
                w.ok and "OK " or "ERR", w.name, w.size, w.hash)
        end
        emit("_manifest.txt", table.concat(man, "\n"))

        -- ── history ledger ──
        local okCount = 0
        for _, w in ipairs(written) do
            if w.ok then okCount = okCount + 1 end
        end
        table.insert(SS2.vaultHistory, {
            time = os.date("%H:%M:%S"),
            files = #written,
            ok = okCount,
            master = masterName,
            masterSize = #master,
        })

        print("[vault] EXPORT COMPLETE — " .. okCount .. "/" .. #written .. " artifacts")
        print("[vault] folder: SimplySpirited/" .. gf() .. "/vault/")
        print("[vault] latest master: " .. masterName)
        print("[vault] SS2.vaultHistoryList() for the ledger")
    end)
end
SS2.vaultExportAll = SS2.vaultExportAll
SS2.exportAll = SS2.vaultExportAll

-- ═══ export history ═══
function SS2.vaultHistoryList()
    print("═══ export history ═══")
    if #SS2.vaultHistory == 0 then
        print("  (no exports this session)")
        return
    end
    for i, h in ipairs(SS2.vaultHistory) do
        print(("  #%d %s — %d/%d files — master: %s (%d chars)"):format(
            i, h.time, h.ok, h.files, h.master, h.masterSize))
    end
end
SS2.vaultHistoryList = SS2.vaultHistoryList

-- ═══ journal autosave (60s, crash-proofing) ═══
SS2.autosaveJournal = true
task.spawn(function()
    while SS2.autosaveJournal do
        task.wait(60)
        if #SS2.journal > 0 then
            pcall(function()
                ensureVault()
                local jr = {}
                for _, e in ipairs(SS2.journal) do
                    jr[#jr + 1] = ("[%s] %s: %s"):format(e.t, e.tag, e.text)
                end
                writefile("SimplySpirited/" .. gf() .. "/vault/journal_autosave.txt",
                    table.concat(jr, "\n"))
            end)
        end
    end
end)
print("[vault] journal autosave: every 60s")

-- ═══ standalone manifest (absorbed from vault2) ═══
function SS2.vaultManifest()
    ensureVault()
    local folder = gf()
    local lines = {
        "SIMPLYSPIRITED VAULT MANIFEST — " .. os.date(),
        "game folder: " .. folder,
        "────────────────────────────────",
    }
    local known = {
        "full_intel.txt", "calls_raw.txt", "journal.txt", "session_summary.txt",
        "api_doc_v2.txt", "callers_full.txt", "closure_graph.txt",
        "journal_autosave.txt", "stealth_log.txt",
    }
    for _, f in ipairs(known) do
        local ok, content = pcall(function()
            return readfile("SimplySpirited/" .. folder .. "/vault/" .. f)
        end)
        if ok and content then
            lines[#lines + 1] = ("[OK ] %-26s %9d chars"):format(f, #content)
        else
            lines[#lines + 1] = ("[---] %-26s (not present)"):format(f)
        end
    end
    pcall(function()
        local files = listfiles("SimplySpirited/" .. folder .. "/decomp")
        local n = 0
        for _ in ipairs(files) do n = n + 1 end
        lines[#lines + 1] = ("[DIR] decomp/                    %d files"):format(n)
    end)
    writefile("SimplySpirited/" .. folder .. "/vault/_manifest.txt", table.concat(lines, "\n"))
    print("[vault] manifest written — self-audit complete")
    return table.concat(lines, "\n")
end
SS2.vaultManifest = SS2.vaultManifest

print("[SS2-vault] v4.7 LIVE — game-scoped, 8 artifacts, hashed")
print("[vault] SS2.exportAll()        — full export")
print("[vault] SS2.vaultSummary()     — one-page brief")
print("[vault] SS2.vaultHistoryList() — export ledger")
print("[vault] SS2.vaultManifest()    — standalone self-audit")
