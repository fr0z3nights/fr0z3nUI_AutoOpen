local _, ns = ...

-- [ LEVEL-LOCKED OPENABLES ]
-- Items that are openable containers, but should not be auto-opened until the character meets a level requirement.
-- Format: ns.levelLocked[itemID] = { requiredLevel, "Display Name" }

ns.levelLocked = ns.levelLocked or {}

-- Expansion 11: The War Within / Midnight
ns.levelLocked[228361] = { 80, "Seasoned Adventurer's Cache" }
