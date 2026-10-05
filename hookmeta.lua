-- ════════════════════════════════════════════════════════════
--  SIMPLYSPIRITED v2.1 — METAMETHOD HOOK (namecall net)
--  For SHADOWMILESC (computerizedcarrier2)
--  ────────────────────────────────────────────────────────────
--  Hooks game.__namecall: catches EVERY FireServer/InvokeServer
--  call in the game, including remotes fetched dynamically at
--  call time that per-remote hooks can miss.
--
--  DEDUP ARCHITECTURE (the important part):
--    • core.lua's per-remote hooks mark profiles hooked = true
--      BEFORE any call passes through them
--    • This net only records when profile is missing OR unhooked
--    • Result: zero double-logging, total coverage
--  Requires executor with hookmetamethod. Degrades gracefully.
-- ════════════════════════════════════════════════════════════

print("[SS2-meta] arming namecall net...")

local SS2 = getgenv().SS2
if not SS2 then
    warn("[SS2-meta] core.lua must load first")
    return
end

local ok, err = pcall(function()
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()

        -- fast reject: only care about remote-ish instances
        if self and typeof(self) == "Instance" then
            local success, class = pcall(function() return self.ClassName end)

            if success and (class == "RemoteEvent" or class == "RemoteFunction") then
                if method == "FireServer" or method == "InvokeServer" then
                    local args = { ... }
                    local prof = SS2.remotes[self]

                    if prof and prof.hooked then
                        -- core.lua's direct hook owns this remote and will
                        -- record the call itself. Pass through untouched.
                    else
                        -- unknown remote OR direct hook never armed:
                        -- the net catches it. Profile first if needed.
                        if not prof then
                            SS2.hookRemote(self)
                            prof = SS2.remotes[self]
                        end
                        if prof then
                            prof.calls = prof.calls + 1
                            prof.out = prof.out + 1
                            prof.metaCaught = (prof.metaCaught or 0) + 1
                            SS2.recordCall(self, args, "OUT")
                        end
                    end
                end
            end
        end

        return oldNamecall(self, ...)
    end)
end)

if ok then
    SS2.metaHooked = true
    print("[SS2-meta] ══ NAMECALL NET ARMED ══")
    print("[SS2-meta] capture coverage: TOTAL — every FireServer/InvokeServer")
    print("[SS2-meta] in this game now passes through the suite.")
else
    SS2.metaHooked = false
    warn("[SS2-meta] hookmetamethod unavailable: " .. tostring(err))
    warn("[SS2-meta] core per-remote hooks remain active (reduced coverage)")
    warn("[SS2-meta] note: net requires hookmetamethod; most executors ship it")
end
