local _, ns = ...
ns.peekOnly = ns.peekOnly or {}

-- [ Peek-Only Containers ]         /script print(C_QuestLog.IsQuestFlaggedCompleted(QUESTID))
-- These items are opened in "peek" mode: print contents, close loot, take nothing.
ns.peekOnly[117394] = { questID = 83134, name = "Satchel of Chilled Goods" }
