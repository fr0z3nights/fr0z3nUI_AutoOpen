local addonName, ns = ...
local lastOpenTime, atBank, atMail = 0, false, false
local OPEN_COOLDOWN = 1.5

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

local function InitSV()
    fr0z3nUI_AutoOpen_Acc = fr0z3nUI_AutoOpen_Acc or {}
    fr0z3nUI_AutoOpen_Char = fr0z3nUI_AutoOpen_Char or {}
    fr0z3nUI_AutoOpen_Settings = fr0z3nUI_AutoOpen_Settings or { disabled = {} }
    fr0z3nUI_AutoOpen_Timers = fr0z3nUI_AutoOpen_Timers or {}
end

-- [ TIMER RECOVERY & DISRUPTION ]
local function CheckTimersOnLogin()
    if not fr0z3nUI_AutoOpen_Timers then return end
    local currentTime, foundAny = time(), false
    for slotKey, data in pairs(fr0z3nUI_AutoOpen_Timers) do
        local b, s = slotKey:match("(%d+)-(%d+)")
        if b and s then
            b, s = tonumber(b), tonumber(s)
            if b and s then
                local currentID = C_Container.GetContainerItemID(b, s)
                if ns.timed and ns.timed[data.id] then
                    local remaining = ns.timed[data.id][1] - (currentTime - data.startTime)
                    if currentID ~= data.id then
                        if remaining > 0 then print("|cff00ccff[FAO]|r Timer Disrupted: |cffffff00"..ns.timed[data.id][2].."|r moved.") end
                        fr0z3nUI_AutoOpen_Timers[slotKey] = nil
                    elseif remaining > 0 then
                        local d = math.floor(remaining / 86400)
                        local h = math.floor((remaining % 86400) / 3600)
                        local m = math.ceil((remaining % 3600) / 60)
                        print(string.format("|cff00ccff[FAO]|r Timer: |cffffff00%s|r - |cffff0000%dd %dh %dm|r left.", ns.timed[data.id][2], d, h, m))
                        foundAny = true
                    else fr0z3nUI_AutoOpen_Timers[slotKey] = nil end
                end
            end
        end
    end
end

-- [ SCAN ENGINE ]
local frame = CreateFrame('Frame', 'fr0z3nUI_AutoOpenFrame')
function frame:RunScan()
    if atBank or atMail or InCombatLockdown() or LootFrame:IsShown() then return end
    if (GetTime() - lastOpenTime) < OPEN_COOLDOWN then return end
    
    for b = 0, 4 do
        for s = 1, C_Container.GetContainerNumSlots(b) do
            local id = C_Container.GetContainerItemID(b, s)
            if id then
                -- Handle Timers
                local isHatching = false
                if ns.timed and ns.timed[id] then
                    local key = GetSlotKey(b, s)
                    if not fr0z3nUI_AutoOpen_Timers[key] or fr0z3nUI_AutoOpen_Timers[key].id ~= id then
                        fr0z3nUI_AutoOpen_Timers[key] = { id = id, startTime = time() }
                    end
                    local hatchTime = ns.timed[id][1]
                    if (time() - fr0z3nUI_AutoOpen_Timers[key].startTime) < hatchTime then
                        isHatching = true
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
frame:RegisterEvent('BANKFRAME_OPENED'); frame:RegisterEvent('BANKFRAME_CLOSED'); frame:RegisterEvent('MAIL_SHOW'); frame:RegisterEvent('MAIL_CLOSED')

frame:SetScript('OnEvent', function(self, event)
    if event == "PLAYER_LOGIN" then 
        InitSV(); C_Timer.After(2, CheckTimersOnLogin)
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
    if data.id and ns.timed and ns.timed[data.id] then
        for _, tData in pairs(fr0z3nUI_AutoOpen_Timers) do
            if tData.id == data.id then
                local rem = ns.timed[data.id][1] - (time() - tData.startTime)
                if rem > 0 then
                    tooltip:AddLine(" "); tooltip:AddLine(string.format("|cff00ccffHatching In:|r |cffff0000%dd %dh %dm|r", math.floor(rem/86400), math.floor((rem%86400)/3600), math.ceil((rem%3600)/60)))
                end
            end
        end
    end
end)

-- [ SLASH COMMAND + SIMPLE OPTIONS WINDOW ]
local function AddItemByID(id, scope)
    if not id then print("|cff00ccff[FAO]|r Please enter a valid item ID.") return end
    InitSV()
    if ns.exclude and ns.exclude[id] then
        local name = ns.exclude[id][1] or ("ID "..id)
        local reason = ns.exclude[id][2] or "Excluded"
        print("|cff00ccff[FAO]|r Excluded: |cffffff00"..name.."|r - "..reason)
        return
    end
    if scope == "acc" then
        if fr0z3nUI_AutoOpen_Acc[id] then print("|cff00ccff[FAO]|r Already in Account whitelist: "..(GetItemInfo and (GetItemInfo(id) or id) or id)) return end
        fr0z3nUI_AutoOpen_Acc[id] = true
    else
        if fr0z3nUI_AutoOpen_Char[id] then print("|cff00ccff[FAO]|r Already in Character whitelist: "..(GetItemInfo and (GetItemInfo(id) or id) or id)) return end
        fr0z3nUI_AutoOpen_Char[id] = true
    end
    local iname = (GetItemInfo and GetItemInfo(id)) or tostring(id)
    print("|cff00ccff[FAO]|r Added: |cffffff00"..iname.."|r to "..(scope=="acc" and "Account" or "Character"))
end

local function CreateOptionsWindow()
    if fr0z3nUI_AutoOpenOptions then return end
    local f = CreateFrame("Frame", "fr0z3nUI_AutoOpenOptions", UIParent, "BackdropTemplate")
    fr0z3nUI_AutoOpenOptions = f
    f:SetSize(300,150)
    f:SetPoint("CENTER")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) if self.StopMovingOrSizing then self:StopMovingOrSizing() end end)
    f:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background", tile = true, tileSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 }})
    f:SetBackdropColor(0,0,0,0.7)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("fr0z3nUI AutoOpen")

    local info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    info:SetPoint("TOP", title, "BOTTOM", 0, -6)
    info:SetText("Enter ItemID Below")

    local edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    edit:SetSize(180,36)
    edit:SetPoint("TOP", info, "BOTTOM", 0, -4)
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
    nameLabel:SetPoint("TOP", edit, "BOTTOM", 0, -4)
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

    local btnChar = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnChar:SetSize(110,24)
    btnChar:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -8, 10)
    btnChar:SetText("Character")
    btnChar:SetScript("OnClick", function()
        local id = f.validID or tonumber(edit:GetText() or "")
        AddItemByID(id, "char")
    end)
    btnChar:Disable()
    f.btnChar = btnChar

    local btnAcc = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnAcc:SetSize(110,24)
    btnAcc:SetPoint("BOTTOMLEFT", f, "BOTTOM", 8, 10)
    btnAcc:SetText("Account")
    btnAcc:SetScript("OnClick", function()
        local id = f.validID or tonumber(edit:GetText() or "")
        AddItemByID(id, "acc")
    end)
    btnAcc:Disable()
    f.btnAcc = btnAcc

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
            local displayName = lockedName or (GetItemInfo and GetItemInfo(id)) or ("ID "..id)
            if f.nameLabel then f.nameLabel:SetText("|cffffff00"..displayName.."|r") end
            if f.reasonLabel then f.reasonLabel:SetText("|cffff9900Requires level "..req.." (will not auto-open yet)|r") end
            f.validID = id
            if f.btnChar then f.btnChar:Enable() end
            if f.btnAcc then f.btnAcc:Enable() end
            return
        end

        local iname = (GetItemInfo and GetItemInfo(id)) or ("ID "..id)
        if ns.exclude and ns.exclude[id] then
            local exName = ns.exclude[id][1] or iname
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

    f:Hide()
end

-- /fao opens the GUI (no /fao add)
SLASH_FAO1 = "/fao"
SlashCmdList["FAO"] = function(msg)
    InitSV()
    CreateOptionsWindow()

    local f = fr0z3nUI_AutoOpenOptions
    if not f then return end

    local text = (msg and msg:gsub("^%s+", ""):gsub("%s+$", "")) or ""
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
