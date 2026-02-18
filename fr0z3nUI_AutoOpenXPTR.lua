local _, ns = ...
ns.timed = ns.timed or {}

-- [ TIMED REWARDS DATABASE ]
-- Sorted by itemID (descending).
-- Value is hatch time in seconds (e.g. 259200 for 3 days).

ns.timed[200830]  =  { 604800,   "Zenet Egg" }                     -- 7 Days
ns.timed[187182]  =  { 259200,   "Hatching Corpsefly Egg" }        -- 3 Days
ns.timed[184158]  =  { 259200,   "Oozing Necroray Egg" }           -- 3 Days
ns.timed[184103]  =  { 259200,   "Cracked Blight-Touched Egg" }    -- 3 Days
ns.timed[153050]  =  { 432000,   "Fel-Spotted Egg" }               -- 5 Days
ns.timed[ 94295]  =  { 259200,   "Primal Egg" }                    -- 3 Days
ns.timed[ 68384]  =  { 259200,   "Moonkin Egg" }                   -- 3 Days
ns.timed[ 44718]  =  { 259200,   "Ripe Disgusting Jar" }           -- 3 Days
ns.timed[ 39883]  =  { 259200,   "Mysterious Egg" }                -- 3 Days
ns.timed[ 39878]  =  { 259200,   "Mysterious Egg" }                -- 3 Days

