local StatsConfig = require(script.Parent.StatsConfig)
local UpgradesConfig = require(script.Parent.UpgradesConfig)

local ProfileTemplate = {
	Stats = StatsConfig.GetDefaults(),
	Upgrades = UpgradesConfig.GetDefaults(),
	-- first-time tutorial (see TutorialConfig / Tutorial_Service)
	Tutorial = { Step = 1, Done = false },
}

return ProfileTemplate
