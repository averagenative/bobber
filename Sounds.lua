--[[
Enhanced fishing sounds.

While a fishing pole is equipped, Bobber turns sound effects all the way
up, turns music and ambient sound off, and keeps sound playing while the
game is in the background, so the splash of a bite is easy to hear. Taking
the pole off puts your own sound settings back.

The changes are a CVarLease named "sounds" (see CVarLease.lua), so they're
undone even after a reload or disconnect.
]]

local _, ns = ...

local Sounds = {}
ns.Sounds = Sounds

local SOUND_LEASE_NAME = "sounds"

local FISHING_SOUND_CVARS = {
    Sound_EnableAllSound = 1,
    Sound_EnableSFX = 1,
    Sound_SFXVolume = 1,
    Sound_MusicVolume = 0,
    Sound_AmbienceVolume = 0,
    Sound_EnableSoundWhenGameIsInBG = 1,
}

function Sounds.Update()
    local shouldEnhance = ns.settings.enhanceSounds and ns.IsPoleEquipped()
    local isEnhanced = ns.CVarLease.IsHeld(SOUND_LEASE_NAME)
    if shouldEnhance and not isEnhanced then
        ns.CVarLease.Acquire(SOUND_LEASE_NAME, FISHING_SOUND_CVARS)
    elseif not shouldEnhance and isEnhanced then
        ns.CVarLease.Release(SOUND_LEASE_NAME)
    end
end

ns.On("PLAYER_LOGIN", Sounds.Update)
ns.On("PLAYER_EQUIPMENT_CHANGED", Sounds.Update)
ns.On("BOBBER_SETTINGS_CHANGED", function(settingKey)
    if settingKey == "enhanceSounds" then
        Sounds.Update()
    end
end)
