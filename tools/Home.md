```lua
do
	local function ErrorMessage(msg)
		if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(tostring(msg or ""), 1, 0, 0) end
	end
	local function RequestHouseData(guid)
		if not C_Housing then return false end
		if type(C_Housing.RequestHouseData) ~= "function" then return false end
		if guid ~= nil then pcall(C_Housing.RequestHouseData, guid) else pcall(C_Housing.RequestHouseData) end
		return true
	end
	local function SafeGetPlayerHouseGUIDs()
		if not (C_Housing and type(C_Housing.GetPlayerHouseGUIDs) == "function") then return nil end
		local ok, guids = pcall(C_Housing.GetPlayerHouseGUIDs)
		if not ok then return nil end
		if type(guids) ~= "table" then return guids end
		if guids[1] ~= nil then return guids end
		local out = {} for _, v in pairs(guids) do if v ~= nil then out[#out + 1] = v end end
		if #out > 0 then table.sort(out, function(a, b) return tostring(a) < tostring(b) end) return out end
		return guids
	end
	local function SafeGetHouseInfo(houseGUID)
		if not (C_Housing and type(C_Housing.GetHouseInfo) == "function") then return nil end
		local ok, info = pcall(C_Housing.GetHouseInfo, houseGUID)
		if not ok then return nil end
		return info
	end
	local function RegisterOnceEvent(eventName, callback)
		if type(eventName) ~= "string" or type(callback) ~= "function" then return false end
		if EventUtil and type(EventUtil.RegisterOnceFrameEventAndCallback) == "function" then EventUtil.RegisterOnceFrameEventAndCallback(eventName, callback) return true end
		local f = CreateFrame("Frame")
		f:RegisterEvent(eventName)
		f:SetScript("OnEvent", function(self)
			self:UnregisterEvent(eventName)
			self:SetScript("OnEvent", nil)
			pcall(callback)
		end)
		return true
	end
	local function RequestOwnedHousesRefresh()
		if not C_Housing then return false end
		if type(C_Housing.RefreshPlayerOwnedHouses) == "function" then pcall(C_Housing.RefreshPlayerOwnedHouses) return true end
		if type(C_Housing.RequestPlayerOwnedHouses) == "function" then pcall(C_Housing.RequestPlayerOwnedHouses) return true end
		return false
	end
	local lastSyncMessageAt = 0
	local function SyncMessageOnce(msg)
		local now = (GetTime and GetTime()) or 0
		if now > 0 and (now - lastSyncMessageAt) < 1.0 then return end
		lastSyncMessageAt = now
		ErrorMessage(msg)
	end
	local function NormalizeOwnedHouses(raw)
		if type(raw) ~= "table" then return {} end
		if raw[1] and type(raw[1]) == "table" then return raw end
		if type(raw.houses) == "table" and raw.houses[1] then return raw.houses end
		if type(raw.ownedHouses) == "table" and raw.ownedHouses[1] then return raw.ownedHouses end
		if type(raw.playerOwnedHouses) == "table" and raw.playerOwnedHouses[1] then return raw.playerOwnedHouses end
		local keyed = {}
		for k, v in pairs(raw) do if type(k) == "number" and type(v) == "table" then keyed[#keyed + 1] = { k = k, v = v } end end
		table.sort(keyed, function(a, b) return a.k < b.k end)
		if #keyed > 0 then local out = {} for i = 1, #keyed do out[i] = keyed[i].v end return out end
		local out = {}
		for _, v in pairs(raw) do if type(v) == "table" and (v.houseGUID ~= nil or v.neighborhoodGUID ~= nil or v.plotID ~= nil) then out[#out + 1] = v end end
		table.sort(out, function(a, b)
			local ap = tonumber(a and a.plotID) or math.huge
			local bp = tonumber(b and b.plotID) or math.huge
			if ap ~= bp then return ap < bp end
			local an = tostring(a and (a.neighborhoodName or a.neighborhoodGUID or a.houseGUID) or "")
			local bn = tostring(b and (b.neighborhoodName or b.neighborhoodGUID or b.houseGUID) or "")
			return an < bn
		end)
		return out
	end
	local function GetOwnedHouses()
		if not (C_Housing and C_Housing.GetPlayerOwnedHouses) then return {} end
		local ok, houses = pcall(C_Housing.GetPlayerOwnedHouses)
		if not ok then return {} end
		return NormalizeOwnedHouses(houses)
	end
	local function GetHouseInfoByIndex(index)
		local guids = SafeGetPlayerHouseGUIDs()
		if type(guids) ~= "table" or #guids == 0 then return nil, "noguids" end
		local infos = {}
		for i = 1, #guids do local guid = guids[i] if guid ~= nil then local info = SafeGetHouseInfo(guid) if type(info) == "table" then infos[#infos + 1] = info end end end
		if #infos == 0 then return nil, "noinfo" end
		table.sort(infos, function(a, b)
			local ap = tonumber(a and a.plotID) or math.huge
			local bp = tonumber(b and b.plotID) or math.huge
			if ap ~= bp then return ap < bp end
			local an = tostring(a and (a.neighborhoodName or a.neighborhoodGUID or a.houseGUID) or "")
			local bn = tostring(b and (b.neighborhoodName or b.neighborhoodGUID or b.houseGUID) or "")
			return an < bn
		end)
		return infos[index], "guidinfo"
	end
	local pendingHouseIndex
	local waitingForHouseList = false
	local waitToken = 0
	do
		local warm = CreateFrame("Frame")
		warm:RegisterEvent("PLAYER_LOGIN")
		warm:RegisterEvent("PLAYER_ENTERING_WORLD")
		warm:RegisterEvent("HOUSE_PLOT_ENTERED")
		warm:SetScript("OnEvent", function()
			if C_Housing and C_Housing.GetPlayerOwnedHouses then pcall(C_Housing.GetPlayerOwnedHouses) end
			RequestOwnedHousesRefresh()
			if C_Housing and type(C_Housing.GetPlayerHouseGUIDs) == "function" then pcall(C_Housing.GetPlayerHouseGUIDs) end
		end)
	end
	local function PortToHouse(index)
		if not (C_Housing and C_Housing.TeleportHome) then ErrorMessage("Housing API unavailable") return end
		index = tonumber(index) or 1
		RequestOwnedHousesRefresh()
		local h
		local guids = SafeGetPlayerHouseGUIDs()
		local targetGUID = (type(guids) == "table") and guids[index] or nil
		if targetGUID ~= nil then h = SafeGetHouseInfo(targetGUID) if not (h and h.neighborhoodGUID) then RequestHouseData(targetGUID) end end
		if not h then local houses = GetOwnedHouses() if houses and #houses > 0 then h = houses[index] end end
		if not h then h = (select(1, GetHouseInfoByIndex(index))) end
		if h and h.neighborhoodGUID then
			local neighborhoodName = tostring(h.neighborhoodName or "")
			local zoneName = "House"
			local color = "ffffffff"
			if neighborhoodName == "Founder's Point" then zoneName = "Founder's Point" color = "ff0070dd"
			elseif neighborhoodName == "Razorwind Shores" then zoneName = "Razorwind Shores" color = "ffc41e3a"
			elseif neighborhoodName ~= "" then zoneName = neighborhoodName end
			local neighborhoodGUID = h.neighborhoodGUID
			local houseGUID = h.houseGUID
			local plotID = h.plotID
			if neighborhoodGUID == nil or houseGUID == nil or plotID == nil then ErrorMessage("House data incomplete. Syncing... click again.") if houseGUID ~= nil then RequestHouseData(houseGUID) end RequestOwnedHousesRefresh() return end
			local ok, err = pcall(C_Housing.TeleportHome, neighborhoodGUID, houseGUID, plotID)
			if not ok then local e = tostring(err or "") local el = e:lower() if el:find("protected") or el:find("blocked") then ErrorMessage("Teleport blocked (protected)") else ErrorMessage("Teleport failed") end end
			return
		end
		local requested = true
		requested = RequestHouseData(nil) or requested
		if waitingForHouseList then SyncMessageOnce("Housing data syncing... click again.") return end
		pendingHouseIndex = index
		waitingForHouseList = true
		SyncMessageOnce("Housing data syncing... click again.")
		waitToken = waitToken + 1
		local token = waitToken
		local idxRequested = index
		local ok = RegisterOnceEvent("PLAYER_HOUSE_LIST_UPDATED", function()
			if token ~= waitToken then return end
			waitingForHouseList = false
			local idx = idxRequested
			pendingHouseIndex = nil
			local g2 = SafeGetPlayerHouseGUIDs()
			local target = (type(idx) == "number" and type(g2) == "table") and g2[idx] or nil
			local hh = target and SafeGetHouseInfo(target) or nil
			if not hh then local owned = GetOwnedHouses() if owned and #owned > 0 then hh = owned[idx] end end
			if hh and hh.neighborhoodGUID then
				local neighborhoodName = tostring(hh.neighborhoodName or "")
				if neighborhoodName ~= "" then SyncMessageOnce("Housing synced: " .. neighborhoodName .. ". Click again.") else SyncMessageOnce("Housing synced. Click again.") end
			else
				ErrorMessage("House " .. tostring(idx or "?") .. " data missing. Click again.")
				if target ~= nil then RequestHouseData(target) end
			end
		end)
		if ok and C_Timer and C_Timer.NewTicker then
			local tries = 0
			local ticker
			ticker = C_Timer.NewTicker(0.25, function()
				if token ~= waitToken then if ticker and ticker.Cancel then ticker:Cancel() end return end
				tries = tries + 1
				RequestOwnedHousesRefresh()
				if C_Housing and C_Housing.GetPlayerOwnedHouses then pcall(C_Housing.GetPlayerOwnedHouses) end
				if C_Housing and type(C_Housing.GetPlayerHouseGUIDs) == "function" then pcall(C_Housing.GetPlayerHouseGUIDs) end
				local g2 = SafeGetPlayerHouseGUIDs()
				local target = (type(idxRequested) == "number" and type(g2) == "table") and g2[idxRequested] or nil
				local hh = target and SafeGetHouseInfo(target) or nil
				if not hh then local owned = GetOwnedHouses() if owned and #owned > 0 then hh = owned[idxRequested] end end
				if hh and hh.neighborhoodGUID then if ticker and ticker.Cancel then ticker:Cancel() end waitingForHouseList = false pendingHouseIndex = nil local neighborhoodName = tostring(hh.neighborhoodName or "") if neighborhoodName ~= "" then SyncMessageOnce("Housing synced: " .. neighborhoodName .. ". Click again.") else SyncMessageOnce("Housing synced. Click again.") end return end
				if target ~= nil then RequestHouseData(target) end
				if tries >= 12 then if ticker and ticker.Cancel then ticker:Cancel() end waitingForHouseList = false pendingHouseIndex = nil SyncMessageOnce("Housing data not updating... click again.") end
			end)
		end
		if not ok then
			waitingForHouseList = false
			pendingHouseIndex = nil
			if requested then SyncMessageOnce("Housing data syncing... click again.") else SyncMessageOnce("Loading houses... click again.") end
		end
		return
	end
	ns.PortToHouse = PortToHouse
end
```