# fr0z3nUI_AutoOpen — Changelog

Format: `YYYY.MM.DD.NN` (TOC `## Version`) — short summary. Newest at the top.

Discipline: bump TOC `## Version` on every behavior/UI change (sanity check stays meaningful).

# 2026.03.24.01
- Files: `fr0z3nUI_AutoOpenToggles.lua`, `fr0z3nUI_AutoOpen.lua`, `fr0z3nUI_AutoOpen.toc`, `fr0z3nUI_AutoOpenXP12.lua`, `fr0z3nUI_AutoOpenXPXX.lua`
- Toggles/UI: removed the `NPC Name` control (moved to GameOptions `/fgo` Switches tab).
- CVars: FAO no longer applies the friendly NPC nameplates CVar when `fr0z3nUI_GameOptions` is loaded (prevents the two addons from fighting over `nameplateShowFriendlyNPCs`).
- Auto-open list: moved the Primalist gear tokens into the exclude list so FAO doesn't try to open them.

# 2026.03.17.05
- Files: `fr0z3nUI_AutoOpen.lua`, `fr0z3nUI_AutoOpen.toc`
- Chat: added the selected class-specific kick-open lines (Rogue/Warrior/Mage/Hunter/Priest/Shaman/Druid/Warlock/DH/Monk/DK), with the output text not including any "(… only)" markers.

# 2026.03.17.04
- Files: `fr0z3nUI_AutoOpen.lua`, `fr0z3nUI_AutoOpen.toc`
- Chat: removed parenthetical text from the random kick-open lines (no more `(...)` in the output).

# 2026.03.17.03
- Files: `fr0z3nUI_AutoOpen.lua`, `fr0z3nUI_AutoOpen.toc`
- Chat: corrected formatting so only the `kick` open message uses the random `<Item> opened with ...` line; normal auto-open prints remain just the clean item hyperlink.

# 2026.03.17.02
- Files: `fr0z3nUI_AutoOpen.lua`, `fr0z3nUI_AutoOpen.toc`
- Chat: auto-open and kick-open prints now use the format `<Item> opened with ...` (random WoW-themed lines; Paladin/Void Elf gated lines included).

# 2026.03.17.01
- Files: `fr0z3nUI_AutoOpen.lua`, `fr0z3nUI_AutoOpen.toc`
- Chat: removed the word `Opening` from the auto-open print.
- Chat: item hyperlinks now display without `[...]` brackets (still clickable), matching LootIt style.

# 2026.03.01.01
- Added `/fao status` (and `/fao stat`) to print AutoOpen state and list counts.
- Added `SANITY_VERSION` to the slash-status output for quick sanity checks.
