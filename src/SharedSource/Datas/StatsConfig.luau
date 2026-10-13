--[[
	Single source of truth for the player's core stats.
	Order here = order on the HUD (top to bottom) and in leaderstats.

	Key         - key inside profile.Data.Stats (used by Stats_Service methods)
	DisplayName - name of the value object inside `leaderstats`
	Icon        - placeholder image, replace with real asset ids later
	ValueClass  - class of the value object created in leaderstats
	HudHeight   - relative height of the stat's row on the HUD (default 1)

	Derived stats (not stored, always computed from the primary stats):
		watering can capacity  <- Strength (see `Capacity`)
		walk speed             <- Mobility (see `Movement`)
]]

local StatsConfig = {}

-- Roblox built-in placeholder image; swap each stat's Icon for a real asset id later
local PLACEHOLDER_ICON = "rbxasset://textures/ui/GuiImagePlaceholder.png"

StatsConfig.Folder = "leaderstats"

StatsConfig.Order = {
	{
		Key = "Strength",
		DisplayName = "Strength",
		Icon = PLACEHOLDER_ICON, -- TODO: strength icon
		ValueClass = "IntValue",
		Default = 0,
		Min = 0,
		HudHeight = 1.5, -- also shows "water / capacity" underneath
	},
	{
		Key = "Mobility",
		DisplayName = "Mobility",
		Icon = PLACEHOLDER_ICON, -- TODO: mobility icon
		ValueClass = "IntValue",
		Default = 0,
		Min = 0,
	},
	{
		Key = "Coins",
		DisplayName = "Coins",
		Icon = PLACEHOLDER_ICON, -- TODO: coins icon
		ValueClass = "IntValue",
		Default = 0,
		Min = 0,
	},
	{
		Key = "PlantsGrown",
		DisplayName = "Plants Grown",
		Icon = PLACEHOLDER_ICON, -- TODO: plants grown icon
		ValueClass = "IntValue",
		Default = 0,
		Min = 0,
	},
}

---- Strength -> watering can capacity
-- Capacity is `Base` until a threshold is reached; then it jumps to that threshold's capacity.
-- Thresholds must be sorted by Strength (ascending).
StatsConfig.Capacity = {
	Base = 10,
	Thresholds = {
		{ Strength = 50, Capacity = 15 },
		{ Strength = 150, Capacity = 20 },
		{ Strength = 400, Capacity = 30 },
		{ Strength = 1000, Capacity = 45 },
		{ Strength = 2500, Capacity = 65 },
		{ Strength = 6000, Capacity = 100 },
	},
}

---- Mobility -> walk speed
StatsConfig.Movement = {
	BaseSpeed = 16,
	SpeedPerMobility = 0.03,
	MaxSpeed = 40,
}

StatsConfig.ByKey = {}
for _, definition in ipairs(StatsConfig.Order) do
	StatsConfig.ByKey[definition.Key] = definition
end

function StatsConfig.GetDefaults()
	local defaults = {}
	for _, definition in ipairs(StatsConfig.Order) do
		defaults[definition.Key] = definition.Default
	end
	return defaults
end

--- Watering can capacity for a Strength value.
function StatsConfig.GetCapacity(strength)
	local capacity = StatsConfig.Capacity.Base
	for _, threshold in ipairs(StatsConfig.Capacity.Thresholds) do
		if strength >= threshold.Strength then
			capacity = threshold.Capacity
		else
			break
		end
	end
	return capacity
end

--- Walk speed for a Mobility value.
function StatsConfig.GetWalkSpeed(mobility)
	local movement = StatsConfig.Movement
	return math.min(movement.BaseSpeed + mobility * movement.SpeedPerMobility, movement.MaxSpeed)
end

return StatsConfig
