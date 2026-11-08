--[[
The Bobber window.

One movable window holds everything you look at while fishing:

  +--------------------------------------------------+
  | [icon] Bobber  Elwynn Forest   [gear][lock][-][x] |  header
  | Fishing 142/150 +25 (+3)               Lure 8:12  |  skill and lure
  | [pole][main][off]  Double right-click to cast     |  gear slots and
  |                    Right-click anywhere to loot   |  what clicks do
  |   Session   |    Zone    |   All time             |  scope tabs
  | [i] Raw Brilliant Smallfish          12      60%  |  catch list
  | [i] Sickly Looking Fish               6      30%  |
  | ...                                               |
  | 20 casts  18 caught  2 got away  54/hr  12:30     |  footer
  +--------------------------------------------------+

Controls:

* Drag anywhere on the window to move it (unless it's locked).
* Ctrl + mouse wheel scales the window, Shift + mouse wheel changes its
  background opacity, and the mouse wheel alone scrolls the catch list.
* The header buttons open Bobber's options (the gear), lock the window,
  collapse it to the header, skill line, and footer, and close it.
* The opacity option (and Shift + mouse wheel) fades only the background,
  header, and border. Text and icons stay fully visible, so at 0% the
  window is just its contents floating over the game.
* The window opens when you equip a fishing pole and closes when you take
  it off (both can be turned off in the options).

Combat note: the gear slots are secure buttons (see Gear.lua), and the game
doesn't let addons show, hide, move, or scale a window holding secure
buttons during combat. Those actions wait for combat to end, or are
refused with a message when you ask for them during combat.
]]

local _, ns = ...

local Window = {}
ns.Window = Window

-------------------------------------------------------------------------------
-- Layout
-------------------------------------------------------------------------------

local WINDOW_WIDTH = 276
local EDGE_PADDING = 8
local HEADER_HEIGHT = 24
local INFO_LINE_HEIGHT = 18
local GEAR_SLOT_SIZE = 34
local GEAR_SLOT_SPACING = 4
local GEAR_ROW_HEIGHT = GEAR_SLOT_SIZE + 8
local TAB_ROW_HEIGHT = 22
local LIST_ROW_HEIGHT = 18
local VISIBLE_LIST_ROWS = 8
local FOOTER_HEIGHT = 20

-- Distances from the top of the window to the top of each section.
local INFO_LINE_TOP = HEADER_HEIGHT + 4
local GEAR_ROW_TOP = INFO_LINE_TOP + INFO_LINE_HEIGHT + 2
local TAB_ROW_TOP = GEAR_ROW_TOP + GEAR_ROW_HEIGHT
local LIST_TOP = TAB_ROW_TOP + TAB_ROW_HEIGHT
local LIST_HEIGHT = LIST_ROW_HEIGHT * VISIBLE_LIST_ROWS

local EXPANDED_HEIGHT = LIST_TOP + LIST_HEIGHT + 4 + FOOTER_HEIGHT
local COLLAPSED_HEIGHT = INFO_LINE_TOP + INFO_LINE_HEIGHT + 2 + FOOTER_HEIGHT

local MIN_SCALE = 0.6
local MAX_SCALE = 2.0
local SCALE_STEP = 0.05
local OPACITY_STEP = 0.05

local REFRESH_INTERVAL_SECONDS = 1

local LOCKED_ICON = "Interface\\Buttons\\LockButton-Locked-Up"
local UNLOCKED_ICON = "Interface\\Buttons\\LockButton-Unlocked-Up"
-- The gray gear is the world map's filter button art. If this client
-- doesn't have it, the gear item icon (in the game since launch) stands in.
local SETTINGS_ICONS = {
    "Interface\\WorldMap\\Gear_64Grey",
    "Interface\\Icons\\INV_Misc_Gear_01",
}
local FISHING_ICON = "Interface\\Icons\\Trade_Fishing"
local UNKNOWN_ITEM_ICON = 134400  -- the question mark icon

local SCOPES = {
    { key = "session", label = "Session" },
    { key = "zone", label = "Zone" },
    { key = "lifetime", label = "All time" },
}

local window        -- the main frame, built at BOBBER_DATA_READY
local ui = {}       -- named child widgets
local listRows = {}
local tabButtons = {}
local listScrollOffset = 0
local secondsSinceRefresh = 0
local wasPoleEquipped = nil  -- for opening and closing on pole changes only

local function CurrentTheme()
    return ns.GetTheme(ns.settings.windowTheme)
end

local function SetTextColor(fontString, color)
    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

-- "|cffRRGGBB" for embedding a theme color in text.
local function ColorCode(color)
    return string.format("|cff%02x%02x%02x",
        math.floor(color[1] * 255), math.floor(color[2] * 255), math.floor(color[3] * 255))
end

local function GetItemQualityRGB(quality, theme)
    -- Common (1) and poor (0) items are white and gray, which vanish on a
    -- light theme, so those use the theme's text color there.
    if theme.isLight and quality <= 1 then
        return theme.text[1], theme.text[2], theme.text[3]
    end
    if C_Item and C_Item.GetItemQualityColor then
        local red, green, blue = C_Item.GetItemQualityColor(quality)
        if red then
            return red, green, blue
        end
    end
    local qualityColor = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if qualityColor then
        return qualityColor.r, qualityColor.g, qualityColor.b
    end
    return theme.text[1], theme.text[2], theme.text[3]
end

local function FormatDuration(totalSeconds)
    totalSeconds = math.floor(totalSeconds)
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = totalSeconds % 60
    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, seconds)
    end
    return string.format("%d:%02d", minutes, seconds)
end

-------------------------------------------------------------------------------
-- Moving, scaling, locking
-------------------------------------------------------------------------------

local function SaveWindowPosition()
    local point, _, relativePoint, x, y = window:GetPoint(1)
    local saved = ns.db.window
    saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
end

local function RestoreWindowPosition()
    local saved = ns.db.window
    window:ClearAllPoints()
    window:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    window:SetScale(saved.scale)
end

function Window.StartDragging()
    if ns.settings.windowLocked or InCombatLockdown() then
        return
    end
    window:StartMoving()
end

function Window.StopDragging()
    window:StopMovingOrSizing()
    SaveWindowPosition()
end

-- Let a child widget that catches the mouse still drag the whole window.
local function ForwardDragToWindow(childFrame)
    childFrame:RegisterForDrag("LeftButton")
    childFrame:SetScript("OnDragStart", Window.StartDragging)
    childFrame:SetScript("OnDragStop", Window.StopDragging)
end

local function UpdateLockButton()
    ui.lockButton.icon:SetTexture(ns.settings.windowLocked and LOCKED_ICON or UNLOCKED_ICON)
end

function Window.SetLocked(isLocked)
    ns.settings.windowLocked = isLocked
    UpdateLockButton()
    ns.Print(isLocked and "window locked." or "window unlocked; drag it anywhere to move it.")
end

function Window.ResetPosition()
    if InCombatLockdown() then
        ns.Print("the window can't move during combat.")
        return
    end
    local saved = ns.db.window
    saved.point, saved.relativePoint, saved.x, saved.y, saved.scale = "CENTER", "CENTER", 320, 0, 1
    RestoreWindowPosition()
end

local function ChangeScaleBy(scaleChange)
    if InCombatLockdown() then
        return
    end
    local saved = ns.db.window
    saved.scale = math.max(MIN_SCALE, math.min(MAX_SCALE, saved.scale + scaleChange))
    window:SetScale(saved.scale)
end

-- Opacity is a setting, so the options panel shows the new value too.
local function ChangeOpacityBy(opacityChange)
    local newOpacity = ns.settings.windowOpacity + opacityChange
    ns.settings.windowOpacity = math.max(0, math.min(1, newOpacity))
    Window.ApplyTheme()
end

local function OnMouseWheel(_, wheelDirection)
    if IsControlKeyDown() then
        ChangeScaleBy(wheelDirection * SCALE_STEP)
        return
    end
    if IsShiftKeyDown() then
        ChangeOpacityBy(wheelDirection * OPACITY_STEP)
        return
    end
    -- Wheel up (1) scrolls toward the top of the list.
    listScrollOffset = math.max(0, listScrollOffset - wheelDirection)
    Window.Refresh()
end

-------------------------------------------------------------------------------
-- Collapsing
-------------------------------------------------------------------------------

local function ApplyCollapsedState()
    local isCollapsed = ns.db.window.collapsed
    ui.body:SetShown(not isCollapsed)
    window:SetHeight(isCollapsed and COLLAPSED_HEIGHT or EXPANDED_HEIGHT)
    ui.collapseButton.label:SetText(isCollapsed and "+" or "-")
end

local function ToggleCollapsed()
    if InCombatLockdown() then
        ns.Print("the window can't change size during combat.")
        return
    end
    ns.db.window.collapsed = not ns.db.window.collapsed
    ApplyCollapsedState()
    Window.Refresh()
end

-------------------------------------------------------------------------------
-- Building the window
-------------------------------------------------------------------------------

local function ShowTextTooltip(owner, text)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(text)
    GameTooltip:Show()
end

local function HideTooltip()
    GameTooltip:Hide()
end

-- Texture:SetTexture() returns false when the file doesn't exist on this
-- client, so try each path in turn until one loads.
local function SetFirstAvailableTexture(texture, texturePaths)
    for _, texturePath in ipairs(texturePaths) do
        if texture:SetTexture(texturePath) then
            return
        end
    end
    texture:SetTexture(texturePaths[#texturePaths])
end

-- A small header button. `getTooltipText` returns the tooltip, so it can
-- change with the button's state. `globalName` is optional.
local function CreateHeaderButton(getTooltipText, onClick, globalName)
    local button = CreateFrame("Button", globalName, window)
    button:SetSize(16, 16)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self)
        ShowTextTooltip(self, getTooltipText())
    end)
    button:SetScript("OnLeave", HideTooltip)
    return button
end

local function AddButtonLabel(button, labelText)
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.label:SetPoint("CENTER", 0, 1)
    button.label:SetText(labelText)
end

local function BuildHeader()
    ui.headerBackground = window:CreateTexture(nil, "BACKGROUND", nil, 1)
    ui.headerBackground:SetPoint("TOPLEFT", 1, -1)
    ui.headerBackground:SetPoint("TOPRIGHT", -1, -1)
    ui.headerBackground:SetHeight(HEADER_HEIGHT - 1)

    ui.titleIcon = window:CreateTexture(nil, "ARTWORK")
    ui.titleIcon:SetSize(16, 16)
    ui.titleIcon:SetPoint("TOPLEFT", 6, -4)
    ui.titleIcon:SetTexture(FISHING_ICON)
    ui.titleIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    ui.titleText = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.titleText:SetPoint("LEFT", ui.titleIcon, "RIGHT", 5, 0)
    ui.titleText:SetText("Bobber")

    ui.closeButton = CreateHeaderButton(function() return "Close" end, function()
        Window.Toggle()
    end)
    ui.closeButton:SetPoint("TOPRIGHT", -4, -4)
    AddButtonLabel(ui.closeButton, "x")

    ui.collapseButton = CreateHeaderButton(function()
        return ns.db.window.collapsed and "Expand" or "Collapse"
    end, ToggleCollapsed)
    ui.collapseButton:SetPoint("RIGHT", ui.closeButton, "LEFT", -2, 0)
    AddButtonLabel(ui.collapseButton, "-")

    ui.lockButton = CreateHeaderButton(function()
        return ns.settings.windowLocked and "Unlock the window" or "Lock the window in place"
    end, function()
        Window.SetLocked(not ns.settings.windowLocked)
    end)
    ui.lockButton:SetPoint("RIGHT", ui.collapseButton, "LEFT", -2, 0)
    ui.lockButton.icon = ui.lockButton:CreateTexture(nil, "ARTWORK")
    ui.lockButton.icon:SetAllPoints()

    ui.settingsButton = CreateHeaderButton(function() return "Bobber options" end, function()
        ns.Options.Open()
    end, "BobberWindowSettingsButton")
    ui.settingsButton:SetPoint("RIGHT", ui.lockButton, "LEFT", -2, 0)
    ui.settingsButton.icon = ui.settingsButton:CreateTexture(nil, "ARTWORK")
    ui.settingsButton.icon:SetPoint("TOPLEFT", 1, -1)
    ui.settingsButton.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    SetFirstAvailableTexture(ui.settingsButton.icon, SETTINGS_ICONS)
    ui.settingsButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    ui.zoneText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.zoneText:SetPoint("LEFT", ui.titleText, "RIGHT", 6, 0)
    ui.zoneText:SetPoint("RIGHT", ui.settingsButton, "LEFT", -4, 0)
    ui.zoneText:SetJustifyH("LEFT")
    ui.zoneText:SetWordWrap(false)
end

local function BuildInfoLine()
    ui.skillText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.skillText:SetPoint("TOPLEFT", EDGE_PADDING, -INFO_LINE_TOP)
    ui.skillText:SetJustifyH("LEFT")

    ui.lureText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.lureText:SetPoint("TOPRIGHT", -EDGE_PADDING, -INFO_LINE_TOP)
    ui.lureText:SetJustifyH("RIGHT")
end

local function BuildGearRow()
    for slotIndex, slotKey in ipairs(ns.Gear.SLOT_KEYS) do
        local slotButton = ns.Gear.CreateSlotButton(slotKey, ui.body, GEAR_SLOT_SIZE)
        local slotLeft = EDGE_PADDING + (slotIndex - 1) * (GEAR_SLOT_SIZE + GEAR_SLOT_SPACING)
        slotButton:SetPoint("TOPLEFT", window, "TOPLEFT", slotLeft, -GEAR_ROW_TOP)
    end

    local hintsLeft = EDGE_PADDING + #ns.Gear.SLOT_KEYS * (GEAR_SLOT_SIZE + GEAR_SLOT_SPACING) + 4
    local hintsWidth = WINDOW_WIDTH - hintsLeft - EDGE_PADDING

    ui.castHintText = ui.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.castHintText:SetPoint("TOPLEFT", window, "TOPLEFT", hintsLeft, -(GEAR_ROW_TOP + 3))
    ui.castHintText:SetWidth(hintsWidth)
    ui.castHintText:SetJustifyH("LEFT")

    ui.hookHintText = ui.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.hookHintText:SetPoint("TOPLEFT", ui.castHintText, "BOTTOMLEFT", 0, -3)
    ui.hookHintText:SetWidth(hintsWidth)
    ui.hookHintText:SetJustifyH("LEFT")
end

function Window.SetScope(scopeKey)
    ns.db.window.scope = scopeKey
    listScrollOffset = 0
    Window.Refresh()
end

local function BuildTabs()
    local tabWidth = (WINDOW_WIDTH - 2 * EDGE_PADDING) / #SCOPES
    for tabIndex, scope in ipairs(SCOPES) do
        local tabButton = CreateFrame("Button", nil, ui.body)
        tabButton.scopeKey = scope.key
        tabButton:SetSize(tabWidth, TAB_ROW_HEIGHT - 4)
        tabButton:SetPoint("TOPLEFT", window, "TOPLEFT", EDGE_PADDING + (tabIndex - 1) * tabWidth, -TAB_ROW_TOP)

        tabButton.label = tabButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tabButton.label:SetPoint("CENTER")
        tabButton.label:SetText(scope.label)

        tabButton.underline = tabButton:CreateTexture(nil, "ARTWORK")
        tabButton.underline:SetPoint("BOTTOMLEFT", 6, 0)
        tabButton.underline:SetPoint("BOTTOMRIGHT", -6, 0)
        tabButton.underline:SetHeight(2)

        tabButton:SetScript("OnClick", function(self)
            Window.SetScope(self.scopeKey)
        end)
        ForwardDragToWindow(tabButton)
        tabButtons[tabIndex] = tabButton
    end
end

local function ShowListRowTooltip(row)
    if not row.itemID then
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(row.itemID)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(string.format("Caught %d (%d%% of this list)",
        row.caughtCount, math.floor(row.share * 100 + 0.5)), 1, 1, 1)
    GameTooltip:Show()
end

local function BuildListRows()
    local rowWidth = WINDOW_WIDTH - 2 * EDGE_PADDING
    for rowIndex = 1, VISIBLE_LIST_ROWS do
        local row = CreateFrame("Button", nil, ui.body)
        row:SetSize(rowWidth, LIST_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", window, "TOPLEFT", EDGE_PADDING, -(LIST_TOP + (rowIndex - 1) * LIST_ROW_HEIGHT))

        -- A bar behind the row whose width shows the item's share.
        row.shareBar = row:CreateTexture(nil, "BACKGROUND")
        row.shareBar:SetPoint("TOPLEFT", 0, -1)
        row.shareBar:SetPoint("BOTTOMLEFT", 0, 1)
        row.shareBar:SetWidth(1)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(LIST_ROW_HEIGHT - 4, LIST_ROW_HEIGHT - 4)
        row.icon:SetPoint("LEFT", 2, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        row.shareText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.shareText:SetPoint("RIGHT", -2, 0)
        row.shareText:SetWidth(36)
        row.shareText:SetJustifyH("RIGHT")

        row.countText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.countText:SetPoint("RIGHT", row.shareText, "LEFT", -4, 0)
        row.countText:SetWidth(36)
        row.countText:SetJustifyH("RIGHT")

        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.nameText:SetPoint("RIGHT", row.countText, "LEFT", -4, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)

        row.itemID = nil
        row.caughtCount = 0
        row.share = 0
        row:SetScript("OnEnter", ShowListRowTooltip)
        row:SetScript("OnLeave", HideTooltip)
        ForwardDragToWindow(row)
        listRows[rowIndex] = row
    end

    ui.emptyListText = ui.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.emptyListText:SetPoint("TOP", window, "TOP", 0, -(LIST_TOP + LIST_HEIGHT / 2 - 8))
    ui.emptyListText:SetWidth(WINDOW_WIDTH - 4 * EDGE_PADDING)
end

local function BuildFooter()
    ui.footerText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.footerText:SetPoint("BOTTOMLEFT", EDGE_PADDING, 6)
    ui.footerText:SetPoint("BOTTOMRIGHT", -EDGE_PADDING, 6)
    ui.footerText:SetJustifyH("LEFT")
    ui.footerText:SetWordWrap(false)
end

local function BuildWindow()
    window = CreateFrame("Frame", "BobberWindow", UIParent, "BackdropTemplate")
    window:SetSize(WINDOW_WIDTH, EXPANDED_HEIGHT)
    window:SetFrameStrata("MEDIUM")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", Window.StartDragging)
    window:SetScript("OnDragStop", Window.StopDragging)
    window:EnableMouseWheel(true)
    window:SetScript("OnMouseWheel", OnMouseWheel)
    window:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    window:Hide()

    -- Everything that collapsing hides lives in `body`.
    ui.body = CreateFrame("Frame", nil, window)
    ui.body:SetAllPoints()

    BuildHeader()
    BuildInfoLine()
    BuildGearRow()
    BuildTabs()
    BuildListRows()
    BuildFooter()

    window:SetScript("OnShow", function()
        secondsSinceRefresh = 0
        Window.Refresh()
    end)
    -- Refresh once a second while shown, for the lure timer and fishing time.
    window:SetScript("OnUpdate", function(_, elapsedSeconds)
        secondsSinceRefresh = secondsSinceRefresh + elapsedSeconds
        if secondsSinceRefresh >= REFRESH_INTERVAL_SECONDS then
            secondsSinceRefresh = 0
            Window.Refresh()
        end
    end)

    RestoreWindowPosition()
    ApplyCollapsedState()
    UpdateLockButton()
end

-------------------------------------------------------------------------------
-- Theme
-------------------------------------------------------------------------------

-- Colors come from the theme; how see-through the background, header, and
-- border are comes from the opacity setting. The header and border stay a
-- little stronger than the body so the window's edges remain visible.
function Window.ApplyTheme()
    local theme = CurrentTheme()
    local opacity = ns.settings.windowOpacity
    local edgeOpacity = math.min(1, opacity * 1.1)
    local background, header, border = theme.background, theme.header, theme.border
    window:SetBackdropColor(background[1], background[2], background[3], opacity)
    window:SetBackdropBorderColor(border[1], border[2], border[3], edgeOpacity)
    ui.headerBackground:SetColorTexture(header[1], header[2], header[3], edgeOpacity)
    SetTextColor(ui.titleText, theme.accent)
    SetTextColor(ui.zoneText, theme.muted)
    SetTextColor(ui.skillText, theme.text)
    SetTextColor(ui.footerText, theme.muted)
    SetTextColor(ui.emptyListText, theme.muted)
    SetTextColor(ui.closeButton.label, theme.muted)
    SetTextColor(ui.collapseButton.label, theme.muted)
    for _, row in ipairs(listRows) do
        SetTextColor(row.countText, theme.text)
        SetTextColor(row.shareText, theme.muted)
    end
    Window.Refresh()
end

-------------------------------------------------------------------------------
-- Refreshing
-------------------------------------------------------------------------------

-- Seconds left on the pole's lure: nil without a pole, 0 with no lure.
local function GetLureSecondsLeft()
    if not ns.IsPoleEquipped() then
        return nil
    end
    local hasMainHandEnchant, mainHandExpirationMilliseconds = GetWeaponEnchantInfo()
    if ns.IsSecret(hasMainHandEnchant) or ns.IsSecret(mainHandExpirationMilliseconds) then
        return nil
    end
    if hasMainHandEnchant and mainHandExpirationMilliseconds then
        return mainHandExpirationMilliseconds / 1000
    end
    return 0
end

local function RefreshSkillAndLure(theme)
    local skill, maxSkill, bonus = ns.Catches.GetFishingSkill()
    if skill then
        local skillLine = string.format("Fishing %d/%d", skill, maxSkill)
        if bonus and bonus > 0 then
            skillLine = skillLine .. " " .. ColorCode(theme.accent) .. "+" .. bonus .. "|r"
        end
        local sessionGain = ns.Catches.GetSessionSkillGain()
        if sessionGain > 0 then
            skillLine = skillLine .. " " .. ColorCode(theme.muted) .. "(+" .. sessionGain .. " today)|r"
        end
        ui.skillText:SetText(skillLine)
    else
        ui.skillText:SetText(ColorCode(theme.muted) .. "Fishing not learned|r")
    end

    local lureSecondsLeft = GetLureSecondsLeft()
    if ns.Lures.IsLureGoingOn() then
        ui.lureText:SetText("Lure going on")
        SetTextColor(ui.lureText, theme.accent)
    elseif lureSecondsLeft == nil then
        ui.lureText:SetText("")
    elseif lureSecondsLeft > 0 then
        ui.lureText:SetText("Lure " .. FormatDuration(lureSecondsLeft))
        SetTextColor(ui.lureText, theme.accent)
    else
        ui.lureText:SetText("No lure")
        SetTextColor(ui.lureText, theme.muted)
    end
end

-- Hints stay at 28 characters or fewer, so each fits on one line beside
-- the gear slots.
local CAST_HINTS = {
    ready = "Double right-click to cast",
    needs_pole = "Equip a pole to cast",
    off = "Double-click cast is off",
}

local HOOK_HINTS = {
    [ns.HOOK_SINGLE_CLICK] = "Right-click anywhere to loot",
    [ns.HOOK_DOUBLE_CLICK] = "Double right-click to loot",
    [ns.HOOK_OFF] = "Click the bobber to loot",
}

-- The first hint says what your next press does.
local function GetCastHint(doubleClickState)
    if ns.Casting.IsLineOut() then
        return "Line is out", true
    elseif ns.Lures.IsLureGoingOn() then
        return "Putting on a lure...", true
    elseif doubleClickState == "ready" and ns.Lures.GetLureForNextPress() then
        return "Next cast puts on a lure", true
    end
    return CAST_HINTS[doubleClickState], doubleClickState == "ready"
end

local function RefreshHints(theme)
    local castHint, isHighlighted = GetCastHint(ns.Casting.GetDoubleClickState())
    ui.castHintText:SetText(castHint)
    SetTextColor(ui.castHintText, isHighlighted and theme.accent or theme.muted)
    ui.hookHintText:SetText(HOOK_HINTS[ns.settings.rightClickHookMode] or HOOK_HINTS[ns.HOOK_OFF])
    SetTextColor(ui.hookHintText, ns.Casting.IsLineOut() and theme.accent or theme.text)
end

local function RefreshTabs(theme)
    for _, tabButton in ipairs(tabButtons) do
        local isSelected = tabButton.scopeKey == ns.db.window.scope
        SetTextColor(tabButton.label, isSelected and theme.accent or theme.muted)
        tabButton.underline:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3], isSelected and 1 or 0)
    end
end

local EMPTY_LIST_MESSAGES = {
    session = "No catches yet this session.",
    zone = "Nothing caught in this zone yet.",
    lifetime = "Nothing caught yet.",
}

local function RefreshList(theme)
    local scopeKey = ns.db.window.scope
    local entries = ns.Catches.GetSortedItems(ns.Catches.GetTally(scopeKey))
    local largestOffset = math.max(0, #entries - VISIBLE_LIST_ROWS)
    listScrollOffset = math.min(listScrollOffset, largestOffset)

    local rowWidth = WINDOW_WIDTH - 2 * EDGE_PADDING
    for rowIndex, row in ipairs(listRows) do
        local entry = entries[rowIndex + listScrollOffset]
        if entry then
            local red, green, blue = GetItemQualityRGB(entry.quality, theme)
            row.itemID = entry.itemID
            row.caughtCount = entry.count
            row.share = entry.share
            row.icon:SetTexture(entry.icon or UNKNOWN_ITEM_ICON)
            row.nameText:SetText(entry.name)
            row.nameText:SetTextColor(red, green, blue)
            row.countText:SetText(entry.count)
            row.shareText:SetText(math.floor(entry.share * 100 + 0.5) .. "%")
            row.shareBar:SetWidth(math.max(1, rowWidth * entry.share))
            row.shareBar:SetColorTexture(red, green, blue, 0.16)
            row:Show()
        else
            row.itemID = nil
            row:Hide()
        end
    end

    if #entries == 0 then
        ui.emptyListText:SetText(EMPTY_LIST_MESSAGES[scopeKey])
        ui.emptyListText:Show()
    else
        ui.emptyListText:Hide()
    end
end

local function RefreshFooter()
    local scopeKey = ns.db.window.scope
    local tally = ns.Catches.GetTally(scopeKey)
    local parts = {
        tally.casts .. " casts",
        tally.catches .. " caught",
    }
    if tally.escapes > 0 then
        parts[#parts + 1] = tally.escapes .. " got away"
    end
    if tally.earlyHooks > 0 then
        parts[#parts + 1] = tally.earlyHooks .. " too early"
    end
    if scopeKey == "session" then
        local catchesPerHour = ns.Catches.GetSessionCatchesPerHour()
        if catchesPerHour then
            parts[#parts + 1] = math.floor(catchesPerHour + 0.5) .. "/hr"
        end
        parts[#parts + 1] = FormatDuration(ns.Catches.GetSessionFishingSeconds())
    end
    ui.footerText:SetText(table.concat(parts, "  "))
end

function Window.Refresh()
    if not window or not window:IsShown() then
        return
    end
    local theme = CurrentTheme()
    ui.zoneText:SetText(ns.Catches.GetZoneName())
    RefreshSkillAndLure(theme)
    RefreshFooter()
    if not ns.db.window.collapsed then
        ns.Gear.UpdateSlotButtons(theme)
        RefreshHints(theme)
        RefreshTabs(theme)
        RefreshList(theme)
    end
end

-------------------------------------------------------------------------------
-- Showing and hiding
-------------------------------------------------------------------------------

function Window.Toggle()
    if InCombatLockdown() then
        ns.Print("the window can't open or close during combat.")
        return
    end
    window:SetShown(not window:IsShown())
end

-- Open the window when a pole goes on and close it when the pole comes off.
-- Only changes count, so a window you opened or closed yourself stays that
-- way until the next pole change.
function Window.UpdateForPoleChange()
    local isPoleEquipped = ns.IsPoleEquipped()
    if isPoleEquipped == wasPoleEquipped then
        return
    end
    if InCombatLockdown() then
        ns.RunOutOfCombat(Window.UpdateForPoleChange)
        return
    end
    wasPoleEquipped = isPoleEquipped
    if isPoleEquipped and ns.settings.showWindowWithPole then
        window:Show()
    elseif not isPoleEquipped and ns.settings.hideWindowWithoutPole then
        window:Hide()
    end
end

-- The key binding and the addon compartment (the addons button by the
-- minimap) call these globals.
function Bobber_ToggleWindow()
    Window.Toggle()
end

function Bobber_OnAddonCompartmentClick(_, mouseButton)
    if mouseButton == "RightButton" then
        ns.Options.Open()
    else
        Window.Toggle()
    end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

-- Gear.lua's BOBBER_DATA_READY listener runs before this one (files load in
-- TOC order), so the gear data exists when the slot buttons are built.
ns.On("BOBBER_DATA_READY", function()
    BuildWindow()
    Window.ApplyTheme()
end)

ns.On("PLAYER_LOGIN", Window.UpdateForPoleChange)
ns.On("BOBBER_GEAR_CHANGED", function()
    Window.UpdateForPoleChange()
    Window.Refresh()
end)

ns.On("BOBBER_STATS_CHANGED", Window.Refresh)
ns.On("BOBBER_LURE_CHANGED", Window.Refresh)
ns.On("BOBBER_CAST_START", Window.Refresh)
ns.On("BOBBER_CAST_STOP", Window.Refresh)

ns.On("BOBBER_SETTINGS_CHANGED", function(settingKey)
    if settingKey == "windowTheme" or settingKey == "windowOpacity" then
        Window.ApplyTheme()
    elseif settingKey == "windowLocked" then
        UpdateLockButton()
    else
        Window.Refresh()
    end
end)
