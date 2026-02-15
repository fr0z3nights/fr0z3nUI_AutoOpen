local _, ns = ...
ns.timed = ns.timed or {}

-- [ TIMED REWARDS DATABASE ]
-- Set to the appropriate hatch time (Example: 259200 for 3 days or 0 if immediate)

-- Expansion 10: Dragonflight
ns.timed[200830]  =  { 604800,   "Zenet Egg" }  -- 7 Days

ns.timed[187182]  =  { 259200,   "Hatching Corpsefly Egg" }  -- 3 Days
ns.timed[184158]  =  { 259200,   "Oozing Necroray Egg" }  -- 3 Days
ns.timed[184103]  =  { 259200,   "Cracked Blight-Touched Egg" }  -- 3 Days

-- Expansion 07: Legion
ns.timed[153050]  =  { 432000,   "Fel-Spotted Egg" } -- 5 Days

-- 05 Mists of Pandaria
ns.timed[ 94295]  =  { 259200,   "Primal Egg" }  -- 3 Days

-- 04 Cataclysm
ns.timed[ 68384]  =  { 259200,   "Moonkin Egg" } -- 3 Days

-- 03 WotLK
ns.timed[ 39883]  =  { 259200,   "Mysterious Egg" }  -- 3 Days
ns.timed[ 44718]  =  { 259200,   "Ripe Disgusting Jar" }  -- 3 Days
ns.timed[ 39878]  =  { 259200,   "Mysterious Egg" }  -- 3 Days