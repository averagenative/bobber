--[[
Casting and hooking.

Addons can't cast Fishing or click the bobber on their own. The game only
allows those actions in direct response to a real mouse click or key press,
and Blizzard's rules forbid working around that. So every cast and every
hook in Bobber is still your own click; Bobber only changes what one click
does:

* Double right-click to cast. When your second right-click lands within
  `doubleClickSeconds` of the first, Bobber points the right mouse button at
  a hidden secure button that casts Fishing, so that same click casts. Right-
  click goes back to normal right after. This works only while a fishing
  pole is equipped, so double right-clicks do nothing unusual otherwise.

* Right-click to hook. While the line is out, the right mouse button runs
  the game's Interact Key action (INTERACTTARGET), which interacts with the
  soft target. Soft targeting is widened while the line is out, so the soft
  target is your bobber wherever you click. Depending on the option, this is
  a single right-click anywhere (the default) or a double right-click.

  With a single right-click, holding the right button to turn the camera
  also hooks, because the press itself is the hook. Turn the camera with the
  left button while the line is out.

* The cast key. The "Cast Fishing" key binding casts, and while the line is
  out the same key hooks.

* Lures. When your pole has no lure, a cast press (double right-click or
  the cast key) puts on the best lure in your bags instead of casting; the
  next press casts. Lures.lua picks the lure and tracks it going on.

How the game handles these changes: SetOverrideBinding() temporarily gives a
key or mouse button a different action, on behalf of an "owner" frame, and
ClearOverrideBindings(owner) removes that owner's overrides. Bindings can't
change during combat, so every override is removed in PLAYER_REGEN_DISABLED,
the last moment before combat locks them.
]]

local _, ns = ...

local Casting = {}
ns.Casting = Casting

local CAST_BUTTON_NAME = "BobberCastButton"
Casting.CAST_BINDING = "CLICK " .. CAST_BUTTON_NAME .. ":LeftButton"

-- Two clicks closer together than this are one click bouncing, not a double.
local MIN_DOUBLE_CLICK_SECONDS = 0.04
-- A triple-click must not cast twice.
local CAST_DEBOUNCE_SECONDS = 0.5
-- After a double-click override, wait this long past the mouse release
-- before removing it, so the release itself still reaches the override.
local OVERRIDE_CLEAR_DELAY_SECONDS = 0.1
-- After the line comes in, a key release within this window belongs to the
-- hook press, not to a new cast.
local HOOK_RELEASE_WINDOW_SECONDS = 1

-- Soft-targeting settings while the line is out. SoftTargetInteract = 3 turns
-- soft targeting on for every input type, arc 2 is the widest search arc, and
-- the range (in yards) covers the longest casts.
local REACH_CVARS = {
    SoftTargetInteract = 3,
    SoftTargetInteractArc = 2,
    SoftTargetInteractRange = 60,
}
local BOBBER_ICON_CVARS = {
    SoftTargetIconGameObject = 1,
    SoftTargetIconInteract = 1,
}

-- Override owners. Separate owners let Bobber remove the one-click
-- double-click override without touching the while-fishing hook, and the
-- other way around.
local doubleClickOverrideOwner = CreateFrame("Frame")
local hookOverrideOwner = CreateFrame("Frame")

local isLineOut = false
local lastRightClickTime = 0
local lastDoubleClickCastTime = 0
local lineCameInTime = 0
local hasDoubleClickOverride = false
-- The line went out while the right button was still held from the cast;
-- the hook is set up once the button comes up.
local isHookWaitingForRelease = false
-- The cast button saw the down half of the current key press.
local castButtonSawPressDown = false
-- Shown once per login when you double right-click without a pole.
local hasShownNeedsPoleHint = false

-------------------------------------------------------------------------------
-- The secure cast button
-------------------------------------------------------------------------------

-- A SecureActionButtonTemplate button is the only kind of button allowed to
-- cast a spell. Its attributes say what it does ("type" = "spell", "spell" =
-- the spell name). It has no size, so it's never seen or clicked directly;
-- the cast key binding and the double-click override click it.
local castButton = CreateFrame("Button", CAST_BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
-- Register both halves of a press. The template acts on the down half or the
-- up half depending on the game's "ActionButtonUseKeyDown" option.
castButton:RegisterForClicks("AnyUp", "AnyDown")
castButton:SetAttribute("type", "spell")

local function SetCastButtonToCastFishing()
    if InCombatLockdown() then
        return
    end
    castButton:SetAttribute("type", "spell")
    castButton:SetAttribute("macrotext", nil)
    if ns.fishingSpellName then
        castButton:SetAttribute("spell", ns.fishingSpellName)
    end
end

-- Make the current press do nothing, then go back to casting shortly after.
local function SkipThisPress(button)
    button:SetAttribute("type", nil)
    C_Timer.After(0.5, function()
        ns.RunOutOfCombat(SetCastButtonToCastFishing)
    end)
end

-- Make the current press run `macroText` instead of casting. The button
-- goes back to casting when the press comes up (PostClick below), or after
-- a second if the release never reaches the button.
local isPressRunningMacro = false
local function RunMacroForThisPress(button, macroText)
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", macroText)
    isPressRunningMacro = true
    C_Timer.After(1, function()
        if isPressRunningMacro then
            isPressRunningMacro = false
            ns.RunOutOfCombat(SetCastButtonToCastFishing)
        end
    end)
end

-- Decide what this press does, before the template acts on it. In order:
-- 1. No pole: equip it (if that option is on); the next press goes on.
-- 2. A lure is going on: wait, so the press can't interrupt it.
-- 3. The pole has no lure and the bags have one: put it on (Lures.lua).
-- 4. Otherwise: cast Fishing, which the button does by default.
local function ChooseWhatThisPressDoes(button)
    if ns.settings.castKeyEquipsPole and not ns.IsPoleEquipped() and ns.Gear.EquipPole() then
        SkipThisPress(button)
        return
    end
    if ns.Lures.IsLureGoingOn() then
        SkipThisPress(button)
        return
    end
    local lureMacroText = ns.Lures.GetLureMacroForThisPress()
    if lureMacroText then
        RunMacroForThisPress(button, lureMacroText)
    end
end

-- PreClick runs just before the template acts, once for each half of a
-- press. The decision is made on the down half, which always comes first,
-- so it's in place whichever half the template acts on.
castButton:HookScript("PreClick", function(self, _, isDown)
    if InCombatLockdown() then
        return
    end
    if isDown then
        castButtonSawPressDown = true
        ChooseWhatThisPressDoes(self)
    elseif not castButtonSawPressDown and GetTime() - lineCameInTime < HOOK_RELEASE_WINDOW_SECONDS then
        -- The key went down as a hook and is coming up after the line came
        -- in. Without this, players who cast on key release would recast.
        SkipThisPress(self)
    end
end)

castButton:HookScript("PostClick", function(_, _, isDown)
    if isDown then
        return
    end
    castButtonSawPressDown = false
    if isPressRunningMacro and not InCombatLockdown() then
        isPressRunningMacro = false
        SetCastButtonToCastFishing()
    end
end)

local function UpdateFishingSpell()
    ns.RefreshFishingSpellName()
    ns.RunOutOfCombat(SetCastButtonToCastFishing)
end

ns.On("PLAYER_LOGIN", UpdateFishingSpell)
ns.On("SPELLS_CHANGED", UpdateFishingSpell)

-------------------------------------------------------------------------------
-- When casting is allowed
-------------------------------------------------------------------------------

-- Right-clicks on units (NPCs, mobs, players) and on the interface keep
-- their normal meaning; only right-clicks on the open world count.
local function IsPointerOverOpenWorld()
    if UnitExists("mouseover") then
        return false
    end
    if GetMouseFoci then
        local framesUnderPointer = GetMouseFoci()
        local topFrame = framesUnderPointer and framesUnderPointer[1]
        return topFrame == nil or topFrame == WorldFrame
    end
    return true
end

local function CanCastFishingNow()
    return ns.fishingSpellName ~= nil
        and ns.IsPoleEquipped()
        and not InCombatLockdown()
        and GetNumLootItems() == 0
        and not IsMounted()
        and not IsFlying()
        and not IsFalling()
        and not IsSwimming()
        and not (IsSubmerged and IsSubmerged())
        and not (IsPlayerMoving and IsPlayerMoving())
        and not IsStealthed()
        and not UnitIsDeadOrGhost("player")
        and not (UnitHasVehicleUI and UnitHasVehicleUI("player"))
        and HasFullControl()
end

-- What the window says about double-click casting:
-- "off" (option off), "ready" (pole equipped), or "needs_pole".
function Casting.GetDoubleClickState()
    if not ns.settings.doubleClickCast then
        return "off"
    end
    return ns.IsPoleEquipped() and "ready" or "needs_pole"
end

function Casting.IsLineOut()
    return isLineOut
end

-------------------------------------------------------------------------------
-- Hooking while the line is out
-------------------------------------------------------------------------------

local function RemoveDoubleClickOverride()
    if InCombatLockdown() then
        return
    end
    ClearOverrideBindings(doubleClickOverrideOwner)
    hasDoubleClickOverride = false
end

local function RemoveHookOverrides()
    isHookWaitingForRelease = false
    if not InCombatLockdown() then
        ClearOverrideBindings(hookOverrideOwner)
    end
end

-- Point the right mouse button (single-click mode) and the cast key at the
-- Interact Key action, so the next press hooks the bobber.
local function SetUpHookOverrides()
    isHookWaitingForRelease = false
    if InCombatLockdown() or not isLineOut then
        return
    end
    -- Changing the right button's action while it's held would hand its
    -- release to the new action; wait until it comes up.
    if IsMouseButtonDown("RightButton") then
        isHookWaitingForRelease = true
        return
    end
    RemoveDoubleClickOverride()
    ClearOverrideBindings(hookOverrideOwner)
    if ns.settings.rightClickHookMode == ns.HOOK_SINGLE_CLICK then
        SetOverrideBinding(hookOverrideOwner, true, "BUTTON2", "INTERACTTARGET")
    end
    if ns.settings.castKeyHooks then
        for _, boundKey in ipairs({ GetBindingKey(Casting.CAST_BINDING) }) do
            SetOverrideBinding(hookOverrideOwner, true, boundKey, "INTERACTTARGET")
        end
    end
end

local function ExtendBobberReach()
    if not ns.settings.extendBobberReach then
        return
    end
    ns.CVarLease.Acquire("reach", REACH_CVARS)
    if ns.settings.showBobberIcon then
        ns.CVarLease.Acquire("reach", BOBBER_ICON_CVARS)
    end
end

local function OnLineOut()
    isLineOut = true
    ExtendBobberReach()
    SetUpHookOverrides()
    ns.Fire("BOBBER_CAST_START")
end

local function OnLineIn()
    isLineOut = false
    lineCameInTime = GetTime()
    RemoveHookOverrides()
    ns.CVarLease.Release("reach")
    ns.Fire("BOBBER_CAST_STOP")
end

ns.On("UNIT_SPELLCAST_CHANNEL_START", function(_, _, spellID)
    if ns.IsFishingSpell(spellID) then
        OnLineOut()
    end
end, "player")

ns.On("UNIT_SPELLCAST_CHANNEL_STOP", function()
    if isLineOut then
        OnLineIn()
    end
end, "player")

-- A loading screen can end the channel without a stop event.
ns.On("PLAYER_LEAVING_WORLD", function()
    if isLineOut then
        OnLineIn()
    end
end)

-------------------------------------------------------------------------------
-- Double right-click
-------------------------------------------------------------------------------

local function OnDoubleRightClick()
    local now = GetTime()
    if isLineOut then
        if ns.settings.rightClickHookMode == ns.HOOK_DOUBLE_CLICK then
            SetOverrideBinding(doubleClickOverrideOwner, true, "BUTTON2", "INTERACTTARGET")
            hasDoubleClickOverride = true
        end
        return
    end
    if not ns.settings.doubleClickCast or now - lastDoubleClickCastTime < CAST_DEBOUNCE_SECONDS then
        return
    end
    if not ns.IsPoleEquipped() then
        if not hasShownNeedsPoleHint then
            hasShownNeedsPoleHint = true
            ns.Print("double right-click casting works while a fishing pole is equipped.")
        end
        return
    end
    if CanCastFishingNow() then
        SetOverrideBindingClick(doubleClickOverrideOwner, true, "BUTTON2", CAST_BUTTON_NAME)
        hasDoubleClickOverride = true
        lastDoubleClickCastTime = now
    end
end

-- GLOBAL_MOUSE_DOWN arrives before the game acts on the click, so an
-- override set here already applies to this same click.
ns.On("GLOBAL_MOUSE_DOWN", function(mouseButton)
    if mouseButton ~= "RightButton" then
        return
    end
    if InCombatLockdown() or IsMouseButtonDown("LeftButton") or not IsPointerOverOpenWorld() then
        lastRightClickTime = 0
        return
    end
    local now = GetTime()
    local secondsSinceLastRightClick = now - lastRightClickTime
    local isDoubleClick = secondsSinceLastRightClick >= MIN_DOUBLE_CLICK_SECONDS
        and secondsSinceLastRightClick <= ns.settings.doubleClickSeconds
    if isDoubleClick then
        lastRightClickTime = 0
        OnDoubleRightClick()
    else
        lastRightClickTime = now
    end
end)

ns.On("GLOBAL_MOUSE_UP", function(mouseButton)
    if mouseButton ~= "RightButton" then
        return
    end
    if hasDoubleClickOverride then
        C_Timer.After(OVERRIDE_CLEAR_DELAY_SECONDS, function()
            if not IsMouseButtonDown("RightButton") then
                RemoveDoubleClickOverride()
            end
        end)
    end
    if isHookWaitingForRelease then
        C_Timer.After(OVERRIDE_CLEAR_DELAY_SECONDS, SetUpHookOverrides)
    end
end)

-------------------------------------------------------------------------------
-- Combat
-------------------------------------------------------------------------------

ns.On("PLAYER_REGEN_DISABLED", function()
    -- Last moment before combat lockdown: every button back to normal.
    ClearOverrideBindings(doubleClickOverrideOwner)
    ClearOverrideBindings(hookOverrideOwner)
    hasDoubleClickOverride = false
    isHookWaitingForRelease = false
    ns.CVarLease.Release("reach")
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    SetCastButtonToCastFishing()
    -- If the line is still out after the fight, hooking works again.
    if ns.IsChannelingFishing() then
        isLineOut = true
        ExtendBobberReach()
        SetUpHookOverrides()
    elseif isLineOut then
        OnLineIn()
    end
end)

-- A changed hook option applies to a line that's already out.
ns.On("BOBBER_SETTINGS_CHANGED", function()
    if isLineOut then
        ns.RunOutOfCombat(SetUpHookOverrides)
    end
end)
