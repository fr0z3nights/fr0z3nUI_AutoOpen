local _, ns = ...

-- Macro helpers (non-UI). Split out of Hearth module.

local PREFIX = "|cff00ccff[FAO]|r "
local function Print(msg)
    print(PREFIX .. tostring(msg or ""))
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

local function GetHearthDB()
    if ns and ns.Hearth and type(ns.Hearth.EnsureInit) == "function" then
        return ns.Hearth.EnsureInit()
    end

    -- Fallback (should not normally happen): mimic Hearth module storage.
    _G.fr0z3nUI_AutoOpen_UI = _G.fr0z3nUI_AutoOpen_UI or {}
    local root = _G.fr0z3nUI_AutoOpen_UI
    root.hearth = root.hearth or {}
    root.hearth.window = root.hearth.window or { tab = "hearth", macroPerChar = false }
    return root.hearth, ""
end

local function GetMacroPerCharSetting()
    local db = GetHearthDB()
    local w = (db and db.window) or {}
    return w.macroPerChar and true or false
end

local function SetMacroPerCharSetting(perChar)
    local db = GetHearthDB()
    db.window = db.window or {}
    db.window.macroPerChar = perChar and true or false
end

local MAX_MACRO_CHARS = 255

local BUILTIN_SHOWTOOLTIP_NAME = "#showtooltip (25)"
-- 25 chars including the newline when injected: '#showtooltip item:0000000' (24) + '\n' (1)
-- The 'item:0000000' token is intended to be replaced by the first /use'd item in the macro.
local BUILTIN_SHOWTOOLTIP_TEXT = "#showtooltip item:0000000"
local BUILTIN_SAFARI_NAME = "Safari Hat"
local BUILTIN_SAFARI_TEXT = "/cancelaura Safari Hat"

local function EnsureOptionalEntryAt(opt, name, text, index)
    if type(opt) ~= "table" then
        return
    end

    opt.entries = opt.entries or {}
    local entries = opt.entries

    local foundIndex
    for i = 1, #entries do
        local e = entries[i]
        if type(e) == "table" and e.name == name then
            foundIndex = i
            break
        end
    end

    if foundIndex then
        entries[foundIndex].text = text
        if type(index) == "number" and index >= 1 and index <= #entries and foundIndex ~= index then
            local e = table.remove(entries, foundIndex)
            table.insert(entries, index, e)
        end
        return
    end

    local newEntry = { name = name, text = text }
    if type(index) == "number" and index >= 1 and index <= (#entries + 1) then
        table.insert(entries, index, newEntry)
    else
        entries[#entries + 1] = newEntry
    end
end

local function GetMacroOptionalDB()
    local db = GetHearthDB()
    db.window = db.window or {}
    db.window.optionalMacro = db.window.optionalMacro or {}
    local opt = db.window.optionalMacro

    -- Migration from older schema.
    if opt.entries == nil then
        opt.entries = {}
    end
    if opt.selected == nil then
        opt.selected = {}
    end

    if opt.enabled ~= nil or opt.cancelSafariHat ~= nil or opt.custom ~= nil then
        local hadEnabled = opt.enabled and true or false
        if opt.cancelSafariHat then
            opt.entries[#opt.entries + 1] = { name = BUILTIN_SAFARI_NAME, text = BUILTIN_SAFARI_TEXT }
            if hadEnabled then opt.selected[BUILTIN_SAFARI_NAME] = true end
        end
        if type(opt.custom) == "string" and opt.custom ~= "" then
            opt.entries[#opt.entries + 1] = { name = "Custom", text = opt.custom }
            if hadEnabled then opt.selected["Custom"] = true end
        end
        opt.enabled = nil
        opt.cancelSafariHat = nil
        opt.custom = nil
    end

    -- Ensure built-ins exist and appear first.
    EnsureOptionalEntryAt(opt, BUILTIN_SHOWTOOLTIP_NAME, BUILTIN_SHOWTOOLTIP_TEXT, 1)
    EnsureOptionalEntryAt(opt, BUILTIN_SAFARI_NAME, BUILTIN_SAFARI_TEXT, 2)

    return opt
end

local function SplitLines(s)
    local out = {}
    if type(s) ~= "string" or s == "" then
        return out
    end
    s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
    for line in s:gmatch("[^\n]+") do
        local trimmed = tostring(line):gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then
            out[#out + 1] = trimmed
        end
    end
    return out
end

local function NormalizeName(name)
    name = tostring(name or "")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    return name
end

local function AddOrUpdateOptionalEntry(name, text)
    local opt = GetMacroOptionalDB()
    name = NormalizeName(name)
    if name == "" then
        return false, "Missing name"
    end
    text = tostring(text or "")

    local entries = opt.entries or {}
    for i = 1, #entries do
        local e = entries[i]
        if type(e) == "table" and e.name == name then
            e.text = text
            return true
        end
    end

    entries[#entries + 1] = { name = name, text = text }
    opt.entries = entries
    return true
end

local function ToggleOptionalEntry(name)
    local opt = GetMacroOptionalDB()
    name = NormalizeName(name)
    if name == "" then
        return
    end
    opt.selected = opt.selected or {}
    opt.selected[name] = not (opt.selected[name] and true or false)
end

local function IsOptionalEntrySelected(name)
    local opt = GetMacroOptionalDB()
    name = NormalizeName(name)
    return (opt.selected and opt.selected[name]) and true or false
end

local function GetOptionalEntries()
    local opt = GetMacroOptionalDB()
    return opt.entries or {}
end

local function GetOptionalMacroLines()
    local opt = GetMacroOptionalDB()
    local lines = {}

    local entries = opt.entries or {}
    local selected = opt.selected or {}
    for i = 1, #entries do
        local e = entries[i]
        local name = type(e) == "table" and e.name or nil
        local text = type(e) == "table" and e.text or nil
        if name and selected[name] then
            local entryLines = SplitLines(text)
            for j = 1, #entryLines do
                lines[#lines + 1] = entryLines[j]
            end
        end
    end

    return lines
end

local function FindFirstUseItemID(body)
    if type(body) ~= "string" then
        return nil
    end
    body = body:gsub("\r\n", "\n"):gsub("\r", "\n")
    local id = body:match("/use[^\n]*item:(%d+)")
    return tonumber(id)
end

local function ReplaceShowtooltipItemPlaceholder(body)
    if type(body) ~= "string" or body == "" then
        return body
    end

    -- Only act on a showtooltip line that uses an all-zero item placeholder.
    if not body:match("^#showtooltip%s+item:0+") then
        return body
    end

    local firstUseID = FindFirstUseItemID(body)
    if not firstUseID then
        return body
    end

    local lines = {}
    body = body:gsub("\r\n", "\n"):gsub("\r", "\n")
    for line in body:gmatch("[^\n]*\n?") do
        if line == "" then break end
        local ln = line:gsub("\n$", "")
        if ln:match("^#showtooltip%s+item:0+") then
            ln = ln:gsub("item:0+", "item:" .. tostring(firstUseID), 1)
        end
        lines[#lines + 1] = ln
    end
    return table.concat(lines, "\n")
end

local function FinalizeMacroBody(body)
    -- Keep placeholder during counting; replace only when writing.
    return ReplaceShowtooltipItemPlaceholder(body)
end

local function ApplyOptionalLines(body)
    if type(body) ~= "string" or body == "" then
        return body
    end

    body = body:gsub("\r\n", "\n"):gsub("\r", "\n")

    local lines = GetOptionalMacroLines()
    if #lines == 0 then
        return body
    end

    local tooltipLine
    local otherLines = {}
    for i = 1, #lines do
        local ln = lines[i]
        if not tooltipLine and type(ln) == "string" and ln:match("^#showtooltip") then
            tooltipLine = ln
        else
            otherLines[#otherLines + 1] = ln
        end
    end

    if tooltipLine then
        local first, rest = body:match("^(#[^\n]*showtooltip[^\n]*)(\n.*)$")
        if first then
            body = tooltipLine .. (rest or "")
        else
            body = tooltipLine .. "\n" .. body
        end
    end

    if #otherLines == 0 then
        return body
    end

    local first, rest = body:match("^(#[^\n]*showtooltip[^\n]*)(\n.*)$")
    if first then
        return first .. "\n" .. table.concat(otherLines, "\n") .. (rest or "")
    end

    return table.concat(otherLines, "\n") .. "\n" .. body
end

local function MacroWithinLimit(body)
    if type(body) ~= "string" then
        return false, "Invalid macro"
    end
    if #body > MAX_MACRO_CHARS then
        return false, "Macro too long"
    end
    return true
end

local function EnsureMacro(name, body, perCharacter)
    if InCombat() then
        return false, "Can't create macros in combat"
    end
    if not (GetMacroIndexByName and CreateMacro and EditMacro) then
        return false, "Macro API unavailable"
    end
    if type(body) ~= "string" or body == "" then
        return false, "Empty macro body"
    end

    body = ApplyOptionalLines(body)
    local okLen, whyLen = MacroWithinLimit(body)
    if not okLen then
        return false, whyLen or "Macro too long"
    end

    body = FinalizeMacroBody(body)
    okLen, whyLen = MacroWithinLimit(body)
    if not okLen then
        return false, whyLen or "Macro too long"
    end

    local idx = GetMacroIndexByName(name)
    if idx and idx > 0 then
        EditMacro(idx, name, nil, body)
        return true
    end

    local iconTexture = 134400
    local created = CreateMacro(name, iconTexture, body, perCharacter and true or false)
    if created then
        return true
    end

    return false, "CreateMacro failed (macro limit?)"
end

local function CreateOrUpdateNamedMacro(name, body, perCharacter)
    if InCombat() then
        Print("Can't create macros in combat.")
        return
    end
    if type(GetMacroIndexByName) ~= "function" or type(CreateMacro) ~= "function" then
        Print("Macro API unavailable.")
        return
    end
    if type(body) ~= "string" or body == "" then
        Print("Nothing to write for macro '" .. tostring(name) .. "'.")
        return
    end

    body = ApplyOptionalLines(body)
    local okLen, whyLen = MacroWithinLimit(body)
    if not okLen then
        Print("Macro too long (" .. tostring(#body) .. "/" .. tostring(MAX_MACRO_CHARS) .. "). Remove optional lines.")
        return
    end

    body = FinalizeMacroBody(body)
    okLen, whyLen = MacroWithinLimit(body)
    if not okLen then
        Print("Macro too long (" .. tostring(#body) .. "/" .. tostring(MAX_MACRO_CHARS) .. "). Remove optional lines.")
        return
    end

    local idx = GetMacroIndexByName(name)
    if idx and idx > 0 then
        if type(EditMacro) == "function" then
            EditMacro(idx, name, "INV_Misc_QuestionMark", body)
            Print("Updated macro '" .. tostring(name) .. "'.")
        else
            Print("Macro '" .. tostring(name) .. "' already exists.")
        end
        return
    end

    if perCharacter == nil then
        perCharacter = GetMacroPerCharSetting()
    end

    local ok = CreateMacro(name, "INV_Misc_QuestionMark", body, perCharacter and true or false)
    if ok then
        Print("Created macro '" .. tostring(name) .. "'.")
    else
        Print("Could not create macro '" .. tostring(name) .. "' (macro slots full?).")
    end
end

local function GetMacroBindText(macroName)
    if not (GetBindingKey and macroName) then return "" end
    local k1, k2 = GetBindingKey("MACRO " .. macroName)
    if k1 and k2 then return k1 .. ", " .. k2 end
    return k1 or k2 or ""
end

local function SetMacroBinding(macroName, key)
    if not (SetBindingMacro and SaveBindings and GetCurrentBindingSet) then
        return false, "Binding API unavailable"
    end

    if key == nil or key == "" then
        return false, "No key"
    end

    if key == "LeftButton" or key == "RightButton" or key == "MiddleButton" then
        return false, "Mouse buttons not supported here"
    end

    SetBindingMacro(key, macroName)
    SaveBindings(GetCurrentBindingSet())
    return true
end

-- Macro bodies
local function MacroBody_HS_Garrison()
    return table.concat({
        "/fao hs garrison",
        "/use item:110560",
    }, "\n")
end

local function MacroBody_HS_Dalaran()
    return table.concat({
        "/fao hs dalaran",
        "/use item:140192",
    }, "\n")
end

local function MacroBody_HS_Whistle()
    return table.concat({
        "/fao hs whistle",
        "/use item:230850",
        "/use item:141605",
        "/use item:205255",
    }, "\n")
end

local function MacroBody_HS_Dornogal()
    return table.concat({
        "/fao hs dornogal",
        "/use item:243056",
    }, "\n")
end

local function MacroBody_InstanceIO()
    return table.concat({
        "/run LFGTeleport(IsInLFGDungeon())",
        "/run LFGTeleport(IsInLFGDungeon())",
        "/run print(\"Attempting Dungeon Teleport\")",
    }, "\n")
end

local function MacroBody_InstanceReset()
    return "/script ResetInstances();"
end

local function MacroBody_Rez()
    return table.concat({
        "/use Ancestral Spirit",
        "/cast Redemption",
        "/cast Resurrection",
        "/cast Resuscitate",
        "/cast Return",
        "/cast Revive",
        "/cast Raise Ally",
    }, "\n")
end

local function MacroBody_RezCombat()
    return table.concat({
        "/cast Rebirth",
        "/cast Intercession",
        "/cast Raise Ally",
    }, "\n")
end

local function MacroBody_ScriptErrors()
    return "/fao scripterrors"
end

ns.Macros = ns.Macros or {}
ns.Macros.Print = Print
ns.Macros.InCombat = InCombat
ns.Macros.GetMacroPerCharSetting = GetMacroPerCharSetting
ns.Macros.SetMacroPerCharSetting = SetMacroPerCharSetting
ns.Macros.GetMacroOptionalDB = GetMacroOptionalDB
ns.Macros.GetOptionalEntries = GetOptionalEntries
ns.Macros.AddOrUpdateOptionalEntry = AddOrUpdateOptionalEntry
ns.Macros.ToggleOptionalEntry = ToggleOptionalEntry
ns.Macros.IsOptionalEntrySelected = IsOptionalEntrySelected
ns.Macros.ApplyOptionalLines = ApplyOptionalLines
ns.Macros.MAX_MACRO_CHARS = MAX_MACRO_CHARS
ns.Macros.EnsureMacro = EnsureMacro
ns.Macros.CreateOrUpdateNamedMacro = CreateOrUpdateNamedMacro
ns.Macros.GetMacroBindText = GetMacroBindText
ns.Macros.SetMacroBinding = SetMacroBinding

ns.Macros.MacroBody_HS_Garrison = MacroBody_HS_Garrison
ns.Macros.MacroBody_HS_Dalaran = MacroBody_HS_Dalaran
ns.Macros.MacroBody_HS_Dornogal = MacroBody_HS_Dornogal
ns.Macros.MacroBody_HS_Whistle = MacroBody_HS_Whistle
ns.Macros.MacroBody_InstanceIO = MacroBody_InstanceIO
ns.Macros.MacroBody_InstanceReset = MacroBody_InstanceReset
ns.Macros.MacroBody_Rez = MacroBody_Rez
ns.Macros.MacroBody_RezCombat = MacroBody_RezCombat
ns.Macros.MacroBody_ScriptErrors = MacroBody_ScriptErrors

-- Hearth logic (moved from fr0z3nUI_AutoOpenHearth.lua).
do
    local MACRO_NAME = "FAO Hearth"

    local function SafeLower(s)
        return tostring(s or ""):lower()
    end

    local function GetCharKey()
        if UnitFullName then
            local name, realm = UnitFullName("player")
            if name and realm and realm ~= "" then
                return tostring(name) .. "-" .. tostring(realm)
            end
            if name then
                return tostring(name)
            end
        end
        if UnitName then
            local name = UnitName("player")
            local realm = GetRealmName and GetRealmName() or nil
            if name and realm and realm ~= "" then
                return tostring(name) .. "-" .. tostring(realm)
            end
            if name then
                return tostring(name)
            end
        end
        return "player"
    end

    local function EnsureInit()
        _G.fr0z3nUI_AutoOpen_UI = _G.fr0z3nUI_AutoOpen_UI or {}
        local root = _G.fr0z3nUI_AutoOpen_UI
        root.hearth = root.hearth or {}
        local db = root.hearth

        db.window = db.window or { tab = "hearth", macroPerChar = false }
        db.zoneByChar = db.zoneByChar or {}
        db.customUseItems = db.customUseItems or {}

        if db.selectedUseItemID ~= nil then
            db.selectedUseItemID = tonumber(db.selectedUseItemID)
        end

        if db.autoRotate ~= nil then
            db.autoRotate = db.autoRotate and true or false
        else
            db.autoRotate = false
        end

        if db.toyShowAll ~= nil then
            db.toyShowAll = db.toyShowAll and true or false
        else
            db.toyShowAll = false
        end

        if db.toyFilter == nil then
            db.toyFilter = ""
        end

        return db, GetCharKey()
    end

    local function IsDraeneiPlayer()
        if not UnitRace then return false end
        local _, raceFile = UnitRace("player")
        return raceFile == "Draenei" or raceFile == "LightforgedDraenei"
    end

    local function GetItemCountByID(itemID)
        itemID = tonumber(itemID)
        if not itemID then return 0 end
        if C_Item and C_Item.GetItemCount then
            return tonumber(C_Item.GetItemCount(itemID, true, false)) or 0
        end
        if GetItemCount then
            return tonumber(GetItemCount(itemID, true)) or 0
        end
        return 0
    end

    local function GetItemNameByID(itemID)
        itemID = tonumber(itemID)
        if not itemID then return nil end
        if C_Item and C_Item.GetItemNameByID then
            return C_Item.GetItemNameByID(itemID)
        end
        if GetItemInfo then
            return GetItemInfo(itemID)
        end
        return nil
    end

    local function BuildMacroRunLine(useItemID)
        useItemID = tonumber(useItemID) or 6948
        return ("/run local id=%d; local s,d=GetItemCooldown(id); s=s+d-GetTime(); if s>1 then print(format('Hearth in %d mins', s/60)) else print('Hearthing') end")
            :format(useItemID)
    end

    local CURATED_USE_ITEMS = {
        { id = 263489, label = "Naaru's Enfold" },
        { id = 246565, label = "Cosmic Hearthstone" },
        { id = 245970, label = "P.O.S.T. Master's Express Hearthstone" },
        { id = 236687, label = "Explosive Hearthstone" },
        { id = 235016, label = "Redeployment Module" },
        { id = 228940, label = "Notorious Thread's Hearthstone" },
        { id = 228834, label = "Explosive Hearthstone (alt)" },
        { id = 228833, label = "Redeployment Module (alt)" },
        { id = 213327, label = "Stone of the Hearth (alt)" },
        { id = 212337, label = "Stone of the Hearth" },
        { id = 210629, label = "Deepdweller's Earthen Hearthstone (alt)" },
        { id = 210455, label = "Draenic Hologem" },
        { id = 209035, label = "Hearthstone of the Flame" },
        { id = 208704, label = "Deepdweller's Earthen Hearthstone" },
        { id = 206195, label = "Path of the Naaru" },
        { id = 200630, label = "Ohn'ir Windsage's Hearthstone" },
        { id = 193588, label = "Timewalker's Hearthstone" },
        { id = 190237, label = "Broker Translocation Matrix" },
        { id = 190196, label = "Enlightened Hearthstone" },
        { id = 188952, label = "Dominated Hearthstone" },
        { id = 184353, label = "Kyrian Hearthstone" },
        { id = 183716, label = "Venthyr Sinstone" },
        { id = 183710, label = "Venthyr Sinstone (alt)" },
        { id = 183709, label = "Necrolord Hearthstone (alt)" },
        { id = 183708, label = "Night Fae Hearthstone (alt)" },
        { id = 182773, label = "Necrolord Hearthstone" },
        { id = 180290, label = "Night Fae Hearthstone" },
        { id = 172179, label = "Eternal Traveler's Hearthstone" },
        { id = 168907, label = "Holographic Digitalization Hearthstone" },
        { id = 166747, label = "Brewfest Reveler's Hearthstone" },
        { id = 166746, label = "Fire Eater's Hearthstone" },
        { id = 165802, label = "Noble Gardener's Lovely Hearthstone" },
        { id = 165670, label = "Peddlefeet's Lovely Hearthstone" },
        { id = 165669, label = "Lunar Elder's Hearthstone" },
        { id = 163045, label = "Headless Horseman's Hearthstone" },
        { id = 162973, label = "Greatfather Winter's Hearthstone" },
        { id = 142542, label = "Tome of Town Portal" },
        { id = 93672, label = "Dark Portal" },
        { id = 64488, label = "The Innkeeper's Daughter" },
        { id = 54452, label = "Ethereal Portal" },
    }

    local function HasUseItem(itemID)
        itemID = tonumber(itemID)
        if not itemID then return false end

        if itemID == 210455 and not IsDraeneiPlayer() then
            return false
        end

        if itemID == 6948 then
            return (GetItemCountByID(6948) or 0) > 0
        end
        if PlayerHasToy and PlayerHasToy(itemID) then
            return true
        end
        return (GetItemCountByID(itemID) or 0) > 0
    end

    local function GetUseItemName(itemID, fallback)
        itemID = tonumber(itemID)
        if not itemID then return tostring(fallback or "") end
        if itemID == 6948 then
            return "Hearthstone"
        end
        return GetItemNameByID(itemID) or tostring(fallback or ("item:" .. tostring(itemID)))
    end

    local function GetToyCooldownStart(itemID)
        itemID = tonumber(itemID)
        if not itemID then return 0 end
        if PlayerHasToy and PlayerHasToy(itemID) and C_ToyBox and C_ToyBox.GetToyCooldown then
            local startTime, duration = C_ToyBox.GetToyCooldown(itemID)
            startTime = tonumber(startTime) or 0
            duration = tonumber(duration) or 0
            if startTime > 0 and duration > 0 then
                return startTime
            end
            return 0
        end
        if C_Item and C_Item.GetItemCooldown then
            local startTime, duration = C_Item.GetItemCooldown(itemID)
            startTime = tonumber(startTime) or 0
            duration = tonumber(duration) or 0
            if startTime > 0 and duration > 0 then
                return startTime
            end
        end
        return 0
    end

    local function RollRandomUseItem(db)
        if type(db) ~= "table" then return nil end
        local pool = {}
        for _, e in ipairs(CURATED_USE_ITEMS) do
            local id = tonumber(e.id)
            if id and HasUseItem(id) then
                pool[#pool + 1] = id
            end
        end
        if HasUseItem(6948) then
            pool[#pool + 1] = 6948
        end
        if #pool == 0 then
            return nil
        end
        local pick = pool[math.random(1, #pool)]
        db.selectedUseItemID = pick
        return pick
    end

    local function BuildMacroText(db)
        local useID = db and tonumber(db.selectedUseItemID)
        if useID and not HasUseItem(useID) then
            useID = nil
        end
        local lines = { "/fao hs hearth" }
        if useID and useID > 0 then
            lines[#lines + 1] = "/use item:" .. tostring(useID)
        end
        return table.concat(lines, "\n")
    end

    local function GetOwnedHearthToys()
        local out = {}

        local hsCount = GetItemCountByID(6948)
        if hsCount and hsCount > 0 then
            out[#out + 1] = { id = 6948, name = "Hearthstone (item)" }
        end

        if not (C_ToyBox and C_ToyBox.GetNumToys and C_ToyBox.GetToyFromIndex and PlayerHasToy) then
            return out
        end

        local n = C_ToyBox.GetNumToys() or 0
        for i = 1, n do
            local itemID = C_ToyBox.GetToyFromIndex(i)
            if itemID and PlayerHasToy(itemID) then
                if C_Item and C_Item.RequestLoadItemDataByID then
                    C_Item.RequestLoadItemDataByID(itemID)
                end
                local name = GetItemNameByID(itemID)
                out[#out + 1] = { id = itemID, name = name or ("Toy " .. tostring(itemID)) }
            end
        end

        table.sort(out, function(a, b)
            return SafeLower(a.name) < SafeLower(b.name)
        end)

        return out
    end

    local function PassToyFilter(toyName, filterText)
        local ft = SafeLower(filterText)
        if ft == "" then return true end
        local tn = SafeLower(toyName)
        return tn:find(ft, 1, true) ~= nil
    end

    local function GetCurrentDisplayText()
        local db, charKey = EnsureInit()
        local bind = (GetBindLocation and GetBindLocation()) or ""
        local zone = (db.zoneByChar and db.zoneByChar[charKey]) or ""
        if zone == "" then
            return bind, "(zone not captured yet - set your hearth once)"
        end
        return bind, zone
    end

    ns.Hearth = ns.Hearth or {}
    ns.Hearth.MACRO_NAME = MACRO_NAME
    ns.Hearth.CURATED_USE_ITEMS = CURATED_USE_ITEMS
    ns.Hearth.EnsureInit = EnsureInit
    ns.Hearth.PassToyFilter = PassToyFilter
    ns.Hearth.GetUseItemName = GetUseItemName
    ns.Hearth.HasUseItem = HasUseItem
    ns.Hearth.GetOwnedHearthToys = GetOwnedHearthToys
    ns.Hearth.RollRandomUseItem = RollRandomUseItem
    ns.Hearth.BuildMacroText = BuildMacroText
    ns.Hearth.GetCurrentDisplayText = GetCurrentDisplayText

    -- Event wiring: zone capture + auto-rotate behavior for the hearth macro.
    do
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_LOGIN")
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:RegisterEvent("UPDATE_BINDINGS")
        f:RegisterEvent("HEARTHSTONE_BOUND")
        f:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
        f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        f:RegisterEvent("BAG_UPDATE_COOLDOWN")
        f:RegisterEvent("TOYS_UPDATED")

        local lastSeenCooldownStart = 0
        local lastMacroUpdateAt = 0

        local function MacroExists()
            return type(GetMacroIndexByName) == "function" and (GetMacroIndexByName(MACRO_NAME) or 0) > 0
        end

        local function UpdateMacroIfExists()
            if InCombat() then return end
            if type(GetMacroIndexByName) ~= "function" or type(EditMacro) ~= "function" then return end
            local idx = GetMacroIndexByName(MACRO_NAME)
            if not (idx and idx > 0) then return end

            local now = (GetTime and GetTime()) or 0
            if now > 0 and (now - lastMacroUpdateAt) < 0.5 then
                return
            end
            lastMacroUpdateAt = now

            local db = EnsureInit()
            local body = BuildMacroText(db)
            EditMacro(idx, MACRO_NAME, "INV_Misc_QuestionMark", body)
        end

        local function MaybeRotateAndUpdate(reason)
            local db = EnsureInit()
            if not db.autoRotate then return end
            if not MacroExists() then return end
            if InCombat() then return end

            local id = RollRandomUseItem(db)
            if not id then return end
            UpdateMacroIfExists()

            if reason then
                Print("Auto-rotated macro (" .. tostring(reason) .. "): " .. GetUseItemName(id))
            end
        end

        local function CheckUsedAndRotate()
            local db = EnsureInit()
            if not db.autoRotate then return end
            if InCombat() then return end
            if not MacroExists() then return end

            local useID = tonumber(db.selectedUseItemID)
            if not useID or useID <= 0 then return end

            local start = GetToyCooldownStart(useID)
            if start > 0 and (lastSeenCooldownStart == 0 or start ~= lastSeenCooldownStart) then
                lastSeenCooldownStart = start
                MaybeRotateAndUpdate("used")
            end
            if start == 0 then
                lastSeenCooldownStart = 0
            end
        end

        f:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_LOGIN" then
                EnsureInit()
                local rs = math and rawget(math, "randomseed")
                local rr = math and rawget(math, "random")
                if time and rs then
                    rs((time() or 0) + (GetServerTime and (GetServerTime() or 0) or 0))
                    if rr then rr(); rr() end
                end
                return
            end

            if event == "PLAYER_ENTERING_WORLD" then
                MaybeRotateAndUpdate("login")
                return
            end

            local db, charKey = EnsureInit()
            if event == "HEARTHSTONE_BOUND" or event == "UPDATE_BINDINGS" then
                db.zoneByChar = db.zoneByChar or {}
                db.zoneByChar[charKey] = GetRealZoneText() or ""
                return
            end

            if event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" or event == "TOYS_UPDATED" then
                CheckUsedAndRotate()
            end
        end)
    end
end
