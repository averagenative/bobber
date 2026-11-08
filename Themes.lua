--[[
Window color themes.

Each theme is a set of colors as { red, green, blue, alpha } from 0 to 1:

  background  the window body
  header      the title bar
  border      the window edge and unequipped gear slots
  text        normal text
  muted       secondary text (labels, hints, inactive tabs)
  accent      highlights: the title, the active tab, equipped gear, ready hints

Themes with `isLight = true` have a pale background, so item names that are
normally white (common quality) or gray (poor quality) use the theme's text
color instead, to stay readable.
]]

local _, ns = ...

ns.THEMES = {
    {
        key = "harbor",
        label = "Harbor (dark teal)",
        background = { 0.05, 0.07, 0.09, 0.90 },
        header = { 0.08, 0.13, 0.16, 0.95 },
        border = { 0.20, 0.42, 0.50, 0.95 },
        text = { 0.88, 0.92, 0.95, 1 },
        muted = { 0.55, 0.63, 0.68, 1 },
        accent = { 0.31, 0.76, 0.97, 1 },
    },
    {
        key = "midnight",
        label = "Midnight (dark violet)",
        background = { 0.07, 0.06, 0.11, 0.90 },
        header = { 0.12, 0.10, 0.19, 0.95 },
        border = { 0.36, 0.30, 0.58, 0.95 },
        text = { 0.90, 0.88, 0.96, 1 },
        muted = { 0.60, 0.57, 0.70, 1 },
        accent = { 0.71, 0.58, 1.00, 1 },
    },
    {
        key = "ember",
        label = "Ember (dark amber)",
        background = { 0.08, 0.06, 0.03, 0.90 },
        header = { 0.14, 0.10, 0.04, 0.95 },
        border = { 0.55, 0.38, 0.12, 0.95 },
        text = { 1.00, 0.86, 0.62, 1 },
        muted = { 0.70, 0.57, 0.38, 1 },
        accent = { 1.00, 0.69, 0.20, 1 },
    },
    {
        key = "parchment",
        label = "Parchment (light)",
        isLight = true,
        background = { 0.93, 0.89, 0.80, 0.95 },
        header = { 0.84, 0.78, 0.65, 0.98 },
        border = { 0.50, 0.40, 0.25, 0.95 },
        text = { 0.20, 0.15, 0.08, 1 },
        muted = { 0.42, 0.35, 0.24, 1 },
        accent = { 0.10, 0.38, 0.55, 1 },
    },
}

local themesByKey = {}
for _, theme in ipairs(ns.THEMES) do
    themesByKey[theme.key] = theme
end

-- The theme for `themeKey`, falling back to the first (default) theme.
function ns.GetTheme(themeKey)
    return themesByKey[themeKey] or ns.THEMES[1]
end
