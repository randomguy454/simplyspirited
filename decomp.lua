-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.0 — ADVANCED DECOMPILER
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  Layer 1: SOURCE read (.Source when the executor can)
--  Layer 2: BYTECODE capture (getscriptbytecode) for protected
--  Layer 3: CONSTANT MINING — extracts all strings, numbers,
--           and readable sequences from bytecode. Protected
--           scripts still confess their config tables, remote
--           names, URLs, and API strings.
--  Browser: game script tree with per-script actions
--  Output: SimplySpirited/decomp/ on Delta workspace
-- ════════════════════════════════════════════════════════════

print("[SS2-decomp] loading decompiler...")

local SS2 = getgenv().SS2
if not SS2 then warn("[SS2-decomp] core must load first") return end

local Players = game:GetService("Players")
local P = Players.LocalPlayer

SS2.decomp = {}

-- ═══════════ HELPERS ═══════════
local function sanitizePath(full)
    return full:gsub("[^%w_]", "_"):sub(1, 130)
end

local function ensureFolders()
    pcall(function() makefolder("SimplySpirited") end)
    pcall(function() makefolder("SimplySpirited/decomp") end)
end

local function hasSource(s)
    local ok, src = pcall(function() return s.Source end)
    return ok and type(src) == "string" and #src > 0, src
end

-- ═══════════ LAYER 3: CONSTANT MINING ═══════════
-- Bytecode is binary, but Luau embeds all string constants and
-- numeric literals in readable/parseable form. We extract:
--   - printable string runs (>= 4 chars)
--   - suspicious keywords (remote names, URLs, "Fire", "Gold"...)
local function mineConstants(bytecode)
    local found = {
        strings = {},
        urls = {},
        remotes = {},
        numbers = {},
    }
    if type(bytecode) ~= "string" or #bytecode == 0 then return found end

    -- printable string runs
    for s in bytecode:gmatch("[%w%p%s%-%_%.%:%/%\\]{4,}") do
        -- filter binary noise: keep runs that are mostly readable
        local readable = 0
        for i = 1, #s do
            local c = s:byte(i)
            if (c >= 32 and c <= 126) then readable = readable + 1 end
        end
        if readable / #s > 0.85 and #s >= 4 then
            local clean = s:match("^%s*(.-)%s*$")
            if #clean >= 4 then
                found.strings[#found.strings + 1] = clean
            end
        end
    end

    -- URLs
    for u in bytecode:gmatch("https?://[%w%.%-%_/%?%=%&]+") do
        found.urls[#found.urls + 1] = u
    end

    -- likely remote/API names (camelCase or snake_case words near common verbs)
    local keywords = { "Fire", "Invoke", "Remote", "Server", "Client", "Buy", "Purchase",
        "Damage", "Coins", "Cash", "Gold", "Gems", "Spawn", "Craft", "Sell", "Reward",
        "Points", "Tokens", "Level", "XP", "Shop", "Trade" }
    for _, kw in ipairs(keywords) do
        for s in bytecode:gmatch("%w*" .. kw .. "%w*") do
            if #s > #kw then
                found.remotes[#found.remotes + 1] = s
            end
        end
    end

    -- dedupe
    local function dedupe(t)
        local seen, out = {}, {}
        for _, v in ipairs(t) do
            if not seen[v] then
                seen[v] = true
                out[#out + 1] = v
            end
            if #out > 300 then break end
        end
        return out
    end
    found.strings = dedupe(found.strings)
    found.urls = dedupe(found.urls)
    found.remotes = dedupe(found.remotes)
    return found
end
SS2.decomp.mineConstants = mineConstants

-- ═══════════ SINGLE SCRIPT DECOMPILE ═══════════
-- returns report string, saves layers to disk
function SS2.decomp.script(s)
    if not s or not (s:IsA("LocalScript") or s:IsA("ModuleScript")) then
        return nil, "not a script"
    end
    ensureFolders()
    local clean = sanitizePath(s:GetFullName())
    local report = {
        "╔══════════════════════════════════════╗",
        "  DECOMP REPORT: " .. s:GetFullName(),
        "  class: " .. s.ClassName .. " | date: " .. os.date(),
        "╚══════════════════════════════════════╝",
    }

    -- LAYER 1: source
    local hasSrc, src = hasSource(s)
    if hasSrc then
        local path = "SimplySpirited/decomp/" .. clean .. ".src.lua"
        pcall(function() writefile(path, "-- SOURCE: " .. s:GetFullName() .. "\n" .. src) end)
        report[#report + 1] = "[L1] SOURCE: captured (" .. #src .. " chars) -> " .. path
    else
        report[#report + 1] = "[L1] SOURCE: inaccessible (protected or executor limitation)"
    end

    -- LAYER 2: bytecode
    local bc = nil
    pcall(function() bc = getscriptbytecode(s) end)
    if type(bc) == "string" and #bc > 0 then
        local path = "SimplySpirited/decomp/" .. clean .. ".bytecode"
        pcall(function() writefile(path, bc) end)
        report[#report + 1] = "[L2] BYTECODE: captured (" .. #bc .. " bytes) -> " .. path

        -- LAYER 3: constants
        local mined = mineConstants(bc)
        local mpath = "SimplySpirited/decomp/" .. clean .. ".constants.txt"
        local mOut = {}
        mOut[#mOut + 1] = "=== CONSTANTS: " .. s:GetFullName() .. " ==="
        mOut[#mOut + 1] = "URLs found: " .. #mined.urls
        for _, u in ipairs(mined.urls) do mOut[#mOut + 1] = "  " .. u end
        mOut[#mOut + 1] = "API/remote-name candidates: " .. #mined.remotes
        for _, r in ipairs(mined.remotes) do mOut[#mOut + 1] = "  " .. r end
        mOut[#mOut + 1] = "string constants: " .. #mined.strings
        for _, st in ipairs(mined.strings) do mOut[#mOut + 1] = "  " .. st:sub(1, 200) end
        pcall(function() writefile(mpath, table.concat(mOut, "\n")) end)
        report[#report + 1] = ("[L3] CONSTANTS: %d strings, %d urls, %d api-candidates -> %s"):format(
            #mined.strings, #mined.urls, #mined.remotes, mpath)
    else
        report[#report + 1] = "[L2] BYTECODE: capture failed (getscriptbytecode unavailable or blocked)"
    end

    local text = table.concat(report, "\n")
    print(text)
    return text
end
SS2.decomp.script = SS2.decomp.script

-- ═══════════ BULK DUMP ═══════════
function SS2.decomp.bulk(containerName, maxScripts)
    containerName = containerName or "ReplicatedStorage"
    maxScripts = maxScripts or 200
    task.spawn(function()
        ensureFolders()
        local root = containerName == "Players" and P or game:GetService(containerName)
        local nSrc, nBC, nSkip = 0, 0, 0
        local manifest = {
            "SIMPLYSPIRITED DECOMP BULK — " .. SS2.game,
            "container: " .. containerName .. " | date: " .. os.date(),
            "operator: SHADOWMILESC",
            "────────────────────────────────",
        }
        for _, d in ipairs(root:GetDescendants()) do
            if (nSrc + nBC) >= maxScripts then break end
            if d:IsA("LocalScript") or d:IsA("ModuleScript") then
                local clean = sanitizePath(d:GetFullName())
                local hasSrc, src = hasSource(d)
                if hasSrc then
                    pcall(function()
                        writefile("SimplySpirited/decomp/" .. clean .. ".src.lua",
                            "-- SOURCE: " .. d:GetFullName() .. "\n" .. src)
                    end)
                    nSrc = nSrc + 1
                    manifest[#manifest + 1] = ("[SRC] %s (%dc)"):format(d:GetFullName(), #src)
                else
                    local bc = nil
                    pcall(function() bc = getscriptbytecode(d) end)
                    if type(bc) == "string" and #bc > 0 then
                        pcall(function()
                            writefile("SimplySpirited/decomp/" .. clean .. ".bytecode", bc)
                        end)
                        local mined = mineConstants(bc)
                        local mOut = { "=== " .. d:GetFullName() .. " ===" }
                        for _, u in ipairs(mined.urls) do mOut[#mOut + 1] = "URL: " .. u end
                        for _, r in ipairs(mined.remotes) do mOut[#mOut + 1] = "API: " .. r end
                        for _, st in ipairs(mined.strings) do mOut[#mOut + 1] = "STR: " .. st:sub(1, 150) end
                        pcall(function()
                            writefile("SimplySpirited/decomp/" .. clean .. ".constants.txt",
                                table.concat(mOut, "\n"))
                        end)
                        nBC = nBC + 1
                        manifest[#manifest + 1] = ("[BC ] %s (%d bytes, %d constants)"):format(
                            d:GetFullName(), #bc, #mined.strings)
                    else
                        nSkip = nSkip + 1
                        manifest[#manifest + 1] = ("[---] %s (inaccessible)"):format(d:GetFullName())
                    end
                end
                task.wait()
            end
        end
        manifest[#manifest + 1] = "────────────────────────────────"
        manifest[#manifest + 1] = ("totals: %d source | %d bytecode | %d inaccessible"):format(nSrc, nBC, nSkip)
        writefile("SimplySpirited/decomp/_manifest.txt", table.concat(manifest, "\n"))
        print(("[SS2-decomp] BULK DONE: %d source, %d bytecode, %d skipped -> SimplySpirited/decomp/"):format(nSrc, nBC, nSkip))
        SS2.journalAdd and SS2.journalAdd("DECOMP", ("bulk %s: %d src, %d bc"):format(containerName, nSrc, nBC))
    end)
end
SS2.decomp.bulk = SS2.decomp.bulk

-- ═══════════ SCRIPT TREE BROWSER (console) ═══════════
function SS2.decomp.tree(containerName)
    containerName = containerName or "ReplicatedStorage"
    local root = containerName == "Players" and P or game:GetService(containerName)
    print("═══ SCRIPT TREE: " .. containerName .. " ═══")
    local n = 0
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("LocalScript") or d:IsA("ModuleScript") then
            n = n + 1
            local hasSrc = hasSource(d)
            print(("  %s %s%s"):format(
                hasSrc and "[src]" or "[??]", 
                string.rep("  ", 0),
                d:GetFullName()))
            if n > 80 then print("  ... (truncated at 80 — use bulk dump for full scan)") break end
        end
    end
    print("  total visible: " .. n)
    print("  decompile one: SS2.decomp.script(game.Path.To.Script)")
    print("  decompile all: SS2.decomp.bulk('" .. containerName .. "', 200)")
end
SS2.decomp.tree = SS2.decomp.tree

-- ═══════════ QUICK TARGETS (the usual suspects) ═══════════
function SS2.decomp.quick()
    print("═══ QUICK DECOMPILE: high-value targets ═══")
    local targets = {}
    -- main game modules in ReplicatedStorage
    for _, d in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
        if d:IsA("ModuleScript") and d.Name:lower():match("config|setting|main|init|remote|api|data") then
            targets[#targets + 1] = d
        end
    end
    -- starter player scripts
    for _, d in ipairs(game:GetService("StarterPlayer"):GetDescendants()) do
        if d:IsA("LocalScript") or d:IsA("ModuleScript") then
            targets[#targets + 1] = d
        end
    end
    print("  found " .. #targets .. " high-value targets")
    for i, t in ipairs(targets) do
        if i > 12 then print("  ...") break end
        SS2.decomp.script(t)
    end
end
SS2.decomp.quick = SS2.decomp.quick

print("[SS2-decomp] decompiler LIVE")
print("[decomp] console commands:")
print("  SS2.decomp.tree('ReplicatedStorage')      — browse script tree")
print("  SS2.decomp.script(game.Path.To.Script)    — full 3-layer decompile")
print("  SS2.decomp.bulk('ReplicatedStorage', 200) — bulk dump container")
print("  SS2.decomp.quick()                        — auto-hit high-value targets")
print("  SS2.decomp.mineConstants(bytecode)        — raw constant mining")
