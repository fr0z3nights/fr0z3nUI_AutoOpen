# fr0z3nUI AutoOpen

Automatically opens whitelisted containers (bags/caches/lockboxes, etc.) based on expansion-specific databases.

## Install
1. Copy the folder `fr0z3nUI_AutoOpen` into:
	- `World of Warcraft/_retail_/Interface/AddOns/`
2. Launch WoW and enable the addon.

## Slash Commands
- `/fao` or `/frozenautoopen` — open/toggle the options window
- `/fao <itemID>` — open window and prefill the item ID
- `/fao ?` or `/fao help` — print help
- `/fao kick` — manually kick a scan (uses normal safety guards)

### Auto-open
- `/fao on|off` — shorthand toggle for auto-opening containers
- `/fao ao on|off|toggle` — auto-open containers
- `/fao cache [seconds]` — temporarily pauses auto-open (clamped 2–10s)
- `/fao cd <seconds>` — set open cooldown (normalized to 0–10)

### Auto Loot on login
- `/fao autoloot [on|off|acc|toggle|status]` — controls “force Auto Loot ON” behavior

### Great Vault
- `/fao gv` — cycle Great Vault auto-open OFF/ON/ACC
- `/fao gv on|off|acc` — explicit mode
- `/fao gv try` — queue an attempt now
- `/fao gv debug` — prints Great Vault state details

### Talents reminder
- `/fao talents` — prints status + help
- `/fao talents toggle` — cycle OFF/ON/ACC
- `/fao talents ui off|on|acc` — set mode
- `/fao talents check` — run a check now

### Debug
- `/fao debug talents [on|off|toggle|status]`
- `/fao debug gv [on|off|toggle|status]`

## SavedVariables
- Account: `fr0z3nUI_AutoOpen_Acc`, `fr0z3nUI_AutoOpen_Settings`, `fr0z3nUI_AutoOpen_Timers`, `fr0z3nUI_AutoOpen_UI`
- Character: `fr0z3nUI_AutoOpen_Char`, `fr0z3nUI_AutoOpen_CharSettings`

## Notes
- Respects common safety guards (combat lockdown, loot window open, banking/mail/merchant contexts, etc.).
- Database files load first (per-expansion lists), then the scan engine in `fr0z3nUI_AutoOpen.lua`.







