local StatsConfig = require(script.Parent.StatsConfig)
local UpgradesConfig = require(script.Parent.UpgradesConfig)

local ProfileTemplate = {
	Stats = StatsConfig.GetDefaults(),
	Upgrades = UpgradesConfig.GetDefaults(),
}

return ProfileTemplate
