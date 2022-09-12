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
    OFFSPEC  = CONSTANTS.SLOT_VALUE_TIER.BASE,
    DUALSPEC = CONSTANTS.SLOT_VALUE_TIER.SMALL,
    UPGRADE  = CONSTANTS.SLOT_VALUE_TIER.MEDIUM,
    BONUS    = CONSTANTS.SLOT_VALUE_TIER.MAX
}

CONSTANTS.REPORTTHIS.BID_TYPE = {
    OFFSPEC = CONSTANTS.BID_TYPE[CONSTANTS.REPORTTHIS.SLOT_VALUE_TIER.OFFSPEC],
    DUALSPEC = CONSTANTS.BID_TYPE[CONSTANTS.REPORTTHIS.SLOT_VALUE_TIER.DUALSPEC],
    UPGRADE = CONSTANTS.BID_TYPE[CONSTANTS.REPORTTHIS.SLOT_VALUE_TIER.UPGRADE],
    BONUS = CONSTANTS.BID_TYPE[CONSTANTS.REPORTTHIS.SLOT_VALUE_TIER.BONUS],
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
    if bidType == CONSTANTS.REPORTTHIS.BID_TYPE.OFFSPEC or bidType == CONSTANTS.REPORTTHIS.BID_TYPE.DUALSPEC then return offspecCost end
    if bidType == CONSTANTS.REPORTTHIS.BID_TYPE.UPGRADE then return upgradeCost end

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

    return UTILS.CalculateItemCost(selectedRoster, CONSTANTS.REPORTTHIS.BID_TYPE.BONUS,
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

--[[ Data ]] --

do

    local data = {}

    local function merge(t1, ...)
        local ac = select('#', ...)

        if ac == 0 then
            return t1
        end
        for ax = 1, ac do

            local t2 = select(ax, ...)
            for _, v in ipairs(t2) do
                table.insert(t1, v)
            end
        end
        return t1
    end

    local wandOnly = {
        Enum.ItemWeaponSubclass.Bows,
        Enum.ItemWeaponSubclass.Guns,
        Enum.ItemWeaponSubclass.Thrown,
        Enum.ItemWeaponSubclass.Crossbow
    }
    local noRangedWeapon = merge({ Enum.ItemWeaponSubclass.Wand })


    local noIdolSlot = {
        Enum.ItemArmorSubclass.Libram,
        Enum.ItemArmorSubclass.Idol,
        Enum.ItemArmorSubclass.Totem,
        Enum.ItemArmorSubclass.Sigil,
    }

    local function excludeOtherRelics(value)
        local i = {}
        for _, v in ipairs(noIdolSlot) do
            if v ~= value then
                table.insert(i, v)
            end
        end
        return i
    end

    data['DEATHKNIGHT'] = {
        [Enum.ItemClass.Weapon] = -- weapon, armor, dual-wield
        merge({
            Enum.ItemWeaponSubclass.Bows,
            Enum.ItemWeaponSubclass.Guns,
            Enum.ItemWeaponSubclass.Staff,
            Enum.ItemWeaponSubclass.Warglaive,
            Enum.ItemWeaponSubclass.Unarmed,
            Enum.ItemWeaponSubclass.Dagger,
        },
            noRangedWeapon,
            excludeOtherRelics(Enum.ItemArmorSubclass.Sigil)
        ),
        [Enum.ItemClass.Armor] = { Enum.ItemArmorSubclass.Shield },
        idealArmor = Enum.ItemArmorSubclass.Plate,
        dualWield = false
    }
    data['DEMONHUNTER'] = {
        [Enum.ItemClass.Weapon] = merge({
            Enum.ItemWeaponSubclass.Axe2H,
            Enum.ItemWeaponSubclass.Mace1H,
            Enum.ItemWeaponSubclass.Mace2H,
            Enum.ItemWeaponSubclass.Polearm,
            Enum.ItemWeaponSubclass.Sword2H,
            Enum.ItemWeaponSubclass.Staff,
        },
            noRangedWeapon
        ),
        [Enum.ItemClass.Armor] = { Enum.ItemArmorSubclass.Mail, Enum.ItemArmorSubclass.Plate,
            Enum.ItemArmorSubclass.Shield },
        idealArmor = Enum.ItemArmorSubclass.Leather,
        dualWield = true
    }
    data['DRUID'] = {
        [Enum.ItemClass.Weapon] = merge({
            Enum.ItemWeaponSubclass.Axe1H,
            Enum.ItemWeaponSubclass.Axe2H,
            Enum.ItemWeaponSubclass.Sword1H,
            Enum.ItemWeaponSubclass.Sword2H,
        },
            noRangedWeapon,
            excludeOtherRelics(Enum.ItemArmorSubclass.Sigil)
        ),
        [Enum.ItemClass.Armor] = { Enum.ItemArmorSubclass.Mail, Enum.ItemArmorSubclass.Plate,
            Enum.ItemArmorSubclass.Shield },
        idealArmor = Enum.ItemArmorSubclass.Leather,
        dualWield = false
    }
    data['HUNTER'] = {
        [Enum.ItemClass.Weapon] = merge({
            Enum.ItemWeaponSubclass.Mace1H,
            Enum.ItemWeaponSubclass.Mace2H,
            Enum.ItemWeaponSubclass.Warglaive,
            Enum.ItemWeaponSubclass.Thrown,
            Enum.ItemWeaponSubclass.Wand,

        }, noIdolSlot
        ),
        [Enum.ItemClass.Armor] = {
            Enum.ItemArmorSubclass.Plate,
            Enum.ItemArmorSubclass.Shield
        },
        idealArmor = Enum.ItemArmorSubclass.Mail,
        dualWield = true
    }
    data['MAGE'] = {
        [Enum.ItemClass.Weapon] = merge({
            Enum.ItemWeaponSubclass.Axe1H,
            Enum.ItemWeaponSubclass.Axe2H,
            Enum.ItemWeaponSubclass.Mace1H,
            Enum.ItemWeaponSubclass.Mace2H,
            Enum.ItemWeaponSubclass.Polearm,
            Enum.ItemWeaponSubclass.Sword2H,
            Enum.ItemWeaponSubclass.Warglaive,
            Enum.ItemWeaponSubclass.Unarmed
        },
            wandOnly,
            noIdolSlot
        ),
        [Enum.ItemClass.Armor] = {
            Enum.ItemArmorSubclass.Leather,
            Enum.ItemArmorSubclass.Mail,
            Enum.ItemArmorSubclass.Plate,
            Enum.ItemArmorSubclass.Shield
        },
        idealArmor = Enum.ItemArmorSubclass.Cloth,
        dualWield = false
    }
    data['MONK'] = {
        [Enum.ItemClass.Weapon] = merge({
            Enum.ItemWeaponSubclass.Axe2H,
            Enum.ItemWeaponSubclass.Mace2H,
            Enum.ItemWeaponSubclass.Sword2H,
            Enum.ItemWeaponSubclass.Warglaive,
            Enum.ItemWeaponSubclass.Dagger,
        },
            noRangedWeapon,
            noIdolSlot
        ),
        [Enum.ItemClass.Armor] = {
            Enum.ItemArmorSubclass.Mail,
            Enum.ItemArmorSubclass.Plate,
            Enum.ItemArmorSubclass.Shield
        },
        idealArmor = Enum.ItemArmorSubclass.Leather,
        dualWield = true
    }
    data['PALADIN'] = {
        [Enum.ItemClass.Weapon] = merge({
            Enum.ItemWeaponSubclass.Warglaive,
            Enum.ItemWeaponSubclass.Staff,
            Enum.ItemWeaponSubclass.Unarmed,
            Enum.ItemWeaponSubclass.Dagger
        },
            noRangedWeapon,
            excludeOtherRelics(Enum.ItemArmorSubclass.Sigil)
        ),
        [Enum.ItemClass.Armor] = {},
        idealArmor = Enum.ItemArmorSubclass.Plate,
        dualWield = false
    }
    data['PRIEST'] = {
        [Enum.ItemClass.Weapon] = merge({
            Enum.ItemWeaponSubclass.Axe1H,
            Enum.ItemWeaponSubclass.Axe2H,
            Enum.ItemWeaponSubclass.Mace2H,
            Enum.ItemWeaponSubclass.Polearm,
            Enum.ItemWeaponSubclass.Sword1H,
            Enum.ItemWeaponSubclass.Sword2H,
            Enum.ItemWeaponSubclass.Warglaive,
            Enum.ItemWeaponSubclass.Unarmed
        },
            wandOnly,
            noIdolSlot
        ),
        [Enum.ItemClass.Armor] = {
            Enum.ItemArmorSubclass.Leather,
            Enum.ItemArmorSubclass.Mail,
            Enum.ItemArmorSubclass.Plate,
            Enum.ItemArmorSubclass.Shield
        },
        idealArmor = Enum.ItemArmorSubclass.Cloth,
        dualWield = false
    }
    data['ROGUE'] = {
        [Enum.ItemClass.Weapon] = {
            Enum.ItemWeaponSubclass.Axe2H,
            Enum.ItemWeaponSubclass.Mace2H,
            Enum.ItemWeaponSubclass.Polearm,
            Enum.ItemWeaponSubclass.Sword2H,
            Enum.ItemWeaponSubclass.Warglaive,
            Enum.ItemWeaponSubclass.Staff,
            Enum.ItemWeaponSubclass.Wand
        },
        [Enum.ItemClass.Armor] = {
            Enum.ItemArmorSubclass.Mail,
            Enum.ItemArmorSubclass.Plate,
            Enum.ItemArmorSubclass.Shield
        },
        idealArmor = Enum.ItemArmorSubclass.Leather,
        dualWield = true
    }
    data['SHAMAN'] = {
        [Enum.ItemClass.Weapon] = merge({
            Enum.ItemWeaponSubclass.Polearm,
            Enum.ItemWeaponSubclass.Sword1H,
            Enum.ItemWeaponSubclass.Sword2H,
            Enum.ItemWeaponSubclass.Warglaive
        },
            noRangedWeapon,
            noIdolSlot
        ),
        [Enum.ItemClass.Armor] = { Enum.ItemArmorSubclass.Plate },
        idealArmor = Enum.ItemArmorSubclass.Mail,
        dualWield = true
    }
    data['WARLOCK'] = {
        [Enum.ItemClass.Weapon] = merge({
            Enum.ItemWeaponSubclass.Axe1H,
            Enum.ItemWeaponSubclass.Axe2H,
            Enum.ItemWeaponSubclass.Mace1H,
            Enum.ItemWeaponSubclass.Mace2H,
            Enum.ItemWeaponSubclass.Polearm,
            Enum.ItemWeaponSubclass.Sword2H,
            Enum.ItemWeaponSubclass.Warglaive,
            Enum.ItemWeaponSubclass.Unarmed
        },
            wandOnly,
            noIdolSlot
        ),
        [Enum.ItemClass.Armor] = {
            Enum.ItemArmorSubclass.Leather,
            Enum.ItemArmorSubclass.Mail,
            Enum.ItemArmorSubclass.Plate,
            Enum.ItemArmorSubclass.Shield
        },
        idealArmor = Enum.ItemArmorSubclass.Cloth,
        dualWield = false
    }
    data['WARRIOR'] = {
        [Enum.ItemClass.Weapon] = {
            Enum.ItemWeaponSubclass.Warglaive,
            Enum.ItemWeaponSubclass.Wand
        },
        [Enum.ItemClass.Armor] = {},
        idealArmor = Enum.ItemArmorSubclass.Plate,
        dualWield = true
    }


    for _, usable in pairs(data) do
        do
            local list = {}
            for _, subclass in pairs(Enum.ItemArmorSubclass) do
                list[subclass] = true
            end
            for _, subclass in ipairs(usable[Enum.ItemClass.Armor]) do
                list[subclass] = false
            end
            usable[Enum.ItemClass.Armor] = list
        end
        do
            local list = {}
            for _, subclass in pairs(Enum.ItemWeaponSubclass) do
                list[subclass] = true
            end
            for _, subclass in ipairs(usable[Enum.ItemClass.Weapon]) do
                list[subclass] = false
            end
            usable[Enum.ItemClass.Weapon] = list
        end

    end

    --[[ API ]] --
    function UTILS.IsUsableByPlayer(playerClass, itemtype, itemSubtype, slot)
        if itemtype and itemSubtype and data[string.upper(playerClass)] and data[playerClass][itemtype] then
            local record = data[playerClass]
            if slot == 'INVTYPE_WEAPONOFFHAND' and not record.dualWield then return false end
            return record[itemtype][itemSubtype]
        end
        return true
    end

end
