local _, ns = ...

-- Home tab: Home Teleports UI + Guests popout.
-- Home Teleports mirrors the working "Add" -> "Create Macro" flow from MultipleHouseTeleports,
-- using FAO's secure /click buttons and captured current-house info.

local PREFIX = "|cff00ccff[FAO]|r "
local function Print(msg)
    if ns and ns.Macros and type(ns.Macros.Print) == "function" then
        ns.Macros.Print(msg)
        return
    end
    print(PREFIX .. tostring(msg or ""))
end

local function ErrorMessage(msg)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(tostring(msg or ""), 1, 0, 0)
    end
end

local function SetTooltip(frame, textOrFn)
    if not (frame and frame.SetScript) then
        return
    end
    frame:SetScript("OnEnter", function(self)
        local txt = textOrFn
        if type(txt) == "function" then
            txt = txt()
        end
        if type(txt) ~= "string" or txt == "" then
            return
        end
        if GameTooltip and GameTooltip.SetOwner and GameTooltip.SetText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(txt)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function()
        if GameTooltip and GameTooltip.Hide then
            GameTooltip:Hide()
        end
    end)
end

local function GetHomeTeleportSV()
    local cs = _G.fr0z3nUI_AutoOpen_CharSettings
    if type(cs) ~= "table" then
        return {}
    end
    local sv = cs.faoHomeTeleports
    if type(sv) ~= "table" then
        return {}
    end
    return sv
end

local function GetSavedTeleportsDB()
    _G.fr0z3nUI_AutoOpen_CharSettings = _G.fr0z3nUI_AutoOpen_CharSettings or {}
    local cs = _G.fr0z3nUI_AutoOpen_CharSettings
    if type(cs.faoSavedTeleports) ~= "table" then
        cs.faoSavedTeleports = {}
    end
    local db = cs.faoSavedTeleports
    if type(db.list) ~= "table" then
        db.list = {}
    end
    if type(db.nextId) ~= "number" then
        db.nextId = 1
    end
    return db
end

local function Trim(s)
    if type(s) ~= "string" then
        return ""
    end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function GetSavedTeleportMacroName(id)
    id = tonumber(id)
    if not id then
        return nil
    end
    return "FAO TP " .. tostring(id)
end

-- Dialogs (match MHT flow: click Add -> enter name)

local function EnsureFAOStaticPopups()
    local dialogs = _G and rawget(_G, "StaticPopupDialogs")
    if type(dialogs) ~= "table" then
        return false
    end

    if not dialogs["FAO_ADD_SAVED_LOCATION"] then
        dialogs["FAO_ADD_SAVED_LOCATION"] = {
            text = "Enter a name for this location:",
            button1 = "Save",
            button2 = "Cancel",
            hasEditBox = true,
            maxLetters = 50,
            OnAccept = function(self)
                local data = self.data
                if type(data) == "table" and type(data.onAccept) == "function" then
                    data.onAccept(self.EditBox:GetText())
                end
            end,
            OnShow = function(self)
                local data = self.data
                local prefill
                if type(data) == "table" and type(data.getPrefill) == "function" then
                    local ok, v = pcall(data.getPrefill)
                    if ok and type(v) == "string" then
                        prefill = v
                    end
                end
                if prefill == nil and type(data) == "table" then
                    prefill = data.prefill
                end
                if type(prefill) ~= "string" then
                    prefill = ""
                end
                self.EditBox:SetText(prefill)
                self.EditBox:HighlightText()
            end,
            EditBoxOnEnterPressed = function(self)
                local parent = self:GetParent()
                local data = parent.data
                if type(data) == "table" and type(data.onAccept) == "function" then
                    data.onAccept(self:GetText())
                end
                parent:Hide()
            end,
            EditBoxOnEscapePressed = function(self)
                self:GetParent():Hide()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end

    if not dialogs["FAO_RENAME_SAVED_LOCATION"] then
        dialogs["FAO_RENAME_SAVED_LOCATION"] = {
            text = "Enter a new name:",
            button1 = "Rename",
            button2 = "Cancel",
            hasEditBox = true,
            maxLetters = 50,
            OnAccept = function(self)
                local data = self.data
                if type(data) == "table" and type(data.onAccept) == "function" then
                    data.onAccept(self.EditBox:GetText())
                end
            end,
            OnShow = function(self)
                local data = self.data
                local currentName = (type(data) == "table") and data.currentName or nil
                if type(currentName) ~= "string" then
                    currentName = ""
                end
                self.EditBox:SetText(currentName)
                self.EditBox:HighlightText()
            end,
            EditBoxOnEnterPressed = function(self)
                local parent = self:GetParent()
                local data = parent.data
                if type(data) == "table" and type(data.onAccept) == "function" then
                    data.onAccept(self:GetText())
                end
                parent:Hide()
            end,
            EditBoxOnEscapePressed = function(self)
                self:GetParent():Hide()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end

    return true
end

-- Forward-safe indirection so CaptureSavedTeleport/CaptureNow can resolve names.
-- Real implementation is assigned later once neighborhood info cache is defined.
local function LookupNeighborhoodNameByGUID(neighborhoodGUID)
    return nil
end

local function CaptureSavedTeleport(name)
    name = Trim(name)
    if InCombatLockdown and InCombatLockdown() then
        ErrorMessage("Can't capture in combat")
        return false
    end
    if not (C_Housing and type(C_Housing.GetCurrentHouseInfo) == "function") then
        ErrorMessage("Housing API unavailable")
        return false
    end

    if C_HousingNeighborhood and type(C_HousingNeighborhood.RequestNeighborhoodInfo) == "function" then
        pcall(C_HousingNeighborhood.RequestNeighborhoodInfo)
    end

    local ok, info = pcall(C_Housing.GetCurrentHouseInfo)
    if not ok or type(info) ~= "table" then
        ErrorMessage("No current house info")
        return false
    end

    local neighborhoodGUID = info.neighborhoodGUID
    local houseGUID = info.houseGUID
    local plotID = info.plotID
    if neighborhoodGUID == nil or houseGUID == nil or plotID == nil then
        ErrorMessage("Enter a plot first")
        return false
    end

    local neighborhoodName = info.neighborhoodName or info["neighborhood"]
    if type(neighborhoodName) ~= "string" then
        neighborhoodName = ""
    end
    if neighborhoodName == "" then
        local lookedUp = LookupNeighborhoodNameByGUID(neighborhoodGUID)
        if type(lookedUp) == "string" and lookedUp ~= "" then
            neighborhoodName = lookedUp
        end
    end

    if name == "" then
        local fallback = info["plotName"] or info["ownerName"]
        if type(fallback) == "string" and fallback ~= "" then
            name = fallback
        else
            name = "Location"
        end
    end

    local db = GetSavedTeleportsDB()
    local list = db.list

    -- If already saved, update the name and return existing id.
    for i = 1, #list do
        local e = list[i]
        if type(e) == "table" and e.neighborhoodGUID == neighborhoodGUID and e.houseGUID == houseGUID and e.plotID == plotID then
            e.name = name
            e.neighborhoodName = neighborhoodName
            if ns and ns.Home and type(ns.Home.ConfigureSavedTeleportClickButtonById) == "function" then
                ns.Home.ConfigureSavedTeleportClickButtonById(e.id)
            end
            return true, e.id, true
        end
    end

    local id = tonumber(db.nextId) or 1
    db.nextId = id + 1

    local entry = {
        id = id,
        name = name,
        neighborhoodGUID = neighborhoodGUID,
        houseGUID = houseGUID,
        plotID = plotID,
        neighborhoodName = neighborhoodName,
    }
    table.insert(list, entry)

    if ns and ns.Home and type(ns.Home.ConfigureSavedTeleportClickButtonById) == "function" then
        ns.Home.ConfigureSavedTeleportClickButtonById(id)
    end
    return true, id, false
end

local function CanAddSavedLocation()
    if not (C_Housing and type(C_Housing.GetCurrentHouseInfo) == "function") then
        return false
    end
    local ok, info = pcall(C_Housing.GetCurrentHouseInfo)
    if not ok or type(info) ~= "table" then
        return false
    end
    return (info.neighborhoodGUID ~= nil and info.houseGUID ~= nil and info.plotID ~= nil)
end

local function GetHomeSlotLabel(which)
    local sv = GetHomeTeleportSV()
    local h = sv and sv[which] or nil
    if type(h) ~= "table" then
        return "(empty)"
    end
    local n = h.neighborhoodName
    if type(n) ~= "string" or n == "" then
        n = "House"
    end

    if n == "Founder's Point" then
        return "Alliance - " .. n
    end
    if n == "Razorwind Shores" then
        return "Horde - " .. n
    end
    return n
end

local function GetDefaultMacroNameForSlot(which)
    local sv = GetHomeTeleportSV()
    local h = sv and sv[which] or nil
    local n = (type(h) == "table") and h.neighborhoodName or nil
    if n == "Founder's Point" then
        return "FAO HM Alliance"
    end
    if n == "Razorwind Shores" then
        return "FAO HM Horde"
    end
    return (which == 2) and "FAO Home2" or "FAO Home1"
end

local function CaptureNow()
    if C_HousingNeighborhood and type(C_HousingNeighborhood.RequestNeighborhoodInfo) == "function" then
        pcall(C_HousingNeighborhood.RequestNeighborhoodInfo)
    end
    if not (C_Housing and type(C_Housing.GetCurrentHouseInfo) == "function") then
        ErrorMessage("Housing API unavailable")
        return false
    end
    local ok, info = pcall(C_Housing.GetCurrentHouseInfo)
    if not ok or type(info) ~= "table" then
        ErrorMessage("No current house info")
        return false
    end
    local neighborhoodGUID = info.neighborhoodGUID
    local houseGUID = info.houseGUID
    local plotID = info.plotID
    if neighborhoodGUID == nil or houseGUID == nil or plotID == nil then
        ErrorMessage("Enter your plot first")
        return false
    end

    _G.fr0z3nUI_AutoOpen_CharSettings = _G.fr0z3nUI_AutoOpen_CharSettings or {}
    local cs = _G.fr0z3nUI_AutoOpen_CharSettings
    cs.faoHomeTeleports = cs.faoHomeTeleports or {}
    local sv = cs.faoHomeTeleports

    local neighborhoodName = info.neighborhoodName or info["neighborhood"]
    if type(neighborhoodName) ~= "string" then
        neighborhoodName = ""
    end

    if neighborhoodName == "" then
        local lookedUp = LookupNeighborhoodNameByGUID(neighborhoodGUID)
        if type(lookedUp) == "string" and lookedUp ~= "" then
            neighborhoodName = lookedUp
        end
    end

    local which
    if neighborhoodName == "Founder's Point" then
        which = 1
    elseif neighborhoodName == "Razorwind Shores" then
        which = 2
    else
        which = (type(sv[1]) ~= "table") and 1 or 2
    end

    sv[which] = {
        neighborhoodGUID = neighborhoodGUID,
        houseGUID = houseGUID,
        plotID = plotID,
        neighborhoodName = neighborhoodName,
    }

    return true
end

local function CaptureHomeSlot(which)
    if InCombatLockdown and InCombatLockdown() then
        ErrorMessage("Can't capture in combat")
        return false
    end
    if C_HousingNeighborhood and type(C_HousingNeighborhood.RequestNeighborhoodInfo) == "function" then
        pcall(C_HousingNeighborhood.RequestNeighborhoodInfo)
    end
    if not (C_Housing and type(C_Housing.GetCurrentHouseInfo) == "function") then
        ErrorMessage("Housing API unavailable")
        return false
    end

    local ok, info = pcall(C_Housing.GetCurrentHouseInfo)
    if not ok or type(info) ~= "table" then
        ErrorMessage("No current house info")
        return false
    end

    local neighborhoodGUID = info.neighborhoodGUID
    local houseGUID = info.houseGUID
    local plotID = info.plotID
    if neighborhoodGUID == nil or houseGUID == nil or plotID == nil then
        ErrorMessage("Enter a plot first")
        return false
    end

    local neighborhoodName = info.neighborhoodName or info["neighborhood"]
    if type(neighborhoodName) ~= "string" then
        neighborhoodName = ""
    end

    local sv = GetHomeTeleportSV()
    sv[which] = {
        neighborhoodGUID = neighborhoodGUID,
        houseGUID = houseGUID,
        plotID = plotID,
        neighborhoodName = neighborhoodName,
    }
    return true
end

local function EnsureHomeMacro(which, perCharacter)
    if InCombatLockdown and InCombatLockdown() then
        ErrorMessage("Can't create macros in combat")
        return false
    end
    if not (ns and ns.Macros and type(ns.Macros.EnsureMacro) == "function") then
        ErrorMessage("Macro helpers unavailable")
        return false
    end

    local sv = GetHomeTeleportSV()
    local h = sv and sv[which] or nil
    if type(h) ~= "table" then
        ErrorMessage("Capture a plot first")
        return false
    end

    local macroName = GetDefaultMacroNameForSlot(which)
    local macroBody = (ns.Home and ns.Home.GetHomeClickMacroBody and ns.Home.GetHomeClickMacroBody(which)) or ("/click " .. ((which == 2) and "FAO_HomeTeleport2" or "FAO_HomeTeleport1"))

    local ok, why = ns.Macros.EnsureMacro(macroName, macroBody, perCharacter and true or false)
    if not ok then
        ErrorMessage(tostring(why or "Could not create macro"))
        return false
    end
    return true
end

local function EnsureFactionHomeMacro(faction)
    local which = (faction == "HORDE") and 2 or 1
    local perCharacter = (ns and ns.Macros and type(ns.Macros.GetMacroPerCharSetting) == "function" and ns.Macros.GetMacroPerCharSetting()) or false

    local sv = GetHomeTeleportSV()
    local h = sv and sv[which] or nil
    if type(h) ~= "table" then
        ErrorMessage("Capture your " .. ((which == 2) and "Horde" or "Alliance") .. " plot first")
        return false
    end

    if not (ns and ns.Macros and type(ns.Macros.EnsureMacro) == "function") then
        ErrorMessage("Macro helpers unavailable")
        return false
    end

    local macroName = (which == 2) and "FAO HM Horde" or "FAO HM Alliance"
    local macroBody = (ns.Home and ns.Home.GetHomeClickMacroBody and ns.Home.GetHomeClickMacroBody(which)) or ("/click " .. ((which == 2) and "FAO_HomeTeleport2" or "FAO_HomeTeleport1"))
    local ok, why = ns.Macros.EnsureMacro(macroName, macroBody, perCharacter and true or false)
    if not ok then
        ErrorMessage(tostring(why or "Could not create macro"))
        return false
    end
    return true, macroName
end

local function GetClassColorStr(classFile)
    if not classFile then return nil end
    if type(classFile) ~= "string" then return nil end
    local colors
    if type(_G) == "table" and rawget then
        colors = rawget(_G, "CUSTOM_CLASS_COLORS") or rawget(_G, "RAID_CLASS_COLORS")
    end
    local c = colors and colors[classFile] or nil
    if not c then return nil end
    if c.colorStr then return c.colorStr end
    if c.GenerateHexColor then return c:GenerateHexColor() end
    return nil
end

local function ColorName(name, classFile)
    local n = tostring(name or "")
    local hex = GetClassColorStr(classFile)
    if hex and hex ~= "" then
        return "|c" .. hex .. n .. "|r"
    end
    return n
end

local function SafeOwnedHouses()
    if not (C_Housing and C_Housing.GetPlayerOwnedHouses) then return nil end
    local ok, v = pcall(C_Housing.GetPlayerOwnedHouses)
    if ok then return v end
    return nil
end

local function SafeNeighborhoodCitizens()
    if not (C_Housing and C_Housing.GetNeighborhoodCitizens) then return nil end
    local ok, v = pcall(C_Housing.GetNeighborhoodCitizens)
    if ok then return v end
    return nil
end

-- Neighborhood info cache (mirrors MultipleHouseTeleports' approach) so we can
-- resolve neighborhood names even when GetCurrentHouseInfo doesn't include them.
local cachedNeighborhoodInfo = nil
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("NEIGHBORHOOD_INFO_UPDATED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "NEIGHBORHOOD_INFO_UPDATED" then
            cachedNeighborhoodInfo = ...
            return
        end

        if event == "PLAYER_ENTERING_WORLD" then
            if C_HousingNeighborhood and type(C_HousingNeighborhood.RequestNeighborhoodInfo) == "function" then
                pcall(C_HousingNeighborhood.RequestNeighborhoodInfo)
            end
        end
    end)
end

LookupNeighborhoodNameByGUID = function(neighborhoodGUID)
    if neighborhoodGUID == nil then
        return nil
    end

    local info = cachedNeighborhoodInfo
    if type(info) ~= "table" then
        return nil
    end

    local function TryTable(t)
        if type(t) ~= "table" then
            return nil
        end
        local guid = t.neighborhoodGUID or t.guid
        if guid ~= nil and guid == neighborhoodGUID then
            local n = t.neighborhoodName or t.name or t.neighborhood or t["neighborhoodName"] or t["name"]
            if type(n) == "string" and n ~= "" then
                return n
            end
        end
        return nil
    end

    local direct = TryTable(info)
    if direct then
        return direct
    end

    for _, v in pairs(info) do
        local n = TryTable(v)
        if n then
            return n
        end
    end

    return nil
end

local function GuessMyPlotID(citizens)
    local myGUID = UnitGUID and UnitGUID("player") or nil
    if myGUID and type(citizens) == "table" then
        for _, c in ipairs(citizens) do
            if type(c) == "table" and c.guid == myGUID and c.plotID ~= nil then
                return c.plotID
            end
        end
    end

    local houses = SafeOwnedHouses()
    if type(houses) == "table" then
        for _, h in ipairs(houses) do
            if type(h) == "table" and h.plotID ~= nil then
                return h.plotID
            end
        end
    end

    return nil
end

local function BuildGuestList()
    if not C_Housing then
        return {}, "Housing API unavailable"
    end
    if type(C_Housing.GetNeighborhoodCitizens) ~= "function" then
        return {}, "GetNeighborhoodCitizens unavailable"
    end

    local citizens = SafeNeighborhoodCitizens()
    if type(citizens) ~= "table" then
        return {}, "No neighborhood data (yet)"
    end

    local myGUID = UnitGUID and UnitGUID("player") or nil
    local myPlotID = GuessMyPlotID(citizens)
    local unfiltered = (myPlotID == nil)

    local out = {}
    for _, c in ipairs(citizens) do
        if type(c) == "table" then
            local guid = c.guid
            if guid and guid ~= myGUID then
                local plotOk = unfiltered or (c.plotID == myPlotID)
                if plotOk then
                    local classFile = c.class or c.classFile or c.classFilename
                    local name = c.name or c.fullName or "Unknown"
                    out[#out + 1] = {
                        guid = guid,
                        plotID = c.plotID,
                        name = name,
                        classFile = classFile,
                        coloredName = ColorName(name, classFile),
                    }
                end
            end
        end
    end

    table.sort(out, function(a, b)
        return tostring(a.name or "") < tostring(b.name or "")
    end)

    local note
    if unfiltered then
        note = "(unfiltered: plotID unknown)"
    elseif myPlotID ~= nil then
        note = "(plotID " .. tostring(myPlotID) .. ")"
    end

    return out, note
end

local function BuildHomePanel(parent)
    if not parent or parent._faoHomeBuilt then return end
    parent._faoHomeBuilt = true

    -- Main Home tab content: centered buttons + title.
    local btnAlliance = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btnAlliance:SetSize(90, 18)
    btnAlliance:SetPoint("TOP", parent, "TOP", -54, -52)
    btnAlliance:SetText("Alliance")

    local btnHorde = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btnHorde:SetSize(90, 18)
    btnHorde:SetPoint("TOP", parent, "TOP", 54, -52)
    btnHorde:SetText("Horde")

    local clickTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    clickTitle:SetPoint("TOP", btnAlliance, "BOTTOM", 54, -6)
    clickTitle:SetJustifyH("CENTER")
    clickTitle:SetText("Click At Home")
    do
        local font, size, flags = clickTitle:GetFont()
        if font and size then
            clickTitle:SetFont(font, math.max(8, (size or 12) - 2), flags)
        end
    end

    -- Status is now conveyed via entries in the box (not a separate line).
    local function SetStatus(text, kind) end

    -- Guests toggle (opens Guests popout)
    local btnGuests = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btnGuests:SetSize(70, 18)
    btnGuests:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, -52)
    btnGuests:SetText("Guests")

    -- Guests popout
    local popout = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    popout:SetWidth(360)
    popout:SetPoint("TOPLEFT", parent, "TOPRIGHT", 0, 0)
    popout:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", 0, 0)
    popout:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        tile = true, tileSize = 16,
    })
    popout:SetBackdropColor(0, 0, 0, 0.85)
    popout:Hide()

    local popoutClose = CreateFrame("Button", nil, popout, "UIPanelCloseButton")
    popoutClose:SetPoint("TOPRIGHT", popout, "TOPRIGHT", -3, -3)
    popoutClose:SetScript("OnClick", function() popout:Hide() end)

    btnGuests:SetScript("OnClick", function()
        if popout:IsShown() then popout:Hide() else popout:Show() end
    end)

    local gTitle = popout:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    gTitle:SetPoint("TOPLEFT", popout, "TOPLEFT", 14, -12)
    gTitle:SetJustifyH("LEFT")
    gTitle:SetText("Guests")

    local gStatus = popout:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    gStatus:SetPoint("TOPLEFT", gTitle, "BOTTOMLEFT", 0, -6)
    gStatus:SetJustifyH("LEFT")
    gStatus:SetText("")

    local btnRefresh = CreateFrame("Button", nil, popout, "UIPanelButtonTemplate")
    btnRefresh:SetSize(70, 18)
    btnRefresh:SetPoint("TOPRIGHT", popout, "TOPRIGHT", -18, -12)
    btnRefresh:SetText("Refresh")

    local scroll = CreateFrame("ScrollFrame", nil, popout, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", gStatus, "BOTTOMLEFT", 0, -10)
    scroll:SetPoint("TOPRIGHT", popout, "TOPRIGHT", -28, -48)
    scroll:SetPoint("BOTTOMLEFT", popout, "BOTTOMLEFT", 14, 14)

    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(1, 1)
    scroll:SetScrollChild(scrollChild)

    local rows = {}
    local ROW_H = 20

    local function EnsureRow(i)
        if rows[i] then return rows[i] end
        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -((i - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -6, -((i - 1) * ROW_H))

        local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFS:SetPoint("LEFT", row, "LEFT", 0, 0)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetText("")

        local btnKick = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btnKick:SetSize(46, 18)
        btnKick:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        btnKick:SetText("Kick")
        btnKick:Disable()

        row._nameFS = nameFS
        row._btnKick = btnKick
        rows[i] = row
        return row
    end

    local function SetKickEnabled(btn, guid)
        if not btn then return end
        if guid and type(C_Housing) == "table" and type(C_Housing.EjectGuest) == "function" then
            btn:Enable()
        else
            btn:Disable()
        end
    end

    local function RefreshGuests()
        local list, note = BuildGuestList()
        local msg
        if type(note) == "string" and note ~= "" then
            msg = tostring(#list) .. " guest(s) " .. note
        else
            msg = tostring(#list) .. " guest(s)"
        end
        gStatus:SetText(msg)

        local shown = 0
        for i = 1, #list do
            local e = list[i]
            local row = EnsureRow(i)
            row:Show()
            row._nameFS:SetText(e.coloredName or e.name or "")

            local guid = e.guid
            row._btnKick:SetScript("OnClick", function()
                if InCombatLockdown and InCombatLockdown() then
                    Print("Cannot kick in combat")
                    return
                end
                if not (C_Housing and C_Housing.EjectGuest) then
                    Print("EjectGuest unavailable")
                    return
                end
                local ok, err = pcall(C_Housing.EjectGuest, guid)
                if ok then
                    Print("Kick attempted")
                else
                    Print("Kick failed: " .. tostring(err or "unknown"))
                end
            end)
            SetKickEnabled(row._btnKick, guid)

            shown = i
        end

        for i = shown + 1, #rows do
            if rows[i] then rows[i]:Hide() end
        end

        local totalH = math.max(1, shown) * ROW_H
        scrollChild:SetHeight(totalH)
    end

    btnRefresh:SetScript("OnClick", RefreshGuests)

    -- Optional keybind capture (shift-click on Alliance/Horde).
    local binder = parent._faoHomeBinder
    if not binder then
        binder = CreateFrame("Frame", nil, UIParent)
        binder:Hide()
        binder:EnableKeyboard(true)
        if binder.SetPropagateKeyboardInput then binder:SetPropagateKeyboardInput(false) end
        binder:SetAllPoints(UIParent)
        binder:SetFrameStrata("TOOLTIP")
        binder:SetFrameLevel(999)
        parent._faoHomeBinder = binder
    end

    local function StopBindCapture(msg)
        binder:Hide()
        binder._targetMacro = nil
        if msg and msg ~= "" then
            ErrorMessage(msg)
        end
    end

    if not binder._faoHomeKeyScripted then
        binder._faoHomeKeyScripted = true
        binder:SetScript("OnKeyDown", function(_, key)
            if key == "ESCAPE" then
                StopBindCapture("")
                return
            end

            if key == "LALT" or key == "RALT" or key == "ALT"
                or key == "LSHIFT" or key == "RSHIFT" or key == "SHIFT"
                or key == "LCTRL" or key == "RCTRL" or key == "CTRL" then
                return
            end

            if key == "UNKNOWN" or key == nil or key == "" then
                return
            end

            local macroName = binder._targetMacro
            if not macroName then
                StopBindCapture("")
                return
            end

            if InCombatLockdown and InCombatLockdown() then
                StopBindCapture("Cannot bind in combat")
                return
            end

            if not (ns and ns.Macros and type(ns.Macros.SetMacroBinding) == "function") then
                StopBindCapture("Bind unavailable")
                return
            end

            local bindingKey = tostring(key)
            if IsShiftKeyDown and IsShiftKeyDown() then
                bindingKey = "SHIFT-" .. bindingKey
            end
            if IsControlKeyDown and IsControlKeyDown() then
                bindingKey = "CTRL-" .. bindingKey
            end
            if IsAltKeyDown and IsAltKeyDown() then
                bindingKey = "ALT-" .. bindingKey
            end

            local ok, why = ns.Macros.SetMacroBinding(macroName, bindingKey)
            if ok then
                StopBindCapture("")
            else
                StopBindCapture(tostring(why or "Bind failed"))
            end
        end)
    end

    local function StartBind(macroName)
        binder._targetMacro = macroName
        ErrorMessage("Press a key to bind (ESC cancels)")
        binder:Show()
    end

    SetTooltip(btnAlliance, "Captures current plot (if possible) and creates 'FAO HM Alliance'\nShift-click to bind")
    SetTooltip(btnHorde, "Captures current plot (if possible) and creates 'FAO HM Horde'\nShift-click to bind")

    -- (Handlers updated later, after the box is created.)

    -- Teleports rows
    local function MakeTeleportRow(which, y)
        local row = CreateFrame("Frame", nil, parent)
        row:SetHeight(22)
        row:SetPoint("TOPLEFT", btnAlliance, "BOTTOMLEFT", 0, -(y))
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, -(52 + 24 + 12 + 18 + 6 + y))

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", row, "LEFT", 0, 0)
        label:SetJustifyH("LEFT")
        label:SetText("")

        local btnAdd = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btnAdd:SetSize(46, 18)
        btnAdd:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        btnAdd:SetText("Add")

        local btnMacro = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btnMacro:SetSize(86, 18)
        btnMacro:SetPoint("RIGHT", btnAdd, "LEFT", -6, 0)
        btnMacro:SetText("Create Macro")

        local function FlashButtonText(btn, text, seconds, fallback)
            if not btn then return end
            local old = btn:GetText()
            btn:SetText(text)
            if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
                C_Timer.After(seconds or 0.8, function()
                    if btn and btn.SetText then
                        btn:SetText(fallback or old or "")
                    end
                end)
            end
        end

        local function RefreshRow()
            local sv = GetHomeTeleportSV()
            local has = (type(sv) == "table") and type(sv[which]) == "table"
            local prefix = "|cffffff00FAO|r "
            label:SetText(prefix .. ((which == 2) and "Home 2: " or "Home 1: ") .. GetHomeSlotLabel(which))

            local macroName = GetDefaultMacroNameForSlot(which)
            local macroExists = false
            if type(GetMacroIndexByName) == "function" and type(macroName) == "string" and macroName ~= "" then
                local idx = GetMacroIndexByName(macroName)
                macroExists = (idx and idx > 0) and true or false
            end

            if not has then
                btnMacro:Disable()
                btnMacro:SetText("Create Macro")
            elseif macroExists then
                btnMacro:Disable()
                btnMacro:SetText("Macro Exists")
            else
                btnMacro:Enable()
                btnMacro:SetText("Create Macro")
            end
        end

        btnAdd:SetScript("OnClick", function()
            if InCombatLockdown and InCombatLockdown() then
                ErrorMessage("Can't capture in combat")
                return
            end
            if CaptureNow() then
                RefreshRow()
                FlashButtonText(btnAdd, "Added", 0.8, "Add")
                SetStatus("Home " .. tostring(which) .. " captured. Click Create Macro.", "ok")
            end
        end)

        btnMacro:SetScript("OnClick", function()
            local perCharacter = (ns and ns.Macros and type(ns.Macros.GetMacroPerCharSetting) == "function" and ns.Macros.GetMacroPerCharSetting()) or false
            if EnsureHomeMacro(which, perCharacter) then
                FlashButtonText(btnMacro, "Created", 0.8, "Macro Exists")
                RefreshRow()
                SetStatus("Created macro: " .. tostring(GetDefaultMacroNameForSlot(which)) .. " (open /macro to place)", "ok")
            end
        end)

        RefreshRow()
        return RefreshRow
    end

    -- Hide FAO Home 1/2 rows
    local refreshRow1 = function() end
    local refreshRow2 = function() end

    -- Saved Locations list (no header text)

    local function FlashButtonText(btn, text, seconds, fallback)
        if not btn then return end
        local old = btn:GetText()
        btn:SetText(text)
        if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            C_Timer.After(seconds or 0.8, function()
                if btn and btn.SetText then
                    btn:SetText(fallback or old or "")
                end
            end)
        end
    end

    local btnAddSaved = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btnAddSaved:SetSize(90, 22) -- match Reload UI sizing
    btnAddSaved:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 14, 12)

    local function RefreshAddSavedButton()
        local canAdd = CanAddSavedLocation()
        btnAddSaved:SetText(canAdd and "|cFF00FF00+ Friend|r" or "|cFF888888+ Friend|r")
        if canAdd then
            btnAddSaved:Enable()
        else
            btnAddSaved:Disable()
        end
    end
    RefreshAddSavedButton()

    SetTooltip(btnAddSaved, function()
        if CanAddSavedLocation() then
            return "+ Friend\nSaves the plot you are currently standing in."
        end
        return "+ Friend\nEnter a housing plot first."
    end)

    -- Box: taller/wider, no border, no visible scrollbar.
    local savedBox = CreateFrame("Frame", nil, parent)
    savedBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -96)
    savedBox:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, -96)
    savedBox:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 14, 42)

    local savedBoxBg = savedBox:CreateTexture(nil, "BACKGROUND")
    savedBoxBg:SetAllPoints()
    savedBoxBg:SetColorTexture(0, 0, 0, 0.20)

    local savedScroll = CreateFrame("ScrollFrame", nil, savedBox, "UIPanelScrollFrameTemplate")
    savedScroll:SetPoint("TOPLEFT", savedBox, "TOPLEFT", 4, -4)
    savedScroll:SetPoint("BOTTOMRIGHT", savedBox, "BOTTOMRIGHT", -4, 4)
    if savedScroll.ScrollBar then
        savedScroll.ScrollBar:Hide()
        savedScroll.ScrollBar:SetAlpha(0)
        savedScroll.ScrollBar:EnableMouse(false)
    end

    local savedChild = CreateFrame("Frame", nil, savedScroll)
    savedChild:SetSize(1, 1)
    savedScroll:SetScrollChild(savedChild)

    local emptyText = savedChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    emptyText:SetPoint("TOPLEFT", savedChild, "TOPLEFT", 8, -8)
    emptyText:SetPoint("RIGHT", savedChild, "RIGHT", -8, 0)
    emptyText:SetJustifyH("LEFT")
    emptyText:SetText("No saved locations.")
    emptyText:Hide()

    local function RefreshSavedChildWidth()
        if not (savedScroll and savedChild) then return end
        local w = savedScroll:GetWidth()
        if w and w > 0 then
            savedChild:SetWidth(w)
        end
    end

    savedBox:SetScript("OnSizeChanged", RefreshSavedChildWidth)
    savedBox:HookScript("OnShow", function()
        RefreshSavedChildWidth()
        if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            C_Timer.After(0, RefreshSavedChildWidth)
        end
    end)

    -- Set an initial width immediately (OnSizeChanged won't always fire on first show)
    RefreshSavedChildWidth()
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(0, RefreshSavedChildWidth)
    end

    local SAVED_ROW_H = 24

    local savedRows = {}

    -- Empty state text should appear below the two fixed faction rows.
    emptyText:ClearAllPoints()
    emptyText:SetPoint("TOPLEFT", savedChild, "TOPLEFT", 8, -((2 * SAVED_ROW_H) + 8))
    emptyText:SetPoint("RIGHT", savedChild, "RIGHT", -8, 0)

    local function EnsureSavedRow(i)
        if savedRows[i] then
            return savedRows[i]
        end
        local row = CreateFrame("Frame", nil, savedChild)
        row:SetHeight(SAVED_ROW_H)
        row:SetPoint("TOPLEFT", savedChild, "TOPLEFT", 0, -((i - 1) * SAVED_ROW_H))
        row:SetPoint("TOPRIGHT", savedChild, "TOPRIGHT", -6, -((i - 1) * SAVED_ROW_H))

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if i % 2 == 0 then
            bg:SetColorTexture(1, 1, 1, 0.03)
        else
            bg:SetColorTexture(0, 0, 0, 0.03)
        end

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)

        local indexFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        indexFS:SetPoint("LEFT", row, "LEFT", 0, 0)
        indexFS:SetJustifyH("LEFT")
        indexFS:SetWidth(18)
        indexFS:SetText("")
        indexFS:SetTextColor(0.6, 0.6, 0.6)

        local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameFS:SetPoint("LEFT", indexFS, "RIGHT", 6, 0)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetText("")
        nameFS:SetWordWrap(false)

        local btnDel = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btnDel:SetSize(26, 24)
        btnDel:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        btnDel:SetText("D")
        btnDel:GetFontString():SetTextColor(1, 0.3, 0.3)

        local btnRename = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btnRename:SetSize(26, 24)
        btnRename:SetPoint("RIGHT", btnDel, "LEFT", -4, 0)
        btnRename:SetText("R")

        local btnMacro = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btnMacro:SetSize(90, 24)
        btnMacro:SetPoint("RIGHT", btnRename, "LEFT", -4, 0)
        btnMacro:SetText("Create Macro")

        -- Name should fill remaining space (avoid hard-coded offsets)
        nameFS:SetPoint("RIGHT", btnMacro, "LEFT", -8, 0)

        row._indexFS = indexFS
        row._nameFS = nameFS
        row._btnMacro = btnMacro
        row._btnRename = btnRename
        row._btnDel = btnDel
        savedRows[i] = row
        return row
    end

    local function RefreshSavedList()
        local db = GetSavedTeleportsDB()
        local list = db.list
        local shown = 0
        local savedIndex = 0

        local function SetupFactionRow(row, which)
            row._isFactionRow = true

            row._indexFS:SetText("")

            local labelText = (which == 2) and "FAO HM Horde" or "FAO HM Alliance"
            local colorHex = (which == 2) and "FFFF4444" or "FF3399FF"
            row._nameFS:SetText("|c" .. colorHex .. labelText .. "|r")

            -- No rename/delete for these fixed rows.
            row._btnDel:Hide()
            row._btnDel:Disable()
            row._btnRename:Hide()
            row._btnRename:Disable()

            -- Macro button should sit flush right.
            row._btnMacro:ClearAllPoints()
            row._btnMacro:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            row._btnMacro:SetText("Create Macro")

            local macroName = labelText
            local idx = (type(GetMacroIndexByName) == "function") and GetMacroIndexByName(macroName) or 0
            if idx and idx > 0 then
                row._btnMacro:Disable()
                row._btnMacro:SetText("Macro Exists")
            else
                row._btnMacro:Enable()
                row._btnMacro:SetText("Create Macro")
            end

            row._btnMacro:SetScript("OnClick", function()
                if InCombatLockdown and InCombatLockdown() then
                    ErrorMessage("Can't create macros in combat")
                    return
                end

                -- If you're in a plot, update the stored location first.
                if CanAddSavedLocation() then
                    CaptureHomeSlot(which)
                end

                local ok, createdName = EnsureFactionHomeMacro((which == 2) and "HORDE" or "ALLIANCE")
                if ok and createdName and IsShiftKeyDown and IsShiftKeyDown() then
                    StartBind(createdName)
                end
                RefreshSavedList()
            end)

            SetTooltip(row._btnMacro, (which == 2)
                and "Captures current plot (if possible) and creates 'FAO HM Horde'\nShift-click to bind"
                or "Captures current plot (if possible) and creates 'FAO HM Alliance'\nShift-click to bind")
        end

        -- Faction home macro entries always show at the top.
        do
            shown = shown + 1
            local rowA = EnsureSavedRow(shown)
            rowA:Show()
            SetupFactionRow(rowA, 1)

            shown = shown + 1
            local rowH = EnsureSavedRow(shown)
            rowH:Show()
            SetupFactionRow(rowH, 2)
        end

        for i = 1, #list do
            local e = list[i]
            if type(e) == "table" and e.id ~= nil then
                local entry = e
                local entryId = entry.id
                local macroName = GetSavedTeleportMacroName(entryId)

            savedIndex = savedIndex + 1
            shown = shown + 1
                local row = EnsureSavedRow(shown)
                row:Show()

            -- Restore normal row controls (in case this row was previously used differently).
            row._isFactionRow = nil
            row._btnDel:Show()
            row._btnRename:Show()
            row._btnDel:Enable()
            row._btnRename:Enable()

            row._indexFS:SetText(tostring(savedIndex) .. ".")

                local baseName = entry.name
                if type(baseName) ~= "string" or baseName == "" then
                    baseName = "Location"
                end
                local display = tostring(baseName)
                local neigh = entry.neighborhoodName
                if type(neigh) == "string" and neigh ~= "" then
                    display = display .. " |cFF888888(" .. neigh .. ")|r"
                end
                row._nameFS:SetText(display)

                local macroExists = false
                if type(macroName) == "string" and macroName ~= "" and type(GetMacroIndexByName) == "function" then
                    local idx = GetMacroIndexByName(macroName)
                    macroExists = (idx and idx > 0) and true or false
                end
                if macroExists then
                    row._btnMacro:Disable()
                    row._btnMacro:SetText("Macro Exists")
                else
                    row._btnMacro:Enable()
                    row._btnMacro:SetText("Create Macro")
                end

                row._btnMacro:SetScript("OnClick", function()
                    if InCombatLockdown and InCombatLockdown() then
                        ErrorMessage("Can't create macros in combat")
                        return
                    end
                    if not (ns and ns.Macros and type(ns.Macros.EnsureMacro) == "function") then
                        ErrorMessage("Macro helpers unavailable")
                        return
                    end
                    if ns.Home and type(ns.Home.ConfigureSavedTeleportClickButtonById) == "function" then
                        ns.Home.ConfigureSavedTeleportClickButtonById(entryId)
                    end
                    local body = (ns.Home and type(ns.Home.GetSavedTeleportClickMacroBodyById) == "function") and ns.Home.GetSavedTeleportClickMacroBodyById(entryId) or nil
                    if type(body) ~= "string" or body == "" then
                        ErrorMessage("Macro body unavailable")
                        return
                    end
                    local perCharacter = (ns and ns.Macros and type(ns.Macros.GetMacroPerCharSetting) == "function" and ns.Macros.GetMacroPerCharSetting()) or false

                    -- Visible feedback (match MHT feel, without chat spam)
                    row._btnMacro:SetText("Creating...")
                    row._btnMacro:Disable()

                    local ok, why = ns.Macros.EnsureMacro(macroName, body, perCharacter and true or false)
                    if not ok then
                        ErrorMessage(tostring(why or "Could not create macro"))
                        row._btnMacro:SetText("Create Macro")
                        row._btnMacro:Enable()
                        SetStatus(tostring(why or "Could not create macro"), "error")
                        return
                    end

                    FlashButtonText(row._btnMacro, "Created", 0.8, "Macro Exists")
                    row._btnMacro:SetText("Macro Exists")
                    row._btnMacro:Disable()

                    SetStatus("Created macro: " .. tostring(macroName) .. " (open /macro to place)", "ok")

                    if IsShiftKeyDown and IsShiftKeyDown() then
                        StartBind(macroName)
                    end

                    RefreshSavedList()
                end)

                SetTooltip(row._btnMacro, function()
                    local body = (ns.Home and type(ns.Home.GetSavedTeleportClickMacroBodyById) == "function") and ns.Home.GetSavedTeleportClickMacroBodyById(entryId) or ""
                    return "Creates macro '" .. tostring(macroName or "") .. "'\n" .. tostring(body) .. "\nShift-click to bind"
                end)

                row._btnRename:SetScript("OnClick", function()
                    if InCombatLockdown and InCombatLockdown() then
                        ErrorMessage("Can't rename in combat")
                        return
                    end
                    local data = {
                        currentName = tostring(entry.name or ""),
                        onAccept = function(newName)
                            newName = Trim(newName)
                            if newName == "" then
                                return
                            end
                            local db2 = GetSavedTeleportsDB()
                            local list2 = db2.list
                            for j = 1, #list2 do
                                local cur = list2[j]
                                if type(cur) == "table" and cur.id == entryId then
                                    cur.name = newName
                                    break
                                end
                            end
                            RefreshSavedList()
                        end,
                    }
                    EnsureFAOStaticPopups()
                    StaticPopup_Show("FAO_RENAME_SAVED_LOCATION", nil, nil, data)
                end)

                row._btnDel:SetScript("OnClick", function()
                    if InCombatLockdown and InCombatLockdown() then
                        ErrorMessage("Can't delete in combat")
                        return
                    end

                    if not (IsShiftKeyDown and IsShiftKeyDown()) then
                        ErrorMessage("Hold Shift to delete")
                        return
                    end

                    local id = entryId
                    for j = 1, #list do
                        local cur = list[j]
                        if type(cur) == "table" and cur.id == id then
                            table.remove(list, j)
                            break
                        end
                    end

                    if ns and ns.Home and type(ns.Home.ConfigureSavedTeleportClickButtonById) == "function" then
                        ns.Home.ConfigureSavedTeleportClickButtonById(id)
                    end
                    RefreshSavedList()
                end)
            end
        end

        for i = shown + 1, #savedRows do
            if savedRows[i] then
                savedRows[i]:Hide()
            end
        end

        if #list <= 0 then
            emptyText:Show()
        else
            emptyText:Hide()
        end

        savedChild:SetHeight(math.max(1, shown) * SAVED_ROW_H)
    end

    btnAddSaved:SetScript("OnClick", function()
        if InCombatLockdown and InCombatLockdown() then
            ErrorMessage("Can't capture in combat")
            return
        end
        if not CanAddSavedLocation() then
            ErrorMessage("Enter a plot first")
            return
        end

        local data = {
            getPrefill = function()
                if not (C_Housing and type(C_Housing.GetCurrentHouseInfo) == "function") then
                    return ""
                end
                local ok, info = pcall(C_Housing.GetCurrentHouseInfo)
                if not ok or type(info) ~= "table" then
                    return ""
                end
                local v = info["plotName"] or info["ownerName"] or ""
                if type(v) ~= "string" then
                    v = ""
                end
                return v
            end,
            onAccept = function(name)
                local ok2, id, updated = CaptureSavedTeleport(name)
                if ok2 then
                    -- Give a visible cue like MHT's instant state changes
                    btnAddSaved:Disable()
                    FlashButtonText(btnAddSaved, "Added", 0.8)

                    if updated then
                        SetStatus("Updated location #" .. tostring(id) .. ": " .. tostring(Trim(name) ~= "" and Trim(name) or "Location"), "ok")
                    else
                        SetStatus("Saved location #" .. tostring(id) .. ": " .. tostring(Trim(name) ~= "" and Trim(name) or "Location"), "ok")
                    end

                    RefreshSavedList()
                    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
                        C_Timer.After(0.85, function()
                            if parent and parent:IsShown() then
                                RefreshAddSavedButton()
                            end
                        end)
                    else
                        RefreshAddSavedButton()
                    end
                end
            end,
        }
        EnsureFAOStaticPopups()
        StaticPopup_Show("FAO_ADD_SAVED_LOCATION", nil, nil, data)
    end)

    -- Wire faction buttons to: capture (when possible) + create macro (previous behavior)
    btnAlliance:SetScript("OnClick", function()
        -- If you're in a plot, update the stored location first.
        if CanAddSavedLocation() then
            CaptureHomeSlot(1)
        end

        local ok, macroName = EnsureFactionHomeMacro("ALLIANCE")
        if ok and macroName and IsShiftKeyDown and IsShiftKeyDown() then
            StartBind(macroName)
        end
        RefreshSavedList()
    end)

    btnHorde:SetScript("OnClick", function()
        if CanAddSavedLocation() then
            CaptureHomeSlot(2)
        end

        local ok, macroName = EnsureFactionHomeMacro("HORDE")
        if ok and macroName and IsShiftKeyDown and IsShiftKeyDown() then
            StartBind(macroName)
        end
        RefreshSavedList()
    end)

    local ev = CreateFrame("Frame")
    parent._faoHomeEventFrame = ev

    local function SafeRegisterEvent(frame, evName)
        if not (frame and frame.RegisterEvent and evName) then
            return
        end
        pcall(frame.RegisterEvent, frame, evName)
    end

    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("NEIGHBORHOOD_LIST_UPDATED")
    ev:RegisterEvent("HOUSE_PLOT_ENTERED")
    SafeRegisterEvent(ev, "CURRENT_HOUSE_INFO_UPDATED")
    SafeRegisterEvent(ev, "CURRENT_HOUSE_INFO_RECIEVED")
    SafeRegisterEvent(ev, "CURRENT_HOUSE_INFO_RECEIVED")
    ev:SetScript("OnEvent", function()
        if parent:IsShown() then
            refreshRow1()
            refreshRow2()
            RefreshSavedList()
            RefreshAddSavedButton()
        end
        if popout:IsShown() then
            RefreshGuests()
        end
    end)

    popout:HookScript("OnShow", function()
        RefreshGuests()
    end)

    local credit = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    credit:SetPoint("BOTTOM", parent, "BOTTOM", 0, 10)
    credit:SetJustifyH("CENTER")
    credit:SetText("Thanks to Sponson's\nMultiple House Teleports")

    refreshRow1()
    refreshRow2()
    RefreshSavedList()
end

ns.BuildHomePanel = BuildHomePanel
