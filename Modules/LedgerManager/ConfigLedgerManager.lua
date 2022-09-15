-- ------------------------------- --
local CLM       = LibStub("ClassicLootManager").CLM
-- ------ CLM common cache ------- --
local LOG       = CLM.LOG
local CONSTANTS = CLM.CONSTANTS
local UTILS     = CLM.UTILS
-- ------------------------------- --

local LedgerManager = CLM.MODULES.LedgerManager

local type, pairs = type, pairs

local DeepCopy = UTILS.DeepCopy
local assertType = UTILS.assertType

local DB = {}
if type(CLM_ReportThis) ~= "table" then
    CLM_ReportThis = {}
end

-- You really do not want to modify this
-- vvvvv
local DB_NAME_GUILD = 'guild'
local DB_NAME_LEDGER = 'ledger'
-- ^^^^^

local function UpdateGuild()
    DB.server_faction_guild = string.lower(UnitFactionGroup("player") ..
        " " .. GetNormalizedRealmName() .. " " .. (GetGuildInfo("player") or "unguilded"))
    LOG:Debug("Using database: %s", DB.server_faction_guild)
end

function DB:Initialize()
    LOG:Trace("DB:Initialize()")
    -- Below API requires delay after loading to work after variables loaded event
    UpdateGuild()

    if type(CLM_ReportThis[self.server_faction_guild]) ~= "table" then
        CLM_ReportThis[self.server_faction_guild] = {}
    end
    if type(CLM_ReportThis[self.server_faction_guild][DB_NAME_GUILD]) ~= "table" then
        CLM_ReportThis[self.server_faction_guild][DB_NAME_GUILD] = {}
    end
    if type(CLM_ReportThis[self.server_faction_guild][DB_NAME_LEDGER]) ~= "table" then
        CLM_ReportThis[self.server_faction_guild][DB_NAME_LEDGER] = {}
    end
end

function DB:Ledger()
    return CLM_ReportThis[self.server_faction_guild][DB_NAME_LEDGER]
end

function DB:UpdateLedger(ledger)
    CLM_ReportThis[self.server_faction_guild][DB_NAME_LEDGER] = ledger
end

local pairs, ipairs = pairs, ipairs
local wipe, collectgarbage, tinsert = wipe, collectgarbage, table.insert

local LedgerLib = LibStub("EventSourcing/LedgerFactory")

local STATUS_SYNCED = "synced"
local STATUS_OUT_OF_SYNC = "out_of_sync"
-- local STATUS_UNKNOWN = "unknown"
local STATUS_UNKNOWN_TYPE = "unknown_type"

local LEDGER_SYNC_COMM_PREFIX = "RTLedgerS2"
local LEDGER_DATA_COMM_PREFIX = "RTLedgerD2"

local previousCallback = nil
local function registerReceiveCallback(callback)
    if not previousCallback then
        previousCallback = callback
    end

    -- Comms:Register(LEDGER_SYNC_COMM_PREFIX, callback, function(name, length)
    --     return length < 4096
    -- end)
    CLM.MODULES.Comms:Register(LEDGER_SYNC_COMM_PREFIX, callback, CONSTANTS.ACL.LEVEL.PLEBS)
    CLM.MODULES.Comms:Register(LEDGER_DATA_COMM_PREFIX, callback, CONSTANTS.ACL.LEVEL.ASSISTANT)
end

local function createLedger(self, database)
    local ledger = LedgerLib.createLedger(
        database,
        (function(data, distribution, target, callbackFn, callbackArg)
            return CLM.MODULES.Comms:Send(LEDGER_SYNC_COMM_PREFIX, data, distribution, target, "BULK")
        end), -- send
        registerReceiveCallback, -- registerReceiveHandler
        (function(entry, sender)
            return CLM.MODULES.ACL:CheckLevel(CONSTANTS.ACL.LEVEL.ASSISTANT, sender)
        end), -- authorizationHandler
        (function(data, distribution, target, progressCallback)
            return CLM.MODULES.Comms:Send(LEDGER_DATA_COMM_PREFIX, data, distribution, target, "BULK")
        end), -- sendLargeMessage
        0, 100, LOG)

    ledger.addSyncStateChangedListener(function(_, status)
        self:UpdateSyncState(status)
    end)

    -- ledger.setDefaultHandler(function()
    --     self:UpdateSyncState(STATUS_UNKNOWN_TYPE)
    --     LOG:Warning("LegerManager: Entering incoherent state.")
    -- end)

    return ledger
end

local ConfigLedgerManager = { _initialized = false }
function ConfigLedgerManager:Initialize()
    if self._initialized then return end
    DB:Initialize()
    self.activeDatabase = DB:Ledger()
    self.activeLedger = createLedger(self, self.activeDatabase)
    self.mutatorCallbacks = {}
    self.onUpdateCallbacks = {}
    self.onRestartCallbacks = {}
    self._initialized = true
    ConfigLedgerManager:Enable()
end

function ConfigLedgerManager:IsInitialized()
    return self._initialized
end

function ConfigLedgerManager:Enable()
    self.activeLedger.getStateManager():setUpdateInterval(120)
    if CLM.MODULES.ACL:CheckLevel(CONSTANTS.ACL.LEVEL.ASSISTANT) then
        self.activeLedger.enableSending()
    end
end

function ConfigLedgerManager:RegisterEntryType(class, mutatorFn)
    if self.mutatorCallbacks[class] then
        LOG:Error("Class %s already exists in Ledger Entries.", class)
        return
    end
    self.mutatorCallbacks[class] = mutatorFn

    self.activeLedger.registerMutator(class, mutatorFn)
end

function ConfigLedgerManager:RegisterOnRestart(callback)
    tinsert(self.onRestartCallbacks, callback)
    self.activeLedger.addStateRestartListener(callback)
end

function ConfigLedgerManager:RegisterOnUpdate(callback)
    tinsert(self.onUpdateCallbacks, callback)
    self.activeLedger.addStateChangedListener(callback)
end

function ConfigLedgerManager:GetPeerStatus()
    return self.activeLedger.getPeerStatus()
end

function ConfigLedgerManager:RequestPeerStatusFromGuild()
    self.activeLedger.requestPeerStatusFromGuild()
end

function ConfigLedgerManager:UpdateSyncState(status)
    self.incoherentState = false
    self.inSync = false
    self.syncOngoing = false
    if self._initialized then
        if status == STATUS_UNKNOWN_TYPE then
            self.incoherentState = true
        elseif status == STATUS_SYNCED then
            self.inSync = true
        elseif status == STATUS_OUT_OF_SYNC then
            self.syncOngoing = true
        end
    end
end

function ConfigLedgerManager:IsInIncoherentState()
    return self.incoherentState
end

function ConfigLedgerManager:IsInSync()
    return self.inSync
end

function ConfigLedgerManager:IsSyncOngoing()
    return self.syncOngoing
end

function ConfigLedgerManager:Lag()
    return self.activeLedger.getStateManager():lag()
end

function ConfigLedgerManager:Hash()
    return self.activeLedger.getStateManager():stateHash()
end

function ConfigLedgerManager:Length()
    return self.activeLedger.getSortedList():length()
end

function ConfigLedgerManager:GetData()
    return self.activeLedger.getSortedList():entries()
end

function ConfigLedgerManager:RequestPeerStatusFromRaid()
    self.activeLedger.requestPeerStatusFromRaid()
end

function ConfigLedgerManager:Submit(entry, catchup)
    LOG:Trace("ConfigLedgerManager:Submit()")
    if not entry then return end
    self.lastEntry = entry
    self.activeLedger.submitEntry(entry)
    if catchup then
        self.activeLedger.catchup()
    end
end

function ConfigLedgerManager:Remove(entry, catchup)
    LOG:Trace("ConfigLedgerManager:Remove()")
    if not entry then return end
    self.activeLedger.ignoreEntry(entry)
    if catchup then
        self.activeLedger.catchup()
    end
end

function ConfigLedgerManager:CancelLastEntry()
    if not self._initialized then return end
    if self.lastEntry then
        self:Remove(self.lastEntry)
        self.lastEntry = nil
    end
end

function ConfigLedgerManager:Wipe()
    if not self._initialized then return end
    self:DisableAdvertising()
    local db = CLM.MODULES.Database:Ledger()
    wipe(db)
    collectgarbage()
    self:Enable()
end

--@do-not-package@
function ConfigLedgerManager:Reset()
    self.activeLedger.reset()
end

--@end-do-not-package@

CLM.MODULES.ReportThisConfigLedgerManager = ConfigLedgerManager

local oldLedgerManagerInitialize = LedgerManager.Initialize
function LedgerManager:Initialize(...)
    ConfigLedgerManager:Initialize()
    return oldLedgerManagerInitialize(self, ...)
end

local oldLedgerManagerEnable = LedgerManager.Enable
function LedgerManager:Enable(...)
    ConfigLedgerManager:Enable()
    return oldLedgerManagerEnable(self, ...)
end
