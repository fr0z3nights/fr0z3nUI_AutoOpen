# FAO (fr0z3nUI_AutoOpen) — Scan & Update

This note documents the repeatable workflow for scanning external addons (and this repo) for itemIDs, and updating FAO’s databases using a **review-first, non-destructive** approach.

Policy:
- Scanners and audits should **only generate reports and candidate blocks**.
- Do **not** remove/move items based on “judgement calls” (e.g. “this looks like gear” or “another addon doesn’t open it”). If something looks suspicious, **flag it** and let you decide.
- Only you decide what’s “wrong”. Neither scripts nor the assistant should auto-move IDs into `ns.exclude`/`ns.timed`; they can only surface candidates for your manual edit.

Definitions:
- **Duplicate** = the same itemID appears more than once anywhere in FAO’s databases (regardless of provenance).
- **Wrong/undesired to auto-open** ≠ “delete it”. If you decide FAO should not auto-open an item, keep the ID present by putting it in `ns.exclude[...]` (or `ns.timed[...]`) so it stays in the known-union and won’t keep resurfacing as “missing” in future scans.

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

Rule:
- Only move/add IDs into `ns.exclude[...]` when the **source addon explicitly signals exclusion** (blacklist/manual-only/locked/commented-out allow, etc.). Do not exclude items just because they “seem wrong”.

Review rule (source excludes vs FAO whitelist):
- If an itemID is present in FAO (`ns.items[...]`) and **FAO does not exclude it**, but a source addon explicitly marks it as excluded/locked/manual-only, keep it in FAO (do not delete). For visibility, you can **manually move** that `ns.items[...]` line to the bottom of the same file under a “REVIEW” header so it’s easy to audit.

Concrete signals that can be useful during review:
- Open‑Sesame: IDs that exist but are **commented out** (e.g. `-- [12345] = true`) indicate the source addon chose not to open them by default. Treat as a *review signal*; do not auto-move/remove anything.
- OpenableBeGone: IDs present in `OpenableBeGoneAllLockedContainerItemIds` are locked containers in that addon’s model. This is often a good *exclude candidate*, but still requires review.

This prevents importing items that the source addon itself avoids (lockboxes, currency bundles, profession-locked containers, etc.).

### 3) Use the AutoOpenContainers scanner (automation)
There is a repeatable scanner script that diffs AutoOpenContainers’ `Data.OPENABLE`/`Data.LOCKED` against **known IDs**.

Script:
- `AddonDev\tools\scan_autoopencontainers.ps1`

Run it from inside `fr0z3nUI_AutoOpen/`:
- FAO-only known-union (fast): `powershell -ExecutionPolicy Bypass -File ..\tools\scan_autoopencontainers.ps1`
- Known-union across **all addons** under AddonDev (use this when you want “it’s already in my addon(s)” coverage): `powershell -ExecutionPolicy Bypass -File ..\tools\scan_autoopencontainers.ps1 -ScanAllAddons`

Outputs (written to `AddonDev\reports\`):
- `aoc-scan-latest.md` (missing counts + lists)
- `aoc-import-blocks-latest.md` (copy/paste candidate blocks)
- `aoc-duplicates-latest.md` (flags `-- from AutoOpenContainers` lines for review when an ID appears multiple times or alongside non-AOC entries)

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
