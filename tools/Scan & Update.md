# FAO (fr0z3nUI_AutoOpen) — Scan & Update

This note documents the repeatable workflow for scanning external addons (and this repo) for itemIDs, and updating FAO’s databases without importing obvious false-positives (lockboxes/manual-use items, etc).

Key learnings from the last import pass:
- Parse patterns must allow **whitespace inside brackets** (FAO uses aligned formatting like `ns.exclude[  4632]`).
- External addons often ship both “open” lists and implicit/explicit “don’t open” signals (commented-out allowlist entries, locked-container tables, etc.). Treat those as potential **exclusions**, not whitelist imports.

## What to scan

### 1) Scan *all* of FAO (not just XP01–XP12)
Search across **every Lua file** in `fr0z3nUI_AutoOpen/` for itemIDs and for how FAO treats them.

Key patterns:
- `ns.items[ITEM_ID] = "Name"` → whitelist (auto-open)
- `ns.exclude[ITEM_ID] = { "Name", "Reason" }` → never auto-open
- `ns.timed[ITEM_ID] = { seconds, "Name" }` → openable but delayed / blocked while hatching

Important parsing detail:
- When searching/parsing, always match bracketed IDs with optional spaces: `\[\s*(\d+)\s*\]`.

Notes:
- An item can technically appear in both `ns.items` and `ns.exclude`; FAO blocks opening when excluded, but keep the data clean: **if it’s excluded, don’t keep it whitelisted**.

### 2) Scan external addons — but also scan “what they do” with IDs
When scanning a source addon (e.g. Open‑Sesame, OpenableBeGone), don’t only harvest itemIDs — also capture how the addon treats each ID:
- If the source addon *whitelists* / “open this” → candidate for FAO `ns.items`
- If the source addon *blacklists* / “don’t open” / “manual only” / “locked” → candidate for FAO `ns.exclude`
- If the source addon has a *cooldown/timer/egg hatch* concept → candidate for FAO `ns.timed`

Concrete heuristics that worked well:
- Open‑Sesame: IDs that exist but are **commented out** (e.g. `-- [12345] = true`) should be treated as “source excluded/disabled” and reviewed for FAO `ns.exclude`.
- OpenableBeGone: IDs present in `OpenableBeGoneAllLockedContainerItemIds` are locked containers; they generally belong in FAO `ns.exclude`.

This prevents importing items that the source addon itself avoids (lockboxes, currency bundles, profession-locked containers, etc.).

## Update rules

### A) Never import into whitelist if excluded
Before adding to `ns.items`, always cross-check against:
- `fr0z3nUI_AutoOpenXPXX.lua` (`ns.exclude`)
- `fr0z3nUI_AutoOpenXPTR.lua` (`ns.timed`)

If an ID is excluded or timed, do **not** add it to the whitelist.

Additionally:
- Keep the data clean: don’t leave `ns.items[id]` in an XP file if that same `id` is in `ns.exclude` or `ns.timed`.

### B) Decide destination file
- Whitelist goes into the best-matching expansion file: `fr0z3nUI_AutoOpenXP01.lua` … `fr0z3nUI_AutoOpenXP12.lua`
- Exclusions go into `fr0z3nUI_AutoOpenXPXX.lua`
- Timed items go into `fr0z3nUI_AutoOpenXPTR.lua`

### C) Keep provenance on imports
When importing from another addon, add an inline note:
- `-- from Open-Sesame`
- `-- from OpenableBeGone`

If an ID is added to `ns.exclude` because a source addon avoids it, reflect that in the reason string (e.g. `"Locked - Requires Key"`, `"Manual use only"`, `"Profession Locked"`).

## Fast checks after updating

Run the one-command audit:
- `powershell -ExecutionPolicy Bypass -File .\tools\audit_db.ps1`

1) Ensure no overlap: imported `ns.items[...] -- from ...` must not exist in `ns.exclude`.
2) Ensure `fr0z3nUI_AutoOpenXPXX.lua` contains only `ns.exclude[...]` entries (no stray `ns.items[...]`).
3) Ensure new blocks don’t break file encoding (prefer append-only changes; avoid full-file rewrites when possible).
4) Ensure no overlap: `ns.items[...]` must not exist in `ns.timed` (timed items should live only in `XPTR`).
