local CLM = LibStub("ClassicLootManager").CLM

local LOG = CLM.LOG

local UTILS = CLM.UTILS
local MODULES = CLM.MODULES
local MODELS = CLM.MODELS
local GUI = CLM.GUI
local CONSTANTS = CLM.CONSTANTS

local ProfileManager = MODULES.ProfileManager
local RosterManager = MODULES.RosterManager
local LootManager = MODULES.LootManager
local RaidManager = MODULES.RaidManager
local EventManager = MODULES.EventManager

local Comms = MODULES.Comms

-- local Roster = MODELS.Roster
local Raid = MODELS.Raid
local RosterConfiguration = MODELS.RosterConfiguration

local typeof = UTILS.typeof

local AuctionCommStructure = MODELS.AuctionCommStructure
local AuctionCommStartAuction = MODELS.AuctionCommStartAuction
local AuctionCommDenyBid = MODELS.AuctionCommDenyBid
local AuctionCommDistributeBid = MODELS.AuctionCommDistributeBid
local AuctionCommResponses = MODELS.AuctionCommResponses

local AUCTION_COMM_PREFIX = "Auction1"

local EVENT_START_AUCTION = "CLM_AUCTION_START"
local EVENT_END_AUCTION = "CLM_AUCTION_END"

local AuctionManager = {}

local rollPattern = UTILS.CreatePattern(RANDOM_ROLL_RESULT)

local function InitializeDB(self)
    self.db = MODULES.Database:Personal('auction', {
        autoAward = true,
        autoTrade = true
    })
end

function AuctionManager:Initialize()
    LOG:Trace("AuctionManager:Initialize()")

    InitializeDB(self)

    self:ClearBids()
    self.auctionInProgress = false
    self.auctioneer = nil
    self.rollInProgress = false

    Comms:Register(AUCTION_COMM_PREFIX,
        (function(rawMessage, distribution, sender)
            local message = AuctionCommStructure:New(rawMessage)
            if CONSTANTS.AUCTION_COMM.TYPES[message:Type()] == nil then return end
            -- Auction Manager is owner of the channel
            -- pass handling to BidManager
            MODULES.BiddingManager:HandleIncomingMessage(message, distribution, sender)
            AuctionManager:HandleIncomingSyncMessage(message, distribution, sender)
        end),
        (function(name)
            return self:IsAuctioneer(name, true) -- relaxed for cross-guild bidding
        end),
        true)

    EventManager:RegisterWoWEvent({ "CHAT_MSG_SYSTEM" }, (function(addon, _, text, ...)
        if not self.rollInProgress then return end
        local pattern = string.gsub(RANDOM_ROLL_RESULT, "[%(%)%-]", "%%%1")
        pattern = string.gsub(pattern, "%%s", "(.+)")
        pattern = string.gsub(pattern, "%%d", "%(%%d+%)")
        for name, roll, low, high in string.gmatch(text, pattern) do
            LOG:Debug("name %s, roll %s, low %s, high %s", name, roll, low, high)
            if (low ~= "1" or high ~= "100") then
                return
            end
            roll = tonumber(roll)

            if not AuctionManager.userResponses.bidData[name] then
                UTILS.SendChatMessage(CLM.L["Your roll was not accepted."], "WHISPER", nil, name)
                return
            end

            local result = AuctionManager.userResponses.bidData[name]

            if result.roll then
                UTILS.SendChatMessage(CLM.L["Your have already rolled."], "WHISPER", nil, name)
            else
                result.roll = roll
                AuctionManager:UpdateBidList()
            end
        end
    end))

    self.handlers = {
        [CONSTANTS.BIDDING_COMM.TYPE.SUBMIT_BID]     = "HandleSubmitBid",
        [CONSTANTS.BIDDING_COMM.TYPE.CANCEL_BID]     = "HandleCancelBid",
        [CONSTANTS.BIDDING_COMM.TYPE.NOTIFY_PASS]    = "HandleNotifyPass",
        [CONSTANTS.BIDDING_COMM.TYPE.NOTIFY_BONUS]   = "HandleNotifyBonus",
        [CONSTANTS.BIDDING_COMM.TYPE.NOTIFY_UPGRADE] = "HandleNotifyUpgrade",
        [CONSTANTS.BIDDING_COMM.TYPE.NOTIFY_OFFSPEC] = "HandleNotifyOffspec",
        [CONSTANTS.BIDDING_COMM.TYPE.NOTIFY_HIDE]    = "HandleNotifyHide",
        [CONSTANTS.BIDDING_COMM.TYPE.NOTIFY_CANTUSE] = "HandleNotifyCantUse",
    }

    self.syncHandlers = {
        [CONSTANTS.AUCTION_COMM.TYPE.START_AUCTION] = "HandleStartAuction",
        [CONSTANTS.AUCTION_COMM.TYPE.STOP_AUCTION]  = "HandleStopAuction",
        [CONSTANTS.AUCTION_COMM.TYPE.START_ROLL]    = "HandleStartRoll",
        [CONSTANTS.AUCTION_COMM.TYPE.STOP_ROLL]     = "HandleStopRoll",
        [CONSTANTS.AUCTION_COMM.TYPE.ANTISNIPE]     = "HandleAntiSnipe",
        [CONSTANTS.AUCTION_COMM.TYPE.BID_LIST]      = "HandleBidList",
    }

    local options = {
        auctioning_header = {
            type = "header",
            name = CLM.L["Auctioning"],
            order = 30
        },
        auctioning_guild_award_announcement = {
            name = CLM.L["Announce award to Guild"],
            desc = CLM.L["Toggles loot award announcement to guild"],
            type = "toggle",
            set = function(i, v) CLM.GlobalConfigs:SetAnnounceAwardToGuild(v) end,
            get = function(i) return CLM.GlobalConfigs:GetAnnounceAwardToGuild() end,
            width = "double",
            order = 31
        },
        auctioning_enable_auto_award_from_corpse = {
            name = CLM.L["Auto-award from corpse"],
            desc = CLM.L["Enable loot auto-award (Master Looter UI) from corpse when item is awarded"],
            type = "toggle",
            set = function(i, v) self:SetAutoAward(v) end,
            get = function(i) return self:GetAutoAward() end,
            width = "double",
            order = 32
        },
        auctioning_enable_auto_trade = {
            name = CLM.L["Auto-trade after award"],
            desc = CLM.L["Enables auto-trade awarded loot after auctioning from bag"],
            type = "toggle",
            set = function(i, v) self:SetAutoTrade(v) end,
            get = function(i) return self:GetAutoTrade() end,
            -- width = "double",
            order = 33
        },
        auctioning_chat_commands_header = {
            type = "header",
            name = CLM.L["Auctioning - Chat Commands"],
            order = 34
        },
        auctioning_chat_commands = {
            name = CLM.L["Enable chat commands"],
            desc = CLM.L["Enble !dkp and !bid through whisper / raid. Change requires /reload."],
            type = "toggle",
            set = function(i, v) CLM.GlobalConfigs:SetAllowChatCommands(v) end,
            get = function(i) return CLM.GlobalConfigs:GetAllowChatCommands() end,
            width = "double",
            order = 35
        },
        auctioning_suppress_incoming = {
            name = CLM.L["Suppress incoming whispers"],
            desc = CLM.L["Hides incoming !dkp and !bid whispers. Change requires /reload."],
            type = "toggle",
            set = function(i, v) CLM.GlobalConfigs:SetSuppressIncomingChatCommands(v) end,
            get = function(i) return CLM.GlobalConfigs:GetSuppressIncomingChatCommands() end,
            width = "double",
            order = 36
        },
        auctioning_suppress_outgoing = {
            name = CLM.L["Suppress outgoing whispers"],
            desc = CLM.L["Hides outgoing !dkp and !bid responses. Change requires /reload."],
            type = "toggle",
            set = function(i, v) CLM.GlobalConfigs:SetSuppressOutgoingChatCommands(v) end,
            get = function(i) return CLM.GlobalConfigs:GetSuppressOutgoingChatCommands() end,
            width = "double",
            order = 37
        }
    }
    MODULES.ConfigManager:Register(CLM.CONSTANTS.CONFIGS.GROUP.GLOBAL, options)

    MODULES.ConfigManager:RegisterUniversalExecutor("aum", "AuctionManager", self)

    self._initialized = true
end

function AuctionManager:SetAutoAward(value)
    self.db.autoAward = value and true or false
end

function AuctionManager:GetAutoAward()
    return self.db.autoAward
end

function AuctionManager:SetAutoTrade(value)
    self.db.autoTrade = value and true or false
end

function AuctionManager:GetAutoTrade()
    return self.db.autoTrade
end

-- We pass configuration separately as it can be overriden on per-auction basis
function AuctionManager:StartAuction(itemId, itemLink, itemSlot, _, _, note, raid, configuration)
    LOG:Trace("AuctionManager:StartAuction()")
    if self.auctionInProgress then
        LOG:Warning("AuctionManager:StartAuction(): Auction in progress")
        return
    end
    if not self:IsAuctioneer() then
        LOG:Message(CLM.L["You are not allowed to auction items"])
        return
    end
    -- Auction parameters sanity checks
    note = note or ""
    if not typeof(raid, Raid) then
        LOG:Warning("AuctionManager:StartAuction(): Invalid raid object")
        return false
    end
    self.raid = raid
    itemId = tonumber(itemId)
    if not itemId then
        LOG:Warning("AuctionManager:StartAuction(): invalid item id")
        return false
    end
    self.itemId = itemId
    if not itemLink then
        LOG:Warning("AuctionManager:StartAuction(): invalid item link")
        return false
    end
    self.itemLink = itemLink
    if not typeof(configuration, RosterConfiguration) then
        LOG:Warning("AuctionManager:StartAuction(): Invalid roster configuration object")
        return false
    end
    -- Auction Settings sanity checks
    local auctionTime = configuration:Get("auctionTime")
    if auctionTime <= 0 then
        LOG:Warning("AuctionManager:StartAuction(): 0s auction time")
        return false
    end
    if auctionTime < 10 then
        LOG:Warning("AuctionManager:StartAuction(): Very short (below 10s) auction time")
    end
    self.auctionTime = auctionTime
    self.baseValue = 0
    self.maxValue = 1000
    if self.auctionTime <= 0 then
        LOG:Warning("AuctionManager:StartAuction(): Auction time must be greater than 0 seconds")
        return false
    end
    self.allowNegativeBidders = configuration:Get("allowNegativeBidders")
    self.allowNegativeStandings = configuration:Get("allowNegativeStandings")
    -- Auctioning
    -- Start Auction Messages
    self.note = note
    self.antiSnipe = configuration:Get("antiSnipe")
    if CLM.GlobalConfigs:GetAuctionWarning() then
        local auctionMessage = string.format(CLM.L["Starting loot of %s"], itemLink)
        if note:len() > 0 then
            auctionMessage = auctionMessage .. " (" .. tostring(note) .. ")"
        end
        -- Max 2 raid warnings are displayed at the same time
        UTILS.SendChatMessage(auctionMessage, "RAID_WARNING")
        auctionMessage = ""
        auctionMessage = auctionMessage .. string.format(CLM.L["Auction time: %s."] .. " ", tostring(auctionTime))
        if self.antiSnipe > 0 then
            auctionMessage = auctionMessage .. string.format(CLM.L["Anti-snipe time: %s."], tostring(self.antiSnipe))
        end
        UTILS.SendChatMessage(auctionMessage, "RAID_WARNING")
        if CLM.GlobalConfigs:GetCommandsWarning() and CLM.GlobalConfigs:GetAllowChatCommands() then
            auctionMessage = "The following commands can be sent through whisper or raid chat:"
            auctionMessage = auctionMessage .. " '!howto to list bidding commands."
            auctionMessage = auctionMessage .. " '!dkp' to check your dkp."
            auctionMessage = auctionMessage .. " '!help' for information on the rules."
            UTILS.SendChatMessage(auctionMessage, "RAID")
        end
    end
    -- Get Auction Type info
    self.auctionType = configuration:Get("auctionType")
    -- AntiSnipe settings
    self.antiSnipeLimit = (self.antiSnipe > 0) and (CONSTANTS.AUCTION_TYPES_OPEN[self.auctionType] and 100 or 3) or 0

    -- calculate server end time
    self.auctionEndTime = GetServerTime() + self.auctionTime
    self.auctionTimeLeft = self.auctionEndTime
    -- minimal increment
    self.minimalIncrement = self.raid:Roster():GetConfiguration("minimalIncrement")
    -- Set auction in progress
    -- Send auction information
    self:SendAuctionStart(self.raid:Roster():UID())
    -- Start Auction Ticker
    self.lastCountdownValue = 5
    self.ticker = C_Timer.NewTicker(0.1, (function()
        self.auctionTimeLeft = self.auctionEndTime - GetServerTime()
        if CLM.GlobalConfigs:GetCountdownWarning() and self.lastCountdownValue > 0 and
            self.auctionTimeLeft <= self.lastCountdownValue and self.auctionTimeLeft <= 5 then
            UTILS.SendChatMessage(tostring(math.ceil(self.auctionTimeLeft)), "RAID_WARNING")
            self.lastCountdownValue = self.lastCountdownValue - 1
        end
        if self.auctionTimeLeft < 0.1 then
            self:StopAuctionTimed()
            return
        end
    end))
    -- UI
    self:UpdateBidList()
    -- Event
    EventManager:DispatchEvent(EVENT_START_AUCTION, { itemId = self.itemId })
    return true
end

local function AuctionEnd(self, postToChat)
    self.lastAuctionEndTime = GetServerTime()
    EventManager:DispatchEvent(EVENT_END_AUCTION, {
        link = self.itemLink,
        id = self.itemId,
        bids = self.userResponses.bids,
        time = self.lastAuctionEndTime,
        postToChat = postToChat
    })

    self:RequestRollOff()
    self:SendAuctionEnd()
    self:UpdateBidList()
end

function AuctionManager:StopAuctionTimed()
    LOG:Trace("AuctionManager:StopAuctionTimed()")
    self.ticker:Cancel()
    if CLM.GlobalConfigs:GetAuctionWarning() then
        UTILS.SendChatMessage(CLM.L["Auction complete"], "RAID_WARNING")
    end
    AuctionEnd(self, true)
end

function AuctionManager:StopAuctionManual()
    LOG:Trace("AuctionManager:StopAuctionManual()")
    self.ticker:Cancel()
    if CLM.GlobalConfigs:GetAuctionWarning() then
        UTILS.SendChatMessage(CLM.L["Auction stopped by Master Looter"], "RAID_WARNING")
    end
    AuctionEnd(self, false)
end

function AuctionManager:AntiSnipe()
    LOG:Trace("AuctionManager:AntiSnipe()")
    if self.antiSnipeLimit > 0 then
        if self.auctionTimeLeft < self.antiSnipe then
            self.auctionEndTime = self.auctionEndTime + self.antiSnipe
            self.antiSnipeLimit = self.antiSnipeLimit - 1
            self:SendAntiSnipe()
            -- Cheeky update the warning countdown, but only if above 3/5s
            if self.antiSnipe >= 5 then
                self.lastCountdownValue = 5
            elseif self.antiSnipe >= 3 then
                self.lastCountdownValue = 3
            end
        end
    end
end

function AuctionManager:RequestRollOff()
    local bids, minPoints, hasOffspec = self:GetEligibleBids()
    if #bids <= 1 then
        return
    end
    self:SendRollStart()

    local prefix = {}
    if hasOffspec then
        table.insert(prefix, #bids .. " Offspec bids.")
    else
        table.insert(prefix, #bids .. " Players within " .. self:GetRollDifference() .. ".")
    end

    local candidates = {}
    table.insert(prefix, "The following players please /roll: ")
    for index, value in ipairs(bids) do
        if hasOffspec then
            table.insert(candidates, value.name)
        else
            local diff = value.points - minPoints
            if diff == 0 then
                table.insert(candidates, value.name .. " [!" .. string.lower(value.type) .. "]")
            else
                table.insert(candidates, value.name .. " [!" .. string.lower(value.type) .. "] (+" .. diff .. ")")
            end
        end

        if #candidates >= 5 then
            UTILS.SendChatMessage(table.concat(prefix, " ") .. table.concat(candidates, ", "), "RAID_WARNING")
            candidates = {}
            prefix = {}
        end
    end
    if #candidates > 0 then
        UTILS.SendChatMessage(table.concat(prefix, " ") .. table.concat(candidates, ", "), "RAID_WARNING")
    end
end

function AuctionManager:SendAuctionStart(rosterUid)
    if self.auctionInProgress then return end
    self.auctionInProgress = true
    self.auctioneer = UTILS.whoami()
    if not self:IAmTheAuctioneer() then return end
    for _, value in pairs(self.userResponses.bidData) do
        value.roll = nil
    end
    local message = AuctionCommStructure:New(
        CONSTANTS.AUCTION_COMM.TYPE.START_AUCTION,
        AuctionCommStartAuction:New(
            self.auctionType,
            self.itemValueMode,
            self.baseValue,
            self.maxValue,
            self.itemLink,
            self.auctionTime,
            self.auctionEndTime,
            self.antiSnipe,
            self.note,
            self.minimalIncrement,
            rosterUid
        )
    )
    Comms:Send(AUCTION_COMM_PREFIX, message, CONSTANTS.COMMS.DISTRIBUTION.RAID)
end

function AuctionManager:SendAuctionEnd()
    if not self.auctionInProgress then return end
    self.auctionInProgress = false
    if not self:IAmTheAuctioneer() then return end
    local message = AuctionCommStructure:New(CONSTANTS.AUCTION_COMM.TYPE.STOP_AUCTION, {})
    Comms:Send(AUCTION_COMM_PREFIX, message, CONSTANTS.COMMS.DISTRIBUTION.RAID)
end

local function SendBidList()
    LOG:Debug("SendBidList()")
    if not AuctionManager:IAmTheAuctioneer() then return end
    local message = AuctionCommStructure:New(
        CONSTANTS.AUCTION_COMM.TYPE.BID_LIST,
        AuctionCommResponses:New(
            nil,
            AuctionManager.userResponses.bidData,
            AuctionManager.userResponses.bids,
            AuctionManager.userResponses.passes,
            AuctionManager.userResponses.hidden,
            AuctionManager.userResponses.cantUse
        )
    )
    Comms:Send(AUCTION_COMM_PREFIX, message, CONSTANTS.COMMS.DISTRIBUTION.RAID)
end

function AuctionManager:SendRollStart()
    if self.rollInProgress then return end
    self.rollInProgress = true
    if not self:IAmTheAuctioneer() then return end
    local message = AuctionCommStructure:New(CONSTANTS.AUCTION_COMM.TYPE.START_ROLL, {})
    Comms:Send(AUCTION_COMM_PREFIX, message, CONSTANTS.COMMS.DISTRIBUTION.RAID)
end

function AuctionManager:SendRollEnd()
    if not self.rollInProgress then return end
    self.rollInProgress = false
    if not self:IAmTheAuctioneer() then return end
    local message = AuctionCommStructure:New(CONSTANTS.AUCTION_COMM.TYPE.STOP_ROLL, {})
    Comms:Send(AUCTION_COMM_PREFIX, message, CONSTANTS.COMMS.DISTRIBUTION.RAID)
end

function AuctionManager:SendAntiSnipe()
    if not self.auctionInProgress or not self:IAmTheAuctioneer() then return end
    local message = AuctionCommStructure:New(CONSTANTS.AUCTION_COMM.TYPE.ANTISNIPE, {})
    Comms:Send(AUCTION_COMM_PREFIX, message, CONSTANTS.COMMS.DISTRIBUTION.RAID)
end

function AuctionManager:SendBidAccepted(name)
    if not self.auctionInProgress or not self:IAmTheAuctioneer() then return end
    local message = AuctionCommStructure:New(CONSTANTS.AUCTION_COMM.TYPE.ACCEPT_BID, {})
    Comms:Send(AUCTION_COMM_PREFIX, message, CONSTANTS.COMMS.DISTRIBUTION.WHISPER, name, CONSTANTS.COMMS.PRIORITY.ALERT)
end

function AuctionManager:SendBidDenied(name, reason)
    if not self.auctionInProgress or not self:IAmTheAuctioneer() then return end
    local message = AuctionCommStructure:New(
        CONSTANTS.AUCTION_COMM.TYPE.DENY_BID,
        AuctionCommDenyBid:New(reason)
    )
    Comms:Send(AUCTION_COMM_PREFIX, message, CONSTANTS.COMMS.DISTRIBUTION.WHISPER, name, CONSTANTS.COMMS.PRIORITY.ALERT)
end

function AuctionManager:SendBidInfo(name, bid)
    if not self.auctionInProgress or not self:IAmTheAuctioneer() then return end
    local message = AuctionCommStructure:New(
        CONSTANTS.AUCTION_COMM.TYPE.DISTRIBUTE_BID,
        AuctionCommDistributeBid:New(name, bid)
    )
    Comms:Send(AUCTION_COMM_PREFIX, message, CONSTANTS.COMMS.DISTRIBUTION.RAID)
end

function AuctionManager:HandleIncomingMessage(message, distribution, sender)
    LOG:Trace("AuctionManager:HandleIncomingMessage()")
    local mtype = message:Type() or 0
    -- UTILS.DumpTable(message)
    if self.handlers[mtype] then
        self[self.handlers[mtype]](self, message:Data(), sender)
    end
end

function AuctionManager:HandleIncomingSyncMessage(message, distribution, sender)
    LOG:Trace("AuctionManager:HandleIncomingSyncMessage()")
    local mtype = message:Type() or 0
    -- UTILS.DumpTable(message)
    if self.syncHandlers[mtype] then
        self[self.syncHandlers[mtype]](self, message:Data(), sender)
    end
end

function AuctionManager:HandleSubmitBid(data, sender)
    LOG:Trace("AuctionManager:HandleSubmitBid()")
    if not self.auctionInProgress then
        LOG:Debug("Received submit bid from %s while no auctions are in progress", sender)
        return
    end
    self:UpdateBid(sender, data:Bid())
end

function AuctionManager:HandleCancelBid(data, sender)
    LOG:Trace("AuctionManager:HandleCancelBid()")
    if not self.auctionInProgress then
        LOG:Debug("Received cancel bid from %s while no auctions are in progress", sender)
        return
    end
    self:UpdateBid(sender, nil)
end

function AuctionManager:HandleNotifyPass(data, sender)
    LOG:Trace("AuctionManager:HandleNotifyPass()")
    if not self.auctionInProgress then
        LOG:Debug("Received pass from %s while no auctions are in progress", sender)
        return
    end
    -- Pass (unlike other notifciations) needs to go through update bid since it overwrites bid value
    self:UpdateBid(sender, CONSTANTS.AUCTION_COMM.BID_PASS)
end

function AuctionManager:HandleNotifyBonus(data, sender)
    LOG:Trace("AuctionManager:HandleNotifyBonus()")
    if not self.auctionInProgress then
        LOG:Debug("Received bonus from %s while no auctions are in progress", sender)
        return
    end
    -- Pass (unlike other notifciations) needs to go through update bid since it overwrites bid value
    self:UpdateBid(sender, CONSTANTS.AUCTION_COMM.BID_BONUS)
end

function AuctionManager:HandleNotifyUpgrade(data, sender)
    LOG:Trace("AuctionManager:HandleNotifyUpgrade()")
    if not self.auctionInProgress then
        LOG:Debug("Received upgrade from %s while no auctions are in progress", sender)
        return
    end
    -- Pass (unlike other notifciations) needs to go through update bid since it overwrites bid value
    self:UpdateBid(sender, CONSTANTS.AUCTION_COMM.BID_UPGRADE)
end

function AuctionManager:HandleNotifyOffspec(data, sender)
    LOG:Trace("AuctionManager:HandleNotifyOffspec()")
    if not self.auctionInProgress then
        LOG:Debug("Received offspec from %s while no auctions are in progress", sender)
        return
    end
    -- Pass (unlike other notifciations) needs to go through update bid since it overwrites bid value
    self:UpdateBid(sender, CONSTANTS.AUCTION_COMM.BID_OFFSPEC)
end

function AuctionManager:HandleNotifyHide(data, sender)
    LOG:Trace("AuctionManager:HandleNotifyHide()")
    if not self.auctionInProgress then
        LOG:Debug("Received hide from %s while no auctions are in progress", sender)
        return
    end
    self.userResponses.hidden[sender] = true
    self:UpdateBidList()
end

function AuctionManager:HandleNotifyCantUse(data, sender)
    LOG:Trace("AuctionManager:HandleNotifyCantUse()")
    if not self.auctionInProgress then
        LOG:Debug("Received can't use from %s while no auctions are in progress", sender)
        return
    end
    self.userResponses.cantUse[sender] = true
    self:UpdateBidList()
end

function AuctionManager:HandleStartAuction(data, sender)
    LOG:Debug("AuctionManager:HandleStartAuction() %s %s", UTILS.whoami(), sender)
    if not self:IsAuctionComplete() then
        LOG:Debug("Received start auction when i was the auctioneer", sender)
        return
    end
    self.auctionType = data:Type()
    self.itemValueMode = data:Mode()
    self.baseValue = data:Base()
    self.maxValue = data:Max()
    self.itemLink = data:ItemLink()
    GUI.AuctionManager.itemLink = data:ItemLink()
    self.auctionTime = data:Time()
    self.auctionEndTime = data:EndTime()
    self.antiSnipe = data:AntiSnipe()
    self.note = data:Note()
    self.minimalIncrement = data:Increment()
    local rosterUid = data:RosterUid()

    self.auctioneer = sender
    self.auctionInProgress = true
    GUI.AuctionManager:Show()
end

function AuctionManager:HandleStopAuction(data, sender)
    LOG:Debug("AuctionManager:HandleStopAuction() %s %s", UTILS.whoami(), sender)
    if self:IAmTheAuctioneer() then
        LOG:Debug("Received stop auction when i was the auctioneer", sender)
        return
    end
    self.auctioneer = nil
    self.auctionInProgress = false
    GUI.AuctionManager:Refresh()
end

function AuctionManager:HandleStartRoll(data, sender)
    LOG:Debug("AuctionManager:HandleStartRoll() %s %s", UTILS.whoami(), sender)
    if self:IAmTheAuctioneer() then
        LOG:Debug("Received start roll when i was the auctioneer", sender)
        return
    end

    self.auctioneer = sender
    self.rollInProgress = true
    GUI.AuctionManager:Refresh()
end

function AuctionManager:HandleStopRoll(data, sender)
    LOG:Debug("AuctionManager:HandleStopRoll() %s %s", UTILS.whoami(), sender)
    if self:IAmTheAuctioneer() then
        LOG:Debug("Received stop roll when i was the auctioneer", sender)
        return
    end
    self.auctioneer = nil
    self.rollInProgress = false
    GUI.AuctionManager:Refresh()
end

function AuctionManager:HandleAntiSnipe(data, sender)
    LOG:Debug("AuctionManager:HandleAntiSnipe()")
    if UTILS.whoami() == sender then
        LOG:Debug("Received antisnipe from %s while no auctions are in progress", sender)
        return
    end
end

function AuctionManager:HandleBidList(data, sender)
    LOG:Debug("AuctionManager:HandleBidList()")
    if UTILS.whoami() == sender then
        return
    end

    self.userResponses.bidData = data:BidData()
    self.userResponses.bids = data:Bids()
    self.userResponses.passes = data:Passes()
    self.userResponses.hidden = data:Hidden()
    self.userResponses.cantUse = data:CantUse()
    GUI.AuctionManager:Refresh()
end

function AuctionManager:ValidateBid(name, bid)
    -- bid cancelling
    if bid == nil then
        return true
    end
    -- bid passing
    if bid == CONSTANTS.AUCTION_COMM.BID_PASS then return true end
    -- sanity check
    local profile = ProfileManager:GetProfileByName(name)
    if not profile then return false, CONSTANTS.AUCTION_COMM.DENY_BID_REASON.NOT_IN_ROSTER end
    local GUID = profile:GUID()
    if not self.raid:Roster():IsProfileInRoster(GUID) then return false,
            CONSTANTS.AUCTION_COMM.DENY_BID_REASON.NOT_IN_ROSTER
    end
    -- allow negative bidders
    local current = self.raid:Roster():Standings(GUID)
    if current < 0 and not self.allowNegativeBidders then return false,
            CONSTANTS.AUCTION_COMM.DENY_BID_REASON.NEGATIVE_BIDDER
    end

    if bid == CONSTANTS.AUCTION_COMM.BID_BONUS then return true end
    if bid == CONSTANTS.AUCTION_COMM.BID_UPGRADE then return true end
    if bid == CONSTANTS.AUCTION_COMM.BID_OFFSPEC then return true end

    local currentPoints = UTILS.GetCurrentPoints(self.raid, name)
    local bidType = UTILS.InferBidType(bid, currentPoints)
    if not bidType then return false end
    if bidType == CONSTANTS.AUCTION_COMM.BID_UPGRADE then currentPoints = self:GetUpgradeCost() end

    -- allow negative standings after bid
    local new = currentPoints - UTILS.CalculateItemCost(self.raid, bidType, currentPoints, self.itemId)
    if new < 0 and not self.allowNegativeStandings then return false,
            CONSTANTS.AUCTION_COMM.DENY_BID_REASON.NEGATIVE_STANDING_AFTER
    end
    -- accept otherwise
    return true
end

function AuctionManager:UpdateBidList()
    if self:IAmTheAuctioneer() then
        UTILS.Debounce("bidlist", 1, function() SendBidList() end)
    end

    GUI.AuctionManager:UpdateBids()
end

function AuctionManager:UpdateBid(name, bid)
    LOG:Trace("AuctionManager:UpdateBid()")
    LOG:Debug("Bid from %s: %s", name, bid)
    if not self:IsAuctionInProgress() then return false, CONSTANTS.AUCTION_COMM.DENY_BID_REASON.NO_AUCTION_IN_PROGRESS end
    local accept, reason = self:ValidateBid(name, bid)
    if accept then
        self:UpdateBidsInternal(name, bid)
        self:SendBidAccepted(name)
    else
        LOG:Debug("Bid denied %s", reason)
        self:SendBidDenied(name, reason)
    end

    self:UpdateBidList()

    return accept, reason
end

function AuctionManager:GetUpgradeCost(raidOrRoster, itemId)
    return UTILS.GetUpgradeCost(raidOrRoster or self.raid, itemId)
end

function AuctionManager:GetOffspecCost(raidOrRoster, itemId)
    return UTILS.GetOffspecCost(raidOrRoster or self.raid, itemId)
end

function AuctionManager:GetMaxCost(raidOrRoster, itemId)
    return UTILS.GetMaxCost(raidOrRoster or self.raid, itemId)
end

function AuctionManager:UpdateBidsInternal(name, bid)

    local function setBidData(userResponses, name, points, b, pass)
        userResponses.bids[name] = points
        userResponses.bidData[name] = {
            name = name,
            type = b,
            points = points,
            rank = UTILS.GetGuildRank(name),
        }
        userResponses.passes[name] = pass or nil
    end

    local upgradeCost = AuctionManager:GetUpgradeCost()
    local offspecCost = AuctionManager:GetOffspecCost()

    if bid == CONSTANTS.AUCTION_COMM.BID_PASS then
        self.userResponses.passes[name] = true
        self.userResponses.bids[name] = nil
        self.userResponses.bidData[name] = nil
        return false
    end

    local points = UTILS.GetCurrentPoints(self.raid, name)

    if bid == CONSTANTS.AUCTION_COMM.BID_BONUS then
        if points <= upgradeCost then
            bid = CONSTANTS.AUCTION_COMM.BID_UPGRADE
        end
        setBidData(self.userResponses, name, points, bid)
        return false
    end

    if bid == CONSTANTS.AUCTION_COMM.BID_UPGRADE then
        if points > upgradeCost then points = upgradeCost end
        setBidData(self.userResponses, name, points, bid)
        return false
    end

    if bid == CONSTANTS.AUCTION_COMM.BID_OFFSPEC then
        setBidData(self.userResponses, name, offspecCost, bid)
        return false
    end

    local bidType = UTILS.InferBidType(bid, points)
    if bidType then
        if bidType == CONSTANTS.AUCTION_COMM.BID_BONUS then
            if points <= upgradeCost then bidType = CONSTANTS.AUCTION_COMM.BID_UPGRADE end
        end
        if bidType == CONSTANTS.AUCTION_COMM.BID_UPGRADE then
            if points > upgradeCost then points = upgradeCost end
        end
        if bidType == CONSTANTS.AUCTION_COMM.BID_OFFSPEC then points = offspecCost end
        setBidData(self.userResponses, name, points, bidType)
        return false
    end

    self.userResponses.bids[name] = nil
    self.userResponses.bidData[name] = nil
    self.userResponses.passes[name] = nil

    return false
end

function AuctionManager:Bids()
    return self.userResponses.bids
end

function AuctionManager:BidData()
    return self.userResponses.bidData
end

function AuctionManager:TotalBid(bid)
    local value = bid.points or 0
    if bid.roll then value = value + tonumber(bid.roll or "0") end
    return value
end

function AuctionManager:GetTopBid()
    local topBid = nil
    for _, data in pairs(AuctionManager:BidData()) do
        if not topBid or self:TotalBid(data) > self:TotalBid(topBid) then
            topBid = data
        end
    end
    return topBid
end

function AuctionManager:CalculateItemCost(player)
    local data = AuctionManager:BidData()[player]
    if not data then return 0 end

    return UTILS.CalculateItemCost(self.raid, data.type, data.points, self.itemId)
end

function AuctionManager:GetEligibleBids()
    local bids = {}
    local hasUpgradeOrBonus = false
    local topBid = self:GetTopBid()
    if not topBid then
        return bids, 0
    end
    local minEligableBid = topBid.points

    LOG:Debug("minEligableBid: %s", minEligableBid)
    local rollDifference = self:GetRollDifference()
    for _, data in pairs(AuctionManager:BidData()) do
        hasUpgradeOrBonus = hasUpgradeOrBonus
            or data.type == CONSTANTS.AUCTION_COMM.BID_UPGRADE
            or data.type == CONSTANTS.AUCTION_COMM.BID_BONUS

        if (data.type ~= CONSTANTS.AUCTION_COMM.BID_PASS)
            and (tonumber(topBid.points) - tonumber(data.points)) <= rollDifference
            and (minEligableBid < 0 or data.points > 0)
        then
            table.insert(bids, data)
            LOG:Debug("minEligableBid (%s) > data.points (%s) = %s", tostring(minEligableBid), tostring(data.points),
                tostring(minEligableBid > data.points))
            if minEligableBid > data.points then
                LOG:Debug("minEligableBid: %s", minEligableBid)
                minEligableBid = data.points
            end
        end
    end
    if hasUpgradeOrBonus then
        for index, value in ipairs(bids) do
            if value.type == CONSTANTS.AUCTION_COMM.BID_OFFSPEC then
                table.remove(bids, index)
            end
        end
    end
    table.sort(bids, function(a, b) return a.name > b.name end)
    return bids, minEligableBid, not hasUpgradeOrBonus
end

function AuctionManager:GetRollDifference()
    return CLM.OPTIONS.ReportThisRosterManager:GetConfiguration(self.raid:Roster(), "rollDifference")
end

function AuctionManager:Passes()
    return self.userResponses.passes
end

function AuctionManager:CantUse()
    return self.userResponses.cantUse
end

function AuctionManager:Hidden()
    return self.userResponses.hidden
end

function AuctionManager:ClearBids()
    self.userResponses = {
        bids    = {},
        bidData = {},
        passes  = {},
        cantUse = {},
        hidden  = {},
    }
    self:SendRollEnd()
    self:UpdateBidList()
end

function AuctionManager:Award(itemLink, itemId, price, name)
    LOG:Trace("AuctionManager:Award()")
    self:SendRollEnd()
    local success, uuid = LootManager:AwardItem(self.raid, name, itemLink, itemId, price)
    if success then
        MODULES.AuctionHistoryManager:CorrelateWithLoot(self.lastAuctionEndTime, uuid)
    end
    -- clear bids
    self:ClearBids()

    return success
end

function AuctionManager:IsAuctioneer(name, relaxed)
    LOG:Trace("AuctionManager:IsAuctioneer()")
    name = name or UTILS.whoami()
    return RaidManager:IsAllowedToAuction(name, relaxed)
end

function AuctionManager:IsAuctionInProgress()
    return self.auctionInProgress
end

function AuctionManager:IsRollInProgress()
    return self.rollInProgress
end

function AuctionManager:IsAuctionComplete()
    return not (self.auctionInProgress or self.rollInProgress)
end

function AuctionManager:GetTheAuctioneer()
    return self.auctioneer
end

function AuctionManager:IAmTheAuctioneer()
    local canAuction = self:IsAuctioneer(UTILS.whoami())
    local iAmTheAuctioneer = self.auctioneer == UTILS.whoami()

    local result = canAuction
        and (iAmTheAuctioneer
            or (not self.auctioneer and AuctionManager:IsAuctionComplete())
        )
    LOG:Debug("AuctionManager:IAmTheAuctioneer() = %s", tostring(result))
    return result
end

CONSTANTS.AUCTION_COMM = {
    BID_PASS                = CLM.L["PASS"],
    BID_BONUS               = CLM.L["BONUS"],
    BID_UPGRADE             = CLM.L["UPGRADE"],
    BID_OFFSPEC             = CLM.L["OFFSPEC"],
    TYPE                    = {
        START_AUCTION = 1,
        STOP_AUCTION = 2,
        ANTISNIPE = 3,
        ACCEPT_BID = 4,
        DENY_BID = 5,
        DISTRIBUTE_BID = 6,
        BID_LIST = 7,
        START_ROLL = 8,
        STOP_ROLL = 9,
    },
    TYPES                   = UTILS.Set({
        1, -- START_AUCTION
        2, -- STOP_AUCTION
        3, -- ANTISNIPE
        4, -- ACCEPT_BID
        5, -- DENY_BID
        6, -- DISTRIBUTE_BID
        7, -- BID_LIST
        8, -- START_ROLL
        9, -- STOP_ROLL
    }),
    DENY_BID_REASON         = {
        NOT_IN_ROSTER = 1,
        NEGATIVE_BIDDER = 2,
        NEGATIVE_STANDING_AFTER = 3,
        BID_VALUE_TOO_LOW = 4,
        BID_VALUE_TOO_HIGH = 5,
        BID_VALUE_INVALID = 6,
        BID_INCREMENT_TOO_LOW = 7,
        NO_AUCTION_IN_PROGRESS = 8,
        CANCELLING_NOT_ALLOWED = 9,
        PASSING_NOT_ALLOWED = 10,
    },
    DENY_BID_REASONS        = UTILS.Set({
        1, -- NOT_IN_ROSTER
        2, -- NEGATIVE_BIDDER
        3, -- NEGATIVE_STANDING_AFTER
        4, -- BID_VALUE_TOO_LOW
        5, -- BID_VALUE_TOO_HIGH
        6, -- BID_VALUE_INVALID
        7, -- BID_INCREMENT_TOO_LOW
        8, -- NO_AUCTION_IN_PROGRESS
        9, -- CANCELLING_NOT_ALLOWED
        10 -- PASSING_NOT_ALLOWED
    }),
    DENY_BID_REASONS_STRING = {
        [1] = CLM.L["Not in a roster"],
        [2] = CLM.L["Negative bidders not allowed"],
        [3] = CLM.L["Bidding over current standings not allowed"],
        [4] = CLM.L["Bid too low"],
        [5] = CLM.L["Bid too high"],
        [6] = CLM.L["Invalid bid value"],
        [7] = CLM.L["Bid increment too low"],
        [8] = CLM.L["No auction in progress"],
        [9] = CLM.L["Bid cancelling not allowed"],
        [10] = CLM.L["Passing after bidding not allowed"]
    }
}

MODULES.AuctionManager = AuctionManager
