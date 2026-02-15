local _, ns = ...

-- Macros tab UI (split out of Hearth module).

local function SafeLower(s)
    return tostring(s or ""):lower()
end

local function SetButtonTooltip(btn, tooltipText)
    if not (btn and tooltipText) then return end
    btn:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        local tt = tooltipText
        if type(tt) == "function" then
            tt = tt(self)
        end
        if not tt or tt == "" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local first = true
        for line in tostring(tt):gmatch("[^\n]+") do
            if first then
                GameTooltip:SetText(line, 1, 1, 1)
                first = false
            else
                GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true)
            end
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end

local function FitFontStringToWidth(fs, text, maxWidth, targetHeight)
    if not (fs and fs.SetText and fs.GetFont and fs.SetFont) then
        return
    end

    local wantedText = tostring(text or "")
    fs:SetText(wantedText)

    local fontPath, fontSize, flags = fs:GetFont()
    if not fontPath then
        return
    end

    if not fs._faoBaseFont then
        fs._faoBaseFont = { path = fontPath, size = tonumber(fontSize) or 14, flags = flags }
    end

    local base = fs._faoBaseFont
    if base and base.path then
        fs:SetFont(base.path, base.size or 14, base.flags)
        fontPath, fontSize, flags = fs:GetFont()
    end

    local w = tonumber(maxWidth) or 0
    if w <= 0 and fs.GetWidth then
        w = tonumber(fs:GetWidth()) or 0
    end
    if w <= 0 then
        w = 320
    end

    local startSize = tonumber(fontSize) or math.floor(tonumber(targetHeight) or 14)
    startSize = math.floor(startSize)
    if startSize < 10 then startSize = 10 end
    if startSize > 24 then startSize = 24 end

    local minSize = 6
    for s = startSize, minSize, -1 do
        fs:SetFont(fontPath, s, flags)
        -- Some clients only update width reliably after re-setting text.
        fs:SetText(wantedText)
        local curW = 0
        if fs.GetUnboundedStringWidth then
            curW = tonumber(fs:GetUnboundedStringWidth()) or 0
        else
            curW = tonumber(fs:GetStringWidth()) or 0
        end
        if curW <= w then
            break
        end
    end
end

local function GetPanelWidth(parent)
    local w = parent and parent.GetWidth and parent:GetWidth() or 0
    if not w or w <= 0 then
        w = 520
    end
    return w
end

local function BuildMacrosPanel(parent)
    if not parent or parent._faoMacrosBuilt then
        return
    end
    parent._faoMacrosBuilt = true

    if not (ns and ns.Macros) then
        return
    end

    local M = ns.Macros
    local H = (ns and ns.Hearth) or {}

    local BTN_W, BTN_H = 95, 23 -- ~5% bigger than 90x22 (Reload UI)
    local BTN_GAP = BTN_H

    -- Forward declarations (used by Optional/Hearth helpers below)
    local btnHS06, btnHS07, btnHS11, btnHS78
    local btnInstanceIO, btnInstanceReset, btnRez, btnRezCombat
    local btnScriptErrors
    local hearthPopout, btnCreateHearthMacro

    -- Optional macro additions (left popout)
    local btnOptional = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btnOptional:SetSize(80, 20)
    btnOptional:SetText("Optional")
    btnOptional:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 12, 12)

    local optPopout = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    optPopout:SetWidth(260)
    optPopout:SetPoint("TOPRIGHT", parent, "TOPLEFT", 0, 0)
    optPopout:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", 0, 0)
    optPopout:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        tile = true, tileSize = 16,
    })
    optPopout:SetBackdropColor(0, 0, 0, 0.85)
    optPopout:Hide()

    local optTitle = optPopout:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    optTitle:SetPoint("TOP", optPopout, "TOP", 0, -10)
    optTitle:SetText("Optional")

    local nameBox = CreateFrame("EditBox", nil, optPopout, "InputBoxTemplate")
    nameBox:SetSize(220, 18)
    nameBox:SetPoint("TOP", optPopout, "TOP", 0, -34)
    nameBox:SetAutoFocus(false)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local textLabel = optPopout:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    textLabel:SetPoint("TOPLEFT", optPopout, "TOPLEFT", 12, -58)
    textLabel:SetText("Text (one line per macro line):")

    local textScroll = CreateFrame("ScrollFrame", nil, optPopout, "UIPanelScrollFrameTemplate")
    textScroll:SetPoint("TOPLEFT", textLabel, "BOTTOMLEFT", -2, -6)
    textScroll:SetPoint("TOPRIGHT", optPopout, "TOPRIGHT", -28, -78)
    textScroll:SetHeight(70)

    local textBox = CreateFrame("EditBox", nil, textScroll, "InputBoxTemplate")
    textBox:SetMultiLine(true)
    textBox:SetAutoFocus(false)
    textBox:SetFontObject("ChatFontNormal")
    textBox:SetWidth(220)
    textBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    textBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    textScroll:SetScrollChild(textBox)

    local btnAddOptional = CreateFrame("Button", nil, optPopout, "UIPanelButtonTemplate")
    btnAddOptional:SetSize(60, 18)
    btnAddOptional:SetText("Add")
    btnAddOptional:SetPoint("TOP", textScroll, "BOTTOM", 0, -10)

    local listScroll = CreateFrame("ScrollFrame", nil, optPopout, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", btnAddOptional, "BOTTOMLEFT", -86, -12)
    listScroll:SetPoint("TOPRIGHT", optPopout, "TOPRIGHT", -28, -188)
    listScroll:SetPoint("BOTTOMRIGHT", optPopout, "BOTTOMRIGHT", -28, 12)

    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(1, 1)
    listScroll:SetScrollChild(listChild)

    SetButtonTooltip(btnOptional, "Optional\n\nToggle optional macro lines")
    SetButtonTooltip(nameBox, "Name\n\nExample: Safari Hat")
    SetButtonTooltip(textBox, "Text\n\nThese lines will be inserted into macros when this option is selected.")
    SetButtonTooltip(btnAddOptional, "Add\n\nAdds/updates the entry by name.")

    local optionalListButtons = {}

    local function MacroWouldFit(rawBody)
        if type(rawBody) ~= "string" then return true end
        local max = tonumber(M.MAX_MACRO_CHARS) or 255
        local body = rawBody
        if type(M.ApplyOptionalLines) == "function" then
            body = M.ApplyOptionalLines(body)
        end
        return #tostring(body or "") <= max
    end

    local function MacroUsesItem(rawBody)
        if type(rawBody) ~= "string" then return false end
        local s = rawBody:gsub("\r\n", "\n"):gsub("\r", "\n")
        return s:match("/use[^\n]*item:%d+") ~= nil
    end

    local function UpdateMacroCreateButtonsEnabled()
        -- Disable any macro creation buttons that would exceed the macro length limit.
        -- If '#showtooltip (25)' is selected, also disable any macros that do not '/use item:<id>'.
        local showTooltipSelected = (type(M.IsOptionalEntrySelected) == "function") and M.IsOptionalEntrySelected("#showtooltip (25)") or false

        local rawHS06 = (M.MacroBody_HS_Garrison and M.MacroBody_HS_Garrison()) or ""
        if btnHS06 then btnHS06:SetEnabled(MacroWouldFit(rawHS06) and (not showTooltipSelected or MacroUsesItem(rawHS06))) end

        local rawHS07 = (M.MacroBody_HS_Dalaran and M.MacroBody_HS_Dalaran()) or ""
        if btnHS07 then btnHS07:SetEnabled(MacroWouldFit(rawHS07) and (not showTooltipSelected or MacroUsesItem(rawHS07))) end

        local rawHS11 = (M.MacroBody_HS_Dornogal and M.MacroBody_HS_Dornogal()) or ""
        if btnHS11 then btnHS11:SetEnabled(MacroWouldFit(rawHS11) and (not showTooltipSelected or MacroUsesItem(rawHS11))) end

        local rawHS78 = (M.MacroBody_HS_Whistle and M.MacroBody_HS_Whistle()) or ""
        if btnHS78 then btnHS78:SetEnabled(MacroWouldFit(rawHS78) and (not showTooltipSelected or MacroUsesItem(rawHS78))) end

        local rawIO = (M.MacroBody_InstanceIO and M.MacroBody_InstanceIO()) or ""
        if btnInstanceIO then btnInstanceIO:SetEnabled(MacroWouldFit(rawIO) and (not showTooltipSelected or MacroUsesItem(rawIO))) end

        local rawReset = (M.MacroBody_InstanceReset and M.MacroBody_InstanceReset()) or ""
        if btnInstanceReset then btnInstanceReset:SetEnabled(MacroWouldFit(rawReset) and (not showTooltipSelected or MacroUsesItem(rawReset))) end

        local rawRez = (M.MacroBody_Rez and M.MacroBody_Rez()) or ""
        if btnRez then btnRez:SetEnabled(MacroWouldFit(rawRez) and (not showTooltipSelected or MacroUsesItem(rawRez))) end

        local rawRezCombat = (M.MacroBody_RezCombat and M.MacroBody_RezCombat()) or ""
        if btnRezCombat then btnRezCombat:SetEnabled(MacroWouldFit(rawRezCombat) and (not showTooltipSelected or MacroUsesItem(rawRezCombat))) end

        local rawErrors = (M.MacroBody_ScriptErrors and M.MacroBody_ScriptErrors()) or ""
        if btnScriptErrors then btnScriptErrors:SetEnabled(MacroWouldFit(rawErrors) and (not showTooltipSelected or MacroUsesItem(rawErrors))) end

        if hearthPopout and hearthPopout:IsShown() and btnCreateHearthMacro and type(H.BuildMacroText) == "function" and type(H.EnsureInit) == "function" then
            local db2 = H.EnsureInit()
            local raw = H.BuildMacroText(db2)
            local ok = MacroWouldFit(raw) and (not showTooltipSelected or MacroUsesItem(raw))
            btnCreateHearthMacro:SetEnabled(ok)
        end
    end

    local function RebuildOptionalList()
        if type(M.GetOptionalEntries) ~= "function" then
            return
        end

        local entries = M.GetOptionalEntries() or {}
        local rowH = 18

        local w = listScroll.GetWidth and listScroll:GetWidth() or 0
        if w and w > 0 and listChild.SetWidth then
            listChild:SetWidth(w)
        end

        local y = 0
        for i = 1, #entries do
            local e = entries[i]
            local name = type(e) == "table" and e.name or nil
            if name and name ~= "" then
                local b = optionalListButtons[i]
                if not b then
                    b = CreateFrame("Button", nil, listChild, "UIPanelButtonTemplate")
                    b:SetHeight(rowH)
                    optionalListButtons[i] = b
                end

                b:Show()
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -y)
                b:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -y)
                b:SetText(tostring(name))

                local selected = (type(M.IsOptionalEntrySelected) == "function") and M.IsOptionalEntrySelected(name) or false
                if selected then b:LockHighlight() else b:UnlockHighlight() end

                b:SetScript("OnClick", function()
                    if type(M.ToggleOptionalEntry) == "function" then
                        M.ToggleOptionalEntry(name)
                    end
                    RebuildOptionalList()
                    UpdateMacroCreateButtonsEnabled()
                end)

                y = y + rowH + 2
            end
        end

        for i = #entries + 1, #optionalListButtons do
            local b = optionalListButtons[i]
            if b and b.Hide then b:Hide() end
        end

        listChild:SetHeight(math.max(1, y))
    end

    btnAddOptional:SetScript("OnClick", function()
        if type(M.AddOrUpdateOptionalEntry) ~= "function" then
            return
        end

        local name = tostring(nameBox:GetText() or "")
        local text = tostring(textBox:GetText() or "")
        local ok, why = M.AddOrUpdateOptionalEntry(name, text)
        if not ok then
            M.Print(why or "Could not add")
            return
        end

        nameBox:SetText("")
        textBox:SetText("")
        nameBox:ClearFocus()
        textBox:ClearFocus()

        RebuildOptionalList()
        UpdateMacroCreateButtonsEnabled()
    end)

    optPopout:SetScript("OnShow", function()
        RebuildOptionalList()
        UpdateMacroCreateButtonsEnabled()
    end)
    btnOptional:SetScript("OnClick", function()
        if optPopout:IsShown() then optPopout:Hide() else optPopout:Show() end
    end)

    -- Macro scope (title-like control)
    local macroScopeBtn = CreateFrame("Button", nil, parent)
    macroScopeBtn:SetHeight(28)
    macroScopeBtn:SetPoint("TOP", 0, -56)
    macroScopeBtn:SetPoint("LEFT", parent, "LEFT", 16, 0)
    macroScopeBtn:SetPoint("RIGHT", parent, "RIGHT", -16, 0)

    local macroScopeText = macroScopeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    macroScopeText:SetAllPoints(macroScopeBtn)
    macroScopeText:SetJustifyH("CENTER")

    do
        local fontPath, fontSize, flags = macroScopeText:GetFont()
        if fontPath and fontSize then
            macroScopeText:SetFont(fontPath, fontSize + 2, flags)
        end
    end

    SetButtonTooltip(macroScopeBtn, function()
        local perChar = M.GetMacroPerCharSetting()
        local current = perChar and "CHARACTER" or "ACCOUNT"
        local nextScope = perChar and "ACCOUNT" or "CHARACTER"
        local what = perChar and "character-only" or "account-wide"
        return "Macro Creation Scope\n\nCurrent: " .. current .. "\nCreates/updates " .. what .. " macros.\n\nSwitches to: " .. nextScope
    end)

    local function UpdateMacroScopeUI()
        local perChar = M.GetMacroPerCharSetting()
        if perChar then
            macroScopeText:SetText("MACRO SCOPE: CHARACTER")
        else
            macroScopeText:SetText("MACRO SCOPE: ACCOUNT")
        end
    end

    macroScopeBtn:SetScript("OnClick", function()
        M.SetMacroPerCharSetting(not M.GetMacroPerCharSetting())
        UpdateMacroScopeUI()
    end)

    macroScopeBtn:SetScript("OnShow", UpdateMacroScopeUI)

    -- Helpers for macro buttons
    local function MakeMacroButton(text, bodyFn, tooltipText, macroNameOverride, perCharacter)
        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        btn:SetSize(BTN_W, BTN_H)
        btn:SetText(text)
        if tooltipText and tooltipText ~= "" then
            SetButtonTooltip(btn, tooltipText)
        end
        btn:SetScript("OnClick", function()
            local macroName = tostring(macroNameOverride or text)
            local body = bodyFn and bodyFn() or ""
            M.CreateOrUpdateNamedMacro(macroName, body, perCharacter)
        end)
        return btn
    end

    -- Macro buttons (layout defined later)
    btnHS06 = MakeMacroButton("HS 06 Garrison", M.MacroBody_HS_Garrison)
    btnHS07 = MakeMacroButton("HS 07 Dalaran", M.MacroBody_HS_Dalaran)
    btnHS11 = MakeMacroButton("HS 11 Dornogal", M.MacroBody_HS_Dornogal)
    btnHS78 = MakeMacroButton("HS 78 Whistle", M.MacroBody_HS_Whistle, "Legion/BFA Flight Points\nZaralek Caverns Mitts")

    btnInstanceIO = MakeMacroButton("Instance IO", M.MacroBody_InstanceIO, "Teleport to/from LFG Instances")
    btnInstanceReset = MakeMacroButton("Instance Reset", M.MacroBody_InstanceReset)
    btnRez = MakeMacroButton("Rez", M.MacroBody_Rez)
    btnRezCombat = MakeMacroButton("Rez Combat", M.MacroBody_RezCombat)

    btnScriptErrors = MakeMacroButton("Script Errors", M.MacroBody_ScriptErrors)

    -- Home row
    local function NormalizeOwnedHouses(raw)
        if type(raw) ~= "table" then
            return {}
        end
        if raw[1] and type(raw[1]) == "table" then
            return raw
        end
        if type(raw.houses) == "table" and raw.houses[1] then
            return raw.houses
        end
        if type(raw.ownedHouses) == "table" and raw.ownedHouses[1] then
            return raw.ownedHouses
        end
        if type(raw.playerOwnedHouses) == "table" and raw.playerOwnedHouses[1] then
            return raw.playerOwnedHouses
        end

        local keyed = {}
        for k, v in pairs(raw) do
            if type(k) == "number" and type(v) == "table" then
                keyed[#keyed + 1] = { k = k, v = v }
            end
        end
        table.sort(keyed, function(a, b) return a.k < b.k end)
        if #keyed > 0 then
            local out = {}
            for i = 1, #keyed do
                out[i] = keyed[i].v
            end
            return out
        end

        local out = {}
        for _, v in pairs(raw) do
            if type(v) == "table" and (v.houseGUID ~= nil or v.neighborhoodGUID ~= nil or v.plotID ~= nil) then
                out[#out + 1] = v
            end
        end
        return out
    end

    -- Hearth selection row + popout
    local btnHSHearth = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btnHSHearth:SetSize(BTN_W, BTN_H)
    btnHSHearth:SetText("HS Hearth")

    local hearthZoneLine = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hearthZoneLine:SetJustifyH("LEFT")
    hearthZoneLine:SetWordWrap(false)
    if hearthZoneLine.SetMaxLines then hearthZoneLine:SetMaxLines(1) end
    hearthZoneLine:SetText("")

    hearthPopout = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    hearthPopout:SetWidth(360)
    hearthPopout:SetPoint("TOPLEFT", parent, "TOPRIGHT", 0, 0)
    hearthPopout:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", 0, 0)
    hearthPopout:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        tile = true, tileSize = 16,
    })
    hearthPopout:SetBackdropColor(0, 0, 0, 0.85)
    hearthPopout:Hide()

    local popoutClose = CreateFrame("Button", nil, hearthPopout, "UIPanelCloseButton")
    popoutClose:SetPoint("TOPRIGHT", hearthPopout, "TOPRIGHT", -3, -3)

    local popoutFilter = CreateFrame("EditBox", nil, hearthPopout, "InputBoxTemplate")
    popoutFilter:SetSize(200, 18)
    popoutFilter:SetPoint("TOP", hearthPopout, "TOP", 0, -12)
    popoutFilter:SetAutoFocus(false)
    popoutFilter:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    SetButtonTooltip(popoutFilter, "Type to filter\nOr enter an itemID to add")

    local btnAll = CreateFrame("Button", nil, hearthPopout, "UIPanelButtonTemplate")
    btnAll:SetSize(56, 18)
    btnAll:SetPoint("BOTTOM", hearthPopout, "BOTTOM", -(56 + 10), 42)
    btnAll:SetText("All")

    SetButtonTooltip(btnAll, function()
        if type(H.EnsureInit) ~= "function" then
            return "All\n\nShows the full hearthstone list."
        end
        local db2 = H.EnsureInit()
        local on = db2.toyShowAll and true or false
        return "All\n\nToggle showing ALL hearthstones in the list.\n\nCurrently: " .. (on and "ON" or "OFF")
    end)

    local btnAuto = CreateFrame("Button", nil, hearthPopout, "UIPanelButtonTemplate")
    btnAuto:SetSize(56, 18)
    btnAuto:SetPoint("LEFT", btnAll, "RIGHT", 10, 0)
    btnAuto:SetText("Auto")

    SetButtonTooltip(btnAuto, function()
        if type(H.EnsureInit) ~= "function" then
            return "Auto\n\nAuto-rotates hearthstones when creating the macro."
        end
        local db2 = H.EnsureInit()
        local on = db2.autoRotate and true or false
        return "Auto\n\nWhen ON, 'Create Macro' will use a rolled hearthstone automatically.\n\nCurrently: " .. (on and "ON" or "OFF")
    end)

    local btnRoll = CreateFrame("Button", nil, hearthPopout, "UIPanelButtonTemplate")
    btnRoll:SetSize(56, 18)
    btnRoll:SetPoint("LEFT", btnAuto, "RIGHT", 10, 0)
    btnRoll:SetText("Roll")

    SetButtonTooltip(btnRoll, "Roll\n\nPick a random hearthstone from the list for this macro.")

    local scroll = CreateFrame("ScrollFrame", nil, hearthPopout, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", hearthPopout, "TOPLEFT", 10, -44)
    scroll:SetPoint("TOPRIGHT", hearthPopout, "TOPRIGHT", -28, -44)
    scroll:SetPoint("BOTTOM", hearthPopout, "BOTTOM", 0, 74)

    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(1, 1)
    scroll:SetScrollChild(scrollChild)

    btnCreateHearthMacro = CreateFrame("Button", nil, hearthPopout, "UIPanelButtonTemplate")
    btnCreateHearthMacro:SetSize(BTN_W, BTN_H)
    btnCreateHearthMacro:SetPoint("BOTTOM", hearthPopout, "BOTTOM", 0, 12)
    btnCreateHearthMacro:SetText("Create Macro")

    local function UpdateHearthZoneLine()
        if type(H.GetCurrentDisplayText) ~= "function" then
            hearthZoneLine:SetText("")
            return
        end
        local bind, zone = H.GetCurrentDisplayText()
        local line = tostring(bind or "")
        if zone and zone ~= "" then
            line = line .. ", " .. tostring(zone)
        end

        local maxW = hearthZoneLine._maxWidth
        if not maxW or maxW <= 0 then
            maxW = hearthZoneLine.GetWidth and hearthZoneLine:GetWidth() or 0
        end
        if not maxW or maxW <= 0 then
            maxW = 320
        end

        FitFontStringToWidth(hearthZoneLine, line, maxW, BTN_H)
    end

    local function UpdatePopoutButtons()
        if type(H.EnsureInit) ~= "function" then
            return
        end

    -- Keep the HS location line in sync with bind/zone changes.
    do
        local ev = CreateFrame("Frame")
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        ev:RegisterEvent("UPDATE_BINDINGS")
        ev:RegisterEvent("HEARTHSTONE_BOUND")
        ev:SetScript("OnEvent", function()
            if parent and parent.IsShown and parent:IsShown() then
                UpdateHearthZoneLine()
            end
        end)
    end
        local db2 = H.EnsureInit()
        if db2.toyShowAll then btnAll:LockHighlight() else btnAll:UnlockHighlight() end
        if db2.autoRotate then btnAuto:LockHighlight() else btnAuto:UnlockHighlight() end

        local hasSelection = (tonumber(db2.selectedUseItemID) ~= nil)
        local canCreate = (db2.autoRotate and true or false) or hasSelection
        btnCreateHearthMacro:SetEnabled(canCreate)

        if canCreate and type(H.BuildMacroText) == "function" then
            local body = H.BuildMacroText(db2)
            if type(M.ApplyOptionalLines) == "function" then
                body = M.ApplyOptionalLines(body)
            end
            local max = tonumber(M.MAX_MACRO_CHARS) or 255
            if #tostring(body or "") > max then
                btnCreateHearthMacro:SetEnabled(false)
            end
        end
    end

    local function GetPopoutList()
        if type(H.EnsureInit) ~= "function" then
            return {}
        end
        local db2 = H.EnsureInit()
        local filterText = tostring(db2.toyFilter or "")

        local curated = H.CURATED_USE_ITEMS or {}
        local pass = H.PassToyFilter
        local getName = H.GetUseItemName
        local hasItem = H.HasUseItem

        local list = {}
        local seen = {}
        local function Add(id, label)
            id = tonumber(id)
            if not id or id <= 0 then return end
            if seen[id] then return end
            local name = (type(getName) == "function") and getName(id, label) or ("item:" .. tostring(id))
            if type(pass) == "function" then
                if not pass(name, filterText) then return end
            else
                local ft = SafeLower(filterText)
                if ft ~= "" and not SafeLower(name):find(ft, 1, true) then return end
            end

            local owned = (type(hasItem) == "function") and (hasItem(id) == true) or true
            list[#list + 1] = { id = id, name = tostring(name), owned = owned }
            seen[id] = true
        end

        if type(db2.customUseItems) == "table" then
            for _, id in ipairs(db2.customUseItems) do
                Add(id)
            end
        end

        for _, e in ipairs(curated) do
            Add(e.id, e.label)
        end

        if db2.toyShowAll and type(H.GetOwnedHearthToys) == "function" then
            for _, t in ipairs(H.GetOwnedHearthToys()) do
                Add(t.id, t.name)
            end
        end

        table.sort(list, function(a, b)
            return SafeLower(a.name) < SafeLower(b.name)
        end)

        return list
    end

    local listButtons = {}
    local function ClearListButtons()
        for i = 1, #listButtons do
            local b = listButtons[i]
            if b and b.Hide then b:Hide() end
        end
    end

    local function RebuildPopoutList()
        ClearListButtons()
        if type(H.EnsureInit) ~= "function" then
            return
        end
        local db2 = H.EnsureInit()
        local selected = tonumber(db2.selectedUseItemID)
        local list = GetPopoutList()

        local w = scroll.GetWidth and scroll:GetWidth() or 0
        if w and w > 0 and scrollChild.SetWidth then
            scrollChild:SetWidth(w)
        end

        local y = 0
        local rowH = 18
        for i = 1, #list do
            local e = list[i]
            local btn = listButtons[i]
            if not btn then
                btn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
                btn:SetHeight(rowH)
                listButtons[i] = btn
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
            btn:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -y)
            btn:SetText(e.name)
            if e.owned then btn:Enable() else btn:Disable() end
            if selected and selected == e.id then btn:LockHighlight() else btn:UnlockHighlight() end
            btn:SetScript("OnClick", function()
                if not e.owned then return end
                db2.selectedUseItemID = e.id
                RebuildPopoutList()
                UpdatePopoutButtons()
                UpdateHearthZoneLine()
            end)
            y = y + rowH + 2
        end

        scrollChild:SetHeight(math.max(1, y))
    end

    local function TryCreateHearthMacro()
        if M.InCombat() then
            M.Print("Can't create macros in combat.")
            return
        end
        if type(GetMacroIndexByName) ~= "function" or type(CreateMacro) ~= "function" then
            M.Print("Macro API unavailable.")
            return
        end
        if type(H.EnsureInit) ~= "function" or type(H.BuildMacroText) ~= "function" then
            M.Print("Hearth data unavailable.")
            return
        end

        local db2 = H.EnsureInit()
        if db2.autoRotate and not db2.selectedUseItemID and type(H.RollRandomUseItem) == "function" then
            H.RollRandomUseItem(db2)
        end

        local body = H.BuildMacroText(db2)
        if type(M.ApplyOptionalLines) == "function" then
            body = M.ApplyOptionalLines(body)
        end

        local max = tonumber(M.MAX_MACRO_CHARS) or 255
        if #tostring(body or "") > max then
            M.Print("Macro too long (" .. tostring(#tostring(body or "")) .. "/" .. tostring(max) .. "). Remove Optional lines.")
            return
        end
        local idx = GetMacroIndexByName(H.MACRO_NAME or "FAO Hearth")
        local macroName = H.MACRO_NAME or "FAO Hearth"
        local perCharacter = M.GetMacroPerCharSetting()

        if idx and idx > 0 then
            if type(EditMacro) == "function" then
                EditMacro(idx, macroName, "INV_Misc_QuestionMark", body)
                M.Print("Updated macro '" .. macroName .. "'.")
            else
                M.Print("Macro '" .. macroName .. "' already exists.")
            end
            hearthPopout:Hide()
            return
        end

        local ok = CreateMacro(macroName, "INV_Misc_QuestionMark", body, perCharacter)
        if ok then
            M.Print("Created macro '" .. macroName .. "'.")
            hearthPopout:Hide()
        else
            M.Print("Could not create macro (macro slots full?).")
        end
    end

    btnCreateHearthMacro:SetScript("OnClick", TryCreateHearthMacro)
    popoutClose:SetScript("OnClick", function() hearthPopout:Hide() end)

    btnAll:SetScript("OnClick", function()
        if type(H.EnsureInit) ~= "function" then return end
        local db2 = H.EnsureInit()
        db2.toyShowAll = not (db2.toyShowAll and true or false)
        UpdatePopoutButtons()
        RebuildPopoutList()
        UpdateMacroCreateButtonsEnabled()
    end)

    btnAuto:SetScript("OnClick", function()
        if type(H.EnsureInit) ~= "function" then return end
        local db2 = H.EnsureInit()
        db2.autoRotate = not (db2.autoRotate and true or false)
        UpdatePopoutButtons()
        UpdateMacroCreateButtonsEnabled()
    end)

    btnRoll:SetScript("OnClick", function()
        if M.InCombat() then
            M.Print("Can't roll in combat.")
            return
        end
        if type(H.EnsureInit) ~= "function" or type(H.RollRandomUseItem) ~= "function" or type(H.GetUseItemName) ~= "function" then
            return
        end
        local db2 = H.EnsureInit()
        local id = H.RollRandomUseItem(db2)
        if id then
            db2.selectedUseItemID = id
            M.Print("Rolled: " .. H.GetUseItemName(id))
        else
            M.Print("No usable hearth toys found.")
        end
        UpdatePopoutButtons()
        RebuildPopoutList()
        UpdateHearthZoneLine()
    end)

    local function AddCustomUseItem(id)
        if type(H.EnsureInit) ~= "function" then return end
        local db2 = H.EnsureInit()
        db2.customUseItems = db2.customUseItems or {}
        for _, v in ipairs(db2.customUseItems) do
            if tonumber(v) == id then
                return
            end
        end
        table.insert(db2.customUseItems, id)
    end

    popoutFilter:SetScript("OnShow", function(self)
        if type(H.EnsureInit) ~= "function" then return end
        local db2 = H.EnsureInit()
        self:SetText(tostring(db2.toyFilter or ""))
    end)
    popoutFilter:SetScript("OnEnterPressed", function(self)
        if type(H.EnsureInit) ~= "function" then return end
        local txt = tostring(self:GetText() or "")
        local id = tonumber(txt)
        local db2 = H.EnsureInit()
        if id and id > 0 then
            AddCustomUseItem(id)
            self:SetText("")
        else
            db2.toyFilter = txt
        end
        self:ClearFocus()
        RebuildPopoutList()
        UpdatePopoutButtons()
    end)
    popoutFilter:SetScript("OnEditFocusLost", function(self)
        if type(H.EnsureInit) ~= "function" then return end
        local db2 = H.EnsureInit()
        db2.toyFilter = tostring(self:GetText() or "")
        RebuildPopoutList()
        UpdatePopoutButtons()
    end)

    btnHSHearth:SetScript("OnClick", function()
        if hearthPopout:IsShown() then
            hearthPopout:Hide()
            return
        end
        UpdateHearthZoneLine()
        popoutFilter:GetScript("OnShow")(popoutFilter)
        UpdatePopoutButtons()
        RebuildPopoutList()
        hearthPopout:Show()
    end)

    -- Layout
    local function LayoutMacroButtons()
        local rowTotal = (BTN_W * 4) + (BTN_GAP * 3)
        local left = math.floor(((GetPanelWidth(parent) - rowTotal) / 2) + 0.5)
        if left < 10 then left = 10 end

        btnScriptErrors:ClearAllPoints()
        btnScriptErrors:SetPoint("BOTTOM", parent, "BOTTOM", 0, 12)

        local row2Y = 12 + BTN_H + BTN_GAP
        local row1Y = row2Y + BTN_H + BTN_GAP
        local hearthRowY = row1Y + BTN_H + BTN_GAP

        local row1 = { btnHS06, btnHS07, btnHS11, btnHS78 }
        local row2 = { btnInstanceIO, btnInstanceReset, btnRez, btnRezCombat }

        for i = 1, 4 do
            local b1 = row1[i]
            b1:ClearAllPoints()
            b1:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", left + ((i - 1) * (BTN_W + BTN_GAP)), row1Y)

            local b2 = row2[i]
            b2:ClearAllPoints()
            b2:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", left + ((i - 1) * (BTN_W + BTN_GAP)), row2Y)
        end

        do
            local threeBtnW = (BTN_W * 3) + (BTN_GAP * 2)
            local lineW = threeBtnW
            local hzTotal = BTN_W + BTN_GAP + lineW
            local hzLeft = math.floor(((GetPanelWidth(parent) - hzTotal) / 2) + 0.5)
            if hzLeft < 10 then hzLeft = 10 end

            btnHSHearth:ClearAllPoints()
            btnHSHearth:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", hzLeft, hearthRowY)

            hearthZoneLine:ClearAllPoints()
            hearthZoneLine:SetPoint("LEFT", btnHSHearth, "RIGHT", BTN_GAP, 0)
            hearthZoneLine:SetHeight(BTN_H)
            hearthZoneLine:SetWidth(lineW)
            hearthZoneLine._maxWidth = lineW
        end

        do
            local w = GetPanelWidth(parent) - 160
            if w < 260 then w = 260 end
            if w > 320 then w = 320 end
            hearthPopout:SetWidth(w)
        end

        UpdateHearthZoneLine()
    end

    parent:SetScript("OnShow", function()
        UpdateMacroScopeUI()
        LayoutMacroButtons()
    end)

    UpdateMacroScopeUI()
    LayoutMacroButtons()
end

ns.BuildMacrosPanel = BuildMacrosPanel
ns.BuildHearthMacrosPanel = BuildMacrosPanel
