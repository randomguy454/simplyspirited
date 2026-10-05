-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.4 — OUTPUT MANAGER
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  verbosity: quiet | smart | loud  (default: smart)
--  smart = first contact with each remote + keyword-flagged calls
--  F9 stays readable. Everything still captured to SS2.log always.
-- ════════════════════════════════════════════════════════════

print("[SS2-out] loading output manager...")

local SS2 = getgenv().SS2
if not SS2 then warn("[SS2-out] core must load first") return end

SS2.verbosity = SS2.verbosity or "smart"

local INTERESTING = {
    "buy", "purchase", "cash", "coin", "gold", "gem", "money",
    "damage", "hit", "attack", "kill", "death", "reward", "claim",
    "spawn", "craft", "sell", "trade", "level", "xp", "win",
    "data", "save", "auth", "key", "remote",
}

SS2._isInteresting = function(rec)
    local hay = (rec.name .. " " .. table.concat(rec.args, " ")):lower()
    for _, kw in ipairs(INTERESTING) do
        if hay:find(kw, 1, true) then return true end
    end
    return false
end

function SS2.setVerbosity(level)
    if level == "quiet" or level == "smart" or level == "loud" then
        SS2.verbosity = level
        print("[out] verbosity: " .. level)
    else
        print("[out] invalid — use quiet / smart / loud")
    end
end

print("[SS2-out] LIVE — verbosity: " .. SS2.verbosity)
print("[out] SS2.setVerbosity('quiet' | 'smart' | 'loud')")
