local CLM = LibStub("ClassicLootManager").CLM
local LOG = CLM.LOG

local UTILS = CLM.UTILS
local CONSTANTS = CLM.CONSTANTS
local ProfileManager = CLM.MODULES.ProfileManager
local RosterManager = CLM.MODULES.RosterManager
local GuildInfoListener = CLM.MODULES.GuildInfoListener

if not CONSTANTS.REPORTTHIS then
    CONSTANTS.REPORTTHIS = {}
end

CONSTANTS.REPORTTHIS.SLOT_VALUE_TIER = {
    OFFSPEC = CONSTANTS.SLOT_VALUE_TIER.BASE,
    UPGRADE = CONSTANTS.SLOT_VALUE_TIER.SMALL,
    BONUS   = CONSTANTS.SLOT_VALUE_TIER.LARGE
}

function UTILS.VerifyObject(name, original, copy)
    for key, value in pairs(original) do
        if not copy[key] then
            LOG:Warning("<Report This> %s is missing key %s", name, key)
        end
    end
    for key, value in pairs(copy) do
        if not original[key] then
            LOG:Warning("<Report This> %s has extra key %s", name, key)
        end
    end
end

function UTILS.SendChatMessage(message, channel, ...)
    if string.upper(channel) == "WHISPER" then
        message = "<CLM> " .. message
    end
    ChatThrottleLib:SendChatMessage("BULK", "CLM", message, channel, ...)
end

function UTILS.SendWhisper(target, message)
    UTILS.SendChatMessage(message, "WHISPER", nil, target)
end

local whisperImmediateQueue = {}
local whisperQueue = {}
local outboundWhisperCount = 0
local whisperQueueTimer = nil
local outboundWhisperTimer = nil
local function EnsureTimers()
    if not outboundWhisperTimer then
        outboundWhisperTimer = C_Timer.NewTicker(1.5, function()
            outboundWhisperCount = outboundWhisperCount - 1
            if outboundWhisperCount < 1 then
                if whisperQueueTimer then
                    outboundWhisperTimer:Cancel()
                end
                outboundWhisperTimer = nil
            end
        end)
    end

    if not whisperQueueTimer then
        whisperQueueTimer = C_Timer.NewTicker(0.25, function()
            while outboundWhisperCount < 10 do
                if #whisperImmediateQueue > 0 then
                    local whisper = table.remove(whisperImmediateQueue, 1)
                    UTILS.SendWhisper(whisper.target, whisper.message)
                    outboundWhisperCount = outboundWhisperCount + 1
                elseif #whisperQueue > 0 then
                    local whisper = table.remove(whisperQueue, 1)
                    UTILS.SendWhisper(whisper.target, whisper.message)
                    outboundWhisperCount = outboundWhisperCount + 1
                else
                    if whisperQueueTimer then
                        whisperQueueTimer:Cancel()
                    end
                    whisperQueueTimer = nil
                    break
                end
            end
        end)
    end
end

function UTILS.QueueWhisper(target, message)
    table.insert(whisperQueue, { target = target, message = message })
    EnsureTimers()
end

function UTILS.QueueWhisperImmediate(target, message)
    table.insert(whisperImmediateQueue, { target = target, message = message })
    EnsureTimers()
end

function UTILS.GetGuildRank(player)
    local name, rank, rankIndex;
    local guildSize;

    if IsInGuild() then
        guildSize = GetNumGuildMembers();
        for i = 1, guildSize do
            name, rank, rankIndex = GetGuildRosterInfo(i)
            if name == player then
                return rank;
            end
            name = strsub(name, 1, string.find(name, "-") - 1) -- required to remove server name from player (can remove in classic if this is not an issue)
            if name == player then
                return rank;
            end
        end
        return CLM.L["Not in Guild"];
    end
    return CLM.L["No Guild"]
end

local nonces = {}
function UTILS.Debounce(key, time, func)
    if not nonces[key] then
        nonces[key] = 1
    end
    nonces[key] = nonces[key] + 1
    local localNonce = nonces[key]
    C_Timer.After(time, function()
        if nonces[key] ~= localNonce then return end
        func()
    end)
end

function UTILS.CreatePattern(pattern)
    pattern = string.gsub(pattern, "[%(%)%-%+%[%]]", "%%%1")
    pattern = string.gsub(pattern, "%%s", "(.+)")
    pattern = string.gsub(pattern, "%%d", "%(%%d+%)")
    pattern = string.gsub(pattern, "%%%d%$s", "(.+)")
    pattern = string.gsub(pattern, "%%%d$d", "%(%%d+%)")
    --pattern = string.gsub(pattern, "%[", "%|H%(%.%-%)%[")
    --pattern = string.gsub(pattern, "%]", "%]%|h")
    return pattern

end

function UTILS.InferBidType(bid, currentPoints)
    if not bid then return nil end
    bid = tonumber(bid)

    if bid == 0 then
        -- We remove from the bids list but add to pass list
        return CONSTANTS.AUCTION_COMM.BID_OFFSPEC
    end

    if currentPoints < 0 then
        -- We remove from the bids list but add to pass list
        return CONSTANTS.AUCTION_COMM.BID_UPGRADE
    end

    if bid >= currentPoints then
        -- We remove from the bids list but add to pass list
        return CONSTANTS.AUCTION_COMM.BID_BONUS
    end

    if bid < currentPoints then
        return CONSTANTS.AUCTION_COMM.BID_UPGRADE
    end

    return nil
end

local function getRoster(fromRosterOrRaidOrProfileOrPlayer)
    local selectedRoster
    if UTILS.typeof(fromRosterOrRaidOrProfileOrPlayer, CLM.MODELS.Raid) then
        selectedRoster = fromRosterOrRaidOrProfileOrPlayer:Roster()
    elseif UTILS.typeof(fromRosterOrRaidOrProfileOrPlayer, CLM.MODELS.Roster) then
        selectedRoster = fromRosterOrRaidOrProfileOrPlayer
    elseif UTILS.typeof(fromRosterOrRaidOrProfileOrPlayer, CLM.MODELS.Profile) then
        for _, roster in pairs(RosterManager:GetRosters()) do
            if roster:IsProfileInRoster(fromRosterOrRaidOrProfileOrPlayer) then
                selectedRoster = roster
                break
            end
        end
    elseif not fromRosterOrRaidOrProfileOrPlayer then
        -- assume player
        for _, roster in pairs(RosterManager:GetRosters()) do
            LOG:Info("Checking roster %s", roster:Name())
            -- UTILS.DumpTable(fromRosterOrRaidOrProfileOrPlayer)
            if roster:IsProfileInRoster(ProfileManager:GetProfileByName(fromRosterOrRaidOrProfileOrPlayer)) then
                selectedRoster = roster
                break
            end
        end
    else
        for _, roster in pairs(RosterManager:GetRosters()) do
            selectedRoster = roster
            break
        end
    end
    return selectedRoster
end

local function getItemCost(selectedRoster, itemId, key)
    if itemId then
        local current = selectedRoster:GetItemValues(itemId)
        if current[key] > 0 then
            return current[key]
        end
    end
    return nil
end

function UTILS.GetCurrentPoints(fromRosterOrRaidOrProfileOrPlayer, name)
    local selectedRoster = getRoster(fromRosterOrRaidOrProfileOrPlayer)
    if not selectedRoster then return -1 end
    local profile = ProfileManager:GetProfileByName(name)
    if not profile then return 0 end

    local GUID = profile:GUID()
    if not selectedRoster:IsProfileInRoster(GUID) then return 0 end

    return selectedRoster:Standings(GUID)
end

function UTILS.CalculateItemCost(fromRosterOrRaidOrProfileOrPlayer, bidType, points, itemId)
    local selectedRoster = getRoster(fromRosterOrRaidOrProfileOrPlayer)
    local upgradeCost = UTILS.GetUpgradeCost(selectedRoster, itemId)
    local offspecCost = UTILS.GetOffspecCost(selectedRoster, itemId)
    if bidType == CONSTANTS.AUCTION_COMM.BID_OFFSPEC or bidType == CONSTANTS.AUCTION_COMM.BID_PASS then return offspecCost end
    if bidType == CONSTANTS.AUCTION_COMM.BID_UPGRADE then return upgradeCost end

    return UTILS.round(
        math.min(UTILS.GetMaxCost(selectedRoster, itemId), math.max(upgradeCost * 2, points / 2)),
        selectedRoster:GetConfiguration("roundDecimals")
    )
end

function UTILS.GetUpgradeCost(fromRosterOrRaidOrProfileOrPlayer, itemId)
    local selectedRoster = getRoster(fromRosterOrRaidOrProfileOrPlayer)
    if not selectedRoster then return -1 end

    return getItemCost(selectedRoster, itemId, CONSTANTS.REPORTTHIS.SLOT_VALUE_TIER.UPGRADE) or
        CLM.OPTIONS.ReportThisRosterManager:GetConfiguration(selectedRoster, "upgradeCost")
end

function UTILS.GetBonusCost(fromRosterOrRaidOrProfileOrPlayer, player)
    if not player then
        player = fromRosterOrRaidOrProfileOrPlayer
    end
    local selectedRoster = getRoster(fromRosterOrRaidOrProfileOrPlayer)
    if not selectedRoster then return -1 end

    return UTILS.CalculateItemCost(selectedRoster, CONSTANTS.AUCTION_COMM.BID_BONUS,
        UTILS.GetCurrentPoints(selectedRoster, player))
end

function UTILS.GetOffspecCost(fromRosterOrRaidOrProfileOrPlayer, itemId)
    local selectedRoster = getRoster(fromRosterOrRaidOrProfileOrPlayer)
    if not selectedRoster then return -1 end

    return getItemCost(selectedRoster, itemId, CONSTANTS.REPORTTHIS.SLOT_VALUE_TIER.OFFSPEC) or
        CLM.OPTIONS.ReportThisRosterManager:GetConfiguration(selectedRoster, "offspecCost")
end

function UTILS.GetMaxCost(fromRosterOrRaidOrProfileOrPlayer, itemId)
    local selectedRoster = getRoster(fromRosterOrRaidOrProfileOrPlayer)
    if not selectedRoster then return -1 end

    return getItemCost(selectedRoster, itemId, CONSTANTS.REPORTTHIS.SLOT_VALUE_TIER.BONUS) or
        CLM.OPTIONS.ReportThisRosterManager:GetConfiguration(selectedRoster, "maxCost")
end

function UTILS.GetRollDifference(fromRosterOrRaidOrProfileOrPlayer)
    local selectedRoster = getRoster(fromRosterOrRaidOrProfileOrPlayer)
    if not selectedRoster then return -1 end

    return CLM.OPTIONS.ReportThisRosterManager:GetConfiguration(selectedRoster, "rollDifference")
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

function UTILS.GetAuthorizedGuildMembers(playerSituation)
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
