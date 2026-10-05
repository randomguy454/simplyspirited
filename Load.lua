-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.0 — LOAD.LUA
--  Draw-based universal intelligence suite
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  Chain loader: core → draw → watch → decomp → export
--  Each part boots independently; failures are named, not fatal
--  Clean-state wipe on every boot — no double hooks ever
-- ════════════════════════════════════════════════════════════

print("╔══════════════════════════════════════════╗")
print("║  SIMPLYSPIRITED v2.0 — DRAW EDITION      ║")
print("║  operator: SHADOWMILESC                  ║")
print("╚══════════════════════════════════════════╝")

-- ═══ CONFIG: point this at your repo ═══
local REPO = "https://raw.githubusercontent.com/randomguy454/luau-telemetryluau-telemetry/refs/heads/main/"

local PARTS = {
    { file = "core.lua",   name = "ENGINE",    required = true  },
    { file = "draw.lua",   name = "DRAW UI",   required = true  },
    { file = "watch.lua",  name = "SURVEILLANCE", required = false },
    { file = "decomp.lua", name = "DECOMPILER", required = false },
    { file = "export.lua", name = "VAULT",     required = false },
}

-- ═══ CLEAN STATE Wipe — kills any previous session ═══
getgenv().SS2 = nil
getgenv().SS2_READY = nil
getgenv().SS2_UI = nil

-- ═══ LOAD SEQUENCE ═══
local loaded, failed = 0, {}
local results = {}

for i, part in ipairs(PARTS) do
    local url = REPO .. part.file .. "?nocache=" .. os.time() .. i
    local src, fetchErr

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
    task.wait(0.1) -- let each part finish its own boot
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
    warn("[load] suite is usable in degraded mode — check failures above")
else
    warn("[load] TOTAL BOOT FAILURE")
end

-- ═══ SESSION FINGERPRINT ═══
local SS2 = getgenv().SS2
if SS2 then
    SS2.sessionStart = os.date()
    SS2.operator = "SHADOWMILESC"
    SS2.displayName = "computerizedcarrier2"
    SS2.version = "2.0"
end
getgenv().SIMPLYSPIRITED_V2 = loaded
