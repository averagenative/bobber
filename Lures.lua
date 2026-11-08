--[[
Lures on the cast press.

Putting a lure on your pole means using an item, and the game only lets
addons use items on your own click or key press. So Bobber does it on a
cast press: when your pole has no lure, your next double right-click (or
Cast Fishing key press) puts on the best lure in your bags instead of
casting. The press after that casts.

* "Best" means the biggest fishing bonus among the lures your fishing
  skill can use. When two have the same bonus, the Wide-Brimmed Fishing Hat
  goes first (it isn't used up), then the easier-to-get lure.
* The Wide-Brimmed Fishing Hat counts while you're wearing it and its lure
  is off cooldown (10 minutes, the same as the lure lasts).
* If there's no usable lure, Bobber casts as usual and says nothing.
* Lures take 5 seconds to put on. Presses during that time do nothing, so
  a quick second click can't interrupt it.
* A lure that fails twice in a row is skipped for the rest of the session,
  so a problem with one lure never stops you from fishing.

How a press puts a lure on: Casting.lua's cast button calls
Lures.GetLureMacroForThisPress() in its PreClick. If a lure should go on,
the button runs "/use item:<lure>" (or "/use 1" for the hat, slot 1 being
the head) and then "/use 16" (16 is the main hand, where the pole is) for
that one press, instead of casting. Every lure, the hat included, waits
for you to pick the pole after it's used; "/use 16" picks it.

How Bobber knows what happened: each lure has its own spell, and the game
reports it like any cast.

  UNIT_SPELLCAST_START      the lure is going on
  UNIT_SPELLCAST_SUCCEEDED  the lure is on (the pole can take a moment to
                            show it, so Bobber trusts this for a few seconds)
  UNIT_SPELLCAST_FAILED,    the lure didn't go on
  UNIT_SPELLCAST_INTERRUPTED

The lure list is WoW: Forever's own game data (build 1.60.1.70862, read
through wago.tools): every spell whose description mentions a fishing pole
(Spell), the items that cast those spells (ItemEffect, ItemXItemEffect),
and each item's required skill (ItemSparse). Two items share a spell:
"Secret" Bait casts the Shiny Bauble spell (8087). The OneCast addon (MIT)
first documented the six classic lures for Forever.
]]

local _, ns = ...

local Lures = {}
ns.Lures = Lures

local HEAD_SLOT = INVSLOT_HEAD or 1

-- At an equal bonus, the lure earlier in this list is the one "best" picks:
-- the hat first (it isn't used up), then the easier-to-get lure.
-- `wornInSlot` marks an item you wear instead of carrying in bags.
local LURES = {
    { itemID = 259846, spellID = 1265220, name = "Wide-Brimmed Fishing Hat", bonus = 25, requiredSkill = 1,
        wornInSlot = HEAD_SLOT },
    { itemID = 6529, spellID = 8087, name = "Shiny Bauble", bonus = 25, requiredSkill = 0 },
    { itemID = 268880, spellID = 8087, name = "\"Secret\" Bait", bonus = 25, requiredSkill = 0 },
    { itemID = 6530, spellID = 8088, name = "Nightcrawlers", bonus = 50, requiredSkill = 50 },
    { itemID = 6811, spellID = 8532, name = "Aquadynamic Fish Lens", bonus = 50, requiredSkill = 50 },
    { itemID = 6532, spellID = 8090, name = "Bright Baubles", bonus = 75, requiredSkill = 100 },
    { itemID = 7307, spellID = 9092, name = "Flesh Eating Worm", bonus = 75, requiredSkill = 100 },
    { itemID = 6533, spellID = 8089, name = "Aquadynamic Fish Attractor", bonus = 100, requiredSkill = 100 },
}
Lures.LIST = LURES

-- Spell ID -> the lures that cast it. Usually one; "Secret" Bait and Shiny
-- Bauble share a spell.
local luresBySpellID = {}
for _, lure in ipairs(LURES) do
    luresBySpellID[lure.spellID] = luresBySpellID[lure.spellID] or {}
    table.insert(luresBySpellID[lure.spellID], lure)
end

local MAIN_HAND = ns.MAIN_HAND_SLOT

-- A press that set up a lure has this long to start the lure's spell.
local START_TIMEOUT_SECONDS = 1.5
-- A lure that started but never reported an end is written off after this.
local APPLY_TIMEOUT_SECONDS = 7
-- After a lure succeeds, count it as on for this long even if the pole
-- doesn't show it yet, so the same lure is never put on twice.
local TRUST_SUCCESS_SECONDS = 3
-- Failures in a row before a lure is skipped for the session.
local FAILURES_BEFORE_SKIPPING = 2

local GetItemCountByID = (C_Item and C_Item.GetItemCount) or GetItemCount

local lureSetUpByPress = nil   -- the lure a press set up, until its spell starts
local pressSetUpAt = 0
local lureGoingOn = nil        -- the lure whose 5-second cast is running
local lureStartedAt = 0
local trustLureOnUntil = 0
local failuresInARowByItemID = {}
local skippedItemIDs = {}      -- lures that kept failing, skipped this session

-------------------------------------------------------------------------------
-- Choosing a lure
-------------------------------------------------------------------------------

local function GetBaseFishingSkill()
    local skill = ns.Catches.GetFishingSkill()
    return skill or 0
end

-- A worn lure (the hat) is ready when it's on and its cooldown is over.
local function IsWornLureReady(lure)
    if GetInventoryItemID("player", lure.wornInSlot) ~= lure.itemID then
        return false
    end
    local cooldownStart, cooldownDuration = GetInventoryItemCooldown("player", lure.wornInSlot)
    if ns.IsSecret(cooldownStart) or ns.IsSecret(cooldownDuration) then
        return false
    end
    return cooldownStart == 0 or cooldownStart + cooldownDuration <= GetTime()
end

local function IsLureAvailable(lure)
    if lure.wornInSlot then
        return IsWornLureReady(lure)
    end
    return GetItemCountByID(lure.itemID) > 0
end

-- The lure that would go on now, or nil if none can be used. A bigger
-- bonus wins; at an equal bonus the one earlier in LURES wins.
function Lures.FindBestLure()
    local baseSkill = GetBaseFishingSkill()
    local bestLure
    for _, lure in ipairs(LURES) do
        local isUsable = lure.requiredSkill <= baseSkill
            and not skippedItemIDs[lure.itemID]
            and IsLureAvailable(lure)
        if isUsable and (not bestLure or lure.bonus > bestLure.bonus) then
            bestLure = lure
        end
    end
    return bestLure
end

-------------------------------------------------------------------------------
-- What's on the pole
-------------------------------------------------------------------------------

function Lures.IsLureOnPole()
    if GetTime() < trustLureOnUntil then
        return true
    end
    local hasMainHandEnchant = GetWeaponEnchantInfo()
    if ns.IsSecret(hasMainHandEnchant) then
        return true  -- can't tell; don't spend a lure on a guess
    end
    return hasMainHandEnchant == true
end

-- True while a lure is going on, or a press just set one up and its spell
-- hasn't started yet. Presses wait during this time.
function Lures.IsLureGoingOn()
    local now = GetTime()
    if lureGoingOn and now - lureStartedAt < APPLY_TIMEOUT_SECONDS then
        return true
    end
    return lureSetUpByPress ~= nil and now - pressSetUpAt < START_TIMEOUT_SECONDS
end

-- The lure your next press would put on, or nil if it would cast.
function Lures.GetLureForNextPress()
    if not ns.settings.applyLures or not ns.IsPoleEquipped() or Lures.IsLureOnPole() then
        return nil
    end
    return Lures.FindBestLure()
end

-------------------------------------------------------------------------------
-- The press
-------------------------------------------------------------------------------

local function RecordFailure(lure)
    local failures = (failuresInARowByItemID[lure.itemID] or 0) + 1
    failuresInARowByItemID[lure.itemID] = failures
    if failures >= FAILURES_BEFORE_SKIPPING then
        skippedItemIDs[lure.itemID] = true
        ns.Debug(lure.name .. " failed twice; skipping it this session")
    end
    ns.Fire("BOBBER_LURE_CHANGED")
end

-- A /use whose target never arrived leaves the cursor waiting to pick one.
local function CancelLeftoverTargeting()
    if SpellIsTargeting and SpellIsTargeting() and SpellStopTargeting then
        SpellStopTargeting()
    end
end

-- If the press's lure never started (the item couldn't be used, say), count
-- a failure so the next press moves on.
local function CheckThatLureStarted(lure, setUpAt)
    if lureSetUpByPress == lure and pressSetUpAt == setUpAt then
        lureSetUpByPress = nil
        CancelLeftoverTargeting()
        RecordFailure(lure)
    end
end

-- Called by the cast button's PreClick on the press's first half. Returns
-- the macro text that puts a lure on, or nil to cast as usual.
function Lures.GetLureMacroForThisPress()
    local lure = Lures.GetLureForNextPress()
    if not lure then
        return nil
    end
    lureSetUpByPress = lure
    pressSetUpAt = GetTime()
    local setUpAt = pressSetUpAt
    C_Timer.After(START_TIMEOUT_SECONDS, function()
        CheckThatLureStarted(lure, setUpAt)
    end)
    ns.Fire("BOBBER_LURE_CHANGED")
    local useLureLine = lure.wornInSlot and ("/use " .. lure.wornInSlot) or ("/use item:" .. lure.itemID)
    return useLureLine .. "\n/use " .. MAIN_HAND
end

-------------------------------------------------------------------------------
-- Lure spell events
-------------------------------------------------------------------------------

-- The lure a lure spell belongs to. When lures share a spell, the one a
-- press set up (or the one going on) is the one that cast it.
local function GetLureForSpell(spellID)
    if spellID == nil or ns.IsSecret(spellID) then
        return nil
    end
    local luresWithSpell = luresBySpellID[spellID]
    if not luresWithSpell then
        return nil
    end
    for _, lure in ipairs(luresWithSpell) do
        if lure == lureSetUpByPress or lure == lureGoingOn then
            return lure
        end
    end
    return luresWithSpell[1]
end

ns.On("UNIT_SPELLCAST_START", function(_, _, spellID)
    local lure = GetLureForSpell(spellID)
    if lure then
        lureSetUpByPress = nil
        lureGoingOn = lure
        lureStartedAt = GetTime()
        ns.Fire("BOBBER_LURE_CHANGED")
    end
end, "player")

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(_, _, spellID)
    local lure = GetLureForSpell(spellID)
    if lure then
        lureSetUpByPress = nil
        lureGoingOn = nil
        trustLureOnUntil = GetTime() + TRUST_SUCCESS_SECONDS
        failuresInARowByItemID[lure.itemID] = 0
        ns.Fire("BOBBER_LURE_CHANGED")
    end
end, "player")

local function OnLureSpellFailed(_, _, spellID)
    local lure = GetLureForSpell(spellID)
    if lure and (lureGoingOn == lure or lureSetUpByPress == lure) then
        lureSetUpByPress = nil
        lureGoingOn = nil
        RecordFailure(lure)
    end
end

ns.On("UNIT_SPELLCAST_FAILED", OnLureSpellFailed, "player")
ns.On("UNIT_SPELLCAST_INTERRUPTED", OnLureSpellFailed, "player")

-- Bag and enchant changes can change what the next press does.
ns.On("UNIT_INVENTORY_CHANGED", function()
    ns.Fire("BOBBER_LURE_CHANGED")
end, "player")
