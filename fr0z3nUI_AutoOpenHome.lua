local _, ns = ...

-- Home / Housing module.
-- UI is in fr0z3nUI_AutoOpenHomeUI.lua.

ns.Home = ns.Home or {}

local PREFIX = "|cff00ccff[FAO]|r "
local function Print(msg)
    print(PREFIX .. tostring(msg or ""))
end

local HOME_CLICK_BTN_1 = "FAO_HomeTeleport1"
local HOME_CLICK_BTN_2 = "FAO_HomeTeleport2"
local SAVED_CLICK_BTN_PREFIX = "FAO_TeleportButton"

local function GetHomeClickMacroBody(which)
    local name = (which == 2) and HOME_CLICK_BTN_2 or HOME_CLICK_BTN_1
    return "/click " .. name
end

local function GetSavedTeleportClickMacroBodyById(id)
    id = tonumber(id)
    if not id then
        return nil
    end
    return "/click " .. SAVED_CLICK_BTN_PREFIX .. tostring(id)
end

local ConfigureSavedTeleportClickButtonById
local ConfigureAllSavedTeleportButtons

local AttachAttemptTracking
local CaptureSavedTeleportFromCurrentHouse
local MoveSavedTeleportById

-- Home teleport engine (secure /click buttons + stale GUID retry).
do
    local function ErrorMessage(msg)
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage(tostring(msg or ""), 1, 0, 0)
        end
    end

    local _homeDiagSeq = 0
    local function SetHomeDiag(status, details)
        _homeDiagSeq = _homeDiagSeq + 1
        if not ns then
            return
        end
        local now = (GetTime and GetTime()) or 0
        local s = tostring(status or "")
        local d = tostring(details or "")
        if #d > 2000 then
            d = d:sub(1, 2000) .. "..."
        end
        ns._faoHomeDiag = {
            seq = _homeDiagSeq,
            time = now,
            status = s,
            details = d,
        }
    end

    local function SafePCall1(fn, ...)
        if type(fn) ~= "function" then
            return false, nil, "not a function"
        end
        local ok, a = pcall(fn, ...)
        if ok then
            return true, a, nil
        end
        return false, nil, a
    end

    local function HousingApiSummary()
        local ch = C_Housing
        if type(ch) ~= "table" then
            return "C_Housing=" .. tostring(ch)
        end
        local parts = {
            "GetPlayerOwnedHouses=" .. tostring(type(ch.GetPlayerOwnedHouses)),
            "GetPlayerHouseGUIDs=" .. tostring(type(ch.GetPlayerHouseGUIDs)),
            "GetHouseInfo=" .. tostring(type(ch.GetHouseInfo)),
            "RequestHouseData=" .. tostring(type(ch.RequestHouseData)),
            "RefreshPlayerOwnedHouses=" .. tostring(type(ch.RefreshPlayerOwnedHouses)),
            "RequestPlayerOwnedHouses=" .. tostring(type(ch.RequestPlayerOwnedHouses)),
        }
        return table.concat(parts, " ")
    end

    local function HousingKeySummary(limit)
        local ch = C_Housing
        if type(ch) ~= "table" then
            return "<no C_Housing table>"
        end
        limit = tonumber(limit) or 16
        if limit < 1 then limit = 1 end
        if limit > 30 then limit = 30 end
        local keys = {}
        for k in pairs(ch) do
            keys[#keys + 1] = tostring(k)
        end
        table.sort(keys)
        local out = {}
        for i = 1, math.min(limit, #keys) do
            local k = keys[i]
            local v = ch[k]
            out[#out + 1] = k .. ":" .. tostring(type(v))
        end
        return table.concat(out, " ")
    end

    local function HousingMatchKeys(patterns, limit)
        local ch = C_Housing
        if type(ch) ~= "table" then
            return "<no C_Housing table>"
        end
        if type(patterns) == "string" then
            patterns = { patterns }
        end
        if type(patterns) ~= "table" or #patterns == 0 then
            return "<no patterns>"
        end
        limit = tonumber(limit) or 24
        if limit < 1 then limit = 1 end
        if limit > 60 then limit = 60 end

        local keys = {}
        for k in pairs(ch) do
            keys[#keys + 1] = tostring(k)
        end
        table.sort(keys)

        local out = {}
        for i = 1, #keys do
            local k = keys[i]
            local kl = k:lower()
            local matched = false
            for j = 1, #patterns do
                local p = patterns[j]
                if type(p) == "string" and p ~= "" then
                    if kl:find(p:lower(), 1, true) then
                        matched = true
                        break
                    end
                end
            end
            if matched then
                out[#out + 1] = k .. ":" .. tostring(type(ch[k]))
                if #out >= limit then
                    break
                end
            end
        end

        if #out == 0 then
            return "<no matches>"
        end
        return table.concat(out, " ")
    end

    local function RequestHouseData(guid)
        if not C_Housing then
            return false
        end
        if type(C_Housing.RequestHouseData) ~= "function" then
            return false
        end
        if guid ~= nil then
            pcall(C_Housing.RequestHouseData, guid)
        else
            pcall(C_Housing.RequestHouseData)
        end
        return true
    end

    local function NormalizeGUIDList(raw)
        if type(raw) ~= "table" then
            return nil
        end
        if raw[1] ~= nil then
            return raw
        end
        local out = {}
        for _, v in pairs(raw) do
            if v ~= nil then
                out[#out + 1] = v
            end
        end
        if #out == 0 then
            return raw
        end
        table.sort(out, function(a, b)
            return tostring(a) < tostring(b)
        end)
        return out
    end

    local function SafeGetPlayerHouseGUIDs()
        if not (C_Housing and type(C_Housing.GetPlayerHouseGUIDs) == "function") then
            return nil
        end
        local ok, guids = pcall(C_Housing.GetPlayerHouseGUIDs)
        if not ok then
            return nil
        end
        return NormalizeGUIDList(guids)
    end

    local function SafeGetHouseInfo(houseGUID)
        if not (C_Housing and type(C_Housing.GetHouseInfo) == "function") then
            return nil
        end
        local ok, info = pcall(C_Housing.GetHouseInfo, houseGUID)
        if not ok then
            return nil
        end
        return info
    end

    local function RegisterOnceEvent(eventName, callback)
        if type(eventName) ~= "string" or type(callback) ~= "function" then
            return false
        end

        if EventUtil and type(EventUtil.RegisterOnceFrameEventAndCallback) == "function" then
            EventUtil.RegisterOnceFrameEventAndCallback(eventName, callback)
            return true
        end

        -- Fallback for builds without EventUtil.
        local f = CreateFrame("Frame")
        f:RegisterEvent(eventName)
        f:SetScript("OnEvent", function(self)
            self:UnregisterEvent(eventName)
            self:SetScript("OnEvent", nil)
            pcall(callback)
        end)
        return true
    end

    local function RegisterOnceAnyEvent(eventNames, callback)
        if type(callback) ~= "function" then
            return false
        end
        if type(eventNames) == "string" then
            eventNames = { eventNames }
        end
        if type(eventNames) ~= "table" or #eventNames == 0 then
            return false
        end
        local f = CreateFrame("Frame")
        local fired = false
        for i = 1, #eventNames do
            local ev = eventNames[i]
            if type(ev) == "string" and ev ~= "" then
                f:RegisterEvent(ev)
            end
        end
        f:SetScript("OnEvent", function(self, evName)
            if fired then
                return
            end
            fired = true
            for i = 1, #eventNames do
                local ev = eventNames[i]
                if type(ev) == "string" and ev ~= "" then
                    self:UnregisterEvent(ev)
                end
            end
            self:SetScript("OnEvent", nil)
            pcall(callback, evName)
        end)
        return true
    end

    local function RequestOwnedHousesRefresh()
        if not C_Housing then
            return false
        end

        -- 12.0.1+: some clients expose a refresh call; older builds used request.
        if type(C_Housing.RefreshPlayerOwnedHouses) == "function" then
            pcall(C_Housing.RefreshPlayerOwnedHouses)
            return true
        end
        if type(C_Housing.RequestPlayerOwnedHouses) == "function" then
            pcall(C_Housing.RequestPlayerOwnedHouses)
            return true
        end
        return false
    end

    local lastSyncMessageAt = 0
    local function SyncMessageOnce(msg)
        local now = (GetTime and GetTime()) or 0
        if now > 0 and (now - lastSyncMessageAt) < 1.0 then
            return
        end
        lastSyncMessageAt = now
        ErrorMessage(msg)
    end

    local function DebugPrintOwnedHouses(prefix, raw)
        local pfx = tostring(prefix or "[Home]")
        if type(raw) ~= "table" then
            Print(pfx .. " owned houses: <" .. tostring(type(raw)) .. ">")
            return
        end
        local n = 0
        for _ in pairs(raw) do n = n + 1 end
        local firstKey
        for k in pairs(raw) do firstKey = k break end
        Print(pfx .. " owned houses table keys=" .. tostring(n) .. " firstKey=" .. tostring(firstKey))
        if raw[1] and type(raw[1]) == "table" then
            local h1 = raw[1]
            Print(pfx .. " [1] neighborhoodName=" .. tostring(h1.neighborhoodName or h1.neighborhood or "") .. " plotID=" .. tostring(h1.plotID))
        end
        if raw[2] and type(raw[2]) == "table" then
            local h2 = raw[2]
            Print(pfx .. " [2] neighborhoodName=" .. tostring(h2.neighborhoodName or h2.neighborhood or "") .. " plotID=" .. tostring(h2.plotID))
        end
    end

    local function NormalizeOwnedHouses(raw)
        if type(raw) ~= "table" then
            return {}
        end

        -- Common shapes: array, or wrapper fields.
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

        -- Fallback: numeric-keyed table.
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

        -- Last resort: collect plausible entries (order unknown).
        local out = {}
        for _, v in pairs(raw) do
            if type(v) == "table" and (v.houseGUID ~= nil or v.neighborhoodGUID ~= nil or v.plotID ~= nil) then
                out[#out + 1] = v
            end
        end

        -- 12.0.1 fix: owned houses may be returned as a GUID->data map, so impose
        -- a stable order for index-based access (home1/home2) by plotID.
        table.sort(out, function(a, b)
            local ap = tonumber(a and a.plotID) or math.huge
            local bp = tonumber(b and b.plotID) or math.huge
            if ap ~= bp then
                return ap < bp
            end

            local an = tostring(a and (a.neighborhoodName or a.neighborhoodGUID or a.houseGUID) or "")
            local bn = tostring(b and (b.neighborhoodName or b.neighborhoodGUID or b.houseGUID) or "")
            return an < bn
        end)
        return out
    end

    local function GetOwnedHouses()
        if not (C_Housing and C_Housing.GetPlayerOwnedHouses) then
            return {}
        end
        local ok, houses = pcall(C_Housing.GetPlayerOwnedHouses)
        if not ok then
            return {}
        end
        return NormalizeOwnedHouses(houses)
    end

    local function GetHouseInfoByIndex(index)
        local guids = SafeGetPlayerHouseGUIDs()
        if type(guids) ~= "table" or #guids == 0 then
            return nil, "noguids"
        end

        local infos = {}
        for i = 1, #guids do
            local guid = guids[i]
            if guid ~= nil then
                local info = SafeGetHouseInfo(guid)
                if type(info) == "table" then
                    infos[#infos + 1] = info
                end
            end
        end

        if #infos == 0 then
            return nil, "noinfo"
        end

        table.sort(infos, function(a, b)
            local ap = tonumber(a and a.plotID) or math.huge
            local bp = tonumber(b and b.plotID) or math.huge
            if ap ~= bp then
                return ap < bp
            end

            local an = tostring(a and (a.neighborhoodName or a.neighborhoodGUID or a.houseGUID) or "")
            local bn = tostring(b and (b.neighborhoodName or b.neighborhoodGUID or b.houseGUID) or "")
            return an < bn
        end)

        return infos[index], "guidinfo"
    end

    local pendingHouseIndex
    local waitingForHouseList = false
    local waitToken = 0
    local pollTicker

    local function CancelPollTicker()
        if pollTicker and type(pollTicker.Cancel) == "function" then
            pollTicker:Cancel()
        end
        pollTicker = nil
    end

    local function TryResolveHouseByIndex(idx)
        if type(idx) ~= "number" then
            return nil, nil
        end

        local guids = SafeGetPlayerHouseGUIDs()
        local targetGUID = (type(guids) == "table") and guids[idx] or nil
        if targetGUID ~= nil then
            local info = SafeGetHouseInfo(targetGUID)
            if type(info) == "table" then
                return info, targetGUID
            end
        end

        local owned = GetOwnedHouses()
        if type(owned) == "table" and #owned > 0 then
            local h = owned[idx]
            if type(h) == "table" then
                return h, targetGUID
            end
        end

        local h = (select(1, GetHouseInfoByIndex(idx)))
        if type(h) == "table" then
            return h, targetGUID
        end

        return nil, targetGUID
    end

    local function SummarizeHouse(h)
        if type(h) ~= "table" then
            return "<" .. tostring(type(h)) .. ">"
        end
        local n = h.neighborhoodGUID
        local hg = h.houseGUID
        local p = h.plotID
        local name = h.neighborhoodName
        local keyCount = 0
        local keys = {}
        for k in pairs(h) do
            keyCount = keyCount + 1
            if #keys < 8 then
                keys[#keys + 1] = tostring(k)
            end
        end
        table.sort(keys)
        return "name=" .. tostring(name) .. " n=" .. tostring(n) .. " h=" .. tostring(hg) .. " p=" .. tostring(p) .. " keys=" .. tostring(keyCount) .. " [" .. table.concat(keys, ",") .. "]"
    end

    local function StartHousePoll(token, idxRequested)
        CancelPollTicker()
        SetHomeDiag("polling", "idx=" .. tostring(idxRequested))

        local tries = 0
        local maxTries = 12 -- ~3s @ 0.25s
        if not (C_Timer and C_Timer.NewTicker) then
            return false
        end

        pollTicker = C_Timer.NewTicker(0.25, function()
            if token ~= waitToken then
                CancelPollTicker()
                return
            end

            tries = tries + 1

            -- Poke caches; some builds only update after reads.
            RequestOwnedHousesRefresh()
            local ownedOk, ownedRaw = false, nil
            if C_Housing and C_Housing.GetPlayerOwnedHouses then
                ownedOk, ownedRaw = pcall(C_Housing.GetPlayerOwnedHouses)
            end
            if C_Housing and type(C_Housing.GetPlayerHouseGUIDs) == "function" then
                pcall(C_Housing.GetPlayerHouseGUIDs)
            end

            if ownedOk and ownedRaw == nil and tries >= 2 then
                -- API present but returning nil consistently: likely feature gated / not initialized yet.
                waitingForHouseList = false
                pendingHouseIndex = nil
                CancelPollTicker()
                SetHomeDiag(
                    "api_nil",
                    "GetPlayerOwnedHouses returned nil; "
                        .. HousingApiSummary()
                        .. " keys{" .. HousingKeySummary(30) .. "}"
                        .. " match{" .. HousingMatchKeys({ "owned", "player", "house", "plot", "neighborhood", "request", "refresh", "guid" }, 40) .. "}"
                )
                SyncMessageOnce("Housing not initialized. Enter your plot once, then try again.")
                return
            end

            local hh, targetGUID = TryResolveHouseByIndex(idxRequested)
            if hh and hh.neighborhoodGUID then
                waitingForHouseList = false
                pendingHouseIndex = nil
                CancelPollTicker()

                local neighborhoodName = tostring(hh.neighborhoodName or "")
                if neighborhoodName ~= "" then
                    SyncMessageOnce("Housing synced: " .. neighborhoodName .. ". Click again.")
                    SetHomeDiag("synced", "poll:" .. neighborhoodName)
                else
                    SyncMessageOnce("Housing synced. Click again.")
                    SetHomeDiag("synced", "poll:<no name>")
                end
                return
            end

            if targetGUID ~= nil then
                RequestHouseData(targetGUID)
            end

            if tries >= maxTries then
                waitingForHouseList = false
                pendingHouseIndex = nil
                CancelPollTicker()

                local guids = SafeGetPlayerHouseGUIDs()
                local guidCount = (type(guids) == "table") and #guids or 0
                local owned = GetOwnedHouses()
                local ownedCount = (type(owned) == "table") and #owned or 0
                local sample = hh or ((type(owned) == "table") and owned[idxRequested]) or nil

                local ch = C_Housing
                local okOwned, ownedRaw, errOwned = SafePCall1(ch and ch.GetPlayerOwnedHouses)
                local okGuids, guidsRaw, errGuids = SafePCall1(ch and ch.GetPlayerHouseGUIDs)
                local ownedRawType = tostring(type(ownedRaw))
                local guidsRawType = tostring(type(guidsRaw))
                local ownedKeys = 0
                if type(ownedRaw) == "table" then
                    for _ in pairs(ownedRaw) do ownedKeys = ownedKeys + 1 end
                end
                local guidsKeys = 0
                if type(guidsRaw) == "table" then
                    for _ in pairs(guidsRaw) do guidsKeys = guidsKeys + 1 end
                end

                local extra = " api{" .. HousingApiSummary() .. "}"
                    .. " ownedRaw{" .. tostring(okOwned) .. ":" .. ownedRawType .. ":keys=" .. tostring(ownedKeys) .. (errOwned and (":err=" .. tostring(errOwned)) or "") .. "}"
                    .. " guidsRaw{" .. tostring(okGuids) .. ":" .. guidsRawType .. ":keys=" .. tostring(guidsKeys) .. (errGuids and (":err=" .. tostring(errGuids)) or "") .. "}"
                    .. " keys{" .. HousingKeySummary(30) .. "}"
                    .. " match{" .. HousingMatchKeys({ "owned", "player", "house", "plot", "neighborhood", "request", "refresh", "guid" }, 40) .. "}"

                SetHomeDiag(
                    "timeout",
                    "poll timeout idx=" .. tostring(idxRequested)
                        .. " guids=" .. tostring(guidCount)
                        .. " owned=" .. tostring(ownedCount)
                        .. " sample=" .. SummarizeHouse(sample)
                        .. extra
                )
                SyncMessageOnce("Housing data not updating... click again.")
            end
        end)

        return true
    end

    -- Cache warm: GetPlayerOwnedHouses() often populates asynchronously.
    local function GetHomeTeleportSV()
        _G.fr0z3nUI_AutoOpen_CharSettings = _G.fr0z3nUI_AutoOpen_CharSettings or {}
        local cs = _G.fr0z3nUI_AutoOpen_CharSettings
        if type(cs.faoHomeTeleports) ~= "table" then
            cs.faoHomeTeleports = {}
        end
        return cs.faoHomeTeleports
    end

    local function GetSavedTeleportsSV()
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

    local _savedPendingCombat = false
    local function MarkSavedPendingCombat()
        _savedPendingCombat = true
    end

    local function EnsureHomeClickButton(which)
        if type(CreateFrame) ~= "function" then
            return nil
        end
        local name = (which == 2) and HOME_CLICK_BTN_2 or HOME_CLICK_BTN_1
        local b = _G[name]
        if not b then
            b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
            if b and b.Hide then
                b:Hide()
            end
        end
        if b and b.SetAttribute then
            b:SetAttribute("type", "teleporthome")
        end

        -- Track attempts for stale GUID retry (MHT-style)
        b._faoTeleportKind = "home"
        b._faoTeleportWhich = which

        if AttachAttemptTracking then
            AttachAttemptTracking(b)
        end
        return b
    end

    local function ConfigureHomeClickButton(which)
        if InCombatLockdown and InCombatLockdown() then
            MarkSavedPendingCombat()
            return false
        end

        local b = EnsureHomeClickButton(which)
        if not b then
            return false
        end

        local sv = GetHomeTeleportSV()
        local info = (type(sv) == "table") and sv[which] or nil
        if type(info) ~= "table" then
            if b.SetAttribute then
                b:SetAttribute("house-neighborhood-guid", nil)
                b:SetAttribute("house-guid", nil)
                b:SetAttribute("house-plot-id", nil)
            end
            return true
        end

        if b.SetAttribute then
            b:SetAttribute("house-neighborhood-guid", info.neighborhoodGUID)
            b:SetAttribute("house-guid", info.houseGUID)
            b:SetAttribute("house-plot-id", info.plotID)
        end

        return true
    end

    local function EnsureSavedTeleportClickButton(id)
        if type(CreateFrame) ~= "function" then
            return nil
        end
        id = tonumber(id)
        if not id then
            return nil
        end
        local name = SAVED_CLICK_BTN_PREFIX .. tostring(id)
        local b = _G[name]
        if not b then
            b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
            if b and b.Hide then
                b:Hide()
            end
        end
        if b and b.SetAttribute then
            b:SetAttribute("type", "teleporthome")
        end

        -- Track attempts for stale GUID retry (MHT-style)
        b._faoTeleportKind = "saved"
        b._faoTeleportId = id

        if AttachAttemptTracking then
            AttachAttemptTracking(b)
        end
        return b
    end

    ConfigureSavedTeleportClickButtonById = function(id)
        if InCombatLockdown and InCombatLockdown() then
            MarkSavedPendingCombat()
            return false
        end

        local db = GetSavedTeleportsSV()
        local list = db and db.list
        if type(list) ~= "table" then
            return false
        end

        id = tonumber(id)
        if not id then
            return false
        end

        local entry
        for i = 1, #list do
            local e = list[i]
            if type(e) == "table" and tonumber(e.id) == id then
                entry = e
                break
            end
        end

        local b = EnsureSavedTeleportClickButton(id)
        if not b or not b.SetAttribute then
            return false
        end

        if type(entry) ~= "table" then
            b:SetAttribute("house-neighborhood-guid", nil)
            b:SetAttribute("house-guid", nil)
            b:SetAttribute("house-plot-id", nil)
            return true
        end

        b:SetAttribute("house-neighborhood-guid", entry.neighborhoodGUID)
        b:SetAttribute("house-guid", entry.houseGUID)
        b:SetAttribute("house-plot-id", entry.plotID)
        return true
    end

    ConfigureAllSavedTeleportButtons = function()
        local db = GetSavedTeleportsSV()
        local list = db and db.list
        if type(list) ~= "table" then
            return false
        end
        for i = 1, #list do
            local e = list[i]
            if type(e) == "table" and e.id ~= nil then
                ConfigureSavedTeleportClickButtonById(e.id)
            end
        end
        return true
    end

    ---------------------------------------------------------------------------
    -- Stale GUID Auto-Refresh + Smart Retry (ported from MHT)
    ---------------------------------------------------------------------------

    local lastTeleportAttempt = nil -- { kind = 'home'|'saved', which|id, time = GetTime() }
    local teleportAttemptCount = 0
    local RETRY_WINDOW = 1.5

    local STALE_GUID_ERRORS = {}
    local function BuildStaleErrorSet()
        local keys = {
            "ERR_HOUSING_RESULT_PERMISSION_DENIED",
            "ERR_HOUSING_RESULT_HOUSE_NOT_FOUND",
            "ERR_HOUSING_RESULT_INVALID_HOUSE",
        }
        for _, key in ipairs(keys) do
            local text = _G and _G[key] or nil
            if text then
                STALE_GUID_ERRORS[text] = true
            end
        end
    end

    local function NotifyRetry(msg)
        if UIErrorsFrame and UIErrorsFrame.TryDisplayMessage then
            UIErrorsFrame:TryDisplayMessage(0, tostring(msg or ""), 1.0, 0.82, 0.0)
        end
    end

    local function DescribeAttempt(attempt)
        if type(attempt) ~= "table" then
            return nil
        end

        if attempt.kind == "home" then
            local which = tonumber(attempt.which) or 1
            local sv = GetHomeTeleportSV()
            local h = sv and sv[which] or nil
            if type(h) == "table" then
                local n = tostring(h.neighborhoodName or "")
                if n ~= "" then
                    return n
                end
            end
            return "Home " .. tostring(which)
        end

        if attempt.kind == "saved" then
            local id = tonumber(attempt.id)
            local db = GetSavedTeleportsSV()
            local list = db and db.list
            if type(list) == "table" and id then
                for i = 1, #list do
                    local e = list[i]
                    if type(e) == "table" and tonumber(e.id) == id then
                        local n = tostring(e.name or "")
                        if n ~= "" then
                            return n
                        end
                        break
                    end
                end
            end
            if id then
                return "Saved " .. tostring(id)
            end
            return "Saved"
        end

        return nil
    end

    local function CheckTeleportCooldown()
        if not (C_Housing and type(C_Housing.GetVisitCooldownInfo) == "function") then
            return false
        end
        local ok, cooldownInfo = pcall(C_Housing.GetVisitCooldownInfo)
        if not ok or type(cooldownInfo) ~= "table" then
            return false
        end
        if not cooldownInfo.isEnabled then
            return false
        end
        local remaining = ((cooldownInfo.startTime or 0) + (cooldownInfo.duration or 0)) - ((GetTime and GetTime()) or 0)
        if remaining > 1 then
            local timeString = SecondsToTime(remaining, false, true)
            if UIErrorsFrame and UIErrorsFrame.TryDisplayMessage and ITEM_COOLDOWN_TIME then
                UIErrorsFrame:TryDisplayMessage(0, ITEM_COOLDOWN_TIME:format("|cFFFFFFFF" .. timeString .. "|r"), 0.53, 0.67, 1.0)
            elseif UIErrorsFrame and UIErrorsFrame.AddMessage then
                UIErrorsFrame:AddMessage("Cooldown: " .. tostring(timeString), 0.53, 0.67, 1.0)
            end
            return true
        end
        return false
    end

    local function IncrementHouseGUID(guid)
        if type(guid) ~= "string" or guid == "" then
            return nil
        end
        local prefix, num = guid:match("^(.+-)(%d+)$")
        if prefix and num then
            local nextNum = (tonumber(num) % 9) + 1
            return prefix .. nextNum
        end
        return nil
    end

    local function RefreshExistingGUIDsFromHouseInfo(info)
        if type(info) ~= "table" then
            return
        end
        if info.neighborhoodGUID == nil or info.houseGUID == nil or info.plotID == nil then
            return
        end

        -- Update existing home slots that match neighborhoodGUID+plotID.
        local hsv = GetHomeTeleportSV()
        for which = 1, 2 do
            local h = hsv and hsv[which] or nil
            if type(h) == "table" and h.neighborhoodGUID == info.neighborhoodGUID and h.plotID == info.plotID then
                if h.houseGUID ~= info.houseGUID then
                    h.houseGUID = info.houseGUID
                    if type(info.neighborhoodName) == "string" and info.neighborhoodName ~= "" then
                        h.neighborhoodName = info.neighborhoodName
                    end
                    ConfigureHomeClickButton(which)
                end
            end
        end

        -- Update saved teleports that match neighborhoodGUID+plotID.
        local db = GetSavedTeleportsSV()
        local list = db and db.list
        if type(list) == "table" then
            for i = 1, #list do
                local e = list[i]
                if type(e) == "table" and e.neighborhoodGUID == info.neighborhoodGUID and e.plotID == info.plotID then
                    if e.houseGUID ~= info.houseGUID then
                        e.houseGUID = info.houseGUID
                        if type(info.neighborhoodName) == "string" and info.neighborhoodName ~= "" then
                            e.neighborhoodName = info.neighborhoodName
                        end
                        ConfigureSavedTeleportClickButtonById(e.id)
                    end
                end
            end
        end
    end

    local function OnTeleportError(attempt)
        if type(attempt) ~= "table" then
            return
        end

        if attempt.kind == "home" then
            local which = attempt.which
            local sv = GetHomeTeleportSV()
            local h = sv and sv[which] or nil
            if type(h) ~= "table" or type(h.houseGUID) ~= "string" then
                return
            end
            local newGUID = IncrementHouseGUID(h.houseGUID)
            if not newGUID then
                return
            end
            h.houseGUID = newGUID
            ConfigureHomeClickButton(which)
            NotifyRetry("Home ID updated - press again (" .. tostring(teleportAttemptCount) .. "/9)")
            return
        end

        if attempt.kind == "saved" then
            local id = attempt.id
            local db = GetSavedTeleportsSV()
            local list = db and db.list
            if type(list) ~= "table" then
                return
            end
            for i = 1, #list do
                local e = list[i]
                if type(e) == "table" and tonumber(e.id) == tonumber(id) and type(e.houseGUID) == "string" then
                    local newGUID = IncrementHouseGUID(e.houseGUID)
                    if not newGUID then
                        return
                    end
                    e.houseGUID = newGUID
                    ConfigureSavedTeleportClickButtonById(e.id)
                    NotifyRetry("Teleport ID updated - press again (" .. tostring(teleportAttemptCount) .. "/9)")
                    return
                end
            end
        end
    end

    AttachAttemptTracking = function(btn)
        if not (btn and btn.SetScript) then
            return
        end
        if btn._faoAttemptTrackingAttached then
            return
        end
        btn._faoAttemptTrackingAttached = true
        btn:SetScript("PostClick", function(self)
            -- If we're on visit cooldown, don't treat this click as a stale GUID attempt.
            if CheckTeleportCooldown() then
                lastTeleportAttempt = nil
                teleportAttemptCount = 0
                return
            end

            teleportAttemptCount = teleportAttemptCount + 1
            local attempt = { time = GetTime and GetTime() or 0 }
            if self._faoTeleportKind == "home" then
                attempt.kind = "home"
                attempt.which = tonumber(self._faoTeleportWhich) or 1
            elseif self._faoTeleportKind == "saved" then
                attempt.kind = "saved"
                attempt.id = tonumber(self._faoTeleportId)
            end
            attempt.displayName = DescribeAttempt(attempt)
            lastTeleportAttempt = attempt

            if attempt.displayName then
                Print("Teleporting to: " .. tostring(attempt.displayName))
            end

            if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
                local attemptInfo = attempt
                C_Timer.After(RETRY_WINDOW + 0.5, function()
                    if lastTeleportAttempt == attemptInfo then
                        lastTeleportAttempt = nil
                        if teleportAttemptCount > 1 and attemptInfo.displayName then
                            Print("Found ID for: " .. tostring(attemptInfo.displayName) .. ", teleport should now work during this session.")
                        end
                        teleportAttemptCount = 0
                    end
                end)
            end
        end)
    end

    do
        local stale = CreateFrame("Frame")

        local function SafeRegisterEvent(frame, evName)
            if not (frame and frame.RegisterEvent) then
                return
            end
            if type(evName) ~= "string" or evName == "" then
                return
            end
            pcall(frame.RegisterEvent, frame, evName)
        end

        stale:RegisterEvent("PLAYER_LOGIN")
        stale:RegisterEvent("UI_ERROR_MESSAGE")
        stale:RegisterEvent("CURRENT_HOUSE_INFO_UPDATED")
        stale:RegisterEvent("CURRENT_HOUSE_INFO_RECIEVED")
        SafeRegisterEvent(stale, "CURRENT_HOUSE_INFO_RECEIVED")
        stale:SetScript("OnEvent", function(_, event, ...)
            if event == "PLAYER_LOGIN" then
                BuildStaleErrorSet()
                return
            end

            if event == "UI_ERROR_MESSAGE" then
                local _, message = ...
                if not lastTeleportAttempt then
                    return
                end
                if (GetTime and (GetTime() - (lastTeleportAttempt.time or 0)) or 0) > RETRY_WINDOW then
                    lastTeleportAttempt = nil
                    teleportAttemptCount = 0
                    return
                end
                if message and STALE_GUID_ERRORS[message] then
                    OnTeleportError(lastTeleportAttempt)
                    lastTeleportAttempt = nil
                end
                return
            end

            if event == "CURRENT_HOUSE_INFO_UPDATED" or event == "CURRENT_HOUSE_INFO_RECIEVED" or event == "CURRENT_HOUSE_INFO_RECEIVED" then
                if C_Housing and type(C_Housing.GetCurrentHouseInfo) == "function" then
                    local ok, info = pcall(C_Housing.GetCurrentHouseInfo)
                    if ok and type(info) == "table" then
                        RefreshExistingGUIDsFromHouseInfo(info)
                    end
                end
            end
        end)
    end

    local function CaptureCurrentHouseInfoToSV()
        if not (C_Housing and type(C_Housing.GetCurrentHouseInfo) == "function") then
            return false
        end

        local ok, info = pcall(C_Housing.GetCurrentHouseInfo)
        if not ok or type(info) ~= "table" then
            return false
        end

        local neighborhoodGUID = info.neighborhoodGUID
        local houseGUID = info.houseGUID
        local plotID = info.plotID
        if neighborhoodGUID == nil or houseGUID == nil or plotID == nil then
            return false
        end

        local neighborhoodName = info.neighborhoodName or info["neighborhood"]
        if type(neighborhoodName) ~= "string" then
            neighborhoodName = ""
        end

        local function GuessSlot()
            if neighborhoodName == "Founder's Point" then
                return 1
            end
            if neighborhoodName == "Razorwind Shores" then
                return 2
            end

            local sv = GetHomeTeleportSV()
            for i = 1, 2 do
                local existing = sv[i]
                if type(existing) == "table" then
                    if existing.neighborhoodGUID == neighborhoodGUID and existing.houseGUID == houseGUID and existing.plotID == plotID then
                        return i
                    end
                end
            end
            if type(sv[1]) ~= "table" then
                return 1
            end
            if type(sv[2]) ~= "table" then
                return 2
            end
            return 1
        end

        local which = GuessSlot()
        local sv = GetHomeTeleportSV()
        sv[which] = {
            neighborhoodGUID = neighborhoodGUID,
            houseGUID = houseGUID,
            plotID = plotID,
            neighborhoodName = neighborhoodName,
        }

        ConfigureHomeClickButton(1)
        ConfigureHomeClickButton(2)

        SetHomeDiag(
            "captured",
            "slot=" .. tostring(which)
                .. " n=" .. tostring(neighborhoodName)
                .. " ng=" .. tostring(neighborhoodGUID)
                .. " hg=" .. tostring(houseGUID)
                .. " p=" .. tostring(plotID)
        )
        return true
    end

    CaptureSavedTeleportFromCurrentHouse = function(name)
        if not (C_Housing and type(C_Housing.GetCurrentHouseInfo) == "function") then
            return false, nil, "C_Housing.GetCurrentHouseInfo unavailable"
        end
        local ok, info = pcall(C_Housing.GetCurrentHouseInfo)
        if not ok or type(info) ~= "table" then
            return false, nil, "GetCurrentHouseInfo failed"
        end

        local neighborhoodGUID = info.neighborhoodGUID
        local houseGUID = info.houseGUID
        local plotID = info.plotID
        if neighborhoodGUID == nil or houseGUID == nil or plotID == nil then
            return false, nil, "Missing house info"
        end

        local desiredName = tostring(name or "")
        desiredName = desiredName:gsub("^%s+", ""):gsub("%s+$", "")
        if desiredName == "" then
            desiredName = tostring(info["plotName"] or info["ownerName"] or info.neighborhoodName or ("Plot " .. tostring(plotID)))
        end

        local neighborhoodName = tostring(info.neighborhoodName or info["neighborhood"] or "")

        local db = GetSavedTeleportsSV()
        local list = db and db.list
        if type(list) ~= "table" then
            return false, nil, "Saved DB unavailable"
        end

        for i = 1, #list do
            local e = list[i]
            if type(e) == "table" and e.neighborhoodGUID == neighborhoodGUID and e.plotID == plotID then
                e.houseGUID = houseGUID
                e.neighborhoodName = neighborhoodName
                e.name = desiredName
                if ConfigureSavedTeleportClickButtonById then
                    ConfigureSavedTeleportClickButtonById(e.id)
                end
                return true, tonumber(e.id), "updated"
            end
        end

        local id = tonumber(db.nextId) or 1
        db.nextId = id + 1
        local entry = {
            id = id,
            name = desiredName,
            neighborhoodGUID = neighborhoodGUID,
            houseGUID = houseGUID,
            plotID = plotID,
            neighborhoodName = neighborhoodName,
        }
        list[#list + 1] = entry

        if ConfigureSavedTeleportClickButtonById then
            ConfigureSavedTeleportClickButtonById(id)
        end
        return true, id, "created"
    end

    MoveSavedTeleportById = function(id, delta)
        id = tonumber(id)
        delta = tonumber(delta) or 0
        if not id or delta == 0 then
            return false, nil, "bad args"
        end

        local db = GetSavedTeleportsSV()
        local list = db and db.list
        if type(list) ~= "table" then
            return false, nil, "db missing"
        end

        local idx
        for i = 1, #list do
            local e = list[i]
            if type(e) == "table" and tonumber(e.id) == id then
                idx = i
                break
            end
        end
        if not idx then
            return false, nil, "not found"
        end

        local newIdx = idx + (delta < 0 and -1 or 1)
        if newIdx < 1 or newIdx > #list then
            return false, idx, "edge"
        end

        list[idx], list[newIdx] = list[newIdx], list[idx]
        return true, newIdx, "moved"
    end

    do
        local function SafeRegisterEvent(frame, evName)
            if not (frame and frame.RegisterEvent and evName) then
                return
            end
            pcall(frame.RegisterEvent, frame, evName)
        end

        local regen = CreateFrame("Frame")
        regen:RegisterEvent("PLAYER_REGEN_ENABLED")
        regen:SetScript("OnEvent", function()
            if not _savedPendingCombat then
                return
            end
            _savedPendingCombat = false
            ConfigureHomeClickButton(1)
            ConfigureHomeClickButton(2)
            ConfigureAllSavedTeleportButtons()
        end)

        local warm = CreateFrame("Frame")
        warm:RegisterEvent("PLAYER_LOGIN")
        warm:RegisterEvent("PLAYER_ENTERING_WORLD")
        warm:RegisterEvent("HOUSE_PLOT_ENTERED")
        SafeRegisterEvent(warm, "CURRENT_HOUSE_INFO_UPDATED")
        SafeRegisterEvent(warm, "CURRENT_HOUSE_INFO_RECIEVED")
        SafeRegisterEvent(warm, "CURRENT_HOUSE_INFO_RECEIVED")
        warm:SetScript("OnEvent", function()
            if C_Housing and C_Housing.GetPlayerOwnedHouses then
                pcall(C_Housing.GetPlayerOwnedHouses)
            end
            RequestOwnedHousesRefresh()
            -- 12.0.1+ handshake: pull GUIDs into cache if available.
            if C_Housing and type(C_Housing.GetPlayerHouseGUIDs) == "function" then
                pcall(C_Housing.GetPlayerHouseGUIDs)
            end

            ConfigureHomeClickButton(1)
            ConfigureHomeClickButton(2)
            ConfigureAllSavedTeleportButtons()

            -- Attach stale-retry attempt tracking to all buttons we manage.
            AttachAttemptTracking(_G[HOME_CLICK_BTN_1])
            AttachAttemptTracking(_G[HOME_CLICK_BTN_2])
            do
                local db = GetSavedTeleportsSV()
                local list = db and db.list
                if type(list) == "table" then
                    for i = 1, #list do
                        local e = list[i]
                        if type(e) == "table" and e.id ~= nil then
                            local b = _G[SAVED_CLICK_BTN_PREFIX .. tostring(tonumber(e.id) or "")]
                            AttachAttemptTracking(b)
                        end
                    end
                end
            end

            -- If we're currently in a house, refresh stale GUIDs for existing entries.
            if C_Housing and type(C_Housing.GetCurrentHouseInfo) == "function" then
                local ok, info = pcall(C_Housing.GetCurrentHouseInfo)
                if ok and type(info) == "table" then
                    RefreshExistingGUIDsFromHouseInfo(info)
                end
            end
        end)
    end

    -- (Legacy /fao home1/home2 porting code removed.)
end

ns.Home.Print = Print
ns.Home.GetHomeClickMacroBody = GetHomeClickMacroBody
ns.Home.GetSavedTeleportClickMacroBodyById = GetSavedTeleportClickMacroBodyById
ns.Home.ConfigureSavedTeleportClickButtonById = ConfigureSavedTeleportClickButtonById
ns.Home.ConfigureAllSavedTeleportButtons = ConfigureAllSavedTeleportButtons
ns.Home.CaptureSavedTeleportFromCurrentHouse = CaptureSavedTeleportFromCurrentHouse
ns.Home.MoveSavedTeleportById = MoveSavedTeleportById

local function Trim(s)
	s = tostring(s or "")
	return s:gsub("^%s+", ""):gsub("%s+$", "")
end

-- Slash handler: /fao hm ...
function ns.Home.HandleHM(sub, subarg)
	sub = tostring(sub or ""):lower()
	subarg = tostring(subarg or "")

	local function HMHelp()
		print("|cff00ccff[FAO]|r Housing commands:")
		print("|cff00ccff[FAO]|r /fao hm list")
		print("|cff00ccff[FAO]|r /fao hm add [name]")
		print("|cff00ccff[FAO]|r /fao hm up <id>")
		print("|cff00ccff[FAO]|r /fao hm down <id>")
		print("|cff00ccff[FAO]|r /fao hm macro <id>")
		print("|cff00ccff[FAO]|r Note: secure teleports require a macro (/click).")
	end

	if sub == "" or sub == "help" or sub == "?" then
		HMHelp()
		return true
	end

	if sub == "list" then
		local cs = _G.fr0z3nUI_AutoOpen_CharSettings
		local db = cs and cs.faoSavedTeleports
		local list = db and db.list
		if type(list) ~= "table" or #list == 0 then
			print("|cff00ccff[FAO]|r No saved locations.")
			return true
		end
		print("|cff00ccff[FAO]|r Saved locations:")
		for i = 1, #list do
			local e = list[i]
			if type(e) == "table" then
				local id = tonumber(e.id)
				local n = tostring(e.name or "")
				local hood = tostring(e.neighborhoodName or "")
				if hood ~= "" then
					print("|cff00ccff[FAO]|r " .. tostring(id or "?") .. ". " .. n .. " |cFF888888(" .. hood .. ")|r")
				else
					print("|cff00ccff[FAO]|r " .. tostring(id or "?") .. ". " .. n)
				end
			end
		end
		print("|cff00ccff[FAO]|r Tip: /fao hm macro <id>")
		return true
	end

	if sub == "add" then
		local ok, id, mode = ns.Home.CaptureSavedTeleportFromCurrentHouse(subarg)
		if not ok then
			print("|cff00ccff[FAO]|r Unable to add current location.")
			return true
		end
		print("|cff00ccff[FAO]|r Saved location " .. tostring(id) .. " (" .. tostring(mode or "") .. ")")
		print("|cff00ccff[FAO]|r Macro body: |cFFFFCC00" .. tostring(ns.Home.GetSavedTeleportClickMacroBodyById and ns.Home.GetSavedTeleportClickMacroBodyById(id) or "") .. "|r")
		return true
	end

	if sub == "macro" then
		local token = Trim(subarg)
		if token == "" then
			HMHelp()
			return true
		end

		local id = tonumber(token)
		if not id then
			print("|cff00ccff[FAO]|r Usage: /fao hm macro <id>")
			return true
		end
		local body = ns.Home.GetSavedTeleportClickMacroBodyById and ns.Home.GetSavedTeleportClickMacroBodyById(id) or nil
		if not body then
			print("|cff00ccff[FAO]|r Unknown saved location id: " .. tostring(id))
			return true
		end
		print("|cff00ccff[FAO]|r Saved " .. tostring(id) .. " macro body: |cFFFFCC00" .. tostring(body) .. "|r")
		return true
	end

	if sub == "up" or sub == "down" then
		local id = tonumber(subarg)
		if not id then
			print("|cff00ccff[FAO]|r Usage: /fao hm " .. sub .. " <id>")
			return true
		end
		local delta = (sub == "up") and -1 or 1
		local ok, newIndex, why = ns.Home.MoveSavedTeleportById(id, delta)
		if ok then
			print("|cff00ccff[FAO]|r Moved " .. tostring(id) .. " to position " .. tostring(newIndex))
		else
			if why == "edge" then
				print("|cff00ccff[FAO]|r Already at edge")
			else
				print("|cff00ccff[FAO]|r Could not move: " .. tostring(why or ""))
			end
		end
		return true
	end

	HMHelp()
	return true
end
