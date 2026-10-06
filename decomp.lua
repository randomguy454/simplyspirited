-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v4.0 — DECOMPILER ENGINE
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  L1 source | L2 bytecode | L3 constants | L4 structure
--  L5 live-wire cross-reference | L6 synthesized report
--  Every extraction pcall'd and bounded. Failures are data.
-- ════════════════════════════════════════════════════════════

print("[SS2-decomp] v4.0 engine loading...")

local SS2 = getgenv().SS2
if not SS2 then warn("[SS2-decomp] core must load first") return end

local Players = game:GetService("Players")
local P = Players.LocalPlayer

SS2.decomp = {}
SS2.decompResults = {}

-- ═══ capability probes ═══
local CAPS = { source = false, bytecode = false }
local probe = Instance.new("ModuleScript")
pcall(function()
    if type(probe.Source) == "string" then CAPS.source = true end
end)
pcall(function()
    if getscriptbytecode and type(getscriptbytecode(probe)) == "string" then
        CAPS.bytecode = true
    end
end)
probe:Destroy()
print(("[SS2-decomp] caps: source=%s bytecode=%s"):format(
    tostring(CAPS.source), tostring(CAPS.bytecode)))
SS2.decomp.caps = CAPS

local function sanitizePath(full)
    return full:gsub("[^%w_]", "_"):sub(1, 130)
end

local function ensureFolders()
    pcall(function() makefolder("SimplySpirited") end)
    pcall(function() makefolder("SimplySpirited/decomp") end)
end
SS2.decomp.ensureFolders = ensureFolders

-- ═══ L3: CONSTANT MINER ═══
local REMOTE_HINTS = { "Fire", "Invoke", "Remote", "Server", "Client",
    "Buy", "Purchase", "Damage", "Coin", "Cash", "Gold", "Gem", "Money",
    "Spawn", "Craft", "Sell", "Reward", "Points", "Token", "Shop",
    "Trade", "Level", "XP", "Speed", "Teleport", "Weapon", "Tool" }
local SENSITIVE = { "password", "token", "secret", "apikey", "webhook" }

local function mineConstants(bytecode)
    local M = { strings = {}, urls = {}, webhooks = {},
        remoteHints = {}, sensitive = {}, numbers = {} }
    if type(bytecode) ~= "string" or #bytecode == 0 then return M end

    local seenS, seenU, seenR, seenX, seenN = {}, {}, {}, {}, {}

    for s in bytecode:gmatch("[%w%p%s%-%_%.%:%/%\\]{4,}") do
        local readable = 0
        for i = 1, #s do
            local c = s:byte(i)
            if c >= 32 and c <= 126 then readable = readable + 1 end
        end
        if readable / #s > 0.9 and #s >= 4 then
            local clean = s:match("^%s*(.-)%s*$")
            if #clean >= 4 then
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
                    if lower:find(kw, 1, true) and not seenX[s] then
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
        end
    end

    for n in bytecode:gmatch("[%c%s](%d%d%d%d+)") do
        local v = tonumber(n)
        if v and not seenN[v] then
            seenN[v] = true
            M.numbers[#M.numbers + 1] = v
            if #M.numbers > 60 then break end
        end
    end

    return M
end
SS2.decomp.mineConstants = mineConstants

-- ═══ L4: STRUCTURE ANALYSIS (source only) ═══
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

-- ═══ L5: LIVE-WIRE CROSS-REFERENCE ═══
local function crossReference(mined, structure)
    local xref, seen = {}, {}
    for _, s in ipairs(mined.strings or {}) do
        for name, prof in pairs(SS2.remotes) do
            if s == name and not seen[name] then
                seen[name] = true
                xref[#xref + 1] = ("live remote: %s (%d calls seen)"):format(name, prof.calls)
            end
        end
    end
    for _, ref in ipairs(structure.remoteRefs or {}) do
        local target = ref:match("Find:(.+)$") or ref:match("Wait:(.+)$")
        if target then
            for name, prof in pairs(SS2.remotes) do
                if name == target and not seen[name] then
                    seen[name] = true
                    xref[#xref + 1] = ("live remote via ref: %s"):format(target)
                end
            end
        end
    end
    return xref
end
SS2.decomp.crossReference = crossReference

-- ═══ FULL PIPELINE: one script, all layers ═══
function SS2.decomp.script(s)
    if not s or not (s:IsA("LocalScript") or s:IsA("ModuleScript")) then
        return nil, "not a script"
    end
    ensureFolders()
    local clean = sanitizePath(s:GetFullName())
    local report = {}
    local result = { name = s:GetFullName(), class = s.ClassName }

    -- L1
    local ok1, src = pcall(function() return s.Source end)
    if ok1 and type(src) == "string" and #src > 0 then
        result.hasSource = true
        pcall(function()
            writefile("SimplySpirited/decomp/" .. clean .. ".src.lua",
                "-- SOURCE: " .. s:GetFullName() .. "\n" .. src)
        end)
        report[#report + 1] = ("[L1] SOURCE: %d chars captured"):format(#src)
        result.structure = analyzeStructure(src)
        report[#report + 1] = ("[L4] STRUCTURE: %d lines, %d functions, %d refs, obfuscated=%s"):format(
            result.structure.lineCount, result.structure.functionCount,
            #result.structure.remoteRefs, tostring(result.structure.obfuscated))
    else
        result.hasSource = false
        report[#report + 1] = "[L1] SOURCE: inaccessible"
    end

    -- L2 + L3
    local ok2, bc = pcall(function() return getscriptbytecode(s) end)
    if ok2 and type(bc) == "string" and #bc > 0 then
        result.bytecodeLen = #bc
        pcall(function()
            writefile("SimplySpirited/decomp/" .. clean .. ".bytecode", bc)
        end)
        report[#report + 1] = ("[L2] BYTECODE: %d bytes captured"):format(#bc)

        result.mined = mineConstants(bc)
        local mOut = { "=== L3 CONSTANTS: " .. s:GetFullName() .. " ===" }
        mOut[#mOut + 1] = "URLs: " .. #result.mined.urls
        for _, u in ipairs(result.mined.urls) do mOut[#mOut + 1] = "  " .. u end
        mOut[#mOut + 1] = "WEBHOOKS: " .. #result.mined.webhooks
        for _, u in ipairs(result.mined.webhooks) do mOut[#mOut + 1] = "  !! " .. u end
        mOut[#mOut + 1] = "SENSITIVE: " .. #result.mined.sensitive
        for _, u in ipairs(result.mined.sensitive) do mOut[#mOut + 1] = "  ?? " .. u end
        mOut[#mOut + 1] = "REMOTE/API HINTS: " .. #result.mined.remoteHints
        for _, u in ipairs(result.mined.remoteHints) do mOut[#mOut + 1] = "  " .. u end
        mOut[#mOut + 1] = "STRINGS: " .. #result.mined.strings
        for _, u in ipairs(result.mined.strings) do mOut[#mOut + 1] = "  " .. u:sub(1, 180) end
        local nums = {}
        for _, n in ipairs(result.mined.numbers) do nums[#nums + 1] = tostring(n) end
        mOut[#mOut + 1] = "NUMBERS: " .. table.concat(nums, ", ")
        pcall(function()
            writefile("SimplySpirited/decomp/" .. clean .. ".constants.txt",
                table.concat(mOut, "\n"))
        end)
        report[#report + 1] = ("[L3] CONSTANTS: %d strings, %d urls, %d hints, %d sensitive"):format(
            #result.mined.strings, #result.mined.urls,
            #result.mined.remoteHints, #result.mined.sensitive)
    else
        report[#report + 1] = "[L2] BYTECODE: capture failed"
    end

    -- L5
    if result.mined then
        result.xref = crossReference(result.mined, result.structure or {})
        if #result.xref > 0 then
            report[#report + 1] = ("[L5] CROSS-REF: %d LIVE-WIRE MATCHES"):format(#result.xref)
            for _, x in ipairs(result.xref) do
                report[#report + 1] = ("  ★ %s"):format(x)
            end
        end
    end

    local text = table.concat(report, "\n")
    result.report = text
    SS2.decompResults[s:GetFullName()] = result
    return text, nil, result
end
SS2.decomp.script = SS2.decomp.script

-- ═══ BULK ═══
function SS2.decomp.bulk(containerName, maxScripts)
    containerName = containerName or "ReplicatedStorage"
    maxScripts = maxScripts or 200
    task.spawn(function()
        ensureFolders()
        local root = containerName == "Players" and P or game:GetService(containerName)
        local nSrc, nBC, nSkip, crossHits = 0, 0, 0, 0
        local manifest = {
            "SIMPLYSPIRITED v4.0 DECOMP BULK",
            "container: " .. containerName .. " | date: " .. os.date(),
            "operator: SHADOWMILESC (computerizedcarrier2)",
            "════════════════════════════════",
        }
        for _, d in ipairs(root:GetDescendants()) do
            if (nSrc + nBC) >= maxScripts then break end
            if d:IsA("LocalScript") or d:IsA("ModuleScript") then
                local clean = sanitizePath(d:GetFullName())
                local ok1, src = pcall(function() return d.Source end)
                if ok1 and type(src) == "string" and #src > 0 then
                    pcall(function()
                        writefile("SimplySpirited/decomp/" .. clean .. ".src.lua",
                            "-- SOURCE: " .. d:GetFullName() .. "\n" .. src)
                    end)
                    nSrc = nSrc + 1
                    manifest[#manifest + 1] = ("[SRC] %s (%dc)"):format(d:GetFullName(), #src)
                else
                    local ok2, bc = pcall(function() return getscriptbytecode(d) end)
                    if ok2 and type(bc) == "string" and #bc > 0 then
                        pcall(function()
                            writefile("SimplySpirited/decomp/" .. clean .. ".bytecode", bc)
                        end)
                        local mined = mineConstants(bc)
                        local mOut = { "=== " .. d:GetFullName() .. " ===" }
                        for _, u in ipairs(mined.urls) do mOut[#mOut + 1] = "URL: " .. u end
                        for _, u in ipairs(mined.webhooks) do mOut[#mOut + 1] = "WEBHOOK: " .. u end
                        for _, u in ipairs(mined.sensitive) do mOut[#mOut + 1] = "SENSITIVE: " .. u end
                        for _, r in ipairs(mined.remoteHints) do mOut[#mOut + 1] = "API: " .. r end
                        for _, st in ipairs(mined.strings) do mOut[#mOut + 1] = "STR: " .. st:sub(1, 150) end
                        pcall(function()
                            writefile("SimplySpirited/decomp/" .. clean .. ".constants.txt",
                                table.concat(mOut, "\n"))
                        end)
                        local xref = crossReference(mined, {})
                        for _, x in ipairs(xref) do
                            crossHits = crossHits + 1
                            manifest[#manifest + 1] = ("[XRF] %s — %s"):format(d:GetFullName(), x)
                        end
                        nBC = nBC + 1
                        manifest[#manifest + 1] = ("[BC ] %s (%d bytes)"):format(d:GetFullName(), #bc)
                    else
                        nSkip = nSkip + 1
                        manifest[#manifest + 1] = ("[---] %s (inaccessible)"):format(d:GetFullName())
                    end
                end
                task.wait()
            end
        end
        manifest[#manifest + 1] = "════════════════════════════════"
        manifest[#manifest + 1] = ("totals: %d source | %d bytecode | %d skipped | %d cross-refs"):format(
            nSrc, nBC, nSkip, crossHits)
        writefile("SimplySpirited/decomp/_manifest.txt", table.concat(manifest, "\n"))
        print(("[SS2-decomp] BULK DONE: %d src | %d bc | %d skipped | %d LIVE-WIRE MATCHES"):format(
            nSrc, nBC, nSkip, crossHits))
        if SS2.journalAdd then
            SS2.journalAdd("DECOMP", ("bulk %s: %d src, %d bc, %d xref"):format(containerName, nSrc, nBC, crossHits))
        end
    end)
end
SS2.decomp.bulk = SS2.decomp.bulk

-- ═══ TREE ═══
function SS2.decomp.tree(containerName)
    containerName = containerName or "ReplicatedStorage"
    local root = containerName == "Players" and P or game:GetService(containerName)
    print("═══ SCRIPT TREE: " .. containerName .. " ═══")
    local n = 0
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("LocalScript") or d:IsA("ModuleScript") then
            n = n + 1
            local ok = pcall(function() return #d.Source > 0 end)
            print(("  %s %s"):format(ok and "[src]" or "[??]", d:GetFullName()))
            if n > 80 then print("  … (80 shown)") break end
        end
    end
    print("  total: " .. n)
end
SS2.decomp.tree = SS2.decomp.tree

-- ═══ QUICK ═══
function SS2.decomp.quick()
    print("═══ QUICK: high-value targets ═══")
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

print("[SS2-decomp] v4.0 engine LIVE — 6 layers, cross-referencing armed")
