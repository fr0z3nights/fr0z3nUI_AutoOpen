local addonName, ns = ...
local lastOpenTime, atBank, atMail, atMerchant = 0, false, false, false
local OPEN_COOLDOWN = 1.5

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
        local currentID = C_Container.GetContainerItemID(tonumber(b), tonumber(s))
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

-- [ SCAN ENGINE ]
local frame = CreateFrame('Frame', 'fr0z3nUI_AutoOpenFrame')
function frame:RunScan()
    if atBank or atMail or atMerchant or InCombatLockdown() or C_Loot.IsLootOpen() then return end
    if (GetTime() - lastOpenTime) < OPEN_COOLDOWN then return end
    
    for b = 0, 4 do
        for s = 1, C_Container.GetContainerNumSlots(b) do
            local id = C_Container.GetContainerItemID(b, s)
            if id then
                -- Handle Timers
                if ns.timed and ns.timed[id] then
                    local key = b.."-"..s
                    if not fr0z3nUI_AutoOpen_Timers[key] or fr0z3nUI_AutoOpen_Timers[key].id ~= id then
                        fr0z3nUI_AutoOpen_Timers[key] = { id = id, startTime = time() }
                    end
                    if (time() - fr0z3nUI_AutoOpen_Timers[key].startTime) < ns.timed[id][1] then id = nil end
                end
                
                -- Check Whitelist/Custom IDs and Filter via ns.exclude
                if id and (ns.items[id] or fr0z3nUI_AutoOpen_Acc[id] or fr0z3nUI_AutoOpen_Char[id]) then
                    if not ns.exclude[id] and not fr0z3nUI_AutoOpen_Settings.disabled[id] then
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
    if event == "PLAYER_LOGIN" then InitSV(); C_Timer.After(2, CheckTimersOnLogin)
    elseif event:find("OPENED") or event:find("SHOW") then atBank = true
    elseif event:find("CLOSED") then atBank = false; atMail = false
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
