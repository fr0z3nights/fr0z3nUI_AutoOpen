# fr0z3nUI_AutoOpen — Changelog

Format: `YYYY.MM.DD.NN` (TOC `## Version`) — short summary. Newest at the top.

Discipline: bump TOC `## Version` on every behavior/UI change (sanity check stays meaningful).

## 2026.10.20.08
- Files: `fr0z3nUI_AutoOpen.lua`, `fr0z3nUI_AutoOpenToggles.lua`, `fr0z3nUI_AutoOpen.toc`, `README.md`, `README Changelog.md`.
- Make Button Show/Hide account-wide, displaying Show ACC/Hide ACC. Seed the account preference from the first loaded character's previous setting, without overwriting an existing account choice; clear legacy character preferences. Position remains per character and hidden macro use is unchanged.

## 2026.10.20.07
- Files: `fr0z3nUI_AutoOpen.lua`, `fr0z3nUI_AutoOpenToggles.lua`, `fr0z3nUI_AutoOpen.toc`, `README.md`, `README Changelog.md`.
- Add per-character Button Show/Hide control to Toggles, defaulting to Show. Hiding preserves scanning and the secure item target for `/click FAOButton`; visibility changes defer during combat.

## 2026.10.20.06
- Files: `fr0z3nUI_AutoOpenXPXB.lua` (renamed from `fr0z3nUI_AutoOpenXPBT.lua`), `fr0z3nUI_AutoOpen.toc`, `README.md`, `README Changelog.md`.
- Rename the button item database from XPBT to XPXB and update its load entry and documentation; behavior unchanged.

## 2026.10.20.05
- Files: `fr0z3nUI_AutoOpen.lua`, `fr0z3nUI_AutoOpenUI.lua`, `fr0z3nUI_AutoOpen.toc`, `README.md`, `README Changelog.md`.
- Rename BT status from `Manual Open:` to `Button:` in item tooltips, the item-ID panel, and custom-add feedback.

## 2026.10.20.04
- Files: `fr0z3nUI_AutoOpenXPBT.lua`, `fr0z3nUI_AutoOpen.lua`, `fr0z3nUI_AutoOpenUI.lua`, `fr0z3nUI_AutoOpen.toc`, `README.md`, `README Changelog.md`.
- Standardize BT entries as name/reason tables like XX. Show `Manual Open: Reason` in item tooltips and the item-ID panel, taking precedence over overlapping exclusions, and prevent adding button-only items to custom auto-open lists. Preserve manual button selection and opening.

## 2026.10.20.03
- Files: `fr0z3nUI_AutoOpenXPBT.lua`, `fr0z3nUI_AutoOpen.lua`, `fr0z3nUI_AutoOpen.toc`, `README.md`, `README Changelog.md`.
- Move manual-open button runtime logic into the main AutoOpen engine, leaving XPBT as an item database only. Preserve secure button name, scanning, position storage, and click behavior.

## 2026.10.20.02
- Files: `fr0z3nUI_AutoOpenXPBT.lua`, `fr0z3nUI_AutoOpen.toc`, `README.md`, `README Changelog.md`.
- Shorten the secure manual-open button name to `FAOButton`, allowing `/click FAOButton` in action-bar macros.

## 2026.10.20.01
- Files: `fr0z3nUI_AutoOpenXPBT.lua`, `fr0z3nUI_AutoOpen.lua`, `fr0z3nUI_AutoOpen.toc`, `README.md`, `README Changelog.md`.
- Add standalone secure click-to-open button for `ns.button` items, starting with Handful of Treats (37586). Show only while a listed item is carried; left-click to open one, right-drag to move, save position per character, and hide in combat. Button-only entries are excluded from automatic opening even if also custom-whitelisted.

## 2026.10.03.03
- Files: `fr0z3nUI_AutoOpen.lua`, `README Changelog.md`, `fr0z3nUI_AutoOpen.toc`
- Talents: auto-open no longer closes the talent window when it is already open.

## 2026.10.03.02
- Files: `fr0z3nUI_AutoOpen.lua`, `README Changelog.md`, `fr0z3nUI_AutoOpen.toc`
- Talents: also run the talent check about 1 second after a taxi flight starts.

## 2026.10.03.01
- Files: `fr0z3nUI_AutoOpen.lua`, `README Changelog.md`, `fr0z3nUI_AutoOpen.toc`
- Talents: a talent check that lands in combat is now skipped instead of re-running after combat ends.

## 2026.09.10.01
- Files: `fr0z3nUI_AutoOpen.lua`, `fr0z3nUI_AutoOpen.toc`
- Talents: delayed the automatic talent check after entering the world from 2 seconds to 45 seconds.
    - Takes pressure off load and allows other addons like Zyogr's Talent UI to load in first.


## 2026.08.24.01
- Files: `fr0z3nUI_AutoOpen.lua`, `fr0z3nUI_AutoOpenToggles.lua`, `fr0z3nUI_AutoOpenUI.lua`, `fr0z3nUI_AutoOpen.toc`
- CVars: removed FAO's legacy friendly NPC nameplates enforcement so it no longer changes `nameplateShowFriendlyNPCs` during login or world transitions. This setting is owned by GameOptions.

## 2026.04.11.01
- Files: `fr0z3nUI_AutoOpenXPXX.lua`, `fr0z3nUI_AutoOpen.toc`
- Auto-open list: exclude `Brightly Colored Egg` (`45072`) from auto-open.
- Auto-open list: normalize some excluded gear-token entries to include a consistent reason payload.

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
