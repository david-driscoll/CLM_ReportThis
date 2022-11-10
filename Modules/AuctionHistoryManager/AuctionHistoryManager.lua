-- ------------------------------- --
local CLM       = LibStub("ClassicLootManager").CLM
-- ------ CLM common cache ------- --
local LOG       = CLM.LOG
local CONSTANTS = CLM.CONSTANTS
local UTILS     = CLM.UTILS
-- ------------------------------- --

local pairs, ipairs = pairs, ipairs
local tinsert, tremove = table.insert, table.remove
local tostring, tonumber = tostring, tonumber
local GetServerTime = GetServerTime
local ConfigLedgerManager = CLM.MODULES.ReportThisConfigLedgerManager
local AuctionHistoryEntry = CLM.MODELS.LEDGER.REPORTTHIS.AUCTION.AuctionHistoryEntry

-- ConfigLedgerManager:Submit(LEDGER_REPORTTHIS_ROSTER.UpdateConfigSingle:new(roster:UID(), option, value), true)

local EVENT_END_AUCTION = "CLM_AUCTION_END" -- TODO CONSTANTS

local CHANNELS = {
    [1] = "SAY",
    [2] = "EMOTE",
    [3] = "PARTY",
    [4] = "GUILD",
    [5] = "OFFICER",
    [6] = "YELL",
    [7] = "RAID",
    [8] = "RAID_WARNING"
}

local function getBidTypeName(type)
    if type == CONSTANTS.BID_TYPE[CONSTANTS.REPORTTHIS.SLOT_VALUE_TIER.OFFSPEC] then return "Offspec" end
    if type == CONSTANTS.BID_TYPE[CONSTANTS.REPORTTHIS.SLOT_VALUE_TIER.DUALSPEC] then return "Dual Spec" end
    if type == CONSTANTS.BID_TYPE[CONSTANTS.REPORTTHIS.SLOT_VALUE_TIER.UPGRADE] then return "Upgrade" end
    if type == CONSTANTS.BID_TYPE[CONSTANTS.REPORTTHIS.SLOT_VALUE_TIER.BONUS] then return "Bonus" end
    return "Unknown"
end

local AuctionHistoryManager = {}
function AuctionHistoryManager:Initialize()
    LOG:Trace("AuctionHistoryManager:Initialize()")
    self.db = CLM.MODULES.Database:Personal('auctionHistory', {
        stack = {}, -- legacy
        -- config
        enable = true,
        post_bids = true,
        post_bids_channel = 5
    })
    self.entries = {}
    self.cache = {}
    self.winners = {}
    CLM.MODULES.EventManager:RegisterEvent(EVENT_END_AUCTION, function(_, data)
        if not self:GetEnabled() then return end
        tinsert(self.entries, 1, {
            link     = data.link,
            id       = data.id,
            bids     = data.bids,
            names    = data.bidNames,
            upgraded = data.items,
            time     = data.time,
            data     = data.bidData
        })
        if self:GetPostBids() and data.postToChat then
            local channel = CHANNELS[self:GetPostBidsChannel()] or "OFFICER"
            SendChatMessage(data.link, channel)
            local noBids = true
            local bidList = {}
            for _, bid in pairs(data.bidData) do
                table.insert(bidList, bid)
            end
            table.sort(bidList,
                function(a, b) return CLM.MODULES.AuctionManager:TotalBid(a) > CLM.MODULES.AuctionManager:TotalBid(b) end)
            for _, bid in ipairs(bidList) do
                noBids = false

                local bidder = bid.name;
                local bidName = ""
                if data.bidNames[bidder] then
                    bidName = " - " .. data.bidNames[bidder]
                end

                local items = ""

                if data.items and data.items[bidder] then
                    local _, item1 = GetItemInfo(data.items[bidder][1] or 0)
                    local _, item2 = GetItemInfo(data.items[bidder][2] or 0)

                    if item1 or item2 then
                        items = CLM.L[" over "]
                        if item1 then items = items .. item1 end
                        if item2 then items = items .. item2 end
                    end
                end

                SendChatMessage(bidder ..
                    ": " ..
                    tostring(bid.points) ..
                    CLM.L[" DKP "] ..
                    "(" .. (bid.isMain and "Main / " or "") .. getBidTypeName(bid.type) .. ") " .. items,
                    channel)
            end
            if noBids then
                SendChatMessage(CLM.L["No bids"], channel)
            end
        end
        CLM.GUI.AuctionHistory:Refresh(true)
    end)

    local function observeLootAward(entry)
        self.winners[entry:uuid()] = entry:profile()
        local result = self.cache[entry:uuid()]
        if result then
            local profile = CLM.MODULES.ProfileManager:GetProfileByGUID(UTILS.getGuidFromInteger(entry:profile()))

            result.winner = profile
            if profile then
                result.bids[profile.name] = nil
                result.bids[profile.name .. " (winner)"] = result.bids[profile.name]
            end
        end
    end

    CLM.MODULES.LedgerManager:ObserveEntryType(CLM.MODELS.LEDGER.LOOT.Award, observeLootAward)
    CLM.MODULES.LedgerManager:ObserveEntryType(CLM.MODELS.LEDGER.LOOT.RaidAward, observeLootAward)

    local newEntries = {}
    ConfigLedgerManager:RegisterEntryType(
        AuctionHistoryEntry,
        (function(entry)
            LOG:TraceAndCount("mutator(ReportThis.AuctionHistoryEntry)")

            local result = {}
            result.uuid = entry:uuid()
            result.time = entry:time()
            result.link = entry:link()
            result.id = entry:itemId()
            result.bids = {}
            result.data = {}
            result.sortedData = {}

            local winner = self.winners[entry:uuid()]
            if winner then
                local profile = CLM.MODULES.ProfileManager:GetProfileByGUID(UTILS.getGuidFromInteger(winner))
                result.winner = profile
            end

            local rosterId = string.match(entry:uuid(), "%w+%-%w+%-(%w+)")
            local roster = CLM.MODULES.RosterManager:GetRosterByUid(rosterId)
            for name, v in pairs(entry:data()) do
                local value = {
                    name = name,
                    points = v.v or 0,
                    type = v.t or "u",
                    roll = v.r == '' and 0 or v.r or 0,
                }
                result.data[name] = value
                table.insert(result.sortedData, value)

                local total = CLM.MODULES.AuctionManager:TotalBid(value)
                local type = roster and roster:GetFieldName(value.type) or getBidTypeName(value.type)
                local bidName = name
                if result.winner and result.winner.name == bidName then
                    bidName = bidName .. " (winner)"
                end
                if (value.roll) then
                    result.bids[bidName] = string.format("%d (roll: %d, points: %d) [%s]", total, value.roll,
                        value.points,
                        type)
                else
                    result.bids[bidName] = string.format("%d [%s]", total, type)
                end

            end
            table.sort(result.sortedData, function(a, b)
                return CLM.MODULES.AuctionManager:TotalBid(a) > CLM.MODULES.AuctionManager:TotalBid(b)
            end)

            self.cache[result.uuid] = result
        end))

    ConfigLedgerManager:RegisterOnUpdate(function(lag, uncommitted)
        LOG:Warning("ConfigLedgerManager:RegisterOnUpdate lag: %d uncommitted: %d", lag, uncommitted)
        if lag ~= 0 or uncommitted ~= 0 then return end
        if #newEntries > 0 then return end
        if #self.db.stack == 0 then return end

        -- legacy items in the stack
        for _, auction in ipairs(self.db.stack) do
            if auction.uuid then
                for uuid, _ in pairs(auction.uuid) do
                    local data = {}
                    for name, value in pairs(auction.bids) do
                        data[name] = {
                            points = value,
                            type = nil
                        }
                    end

                    table.insert(newEntries,
                        AuctionHistoryEntry:new(uuid, auction.time, auction.link, auction.id, data))
                end
            end
        end
        self.db.stack = {}
        if #newEntries > 0 then
            C_Timer.After(1, function()
                for _, entry in ipairs(newEntries) do
                    ConfigLedgerManager:Submit(entry, true)
                end
                newEntries = {}
            end)
        end
    end)

    local options = {
        auction_history_header = {
            type = "header",
            name = CLM.L["Auctioning - History"],
            order = 39
        },
        auction_history_store_bids = {
            name = CLM.L["Store bids"],
            desc = CLM.L["Store finished auction bids information."],
            type = "toggle",
            set = function(i, v) self:SetEnabled(v) end,
            get = function(i) return self:GetEnabled() end,
            order = 40
        },
        auction_history_post_bids = {
            name = CLM.L["Post bids"],
            desc = CLM.L["Toggles posting bids in selected channel after auction has ended."],
            type = "toggle",
            set = function(i, v) self:SetPostBids(v) end,
            get = function(i) return self:GetPostBids() end,
            order = 41
        },
        auction_history_post_bids_channel = {
            name = CLM.L["Post channel"],
            desc = CLM.L["Channel for posting bids."],
            type = "select",
            values = CHANNELS,
            set = function(i, v) self:SetPostBidsChannel(v) end,
            get = function(i) return self:GetPostBidsChannel() end,
            order = 42
        }
    }
    CLM.MODULES.ConfigManager:Register(CONSTANTS.CONFIGS.GROUP.GLOBAL, options)


end

function AuctionHistoryManager:SetEnabled(value)
    self.db.enable = value and true or false
end

function AuctionHistoryManager:GetEnabled()
    return self.db.enable
end

function AuctionHistoryManager:SetPostBids(value)
    self.db.post_bids = value and true or false
end

function AuctionHistoryManager:GetPostBids()
    return self.db.post_bids
end

function AuctionHistoryManager:SetPostBidsChannel(value)
    local channel = CHANNELS[value]
    if channel then
        self.db.post_bids_channel = value
    end
end

function AuctionHistoryManager:GetPostBidsChannel()
    return self.db.post_bids_channel
end

function AuctionHistoryManager:CorrelateWithLoot(time, uuid)
    for _, auction in ipairs(self.entries) do
        if auction.time == time then
            if not auction.uuid then
                auction.uuid = {}
            end
            auction.uuid[uuid] = true
            ConfigLedgerManager:Submit(
                AuctionHistoryEntry:new(uuid, auction.time, auction.link, auction.id, auction.data),
                true
            )
        end
    end
end

function AuctionHistoryManager:GetByUUID(uuid)
    if not uuid then return end
    return self.cache[uuid]
end

function AuctionHistoryManager:GetHistory()
    local stack = {}
    for key, value in pairs(self.cache) do
        table.insert(stack, value)
    end
    table.sort(stack, (function(first, second) return first.time < second.time end))
    return stack
end

function AuctionHistoryManager:Remove(id)
    -- id = tonumber(id) or 0
    -- if (id <= #self.db.stack) and (id >= 1) then
    --     tremove(self.db.stack, id)
    --     CLM.GUI.AuctionHistory:Refresh(true)
    -- end
end

function AuctionHistoryManager:RemoveOld(time)
    -- time = tonumber(time) or 2678400 -- 31 days old
    -- local cutoff = GetServerTime() - time
    -- UTILS.OnePassRemove(self.db.stack, function(t, i, j)
    --     return t[i].time > cutoff
    -- end)
    -- CLM.GUI.AuctionHistory:Refresh(true)
end

function AuctionHistoryManager:Wipe()
    -- while (#self.db.stack > 0) do
    --     tremove(self.db.stack)
    -- end
    -- CLM.GUI.AuctionHistory:Refresh(true)
end

CLM.MODULES.AuctionHistoryManager = AuctionHistoryManager
