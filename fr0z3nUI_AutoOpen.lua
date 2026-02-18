local addonName, ns = ...
local lastOpenTime = 0
local atBank, atMail, atMerchant, atTrade, atAuction = false, false, false, false, false
local scanPending = false
local RequestScan
local cachePauseSeq = 0
local didPruneCustomWhitelists = false
local lastTalentsDebugAt, lastTalentsDebugLine = 0, nil
local autoLootKickSeq = 0
local lastAutoLootEnforceAt = 0
local frame
local WATCHDOG_INTERVAL = 10
local WATCHDOG_MIN_SCAN_GAP = 12
local IsLootOpenSafe

local PREFIX = "|cff00ccff[FAO]|r "
local PRINT_QUEUE_START_DELAY = 0.05
local PRINT_QUEUE_STEP_DELAY = 0.12
local MAX_QUEUED_PRINTS = 50

local function Print(msg)
    print(PREFIX .. tostring(msg or ""))
end

local _printQueue, _printQueueRunning = {}, false
local function PrintDelayed(msg)
    if msg == nil then return end

    if #_printQueue >= MAX_QUEUED_PRINTS then
        -- Prevent unbounded growth if something goes wrong.
        _printQueue = {}
    end
    _printQueue[#_printQueue + 1] = msg

    if _printQueueRunning then return end
    if not (C_Timer and C_Timer.After) then
        -- Fallback: no timers, print immediately.
        Print(msg)
        return
    end

    _printQueueRunning = true

    local function step()
        if #_printQueue == 0 then
            _printQueueRunning = false
            return
        end

        local nextMsg = table.remove(_printQueue, 1)
        Print(nextMsg)

        if #_printQueue == 0 then
            _printQueueRunning = false
            return
        end

        C_Timer.After(PRINT_QUEUE_STEP_DELAY, step)
    end

    C_Timer.After(PRINT_QUEUE_START_DELAY, step)
end

local function IsGlobalFrameShownSafe(frameName)
    local f = _G and frameName and _G[frameName]
    if not (f and f.IsShown) then return false end
    local ok, shown = pcall(f.IsShown, f)
    return ok and shown == true
end

local function RefreshInteractionFlagsFromUI()
    -- Self-heal the cached interaction flags.
    -- Missing *_CLOSED events (or UI path differences) can otherwise leave these stuck true
    -- and the scan engine will appear "dead" until /reload.
    if _G and (_G["BankFrame"] or _G["GuildBankFrame"]) then
        atBank = IsGlobalFrameShownSafe("BankFrame") or IsGlobalFrameShownSafe("GuildBankFrame")
    end
    if _G and _G["MailFrame"] then
        atMail = IsGlobalFrameShownSafe("MailFrame")
    end
    if _G and _G["MerchantFrame"] then
        atMerchant = IsGlobalFrameShownSafe("MerchantFrame")
    end
    if _G and _G["TradeFrame"] then
        atTrade = IsGlobalFrameShownSafe("TradeFrame")
    end
    if _G and (_G["AuctionHouseFrame"] or _G["AuctionFrame"]) then
        atAuction = IsGlobalFrameShownSafe("AuctionHouseFrame") or IsGlobalFrameShownSafe("AuctionFrame")
    end
end

local function IsAutoOpenEnabledNow()
    if not fr0z3nUI_AutoOpen_CharSettings then return true end
    return fr0z3nUI_AutoOpen_CharSettings.autoOpen ~= false
end

local function IsScanAllowedNow()
    if not IsAutoOpenEnabledNow() then return false, "auto open OFF" end
    RefreshInteractionFlagsFromUI()
    if atBank then return false, "bank" end
    if atMail then return false, "mail" end
    if atMerchant then return false, "merchant" end
    if atTrade then return false, "trade" end
    if atAuction then return false, "auction" end
    if (InCombatLockdown and InCombatLockdown()) then return false, "combat" end
    if IsLootOpenSafe() then return false, "loot window" end
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID and C_Container.GetContainerItemInfo and C_Container.UseContainerItem) then
        return false, "bag API"
    end
    return true, nil
end

local function WatchdogDebug(msg)
    if not (fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.debugWatchdogAcc) then
        return
    end
    if not (frame and msg) then return end

    local now = (GetTime and GetTime()) or 0

    -- Dedupe + throttle: only print when the message changes, or after a cooldown.
    if frame._watchdogLastMsg == msg and now > 0 and frame._watchdogLastAt and (now - frame._watchdogLastAt) < 30 then
        return
    end

    frame._watchdogLastMsg = msg
    frame._watchdogLastAt = now
    PrintDelayed(msg)
end

local function EnsureWatchdogTicker()
    if not (C_Timer and C_Timer.NewTicker) then return end
    if not frame then return end
    if frame._watchdogTicker then return end

    frame._watchdogTicker = C_Timer.NewTicker(WATCHDOG_INTERVAL, function()
        if not frame then return end
        if not RequestScan then return end
        if scanPending then
            WatchdogDebug("Watchdog: scan already pending")
            return
        end
        if frame._scanTimer then
            WatchdogDebug("Watchdog: scan timer active")
            return
        end
        local ok, why = IsScanAllowedNow()
        if not ok then
            WatchdogDebug("Watchdog: blocked by " .. tostring(why or "unknown"))
            return
        end

        local now = (GetTime and GetTime()) or 0
        local last = tonumber(frame._lastScanAt or 0) or 0
        if now > 0 and last > 0 and (now - last) < WATCHDOG_MIN_SCAN_GAP then
            return
        end

        WatchdogDebug("Watchdog: kicking scan")
        RequestScan(0.1)
    end)
end

IsLootOpenSafe = function()
    if C_Loot and C_Loot.IsLootOpen then
        local ok, v = pcall(C_Loot.IsLootOpen)
        if ok and v == true then
            return true
        end
    end
    local lf = _G and _G["LootFrame"]
    if lf and lf.IsShown and lf:IsShown() then
        return true
    end
    return false
end

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
    if not (fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_CharSettings) then return end
    local acc = fr0z3nUI_AutoOpen_Settings.autoLootOnLoginAccount
    local enabled
    if acc == true then
        enabled = true
    else
        enabled = (fr0z3nUI_AutoOpen_CharSettings.autoLootOnLogin) and true or false
    end
    if not enabled then return end

    local now = (GetTime and GetTime()) or 0
    if now > 0 and lastAutoLootEnforceAt > 0 and (now - lastAutoLootEnforceAt) < 0.5 then
        return
    end
    lastAutoLootEnforceAt = now

    SetAutoLootDefaultSafe(true)

    -- Some addons / CVars can flip autoLootDefault shortly after zone/instance transitions.
    -- Verify again a moment later and re-apply if needed.
    autoLootKickSeq = autoLootKickSeq + 1
    local seq = autoLootKickSeq
    if C_Timer and C_Timer.After then
        C_Timer.After(2, function()
            if seq ~= autoLootKickSeq then return end
            if not (fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_CharSettings) then return end

            local acc2 = fr0z3nUI_AutoOpen_Settings.autoLootOnLoginAccount
            local enabled2
            if acc2 == true then
                enabled2 = true
            else
                enabled2 = (fr0z3nUI_AutoOpen_CharSettings.autoLootOnLogin) and true or false
            end
            if not enabled2 then return end

            local cur = GetAutoLootDefaultSafe()
            if cur == false then
                SetAutoLootDefaultSafe(true)
            end
        end)
    end
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

-- [ OPEN STATS / AUTO-DISABLE ]
local function EnsureAccStatsSV()
    fr0z3nUI_AutoOpen_AccStats = fr0z3nUI_AutoOpen_AccStats or {}
    if type(fr0z3nUI_AutoOpen_AccStats.items) ~= "table" then
        fr0z3nUI_AutoOpen_AccStats.items = {}
    end
    if type(fr0z3nUI_AutoOpen_AccStats.cfg) ~= "table" then
        fr0z3nUI_AutoOpen_AccStats.cfg = {}
    end

    if fr0z3nUI_AutoOpen_AccStats.cfg.disableAfterFails == nil then
        fr0z3nUI_AutoOpen_AccStats.cfg.disableAfterFails = 5
    end
    if fr0z3nUI_AutoOpen_AccStats.cfg.verifyDelay == nil then
        fr0z3nUI_AutoOpen_AccStats.cfg.verifyDelay = 1.0
    end
end

local function GetAccStatsEntry(id)
    EnsureAccStatsSV()
    if not id then return nil end
    local t = fr0z3nUI_AutoOpen_AccStats.items
    local e = t[id]
    if type(e) ~= "table" then
        e = { attempts = 0, success = 0, fail = 0, failStreak = 0, failedGuids = {} }
        t[id] = e
    end
    if type(e.failedGuids) ~= "table" then
        e.failedGuids = {}
    end
    return e
end

local function ResetAccFailStreak(id)
    local e = GetAccStatsEntry(id)
    if not e then return end
    e.attempts = 0
    e.success = 0
    e.fail = 0
    e.failStreak = 0
    e.lastAttemptAt = nil
    e.lastFailAt = nil
    e.lastSuccessAt = nil
    e.autoDisabledAt = nil
    e.autoDisabledReason = nil
    e.failedGuids = {}
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

    -- Cheap early-outs from instant item info.
    if C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(id)

        -- Reagents are never caches.
        local reagentClass = (Enum and Enum.ItemClass and Enum.ItemClass.Reagent) or 5
        if classID == reagentClass then
            return false, "reagent"
        end

        -- If it looks equippable, it's almost certainly not an openable cache.
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
    EnsureAccStatsSV()

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

    -- Normalize legacy values (older versions supported RL).
    do
        local gv = tostring(fr0z3nUI_AutoOpen_CharSettings.greatVaultMode or "OFF"):upper()
        if gv ~= "OFF" then
            fr0z3nUI_AutoOpen_CharSettings.greatVaultMode = "ON"
        end
    end

    -- Great Vault account override (3-state)
    -- OFF     = off (per-character)
    -- ON      = on (per-character)
    -- ON ACC  = on account-wide override (overrides character)
    -- Default: account override unset
    if fr0z3nUI_AutoOpen_Settings.greatVaultAccount ~= nil and type(fr0z3nUI_AutoOpen_Settings.greatVaultAccount) ~= "boolean" then
        fr0z3nUI_AutoOpen_Settings.greatVaultAccount = nil
    end

    if fr0z3nUI_AutoOpen_CharSettings.autoOpen == nil then
        -- Migration: older versions stored this account-wide
        if fr0z3nUI_AutoOpen_Settings.autoOpen ~= nil then
            fr0z3nUI_AutoOpen_CharSettings.autoOpen = fr0z3nUI_AutoOpen_Settings.autoOpen and true or false
        else
            fr0z3nUI_AutoOpen_CharSettings.autoOpen = true
        end
    end

    -- Talent reminder:
    -- Merged into the Talent UI toggle.
    -- If Talent UI is ON (CHAR/ACC), the reminder runs using WORLD behavior.
    -- If Talent UI is OFF, no reminders.
    do
        local legacyMode = tostring((fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.talentMode) or (fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.talentMode) or "OFF"):upper()
        if legacyMode ~= "OFF" then
            -- Migration: older versions had a separate toggle; treat that as enabling Talent UI.
            if type(fr0z3nUI_AutoOpen_CharSettings.talentAutoOpen) ~= "boolean" then
                fr0z3nUI_AutoOpen_CharSettings.talentAutoOpen = true
            end
        end
        -- Cleanup: legacy field is no longer used.
        if fr0z3nUI_AutoOpen_CharSettings then fr0z3nUI_AutoOpen_CharSettings.talentMode = nil end
        if fr0z3nUI_AutoOpen_Settings then fr0z3nUI_AutoOpen_Settings.talentMode = nil end
    end

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
    if type(fr0z3nUI_AutoOpen_CharSettings.debugGreatVault) ~= "boolean" then
        fr0z3nUI_AutoOpen_CharSettings.debugGreatVault = false
    end

    -- Debug toggles (account-wide)
    if type(fr0z3nUI_AutoOpen_Settings.debugWatchdogAcc) ~= "boolean" then
        fr0z3nUI_AutoOpen_Settings.debugWatchdogAcc = false
    end

    -- Auto Loot (per-character): when ON, force the account CVar to enabled on login.
    -- Default: ON
    if type(fr0z3nUI_AutoOpen_CharSettings.autoLootOnLogin) ~= "boolean" then
        fr0z3nUI_AutoOpen_CharSettings.autoLootOnLogin = true
    end

    -- Auto Loot account override (3-state)
    -- OFF     = off (per-character)
    -- ON      = on (per-character)
    -- ON ACC  = on account-wide override (overrides character)
    -- Default: account override unset
    if fr0z3nUI_AutoOpen_Settings.autoLootOnLoginAccount ~= nil and type(fr0z3nUI_AutoOpen_Settings.autoLootOnLoginAccount) ~= "boolean" then
        fr0z3nUI_AutoOpen_Settings.autoLootOnLoginAccount = nil
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

    -- Profession trainer auto-learn (per-character): when ON, auto-learn all available trainer recipes.
    if type(fr0z3nUI_AutoOpen_CharSettings.autoLearnTrainer) ~= "boolean" then
        fr0z3nUI_AutoOpen_CharSettings.autoLearnTrainer = false
    end

    -- Trainer auto-learn account override (3-state)
    -- OFF     = off (per-character)
    -- ON      = on (per-character)
    -- ON ACC  = on account-wide override (overrides character)
    -- Default: ON ACC
    if fr0z3nUI_AutoOpen_Settings.autoLearnTrainerAccount ~= nil and type(fr0z3nUI_AutoOpen_Settings.autoLearnTrainerAccount) ~= "boolean" then
        fr0z3nUI_AutoOpen_Settings.autoLearnTrainerAccount = nil
    end

    -- Apply the default (ON ACC) only once so the user can actually turn it OFF.
    if fr0z3nUI_AutoOpen_Settings.trainerLearnDefaulted ~= true then
        if fr0z3nUI_AutoOpen_Settings.autoLearnTrainerAccount == nil and fr0z3nUI_AutoOpen_CharSettings.autoLearnTrainer == false then
            fr0z3nUI_AutoOpen_Settings.autoLearnTrainerAccount = true
        end
        fr0z3nUI_AutoOpen_Settings.trainerLearnDefaulted = true
    end

    -- Minimap button (account-wide)
    -- Default: OFF
    if type(fr0z3nUI_AutoOpen_Settings.minimapButton) ~= "boolean" then
        fr0z3nUI_AutoOpen_Settings.minimapButton = false
    end
    if type(fr0z3nUI_AutoOpen_Settings.minimapButtonX) ~= "number" then
        fr0z3nUI_AutoOpen_Settings.minimapButtonX = -70
    end
    if type(fr0z3nUI_AutoOpen_Settings.minimapButtonY) ~= "number" then
        fr0z3nUI_AutoOpen_Settings.minimapButtonY = -70
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

-- Forward decls (defined later)
local UpdateMinimapButtonVisibility
local ToggleFAOOptionsWindow

-- [ PROFESSION TRAINER AUTO-LEARN ]
local trainerLearnSeq = 0
local trainerMissingApiWarned = false

local function GetTrainerAutoLearnMode()
    if fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.autoLearnTrainerAccount == true then
        return "ACC"
    end
    if fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.autoLearnTrainer == true then
        return "CHAR"
    end
    return "OFF"
end

local function IsTrainerAutoLearnEnabled()
    local mode = GetTrainerAutoLearnMode()
    return (mode == "ACC" or mode == "CHAR")
end

local function IsTrainerAutoLearnSuppressedByShift()
    if not (IsShiftKeyDown and IsShiftKeyDown()) then
        return false
    end
    return true
end

local function IsTrainerInteractionType(interactionType)
    if not interactionType then return false end

    -- Some builds/addons use the numeric interaction type directly (Trainer = 7).
    if type(interactionType) == "number" and interactionType == 7 then
        return true
    end

    local e = _G and rawget(_G, "Enum")
    local pit = e and e.PlayerInteractionType
    local trainer = pit and (rawget(pit, "Trainer") or rawget(pit, "trainer"))
    return (trainer ~= nil) and (interactionType == trainer)
end

local function GetTrainerApi()
    -- Modern (Retail) API
    -- Different builds expose slightly different shapes; support both.
    local function wrapRetailTrainer(ct, kindLabel)
        if type(ct) ~= "table" then return nil end
        if type(ct.GetNumTrainerServices) ~= "function" or type(ct.BuyTrainerService) ~= "function" then
            return nil
        end

        -- Preferred: structured info table.
        if type(ct.GetTrainerServiceInfo) == "function" then
            return {
                kind = kindLabel,
                getNum = function() return ct.GetNumTrainerServices() end,
                getInfo = function(i) return ct.GetTrainerServiceInfo(i) end,
                buy = function(i) return ct.BuyTrainerService(i) end,
            }
        end

        -- Fallback: type/cost accessors.
        if type(ct.GetTrainerServiceType) == "function" then
            local getCost = (type(ct.GetTrainerServiceCost) == "function") and ct.GetTrainerServiceCost or nil
            return {
                kind = kindLabel,
                getNum = function() return ct.GetNumTrainerServices() end,
                getInfo = function(i)
                    return {
                        serviceType = ct.GetTrainerServiceType(i),
                        moneyCost = getCost and tonumber(getCost(i)) or 0,
                    }
                end,
                buy = function(i) return ct.BuyTrainerService(i) end,
            }
        end

        return nil
    end

    if _G then
        local ct = rawget(_G, "C_Trainer")
        local api = wrapRetailTrainer(ct, "C_Trainer")
        if api then return api end

        -- Some clients have a differently named namespace.
        local ct2 = rawget(_G, "C_TrainerUI")
        local api2 = wrapRetailTrainer(ct2, "C_TrainerUI")
        if api2 then return api2 end
    end

    -- Legacy (Classic-era) globals
    local getNum = _G and rawget(_G, "GetNumTrainerServices")
    local getInfo = _G and rawget(_G, "GetTrainerServiceInfo")
    local getType = _G and rawget(_G, "GetTrainerServiceType")
    local getCost = _G and rawget(_G, "GetTrainerServiceCost")
    local buy = _G and rawget(_G, "BuyTrainerService")
    if type(getNum) == "function" and type(buy) == "function" then
        -- Prefer full info if available (works even when GetTrainerServiceType isn't exposed).
        if type(getInfo) == "function" then
            return {
                kind = "legacy",
                getNum = function() return getNum() end,
                getInfo = function(i)
                    -- GetTrainerServiceInfo historically returns multiple values; the 5th is availability.
                    -- availability is typically "available" / "unavailable" / "used" / etc (locale-dependent).
                    local _name, _rank, _cat, _expanded, availability = getInfo(i)
                    local availabilityText = availability
                    -- Some client variants return the availability string as the 2nd return.
                    if availabilityText == nil and type(_rank) == "string" then
                        availabilityText = _rank
                    end

                    local costNum = 0
                    if type(getCost) == "function" then
                        -- GetTrainerServiceCost can return multiple values; capture only the first.
                        local rawCost = getCost(i)
                        costNum = tonumber(rawCost) or 0
                    end
                    return {
                        available = availabilityText,
                        moneyCost = costNum,
                    }
                end,
                buy = function(i) return buy(i) end,
            }
        end

        -- Fallback: type/cost accessors.
        if type(getType) == "function" then
            return {
                kind = "legacy",
                getNum = function() return getNum() end,
                getInfo = function(i)
                    local costNum = 0
                    if type(getCost) == "function" then
                        local rawCost = getCost(i)
                        costNum = tonumber(rawCost) or 0
                    end
                    return {
                        serviceType = getType(i),
                        moneyCost = costNum,
                    }
                end,
                buy = function(i) return buy(i) end,
            }
        end
    end

    return nil
end

local function IsServiceAvailable(info)
    if type(info) == "string" then
        return info:lower() == "available"
    end
    if type(info) ~= "table" then
        return false
    end

    -- Legacy GetTrainerServiceInfo() variants often provide availability as a string field.
    if type(info.available) == "string" then
        return info.available:lower() == "available"
    end

    if info.isLearnable == true or info.available == true then
        return true
    end

    local st = info.serviceType or info.type
    if type(st) == "string" then
        return st:lower() == "available"
    end

    local e = _G and rawget(_G, "Enum")
    local tst = e and e.TrainerServiceType
    local avail = tst and (tst.Available or tst.available)
    if type(st) == "number" and avail ~= nil and st == avail then
        return true
    end

    return false
end

local function LearnAllTrainerServicesOnce()
    if not IsTrainerAutoLearnEnabled() then return 0 end
    if IsTrainerAutoLearnSuppressedByShift() then return 0 end
    if InCombatLockdown and InCombatLockdown() then return 0 end

    -- Best-effort: load Blizzard trainer UI if it exists (some builds still keep it separate).
    if _G and type(rawget(_G, "UIParentLoadAddOn")) == "function" and type(rawget(_G, "IsAddOnLoaded")) == "function" then
        if not _G.IsAddOnLoaded("Blizzard_TrainerUI") then
            pcall(_G.UIParentLoadAddOn, "Blizzard_TrainerUI")
        end
    end

    local api = GetTrainerApi()
    if not api then
        if not trainerMissingApiWarned then
            trainerMissingApiWarned = true
            print("|cff00ccff[FAO]|r Trainer auto-learn: trainer API unavailable (this NPC may not use trainer services).")
        end
        return 0
    end

    local money = (GetMoney and GetMoney()) or nil

    local learned = 0
    local n = tonumber(api.getNum()) or 0
    for i = 1, n do
        local info = api.getInfo(i)
        if IsServiceAvailable(info) then
            local cost = tonumber((type(info) == "table" and (info.moneyCost or info.cost)) or 0) or 0
            if (not money) or (not cost) or cost <= 0 or (money >= cost) then
                api.buy(i)
                learned = learned + 1
                money = (GetMoney and GetMoney()) or money
            end
        end
    end

    return learned
end

local function RequestTrainerAutoLearn()
    trainerLearnSeq = trainerLearnSeq + 1
    local seq = trainerLearnSeq

    if not (C_Timer and C_Timer.After) then return end
    if not IsTrainerAutoLearnEnabled() then return end
    if IsTrainerAutoLearnSuppressedByShift() then
        -- Cancel any in-flight loop and skip while the user is intentionally holding Shift.
        trainerLearnSeq = trainerLearnSeq + 1
        return
    end

    local totalLearned = 0
    local function Step(pass)
        if seq ~= trainerLearnSeq then return end
        if InCombatLockdown and InCombatLockdown() then return end

        local learned = LearnAllTrainerServicesOnce()
        if learned and learned > 0 then
            totalLearned = totalLearned + learned
            if pass < 25 then
                C_Timer.After(0.15, function() Step(pass + 1) end)
                return
            end
        end

        if totalLearned > 0 then
            print("|cff00ccff[FAO]|r Trainer: learned " .. tostring(totalLearned) .. " recipe" .. (totalLearned == 1 and "" or "s") .. ".")
        end
    end

    -- Small delay so trainer services list is populated.
    C_Timer.After(0.20, function() Step(0) end)
end

local function GetMaxPlayerLevelSafe()
    if GetMaxPlayerLevel then
        local max = GetMaxPlayerLevel()
        if type(max) == "number" and max > 0 then return max end
    end
    local legacyMax = _G and _G["MAX_PLAYER_LEVEL"]
    if type(legacyMax) == "number" and legacyMax > 0 then
        return legacyMax
    end
    return nil
end

local function GetMaxLevelForPlayerExpansionSafe()
    -- Retail API: prefers the account's current expansion cap (more stable during prepatch).
    if GetMaxLevelForPlayerExpansion then
        local ok, v = pcall(GetMaxLevelForPlayerExpansion)
        if ok and type(v) == "number" and v > 0 then
            return v
        end
    end
    return nil
end

local function AutoEnableGreatVaultAtMaxLevel()
    -- Deprecated: Great Vault now defaults to OFF and is never auto-enabled.
    return false
end

local function GetGreatVaultAutoOpenMode()
    if fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.greatVaultAccount == true then
        return "ACC", true
    end
    local mode = tostring((fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.greatVaultMode) or "OFF"):upper()
    local on = (mode ~= "OFF")
    return on and "CHAR" or "OFF", on
end

local function GetGreatVaultRequiredLevel()
    -- Midnight pre-patch has historically been noisy about level-cap APIs for a bit.
    -- Defaulting to 80 keeps behavior sensible for current retail characters.
    local DEFAULT_CAP = 80

    local maxLevel = GetMaxLevelForPlayerExpansionSafe() or GetMaxPlayerLevelSafe()
    if type(maxLevel) ~= "number" then
        return DEFAULT_CAP
    end

    -- Guard against clearly wrong values (0, negative, or implausibly high).
    if maxLevel < 10 or maxLevel > 100 then
        return DEFAULT_CAP
    end

    -- Prepatch heuristic:
    -- Sometimes the client reports the *next* expansion cap (e.g., 90) while characters
    -- are still effectively capped at the current expansion max (e.g., 80).
    local level = (UnitLevel and UnitLevel("player"))
    if type(level) == "number" and level >= 60 and (level % 10) == 0 then
        if (maxLevel - level) == 10 then
            return level
        end
    end

    return maxLevel
end

local function IsPlayerAtGreatVaultLevel()
    if not UnitLevel then return nil end
    local level = UnitLevel("player")
    if type(level) ~= "number" then return nil end
    return level >= GetGreatVaultRequiredLevel()
end

-- [ GREAT VAULT ]
local function ShowGreatVaultCore()
    if C_AddOns and C_AddOns.LoadAddOn then
        if type(securecall) == "function" then
            securecall(C_AddOns.LoadAddOn, "Blizzard_WeeklyRewards")
        else
            C_AddOns.LoadAddOn("Blizzard_WeeklyRewards")
        end
    end
    if WeeklyRewardsFrame then
        if type(securecall) == "function" then
            securecall(WeeklyRewardsFrame.Show, WeeklyRewardsFrame)
        else
            WeeklyRewardsFrame:Show()
        end
        return
    end
    C_Timer.After(0.5, function()
        if WeeklyRewardsFrame then
            if type(securecall) == "function" then
                securecall(WeeklyRewardsFrame.Show, WeeklyRewardsFrame)
            else
                WeeklyRewardsFrame:Show()
            end
        end
    end)
end

ns.ShowGreatVault = function()
    InitSV()
    local _, enabled = GetGreatVaultAutoOpenMode()
    if not enabled then return end
    local ok = IsPlayerAtGreatVaultLevel()
    if ok ~= true then return end
    ShowGreatVaultCore()
end

local function QueueGreatVaultAutoOpen(isReloadingUi)
    if isReloadingUi then return end
    if frame._didOpenGreatVaultThisLogin == true then return end
    if frame._gvPending == true then return end

    InitSV()
    local _, gvEnabled = GetGreatVaultAutoOpenMode()
    if not gvEnabled then return end

    if fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.debugGreatVault then
        local lvl = (UnitLevel and UnitLevel("player"))
        local req = GetGreatVaultRequiredLevel and GetGreatVaultRequiredLevel() or "?"
        print("|cff00ccff[FAO]|r [GV] Queue: lvl="..tostring(lvl).." req="..tostring(req).." pending=false opened="..tostring(frame._didOpenGreatVaultThisLogin))
    end

    frame._gvPending = true
    frame._gvSeq = (frame._gvSeq or 0) + 1
    local seq = frame._gvSeq

    local function Try(attempt)
        if frame._gvSeq ~= seq then return end
        InitSV()
        local _, enabled = GetGreatVaultAutoOpenMode()
        if not enabled then
            frame._gvPending = false
            return
        end

        local isMax = IsPlayerAtGreatVaultLevel()

        if fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.debugGreatVault then
            local lvl = (UnitLevel and UnitLevel("player"))
            local req = GetGreatVaultRequiredLevel and GetGreatVaultRequiredLevel() or "?"
            local frameExists = (WeeklyRewardsFrame and true) or false
            local addOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_WeeklyRewards"))
            print("|cff00ccff[FAO]|r [GV] Try("..tostring(attempt).."): enabled="..tostring(enabled).." lvl="..tostring(lvl).." req="..tostring(req).." atLvl="..tostring(isMax).." addonLoaded="..tostring(addOnLoaded).." frame="..tostring(frameExists))
        end

        if isMax == false then
            frame._gvPending = false
            return
        end

        if isMax ~= true then
            if attempt < 6 then
                C_Timer.After(5, function() Try(attempt + 1) end)
            else
                frame._gvPending = false
            end
            return
        end

        frame._gvPending = false
        frame._didOpenGreatVaultThisLogin = true
        ShowGreatVaultCore()
    end

    C_Timer.After(5, function() Try(0) end)
end

-- [ TALENTS ]
local lastTalentNotifyAt, lastTalentNotifiedPoints = 0, nil
local didTryLoadTalentAddonsForPoints = false
local talentCheckSeq = 0
local talentDeferredAfterCombat = nil -- { isInitialLogin=bool, isReloadingUi=bool, seq=number, at=time }
local lastCombatEndedAt = 0
local TALENT_POST_COMBAT_DELAY = 30

local function GetUnspentTalentPointsSafe()
    local function Query()
        local total = 0
        local gotAnyData = false
        local gotClassData = false
        local gotHeroData = false
        local classPoints, heroPoints

        -- Prefer the modern APIs which also return numeric counts.
        if C_ClassTalents then
            if C_ClassTalents.HasUnspentTalentPoints then
                local ok, hasAny, numClassPoints, numSpecPoints = pcall(C_ClassTalents.HasUnspentTalentPoints)
                if ok and type(hasAny) == "boolean" then
                    gotAnyData = true
                    gotClassData = true
                    local cp = tonumber(numClassPoints) or 0
                    local sp = tonumber(numSpecPoints) or 0
                    classPoints = cp + sp
                    total = total + classPoints
                end
            end

            if C_ClassTalents.HasUnspentHeroTalentPoints then
                local ok, r1, r2 = pcall(C_ClassTalents.HasUnspentHeroTalentPoints)
                if ok then
                    -- Normal signature: (hasAny:boolean, numPoints:number)
                    if type(r1) == "boolean" then
                        gotAnyData = true
                        gotHeroData = true
                        heroPoints = tonumber(r2) or 0
                        total = total + heroPoints
                    -- Some builds appear to return just a numeric count.
                    elseif type(r1) == "number" then
                        gotAnyData = true
                        gotHeroData = true
                        heroPoints = tonumber(r1) or 0
                        total = total + heroPoints
                    end
                end
            end

            -- Fallbacks for older clients.
            if (not gotClassData) and C_ClassTalents.GetUnspentTalentPoints then
                local ok, p = pcall(C_ClassTalents.GetUnspentTalentPoints)
                if ok and type(p) == "number" then
                    classPoints = p
                    total = total + p
                    gotAnyData = true
                end
            end
            if (not gotHeroData) and C_ClassTalents.GetUnspentHeroTalentPoints then
                local ok, p = pcall(C_ClassTalents.GetUnspentHeroTalentPoints)
                if ok and type(p) == "number" then
                    heroPoints = p
                    total = total + p
                    gotAnyData = true
                end
            end
        end

        if not gotAnyData then return nil end
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
        local ok, r1 = pcall(C_ClassTalents.HasUnspentHeroTalentPoints)
        if ok then
            if type(r1) == "boolean" then
                return r1
            elseif type(r1) == "number" then
                return r1 > 0
            end
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

local function GetAutoLootEnforceMode()
    if fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.autoLootOnLoginAccount == true then
        return "ACC", true
    end
    local on = (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.autoLootOnLogin) and true or false
    return on and "CHAR" or "OFF", on
end

local function IsHeroTalentTreeSelectedSafe()
    -- Some clients will not report hero points (or even the boolean) until a hero talent tree is selected.
    -- We treat "no active hero spec" as actionable even if the points API still says 0.
    if not (C_ClassTalents and type(C_ClassTalents) == "table") then return nil end

    -- Most likely API.
    if type(C_ClassTalents.GetActiveHeroTalentSpec) == "function" then
        local ok, v = pcall(C_ClassTalents.GetActiveHeroTalentSpec)
        if ok then
            if type(v) == "number" then
                if v > 0 then return true end
                return false
            end
            -- Nil here often means the talent system isn't fully initialized yet.
            -- Treat as unknown and let the retry logic decide.
            if v == nil then
                return nil
            end
        end
    end

    -- Fallback: if specs exist but we cannot detect an active one, assume not selected.
    if type(C_ClassTalents.GetHeroTalentSpecs) == "function" then
        local ok, specs = pcall(C_ClassTalents.GetHeroTalentSpecs)
        if ok and type(specs) == "table" then
            if #specs > 0 then
                return nil
            end
        end
    end

    return nil
end

local function ShowTalentsUI()
    if InCombatLockdown and InCombatLockdown() then
        return false
    end

    if C_AddOns and C_AddOns.LoadAddOn then
        if type(securecall) == "function" then
            securecall(C_AddOns.LoadAddOn, "Blizzard_PlayerSpells")
            securecall(C_AddOns.LoadAddOn, "Blizzard_ClassTalentUI")
            securecall(C_AddOns.LoadAddOn, "Blizzard_TalentUI")
        else
            C_AddOns.LoadAddOn("Blizzard_PlayerSpells")
            C_AddOns.LoadAddOn("Blizzard_ClassTalentUI")
            C_AddOns.LoadAddOn("Blizzard_TalentUI")
        end
    end

    local togglePlayerSpellsFrame = _G and _G["TogglePlayerSpellsFrame"]
    if type(togglePlayerSpellsFrame) == "function" then
        if type(securecall) == "function" then
            securecall(togglePlayerSpellsFrame)
        else
            togglePlayerSpellsFrame()
        end
        return true
    end

    local playerSpellsFrame = _G and _G["PlayerSpellsFrame"]
    if playerSpellsFrame and playerSpellsFrame.Show then
        if type(securecall) == "function" then
            securecall(playerSpellsFrame.Show, playerSpellsFrame)
        else
            playerSpellsFrame:Show()
        end
        return true
    end

    local classTalentFrame = _G and _G["ClassTalentFrame"]
    if classTalentFrame and classTalentFrame.Show then
        if type(securecall) == "function" then
            securecall(classTalentFrame.Show, classTalentFrame)
        else
            classTalentFrame:Show()
        end
        return true
    end

    local toggleTalentFrame = _G and _G["ToggleTalentFrame"]
    if type(toggleTalentFrame) == "function" then
        if type(securecall) == "function" then
            securecall(toggleTalentFrame)
        else
            toggleTalentFrame()
        end
        return true
    end
    return false
end

local function ShouldTalentTrigger(mode, isInitialLogin, isReloadingUi)
    mode = tostring(mode or "OFF"):upper()
    if mode == "OFF" then return false end
    if mode == "LOGIN" then return isInitialLogin and not isReloadingUi end
    if mode == "RL" then return isReloadingUi end
    -- WORLD = any non-initial PLAYER_ENTERING_WORLD (reload + portals/instances).
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

    -- Don't fire talent reminders during combat. Defer the check until combat ends.
    if InCombatLockdown and InCombatLockdown() then
        if attempt == 0 and seq ~= nil then
            talentDeferredAfterCombat = {
                isInitialLogin = isInitialLogin,
                isReloadingUi = isReloadingUi,
                seq = seq,
                at = (GetTime and GetTime()) or 0,
            }
        end
        return
    end

    -- Don't fire talent reminders immediately after combat either.
    local nowForCombat = (GetTime and GetTime()) or 0
    if lastCombatEndedAt and lastCombatEndedAt > 0 and nowForCombat > 0 then
        local since = nowForCombat - lastCombatEndedAt
        if since < TALENT_POST_COMBAT_DELAY then
            if attempt == 0 and seq ~= nil then
                talentDeferredAfterCombat = {
                    isInitialLogin = isInitialLogin,
                    isReloadingUi = isReloadingUi,
                    seq = seq,
                    at = nowForCombat,
                }
            end
            return
        end
    end

    local uiMode, talentEnabled = GetTalentAutoOpenMode()
    local mode = "WORLD"
    local shouldTrigger = (talentEnabled == true) and ShouldTalentTrigger(mode, isInitialLogin, isReloadingUi)
    if attempt == 0 then
        local lvl = (UnitLevel and UnitLevel("player")) or "?"
        DebugTalentLine(string.format("start lvl=%s mode=%s ui=%s trigger=%s initial=%s reload=%s", tostring(lvl), tostring(mode):upper(), tostring(uiMode), tostring(shouldTrigger), tostring(isInitialLogin), tostring(isReloadingUi)), true)
    end
    if not shouldTrigger then return end

    local now = (GetTime and GetTime()) or 0
    if now > 0 and (now - lastTalentNotifyAt) < 10 then return end

    local points, classPoints, heroPoints = GetUnspentTalentPointsSafe()
    if points == nil then
        local level = (UnitLevel and UnitLevel("player")) or nil
        local hasAny = HasUnspentTalentPointsSafe()
        local hasHeroAny = HasUnspentHeroTalentPointsSafe()
        local heroSelected = nil
        if type(level) == "number" and level >= 71 then
            heroSelected = IsHeroTalentTreeSelectedSafe()
        end

        if attempt == 0 then
            DebugTalentLine(string.format("query points=nil class=nil hero=nil hasAny=%s hasHero=%s didLoad=%s", tostring(hasAny), tostring(hasHeroAny), tostring(didTryLoadTalentAddonsForPoints)), true)
        end

        if heroSelected == false then
            -- Hero selection can transiently read as "not selected" while the talent system warms up.
            -- Require it to persist for a few retries before notifying.
            if attempt < 5 then
                C_Timer.After(1, function()
                    MaybeHandleTalents(isInitialLogin, isReloadingUi, attempt + 1, seq)
                end)
                return
            end

            -- Hero tree not selected: points may not be visible to the APIs yet, but the player still needs to act.
            if now > 0 and (now - lastTalentNotifyAt) < 10 then return end
            lastTalentNotifyAt = now
            lastTalentNotifiedPoints = "?"

            local _, shouldOpenUI = GetTalentAutoOpenMode()
            if shouldOpenUI then
                local ok = ShowTalentsUI()
                if ok then
                    print("|cff00ccff[FAO]|r Initiate Hero Talent Tree")
                else
                    print("|cff00ccff[FAO]|r Initiate Hero Talent Tree (cannot open talents in combat)")
                end
            else
                print("|cff00ccff[FAO]|r Initiate Hero Talent Tree")
            end

            C_Timer.After(2, function()
                MaybeHandleTalents(isInitialLogin, isReloadingUi, attempt + 1, seq)
            end)
            return

        elseif hasHeroAny == false and hasAny == false then
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
        local heroSelected = nil
        if type(level) == "number" and level >= 71 then
            heroSelected = IsHeroTalentTreeSelectedSafe()
        end

        if heroSelected == false then
            if attempt < 5 then
                C_Timer.After(1, function()
                    MaybeHandleTalents(isInitialLogin, isReloadingUi, attempt + 1, seq)
                end)
                return
            end

            if now > 0 and (now - lastTalentNotifyAt) < 10 then return end
            lastTalentNotifyAt = now
            lastTalentNotifiedPoints = "?"

            local _, shouldOpenUI = GetTalentAutoOpenMode()
            if shouldOpenUI then
                local ok = ShowTalentsUI()
                if ok then
                    print("|cff00ccff[FAO]|r Initiate Hero Talent Tree")
                else
                    print("|cff00ccff[FAO]|r Initiate Hero Talent Tree (cannot open talents in combat)")
                end
            else
                print("|cff00ccff[FAO]|r Initiate Hero Talent Tree")
            end

            C_Timer.After(2, function()
                MaybeHandleTalents(isInitialLogin, isReloadingUi, attempt + 1, seq)
            end)
            return
        end

        if type(level) == "number" and level >= 71 and attempt < 20 then
            C_Timer.After(1, function()
                MaybeHandleTalents(isInitialLogin, isReloadingUi, attempt + 1, seq)
            end)
            return
        end
        local hasAny = HasUnspentTalentPointsSafe()
        local hasHeroAny = HasUnspentHeroTalentPointsSafe()

        -- If booleans say points exist, don't silently drop the reminder just because numeric APIs are returning 0.
        if hasAny == true or hasHeroAny == true then
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

            C_Timer.After(2, function()
                MaybeHandleTalents(isInitialLogin, isReloadingUi, attempt + 1, seq)
            end)
            return
        end

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
frame = CreateFrame('Frame', 'fr0z3nUI_AutoOpenFrame')

local function GetStackCountSafe(bag, slot)
    if not (C_Container and C_Container.GetContainerItemInfo) then return nil end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info then return nil end
    return tonumber(info.stackCount or 1) or 1
end

local function NoteOpenAttempt(id)
    local e = GetAccStatsEntry(id)
    if not e then return end
    e.attempts = (tonumber(e.attempts) or 0) + 1
    e.lastAttemptAt = time and time() or nil
end

local function NoteOpenSuccess(id)
    local e = GetAccStatsEntry(id)
    if not e then return end
    e.success = (tonumber(e.success) or 0) + 1
    e.failStreak = 0
    e.lastSuccessAt = time and time() or nil
end

local function NoteOpenFailure(id, guid)
    local e = GetAccStatsEntry(id)
    if not e then return end
    e.fail = (tonumber(e.fail) or 0) + 1
    e.lastFailAt = time and time() or nil

    -- Only advance the streak once per distinct item instance.
    -- This matches: "5 different pickups of the same itemID" (each pickup typically has a different GUID).
    if guid and type(guid) == "string" then
        if not e.failedGuids[guid] then
            e.failedGuids[guid] = (time and time()) or true
            e.failStreak = (tonumber(e.failStreak) or 0) + 1
        end
    else
        -- If GUID is unavailable, don't treat repeated retries as new "pickups".
        -- Still record the failure count, but avoid auto-disabling on noisy repeats.
        return
    end

    local cfg = (fr0z3nUI_AutoOpen_AccStats and fr0z3nUI_AutoOpen_AccStats.cfg) or {}
    local limit = tonumber(cfg.disableAfterFails) or 5
    if limit < 1 then return end

    if e.failStreak >= limit then
        if fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.disabled and not fr0z3nUI_AutoOpen_Settings.disabled[id] then
            fr0z3nUI_AutoOpen_Settings.disabled[id] = true
            e.autoDisabledAt = time and time() or nil
            e.autoDisabledReason = "failStreak"

            local nm = GetItemNameSafe(id) or ("ID " .. tostring(id))
            PrintDelayed("Auto-disabled (Account) after " .. tostring(limit) .. " failures: |cffffff00" .. tostring(nm) .. "|r")
        end
    end
end

local function ScheduleOpenVerify(id, bag, slot, hyperlink)
    if not (C_Timer and C_Timer.After) then return end
    if not frame then return end

    EnsureAccStatsSV()
    local cfg = fr0z3nUI_AutoOpen_AccStats.cfg or {}
    local delay = tonumber(cfg.verifyDelay) or 1.0
    if delay < 0.1 then delay = 0.1 end
    if delay > 5 then delay = 5 end

    frame._openVerifySeq = (tonumber(frame._openVerifySeq) or 0) + 1
    local seq = frame._openVerifySeq

    local guid = GetItemGUIDForBagSlot(bag, slot)
    local count = GetStackCountSafe(bag, slot)
    frame._pendingOpen = {
        seq = seq,
        id = id,
        bag = bag,
        slot = slot,
        guid = guid,
        count = count,
        at = (GetTime and GetTime()) or 0,
        hyperlink = hyperlink,
        lootOpened = false,
    }

    C_Timer.After(delay, function()
        if not frame then return end
        local p = frame._pendingOpen
        if type(p) ~= "table" or p.seq ~= seq then return end
        frame._pendingOpen = nil

        local b2, s2 = nil, nil
        if p.guid then
            b2, s2 = FindBagSlotByGUID(p.guid)
        else
            b2, s2 = p.bag, p.slot
        end

        if not (b2 and s2) then
            NoteOpenSuccess(p.id)
            return
        end

        local curID = C_Container.GetContainerItemID(b2, s2)
        if curID ~= p.id then
            NoteOpenSuccess(p.id)
            return
        end

        if p.lootOpened == true then
            NoteOpenSuccess(p.id)
            return
        end

        local curCount = GetStackCountSafe(b2, s2)
        if curCount and p.count and curCount < p.count then
            NoteOpenSuccess(p.id)
            return
        end

        NoteOpenFailure(p.id, p.guid)
    end)
end

function frame:RunScan(isKick)
    if not fr0z3nUI_AutoOpen_Settings or not fr0z3nUI_AutoOpen_Acc or not fr0z3nUI_AutoOpen_Char or not fr0z3nUI_AutoOpen_CharSettings then InitSV() end
    if fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.autoOpen == false then return end
    RefreshInteractionFlagsFromUI()
    if atBank or atMail or atMerchant or atTrade or atAuction then return end
    if (InCombatLockdown and InCombatLockdown()) then return end
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID and C_Container.GetContainerItemInfo and C_Container.UseContainerItem) then
        return
    end
    if IsLootOpenSafe() then
        -- Loot frame can stick around briefly; retry.
        if RequestScan then RequestScan(0.5) end
        return
    end

    self._lastScanAt = (GetTime and GetTime()) or 0

    local now = (GetTime and GetTime()) or 0
    local cd = GetOpenCooldown()
    if now > 0 and (now - lastOpenTime) < cd then
        local remaining = cd - (now - lastOpenTime)
        if remaining < 0 then remaining = 0 end
        if RequestScan then RequestScan(remaining + 0.05) end
        return
    end
    
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
                            if isKick then
                                PrintDelayed((info.hyperlink or tostring(id)) .. " kicked open")
                            else
                                PrintDelayed("Opening " .. (info.hyperlink or id))
                            end
                            NoteOpenAttempt(id)
                            C_Container.UseContainerItem(b, s)
                            lastOpenTime = (GetTime and GetTime()) or 0
                            ScheduleOpenVerify(id, b, s, info.hyperlink)
                            -- Chain-open: keep scanning until all eligible items are opened.
                            if RequestScan then RequestScan(GetOpenCooldown() + 0.05) end
                            return
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
frame:RegisterEvent('LOOT_OPENED')
frame:RegisterEvent('BANKFRAME_OPENED'); frame:RegisterEvent('BANKFRAME_CLOSED'); frame:RegisterEvent('MAIL_SHOW'); frame:RegisterEvent('MAIL_CLOSED')
frame:RegisterEvent('MERCHANT_SHOW'); frame:RegisterEvent('MERCHANT_CLOSED')
frame:RegisterEvent('TRADE_SHOW'); frame:RegisterEvent('TRADE_CLOSED')
frame:RegisterEvent('AUCTION_HOUSE_SHOW'); frame:RegisterEvent('AUCTION_HOUSE_CLOSED')
frame:RegisterEvent('TRAINER_SHOW'); frame:RegisterEvent('TRAINER_UPDATE'); frame:RegisterEvent('TRAINER_CLOSED')
frame:RegisterEvent('PLAYER_INTERACTION_MANAGER_FRAME_SHOW'); frame:RegisterEvent('PLAYER_INTERACTION_MANAGER_FRAME_HIDE')

-- Used to debounce the post-vendor "kick" scan.
local merchantKickSeq = 0

RequestScan = function(delay)
    delay = tonumber(delay) or 0
    if delay < 0 then delay = 0 end
    if not (C_Timer and (C_Timer.NewTimer or C_Timer.After)) then return end

    local now = (GetTime and GetTime()) or 0
    local targetAt = (now > 0) and (now + delay) or nil

    -- Debounce: keep the earliest scheduled scan.
    if frame and frame._scanTimer then
        if frame._scanTimerAt and targetAt and frame._scanTimerAt <= targetAt then
            return
        end
        if frame._scanTimer.Cancel then
            frame._scanTimer:Cancel()
        end
        frame._scanTimer = nil
        frame._scanTimerAt = nil
    end

    scanPending = true
    frame._scanTimerAt = targetAt
    if C_Timer.NewTimer then
        frame._scanTimer = C_Timer.NewTimer(delay, function()
            scanPending = false
            frame._scanTimer = nil
            frame._scanTimerAt = nil
            if frame and frame.RunScan then
                frame:RunScan()
            end
        end)
    else
        -- Fallback: no cancel handle; best-effort.
        C_Timer.After(delay, function()
            scanPending = false
            if frame and frame.RunScan then
                frame:RunScan()
            end
        end)
    end
end

frame:SetScript('OnEvent', function(self, event, ...)
    if event == "PLAYER_LOGIN" then 
        InitSV()
        EnsureWatchdogTicker()
        ApplyAutoLootSettingOnWorld()
        ApplyNPCNameplatesSettingOnWorld()
        if UpdateMinimapButtonVisibility then
            UpdateMinimapButtonVisibility()
        end
        frame._didOpenGreatVaultThisLogin = false
        frame._gvPending = false
        C_Timer.After(2, CheckTimersOnLogin)
        if RequestScan then
            RequestScan(2.5)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        isInitialLogin = isInitialLogin and true or false
        isReloadingUi = isReloadingUi and true or false
        InitSV()
        EnsureWatchdogTicker()
        ApplyAutoLootSettingOnWorld()
        ApplyNPCNameplatesSettingOnWorld()
        if frame._didOpenGreatVaultThisLogin == nil then
            frame._didOpenGreatVaultThisLogin = false
        end
        if frame._gvPending == nil then
            frame._gvPending = false
        end
        -- Only auto-open on the initial login load. Zoning/hearth/portals also fire
        -- PLAYER_ENTERING_WORLD and should not trigger the vault.
        if isInitialLogin then
            QueueGreatVaultAutoOpen(isReloadingUi)
        end

        -- Talents: useful on /reload, portals, and instance transitions.
        talentCheckSeq = talentCheckSeq + 1
        local seq = talentCheckSeq
        C_Timer.After(2, function()
            MaybeHandleTalents(isInitialLogin, isReloadingUi, 0, seq)
        end)

        -- Re-scan after zone/instance transitions and /reload.
        -- Bag events usually cover this, but PLAYER_ENTERING_WORLD is a reliable backstop.
        if RequestScan then
            RequestScan(isInitialLogin and 2.0 or 1.0)
        end
    elseif event == "LOOT_OPENED" then
        -- Safety net: if something flipped auto-loot off after zoning, re-apply right when loot opens.
        InitSV()
        ApplyAutoLootSettingOnWorld()

        -- Best-effort success hint: loot opening shortly after a UseContainerItem likely means success.
        if frame and type(frame._pendingOpen) == "table" then
            local p = frame._pendingOpen
            local now = (GetTime and GetTime()) or 0
            local at = tonumber(p.at or 0) or 0
            if now > 0 and at > 0 and (now - at) <= 1.75 then
                p.lootOpened = true
            end
        end
    elseif event == "PLAYER_LEVEL_UP" then
        local newLevel = ...
        InitSV()
        -- Great Vault is no longer auto-enabled at max level.
    elseif event == "BANKFRAME_OPENED" then 
        atBank = true
    elseif event == "BANKFRAME_CLOSED" then 
        atBank = false
        if RequestScan then RequestScan(0.3) end
    elseif event == "MAIL_SHOW" then 
        atMail = true
    elseif event == "MAIL_CLOSED" then 
        atMail = false
        if RequestScan then RequestScan(0.3) end
    elseif event == "MERCHANT_SHOW" then
        atMerchant = true
        -- Cancel any pending post-close kick.
        merchantKickSeq = merchantKickSeq + 1
    elseif event == "MERCHANT_CLOSED" then
        atMerchant = false
        -- Little push: scan again a few seconds after closing vendor.
        merchantKickSeq = merchantKickSeq + 1
        local seq = merchantKickSeq
        C_Timer.After(5, function()
            if merchantKickSeq ~= seq then
                return
            end
            if atMerchant then
                return
            end
            if RequestScan then RequestScan(0) end
        end)
    elseif event == "TRADE_SHOW" then
        atTrade = true
    elseif event == "TRADE_CLOSED" then
        atTrade = false
        if RequestScan then RequestScan(0.3) end
    elseif event == "AUCTION_HOUSE_SHOW" then
        atAuction = true
    elseif event == "AUCTION_HOUSE_CLOSED" then
        atAuction = false
        if RequestScan then RequestScan(0.3) end
    elseif event == "TRAINER_SHOW" then
        InitSV()
        trainerMissingApiWarned = false
        RequestTrainerAutoLearn()
    elseif event == "TRAINER_UPDATE" then
        -- Trainer windows can populate lazily; retry a couple times while open.
        InitSV()
        RequestTrainerAutoLearn()
    elseif event == "TRAINER_CLOSED" then
        trainerLearnSeq = trainerLearnSeq + 1
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        -- Modern UI path: interaction manager can host trainer frames.
        local interactionType = ...
        if IsTrainerInteractionType(interactionType) then
            InitSV()
            trainerMissingApiWarned = false
            RequestTrainerAutoLearn()
        end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local interactionType = ...
        if IsTrainerInteractionType(interactionType) then
            trainerLearnSeq = trainerLearnSeq + 1
        end
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_REGEN_ENABLED" then
        RequestScan(0.3)

        -- If a talent check was deferred due to combat, retry shortly after leaving combat.
        if event == "PLAYER_REGEN_ENABLED" and talentDeferredAfterCombat then
            lastCombatEndedAt = (GetTime and GetTime()) or 0
            local d = talentDeferredAfterCombat
            talentDeferredAfterCombat = nil
            local now = (GetTime and GetTime()) or 0
            if d.seq == talentCheckSeq and (now <= 0 or d.at <= 0 or (now - d.at) <= 60) then
                local delay = 1
                if now > 0 and lastCombatEndedAt > 0 then
                    local remaining = TALENT_POST_COMBAT_DELAY - (now - lastCombatEndedAt)
                    if remaining and remaining > delay then
                        delay = remaining
                    end
                end
                C_Timer.After(delay, function()
                    MaybeHandleTalents(d.isInitialLogin, d.isReloadingUi, 0, d.seq)
                end)
            end
        end
    end
end)

-- [ TOOLTIP COUNTDOWN ]
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
    and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
then
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    local id = data and data.id

    if id then
        -- FAO status summary (only show when relevant)
        local isExcludedDb = (ns and ns.exclude and ns.exclude[id]) and true or false
        local isAdded = false
        local addedSource -- "ACC" | "CHAR" | "ADDON"
        if fr0z3nUI_AutoOpen_Acc and fr0z3nUI_AutoOpen_Acc[id] then
            isAdded = true
            addedSource = "ACC"
        elseif fr0z3nUI_AutoOpen_Char and fr0z3nUI_AutoOpen_Char[id] then
            isAdded = true
            addedSource = "CHAR"
        elseif ns and ns.items and ns.items[id] then
            isAdded = true
            addedSource = "ADDON"
        end

        local isDisabledAcc = (fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.disabled and fr0z3nUI_AutoOpen_Settings.disabled[id]) and true or false
        local isDisabledChar = (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.disabled and fr0z3nUI_AutoOpen_CharSettings.disabled[id]) and true or false

        local statusLine
        if isExcludedDb then
            statusLine = "Excluded"
        elseif isDisabledAcc then
            statusLine = "Excluded Acc"
        elseif isDisabledChar then
            statusLine = "Excluded Char"
        elseif isAdded then
            if addedSource == "ACC" then
                statusLine = "Auto Open (Acc)"
            elseif addedSource == "CHAR" then
                statusLine = "Auto Open (Char)"
            else
                statusLine = "Auto Open"
            end
        end

        if statusLine then
            tooltip:AddLine("|cff00ccff[FAO]|r " .. statusLine)
        end

        if ns.timed and ns.timed[id] then
            tooltip:AddLine("|cff00ccff[FAO]|r Timed")
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
end

-- [ SLASH COMMAND + OPTIONS WINDOW ]
-- Options UI moved to fr0z3nUI_AutoOpenUI.lua

local function ResetAllSavedVariables()
    fr0z3nUI_AutoOpen_Acc = {}
    fr0z3nUI_AutoOpen_Char = {}
    fr0z3nUI_AutoOpen_Settings = {}
    fr0z3nUI_AutoOpen_CharSettings = {}
    fr0z3nUI_AutoOpen_Timers = {}
    fr0z3nUI_AutoOpen_AccStats = {}
    didPruneCustomWhitelists = false
    InitSV()
end

-- [ MINIMAP BUTTON ]
do
    local minimapButton

    local function ClampToMinimap(dx, dy)
        if not Minimap or not Minimap.GetWidth then
            return dx, dy
        end

        local radius = (Minimap:GetWidth() / 2) + 10
        local dist = math.sqrt((dx * dx) + (dy * dy))
        if dist > radius and dist > 0 then
            local scale = radius / dist
            dx = dx * scale
            dy = dy * scale
        end
        return dx, dy
    end

    local function SetMinimapButtonPosition()
        if not minimapButton then return end
        if not (Minimap and Minimap.GetCenter) then return end
        InitSV()

        local dx = tonumber(fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.minimapButtonX) or -70
        local dy = tonumber(fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.minimapButtonY) or -70
        dx, dy = ClampToMinimap(dx, dy)
        if fr0z3nUI_AutoOpen_Settings then
            fr0z3nUI_AutoOpen_Settings.minimapButtonX = dx
            fr0z3nUI_AutoOpen_Settings.minimapButtonY = dy
        end

        minimapButton:ClearAllPoints()
        minimapButton:SetPoint("CENTER", Minimap, "CENTER", dx, dy)
    end

    local function UpdateDragPosition()
        if not minimapButton then return end
        if not (Minimap and Minimap.GetCenter and GetCursorPosition) then return end
        InitSV()

        local mx, my = Minimap:GetCenter()
        if not mx or not my then return end

        local cx, cy = GetCursorPosition()
        local scale = (Minimap.GetEffectiveScale and Minimap:GetEffectiveScale()) or 1
        if scale and scale > 0 then
            cx = cx / scale
            cy = cy / scale
        end

        local dx = cx - mx
        local dy = cy - my
        dx, dy = ClampToMinimap(dx, dy)

        fr0z3nUI_AutoOpen_Settings.minimapButtonX = dx
        fr0z3nUI_AutoOpen_Settings.minimapButtonY = dy

        minimapButton:ClearAllPoints()
        minimapButton:SetPoint("CENTER", Minimap, "CENTER", dx, dy)
    end

    local function CreateMinimapButton()
        if minimapButton then return minimapButton end
        if not Minimap then return nil end

        minimapButton = CreateFrame("Button", "fr0z3nUI_AutoOpen_MinimapButton", Minimap)
        minimapButton:SetSize(32, 32)
        minimapButton:SetFrameStrata("MEDIUM")
        minimapButton:SetFrameLevel(8)
        minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

        local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
        icon:SetAllPoints()
        icon:SetTexture("Interface\\AddOns\\fr0z3nUI_AutoOpen\\Icons\\AutoIcon.tga")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        minimapButton.icon = icon

        local border = minimapButton:CreateTexture(nil, "OVERLAY")
        border:SetAllPoints()
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        minimapButton.border = border

        minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        minimapButton:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                if ToggleFAOOptionsWindow then
                    ToggleFAOOptionsWindow()
                end
                return
            end

            -- Left-click: open window directly to Toggles tab
            if ns and ns.UI and type(ns.UI.CreateOptionsWindow) == "function" then
                ns.UI.CreateOptionsWindow()
            end
            local f = fr0z3nUI_AutoOpenOptions
            if not f then return end
            f.activeTab = 2
            if f.SelectTab then
                f.SelectTab(2)
            end
            if not f:IsShown() then
                f:Show()
            end
        end)

        minimapButton:RegisterForDrag("LeftButton")
        minimapButton:SetMovable(true)
        minimapButton:SetClampedToScreen(true)
        minimapButton:SetScript("OnDragStart", function(self)
            self:StartMoving()
            self:SetScript("OnUpdate", UpdateDragPosition)
        end)
        minimapButton:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            self:SetScript("OnUpdate", nil)
            SetMinimapButtonPosition()
        end)

        minimapButton:SetScript("OnEnter", function()
            if not GameTooltip then return end
            GameTooltip:SetOwner(minimapButton, "ANCHOR_LEFT")
            GameTooltip:SetText("FAO")
            GameTooltip:AddLine("Left-click: Toggles", 1, 1, 1, true)
            GameTooltip:AddLine("Right-click: Toggle FAO window", 1, 1, 1, true)
            GameTooltip:AddLine("Drag: Move button", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        minimapButton:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)

        SetMinimapButtonPosition()
        return minimapButton
    end

    ToggleFAOOptionsWindow = function()
        if ns and ns.UI and type(ns.UI.ToggleWindow) == "function" then
            ns.UI.ToggleWindow()
        end
    end

    UpdateMinimapButtonVisibility = function()
        InitSV()
        local on = (fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.minimapButton == true)
        if on then
            CreateMinimapButton()
            if minimapButton then minimapButton:Show() end
        else
            if minimapButton then minimapButton:Hide() end
        end
    end
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
    local rest = text:match("^%S+%s+(.+)$") or ""
    local rest2 = text:match("^%S+%s+%S+%s+(.+)$") or ""

    if text == "?" or cmd == "?" or cmd == "help" then
        print("|cff00ccff[FAO]|r Commands:")
        print("|cff00ccff[FAO]|r /fao              - open/toggle window")
        print("|cff00ccff[FAO]|r /fao <itemid>      - open window + set item id")
        print("|cff00ccff[FAO]|r /fao kick          - manual scan kick")
        print("|cff00ccff[FAO]|r /fao on|off        - auto-open containers (shorthand)")
        print("|cff00ccff[FAO]|r /fao ao on|off     - auto-open containers")
        print("|cff00ccff[FAO]|r /fao cache [sec]   - pause auto-open briefly")
        print("|cff00ccff[FAO]|r /fao autoloot       - toggle forcing Auto Loot ON at login")
        print("|cff00ccff[FAO]|r /fao cd <seconds>  - open cooldown (0-10)")
        print("|cff00ccff[FAO]|r /fao gv            - cycle Great Vault OFF/ON/RL")
        print("|cff00ccff[FAO]|r /fao talents       - talent reminder help")
        print("|cff00ccff[FAO]|r /fao debug talents - toggle talent debug output")
        print("|cff00ccff[FAO]|r /fao debug gv      - toggle Great Vault debug output")
        return
    end

    if cmd == "kick" or cmd == "scan" then
        -- Silent unless an item actually opens; uses RunScan's normal guards.
        C_Timer.After(0.1, function()
            if frame and frame.RunScan then
                frame:RunScan(true)
            end
        end)
        return
    end

    -- Shorthand: /fao on|off
    if cmd == "on" or cmd == "off" then
        fr0z3nUI_AutoOpen_CharSettings.autoOpen = (cmd == "on")
        if cmd == "on" then
            print("|cff00ccff[FAO]|r Auto Open: |cff00ff00ON|r")
            C_Timer.After(0.1, function() if frame and frame.RunScan then frame:RunScan() end end)
        else
            print("|cff00ccff[FAO]|r Auto Open: |cffff0000OFF|r")
        end
        return
    end

    if cmd == "cache" then
        local seconds = tonumber(arg) or 2.2
        if seconds < 2 then seconds = 2 end
        if seconds > 10 then seconds = 10 end

        local wasEnabled = (fr0z3nUI_AutoOpen_CharSettings.autoOpen ~= false)
        if not wasEnabled then
            return
        end

        cachePauseSeq = cachePauseSeq + 1
        local seq = cachePauseSeq
        fr0z3nUI_AutoOpen_CharSettings.autoOpen = false

        C_Timer.After(seconds, function()
            if seq ~= cachePauseSeq then return end
            -- Only restore if still off (user didn't manually change it).
            if fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.autoOpen == false then
                fr0z3nUI_AutoOpen_CharSettings.autoOpen = true
                RequestScan(0.2)
            end
        end)
        return
    end

    if cmd == "autoloot" or cmd == "loot" or cmd == "al" then
        local state = arg
        local mode = GetAutoLootEnforceMode()

        if state == "" or state == "toggle" then
            if mode == "OFF" then
                fr0z3nUI_AutoOpen_CharSettings.autoLootOnLogin = true
                fr0z3nUI_AutoOpen_Settings.autoLootOnLoginAccount = nil
            elseif mode == "CHAR" then
                fr0z3nUI_AutoOpen_Settings.autoLootOnLoginAccount = true
            else
                fr0z3nUI_AutoOpen_Settings.autoLootOnLoginAccount = nil
                fr0z3nUI_AutoOpen_CharSettings.autoLootOnLogin = false
            end
        elseif state == "on" or state == "1" or state == "true" then
            fr0z3nUI_AutoOpen_Settings.autoLootOnLoginAccount = nil
            fr0z3nUI_AutoOpen_CharSettings.autoLootOnLogin = true
        elseif state == "acc" or state == "account" then
            fr0z3nUI_AutoOpen_CharSettings.autoLootOnLogin = true
            fr0z3nUI_AutoOpen_Settings.autoLootOnLoginAccount = true
        elseif state == "off" or state == "0" or state == "false" then
            fr0z3nUI_AutoOpen_Settings.autoLootOnLoginAccount = nil
            fr0z3nUI_AutoOpen_CharSettings.autoLootOnLogin = false
        elseif state == "status" then
            -- no-op
        else
            print("|cff00ccff[FAO]|r Usage: /fao autoloot [on|off|acc|toggle|status]")
            return
        end

        local _, enforce = GetAutoLootEnforceMode()
        if enforce then
            local ok = SetAutoLootDefaultSafe(true)
            if not ok then
                print("|cff00ccff[FAO]|r Auto Loot: |cffff0000failed to set CVar|r")
            end
        end

        local cur = GetAutoLootDefaultSafe()
        local curText = (cur == nil) and "unknown" or (cur and "ON" or "OFF")
        local m = GetAutoLootEnforceMode()
        local label = (m == "ACC") and "|cff00ff00ON ACC|r" or (m == "CHAR" and "|cff00ff00ON|r" or "|cffff0000OFF|r")
        print("|cff00ccff[FAO]|r Auto Loot on world: " .. label .. " (current: |cffffff00" .. curText .. "|r)")
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

        if target == "gv" or target == "greatvault" then
            InitSV()
            local cur = (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.debugGreatVault) and true or false
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
                print("|cff00ccff[FAO]|r Usage: /fao debug gv [on|off|toggle|status]")
                return
            end

            fr0z3nUI_AutoOpen_CharSettings.debugGreatVault = nextVal
            print("|cff00ccff[FAO]|r Great Vault debug: " .. (nextVal and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
            return
        end

        print("|cff00ccff[FAO]|r Usage: /fao debug talents [on|off|toggle|status]")
        print("|cff00ccff[FAO]|r Usage: /fao debug gv     [on|off|toggle|status]")
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
            local mode = GetGreatVaultAutoOpenMode()
            if mode == "OFF" then
                fr0z3nUI_AutoOpen_CharSettings.greatVaultMode = "ON"
                fr0z3nUI_AutoOpen_Settings.greatVaultAccount = nil
                arg = "on"
            elseif mode == "CHAR" then
                fr0z3nUI_AutoOpen_CharSettings.greatVaultMode = "ON"
                fr0z3nUI_AutoOpen_Settings.greatVaultAccount = true
                arg = "acc"
            else
                fr0z3nUI_AutoOpen_Settings.greatVaultAccount = nil
                fr0z3nUI_AutoOpen_CharSettings.greatVaultMode = "OFF"
                arg = "off"
            end
        end

        if arg == "off" then
            fr0z3nUI_AutoOpen_CharSettings.greatVaultMode = "OFF"
            fr0z3nUI_AutoOpen_Settings.greatVaultAccount = nil
            fr0z3nUI_AutoOpen_CharSettings.greatVaultTouched = true
            print("|cff00ccff[FAO]|r AutoOpen Great Vault: |cffff0000OFF|r")
        elseif arg == "on" then
            fr0z3nUI_AutoOpen_CharSettings.greatVaultMode = "ON"
            fr0z3nUI_AutoOpen_Settings.greatVaultAccount = nil
            fr0z3nUI_AutoOpen_CharSettings.greatVaultTouched = true
            print("|cff00ccff[FAO]|r AutoOpen Great Vault: |cff00ff00ON|r")
            C_Timer.After(0.1, ns.ShowGreatVault)
        elseif arg == "acc" or arg == "account" then
            fr0z3nUI_AutoOpen_CharSettings.greatVaultMode = "ON"
            fr0z3nUI_AutoOpen_Settings.greatVaultAccount = true
            fr0z3nUI_AutoOpen_CharSettings.greatVaultTouched = true
            print("|cff00ccff[FAO]|r AutoOpen Great Vault: |cff00ff00ON ACC|r")
            C_Timer.After(0.1, ns.ShowGreatVault)
        elseif arg == "try" or arg == "test" then
            InitSV()
            if QueueGreatVaultAutoOpen then
                QueueGreatVaultAutoOpen(false)
                print("|cff00ccff[FAO]|r [GV] queued")
            else
                print("|cff00ccff[FAO]|r [GV] queue unavailable")
            end
        elseif arg == "debug" then
            InitSV()
            local mode, enabled = GetGreatVaultAutoOpenMode()
            local lvl = (UnitLevel and UnitLevel("player"))
            local req = GetGreatVaultRequiredLevel and GetGreatVaultRequiredLevel() or "?"
            local atLvl = IsPlayerAtGreatVaultLevel and IsPlayerAtGreatVaultLevel()
            local addonLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_WeeklyRewards"))
            local frameExists = (WeeklyRewardsFrame and true) or false
            local acc = fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.greatVaultAccount
            local charMode = fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.greatVaultMode
            print("|cff00ccff[FAO]|r [GV] mode="..tostring(mode).." enabled="..tostring(enabled).." accFlag="..tostring(acc).." charMode="..tostring(charMode))
            print("|cff00ccff[FAO]|r [GV] lvl="..tostring(lvl).." req="..tostring(req).." atLvl="..tostring(atLvl).." addonLoaded="..tostring(addonLoaded).." frame="..tostring(frameExists))
            print("|cff00ccff[FAO]|r [GV] didOpenThisLogin="..tostring(frame and frame._didOpenGreatVaultThisLogin).." pending="..tostring(frame and frame._gvPending).." seq="..tostring(frame and frame._gvSeq))
            return
        else
            print("|cff00ccff[FAO]|r Usage: /fao gv           - cycle OFF/ON/ACC")
            print("|cff00ccff[FAO]|r Usage: /fao gv off       - disable")
            print("|cff00ccff[FAO]|r Usage: /fao gv on        - enable (opens on initial login; requires max level)")
            print("|cff00ccff[FAO]|r Usage: /fao gv acc       - enable account-wide (opens on initial login; requires max level)")
            print("|cff00ccff[FAO]|r Usage: /fao gv try       - queue auto-open now")
            print("|cff00ccff[FAO]|r Usage: /fao gv debug     - print Great Vault state")
        end
        return
    end

    if cmd == "talent" or cmd == "talents" then
        local sub, subarg = text:match("^%S+%s+(%S+)%s*(%S*)")
        sub = sub and sub:lower() or ""
        subarg = subarg and subarg:lower() or ""

        local function PrintTalentStatus()
            local uiMode = GetTalentAutoOpenMode()
            local ui = (uiMode == "ACC") and "ON ACC" or (uiMode == "CHAR" and "ON" or "OFF")
            print("|cff00ccff[FAO]|r Talents: "..ui.." (WORLD)")
        end

        if arg == "" and sub == "" then
            PrintTalentStatus()
            print("|cff00ccff[FAO]|r Usage: /fao talents toggle")
            print("|cff00ccff[FAO]|r Usage: /fao talents ui off|on|acc")
            print("|cff00ccff[FAO]|r Usage: /fao talents check")
            return
        end

        if arg == "toggle" then
            local uiMode = GetTalentAutoOpenMode()
            if uiMode == "OFF" then
                fr0z3nUI_AutoOpen_CharSettings.talentAutoOpen = true
                fr0z3nUI_AutoOpen_Settings.talentAutoOpenAccount = nil
            elseif uiMode == "CHAR" then
                fr0z3nUI_AutoOpen_Settings.talentAutoOpenAccount = true
            else
                fr0z3nUI_AutoOpen_Settings.talentAutoOpenAccount = nil
                fr0z3nUI_AutoOpen_CharSettings.talentAutoOpen = false
            end
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

        if arg == "off" then
            fr0z3nUI_AutoOpen_Settings.talentAutoOpenAccount = nil
            fr0z3nUI_AutoOpen_CharSettings.talentAutoOpen = false
            PrintTalentStatus()
            return
        end
        if arg == "on" then
            fr0z3nUI_AutoOpen_Settings.talentAutoOpenAccount = nil
            fr0z3nUI_AutoOpen_CharSettings.talentAutoOpen = true
            PrintTalentStatus()
            return
        end

        -- Backwards-compat: legacy mode args now map to ON/OFF with WORLD behavior.
        if arg == "login" or arg == "rl" or arg == "reload" or arg == "world" then
            fr0z3nUI_AutoOpen_Settings.talentAutoOpenAccount = nil
            fr0z3nUI_AutoOpen_CharSettings.talentAutoOpen = (arg ~= "off")
            PrintTalentStatus()
            return
        end

        print("|cff00ccff[FAO]|r Usage: /fao talents ui off|on|acc")
        return
    end

    -- Default behavior: open/toggle GUI and allow pasting an itemID
    if ns and ns.UI and type(ns.UI.ToggleWindow) == "function" then
        ns.UI.ToggleWindow(text)
    end
end

-- Expose a small, explicit API for UI modules.
ns.API = ns.API or {}
ns.API.engineFrame = frame
ns.API.InitSV = InitSV
ns.API.NormalizeCooldown = NormalizeCooldown
ns.API.GetOpenCooldown = GetOpenCooldown
ns.API.ResetAllSavedVariables = ResetAllSavedVariables
ns.API.ResetAccFailStreak = ResetAccFailStreak
ns.API.GetItemNameSafe = GetItemNameSafe
ns.API.GetRequiredLevelForID = GetRequiredLevelForID
ns.API.IsProbablyOpenableCacheID = IsProbablyOpenableCacheID
ns.API.SetAutoLootDefaultSafe = SetAutoLootDefaultSafe
ns.API.GetAutoLootEnforceMode = GetAutoLootEnforceMode
ns.API.ApplyNPCNameplatesSettingOnWorld = ApplyNPCNameplatesSettingOnWorld
ns.API.GetFriendlyNPCNameplatesSafe = GetFriendlyNPCNameplatesSafe
ns.API.GetNPCNameplatesSettingEffective = GetNPCNameplatesSettingEffective
ns.API.GetGreatVaultAutoOpenMode = GetGreatVaultAutoOpenMode
ns.API.ShowGreatVault = ns and ns.ShowGreatVault or nil
ns.API.GetTalentAutoOpenMode = GetTalentAutoOpenMode
ns.API.GetTrainerAutoLearnMode = GetTrainerAutoLearnMode
ns.API.UpdateMinimapButtonVisibility = UpdateMinimapButtonVisibility
