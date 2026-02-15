local addonName, ns = ...

ns.Toggles = ns.Toggles or {}

function ns.Toggles.Build(opts)
    opts = opts or {}

    local f = opts.optionsFrame
    local togglesPanel = opts.togglesPanel
    local itemsPanel = opts.itemsPanel

    if not (f and togglesPanel and itemsPanel) then
        return nil
    end

    local InitSV = opts.InitSV
    local engineFrame = opts.engineFrame

    local BTN_W = tonumber(opts.BTN_W) or 125
    local BTN_H = tonumber(opts.BTN_H) or 22
    local ACTION_W = tonumber(opts.ACTION_W) or 90
    local ACTION_H = tonumber(opts.ACTION_H) or 22
    local FRAME_W = tonumber(opts.FRAME_W) or 520

    local SetAutoLootDefaultSafe = opts.SetAutoLootDefaultSafe
    local GetAutoLootEnforceMode = opts.GetAutoLootEnforceMode

    local ApplyNPCNameplatesSettingOnWorld = opts.ApplyNPCNameplatesSettingOnWorld
    local GetFriendlyNPCNameplatesSafe = opts.GetFriendlyNPCNameplatesSafe
    local GetNPCNameplatesSettingEffective = opts.GetNPCNameplatesSettingEffective

    local GetGreatVaultAutoOpenMode = opts.GetGreatVaultAutoOpenMode
    local ShowGreatVault = opts.ShowGreatVault

    local GetTalentAutoOpenMode = opts.GetTalentAutoOpenMode

    local GetTrainerAutoLearnMode = opts.GetTrainerAutoLearnMode

    local UpdateMinimapButtonVisibility = opts.UpdateMinimapButtonVisibility
    local ResetAllSV = opts.ResetAllSV

    local function EnsureSplitButtonText(btn)
        if not btn or btn._splitReady then return end
        btn._splitReady = true

        local fs = btn.GetFontString and btn:GetFontString() or nil
        if fs and fs.Hide then fs:Hide() end

        local left = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        left:SetPoint("LEFT", btn, "LEFT", 8, 0)
        left:SetJustifyH("LEFT")

        local right = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        right:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
        right:SetJustifyH("RIGHT")

        btn._leftText = left
        btn._rightText = right
    end

    local function SetSplitButtonText(btn, leftText, rightText)
        if not btn then return end
        EnsureSplitButtonText(btn)
        if btn._leftText then btn._leftText:SetText(tostring(leftText or "")) end
        if btn._rightText then btn._rightText:SetText(tostring(rightText or "")) end
    end

    local function UpdateMinimapButton()
        if type(InitSV) == "function" then InitSV() end
        if f.btnMinimap then
            local on = (fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.minimapButton == true)
            SetSplitButtonText(f.btnMinimap, "Minimap", (on and "ON ACC" or "OFF ACC"))
        end
        if type(UpdateMinimapButtonVisibility) == "function" then
            UpdateMinimapButtonVisibility()
        end
    end

    local function UpdateAutoOpenButton()
        if type(InitSV) == "function" then InitSV() end
        local enabled = (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.autoOpen ~= false)
        if f.btnAutoOpen then
            SetSplitButtonText(f.btnAutoOpen, "Auto Open", (enabled and "ON" or "OFF"))
        end
    end

    local function UpdateAutoLootButton()
        if type(InitSV) == "function" then InitSV() end
        if f.btnAutoLoot then
            local mode = (type(GetAutoLootEnforceMode) == "function") and GetAutoLootEnforceMode() or "OFF"
            if mode == "ACC" then
                SetSplitButtonText(f.btnAutoLoot, "Auto Loot", "ON ACC")
            elseif mode == "CHAR" then
                SetSplitButtonText(f.btnAutoLoot, "Auto Loot", "ON")
            else
                SetSplitButtonText(f.btnAutoLoot, "Auto Loot", "OFF")
            end
        end
    end

    local function UpdateNPCNameButton()
        if type(InitSV) == "function" then InitSV() end
        if not f.btnNPCName then return end

        local acc = fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.npcNameplatesAccount
        if acc == true then
            SetSplitButtonText(f.btnNPCName, "NPC Name", "ON ACC")
        elseif acc == false then
            SetSplitButtonText(f.btnNPCName, "NPC Name", "OFF ACC")
        else
            local enabled = (type(GetNPCNameplatesSettingEffective) == "function") and GetNPCNameplatesSettingEffective() or false
            SetSplitButtonText(f.btnNPCName, "NPC Name", (enabled and "ON" or "OFF"))
        end
    end

    local function UpdateGreatVaultButton()
        if type(InitSV) == "function" then InitSV() end
        if f.btnGreatVault then
            local mode = (type(GetGreatVaultAutoOpenMode) == "function") and GetGreatVaultAutoOpenMode() or "OFF"
            if mode == "ACC" then
                SetSplitButtonText(f.btnGreatVault, "Great Vault", "ON ACC")
            elseif mode == "CHAR" then
                SetSplitButtonText(f.btnGreatVault, "Great Vault", "ON")
            else
                SetSplitButtonText(f.btnGreatVault, "Great Vault", "OFF")
            end
        end
    end

    local function UpdateCacheLockButton()
        if type(InitSV) == "function" then InitSV() end
        local enabled = (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.cacheLockCheck ~= false)
        if f.btnCacheLock then
            SetSplitButtonText(f.btnCacheLock, "Cache", (enabled and "ON" or "OFF"))
        end
    end

    local function UpdateTalentButtons()
        if type(InitSV) == "function" then InitSV() end
        local uiMode = (type(GetTalentAutoOpenMode) == "function") and GetTalentAutoOpenMode() or "OFF"
        if f.btnTalentsAuto then
            if uiMode == "ACC" then
                SetSplitButtonText(f.btnTalentsAuto, "Talents", "ON ACC")
            elseif uiMode == "CHAR" then
                SetSplitButtonText(f.btnTalentsAuto, "Talents", "ON")
            else
                SetSplitButtonText(f.btnTalentsAuto, "Talents", "OFF")
            end
        end
    end

    local function UpdateTrainerLearnButton()
        if type(InitSV) == "function" then InitSV() end
        if f.btnTrainerLearn then
            local mode = (type(GetTrainerAutoLearnMode) == "function") and GetTrainerAutoLearnMode() or "OFF"
            if mode == "ACC" then
                SetSplitButtonText(f.btnTrainerLearn, "Trainer", "ON ACC")
            elseif mode == "CHAR" then
                SetSplitButtonText(f.btnTrainerLearn, "Trainer", "ON")
            else
                SetSplitButtonText(f.btnTrainerLearn, "Trainer", "OFF")
            end
        end
    end

    local function UpdateWatchdogDebugButton()
        if type(InitSV) == "function" then InitSV() end
        if not f.btnWatchdogDebug then return end
        local on = (fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.debugWatchdogAcc) and true or false
        SetSplitButtonText(f.btnWatchdogDebug, "Watchdog", (on and "DBG ON ACC" or "DBG OFF ACC"))
    end

    local function UpdateAll()
        UpdateAutoOpenButton()
        UpdateAutoLootButton()
        UpdateNPCNameButton()
        UpdateGreatVaultButton()
        UpdateCacheLockButton()
        UpdateTalentButtons()
        UpdateTrainerLearnButton()
        UpdateMinimapButton()
        UpdateWatchdogDebugButton()
    end

    local TOGGLE_TOP_Y = -46
    local TOGGLE_ROW_STEP = BTN_H * 2
    local TOGGLE_COL_X = math.floor((FRAME_W or 520) / 4)

    local btnAutoLoot = CreateFrame("Button", nil, togglesPanel, "UIPanelButtonTemplate")
    btnAutoLoot:SetSize(BTN_W, BTN_H)
    btnAutoLoot:SetPoint("TOP", togglesPanel, "TOP", -TOGGLE_COL_X, TOGGLE_TOP_Y - TOGGLE_ROW_STEP)
    btnAutoLoot:SetScript("OnClick", function()
        if type(InitSV) == "function" then InitSV() end
        local mode = (type(GetAutoLootEnforceMode) == "function") and GetAutoLootEnforceMode() or "OFF"
        if mode == "OFF" then
            fr0z3nUI_AutoOpen_CharSettings.autoLootOnLogin = true
            fr0z3nUI_AutoOpen_Settings.autoLootOnLoginAccount = nil
            local ok = (type(SetAutoLootDefaultSafe) == "function") and SetAutoLootDefaultSafe(true)
            if ok then
                print("|cff00ccff[FAO]|r Auto Loot on world: |cff00ff00ON|r")
            else
                print("|cff00ccff[FAO]|r Auto Loot on world: |cff00ff00ON|r (but failed to set CVar)")
            end
        elseif mode == "CHAR" then
            fr0z3nUI_AutoOpen_Settings.autoLootOnLoginAccount = true
            local ok = (type(SetAutoLootDefaultSafe) == "function") and SetAutoLootDefaultSafe(true)
            if ok then
                print("|cff00ccff[FAO]|r Auto Loot on world: |cff00ff00ON ACC|r")
            else
                print("|cff00ccff[FAO]|r Auto Loot on world: |cff00ff00ON ACC|r (but failed to set CVar)")
            end
        else
            fr0z3nUI_AutoOpen_Settings.autoLootOnLoginAccount = nil
            fr0z3nUI_AutoOpen_CharSettings.autoLootOnLogin = false
            print("|cff00ccff[FAO]|r Auto Loot on world: |cffff0000OFF|r")
        end
        UpdateAutoLootButton()
    end)
    btnAutoLoot:SetScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:SetOwner(f, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("BOTTOM", btnAutoLoot, "TOP", 0, 10)
            GameTooltip:SetText("Auto Loot")
            GameTooltip:AddLine("When enabled, forces Auto Loot to be enabled on world entry.", 1, 1, 1, true)
            GameTooltip:AddLine("(/reload, portals, instances)", 1, 1, 1, true)
            GameTooltip:AddLine("\nCycles: OFF -> ON -> ON ACC", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    btnAutoLoot:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    f.btnAutoLoot = btnAutoLoot

    local btnNPCName = CreateFrame("Button", nil, togglesPanel, "UIPanelButtonTemplate")
    btnNPCName:SetSize(BTN_W, BTN_H)
    btnNPCName:SetPoint("TOP", togglesPanel, "TOP", TOGGLE_COL_X, TOGGLE_TOP_Y - TOGGLE_ROW_STEP)
    btnNPCName:SetScript("OnClick", function()
        if type(InitSV) == "function" then InitSV() end
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
        if type(ApplyNPCNameplatesSettingOnWorld) == "function" then
            ApplyNPCNameplatesSettingOnWorld()
        end
        UpdateNPCNameButton()
    end)
    btnNPCName:SetScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:SetOwner(f, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("BOTTOM", btnNPCName, "TOP", 0, 10)
            GameTooltip:SetText("Friendly NPC Nameplates")
            GameTooltip:AddLine("Cycles: ON (default) -> ON ACC -> OFF ACC", 1, 1, 1, true)
            local cur = (type(GetFriendlyNPCNameplatesSafe) == "function") and GetFriendlyNPCNameplatesSafe() or nil
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
    btnAutoOpen:SetPoint("TOP", togglesPanel, "TOP", TOGGLE_COL_X, TOGGLE_TOP_Y)
    btnAutoOpen:SetScript("OnClick", function()
        if type(InitSV) == "function" then InitSV() end
        local enabled = (fr0z3nUI_AutoOpen_CharSettings.autoOpen ~= false)
        fr0z3nUI_AutoOpen_CharSettings.autoOpen = not enabled
        if fr0z3nUI_AutoOpen_CharSettings.autoOpen then
            print("|cff00ccff[FAO]|r Auto Open: |cff00ff00ON|r")
            C_Timer.After(0.1, function()
                if engineFrame and engineFrame.RunScan then
                    engineFrame:RunScan()
                end
            end)
        else
            print("|cff00ccff[FAO]|r Auto Open: |cffff0000OFF|r")
        end
        UpdateAutoOpenButton()
    end)
    f.btnAutoOpen = btnAutoOpen

    local btnGreatVault = CreateFrame("Button", nil, togglesPanel, "UIPanelButtonTemplate")
    btnGreatVault:SetSize(BTN_W, BTN_H)
    btnGreatVault:SetPoint("TOP", togglesPanel, "TOP", -TOGGLE_COL_X, TOGGLE_TOP_Y)
    btnGreatVault:SetScript("OnClick", function()
        if type(InitSV) == "function" then InitSV() end
        local mode = (type(GetGreatVaultAutoOpenMode) == "function") and GetGreatVaultAutoOpenMode() or "OFF"
        if mode == "OFF" then
            fr0z3nUI_AutoOpen_CharSettings.greatVaultMode = "ON"
            fr0z3nUI_AutoOpen_Settings.greatVaultAccount = nil
        elseif mode == "CHAR" then
            fr0z3nUI_AutoOpen_CharSettings.greatVaultMode = "ON"
            fr0z3nUI_AutoOpen_Settings.greatVaultAccount = true
        else
            fr0z3nUI_AutoOpen_Settings.greatVaultAccount = nil
            fr0z3nUI_AutoOpen_CharSettings.greatVaultMode = "OFF"
        end
        fr0z3nUI_AutoOpen_CharSettings.greatVaultTouched = true

        local m = (type(GetGreatVaultAutoOpenMode) == "function") and GetGreatVaultAutoOpenMode() or "OFF"
        if m == "OFF" then
            print("|cff00ccff[FAO]|r AutoOpen Great Vault: |cffff0000OFF|r")
        elseif m == "ACC" then
            print("|cff00ccff[FAO]|r AutoOpen Great Vault: |cff00ff00ON ACC|r")
            if type(ShowGreatVault) == "function" then C_Timer.After(0.1, ShowGreatVault) end
        else
            print("|cff00ccff[FAO]|r AutoOpen Great Vault: |cff00ff00ON|r")
            if type(ShowGreatVault) == "function" then C_Timer.After(0.1, ShowGreatVault) end
        end
        UpdateGreatVaultButton()
    end)
    btnGreatVault:SetScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:SetOwner(f, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("LEFT", btnGreatVault, "RIGHT", 8, 0)
            GameTooltip:SetText("Great Vault")
            GameTooltip:AddLine("Opens automatically on initial login world entry when enabled.", 1, 1, 1, true)
            GameTooltip:AddLine("Requires max level.", 1, 1, 1, true)
            GameTooltip:AddLine("\nCycles: OFF -> ON -> ON ACC", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    btnGreatVault:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    f.btnGreatVault = btnGreatVault

    local btnCacheLock = CreateFrame("Button", nil, itemsPanel, "UIPanelButtonTemplate")
    btnCacheLock:SetSize(ACTION_W, ACTION_H)
    btnCacheLock:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 10)
    btnCacheLock:SetScript("OnClick", function()
        if type(InitSV) == "function" then InitSV() end
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

    local btnTrainerLearn = CreateFrame("Button", nil, togglesPanel, "UIPanelButtonTemplate")
    btnTrainerLearn:SetSize(BTN_W, BTN_H)
    btnTrainerLearn:SetPoint("TOP", togglesPanel, "TOP", TOGGLE_COL_X, TOGGLE_TOP_Y - (TOGGLE_ROW_STEP * 2))
    btnTrainerLearn:SetScript("OnClick", function()
        if type(InitSV) == "function" then InitSV() end
        local mode = (type(GetTrainerAutoLearnMode) == "function") and GetTrainerAutoLearnMode() or "OFF"

        if mode == "OFF" then
            fr0z3nUI_AutoOpen_CharSettings.autoLearnTrainer = true
            fr0z3nUI_AutoOpen_Settings.autoLearnTrainerAccount = nil
        elseif mode == "CHAR" then
            fr0z3nUI_AutoOpen_Settings.autoLearnTrainerAccount = true
        else
            fr0z3nUI_AutoOpen_Settings.autoLearnTrainerAccount = nil
            fr0z3nUI_AutoOpen_CharSettings.autoLearnTrainer = false
        end

        local newMode = (type(GetTrainerAutoLearnMode) == "function") and GetTrainerAutoLearnMode() or "OFF"
        if newMode == "ACC" then
            print("|cff00ccff[FAO]|r Trainer auto-learn: |cff00ff00ON ACC|r")
        elseif newMode == "CHAR" then
            print("|cff00ccff[FAO]|r Trainer auto-learn: |cff00ff00ON|r")
        else
            print("|cff00ccff[FAO]|r Trainer auto-learn: |cffff0000OFF|r")
        end
        UpdateTrainerLearnButton()
    end)
    btnTrainerLearn:SetScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:SetOwner(f, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("LEFT", btnTrainerLearn, "RIGHT", 8, 0)
            GameTooltip:SetText("Profession Trainer Auto-Learn")
            GameTooltip:AddLine("When enabled, automatically learns all available trainer recipes when you open a trainer.", 1, 1, 1, true)
            GameTooltip:AddLine("(Works with the Trainer UI; skips if unavailable.)", 1, 1, 1, true)
            GameTooltip:AddLine("\nCycles: OFF -> ON -> ON ACC", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    btnTrainerLearn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    f.btnTrainerLearn = btnTrainerLearn

    local btnMinimap = CreateFrame("Button", nil, togglesPanel, "UIPanelButtonTemplate")
    btnMinimap:SetSize(BTN_W, BTN_H)
    btnMinimap:SetPoint("TOP", togglesPanel, "TOP", -TOGGLE_COL_X, TOGGLE_TOP_Y - (TOGGLE_ROW_STEP * 3))
    btnMinimap:SetScript("OnClick", function()
        if type(InitSV) == "function" then InitSV() end
        local cur = (fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.minimapButton == true)
        fr0z3nUI_AutoOpen_Settings.minimapButton = not cur
        print("|cff00ccff[FAO]|r Minimap button: "..(fr0z3nUI_AutoOpen_Settings.minimapButton and "|cff00ff00ON ACC|r" or "|cffff0000OFF ACC|r"))
        UpdateMinimapButton()
    end)
    btnMinimap:SetScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:SetOwner(f, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("LEFT", btnMinimap, "RIGHT", 8, 0)
            GameTooltip:SetText("Minimap Button")
            GameTooltip:AddLine("Shows/hides the FAO minimap button (account-wide).", 1, 1, 1, true)
            GameTooltip:AddLine("Default: OFF", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    btnMinimap:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    f.btnMinimap = btnMinimap

    local btnWatchdogDebug = CreateFrame("Button", nil, togglesPanel, "UIPanelButtonTemplate")
    btnWatchdogDebug:SetSize(BTN_W, BTN_H)
    btnWatchdogDebug:SetPoint("TOP", togglesPanel, "TOP", TOGGLE_COL_X, TOGGLE_TOP_Y - (TOGGLE_ROW_STEP * 3))
    btnWatchdogDebug:SetScript("OnClick", function()
        if type(InitSV) == "function" then InitSV() end
        local cur = (fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.debugWatchdogAcc) and true or false
        fr0z3nUI_AutoOpen_Settings.debugWatchdogAcc = not cur
        print("|cff00ccff[FAO]|r Watchdog debug: " .. (fr0z3nUI_AutoOpen_Settings.debugWatchdogAcc and "|cff00ff00ON ACC|r" or "|cffff0000OFF ACC|r"))
        UpdateWatchdogDebugButton()
    end)
    btnWatchdogDebug:SetScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:SetOwner(f, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("LEFT", btnWatchdogDebug, "RIGHT", 8, 0)
            GameTooltip:SetText("Watchdog Debug")
            GameTooltip:AddLine("When ON, prints a message when the watchdog kicks a scan.", 1, 1, 1, true)
            GameTooltip:AddLine("Default: OFF ACC", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    btnWatchdogDebug:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    f.btnWatchdogDebug = btnWatchdogDebug

    local btnReset = CreateFrame("Button", nil, togglesPanel, "UIPanelButtonTemplate")
    btnReset:SetSize(ACTION_W, ACTION_H)
    btnReset:SetPoint("BOTTOM", togglesPanel, "BOTTOM", -TOGGLE_COL_X, 10)
    btnReset:SetText("Reset SV")
    btnReset:SetScript("OnClick", function()
        if type(ResetAllSV) == "function" then
            ResetAllSV()
        end
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

    local btnTalentsAuto = CreateFrame("Button", nil, togglesPanel, "UIPanelButtonTemplate")
    btnTalentsAuto:SetSize(BTN_W, BTN_H)
    btnTalentsAuto:SetPoint("TOP", togglesPanel, "TOP", -TOGGLE_COL_X, TOGGLE_TOP_Y - (TOGGLE_ROW_STEP * 2))
    btnTalentsAuto:SetScript("OnClick", function()
        if type(InitSV) == "function" then InitSV() end
        local mode = (type(GetTalentAutoOpenMode) == "function") and GetTalentAutoOpenMode() or "OFF"
        if mode == "OFF" then
            fr0z3nUI_AutoOpen_CharSettings.talentAutoOpen = true
            fr0z3nUI_AutoOpen_Settings.talentAutoOpenAccount = nil
            print("|cff00ccff[FAO]|r Talents: ON (Character)")
        elseif mode == "CHAR" then
            fr0z3nUI_AutoOpen_Settings.talentAutoOpenAccount = true
            print("|cff00ccff[FAO]|r Talents: ON (Account)")
        else
            fr0z3nUI_AutoOpen_Settings.talentAutoOpenAccount = nil
            fr0z3nUI_AutoOpen_CharSettings.talentAutoOpen = false
            print("|cff00ccff[FAO]|r Talents: OFF")
        end
        UpdateTalentButtons()
    end)
    btnTalentsAuto:SetScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:SetOwner(f, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("LEFT", btnTalentsAuto, "RIGHT", 8, 0)
            GameTooltip:SetText("Talents")
            GameTooltip:AddLine("When enabled, FAO checks for unspent talent points and can open the talents UI (out of combat).", 1, 1, 1, true)
            GameTooltip:AddLine("Trigger: WORLD (reload + portals/instances)", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    btnTalentsAuto:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    f.btnTalentsAuto = btnTalentsAuto

    UpdateAll()

    return {
        UpdateAll = UpdateAll,
        UpdateAutoOpenButton = UpdateAutoOpenButton,
        UpdateAutoLootButton = UpdateAutoLootButton,
        UpdateNPCNameButton = UpdateNPCNameButton,
        UpdateGreatVaultButton = UpdateGreatVaultButton,
        UpdateCacheLockButton = UpdateCacheLockButton,
        UpdateTalentButtons = UpdateTalentButtons,
        UpdateTrainerLearnButton = UpdateTrainerLearnButton,
        UpdateMinimapButton = UpdateMinimapButton,
        UpdateWatchdogDebugButton = UpdateWatchdogDebugButton,
    }
end
