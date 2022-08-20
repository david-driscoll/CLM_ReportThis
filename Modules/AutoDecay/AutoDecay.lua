local CLM = LibStub("ClassicLootManager").CLM

local LOG = CLM.LOG
local CONSTANTS = CLM.CONSTANTS
local ACL = CLM.MODULES.ACL
local LedgerManager = CLM.MODULES.LedgerManager
local RosterManager = CLM.MODULES.RosterManager
local PointManager = CLM.MODULES.PointManager

CLM.OPTIONS.AutoDecay = { lastDecayList = {} }

function CLM.OPTIONS.AutoDecay:Initialize()
    LOG:Warning("CLM.OPTIONS.AutoDecay")

    LedgerManager:ObserveEntryType(CLM.MODELS.LEDGER.DKP.DecayRoster, function(entry)
        self.lastDecayList[entry:rosterUid()] = tonumber(entry:time())
    end)
    LedgerManager:ObserveEntryType(CLM.MODELS.LEDGER.ROSTER.Create, function(entry)
        self.lastDecayList[entry:rosterUid()] = tonumber(entry:time())
    end)

    LedgerManager:RegisterOnUpdate(function(lag, uncommitted)
        LOG:Warning("LedgerManager:RegisterOnUpdate lag: %d uncommitted: %d", lag, uncommitted)
        if lag ~= 0 or uncommitted ~= 0 then return end

        -- local date = C_DateAndTime.GetCalendarTimeFromEpoch(0)
        -- UTILS.DumpTable(date)
        -- print(lastRosterDecay)
        -- local date = C_DateAndTime.GetCalendarTimeFromEpoch(lastRosterDecay * 1000000)
        -- UTILS.DumpTable(date)
        -- print(C_DateAndTime.GetSecondsUntilWeeklyReset())
        for name, roster in pairs(RosterManager:GetRosters()) do
            local lastRosterDecay = self.lastDecayList[roster:UID()]
            -- print(name .. "lastRosterDecay" .. tostring(lastRosterDecay))
            if lastRosterDecay then
                local sevenDays = 7 * 24 * 60 * 60 -- 604800
                local serverTimeAtNextReset = GetServerTime() + C_DateAndTime.GetSecondsUntilWeeklyReset()
                local serverTimeAtPreviousReset = serverTimeAtNextReset - sevenDays
                -- local decayTime = serverTimeAtPreviousReset
                -- local count = 0
                -- while lastRosterDecay < decayTime do
                --     count = count + 1
                --     decayTime = decayTime - sevenDays
                -- end

                local decayTime = serverTimeAtPreviousReset

                -- print(name .. " lastRosterDecay: " .. count)
                -- print(name .. " Decay count: " .. count)

                if ACL:CheckLevel(CONSTANTS.ACL.LEVEL.GUILD_MASTER) then
                    if CLM.OPTIONS.ReportThisRosterManager:GetConfiguration(roster, "autoDecay") then
                        -- while lastRosterDecay < decayTime do
                        --     -- PointManager:UpdateRosterPoints(
                        --     --     roster,
                        --     --     CLM.OPTIONS.ReportThisRosterManager:GetConfiguration(roster, "autoDecayPercent"),
                        --     --     CONSTANTS.POINT_CHANGE_REASON.DECAY,
                        --     --     CONSTANTS.POINT_MANAGER_ACTION.DECAY,
                        --     --     false
                        --     -- )
                        --     decayTime = decayTime - sevenDays
                        -- end
                    end
                end
            else
                print(name .. " lastRosterDecay: nil")
            end
        end


        -- print(string.format("seconds in week %d", 604800))
        -- print(string.format("seconds until reset %d", C_DateAndTime.GetSecondsUntilWeeklyReset()))
        -- print(string.format("server time %d", GetServerTime()))
        -- print(string.format("server time at reset %d", GetServerTime() + C_DateAndTime.GetSecondsUntilWeeklyReset()))
        -- print(string.format("server time last reset %d",
        --     GetServerTime() + C_DateAndTime.GetSecondsUntilWeeklyReset() - 604800))
        -- print(string.format("lastRosterDeacy %d", lastRosterDecay))



    end)
end
