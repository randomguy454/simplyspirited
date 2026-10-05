-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.0 — INTEL VAULT (EXPORT)
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  • FULL EXPORT: every byte of session intelligence, one file
--  • JOURNAL DUMP: timestamped event history
--  • PRESET LIBRARY: saved call library -> portable file
--  • REMOTE PROFILE EXPORT: per-remote full dossiers
--  • SESSION SUMMARY: the one-page brief
--  Everything lands in workspace/SimplySpirited/vault/
-- ════════════════════════════════════════════════════════════

print("[SS2-vault] loading export tier...")

local SS2 = getgenv().SS2
if not SS2 then warn("[SS2-vault] core must load first") return end

local Players = game:GetService("Players")
local P = Players.LocalPlayer

local function ensureVault()
    pcall(function() makefolder("SimplySpirited") end)
    pcall(function() makefolder("SimplySpirited/vault") end)
end

local function writeVault(name, content)
    ensureVault()
    local path = "SimplySpirited/vault/" .. name
    local ok = pcall(function() writefile(path, content) end)
    print(("[vault] %s -> %s (%s chars)"):format(ok and "SAVED" or "FAILED", path, tostring(#content)))
    return ok, path
end

-- ═══════════ SECTION BUILDERS ═══════════
local function buildHeader(title)
    return table.concat({
        "╔══════════════════════════════════════════╗",
        "  " .. title,
        "  game:    " .. SS2.game,
        "  place:   " .. SS2.placeId,
        "  job:     " .. SS2.jobId,
        "  date:    " .. os.date(),
        "  operator: SHADOWMILESC (computerizedcarrier2)",
        "  suite:   SIMPLYSPIRITED v" .. tostring(SS2.version) .. " DRAW EDITION",
        "╚══════════════════════════════════════════╝",
        "",
    }, "\n")
end

-- ═══ 1. SESSION SUMMARY ═══
function SS2.vaultSummary()
    local remoteCount = 0
    local totalCalls = 0
    for r, prof in pairs(SS2.remotes) do
        remoteCount = remoteCount + 1
        totalCalls = totalCalls + prof.calls
    end
    local valueCount = 0
    for _ in pairs(SS2.values) do valueCount = valueCount + 1 end
    local presetCount = 0
    for _ in pairs(SS2.presets or {}) do presetCount = presetCount + 1 end

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
        ("journal entries:    %d"):format(#SS2.journal),
        "",
        "TOP 10 REMOTES BY ACTIVITY:",
    }
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

-- ═══ 2. FULL EXPORT ═══
function SS2.vaultExportAll()
    task.spawn(function()
        ensureVault()

        -- -- file 1: full_intel.txt (the master document) -- --
        local out = {}
        out[#out + 1] = buildHeader("FULL INTELLIGENCE EXPORT")
        out[#out + 1] = SS2.vaultSummary()
        out[#out + 1] = ""

        out[#out + 1] = "══════════════ SECTION 1: REMOTE PROFILES ══════════════"
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
            local sigs = {}
            for sig, cnt in pairs(prof.sigs) do
                sigs[#sigs + 1] = { s = sig, c = cnt }
            end
            table.sort(sigs, function(a, b) return a.c > b.c end)
            for k = 1, math.min(10, #sigs) do
                out[#out + 1] = ("  [%dx] %s"):format(sigs[k].c, sigs[k].s)
            end
        end

        out[#out + 1] = ""
        out[#out + 1] = ("══════════════ SECTION 2: CALL LOG (%d) ══════════════"):format(#SS2.log)
        for _, rec in ipairs(SS2.log) do
            out[#out + 1] = ("#%d [%s] %s %s :: %s"):format(
                rec.id, rec.dir, rec.class, rec.name, table.concat(rec.args, " | "))
        end

        out[#out + 1] = ""
        out[#out + 1] = "══════════════ SECTION 3: TRACKED VALUES ══════════════"
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
        out[#out + 1] = ("══════════════ SECTION 4: PRESETS (%d) ══════════════"):format(
            (function()
                local n = 0
                for _ in pairs(SS2.presets or {}) do n = n + 1 end
                return n
            end)())
        for name, p in pairs(SS2.presets or {}) do
            out[#out + 1] = ("PRESET: %s | %s %s | saved %s"):format(name, p.class, p.remoteName, p.saved)
            out[#out + 1] = ("  args: %s"):format(table.concat(p.args, " | "))
        end

        out[#out + 1] = ""
        out[#out + 1] = ("══════════════ SECTION 5: JOURNAL (%d) ══════════════"):format(#SS2.journal)
        for _, e in ipairs(SS2.journal) do
            out[#out + 1] = ("[%s] %s: %s"):format(e.t, e.tag, e.text)
        end

        writeVault("full_intel.txt", table.concat(out, "\n"))

        -- -- file 2: raw call log (machine-readable) -- --
        local raw = {}
        for _, rec in ipairs(SS2.log) do
            raw[#raw + 1] = table.concat({
                "id=" .. rec.id,
                "dir=" .. rec.dir,
                "class=" .. rec.class,
                "name=" .. rec.name,
                "path=" .. rec.path,
                "nargs=" .. #rec.raw,
                "args=" .. table.concat(rec.args, "~|~"),
            }, "\t")
        end
        writeVault("calls_raw.txt", table.concat(raw, "\n"))

        -- -- file 3: journal -- --
        local jr = {}
        for _, e in ipairs(SS2.journal) do
            jr[#jr + 1] = ("[%s] %s: %s"):format(e.t, e.tag, e.text)
        end
        writeVault("journal.txt", table.concat(jr, "\n"))

        -- -- file 4: session brief -- --
        writeVault("session_summary.txt", buildHeader("SESSION SUMMARY") .. "\n" .. SS2.vaultSummary())

        print("[vault] EXPORT COMPLETE — 4 files in SimplySpirited/vault/")
        print("[vault]   full_intel.txt      <- the master document")
        print("[vault]   calls_raw.txt       <- machine-readable call log")
        print("[vault]   journal.txt         <- event history")
        print("[vault]   session_summary.txt <- the one-page brief")
        print("[vault] take the vault folder to your PC — session complete")
    end)
end
SS2.exportAll = SS2.vaultExportAll

-- ═══════════ UI BUTTONS (inject into existing draw window) ═══════════
pcall(function()
    -- vault controls live in console for v2.0; draw integration in v2.1
end)

print("[SS2-vault] export tier LIVE")
print("[vault] console commands:")
print("  SS2.vaultSummary()   — print the one-page brief to console")
print("  SS2.exportAll()      — pack EVERYTHING -> SimplySpirited/vault/")
print("  SS2.apiDoc()         — API document (from watch.lua)")
print("  SS2.decomp.bulk()    — script dumping (from decomp.lua)")
print("")
print("[vault] FULL SESSION PIPELINE:")
print("  1. play the game (suite captures everything)")
print("  2. SS2.exportAll()")
print("  3. SS2.apiDoc() + SS2.decomp.bulk() for deep intel")
print("  4. copy workspace/SimplySpirited/ to your PC")
print("  5. that folder IS the game's confession")-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.0 — INTEL VAULT (EXPORT)
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  • FULL EXPORT: every byte of session intelligence, one file
--  • JOURNAL DUMP: timestamped event history
--  • PRESET LIBRARY: saved call library -> portable file
--  • REMOTE PROFILE EXPORT: per-remote full dossiers
--  • SESSION SUMMARY: the one-page brief
--  Everything lands in workspace/SimplySpirited/vault/
-- ════════════════════════════════════════════════════════════

print("[SS2-vault] loading export tier...")

local SS2 = getgenv().SS2
if not SS2 then warn("[SS2-vault] core must load first") return end

local Players = game:GetService("Players")
local P = Players.LocalPlayer

local function ensureVault()
    pcall(function() makefolder("SimplySpirited") end)
    pcall(function() makefolder("SimplySpirited/vault") end)
end

local function writeVault(name, content)
    ensureVault()
    local path = "SimplySpirited/vault/" .. name
    local ok = pcall(function() writefile(path, content) end)
    print(("[vault] %s -> %s (%s chars)"):format(ok and "SAVED" or "FAILED", path, tostring(#content)))
    return ok, path
end

-- ═══════════ SECTION BUILDERS ═══════════
local function buildHeader(title)
    return table.concat({
        "╔══════════════════════════════════════════╗",
        "  " .. title,
        "  game:    " .. SS2.game,
        "  place:   " .. SS2.placeId,
        "  job:     " .. SS2.jobId,
        "  date:    " .. os.date(),
        "  operator: SHADOWMILESC (computerizedcarrier2)",
        "  suite:   SIMPLYSPIRITED v" .. tostring(SS2.version) .. " DRAW EDITION",
        "╚══════════════════════════════════════════╝",
        "",
    }, "\n")
end

-- ═══ 1. SESSION SUMMARY ═══
function SS2.vaultSummary()
    local remoteCount = 0
    local totalCalls = 0
    for r, prof in pairs(SS2.remotes) do
        remoteCount = remoteCount + 1
        totalCalls = totalCalls + prof.calls
    end
    local valueCount = 0
    for _ in pairs(SS2.values) do valueCount = valueCount + 1 end
    local presetCount = 0
    for _ in pairs(SS2.presets or {}) do presetCount = presetCount + 1 end

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
        ("journal entries:    %d"):format(#SS2.journal),
        "",
        "TOP 10 REMOTES BY ACTIVITY:",
    }
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

-- ═══ 2. FULL EXPORT ═══
function SS2.vaultExportAll()
    task.spawn(function()
        ensureVault()

        -- -- file 1: full_intel.txt (the master document) -- --
        local out = {}
        out[#out + 1] = buildHeader("FULL INTELLIGENCE EXPORT")
        out[#out + 1] = SS2.vaultSummary()
        out[#out + 1] = ""

        out[#out + 1] = "══════════════ SECTION 1: REMOTE PROFILES ══════════════"
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
            local sigs = {}
            for sig, cnt in pairs(prof.sigs) do
                sigs[#sigs + 1] = { s = sig, c = cnt }
            end
            table.sort(sigs, function(a, b) return a.c > b.c end)
            for k = 1, math.min(10, #sigs) do
                out[#out + 1] = ("  [%dx] %s"):format(sigs[k].c, sigs[k].s)
            end
        end

        out[#out + 1] = ""
        out[#out + 1] = ("══════════════ SECTION 2: CALL LOG (%d) ══════════════"):format(#SS2.log)
        for _, rec in ipairs(SS2.log) do
            out[#out + 1] = ("#%d [%s] %s %s :: %s"):format(
                rec.id, rec.dir, rec.class, rec.name, table.concat(rec.args, " | "))
        end

        out[#out + 1] = ""
        out[#out + 1] = "══════════════ SECTION 3: TRACKED VALUES ══════════════"
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
        out[#out + 1] = ("══════════════ SECTION 4: PRESETS (%d) ══════════════"):format(
            (function()
                local n = 0
                for _ in pairs(SS2.presets or {}) do n = n + 1 end
                return n
            end)())
        for name, p in pairs(SS2.presets or {}) do
            out[#out + 1] = ("PRESET: %s | %s %s | saved %s"):format(name, p.class, p.remoteName, p.saved)
            out[#out + 1] = ("  args: %s"):format(table.concat(p.args, " | "))
        end

        out[#out + 1] = ""
        out[#out + 1] = ("══════════════ SECTION 5: JOURNAL (%d) ══════════════"):format(#SS2.journal)
        for _, e in ipairs(SS2.journal) do
            out[#out + 1] = ("[%s] %s: %s"):format(e.t, e.tag, e.text)
        end

        writeVault("full_intel.txt", table.concat(out, "\n"))

        -- -- file 2: raw call log (machine-readable) -- --
        local raw = {}
        for _, rec in ipairs(SS2.log) do
            raw[#raw + 1] = table.concat({
                "id=" .. rec.id,
                "dir=" .. rec.dir,
                "class=" .. rec.class,
                "name=" .. rec.name,
                "path=" .. rec.path,
                "nargs=" .. #rec.raw,
                "args=" .. table.concat(rec.args, "~|~"),
            }, "\t")
        end
        writeVault("calls_raw.txt", table.concat(raw, "\n"))

        -- -- file 3: journal -- --
        local jr = {}
        for _, e in ipairs(SS2.journal) do
            jr[#jr + 1] = ("[%s] %s: %s"):format(e.t, e.tag, e.text)
        end
        writeVault("journal.txt", table.concat(jr, "\n"))

        -- -- file 4: session brief -- --
        writeVault("session_summary.txt", buildHeader("SESSION SUMMARY") .. "\n" .. SS2.vaultSummary())

        print("[vault] EXPORT COMPLETE — 4 files in SimplySpirited/vault/")
        print("[vault]   full_intel.txt      <- the master document")
        print("[vault]   calls_raw.txt       <- machine-readable call log")
        print("[vault]   journal.txt         <- event history")
        print("[vault]   session_summary.txt <- the one-page brief")
        print("[vault] take the vault folder to your PC — session complete")
    end)
end
SS2.exportAll = SS2.vaultExportAll

-- ═══════════ UI BUTTONS (inject into existing draw window) ═══════════
pcall(function()
    -- vault controls live in console for v2.0; draw integration in v2.1
end)

print("[SS2-vault] export tier LIVE")
print("[vault] console commands:")
print("  SS2.vaultSummary()   — print the one-page brief to console")
print("  SS2.exportAll()      — pack EVERYTHING -> SimplySpirited/vault/")
print("  SS2.apiDoc()         — API document (from watch.lua)")
print("  SS2.decomp.bulk()    — script dumping (from decomp.lua)")
print("")
print("[vault] FULL SESSION PIPELINE:")
print("  1. play the game (suite captures everything)")
print("  2. SS2.exportAll()")
print("  3. SS2.apiDoc() + SS2.decomp.bulk() for deep intel")
print("  4. copy workspace/SimplySpirited/ to your PC")
print("  5. that folder IS the game's confession")
