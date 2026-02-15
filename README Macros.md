
## Housing macros (Saved Locations)

The old Home1/Home2 macro buttons are deprecated/removed.
The old `/fao home1`/`/fao home2` slash commands are also removed.

Current flow:
- Open the FAO window -> Home tab -> Saved Locations -> Create Macro (per entry)
- Or use chat: `/fao hm macro <id>` to print the `/click ...` macro body

# HEARTH Macro

Button Name
HS Hearth -> Create Macro

Created Macro
FAO HS Hearth

Macro Body
/fao hs hearth
/use item:212337

Behind /fao Command
/run local s,d=GetItemCooldown(212337); s=s+d-GetTime(); local n,r=UnitFullName('player'); local ck=(n and r and r~='' and (n..'-'..r)) or ((UnitName('player') or '')..'-'..(GetRealmName() or '')); local root=fr0z3nUI_AutoOpen_UI; local z=root and root.hearth and root.hearth.zoneByChar and root.hearth.zoneByChar[ck] or ''; local b=GetBindLocation() or ''; local to=(z=='' and b) or (b=='' and z) or (b..', '..z); if s>1 then print(format('Hearthing in %d mins to %s', s/60, to)) else print(format('Hearthing to %s', to)) end

Notes: `/use item:212337` line would still need to use the selected toy’s itemID (or 6948 if you want the base Hearthstone).

## FAO HS 06 Garrison

Button Name
HS Garrison

Created Macro
FAO HS Garrison

Macro Body
/fao hs garrison
/use item:110560

Behind /fao Command
/run local s,d=GetItemCooldown(110560); s=s+d-GetTime(); print(format(s>1 and "Hearthing to Garrison in %d mins" or "Hearthing to Garrison", s/60))

## FAO HS 07 Dalaran

Button Name
HS 07 Dalaran

Created Macro
FAO HS 07 Dalaran

Macro Body
/fao hs dalaran
/use item:140192

Behind /fao Command
/run local s,d=GetItemCooldown(140192); s=s+d-GetTime(); print(format(s>1 and "Hearthing to Dalaran in %d mins" or "Hearthing to Dalaran", s/60))

## FAO HS 11 Dornogal

Button Name
HS 11 Dornogal

Created Macro
FAO HS 11 Dornogal

Macro Body
/fao hs dornogal
/use item:243056

Behind /fao Command
/run local s,d=GetItemCooldown(243056); s=s+d-GetTime(); print(format(s>1 and "Portal to Dornogal in %d mins" or "Portal to Dornogal Opening", s/60))

## FAO HS 78 Whistle

Button Name
HS 78 Whistle

Created Macro
FAO HS 78 Whistle

New Macro Body
/fao hs whistle
/use item:230850
/use item:141605
/use item:205255

Behind /fao Command
/run local s,d=GetItemCooldown"230850"s=s+d-GetTime()print(format((s>1 and"Ride to a Delve in %d mins"or"Yay! Off To A Delve"),s/60,s%60))

## FAO HS Instance IO

Button Name
Instance IO

Created Macro
FAO InstanceIO

Current Macro Body
/run LFGTeleport(IsInLFGDungeon())
/run LFGTeleport(IsInLFGDungeon())
/run print("Attempting Dungeon Teleport")

Notes: typically treated as a protected action. A slash command implemented in addon code may be blocked

## FAO HS Instance Reset

Button Name
Instance Reset

Created Macro
FAO InstanceReset

Current Macro Body
/script ResetInstances();

Notes:`ResetInstances()` may be protected/restricted depending on state; safest to keep as a macro.

## FAO HS Rez

Button Name
Rez

Created Macro
FAO Rez

Current Macro Body
/use Ancestral Spirit
/cast Redemption
/cast Resurrection
/cast Resuscitate
/cast Return
/cast Revive
/cast Raise Ally

Notes: Casting spells is a protected action; addons can’t securely choose/cast these spells on-demand.

## FAO HS Rez Combat

Button Name
Rez Combat

Created Macro
FAO Rez Combat

Current Macro Body
/cast Rebirth
/cast Intercession
/cast Raise Ally

Notes: Same protected-action restriction as Rez.

## FAO HS Script Errors

Button Name
Script Errors

Created Macro
FAO ScriptErrors

New Macro Body
/fao scripterrors

Behind /fao Command
/run local k="ScriptErrors"; local v=tonumber(C_CVar.GetCVar(k)) or 0; C_CVar.SetCVar(k, v==1 and 0 or 1); print("ScriptErrors "..(v==1 and "Disabled" or "Enabled"))

