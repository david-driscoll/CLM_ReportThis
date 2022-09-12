local CLM            = LibStub("ClassicLootManager").CLM
-- ------ CLM common cache ------- --
local LOG            = CLM.LOG
local CONSTANTS      = CLM.CONSTANTS
local UTILS          = CLM.UTILS
-- ------------------------------- --
-- Libs
local ScrollingTable = LibStub("ScrollingTable")
local AceGUI         = LibStub("AceGUI-3.0")

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local mergeDictsInline = UTILS.mergeDictsInline
local RemoveColorCode = UTILS.RemoveColorCode

local AuctionManager = CLM.MODULES.AuctionManager
local ProfileManager = CLM.MODULES.ProfileManager
local RaidManager = CLM.MODULES.RaidManager
local EventManager = CLM.MODULES.EventManager
local AutoAward = CLM.MODULES.AutoAward

local RosterConfiguration = CLM.MODELS.RosterConfiguration

local REGISTRY = "clm_auction_manager_gui_options"

local EVENT_FILL_AUCTION_WINDOW = "CLM_AUCTION_WINDOW_FILL"

local whoami = UTILS.whoami()
local colorGreen = { r = 0.2, g = 0.93, b = 0.2, a = 1.0 }
local colorYellow = { r = 0.93, g = 0.93, b = 0.2, a = 1.0 }
local colorRedTransparent = { r = 0.93, g = 0.2, b = 0.2, a = 0.3 }
local colorGreenTransparent = { r = 0.2, g = 0.93, b = 0.2, a = 0.3 }
local colorBlueTransparent = { r = 0.2, g = 0.2, b = 0.93, a = 0.3 }

local colorRedTransparentHex = "ED3333"
local colorGreenTransparentHex = "33ED33"
local colorBlueTransparentHex = "3333ED"

local guiOptions = {
    type = "group",
    args = {}
}

local function ST_GetHighlightFunction(row)
    return row.cols[5].value
end

local highlightRole = {
    ["DAMAGER"] = UTILS.getHighlightMethod(colorRedTransparent),
    ["TANK"] = UTILS.getHighlightMethod(colorBlueTransparent),
    ["HEALER"] = UTILS.getHighlightMethod(colorGreenTransparent),
}

local function GetModifierCombination()
    local combination = ""

    if IsAltKeyDown() then
        combination = combination .. "a"
    end

    if IsShiftKeyDown() then
        combination = combination .. "s"
    end

    if IsControlKeyDown() then
        combination = combination .. "c"
    end

    return combination
end

local function CheckModifierCombination()
    return (CLM.GlobalConfigs:GetModifierCombination() == GetModifierCombination())
end

local function FillAuctionWindowFromTooltip(frame, button)
    if GameTooltip and CheckModifierCombination() then
        local _, itemLink = GameTooltip:GetItem()
        if itemLink then
            CLM.MODULES.EventManager:DispatchEvent(EVENT_FILL_AUCTION_WINDOW, {
                link = itemLink,
                start = (button == "RightButton")
            })
        end
    end
end

local function HookBagSlots()
    hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", FillAuctionWindowFromTooltip)
end

local function HookCorpseSlots(hookedSlots)
    local UIs = {
        wow = "LootButton",
        elv = "ElvLootSlot"
    }

    local numLootItems = GetNumLootItems()

    for ui, prefix in pairs(UIs) do
        for buttonIndex = 1, numLootItems do
            if not hookedSlots[ui][buttonIndex] then
                local button = getglobal(prefix .. buttonIndex)
                if button then
                    button:HookScript("OnClick", FillAuctionWindowFromTooltip)
                    hookedSlots[ui][buttonIndex] = true
                end
            end
        end
    end
end

local alreadyPostedLoot = {}
local function PostLootToRaidChat()
    if not IsInRaid() then return end
    if not CLM.MODULES.ACL:IsTrusted() then return end
    if not CLM.GlobalConfigs:GetAnnounceLootToRaid() then return end
    if CLM.GlobalConfigs:GetAnnounceLootToRaidOwnerOnly() then
        if not RaidManager:IsRaidOwner(whoami) then return end
    end
    local targetGuid = UnitGUID("target")
    if targetGuid then
        if alreadyPostedLoot[targetGuid] then return end
        alreadyPostedLoot[targetGuid] = true
    end

    local numLootItems = GetNumLootItems()
    local num = 1
    for lootIndex = 1, numLootItems do
        local _, _, _, _, rarity = GetLootSlotInfo(lootIndex)
        local itemLink = GetLootSlotLink(lootIndex)
        if itemLink then
            if (tonumber(rarity) or 0) >= CLM.GlobalConfigs:GetAnnounceLootToRaidLevel() then
                UTILS.SendChatMessage(num .. ". " .. itemLink, "RAID")
                num = num + 1
            end
        end
    end
end

local function InitializeDB(self)
    self.db = CLM.MODULES.Database:GUI('auction', {
        location = { nil, nil, "CENTER", 0, 0 },
        notes = {}
    })
end

local function StoreLocation(self)
    self.db.location = { self.top:GetPoint() }
end

local function RestoreLocation(self)
    if self.db.location then
        self.top:ClearAllPoints()
        self.top:SetPoint(self.db.location[3], self.db.location[4], self.db.location[5])
    end
end

local AuctionManagerGUI = {}
function AuctionManagerGUI:Initialize()
    LOG:Trace("AuctionManagerGUI:Initialize()")
    InitializeDB(self)
    EventManager:RegisterWoWEvent({ "PLAYER_LOGOUT" }, (function(...) StoreLocation(self) end))
    self:Create()
    if CLM.MODULES.ACL:IsTrusted() then
        HookBagSlots()
    end
    self.hookedSlots = { wow = {}, elv = {} }
    self.values = {}
    EventManager:RegisterWoWEvent({ "LOOT_OPENED" }, (function(...) self:HandleLootOpenedEvent() end))
    EventManager:RegisterWoWEvent({ "LOOT_CLOSED" }, (function(...) self:HandleLootClosedEvent() end))
    EventManager:RegisterEvent(EVENT_FILL_AUCTION_WINDOW, function(event, data)
        if not RaidManager:IsInProgressingRaid() then
            return
        end
        if not AuctionManager:IsAuctionInProgress() then
            self.itemLink = data.link
            AuctionManager:ClearBids()
            self:Refresh()
            if data.start then
                self:StartAuction()
            else
                if not self:IsVisible() then
                    self:Show()
                end
            end
        end
    end)
    self:RegisterSlash()
    self._initialized = true
end

function AuctionManagerGUI:HandleLootOpenedEvent()
    -- Set window open
    self.lootWindowIsOpen = true
    -- Post loot to raid chat
    PostLootToRaidChat()
    -- Hook slots
    HookCorpseSlots(self.hookedSlots)
end

function AuctionManagerGUI:HandleLootClosedEvent()
    self.lootWindowIsOpen = false
end

local function CreateBidWindow(self)
    local BidWindowGroup = AceGUI:Create("SimpleGroup")
    BidWindowGroup:SetLayout("Flow")
    local columns = {
        { name = CLM.L["Name"], width = 70 },
        { name = CLM.L["Spec"], width = 60 },
        { name = CLM.L["Rank"], width = 100 },
        { name = CLM.L["Type"], width = 60, color = { r = 0.0, g = 0.93, b = 0.0, a = 1.0 },
            -- sort = ScrollingTable.SORT_DSC,
            -- sortnext = 5
        },
        { name = CLM.L["Points"], width = 50, color = { r = 0.0, g = 0.93, b = 0.0, a = 1.0 },
            -- sort = ScrollingTable.SORT_DSC,
            -- sortnext = 5
        },
        { name = CLM.L["Roll"], width = 60, color = { r = 0.0, g = 0.93, b = 0.0, a = 1.0 },
            -- sort = ScrollingTable.SORT_DSC,
            -- sortnext = 5
        },
        { name = CLM.L["Total"], width = 50, color = { r = 0.0, g = 0.93, b = 0.0, a = 1.0 },
            sort = ScrollingTable.SORT_DSC,
            -- sortnext = 5,
            comparesort = UTILS.LibStCompareSortWrapper(
                (function(a1, b1)
                    return tonumber(a1), tonumber(b1)
                end)
            )
        },
    }
    self.st = ScrollingTable:CreateST(columns, 10, 18, nil, self.top.frame)
    self.st:EnableSelection(true)
    self.st.frame:SetPoint("BOTTOMLEFT", self.top.frame, "BOTTOMLEFT", 12, 40)
    self.st.frame:SetBackdropColor(0.1, 0.1, 0.1, 0.1)

    --- selection ---
    local OnClickHandler = (function(rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
        self.st.DefaultEvents["OnClick"](rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
        if not AuctionManager:IAmTheAuctioneer() then
            self.top:SetStatusText("")
            return
        end

        local selected = self.st:GetRow(self.st:GetSelection())
        if type(selected) ~= "table" then return false end
        if selected.cols == nil then return false end -- Handle column titles click
        self.awardPlayer = RemoveColorCode(selected.cols[1].value or "")
        self:UpdateAwardValue()
        if self.awardPlayer and self.awardPlayer:len() > 0 then
            self.top:SetStatusText(string.format(CLM.L["Awarding to %s for %d."], self.awardPlayer, self.awardValue))
        else
            self.top:SetStatusText("")
        end
        return selected
    end)
    self.st:RegisterEvents({
        OnClick = OnClickHandler,
        -- OnLeave = (function(rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
        --     local status = table.DefaultEvents["OnLeave"](rowFrame, cellFrame, data, cols, row, realrow, column, table,
        --         ...)
        --     local rowData = table:GetRow(realrow)
        --     if not rowData or not rowData.cols then return status end
        --     ST_GetHighlightFunction(rowData)(rowFrame, cellFrame, data, cols, row, realrow, column, true, table, ...)
        --     return status
        -- end),
    })
    --- --- ---

    return BidWindowGroup
end

local function UpdateOptions(self)
    for k, _ in pairs(guiOptions.args) do
        guiOptions.args[k] = nil
    end
    mergeDictsInline(guiOptions.args, self:GenerateAuctionOptions())
end

local function CreateOptions(self)
    local OptionsGroup = AceGUI:Create("SimpleGroup")
    OptionsGroup:SetLayout("Flow")
    OptionsGroup:SetWidth(510)
    self.OptionsGroup = OptionsGroup
    UpdateOptions(self)
    AceConfigRegistry:RegisterOptionsTable(REGISTRY, guiOptions)
    AceConfigDialog:Open(REGISTRY, OptionsGroup)

    return OptionsGroup
end

function AuctionManagerGUI:GenerateAuctionOptions()
    local icon = "Interface\\Icons\\INV_Misc_QuestionMark"
    if self.itemLink then
        self.itemId, _, _, self.itemEquipLoc, icon = GetItemInfoInstant(self.itemLink)
    end

    self.note = ""
    self.values = {}
    if RaidManager:IsInRaid() then
        self.raid = RaidManager:GetRaid()
        self.roster = self.raid:Roster()
        if self.roster then
            self.configuration:Copy(self.roster.configuration)
            self.values = UTILS.ShallowCopy(self.roster:GetItemValues(self.itemId))
        end
    end

    local o = {
        icon = {
            name = "",
            type = "description",
            image = icon,
            width = 0.4,
            order = 1,
            itemLink = "item:" .. tostring(self.itemId),
        },
        item = {
            name = CLM.L["Item"],
            type = "input",
            get = (function(i)
                return self.itemLink or ""
            end),
            set = (function(i, v)
                if not AuctionManager:IAmTheAuctioneer() or not AuctionManager:IsAuctionComplete() then return end
                if v and GetItemInfoInstant(v) then -- validate if it is an itemLink or itemString or itemId
                    self.itemLink = v
                    self.st:SetData({})
                else
                    self.itemLink = nil
                end
                AuctionManager:ClearBids()
                self:Refresh()
            end),
            -- disabled = (
            --     function() return not AuctionManager:IAmTheAuctioneer() or not AuctionManager:IsAuctionComplete() end),
            width = 2.3,
            order = 2,
            itemLink = "item:" .. tostring(self.itemId),
        },
    }

    if not AuctionManager:IAmTheAuctioneer() then
        return o
    end

    UTILS.mergeDictsInline(o, {
        note = {
            name = CLM.L["Note"],
            type = "input",
            set = (function(i, v)
                self.note = tostring(v)
                if self.itemId then
                    if self.note ~= "" then
                        self.db.notes[self.itemId] = self.note
                    else
                        self.db.notes[self.itemId] = nil
                    end
                end
            end),
            get = (function(i)
                if self.itemId then
                    if self.db.notes[self.itemId] then
                        self.note = self.db.notes[self.itemId]
                    end
                end
                return self.note
            end),
            disabled = (function() return not AuctionManager:IsAuctionComplete() end),
            width = 1.9,
            order = 8
        },
        time_auction = {
            name = CLM.L["Auction length"],
            type = "input",
            set = (function(i, v) self.configuration:Set("auctionTime", v or 0) end),
            get = (function(i) return tostring(self.configuration:Get("auctionTime")) end),
            disabled = (function(i) return not AuctionManager:IsAuctionComplete() end),
            pattern = "%d+",
            width = 0.4,
            order = 9
        },
        time_antiSnipe = {
            name = CLM.L["Anti-snipe"],
            type = "input",
            set = (function(i, v) self.configuration:Set("antiSnipe", v or 0) end),
            get = (function(i) return tostring(self.configuration:Get("antiSnipe")) end),
            disabled = (function(i) return not AuctionManager:IsAuctionComplete() end),
            pattern = "%d+",
            width = 0.4,
            order = 10
        },
        auction = {
            name = (function() return AuctionManager:IsAuctionInProgress() and CLM.L["Stop"] or CLM.L["Start"] end),
            type = "execute",
            func = (function()
                if not AuctionManager:IsAuctionInProgress() then
                    self:StartAuction()
                else
                    AuctionManager:StopAuctionManual()
                end
            end),
            width = 2.75 / 2,
            order = 11,
            disabled = (function() return not ((self.itemLink or false) and RaidManager:IsInProgressingRaid()) end)
        },
        clear = {
            name = (function() return CLM.L["Clear"] end),
            type = "execute",
            func = (function()
                -- clear bids
                AuctionManager:ClearBids()
                self:Refresh()
            end),
            width = 2.75 / 2,
            order = 11.5,
            disabled = (
                function() return AuctionManager:IsAuctionInProgress() or
                        not ((self.itemLink or false) and RaidManager:IsInProgressingRaid())
                end)
        },
        auction_results = {
            name = CLM.L["Auction Results"],
            type = "header",
            order = 12
        },
        award_label = {
            name = CLM.L["Award item"],
            type = "description",
            width = 0.5,
            order = 13
        },
        award_value = {
            name = CLM.L["Award value"],
            type = "input",
            set = (function(i, v)
                AuctionManagerGUI:setInputAwardValue(v)
            end),
            get = (function(i) return tostring(self.awardValue) end),
            disabled = (function(i) return (not (self.itemLink or false)) or AuctionManager:IsAuctionInProgress() end),
            width = 0.7,
            order = 14
        },
        award = {
            name = CLM.L["Award"],
            type = "execute",
            func = (function()
                local awarded = AuctionManager:Award(self.itemLink, self.itemId, self.awardValue, self.awardPlayer)
                if awarded and not AutoAward:IsIgnored(self.itemId) then
                    if AuctionManager:GetAutoAward() and self.lootWindowIsOpen then
                        AutoAward:GiveMasterLooterItem(self.itemId, self.awardPlayer)
                    elseif AuctionManager:GetAutoTrade() then
                        AutoAward:Track(self.itemId, self.awardPlayer)
                    end
                end
                self.itemLink = nil
                self.itemId = 0
                self.awardValue = 0
                self.awardPlayer = ""
                self.st:ClearSelection()
                self:Refresh()
            end),
            confirm = (function()
                return string.format(
                    CLM.L["Are you sure, you want to award %s to %s for %s DKP?"],
                    self.itemLink,
                    UTILS.ColorCodeText(self.awardPlayer, "FFD100"),
                    tostring(self.awardValue)
                )
            end),
            width = 0.7,
            order = 15,
            disabled = (function() return (not (self.itemLink or false)) or AuctionManager:IsAuctionInProgress() end)
        },
        bid_stats_info = {
            name = "Info",
            desc = (function()
                if not RaidManager:IsInActiveRaid() or self.raid == nil then return "Not in raid" end
                -- Unique did any action dict
                local didAnyAction = {}
                -- generateInfo closure
                local _generateInfo = (function(dataDict, ignoreListOfDicts, prefix, skipAction)
                    local dataList, userCodedString = {}, ""
                    for p, _ in pairs(dataDict) do
                        local inIgnoreList = false
                        for _, d in ipairs(ignoreListOfDicts) do
                            if d[p] then
                                inIgnoreList = true
                                break
                            end
                        end
                        if not inIgnoreList then
                            table.insert(dataList, p)
                            if not skipAction then
                                didAnyAction[p] = true
                            end
                        end
                    end
                    local count = #dataList
                    if count > 0 then
                        userCodedString = "\n\n" .. UTILS.ColorCodeText(prefix .. ": ", "EAB221")
                        for i = 1, count do
                            local profile = ProfileManager:GetProfileByName(dataList[i])
                            local coloredName = dataList[i]
                            if profile then
                                coloredName = UTILS.ColorCodeText(profile:Name(),
                                    UTILS.GetClassColor(profile:Class()).hex)
                            end
                            userCodedString = userCodedString .. coloredName
                            if i ~= count then
                                userCodedString = userCodedString .. ", "
                            end
                        end
                    end
                    return count, userCodedString
                end)
                for p, _ in pairs(AuctionManager:Bids()) do
                    didAnyAction[p] = true
                end
                -- passess list
                local _, passed = _generateInfo(
                    AuctionManager:Passes(),
                    { AuctionManager:Bids() },
                    "Passed")
                -- cant use actions
                local _, cantUse = _generateInfo(
                    AuctionManager:CantUse(),
                    { AuctionManager:Bids(), AuctionManager:Passes() },
                    "Can't use")
                -- closed actions
                local _, closed = _generateInfo(AuctionManager:Hidden(),
                    { AuctionManager:Bids(), AuctionManager:Passes(), AuctionManager:CantUse() },
                    "Closed")
                -- no action
                local raidersDict = {}
                for _, GUID in ipairs(self.raid:Players()) do
                    local profile = ProfileManager:GetProfileByGUID(GUID)
                    if profile then
                        raidersDict[profile:Name()] = true
                    end
                end
                local _, noAction = _generateInfo(raidersDict,
                    { AuctionManager:Bids(), AuctionManager:Passes(), AuctionManager:CantUse(), AuctionManager:Hidden() }
                    ,
                    "No action", true)
                -- did any actions count
                local didAnyActionCount = 0
                for _, _ in pairs(didAnyAction) do didAnyActionCount = didAnyActionCount + 1 end
                -- Stats
                local stats = string.format("%d/%d %s", didAnyActionCount, #self.raid:Players(), "total")
                -- Result
                return stats .. passed .. cantUse .. closed .. noAction
            end),
            type = "execute",
            func = (function() end),
            image = "Interface\\Icons\\INV_Misc_QuestionMark",
            width = 0.3,
            order = 16
        }
    })

    return o
end

function AuctionManagerGUI:Create()
    LOG:Trace("AuctionManagerGUI:Create()")
    -- Main Frame
    local f = AceGUI:Create("Frame")
    f:SetTitle(CLM.L["Auctioning"])
    f:SetStatusText("")
    f:SetLayout("flow")
    f:EnableResize(false)
    f:SetWidth(510)
    f:SetAutoAdjustHeight(true)
    f:SetHeight(490)
    self.top = f
    UTILS.MakeFrameCloseOnEsc(f.frame, "CLM_Auctioning_GUI")

    self.configuration = RosterConfiguration:New()
    self.itemLink = nil
    self.itemId = 0
    self.note = ""
    self.awardValue = 0
    self.bids = {}

    self.optionsFrame = CreateOptions(self)
    self.bidWindowFrame = CreateBidWindow(self)

    f:AddChild(self.optionsFrame)
    f:AddChild(self.bidWindowFrame)

    -- Clear active bid on close
    f:SetCallback('OnClose', function()
        if AuctionManager:IAmTheAuctioneer() then
            AuctionManagerGUI:ClearSelectedBid()
        end
    end)

    RestoreLocation(self)
    -- Hide by default
    f:Hide()
end

function AuctionManagerGUI:StartAuction()
    self:ClearSelectedBid()
    AuctionManager:StartAuction(self.itemId, self.itemLink, self.itemEquipLoc, self.values, self.note, self.raid,
        self.configuration)
end

function AuctionManagerGUI:UpdateAwardValue()
    LOG:Trace("AuctionManagerGUI:UpdateAwardValue()")

    self:setInputAwardValue(AuctionManager:CalculateItemCost(self.awardPlayer))
    self:Refresh()
end

function AuctionManagerGUI:setInputAwardValue(v)
    self.awardValue = tonumber(v) or 0;
    if self.top then
        if self.awardPlayer and self.awardPlayer:len() > 0 then
            self.top:SetStatusText(string.format(CLM.L["Awarding to %s for %d."], self.awardPlayer, self.awardValue))
        else
            self.top:SetStatusText("")
        end
    end
end

function AuctionManagerGUI:ClearSelectedBid()
    LOG:Trace("AuctionManagerGUI:ClearAwardValue()")
    self.awardValue = ""
    self.awardPlayer = ""
    self.top:SetStatusText("")
    self.st:ClearSelection()
end

function AuctionManagerGUI:UpdateBids()
    LOG:Trace("AuctionManagerGUI:UpdateBids()")
    AuctionManagerGUI:UpdateAwardValue()
    self:Refresh()
end

local function rowColor(topBid, rollDifference, data)

    local rowPoints = AuctionManager:TotalBid(data)
    local topPoints = AuctionManager:TotalBid(topBid)
    local color = { r = 1, g = 1, b = 1, a = 1 }

    if (topPoints - rowPoints) > rollDifference then
        color = { r = 1, g = 0, b = 0, a = 1 }
    elseif not data.roll then
        color = { r = 1, g = 0.65, b = 0, a = 1 }
    elseif rowPoints == topPoints then
        color = { r = 0, g = 1, b = 0, a = 1 }
    end

    return color

end

function AuctionManagerGUI:Refresh()
    LOG:Trace("AuctionManagerGUI:Refresh()")
    if not self._initialized then return end

    if RaidManager:IsInActiveRaid() then
        self.raid = RaidManager:GetRaid()
        self.roster = self.raid:Roster()
        if self.roster then
            self.configuration:Copy(self.roster.configuration)
        end

        local tableData = {}
        local topPoints = AuctionManager:GetTopBid()
        local rollDifference = CLM.OPTIONS.ReportThisRosterManager:GetConfiguration(self.raid:Roster(), "rollDifference")
        for name, data in pairs(AuctionManager:BidData()) do
            local profile = ProfileManager:GetProfileByName(name)
            if profile then
                local row = { cols = {} }
                local rowColorValue = rowColor(topPoints, rollDifference, data)
                -- name
                table.insert(row.cols,
                    { value = UTILS.ColorCodeText(profile:Name(), UTILS.GetClassColor(profile:Class()).hex) }) -- spec
                table.insert(row.cols, { value = profile:SpecString() })
                -- rank
                table.insert(row.cols, { value = data.rank })
                -- type
                table.insert(row.cols, { value = string.lower(self.roster:GetFieldName(data.type)) })
                -- points
                table.insert(row.cols, { value = data.points, color = rowColorValue })
                -- roll
                table.insert(row.cols, { value = data.roll or "", color = rowColorValue })
                -- total
                table.insert(row.cols, { value = AuctionManager:TotalBid(data), color = rowColorValue })
                table.insert(tableData, row)
            end
        end
        self.st:SetData(tableData)
    end

    UpdateOptions(self)
    AceConfigDialog:Open(REGISTRY, self.OptionsGroup)
    AceConfigRegistry:NotifyChange(REGISTRY)
    if AuctionManager:IAmTheAuctioneer() then
        self.top:SetHeight(490)
    else
        self.top:SetHeight(340)
    end
end

function AuctionManagerGUI:Show()
    self:Refresh()
    self.top:Show()
end

function AuctionManagerGUI:IsVisible()
    return self.top:IsVisible()
end

function AuctionManagerGUI:Toggle()
    LOG:Trace("AuctionManagerGUI:Toggle()")
    if not self._initialized then return end
    if self.top:IsVisible() or not CLM.MODULES.ACL:IsTrusted() then
        -- Award reset on closing BidWindow.
        AuctionManagerGUI:ClearSelectedBid()
        self.top:Hide()
    else
        self:Refresh()
        self.top:Show()
    end
end

function AuctionManagerGUI:RegisterSlash()
    local options = {
        auction = {
            type = "execute",
            name = "Auctioning",
            desc = CLM.L["Toggle Auctioning window display"],
            handler = self,
            func = "Toggle",
        }
    }
    CLM.MODULES.ConfigManager:RegisterSlash(options)
end

function AuctionManagerGUI:Reset()
    LOG:Trace("AuctionManagerGUI:Reset()")
    self.top:ClearAllPoints()
    self.top:SetPoint("CENTER", 0, 0)
end

CLM.GUI.AuctionManager = AuctionManagerGUI
