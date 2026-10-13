--[[
	Water collection / watering tuning and the names of the replicated player attributes
	(server writes them, clients read them).
]]

local WaterConfig = {}

WaterConfig.Attributes = {
	Water = "Water", -- integer water amount currently carried
	Can = "WateringCan", -- id of the equipped watering can (see WateringCansConfig)
	Filling = "Filling", -- true while collecting water at a source
	Watering = "Watering", -- true while pouring water on the plant
}

-- A hold prompt keeps working until released, so the duration is just "very long".
local HOLD_FOREVER = 3600

--- Water sources. Each `Path` is a chain of child names starting at Workspace.
WaterConfig.Sources = {
	{
		Path = { "Garden", "WaterSource", "MainHouse" },
		FillMultiplier = 1,
		ObjectText = "Water Source",
		ActionText = "Hold to fill",
		MaxActivationDistance = 20,
	},
}

--- The prompt used to water the plant (placed on Workspace.Garden.PlantBed).
WaterConfig.PlantPrompt = {
	Path = { "Garden", "PlantBed" },
	ObjectText = "Plant",
	ActionText = "Hold to water",
	MaxActivationDistance = 16,
}

WaterConfig.Prompt = {
	HoldDuration = HOLD_FOREVER,
	KeyboardKeyCode = Enum.KeyCode.E,
	GamepadKeyCode = Enum.KeyCode.ButtonX,
	RequiresLineOfSight = false,
}

-- extra studs of leeway when the server re-checks the player's distance while holding
WaterConfig.DistanceTolerance = 6

-- how often accumulated watering is applied to the plant (seconds)
WaterConfig.GrowthFlushInterval = 0.2

-- how often changed water totals are sent to clients (seconds). Totals are rounded to whole units
-- and only sent when the rounded value changed, which keeps traffic low with 100 players.
WaterConfig.StatsBroadcastInterval = 0.25

---- Rewards for watering
-- coins earned per unit of water poured on the plant (fractions accumulate, whole coins are paid out)
WaterConfig.CoinsPerWater = 1
-- a player gets +1 Plants Grown when the plant finishes if they poured at least this much water into it
WaterConfig.MinWaterForPlantsGrown = 1

return WaterConfig
