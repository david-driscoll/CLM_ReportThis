local CLM = LibStub("ClassicLootManager").CLM
local CONSTANTS = CLM.CONSTANTS
local ACL = CLM.MODULES.ACL

-- extend roster config here

local UTILS = CLM.UTILS
local RosterConfiguration = CLM.MODELS.RosterConfiguration
local RosterManager = CLM.MODULES.RosterManager
local RosterManagerOptions = CLM.OPTIONS.RosterManager

local oldNew = RosterConfiguration.New
function RosterConfiguration:New(i)
    local o = oldNew(self, i)

    -- the upgrade cost of an item
    o._.upgradeCost = 25
    o._.offspecCost = 0
    -- the max cost of a bonus item
    o._.maxCost = 200
    -- the difference where two people would roll off
    o._.rollDifference = 50
    o._.autoDecay = false
    o._.autoDecayPercent = 20

    return o
end

local oldFields = RosterConfiguration.fields
function RosterConfiguration:fields()
    local fields = oldFields(self)
    table.insert(fields, "upgradeCost")
    table.insert(fields, "offspecCost")
    table.insert(fields, "maxCost")
    table.insert(fields, "rollDifference")
    table.insert(fields, "autoDecay")
    table.insert(fields, "autoDecayPercent")
    return fields
end

local function IsNumeric(value) return type(value) == "number" end

local function IsBoolean(value) return type(value) == "boolean" end

local function IsPositive(value) return value >= 0 end

function RosterConfiguration._validate_upgradeCost(value)
    value = tonumber(value);
    return IsNumeric(value) and IsPositive(value)
end

function RosterConfiguration._validate_maxCost(value)
    value = tonumber(value);
    return IsNumeric(value) and IsPositive(value)
end

function RosterConfiguration._validate_offspecCost(value)
    value = tonumber(value);
    return IsNumeric(value) and IsPositive(value)
end

function RosterConfiguration._validate_rollDifference(value)
    value = tonumber(value);
    return IsNumeric(value) and IsPositive(value) and value < 100
end

function RosterConfiguration._validate_autoDecay(value)
    return IsBoolean(value)
end

function RosterConfiguration._validate_autoDecayPercent(value)
    value = tonumber(value);
    return IsNumeric(value) and IsPositive(value) and value <= 100
end

local function transform_boolean(value) return value and true or false end

local function transform_number(value) return tonumber(value) or 0 end

local TRANSFORMS = {
    upgradeCost = transform_number,
    offspecCost = transform_number,
    maxCost = transform_number,
    rollDifference = transform_number,
    autoDecay = transform_boolean,
    autoDecayPercent = transform_number,
}

local oldInflate = RosterConfiguration.inflate
function RosterConfiguration:inflate(data)
    pcall(oldInflate, self, data)
    for key, _ in pairs(TRANSFORMS) do
        if TRANSFORMS[key] then
            -- self._[key] = data[i]
            self._[key] = TRANSFORMS[key](data[key])
        end
    end
end

local oldSet = RosterConfiguration.Set
function RosterConfiguration:Set(option, value)
    if not TRANSFORMS[option] then
        return oldSet(self, option, value)
    end

    if option == nil then return end
    if self._[option] ~= nil then
        if self:Validate(option, value) then
            self._[option] = TRANSFORMS[option](value)
            self:PostProcess(option)
        end
    end
end

function RosterConfiguration:deflate()
    local result = {}
    for _, key in ipairs(self:fields()) do
        table.insert(result, self._[key])
    end
    return result
end

local function GetRosterOption(name, option)
    local roster = RosterManager:GetRosterByName(name)
    if roster == nil then return nil end
    return roster:GetConfiguration(option)
end

local function SetRosterOption(name, option, value)
    RosterManager:SetRosterConfiguration(name, option, value)
end

local oldRosterManagerOptionsInitialize = RosterManagerOptions.Initialize
function RosterManagerOptions:Initialize()
    oldRosterManagerOptionsInitialize(self);
    UTILS.mergeDictsInline(self.handlers, {
        upgrade_cost_get = (function(name)
            return tostring(GetRosterOption(name, "upgradeCost"))
        end),
        upgrade_cost_set = (function(name, value)
            SetRosterOption(name, "upgradeCost", value)
        end),
        offspec_cost_get = (function(name)
            return tostring(GetRosterOption(name, "offspecCost"))
        end),
        offspec_cost_set = (function(name, value)
            SetRosterOption(name, "offspecCost", value)
        end),
        max_cost_get = (function(name)
            return tostring(GetRosterOption(name, "maxCost"))
        end),
        max_cost_set = (function(name, value)
            SetRosterOption(name, "maxCost", value)
        end),
        roll_difference_get = (function(name)
            return tostring(GetRosterOption(name, "rollDifference"))
        end),
        roll_difference_set = (function(name, value)
            SetRosterOption(name, "rollDifference", value)
        end),
        auto_decay_get = (function(name)
            return GetRosterOption(name, "autoDecay")
        end),
        auto_decay_set = (function(name, value)
            SetRosterOption(name, "autoDecay", value)
        end),
        auto_decay_percent_get = (function(name)
            return tostring(GetRosterOption(name, "autoDecayPercent"))
        end),
        auto_decay_percent_set = (function(name, value)
            SetRosterOption(name, "autoDecayPercent", value)
        end),
    })
end

local oldRosterManagerOptionsGenerateRosterOptions = RosterManagerOptions.GenerateRosterOptions
function RosterManagerOptions:GenerateRosterOptions(name)
    local o = oldRosterManagerOptionsGenerateRosterOptions(self, name)
    UTILS.mergeDictsInline(o.args, {

        upgrade_cost = {
            name = CLM.L["Upgrade Cost"],
            desc = CLM.L["The minimum cost of an item"],
            type = "input",
            disabled = (function() return not ACL:CheckLevel(CONSTANTS.ACL.LEVEL.MANAGER) end),
            order = 20,
            pattern = CONSTANTS.REGEXP_FLOAT_POSITIVE,
            -- width = 0.6
        },

        offspec_cost = {
            name = CLM.L["Offspec Cost"],
            desc = CLM.L["The cost of an offspec item"],
            type = "input",
            disabled = (function() return not ACL:CheckLevel(CONSTANTS.ACL.LEVEL.MANAGER) end),
            order = 20,
            pattern = CONSTANTS.REGEXP_FLOAT_POSITIVE,
            -- width = 0.6
        },

        max_cost = {
            name = CLM.L["Max Bonus Cost"],
            desc = CLM.L["The max cost of an item"],
            type = "input",
            disabled = (function() return not ACL:CheckLevel(CONSTANTS.ACL.LEVEL.MANAGER) end),
            order = 20,
            pattern = CONSTANTS.REGEXP_FLOAT_POSITIVE,
            -- width = 0.6
        },

        roll_difference = {
            name = CLM.L["Roll Difference"],
            desc = CLM.L["The maximum point difference between two players to roll off"],
            type = "input",
            disabled = (function() return not ACL:CheckLevel(CONSTANTS.ACL.LEVEL.MANAGER) end),
            order = 20,
            pattern = CONSTANTS.REGEXP_FLOAT_POSITIVE,
            -- width = 0.6
        },

        auto_decay = {
            name = CLM.L["Automatic decay"],
            desc = CLM.L["Automatically decay this roster"],
            type = "toggle",
            disabled = (function() return not ACL:CheckLevel(CONSTANTS.ACL.LEVEL.MANAGER) end),
            order = 20,
            -- width = 0.6
        },

        auto_decay_percent = {
            name = CLM.L["Automatic decay percentage"],
            desc = CLM.L["The percent to automatically decay points every week"],
            type = "input",
            disabled = (function() return not ACL:CheckLevel(CONSTANTS.ACL.LEVEL.MANAGER) end),
            order = 20,
            pattern = CONSTANTS.REGEXP_FLOAT_POSITIVE,
            -- width = 0.6
        },
    })
    return o

end
