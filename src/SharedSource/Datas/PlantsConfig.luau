--[[
	Plant configuration. To add a plant, add one entry to `Plants` and drop a model with the
	same name into ReplicatedStorage/Assets/Fruits. To add a rarity, add one entry to `Rarities`.

	Plant fields:
		Rarity      (required) key of `Rarities`
		DisplayName (optional) defaults to the plant id
		ModelName   (optional) name of the model in the Fruits folder, defaults to the plant id
		Weight      (optional) overrides the rarity weight (relative selection chance)
		GrowTime    (optional) overrides the rarity grow time, in seconds
		GrowthMultiplier (optional) overrides the rarity multiplier for growth gained from watering
		WaterGoal   (optional) overrides the rarity water goal (see below)
		BaseWeight  (optional) overrides the rarity base weight (see below)

	Rarity fields:
		Order       sort order, lower = more common
		Weight      relative chance of ONE plant of this rarity being selected
		GrowTime    seconds of growing; rarer rarities grow faster
		GrowthMultiplier  multiplier for growth points gained per unit of water
		WaterGoal   total water (all players) that fully boosts the plant; the grow timer shrinks as the
		            server approaches it (see RewardConfig)
		BaseWeight  abstract weight (kg) of a fresh plant; it grows with the plant and scales the harvest rewards
		Color/DarkColor  UI colors (body / border)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlantsConfig = {}

---- World / assets
-- Folder names are tried in order; "Aseets" is the legacy misspelling used by older notes.
PlantsConfig.AssetFolderNames = { "Assets", "Aseets" }
PlantsConfig.FruitsFolderName = "Fruits"
PlantsConfig.GardenName = "Garden"
PlantsConfig.PlantBedName = "PlantBed"
PlantsConfig.PlantTag = "GardenPlant" -- CollectionService tag on the plant model currently in the world

---- Cycle
PlantsConfig.Cycle = {
	FinishedDuration = 40, -- TESTING (was 180): seconds between "fully grown" and the next plant being selected
	FirstCycleDelay = 2, -- seconds after the first player joins before the first selection
}

---- Selection animation (shared so the server phase length matches the client animation)
PlantsConfig.Selection = {
	ScrollTime = 6, -- carousel spin, with a smooth slowdown
	RevealTime = 3.5, -- winner reveal, ends with the overlay fading out
	ReelLength = 30, -- number of cards in the carousel
	WinnerIndex = 24, -- index of the winning card inside the carousel
	VisibleCards = 5, -- cards visible at once
}

---- Plant growth through watering (the larger the plant, the slower it grows)
-- scale = SeedlingScale * (1 + (points * Coefficient) ^ Exponent), Exponent < 1 => diminishing growth
PlantsConfig.Growth = {
	SeedlingScale = 0.2,
	PointsPerWater = 1, -- growth points gained per unit of water poured on the plant
	Coefficient = 0.25,
	Exponent = 0.5,
	TweenTime = 0.6,
}

---- Rarities
PlantsConfig.Rarities = {
	Common = {
		Order = 1,
		DisplayName = "Common",
		Weight = 20,
		GrowTime = 600,
		GrowthMultiplier = 1,
		WaterGoal = 250,
		BaseWeight = 1,
		Color = Color3.fromRGB(150, 214, 92),
		DarkColor = Color3.fromRGB(58, 120, 46),
	},
	Uncommon = {
		Order = 2,
		DisplayName = "Uncommon",
		Weight = 12,
		GrowTime = 480,
		GrowthMultiplier = 1,
		WaterGoal = 220,
		BaseWeight = 2,
		Color = Color3.fromRGB(86, 200, 168),
		DarkColor = Color3.fromRGB(28, 112, 100),
	},
	Rare = {
		Order = 3,
		DisplayName = "Rare",
		Weight = 7,
		GrowTime = 360,
		GrowthMultiplier = 1,
		WaterGoal = 200,
		BaseWeight = 4,
		Color = Color3.fromRGB(88, 160, 255),
		DarkColor = Color3.fromRGB(34, 78, 168),
	},
	Epic = {
		Order = 4,
		DisplayName = "Epic",
		Weight = 3,
		GrowTime = 240,
		GrowthMultiplier = 1,
		WaterGoal = 180,
		BaseWeight = 9,
		Color = Color3.fromRGB(190, 108, 255),
		DarkColor = Color3.fromRGB(96, 40, 164),
	},
	Legendary = {
		Order = 5,
		DisplayName = "Legendary",
		Weight = 1,
		GrowTime = 120,
		GrowthMultiplier = 1,
		WaterGoal = 150,
		BaseWeight = 25,
		Color = Color3.fromRGB(255, 196, 56),
		DarkColor = Color3.fromRGB(176, 104, 18),
	},
}

---- Plants
PlantsConfig.Plants = {
	Banana = { Rarity = "Common" },
	Orange = { Rarity = "Common" },
	RedApple = { DisplayName = "Red Apple", Rarity = "Common" },
	GreenApple = { DisplayName = "Green Apple", Rarity = "Common" },
	Tomato = { Rarity = "Common" },

	GreenGrape = { DisplayName = "Green Grape", Rarity = "Uncommon" },
	PurpleGrape = { DisplayName = "Purple Grape", Rarity = "Uncommon" },
	Pepper = { Rarity = "Uncommon" },

	Raspberry = { Rarity = "Rare" },
	DragonFruit = { DisplayName = "Dragon Fruit", Rarity = "Rare" },

	FurryFruit = { DisplayName = "Furry Fruit", Rarity = "Epic" },
	FireFlower = { DisplayName = "Fire Flower", Rarity = "Epic" },

	GoldenApple = { DisplayName = "Golden Apple", Rarity = "Legendary" },
}

---- Accessors (use these instead of reading the tables directly)

function PlantsConfig.GetPlant(plantId)
	return PlantsConfig.Plants[plantId]
end

function PlantsConfig.GetRarity(plantId)
	local plant = PlantsConfig.Plants[plantId]
	return plant and PlantsConfig.Rarities[plant.Rarity]
end

function PlantsConfig.GetDisplayName(plantId)
	local plant = PlantsConfig.Plants[plantId]
	return plant and (plant.DisplayName or plantId) or "?"
end

function PlantsConfig.GetWeight(plantId)
	local plant = PlantsConfig.Plants[plantId]
	local rarity = PlantsConfig.GetRarity(plantId)
	return plant and (plant.Weight or (rarity and rarity.Weight)) or 0
end

-- TESTING: when set, every plant grows in this many seconds. Set to nil for the real grow times.
PlantsConfig.TestGrowTime = 20

function PlantsConfig.GetGrowTime(plantId)
	if PlantsConfig.TestGrowTime then
		return PlantsConfig.TestGrowTime
	end
	local plant = PlantsConfig.Plants[plantId]
	local rarity = PlantsConfig.GetRarity(plantId)
	return plant and (plant.GrowTime or (rarity and rarity.GrowTime)) or 600
end

function PlantsConfig.GetGrowthMultiplier(plantId)
	local plant = PlantsConfig.Plants[plantId]
	local rarity = PlantsConfig.GetRarity(plantId)
	return plant and (plant.GrowthMultiplier or (rarity and rarity.GrowthMultiplier)) or 1
end

function PlantsConfig.GetWaterGoal(plantId)
	local plant = PlantsConfig.Plants[plantId]
	local rarity = PlantsConfig.GetRarity(plantId)
	return plant and (plant.WaterGoal or (rarity and rarity.WaterGoal)) or 250
end

function PlantsConfig.GetBaseWeight(plantId)
	local plant = PlantsConfig.Plants[plantId]
	local rarity = PlantsConfig.GetRarity(plantId)
	return plant and (plant.BaseWeight or (rarity and rarity.BaseWeight)) or 1
end

--- Returns the model template for a plant, or nil if it's missing.
function PlantsConfig.GetTemplate(plantId)
	local plant = PlantsConfig.Plants[plantId]
	if not plant then
		return nil
	end
	for _, folderName in ipairs(PlantsConfig.AssetFolderNames) do
		local assets = ReplicatedStorage:FindFirstChild(folderName)
		local fruits = assets and assets:FindFirstChild(PlantsConfig.FruitsFolderName)
		local template = fruits and fruits:FindFirstChild(plant.ModelName or plantId)
		if template then
			return template
		end
	end
	return nil
end

return PlantsConfig
