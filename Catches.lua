--[[
Catch tracking and fishing auto-loot.

A catch is the loot window that opens after you hook a fish. Bobber counts:

* casts: each time the line goes out,
* catches: each fishing loot window, with every item in it,
* escapes: "Your fish got away." (your skill is low for the water),
* early hooks: "No fish are hooked." (you hooked before the bite).

It keeps those counts in three scopes, which are the window's tabs:

* Session: since you logged in, or since a break of 30 minutes or more.
* Zone: everything this character caught in the zone you're in.
* All time: everything this character caught with Bobber.

Fish per hour uses only time spent fishing: the time between casts counts,
but a gap of more than two minutes between casts is a break and doesn't.
]]

local _, ns = ...

local Catches = {}
ns.Catches = Catches

local NEW_SESSION_AFTER_IDLE_SECONDS = 30 * 60
local MAX_GAP_COUNTED_AS_FISHING_SECONDS = 2 * 60

local ITEM_LOOT_SLOT_TYPE = (Enum.LootSlotType and Enum.LootSlotType.Item) or LOOT_SLOT_ITEM or 1

-- The current session's tally, plus the extra fields only a session has.
local session

-- Set when the line goes out; the next fishing loot window is its catch.
-- (The loot window can report itself more than once.)
local isWaitingForCatch = false

-------------------------------------------------------------------------------
-- Sessions
-------------------------------------------------------------------------------

function Catches.StartNewSession()
    session = ns.NewTally()
    session.startedAt = GetTime()
    session.fishingSeconds = 0   -- time between casts, breaks left out
    session.lastCastAt = nil
    session.startingSkill = nil  -- fishing skill when the session began
    ns.Fire("BOBBER_STATS_CHANGED")
end

-------------------------------------------------------------------------------
-- Zones
-------------------------------------------------------------------------------

function Catches.GetZoneName()
    local zoneName = GetRealZoneText()
    if not zoneName or zoneName == "" or ns.IsSecret(zoneName) then
        return "Unknown zone"
    end
    return zoneName
end

local function GetZoneTally(zoneName)
    local zones = ns.charDB.zones
    if not zones[zoneName] then
        zones[zoneName] = ns.NewTally()
    end
    return zones[zoneName]
end

-- Every tally an event counts toward: session, this zone, and lifetime.
local function GetTalliesToCount()
    return { session, GetZoneTally(Catches.GetZoneName()), ns.charDB.lifetime }
end

-------------------------------------------------------------------------------
-- Scopes for the window
-------------------------------------------------------------------------------

-- `scopeKey` is "session", "zone", or "lifetime".
function Catches.GetTally(scopeKey)
    if scopeKey == "zone" then
        return ns.charDB.zones[Catches.GetZoneName()] or ns.NewTally()
    elseif scopeKey == "lifetime" then
        return ns.charDB.lifetime
    end
    return session
end

-- The tally's items as a list sorted by count, most caught first. Each
-- entry has: itemID, count, share (of all items in the tally, 0 to 1),
-- name, icon, quality.
function Catches.GetSortedItems(tally)
    local entries = {}
    local totalCount = 0
    for itemID, count in pairs(tally.items) do
        totalCount = totalCount + count
        local info = ns.db.itemInfo[itemID] or {}
        entries[#entries + 1] = {
            itemID = itemID,
            count = count,
            name = info.name or ("item " .. itemID),
            icon = info.icon,
            quality = info.quality or 1,
        }
    end
    for _, entry in ipairs(entries) do
        entry.share = totalCount > 0 and entry.count / totalCount or 0
    end
    table.sort(entries, function(first, second)
        if first.count ~= second.count then
            return first.count > second.count
        end
        return first.name < second.name
    end)
    return entries
end

-- Seconds spent fishing this session, including the cast in progress.
function Catches.GetSessionFishingSeconds()
    local seconds = session.fishingSeconds
    if session.lastCastAt then
        seconds = seconds + math.min(GetTime() - session.lastCastAt, MAX_GAP_COUNTED_AS_FISHING_SECONDS)
    end
    return seconds
end

-- Catches per hour this session, or nil until there's a minute of fishing.
function Catches.GetSessionCatchesPerHour()
    local seconds = Catches.GetSessionFishingSeconds()
    if seconds < 60 then
        return nil
    end
    return session.catches / seconds * 3600
end

-------------------------------------------------------------------------------
-- Fishing skill
-------------------------------------------------------------------------------

-- Returns skill, maximum skill, and bonus (from the pole and lure), or nil
-- if the character doesn't know Fishing.
function Catches.GetFishingSkill()
    if not (GetProfessions and GetProfessionInfo) then
        return nil
    end
    local _, _, _, fishingProfessionIndex = GetProfessions()
    if not fishingProfessionIndex then
        return nil
    end
    local _, _, skill, maxSkill, _, _, _, bonus = GetProfessionInfo(fishingProfessionIndex)
    if skill == nil or ns.IsSecret(skill) then
        return nil
    end
    return skill, maxSkill, bonus or 0
end

-- Skill points gained this session.
function Catches.GetSessionSkillGain()
    local skill = Catches.GetFishingSkill()
    if not skill then
        return 0
    end
    if not session.startingSkill then
        session.startingSkill = skill
    end
    return skill - session.startingSkill
end

-------------------------------------------------------------------------------
-- Counting
-------------------------------------------------------------------------------

local function OnLineOut()
    local now = GetTime()
    if session.lastCastAt and now - session.lastCastAt > NEW_SESSION_AFTER_IDLE_SECONDS then
        Catches.StartNewSession()
    end
    if session.lastCastAt then
        local gapSeconds = now - session.lastCastAt
        if gapSeconds <= MAX_GAP_COUNTED_AS_FISHING_SECONDS then
            session.fishingSeconds = session.fishingSeconds + gapSeconds
        end
    end
    session.lastCastAt = now
    Catches.GetSessionSkillGain()  -- records the starting skill on the first cast

    for _, tally in ipairs(GetTalliesToCount()) do
        tally.casts = tally.casts + 1
    end
    isWaitingForCatch = true
    ns.Fire("BOBBER_STATS_CHANGED")
end

-- Remember an item's name, icon, and quality so the window can show it
-- without asking the game again.
local function RememberItemInfo(itemID, name, icon, quality)
    if ns.IsSecret(name) or ns.IsSecret(icon) or ns.IsSecret(quality) then
        return
    end
    ns.db.itemInfo[itemID] = { name = name, icon = icon, quality = quality }
end

local function GetLootSlotItemID(lootSlotIndex)
    local itemLink = GetLootSlotLink(lootSlotIndex)
    if not itemLink or ns.IsSecret(itemLink) then
        return nil
    end
    return (C_Item.GetItemInfoInstant(itemLink))
end

local function RecordCatch()
    isWaitingForCatch = false
    local tallies = GetTalliesToCount()
    for lootSlotIndex = 1, GetNumLootItems() do
        if GetLootSlotType(lootSlotIndex) == ITEM_LOOT_SLOT_TYPE then
            local icon, name, quantity, _, quality = GetLootSlotInfo(lootSlotIndex)
            local itemID = GetLootSlotItemID(lootSlotIndex)
            if itemID then
                RememberItemInfo(itemID, name, icon, quality)
                local caughtCount = (quantity and not ns.IsSecret(quantity) and quantity > 0) and quantity or 1
                for _, tally in ipairs(tallies) do
                    tally.items[itemID] = (tally.items[itemID] or 0) + caughtCount
                end
            end
        end
    end
    for _, tally in ipairs(tallies) do
        tally.catches = tally.catches + 1
    end
    ns.Fire("BOBBER_STATS_CHANGED")
end

-- Take every item, last slot first so the slot numbers don't shift.
local function LootEverything()
    for lootSlotIndex = GetNumLootItems(), 1, -1 do
        if LootSlotHasItem(lootSlotIndex) then
            LootSlot(lootSlotIndex)
        end
    end
end

-- `isGameAutoLooting` is true when the game's own auto loot will take the
-- items, in which case Bobber leaves the looting to it.
ns.On("LOOT_READY", function(isGameAutoLooting)
    if not IsFishingLoot() then
        return
    end
    if isWaitingForCatch then
        RecordCatch()
    end
    if ns.settings.autoLootFish and not isGameAutoLooting then
        LootEverything()
    end
end)

local function CountForAllTallies(fieldName)
    for _, tally in ipairs(GetTalliesToCount()) do
        tally[fieldName] = tally[fieldName] + 1
    end
    ns.Fire("BOBBER_STATS_CHANGED")
end

ns.On("UI_ERROR_MESSAGE", function(_, message)
    if message == nil or ns.IsSecret(message) then
        return
    end
    if ERR_FISH_ESCAPED and message == ERR_FISH_ESCAPED then
        CountForAllTallies("escapes")
    elseif ERR_FISH_NOT_HOOKED and message == ERR_FISH_NOT_HOOKED then
        CountForAllTallies("earlyHooks")
    end
end)

ns.On("BOBBER_CAST_START", OnLineOut)

ns.On("BOBBER_DATA_READY", Catches.StartNewSession)

local function OnSkillOrZoneChanged()
    ns.Fire("BOBBER_STATS_CHANGED")
end

ns.On("SKILL_LINES_CHANGED", OnSkillOrZoneChanged)
ns.On("ZONE_CHANGED_NEW_AREA", OnSkillOrZoneChanged)
