--[[
    simplyspirited v4.6 — intel vault
    SHADOWMILESC / computerizedcarrier2

    the filing department. every byte of session intelligence,
    packed, named, versioned, and self-audited.

    v4.6: versioned filenames (no overwrites), per-file integrity
    hashes, export history ledger, 7 artifacts per run.

    the pipeline: play -> export -> copy workspace/SimplySpirited/
    vault/ to PC. the folder is the game's confession.
]]

print("[SS2-vault] v4.6 loading...")

local SS2 = getgenv().SS2
if not SS2 then
    warn("ss2-vault: core.lua must load first")
    return
end

local Players = game:GetService("Players")
local P = Players.LocalPlayer

-- ═══ vault infrastructure ═══
local function ensureVault()
    pcall(function() makefolder("SimplySpirited") end)
    pcall(function() makefolder("SimplySpirited/vault") end)
end

SS2.vaultHistory = SS2.vaultHistory or {}

-- content fingerprint: length + first/last chars checksum.
-- not crypto — a truncation detector. if the PC-side file
-- length differs from the recorded hash length, the transfer
-- was cut. simple, catches the common failure.
local function fingerprint(content)
    if type(content) ~= "string" then return "?" end
    local a = string.byte(content, 1) or 0
    local b = string.byte(content, -1) or 0
    return ("%d:%02x%02x"):format(#content, a, b)
end

-- ═══ timestamped filename helper ═══
local function stampName(base, ext)
    local t = os.time()
    local d = os.date("*t", t)
    return ("%s_%s%02d%02d_%02d%02d%02d.%s"):format(
        base, d.year, d.month, d.day, d.hour, d.min, d.sec, ext)
end

-- ═══ header builder ═══
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

-- ═══ 1. SESSION SUMMARY ═══
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
        ("capture health:     %.1f c/s smoothed"):format(
            SS2.health and SS2.health.callsEMA or 0),
    }
    if SS2.decompDB then
        lines[#lines + 1] = ("constants mined:    %d"):format(SS2.decompDB.count or 0)
    end
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

-- ═══ 2. THE MASTER EXPORT ═══
function SS2.vaultExportAll()
    task.spawn(function()
        ensureVault()
        local written = {}

        local function emit(name, content)
            local ok = pcall(function()
                writefile("SimplySpirited/vault/" .. name, content)
            end)
            written[#written + 1] = {
                name = name, ok = ok,
                size = ok and #content or 0,
                hash = ok and fingerprint(content) or "—",
            }
            print(("[vault] %s %s (%s chars, %s)"):format(
                ok and "✓" or "✗", name, tostring(#content), ok and fingerprint(content) or "—"))
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
            -- callers (from callers.lua)
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
            out[#out + 1] = ("PRESET: %s | %s %s | %s"):format(name, p.class, p.remoteName, p.saved)
            out[#out + 1] = ("  args: %s"):format(table.concat(p.args, " | "))
        end

        out[#out + 1] = ""
        out[#out + 1] = ("══════ SECTION 5: JOURNAL (%d) ══════"):format(#SS2.journal)
        for _, e in ipairs(SS2.journal) do
            out[#out + 1] = ("[%s] %s: %s"):format(e.t, e.tag, e.text)
        end

        -- call sites from callers.lua
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
            pl[#pl + 1] = ("  remote: %s (%s)"):format(p.remoteName, p.class)
            pl[#pl + 1] = ("  path:   %s"):format(p.path)
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

        -- ── artifact 7: caller attribution (if callers.lua loaded) ──
        if SS2.callSites then
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

        -- ── manifest with hashes ──
        local man = {
            "VAULT EXPORT MANIFEST",
            "game: " .. SS2.game .. " | " .. os.date(),
            "hash format: length:firstlast-byte checksum (truncation detector)",
            "────────────────────────────────",
        }
        for _, w in ipairs(written) do
            man[#man + 1] = ("[%s] %-36s %9d chars  %s"):format(
                w.ok and "OK " or "ERR", w.name, w.size, w.hash)
        end
        emit("_manifest.txt", table.concat(man, "\n"))

        -- ── history ledger ──
        table.insert(SS2.vaultHistory, {
            time = os.date("%H:%M:%S"),
            files = #written,
            ok = (function() local n = 0 for _, w in ipairs(written) do if w.ok then n = n + 1 end end return n end)(),
            master = masterName,
            masterSize = #master,
        })

        print("[vault] EXPORT COMPLETE — " .. #written .. " artifacts")
        print("[vault] latest master: " .. masterName)
        print("[vault] SS2.vaultHistory() for the ledger")
    end)
end
SS2.vaultExportAll = SS2.vaultExportAll
SS2.exportAll = SS2.vaultExportAll

-- ═══ 3. EXPORT HISTORY ═══
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
SS2.vaultHistory = SS2.vaultHistory

print("[SS2-vault] v4.6 LIVE — versioned exports, hashes, history")
print("[vault] SS2.exportAll()      — 7 artifacts -> vault/")
print("[vault] SS2.vaultSummary()   — one-page brief")
print("[vault] SS2.vaultHistoryList() — export ledger")
