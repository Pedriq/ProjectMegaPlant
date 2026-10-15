--[[
	Plant configuration. To add a plant, add one entry to `Plants` and drop a model with the
	same name into ReplicatedStorage/Assets/Fruits. To add a rarity, add one entry to `Rarities`.

	Plant fields:
		Rarity      (required) key of `Rarities`
		DisplayName (optional) defaults to the plant id
		ModelName   (optional) name of the model in the Fruits folder, defaults to the plant id
		Weight      (optional) overrides the rarity weight (relative selection chance)
		GrowTime    (optional) overrides the derived grow time, in seconds (normally from BalanceConfig.TargetTime)
		GrowthMultiplier (optional) overrides the rarity multiplier for growth gained from watering
		WaterGoal   (optional) overrides the rarity water goal (see below)
		BaseWeight  (optional) overrides the rarity base weight (see below)

	Rarity fields:
		Order       sort order, lower = more common
		Weight      relative chance of ONE plant of this rarity being selected
		GrowTime    (optional) fixed grow time; by default derived from BalanceConfig.TargetTime (rarer = faster)
		GrowthMultiplier  multiplier for growth points gained per unit of water
		WaterGoal   total water (all players) that fully boosts the plant; the grow timer shrinks as the
		            (derived from BalanceConfig unless set explicitly) 		            server approaches it (see RewardConfig)
		BaseWeight  abstract weight (kg) of a fresh plant; it grows with the plant and scales the harvest rewards
		Color/DarkColor  UI colors (body / border)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BalanceConfig = require(ReplicatedStorage.SharedSource.Datas.BalanceConfig)

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
	FinishedDuration = BalanceConfig.Cycle.FinishedDuration, -- seconds between "fully grown" and the next plant being selected
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
	SeedlingScale = 0.28,
	PointsPerWater = 1, -- base growth points per unit of water (the plant's goal normalises it, see GetGrowthMultiplier)
	-- size ratio at the water goal = 1 + (PointsAtGoal * Coefficient) ^ Exponent = 1 + (1200 * 0.06) ^ 0.55 ~ 11.5
	-- = almost the juice maximum. Growth never stops: past the goal it only slows down (SlowdownRate),
	-- and the juice maximum (ratio 12) is reached at roughly 1.1x the goal water.
	Coefficient = 0.06,
	Exponent = 0.55,
	-- points beyond the water goal count only this fraction (0-1, never 0: the plant always keeps growing)
	SlowdownRate = 0.7,
	-- makes the model physically bigger without touching juice / weight (those use the plain ratio above)
	VisualSizeBoost = 1.6,
	-- the size animation is stepped at StepRate Hz (not every frame): every step of a big model is replicated
	-- to up to 100 clients, so a lower rate saves a lot of bandwidth while the eased steps still look smooth
	StepRate = 15,
	TweenTime = 0.4,
}

---- Rarities
PlantsConfig.Rarities = {
	Common = {
		Order = 1,
		DisplayName = "Common",
		Weight = 20,
		GrowthMultiplier = 1,
		BaseWeight = BalanceConfig.BaseWeight.Common,
		Color = Color3.fromRGB(150, 214, 92),
		DarkColor = Color3.fromRGB(58, 120, 46),
	},
	Uncommon = {
		Order = 2,
		DisplayName = "Uncommon",
		Weight = 12,
		GrowthMultiplier = 1,
		BaseWeight = BalanceConfig.BaseWeight.Uncommon,
		Color = Color3.fromRGB(86, 200, 168),
		DarkColor = Color3.fromRGB(28, 112, 100),
	},
	Rare = {
		Order = 3,
		DisplayName = "Rare",
		Weight = 7,
		GrowthMultiplier = 1,
		BaseWeight = BalanceConfig.BaseWeight.Rare,
		Color = Color3.fromRGB(88, 160, 255),
		DarkColor = Color3.fromRGB(34, 78, 168),
	},
	Epic = {
		Order = 4,
		DisplayName = "Epic",
		Weight = 3,
		GrowthMultiplier = 1,
		BaseWeight = BalanceConfig.BaseWeight.Epic,
		Color = Color3.fromRGB(190, 108, 255),
		DarkColor = Color3.fromRGB(96, 40, 164),
	},
	Legendary = {
		Order = 5,
		DisplayName = "Legendary",
		Weight = 1,
		GrowthMultiplier = 1,
		BaseWeight = BalanceConfig.BaseWeight.Legendary,
		Color = Color3.fromRGB(255, 196, 56),
		DarkColor = Color3.fromRGB(176, 104, 18),
	},
	Mythic = {
		Order = 6,
		DisplayName = "Mythic",
		Weight = 0.4,
		GrowthMultiplier = 1,
		BaseWeight = BalanceConfig.BaseWeight.Mythic,
		Color = Color3.fromRGB(255, 84, 120),
		DarkColor = Color3.fromRGB(140, 24, 64),
	},
}

---- Plants
PlantsConfig.Plants = {
	Orange = { Rarity = "Common" },
	Tomato = { Rarity = "Common" },
	Strawberry = { Rarity = "Common" },

	Blueberry = { Rarity = "Rare" },
	Peach = { Rarity = "Rare" },
	Mango = { Rarity = "Rare" },

	Melon = { Rarity = "Epic" },
	Watermelon = { Rarity = "Epic" },
	Pomegranate = { Rarity = "Epic" },

	DragonFruit = { DisplayName = "Dragon Fruit", Rarity = "Legendary" },
	MoonGrapes = { DisplayName = "Moon Grapes", Rarity = "Legendary" },

	CosmicPear = { DisplayName = "Cosmic Pear", Rarity = "Mythic" },
	CrystalPineapple = { DisplayName = "Crystal Pineapple", Rarity = "Mythic" },
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

-- TESTING: when set (e.g. 20), every plant grows in this many seconds. nil = the real, balanced grow times.
PlantsConfig.TestGrowTime = nil

--- The real (configured) grow time, ignoring the testing override.
function PlantsConfig.GetBaseGrowTime(plantId)
	local plant = PlantsConfig.Plants[plantId]
	local rarity = PlantsConfig.GetRarity(plantId)
	local explicit = plant and (plant.GrowTime or (rarity and rarity.GrowTime))
	if explicit then
		return explicit
	end
	-- derived from the rarity's target time (see BalanceConfig.TargetTime)
	local target = BalanceConfig.TargetTime[plant and plant.Rarity or "Common"] or BalanceConfig.TargetTime.Common
	return target * (1 + BalanceConfig.Goal.BoostMax / BalanceConfig.Goal.Fill)
end

function PlantsConfig.GetGrowTime(plantId)
	if PlantsConfig.TestGrowTime then
		return PlantsConfig.TestGrowTime
	end
	return PlantsConfig.GetBaseGrowTime(plantId)
end

-- Total water that makes a plant fully grown. At this water the plant is ~10.5x its seedling size (size factor
-- ~0.95), so its juice multiplier lands well above the midpoint of the rarity range (JuiceConfig.Multipliers).
PlantsConfig.DefaultWaterGoal = 170500

--- Total water (all players together) that fully boosts the plant. Unless the plant / rarity sets
--- WaterGoal explicitly it is derived from the reference population (see BalanceConfig):
--- 100 players * 60% active * 1.5 water/s * grow time * 0.6.
function PlantsConfig.GetWaterGoal(plantId)
	local plant = PlantsConfig.Plants[plantId]
	local rarity = PlantsConfig.GetRarity(plantId)
	local explicit = plant and (plant.WaterGoal or (rarity and rarity.WaterGoal)) or PlantsConfig.DefaultWaterGoal
	if explicit then
		return explicit
	end
	local reference = BalanceConfig.Reference
	local goal = reference.Players
		* reference.ActiveFraction
		* reference.WaterPerSecond
		* PlantsConfig.GetBaseGrowTime(plantId)
		* BalanceConfig.Goal.Fill
	return math.max(math.floor(goal + 0.5), 1)
end

--- Growth points per unit of water. Normalised by the goal: reaching the water goal always yields
--- BalanceConfig.PointsAtGoal points, so every plant has the same size at its own goal.
--- `goal` is the water goal of this particular cycle (defaults to the full-server goal).
function PlantsConfig.GetGrowthMultiplier(plantId, goal)
	local plant = PlantsConfig.Plants[plantId]
	local rarity = PlantsConfig.GetRarity(plantId)
	local multiplier = plant and (plant.GrowthMultiplier or (rarity and rarity.GrowthMultiplier)) or 1
	return multiplier * BalanceConfig.PointsAtGoal / math.max(goal or PlantsConfig.GetWaterGoal(plantId), 1)
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
