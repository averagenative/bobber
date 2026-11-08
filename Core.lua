--[[
Bobber: a fishing helper for World of Warcraft: Forever.

Core.lua loads first and sets up the pieces every other file uses:

* The shared addon table, `ns`. The game passes the same table to every
  file of an addon as the second value of `...`, so Bobber's files share
  functions and state through it: ns.Casting, ns.Gear, ns.Catches, and so on.
* A small event bus. ns.On() listens and ns.Fire() sends. Game events are
  registered with the game automatically. Events whose names start with
  "BOBBER_" are Bobber's own and only travel between Bobber's files.
* The saved variables (BobberDB for the account, BobberCharDB for each
  character) and their default values.
* Helpers: chat output, the Fishing spell, fishing pole checks, and running
  work after combat ends.
* The /bobber slash command and the key binding labels.

Bobber's own events:

  BOBBER_DATA_READY        saved variables are loaded and filled with defaults
  BOBBER_SETTINGS_CHANGED  an option changed; the first argument is its key
  BOBBER_CAST_START        the Fishing channel started (the line is out)
  BOBBER_CAST_STOP         the Fishing channel ended (the line came in)
  BOBBER_GEAR_CHANGED      the pole or weapon slots changed
  BOBBER_LURE_CHANGED      a lure went on, failed, or what the next press does changed
  BOBBER_STATS_CHANGED     a cast, catch, or getaway was counted
]]

local ADDON_NAME, ns = ...

ns.ADDON_NAME = ADDON_NAME
ns.debugEnabled = false

ns.MAIN_HAND_SLOT = INVSLOT_MAINHAND or 16
ns.OFF_HAND_SLOT = INVSLOT_OFFHAND or 17

-- How the right mouse button hooks the bobber while the line is out.
ns.HOOK_OFF = 0
ns.HOOK_SINGLE_CLICK = 1
ns.HOOK_DOUBLE_CLICK = 2

-------------------------------------------------------------------------------
-- Chat output
-------------------------------------------------------------------------------

local CHAT_PREFIX = "|cff4fc3f7Bobber|r: "

function ns.Print(message)
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. message)
end

-- Debug lines show only after "/bobber debug".
function ns.Debug(message)
    if ns.debugEnabled then
        ns.Print("|cff888888" .. message .. "|r")
    end
end

-------------------------------------------------------------------------------
-- Event bus
-------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local listenersByEventName = {}

local function IsBobberEvent(eventName)
    return eventName:sub(1, 7) == "BOBBER_"
end

-- Listen for an event. `unit` is optional: pass "player" for unit events
-- such as UNIT_SPELLCAST_CHANNEL_START to hear only about your character.
function ns.On(eventName, callback, unit)
    local listeners = listenersByEventName[eventName]
    if not listeners then
        listeners = {}
        listenersByEventName[eventName] = listeners
        if not IsBobberEvent(eventName) then
            -- RegisterEvent raises an error for an event this client doesn't
            -- have, so register inside pcall and carry on without it.
            local registered
            if unit then
                registered = pcall(eventFrame.RegisterUnitEvent, eventFrame, eventName, unit)
            else
                registered = pcall(eventFrame.RegisterEvent, eventFrame, eventName)
            end
            if not registered then
                ns.Debug("this client has no event " .. eventName)
            end
        end
    end
    listeners[#listeners + 1] = callback
end

-- Send an event to every listener, in the order they started listening.
function ns.Fire(eventName, ...)
    local listeners = listenersByEventName[eventName]
    if not listeners then
        return
    end
    for index = 1, #listeners do
        -- One failing listener must not stop the rest, so report its error
        -- through the game's error handler and keep going.
        local succeeded, errorMessage = pcall(listeners[index], ...)
        if not succeeded then
            geterrorhandler()(errorMessage)
        end
    end
end

eventFrame:SetScript("OnEvent", function(_, eventName, ...)
    ns.Fire(eventName, ...)
end)

-------------------------------------------------------------------------------
-- Saved variables
-------------------------------------------------------------------------------

-- Option defaults. These are the values a new install starts with; the
-- options panel (Options.lua) shows and edits the same keys.
ns.DEFAULT_SETTINGS = {
    doubleClickCast = true,        -- double right-click casts, while a pole is equipped
    doubleClickSeconds = 0.4,      -- longest gap between the two clicks of a double-click
    rightClickHookMode = ns.HOOK_SINGLE_CLICK,
    castKeyHooks = true,           -- the cast key binding also hooks while the line is out
    castKeyEquipsPole = true,      -- the cast key equips your pole when it isn't on
    applyLures = true,             -- a cast press puts on a lure when the pole has none
    extendBobberReach = true,      -- widen soft targeting so the bobber is always in reach
    showBobberIcon = false,        -- the game's interact icon over the bobber
    autoLootFish = true,           -- take everything from fishing loot windows
    enhanceSounds = true,          -- louder splash while a pole is equipped
    backgroundSound = true,        -- game sound keeps playing when WoW isn't the active window
    weaponsOnCombat = true,        -- put weapons back the moment combat starts
    showWindowWithPole = true,
    hideWindowWithoutPole = true,
    windowLocked = false,
    windowTheme = "harbor",
    windowOpacity = 0.9,           -- background opacity, 0 (clear) to 1 (solid)
}

-- A tally counts one scope of fishing: a session, a zone, or a lifetime.
function ns.NewTally()
    return {
        casts = 0,
        catches = 0,
        escapes = 0,     -- "Your fish got away."
        earlyHooks = 0,  -- "No fish are hooked." (hooked before the bite)
        items = {},      -- [itemID] = number caught
    }
end

local DEFAULT_ACCOUNT_DATA = {
    settings = {},
    window = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 320,
        y = 0,
        scale = 1,
        collapsed = false,
        scope = "session",
    },
    cvarBackup = {},  -- CVarLease.lua: original CVar values while a lease is held
    itemInfo = {},    -- [itemID] = { name, icon, quality } for caught items
}

local DEFAULT_CHARACTER_DATA = {
    gear = {
        chosen = {},      -- items you dragged onto a slot: pole, mainHand, offHand
        remembered = {},  -- items Bobber noticed you using
    },
    zones = {},           -- [zone name] = tally
    lifetime = ns.NewTally(),
}

-- Fill in every key that `target` is missing, recursing into tables, so new
-- defaults reach existing installs without overwriting what's saved.
local function CopyMissingDefaults(target, defaults)
    for key, defaultValue in pairs(defaults) do
        if target[key] == nil then
            if type(defaultValue) == "table" then
                target[key] = CopyMissingDefaults({}, defaultValue)
            else
                target[key] = defaultValue
            end
        elseif type(defaultValue) == "table" and type(target[key]) == "table" then
            CopyMissingDefaults(target[key], defaultValue)
        end
    end
    return target
end

ns.On("ADDON_LOADED", function(loadedAddonName)
    if loadedAddonName ~= ADDON_NAME then
        return
    end
    BobberDB = CopyMissingDefaults(BobberDB or {}, DEFAULT_ACCOUNT_DATA)
    BobberCharDB = CopyMissingDefaults(BobberCharDB or {}, DEFAULT_CHARACTER_DATA)
    CopyMissingDefaults(BobberDB.settings, ns.DEFAULT_SETTINGS)

    ns.db = BobberDB
    ns.charDB = BobberCharDB
    ns.settings = BobberDB.settings

    ns.Fire("BOBBER_DATA_READY")
end)

-------------------------------------------------------------------------------
-- Secret values
-------------------------------------------------------------------------------

-- WoW: Forever uses the Midnight addon API, where some values are "secret":
-- addon code may display them but can't compare or inspect them (doing so is
-- an error). Check with ns.IsSecret() before comparing anything that comes
-- from the game and might be one.
function ns.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

-------------------------------------------------------------------------------
-- The Fishing spell
-------------------------------------------------------------------------------

-- Fishing has had many spell IDs across versions of the game. Any of these
-- starting a channel means the line is out.
local KNOWN_FISHING_SPELL_IDS = {
    [7620] = true, [7731] = true, [7732] = true, [18248] = true,
    [33095] = true, [51294] = true, [88868] = true, [110410] = true,
    [131474] = true, [131476] = true, [131490] = true, [158743] = true,
    [377895] = true, [1224771] = true,
}

-- Spells whose name gives the client's own (translated) name for Fishing.
local SPELL_IDS_FOR_FISHING_NAME = { 7620, 131474 }

-- The cast button casts by name, so this is what it casts.
ns.fishingSpellName = nil

function ns.RefreshFishingSpellName()
    for _, spellID in ipairs(SPELL_IDS_FOR_FISHING_NAME) do
        local spellName = C_Spell.GetSpellName(spellID)
        if spellName and not ns.IsSecret(spellName) then
            ns.fishingSpellName = spellName
            return spellName
        end
    end
    return nil
end

function ns.IsFishingSpell(spellID)
    if spellID == nil or ns.IsSecret(spellID) then
        return false
    end
    if KNOWN_FISHING_SPELL_IDS[spellID] then
        return true
    end
    local spellName = C_Spell.GetSpellName(spellID)
    return spellName ~= nil and not ns.IsSecret(spellName) and spellName == ns.fishingSpellName
end

-- True while your character is channeling Fishing.
function ns.IsChannelingFishing()
    local spellID = select(8, UnitChannelInfo("player"))
    return ns.IsFishingSpell(spellID)
end

-------------------------------------------------------------------------------
-- Fishing poles
-------------------------------------------------------------------------------

-- `item` can be an item ID, an item link, or nil.
function ns.IsFishingPole(item)
    if not item then
        return false
    end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(item)
    return classID == Enum.ItemClass.Weapon and subclassID == Enum.ItemWeaponSubclass.Fishingpole
end

function ns.IsPoleEquipped()
    return ns.IsFishingPole(GetInventoryItemID("player", ns.MAIN_HAND_SLOT))
end

-------------------------------------------------------------------------------
-- Combat lockdown
-------------------------------------------------------------------------------

-- During combat the game locks key bindings and secure buttons, so work that
-- changes them has to wait. RunOutOfCombat runs `task` now if it can, or
-- once combat ends. A task waiting already isn't queued twice.
local tasksWaitingForCombatEnd = {}

function ns.RunOutOfCombat(task)
    if not InCombatLockdown() then
        task()
        return
    end
    tasksWaitingForCombatEnd[task] = true
end

ns.On("PLAYER_REGEN_ENABLED", function()
    local tasks = tasksWaitingForCombatEnd
    tasksWaitingForCombatEnd = {}
    for task in pairs(tasks) do
        task()
    end
end)

-------------------------------------------------------------------------------
-- Key binding labels (Options > Keybindings > AddOns > Bobber)
-------------------------------------------------------------------------------

BINDING_HEADER_BOBBER = "Bobber"
_G["BINDING_NAME_CLICK BobberCastButton:LeftButton"] = "Cast Fishing (hooks while the line is out)"
_G["BINDING_NAME_CLICK BobberEquipPoleButton:LeftButton"] = "Equip fishing pole"
_G["BINDING_NAME_CLICK BobberEquipWeaponsButton:LeftButton"] = "Equip weapons"
BINDING_NAME_BOBBER_TOGGLE_WINDOW = "Show or hide the Bobber window"

-------------------------------------------------------------------------------
-- Slash command
-------------------------------------------------------------------------------

local SLASH_COMMAND_HELP = {
    "/bobber - show or hide the window",
    "/bobber options - open the options",
    "/bobber lock | unlock - lock or unlock the window",
    "/bobber reset - move the window back to the middle of the screen",
    "/bobber newsession - start a new fishing session",
    "/bobber debug - toggle debug messages",
}

local slashCommandHandlers = {
    [""] = function() ns.Window.Toggle() end,
    options = function() ns.Options.Open() end,
    config = function() ns.Options.Open() end,
    lock = function() ns.Window.SetLocked(true) end,
    unlock = function() ns.Window.SetLocked(false) end,
    reset = function() ns.Window.ResetPosition() end,
    newsession = function()
        ns.Catches.StartNewSession()
        ns.Print("started a new fishing session.")
    end,
    debug = function()
        ns.debugEnabled = not ns.debugEnabled
        ns.Print("debug messages " .. (ns.debugEnabled and "on" or "off") .. ".")
    end,
    help = function()
        for _, line in ipairs(SLASH_COMMAND_HELP) do
            ns.Print(line)
        end
    end,
}

SLASH_BOBBER1 = "/bobber"
SlashCmdList.BOBBER = function(message)
    local command = (message or ""):lower():match("^%s*(%S*)")
    local handler = slashCommandHandlers[command] or slashCommandHandlers.help
    handler()
end
