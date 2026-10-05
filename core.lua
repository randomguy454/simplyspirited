-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.0 — CORE ENGINE
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  Universal remote intelligence. Assumes nothing about the game.
--  • Discovery + hooks: every RemoteEvent/Function, in AND out
--  • Full call storage: RAW args preserved (replayer-grade)
--  • Remote profiles: per-remote counts + arg signature histories
--  • Value watcher: any ValueBase, delta-tracked
--  • Player census • session journal • toggleable noise filters
--  All state: getgenv().SS2
-- ════════════════════════════════════════════════════════════

print("[SS2-core] booting...")

local Players = game:GetService("Players")
local P = Players.LocalPlayer

-- ═══════════ STATE ═══════════
getgenv().SS2 = {
    version = "2.0",
    game = game.Name,
    placeId = game.PlaceId,
    jobId = game.JobId,

    remotes = {},   -- [remote] = profile {path, class, calls, out, inn, hooked, sigs={sig->count}, firstSeen, lastSeen}
    log = {},       -- call records {id, remote, name, path, class, dir, t, args(desc), raw}
    journal = {},   -- significant events
    values = {},    -- [valueObj] = lastValue
    players = {},   -- [player] = snapshot

    filters = {
        heartbeat = true, stepped = true, renderstepped = true,
        input = true, mouse = true, camera = true, touch = true,
        keyframe = true, animation = true, physics = true,
    },
    maxLog = 2000,
    capture = true,
    startTime = os.clock(),
}
local SS2 = getgenv().SS2

-- ═══════════ JOURNAL ═══════════
local function journal(tag, text)
    local entry = {
        t = os.date("%H:%M:%S"),
        tag = tag,
        text = text,
    }
    table.insert(SS2.journal, entry)
    if #SS2.journal > 500 then table.remove(SS2.journal, 1) end
end
SS2.journalAdd = journal

-- ═══════════ DECONSTRUCTOR ═══════════
local function describe(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "string" then
        if #v <= 80 then return '"' .. v .. '"' end
        return 'str(' .. #v .. '):"' .. v:sub(1, 40) .. '..."'
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
                parts[#parts + 1] = "..."
                break
            end
            local key
            if typeof(k) == "string" then key = k else key = "[" .. tostring(k) .. "]" end
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

-- ═══════════ CALL RECORDER ═══════════
local callId = 0

local function recordCall(remote, args, direction)
    if not SS2.capture then return end
    local lname = remote.Name:lower()
    for bad, on in pairs(SS2.filters) do
        if on and lname:find(bad, 1, true) then return end
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

    -- profile update
    if prof then
        prof.calls = prof.calls + 1
        prof.lastSeen = os.date("%H:%M:%S")
        if direction == "OUT" then prof.out = prof.out + 1 else prof.inn = prof.inn + 1 end
        local sig = table.concat(rec.args, "|")
        prof.sigs[sig] = (prof.sigs[sig] or 0) + 1
    end

    local tag = direction == "OUT" and ">>>" or "<<<"
    print(("[%s #%d] %s %s\n    %s"):format(
        tag, rec.id, rec.class, rec.path, table.concat(rec.args, " | ")))

    if SS2.onCall then
        pcall(SS2.onCall, rec)
    end
end
SS2.recordCall = recordCall

-- ═══════════ REMOTE HOOKS ═══════════
local function profileFor(r)
    local prof = SS2.remotes[r]
    if not prof then
        prof = {
            path = r.Name,
            class = r.ClassName,
            calls = 0, out = 0, inn = 0,
            hooked = false,
            sigs = {},
            firstSeen = os.date("%H:%M:%S"),
        }
        pcall(function()
            prof.path = r:GetFullName():gsub("Players%." .. P.Name .. "%.", "ME.")
        end)
        SS2.remotes[r] = prof
    end
    return prof
end

local function hookRemote(r)
    local prof = profileFor(r)
    if prof.hooked then return end
    prof.hooked = true

    -- inbound
    if r:IsA("RemoteEvent") then
        pcall(function()
            r.OnClientEvent:Connect(function(...)
                prof.calls = prof.calls + 1
                prof.inn = prof.inn + 1
                recordCall(r, { ... }, "IN")
            end)
        end)
    end

    -- outbound: FireServer
    pcall(function()
        local oldFire
        oldFire = hookfunction(r.FireServer, function(self, ...)
            prof.calls = prof.calls + 1
            prof.out = prof.out + 1
            recordCall(r, { ... }, "OUT")
            return oldFire(self, ...)
        end)
    end)

    -- outbound: InvokeServer
    pcall(function()
        local oldInvoke
        oldInvoke = hookfunction(r.InvokeServer, function(self, ...)
            prof.calls = prof.calls + 1
            prof.out = prof.out + 1
            recordCall(r, { ... }, "OUT")
            return oldInvoke(self, ...)
        end)
    end)
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
    pcall(function()
        obj.Changed:Connect(onChange)
    end)
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

-- ═══════════ BOOT ═══════════
local remoteCount = scanAllRemotes()

journal("BOOT", "suite online in " .. SS2.game)
print("[SS2-core] discovered + hooked " .. remoteCount .. " remotes")
print("[SS2-core] value watcher live | census done | journal started")
print("[SS2-core] engine ready — await draw.lua (UI) + intel tiers")
getgenv().SS2_READY = true
