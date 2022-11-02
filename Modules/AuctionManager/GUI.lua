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
local colorTurquoise = { r = 0.2, g = 0.93, b = 0.93, a = 1.0 }
local colorGold = { r = 0.92, g = 0.70, b = 0.13, a = 1.0 }

local guiOptions = {
    type = "group",
    args = {}
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
    self.tooltips = {}
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
    CLM.MODULES.EventManager:RegisterEvent("CLM_UI_RESIZE", (function(event, data)
        self.top.frame:SetScale(data.scale)
    end))
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

local function getHighlightMethod(highlightColor)
    return (function(rowFrame, cellFrame, data, cols, row, realrow, column, fShow, table, ...)
        table.DoCellUpdate(rowFrame, cellFrame, data, cols, row, realrow, column, fShow, table, ...)
        local color
        local selected = (table.selected == realrow)
        if selected then
            color = table:GetDefaultHighlight()
        else
            color = highlightColor
        end

        table:SetHighLightColor(rowFrame, color)
    end)
end

local highlightAlt = getHighlightMethod({ r = 0.53, g = 0, b = 0.75, a = 0.3 })
local highlightOffspec = getHighlightMethod({ r = 0.9, g = 0, b = 0.45, a = 0.3 })

local function ST_GetHighlight(row)
    return row.cols[11].value
end

local function CreateBidWindow(self)
    local BidWindowGroup = AceGUI:Create("SimpleGroup")
    BidWindowGroup:SetLayout("Flow")
    local st = ScrollingTable:CreateST({}, 10, 18, nil, BidWindowGroup.frame)
    local columns = {
        { name = "", width = 18, DoCellUpdate = UTILS.LibStClassCellUpdate },
        { name = CLM.L["Name"], width = 76 },
        -- { name = CLM.L["Spec"], width = 60 },
        { name = CLM.L["Rank"], width = 100 },
        { name = CLM.L["Main"], width = 35 },
        { name = CLM.L["Type"], width = 56, color = { r = 0.0, g = 0.93, b = 0.0, a = 1.0 },
            -- sort = ScrollingTable.SORT_DSC,
            -- sortnext = 5
        },
        { name = CLM.L["Points"], width = 50, color = { r = 0.0, g = 0.93, b = 0.0, a = 1.0 },
            -- sort = ScrollingTable.SORT_DSC,
            -- sortnext = 5
            align = "CENTER"
        },
        { name = CLM.L["Roll"], width = 35, color = { r = 0.0, g = 0.93, b = 0.0, a = 1.0 },
            -- sort = ScrollingTable.SORT_DSC,
            -- sortnext = 5
            align = "CENTER"
        },
        { name = CLM.L["Total"], width = 50, color = { r = 0.0, g = 0.93, b = 0.0, a = 1.0 },
            sort = ScrollingTable.SORT_DSC,
            -- sortnext = 5,
            comparesort = UTILS.LibStCompareSortWrapper(
                (function(a1, b1)
                    return tonumber(a1), tonumber(b1)
                end)
            ),
            align = "CENTER"
        },
        { name = "", width = 18, DoCellUpdate = UTILS.LibStItemCellUpdate },
        { name = "", width = 18, DoCellUpdate = UTILS.LibStItemCellUpdate },
    }
    self.st = st
    st:SetDisplayCols(columns)
    st:EnableSelection(true)
    self.st.frame:SetPoint("BOTTOMLEFT", self.top.frame, "BOTTOMLEFT", 12, 40)
    -- self.st.frame:SetBackdropColor(0.1, 0.1, 0.1, 0.1)

    local menuRowData
    local RightClickMenu = CLM.UTILS.GenerateDropDownMenu(
        {
            {
                title = CLM.L["Remove"],
                func = (function()
                    local name = menuRowData.cols[2].value or ""
                    if name then
                        AuctionManager:RemoveBid(name)
                        self:Refresh()
                    end
                end),
                color = "cc0000"
            }
        },
        CLM.MODULES.ACL:CheckLevel(CLM.CONSTANTS.ACL.LEVEL.ASSISTANT),
        CLM.MODULES.ACL:CheckLevel(CLM.CONSTANTS.ACL.LEVEL.MANAGER)
    )

    --- selection ---
    self.st:RegisterEvents({
        OnClick = (function(rowFrame, cellFrame, data, cols, row, realrow, column, table, button, ...)
            local rightButton = (button == "RightButton")
            if rightButton then
                menuRowData = table:GetRow(realrow)
                UTILS.LibDD:CloseDropDownMenus()
                UTILS.LibDD:ToggleDropDownMenu(1, nil, RightClickMenu, cellFrame, -20, 0)
                return
            end

            self.st.DefaultEvents["OnClick"](rowFrame, cellFrame, data, cols, row, realrow, column, table, button, ...)

            local selected = self.st:GetRow(self.st:GetSelection())
            if type(selected) ~= "table" then return false end
            if selected.cols == nil then return false end -- Handle column titles click
            self.awardPlayer = selected.cols[2].value or ""
            self:UpdateAwardValue()
            if self.awardPlayer and self.awardPlayer:len() > 0 then
                self.top:SetStatusText(string.format(CLM.L["Awarding to %s for %d."], self.awardPlayer, self.awardValue))
            else
                self.top:SetStatusText("")
            end
            return selected
        end),

        -- OnEnter handler -> on hover
        OnEnter = (function(rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
            local status = table.DefaultEvents["OnEnter"](rowFrame, cellFrame, data, cols, row, realrow, column, table,
                ...)
            return status
        end),
        -- OnLeave handler -> on hover out
        OnLeave = (function(rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
            local status = table.DefaultEvents["OnLeave"](rowFrame, cellFrame, data, cols, row, realrow, column, table,
                ...)
            local rowData = table:GetRow(realrow)
            if not rowData or not rowData.cols then return status end
            local highlight = ST_GetHighlight(rowData)
            if highlight then
                highlight(rowFrame, cellFrame, data, cols, row, realrow, column, true, table, ...)
            end
            return status
        end),
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
            type = "execute",
            image = icon,
            func = (function() end),
            itemLink = "item:" .. tostring(self.itemId),
            width = 0.4,
            order = 1,
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
            width = 0.5,
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
            width = 0.5,
            order = 15,
            disabled = (function() return (not (self.itemLink or false)) or AuctionManager:IsAuctionInProgress() end)
        },
        bid_stats_info = {
            name = "Info",
            desc = (function()
                if not RaidManager:IsInActiveRaid() or self.raid == nil then return "Not in raid" end

                local bidInfo = AuctionManager:GetCurrentBidInfo()
                local passed = bidInfo.passed
                local cantUse = bidInfo.cantUse
                local closed = bidInfo.closed
                local anyAction = bidInfo.anyAction
                local noAction = bidInfo.noAction

                -- generateInfo closure
                local _generateString = (function(dataList, prefix)
                    local count = #dataList
                    local userCodedString = ""
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
                    return userCodedString
                end)

                local stats = string.format("%d/%d %s", #anyAction, bidInfo.total, "total")
                -- Result
                return stats
                    .. _generateString(passed, "Passed")
                    .. _generateString(cantUse, "Can't Use")
                    .. _generateString(closed, "Closed")
                    .. _generateString(noAction, "No Action")
            end),
            type = "execute",
            func = (function() end),
            image = "Interface\\Icons\\INV_Misc_QuestionMark",
            width = 0.3,
            order = 16
        },

        request_roll = {
            name = CLM.L["Request Roll"],
            type = "execute",
            func = (function()
                AuctionManager:RequestRollOff()
            end),
            width = 0.7,
            order = 17,
            disabled = (function()
                if AuctionManager:IsAuctionComplete() then return true end
                local bids = AuctionManager:GetEligibleBids()
                if #bids <= 1 then
                    return true
                end
                return false
            end)
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
    })

    local nextInQueue = CLM.MODULES.LootQueueManager:GetQueue()[1]
    if nextInQueue then

        local _, _, _, _, icon = GetItemInfoInstant(nextInQueue.link)
        o.nextInQueue = {
            name = "Next",
            type = "execute",
            image = icon,
            func = (function()
                CLM.MODULES.EventManager:DispatchEvent("CLM_AUCTION_WINDOW_FILL", {
                    link = nextInQueue.link,
                    start = false
                })
            end),
            itemLink = "item:" .. tostring(nextInQueue.id),
            width = 0.4,
            order = 3,
        }

        o.item.width = o.item.width - 0.4
    end

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
    f.frame:SetScale(CLM.GlobalConfigs:GetUIScale())

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
    self:Refresh()
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

local function rowColor(topBid, rollDifference, data, topBidIsUpgrade, topBidIsMain)

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
        local topPoints, isUpgradeOrBonus, isMain = AuctionManager:GetTopBid()

        local upgradedItems = CLM.MODULES.AuctionManager:UpgradedItems()

        local rollDifference = CLM.OPTIONS.ReportThisRosterManager:GetConfiguration(self.raid:Roster(), "rollDifference")
        for name, data in pairs(AuctionManager:BidData()) do
            local profile = ProfileManager:GetProfileByName(name)
            if profile then
                local items = upgradedItems[name] or {}
                local primaryItem = items[1]
                local secondaryItem = items[2]
                if (not primaryItem) and secondaryItem then
                    primaryItem = secondaryItem
                    secondaryItem = nil
                end

                local highlight
                local rowColorValue = rowColor(topPoints, rollDifference, data, isUpgradeOrBonus, isMain)

                if isUpgradeOrBonus and isMain and not data.isMain then
                    highlight = highlightAlt
                end

                if data.isOffspec then
                    highlight = highlightOffspec
                end

                local row = {
                    cols = {
                        { value = profile:ClassInternal() },
                        { value = profile:Name(), color = UTILS.GetClassColor(profile:Class()) },
                        { value = data.rank },
                        { value = data.isMain and "Yes" or "No", color = rowColorValue },
                        { value = string.lower(self.roster:GetFieldName(data.type)) },
                        { value = data.points, color = rowColorValue },
                        { value = data.roll or "", color = rowColorValue },
                        { value = AuctionManager:TotalBid(data), color = rowColorValue },
                        { value = primaryItem },
                        { value = secondaryItem },
                        { value = highlight }
                    },
                    DoCellUpdate = highlight
                }
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
        self.top:SetHeight(412)
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
