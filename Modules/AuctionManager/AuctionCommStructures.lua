local CLM = LibStub("ClassicLootManager").CLM

local MODELS = CLM.MODELS
local UTILS = CLM.UTILS
local CONSTANTS = CLM.CONSTANTS

local AuctionCommStartAuction = MODELS.AuctionCommStartAuction
local AuctionCommDenyBid = MODELS.AuctionCommDenyBid
local AuctionCommDistributeBid = MODELS.AuctionCommDistributeBid

local AuctionCommResponses = {}
function AuctionCommResponses:New(object, bidData, bids, passes, hidden, cantUse, bidTypes, upgradedItems)
    local isCopyConstructor = (type(object) == "table")

    local o = isCopyConstructor and object or {}

    setmetatable(o, self)
    self.__index = self

    if isCopyConstructor then

        -- userResponses.bidData[name] = {
        --     name = name,
        --     type = b,
        --     points = 0,
        --     rank = UTILS.GetGuildRank(name),
        --     pass = pass or false
        -- }

        for key, value in pairs(o.l or {}) do
            local isOffspec = value.type == CONSTANTS.REPORTTHIS.BID_TYPE.OFFSPEC or
                value.type == CONSTANTS.REPORTTHIS.BID_TYPE.DUALSPEC
            local isMain = not (string.find(value.rank, "Alt") ~= nil or string.find(value.rank, "Casual") ~= nil)
            o.l[key].name = key
            o.l[key].total = value.points + tonumber(o.l[key].roll or "0")
            o.l[key].isMain = isMain
            o.l[key].isOffspec = isOffspec
            o.l[key].isUpgrade = value.type == CONSTANTS.REPORTTHIS.BID_TYPE.BONUS or
                value.type == CONSTANTS.REPORTTHIS.BID_TYPE.UPGRADE
        end
        return o
    end


    o.l = {}
    for key, value in pairs(bidData or {}) do
        o.l[key] = {
            type = value.type,
            rank = value.rank,
            points = value.points,
            roll = value.roll
        }
    end
    o.b = bids
    o.p = passes
    o.h = hidden
    o.c = cantUse
    o.t = bidTypes
    o.u = upgradedItems

    return o
end

function AuctionCommResponses:BidData()
    return self.l
end

function AuctionCommResponses:Bids()
    return self.b
end

function AuctionCommResponses:BidTypes()
    return self.t
end

function AuctionCommResponses:UpgradedItems()
    return self.u
end

function AuctionCommResponses:Passes()
    return self.p
end

function AuctionCommResponses:Hidden()
    return self.h
end

function AuctionCommResponses:CantUse()
    return self.c
end

local AuctionCommStructure = {}
function AuctionCommStructure:New(typeOrObject, data)
    local isCopyConstructor = (type(typeOrObject) == "table")

    local o = isCopyConstructor and typeOrObject or {}

    setmetatable(o, self)
    self.__index = self

    if isCopyConstructor then
        if o.t == CONSTANTS.AUCTION_COMM.TYPE.START_AUCTION then
            o.d = AuctionCommStartAuction:New(o.d)
        elseif o.t == CONSTANTS.AUCTION_COMM.TYPE.DENY_BID then
            o.d = AuctionCommDenyBid:New(o.d)
        elseif o.t == CONSTANTS.AUCTION_COMM.TYPE.DISTRIBUTE_BID then
            o.d = AuctionCommDistributeBid:New(o.d)
        elseif o.t == CONSTANTS.AUCTION_COMM.TYPE.BID_LIST then
            o.d = AuctionCommResponses:New(o.d)
        end
        return o
    end

    o.t = tonumber(typeOrObject) or 0
    o.d = data

    return o
end

function AuctionCommStructure:Type()
    return self.t or 0
end

function AuctionCommStructure:Data()
    return self.d
end

MODELS.AuctionCommStructure = AuctionCommStructure
MODELS.AuctionCommResponses = AuctionCommResponses
