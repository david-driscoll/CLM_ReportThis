local CLM = LibStub("ClassicLootManager").CLM

local LOG = CLM.LOG
local MODULES = CLM.MODULES
local CONSTANTS = CLM.CONSTANTS
local UTILS = CLM.UTILS
local ACL = MODULES.ACL
local StandbyStagingManager = MODULES.StandbyStagingManager
local ProfileManager = MODULES.ProfileManager
local RaidManager = MODULES.RaidManager

local function HandleSubscribe(self, data, sender)
    LOG:Trace("StandbyStagingManager:HandleSubscribe()")
    if not ACL:IsTrusted() then return end
    local raidUid = data:RaidUid()
    local raid = RaidManager:GetRaidByUid(raidUid)
    if not raid then
        LOG:Debug("Non existent raid: %s", raidUid)
        return
    end
    if raid:Status() ~= CONSTANTS.RAID_STATUS.CREATED and raid:Status() ~= CONSTANTS.RAID_STATUS.IN_PROGRESS then
        LOG:Debug("Raid %s is not in freshly created", raidUid)
        return
    end
    if not raid:Configuration():Get("selfBenchSubscribe") then
        LOG:Debug("Self-subscribe is disabled")
        return
    end
    local profile = ProfileManager:GetProfileByName(sender)
    if profile then
        local updated = false
        if RaidManager:IsInProgressingRaid() then
            local profiles = {}
            table.insert(profiles, profile)
            RaidManager:AddToStandby(raid, profiles)
            updated = true
        else
            updated = self:AddToStandby(raidUid, profile:GUID())
        end
        if updated then
            LOG:Message(CLM.L["%s has %s standby"],
                UTILS.ColorCodeText(profile:Name(), UTILS.GetClassColor(profile:Class()).hex),
                UTILS.ColorCodeText(CLM.L["requested"], "44cc44"))
        end
    else
        LOG:Warning("Missing profile for player %s", sender)
    end
    CLM.GUI.Unified:Refresh(true)
end

local function HandleRevoke(self, data, sender)
    LOG:Trace("StandbyStagingManager:HandleRevoke()")
    if not ACL:IsTrusted() then return end
    local raidUid = data:RaidUid()
    local raid = RaidManager:GetRaidByUid(raidUid)
    if not raid then
        LOG:Debug("Non existent raid: %s", raidUid)
        return
    end
    if raid:Status() ~= CONSTANTS.RAID_STATUS.CREATED and raid:Status() ~= CONSTANTS.RAID_STATUS.IN_PROGRESS then
        return
    end
    if not raid:Configuration():Get("selfBenchSubscribe") then
        LOG:Debug("Self-subscribe is disabled")
        return
    end
    local profile = ProfileManager:GetProfileByName(sender)
    if profile then
        local updated = false
        if RaidManager:IsInProgressingRaid() then
            local profiles = {}
            table.insert(profiles, profile)
            RaidManager:RemoveFromStandby(raid, profiles)
            updated = true
        else
            updated = self:RemoveFromStandby(raidUid, profile:GUID())
        end

        if updated then
            LOG:Message(CLM.L["%s has %s standby"],
                UTILS.ColorCodeText(profile:Name(), UTILS.GetClassColor(profile:Class()).hex),
                UTILS.ColorCodeText(CLM.L["revoked"], "cc4444"))
        end
    else
        LOG:Warning("Missing profile for player %s", sender)
    end
    CLM.GUI.Unified:Refresh(true)
end

local oldInitialize = StandbyStagingManager.Initialize
function StandbyStagingManager:Initialize()
    oldInitialize(self)
    self.handlers[CONSTANTS.STANDBY_STAGING_COMM.TYPE.SUBSCRIBE] = HandleSubscribe
    self.handlers[CONSTANTS.STANDBY_STAGING_COMM.TYPE.REVOKE]    = HandleRevoke
end
