--[[
    simplyspirited v4.7 — core engine
    SHADOWMILESC / computerizedcarrier2

    universal remote intelligence. assumes nothing about the game.

    capture architecture:
      INBOUND  = OnClientEvent connections (reliable)
      OUTBOUND = namecall net (total coverage)
      per-remote hookfunction layer removed — the net is whole game.

    v4.7 additions:
      - gameFolder(): game-scoped folder naming for every tier
      - adaptive rescan (2s boot window, then 15s steady)
      - capture health metrics (EMA rate, drop counters)
      - runtime-editable filters/keywords, journaled
      - everything swallowed is counted, nothing silent
]]

print("[SS2-core] v4.7 booting...")

local Players = game:GetService("Players")
local P = Players.LocalPlayer

-- ═══════════ STATE ═══════════
getgenv().SS2 = {
    version = "4.7",
    game = game.Name,
    placeId = game.PlaceId,
    jobId = game.JobId,

    remotes = {},   -- [remote] = profile
    log = {},       -- call records (bounded ring)
    journal = {},   -- significant events
    values = {},    -- [valueObj] = lastValue
    players = {},   -- [player] = snapshot

    verbosity = "smart",      -- quiet | smart | loud
    keywords = {              -- smart-mode interest keywords (editable)
        "buy", "purchase", "cash", "coin", "gold", "gem", "money",
        "damage", "hit", "attack", "kill", "death", "reward", "claim",
        "spawn", "craft", "sell", "trade", "level", "xp", "win",
        "data", "save", "auth", "key", "remote",
    },

    filters = {               -- name-fragments dropped entirely
        heartbeat = true, stepped = true, renderstepped = true,
        input = true, mouse = true, camera = true, touch = true,
        keyframe = true, animation = true, physics = true,
    },

    maxLog = 2000,
    capture = true,
    startTime = os.clock(),

    health = {
        callsEMA = 0,
        thisSecond = 0,
        filterDropped = 0,
        verbositySuppressed = 0,
        rescanFinds = 0,
    },
}
local SS2 = getgenv().SS2

-- ═══════════ JOURNAL ═══════════
local function journal(tag, text)
    local entry = { t = os.date("%H:%M:%S"), tag = tag, text = text }
    table.insert(SS2.journal, entry)
    if #SS2.journal > 500 then table.remove(SS2.journal, 1) end
end
SS2.journalAdd = journal

-- ════════════════════════════════════════════════════════════
-- v4.7: GAME-SCOPED FOLDER NAMING
-- every tier's output lands under the game's own folder
-- ════════════════════════════════════════════════════════════
local function gameFolderName()
    local name = tostring(SS2.game or game.Name)
    name = name:gsub("[^%w]", "_")
    name = name:gsub("_+", "_")
    name = name:match("^_*(.-)_*$") or name
    if #name < 2 then name = "UnknownGame" end
    return name
end
SS2.gameFolder = gameFolderName

-- ═══════════ DECONSTRUCTOR ═══════════
local function describe(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "string" then
        if #v <= 80 then return '"' .. v .. '"' end
        return ('str(%d):"%s…"'):format(#v, v:sub(1, 40))
    elseif t == "Vector3" then
        return ("V3(%.2f,%.2f,%.2f)"):format(v.X, v.Y, v.Z)
    elseif t == "Vector2" then
        return ("V2(%.1f,%.1f)"):format(v.X, v.Y)
    elseif t == "CFrame" then
        local p = v.Position
        return ("CF(%.1f,%.1f,%.1f)"):format(p.X, p.Y, p.Z)
    elseif t == "Instance" then
        return v.ClassName .. ":" .. v.Name
    elseif t == "number" then
        if v == math.floor(v) and math.abs(v) < 1e12 then return tostring(v) end
        return ("%.4f"):format(v)
    elseif t == "boolean" then
        return tostring(v)
    elseif t == "nil" then
        return "nil"
    elseif t == "Color3" then
        return ("C3(%d,%d,%d)"):format(v.R * 255, v.G * 255, v.B * 255)
    elseif t == "EnumItem" then
        return tostring(v)
    elseif t == "table" then
        if depth >= 2 then return "tbl#" .. #v end
        local parts, n = {}, 0
        for k, vv in pairs(v) do
            n = n + 1
            if n > 6 then
                parts[#parts + 1] = "…"
                break
            end
            local key = typeof(k) == "string" and k or ("[" .. tostring(k) .. "]")
            parts[#parts + 1] = key .. "=" .. describe(vv, depth + 1)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif t == "function" then
        return "function"
    elseif t == "thread" then
        return "thread"
    else
        return t
    end
end
SS2.describe = describe

-- ═══════════ HEALTH METER ═══════════
local function tickHealth()
    SS2.health.thisSecond = SS2.health.thisSecond + 1
end

-- ═══════════ CALL RECORDER (verbosity-gated) ═══════════
local callId = 0

local function recordCall(remote, args, direction)
    if not SS2.capture then return end

    tickHealth()

    local lname = remote.Name:lower()
    for bad, on in pairs(SS2.filters) do
        if on and lname:find(bad, 1, true) then
            SS2.health.filterDropped = SS2.health.filterDropped + 1
            return
        end
    end
    callId = callId + 1

    local prof = SS2.remotes[remote]
    local path = remote.Name
    if prof and prof.path then path = prof.path end

    local rec = {
        id = callId,
        remote = remote,
        name = remote.Name,
        path = path,
        class = remote.ClassName,
        dir = direction,
        t = os.clock(),
        args = {},
        raw = args,
    }
    for i, v in ipairs(args) do
        rec.args[i] = describe(v)
    end

    table.insert(SS2.log, rec)
    if #SS2.log > SS2.maxLog then table.remove(SS2.log, 1) end

    if prof then
        prof.calls = prof.calls + 1
        prof.lastSeen = os.date("%H:%M:%S")
        if direction == "OUT" then prof.out = prof.out + 1 else prof.inn = prof.inn + 1 end
        local sig = table.concat(rec.args, "|")
        prof.sigs[sig] = (prof.sigs[sig] or 0) + 1
    end

    -- verbosity gate
    local tag = direction == "OUT" and ">>>" or "<<<"
    local showIt
    if SS2.verbosity == "loud" then
        showIt = true
    elseif SS2.verbosity == "quiet" then
        showIt = false
        SS2.health.verbositySuppressed = SS2.health.verbositySuppressed + 1
    else
        showIt = (prof and prof.calls <= 2)
            or (SS2._isInteresting and SS2._isInteresting(rec))
        if not showIt then
            SS2.health.verbositySuppressed = SS2.health.verbositySuppressed + 1
        end
    end
    if showIt then
        print(("[%s #%d] %s %s\n    %s"):format(
            tag, rec.id, rec.class, rec.path, table.concat(rec.args, " | ")))
    end

    if SS2.onCall then
        pcall(SS2.onCall, rec)
    end
end
SS2.recordCall = recordCall

-- ═══════════ REMOTE PROFILES + INBOUND HOOKS ═══════════
local function profileFor(r)
    local prof = SS2.remotes[r]
    if not prof then
        prof = {
            path = r.Name,
            class = r.ClassName,
            calls = 0, out = 0, inn = 0,
            hooked = false,
            metaCaught = 0,
            sigs = {},
            callers = {},
            firstSeen = os.date("%H:%M:%S"),
        }
        pcall(function()
            prof.path = r:GetFullName():gsub("Players%." .. P.Name .. "%.", "ME.")
        end)
        SS2.remotes[r] = prof
    end
    return prof
end
SS2.profileFor = profileFor

local function hookRemote(r)
    local prof = profileFor(r)
    if prof.hooked then return end
    prof.hooked = true

    -- inbound only — outbound belongs to the net
    if r:IsA("RemoteEvent") then
        pcall(function()
            r.OnClientEvent:Connect(function(...)
                prof.calls = prof.calls + 1
                prof.inn = prof.inn + 1
                recordCall(r, { ... }, "IN")
            end)
        end)
    end
end
SS2.hookRemote = hookRemote

local function scanAllRemotes()
    local n = 0
    for _, d in ipairs(game:GetDescendants()) do
        if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
            pcall(hookRemote, d)
            n = n + 1
        end
    end
    return n
end
SS2.scanRemotes = scanAllRemotes

game.DescendantAdded:Connect(function(d)
    if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
        task.defer(pcall, hookRemote, d)
    end
end)

-- ═══════════ ADAPTIVE RESCAN (v4.6, kept) ═══════════
-- aggressive early (boot-race recovery), then steady 15s.
-- reports every recovery into the journal.
task.spawn(function()
    local sweeps = 0
    while true do
        local waitTime = (sweeps < 30) and 2 or 15
        task.wait(waitTime)
        sweeps = sweeps + 1
        pcall(function()
            local found = 0
            for _, d in ipairs(game:GetDescendants()) do
                if (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) and not SS2.remotes[d] then
                    pcall(hookRemote, d)
                    found = found + 1
                end
            end
            if found > 0 then
                SS2.health.rescanFinds = SS2.health.rescanFinds + found
                journal("RESCAN", "recovered " .. found .. " late-loaded remotes")
                print("[SS2-core] rescan recovered " .. found .. " late remotes")
            end
        end)
    end
end)

-- ═══════════ NAMECALL NET (outbound, total) ═══════════
pcall(function()
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if self and typeof(self) == "Instance" then
            local ok, class = pcall(function() return self.ClassName end)
            if ok and (class == "RemoteEvent" or class == "RemoteFunction") then
                if method == "FireServer" or method == "InvokeServer" then
                    local args = { ... }
                    local prof = profileFor(self)
                    prof.calls = prof.calls + 1
                    prof.out = prof.out + 1
                    prof.metaCaught = prof.metaCaught + 1
                    recordCall(self, args, "OUT")
                end
            end
        end
        return oldNamecall(self, ...)
    end)
    SS2.metaHooked = true
    print("[SS2-core] namecall net armed — outbound: total")
end)

-- ═══════════ VALUE WATCHER ═══════════
local function watchValue(obj)
    if SS2.values[obj] ~= nil then return end
    SS2.values[obj] = obj.Value
    journal("VALUE", "tracking " .. obj.Name .. " = " .. tostring(obj.Value))
    local function onChange(v)
        local old = SS2.values[obj]
        SS2.values[obj] = v
        local path = obj.Name
        pcall(function()
            path = obj:GetFullName():gsub("Players%." .. P.Name .. "%.", "ME.")
        end)
        local delta = ""
        if tonumber(v) and tonumber(old) then
            local d = v - old
            delta = " (" .. (d >= 0 and "+" or "") .. tostring(d) .. ")"
        end
        print(("[VALUE] " .. path .. ": " .. tostring(old) .. " -> " .. tostring(v) .. delta))
        if SS2.onValue then
            pcall(SS2.onValue, obj, old, v)
        end
    end
    pcall(function() obj.Changed:Connect(onChange) end)
end
SS2.watchValue = watchValue

task.spawn(function()
    local ls = P:WaitForChild("leaderstats", 15)
    if ls then
        for _, d in ipairs(ls:GetChildren()) do
            if d:IsA("ValueBase") then watchValue(d) end
        end
        ls.ChildAdded:Connect(function(d)
            if d:IsA("ValueBase") then watchValue(d) end
        end)
        journal("VALUE", "leaderstats attached")
    else
        journal("VALUE", "no leaderstats — fallback scanning player")
        for _, d in ipairs(P:GetDescendants()) do
            if d:IsA("ValueBase") then watchValue(d) end
        end
    end
    P.DescendantAdded:Connect(function(d)
        if d:IsA("ValueBase") then
            task.defer(pcall, watchValue, d)
        end
    end)
end)

-- ═══════════ PLAYER CENSUS ═══════════
local function playerSnapshot(pl)
    local snap = { name = pl.Name, display = pl.DisplayName, stats = {}, at = os.date("%H:%M:%S") }
    pcall(function()
        local ls = pl:FindFirstChild("leaderstats")
        if ls then
            for _, d in ipairs(ls:GetChildren()) do
                if d:IsA("ValueBase") then snap.stats[d.Name] = d.Value end
            end
        end
    end)
    return snap
end
SS2.playerSnapshot = playerSnapshot

task.spawn(function()
    task.wait(3)
    print("═══ [SS2] PLAYER CENSUS ═══")
    for _, pl in ipairs(Players:GetPlayers()) do
        local s = playerSnapshot(pl)
        SS2.players[pl] = s
        local st = ""
        for k, v in pairs(s.stats) do
            st = st .. k .. ":" .. tostring(v) .. " "
        end
        print(("  %s (%s) %s"):format(s.name, s.display, st))
    end
end)

Players.PlayerAdded:Connect(function(pl)
    journal("PLAYER", pl.Name .. " joined")
end)
Players.PlayerRemoving:Connect(function(pl)
    journal("PLAYER", pl.Name .. " left")
    SS2.players[pl] = nil
end)

-- ═══════════ RUNTIME-EDITABLE KEYWORDS ═══════════
function SS2.addKeyword(kw)
    if kw and #kw > 1 then
        table.insert(SS2.keywords, kw:lower())
        journal("CONFIG", "keyword added: " .. kw)
        print("[core] keyword added: " .. kw)
    end
end

function SS2.listKeywords()
    print("═══ smart-mode keywords ═══")
    print("  " .. table.concat(SS2.keywords, ", "))
end

-- ═══════════ HEALTH REPORT ═══════════
task.spawn(function()
    while true do
        task.wait(1)
        local inst = SS2.health.thisSecond
        SS2.health.callsEMA = SS2.health.callsEMA * 0.7 + inst * 0.3
        SS2.health.thisSecond = 0
    end
end)

function SS2.healthReport()
    local h = SS2.health
    local rc = 0
    for _ in pairs(SS2.remotes) do rc = rc + 1 end
    print("═══ capture health ═══")
    print(("  remotes: %d | calls buffered: %d"):format(rc, #SS2.log))
    print(("  rate: %.1f calls/sec (smoothed)"):format(h.callsEMA))
    print(("  filter-dropped: %d | verbosity-suppressed: %d"):format(
        h.filterDropped, h.verbositySuppressed))
    print(("  rescan-recovered remotes: %d"):format(h.rescanFinds))
    print(("  journal entries: %d"):format(#SS2.journal))
    print(("  game folder: SimplySpirited/%s/"):format(gameFolderName()))
end
SS2.healthReport = SS2.healthReport

-- ═══════════ FILTER RUNTIME EDITS ═══════════
function SS2.addFilter(fragment)
    if fragment and #fragment > 1 then
        SS2.filters[fragment:lower()] = true
        print("[core] filter added: " .. fragment)
    end
end

function SS2.removeFilter(fragment)
    SS2.filters[fragment:lower()] = nil
    print("[core] filter removed: " .. fragment)
end

function SS2.listFilters()
    print("═══ active filters ═══")
    for f, on in pairs(SS2.filters) do
        if on then print("  " .. f) end
    end
end

-- ═══════════ BOOT ═══════════
local remoteCount = scanAllRemotes()

journal("BOOT", "v4.7 online in " .. SS2.game .. " | " .. remoteCount .. " remotes")
print("[SS2-core] discovered " .. remoteCount .. " remotes (inbound watch)")
print("[SS2-core] namecall net: " .. tostring(SS2.metaHooked) .. " (outbound watch)")
print("[SS2-core] adaptive rescan live | health metrics live")
print("[SS2-core] game folder: SimplySpirited/" .. gameFolderName() .. "/")
print("[SS2-core] verbosity: " .. SS2.verbosity .. " | filters/keywords runtime-editable")
print("[SS2-core] engine ready — SS2.healthReport() for capture vitals")
getgenv().SS2_READY = true
