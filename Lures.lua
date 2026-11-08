--[[
Lures on the cast press.

Putting a lure on your pole means using an item, and the game only lets
addons use items on your own click or key press. So Bobber does it on a
cast press: when your pole has no lure, your next double right-click (or
Cast Fishing key press) puts on the best lure in your bags instead of
casting. The press after that casts.

* "Best" means the biggest fishing bonus among the lures in your bags that
  your fishing skill can use.
* If there's no usable lure in your bags, Bobber casts as usual and says
  nothing.
* Lures take 5 seconds to put on. Presses during that time do nothing, so
  a quick second click can't interrupt it.
* A lure that fails twice in a row is skipped for the rest of the session,
  so a problem with one lure never stops you from fishing.

How a press puts a lure on: Casting.lua's cast button calls
Lures.GetLureMacroForThisPress() in its PreClick. If a lure should go on,
the button runs "/use item:<lure>" then "/use 16" (16 is the main hand,
where the pole is) for that one press, instead of casting.

How Bobber knows what happened: each lure has its own spell, and the game
reports it like any cast.

  UNIT_SPELLCAST_START      the lure is going on
  UNIT_SPELLCAST_SUCCEEDED  the lure is on (the pole can take a moment to
                            show it, so Bobber trusts this for a few seconds)
  UNIT_SPELLCAST_FAILED,    the lure didn't go on
  UNIT_SPELLCAST_INTERRUPTED

The lure list (item IDs, spell IDs, required skill, bonus) comes from the
OneCast addon (MIT), which checked it against WoW: Forever's game data.
]]

local _, ns = ...

local Lures = {}
ns.Lures = Lures

-- Equal bonuses keep the easier-to-get lure first; that's the one "best" picks.
local LURES = {
    { itemID = 6529, spellID = 8087, name = "Shiny Bauble", bonus = 25, requiredSkill = 0 },
    { itemID = 6530, spellID = 8088, name = "Nightcrawlers", bonus = 50, requiredSkill = 50 },
    { itemID = 6811, spellID = 8532, name = "Aquadynamic Fish Lens", bonus = 50, requiredSkill = 50 },
    { itemID = 6532, spellID = 8090, name = "Bright Baubles", bonus = 75, requiredSkill = 100 },
    { itemID = 7307, spellID = 9092, name = "Flesh Eating Worm", bonus = 75, requiredSkill = 100 },
    { itemID = 6533, spellID = 8089, name = "Aquadynamic Fish Attractor", bonus = 100, requiredSkill = 100 },
}
Lures.LIST = LURES

local luresBySpellID = {}
for _, lure in ipairs(LURES) do
    luresBySpellID[lure.spellID] = lure
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

-- The lure that would go on now, or nil if none in the bags can be used.
function Lures.FindBestLureInBags()
    local baseSkill = GetBaseFishingSkill()
    local bestLure
    for _, lure in ipairs(LURES) do
        local isUsable = lure.requiredSkill <= baseSkill
            and not skippedItemIDs[lure.itemID]
            and GetItemCountByID(lure.itemID) > 0
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
    return Lures.FindBestLureInBags()
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
    return "/use item:" .. lure.itemID .. "\n/use " .. MAIN_HAND
end

-------------------------------------------------------------------------------
-- Lure spell events
-------------------------------------------------------------------------------

local function GetLureForSpell(spellID)
    if spellID == nil or ns.IsSecret(spellID) then
        return nil
    end
    return luresBySpellID[spellID]
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
