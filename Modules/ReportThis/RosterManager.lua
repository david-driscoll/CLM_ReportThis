local CLM = LibStub("ClassicLootManager").CLM
local CONSTANTS = CLM.CONSTANTS
local ACL = CLM.MODULES.ACL

-- extend roster config here

local UTILS = CLM.UTILS
local LOG = CLM.LOG
local RosterManager = CLM.MODULES.RosterManager
local LedgerManager = CLM.MODULES.LedgerManager
local ConfigLedgerManager = CLM.OPTIONS.ReportThisConfigLedgerManager
local LEDGER_REPORTTHIS_ROSTER = CLM.MODELS.LEDGER.REPORTTHIS.ROSTER
local LEDGER_ROSTER = CLM.MODELS.LEDGER.ROSTER
local ReportThisRosterConfiguration = CLM.MODELS.ReportThisRosterConfiguration
local RosterManagerOptions = CLM.OPTIONS.RosterManager
local ReportThisRosterManager = {}
CLM.OPTIONS.ReportThisRosterManager = ReportThisRosterManager

local function GetRosterOption(name, option)
    LOG:Debug("RT:RosterManager:GetRosterOption(%s, %s)", name, tostring(option))
    local roster = RosterManager:GetRosterByName(name)
    if roster == nil then return nil end
    return ReportThisRosterManager:GetConfiguration(roster, option)
end

local function SetRosterOption(name, option, value)
    LOG:Debug("RT:RosterManager:SetRosterOption()")
    local roster = RosterManager:GetRosterByName(name)
    if not roster then
        LOG:Error("RT:RosterManager:SetRosterOption(): Unknown roster name %s", name)
        return
    end
    if not option then
        LOG:Error("RT:RosterManager:SetRosterOption(): Missing option")
        return
    end
    if value == nil then
        LOG:Error("RT:RosterManager:SetRosterOption(): Missing value")
        return
    end
    local current = ReportThisRosterManager:GetConfiguration(roster, option)
    if type(current) == "number" then
        value = tonumber(value)
    elseif type(current) == "string" then
        value = tostring(value)
    elseif type(current) == "boolean" then
        value = value and true or false
    end
    if current == value then
        LOG:Debug("RT:RosterManager:SetRosterOption(): No change to option [%s]. Skipping.", option)
        return
    end

    ConfigLedgerManager:Submit(LEDGER_REPORTTHIS_ROSTER.UpdateConfigSingle:new(roster:UID(), option, value), true)
end

local oldRosterManagerOptionsInitialize = RosterManagerOptions.Initialize
function RosterManagerOptions:Initialize()
    LOG:Info("oldRosterManagerOptionsInitialize()")
    oldRosterManagerOptionsInitialize(self)

    UTILS.mergeDictsInline(self.handlers, {
        auction_upgrade_cost_get = (function(name)
            return tostring(GetRosterOption(name, "upgradeCost"))
        end),
        auction_upgrade_cost_set = (function(name, value)
            SetRosterOption(name, "upgradeCost", value)
        end),
        auction_offspec_cost_get = (function(name)
            return tostring(GetRosterOption(name, "offspecCost"))
        end),
        auction_offspec_cost_set = (function(name, value)
            SetRosterOption(name, "offspecCost", value)
        end),
        auction_max_cost_get = (function(name)
            return tostring(GetRosterOption(name, "maxCost"))
        end),
        auction_max_cost_set = (function(name, value)
            SetRosterOption(name, "maxCost", value)
        end),
        auction_roll_difference_get = (function(name)
            return tostring(GetRosterOption(name, "rollDifference"))
        end),
        auction_roll_difference_set = (function(name, value)
            SetRosterOption(name, "rollDifference", value)
        end),
        auction_auto_decay_get = (function(name)
            return GetRosterOption(name, "autoDecay")
        end),
        auction_auto_decay_set = (function(name, value)
            SetRosterOption(name, "autoDecay", value)
        end),
        auction_auto_decay_percent_get = (function(name)
            return tostring(GetRosterOption(name, "autoDecayPercent"))
        end),
        auction_auto_decay_percent_set = (function(name, value)
            SetRosterOption(name, "autoDecayPercent", value)
        end),
    })
end

function ReportThisRosterManager:Initialize()

    LOG:Info("ReportThisRosterManager:Initialize()")
    self.rostersCache = {}

    LedgerManager:ObserveEntryType(LEDGER_ROSTER.Create, function(entry)
        LOG:Debug("observe(LEDGER_ROSTER.Create)")
        if not self.rostersCache[entry:rosterUid()] then
            self.rostersCache[entry:rosterUid()] = ReportThisRosterConfiguration:New()
        end
    end)

    LedgerManager:ObserveEntryType(LEDGER_ROSTER.Delete, function(entry)
        LOG:Debug("observe(LEDGER_ROSTER.Delete)")
        self.rostersCache[entry:rosterUid()] = nil
    end)

    ConfigLedgerManager:RegisterEntryType(
        LEDGER_REPORTTHIS_ROSTER.UpdateConfigSingle,
        (function(entry)
            LOG:TraceAndCount("mutator(ReportThis.RosterUpdateConfigSingle)")
            local rosterUid = entry:rosterUid()

            local roster = RosterManager:GetRosterByUid(rosterUid)
            if not roster or not self.rostersCache[entry:rosterUid()] then
                self.rostersCache[entry:rosterUid()] = ReportThisRosterConfiguration:New()
            end

            self.rostersCache[entry:rosterUid()]:Set(entry:config(), entry:value())
            RosterManagerOptions:UpdateOptions()
        end))
end

function ReportThisRosterManager:GetConfiguration(roster, option)
    LOG:Debug("ReportThisRosterManager:GetConfiguration(%s, %s)", tostring(roster), option)
    if UTILS.typeof(roster, CLM.MODELS.Roster) then roster = roster:UID() end
    LOG:Debug("self.rostersCache[roster] %s", tostring(self.rostersCache[roster] and true or false))
    if not self.rostersCache[roster] then
        self.rostersCache[roster] = ReportThisRosterConfiguration:New()
    end
    return self.rostersCache[roster]:Get(option)
end

local oldRosterManagerOptionsGenerateRosterOptions = RosterManagerOptions.GenerateRosterOptions
function RosterManagerOptions:GenerateRosterOptions(name)
    local o = oldRosterManagerOptionsGenerateRosterOptions(self, name)

    local orderStart = 100

    UTILS.mergeDictsInline(o.args.auction.args, {

        rt_header = {
            name = CLM.L["Report This Setings"],
            type = "header",
            order = orderStart,
            width = "full"
        },

        upgrade_cost = {
            name = CLM.L["Upgrade Cost"],
            desc = CLM.L["The minimum cost of an item"],
            type = "input",
            disabled = (function() return not ACL:CheckLevel(CONSTANTS.ACL.LEVEL.MANAGER) end),
            order = orderStart + 2,
            pattern = CONSTANTS.REGEXP_FLOAT_POSITIVE,
            -- width = 0.6
        },

        offspec_cost = {
            name = CLM.L["Offspec Cost"],
            desc = CLM.L["The cost of an offspec item"],
            type = "input",
            disabled = (function() return not ACL:CheckLevel(CONSTANTS.ACL.LEVEL.MANAGER) end),
            order = orderStart + 1,
            pattern = CONSTANTS.REGEXP_FLOAT_POSITIVE,
            -- width = 0.6
        },

        max_cost = {
            name = CLM.L["Max Bonus Cost"],
            desc = CLM.L["The max cost of an item"],
            type = "input",
            disabled = (function() return not ACL:CheckLevel(CONSTANTS.ACL.LEVEL.MANAGER) end),
            order = orderStart + 3,
            pattern = CONSTANTS.REGEXP_FLOAT_POSITIVE,
            -- width = 0.6
        },

        roll_difference = {
            name = CLM.L["Roll Difference"],
            desc = CLM.L["The maximum point difference between two players to roll off"],
            type = "input",
            disabled = (function() return not ACL:CheckLevel(CONSTANTS.ACL.LEVEL.MANAGER) end),
            order = orderStart + 4,
            pattern = CONSTANTS.REGEXP_FLOAT_POSITIVE,
            -- width = 0.6
        },

        auto_decay = {
            name = CLM.L["Automatic decay"],
            desc = CLM.L["Automatically decay this roster"],
            type = "toggle",
            disabled = (function() return not ACL:CheckLevel(CONSTANTS.ACL.LEVEL.MANAGER) end),
            order = orderStart + 5,
            -- width = 0.6
        },

        auto_decay_percent = {
            name = CLM.L["Automatic decay percentage"],
            desc = CLM.L["The percent to automatically decay points every week"],
            type = "input",
            disabled = (function() return not ACL:CheckLevel(CONSTANTS.ACL.LEVEL.MANAGER) end),
            order = orderStart + 6,
            pattern = CONSTANTS.REGEXP_FLOAT_POSITIVE,
            -- width = 0.6
        },
    })


    return o
end
