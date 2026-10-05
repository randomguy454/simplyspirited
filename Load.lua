-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.4 — LOAD.LUA
--  Draw-based universal intelligence suite
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  Chain loader: ENGINE → META NET → CLOSURE → DRAW UI →
--  SURVEILLANCE → UI PLUS → GOVERNOR → STEALTH → ARG FIDELITY →
--  OUTPUT → DECOMPILER → VAULT → VAULT 2
--  13 parts. Required halt cleanly. Optional degrade gracefully.
-- ════════════════════════════════════════════════════════════

print("╔══════════════════════════════════════════╗")
print("║  SIMPLYSPIRITED v2.4 — DRAW EDITION      ║")
print("║  operator: SHADOWMILESC                  ║")
print("╚══════════════════════════════════════════╝")

local REPO = "https://raw.githubusercontent.com/randomguy454/simplyspirited/refs/heads/main/"

local PARTS = {
    { file = "core.lua",         name = "ENGINE",       required = true  },
    { file = "hookmeta.lua",     name = "META NET",     required = false },
    { file = "closure.lua",      name = "CLOSURE",      required = false },
    { file = "draw.lua",         name = "DRAW UI",      required = true  },
    { file = "watch.lua",        name = "SURVEILLANCE", required = false },
    { file = "uiplus.lua",       name = "UI PLUS",      required = false },
    { file = "governor.lua",     name = "GOVERNOR",     required = false },
    { file = "output.lua",       name = "OUTPUT",       required = false },
    { file = "stealth.lua",      name = "STEALTH",      required = false },
    { file = "describe_ext.lua", name = "ARG FIDELITY", required = false },
    { file = "decomp.lua",       name = "DECOMPILER",   required = false },
    { file = "export.lua",       name = "VAULT",        required = false },
    { file = "vault2.lua",       name = "VAULT 2",      required = false },
}

getgenv().SS2 = nil
getgenv().SS2_READY = nil
getgenv().SS2_UI = nil

local loaded, failed = 0, {}
local results = {}

for i, part in ipairs(PARTS) do
    local url = REPO .. part.file .. "?nocache=" .. os.time() .. i
    local src

    local okFetch = pcall(function()
        src = game:HttpGet(url)
    end)

    if not okFetch or type(src) ~= "string" or #src < 10 then
        failed[#failed + 1] = part.name .. " (fetch failed)"
        results[#results + 1] = { name = part.name, ok = false, why = "fetch" }
        warn(("[load] %s: FETCH FAILED%s"):format(part.name,
            part.required and " — REQUIRED, boot halted" or " — skipping (optional)"))
        if part.required then
            warn("[load] cannot continue without " .. part.file)
            return
        end
    else
        local fn, compileErr = loadstring(src)
        if not fn then
            failed[#failed + 1] = part.name .. " (compile: " .. tostring(compileErr) .. ")"
            results[#results + 1] = { name = part.name, ok = false, why = "compile" }
            warn(("[load] %s: COMPILE ERROR: %s"):format(part.name, tostring(compileErr)))
            if part.required then
                warn("[load] cannot continue without " .. part.file)
                return
            end
        else
            local okRun, runErr = pcall(fn)
            if okRun then
                loaded = loaded + 1
                results[#results + 1] = { name = part.name, ok = true }
                print(("[load] %d/%d %s — ONLINE"):format(loaded, #PARTS, part.name))
            else
                failed[#failed + 1] = part.name .. " (runtime: " .. tostring(runErr) .. ")"
                results[#results + 1] = { name = part.name, ok = false, why = "runtime" }
                warn(("[load] %s: RUNTIME ERROR: %s"):format(part.name, tostring(runErr)))
                if part.required then
                    warn("[load] cannot continue without " .. part.file)
                    return
                end
            end
        end
    end
    task.wait(0.1)
end

print("══════════ BOOT REPORT ══════════")
for _, r in ipairs(results) do
    print(("  %-14s %s"):format(r.name, r.ok and "✓ ONLINE" or "✗ " .. (r.why or "failed")))
end
print("═════════════════════════════════")

if #failed == 0 then
    print("[load] ALL SYSTEMS ONLINE — " .. loaded .. "/" .. #PARTS)
elseif loaded > 0 then
    warn("[load] PARTIAL BOOT: " .. loaded .. "/" .. #PARTS .. " | failed: " .. table.concat(failed, "; "))
    warn("[load] suite usable in degraded mode")
else
    warn("[load] TOTAL BOOT FAILURE")
end

local SS2 = getgenv().SS2
if SS2 then
    SS2.sessionStart = os.date()
    SS2.operator = "SHADOWMILESC"
    SS2.displayName = "computerizedcarrier2"
    SS2.version = "2.4"
end
getgenv().SIMPLYSPIRITED_V2 = loaded
