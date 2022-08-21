local CLM = LibStub("ClassicLootManager") and LibStub("ClassicLootManager").CLM
if not CLM then return end

local UTILS = CLM.UTILS
local LOG = CLM.LOG

local CONSTANTS = CLM.CONSTANTS
local ACL = CLM.MODULES.ACL
local ConfigManager = CLM.MODULES.ConfigManager
local LootQueueManager = CLM.MODULES.LootQueueManager
local Comms = CLM.MODULES.Comms
local DATA_COMM_PREFIX = "rtSettingsPush"

-- extend roster config here

local SettingsPush = {}
CLM.OPTIONS.SettingsPush = SettingsPush

local function GetSettings(obj)
    local settings = {}

    for key, value in pairs(obj) do
        if string.find(key, "danger_zone_") ~= 1
            and string.find(key, "logger_") ~= 1
            and string.find(key, "bidding_") ~= 1
            and string.find(key, "settings_push_") ~= 1
            and string.find(key, "changelog_") ~= 1
            and (string.find(key, "global_raid_") == 1 or string.find(key, "global_") ~= 1)
        then
            if value.get and value.set then
                settings[key] = value.get()
            end
        end
    end

    return { settings = settings, other = {
        loot_queue_ignore_classes = LootQueueManager.db.ignoredClasses
    } }
end

function SettingsPush:Initialize()
    Comms:Register(DATA_COMM_PREFIX,
        (function(rawMessage, distribution, sender)
            local options = ConfigManager.options[CLM.CONSTANTS.CONFIGS.GROUP.GLOBAL].args
            if rawMessage and rawMessage.settings then
                for key, value in pairs(rawMessage.settings) do
                    if options[key] and options[key].set then
                        options[key]:set(value)
                    end
                end
            end
            if rawMessage and rawMessage.other then
                for key, value in pairs(rawMessage.other) do
                    if key == "loot_queue_ignore_classes" then
                        LootQueueManager.db.ignoredClasses = value
                    end
                end
            end
            ConfigManager:UpdateOptions(CONSTANTS.CONFIGS.GROUP.GLOBAL)
        end),
        (function()
            return ACL:CheckLevel(CONSTANTS.ACL.LEVEL.MANAGER)
        end))


    ConfigManager:Register(CLM.CONSTANTS.CONFIGS.GROUP.GLOBAL, {
        settings_push_header = {
            type = "header",
            name = CLM.L["Sync Settings"],
            order = 9000
        },
        settings_push_push = {
            name = CLM.L["Push Settings to managers"],
            desc = CLM.L["Pushes all the relevant settings to the online managers (loot rules are done automatically)."],
            type = "execute",
            confirm = true,
            width = "double",
            func = function() SettingsPush:PushSettings() end,
            order = 9001
        },
    })
end

function SettingsPush:PushSettings()
    local settings = GetSettings(ConfigManager.options[CLM.CONSTANTS.CONFIGS.GROUP.GLOBAL].args)
    for key, value in pairs(UTILS.GetAuthorizedGuildMembers()) do

        if value.online and value.manager and value.name ~= UTILS.whoami() then
            Comms:Send(DATA_COMM_PREFIX, settings, CONSTANTS.COMMS.DISTRIBUTION.WHISPER, value.name)
        end
    end
end

-- SettingsPush:Initialize()
-- MODULES.ConfigManager:Register(CLM.CONSTANTS.CONFIGS.GROUP.GLOBAL, options)
