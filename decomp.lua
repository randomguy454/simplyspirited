--[[
    simplyspirited v4.6 — decompiler engine
    SHADOWMILESC / computerizedcarrier2

    six layers:
      L1 source read          L2 bytecode capture
      L3 constant mining      L4 structure analysis
      L5 live-wire cross-ref  L6 synthesized report

    v4.6:
      - lua string-literal extraction (escape-aware) from bytecode
      - identifier mining: config-table keys from bytecode
      - fuzzy cross-ref: scored partial matches, case-insensitive
      - priority bulk: scripts referencing live remotes first
      - global constant database: game vocabulary, ranked
      - machine-readable index: decomp/index.txt

    honest scope: bytecode-to-source reconstruction does not exist
    client-side. every tool that claims it is doing extraction +
    presentation. this is the most complete extraction pipeline
    that fits in a client — and it is honest about that in every
    report it writes.
]]

print("[SS2-decomp] v4.6 engine loading...")

local SS2 = getgenv().SS2
if not SS2 then
    warn("ss2-decomp: core.lua must load first")
    return
end

local Players = game:GetService("Players")
local P = Players.LocalPlayer

SS2.decomp = {}
SS2.decompResults = {}

-- ════════════════════════════════════════════════════════════
-- capability probes (dynamic — re-probe per bulk run)
-- ════════════════════════════════════════════════════════════
local function probeCaps()
    local c = { source = false, bytecode = false }
    local probe = Instance.new("ModuleScript")
    pcall(function()
        if type(probe.Source) == "string" then c.source = true end
    end)
    pcall(function()
        if getscriptbytecode and type(getscriptbytecode(probe)) == "string" then
            c.bytecode = true
        end
    end)
    probe:Destroy()
    return c
end
SS2.decomp.caps = probeCaps()
print(("[SS2-decomp] caps: source=%s bytecode=%s"):format(
    tostring(SS2.decomp.caps.source), tostring(SS2.decomp.caps.bytecode)))

-- ════════════════════════════════════════════════════════════
-- storage
-- ════════════════════════════════════════════════════════════
SS2.decompDB = SS2.decompDB or {
    constants = {},   -- [constant] = {count, scripts={}}
    scripts = {},     -- [path] = result table (last analysis)
    count = 0,
}
local DB = SS2.decompDB

local function sanitizePath(full)
    return full:gsub("[^%w_]", "_"):sub(1, 130)
end

local function ensureFolders()
    pcall(function() makefolder("SimplySpirited") end)
    pcall(function() makefolder("SimplySpirited/decomp") end)
end
SS2.decomp.ensureFolders = ensureFolders

-- ════════════════════════════════════════════════════════════
-- L3a: RAW RUN EXTRACTION (readable printable runs)
-- ════════════════════════════════════════════════════════════
local function extractRuns(bc)
    local runs = {}
    for s in bc:gmatch("[%w%p%s%-%_%.%:%/%\\]{4,}") do
        local readable = 0
        for i = 1, #s do
            local c = s:byte(i)
            if c >= 32 and c <= 126 then readable = readable + 1 end
        end
        if readable / #s > 0.9 and #s >= 4 then
            local clean = s:match("^%s*(.-)%s*$")
            if #clean >= 4 then
                runs[#runs + 1] = clean
            end
        end
    end
    return runs
end

-- ════════════════════════════════════════════════════════════
-- L3b: LUA STRING-LITERAL EXTRACTION (escape-aware)
-- bytecode stores constants contiguously; quoted literals with
-- escapes often survive as \"...\" runs — worth mining separately
-- ════════════════════════════════════════════════════════════
local function extractStringLiterals(bc)
    local literals = {}
    -- \"..." escaped form
    for s in bc:gmatch('\\"([%w%s%p%-%_%.%:%/%\\]-)\\"') do
        if #s >= 3 and #s <= 300 then
            literals[#literals + 1] = s
        end
    end
    return literals
end

-- ════════════════════════════════════════════════════════════
-- L3c: IDENTIFIER MINING (camelCase / snake_case config keys)
-- ════════════════════════════════════════════════════════════
local function extractIdentifiers(runs)
    local ids = {}
    local seen = {}
    for _, s in ipairs(runs) do
        -- identifiers that look like config keys (not sentences)
        if #s <= 40 and not s:find("%s") and s:match("^[%a%_][%w%_]*$") then
            local hasLower, hasUpper = s:match("[a-z]"), s:match("[A-Z]")
            if (hasLower and hasUpper) or s:find("_", 1, true) then
                if not seen[s] then
                    seen[s] = true
                    ids[#ids + 1] = s
                end
            end
        end
    end
    return ids
end
SS2.decomp.extractIdentifiers = extractIdentifiers

-- ════════════════════════════════════════════════════════════
-- L3d: CATEGORIZATION (the v4.0 logic, kept + webhooks split)
-- ════════════════════════════════════════════════════════════
local REMOTE_HINTS = { "Fire", "Invoke", "Remote", "Server", "Client",
    "Buy", "Purchase", "Damage", "Coin", "Cash", "Gold", "Gem", "Money",
    "Spawn", "Craft", "Sell", "Reward", "Points", "Token", "Shop",
    "Trade", "Level", "XP", "Speed", "Teleport", "Weapon", "Tool" }
local SENSITIVE = { "password", "token", "secret", "apikey", "webhook" }

local function categorize(runs, literals)
    local M = { strings = {}, urls = {}, webhooks = {}, remoteHints = {},
        sensitive = {}, identifiers = {}, numbers = {} }

    local seenS, seenU, seenW, seenR, seenX, seenL = {}, {}, {}, {}, {}, {}

    for _, s in ipairs(runs) do
        if s:match("^https?://") then
            if not seenU[s] then
                seenU[s] = true
                if s:find("webhook", 1, true) then
                    M.webhooks[#M.webhooks + 1] = s
                else
                    M.urls[#M.urls + 1] = s
                end
            end
        end
        local lower = s:lower()
        for _, kw in ipairs(SENSITIVE) do
            if lower:find(kw, 1, true) and #s < 120 and not seenX[s] then
                seenX[s] = true
                M.sensitive[#M.sensitive + 1] = s
                break
            end
        end
        for _, kw in ipairs(REMOTE_HINTS) do
            if s:find(kw, 1, true) then
                if not seenR[s] then
                    seenR[s] = true
                    M.remoteHints[#M.remoteHints + 1] = s
                end
                break
            end
        end
        if not seenS[s] then
            seenS[s] = true
            M.strings[#M.strings + 1] = s
            if #M.strings > 400 then return M end
        end
    end

    for _, s in ipairs(literals) do
        if not seenL[s] then
            seenL[s] = true
            M.strings[#M.strings + 1] = "[lit] " .. s
        end
    end

    return M
end

-- ════════════════════════════════════════════════════════════
-- GLOBAL CONSTANT DATABASE (v4.6)
-- every constant ever mined, deduped, frequency-ranked
-- ════════════════════════════════════════════════════════════
local function dbRecord(constants)
    for _, s in ipairs(constants.strings or {}) do
        local e = DB.constants[s]
        if e then
            e.count = e.count + 1
        else
            DB.constants[s] = { count = 1 }
            DB.count = DB.count + 1
        end
    end
end

function SS2.decomp.topConstants(n)
    n = n or 30
    local sorted = {}
    for c, e in pairs(DB.constants) do
        sorted[#sorted + 1] = { s = c, n = e.count }
    end
    table.sort(sorted, function(a, b) return a.n > b.n end)
    print("═══ game vocabulary (top " .. n .. " of " .. DB.count .. ") ═══")
    for k = 1, math.min(n, #sorted) do
        print(("  [%4dx] %s"):format(sorted[k].n, sorted[k].s:sub(1, 90)))
    end
    return sorted
end
SS2.decomp.topConstants = SS2.decomp.topConstants

-- ════════════════════════════════════════════════════════════
-- L4: STRUCTURE (kept from v4.0, + obfuscation classification)
-- ════════════════════════════════════════════════════════════
local function analyzeStructure(src)
    local A = { functionCount = 0, remoteRefs = {}, requires = {},
        obfuscated = false, lineCount = 0 }
    if type(src) ~= "string" then return A end

    A.lineCount = select(2, src:gsub("\n", "")) + 1
    _, A.functionCount = src:gsub("function%s", "")

    for m in src:gmatch("GetService%(\"([%w]+)\"%)") do
        A.remoteRefs[#A.remoteRefs + 1] = "GetService:" .. m
    end
    for m in src:gmatch("FindFirst%w*%(\"([%w%s%p]-)\"%)") do
        A.remoteRefs[#A.remoteRefs + 1] = "Find:" .. m
    end
    for m in src:gmatch("WaitForChild%(\"([%w%s%p]-)\"%)") do
        A.remoteRefs[#A.remoteRefs + 1] = "Wait:" .. m
    end
    for m in src:gmatch("require%(([%w%.%:]+)%)") do
        A.requires[#A.requires + 1] = m
    end

    if #src > 2000 then
        local nonAscii = 0
        for i = 1, 2000 do
            if src:byte(i) > 126 then nonAscii = nonAscii + 1 end
        end
        if nonAscii / 2000 > 0.3 then A.obfuscated = true end
        if src:find("getfenv", 1, true) and src:find("string%.char", 1, true) then
            A.obfuscated = true
        end
    end
    return A
end
SS2.decomp.analyzeStructure = analyzeStructure

-- ════════════════════════════════════════════════════════════
-- L5: LIVE-WIRE CROSS-REF (v4.6: fuzzy + scored)
-- exact match = 100 pts | case-insensitive = 70 | partial = 40
-- ════════════════════════════════════════════════════════════
local function crossReference(mined, structure)
    local xref, seen = {}, {}
    local function addMatch(kind, name, score)
        if not seen[name] then
            seen[name] = true
            local prof = SS2.remotes[name]
            local calls = prof and prof.calls or 0
            xref[#xref + 1] = {
                kind = kind, name = name, score = score, calls = calls,
            }
        end
    end

    for _, s in ipairs(mined.strings or {}) do
        for name, prof in pairs(SS2.remotes) do
            if s == name then
                addMatch("exact", name, 100)
            elseif #name > 6 and s:lower() == name:lower() then
                addMatch("case-insensitive", name, 70)
            elseif #name > 8 and s:find(name, 1, true) then
                addMatch("contains", name, 40)
            end
        end
    end
    for _, ref in ipairs(structure.remoteRefs or {}) do
        local target = ref:match("Find:(.+)$") or ref:match("Wait:(.+)$")
        if target then
            for name, prof in pairs(SS2.remotes) do
                if name == target and not seen[name] then
                    addMatch("referenced", name, 90)
                end
            end
        end
    end

    table.sort(xref, function(a, b) return a.score > b.score end)
    return xref
end
SS2.decomp.crossReference = crossReference

-- ════════════════════════════════════════════════════════════
-- SINGLE-SCRIPT PIPELINE (all 6 layers)
-- ════════════════════════════════════════════════════════════
function SS2.decomp.script(s)
    if not s or not (s:IsA("LocalScript") or s:IsA("ModuleScript")) then
        return nil, "not a script"
    end
    ensureFolders()
    local clean = sanitizePath(s:GetFullName())
    local report = {}
    local result = { name = s:GetFullName(), class = s.ClassName, layers = {} }

    -- L1
    local ok1, src = pcall(function() return s.Source end)
    if ok1 and type(src) == "string" and #src > 0 then
        result.hasSource = true
        pcall(function()
            writefile("SimplySpirited/decomp/" .. clean .. ".src.lua",
                "-- SOURCE: " .. s:GetFullName() .. "\n" .. src)
        end)
        report[#report + 1] = ("[L1] SOURCE: %d chars"):format(#src)
        result.structure = analyzeStructure(src)
        report[#report + 1] = ("[L4] STRUCTURE: %d lines, %d funcs, %d refs, obfuscated=%s"):format(
            result.structure.lineCount, result.structure.functionCount,
            #result.structure.remoteRefs, tostring(result.structure.obfuscated))
    else
        result.hasSource = false
        report[#report + 1] = "[L1] SOURCE: inaccessible"
    end

    -- L2
    local ok2, bc = pcall(function() return getscriptbytecode(s) end)
    if ok2 and type(bc) == "string" and #bc > 0 then
        result.bytecodeLen = #bc
        pcall(function()
            writefile("SimplySpirited/decomp/" .. clean .. ".bytecode", bc)
        end)
        report[#report + 1] = ("[L2] BYTECODE: %d bytes"):format(#bc)

        -- L3 (v4.6: runs + literals + identifiers)
        local runs = extractRuns(bc)
        local literals = extractStringLiterals(bc)
        result.mined = categorize(runs, literals)
        result.identifiers = extractIdentifiers(runs)

        local mOut = { "=== L3 CONSTANTS: " .. s:GetFullName() .. " ===" }
        mOut[#mOut + 1] = "URLS: " .. #result.mined.urls
        for _, u in ipairs(result.mined.urls) do mOut[#mOut + 1] = "  " .. u end
        mOut[#mOut + 1] = "WEBHOOKS: " .. #result.mined.webhooks
        for _, u in ipairs(result.mined.webhooks) do mOut[#mOut + 1] = "  !! " .. u end
        mOut[#mOut + 1] = "SENSITIVE: " .. #result.mined.sensitive
        for _, u in ipairs(result.mined.sensitive) do mOut[#mOut + 1] = "  ?? " .. u end
        mOut[#mOut + 1] = "REMOTE/API HINTS: " .. #result.mined.remoteHints
        for _, u in ipairs(result.mined.remoteHints) do mOut[#mOut + 1] = "  " .. u end
        mOut[#mOut + 1] = "IDENTIFIERS: " .. #result.identifiers
        for _, u in ipairs(result.identifiers) do mOut[#mOut + 1] = "  " .. u end
        mOut[#mOut + 1] = "STRINGS: " .. #result.mined.strings
        for _, u in ipairs(result.mined.strings) do mOut[#mOut + 1] = "  " .. u:sub(1, 180) end
        pcall(function()
            writefile("SimplySpirited/decomp/" .. clean .. ".constants.txt",
                table.concat(mOut, "\n"))
        end)
        dbRecord(result.mined)
        report[#report + 1] = ("[L3] CONSTANTS: %d strings, %d hints, %d identifiers, %d sensitive"):format(
            #result.mined.strings, #result.mined.remoteHints,
            #result.identifiers, #result.mined.sensitive)
    else
        report[#report + 1] = "[L2] BYTECODE: capture failed"
    end

    -- L5
    if result.mined then
        result.xref = crossReference(result.mined, result.structure or {})
        if #result.xref > 0 then
            report[#report + 1] = ("[L5] CROSS-REF: %d matches"):format(#result.xref)
            for _, x in ipairs(result.xref) do
                report[#report + 1] = ("  ★ [%s %d] %s (%d calls seen)"):format(
                    x.kind, x.score, x.name, x.calls)
            end
        end
    end

    local text = table.concat(report, "\n")
    result.report = text
    SS2.decompResults[s:GetFullName()] = result
    DB.scripts[s:GetFullName()] = result
    return text, nil, result
end
SS2.decomp.script = SS2.decomp.script

-- ════════════════════════════════════════════════════════════
-- BULK (v4.6: PRIORITY-RANKED — live-wire-referencing scripts
-- get mined FIRST, manifest shows the heat map)
-- ════════════════════════════════════════════════════════════
function SS2.decomp.bulk(containerName, maxScripts)
    containerName = containerName or "ReplicatedStorage"
    maxScripts = maxScripts or 200
    task.spawn(function()
        ensureFolders()
        local caps = probeCaps()
        local root = containerName == "Players" and P or game:GetService(containerName)

        -- pass 1: collect scripts + score them against live remotes
        local scored = {}
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("LocalScript") or d:IsA("ModuleScript") then
                local score = 0
                -- name-based pre-score: script names matching live remotes
                for r, prof in pairs(SS2.remotes) do
                    if prof.calls > 0 and d.Name:lower():find(r.Name:lower(), 1, true) then
                        score = score + 50
                    end
                end
                scored[#scored + 1] = { d = d, score = score }
            end
        end
        table.sort(scored, function(a, b) return a.score > b.score end)

        local nSrc, nBC, nSkip, crossHits = 0, 0, 0, 0
        local manifest = {
            "SIMPLYSPIRITED v4.6 DECOMP BULK — priority-ranked",
            "container: " .. containerName .. " | date: " .. os.date(),
            "operator: SHADOWMILESC (computerizedcarrier2)",
            "════════════════════════════════",
        }

        for _, e in ipairs(scored) do
            if (nSrc + nBC) >= maxScripts then break end
            local d = e.d
            local clean = sanitizePath(d:GetFullName())
            local tag = e.score > 0 and ("[HOT:" .. e.score .. "]") or "[   ]"

            local ok1, src = pcall(function() return d.Source end)
            if ok1 and type(src) == "string" and #src > 0 then
                pcall(function()
                    writefile("SimplySpirited/decomp/" .. clean .. ".src.lua",
                        "-- SOURCE: " .. d:GetFullName() .. "\n" .. src)
                end)
                nSrc = nSrc + 1
                manifest[#manifest + 1] = ("[SRC]%s %s (%dc)"):format(tag, d:GetFullName(), #src)
                -- L4 structure even in bulk for source scripts
                local struct = analyzeStructure(src)
                if struct.obfuscated then
                    manifest[#manifest + 1] = ("      !! obfuscated source detected")
                end
            else
                local ok2, bc = pcall(function() return getscriptbytecode(d) end)
                if ok2 and type(bc) == "string" and #bc > 0 then
                    pcall(function()
                        writefile("SimplySpirited/decomp/" .. clean .. ".bytecode", bc)
                    end)
                    local runs = extractRuns(bc)
                    local literals = extractStringLiterals(bc)
                    local mined = categorize(runs, literals)
                    local mOut = { "=== " .. d:GetFullName() .. " ===" }
                    for _, u in ipairs(mined.urls) do mOut[#mOut + 1] = "URL: " .. u end
                    for _, u in ipairs(mined.webhooks) do mOut[#mOut + 1] = "WEBHOOK: " .. u end
                    for _, u in ipairs(mined.sensitive) do mOut[#mOut + 1] = "SENSITIVE: " .. u end
                    for _, r in ipairs(mined.remoteHints) do mOut[#mOut + 1] = "API: " .. r end
                    for _, id in ipairs(extractIdentifiers(runs)) do mOut[#mOut + 1] = "ID: " .. id end
                    for _, st in ipairs(mined.strings) do mOut[#mOut + 1] = "STR: " .. st:sub(1, 150) end
                    pcall(function()
                        writefile("SimplySpirited/decomp/" .. clean .. ".constants.txt",
                            table.concat(mOut, "\n"))
                    end)
                    dbRecord(mined)
                    -- live-wire cross-ref
                    local xref = crossReference(mined, {})
                    for _, x in ipairs(xref) do
                        crossHits = crossHits + 1
                        manifest[#manifest + 1] = ("[XRF]%s %s — %s (%s, %d)"):format(
                            tag, d:GetFullName(), x.name, x.kind, x.calls)
                    end
                    nBC = nBC + 1
                    manifest[#manifest + 1] = ("[BC ]%s %s (%d bytes)"):format(tag, d:GetFullName(), #bc)
                else
                    nSkip = nSkip + 1
                    manifest[#manifest + 1] = ("[---]%s %s (inaccessible)"):format(tag, d:GetFullName())
                end
            end
            task.wait()
        end

        manifest[#manifest + 1] = "════════════════════════════════"
        manifest[#manifest + 1] = ("totals: %d src | %d bc | %d skipped | %d xref | %d unique constants in DB"):format(
            nSrc, nBC, nSkip, crossHits, DB.count)

        -- machine-readable index (v4.6)
        local index = { "index\ttype\tname\tcalls\tscore" }
        for _, e in ipairs(scored) do
            local okS, s = pcall(function() return #e.d.Source end)
            index[#index + 1] = ("%s\t%s\t%s\t%d\t%d"):format(
                e.d:GetFullName(), okS and "src" or "bc", e.d.Name, 0, e.score)
        end
        writefile("SimplySpirited/decomp/index.txt", table.concat(index, "\n"))

        writefile("SimplySpirited/decomp/_manifest.txt", table.concat(manifest, "\n"))
        print(("[SS2-decomp] BULK DONE: %d src | %d bc | %d skip | %d XRF | DB: %d constants"):format(
            nSrc, nBC, nSkip, crossHits, DB.count))
        if SS2.journalAdd then
            SS2.journalAdd("DECOMP", ("bulk %s: %d/%d/%d, %d xref"):format(
                containerName, nSrc, nBC, nSkip, crossHits))
        end
    end)
end
SS2.decomp.bulk = SS2.decomp.bulk

-- ════════════════════════════════════════════════════════════
-- TREE + QUICK (kept, formatted)
-- ════════════════════════════════════════════════════════════
function SS2.decomp.tree(containerName)
    containerName = containerName or "ReplicatedStorage"
    local root = containerName == "Players" and P or game:GetService(containerName)
    print("═══ script tree: " .. containerName .. " ═══")
    local n = 0
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("LocalScript") or d:IsA("ModuleScript") then
            n = n + 1
            local hasSrc = pcall(function() return #d.Source > 0 end)
            print(("  %s %s"):format(hasSrc and "[src]" or "[??]", d:GetFullName()))
            if n > 80 then print("  … (80 shown)") break end
        end
    end
    print("  total: " .. n)
end
SS2.decomp.tree = SS2.decomp.tree

function SS2.decomp.quick()
    print("═══ quick: high-value targets ═══")
    local targets = {}
    for _, d in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
        if d:IsA("ModuleScript") and d.Name:lower():match("config|setting|main|init|remote|api|data|network") then
            targets[#targets + 1] = d
        end
    end
    for _, d in ipairs(game:GetService("StarterPlayer"):GetDescendants()) do
        if d:IsA("LocalScript") or d:IsA("ModuleScript") then
            targets[#targets + 1] = d
        end
    end
    print("  found " .. #targets .. " targets")
    for i, t in ipairs(targets) do
        if i > 15 then print("  … (15 shown)") break end
        SS2.decomp.script(t)
    end
end
SS2.decomp.quick = SS2.decomp.quick

print("[SS2-decomp] v4.6 LIVE — priority bulk, fuzzy xref, constant DB")
print("[decomp] SS2.decomp.script/bulk/tree/quick")
print("[decomp] SS2.decomp.topConstants(30) — game vocabulary, ranked")
