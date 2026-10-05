-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.3 — VAULT 2 (export extensions)
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  • Caller attribution export (consumes v2.2 meta data)
--  • Preset library file I/O — portable between sessions
--  • Journal auto-save (crash-proofing, every 60s)
--  • Export manifest — the vault audits itself
-- ════════════════════════════════════════════════════════════

print("[SS2-vault2] loading vault extensions...")

local SS2 = getgenv().SS2
if not SS2 then warn("[SS2-vault2] core must load first") return end

local function ensureVault()
    pcall(function() makefolder("SimplySpirited") end)
    pcall(function() makefolder("SimplySpirited/vault") end)
end

local function w(name, content)
    ensureVault()
    pcall(function() writefile("SimplySpirited/vault/" .. name, content) end)
end

-- ═══ 1. CALLER ATTRIBUTION EXPORT ═══
-- aggregates caller data if closure/v2.2 features recorded it
function SS2.exportCallers()
    local out = {
        "SIMPLYSPIRITED — CALLER ATTRIBUTION",
        "game: " .. SS2.game .. " | " .. os.date(),
        "────────────────────────────────────",
    }
    local found = 0
    for r, prof in pairs(SS2.remotes) do
        if prof.callers then
            out[#out + 1] = ("REMOTE: %s (%s)"):format(r.Name, prof.class)
            local sorted = {}
            for caller, cnt in pairs(prof.callers) do
                sorted[#sorted + 1] = { c = caller, n = cnt }
            end
            table.sort(sorted, function(a, b) return a.n > b.n end)
            for _, e in ipairs(sorted) do
                out[#out + 1] = ("   [%4dx] %s"):format(e.n, e.c)
            end
            found = found + 1
        end
    end
    if found == 0 then
        out[#out + 1] = "(no caller data recorded — caller tracking not active this session)"
    end
    w("callers.txt", table.concat(out, "\n"))
    print("[vault2] callers.txt written — " .. found .. " remotes with attribution")
end
SS2.exportCallers = SS2.exportCallers

-- ═══ 2. PRESET LIBRARY I/O ═══
function SS2.savePresetLibrary(name)
    name = name or "default"
    ensureVault()
    local ser = {}
    ser[#ser + 1] = "SIMPLYSPIRITED PRESET LIBRARY — " .. name .. " — " .. os.date()
    ser[#ser + 1] = "game: " .. SS2.game
    ser[#ser + 1] = ""
    for pname, p in pairs(SS2.presets or {}) do
        ser[#ser + 1] = ("PRESET: %s"):format(pname)
        ser[#ser + 1] = ("  remote: %s (%s)"):format(p.remoteName, p.class)
        ser[#ser + 1] = ("  path:   %s"):format(p.path)
        ser[#ser + 1] = ("  saved:  %s"):format(p.saved)
        ser[#ser + 1] = ("  args:   %s"):format(table.concat(p.args, " | "))
    end
    local path = "SimplySpirited/vault/presets_" .. name .. ".txt"
    pcall(function() writefile(path, table.concat(ser, "\n")) end)
    print("[vault2] preset library saved: " .. path .. " (" .. (function()
        local n = 0 for _ in pairs(SS2.presets or {}) do n = n + 1 end return n
    end)() .. " presets)")
end
SS2.savePresetLibrary = SS2.savePresetLibrary

function SS2.loadPresetLibrary(name)
    -- note: reads back what savePresetLibrary wrote, if it exists
    name = name or "default"
    local ok, content = pcall(function()
        return readfile("SimplySpirited/vault/presets_" .. name .. ".txt")
    end)
    if not ok then
        print("[vault2] no library named '" .. name .. "'")
        return
    end
    -- display the library (true arg-reconstruction from text is v2.4's
    -- serialization upgrade — presets live in SS2.presets this session)
    print("═══ PRESET LIBRARY: " .. name .. " ═══")
    print(content)
end
SS2.loadPresetLibrary = SS2.loadPresetLibrary

-- ═══ 3. JOURNAL AUTO-SAVE (crash-proofing) ═══
SS2.autosaveJournal = true
task.spawn(function()
    while SS2.autosaveJournal do
        task.wait(60)
        if #SS2.journal > 0 then
            local jr = {}
            for _, e in ipairs(SS2.journal) do
                jr[#jr + 1] = ("[%s] %s: %s"):format(e.t, e.tag, e.text)
            end
            w("journal_autosave.txt", table.concat(jr, "\n"))
        end
    end
end)
print("[vault2] journal autosave: every 60s -> vault/journal_autosave.txt")

-- ═══ 4. EXPORT MANIFEST (the vault audits itself) ═══
function SS2.vaultManifest()
    ensureVault()
    local lines = {
        "SIMPLYSPIRITED VAULT MANIFEST",
        "game: " .. SS2.game .. " | " .. os.date(),
        "────────────────────────────────",
    }
    -- enumerate known vault files by attempting reads
    local known = {
        "full_intel.txt", "calls_raw.txt", "journal.txt", "session_summary.txt",
        "api_doc_v2.txt", "callers.txt", "journal_autosave.txt",
    }
    for _, f in ipairs(known) do
        local ok, content = pcall(function()
            return readfile("SimplySpirited/vault/" .. f)
        end)
        if ok and content then
            lines[#lines + 1] = ("[OK ] %-24s %8d chars"):format(f, #content)
        else
            lines[#lines + 1] = ("[---] %-24s (not present)"):format(f)
        end
    end
    -- decomp folder count
    local decompCount = 0
    pcall(function()
        local files = listfiles("SimplySpirited/decomp")
        for _ in ipairs(files) do decompCount = decompCount + 1 end
    end)
    lines[#lines + 1] = ("[DIR] decomp/                    %d files"):format(decompCount)
    writeVault = w -- local alias refresh
    w("_manifest.txt", table.concat(lines, "\n"))
    print("[vault2] manifest written — vault self-audit complete")
    lines[#lines + 1] = ""
    return table.concat(lines, "\n")
end
SS2.vaultManifest = SS2.vaultManifest

print("[SS2-vault2] vault extensions LIVE")
print("[vault2] commands:")
print("  SS2.exportCallers()              — caller attribution export")
print("  SS2.savePresetLibrary('name')    — portable preset library")
print("  SS2.loadPresetLibrary('name')    — view a saved library")
print("  SS2.vaultManifest()              — vault self-audit")
print("  (journal autosaves every 60s automatically)")
