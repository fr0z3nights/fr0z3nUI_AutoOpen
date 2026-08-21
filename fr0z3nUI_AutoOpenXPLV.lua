local _, ns = ...

-- [ LEVEL-LOCKED OPENABLES ]
-- Items that are openable containers, but should not be auto-opened until the character meets a level requirement.
-- Format: ns.levelLocked[itemID] = { requiredLevel, "Display Name" }

ns.levelLocked = ns.levelLocked or {}

-- Expansion 11: The War Within / Midnight
ns.levelLocked[271221] = { 90, "Wriggling Recruit's Field Pouch" }                    -- 2026-06-23 Looted
ns.levelLocked[270987] = { 90, "Recruit's Field Pouch" }                              -- 2026-07-09 Looted
ns.levelLocked[270934] = { 90, "Recruit's Field Pouch" }                              -- 2026-06-15 Looted
ns.levelLocked[270933] = { 90, "Bulging Field Pouch" }                                -- 2026-07-18 Looted
ns.levelLocked[270932] = { 90, "Wriggling Field Pouch" }                              -- 2026-07-11 Looted
ns.levelLocked[270247] = { 90, "Field Satchel" }
ns.levelLocked[270244] = { 90, "Field Pouch" }
ns.levelLocked[228361] = { 80, "Seasoned Adventurer's Cache" }
