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

## Manual open button

`fr0z3nUI_AutoOpenXPXB.lua` lists items requiring a manual click using `ns.button[itemID] = { "Item name", "Reason" }`, matching the exclusion database's name/reason format. Item tooltips and the item-ID panel display `Button: Reason`; manual entries take display priority over overlapping exclusions and cannot be added to the custom auto-open whitelist. Entries include Handful of Treats (37586) and Rattling Bag o'Gold (268297).
The database contains item entries only; button creation, bag scanning, movement, and event handling live in `fr0z3nUI_AutoOpen.lua`.

A standalone item-icon button appears while a listed item is in your bags. Left-click to open one item per real click; right-drag to move the button. Position is saved per character. It hides when none remain and during combat, refreshing after combat ends. The icon shows the total carried count. With multiple listed item types, it keeps the current type until depleted, then selects the lowest item ID.

Use this action-bar macro to activate the secure button with a keypress:

```text
/click FAOButton
```

The Toggles tab's **Button** control switches **Show ACC/Hide ACC**, saved account-wide and defaulting to Show. On migration, the first character loaded supplies its previous preference if no account preference exists. Hide only hides the button: bag scanning and its secure item target remain active, so `/click FAOButton` still works. Visibility changes made during combat apply after combat. Button position remains per character.

When no listed items remain, the item target is cleared and the macro has nothing to use. Each press opens at most one item.

Button entries never enter the automatic opening path, including custom whitelist entries. The manual button is independent of the auto-open toggle. Blizzard's normal item-use restrictions still apply; this does not automatically click, open all items at once, or bypass restrictions.

## SavedVariables
- Account: `fr0z3nUI_AutoOpen_Acc`, `fr0z3nUI_AutoOpen_Settings`, `fr0z3nUI_AutoOpen_Timers`, `fr0z3nUI_AutoOpen_UI`
- Character: `fr0z3nUI_AutoOpen_Char`, `fr0z3nUI_AutoOpen_CharSettings`

## Notes
- Respects common safety guards (combat lockdown, loot window open, banking/mail/merchant contexts, etc.).
- Database files load first (per-expansion lists), then the scan engine in `fr0z3nUI_AutoOpen.lua`.
