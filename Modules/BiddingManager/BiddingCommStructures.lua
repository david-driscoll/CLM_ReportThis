local CLM = LibStub("ClassicLootManager").CLM

local MODELS = CLM.MODELS
-- local UTILS = CLM.UTILS
local CONSTANTS = CLM.CONSTANTS


local BiddingCommSubmitBid = {}
function BiddingCommSubmitBid:New(valueOrObject)
    local isCopyConstructor = (type(valueOrObject) == "table")
    local o = isCopyConstructor and valueOrObject or {}

    setmetatable(o, self)
    self.__index = self

    if isCopyConstructor then return o end

    o.d = valueOrObject

    return o
end

function BiddingCommSubmitBid:Bid()
    return self.d or 0
end

local BiddingCommStructure = {}
function BiddingCommStructure:New(typeOrObject, data)
    local isCopyConstructor = (type(typeOrObject) == "table")

    local o = isCopyConstructor and typeOrObject or {}

    setmetatable(o, self)
    self.__index = self

    if isCopyConstructor then
        if o.t == CONSTANTS.BIDDING_COMM.TYPE.SUBMIT_BID then
            o.d = BiddingCommSubmitBid:New(o.d)
        end
        return o
    end

    o.t = tonumber(typeOrObject) or 0
    o.d = data

    return o
end

function BiddingCommStructure:Type()
    return self.t or 0
end

function BiddingCommStructure:Data()
    return self.d
end

MODELS.BiddingCommStructure = BiddingCommStructure
MODELS.BiddingCommSubmitBid = BiddingCommSubmitBid
