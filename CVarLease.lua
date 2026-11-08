--[[
Temporary game setting changes ("leases").

Bobber changes a few game settings (CVars) while you fish: sound volumes
for the louder splash, and soft-targeting reach so the Interact Key always
finds your bobber. A lease records each CVar's original value before it
changes anything, and releasing the lease puts the originals back.

The originals are kept in saved variables (BobberDB.cvarBackup). If the UI
reloads or the game disconnects while a lease is held, the leftover lease is
released the next time Bobber loads, so your own settings always come back.
Leases are also released at logout, so the game never saves Bobber's
temporary values as your settings.

Each lease has a name ("sounds", "reach"), and different leases change
different CVars, so they never fight over a value.
]]

local _, ns = ...

local CVarLease = {}
ns.CVarLease = CVarLease

-- True while Bobber itself is changing a CVar, so the change-watcher below
-- can tell Bobber's changes from yours.
local isApplyingLeaseChange = false

local function SetCVarQuietly(cvarName, value)
    isApplyingLeaseChange = true
    -- Some CVars can't change during combat; pcall keeps that from erroring.
    local succeeded = pcall(C_CVar.SetCVar, cvarName, tostring(value))
    isApplyingLeaseChange = false
    if not succeeded then
        ns.Debug("couldn't set " .. cvarName)
    end
end

-- Change the CVars in `valuesByCVarName` and remember their originals under
-- `leaseName`. Calling it again for a held lease keeps the first originals.
function CVarLease.Acquire(leaseName, valuesByCVarName)
    local originals = ns.db.cvarBackup[leaseName] or {}
    for cvarName, leasedValue in pairs(valuesByCVarName) do
        local currentValue = C_CVar.GetCVar(cvarName)
        -- GetCVar returns nil for a CVar this client doesn't have; skip it.
        if currentValue ~= nil then
            if originals[cvarName] == nil then
                originals[cvarName] = currentValue
            end
            SetCVarQuietly(cvarName, leasedValue)
        end
    end
    ns.db.cvarBackup[leaseName] = originals
end

-- Put back every CVar the lease changed.
function CVarLease.Release(leaseName)
    local originals = ns.db and ns.db.cvarBackup[leaseName]
    if not originals then
        return
    end
    for cvarName, originalValue in pairs(originals) do
        SetCVarQuietly(cvarName, originalValue)
    end
    ns.db.cvarBackup[leaseName] = nil
end

function CVarLease.IsHeld(leaseName)
    return ns.db ~= nil and ns.db.cvarBackup[leaseName] ~= nil
end

function CVarLease.ReleaseAll()
    if not ns.db then
        return
    end
    local leaseNames = {}
    for leaseName in pairs(ns.db.cvarBackup) do
        leaseNames[#leaseNames + 1] = leaseName
    end
    for _, leaseName in ipairs(leaseNames) do
        CVarLease.Release(leaseName)
    end
end

-- If you change a leased CVar yourself while fishing (say you move the music
-- slider), your new value becomes the one restored when the lease ends.
hooksecurefunc(C_CVar, "SetCVar", function(cvarName, newValue)
    if isApplyingLeaseChange or not ns.db or type(cvarName) ~= "string" or newValue == nil then
        return
    end
    local lowerCaseName = cvarName:lower()
    for _, originals in pairs(ns.db.cvarBackup) do
        for leasedCVarName in pairs(originals) do
            if leasedCVarName:lower() == lowerCaseName then
                originals[leasedCVarName] = tostring(newValue)
            end
        end
    end
end)

-- Leftovers from a reload or disconnect mid-fishing go back first thing.
-- The other files then take fresh leases if they still need them.
ns.On("BOBBER_DATA_READY", CVarLease.ReleaseAll)
ns.On("PLAYER_LOGOUT", CVarLease.ReleaseAll)
