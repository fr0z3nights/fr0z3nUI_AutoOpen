# fr0z3nUI AutoOpen - AI Agent Guidelines

## Architecture Overview

This WoW addon automatically opens containers (bags, caches, lockboxes) matching expansion-specific item whitelists. The codebase separates concerns into **database modules** and **engine logic**:

- **fr0z3nUI_AutoOpen.lua**: Core scan engine with event handling, saved variable initialization, timer tracking, and tooltip integration
- **Database modules** (fr0z3nUI_AutoOpenXX.lua, TRZ.lua, 12.lua-01.lua): Namespace tables for exclusions, timed items, and whitelisted IDs per expansion
- **Namespace (ns)**: Global table shared across modules to store `ns.items`, `ns.exclude`, `ns.timed`

Load order in `fr0z3nUI_AutoOpen.toc` is **database-first** (XX down to 01), then engine last.

## Key Data Structures & Patterns

### Item Whitelist (`ns.items`)
Defined per-expansion database file. Maps item ID to name (user-friendly label). Example:
```lua
ns.items = ns.items or {}
ns.items[12345] = "My Container Name"
```

### Exclusion Database (`ns.exclude`)
Maps item IDs to metadata tuples: `{ "Display Name", "Reason" }`. Prevents auto-opening of locked boxes, level-gated caches, and manual-only items. Located in `fr0z3nUI_AutoOpenXX.lua`.

### Timed Items (`ns.timed`)
Maps item ID to `{ duration_seconds, "Display Name" }` for eggs/hatching items. Tracks hatch time in `fr0z3nUI_AutoOpenTR.lua`. Example: `ns.timed[200830] = { 604800, "Zenet Egg" }` (7 days).

### Saved Variables
- `fr0z3nUI_AutoOpen_Acc`: Account-wide custom whitelist (user-added items)
- `fr0z3nUI_AutoOpen_Char`: Per-character custom whitelist
- `fr0z3nUI_AutoOpen_Settings`: Addon settings; `disabled` table tracks user-disabled items
- `fr0z3nUI_AutoOpen_Timers`: Maps `"bag-slot"` keys to `{ id, startTime }` for hatching eggs

## Core Scan Logic

The `RunScan()` function (in `fr0z3nUI_AutoOpen.lua`) iterates bags 0-4, checking each slot:

1. **Timer Check**: If item is in `ns.timed`, verify hatch time hasn't elapsed; skip if still hatching
2. **Whitelist Check**: Accept items from `ns.items` (global), `fr0z3nUI_AutoOpen_Acc` (account), or `fr0z3nUI_AutoOpen_Char` (character)
3. **Exclusion Filter**: Skip if ID is in `ns.exclude` or user-disabled
4. **Loot Check**: Verify `info.hasLoot` and `not info.isLocked` before opening
5. **Cooldown**: Enforces 1.5s delay between opens to prevent spam

Scan triggers on `BAG_UPDATE_DELAYED`, `PLAYER_REGEN_ENABLED` (combat exit), and login recovery.

## Developer Patterns

### Adding Items to Expansion Database
1. Determine WoW expansion (e.g., Expansion 10 = Dragonflight)
2. Open corresponding `fr0z3nUI_AutoOpen{NN}.lua` (NN = expansion number)
3. Add to `ns.items` table: `ns.items[ITEM_ID] = "Display Name"`
4. If excluded, add reasoning to `fr0z3nUI_AutoOpenXX.lua` instead

### Adding Timed Items
Update `fr0z3nUI_AutoOpenTR.lua`:
```lua
ns.timed[ITEM_ID] = { duration_in_seconds, "Egg/Hatch Name" }
-- Example: 3 days = 259200, 7 days = 604800
```

### Event Flow
All events route through `OnEvent` handler. Key event pairs prevent opening at banks/mail:
- `BANKFRAME_OPENED/CLOSED` → sets `atBank` flag
- `MAIL_SHOW/MAIL_CLOSED` → clears flags (note: uses `find("CLOSED")` for both)

### Tooltip Integration
Uses `TooltipDataProcessor.AddTooltipPostCall()` to display countdown timers on item hover. Displays `"Hatching In: Xd Xh Xm"` for timed items.

## Critical Behavioral Rules

- **No opening in combat**: Guarded by `InCombatLockdown()`
- **No opening during loot**: `C_Loot.IsLootOpen()` check
- **No opening at banks/merchants**: Set during event handling
- **Excluded items never open**: Check `ns.exclude` before any open attempt
- **Timer disruption detection**: Warns if hatching item moved to different slot
- **Cooldown enforcement**: 1.5 second minimum between any two opens (prevents race conditions)

## Localization & Output
All messages use the color `|cff00ccff` (cyan prefix) for addon identification: `[FAO]` stands for "Frozen Auto Open". Use `print()` for user-facing messages; chain format strings with `string.format()` for time calculations.

## Testing Considerations
- Verify scan works post-login by checking `CheckTimersOnLogin()` output
- Test exclusions by adding item to `ns.exclude` and confirming no auto-open attempt
- Validate cooldown by rapidly acquiring matching containers; should see 1.5s delays
- Check timer display on tooltip hover; verify countdown decrements on subsequent hovers
