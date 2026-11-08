--[[
The options panel: Options > AddOns > Bobber.

Built with the game's Settings API. Each option is registered against a key
in BobberDB.settings (ns.settings), so the panel reads and writes the same
values the rest of Bobber uses. Defaults come from ns.DEFAULT_SETTINGS in
Core.lua. When an option changes, Bobber fires BOBBER_SETTINGS_CHANGED with
the option's key, and the file that owns the behavior updates itself.
]]

local _, ns = ...

local Options = {}
ns.Options = Options

local settingsCategory

-- Each entry is one control in the panel, in display order. `kind` is
-- "section" (a heading), "checkbox", "dropdown", or "slider".
local OPTION_LIST = {
    { kind = "section", label = "Casting" },
    {
        kind = "checkbox",
        key = "doubleClickCast",
        label = "Double right-click to cast",
        tooltip = "Double right-click the water to cast Fishing. This only works while a fishing pole is equipped, so double right-clicks do nothing unusual at other times.",
    },
    {
        kind = "slider",
        key = "doubleClickSeconds",
        label = "Double-click speed",
        tooltip = "The longest time between the two clicks of a double-click.",
        minimum = 0.2,
        maximum = 0.8,
        step = 0.05,
        formatValue = function(value)
            return string.format("%.2f s", value)
        end,
    },
    {
        kind = "dropdown",
        key = "rightClickHookMode",
        label = "Right-click to loot",
        tooltip = "How the right mouse button hooks the bobber while the line is out. With a single right-click, holding the right button to turn the camera also hooks, so turn with the left button while fishing.",
        choices = {
            { value = ns.HOOK_SINGLE_CLICK, label = "Single right-click anywhere" },
            { value = ns.HOOK_DOUBLE_CLICK, label = "Double right-click anywhere" },
            { value = ns.HOOK_OFF, label = "Off (click the bobber)" },
        },
    },
    {
        kind = "checkbox",
        key = "castKeyHooks",
        label = "Cast key also hooks",
        tooltip = "While the line is out, the Cast Fishing key binding hooks the bobber. Set the key under Options > Keybindings > AddOns > Bobber.",
    },
    {
        kind = "checkbox",
        key = "castKeyEquipsPole",
        label = "Cast key equips your pole",
        tooltip = "Pressing the Cast Fishing key without a pole equipped equips your pole. The next press casts.",
    },
    {
        kind = "checkbox",
        key = "applyLures",
        label = "Put on a lure when you cast",
        tooltip = "When your pole has no lure, your next cast press (double right-click or the cast key) puts on the best lure you have instead, and the press after that casts. That includes the Wide-Brimmed Fishing Hat while you wear it. Lures take 5 seconds to put on, and presses during that time wait. If you have no lure you can use, Bobber just casts.",
    },
    {
        kind = "checkbox",
        key = "extendBobberReach",
        label = "Always reach the bobber",
        tooltip = "Widens soft targeting while the line is out, so right-click finds the bobber wherever it lands.",
    },
    {
        kind = "checkbox",
        key = "showBobberIcon",
        label = "Show an icon over the bobber",
        tooltip = "Shows the game's interact icon over your bobber while the line is out.",
    },

    { kind = "section", label = "Loot and sound" },
    {
        kind = "checkbox",
        key = "autoLootFish",
        label = "Auto-loot fish",
        tooltip = "Takes everything from fishing loot windows. Other loot windows are left alone.",
    },
    {
        kind = "checkbox",
        key = "enhanceSounds",
        label = "Enhance fishing sounds",
        tooltip = "While a fishing pole is equipped: sound effects at full volume, and music and ambient sound off. Your settings come back when the pole comes off.",
    },
    {
        kind = "checkbox",
        key = "backgroundSound",
        label = "Sound in the background",
        tooltip = "Keeps game sound playing when WoW isn't the active window, so you hear the splash while you're in another app. This is on all the time, not just while fishing. Turn it off to get your own setting back.",
    },

    { kind = "section", label = "Gear" },
    {
        kind = "checkbox",
        key = "weaponsOnCombat",
        label = "Weapons back when combat starts",
        tooltip = "If combat starts while your pole is equipped, Bobber puts your weapons back.",
    },

    { kind = "section", label = "Window" },
    {
        kind = "checkbox",
        key = "showWindowWithPole",
        label = "Open the window when you equip a pole",
    },
    {
        kind = "checkbox",
        key = "hideWindowWithoutPole",
        label = "Close the window when you take the pole off",
    },
    {
        kind = "checkbox",
        key = "windowLocked",
        label = "Lock the window",
        tooltip = "A locked window can't be dragged. You can also lock it with the header button or /bobber lock.",
    },
    {
        kind = "dropdown",
        key = "windowTheme",
        label = "Theme",
        tooltip = "Colors for the Bobber window.",
        choices = (function()
            local themeChoices = {}
            for _, theme in ipairs(ns.THEMES) do
                themeChoices[#themeChoices + 1] = { value = theme.key, label = theme.label }
            end
            return themeChoices
        end)(),
    },
    {
        kind = "slider",
        key = "windowOpacity",
        label = "Window opacity",
        tooltip = "How solid the window's background is. Text and icons always stay fully visible. You can also hold Shift and turn the mouse wheel over the window.",
        minimum = 0,
        maximum = 1,
        step = 0.05,
        formatValue = function(value)
            return math.floor(value * 100 + 0.5) .. "%"
        end,
    },
}

local function NotifyChanged(settingKey)
    ns.Fire("BOBBER_SETTINGS_CHANGED", settingKey)
end

-- Register one option's value with the Settings API.
local function RegisterSetting(option)
    local defaultValue = ns.DEFAULT_SETTINGS[option.key]
    local setting = Settings.RegisterAddOnSetting(settingsCategory, "Bobber_" .. option.key, option.key,
        ns.settings, type(defaultValue), option.label, defaultValue)
    setting:SetValueChangedCallback(function()
        NotifyChanged(option.key)
    end)
    return setting
end

local function AddCheckbox(option)
    Settings.CreateCheckbox(settingsCategory, RegisterSetting(option), option.tooltip)
end

local function AddDropdown(option)
    local setting = RegisterSetting(option)
    local function GetDropdownChoices()
        local container = Settings.CreateControlTextContainer()
        for _, choice in ipairs(option.choices) do
            container:Add(choice.value, choice.label)
        end
        return container:GetData()
    end
    Settings.CreateDropdown(settingsCategory, setting, GetDropdownChoices, option.tooltip)
end

local function AddSlider(option)
    local setting = RegisterSetting(option)
    local sliderOptions = Settings.CreateSliderOptions(option.minimum, option.maximum, option.step)
    if MinimalSliderWithSteppersMixin and sliderOptions.SetLabelFormatter then
        sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, option.formatValue)
    end
    Settings.CreateSlider(settingsCategory, setting, sliderOptions, option.tooltip)
end

local function BuildOptionsPanel()
    if not (Settings and Settings.RegisterVerticalLayoutCategory) then
        ns.Debug("this client has no Settings API; the options panel is unavailable")
        return
    end
    local layout
    settingsCategory, layout = Settings.RegisterVerticalLayoutCategory("Bobber")
    for _, option in ipairs(OPTION_LIST) do
        if option.kind == "section" then
            if CreateSettingsListSectionHeaderInitializer then
                layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(option.label))
            end
        elseif option.kind == "checkbox" then
            AddCheckbox(option)
        elseif option.kind == "dropdown" and Settings.CreateDropdown then
            AddDropdown(option)
        elseif option.kind == "slider" and Settings.CreateSlider then
            AddSlider(option)
        end
    end
    Settings.RegisterAddOnCategory(settingsCategory)
end

-- Opens Options > AddOns > Bobber. Used by the window's gear button,
-- /bobber options, and right-clicking Bobber in the addons button by the
-- minimap. The options panel can't open during combat.
function Options.Open()
    if not settingsCategory then
        return
    end
    if InCombatLockdown() then
        ns.Print("the options can't open during combat.")
        return
    end
    Settings.OpenToCategory(settingsCategory:GetID())
end

ns.On("BOBBER_DATA_READY", BuildOptionsPanel)
