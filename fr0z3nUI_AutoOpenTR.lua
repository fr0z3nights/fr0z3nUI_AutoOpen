local _, ns = ...
ns.timed = ns.items or {} -- Keeping your existing namespace logic

-- [ TIMED REWARDS DATABASE ]
-- Expansion 11: The War Within / Midnight (2026)
-- (Add new 2026 IDs here as they are discovered)

-- Expansion 10: Dragonflight
ns.timed[200830] = { 604800, "Zenet Egg" } -- 7 Days

-- Expansion 09: Shadowlands (Your current list)
ns.timed[187182] = { 259200, "Hatching Corpsefly Egg" } -- 3 Days
ns.timed[184158] = { 259200, "Oozing Necroray Egg" } -- 3 Days
ns.timed[184103] = { 259200, "Cracked Blight-Touched Egg" } -- 3 Days

-- [ Expansion 04: Cataclysm - Timed Items ]
-- Set to the appropriate hatch time (Example: 259200 for 3 days or 0 if immediate)
ns.timed[68384] = { 259200, "Moonkin Egg" }

-- [ Expansion 03: WotLK - Timed Items ]
ns.timed[39883] = { 259200, "Mysterious Egg" } -- 3 Days (2026/Retail standard)
ns.timed[44718] = { 259200, "Ripe Disgusting Jar" } -- 3 Days

-- Legacy Timed Items
ns.timed[153050] = { 432000, "Fel-Spotted Egg" } -- 5 Days (Legion)
ns.timed[94295]  = { 259200, "Primal Egg" } -- 3 Days (MoP)
ns.timed[39878]  = { 259200, "Mysterious Egg" } -- 3 Days (WotLK)
