local _, ns = ...
ns.peekOnly = ns.peekOnly or {}

-- [ Peek-Only Containers ]         /script print(C_QuestLog.IsQuestFlaggedCompleted(QUESTID))
-- These items are opened in "peek" mode: print contents, close loot, take nothing.

--  ns.peekOnly[117394] = { name = "Satchel of Chilled Goods" }
--  ns.peekOnly[117394] = { questID = 83134, name = "Satchel of Chilled Goods" }  -- Cheese Was Hotfixed

ns.peekOnly[209025] = { name = "Loot-Filled Pumpkin" }                             -- OpenableBeGone
ns.peekOnly[209024] = { name = "Loot-Filled Pumpkin" }
ns.peekOnly[209020] = { name = "Loot-Filled Pumpkin" }                             -- OpenableBeGone
ns.peekOnly[243347] = { name = "Keg of Curiosities" }