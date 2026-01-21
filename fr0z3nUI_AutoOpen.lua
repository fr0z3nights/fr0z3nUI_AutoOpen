local addonName, ns = ...
local lastOpenTime, atBank, atMail = 0, false, false
local didPruneCustomWhitelists = false
local lastTalentsDebugAt, lastTalentsDebugLine = 0, nil

local function GetAutoLootDefaultSafe()
    if GetCVarBool then
        return GetCVarBool("autoLootDefault")
    end
    if C_CVar and C_CVar.GetCVarBool then
        return C_CVar.GetCVarBool("autoLootDefault")
    end
    if GetCVar then
        local v = GetCVar("autoLootDefault")
        if v == nil then return nil end
        return tostring(v) == "1"
    end
    return nil
end

local function SetAutoLootDefaultSafe(enabled)
    local v = enabled and "1" or "0"
    if C_CVar and C_CVar.SetCVar then
        C_CVar.SetCVar("autoLootDefault", v)
        return true
    end
    if SetCVar then
        SetCVar("autoLootDefault", v)
        return true
    end
    return false
end

local function ApplyAutoLootSettingOnWorld()
    if not (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.autoLootOnLogin) then return end
    SetAutoLootDefaultSafe(true)
end

local function GetFriendlyNPCNameplatesSafe()
    if GetCVarBool then
        return GetCVarBool("nameplateShowFriendlyNPCs")
    end
    if C_CVar and C_CVar.GetCVarBool then
        return C_CVar.GetCVarBool("nameplateShowFriendlyNPCs")
    end
    if GetCVar then
        local v = GetCVar("nameplateShowFriendlyNPCs")
        if v == nil then return nil end
        return tostring(v) == "1"
    end
    return nil
end

local function SetFriendlyNPCNameplatesSafe(enabled)
    local v = enabled and "1" or "0"
    if C_CVar and C_CVar.SetCVar then
        C_CVar.SetCVar("nameplateShowFriendlyNPCs", v)
        return true
    end
    if SetCVar then
        SetCVar("nameplateShowFriendlyNPCs", v)
        return true
    end
    return false
end

local function GetNPCNameplatesSettingEffective()
    if fr0z3nUI_AutoOpen_Settings and type(fr0z3nUI_AutoOpen_Settings.npcNameplatesAccount) == "boolean" then
        return fr0z3nUI_AutoOpen_Settings.npcNameplatesAccount
    end
    if fr0z3nUI_AutoOpen_CharSettings and type(fr0z3nUI_AutoOpen_CharSettings.npcNameplates) == "boolean" then
        return fr0z3nUI_AutoOpen_CharSettings.npcNameplates
    end
    return true
end

local function ApplyNPCNameplatesSettingOnWorld()
    local enabled = GetNPCNameplatesSettingEffective()
    SetFriendlyNPCNameplatesSafe(enabled)
end

local function NormalizeCooldown(value)
    local cd = tonumber(value)
    if not cd then return 2 end
    if cd < 0 then cd = 0 end
    if cd > 10 then cd = 10 end
    return cd
end

local function GetOpenCooldown()
    if fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.cooldown ~= nil then
        return NormalizeCooldown(fr0z3nUI_AutoOpen_Settings.cooldown)
    end
    return 2
end

local function GetItemGUIDForBagSlot(bag, slot)
    if not (ItemLocation and ItemLocation.CreateFromBagAndSlot and C_Item and C_Item.GetItemGUID) then return nil end
    local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
    if not (loc and loc.IsValid and loc:IsValid()) then return nil end
    return C_Item.GetItemGUID(loc)
end

local function FindBagSlotByGUID(guid)
    if not guid then return nil end
    for b = 0, 4 do
        for s = 1, C_Container.GetContainerNumSlots(b) do
            local g = GetItemGUIDForBagSlot(b, s)
            if g and g == guid then
                return b, s
            end
        end
    end
    return nil
end

local function FindBagSlotsByItemID(id)
    local out = {}
    if not id then return out end
    for b = 0, 4 do
        for s = 1, C_Container.GetContainerNumSlots(b) do
            local slotID = C_Container.GetContainerItemID(b, s)
            if slotID and slotID == id then
                out[#out + 1] = { bag = b, slot = s, guid = GetItemGUIDForBagSlot(b, s) }
            end
        end
    end
    return out
end

local function GetRequiredLevelForID(id)
    if not (ns and ns.levelLocked and id) then return nil end
    local entry = ns.levelLocked[id]
    if not entry then return nil end
    local req = tonumber(entry[1])
    local name = entry[2]
    return req, name
end

local function GetSlotKey(bag, slot)
    return bag.."-"..slot
end

local function GetItemNameSafe(id)
    if not id then return nil end
    if C_Item and C_Item.GetItemNameByID then
        return C_Item.GetItemNameByID(id)
    end
    if C_Item and C_Item.GetItemInfo then
        local name = C_Item.GetItemInfo(id)
        return name
    end
    return nil
end

local function GetOpenableTooltipLineText()
    return (_G and _G["ITEM_OPENABLE"]) or nil
end

local function TooltipSuggestsOpenable(id)
    if not (id and C_TooltipInfo and C_TooltipInfo.GetItemByID) then return nil end
    local tip = C_TooltipInfo.GetItemByID(id)
    if not (tip and tip.lines) then return nil end

    local openableText = GetOpenableTooltipLineText()
    if not openableText then return nil end

    for _, line in ipairs(tip.lines) do
        local left = line and line.leftText
        local right = line and line.rightText
        if left == openableText or right == openableText then
            return true
        end
    end
    return false
end

local function IsProbablyOpenableCacheID(id)
    if not id then return false, "invalid" end

    -- User override: allow manual IDs without the cache/openable validation.
    if fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.cacheLockCheck == false then
        return true, "bypass"
    end

    -- If it looks equippable, it's almost certainly not an openable cache.
    if C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, equipLoc = C_Item.GetItemInfoInstant(id)
        if type(equipLoc) == "string" and equipLoc ~= "" then
            return false, "equippable"
        end
    end

    -- Prefer tooltip truth: caches/lockboxes usually show the localized 'Right Click to Open'.
    local tip = TooltipSuggestsOpenable(id)
    if tip == nil then
        if C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(id)
        end
        return nil, "loading"
    end
    if tip == true then
        return true
    end
    return false, "no_open_line"
end

local function InitSV()
    fr0z3nUI_AutoOpen_Acc = fr0z3nUI_AutoOpen_Acc or {}
    fr0z3nUI_AutoOpen_Char = fr0z3nUI_AutoOpen_Char or {}
    fr0z3nUI_AutoOpen_Settings = fr0z3nUI_AutoOpen_Settings or { disabled = {} }
    fr0z3nUI_AutoOpen_CharSettings = fr0z3nUI_AutoOpen_CharSettings or {}

    if type(fr0z3nUI_AutoOpen_Settings.disabled) ~= "table" then
        fr0z3nUI_AutoOpen_Settings.disabled = {}
    end
    if type(fr0z3nUI_AutoOpen_CharSettings.disabled) ~= "table" then
        fr0z3nUI_AutoOpen_CharSettings.disabled = {}
    end

    if fr0z3nUI_AutoOpen_Settings.cooldown == nil then
        fr0z3nUI_AutoOpen_Settings.cooldown = 2
    else
        fr0z3nUI_AutoOpen_Settings.cooldown = NormalizeCooldown(fr0z3nUI_AutoOpen_Settings.cooldown)
    end

    -- Great Vault is stored per-character as a 3-state mode:
    -- OFF = disabled, ON = show at login, RL = show on /reload.
    -- Migration: older versions used fr0z3nUI_GreatVault_CharSettings.enabled or fr0z3nUI_AutoOpen_CharSettings.greatVault (boolean).
    if fr0z3nUI_AutoOpen_CharSettings.greatVaultMode == nil then
        if type(fr0z3nUI_AutoOpen_CharSettings.greatVault) == "boolean" then
            fr0z3nUI_AutoOpen_CharSettings.greatVaultMode = fr0z3nUI_AutoOpen_CharSettings.greatVault and "ON" or "OFF"
            fr0z3nUI_AutoOpen_CharSettings.greatVault = nil
            fr0z3nUI_AutoOpen_CharSettings.greatVaultTouched = true
        elseif type(fr0z3nUI_GreatVault_CharSettings) == "table" and fr0z3nUI_GreatVault_CharSettings.enabled ~= nil then
            fr0z3nUI_AutoOpen_CharSettings.greatVaultMode = fr0z3nUI_GreatVault_CharSettings.enabled and "ON" or "OFF"
            fr0z3nUI_GreatVault_CharSettings = nil
            fr0z3nUI_AutoOpen_CharSettings.greatVaultTouched = true
        else
            fr0z3nUI_AutoOpen_CharSettings.greatVaultMode = "OFF"
        end
    end

    if fr0z3nUI_AutoOpen_CharSettings.autoOpen == nil then
        -- Migration: older versions stored this account-wide
        if fr0z3nUI_AutoOpen_Settings.autoOpen ~= nil then
            fr0z3nUI_AutoOpen_CharSettings.autoOpen = fr0z3nUI_AutoOpen_Settings.autoOpen and true or false
        else
            fr0z3nUI_AutoOpen_CharSettings.autoOpen = true
        end
    end

    -- Talent reminder (per-character)
    -- Modes:
    -- OFF   = disabled
    -- LOGIN = only initial login
    -- RL    = only /reload
    -- WORLD = any non-initial PLAYER_ENTERING_WORLD (reload + portals/instances)
    -- Default: WORLD
    if fr0z3nUI_AutoOpen_CharSettings.talentMode == nil then
        -- Migration: older builds briefly stored this account-wide.
        if type(fr0z3nUI_AutoOpen_Settings.talentMode) == "string" and fr0z3nUI_AutoOpen_Settings.talentMode ~= "" then
            fr0z3nUI_AutoOpen_CharSettings.talentMode = tostring(fr0z3nUI_AutoOpen_Settings.talentMode):upper()
        else
            fr0z3nUI_AutoOpen_CharSettings.talentMode = "WORLD"
        end
    end
    fr0z3nUI_AutoOpen_Settings.talentMode = nil

    -- Talent UI auto-open (3-state)
    -- OFF     = off (per-character)
    -- ON      = on (per-character)
    -- ON ACC  = on account-wide override (overrides character)
    -- Defaults: character OFF, account override unset
    if type(fr0z3nUI_AutoOpen_CharSettings.talentAutoOpen) ~= "boolean" then
        local legacy = tostring(fr0z3nUI_AutoOpen_CharSettings.talentUIMode or "OFF"):upper()
        fr0z3nUI_AutoOpen_CharSettings.talentAutoOpen = (legacy == "ON" or legacy == "RL" or legacy == "WORLD")
    end
    fr0z3nUI_AutoOpen_CharSettings.talentUIMode = nil

    -- Migration: older builds stored this account-wide as talentAutoOpen.
    -- Treat that as the account override (ON ACC) to preserve behavior.
    if type(fr0z3nUI_AutoOpen_Settings.talentAutoOpenAccount) ~= "boolean" then
        if type(fr0z3nUI_AutoOpen_Settings.talentAutoOpen) == "boolean" then
            fr0z3nUI_AutoOpen_Settings.talentAutoOpenAccount = fr0z3nUI_AutoOpen_Settings.talentAutoOpen
        end
    end
    fr0z3nUI_AutoOpen_Settings.talentAutoOpen = nil

    -- Debug toggles (per-character)
    if type(fr0z3nUI_AutoOpen_CharSettings.debugTalents) ~= "boolean" then
        fr0z3nUI_AutoOpen_CharSettings.debugTalents = false
    end

    -- Auto Loot (per-character): when ON, force the account CVar to enabled on login.
    -- Default: ON
    if type(fr0z3nUI_AutoOpen_CharSettings.autoLootOnLogin) ~= "boolean" then
        fr0z3nUI_AutoOpen_CharSettings.autoLootOnLogin = true
    end

    -- Friendly NPC Nameplates (3-state)
    -- ON      = on (per-character)
    -- ON ACC  = account override on (overrides character)
    -- OFF ACC = account override off (overrides character)
    -- Defaults: character ON, account override unset
    if type(fr0z3nUI_AutoOpen_CharSettings.npcNameplates) ~= "boolean" then
        fr0z3nUI_AutoOpen_CharSettings.npcNameplates = true
    end
    if fr0z3nUI_AutoOpen_Settings.npcNameplatesAccount ~= nil and type(fr0z3nUI_AutoOpen_Settings.npcNameplatesAccount) ~= "boolean" then
        fr0z3nUI_AutoOpen_Settings.npcNameplatesAccount = nil
    end

    -- Cache Lock (per-character): when OFF, bypass openable-cache validation for manual adds.
    if fr0z3nUI_AutoOpen_CharSettings.cacheLockCheck == nil then
        fr0z3nUI_AutoOpen_CharSettings.cacheLockCheck = true
    end
    fr0z3nUI_AutoOpen_Timers = fr0z3nUI_AutoOpen_Timers or {}

    -- Cleanup: if a user-added SavedVariable item is now in the addon database,
    -- remove it from the custom whitelist to avoid redundant entries.
    if not didPruneCustomWhitelists and ns and ns.items then
        local function Prune(tbl)
            for key in pairs(tbl) do
                local id = tonumber(key) or key
                if type(id) == "number" and ns.items[id] then
                    tbl[key] = nil
                end
            end
        end

        Prune(fr0z3nUI_AutoOpen_Acc)
        Prune(fr0z3nUI_AutoOpen_Char)
        didPruneCustomWhitelists = true
    end
end

local function GetMaxPlayerLevelSafe()
    if GetMaxPlayerLevel then
        local max = GetMaxPlayerLevel()
        if type(max) == "number" and max > 0 then return max end
    end
    return nil
end

local function AutoEnableGreatVaultAtMaxLevel()
    if not (UnitLevel and fr0z3nUI_AutoOpen_CharSettings) then return end
    local maxLevel = GetMaxPlayerLevelSafe()
    if not maxLevel then return false end

    local level = UnitLevel("player")
    if not (type(level) == "number" and level >= maxLevel) then return false end

    -- Respect explicit user choice. If untouched, default to ON at level cap.
    if fr0z3nUI_AutoOpen_CharSettings.greatVaultTouched then return false end
    local mode = tostring(fr0z3nUI_AutoOpen_CharSettings.greatVaultMode or "OFF"):upper()
    if mode == "OFF" then
        fr0z3nUI_AutoOpen_CharSettings.greatVaultMode = "ON"
        return true
    end
    return false
end

-- [ GREAT VAULT ]
local function ShowGreatVaultCore()
    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_WeeklyRewards")
    end
    if WeeklyRewardsFrame then
        WeeklyRewardsFrame:Show()
        return
    end
    C_Timer.After(0.5, function()
        if WeeklyRewardsFrame then WeeklyRewardsFrame:Show() end
    end)
end

ns.ShowGreatVault = function()
    InitSV()
    local mode = (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.greatVaultMode) or "OFF"
    mode = tostring(mode):upper()
    if mode ~= "OFF" then
        ShowGreatVaultCore()
    end
end

-- [ TALENTS ]
local lastTalentNotifyAt, lastTalentNotifiedPoints = 0, nil
local didTryLoadTalentAddonsForPoints = false
local talentCheckSeq = 0

local function GetUnspentTalentPointsSafe()
    local function Query()
        local total = 0
        local any = false
        local classPoints, heroPoints

        if C_ClassTalents then
            if C_ClassTalents.GetUnspentTalentPoints then
                local p = C_ClassTalents.GetUnspentTalentPoints()
                if type(p) == "number" then
                    classPoints = p
                    total = total + p
                    any = true
                end
            end
            if C_ClassTalents.GetUnspentHeroTalentPoints then
                local p = C_ClassTalents.GetUnspentHeroTalentPoints()
                if type(p) == "number" then
                    heroPoints = p
                    total = total + p
                    any = true
                end
            end
        end

        if not any then return nil end
        return total, classPoints, heroPoints
    end

    local total, classPoints, heroPoints = Query()

    -- Hero talent points (71-80) can briefly report as numeric 0 before the talent systems are fully initialized.
    -- If we treat that as "ready", we never load the Blizzard talent UI addons and never see the points.
    if total ~= nil and total <= 0 and not didTryLoadTalentAddonsForPoints then
        local level = (UnitLevel and UnitLevel("player")) or nil
        if type(level) == "number" and level >= 71 then
            didTryLoadTalentAddonsForPoints = true
            if C_AddOns and C_AddOns.LoadAddOn then
                C_AddOns.LoadAddOn("Blizzard_PlayerSpells")
                C_AddOns.LoadAddOn("Blizzard_ClassTalentUI")
                C_AddOns.LoadAddOn("Blizzard_TalentUI")
            end
            total, classPoints, heroPoints = Query()
        end
    end

    if total == nil and not didTryLoadTalentAddonsForPoints then
        didTryLoadTalentAddonsForPoints = true
        if C_AddOns and C_AddOns.LoadAddOn then
            -- Some clients don't populate talent APIs until these are loaded.
            C_AddOns.LoadAddOn("Blizzard_PlayerSpells")
            C_AddOns.LoadAddOn("Blizzard_ClassTalentUI")
            C_AddOns.LoadAddOn("Blizzard_TalentUI")
        end
        total, classPoints, heroPoints = Query()
    end

    return total, classPoints, heroPoints
end

local function HasUnspentTalentPointsSafe()
    if C_ClassTalents and C_ClassTalents.HasUnspentTalentPoints then
        local ok, v = pcall(C_ClassTalents.HasUnspentTalentPoints)
        if ok and type(v) == "boolean" then
            return v
        end
    end
    return nil
end

local function HasUnspentHeroTalentPointsSafe()
    if C_ClassTalents and C_ClassTalents.HasUnspentHeroTalentPoints then
        local ok, v = pcall(C_ClassTalents.HasUnspentHeroTalentPoints)
        if ok and type(v) == "boolean" then
            return v
        end
    end
    return nil
end

local function GetTalentAutoOpenMode()
    -- Account override wins when explicitly enabled.
    if fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.talentAutoOpenAccount == true then
        return "ACC", true
    end
    local on = (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.talentAutoOpen) and true or false
    return on and "CHAR" or "OFF", on
end

local function ShowTalentsUI()
    if InCombatLockdown and InCombatLockdown() then
        return false
    end

    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_PlayerSpells")
        C_AddOns.LoadAddOn("Blizzard_ClassTalentUI")
        C_AddOns.LoadAddOn("Blizzard_TalentUI")
    end

    local togglePlayerSpellsFrame = _G and _G["TogglePlayerSpellsFrame"]
    if type(togglePlayerSpellsFrame) == "function" then
        togglePlayerSpellsFrame()
        return true
    end

    local playerSpellsFrame = _G and _G["PlayerSpellsFrame"]
    if playerSpellsFrame and playerSpellsFrame.Show then
        playerSpellsFrame:Show()
        return true
    end

    local classTalentFrame = _G and _G["ClassTalentFrame"]
    if classTalentFrame and classTalentFrame.Show then
        classTalentFrame:Show()
        return true
    end

    local toggleTalentFrame = _G and _G["ToggleTalentFrame"]
    if type(toggleTalentFrame) == "function" then
        toggleTalentFrame()
        return true
    end
    return false
end

local function ShouldTalentTrigger(mode, isInitialLogin, isReloadingUi)
    mode = tostring(mode or "OFF"):upper()
    if mode == "OFF" then return false end
    if mode == "LOGIN" then return isInitialLogin and not isReloadingUi end
    if mode == "RL" then return isReloadingUi end
    if mode == "WORLD" then return not isInitialLogin end
    if mode == "ALL" then return true end
    return false
end

local function MaybeHandleTalents(isInitialLogin, isReloadingUi, attempt, seq)
    InitSV()
    attempt = tonumber(attempt) or 0
    isInitialLogin = isInitialLogin and true or false
    isReloadingUi = isReloadingUi and true or false

    local debugTalents = (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.debugTalents) and true or false
    local function DebugTalentLine(line, force)
        if not debugTalents then return end

        local msg = tostring(line or "")
        local now = (GetTime and GetTime()) or 0

        -- Throttle + de-dupe: avoid spam during retries.
        if not force then
            if msg == lastTalentsDebugLine and now > 0 and (now - lastTalentsDebugAt) < 5 then
                return
            end
            if now > 0 and (now - lastTalentsDebugAt) < 1 then
                return
            end
        end

        lastTalentsDebugAt = now
        lastTalentsDebugLine = msg
        print("|cff00ccff[FAO]|r |cffff8800[TALENTS DBG]|r " .. msg)
    end

    if seq ~= nil and seq ~= talentCheckSeq then return end

    local mode = (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.talentMode) or "WORLD"
    local shouldTrigger = ShouldTalentTrigger(mode, isInitialLogin, isReloadingUi)
    if attempt == 0 then
        local lvl = (UnitLevel and UnitLevel("player")) or "?"
        DebugTalentLine(string.format("start lvl=%s mode=%s trigger=%s initial=%s reload=%s", tostring(lvl), tostring(mode):upper(), tostring(shouldTrigger), tostring(isInitialLogin), tostring(isReloadingUi)), true)
    end
    if not shouldTrigger then return end

    local now = (GetTime and GetTime()) or 0
    if now > 0 and (now - lastTalentNotifyAt) < 10 then return end

    local points, classPoints, heroPoints = GetUnspentTalentPointsSafe()
    if points == nil then
        local level = (UnitLevel and UnitLevel("player")) or nil
        local hasAny = HasUnspentTalentPointsSafe()
        local hasHeroAny = HasUnspentHeroTalentPointsSafe()

        if attempt == 0 then
            DebugTalentLine(string.format("query points=nil class=nil hero=nil hasAny=%s hasHero=%s didLoad=%s", tostring(hasAny), tostring(hasHeroAny), tostring(didTryLoadTalentAddonsForPoints)), true)
        end

        if hasHeroAny == false and hasAny == false then
            -- Hero points can exist while the general boolean is still false (or before APIs warm up).
            -- At hero levels, don't give up immediately; retry for a short window.
            if type(level) == "number" and level >= 71 and attempt < 20 then
                C_Timer.After(1, function()
                    MaybeHandleTalents(isInitialLogin, isReloadingUi, attempt + 1, seq)
                end)
            end
            return
        elseif hasHeroAny == true or hasAny == true then
            -- We know there are unspent points, but the numeric APIs aren't ready.
            if now > 0 and (now - lastTalentNotifyAt) < 10 then return end
            lastTalentNotifyAt = now
            lastTalentNotifiedPoints = "?"

            local _, shouldOpenUI = GetTalentAutoOpenMode()
            if shouldOpenUI then
                local ok = ShowTalentsUI()
                if ok then
                    print("|cff00ccff[FAO]|r Unspent talent points available — check talents")
                else
                    print("|cff00ccff[FAO]|r Unspent talent points available — cannot open talents in combat")
                end
            else
                print("|cff00ccff[FAO]|r Unspent talent points available")
            end

            -- Best-effort follow-up to get the actual numeric count once APIs warm up.
            C_Timer.After(2, function()
                MaybeHandleTalents(isInitialLogin, isReloadingUi, attempt + 1, seq)
            end)
            return
        end

        -- Talent APIs can be unavailable for a few seconds after reload/zone.
        if attempt < 60 then
            C_Timer.After(1, function()
                MaybeHandleTalents(isInitialLogin, isReloadingUi, attempt + 1, seq)
            end)
        end
        return
    end

    -- Some clients can briefly report 0 while the boolean API already knows points exist (common right after level-ups).
    if points ~= nil and points <= 0 then
        -- Special case: hero talent APIs can lag behind even when the boolean API doesn't acknowledge it.
        -- On WORLD checks, quietly retry for a short window at hero levels.
        local level = (UnitLevel and UnitLevel("player")) or nil
        if type(level) == "number" and level >= 71 and attempt < 20 then
            C_Timer.After(1, function()
                MaybeHandleTalents(isInitialLogin, isReloadingUi, attempt + 1, seq)
            end)
            return
        end
        local hasAny = HasUnspentTalentPointsSafe()
        if hasAny == true and attempt < 10 then
            C_Timer.After(1, function()
                MaybeHandleTalents(isInitialLogin, isReloadingUi, attempt + 1, seq)
            end)
        end
        return
    end

    if not (points and points > 0) then return end

    if lastTalentNotifiedPoints == points and now > 0 and (now - lastTalentNotifyAt) < 60 then return end
    lastTalentNotifiedPoints = points
    lastTalentNotifyAt = now

    local breakdown = ""
    if type(classPoints) == "number" or type(heroPoints) == "number" then
        breakdown = string.format(" (class %s, hero %s)", tostring(classPoints or 0), tostring(heroPoints or 0))
    end

    local _, shouldOpenUI = GetTalentAutoOpenMode()

    DebugTalentLine(string.format("result attempt=%d total=%s class=%s hero=%s openUI=%s", tonumber(attempt) or 0, tostring(points), tostring(classPoints or 0), tostring(heroPoints or 0), tostring(shouldOpenUI)), true)

    if shouldOpenUI then
        local ok = ShowTalentsUI()
        if ok then
            print("|cff00ccff[FAO]|r Unspent talent points: |cffffff00"..points.."|r"..breakdown)
        else
            print("|cff00ccff[FAO]|r Unspent talent points: |cffffff00"..points.."|r"..breakdown.." (cannot open talents in combat)")
        end
    else
        print("|cff00ccff[FAO]|r Unspent talent points: |cffffff00"..points.."|r"..breakdown)
    end
end

-- [ TIMER RECOVERY & DISRUPTION ]
local function CheckTimersOnLogin()
    if not fr0z3nUI_AutoOpen_Timers then return end
    local currentTime, foundAny = time(), false
    for key, data in pairs(fr0z3nUI_AutoOpen_Timers) do
        local id = data and tonumber(data.id)
        if not (id and ns.timed and ns.timed[id]) then
            fr0z3nUI_AutoOpen_Timers[key] = nil
        else
            local duration = tonumber(ns.timed[id][1])
            local startTime = tonumber(data.startTime)
            if not (duration and startTime) then
                fr0z3nUI_AutoOpen_Timers[key] = nil
            else
                local remaining = duration - (currentTime - startTime)
                if remaining <= 0 then
                    fr0z3nUI_AutoOpen_Timers[key] = nil
                else
                    local b, s

                    -- New format: key is item GUID (stable across bag cleanup).
                    if type(key) == "string" and not key:match("^%d+%-%d+$") then
                        b, s = FindBagSlotByGUID(key)
                        if not (b and s) then
                            fr0z3nUI_AutoOpen_Timers[key] = nil
                        end
                    else
                        -- Legacy format: key is "bag-slot".
                        local lb, ls = tostring(key):match("(%d+)%-(%d+)")
                        lb, ls = tonumber(lb), tonumber(ls)
                        if lb and ls then
                            local currentID = C_Container.GetContainerItemID(lb, ls)
                            if currentID == id then
                                b, s = lb, ls
                            else
                                -- Try to relocate: if exactly one matching item is found, migrate to GUID/slot.
                                local matches = FindBagSlotsByItemID(id)
                                if #matches == 1 then
                                    b, s = matches[1].bag, matches[1].slot
                                    local guid = matches[1].guid
                                    local newKey = guid or GetSlotKey(b, s)
                                    if newKey ~= key then
                                        fr0z3nUI_AutoOpen_Timers[newKey] = { id = id, startTime = startTime }
                                        fr0z3nUI_AutoOpen_Timers[key] = nil
                                        key = newKey
                                    end
                                elseif #matches == 0 then
                                    -- Item disappeared (commonly hatched/consumed); clear silently.
                                    fr0z3nUI_AutoOpen_Timers[key] = nil
                                else
                                    fr0z3nUI_AutoOpen_Timers[key] = nil
                                end
                            end
                        else
                            fr0z3nUI_AutoOpen_Timers[key] = nil
                        end
                    end

                    if fr0z3nUI_AutoOpen_Timers[key] and b and s then
                        local d = math.floor(remaining / 86400)
                        local h = math.floor((remaining % 86400) / 3600)
                        local m = math.ceil((remaining % 3600) / 60)
                        print(string.format("|cff00ccff[FAO]|r Timer: |cffffff00%s|r - |cffff0000%dd %dh %dm|r left.", ns.timed[id][2], d, h, m))
                        foundAny = true
                    end
                end
            end
        end
    end
end

-- [ SCAN ENGINE ]
local frame = CreateFrame('Frame', 'fr0z3nUI_AutoOpenFrame')
function frame:RunScan()
    if not fr0z3nUI_AutoOpen_Settings or not fr0z3nUI_AutoOpen_Acc or not fr0z3nUI_AutoOpen_Char or not fr0z3nUI_AutoOpen_CharSettings then InitSV() end
    if fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.autoOpen == false then return end
    if atBank or atMail or InCombatLockdown() or LootFrame:IsShown() then return end
    if (GetTime() - lastOpenTime) < GetOpenCooldown() then return end
    
    for b = 0, 4 do
        for s = 1, C_Container.GetContainerNumSlots(b) do
            local id = C_Container.GetContainerItemID(b, s)
            if id then
                -- Handle Timers
                local isHatching = false
                if ns.timed and ns.timed[id] then
                    local legacyKey = GetSlotKey(b, s)
                    local guid = GetItemGUIDForBagSlot(b, s)
                    local key = guid or legacyKey
                    fr0z3nUI_AutoOpen_Timers = fr0z3nUI_AutoOpen_Timers or {}
                    local now = time and time() or nil
                    local hatchTime = tonumber(ns.timed[id][1])
                    if now and hatchTime then
                        -- Migrate any existing legacy slot-based timer to GUID-based when possible.
                        if guid and fr0z3nUI_AutoOpen_Timers[legacyKey] and not fr0z3nUI_AutoOpen_Timers[guid] then
                            local old = fr0z3nUI_AutoOpen_Timers[legacyKey]
                            fr0z3nUI_AutoOpen_Timers[guid] = { id = old.id, startTime = old.startTime }
                            fr0z3nUI_AutoOpen_Timers[legacyKey] = nil
                            key = guid
                        end

                        local entry = fr0z3nUI_AutoOpen_Timers[key]
                        local startTime = entry and tonumber(entry.startTime) or nil
                        if type(entry) ~= "table" or entry.id ~= id or not startTime then
                            fr0z3nUI_AutoOpen_Timers[key] = { id = id, startTime = now }
                            startTime = now
                        end
                        if (now - startTime) < hatchTime then
                            isHatching = true
                        end
                    else
                        -- Bad timed entry or time() unavailable; clear any persisted timer.
                        fr0z3nUI_AutoOpen_Timers[key] = nil
                    end
                end
                
                -- Check Whitelist/Custom IDs and Filter via ns.exclude
                if not isHatching and (ns.items[id] or fr0z3nUI_AutoOpen_Acc[id] or fr0z3nUI_AutoOpen_Char[id]) then
                    local req = GetRequiredLevelForID(id)
                    if req and UnitLevel and UnitLevel("player") < req then
                        -- Level-locked openable: do not auto-open yet
                    elseif not ns.exclude[id]
                        and not (fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.disabled and fr0z3nUI_AutoOpen_Settings.disabled[id])
                        and not (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.disabled and fr0z3nUI_AutoOpen_CharSettings.disabled[id])
                    then
                        local info = C_Container.GetContainerItemInfo(b, s)
                        if info and info.hasLoot and not info.isLocked then
                            print("|cff00ccff[FAO]|r Opening ".. (info.hyperlink or id))
                            C_Container.UseContainerItem(b, s); lastOpenTime = GetTime(); return 
                        end
                    end
                end
            end
        end
    end
end

-- [ EVENTS ]
frame:RegisterEvent('BAG_UPDATE_DELAYED'); frame:RegisterEvent('PLAYER_LOGIN'); frame:RegisterEvent('PLAYER_REGEN_ENABLED')
frame:RegisterEvent('PLAYER_ENTERING_WORLD')
frame:RegisterEvent('PLAYER_LEVEL_UP')
frame:RegisterEvent('BANKFRAME_OPENED'); frame:RegisterEvent('BANKFRAME_CLOSED'); frame:RegisterEvent('MAIL_SHOW'); frame:RegisterEvent('MAIL_CLOSED')

frame:SetScript('OnEvent', function(self, event, ...)
    if event == "PLAYER_LOGIN" then 
        InitSV()
        ApplyAutoLootSettingOnWorld()
        ApplyNPCNameplatesSettingOnWorld()
        C_Timer.After(2, CheckTimersOnLogin)
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        isInitialLogin = isInitialLogin and true or false
        isReloadingUi = isReloadingUi and true or false
        InitSV()
        ApplyAutoLootSettingOnWorld()
        ApplyNPCNameplatesSettingOnWorld()
        AutoEnableGreatVaultAtMaxLevel()
        local mode = (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.greatVaultMode) or "OFF"
        mode = tostring(mode):upper()
        if mode == "ON" and isInitialLogin and not isReloadingUi then
            C_Timer.After(5, ns.ShowGreatVault)
        elseif mode == "RL" and isReloadingUi then
            C_Timer.After(5, ns.ShowGreatVault)
        end

        -- Talents: useful on /reload, portals, and instance transitions.
        talentCheckSeq = talentCheckSeq + 1
        local seq = talentCheckSeq
        C_Timer.After(2, function()
            MaybeHandleTalents(isInitialLogin, isReloadingUi, 0, seq)
        end)
    elseif event == "PLAYER_LEVEL_UP" then
        local newLevel = ...
        InitSV()
        local maxLevel = GetMaxPlayerLevelSafe()
        newLevel = tonumber(newLevel)
        if maxLevel and newLevel and newLevel >= maxLevel then
            local changed = AutoEnableGreatVaultAtMaxLevel()
            if changed then
                print("|cff00ccff[FAO]|r AutoOpen Great Vault On Login (|cffffff00/fao|r)")
            end
        end
    elseif event == "BANKFRAME_OPENED" then 
        atBank = true
    elseif event == "BANKFRAME_CLOSED" then 
        atBank = false
    elseif event == "MAIL_SHOW" then 
        atMail = true
    elseif event == "MAIL_CLOSED" then 
        atMail = false
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_REGEN_ENABLED" then
        C_Timer.After(0.3, function() self:RunScan() end)
    end
end)

-- [ TOOLTIP COUNTDOWN ]
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    local id = data and data.id

    if id then
        if ns.exclude and ns.exclude[id] then
            tooltip:AddLine("|cff00ccff[FAO]|r Item is |cffff0000Excluded|r")
        end

        if ns.items and ns.items[id] then
            tooltip:AddLine("|cff00ccff[FAO]|r Item is |cff00ff00Added|r")
        end

        if ns.timed and ns.timed[id] then
            tooltip:AddLine("|cff00ccff[FAO]|r Item is |cffffff00Timed|r")
        end

        if ns.levelLocked and ns.levelLocked[id] then
            local req = tonumber(ns.levelLocked[id][1])
            local level = (UnitLevel and UnitLevel("player")) or nil
            local ok = (req and level and level >= req) or false
            local color = ok and "|cff00ff00" or "|cffff9900"
            if req then
                if ok then
                    tooltip:AddLine("|cff00ccff[FAO]|r Item is "..color.."Level "..req.." Unlocked|r")
                else
                    tooltip:AddLine("|cff00ccff[FAO]|r Item is "..color.."Level "..req.." Locked|r")
                end
            else
                tooltip:AddLine("|cff00ccff[FAO]|r Item is "..color.."Level Locked|r")
            end
        end
    end

    if data.id and ns.timed and ns.timed[data.id] and type(fr0z3nUI_AutoOpen_Timers) == "table" and time then
        local duration = tonumber(ns.timed[data.id][1])
        local now = time()
        if duration and now then
            local guid = data.guid or data.itemGUID
            local tData = guid and fr0z3nUI_AutoOpen_Timers[guid] or nil
            if tData and tData.id == data.id then
                local startTime = tonumber(tData.startTime)
                if startTime then
                    local rem = duration - (now - startTime)
                    if rem > 0 then
                        tooltip:AddLine(" ")
                        tooltip:AddLine(string.format("|cff00ccffHatching In:|r |cffff0000%dd %dh %dm|r", math.floor(rem/86400), math.floor((rem%86400)/3600), math.ceil((rem%3600)/60)))
                    end
                end
            else
                -- Fallback: legacy timers or tooltips without GUID.
                for _, anyData in pairs(fr0z3nUI_AutoOpen_Timers) do
                    if anyData and anyData.id == data.id then
                        local startTime = tonumber(anyData.startTime)
                        if startTime then
                            local rem = duration - (now - startTime)
                            if rem > 0 then
                                tooltip:AddLine(" ")
                                tooltip:AddLine(string.format("|cff00ccffHatching In:|r |cffff0000%dd %dh %dm|r", math.floor(rem/86400), math.floor((rem%86400)/3600), math.ceil((rem%3600)/60)))
                            end
                        end
                        break
                    end
                end
            end
        end
    end
end)

-- [ SLASH COMMAND + SIMPLE OPTIONS WINDOW ]
local function AddItemByID(id, scope)
    if not id then print("|cff00ccff[FAO]|r Please enter a valid item ID.") return end
    InitSV()
    if ns.items and ns.items[id] then
        print("|cff00ccff[FAO]|r Already in addon database: "..(GetItemNameSafe(id) or id))
        return
    end
    if ns.exclude and ns.exclude[id] then
        local name = ns.exclude[id][1] or ("ID "..id)
        local reason = ns.exclude[id][2] or "Excluded"
        print("|cff00ccff[FAO]|r Excluded: |cffffff00"..name.."|r - "..reason)
        return
    end

    -- Guard: avoid adding non-openable items (e.g., gear).
    local ok, why = IsProbablyOpenableCacheID(id)
    if ok == nil then
        print("|cff00ccff[FAO]|r Item data still loading for ID "..id..". Try again in a second.")
        return
    end
    if ok == false then
        local reason = "Not an openable cache"
        if why == "equippable" then reason = "This looks equippable (not a cache)" end
        if why == "no_open_line" then reason = "No 'Right Click to Open' tooltip line" end
        print("|cff00ccff[FAO]|r Not added: |cffffff00"..(GetItemNameSafe(id) or ("ID "..id)).."|r - "..reason)
        return
    end
    if scope == "acc" then
        if fr0z3nUI_AutoOpen_Acc[id] then print("|cff00ccff[FAO]|r Already in Account whitelist: "..(GetItemNameSafe(id) or id)) return end
        fr0z3nUI_AutoOpen_Acc[id] = true
        if fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.disabled then
            fr0z3nUI_AutoOpen_Settings.disabled[id] = nil
        end
    else
        if fr0z3nUI_AutoOpen_Char[id] then print("|cff00ccff[FAO]|r Already in Character whitelist: "..(GetItemNameSafe(id) or id)) return end
        fr0z3nUI_AutoOpen_Char[id] = true
        if fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.disabled then
            fr0z3nUI_AutoOpen_CharSettings.disabled[id] = nil
        end
    end
    local iname = GetItemNameSafe(id) or tostring(id)
    print("|cff00ccff[FAO]|r Added: |cffffff00"..iname.."|r to "..(scope=="acc" and "Account" or "Character"))
end

local function CreateOptionsWindow()
    if fr0z3nUI_AutoOpenOptions then return end
    InitSV()
    local f = CreateFrame("Frame", "fr0z3nUI_AutoOpenOptions", UIParent, "BackdropTemplate")
    fr0z3nUI_AutoOpenOptions = f

    -- Allow closing with Escape.
    do
        local special = _G and _G["UISpecialFrames"]
        if type(special) == "table" then
            local name = "fr0z3nUI_AutoOpenOptions"
            local exists = false
            for i = 1, #special do
                if special[i] == name then exists = true break end
            end
            if not exists and table and table.insert then table.insert(special, name) end
        end
    end
    local FRAME_W, FRAME_H = 340, 210
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER")
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) if self.StopMovingOrSizing then self:StopMovingOrSizing() end end)
    f:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background", tile = true, tileSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 }})
    f:SetBackdropColor(0,0,0,0.7)

    local itemsPanel = CreateFrame("Frame", nil, f)
    itemsPanel:SetAllPoints()
    f.itemsPanel = itemsPanel

    local togglesPanel = CreateFrame("Frame", nil, f)
    togglesPanel:SetAllPoints()
    togglesPanel:Hide()
    f.togglesPanel = togglesPanel

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetJustifyH("LEFT")
    title:SetText("|cff00ccff[FAO]|r AutoOpen")

    local panelTemplatesSetNumTabs = _G and _G["PanelTemplates_SetNumTabs"]
    local panelTemplatesSetTab = _G and _G["PanelTemplates_SetTab"]

    local function SelectTab(tabID)
        f.activeTab = tabID
        if f.itemsPanel then f.itemsPanel:SetShown(tabID == 1) end
        if f.togglesPanel then f.togglesPanel:SetShown(tabID == 2) end
        if type(panelTemplatesSetTab) == "function" then
            panelTemplatesSetTab(f, tabID)
        end
    end
    f.SelectTab = SelectTab

    local function StyleTab(btn)
        if not btn then return end
        btn:SetHeight(22)

        local n = btn.GetNormalTexture and btn:GetNormalTexture() or nil
        if n and n.SetAlpha then n:SetAlpha(0.65) end
        local h = btn.GetHighlightTexture and btn:GetHighlightTexture() or nil
        if h and h.SetAlpha then h:SetAlpha(0.45) end
        local p = btn.GetPushedTexture and btn:GetPushedTexture() or nil
        if p and p.SetAlpha then p:SetAlpha(0.75) end
        local d = btn.GetDisabledTexture and btn:GetDisabledTexture() or nil
        if d and d.SetAlpha then d:SetAlpha(0.40) end
    end

    local tab1 = CreateFrame("Button", "$parentTab1", f, "PanelTabButtonTemplate")
    tab1:SetID(1)
    tab1:SetText("Items")
    tab1:SetPoint("LEFT", title, "RIGHT", 10, 0)
    tab1:SetScript("OnClick", function(self) SelectTab(self:GetID()) end)
    StyleTab(tab1)
    f.tab1 = tab1

    local tab2 = CreateFrame("Button", "$parentTab2", f, "PanelTabButtonTemplate")
    tab2:SetID(2)
    tab2:SetText("Toggles")
    tab2:SetPoint("LEFT", tab1, "RIGHT", -16, 0)
    tab2:SetScript("OnClick", function(self) SelectTab(self:GetID()) end)
    StyleTab(tab2)
    f.tab2 = tab2

    if type(panelTemplatesSetNumTabs) == "function" then
        panelTemplatesSetNumTabs(f, 2)
    end
    if type(panelTemplatesSetTab) == "function" then
        panelTemplatesSetTab(f, 1)
    end

    local function BumpFont(fs, delta)
        if not (fs and fs.GetFont and fs.SetFont) then return end
        local fontPath, fontSize, fontFlags = fs:GetFont()
        if fontPath and fontSize then
            fs:SetFont(fontPath, fontSize + (delta or 0), fontFlags)
        end
    end

    local info = itemsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    info:SetPoint("TOP", f, "TOP", 0, -54)
    info:SetText("Enter ItemID Below")
    BumpFont(info, 1)

    local edit = CreateFrame("EditBox", nil, itemsPanel, "InputBoxTemplate")
    edit:SetSize(175,38)
    edit:SetPoint("TOP", info, "BOTTOM", 0, -2)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(10)
    edit:SetTextInsets(6, 6, 0, 0)
    edit:SetJustifyH("CENTER")
    if edit.SetJustifyV then edit:SetJustifyV("MIDDLE") end
    if edit.SetNumeric then edit:SetNumeric(true) end
    if edit.GetFont and edit.SetFont then
        local fontPath, _, fontFlags = edit:GetFont()
        if fontPath then edit:SetFont(fontPath, 16, fontFlags) end
    end
    f.edit = edit

    -- Make the input look like a clean field (hide the template frame) + add a placeholder.
    local function HideEditBoxFrame(box)
        if not box or not box.GetRegions then return end
        for i = 1, select("#", box:GetRegions()) do
            local region = select(i, box:GetRegions())
            if region and region.Hide and region.GetObjectType and region:GetObjectType() == "Texture" then
                region:Hide()
            end
        end
    end
    HideEditBoxFrame(edit)

    local placeholder = itemsPanel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    placeholder:SetPoint("CENTER", edit, "CENTER", 0, 0)
    placeholder:SetText("Input Here")
    placeholder:SetTextColor(1, 1, 1, 0.35)
    f.inputPlaceholder = placeholder

    local function UpdatePlaceholder()
        if not f or not f.inputPlaceholder or not f.edit then return end
        local txt = f.edit:GetText() or ""
        local hasText = txt ~= ""
        local focused = f.edit.HasFocus and f.edit:HasFocus() or false
        f.inputPlaceholder:SetShown((not hasText) and (not focused))
    end
    f.UpdateInputPlaceholder = UpdatePlaceholder

    edit:SetScript("OnEditFocusGained", function()
        if f and f.inputPlaceholder then f.inputPlaceholder:Hide() end
    end)
    edit:SetScript("OnEditFocusLost", function()
        UpdatePlaceholder()
    end)

    -- Reserve a fixed space for name/reason so buttons never move.
    local textArea = CreateFrame("Frame", nil, itemsPanel)
    textArea:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -2)
    textArea:SetPoint("TOPRIGHT", edit, "BOTTOMRIGHT", 0, -2)
    textArea:SetPoint("BOTTOM", itemsPanel, "BOTTOM", 0, 58)
    if textArea.SetClipsChildren then textArea:SetClipsChildren(true) end

    local nameLabel = itemsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameLabel:SetPoint("TOP", textArea, "TOP", 0, 0)
    nameLabel:SetPoint("LEFT", textArea, "LEFT", 0, 0)
    nameLabel:SetPoint("RIGHT", textArea, "RIGHT", 0, 0)
    nameLabel:SetJustifyH("CENTER")
    nameLabel:SetWordWrap(true)
    nameLabel:SetText("")
    BumpFont(nameLabel, 1)
    f.nameLabel = nameLabel

    local reasonLabel = itemsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    reasonLabel:SetPoint("TOP", nameLabel, "BOTTOM", 0, -2)
    reasonLabel:SetPoint("LEFT", textArea, "LEFT", 0, 0)
    reasonLabel:SetPoint("RIGHT", textArea, "RIGHT", 0, 0)
    reasonLabel:SetJustifyH("CENTER")
    reasonLabel:SetWordWrap(true)
    reasonLabel:SetText("")
    BumpFont(reasonLabel, 1)
    f.reasonLabel = reasonLabel

    local BTN_W, BTN_H = 125, 22
    local PAD_X = 10
    local BTN_GAP = 14
    local ROW_TOP_Y = 30
    local ROW_BOTTOM_Y = 10
    local TOGGLE_ROW_AUTOLOOT_Y = 98
    local TOGGLE_ROW_TOP_Y = 72
    local TOGGLE_ROW_BOTTOM_Y = 46
    local TOGGLE_ROW_CACHE_Y = 20

    local cooldownLabel = togglesPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cooldownLabel:SetPoint("TOP", togglesPanel, "TOP", 0, -46)
    cooldownLabel:SetText(string.format("Open Cooldown: %.1fs", GetOpenCooldown()))
    f.cooldownLabel = cooldownLabel

    local cdSlider = CreateFrame("Slider", nil, togglesPanel, "UISliderTemplate")
    cdSlider:SetPoint("TOP", cooldownLabel, "BOTTOM", 0, -6)
    cdSlider:SetSize(FRAME_W - 60, 18)
    cdSlider:SetMinMaxValues(0, 10)
    cdSlider:SetValueStep(0.1)
    if cdSlider.SetObeyStepOnDrag then cdSlider:SetObeyStepOnDrag(true) end
    f.cdSlider = cdSlider

    local cdLow = togglesPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cdLow:SetPoint("TOPLEFT", cdSlider, "BOTTOMLEFT", 0, -2)
    cdLow:SetText("0.0s")

    local cdHigh = togglesPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cdHigh:SetPoint("TOPRIGHT", cdSlider, "BOTTOMRIGHT", 0, -2)
    cdHigh:SetText("10.0s")

    local function UpdateCooldownControls()
        InitSV()
        local current = GetOpenCooldown()
        if f.cdSlider then
            f.cdSlider._setting = true
            f.cdSlider:SetValue(current)
            f.cdSlider._setting = false
        end
        if f.cooldownLabel then
            f.cooldownLabel:SetText(string.format("Open Cooldown: %.1fs", current))
        end
    end

    cdSlider:SetScript("OnValueChanged", function(self, value)
        if self._setting then return end
        InitSV()
        local rounded = math.floor((tonumber(value) or 0) * 10 + 0.5) / 10
        local newCd = NormalizeCooldown(rounded)
        fr0z3nUI_AutoOpen_Settings.cooldown = newCd

        self._setting = true
        self:SetValue(newCd)
        self._setting = false

        if f.cooldownLabel then
            f.cooldownLabel:SetText(string.format("Open Cooldown: %.1fs", newCd))
        end
    end)

    local ADD_ROW_X = (BTN_W / 2) + (BTN_GAP / 2)

    local btnChar = CreateFrame("Button", nil, itemsPanel, "UIPanelButtonTemplate")
    btnChar:SetSize(BTN_W, BTN_H)
    btnChar:SetPoint("BOTTOM", itemsPanel, "BOTTOM", -ADD_ROW_X, 28)
    btnChar:SetText("Character")
    btnChar:Disable()
    f.btnChar = btnChar

    local btnAcc = CreateFrame("Button", nil, itemsPanel, "UIPanelButtonTemplate")
    btnAcc:SetSize(BTN_W, BTN_H)
    btnAcc:SetPoint("BOTTOM", itemsPanel, "BOTTOM", ADD_ROW_X, 28)
    btnAcc:SetText("Account")
    btnAcc:Disable()
    f.btnAcc = btnAcc

    local DoValidate

    local function IsOpenableID(id)
        if not id then return false end
        if ns and ns.items and ns.items[id] then return true end
        if fr0z3nUI_AutoOpen_Acc and fr0z3nUI_AutoOpen_Acc[id] then return true end
        if fr0z3nUI_AutoOpen_Char and fr0z3nUI_AutoOpen_Char[id] then return true end
        return false
    end

    local function SetButtonState(btn, label, isDisabled)
        if not btn then return end
        if isDisabled then
            btn:SetText("|cffffff00"..label.."|r") -- yellow = re-enable
        else
            btn:SetText("|cffff0000"..label.."|r") -- red = disable
        end
    end

    local function UpdateScopeButtons(id)
        InitSV()
        if not id then
            if f.btnChar then f.btnChar:Disable() end
            if f.btnAcc then f.btnAcc:Disable() end
            return
        end

        local openable = IsOpenableID(id)

        if openable then
            if f.reasonLabel then
                f.reasonLabel:SetText("|cffaaaaaaRed = disable auto-open. Yellow = re-enable.|r")
            end

            if f.btnAcc then
                f.btnAcc:Enable()
                local isDisabledAcc = (fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.disabled and fr0z3nUI_AutoOpen_Settings.disabled[id]) and true or false
                SetButtonState(f.btnAcc, "Account", isDisabledAcc)
                f.btnAcc:SetScript("OnClick", function()
                    InitSV()
                    local t = fr0z3nUI_AutoOpen_Settings.disabled
                    if t[id] then
                        t[id] = nil
                        print("|cff00ccff[FAO]|r '"..(GetItemNameSafe(id) or id).."' will now open on Account")
                    else
                        t[id] = true
                        print("|cff00ccff[FAO]|r '"..(GetItemNameSafe(id) or id).."' will NOT open on Account")
                    end
                    UpdateScopeButtons(id)
                end)
            end

            if f.btnChar then
                f.btnChar:Enable()
                local isDisabledChar = (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.disabled and fr0z3nUI_AutoOpen_CharSettings.disabled[id]) and true or false
                SetButtonState(f.btnChar, "Character", isDisabledChar)
                f.btnChar:SetScript("OnClick", function()
                    InitSV()
                    local t = fr0z3nUI_AutoOpen_CharSettings.disabled
                    if t[id] then
                        t[id] = nil
                        print("|cff00ccff[FAO]|r '"..(GetItemNameSafe(id) or id).."' will now open on Character")
                    else
                        t[id] = true
                        print("|cff00ccff[FAO]|r '"..(GetItemNameSafe(id) or id).."' will NOT open on Character")
                    end
                    UpdateScopeButtons(id)
                end)
            end
        else
            if f.reasonLabel then f.reasonLabel:SetText("") end

            if f.btnAcc then
                f.btnAcc:Enable()
                f.btnAcc:SetText("Account")
                f.btnAcc:SetScript("OnClick", function()
                    local id2 = f.validID or tonumber(edit:GetText() or "")
                    AddItemByID(id2, "acc")
                    DoValidate()
                end)
            end
            if f.btnChar then
                f.btnChar:Enable()
                f.btnChar:SetText("Character")
                f.btnChar:SetScript("OnClick", function()
                    local id2 = f.validID or tonumber(edit:GetText() or "")
                    AddItemByID(id2, "char")
                    DoValidate()
                end)
            end
        end
    end

    local function UpdateAutoOpenButton()
        InitSV()
        local enabled = (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.autoOpen ~= false)
        if f.btnAutoOpen then
            f.btnAutoOpen:SetText("Auto Open: "..(enabled and "ON" or "OFF"))
        end
    end

    local function UpdateAutoLootButton()
        InitSV()
        local enabled = (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.autoLootOnLogin) and true or false
        if f.btnAutoLoot then
            f.btnAutoLoot:SetText("Auto Loot: "..(enabled and "ON" or "OFF"))
        end
    end

    local function UpdateNPCNameButton()
        InitSV()
        if not f.btnNPCName then return end

        local acc = fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.npcNameplatesAccount
        if acc == true then
            f.btnNPCName:SetText("NPC Name: ON ACC")
        elseif acc == false then
            f.btnNPCName:SetText("NPC Name: OFF ACC")
        else
            local enabled = GetNPCNameplatesSettingEffective()
            f.btnNPCName:SetText("NPC Name: "..(enabled and "ON" or "OFF"))
        end
    end

    local function UpdateGreatVaultButton()
        InitSV()
        local mode = (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.greatVaultMode) or "OFF"
        mode = tostring(mode):upper()
        if f.btnGreatVault then
            f.btnGreatVault:SetText("Great Vault: "..mode)
        end
    end

    local function UpdateCacheLockButton()
        InitSV()
        local enabled = (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.cacheLockCheck ~= false)
        if f.btnCacheLock then
            f.btnCacheLock:SetText("Cache: "..(enabled and "ON" or "OFF"))
        end
    end

    local function UpdateTalentButtons()
        InitSV()
        local mode = tostring((fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.talentMode) or "WORLD"):upper()
        local uiMode = GetTalentAutoOpenMode()

        if f.btnTalentsMode then
            f.btnTalentsMode:SetText("Talents: "..mode)
        end
        if f.btnTalentsAuto then
            if uiMode == "ACC" then
                f.btnTalentsAuto:SetText("Talent UI: ON ACC")
            elseif uiMode == "CHAR" then
                f.btnTalentsAuto:SetText("Talent UI: ON")
            else
                f.btnTalentsAuto:SetText("Talent UI: OFF")
            end
        end
    end

    local btnAutoLoot = CreateFrame("Button", nil, togglesPanel, "UIPanelButtonTemplate")
    btnAutoLoot:SetSize(BTN_W, BTN_H)
    btnAutoLoot:SetPoint("BOTTOMLEFT", f, "BOTTOM", BTN_GAP/2, TOGGLE_ROW_AUTOLOOT_Y)
    btnAutoLoot:SetScript("OnClick", function()
        InitSV()
        local cur = (fr0z3nUI_AutoOpen_CharSettings.autoLootOnLogin) and true or false
        fr0z3nUI_AutoOpen_CharSettings.autoLootOnLogin = not cur
        if fr0z3nUI_AutoOpen_CharSettings.autoLootOnLogin then
            local ok = SetAutoLootDefaultSafe(true)
            if ok then
                print("|cff00ccff[FAO]|r Auto Loot on login: |cff00ff00ON|r")
            else
                print("|cff00ccff[FAO]|r Auto Loot on login: |cff00ff00ON|r (but failed to set CVar)")
            end
        else
            print("|cff00ccff[FAO]|r Auto Loot on login: |cffff0000OFF|r")
        end
        UpdateAutoLootButton()
    end)
    btnAutoLoot:SetScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:SetOwner(f, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("BOTTOM", btnAutoLoot, "TOP", 0, 10)
            GameTooltip:SetText("Auto Loot")
            GameTooltip:AddLine("ON: forces Auto Loot to be enabled on world entry.", 1, 1, 1, true)
            GameTooltip:AddLine("(login, /reload, portals, instances)", 1, 1, 1, true)
            GameTooltip:AddLine("OFF: does not change your setting.", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    btnAutoLoot:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    f.btnAutoLoot = btnAutoLoot

    local btnNPCName = CreateFrame("Button", nil, togglesPanel, "UIPanelButtonTemplate")
    btnNPCName:SetSize(BTN_W, BTN_H)
    btnNPCName:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -BTN_GAP/2, TOGGLE_ROW_AUTOLOOT_Y)
    btnNPCName:SetScript("OnClick", function()
        InitSV()
        local acc = fr0z3nUI_AutoOpen_Settings.npcNameplatesAccount
        if acc == nil then
            fr0z3nUI_AutoOpen_CharSettings.npcNameplates = true
            fr0z3nUI_AutoOpen_Settings.npcNameplatesAccount = true
            print("|cff00ccff[FAO]|r NPC Name: |cff00ff00ON ACC|r")
        elseif acc == true then
            fr0z3nUI_AutoOpen_Settings.npcNameplatesAccount = false
            print("|cff00ccff[FAO]|r NPC Name: |cffff0000OFF ACC|r")
        else
            fr0z3nUI_AutoOpen_Settings.npcNameplatesAccount = nil
            fr0z3nUI_AutoOpen_CharSettings.npcNameplates = true
            print("|cff00ccff[FAO]|r NPC Name: |cff00ff00ON|r")
        end
        ApplyNPCNameplatesSettingOnWorld()
        UpdateNPCNameButton()
    end)
    btnNPCName:SetScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:SetOwner(f, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("BOTTOM", btnNPCName, "TOP", 0, 10)
            GameTooltip:SetText("Friendly NPC Nameplates")
            GameTooltip:AddLine("Cycles: ON (default) -> ON ACC -> OFF ACC", 1, 1, 1, true)
            local cur = GetFriendlyNPCNameplatesSafe()
            if cur ~= nil then
                GameTooltip:AddLine("Current CVar: "..(cur and "ON" or "OFF"), 1, 1, 1, true)
            end
            GameTooltip:Show()
        end
    end)
    btnNPCName:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    f.btnNPCName = btnNPCName

    local btnAutoOpen = CreateFrame("Button", nil, togglesPanel, "UIPanelButtonTemplate")
    btnAutoOpen:SetSize(BTN_W, BTN_H)
    btnAutoOpen:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -BTN_GAP/2, TOGGLE_ROW_TOP_Y)
    btnAutoOpen:SetScript("OnClick", function()
        InitSV()
        local enabled = (fr0z3nUI_AutoOpen_CharSettings.autoOpen ~= false)
        fr0z3nUI_AutoOpen_CharSettings.autoOpen = not enabled
        if fr0z3nUI_AutoOpen_CharSettings.autoOpen then
            print("|cff00ccff[FAO]|r Auto Open: |cff00ff00ON|r")
            C_Timer.After(0.1, function() if frame and frame.RunScan then frame:RunScan() end end)
        else
            print("|cff00ccff[FAO]|r Auto Open: |cffff0000OFF|r")
        end
        UpdateAutoOpenButton()
    end)
    f.btnAutoOpen = btnAutoOpen

    local btnGreatVault = CreateFrame("Button", nil, togglesPanel, "UIPanelButtonTemplate")
    btnGreatVault:SetSize(BTN_W, BTN_H)
    btnGreatVault:SetPoint("BOTTOMLEFT", f, "BOTTOM", BTN_GAP/2, TOGGLE_ROW_TOP_Y)
    btnGreatVault:SetScript("OnClick", function()
        InitSV()
        local current = tostring(fr0z3nUI_AutoOpen_CharSettings.greatVaultMode or "OFF"):upper()
        local nextMode
        if current == "OFF" then nextMode = "ON"
        elseif current == "ON" then nextMode = "RL"
        else nextMode = "OFF" end
        fr0z3nUI_AutoOpen_CharSettings.greatVaultMode = nextMode
        fr0z3nUI_AutoOpen_CharSettings.greatVaultTouched = true

        if nextMode == "OFF" then
            print("|cff00ccff[FAO]|r AutoOpen Great Vault Off")
        elseif nextMode == "ON" then
            print("|cff00ccff[FAO]|r AutoOpen Great Vault On Login")
            if ns and ns.ShowGreatVault then C_Timer.After(0.1, ns.ShowGreatVault) end
        else
            print("|cff00ccff[FAO]|r AutoOpen Great Vault On Reload")
            if ns and ns.ShowGreatVault then C_Timer.After(0.1, ns.ShowGreatVault) end
        end
        UpdateGreatVaultButton()
    end)
    btnGreatVault:SetScript("OnEnter", function()
        InitSV()
        local mode = (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.greatVaultMode) or "OFF"
        mode = tostring(mode):upper()
        if mode == "OFF" then
            if GameTooltip then
                GameTooltip:SetOwner(f, "ANCHOR_NONE")
                GameTooltip:ClearAllPoints()
                GameTooltip:SetPoint("LEFT", btnGreatVault, "RIGHT", 8, 0)
                GameTooltip:SetText("Enable Great Vault")
                GameTooltip:AddLine("AutoOpen at Login", 1, 1, 1, true)
                GameTooltip:Show()
            end
        end
    end)
    btnGreatVault:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    f.btnGreatVault = btnGreatVault

    local btnCacheLock = CreateFrame("Button", nil, togglesPanel, "UIPanelButtonTemplate")
    btnCacheLock:SetSize(BTN_W, BTN_H)
    btnCacheLock:SetPoint("BOTTOMLEFT", f, "BOTTOM", BTN_GAP/2, TOGGLE_ROW_CACHE_Y)
    btnCacheLock:SetScript("OnClick", function()
        InitSV()
        local cur = (fr0z3nUI_AutoOpen_CharSettings.cacheLockCheck ~= false)
        fr0z3nUI_AutoOpen_CharSettings.cacheLockCheck = not cur
        print("|cff00ccff[FAO]|r Cache Lock: "..(fr0z3nUI_AutoOpen_CharSettings.cacheLockCheck and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        UpdateCacheLockButton()
    end)
    btnCacheLock:SetScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:SetOwner(f, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("TOP", btnCacheLock, "BOTTOM", 0, -6)
            GameTooltip:SetText("Cache Lock")
            GameTooltip:AddLine("ON: only allow manual adds if the tooltip shows 'Right Click to Open'.", 1, 1, 1, true)
            GameTooltip:AddLine("OFF: bypass this check (advanced / use with care).", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    btnCacheLock:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    f.btnCacheLock = btnCacheLock

    local btnReset = CreateFrame("Button", nil, togglesPanel, "UIPanelButtonTemplate")
    btnReset:SetSize(BTN_W, BTN_H)
    btnReset:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -BTN_GAP/2, TOGGLE_ROW_CACHE_Y)
    btnReset:SetText("Reset SV")
    btnReset:SetScript("OnClick", function()
        if not (IsShiftKeyDown and IsShiftKeyDown()) then
            print("|cff00ccff[FAO]|r Hold |cffffff00SHIFT|r and click to reset all saved variables.")
            return
        end

        fr0z3nUI_AutoOpen_Acc = {}
        fr0z3nUI_AutoOpen_Char = {}
        fr0z3nUI_AutoOpen_Settings = {}
        fr0z3nUI_AutoOpen_CharSettings = {}
        fr0z3nUI_AutoOpen_Timers = {}
        didPruneCustomWhitelists = false

        InitSV()

        if f.edit then f.edit:SetText("") end
        if f.nameLabel then f.nameLabel:SetText("") end
        if f.reasonLabel then f.reasonLabel:SetText("") end
        f.validID = nil
        if f.btnChar then f.btnChar:Disable() end
        if f.btnAcc then f.btnAcc:Disable() end

        UpdateAutoOpenButton()
        UpdateAutoLootButton()
        UpdateNPCNameButton()
        UpdateGreatVaultButton()
        UpdateCacheLockButton()
        UpdateTalentButtons()
        UpdateCooldownControls()
        if f.UpdateInputPlaceholder then f.UpdateInputPlaceholder() end

        print("|cff00ccff[FAO]|r SavedVariables reset. (Optional: /reload)")
    end)
    btnReset:SetScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:SetOwner(f, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("TOP", btnReset, "BOTTOM", 0, -6)
            GameTooltip:SetText("Reset SavedVariables")
            GameTooltip:AddLine("Resets: whitelists, per-char settings, account settings, timers.", 1, 1, 1, true)
            GameTooltip:AddLine("Hold SHIFT and click to confirm.", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    btnReset:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    local btnTalentsMode = CreateFrame("Button", nil, togglesPanel, "UIPanelButtonTemplate")
    btnTalentsMode:SetSize(BTN_W, BTN_H)
    btnTalentsMode:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -BTN_GAP/2, TOGGLE_ROW_BOTTOM_Y)
    btnTalentsMode:SetScript("OnClick", function()
        InitSV()
        local current = tostring(fr0z3nUI_AutoOpen_CharSettings.talentMode or "WORLD"):upper()
        local nextMode
        if current == "OFF" then nextMode = "LOGIN"
        elseif current == "LOGIN" then nextMode = "RL"
        elseif current == "RL" then nextMode = "WORLD"
        else nextMode = "OFF" end

        fr0z3nUI_AutoOpen_CharSettings.talentMode = nextMode
        if nextMode == "OFF" then
            print("|cff00ccff[FAO]|r Talent reminder Off")
        elseif nextMode == "LOGIN" then
            print("|cff00ccff[FAO]|r Talent reminder On Login")
        elseif nextMode == "RL" then
            print("|cff00ccff[FAO]|r Talent reminder On Reload")
        else
            print("|cff00ccff[FAO]|r Talent reminder On World Enter (reload/portal/instance)")
        end
        UpdateTalentButtons()
    end)
    btnTalentsMode:SetScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:SetOwner(f, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("LEFT", btnTalentsMode, "RIGHT", 8, 0)
            GameTooltip:SetText("Talent Reminder")
            GameTooltip:AddLine("OFF = disabled", 1, 1, 1, true)
            GameTooltip:AddLine("LOGIN = initial login only", 1, 1, 1, true)
            GameTooltip:AddLine("RL = /reload only", 1, 1, 1, true)
            GameTooltip:AddLine("WORLD = reload + portals/instances", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    btnTalentsMode:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    f.btnTalentsMode = btnTalentsMode

    local btnTalentsAuto = CreateFrame("Button", nil, togglesPanel, "UIPanelButtonTemplate")
    btnTalentsAuto:SetSize(BTN_W, BTN_H)
    btnTalentsAuto:SetPoint("BOTTOMLEFT", f, "BOTTOM", BTN_GAP/2, TOGGLE_ROW_BOTTOM_Y)
    btnTalentsAuto:SetScript("OnClick", function()
        InitSV()
        local mode = GetTalentAutoOpenMode()
        if mode == "OFF" then
            fr0z3nUI_AutoOpen_CharSettings.talentAutoOpen = true
            fr0z3nUI_AutoOpen_Settings.talentAutoOpenAccount = nil
            print("|cff00ccff[FAO]|r Talent UI: ON (Character)")
        elseif mode == "CHAR" then
            fr0z3nUI_AutoOpen_Settings.talentAutoOpenAccount = true
            print("|cff00ccff[FAO]|r Talent UI: ON (Account)")
        else
            -- Leaving account override: clear it and revert back to character OFF.
            fr0z3nUI_AutoOpen_Settings.talentAutoOpenAccount = nil
            fr0z3nUI_AutoOpen_CharSettings.talentAutoOpen = false
            print("|cff00ccff[FAO]|r Talent UI: OFF")
        end
        UpdateTalentButtons()
    end)
    btnTalentsAuto:SetScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:SetOwner(f, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("LEFT", btnTalentsAuto, "RIGHT", 8, 0)
            GameTooltip:SetText("Auto-Open Talents")
            GameTooltip:AddLine("When unspent points are detected (> 0), attempts to open the talents UI (out of combat).", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    btnTalentsAuto:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    f.btnTalentsAuto = btnTalentsAuto

    -- debounced validation function
    DoValidate = function()
        local text = (edit:GetText() or "")
        if text == "" then
            if f.nameLabel then f.nameLabel:SetText("") end
            if f.reasonLabel then f.reasonLabel:SetText("") end
            f.validID = nil
            if f.btnChar then f.btnChar:Disable() end
            if f.btnAcc then f.btnAcc:Disable() end
            return
        end
        local id = tonumber(text)
        if not id then
            if f.nameLabel then f.nameLabel:SetText("|cffff0000Invalid ID|r") end
            if f.reasonLabel then f.reasonLabel:SetText("") end
            f.validID = nil
            if f.btnChar then f.btnChar:Disable() end
            if f.btnAcc then f.btnAcc:Disable() end
            return
        end

        local req, lockedName = GetRequiredLevelForID(id)
        if req and UnitLevel and UnitLevel("player") < req then
            local displayName = lockedName or GetItemNameSafe(id) or ("ID "..id)
            if f.nameLabel then f.nameLabel:SetText("|cffffff00"..displayName.."|r") end
            if f.reasonLabel then f.reasonLabel:SetText("|cffff9900Requires level "..req.." (will not auto-open yet)|r") end
            f.validID = id
            UpdateScopeButtons(id)
            return
        end

        local iname = GetItemNameSafe(id)
        if ns.exclude and ns.exclude[id] then
            local exName = ns.exclude[id][1] or iname or ("ID "..id)
            local reason = ns.exclude[id][2] or "Excluded"
            if f.nameLabel then f.nameLabel:SetText("|cffffff00"..exName.."|r") end
            if f.reasonLabel then f.reasonLabel:SetText("|cffff9900Excluded: "..reason.."|r") end
            f.validID = nil
            if f.btnChar then f.btnChar:Disable() end
            if f.btnAcc then f.btnAcc:Disable() end
            return
        end

        if iname then
            if f.nameLabel then f.nameLabel:SetText("|cffffff00"..iname.."|r") end

            local alreadyWhitelisted = IsOpenableID(id)
            local ok, why = IsProbablyOpenableCacheID(id)

            if ok == nil and not alreadyWhitelisted then
                if f.reasonLabel then f.reasonLabel:SetText("|cffaaaaaaLoading item data...|r") end
                f.validID = nil
                if f.btnChar then f.btnChar:Disable() end
                if f.btnAcc then f.btnAcc:Disable() end
                return
            end

            if ok == false and not alreadyWhitelisted then
                local reason = "Not an openable cache"
                if why == "equippable" then reason = "This looks equippable (not a cache)" end
                if why == "no_open_line" then reason = "No 'Right Click to Open' tooltip line" end
                if f.reasonLabel then f.reasonLabel:SetText("|cffff9900"..reason.."|r") end
                f.validID = nil
                if f.btnChar then f.btnChar:Disable() end
                if f.btnAcc then f.btnAcc:Disable() end
                return
            end

            if ok == false and alreadyWhitelisted then
                if f.reasonLabel then f.reasonLabel:SetText("|cffff9900Warning: this does not look openable (still allowing disable/re-enable).|r") end
            else
                if f.reasonLabel then f.reasonLabel:SetText("") end
            end

            f.validID = id
            UpdateScopeButtons(id)
        else
            if f.nameLabel then f.nameLabel:SetText("|cffff0000Item not found (may need cache)|r") end
            if f.reasonLabel then f.reasonLabel:SetText("") end
            f.validID = nil
            if f.btnChar then f.btnChar:Disable() end
            if f.btnAcc then f.btnAcc:Disable() end
        end
    end

    edit:SetScript("OnTextChanged", function(self, userInput)
        local txt = self:GetText() or ""

        if userInput then
            -- Some clients still allow non-digits even with SetNumeric(true); sanitize safely.
            local cleaned = txt:gsub("%D", "")
            if txt ~= cleaned then
                self:SetText(cleaned)
                if self.SetCursorPosition then self:SetCursorPosition(#cleaned) end
                txt = cleaned
            end
        end

        -- Clear previous validation when text changes.
        if fr0z3nUI_AutoOpenOptions then
            if fr0z3nUI_AutoOpenOptions.UpdateInputPlaceholder then
                fr0z3nUI_AutoOpenOptions.UpdateInputPlaceholder()
            end

            fr0z3nUI_AutoOpenOptions.validID = nil
            if fr0z3nUI_AutoOpenOptions.nameLabel then fr0z3nUI_AutoOpenOptions.nameLabel:SetText("") end
            if fr0z3nUI_AutoOpenOptions.reasonLabel then fr0z3nUI_AutoOpenOptions.reasonLabel:SetText("") end
            if fr0z3nUI_AutoOpenOptions.btnChar then fr0z3nUI_AutoOpenOptions.btnChar:Disable() end
            if fr0z3nUI_AutoOpenOptions.btnAcc then fr0z3nUI_AutoOpenOptions.btnAcc:Disable() end

            -- Only debounce validate on real user edits (not programmatic SetText).
            if userInput then
                if fr0z3nUI_AutoOpenOptions._validateTimer then fr0z3nUI_AutoOpenOptions._validateTimer:Cancel() end
                fr0z3nUI_AutoOpenOptions._validateTimer = C_Timer.NewTimer(0.7, DoValidate)
            end
        end
    end)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    f:SetScript("OnShow", function()
        InitSV()
        UpdateAutoOpenButton()
        UpdateAutoLootButton()
        UpdateNPCNameButton()
        UpdateGreatVaultButton()
        UpdateCacheLockButton()
        UpdateTalentButtons()
        UpdateCooldownControls()

        if f.UpdateInputPlaceholder then f.UpdateInputPlaceholder() end

        if f.activeTab == nil then f.activeTab = 1 end
        SelectTab(f.activeTab)
    end)

    UpdateAutoOpenButton()
    UpdateAutoLootButton()
    UpdateNPCNameButton()
    UpdateGreatVaultButton()
    UpdateCacheLockButton()
    UpdateTalentButtons()
    UpdateCooldownControls()
    SelectTab(1)
    f:Hide()
end

-- /fao opens the GUI (no /fao add)
SLASH_FAO1 = "/fao"
SLASH_FAO2 = "/frozenautoopen"
SlashCmdList["FAO"] = function(msg)
    InitSV()
    local text = (msg and msg:gsub("^%s+", ""):gsub("%s+$", "")) or ""
    local cmd, arg = text:match("^(%S+)%s*(%S*)")
    cmd = cmd and cmd:lower() or nil
    arg = arg and arg:lower() or ""

    if text == "?" or cmd == "?" or cmd == "help" then
        print("|cff00ccff[FAO]|r Commands:")
        print("|cff00ccff[FAO]|r /fao              - open/toggle window")
        print("|cff00ccff[FAO]|r /fao <itemid>      - open window + set item id")
        print("|cff00ccff[FAO]|r /fao ao on|off     - auto-open containers")
        print("|cff00ccff[FAO]|r /fao autoloot       - toggle forcing Auto Loot ON at login")
        print("|cff00ccff[FAO]|r /fao cd <seconds>  - open cooldown (0-10)")
        print("|cff00ccff[FAO]|r /fao gv            - cycle Great Vault OFF/ON/RL")
        print("|cff00ccff[FAO]|r /fao talents       - talent reminder help")
        print("|cff00ccff[FAO]|r /fao debug talents - toggle talent debug output")
        return
    end

    if cmd == "autoloot" or cmd == "loot" or cmd == "al" then
        local state = arg
        local enforce = (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.autoLootOnLogin) and true or false

        if state == "" or state == "toggle" then
            enforce = not enforce
        elseif state == "on" or state == "1" or state == "true" then
            enforce = true
        elseif state == "off" or state == "0" or state == "false" then
            enforce = false
        elseif state == "status" then
            -- no-op
        else
            print("|cff00ccff[FAO]|r Usage: /fao autoloot [on|off|toggle|status]")
            return
        end

        fr0z3nUI_AutoOpen_CharSettings.autoLootOnLogin = enforce

        if enforce then
            local ok = SetAutoLootDefaultSafe(true)
            if not ok then
                print("|cff00ccff[FAO]|r Auto Loot: |cffff0000failed to set CVar|r")
            end
        end

        local cur = GetAutoLootDefaultSafe()
        local curText = (cur == nil) and "unknown" or (cur and "ON" or "OFF")
        print("|cff00ccff[FAO]|r Auto Loot on login: " .. (enforce and "|cff00ff00ON|r" or "|cffff0000OFF|r") .. " (current: |cffffff00" .. curText .. "|r)")
        return
    end

    if cmd == "debug" or cmd == "dbg" then
        local target, state = text:match("^%S+%s+(%S+)%s*(%S*)")
        target = target and target:lower() or ""
        state = state and state:lower() or ""

        if target == "talents" or target == "talent" then
            local cur = (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.debugTalents) and true or false
            local nextVal = cur

            if state == "" or state == "toggle" then
                nextVal = not cur
            elseif state == "on" or state == "1" or state == "true" then
                nextVal = true
            elseif state == "off" or state == "0" or state == "false" then
                nextVal = false
            elseif state == "status" then
                nextVal = cur
            else
                print("|cff00ccff[FAO]|r Usage: /fao debug talents [on|off|toggle|status]")
                return
            end

            fr0z3nUI_AutoOpen_CharSettings.debugTalents = nextVal
            print("|cff00ccff[FAO]|r Talent debug: " .. (nextVal and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
            return
        end

        print("|cff00ccff[FAO]|r Usage: /fao debug talents [on|off|toggle|status]")
        return
    end

    if cmd == "cd" or cmd == "cooldown" then
        if arg == "" then
            print(string.format("|cff00ccff[FAO]|r Cooldown: |cffffff00%.1fs|r", GetOpenCooldown()))
            return
        end

        local raw = tonumber(arg)
        if not raw then
            print("|cff00ccff[FAO]|r Usage: /fao cd <seconds>")
            print(string.format("|cff00ccff[FAO]|r Current: |cffffff00%.1fs|r", GetOpenCooldown()))
            return
        end

        local newCd = NormalizeCooldown(raw)
        fr0z3nUI_AutoOpen_Settings.cooldown = newCd
        print(string.format("|cff00ccff[FAO]|r Cooldown set to: |cffffff00%.1fs|r", newCd))
        return
    end

    -- Subcommands
    if cmd == "ao" then
        if arg == "" or arg == "toggle" then
            local enabled = (fr0z3nUI_AutoOpen_CharSettings.autoOpen ~= false)
            fr0z3nUI_AutoOpen_CharSettings.autoOpen = not enabled
            arg = fr0z3nUI_AutoOpen_CharSettings.autoOpen and "on" or "off"
        end

        if arg == "off" then
            fr0z3nUI_AutoOpen_CharSettings.autoOpen = false
            print("|cff00ccff[FAO]|r Auto Open: |cffff0000OFF|r")
        elseif arg == "on" then
            fr0z3nUI_AutoOpen_CharSettings.autoOpen = true
            print("|cff00ccff[FAO]|r Auto Open: |cff00ff00ON|r")
            C_Timer.After(0.1, function() if frame and frame.RunScan then frame:RunScan() end end)
        else
            print("|cff00ccff[FAO]|r Usage: /fao ao        - toggle auto open")
            print("|cff00ccff[FAO]|r Usage: /fao ao on     - enable auto open")
            print("|cff00ccff[FAO]|r Usage: /fao ao off    - disable auto open")
        end
        return
    end

    if cmd == "gv" or cmd == "greatvault" then
        if arg == "" or arg == "toggle" then
            local current = tostring(fr0z3nUI_AutoOpen_CharSettings.greatVaultMode or "OFF"):upper()
            if current == "OFF" then fr0z3nUI_AutoOpen_CharSettings.greatVaultMode = "ON"
            elseif current == "ON" then fr0z3nUI_AutoOpen_CharSettings.greatVaultMode = "RL"
            else fr0z3nUI_AutoOpen_CharSettings.greatVaultMode = "OFF" end
            arg = fr0z3nUI_AutoOpen_CharSettings.greatVaultMode:lower()
        end

        if arg == "off" then
            fr0z3nUI_AutoOpen_CharSettings.greatVaultMode = "OFF"
            fr0z3nUI_AutoOpen_CharSettings.greatVaultTouched = true
            print("|cff00ccff[FAO]|r AutoOpen Great Vault Off")
        elseif arg == "on" then
            fr0z3nUI_AutoOpen_CharSettings.greatVaultMode = "ON"
            fr0z3nUI_AutoOpen_CharSettings.greatVaultTouched = true
            print("|cff00ccff[FAO]|r AutoOpen Great Vault On Login")
            C_Timer.After(0.1, ns.ShowGreatVault)
        elseif arg == "rl" or arg == "reload" then
            fr0z3nUI_AutoOpen_CharSettings.greatVaultMode = "RL"
            fr0z3nUI_AutoOpen_CharSettings.greatVaultTouched = true
            print("|cff00ccff[FAO]|r AutoOpen Great Vault On Reload")
            C_Timer.After(0.1, ns.ShowGreatVault)
        else
            print("|cff00ccff[FAO]|r Usage: /fao gv           - cycle OFF/ON/RL")
            print("|cff00ccff[FAO]|r Usage: /fao gv off       - disable")
            print("|cff00ccff[FAO]|r Usage: /fao gv on        - show at login")
            print("|cff00ccff[FAO]|r Usage: /fao gv rl        - show on /reload")
        end
        return
    end

    if cmd == "talent" or cmd == "talents" then
        local sub, subarg = text:match("^%S+%s+(%S+)%s*(%S*)")
        sub = sub and sub:lower() or ""
        subarg = subarg and subarg:lower() or ""

        local function PrintTalentStatus()
            local mode = tostring(fr0z3nUI_AutoOpen_CharSettings.talentMode or "WORLD"):upper()
            local uiMode = GetTalentAutoOpenMode()
            local ui = (uiMode == "ACC") and "ON ACC" or (uiMode == "CHAR" and "ON" or "OFF")
            print("|cff00ccff[FAO]|r Talents: "..mode.." (UI: "..ui..")")
        end

        if arg == "" and sub == "" then
            PrintTalentStatus()
            print("|cff00ccff[FAO]|r Usage: /fao talents toggle")
            print("|cff00ccff[FAO]|r Usage: /fao talents off|login|rl|world")
            print("|cff00ccff[FAO]|r Usage: /fao talents ui off|on|acc")
            print("|cff00ccff[FAO]|r Usage: /fao talents check")
            return
        end

        if arg == "toggle" then
            local current = tostring(fr0z3nUI_AutoOpen_CharSettings.talentMode or "WORLD"):upper()
            if current == "OFF" then fr0z3nUI_AutoOpen_CharSettings.talentMode = "LOGIN"
            elseif current == "LOGIN" then fr0z3nUI_AutoOpen_CharSettings.talentMode = "RL"
            elseif current == "RL" then fr0z3nUI_AutoOpen_CharSettings.talentMode = "WORLD"
            else fr0z3nUI_AutoOpen_CharSettings.talentMode = "OFF" end
            PrintTalentStatus()
            return
        end

        if arg == "check" then
            MaybeHandleTalents(true, false)
            return
        end

        if arg == "ui" and subarg ~= "" then
            local v = tostring(subarg):lower()
            if v == "0" or v == "false" then v = "off" end
            if v == "1" or v == "true" then v = "on" end
            if v == "reload" then v = "rl" end

            if v == "rl" or v == "world" then v = "on" end
            if v == "acc" or v == "account" or v == "onacc" then
                fr0z3nUI_AutoOpen_Settings.talentAutoOpenAccount = true
            elseif v == "off" or v == "on" then
                -- Any character choosing OFF/ON clears account override.
                fr0z3nUI_AutoOpen_Settings.talentAutoOpenAccount = nil
                fr0z3nUI_AutoOpen_CharSettings.talentAutoOpen = (v == "on")
            else
                print("|cff00ccff[FAO]|r Usage: /fao talents ui off|on|acc")
                return
            end
            PrintTalentStatus()
            return
        end

        if arg == "off" or arg == "login" or arg == "rl" or arg == "reload" or arg == "world" then
            if arg == "reload" then arg = "rl" end
            fr0z3nUI_AutoOpen_CharSettings.talentMode = tostring(arg):upper()
            PrintTalentStatus()
            return
        end

        print("|cff00ccff[FAO]|r Usage: /fao talents off|login|rl|world")
        print("|cff00ccff[FAO]|r Usage: /fao talents ui off|on|acc")
        return
    end

    -- Default behavior: open/toggle GUI and allow pasting an itemID
    CreateOptionsWindow()

    local f = fr0z3nUI_AutoOpenOptions
    if not f then return end

    local idText = text:match("(%d+)")

    if not f:IsShown() then
        f:Show()
    else
        -- If user typed an ID while window is open, update; otherwise toggle.
        if not idText then
            f:Hide()
            return
        end
    end

    if idText and f.edit then
        f.edit:SetText(idText)
        if f.edit.SetCursorPosition then f.edit:SetCursorPosition(#idText) end
        if f.edit.SetFocus then f.edit:SetFocus() end
    elseif f.edit and f.edit.SetFocus then
        f.edit:SetFocus()
    end
end
