local CLM = LibStub("ClassicLootManager").CLM

local ReportThisRosterConfiguration = {} -- Roster Configuration
-- ------------------- --
-- RosterConfiguration --
-- ------------------- --
function ReportThisRosterConfiguration:New(i)
    local o = i or {}

    setmetatable(o, self)
    self.__index = self

    if i then return o end

    o._ = {}
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

-- ------------------------ --
-- ADD NEW  ONLY AT THE END --
-- ------------------------ --
function ReportThisRosterConfiguration:fields()
    return {
        "upgradeCost",
        "offspecCost",
        "maxCost",
        "rollDifference",
        "autoDecay",
        "autoDecayPercent",
    }
end

function ReportThisRosterConfiguration:Storage()
    return self._
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

function ReportThisRosterConfiguration:inflate(data)
    --  Fix for bossKillBonusValue fuckup with adding in between
    if #data < 22 then
        table.insert(data, 10, 0)
    end
    for i, key in ipairs(self:fields()) do
        -- self._[key] = data[i]
        self._[key] = TRANSFORMS[key](data[i])
    end
end

function ReportThisRosterConfiguration:deflate()
    local result = {}
    for _, key in ipairs(self:fields()) do
        table.insert(result, self._[key])
    end
    return result
end

function ReportThisRosterConfiguration:Copy(o)
    for k, v in pairs(o._) do
        self._[k] = v
    end
end

function ReportThisRosterConfiguration:Get(option)
    if option ~= nil then
        return self._[option]
    end
    return nil
end

function ReportThisRosterConfiguration:Set(option, value)
    if option == nil then return end
    if self._[option] ~= nil then
        if self:Validate(option, value) then
            self._[option] = TRANSFORMS[option](value)
            self:PostProcess(option)
        end
    end
end

function ReportThisRosterConfiguration:Validate(option, value)
    local callback = "_validate_" .. option
    if type(self[callback]) == "function" then
        local r = self[callback](value)
        return r
    end

    return true -- TODO: true or false?
end

function ReportThisRosterConfiguration:PostProcess(option)
end

local function IsNumeric(value) return type(value) == "number" end

local function IsBoolean(value) return type(value) == "boolean" end

local function IsPositive(value) return value >= 0 end

function ReportThisRosterConfiguration._validate_upgradeCost(value)
    value = tonumber(value);
    return IsNumeric(value) and IsPositive(value)
end

function ReportThisRosterConfiguration._validate_maxCost(value)
    value = tonumber(value);
    return IsNumeric(value) and IsPositive(value)
end

function ReportThisRosterConfiguration._validate_offspecCost(value)
    value = tonumber(value);
    return IsNumeric(value) and IsPositive(value)
end

function ReportThisRosterConfiguration._validate_rollDifference(value)
    value = tonumber(value);
    return IsNumeric(value) and IsPositive(value) and value < 100
end

function ReportThisRosterConfiguration._validate_autoDecay(value)
    return IsBoolean(value)
end

function ReportThisRosterConfiguration._validate_autoDecayPercent(value)
    value = tonumber(value);
    return IsNumeric(value) and IsPositive(value) and value <= 100
end

CLM.MODELS.ReportThisRosterConfiguration = ReportThisRosterConfiguration
