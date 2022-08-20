local CLM = LibStub("ClassicLootManager").CLM

local MODELS = CLM.MODELS
local UTILS = CLM.UTILS
local CONSTANTS = CLM.CONSTANTS

local AuctionCommStartAuction = {}
function AuctionCommStartAuction:New(typeOrObject, itemValueMode, base, max, itemLink, time, endtime, antiSnipe, note,
                                     increment, rosterUid)
    local isCopyConstructor = (type(typeOrObject) == "table")

    local o = isCopyConstructor and typeOrObject or {}

    setmetatable(o, self)
    self.__index = self

    if isCopyConstructor then return o end

    o.t = typeOrObject
    o.i = itemValueMode
    o.b = base
    o.m = max
    o.l = itemLink
    o.e = time
    o.d = endtime
    o.s = antiSnipe
    o.n = note
    o.c = increment
    o.r = rosterUid

    return o
end

function AuctionCommStartAuction:Type()
    return self.t or 0
end

function AuctionCommStartAuction:Mode()
    return self.i or 0
end

function AuctionCommStartAuction:Base()
    return tonumber(self.b) or 0
end

function AuctionCommStartAuction:Max()
    return tonumber(self.m) or 0
end

function AuctionCommStartAuction:ItemLink()
    return self.l or ""
end

function AuctionCommStartAuction:Time()
    return tonumber(self.e) or 0
end

function AuctionCommStartAuction:EndTime()
    return tonumber(self.d) or 0
end

function AuctionCommStartAuction:AntiSnipe()
    return tonumber(self.s) or 0
end

function AuctionCommStartAuction:Note()
    return self.n or ""
end

function AuctionCommStartAuction:Increment()
    return tonumber(self.c) or 1
end

function AuctionCommStartAuction:RosterUid()
    return self.r or 0
end

local AuctionCommDenyBid = {}
function AuctionCommDenyBid:New(valueOrObject)
    local isCopyConstructor = (type(valueOrObject) == "table")
    local o = isCopyConstructor and valueOrObject or {}

    setmetatable(o, self)
    self.__index = self

    if isCopyConstructor then return o end

    o.d = valueOrObject

    return o
end

function AuctionCommDenyBid:Reason()
    return self.d or 0
end

local AuctionCommDistributeBid = {}
function AuctionCommDistributeBid:New(nameOrObject, value)
    local isCopyConstructor = (type(nameOrObject) == "table")

    local o = isCopyConstructor and nameOrObject or {}

    setmetatable(o, self)
    self.__index = self

    if isCopyConstructor then return o end

    o.n = nameOrObject
    o.d = value

    return o
end

function AuctionCommDistributeBid:Name()
    return self.n
end

function AuctionCommDistributeBid:Value()
    return self.d
end

local AuctionCommResponses = {}
function AuctionCommResponses:New(object, bidData, bids, passes, hidden, cantUse)
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
            o.l[key].name = key
            o.l[key].total = o.l[key].points + tonumber(o.l[key].roll or "0")
        end
        return o
    end

    o.l = {}
    for key, value in pairs(bidData or {}) do
        o.l[key] = { type = value.type, rank = value.rank, points = value.points, roll = value.roll }
    end
    o.b = bids
    o.p = passes
    o.h = hidden
    o.c = cantUse

    return o
end

function AuctionCommResponses:BidData()
    return self.l
end

function AuctionCommResponses:Bids()
    return self.b
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
MODELS.AuctionCommStartAuction = AuctionCommStartAuction
MODELS.AuctionCommDenyBid = AuctionCommDenyBid
MODELS.AuctionCommDistributeBid = AuctionCommDistributeBid
MODELS.AuctionCommResponses = AuctionCommResponses
