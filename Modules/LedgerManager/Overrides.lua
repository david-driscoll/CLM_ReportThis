local CLM = LibStub("ClassicLootManager").CLM

local LOG = CLM.LOG
local MODULES = CLM.MODULES
local LedgerManager = CLM.MODULES.LedgerManager

local observeEvents = {}

function LedgerManager:ObserveEntryType(class, observerFn)
    if observeEvents[class] == nil then
        observeEvents[class] = {}
    end
    table.insert(observeEvents[class], observerFn)
end

local oldRegisterEntryType = LedgerManager.RegisterEntryType
function LedgerManager:RegisterEntryType(class, mutatorFn)
    if not observeEvents[class] then
        observeEvents[class] = {}
    end

    local originalMutatorFn = mutatorFn
    mutatorFn = function(entry)
        for _, observerFn in pairs(observeEvents[class]) do
            pcall(observerFn, entry)
        end
        return originalMutatorFn(entry)
    end
    return oldRegisterEntryType(self, class, mutatorFn)
end
