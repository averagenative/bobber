--[[
Fishing sounds.

Two separate options, each a CVarLease (see CVarLease.lua), so the changes
are undone even after a reload or disconnect:

* Enhanced fishing sounds ("sounds" lease): while a fishing pole is
  equipped, sound effects play at full volume and music and ambient sound
  are off, so the splash of a bite is easy to hear. Taking the pole off
  puts your own sound settings back.
* Sound in the background ("background" lease): game sound keeps playing
  when WoW isn't the active window, so you hear the splash while you're in
  another app. By default this is only while a fishing pole is equipped;
  the option can make it always, or off. When it doesn't apply, your own
  setting is back.
]]

local _, ns = ...

local Sounds = {}
ns.Sounds = Sounds

local FISHING_SOUND_CVARS = {
    Sound_EnableAllSound = 1,
    Sound_EnableSFX = 1,
    Sound_SFXVolume = 1,
    Sound_MusicVolume = 0,
    Sound_AmbienceVolume = 0,
}

local BACKGROUND_SOUND_CVARS = {
    Sound_EnableSoundWhenGameIsInBG = 1,
}

-- Hold the lease while `shouldHold` is true, release it otherwise. A lease
-- that's already held isn't taken again, so your own changes made while it's
-- held (say, a volume slider) aren't overwritten.
local function HoldLeaseWhile(shouldHold, leaseName, valuesByCVarName)
    local isHeld = ns.CVarLease.IsHeld(leaseName)
    if shouldHold and not isHeld then
        ns.CVarLease.Acquire(leaseName, valuesByCVarName)
    elseif not shouldHold and isHeld then
        ns.CVarLease.Release(leaseName)
    end
end

local function ShouldPlaySoundInBackground()
    local mode = ns.settings.backgroundSoundMode
    if mode == ns.BACKGROUND_SOUND_ALWAYS then
        return true
    end
    return mode == ns.BACKGROUND_SOUND_WITH_POLE and ns.IsPoleEquipped()
end

function Sounds.Update()
    HoldLeaseWhile(ns.settings.enhanceSounds and ns.IsPoleEquipped(), "sounds", FISHING_SOUND_CVARS)
    HoldLeaseWhile(ShouldPlaySoundInBackground(), "background", BACKGROUND_SOUND_CVARS)
end

ns.On("PLAYER_LOGIN", Sounds.Update)
ns.On("PLAYER_EQUIPMENT_CHANGED", Sounds.Update)
ns.On("BOBBER_SETTINGS_CHANGED", function(settingKey)
    if settingKey == "enhanceSounds" or settingKey == "backgroundSoundMode" then
        Sounds.Update()
    end
end)
