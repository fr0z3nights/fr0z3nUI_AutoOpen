local addonName, ns = ...
local lastOpenTime, atBank, atMail = 0, false, false
local didPruneCustomWhitelists = false

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

local function InitSV()
    fr0z3nUI_AutoOpen_Acc = fr0z3nUI_AutoOpen_Acc or {}
    fr0z3nUI_AutoOpen_Char = fr0z3nUI_AutoOpen_Char or {}
    fr0z3nUI_AutoOpen_Settings = fr0z3nUI_AutoOpen_Settings or { disabled = {} }
    fr0z3nUI_AutoOpen_CharSettings = fr0z3nUI_AutoOpen_CharSettings or {}

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
                    elseif not ns.exclude[id] and not fr0z3nUI_AutoOpen_Settings.disabled[id] then
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
        InitSV(); C_Timer.After(2, CheckTimersOnLogin)
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        InitSV()
        AutoEnableGreatVaultAtMaxLevel()
        local mode = (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.greatVaultMode) or "OFF"
        mode = tostring(mode):upper()
        if mode == "ON" and isInitialLogin and not isReloadingUi then
            C_Timer.After(5, ns.ShowGreatVault)
        elseif mode == "RL" and isReloadingUi then
            C_Timer.After(5, ns.ShowGreatVault)
        end
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
    if scope == "acc" then
        if fr0z3nUI_AutoOpen_Acc[id] then print("|cff00ccff[FAO]|r Already in Account whitelist: "..(GetItemNameSafe(id) or id)) return end
        fr0z3nUI_AutoOpen_Acc[id] = true
    else
        if fr0z3nUI_AutoOpen_Char[id] then print("|cff00ccff[FAO]|r Already in Character whitelist: "..(GetItemNameSafe(id) or id)) return end
        fr0z3nUI_AutoOpen_Char[id] = true
    end
    local iname = GetItemNameSafe(id) or tostring(id)
    print("|cff00ccff[FAO]|r Added: |cffffff00"..iname.."|r to "..(scope=="acc" and "Account" or "Character"))
end

local function CreateOptionsWindow()
    if fr0z3nUI_AutoOpenOptions then return end
    InitSV()
    local f = CreateFrame("Frame", "fr0z3nUI_AutoOpenOptions", UIParent, "BackdropTemplate")
    fr0z3nUI_AutoOpenOptions = f
    f:SetSize(280,170)
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

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -8)
    title:SetText("fr0z3nUI AutoOpen")

    local info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    info:SetPoint("TOP", title, "BOTTOM", 0, -4)
    info:SetText("Enter ItemID Below")

    local edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    edit:SetSize(155,38)
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

    local nameLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameLabel:SetPoint("TOP", edit, "BOTTOM", 0, -2)
    nameLabel:SetWidth(f:GetWidth() - 20)
    nameLabel:SetJustifyH("CENTER")
    nameLabel:SetWordWrap(true)
    nameLabel:SetText("")
    f.nameLabel = nameLabel

    local reasonLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    reasonLabel:SetPoint("TOP", nameLabel, "BOTTOM", 0, -2)
    reasonLabel:SetWidth(f:GetWidth() - 20)
    reasonLabel:SetJustifyH("CENTER")
    reasonLabel:SetWordWrap(true)
    reasonLabel:SetText("")
    f.reasonLabel = reasonLabel

    local BTN_W, BTN_H = 125, 22
    local PAD_X = 10
    local ROW_TOP_Y = 38
    local ROW_BOTTOM_Y = 10

    local btnChar = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnChar:SetSize(BTN_W, BTN_H)
    btnChar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD_X, ROW_TOP_Y)
    btnChar:SetText("Character")
    btnChar:SetScript("OnClick", function()
        local id = f.validID or tonumber(edit:GetText() or "")
        AddItemByID(id, "char")
    end)
    btnChar:Disable()
    f.btnChar = btnChar

    local btnAcc = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnAcc:SetSize(BTN_W, BTN_H)
    btnAcc:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD_X, ROW_TOP_Y)
    btnAcc:SetText("Account")
    btnAcc:SetScript("OnClick", function()
        local id = f.validID or tonumber(edit:GetText() or "")
        AddItemByID(id, "acc")
    end)
    btnAcc:Disable()
    f.btnAcc = btnAcc

    local function UpdateAutoOpenButton()
        InitSV()
        local enabled = (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.autoOpen ~= false)
        if f.btnAutoOpen then
            f.btnAutoOpen:SetText("Auto Open: "..(enabled and "ON" or "OFF"))
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

    local btnAutoOpen = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnAutoOpen:SetSize(BTN_W, BTN_H)
    btnAutoOpen:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD_X, ROW_BOTTOM_Y)
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

    local btnGreatVault = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnGreatVault:SetSize(BTN_W, BTN_H)
    btnGreatVault:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD_X, ROW_BOTTOM_Y)
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

    -- debounced validation function
    local function DoValidate()
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
            if f.btnChar then f.btnChar:Enable() end
            if f.btnAcc then f.btnAcc:Enable() end
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
            if f.reasonLabel then f.reasonLabel:SetText("") end
            f.validID = id
            if f.btnChar then f.btnChar:Enable() end
            if f.btnAcc then f.btnAcc:Enable() end
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
        UpdateGreatVaultButton()
    end)

    UpdateAutoOpenButton()
    UpdateGreatVaultButton()
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
