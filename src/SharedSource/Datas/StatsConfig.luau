--[[
	Single source of truth for the player's core stats.
	Order here = order on the HUD (top to bottom) and in leaderstats.

	Key         - key inside profile.Data.Stats (used by StatsService methods)
	DisplayName - name of the value object inside `leaderstats`
	Icon        - placeholder image, replace with real asset ids later
	ValueClass  - class of the value object created in leaderstats
]]

local StatsConfig = {}

-- Roblox built-in placeholder image; swap each stat's Icon for a real asset id later
local PLACEHOLDER_ICON = "rbxasset://textures/ui/GuiImagePlaceholder.png"

StatsConfig.Folder = "leaderstats"

StatsConfig.Order = {
	{
		Key = "Capacity",
		DisplayName = "Capacity",
		Icon = PLACEHOLDER_ICON, -- TODO: watering can capacity icon
		ValueClass = "IntValue",
		Default = 10,
		Min = 1,
	},
	{
		Key = "MovementSpeed",
		DisplayName = "Movement Speed",
		Icon = PLACEHOLDER_ICON, -- TODO: movement speed icon
		ValueClass = "NumberValue",
		Default = 16,
		Min = 1,
		Max = 50,
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

return StatsConfig
