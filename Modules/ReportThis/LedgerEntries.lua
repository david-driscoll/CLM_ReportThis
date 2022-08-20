local CLM = LibStub("ClassicLootManager").CLM

local MODELS = CLM.MODELS
local UTILS = CLM.UTILS

local mergeLists = UTILS.mergeLists
local typeof = UTILS.typeof
-- local getIntegerGuid = UTILS.getIntegerGuid
-- local GetGUIDFromEntry = UTILS.GetGUIDFromEntry
local CreateGUIDList = UTILS.CreateGUIDList

local LogEntry = LibStub("EventSourcing/LogEntry")

local RosterUpdateConfigSingle = LogEntry:extend("RT.RC")

-- ------------------------ --
-- RosterUpdateConfigSingle --
-- ------------------------ --
function RosterUpdateConfigSingle:new(rosterUid, config, value)
    local o = LogEntry.new(self);
    o.r = tonumber(rosterUid) or 0
    o.c = tostring(config) or ""
    o.v = value
    return o
end

function RosterUpdateConfigSingle:rosterUid()
    return self.r
end

function RosterUpdateConfigSingle:config()
    return self.c
end

function RosterUpdateConfigSingle:value()
    return self.v
end

local RosterUpdateConfigSingleFields = mergeLists(LogEntry:fields(), { "r", "c", "v" })
function RosterUpdateConfigSingle:fields()
    return RosterUpdateConfigSingleFields
end

if not CLM.MODELS.LEDGER.REPORTTHIS then
    CLM.MODELS.LEDGER.REPORTTHIS = {}
end
CLM.MODELS.LEDGER.REPORTTHIS.ROSTER = {
    UpdateConfigSingle = RosterUpdateConfigSingle,
}
