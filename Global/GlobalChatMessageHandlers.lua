local CLM = LibStub("ClassicLootManager").CLM

local LOG = CLM.LOG
local MODULES = CLM.MODULES
local CONSTANTS = CLM.CONSTANTS
local UTILS = CLM.UTILS

local ACL = MODULES.ACL
local EventManager = MODULES.EventManager
local AuctionManager = MODULES.AuctionManager
local ProfileManager = MODULES.ProfileManager
local RosterManager = MODULES.RosterManager
local RaidManager = MODULES.RaidManager
local GuildInfoListener = MODULES.GuildInfoListener
local Comms = MODULES.Comms

local GlboalChatMessageHandlers = {}
local DATA_COMM_PREFIX = "rtOnline"

local function trim(s)
    return string.gsub(s, "^%s*(.-)%s*$", "%1")
end

local function GetReplyContext(event, playerName)
    if event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
        return "RAID", nil
    elseif event == "CHAT_MSG_GUILD" then
        return "GUILD", nil
    else -- fallback to whisper always - safer option
        return "WHISPER", playerName
    end
end

local function HandleBid(event, playerName, command, secondParam)
    if not AuctionManager:IsAuctionInProgress() then
        LOG:Debug("Received submit bid from %s while no auctions are in progress", playerName)
        return
    end

    local responseChannel, target = GetReplyContext(event, playerName)

    local value
    if command == CLM.L["!bid"] and secondParam then
        value = trim(secondParam)
    else
        value = string.gsub(command, "!", "")
    end

    LOG:Debug("Received submit bid from %s with value %s", playerName, value)

    local accept, reason, bidType = false, nil, nil
    if value == CLM.L["cancel"] then
        accept, reason = AuctionManager:UpdateBid(playerName,
            CLM.MODELS.BiddingCommSubmitBid:New(0, CONSTANTS.BID_TYPE.CANCEL, {}))
    elseif value == CLM.L["pass"] then
        accept, reason = AuctionManager:UpdateBid(playerName,
            CLM.MODELS.BiddingCommSubmitBid:New(0, CONSTANTS.BID_TYPE.PASS, {}))
    elseif value == CLM.L["bonus"] then
        accept, reason = AuctionManager:UpdateBid(playerName,
            CLM.MODELS.BiddingCommSubmitBid:New(0, CONSTANTS.REPORTTHIS.BID_TYPE.BONUS, {}))
    elseif value == CLM.L["upgrade"] then
        accept, reason = AuctionManager:UpdateBid(playerName,
            CLM.MODELS.BiddingCommSubmitBid:New(0, CONSTANTS.REPORTTHIS.BID_TYPE.UPGRADE, {}))
    elseif value == CLM.L["offspec"] then
        accept, reason = AuctionManager:UpdateBid(playerName,
            CLM.MODELS.BiddingCommSubmitBid:New(0, CONSTANTS.REPORTTHIS.BID_TYPE.OFFSPEC, {}))
    elseif value == CLM.L["dualspec"] then
        accept, reason = AuctionManager:UpdateBid(playerName,
            CLM.MODELS.BiddingCommSubmitBid:New(0, CONSTANTS.REPORTTHIS.BID_TYPE.DUALSPEC, {}))
    else
        local numericValue = tonumber(value)
        if type(numericValue) == "number" then
            bidType = AuctionManager:InferBidType(numericValue)
            accept, reason = AuctionManager:UpdateBid(playerName, CLM.MODELS.BiddingCommSubmitBid:New(0, bidType, {}))
        end
    end
    local reasonString = CONSTANTS.AUCTION_COMM.DENY_BID_REASONS_STRING[reason] or
        CLM.L["Invalid value provided"]

    local message = string.format(CLM.L["%s (%s) was %s%s."],
        playerName,
        string.lower(bidType or tostring(value)),
        accept and CLM.L["accepted"] or CLM.L["denied"],
        accept and "" or (": " .. reasonString))
    UTILS.SendChatMessage(message, responseChannel, nil, target)
end

function RespondDkp(from, target)
    if target then
        target = trim(target)
    end
    if not target or target == "" then
        target = from
    end
    local profile = ProfileManager:GetProfileByName(target)
    if not profile then
        UTILS.QueueWhisperImmediate(from,
            string.format(CLM.L["Missing profile for player %s."], tostring(target)))
        return
    end
    local rosters = {}
    if RaidManager:IsInActiveRaid() then
        local raid = RaidManager:GetRaid()
        if raid then
            rosters["_"] = raid:Roster()
        end
    else
        rosters = RosterManager:GetRosters()
    end
    local rostersWithPlayer = {}
    for _, roster in pairs(rosters) do
        if roster and roster:IsProfileInRoster(profile:GUID()) then
            table.insert(rostersWithPlayer, roster)
        end
    end
    if #rostersWithPlayer == 0 then
        UTILS.QueueWhisperImmediate(from,
            string.format(CLM.L["%s not present in any roster."], profile:Name()))
    else
        UTILS.QueueWhisperImmediate(from,
            string.format(CLM.L["%s standings in %d %s:"], profile:Name(),
                #rostersWithPlayer, (#rostersWithPlayer == 1) and CLM.L["roster"] or CLM.L["rosters"]))
    end
    for _, roster in ipairs(rostersWithPlayer) do
        local standings = roster:Standings(profile:GUID())
        local weeklyGains = roster:GetCurrentGainsForPlayer(profile:GUID())
        local weeklyCap = roster:GetConfiguration("weeklyCap")
        if weeklyCap > 0 then
            weeklyGains = weeklyGains .. " / " .. weeklyCap
        end
        UTILS.QueueWhisperImmediate(from,
            string.format(CLM.L["%s: %d DKP (%d this week)."],
                RosterManager:GetRosterNameByUid(roster:UID()), standings, weeklyGains)
        )
    end
end

local function HandleStandby(event, playerName, action, whoToAdd)
    local currentRaid
    for _, raid in pairs(RaidManager:ListRaids()) do
        if raid:Status() == CONSTANTS.RAID_STATUS.CREATED or raid:Status() == CONSTANTS.RAID_STATUS.IN_PROGRESS then
            currentRaid = raid
            break
        end
    end
    local responseChannel, target = GetReplyContext(event, playerName)
    if not currentRaid then
        UTILS.SendChatMessage(CLM.L["<CLM> No active raid found."], responseChannel, nil, target)
        return
    end

    if not action then
        -- list
        local standby = currentRaid:PlayersOnStandby()

        if #standby > 0 then
            local message
            for _, player in ipairs(standby) do
                local name = ProfileManager:GetProfileByGUID(player):Name()
                if message then
                    message = message .. ", " .. name
                else
                    message = name
                end
                if message:len() > 150 then
                    UTILS.SendChatMessage("<CLM> Standby list: " .. message, responseChannel, nil, target)
                    message = nil
                end
            end
            if message and message:len() > 0 then
                UTILS.SendChatMessage("<CLM> Standby list: " .. message, responseChannel, nil, target)
            end
        end
        UTILS.SendChatMessage(
            string.format(CLM.L["<CLM> %d players in raid. %d players on standby."], #currentRaid:Players(), #standby),
            responseChannel,
            nil,
            target
        )
        return
    end

    if not whoToAdd then whoToAdd = playerName end

    local profile = ProfileManager:GetProfileByName(whoToAdd)
    if currentRaid:IsPlayerInRaid(profile:GUID()) then
        UTILS.SendChatMessage(string.format(CLM.L["<CLM> %s is in the raid."], whoToAdd), responseChannel, nil,
            target)
        return
    end

    if string.lower(action) == "add" then
        if currentRaid:IsPlayerOnStandby(profile:GUID()) then
            UTILS.SendChatMessage(string.format(CLM.L["<CLM> %s is already on standby."], whoToAdd), responseChannel, nil
                ,
                target)
            return
        end
        RaidManager:AddToStandby(currentRaid, { [1] = profile })
        UTILS.SendChatMessage(string.format(CLM.L["<CLM> %s added to standby."], whoToAdd), responseChannel, nil, target)
        return
    end

    if string.lower(action) == "remove" then
        if not currentRaid:IsPlayerOnStandby(profile:GUID()) then
            UTILS.SendChatMessage(string.format(CLM.L["<CLM> %s not on standby."], whoToAdd), responseChannel, nil,
                target)
            return
        end

        RaidManager:RemoveFromStandby(currentRaid, { [1] = profile })
        UTILS.SendChatMessage(string.format(CLM.L["<CLM> %s removed from standby."], whoToAdd), responseChannel, nil,
            target)
        return
    end

    UTILS.QueueWhisperImmediate(playerName, string.format(CLM.L["<CLM> Unknown standby command %s."], whoToAdd))
end

local function SendHelp(playerName, command)
    local showCommands = string.find(command, "!command")
    local showRules = command == "!help" or string.find(command, "!rule")
    local showBidHelp = string.find(command, "!howto")

    local roster = RaidManager:GetRaid() and RaidManager:GetRaid():Roster()
    if not roster then
        -- assume player
        for _, r in pairs(RosterManager:GetRosters()) do
            if r:IsProfileInRoster(ProfileManager:GetProfileByName(playerName)) then
                roster = r
                break
            end
        end
    end

    if showRules then
        UTILS.QueueWhisper(playerName,
            "We use a modified DKP system, where your dkp is considered as bonus to your potential roll.")
        UTILS.QueueWhisper(playerName, "---- Earning Dkp ----")
        UTILS.QueueWhisper(playerName,
            "Dkp is earned based on time 5 is awarded at the start of raid, 5 for every hour of the raid and an additional 5 at the end of the raid. Additional points are given for the first time ever killing a boss and at the officers discretion.")
        UTILS.QueueWhisper(playerName, "---- Loot Distribution ----")
        UTILS.QueueWhisper(playerName,
            "Loot is distributed in a auction like format, every player is given the opportunity to bonus, upgrade, offspec or pass on an item.")
        UTILS.QueueWhisper(playerName,
            string.format("'!bonus' uses your full points toward an item but will cost at least half your points or %d which ever is greater up to a max of %d."
                , UTILS.GetUpgradeCost(roster) * 2, UTILS.GetMaxCost(roster)))
        UTILS.QueueWhisper(playerName,
            string.format("'!upgrade' uses up to %d of your points toward an item with a cost of %d.",
                UTILS.GetUpgradeCost(roster), UTILS.GetUpgradeCost(roster)))
        UTILS.QueueWhisper(playerName,
            string.format("'!offspec' for an items you might use for offspec with a cost of %d.",
                UTILS.GetOffspecCost(roster)))
        UTILS.QueueWhisper(playerName,
            string.format("Any player within %d points of one another will cause a roll off.  Your roll will be added to your points and the total will decide the winner."
                , UTILS.GetRollDifference(roster)))
    end

    if showCommands then
        UTILS.QueueWhisper(playerName, CLM.L["Available commands:"])
        if showCommands then
            UTILS.QueueWhisper(playerName, CLM.L["!help - this help menu"])
            UTILS.QueueWhisper(playerName, CLM.L["!howto - show available bidding commands"])
            UTILS.QueueWhisper(playerName, CLM.L["!rule - show rules"])
            UTILS.QueueWhisper(playerName, CLM.L["!dkp - show your dkp or the players DKP"])
            UTILS.QueueWhisper(playerName, CLM.L["!standby - list the current standby players"])
            UTILS.QueueWhisper(playerName,
                CLM.L["!standby add [player] - add yourself (or optional character) to standby"])
            UTILS.QueueWhisper(playerName,
                CLM.L["!standby remove [player] - remove yourself (or optional character) to standby"])
        end
        UTILS.QueueWhisper(playerName,
            string.format(CLM.L["!bonus - submit bonus bid.  Cost: %d"], UTILS.GetBonusCost(playerName)))
        UTILS.QueueWhisper(playerName,
            string.format(CLM.L["!upgrade - submit upgrade bid. Cost: %d"], UTILS.GetUpgradeCost(roster)))
        UTILS.QueueWhisper(playerName,
            string.format(CLM.L["!offspec - submit offspec bid.  Cost: %d"], UTILS.GetOffspecCost(roster)))
        UTILS.QueueWhisper(playerName, CLM.L["!pass - pass on the item"])
        UTILS.QueueWhisper(playerName, CLM.L["!cancel - cancel your bid"])
    end

    if showBidHelp then
        UTILS.QueueWhisper(playerName, CLM.L["Available bid commands:"])
        UTILS.QueueWhisper(playerName,
            string.format(CLM.L["!bonus - submit bonus bid.  Cost: %d"], UTILS.GetBonusCost(playerName)))
        UTILS.QueueWhisper(playerName,
            string.format(CLM.L["!upgrade - submit upgrade bid. Cost: %d"], UTILS.GetUpgradeCost(roster)))
        UTILS.QueueWhisper(playerName,
            string.format(CLM.L["!offspec - submit offspec bid.  Cost: %d"], UTILS.GetOffspecCost(roster)))
        UTILS.QueueWhisper(playerName, CLM.L["!pass - pass on the item"])
        UTILS.QueueWhisper(playerName, CLM.L["!cancel - cancel your bid"])
    end
end

local function createKey(value)
    local key = tostring(value.status)
    key = key .. tostring(value.isInARaid and value.isInMyRaid and 0 or 1)
    key = key .. tostring(value.isInARaid and 0 or 1)
    key = key .. tostring(value.manager and 0 or 1)
    key = key .. tostring(value.assistant and 0 or 1)
    return key .. value.name
end

local function IdentifyRaidMembers(authorizedGuildMembers)
    if not IsInRaid() then return end
    -- Check raid
    for i = 1, MAX_RAID_MEMBERS do
        local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
        if name then
            name = UTILS.RemoveServer(name)
            if authorizedGuildMembers[name] then
                authorizedGuildMembers[name].online = online
                authorizedGuildMembers[name].isInMyRaid = true
            end
        end
    end
end

local function GetAuthorizedGuildMembers(playerSituation)
    if not playerSituation then playerSituation = {} end
    local senders = {}
    local ranks = GuildInfoListener:GetRanks()
    for i = 1, GetNumGuildMembers() do
        local name, rankName, rankIndex, _, _, _, _, _, isOnline, status = GetGuildRosterInfo(i)
        rankIndex = rankIndex + 1
        local rank = ranks[rankIndex]
        if rank.isAssistant or rank.isManager then
            name = UTILS.RemoveServer(name)
            local value = {
                name = name,
                status = status,
                rankIndex = rankIndex,
                manager = rank.isManager,
                assistant = rank.isAssistant,
                online = isOnline,
                isInMyRaid = false,
                isInARaid = playerSituation[name]
            }
            senders[name] = value
        end
    end
    IdentifyRaidMembers(senders)
    return senders
end

local function GetAuthorizedSender(authorizedGuildMembers)

    local senders = {}
    for _, value in pairs(authorizedGuildMembers) do
        if value.online then
            table.insert(senders, value)
        end
    end

    table.sort(senders, (function(first, second) return createKey(first) < createKey(second) end))
    -- UTILS.DumpTable(senders)

    return senders[1].name
end

function GlboalChatMessageHandlers:GetAuthorizedSender(event)
    if event == "CHAT_MSG_WHISPER" then
        return UTILS.whoami()
    end

    if not self.authorizedGuildMembers then
        self.authorizedGuildMembers = GetAuthorizedGuildMembers(self.playerRaidSituation)
    end

    if not self.authorizedSender then
        self.authorizedSender = GetAuthorizedSender(self.authorizedGuildMembers)
    end
    return self.authorizedSender
end

function GlboalChatMessageHandlers:Initialize()
    if not ACL:IsTrusted() then return end
    if not CLM.GlobalConfigs:GetAllowChatCommands() then return end

    --requestPeerStatusFromGuild
    self.authorizedSender = nil
    self.authorizedGuildMembers = nil
    self.playerRaidSituation = {}
    EventManager:RegisterWoWEvent({ "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE" },
        (function(...)
            self.authorizedGuildMembers = nil
        end))
    EventManager:RegisterWoWEvent({ "GROUP_ROSTER_UPDATE" },
        (function(...)
            self.authorizedGuildMembers = GetAuthorizedGuildMembers(self.playerRaidSituation)
            Comms:Send(DATA_COMM_PREFIX, { notify = { isInRaid = IsInRaid() } }, CONSTANTS.COMMS.DISTRIBUTION.GUILD)
        end))

    Comms:Register(DATA_COMM_PREFIX,
        (function(rawMessage, distribution, sender)
            sender = UTILS.RemoveServer(sender)

            if rawMessage and rawMessage.notify then
                self.authorizedSender = nil
                self.playerRaidSituation[sender] = rawMessage.notify.isInRaid or false

                Comms:Send(DATA_COMM_PREFIX, { confirm = { isInRaid = IsInRaid() } },
                    CONSTANTS.COMMS.DISTRIBUTION.WHISPER, sender, CONSTANTS.COMMS.PRIORITY.ALERT)
            elseif rawMessage and rawMessage.confirm then
                self.playerRaidSituation[sender] = rawMessage.confirm.isInRaid or false
            end

            if self.authorizedGuildMembers and self.authorizedGuildMembers[sender] then
                self.authorizedGuildMembers[sender].isInARaid = self.playerRaidSituation[sender]
            end
        end),
        (function()
            return ACL:IsTrusted()
        end), true)

    C_Timer.After(1, (function()
        Comms:Send(DATA_COMM_PREFIX, { notify = { isInRaid = IsInRaid() } }, CONSTANTS.COMMS.DISTRIBUTION.GUILD)
    end))

    EventManager:RegisterWoWEvent({ "CHAT_MSG_WHISPER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD" },
        (function(addon, event, text, playerName, ...)
            -- TODO: relax this a bit
            LOG:Debug("EventManager:RegisterWoWEvent %s %s %s %s",
                tostring(addon),
                tostring(event), tostring(text),
                tostring(playerName)
            )
            if not text or strsub(text, 1, 1) ~= '!' then return end
            local authorizedSender = GlboalChatMessageHandlers:GetAuthorizedSender(event)
            LOG:Debug("GlboalChatMessageHandlers:Initialize authorizedSender %s", authorizedSender)
            if UTILS.whoami() ~= authorizedSender then
                LOG:Debug("GlboalChatMessageHandlers:Initialize not authorizedSender", authorizedSender)
                return
            end

            playerName = UTILS.RemoveServer(playerName)
            local params = { strsplit(" ", text) }
            local command = params[1]
            if command then
                command = command:lower()

                if command == CLM.L["!bid"]
                    or command == CLM.L["!bonus"]
                    or command == CLM.L["!upgrade"]
                    or command == CLM.L["!offspec"]
                    or command == CLM.L["!pass"]
                    or command == CLM.L["!cancel"]
                then
                    local a = AuctionManager:GetTheAuctioneer()
                    if a and a ~= UTILS.whoami() then
                        if event == "CHAT_MSG_WHISPER" then
                            UTILS.SendWhisper(playerName,
                                string.format(string.format(CLM.L["Please whisper %s to use bid commands"], a), a)
                            )
                        end
                        return
                    end
                    HandleBid(event, playerName, command, params[2])
                elseif command == CLM.L["!dkp"] then
                    RespondDkp(playerName, params[2])
                elseif command == CLM.L["!wl"] or command == CLM.L["!standby"] then
                    HandleStandby(event, playerName, params[2], params[3])
                elseif command == CLM.L["!help"]
                    or command == CLM.L["!howto"]
                    or command == CLM.L["!rule"]
                    or command == CLM.L["!rules"]
                    or command == CLM.L["!commands"]
                    or command == CLM.L["!command"]
                then
                    SendHelp(playerName, command)
                end
            end
        end))
    -- Suppress incoming chat commands
    if CLM.GlobalConfigs:GetSuppressIncomingChatCommands() then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", (function(_, _, message, ...)
            message = message:lower()
            if message:find("!dkp") == 1
                or message:find("!bid") == 1
                or message:find("!howto") == 1
                or message:find("!bonus") == 1
                or message:find("!upgrade") == 1
                or message:find("!offspec") == 1
                or message:find("!pass") == 1
                or message:find("!cancel") == 1
                or message:find("!wl") == 1
                or message:find("!standby") == 1
                or message:find("!help") == 1
                or message:find("!rule") == 1
                or message:find("!command") == 1
            then
                return true
            end
            return false
        end))
    end
    -- Suppress outgoing CLM responses
    if CLM.GlobalConfigs:GetSuppressOutgoingChatCommands() then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", (function(_, _, message, ...)
            if message:find("<CLM>") == 1 then
                return true
            end
            return false
        end))
    end
end

CLM.GlboalChatMessageHandlers = GlboalChatMessageHandlers
