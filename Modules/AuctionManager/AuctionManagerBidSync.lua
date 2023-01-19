local CLM = LibStub("ClassicLootManager").CLM

local LOG = CLM.LOG

local UTILS = CLM.UTILS
local GUI = CLM.GUI
local CONSTANTS = CLM.CONSTANTS
local DATA_COMM_PREFIX = "rtBidSync"

-- local Roster = MODELS.Roster

local typeof = UTILS.typeof

local AuctionInfo = CLM.MODELS.AuctionInfo
local AuctionItem = CLM.MODELS.AuctionItem
local UserResponse = CLM.MODELS.UserResponse

local function HookAuctionManager(name, preFunc, postFunc)
    local oldFn = CLM.MODULES.AuctionManager[name]
    CLM.MODULES.AuctionManager[name] = function(self, ...)
        preFunc(self, ...)
        local result = oldFn(self, ...)
        postFunc(self, ...)
        return result
    end
end

local function HookAuctionInfo(name, preFunc, postFunc)
    local oldFn = AuctionInfo[name]
    AuctionInfo[name] = function(self, ...)
        preFunc(self, ...)
        local result = oldFn(self, ...)
        postFunc(self, ...)
        return result
    end
end

local nickMap = {
    "Milhouse",
    "Jenkins",
    "Hemet",
    "Mrgl-Mrgl",
    "Varian",
    "Jaina",
    "Thrall",
    "Garrosh",
    "Velen",
    "Grommash",
    "Uther",
    "Sylvanas",
}

function AuctionInfo:GetAnonymousName(name)
    if not self.anonymousMap[name] then
        self.anonymousMap[name] = nickMap[math.random(1, #nickMap)] .. " " .. tostring(self.nextAnonymousId)
        self.nextAnonymousId = self.nextAnonymousId + 1
    end
    return self.anonymousMap[name]
end

local function SendBidInfo(self, itemId, name, userResponse)
    self.bidInfoSender:Send(itemId, name, userResponse)
end

local function getAuctionRaid()
    return CLM.MODULES.AuctionManager.currentAuction.raid
end

local function getAuctionRoster()
    return CLM.MODULES.AuctionManager.currentAuction.roster
end

local AuctionManagerBidSync = {}

function AuctionManagerBidSync:Initialize()
    LOG:Trace("AuctionManagerBidSync:Initialize()")

    CLM.MODULES.Comms:Register(CLM.COMM_CHANNEL.AUCTION,
        (function(rawMessage, distribution, sender)
            local message = CLM.MODELS.AuctionCommStructure:New(rawMessage)
            if CONSTANTS.AUCTION_COMM.TYPES[message:Type()] == nil then return end
            -- Auction Manager is owner of the channel
            -- pass handling to BidManager
            -- TODO: Is this needed?
            CLM.MODULES.BiddingManager:HandleIncomingMessage(message, distribution, sender)
            self:HandleIncomingSyncMessage(message, distribution, sender)
        end),
        (function(name)
            return CLM.MODULES.AuctionManager:IsAuctioneer(name, true) -- relaxed for cross-guild bidding
        end),
        true)

    CLM.MODULES.Comms:Register(DATA_COMM_PREFIX,
        (function(rawMessage, distribution, sender)
            self:HandleBidList(rawMessage, sender)
        end),
        (function(name)
            return CLM.MODULES.ACL:IsTrusted() -- relaxed for cross-guild bidding
        end),
        true)

    if not CLM.MODULES.ACL:IsTrusted() then return end

    self.syncHandlers = {
        [CONSTANTS.AUCTION_COMM.TYPE.START_AUCTION] = "HandleStartAuction",
        [CONSTANTS.AUCTION_COMM.TYPE.STOP_AUCTION]  = "HandleStopAuction",
    }

    self._initialized = true
end

function AuctionManagerBidSync:IAmTheAuctioneer()
    local canAuction = CLM.MODULES.AuctionManager:IsAuctioneer(UTILS.whoami())
    local iAmTheAuctioneer = self.auctioneer == UTILS.whoami()

    local result = canAuction
        and (iAmTheAuctioneer or (not self.auctioneer and not CLM.MODULES.AuctionManager:IsAuctionInProgress()))
    LOG:Debug("AuctionManagerBidSync:IAmTheAuctioneer() = %s", tostring(result))
    return result
end

function AuctionManagerBidSync:GetTheAuctioneer()
    return self.auctioneer
end

HookAuctionManager("UpdateBid", function(self, name, itemId, userResponse)
    if not self:IsAuctionInProgress() then return end
    local auction = self.currentAuction
    local item = auction:GetItem(itemId)
    -- force bid info and value to get updated.
    AuctionManagerBidSync:GetBidInfo(item, name, userResponse)
end,
    function(self)

        AuctionManagerBidSync:UpdateBidList()
    end)

HookAuctionInfo(
    "Start",
    function(self, ...)
        for _, item in pairs(self.items) do
            item.saveResponses = item:GetAllResponses()
            item.saveRolls = item.userRolls
            item.saveValues = item.rollValues
        end
    end,
    function(self, ...)
        for _, item in pairs(self.items) do
            item.userResponses = item.saveResponses
            item.userRolls     = item.saveRolls
            item.rollValues    = item.saveValues
            item.saveResponses = nil
            item.saveRolls     = nil
            item.saveValues    = nil
        end
    end
)

HookAuctionManager("StartAuction", function(self, ...) end, function(self)
    AuctionManagerBidSync.auctioneer = UTILS.whoami()

    local auction = self.currentAuction
    local auctionType = auction:GetType()
    -- LOG:Info("Sending bid info for existing bids")
    for _, item in pairs(auction:GetItems()) do
        for name, userResponse in pairs(item:GetAllResponses()) do

            -- LOG:Info("name %s item %s", tostring(name), tostring(item:GetItemID()))
            if auctionType == CONSTANTS.AUCTION_TYPE.ANONYMOUS_OPEN then
                local anonomizedName = auction:GetAnonymousName(name)
                local modifiedResponse = UTILS.DeepCopy(userResponse)
                modifiedResponse:SetUpgradedItems({}) -- Clear Upgraded items info
                SendBidInfo(CLM.MODULES.AuctionManager, item:GetItemID(), anonomizedName, modifiedResponse)
            else
                SendBidInfo(CLM.MODULES.AuctionManager, item:GetItemID(), name, userResponse)
            end
        end
    end
end)

HookAuctionManager("StopAuctionManual", function(self, ...) end, function(self)
    AuctionManagerBidSync.auctioneer = nil
end)

HookAuctionManager("HandleIncomingMessage", function(self, ...) end, function(self, message, distribution, sender)
    if CLM.CONSTANTS.BIDDING_COMM.TYPES[message:Type()] == nil then return end
    AuctionManagerBidSync:UpdateBidList()
end)

HookAuctionManager("RemoveItemFromCurrentAuction", function(self, ...) end, function(self, ...)
    AuctionManagerBidSync:UpdateBidList()
end)

HookAuctionManager("ClearItemList", function(self, ...) end, function(self, ...)
    AuctionManagerBidSync:UpdateBidList()
end)

function AuctionManagerBidSync:UpdateBidList()
    -- LOG:Info("AuctionManagerBidSync:UpdateBidList()")
    if self:IAmTheAuctioneer() then
        UTILS.Debounce("bidlist", 1, function() AuctionManagerBidSync:SendBidList() end)
    end

    -- self.currentBidInfo = AuctionManagerBidSync:ComputeCurrentBidInfo()
    -- GUI.AuctionManagerBidSync:UpdateBids()
end

function AuctionManagerBidSync:SendBidList()
    LOG:Debug("AuctionManager:SendBidList()")
    if not AuctionManagerBidSync:IAmTheAuctioneer() then return end

    local info = CLM.MODULES.AuctionManager:GetCurrentAuctionInfo()

    local roster = info:GetRoster():UID()
    local raid = info:GetRaid():UID()
    local sendData = {
        s = info.state,
        o = roster,
        r = raid,
        i = {},
    }

    for _, item in pairs(info:GetItems()) do
        local responses = item:GetAllResponses()

        local itemData = {
            l = item:GetItemLink(),
            n = item:GetNote(),
            r = {},
        }

        for player, response in pairs(responses) do
            itemData.r[player] = {
                v = response:Value(),
                t = response:Type(),
                r = response:Roll(),
                u = response:Items(),
                i = response:GetInvalidReason(),
            }
        end
        table.insert(sendData.i, itemData)
    end

    CLM.MODULES.Comms:Send(DATA_COMM_PREFIX, sendData, CONSTANTS.COMMS.DISTRIBUTION.RAID)
end

function AuctionManagerBidSync:HandleBidList(data, sender)
    -- LOG:Info("AuctionManagerBidSync:HandleBidList()")
    if UTILS.whoami() == sender then
        return
    end

    local info = AuctionInfo:New()

    -- LOG:Info("raid %s", tostring(data.raid))
    info:UpdateRaid(CLM.MODULES.RaidManager:GetRaidByUid(data.r))
    -- LOG:Info("roster %s", tostring(data.roster))
    info:UpdateRoster(CLM.MODULES.RosterManager:GetRosterByUid(data.o))

    -- LOG:Info("item updated raid and roster")
    for _, item in pairs(data.i) do
        -- LOG:Info("item %s", item.l)
        local ai = info:AddItem(Item:CreateFromItemLink(item.l))
        ai:SetNote(item.n)

        for player, response in pairs(item.r) do
            local userResponse = UserResponse:New(response.v, response.t, response.u)

            -- LOG:Info("response player %s value %s type %s", tostring(player), tostring(response.v),
            --     tostring(response.t))

            userResponse.roll = response.r
            userResponse.invalid = response.i
            ai:SetResponse(player, userResponse, true)
        end

        -- LOG:Info("auction item %s", tostring(ai:HasValidBids()))
    end
    info.state = data.s
    -- self.currentBidInfo = AuctionManagerBidSync:ComputeCurrentBidInfo()
    -- GUI.AuctionManagerBidSync:Refresh()
    CLM.MODULES.AuctionManager.currentAuction = info
    if CLM.GUI.AuctionManager.auctionItem then
        local current = CLM.GUI.AuctionManager.auctionItem
        CLM.GUI.AuctionManager.auctionItem = nil
        for _, item in pairs(info:GetItems()) do
            if current:GetItemID() == item:GetItemID() then
                CLM.GUI.AuctionManager.auctionItem = item
                break
            end
        end
    end
    if CLM.GUI.AuctionManager.auctionItem == nil then
        local _, item = next(info:GetItems())
        CLM.GUI.AuctionManager.auctionItem = item
    end

    CLM.MODULES.AuctionManager:RefreshGUI()
end

function AuctionManagerBidSync:HandleIncomingSyncMessage(message, distribution, sender)
    LOG:Trace("AuctionManagerBidSync:HandleIncomingSyncMessage()")
    local mtype = message:Type() or 0
    -- UTILS.DumpTable(message)
    if self.syncHandlers[mtype] then
        self[self.syncHandlers[mtype]](self, message:Data(), sender)
    end
end

function AuctionManagerBidSync:HandleStartAuction(data, sender)
    LOG:Debug("AuctionManagerBidSync:HandleStartAuction() %s %s", UTILS.whoami(), sender)

    self.auctioneer = sender

    if self:IAmTheAuctioneer() then
        LOG:Debug("Received start auction when i was the auctioneer", sender)
        self:SendBidList()
        return
    end

    CLM.GUI.AuctionManager:Show()
end

function AuctionManagerBidSync:HandleStopAuction(data, sender)
    LOG:Debug("AuctionManagerBidSync:HandleStopAuction() %s %s", UTILS.whoami(), sender)

    self.auctioneer = nil

    if self:IAmTheAuctioneer() then
        self:SendBidList()
        LOG:Debug("Received stop auction when i was the auctioneer", sender)
        return
    end
end

function AuctionManagerBidSync:ComputeCurrentBidInfo()
    if not CLM.MODULES.RaidManager:IsInActiveRaid() or self.raid == nil then return {
            bidded = {},
            passed = {},
            cantUse = {},
            closed = {},
            anyAction = {},
            noAction = {},
            total = 0,
            waitingOn = 0,
        }
    end
    -- Unique did any action dict
    local didAnyAction = {}
    -- generateInfo closure
    local _generateInfo = (function(dataDict, ignoreListOfDicts, prefix, skipAction)
        local dataList, userCodedString = {}, ""
        for p, _ in pairs(dataDict) do
            local inIgnoreList = false
            for _, d in ipairs(ignoreListOfDicts) do
                if d[p] then
                    inIgnoreList = true
                    break
                end
            end
            if not inIgnoreList then
                table.insert(dataList, p)
                if not skipAction then
                    didAnyAction[p] = true
                end
            end
        end
        return dataList
    end)
    for p, _ in pairs(AuctionManagerBidSync:Bids()) do
        didAnyAction[p] = true
    end
    -- bidded list
    local bidded = _generateInfo(
        AuctionManagerBidSync:Passes(),
        { AuctionManagerBidSync:Bids() },
        "Passed")
    -- passess list
    local passed = _generateInfo(
        AuctionManagerBidSync:Passes(),
        { AuctionManagerBidSync:Bids() },
        "Passed")
    -- cant use actions
    local cantUse = _generateInfo(
        AuctionManagerBidSync:CantUse(),
        { AuctionManagerBidSync:Bids(), AuctionManagerBidSync:Passes() },
        "Can't use")
    -- closed actions
    local closed = _generateInfo(AuctionManagerBidSync:Hidden(),
        { AuctionManagerBidSync:Bids(), AuctionManagerBidSync:Passes(), AuctionManagerBidSync:CantUse() },
        "Closed")
    -- no action
    local raidersDict = {}
    for _, GUID in ipairs(CLM.MODULES.RaidManager:GetRaid():Players()) do
        local profile = CLM.MODULES.ProfileManager:GetProfileByGUID(GUID)
        if profile then
            raidersDict[profile:Name()] = true
        end
    end
    local noAction = _generateInfo(raidersDict,
        { AuctionManagerBidSync:Bids(), AuctionManagerBidSync:Passes(), AuctionManagerBidSync:CantUse(),
            AuctionManagerBidSync:Hidden() },
        "No action",
        true)

    local anyAction = {}
    -- did any actions count
    for name, _ in pairs(didAnyAction) do table.insert(anyAction, name) end

    return {
        bidded = bidded,
        passed = passed,
        cantUse = cantUse,
        closed = closed,
        anyAction = anyAction,
        noAction = noAction,
        total = #CLM.MODULES.RaidManager:GetRaid():Players(),
        waitingOn = #noAction,
    }
end

function AuctionManagerBidSync:GetUpgradeCost(raidOrRoster, itemId)
    return UTILS.GetUpgradeCost(raidOrRoster or CLM.MODULES.RaidManager:GetRaid(), itemId)
end

function AuctionManagerBidSync:GetOffspecCost(raidOrRoster, itemId)
    return UTILS.GetOffspecCost(raidOrRoster or CLM.MODULES.RaidManager:GetRaid(), itemId)
end

function AuctionManagerBidSync:GetMaxCost(raidOrRoster, itemId)
    return UTILS.GetMaxCost(raidOrRoster or CLM.MODULES.RaidManager:GetRaid(), itemId)
end

local function GetMainPriority()
    return CLM.OPTIONS.ReportThisRosterManager:GetConfiguration(CLM.MODULES.RaidManager:GetRaid():Roster(),
        "mainPriority")
end

local function RankHasPriority(rank)
    if GetMainPriority() then
        return not
            (
            string.find(rank, "Alt") ~= nil or string.find(rank, "Initiate") ~= nil or string.find(rank, "Casual") ~= nil
            )
    end
    return true
end

local function UpdateBidInfo(raid, auctionItem, name, userResponse)

    local upgradeCost = AuctionManagerBidSync:GetUpgradeCost()
    local offspecCost = AuctionManagerBidSync:GetOffspecCost()
    local points = UTILS.GetCurrentPoints(raid, name)

    if userResponse:Type() == CONSTANTS.REPORTTHIS.BID_TYPE.BONUS then
        if points <= upgradeCost then
            userResponse.type = CONSTANTS.REPORTTHIS.BID_TYPE.UPGRADE
        end
        userResponse.bidInfo.bidValue = points
        return true
    end

    if userResponse:Type() == CONSTANTS.REPORTTHIS.BID_TYPE.UPGRADE then
        if points > upgradeCost then points = upgradeCost end
        userResponse.bidInfo.bidValue = points
        return true
    end

    if userResponse:Type() == CONSTANTS.REPORTTHIS.BID_TYPE.OFFSPEC or
        userResponse:Type() == CONSTANTS.REPORTTHIS.BID_TYPE.DUALSPEC then
        userResponse.bidInfo.bidValue = offspecCost
        return true
    end
end

local function GetBidInfo(raid, auctionItem, name, userResponse)
    -- in theory this should work
    if userResponse.bidInfo then
        UpdateBidInfo(raid, auctionItem, name, userResponse)
        return userResponse.bidInfo
    end

    local rank = UTILS.GetGuildRank(name)
    local isMain = RankHasPriority(rank)

    userResponse.bidInfo = {
        bidValue = 0,
        rank = rank,
        isMain = isMain,
        isOffspec = userResponse:Type() == CONSTANTS.REPORTTHIS.BID_TYPE.OFFSPEC or
            userResponse:Type() == CONSTANTS.REPORTTHIS.BID_TYPE.DUALSPEC,
        isUpgrade = userResponse:Type() == CONSTANTS.REPORTTHIS.BID_TYPE.BONUS or
            userResponse:Type() == CONSTANTS.REPORTTHIS.BID_TYPE.UPGRADE
    }

    UpdateBidInfo(raid, auctionItem, name, userResponse)
    return userResponse.bidInfo
end

function TotalBid(bid)
    local value = bid.value or 0
    if (bid.bidInfo and bid.bidInfo.bidValue) then value = bid.bidInfo.bidValue end
    if bid.roll then value = value + tonumber(bid.roll or "0") end
    return value
end

function AuctionManagerBidSync:TotalBid(bid)
    return TotalBid(bid)
end

function AuctionManagerBidSync:GetTopBid(item)
    local topBid = nil
    for name, response in pairs(item:GetAllResponses()) do
        local bidInfo = self:GetBidInfo(item, name, response)
        if bidInfo.isMain and bidInfo.isUpgrade then
            if not topBid then
                topBid = response
            elseif topBid
                and TotalBid(response) > TotalBid(topBid)
            then
                topBid = response
            end
        end
    end
    if topBid then
        return topBid, true, true
    end

    for name, response in pairs(item:GetAllResponses()) do
        local bidInfo = self:GetBidInfo(item, name, response)
        if not bidInfo.isMain and bidInfo.isUpgrade then
            if not topBid then
                topBid = response
            elseif TotalBid(response) > TotalBid(topBid)
            then
                topBid = response
            end
        end
    end
    if topBid then
        return topBid, true, false
    end

    for name, response in pairs(item:GetAllResponses()) do
        if not topBid then
            topBid = response
        elseif TotalBid(response) > TotalBid(topBid)
        then
            topBid = response
        end
    end
    return topBid, false, false
end

function AuctionManagerBidSync:CalculateItemCost(player)
    local data = self:BidData()[player]
    if not data then return 0 end

    return UTILS.CalculateItemCost(CLM.MODULES.RaidManager:GetRaid(), data.type, data.points, self.itemId)
end

function AuctionManagerBidSync:GetBidInfo(item, name, response)
    return GetBidInfo(getAuctionRaid(), item, name, response)
end

function AuctionManagerBidSync:GetEligibleBids()
    local bids = {}
    local topBid, hasUpgradeOrBonus, hasMain = self:GetTopBid()
    if not topBid then
        return bids, 0
    end
    local minEligableBid = topBid.points

    LOG:Debug("minEligableBid: %s", minEligableBid)
    local rollDifference = self:GetRollDifference()
    for _, data in pairs(AuctionManagerBidSync:BidData()) do
        local isUpgrade = hasUpgradeOrBonus and data.isUpgrade
        local isMain = isUpgrade and hasMain and data.isMain
        local isAlt = isUpgrade and not hasMain and not data.isMain
        local isOffspec = not isUpgrade and data.isOffspec

        if (isOffspec or isMain or isAlt) and
            (tonumber(topBid.points) - tonumber(data.points)) <= rollDifference
            and (self:AllowNegativeUpgrades() or (minEligableBid <= 0 or data.points >= 0))
        --(data.type ~= CONSTANTS.AUCTION_COMM.BID_PASS)
        then
            table.insert(bids, data)
            LOG:Debug("minEligableBid (%s) > data.points (%s) = %s", tostring(minEligableBid), tostring(data.points),
                tostring(minEligableBid > data.points))
            if minEligableBid > data.points then
                LOG:Debug("minEligableBid: %s", minEligableBid)
                minEligableBid = data.points
            end
        end

        if hasUpgradeOrBonus then
            for index, value in ipairs(bids) do
                if value.isOffspec then
                    table.remove(bids, index)
                end
            end
        end

        -- if hasMain then
        --     for index, value in ipairs(bids) do
        --         if not value.isMain then
        --             table.remove(bids, index)
        --         end
        --     end
        -- end

        -- update incase one of the items has been removd
        minEligableBid = topBid.points
        for index, value in ipairs(bids) do
            if minEligableBid > value.points then
                LOG:Debug("minEligableBid: %s", minEligableBid)
                minEligableBid = value.points
            end
        end
    end

    table.sort(bids, function(a, b) return a.name > b.name end)
    return bids, minEligableBid, not hasUpgradeOrBonus
end

function AuctionManagerBidSync:GetRollDifference()
    return CLM.OPTIONS.ReportThisRosterManager:GetConfiguration(getAuctionRaid():Roster(), "rollDifference")
end

function AuctionManagerBidSync:AllowNegativeUpgrades()
    return CLM.OPTIONS.ReportThisRosterManager:GetConfiguration(getAuctionRaid():Roster(), "allowNegativeUpgrades")
end

function AuctionManagerBidSync:GetMainPriority()
    return CLM.OPTIONS.ReportThisRosterManager:GetConfiguration(getAuctionRaid():Roster(), "mainPriority")
end

function AuctionManagerBidSync:ClearBids()
    self.userResponses = {
        bids          = {},
        bidData       = {},
        bidTypes      = {},
        passes        = {},
        upgradedItems = {},
        cantUse       = {},
        hidden        = {},
    }
    self.currentBidInfo = {
        bidded = {},
        passed = {},
        cantUse = {},
        closed = {},
        anyAction = {},
        noAction = {},
        total = 0,
        waitingOn = 0,
    }
    self:SendRollEnd()
    self:UpdateBidList()
end

CLM.OPTIONS.AuctionManagerBidSync = AuctionManagerBidSync
