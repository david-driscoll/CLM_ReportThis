local CLM = LibStub("ClassicLootManager").CLM
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local LOG = CLM.LOG
local CONSTANTS = CLM.CONSTANTS
local ACL = CLM.MODULES.ACL
local LedgerManager = CLM.MODULES.LedgerManager
local RosterManager = CLM.MODULES.RosterManager
local PointManager = CLM.MODULES.PointManager

local xpcall = xpcall

local function errorhandler(err)
    return geterrorhandler()(err)
end

local function safecall(func, ...)
    if func then
        return xpcall(func, errorhandler, ...)
    end
end

local function confirmPopup(message, successFunc, cancelFunc, ...)
    local frame = AceConfigDialog.popup
    frame:Show()
    frame.text:SetText(message)
    -- From StaticPopup.lua
    -- local height = 32 + text:GetHeight() + 2;
    -- height = height + 6 + accept:GetHeight()
    -- We add 32 + 2 + 6 + 21 (button height) == 61
    local height = 61 + frame.text:GetHeight()
    frame:SetHeight(height)

    frame.accept:ClearAllPoints()
    frame.accept:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -6, 16)
    frame.cancel:Show()

    local t = { ... }
    local tCount = select("#", ...)
    frame.accept:SetScript("OnClick", function(self)
        safecall(successFunc, unpack(t, 1, tCount)) -- Manually set count as unpack() stops on nil (bug with #table)
        frame:Hide()
        self:SetScript("OnClick", nil)
        frame.cancel:SetScript("OnClick", nil)
    end)
    frame.cancel:SetScript("OnClick", function(self)
        safecall(cancelFunc, unpack(t, 1, tCount)) -- Manually set count as unpack() stops on nil (bug with #table)
        frame:Hide()
        self:SetScript("OnClick", nil)
        frame.accept:SetScript("OnClick", nil)
    end)
end

local AutoDecay = { lastDecayList = {}, rosterCreated = {} }
CLM.OPTIONS.AutoDecay = AutoDecay

function AutoDecay:Initialize()
    LOG:Warning("CLM.OPTIONS.AutoDecay")

    local firstRun = true

    self.decayQueue = {}

    LedgerManager:ObserveEntryType(CLM.MODELS.LEDGER.DKP.DecayRoster, function(entry)
        self.rosterCreated[entry:rosterUid()] = tonumber(entry:time())
        self.lastDecayList[entry:rosterUid()] = tonumber(entry:time())
    end)
    LedgerManager:ObserveEntryType(CLM.MODELS.LEDGER.ROSTER.Create, function(entry)
        self.lastDecayList[entry:rosterUid()] = tonumber(entry:time())
    end)

    LedgerManager:RegisterOnUpdate(function(lag, uncommitted)
        LOG:Warning("LedgerManager:RegisterOnUpdate lag: %d uncommitted: %d", lag, uncommitted)
        if lag ~= 0 or uncommitted ~= 0 then return end
        if #self.decayQueue > 0 then return end

        -- local date = C_DateAndTime.GetCalendarTimeFromEpoch(0)
        -- UTILS.DumpTable(date)
        -- print(lastRosterDecay)
        -- local date = C_DateAndTime.GetCalendarTimeFromEpoch(lastRosterDecay * 1000000)
        -- UTILS.DumpTable(date)
        -- print(C_DateAndTime.GetSecondsUntilWeeklyReset())
        for name, roster in pairs(RosterManager:GetRosters()) do
            local lastRosterDecay = self.lastDecayList[roster:UID()]
            if lastRosterDecay then
                local sevenDays = 604800 -- 7 * 24 * 60 * 60 -- 604800
                local serverTimeAtNextReset = GetServerTime() + C_DateAndTime.GetSecondsUntilWeeklyReset()
                local serverTimeAtPreviousReset = serverTimeAtNextReset - sevenDays

                if ACL:CheckLevel(CONSTANTS.ACL.LEVEL.GUILD_MASTER) then
                    if CLM.OPTIONS.ReportThisRosterManager:GetConfiguration(roster, "autoDecay") then
                        if serverTimeAtPreviousReset > lastRosterDecay then
                            -- queue the decay
                            table.insert(self.decayQueue, {
                                name = name,
                                roster = roster,
                                percent = CLM.OPTIONS.ReportThisRosterManager:GetConfiguration(roster, "autoDecayPercent")
                            })
                        end
                    end
                end
            end
        end

        C_Timer.After(firstRun and 10 or 1, function() self:DequeueDecay() end)
        firstRun = false


        -- print(string.format("seconds in week %d", 604800))
        -- print(string.format("seconds until reset %d", C_DateAndTime.GetSecondsUntilWeeklyReset()))
        -- print(string.format("server time %d", GetServerTime()))
        -- print(string.format("server time at reset %d", GetServerTime() + C_DateAndTime.GetSecondsUntilWeeklyReset()))
        -- print(string.format("server time last reset %d",
        --     GetServerTime() + C_DateAndTime.GetSecondsUntilWeeklyReset() - 604800))
        -- print(string.format("lastRosterDeacy %d", lastRosterDecay))
    end)
end

local function decayRosterConfim(roster, percent)
    PointManager:UpdateRosterPoints(
        roster,
        percent,
        CONSTANTS.POINT_CHANGE_REASON.DECAY,
        CONSTANTS.POINT_MANAGER_ACTION.DECAY,
        false
    )
    C_Timer.After(1, function() AutoDecay:DequeueDecay() end)
end

local function cancelDecay()
    C_Timer.After(1, function() AutoDecay:DequeueDecay() end)
end

function AutoDecay:DequeueDecay()
    if #self.decayQueue == 0 then return end
    local decay = table.remove(self.decayQueue, 1)
    confirmPopup(string.format("Decay missing for %s. Would you like to run the decay now?", decay.name),
        decayRosterConfim, cancelDecay, decay.roster, decay.percent)
end
