--[[
	The first-time tutorial: a short guided quest (see Tutorial_Service / Tutorial_Controller). Every new player goes
	through it once, it cannot be skipped, and progress is saved in the profile (Tutorial.Step / Tutorial.Done).
	Players who already have progress (plants grown or an upgrade bought) never see it.

	It follows the real start of the game: a new player's can holds only 1 water and pays 1 coin per water, so the
	steps are tiny and the player TRAINS before trying to earn real money (training is what makes the can bigger).

	Places: things the arrow points to. Path = names from Workspace, Name = what the arrow says.

	Step fields:
		Id          unique name
		Title       short objective shown in the panel
		Text        one or two sentences of explanation
		Kind        how the SERVER decides the step is done:
		              "FillCan"   the can is full
		              "Pour"      `Amount` water poured onto the plant
		              "Capacity"  the can holds at least `Amount` water (grow it by training Strength)
		              "Coins"     the player holds at least `Amount` coins
		              "Upgrade"   an upgrade was bought
		Target      key of `Places` the arrow points to
		EmptyTarget (optional) the place used while the player's can is EMPTY (go to the water first)
		Gift        (Upgrade) the player is topped up to the first upgrade price, so the step is always possible

	To add a step: add an entry (and, for a new Kind, handle it in Tutorial_Service.progressOf).
]]

local TutorialConfig = {}

-- player attributes written by the server and read by the client
TutorialConfig.StepAttribute = "TutorialStep" -- 1..#Steps while active, 0 when finished
TutorialConfig.ProgressAttribute = "TutorialProgress" -- 0..1 inside the current step

TutorialConfig.Places = {
	WaterSource = { Path = { "Garden", "WaterSource", "MainHouse" }, Name = "Water Source" },
	PlantBed = { Path = { "Garden", "PlantBed" }, Name = "Plant" },
	Shop = { Path = { "Garden", "UpgradeShop", "MainHouse" }, Name = "Upgrade Shop" },
	Training = { Path = { "Garden", "TrainingZone", "Zone1", "Strength", "Main" }, Name = "Strength Training" },
}

TutorialConfig.Steps = {
	{
		Id = "FillCan",
		Title = "Fill your watering can",
		Text = "Go to the water source and hold the button that appears to fill your can.",
		Kind = "FillCan",
		Target = "WaterSource",
	},
	{
		Id = "WaterPlant",
		Title = "Water the plant",
		Text = "Carry the water to the plant and hold the button to pour it out. Every water you pour earns a coin!",
		Kind = "Pour",
		Amount = 1,
		Target = "PlantBed",
		EmptyTarget = "WaterSource",
	},
	{
		Id = "GrowCan",
		Title = "Grow your can",
		Text = "Your can only holds 1 water. Hold the button on the training station and your capacity grows. Keep holding until it reaches 5!",
		Kind = "Capacity",
		Amount = 5,
		Target = "Training",
	},
	{
		Id = "EarnCoins",
		Title = "Earn your first coins",
		Text = "Jump to stop training, then fill your bigger can and pour it on the plant. Earn 5 coins!",
		Kind = "Coins",
		Amount = 5,
		Target = "PlantBed",
		EmptyTarget = "WaterSource",
	},
	{
		Id = "BuyUpgrade",
		Title = "Buy your first upgrade",
		Text = "Open the Upgrade Shop and spend coins to fill or water faster. Here is a little extra to get you started! Harvests pay even more.",
		Kind = "Upgrade",
		Gift = true,
		Target = "Shop",
	},
}

return TutorialConfig
