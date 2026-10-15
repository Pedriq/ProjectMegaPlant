--[[
	Every sound the game plays, by slot name. Put a real sound id in `Id` to replace a slot; the code
	that plays it never changes. Ids can be "rbxassetid://123" or a built-in "rbxasset://sounds/...".

	Volume  base volume (0-1)
	Pitch   base playback speed; callers can multiply it (pitch ladders: coin combo, fill level, ...)
	Loop    looped slots are started/stopped with Audio:SetLoop instead of played once

	The defaults below are the few sounds that ship with Roblox, used as placeholders at different
	pitches. They are NOT good enough for a polished game: replace them with proper SFX (coin
	pickups, magical chimes, water pours, fanfares) from the Creator Store.
]]

local BUILTIN = "rbxasset://sounds/"

local AudioConfig = {}

-- 0-1 master volume for all game sounds
AudioConfig.MasterVolume = 1

AudioConfig.Sounds = {
	---- UI
	UiClick = { Id = BUILTIN .. "volume_slider.ogg", Volume = 0.5, Pitch = 1.3 },
	CardTick = { Id = BUILTIN .. "volume_slider.ogg", Volume = 0.55, Pitch = 1.1 }, -- carousel card passes the marker
	RevealCommon = { Id = BUILTIN .. "action_jump.mp3", Volume = 0.6, Pitch = 1.1 },
	RevealUncommon = { Id = BUILTIN .. "action_jump.mp3", Volume = 0.65, Pitch = 1.3 },
	RevealRare = { Id = BUILTIN .. "action_jump.mp3", Volume = 0.7, Pitch = 1.5 },
	RevealEpic = { Id = BUILTIN .. "action_jump_land.mp3", Volume = 0.8, Pitch = 1.4 },
	RevealLegendary = { Id = BUILTIN .. "impact_explosion_03.mp3", Volume = 0.55, Pitch = 1.5 },
	RevealMythic = { Id = BUILTIN .. "impact_explosion_03.mp3", Volume = 0.7, Pitch = 1.1 },

	---- Water collection
	FillTick = { Id = BUILTIN .. "volume_slider.ogg", Volume = 0.4, Pitch = 1 }, -- pitch rises with the fill level
	FillLoop = { Id = BUILTIN .. "action_swim.mp3", Volume = 0.25, Pitch = 1.2, Loop = true },
	FillFull = { Id = BUILTIN .. "action_jump.mp3", Volume = 0.7, Pitch = 1.7 },

	---- Watering
	PourLoop = { Id = BUILTIN .. "impact_water.mp3", Volume = 0.3, Pitch = 1, Loop = true },
	CoinBeat = { Id = BUILTIN .. "volume_slider.ogg", Volume = 0.6, Pitch = 1.4 }, -- pitch rises with the combo
	CoinLucky = { Id = BUILTIN .. "action_jump.mp3", Volume = 0.85, Pitch = 2 },
	StageUp = { Id = BUILTIN .. "action_jump.mp3", Volume = 0.8, Pitch = 1.6 },
	FullyGrown = { Id = BUILTIN .. "impact_explosion_03.mp3", Volume = 0.5, Pitch = 1.2 },
	Harvest = { Id = BUILTIN .. "action_jump.mp3", Volume = 0.9, Pitch = 2.1 },

	---- Juice pool
	PlantLaunch = { Id = BUILTIN .. "action_get_up.mp3", Volume = 0.7, Pitch = 0.8 },
	PlantExplode = { Id = BUILTIN .. "impact_explosion_03.mp3", Volume = 0.9, Pitch = 0.95 },
	PoolAppear = { Id = BUILTIN .. "impact_water.mp3", Volume = 0.7, Pitch = 1.3 },
	JuiceEnter = { Id = BUILTIN .. "action_jump.mp3", Volume = 0.8, Pitch = 1.7 },

	---- Shop
	ShopOpen = { Id = BUILTIN .. "action_get_up.mp3", Volume = 0.6, Pitch = 1.2 },
	Purchase = { Id = BUILTIN .. "action_jump.mp3", Volume = 0.85, Pitch = 1.9 },
	PurchaseFail = { Id = BUILTIN .. "volume_slider.ogg", Volume = 0.6, Pitch = 0.55 },

	---- Progression
	TrainTick = { Id = BUILTIN .. "volume_slider.ogg", Volume = 0.45, Pitch = 0.8 },
	CapacityUp = { Id = BUILTIN .. "action_jump.mp3", Volume = 0.9, Pitch = 1.9 },
	ZoneUnlocked = { Id = BUILTIN .. "action_jump.mp3", Volume = 0.9, Pitch = 2.2 },
}

return AudioConfig
