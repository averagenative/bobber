--[[
Pole and weapon swapping.

The Bobber window has three gear slots: fishing pole, main hand, and off
hand. Click the pole slot to equip the pole. Click either weapon slot to put
both weapons back.

You don't have to fill the slots yourself:

* Bobber remembers the last fishing pole you equipped. If it hasn't seen
  one yet, it uses the first pole in your bags.
* Bobber remembers the weapons you held before you switched to the pole.

To pick specific items, drag them onto a slot (or pick an item up and click
the slot). Right-click a slot to forget your choice and go back to the
remembered item.

Each slot is a secure macro button running "/equipslot 16 item:12345", so
the weapon slots work even in combat, when addons can't equip anything on
their own. A secure button's macro can only change outside combat, so a
slot you change during combat takes effect when the fight ends. The "Equip
fishing pole" and "Equip weapons" key bindings click hidden buttons with the
same macros.

When combat starts with the pole equipped, Bobber puts your weapons back
(PLAYER_REGEN_DISABLED is the last moment an addon can still equip items).
]]

local _, ns = ...

local Gear = {}
ns.Gear = Gear

local MAIN_HAND = ns.MAIN_HAND_SLOT
local OFF_HAND = ns.OFF_HAND_SLOT

Gear.SLOT_KEYS = { "pole", "mainHand", "offHand" }

local SLOT_LABELS = {
    pole = "Fishing pole",
    mainHand = "Main hand",
    offHand = "Off hand",
}

-- Shown in a slot that has no item yet.
local EMPTY_SLOT_TEXTURES = {
    pole = "Interface\\Icons\\INV_Fishingpole_02",
    mainHand = "Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand",
    offHand = "Interface\\PaperDoll\\UI-PaperDoll-Slot-SecondaryHand",
}

-- Item equip locations each weapon slot accepts.
local MAIN_HAND_EQUIP_LOCATIONS = {
    INVTYPE_WEAPON = true,
    INVTYPE_2HWEAPON = true,
    INVTYPE_WEAPONMAINHAND = true,
}
local OFF_HAND_EQUIP_LOCATIONS = {
    INVTYPE_WEAPON = true,
    INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_SHIELD = true,
    INVTYPE_HOLDABLE = true,
}

-- Wait for both hands to settle before reading what's equipped: equipping a
-- two-handed pole changes the off hand and the main hand as separate events.
local EQUIPMENT_SETTLE_SECONDS = 0.5

local EquipItemByID = (C_Item and C_Item.EquipItemByName) or EquipItemByName
local GetItemCountByID = (C_Item and C_Item.GetItemCount) or GetItemCount

local slotButtons = {}      -- the window's slot buttons
local equipPoleButton       -- hidden, for the key binding
local equipWeaponsButton    -- hidden, for the key binding

-------------------------------------------------------------------------------
-- Which item each slot holds
-------------------------------------------------------------------------------

local function GetGearData()
    return ns.charDB.gear
end

-- The item a slot uses: your choice if you made one, else the remembered one.
function Gear.GetSlotItem(slotKey)
    local gear = GetGearData()
    return gear.chosen[slotKey] or gear.remembered[slotKey]
end

function Gear.IsSlotChosenByPlayer(slotKey)
    return GetGearData().chosen[slotKey] ~= nil
end

local function GetEquipLocation(itemID)
    local _, _, _, equipLocation = C_Item.GetItemInfoInstant(itemID)
    return equipLocation
end

local function IsTwoHanded(itemID)
    return itemID ~= nil and GetEquipLocation(itemID) == "INVTYPE_2HWEAPON"
end

-- Can `itemID` go in this slot? Returns false plus a reason when it can't.
local function CanItemGoInSlot(itemID, slotKey)
    if slotKey == "pole" then
        return ns.IsFishingPole(itemID), "That isn't a fishing pole."
    end
    if ns.IsFishingPole(itemID) then
        return false, "Put fishing poles in the pole slot."
    end
    local equipLocation = GetEquipLocation(itemID)
    if slotKey == "mainHand" then
        return MAIN_HAND_EQUIP_LOCATIONS[equipLocation] == true, "That can't go in your main hand."
    end
    return OFF_HAND_EQUIP_LOCATIONS[equipLocation] == true, "That can't go in your off hand."
end

local function FindPoleInBags()
    local lastBagIndex = NUM_BAG_SLOTS or 4
    for bagIndex = 0, lastBagIndex do
        for slotIndex = 1, C_Container.GetContainerNumSlots(bagIndex) do
            local itemID = C_Container.GetContainerItemID(bagIndex, slotIndex)
            if ns.IsFishingPole(itemID) then
                return itemID
            end
        end
    end
    return nil
end

-- Note what's equipped right now: a pole in the main hand becomes the
-- remembered pole, and anything else becomes the remembered weapons.
local function RememberEquippedGear()
    local remembered = GetGearData().remembered
    local mainHandItem = GetInventoryItemID("player", MAIN_HAND)
    local offHandItem = GetInventoryItemID("player", OFF_HAND)
    if ns.IsFishingPole(mainHandItem) then
        remembered.pole = mainHandItem
    elseif mainHandItem or offHandItem then
        remembered.mainHand = mainHandItem
        remembered.offHand = offHandItem
    end
    if not remembered.pole then
        remembered.pole = FindPoleInBags()
    end
end

-------------------------------------------------------------------------------
-- Equip macros
-------------------------------------------------------------------------------

local function EquipSlotLine(inventorySlot, itemID)
    return "/equipslot " .. inventorySlot .. " item:" .. itemID
end

function Gear.GetPoleMacroText()
    local poleItem = Gear.GetSlotItem("pole")
    return poleItem and EquipSlotLine(MAIN_HAND, poleItem) or nil
end

function Gear.GetWeaponsMacroText()
    local mainHandItem = Gear.GetSlotItem("mainHand")
    local offHandItem = Gear.GetSlotItem("offHand")
    local lines = {}
    if mainHandItem then
        lines[#lines + 1] = EquipSlotLine(MAIN_HAND, mainHandItem)
    end
    if offHandItem and not IsTwoHanded(mainHandItem) then
        lines[#lines + 1] = EquipSlotLine(OFF_HAND, offHandItem)
    end
    return #lines > 0 and table.concat(lines, "\n") or nil
end

-- "type1" and "macrotext1" apply to left clicks only, so right-clicking a
-- slot (to forget your choice) never equips anything.
local function SetButtonMacro(button, macroText)
    button:SetAttribute("type1", macroText and "macro" or nil)
    button:SetAttribute("macrotext1", macroText)
end

local function GetMacroTextForSlot(slotKey)
    if slotKey == "pole" then
        return Gear.GetPoleMacroText()
    end
    return Gear.GetWeaponsMacroText()
end

-- Copy the current slot items into every secure button's macro.
local function UpdateButtonMacros()
    for _, button in ipairs(slotButtons) do
        SetButtonMacro(button, GetMacroTextForSlot(button.slotKey))
    end
    if equipPoleButton then
        SetButtonMacro(equipPoleButton, Gear.GetPoleMacroText())
        SetButtonMacro(equipWeaponsButton, Gear.GetWeaponsMacroText())
    end
end

local function OnGearChanged()
    ns.RunOutOfCombat(UpdateButtonMacros)
    ns.Fire("BOBBER_GEAR_CHANGED")
end

-------------------------------------------------------------------------------
-- Equipping from addon code (outside combat only)
-------------------------------------------------------------------------------

-- Used by the cast key: equip the pole from your bags. Returns true when it
-- started equipping one.
function Gear.EquipPole()
    if InCombatLockdown() then
        return false
    end
    local poleItem = Gear.GetSlotItem("pole") or FindPoleInBags()
    if not poleItem or GetItemCountByID(poleItem) == 0 then
        return false
    end
    EquipItemByID(poleItem, MAIN_HAND)
    return true
end

function Gear.EquipWeapons()
    if InCombatLockdown() then
        return false
    end
    local mainHandItem = Gear.GetSlotItem("mainHand")
    local offHandItem = Gear.GetSlotItem("offHand")
    if mainHandItem then
        EquipItemByID(mainHandItem, MAIN_HAND)
    end
    if offHandItem and not IsTwoHanded(mainHandItem) then
        EquipItemByID(offHandItem, OFF_HAND)
    end
    return mainHandItem ~= nil or offHandItem ~= nil
end

-------------------------------------------------------------------------------
-- Choosing items by drag and drop
-------------------------------------------------------------------------------

-- Take the item on the cursor (if any) as this slot's choice.
local function TakeItemFromCursor(button)
    local cursorType, itemID = GetCursorInfo()
    if cursorType ~= "item" or not itemID then
        return false
    end
    local canGoInSlot, reason = CanItemGoInSlot(itemID, button.slotKey)
    ClearCursor()
    if not canGoInSlot then
        UIErrorsFrame:AddMessage(reason, 1, 0.3, 0.1)
        return true
    end
    GetGearData().chosen[button.slotKey] = itemID
    OnGearChanged()
    return true
end

local function ForgetChosenItem(button)
    GetGearData().chosen[button.slotKey] = nil
    OnGearChanged()
end

-- Picking an item up and clicking a slot drops it there, instead of
-- equipping. The secure action is turned off for that one press.
local function OnSlotPreClick(button, mouseButton)
    if InCombatLockdown() or mouseButton ~= "LeftButton" then
        return
    end
    if TakeItemFromCursor(button) then
        button:SetAttribute("type1", nil)
        C_Timer.After(0.3, function()
            ns.RunOutOfCombat(UpdateButtonMacros)
        end)
    end
end

local function OnSlotPostClick(button, mouseButton, isDown)
    if mouseButton == "RightButton" and not isDown and Gear.IsSlotChosenByPlayer(button.slotKey) then
        ForgetChosenItem(button)
    end
end

local function OnSlotReceiveDrag(button)
    if not InCombatLockdown() then
        TakeItemFromCursor(button)
    end
end

-------------------------------------------------------------------------------
-- Slot tooltips
-------------------------------------------------------------------------------

local function ShowSlotTooltip(button)
    local slotKey = button.slotKey
    local itemID = Gear.GetSlotItem(slotKey)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if itemID then
        GameTooltip:SetItemByID(itemID)
    else
        GameTooltip:SetText(SLOT_LABELS[slotKey])
    end
    GameTooltip:AddLine(" ")
    if slotKey == "pole" then
        GameTooltip:AddLine("Click: equip this fishing pole.", 1, 1, 1)
    else
        GameTooltip:AddLine("Click: put your weapons back.", 1, 1, 1)
    end
    GameTooltip:AddLine("Drag an item here to choose it.", 0.7, 0.7, 0.7)
    if Gear.IsSlotChosenByPlayer(slotKey) then
        GameTooltip:AddLine("Right-click: go back to the remembered item.", 0.7, 0.7, 0.7)
    elseif itemID then
        GameTooltip:AddLine("Remembered automatically.", 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

local function HideTooltip()
    GameTooltip:Hide()
end

-------------------------------------------------------------------------------
-- Buttons
-------------------------------------------------------------------------------

local function CreateSecureEquipButton(globalName, parent)
    local button = CreateFrame("Button", globalName, parent, "SecureActionButtonTemplate")
    -- Both halves, so the template can follow the "ActionButtonUseKeyDown" option.
    button:RegisterForClicks("AnyUp", "AnyDown")
    return button
end

-- Build one of the window's slot buttons. Window.lua positions and themes it.
function Gear.CreateSlotButton(slotKey, parent, size)
    local globalName = "BobberGearSlot" .. slotKey:sub(1, 1):upper() .. slotKey:sub(2)
    local button = CreateSecureEquipButton(globalName, parent)
    button.slotKey = slotKey
    button:SetSize(size, size)

    button.background = button:CreateTexture(nil, "BACKGROUND")
    button.background:SetAllPoints()
    button.background:SetColorTexture(0, 0, 0, 0.5)

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- A thin frame around the icon: accent color when the item is equipped.
    button.borderTop = button:CreateTexture(nil, "OVERLAY")
    button.borderTop:SetPoint("TOPLEFT")
    button.borderTop:SetPoint("TOPRIGHT")
    button.borderTop:SetHeight(1)
    button.borderBottom = button:CreateTexture(nil, "OVERLAY")
    button.borderBottom:SetPoint("BOTTOMLEFT")
    button.borderBottom:SetPoint("BOTTOMRIGHT")
    button.borderBottom:SetHeight(1)
    button.borderLeft = button:CreateTexture(nil, "OVERLAY")
    button.borderLeft:SetPoint("TOPLEFT")
    button.borderLeft:SetPoint("BOTTOMLEFT")
    button.borderLeft:SetWidth(1)
    button.borderRight = button:CreateTexture(nil, "OVERLAY")
    button.borderRight:SetPoint("TOPRIGHT")
    button.borderRight:SetPoint("BOTTOMRIGHT")
    button.borderRight:SetWidth(1)

    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    button:HookScript("PreClick", OnSlotPreClick)
    button:HookScript("PostClick", OnSlotPostClick)
    button:SetScript("OnReceiveDrag", OnSlotReceiveDrag)
    button:SetScript("OnEnter", ShowSlotTooltip)
    button:SetScript("OnLeave", HideTooltip)

    slotButtons[#slotButtons + 1] = button
    ns.RunOutOfCombat(UpdateButtonMacros)
    return button
end

local function SetBorderColor(button, red, green, blue, alpha)
    button.borderTop:SetColorTexture(red, green, blue, alpha)
    button.borderBottom:SetColorTexture(red, green, blue, alpha)
    button.borderLeft:SetColorTexture(red, green, blue, alpha)
    button.borderRight:SetColorTexture(red, green, blue, alpha)
end

local function IsItemEquipped(itemID)
    return itemID ~= nil
        and (GetInventoryItemID("player", MAIN_HAND) == itemID or GetInventoryItemID("player", OFF_HAND) == itemID)
end

-- Refresh the slot icons and borders. `theme` comes from Themes.lua.
function Gear.UpdateSlotButtons(theme)
    for _, button in ipairs(slotButtons) do
        local itemID = Gear.GetSlotItem(button.slotKey)
        if itemID then
            button.icon:SetTexture(C_Item.GetItemIconByID(itemID))
            button.icon:SetDesaturated(false)
            -- An item that's neither equipped nor in your bags shows dimmed.
            local isAvailable = IsItemEquipped(itemID) or GetItemCountByID(itemID) > 0
            button.icon:SetAlpha(isAvailable and 1 or 0.35)
        else
            button.icon:SetTexture(EMPTY_SLOT_TEXTURES[button.slotKey])
            button.icon:SetDesaturated(true)
            button.icon:SetAlpha(0.6)
        end
        if IsItemEquipped(itemID) then
            SetBorderColor(button, theme.accent[1], theme.accent[2], theme.accent[3], 1)
        else
            SetBorderColor(button, theme.border[1], theme.border[2], theme.border[3], 0.6)
        end
    end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

ns.On("BOBBER_DATA_READY", function()
    -- Zero-size buttons that only key bindings click.
    equipPoleButton = CreateSecureEquipButton("BobberEquipPoleButton", UIParent)
    equipWeaponsButton = CreateSecureEquipButton("BobberEquipWeaponsButton", UIParent)
end)

ns.On("PLAYER_LOGIN", function()
    RememberEquippedGear()
    OnGearChanged()
end)

-- Equipping fires one event per slot; act once things settle.
local isEquipmentCheckScheduled = false
ns.On("PLAYER_EQUIPMENT_CHANGED", function(inventorySlot)
    if inventorySlot ~= MAIN_HAND and inventorySlot ~= OFF_HAND then
        return
    end
    if isEquipmentCheckScheduled then
        return
    end
    isEquipmentCheckScheduled = true
    C_Timer.After(EQUIPMENT_SETTLE_SECONDS, function()
        isEquipmentCheckScheduled = false
        RememberEquippedGear()
        OnGearChanged()
    end)
end)

-- Bag changes can make a slot's item available or missing.
ns.On("BAG_UPDATE_DELAYED", function()
    ns.Fire("BOBBER_GEAR_CHANGED")
end)

ns.On("PLAYER_REGEN_DISABLED", function()
    if ns.settings.weaponsOnCombat and ns.IsPoleEquipped() then
        Gear.EquipWeapons()
    end
end)
