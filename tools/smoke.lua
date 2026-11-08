--[[
Smoke test: load Bobber in a fake WoW environment and play a fishing
session. Run from the repository root:

    nvim -l tools/smoke.lua

This can't prove Bobber works in the real game (only the game can), but it
catches what breaks most often: typos, nil values, wrong function names,
logic that leaves an override or a setting behind, and accidental globals.

How it works:

* The "fake game" section defines every WoW API Bobber calls, backed by
  plain tables: an inventory, a bag, CVars, override bindings, a loot
  window, a clock, and timers.
* Frames are tables with the handful of widget methods the tests need.
  Any other method whose name starts with a capital letter (the WoW naming
  style) quietly does nothing, so layout calls don't need fakes.
* Clicking a secure button runs PreClick, then does what the real template
  would ("type" = "spell" casts, "macro" runs /equipslot lines), then runs
  PostClick.
* The scenario at the bottom fires game events in the order the game would
  and checks the results.
]]

-------------------------------------------------------------------------------
-- Test reporting
-------------------------------------------------------------------------------

local failureCount = 0
local checkCount = 0

local function Check(condition, description)
    checkCount = checkCount + 1
    if condition then
        print("ok   " .. description)
    else
        failureCount = failureCount + 1
        print("FAIL " .. description)
    end
end

local function Step(title, body)
    print("-- " .. title)
    local succeeded, errorMessage = pcall(body)
    if not succeeded then
        failureCount = failureCount + 1
        print("FAIL error during '" .. title .. "': " .. tostring(errorMessage))
    end
end

-------------------------------------------------------------------------------
-- Fake game: clock and timers
-------------------------------------------------------------------------------

local currentTime = 1000
local pendingTimers = {}

function GetTime()
    return currentTime
end

C_Timer = {
    After = function(delaySeconds, callback)
        pendingTimers[#pendingTimers + 1] = { dueAt = currentTime + delaySeconds, callback = callback }
    end,
}

-- Move the clock forward, running timers that come due on the way.
local function AdvanceTime(seconds)
    local targetTime = currentTime + seconds
    while true do
        table.sort(pendingTimers, function(first, second) return first.dueAt < second.dueAt end)
        local nextTimer = pendingTimers[1]
        if not nextTimer or nextTimer.dueAt > targetTime then
            break
        end
        table.remove(pendingTimers, 1)
        currentTime = nextTimer.dueAt
        nextTimer.callback()
    end
    currentTime = targetTime
end

-------------------------------------------------------------------------------
-- Fake game: frames
-------------------------------------------------------------------------------

local framesListeningByEvent = {}  -- [event] = { frame = true }
local FrameMethods = {}
local FrameMetatable = {
    __index = function(_, key)
        local method = FrameMethods[key]
        if method then
            return method
        end
        -- Unfaked widget methods (SetPoint, SetTextColor, ...) do nothing.
        if type(key) == "string" and key:match("^%u") then
            return function() end
        end
        return nil
    end,
}

local function NewFrame(globalName)
    local frame = setmetatable({
        isShown = true,
        scripts = {},
        attributes = {},
        text = "",
        width = 0,
        height = 0,
        points = {},
        globalName = globalName,
    }, FrameMetatable)
    if globalName then
        _G[globalName] = frame
    end
    return frame
end

function FrameMethods.SetScript(frame, scriptName, handler) frame.scripts[scriptName] = handler end
function FrameMethods.GetScript(frame, scriptName) return frame.scripts[scriptName] end
function FrameMethods.HookScript(frame, scriptName, handler)
    local previousHandler = frame.scripts[scriptName]
    frame.scripts[scriptName] = function(...)
        if previousHandler then previousHandler(...) end
        handler(...)
    end
end
function FrameMethods.RegisterEvent(frame, eventName)
    framesListeningByEvent[eventName] = framesListeningByEvent[eventName] or {}
    framesListeningByEvent[eventName][frame] = true
end
function FrameMethods.RegisterUnitEvent(frame, eventName) FrameMethods.RegisterEvent(frame, eventName) end
function FrameMethods.SetAttribute(frame, name, value)
    assert(not inCombat or not frame.isSecure, "SetAttribute on a secure frame during combat")
    frame.attributes[name] = value
end
function FrameMethods.GetAttribute(frame, name) return frame.attributes[name] end
function FrameMethods.Show(frame)
    assert(not inCombat or not frame.hasSecureChildren, "Show on a protected frame during combat")
    frame.isShown = true
    if frame.scripts.OnShow then frame.scripts.OnShow(frame) end
end
function FrameMethods.Hide(frame)
    assert(not inCombat or not frame.hasSecureChildren, "Hide on a protected frame during combat")
    frame.isShown = false
end
function FrameMethods.SetShown(frame, shouldShow)
    if shouldShow then frame:Show() else frame:Hide() end
end
function FrameMethods.IsShown(frame) return frame.isShown end
function FrameMethods.IsVisible(frame) return frame.isShown end
function FrameMethods.SetText(frame, text) frame.text = text == nil and "" or tostring(text) end
function FrameMethods.GetText(frame) return frame.text end
function FrameMethods.GetStringWidth(frame) return #frame.text * 6 end
function FrameMethods.SetSize(frame, width, height) frame.width, frame.height = width, height end
function FrameMethods.SetWidth(frame, width) frame.width = width end
function FrameMethods.SetHeight(frame, height) frame.height = height end
function FrameMethods.GetWidth(frame) return frame.width end
function FrameMethods.GetHeight(frame) return frame.height end
function FrameMethods.SetPoint(frame, ...) frame.points[#frame.points + 1] = { ... } end
function FrameMethods.ClearAllPoints(frame) frame.points = {} end
function FrameMethods.GetPoint(frame)
    local firstPoint = frame.points[1] or { "CENTER" }
    return firstPoint[1], UIParent, firstPoint[3] or firstPoint[1], 10, 20
end
function FrameMethods.GetName(frame) return frame.globalName end
function FrameMethods.CreateTexture(frame) return NewFrame() end

-- Every font string is kept, so tests can look for text on screen.
local allFontStrings = {}
function FrameMethods.CreateFontString(frame)
    local fontString = NewFrame()
    fontString.parent = frame
    allFontStrings[#allFontStrings + 1] = fontString
    return fontString
end

-- True if a font string whose frame is shown has text matching `pattern`.
local function IsTextShown(pattern)
    for _, fontString in ipairs(allFontStrings) do
        if fontString.text:find(pattern) and fontString.parent.isShown ~= false then
            return true
        end
    end
    return false
end

function CreateFrame(_, globalName, parent, templateNames)
    local frame = NewFrame(globalName)
    frame.parent = parent
    if templateNames and templateNames:find("SecureActionButtonTemplate") then
        frame.isSecure = true
        -- A frame holding a secure button becomes protected too.
        local ancestor = parent
        while ancestor and ancestor ~= UIParent do
            ancestor.hasSecureChildren = true
            ancestor = ancestor.parent
        end
    end
    return frame
end

UIParent = NewFrame("UIParent")
WorldFrame = NewFrame("WorldFrame")
GameTooltip = NewFrame("GameTooltip")
UIErrorsFrame = NewFrame("UIErrorsFrame")

local chatMessages = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) chatMessages[#chatMessages + 1] = message end }

local function FireEvent(eventName, ...)
    for frame in pairs(framesListeningByEvent[eventName] or {}) do
        frame.scripts.OnEvent(frame, eventName, ...)
    end
end

-------------------------------------------------------------------------------
-- Fake game: items, inventory, bags
-------------------------------------------------------------------------------

local POLE = 6256
local SWORD = 2000
local SHIELD = 3000
local AXE = 2500
local SMALLFISH = 6291
local SUNFISH = 6358

local itemDatabase = {
    [POLE] = { equipLocation = "INVTYPE_2HWEAPON", classID = 2, subclassID = 20 },
    [SWORD] = { equipLocation = "INVTYPE_WEAPON", classID = 2, subclassID = 7 },
    [AXE] = { equipLocation = "INVTYPE_WEAPON", classID = 2, subclassID = 0 },
    [SHIELD] = { equipLocation = "INVTYPE_SHIELD", classID = 4, subclassID = 6 },
    [SMALLFISH] = { equipLocation = "", classID = 7, subclassID = 8 },
    [SUNFISH] = { equipLocation = "", classID = 7, subclassID = 8 },
}

local equippedItems = { [16] = SWORD, [17] = SHIELD }
local bagItemCounts = { [POLE] = 1, [AXE] = 1 }

local function ItemIDFrom(item)
    if type(item) == "number" then
        return item
    end
    return tonumber(tostring(item):match("item:(%d+)"))
end

local function EquipItem(item, inventorySlot)
    local itemID = ItemIDFrom(item)
    inventorySlot = tonumber(inventorySlot)
    if not itemID or (bagItemCounts[itemID] or 0) == 0 then
        return
    end
    local function MoveToBags(slotNumber)
        local previousItem = equippedItems[slotNumber]
        if previousItem then
            bagItemCounts[previousItem] = (bagItemCounts[previousItem] or 0) + 1
            equippedItems[slotNumber] = nil
            FireEvent("PLAYER_EQUIPMENT_CHANGED", slotNumber, false)
        end
    end
    MoveToBags(inventorySlot)
    if inventorySlot == 16 and itemDatabase[itemID].equipLocation == "INVTYPE_2HWEAPON" then
        MoveToBags(17)
    end
    bagItemCounts[itemID] = bagItemCounts[itemID] - 1
    equippedItems[inventorySlot] = itemID
    FireEvent("PLAYER_EQUIPMENT_CHANGED", inventorySlot, true)
end

C_Item = {
    GetItemInfoInstant = function(item)
        local itemID = ItemIDFrom(item)
        local info = itemID and itemDatabase[itemID]
        if not info then
            return nil
        end
        return itemID, "type", "subtype", info.equipLocation, 134400, info.classID, info.subclassID
    end,
    EquipItemByName = EquipItem,
    GetItemCount = function(itemID) return bagItemCounts[itemID] or 0 end,
    GetItemIconByID = function() return 134400 end,
    GetItemQualityColor = function() return 1, 1, 1 end,
}

function GetInventoryItemID(_, inventorySlot) return equippedItems[inventorySlot] end

local function SortedBagItemIDs()
    local itemIDs = {}
    for itemID, count in pairs(bagItemCounts) do
        if count > 0 then itemIDs[#itemIDs + 1] = itemID end
    end
    table.sort(itemIDs)
    return itemIDs
end

C_Container = {
    GetContainerNumSlots = function(bagIndex) return bagIndex == 0 and 16 or 0 end,
    GetContainerItemID = function(_, slotIndex) return SortedBagItemIDs()[slotIndex] end,
}
NUM_BAG_SLOTS = 4

local cursorItemID = nil
function GetCursorInfo()
    if cursorItemID then return "item", cursorItemID end
    return nil
end
function ClearCursor() cursorItemID = nil end

-------------------------------------------------------------------------------
-- Fake game: CVars, bindings, spells, loot, everything else
-------------------------------------------------------------------------------

local ORIGINAL_CVARS = {
    Sound_EnableAllSound = "1", Sound_EnableSFX = "1", Sound_SFXVolume = "0.5",
    Sound_MusicVolume = "0.4", Sound_AmbienceVolume = "0.6", Sound_EnableSoundWhenGameIsInBG = "0",
    SoftTargetInteract = "1", SoftTargetInteractArc = "0", SoftTargetInteractRange = "10",
    SoftTargetIconGameObject = "0", SoftTargetIconInteract = "0", ActionButtonUseKeyDown = "1",
}
local cvars = {}
for name, value in pairs(ORIGINAL_CVARS) do cvars[name] = value end

C_CVar = {
    GetCVar = function(name) return cvars[name] end,
    SetCVar = function(name, value) cvars[name] = tostring(value) end,
}
function GetCVarBool(name) return cvars[name] == "1" end

function hooksecurefunc(tableOrName, functionName, hook)
    local owner = tableOrName
    if type(tableOrName) == "string" then
        owner, functionName, hook = _G, tableOrName, functionName
    end
    local original = owner[functionName]
    owner[functionName] = function(...)
        local results = { original(...) }
        hook(...)
        return unpack(results)
    end
end

-- Override bindings: the newest override for a key wins.
local overrideSequence = 0
local overridesByOwner = {}
local function SetOverride(owner, key, command)
    overridesByOwner[owner] = overridesByOwner[owner] or {}
    if command then
        overrideSequence = overrideSequence + 1
        overridesByOwner[owner][key] = { command = command, sequence = overrideSequence }
    else
        overridesByOwner[owner][key] = nil
    end
end
function SetOverrideBinding(owner, _, key, command)
    assert(not inCombat, "SetOverrideBinding during combat")
    SetOverride(owner, key, command)
end
function SetOverrideBindingClick(owner, _, key, buttonName, mouseButton)
    assert(not inCombat, "SetOverrideBindingClick during combat")
    SetOverride(owner, key, "CLICK " .. buttonName .. ":" .. (mouseButton or "LeftButton"))
end
function ClearOverrideBindings(owner)
    assert(not inCombat, "ClearOverrideBindings during combat")
    overridesByOwner[owner] = nil
end
local function ActiveOverride(key)
    local newest
    for _, overrides in pairs(overridesByOwner) do
        local override = overrides[key]
        if override and (not newest or override.sequence > newest.sequence) then
            newest = override
        end
    end
    return newest and newest.command
end

local boundKeysByCommand = { ["CLICK BobberCastButton:LeftButton"] = "F" }
function GetBindingKey(command) return boundKeysByCommand[command] end

inCombat = false
function InCombatLockdown() return inCombat end

local mouseButtonsDown = {}
function IsMouseButtonDown(mouseButton) return mouseButtonsDown[mouseButton] == true end
function GetMouseFoci() return { WorldFrame } end
function UnitExists() return false end
function IsControlKeyDown() return false end

local channelSpellID = nil
function UnitChannelInfo()
    if channelSpellID then
        return "Fishing", "", 136245, 0, 0, false, false, channelSpellID
    end
    return nil
end

C_Spell = {
    GetSpellName = function(spellID)
        if spellID == 7620 or spellID == 131474 then return "Fishing" end
        return "Some Other Spell"
    end,
}

local lootWindow = { isFishing = false, slots = {} }
function GetNumLootItems() return #lootWindow.slots end
function IsFishingLoot() return lootWindow.isFishing end
function GetLootSlotType() return 1 end
function GetLootSlotInfo(slotIndex)
    local slot = lootWindow.slots[slotIndex]
    return 134400, slot.name, slot.quantity, nil, slot.quality
end
function GetLootSlotLink(slotIndex) return "|Hitem:" .. lootWindow.slots[slotIndex].itemID .. "::|h[x]|h" end
function LootSlotHasItem(slotIndex) return not lootWindow.slots[slotIndex].looted end
function LootSlot(slotIndex) lootWindow.slots[slotIndex].looted = true end

function GetProfessions() return nil, nil, nil, 4, nil end
function GetProfessionInfo() return "Fishing", 136245, fishingSkill or 142, 150, 1, 0, 356, 25 end
function GetWeaponEnchantInfo() return true, 492000, 0, 263 end
function GetRealZoneText() return "Elwynn Forest" end

function IsMounted() return false end
function IsFlying() return false end
function IsFalling() return false end
function IsSwimming() return false end
function IsSubmerged() return false end
function IsPlayerMoving() return false end
function IsStealthed() return false end
function UnitIsDeadOrGhost() return false end
function UnitHasVehicleUI() return false end
function HasFullControl() return true end
function issecretvalue() return false end
function geterrorhandler() return function(message) error(message, 0) end end

Enum = {
    ItemClass = { Weapon = 2 },
    ItemWeaponSubclass = { Fishingpole = 20 },
    LootSlotType = { Item = 1, Money = 2 },
}
INVSLOT_MAINHAND = 16
INVSLOT_OFFHAND = 17
ERR_FISH_ESCAPED = "Your fish got away."
ERR_FISH_NOT_HOOKED = "No fish are hooked."
ITEM_QUALITY_COLORS = {}
SlashCmdList = {}
MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }

local registeredSettings = {}
Settings = {
    RegisterVerticalLayoutCategory = function(name)
        return { name = name, GetID = function() return 1 end }, { AddInitializer = function() end }
    end,
    RegisterAddOnSetting = function(_, _, key, valueTable, valueType, _, defaultValue)
        assert(type(valueTable[key]) == valueType, "setting " .. key .. " should be a " .. valueType)
        assert(type(defaultValue) == valueType, "default for " .. key .. " should be a " .. valueType)
        local setting = { key = key }
        function setting:SetValueChangedCallback(callback) self.onChange = callback end
        registeredSettings[key] = setting
        return setting
    end,
    CreateCheckbox = function() end,
    CreateDropdown = function(_, _, getChoices) assert(#getChoices() > 0, "dropdown with no choices") end,
    CreateSlider = function() end,
    CreateSliderOptions = function() return { SetLabelFormatter = function() end } end,
    CreateControlTextContainer = function()
        local choices = {}
        return {
            Add = function(_, value, label) choices[#choices + 1] = { value = value, label = label } end,
            GetData = function() return choices end,
        }
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
}
function CreateSettingsListSectionHeaderInitializer() return {} end

-------------------------------------------------------------------------------
-- Secure button clicks
-------------------------------------------------------------------------------

local castSpells = {}

local function RunMacro(macroText)
    for line in macroText:gmatch("[^\n]+") do
        local inventorySlot, itemID = line:match("^/equipslot (%d+) item:(%d+)$")
        assert(inventorySlot, "unexpected macro line: " .. line)
        EquipItem(tonumber(itemID), tonumber(inventorySlot))
    end
end

-- One half of a click on a secure button, the way the template handles it.
local function ClickHalf(button, mouseButton, isDown)
    if button.scripts.PreClick then button.scripts.PreClick(button, mouseButton, isDown) end
    local actsOnDown = cvars.ActionButtonUseKeyDown == "1"
    if isDown == actsOnDown then
        local suffix = mouseButton == "LeftButton" and "1" or "2"
        local actionType = button.attributes["type" .. suffix] or button.attributes.type
        if actionType == "spell" then
            castSpells[#castSpells + 1] = button.attributes.spell
        elseif actionType == "macro" then
            RunMacro(button.attributes["macrotext" .. suffix] or button.attributes.macrotext)
        end
    end
    if button.scripts.PostClick then button.scripts.PostClick(button, mouseButton, isDown) end
end

local function Click(button, mouseButton)
    ClickHalf(button, mouseButton or "LeftButton", true)
    ClickHalf(button, mouseButton or "LeftButton", false)
end

-- A right-click on the world: GLOBAL_MOUSE_DOWN first, then the button's
-- current binding gets the press (an override click hits its button).
local function RightClickWorld(holdSeconds)
    mouseButtonsDown.RightButton = true
    FireEvent("GLOBAL_MOUSE_DOWN", "RightButton")
    local command = ActiveOverride("BUTTON2")
    local clickedButtonName = command and command:match("^CLICK ([%w_]+):")
    if clickedButtonName then
        ClickHalf(_G[clickedButtonName], "LeftButton", true)
    end
    AdvanceTime(holdSeconds or 0.05)
    mouseButtonsDown.RightButton = false
    FireEvent("GLOBAL_MOUSE_UP", "RightButton")
    if clickedButtonName then
        ClickHalf(_G[clickedButtonName], "LeftButton", false)
    end
    return command
end

-------------------------------------------------------------------------------
-- Load Bobber
-------------------------------------------------------------------------------

local globalsBeforeLoad = {}
for key in pairs(_G) do globalsBeforeLoad[key] = true end

local addonTable = {}
local tocText = assert(io.open("Bobber.toc")):read("*a")
for line in tocText:gmatch("[^\r\n]+") do
    if line:match("^[%w_]+%.lua$") then
        local chunk = assert(loadfile(line))
        chunk("Bobber", addonTable)
    end
end
local ns = addonTable

local function StartChannel()
    channelSpellID = 7620
    FireEvent("UNIT_SPELLCAST_CHANNEL_START", "player", "cast-guid", 7620)
end

local function StopChannel()
    channelSpellID = nil
    FireEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast-guid", 7620)
end

local function OpenFishingLoot(items)
    lootWindow.isFishing = true
    lootWindow.slots = items
    FireEvent("LOOT_READY", false)
end

local function CloseLoot()
    lootWindow.isFishing = false
    lootWindow.slots = {}
end

-------------------------------------------------------------------------------
-- Scenario
-------------------------------------------------------------------------------

Step("load and log in", function()
    FireEvent("ADDON_LOADED", "Bobber")
    FireEvent("PLAYER_LOGIN")
    Check(BobberDB.settings.enhanceSounds == true, "enhanced sounds default on")
    Check(BobberDB.settings.doubleClickCast == true, "double-click casting default on")
    Check(BobberDB.settings.rightClickHookMode == ns.HOOK_SINGLE_CLICK, "single right-click hooking default on")
    Check(BobberCastButton.attributes.spell == "Fishing", "cast button casts Fishing")
    Check(BobberCharDB.gear.remembered.mainHand == SWORD, "remembers the sword")
    Check(BobberCharDB.gear.remembered.offHand == SHIELD, "remembers the shield")
    Check(BobberCharDB.gear.remembered.pole == POLE, "finds the pole in the bags")
    Check(BobberWindow:IsShown() == false, "window starts hidden without a pole")
    Check(registeredSettings.windowTheme ~= nil, "options panel registered")
end)

Step("double right-click without a pole", function()
    RightClickWorld()
    AdvanceTime(0.2)
    RightClickWorld()
    Check(#castSpells == 0, "no cast without a pole")
    Check(ActiveOverride("BUTTON2") == nil, "no override without a pole")
    Check(chatMessages[#chatMessages]:find("fishing pole") ~= nil, "explains that a pole is needed")
end)

Step("equip the pole from the window slot", function()
    Check(BobberGearSlotPole.attributes.macrotext1 == "/equipslot 16 item:" .. POLE, "pole slot macro")
    Click(BobberGearSlotPole)
    AdvanceTime(1)
    Check(equippedItems[16] == POLE, "pole equipped")
    Check(equippedItems[17] == nil, "off hand went to the bags")
    Check(BobberCharDB.gear.remembered.offHand == SHIELD, "still remembers the shield")
    Check(cvars.Sound_SFXVolume == "1" and cvars.Sound_MusicVolume == "0", "fishing sounds enhanced")
    Check(BobberWindow:IsShown(), "window opened with the pole")
end)

Step("double right-click casts", function()
    AdvanceTime(2)
    RightClickWorld()
    AdvanceTime(0.2)
    mouseButtonsDown.RightButton = true
    FireEvent("GLOBAL_MOUSE_DOWN", "RightButton")
    Check(ActiveOverride("BUTTON2") == "CLICK BobberCastButton:LeftButton", "second click points at the cast button")
    ClickHalf(BobberCastButton, "LeftButton", true)
    Check(castSpells[#castSpells] == "Fishing", "Fishing was cast")
    StartChannel()
    Check(cvars.SoftTargetInteractRange == "60", "bobber reach extended")
    Check(ActiveOverride("BUTTON2") ~= "INTERACTTARGET", "hook waits for the right button to come up")
    AdvanceTime(0.05)
    mouseButtonsDown.RightButton = false
    FireEvent("GLOBAL_MOUSE_UP", "RightButton")
    ClickHalf(BobberCastButton, "LeftButton", false)
    AdvanceTime(0.2)
    Check(ActiveOverride("BUTTON2") == "INTERACTTARGET", "right-click now hooks")
    Check(ActiveOverride("F") == "INTERACTTARGET", "cast key now hooks")
    Check(BobberCharDB.lifetime.casts == 1, "cast counted")
end)

Step("right-click hooks and the catch is looted", function()
    AdvanceTime(8)
    local command = RightClickWorld()
    Check(command == "INTERACTTARGET", "right-click ran Interact")
    OpenFishingLoot({
        { itemID = SMALLFISH, name = "Raw Brilliant Smallfish", quantity = 1, quality = 1 },
        { itemID = SUNFISH, name = "Raw Sunscale Salmon", quantity = 2, quality = 1 },
    })
    Check(lootWindow.slots[1].looted and lootWindow.slots[2].looted, "auto-looted both items")
    StopChannel()
    CloseLoot()
    AdvanceTime(0.2)
    Check(ActiveOverride("BUTTON2") == nil, "right-click back to normal")
    Check(ActiveOverride("F") == nil, "cast key back to normal")
    Check(cvars.SoftTargetInteractRange == "10", "reach restored")
    Check(BobberCharDB.lifetime.catches == 1, "catch counted")
    Check(BobberCharDB.lifetime.items[SUNFISH] == 2, "item quantities counted")
    Check(BobberDB.itemInfo[SMALLFISH].name == "Raw Brilliant Smallfish", "item name remembered")
end)

Step("a getaway and an early hook", function()
    AdvanceTime(3)
    StartChannel()
    FireEvent("UI_ERROR_MESSAGE", 0, ERR_FISH_ESCAPED)
    StopChannel()
    AdvanceTime(3)
    StartChannel()
    FireEvent("UI_ERROR_MESSAGE", 0, ERR_FISH_NOT_HOOKED)
    StopChannel()
    Check(BobberCharDB.lifetime.escapes == 1, "getaway counted")
    Check(BobberCharDB.lifetime.earlyHooks == 1, "early hook counted")
    Check(BobberCharDB.zones["Elwynn Forest"].casts == 3, "zone casts counted")
end)

Step("the window shows the catches", function()
    for _, scopeKey in ipairs({ "session", "zone", "lifetime" }) do
        ns.Window.SetScope(scopeKey)
        Check(IsTextShown("Raw Sunscale Salmon") and IsTextShown("Raw Brilliant Smallfish"),
            "the " .. scopeKey .. " tab lists both fish")
        Check(IsTextShown("^3 casts  1 caught  1 got away  1 too early"), "the " .. scopeKey .. " footer counts")
    end
    Check(IsTextShown("^67%%$"), "salmon is 67% of the catch")
    Check(IsTextShown("Fishing 142/150"), "skill shown")
    Check(IsTextShown("Lure 8:12"), "lure time shown")
    Check(IsTextShown("Right%-click anywhere to loot"), "hook hint shown")
    Check(ns.Catches.GetSortedItems(ns.Catches.GetTally("session"))[1].itemID == SUNFISH, "most caught first")
end)

Step("drag a different weapon onto the main hand slot", function()
    cursorItemID = AXE
    BobberGearSlotMainHand.scripts.OnReceiveDrag(BobberGearSlotMainHand)
    Check(cursorItemID == nil, "item taken from the cursor")
    Check(BobberCharDB.gear.chosen.mainHand == AXE, "axe chosen for the main hand")
    Check(BobberGearSlotMainHand.attributes.macrotext1:find("item:" .. AXE) ~= nil, "weapon macro uses the axe")
    cursorItemID = POLE
    BobberGearSlotMainHand.scripts.OnReceiveDrag(BobberGearSlotMainHand)
    Check(BobberCharDB.gear.chosen.mainHand == AXE, "a pole can't go in the main hand slot")
end)

Step("combat puts the weapons back", function()
    StartChannel()
    AdvanceTime(0.2)
    FireEvent("PLAYER_REGEN_DISABLED")
    inCombat = true
    Check(equippedItems[16] == AXE and equippedItems[17] == SHIELD, "axe and shield equipped")
    Check(ActiveOverride("BUTTON2") == nil and ActiveOverride("F") == nil, "overrides cleared before combat")
    AdvanceTime(1)
    channelSpellID = nil
    inCombat = false
    FireEvent("PLAYER_REGEN_ENABLED")
    AdvanceTime(1)
    Check(cvars.Sound_SFXVolume == "0.5" and cvars.Sound_MusicVolume == "0.4", "your sound settings came back")
    Check(cvars.SoftTargetInteractRange == "10", "reach restored after combat")
    Check(BobberWindow:IsShown() == false, "window closed after the pole came off")
end)

Step("right-click forgets the chosen weapon", function()
    Click(BobberGearSlotMainHand, "RightButton")
    Check(BobberCharDB.gear.chosen.mainHand == nil, "choice forgotten")
end)

Step("double right-click hook mode", function()
    BobberDB.settings.rightClickHookMode = ns.HOOK_DOUBLE_CLICK
    registeredSettings.rightClickHookMode.onChange()
    Click(BobberGearSlotPole)
    AdvanceTime(1)
    StartChannel()
    AdvanceTime(0.2)
    Check(ActiveOverride("BUTTON2") == nil, "single right-click doesn't hook in double mode")
    RightClickWorld()
    AdvanceTime(0.2)
    mouseButtonsDown.RightButton = true
    FireEvent("GLOBAL_MOUSE_DOWN", "RightButton")
    Check(ActiveOverride("BUTTON2") == "INTERACTTARGET", "double right-click hooks")
    mouseButtonsDown.RightButton = false
    FireEvent("GLOBAL_MOUSE_UP", "RightButton")
    AdvanceTime(0.3)
    Check(ActiveOverride("BUTTON2") == nil, "double-click hook override removed after release")
    StopChannel()
end)

Step("cast key equips the pole when it's off", function()
    EquipItem(SWORD, 16)
    AdvanceTime(1)
    Check(not ns.IsPoleEquipped(), "pole is off")
    local castsBefore = #castSpells
    Click(BobberCastButton)
    AdvanceTime(1)
    Check(ns.IsPoleEquipped(), "cast key equipped the pole")
    Check(#castSpells == castsBefore, "that press didn't cast")
    Click(BobberCastButton)
    Check(#castSpells == castsBefore + 1, "the next press casts")
end)

Step("slash commands", function()
    SlashCmdList.BOBBER("lock")
    Check(BobberDB.settings.windowLocked == true, "/bobber lock")
    SlashCmdList.BOBBER("unlock")
    Check(BobberDB.settings.windowLocked == false, "/bobber unlock")
    SlashCmdList.BOBBER("help")
    SlashCmdList.BOBBER("newsession")
    Check(ns.Catches.GetTally("session").casts == 0, "/bobber newsession")
end)

Step("logout restores every setting", function()
    Check(cvars.Sound_SFXVolume == "1", "sounds enhanced again with the pole")
    FireEvent("PLAYER_LOGOUT")
    local allRestored = true
    for name, value in pairs(ORIGINAL_CVARS) do
        if cvars[name] ~= value then
            allRestored = false
            print("     " .. name .. " is " .. tostring(cvars[name]) .. ", expected " .. value)
        end
    end
    Check(allRestored, "all CVars back to the originals")
    Check(next(BobberDB.cvarBackup) == nil, "no leases left")
end)

Step("no stray globals", function()
    local allowedGlobals = {
        BobberDB = true, BobberCharDB = true, SLASH_BOBBER1 = true,
        Bobber_ToggleWindow = true, Bobber_OnAddonCompartmentClick = true,
        BINDING_HEADER_BOBBER = true, BINDING_NAME_BOBBER_TOGGLE_WINDOW = true,
    }
    local strayGlobals = {}
    for key in pairs(_G) do
        local isBobberFrame = type(key) == "string" and key:match("^Bobber%u")
        local isBindingLabel = type(key) == "string" and key:match("^BINDING_NAME_CLICK Bobber")
        if not globalsBeforeLoad[key] and not allowedGlobals[key] and not isBobberFrame and not isBindingLabel then
            strayGlobals[#strayGlobals + 1] = tostring(key)
        end
    end
    Check(#strayGlobals == 0, "no unexpected globals" .. (#strayGlobals > 0 and (": " .. table.concat(strayGlobals, ", ")) or ""))
end)

print(string.format("%d checks, %d failed", checkCount, failureCount))
if failureCount > 0 then
    os.exit(1)
end
