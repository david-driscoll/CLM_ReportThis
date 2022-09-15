local CLM = LibStub("ClassicLootManager").CLM

local MODELS = CLM.MODELS
local UTILS = CLM.UTILS

local mergeLists = UTILS.mergeLists
local typeof = UTILS.typeof
-- local getIntegerGuid = UTILS.getIntegerGuid
-- local GetGUIDFromEntry = UTILS.GetGUIDFromEntry
local CreateGUIDList = UTILS.CreateGUIDList

local LogEntry = LibStub("EventSourcing/LogEntry")

local AuctionHistoryEntry = LogEntry:extend("RT.AH")

-- ------------------------ --
-- AuctionHistoryEntry --
-- ------------------------ --
function AuctionHistoryEntry:new(uuid, time, link, itemId, data)
    local o = LogEntry.new(self);
    o.u = uuid
    o.t = time
    o.l = link
    o.i = itemId
    o.d = {}
    for name, value in pairs(data) do
        o.d[name] = {
            v = value.points,
            r = value.roll or '',
            t = value.type
        }
    end
    return o
end

function AuctionHistoryEntry:uuid()
    return self.u
end

function AuctionHistoryEntry:time()
    return self.t
end

function AuctionHistoryEntry:link()
    return self.l
end

function AuctionHistoryEntry:itemId()
    return self.i
end

function AuctionHistoryEntry:data()
    return self.d
end

local AuctionHistoryEntryFields = mergeLists(LogEntry:fields(), { "u", "t", "l", "i", "d" })
function AuctionHistoryEntry:fields()
    return AuctionHistoryEntryFields
end

if not CLM.MODELS.LEDGER.REPORTTHIS then
    CLM.MODELS.LEDGER.REPORTTHIS = {}
end
CLM.MODELS.LEDGER.REPORTTHIS.AUCTION = {
    AuctionHistoryEntry = AuctionHistoryEntry,
}
