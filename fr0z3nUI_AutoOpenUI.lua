local addonName, ns = ...

ns.UI = ns.UI or {}

local api = ns.API or {}

local frame = api.engineFrame

local InitSV = api.InitSV
local NormalizeCooldown = api.NormalizeCooldown
local GetOpenCooldown = api.GetOpenCooldown
local ResetAllSavedVariables = api.ResetAllSavedVariables
local ResetAccFailStreak = api.ResetAccFailStreak

local GetItemNameSafe = api.GetItemNameSafe
local GetRequiredLevelForID = api.GetRequiredLevelForID
local IsProbablyOpenableCacheID = api.IsProbablyOpenableCacheID

local SetAutoLootDefaultSafe = api.SetAutoLootDefaultSafe
local GetAutoLootEnforceMode = api.GetAutoLootEnforceMode

local ApplyNPCNameplatesSettingOnWorld = api.ApplyNPCNameplatesSettingOnWorld
local GetFriendlyNPCNameplatesSafe = api.GetFriendlyNPCNameplatesSafe
local GetNPCNameplatesSettingEffective = api.GetNPCNameplatesSettingEffective

local GetGreatVaultAutoOpenMode = api.GetGreatVaultAutoOpenMode
local GetTalentAutoOpenMode = api.GetTalentAutoOpenMode
local GetTrainerAutoLearnMode = api.GetTrainerAutoLearnMode

local UpdateMinimapButtonVisibility = api.UpdateMinimapButtonVisibility

local ShowGreatVault = api.ShowGreatVault or (ns and ns.ShowGreatVault) or nil

local function AddItemByID(id, scope)
    if not id then print("|cff00ccff[FAO]|r Please enter a valid item ID.") return end
    if type(InitSV) == "function" then InitSV() end
    if ns.items and ns.items[id] then
        print("|cff00ccff[FAO]|r Already in addon database: "..((type(GetItemNameSafe) == "function" and GetItemNameSafe(id)) or id))
        return
    end
    if ns.exclude and ns.exclude[id] then
        local name = ns.exclude[id][1] or ("ID "..id)
        local reason = ns.exclude[id][2] or "Excluded"
        print("|cff00ccff[FAO]|r Excluded: |cffffff00"..name.."|r - "..reason)
        return
    end

    local ok, why
    if type(IsProbablyOpenableCacheID) == "function" then
        ok, why = IsProbablyOpenableCacheID(id)
    end
    if ok == nil then
        print("|cff00ccff[FAO]|r Item data still loading for ID "..id..". Try again in a second.")
        return
    end
    if ok == false then
        local reason = "Not a cache"
        if why == "equippable" then reason = "Not a cache" end
        if why == "reagent" then reason = "Not a cache" end
        if why == "no_open_line" then reason = "No 'Right Click to Open' tooltip line" end
        print("|cff00ccff[FAO]|r Not added: |cffffff00"..((type(GetItemNameSafe) == "function" and GetItemNameSafe(id)) or ("ID "..id)).."|r - "..reason)
        return
    end
    if scope == "acc" then
        if fr0z3nUI_AutoOpen_Acc[id] then print("|cff00ccff[FAO]|r Already in Account whitelist: "..(((type(GetItemNameSafe) == "function" and GetItemNameSafe(id)) or id))) return end
        fr0z3nUI_AutoOpen_Acc[id] = true
        if fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.disabled then
            fr0z3nUI_AutoOpen_Settings.disabled[id] = nil
        end
        if type(ResetAccFailStreak) == "function" then
            ResetAccFailStreak(id)
        end
    else
        if fr0z3nUI_AutoOpen_Char[id] then print("|cff00ccff[FAO]|r Already in Character whitelist: "..(((type(GetItemNameSafe) == "function" and GetItemNameSafe(id)) or id))) return end
        fr0z3nUI_AutoOpen_Char[id] = true
        if fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.disabled then
            fr0z3nUI_AutoOpen_CharSettings.disabled[id] = nil
        end
    end
    local iname = (type(GetItemNameSafe) == "function" and GetItemNameSafe(id)) or tostring(id)
    print("|cff00ccff[FAO]|r Added: |cffffff00"..iname.."|r to "..(scope=="acc" and "Account" or "Character"))
end

local function CreateOptionsWindow()
    if fr0z3nUI_AutoOpenOptions then return end
    if type(InitSV) == "function" then InitSV() end
    if not frame then frame = CreateFrame("Frame") end

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
            if not exists and table and table.insert then
                table.insert(special, name)
            end
        end
    end
    local FRAME_W, FRAME_H = 520, 320
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
    f:SetBackdropColor(0,0,0,0.85)

    local itemsPanel = CreateFrame("Frame", nil, f)
    itemsPanel:SetAllPoints()
    f.itemsPanel = itemsPanel

    local togglesPanel = CreateFrame("Frame", nil, f)
    togglesPanel:SetAllPoints()
    togglesPanel:Hide()
    f.togglesPanel = togglesPanel

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -6)
    title:SetJustifyH("LEFT")
    title:SetText("|cff00ccff[FAO]|r")

    do
        local fontPath, fontSize, fontFlags = title:GetFont()
        if fontPath and fontSize then
            title:SetFont(fontPath, fontSize + 2, fontFlags)
        end
    end

    local tabBarBG = CreateFrame("Frame", nil, f, "BackdropTemplate")
    tabBarBG:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    tabBarBG:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    tabBarBG:SetHeight(26)
    tabBarBG:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        tile = true,
        tileSize = 16,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    tabBarBG:SetBackdropColor(0, 0, 0, 0.92)
    tabBarBG:SetFrameLevel((f.GetFrameLevel and f:GetFrameLevel() or 0) + 1)
    f._tabBarBG = tabBarBG

    -- Keep the title above the tab bar background.
    if title and title.SetParent and f._tabBarBG then
        title:SetParent(f._tabBarBG)
        title:ClearAllPoints()
        title:SetPoint("LEFT", f._tabBarBG, "LEFT", 8, 0)
    end

    local function SizeTabToText(btn, pad, minW)
        if not (btn and btn.GetFontString and btn.SetWidth) then return end
        local fs = btn:GetFontString()
        local w = (fs and fs.GetStringWidth and fs:GetStringWidth()) or 0
        w = (tonumber(w) or 0) + (tonumber(pad) or 18)
        if minW and w < minW then w = minW end
        btn:SetWidth(w)
    end

    local function StyleTab(btn, active)
        if not (btn and btn.GetFontString) then return end
        local fs = btn:GetFontString()
        if fs and fs.SetTextColor then
            if active then
                fs:SetTextColor(1.0, 0.82, 0.0, 1)
            else
                fs:SetTextColor(0.70, 0.70, 0.70, 1)
            end
        end
    end

    local function SelectTab(tabID)
        f.activeTab = tabID
        if f.itemsPanel then f.itemsPanel:SetShown(tabID == 1) end
        if f.togglesPanel then f.togglesPanel:SetShown(tabID == 2) end

        StyleTab(f.tab1, tabID == 1)
        StyleTab(f.tab2, tabID == 2)
    end
    f.SelectTab = SelectTab

    local tab1 = CreateFrame("Button", "$parentTab1", f, "UIPanelButtonTemplate")
    tab1:SetID(1)
    tab1:SetText("AutoOpen")
    tab1:SetPoint("LEFT", title, "RIGHT", 10, 0)
    tab1:SetScript("OnClick", function(self) SelectTab(self:GetID()) end)
    tab1:SetHeight(22)
    SizeTabToText(tab1, 18, 70)
    f.tab1 = tab1

    local tab2 = CreateFrame("Button", "$parentTab2", f, "UIPanelButtonTemplate")
    tab2:SetID(2)
    tab2:SetText("Toggles")
    tab2:SetPoint("LEFT", tab1, "RIGHT", -6, 0)
    tab2:SetScript("OnClick", function(self) SelectTab(self:GetID()) end)
    tab2:SetHeight(22)
    SizeTabToText(tab2, 18, 70)
    f.tab2 = tab2

    StyleTab(tab1, true)
    StyleTab(tab2, false)

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
        if f then
            f._captureLinkUntil = (GetTime and GetTime() or 0) + 2
        end
    end)
    edit:SetScript("OnEditFocusLost", function()
        UpdatePlaceholder()
    end)

    local function TrySetItemIDFromLink(text)
        if not (f and f.edit and type(text) == "string") then
            return false
        end
        local now = GetTime and GetTime() or 0
        local focused = f.edit.HasFocus and f.edit:HasFocus() or false
        local capture = (f._captureLinkUntil and now <= f._captureLinkUntil) or false
        if not (focused or capture) then
            return false
        end

        local id = tonumber(text:match("item:(%d+):")) or tonumber(text:match("item:(%d+)"))
        if not id then
            return false
        end

        f._forceValidate = true
        f.edit:SetText(tostring(id))
        if f.edit.HighlightText then f.edit:HighlightText() end
        f._captureLinkUntil = nil
        return true
    end

    if not frame._faoHookedInsertLink then
        frame._faoHookedInsertLink = true

        if type(hooksecurefunc) == "function" and _G and type(rawget(_G, "ChatEdit_InsertLink")) == "function" then
            hooksecurefunc("ChatEdit_InsertLink", function(text)
                TrySetItemIDFromLink(text)
            end)
        end

        if type(hooksecurefunc) == "function" and _G and type(rawget(_G, "HandleModifiedItemClick")) == "function" then
            hooksecurefunc("HandleModifiedItemClick", function(link)
                TrySetItemIDFromLink(link)
            end)
        end
    end

    edit:SetScript("OnReceiveDrag", function()
        if not (GetCursorInfo and ClearCursor) then
            return
        end
        local kind, id = GetCursorInfo()
        if kind == "item" and id then
            f._forceValidate = true
            f.edit:SetText(tostring(id))
            if f.edit.HighlightText then f.edit:HighlightText() end
            ClearCursor()
        end
    end)

    edit:SetScript("OnMouseUp", function()
        if not (GetCursorInfo and ClearCursor) then
            return
        end
        local kind, id = GetCursorInfo()
        if kind == "item" and id then
            f._forceValidate = true
            f.edit:SetText(tostring(id))
            if f.edit.HighlightText then f.edit:HighlightText() end
            ClearCursor()
        end
    end)

    local textArea = CreateFrame("Frame", nil, itemsPanel)
    textArea:SetPoint("TOP", edit, "BOTTOM", 0, -2)
    textArea:SetPoint("LEFT", itemsPanel, "LEFT", 16, 0)
    textArea:SetPoint("RIGHT", itemsPanel, "RIGHT", -16, 0)
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

    local actionRow = CreateFrame("Frame", nil, itemsPanel)
    actionRow:SetSize(1, 22)
    actionRow:SetPoint("BOTTOM", itemsPanel, "BOTTOM", 0, 42)

    local function LayoutActionRow()
        if not (actionRow and itemsPanel and itemsPanel.GetHeight) then
            return
        end

        local h = itemsPanel:GetHeight() or 0
        if h <= 0 then
            return
        end

        local y = math.floor(h * 0.42)
        local minY = 70
        local maxY = math.max(minY, math.floor(h - 120))
        if y < minY then y = minY end
        if y > maxY then y = maxY end

        actionRow:ClearAllPoints()
        actionRow:SetPoint("BOTTOM", itemsPanel, "BOTTOM", 0, y)
    end

    actionRow:SetScript("OnShow", LayoutActionRow)
    if itemsPanel.HookScript then
        itemsPanel:HookScript("OnSizeChanged", LayoutActionRow)
    end

    textArea:SetPoint("BOTTOM", actionRow, "TOP", 0, 10)

    local ACTION_W, ACTION_H = 90, 22
    local BTN_W, BTN_H = 125, 22
    local BTN_GAP = 14

    local btnReloadUI = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnReloadUI:SetSize(ACTION_W, ACTION_H)
    btnReloadUI:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
    btnReloadUI:SetText("Reload UI")
    btnReloadUI:SetScript("OnClick", function()
        if type(ReloadUI) == "function" then
            ReloadUI()
        end
    end)
    f.btnReloadUI = btnReloadUI

    local cooldownRow = CreateFrame("Frame", nil, itemsPanel)
    cooldownRow:SetSize(1, ACTION_H)
    cooldownRow:SetPoint("BOTTOM", itemsPanel, "BOTTOM", 0, 12)

    local COOLDOWN_GAP_LABEL = 4
    local COOLDOWN_GAP_SUFFIX = 2

    local cooldownLabel = cooldownRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cooldownLabel:SetPoint("LEFT", cooldownRow, "LEFT", 0, 0)
    cooldownLabel:SetJustifyH("LEFT")
    cooldownLabel:SetText("Opening Cooldown:")

    local cooldownBox = CreateFrame("EditBox", nil, cooldownRow)
    cooldownBox:SetSize(38, ACTION_H)
    cooldownBox:SetPoint("LEFT", cooldownLabel, "RIGHT", COOLDOWN_GAP_LABEL, 0)
    cooldownBox:SetAutoFocus(false)
    cooldownBox:SetTextInsets(0, 0, 0, 0)
    cooldownBox:SetJustifyH("CENTER")
    if cooldownBox.SetJustifyV then cooldownBox:SetJustifyV("MIDDLE") end
    if cooldownBox.GetFont and cooldownBox.SetFont then
        local fontPath, _, fontFlags = cooldownLabel:GetFont()
        if fontPath then cooldownBox:SetFont(fontPath, 12, fontFlags) end
    end

    local cooldownSuffix = cooldownRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cooldownSuffix:SetPoint("LEFT", cooldownBox, "RIGHT", COOLDOWN_GAP_SUFFIX, 0)
    cooldownSuffix:SetText("s")
    cooldownSuffix:SetTextColor(1, 1, 1, 1)

    local function LayoutCooldownRow()
        if not (cooldownRow and cooldownLabel and cooldownBox and cooldownSuffix) then
            return
        end
        local lw = cooldownLabel.GetStringWidth and cooldownLabel:GetStringWidth() or 0
        local sw = cooldownSuffix.GetStringWidth and cooldownSuffix:GetStringWidth() or 0
        local bw = cooldownBox.GetWidth and cooldownBox:GetWidth() or 0
        local total = math.ceil((lw or 0) + COOLDOWN_GAP_LABEL + (bw or 0) + COOLDOWN_GAP_SUFFIX + (sw or 0))
        if total < 60 then total = 60 end
        cooldownRow:SetWidth(total)
    end
    cooldownRow:SetScript("OnShow", LayoutCooldownRow)
    LayoutCooldownRow()

    f.cooldownLabel = cooldownLabel
    f.cooldownBox = cooldownBox

    local function UpdateCooldownControls()
        if type(InitSV) == "function" then InitSV() end
        local current = (type(GetOpenCooldown) == "function") and GetOpenCooldown() or 0
        if f.cooldownBox then
            f.cooldownBox._setting = true
            f.cooldownBox:SetText(string.format("%.1f", current))
            if f.cooldownBox.SetCursorPosition then f.cooldownBox:SetCursorPosition(0) end
            f.cooldownBox._setting = false
        end
    end

    local function ApplyCooldownFromText(raw)
        if type(InitSV) == "function" then InitSV() end
        local s = tostring(raw or "")
        s = s:gsub("[^0-9.]", "")
        local firstDot = s:find("%.")
        if firstDot then
            s = s:sub(1, firstDot) .. s:sub(firstDot + 1):gsub("%.", "")
        end
        local n = tonumber(s)
        if not n then
            UpdateCooldownControls()
            return
        end
        local rounded = math.floor(n * 10 + 0.5) / 10
        local newCd = (type(NormalizeCooldown) == "function") and NormalizeCooldown(rounded) or rounded
        if fr0z3nUI_AutoOpen_Settings then
            fr0z3nUI_AutoOpen_Settings.cooldown = newCd
        end
        UpdateCooldownControls()
    end

    cooldownBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        UpdateCooldownControls()
    end)
    cooldownBox:SetScript("OnEnterPressed", function(self)
        ApplyCooldownFromText(self:GetText())
        self:ClearFocus()
    end)
    cooldownBox:SetScript("OnEditFocusLost", function(self)
        if self._setting then return end
        ApplyCooldownFromText(self:GetText())
    end)
    cooldownBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput or self._setting then return end
        local t = self:GetText() or ""
        local s = t:gsub("[^0-9.]", "")
        local firstDot = s:find("%.")
        if firstDot then
            s = s:sub(1, firstDot) .. s:sub(firstDot + 1):gsub("%.", "")
        end
        if s ~= t then
            self._setting = true
            self:SetText(s)
            if self.SetCursorPosition then self:SetCursorPosition(#s) end
            self._setting = false
        end
    end)

    local ADD_ROW_X = (BTN_W / 2) + (BTN_GAP / 2)

    local btnChar = CreateFrame("Button", nil, itemsPanel, "UIPanelButtonTemplate")
    btnChar:SetSize(BTN_W, BTN_H)
    btnChar:ClearAllPoints()
    btnChar:SetPoint("CENTER", actionRow, "CENTER", -ADD_ROW_X, 0)
    btnChar:SetText("Character")
    if btnChar.RegisterForClicks then btnChar:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    btnChar:Disable()
    f.btnChar = btnChar

    local btnAcc = CreateFrame("Button", nil, itemsPanel, "UIPanelButtonTemplate")
    btnAcc:SetSize(BTN_W, BTN_H)
    btnAcc:ClearAllPoints()
    btnAcc:SetPoint("CENTER", actionRow, "CENTER", ADD_ROW_X, 0)
    btnAcc:SetText("Account")
    if btnAcc.RegisterForClicks then btnAcc:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
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

    local function SetButtonColor(btn, label, state)
        if not btn then return end
        if state == "inactive" then
            btn:SetText("|cffffff00" .. label .. "|r")
            return
        end
        if state == "active" then
            btn:SetText("|cff00ff00" .. label .. "|r")
            return
        end
        if state == "disabled" then
            btn:SetText("|cffff9900" .. label .. "|r")
            return
        end
        btn:SetText(label)
    end

    local function SetDynamicTip(btn, getLines)
        if not (btn and btn.SetScript and getLines) then return end
        btn:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            local t0, l1, l2, l3 = getLines()
            if not t0 then return end
            GameTooltip:SetOwner(self, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("TOP", self, "BOTTOM", 0, -6)
            GameTooltip:SetText(t0)
            if l1 then GameTooltip:AddLine(l1, 1, 1, 1, true) end
            if l2 then GameTooltip:AddLine(l2, 1, 1, 1, true) end
            if l3 then GameTooltip:AddLine(l3, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end

    local function UpdateScopeButtons(id)
        if type(InitSV) == "function" then InitSV() end
        if not id then
            if f.btnChar then f.btnChar:Disable() end
            if f.btnAcc then f.btnAcc:Disable() end
            return
        end

        local inDB = (ns and ns.items and ns.items[id]) and true or false
        local inAcc = (fr0z3nUI_AutoOpen_Acc and fr0z3nUI_AutoOpen_Acc[id]) and true or false
        local inChar = (fr0z3nUI_AutoOpen_Char and fr0z3nUI_AutoOpen_Char[id]) and true or false

        local accRuleExists = inDB or inAcc
        local charRuleExists = inDB or inChar

        local isDisabledAcc = (fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.disabled and fr0z3nUI_AutoOpen_Settings.disabled[id]) and true or false
        local isDisabledChar = (fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.disabled and fr0z3nUI_AutoOpen_CharSettings.disabled[id]) and true or false

        if f.btnAcc then
            f.btnAcc:Enable()
            local aState
            if not accRuleExists then aState = "inactive" else aState = isDisabledAcc and "disabled" or "active" end
            SetButtonColor(f.btnAcc, "Account", aState)
            f.btnAcc:SetScript("OnClick", function(_, mouseButton)
                if type(InitSV) == "function" then InitSV() end
                if not accRuleExists then
                    local id2 = f.validID or tonumber(edit:GetText() or "")
                    AddItemByID(id2, "acc")
                    DoValidate()
                    return
                end

                if mouseButton == "RightButton" then
                    if inAcc then
                        fr0z3nUI_AutoOpen_Acc[id] = nil
                        if fr0z3nUI_AutoOpen_Settings and fr0z3nUI_AutoOpen_Settings.disabled then
                            fr0z3nUI_AutoOpen_Settings.disabled[id] = nil
                        end
                        print("|cff00ccff[FAO]|r Removed from Account whitelist: '" .. (((type(GetItemNameSafe) == "function" and GetItemNameSafe(id)) or id)) .. "'")
                        DoValidate()
                        return
                    end
                    print("|cff00ccff[FAO]|r Built-in items can't be removed. Left-click to disable instead.")
                    return
                end

                local t = fr0z3nUI_AutoOpen_Settings.disabled
                if t[id] then
                    t[id] = nil
                    if type(ResetAccFailStreak) == "function" then
                        ResetAccFailStreak(id)
                    end
                    print("|cff00ccff[FAO]|r '"..(((type(GetItemNameSafe) == "function" and GetItemNameSafe(id)) or id)).."' will now open on Account")
                else
                    t[id] = true
                    print("|cff00ccff[FAO]|r '"..(((type(GetItemNameSafe) == "function" and GetItemNameSafe(id)) or id)).."' will NOT open on Account")
                end
                UpdateScopeButtons(id)
            end)

            SetDynamicTip(f.btnAcc, function()
                local cur = f.validID or tonumber(edit:GetText() or "")
                if not cur then return "Account", "Enter an ItemID first." end

                if not accRuleExists then
                    return "Account (Inactive)", "Left-click: add Account whitelist"
                end
                if isDisabledAcc then
                    return "Account (Disabled)", "Left-click: re-enable auto-open on Account", (inAcc and "Right-click: remove from Account whitelist" or nil)
                end
                return "Account (Active)", "Left-click: disable auto-open on Account", (inAcc and "Right-click: remove from Account whitelist" or "(Built-in item)")
            end)
        end

        if f.btnChar then
            f.btnChar:Enable()
            local cState
            if not charRuleExists then cState = "inactive" else cState = isDisabledChar and "disabled" or "active" end
            SetButtonColor(f.btnChar, "Character", cState)
            f.btnChar:SetScript("OnClick", function(_, mouseButton)
                if type(InitSV) == "function" then InitSV() end
                if not charRuleExists then
                    local id2 = f.validID or tonumber(edit:GetText() or "")
                    AddItemByID(id2, "char")
                    DoValidate()
                    return
                end

                if mouseButton == "RightButton" then
                    if inChar then
                        fr0z3nUI_AutoOpen_Char[id] = nil
                        if fr0z3nUI_AutoOpen_CharSettings and fr0z3nUI_AutoOpen_CharSettings.disabled then
                            fr0z3nUI_AutoOpen_CharSettings.disabled[id] = nil
                        end
                        print("|cff00ccff[FAO]|r Removed from Character whitelist: '" .. (((type(GetItemNameSafe) == "function" and GetItemNameSafe(id)) or id)) .. "'")
                        DoValidate()
                        return
                    end
                    print("|cff00ccff[FAO]|r Built-in items can't be removed. Left-click to disable instead.")
                    return
                end

                local t = fr0z3nUI_AutoOpen_CharSettings.disabled
                if t[id] then
                    t[id] = nil
                    print("|cff00ccff[FAO]|r '"..(((type(GetItemNameSafe) == "function" and GetItemNameSafe(id)) or id)).."' will now open on Character")
                else
                    t[id] = true
                    print("|cff00ccff[FAO]|r '"..(((type(GetItemNameSafe) == "function" and GetItemNameSafe(id)) or id)).."' will NOT open on Character")
                end
                UpdateScopeButtons(id)
            end)

            SetDynamicTip(f.btnChar, function()
                local cur = f.validID or tonumber(edit:GetText() or "")
                if not cur then return "Character", "Enter an ItemID first." end

                if not charRuleExists then
                    return "Character (Inactive)", "Left-click: add Character whitelist"
                end
                if isDisabledChar then
                    return "Character (Disabled)", "Left-click: re-enable auto-open on this character", (inChar and "Right-click: remove from Character whitelist" or nil)
                end
                return "Character (Active)", "Left-click: disable auto-open on this character", (inChar and "Right-click: remove from Character whitelist" or "(Built-in item)")
            end)
        end
    end

    local function ResetAllSV()
        if not (IsShiftKeyDown and IsShiftKeyDown()) then
            print("|cff00ccff[FAO]|r Hold |cffffff00SHIFT|r and click to reset all saved variables.")
            return
        end

        if type(ResetAllSavedVariables) == "function" then
            ResetAllSavedVariables()
        end

        if f.edit then f.edit:SetText("") end
        if f.nameLabel then f.nameLabel:SetText("") end
        if f.reasonLabel then f.reasonLabel:SetText("") end
        f.validID = nil
        if f.btnChar then f.btnChar:Disable() end
        if f.btnAcc then f.btnAcc:Disable() end

        if f._togglesAPI and f._togglesAPI.UpdateAll then
            f._togglesAPI.UpdateAll()
        end
        UpdateCooldownControls()
        if f.UpdateInputPlaceholder then f.UpdateInputPlaceholder() end

        print("|cff00ccff[FAO]|r SavedVariables reset. (Optional: /reload)")
    end

    if ns and ns.Toggles and type(ns.Toggles.Build) == "function" then
        f._togglesAPI = ns.Toggles.Build({
            optionsFrame = f,
            togglesPanel = togglesPanel,
            itemsPanel = itemsPanel,
            InitSV = InitSV,
            engineFrame = frame,
            BTN_W = BTN_W,
            BTN_H = BTN_H,
            ACTION_W = ACTION_W,
            ACTION_H = ACTION_H,
            FRAME_W = FRAME_W,
            SetAutoLootDefaultSafe = SetAutoLootDefaultSafe,
            GetAutoLootEnforceMode = GetAutoLootEnforceMode,
            ApplyNPCNameplatesSettingOnWorld = ApplyNPCNameplatesSettingOnWorld,
            GetFriendlyNPCNameplatesSafe = GetFriendlyNPCNameplatesSafe,
            GetNPCNameplatesSettingEffective = GetNPCNameplatesSettingEffective,
            GetGreatVaultAutoOpenMode = GetGreatVaultAutoOpenMode,
            ShowGreatVault = ShowGreatVault,
            GetTalentAutoOpenMode = GetTalentAutoOpenMode,
            GetTrainerAutoLearnMode = GetTrainerAutoLearnMode,
            UpdateMinimapButtonVisibility = UpdateMinimapButtonVisibility,
            ResetAllSV = ResetAllSV,
        })
    else
        f._togglesAPI = nil
    end

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

        local req, lockedName
        if type(GetRequiredLevelForID) == "function" then
            req, lockedName = GetRequiredLevelForID(id)
        end
        if req and UnitLevel and UnitLevel("player") < req then
            local displayName = lockedName or ((type(GetItemNameSafe) == "function" and GetItemNameSafe(id)) or ("ID "..id))
            if f.nameLabel then f.nameLabel:SetText("|cffffff00"..displayName.."|r") end
            if f.reasonLabel then f.reasonLabel:SetText("|cffff9900Requires level "..req.." (will not auto-open yet)|r") end
            f.validID = id
            UpdateScopeButtons(id)
            return
        end

        local iname = (type(GetItemNameSafe) == "function" and GetItemNameSafe(id)) or nil
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
            local ok, why
            if type(IsProbablyOpenableCacheID) == "function" then
                ok, why = IsProbablyOpenableCacheID(id)
            end

            if ok == nil and not alreadyWhitelisted then
                if f.reasonLabel then f.reasonLabel:SetText("|cffaaaaaaLoading item data...|r") end
                f.validID = nil
                if f.btnChar then f.btnChar:Disable() end
                if f.btnAcc then f.btnAcc:Disable() end
                return
            end

            if ok == false and not alreadyWhitelisted then
                local reason = "Not a cache"
                if why == "equippable" then reason = "Not a cache" end
                if why == "reagent" then reason = "Not a cache" end
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
            local cleaned = txt:gsub("%D", "")
            if txt ~= cleaned then
                self:SetText(cleaned)
                if self.SetCursorPosition then self:SetCursorPosition(#cleaned) end
                txt = cleaned
            end
        end

        if fr0z3nUI_AutoOpenOptions then
            if fr0z3nUI_AutoOpenOptions.UpdateInputPlaceholder then
                fr0z3nUI_AutoOpenOptions.UpdateInputPlaceholder()
            end

            fr0z3nUI_AutoOpenOptions.validID = nil
            if fr0z3nUI_AutoOpenOptions.nameLabel then fr0z3nUI_AutoOpenOptions.nameLabel:SetText("") end
            if fr0z3nUI_AutoOpenOptions.reasonLabel then fr0z3nUI_AutoOpenOptions.reasonLabel:SetText("") end
            if fr0z3nUI_AutoOpenOptions.btnChar then fr0z3nUI_AutoOpenOptions.btnChar:Disable() end
            if fr0z3nUI_AutoOpenOptions.btnAcc then fr0z3nUI_AutoOpenOptions.btnAcc:Disable() end

            local forceValidate = fr0z3nUI_AutoOpenOptions._forceValidate
            fr0z3nUI_AutoOpenOptions._forceValidate = nil

            if userInput or forceValidate then
                if fr0z3nUI_AutoOpenOptions._validateTimer then fr0z3nUI_AutoOpenOptions._validateTimer:Cancel() end
                local delay = userInput and 0.7 or 0.05
                fr0z3nUI_AutoOpenOptions._validateTimer = C_Timer.NewTimer(delay, DoValidate)
            end
        end
    end)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    f:SetScript("OnShow", function()
        if type(InitSV) == "function" then InitSV() end
        if f._togglesAPI and f._togglesAPI.UpdateAll then
            f._togglesAPI.UpdateAll()
        end
        UpdateCooldownControls()

        if f.UpdateInputPlaceholder then f.UpdateInputPlaceholder() end

        local tabID = tonumber(f.activeTab) or 1
        if tabID > 3 then tabID = tabID - 1 end
        if tabID < 1 then tabID = 1 end
        if tabID > 4 then tabID = 4 end
        f.activeTab = tabID
        SelectTab(tabID)
    end)

    if f._togglesAPI and f._togglesAPI.UpdateAll then
        f._togglesAPI.UpdateAll()
    end
    UpdateCooldownControls()
    SelectTab(1)
    f:Hide()
end

function ns.UI.CreateOptionsWindow()
    CreateOptionsWindow()
end

function ns.UI.ToggleWindow(text)
    CreateOptionsWindow()

    local f = fr0z3nUI_AutoOpenOptions
    if not f then return end

    local idText = text and tostring(text):match("(%d+)") or nil

    if not f:IsShown() then
        f:Show()
    else
        if not idText then
            f:Hide()
            return
        end
    end

    if idText and f.edit then
        -- If /fao <itemid> is used, always jump to the Items/AutoOpen tab.
        if f.SelectTab then
            f.activeTab = 1
            f.SelectTab(1)
        end
        f.edit:SetText(idText)
        if f.edit.SetCursorPosition then f.edit:SetCursorPosition(#idText) end
        if f.edit.SetFocus then f.edit:SetFocus() end
    elseif f.edit and f.edit.SetFocus then
        f.edit:SetFocus()
    end
end
