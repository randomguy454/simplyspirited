-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.6 — LOAD.LUA
--  SCREENGUI EDITION (universal intelligence suite)
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  Chain loader: ENGINE → META NET → CLOSURE → CALLERS →
--  SCREEN UI → SG PLUS → SURVEILLANCE → UI PLUS → GOVERNOR →
--  OUTPUT → STEALTH → ARG FIDELITY → DECOMPILER → VAULT → VAULT 2
--  v2.6: Drawing UI replaced with ScreenGui (Delta-compatible).
-- ════════════════════════════════════════════════════════════

print("╔══════════════════════════════════════════╗")
print("║  SIMPLYSPIRITED v2.6 — SCREENGUI EDITION ║")
print("║  operator: SHADOWMILESC                  ║")
print("╚══════════════════════════════════════════╝")

-- ═══ CONFIG ═══
local REPO = "https://raw.githubusercontent.com/randomguy454/simplyspirited/refs/heads/main/"

local PARTS = {
    { file = "core.lua",         name = "ENGINE",       required = true  },
    { file = "closure.lua",      name = "CLOSURE",      required = false },
    { file = "callers.lua",      name = "CALLERS",      required = false },
    { file = "watch.lua",        name = "SURVEILLANCE", required = false },
    { file = "ui.lua",           name = "INTERFACE",    required = true  },
    { file = "output.lua",       name = "OUTPUT",       required = false },
    { file = "governor.lua",     name = "GOVERNOR",     required = false },
    { file = "stealth.lua",      name = "STEALTH",      required = false },
    { file = "describe_ext.lua", name = "ARG FIDELITY", required = false },
    { file = "decomp.lua",       name = "DECOMPILER",   required = false },
    { file = "export.lua",       name = "VAULT",        required = false },
    { file = "vault2.lua",       name = "VAULT 2",      required = false },
    { file = "ss_dump.lua",      name = "GAME DUMP",    required = false },
}
-- ═══ CLEAN STATE WIPE ═══
getgenv().SS2 = nil
getgenv().SS2_READY = nil
getgenv().SS2_UI = nil

-- ═══ LOAD SEQUENCE ═══
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

-- ═══ BOOT REPORT ═══
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

-- ═══ SESSION FINGERPRINT ═══
local SS2 = getgenv().SS2
if SS2 then
    SS2.sessionStart = os.date()
    SS2.operator = "SHADOWMILESC"
    SS2.displayName = "computerizedcarrier2"
    SS2.version = "2.6"
end
getgenv().SIMPLYSPIRITED_V2 = loaded
