local CLM = LibStub("ClassicLootManager").CLM

-- Libs
-- local ScrollingTable = LibStub("ScrollingTable")
local AceGUI = LibStub("AceGUI-3.0")
local LibCandyBar = LibStub("LibCandyBar-3.0")

local LIBS = {
    registry = LibStub("AceConfigRegistry-3.0"),
    gui = LibStub("AceConfigDialog-3.0")
}


local LOG = CLM.LOG
local UTILS = CLM.UTILS
local MODULES = CLM.MODULES
-- local MODELS = CLM.MODELS
-- local CONSTANTS = CLM.CONSTANTS
local GUI = CLM.GUI

local BiddingManager = MODULES.BiddingManager
local EventManager = MODULES.EventManager

local ProfileManager = MODULES.ProfileManager
local RosterManager = MODULES.RosterManager

local mergeDictsInline = UTILS.mergeDictsInline
local IsTooltipTextRed = UTILS.IsTooltipTextRed
local GetItemIdFromLink = UTILS.GetItemIdFromLink
local guiOptions = {
    type = "group",
    args = {}
}

local BASE_WIDTH      = 300
local BASE_HEIGHT     = 175
local EXTENDED_HEIGHT = 200

local REGISTRY = "clm_bidding_manager_gui_options"

local CUSTOM_BUTTON = {}
CUSTOM_BUTTON.MODE = {
    DISABLED = 1,
    ALL_IN = 2,
    CUSTOM_VALUE = 3
}
CUSTOM_BUTTON.MODES = UTILS.Set(CUSTOM_BUTTON.MODE)
CUSTOM_BUTTON.MODES_GUI = {
    [CUSTOM_BUTTON.MODE.DISABLED] = CLM.L["Disabled"],
    [CUSTOM_BUTTON.MODE.ALL_IN] = CLM.L["All in"],
    [CUSTOM_BUTTON.MODE.CUSTOM_VALUE] = CLM.L["Custom value"]
}

local function GetCustomButtonMode(self)
    return self.db.customButton.mode
end

local function SetCustomButtonMode(self, mode)
    self.db.customButton.mode = CUSTOM_BUTTON.MODES[mode] and mode or CUSTOM_BUTTON.MODE.DISABLED
end

local function GetCustomButtonValue(self)
    return self.db.customButton.value
end

local function SetCustomButtonValue(self, value)
    self.db.customButton.value = tonumber(value) or 1
end

local function UpdateOptions(self)
    for k, _ in pairs(guiOptions.args) do
        guiOptions.args[k] = nil
    end
    mergeDictsInline(guiOptions.args, self:GenerateAuctionOptions())
    guiOptions.args.item.width = 2.15
    self.top:SetWidth(BASE_WIDTH)
    self.OptionsGroup:SetWidth(BASE_WIDTH)
    -- end
end

local function CreateOptions(self)
    local OptionsGroup = AceGUI:Create("SimpleGroup")
    OptionsGroup:SetLayout("Flow")
    OptionsGroup:SetWidth(BASE_WIDTH)
    self.OptionsGroup = OptionsGroup
    UpdateOptions(self)
    LIBS.registry:RegisterOptionsTable(REGISTRY, guiOptions)
    LIBS.gui:Open(REGISTRY, OptionsGroup)

    return OptionsGroup
end

local BiddingManagerGUI = {}

local function InitializeDB(self)
    self.db = MODULES.Database:GUI('bidding', {
        location = { nil, nil, "CENTER", 0, 0 },
        customButton = {
            mode = CUSTOM_BUTTON.MODE.DISABLED,
            value = 1
        }
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

local function CreateConfigs(self)
    local options = {
        bidding_mode = {
            name = CLM.L["Custom button mode"],
            desc = CLM.L["Select custom button mode"],
            type = "select",
            values = CUSTOM_BUTTON.MODES_GUI,
            set = function(i, v) SetCustomButtonMode(self, tonumber(v)) end,
            get = function(i) return GetCustomButtonMode(self) end,
            order = 75
        },
        bidding_value = {
            name = CLM.L["Custom value"],
            desc = CLM.L["Value to use in custom mode"],
            type = "range",
            min = 1,
            max = 1000000,
            softMin = 1,
            softMax = 10000,
            step = 0.01,
            set = function(i, v) SetCustomButtonValue(self, v) end,
            get = function(i) return GetCustomButtonValue(self) end,
            order = 76
        }
    }
    MODULES.ConfigManager:Register(CLM.CONSTANTS.CONFIGS.GROUP.GLOBAL, options)
end

function BiddingManagerGUI:Initialize()
    LOG:Trace("BiddingManagerGUI:Initialize()")
    InitializeDB(self)
    EventManager:RegisterWoWEvent({ "PLAYER_LOGOUT" }, (function(...) StoreLocation(self) end))
    self:Create()
    CreateConfigs(self)
    self:RegisterSlash()
    self.standings = 0
    self.canUseItem = true
    self.fakeTooltip = CreateFrame("GameTooltip", "CLMBiddingFakeTooltip", UIParent, "GameTooltipTemplate")
    self.fakeTooltip:SetScript('OnTooltipSetItem', (function(s)
        self.canUseItem = true
        local tooltipName = s:GetName()
        for i = 1, s:NumLines() do
            local l = _G[tooltipName .. 'TextLeft' .. i]
            local r = _G[tooltipName .. 'TextRight' .. i]
            if IsTooltipTextRed(l) or IsTooltipTextRed(r) then
                self.canUseItem = false
                break
            end
        end
        s:Hide()
    end))
    self._initialized = true
end

function BiddingManagerGUI:GenerateAuctionOptions()
    local itemId = 0
    local icon = "Interface\\Icons\\INV_Misc_QuestionMark"
    local itemLink = self.auctionInfo and self.auctionInfo:ItemLink() or nil

    if itemLink then
        itemId, _, _, _, icon = GetItemInfoInstant(self.auctionInfo:ItemLink())
        -- Force caching loot from server
        GetItemInfo(itemId)
    end
    local shortItemLink = "item:" .. tostring(itemId)

    local o = {
        item = {
            inline = true,
            type = "group",
            name = "",
            args = {
                icon = {
                    name = "",
                    type = "description",
                    control = "InteractiveLabel",
                    image = icon,
                    itemLink = shortItemLink,
                    width = 0.25,
                    order = 1
                },
                item = {
                    name = itemLink or "",
                    type = "description",
                    control = "InteractiveLabel",
                    itemLink = shortItemLink,
                    width = 1,
                    order = 2,
                },
            },
            order = 1,
        },
        buttons = {
            type = "group",
            inline = true,
            name = "",
            args = {
                bonus = {
                    name = CLM.L["Bonus"],
                    desc = CLM.L["Go all in on an item (you really want)."],
                    type = "execute",
                    func = (function()
                        BiddingManager:NotifyBonus()
                        BiddingManagerGUI:UpdateStatusText()
                    end),
                    hidden = (function()
                        -- maybe disable if negative
                        return not self.canUseItem
                    end),
                    width = 0.5,
                    order = 5
                },
                upgrade = {
                    name = CLM.L["Upgrade"],
                    desc = CLM.L["Set the upgrade amount on the item (I'm okay with rolling others for it)."],
                    type = "execute",
                    func = (function()
                        BiddingManager:NotifyUpgrade()
                        BiddingManagerGUI:UpdateStatusText()
                    end),
                    hidden = (function()
                        -- maybe disable if negative
                        return not self.canUseItem
                    end),
                    width = 0.5,
                    order = 6
                },
                offspec = {
                    name = CLM.L["Offspec"],
                    desc = CLM.L["I could use it for offspec."],
                    type = "execute",
                    func = (function()
                        BiddingManager:NotifyOffspec()
                        BiddingManagerGUI:UpdateStatusText()
                    end),
                    hidden = (function()
                        -- maybe disable if negative
                        return not self.canUseItem
                    end),
                    width = 0.5,
                    order = 7
                },
            },
            order = 100
        },

        passButtons = {
            type = "group",
            inline = true,
            name = "",
            args = {
                pass = {
                    name = CLM.L["Pass"],
                    desc = (function()
                        if CLM.CONSTANTS.AUCTION_TYPES_OPEN[self.auctionType] then
                            return CLM.L["Notify that you are passing on the item."]
                        end
                    end),
                    type = "execute",
                    func = (function()
                        BiddingManager:NotifyPass();
                        BiddingManagerGUI:UpdateStatusText()
                    end),
                    hidden = (function()
                        -- maybe disable if negative
                        return not self.canUseItem
                    end),
                    width = 0.4,
                    order = 9
                },
                cancel = {
                    name = CLM.L["Cancel"],
                    desc = CLM.L["Cancel your bid."],
                    type = "execute",
                    func = (function()
                        BiddingManager:CancelBid()
                        BiddingManagerGUI:Hide()
                    end),
                    disabled = (function()
                        -- maybe disable if negative
                        return false
                    end),
                    width = 0.43,
                    order = 10
                },
            },
            order = 101
        }
    }

    if self.auctionInfo and self.auctionInfo:Note():len() > 0 then
        o.note = {
            name = self.auctionInfo:Note(),
            type = "description",
            width = "fill",
            order = 2,
        }
    end
    return o
end

function BiddingManagerGUI:Create()
    LOG:Trace("BiddingManagerGUI:Create()")
    -- Main Frame
    local f = AceGUI:Create("Frame")
    f:SetTitle(CLM.L["Bidding"])
    f:SetStatusText("")
    f:SetLayout("flow")
    f:EnableResize(false)
    f:SetWidth(BASE_WIDTH)

    -- f.frame:SetMinResize(200, 120)
    f:SetHeight(BASE_HEIGHT)
    self.top = f
    UTILS.MakeFrameCloseOnEsc(f.frame, "CLM_Bidding_GUI")
    self.bid = 0
    self.barPreviousPercentageLeft = 1
    self.duration = 1
    f:AddChild(CreateOptions(self))
    RestoreLocation(self)
    -- Handle onHide information passing whenever the UI is closed
    local oldOnHide = f.frame:GetScript("OnHide")
    f.frame:SetScript("OnHide", (function(...)
        BiddingManager:NotifyHide()
        oldOnHide(...)
    end))
    -- Hide by default
    f:Hide()
end

function BiddingManagerGUI:Hide()
    self.top:Hide()
end

function BiddingManagerGUI:Show()
    self.top:Show()
end

function BiddingManagerGUI:UpdateCurrentBidValue(value)
    self.bid = tonumber(value or 0)
    self:Refresh()
end

function BiddingManagerGUI:RecolorBar()
    local currentPercentageLeft = (self.bar.remaining / self.duration)
    local percentageChange = self.barPreviousPercentageLeft - currentPercentageLeft
    if percentageChange >= 0.05 or percentageChange < 0 then
        if (currentPercentageLeft >= 0.5) then
            self.bar:SetColor(0, 0.80, 0, 1) -- green
        elseif (currentPercentageLeft >= 0.2) then
            self.bar:SetColor(0.92, 0.70, 0.20, 1) -- gold
        else
            self.bar:SetColor(0.8, 0, 0, 1) -- red
        end
        self.barPreviousPercentageLeft = currentPercentageLeft
    end
end

function BiddingManagerGUI:BuildBar(duration)
    LOG:Trace("BiddingManagerGUI:BuildBar()")
    self.bar = LibCandyBar:New("Interface\\AddOns\\ClassicLootManager\\Media\\Bars\\AceBarFrames.tga", --[[435--]]
        BASE_WIDTH, 25)
    local note = ""
    if self.auctionInfo:Note():len() > 0 then
        note = "(" .. self.auctionInfo:Note() .. ")"
        self.top:SetHeight(EXTENDED_HEIGHT)
    else
        self.top:SetHeight(BASE_HEIGHT)
    end
    self.bar:SetLabel(self.auctionInfo:ItemLink() .. " " .. note)
    self.bar:SetDuration(duration)
    local _, _, _, _, icon = GetItemInfoInstant(self.auctionInfo:ItemLink())
    self.bar:SetIcon(icon)

    self.bar:AddUpdateFunction(function()
        self:RecolorBar()
    end);
    self.bar:SetColor(0, 0.80, 0, 1)
    -- self.bar:SetParent(self.top.frame) -- makes the bar disappear
    self.bar:SetPoint("CENTER", self.top.frame, "TOP", 0, 25)

    self.bar.candyBarBar:SetScript("OnMouseDown", function(_, button)
        if button == 'LeftButton' then
            self:Toggle()
        end
    end)

    self.bar:Start(self.auctionInfo:Time())
end

local function EvaluateItemUsability(self)
    self.fakeTooltip:SetHyperlink("item:" .. GetItemIdFromLink(self.auctionInfo:ItemLink()))
end

local function HandleWindowDisplay(self)
    self:Refresh()
    self.top:Show()
    if not self.canUseItem then
        BiddingManager:NotifyCantUse()
    end
end

function BiddingManagerGUI:UpdateStatusText()
    local statusText = ""
    local myProfile = ProfileManager:GetMyProfile()
    if myProfile and self.auctionInfo then
        local roster = RosterManager:GetRosterByUid(self.auctionInfo:RosterUid())
        if roster then
            self.auctionType = roster:GetConfiguration("auctionType")
            if roster:IsProfileInRoster(myProfile:GUID()) then
                self.standings = roster:Standings(myProfile:GUID())
                statusText = self.standings .. CLM.L[" DKP "]
            end
        end
    end

    if BiddingManager:GetLastBidValue() then
        statusText = statusText .. " ::: " .. BiddingManager:GetLastBidValue()
    end

    if not self.canUseItem then
        statusText = statusText .. " ::: " .. "Class Restricted"
    end

    self.top:SetStatusText(statusText)
end

function BiddingManagerGUI:StartAuction(show, auctionInfo)
    LOG:Trace("BiddingManagerGUI:StartAuction()")
    self.auctionInfo = auctionInfo
    local duration = self.auctionInfo:EndTime() - GetServerTime()
    if duration < 0 then return end
    self.duration = duration
    self:BuildBar(duration)

    BiddingManagerGUI:UpdateStatusText()

    if not show then return end
    self:Refresh()

    if C_Item.IsItemDataCachedByID(self.auctionInfo:ItemLink()) then
        EvaluateItemUsability(self)
        HandleWindowDisplay(self)
    else
        GetItemInfo(self.auctionInfo:ItemLink())
        C_Timer.After(0.5, function()
            if C_Item.IsItemDataCachedByID(self.auctionInfo:ItemLink()) then
                EvaluateItemUsability(self)
            else
                self.canUseItem = true -- fallback
            end
            HandleWindowDisplay(self)
        end)
    end
end

function BiddingManagerGUI:EndAuction()
    LOG:Trace("BiddingManagerGUI:EndAuction()")
    if self.bar.running then
        self.bar:Stop()
    end
    self.top:SetStatusText("")
    self.bar = nil
    self.barPreviousPercentageLeft = 1
    self.duration = 1
    self.top:Hide()
end

function BiddingManagerGUI:AntiSnipe()
    self.bar.exp = (self.bar.exp + self.auctionInfo:AntiSnipe()) -- trick to extend bar
end

function BiddingManagerGUI:Refresh()
    LOG:Trace("BiddingManagerGUI:Refresh()")
    if not self._initialized then return end

    UpdateOptions(self)
    LIBS.registry:NotifyChange(REGISTRY)
    LIBS.gui:Open(REGISTRY, self.OptionsGroup) -- Refresh the config gui panel
    self:UpdateStatusText()
end

function BiddingManagerGUI:Toggle()
    LOG:Trace("BiddingManagerGUI:Toggle()")
    if not self._initialized then return end
    if self.top:IsVisible() then
        self.top:Hide()
    else
        self:Refresh()
        self.top:Show()
    end
end

function BiddingManagerGUI:RegisterSlash()
    local options = {
        bid = {
            type = "execute",
            name = CLM.L["Bidding"],
            desc = CLM.L["Toggle Bidding window display"],
            handler = self,
            func = "Toggle",
        }
    }
    MODULES.ConfigManager:RegisterSlash(options)
end

function BiddingManagerGUI:Reset()
    LOG:Trace("BiddingManagerGUI:Reset()")
    self.top:ClearAllPoints()
    self.top:SetPoint("CENTER", 0, 0)
end

GUI.BiddingManager = BiddingManagerGUI
