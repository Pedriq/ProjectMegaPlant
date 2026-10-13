--[[
	Coin upgrades sold in the Upgrade Shop (Workspace/Garden/UpgradeShop/MainHouse).
	To add an upgrade: add an id to `Order`, an entry to `Upgrades`, and apply its `Effect` where the
	game reads it (Upgrade_Service:GetMultiplier(player, effect)).

	Upgrade fields:
		DisplayName / Description / Icon
		Effect         what it speeds up: "FillSpeed" (water collection) or "PourSpeed" (watering)
		EffectName     short label used in the shop
		(no max level: upgrades can be bought forever)
		BasePrice      price of level 1
		PriceGrowth    every further level costs this many times more (price = BasePrice * PriceGrowth ^ level)
		BonusPerLevel  +this to the speed multiplier per level (0.15 = +15% per level)
]]

local UpgradesConfig = {}

-- Roblox built-in placeholder image; swap for real asset ids later
local PLACEHOLDER_ICON = "rbxasset://textures/ui/GuiImagePlaceholder.png"

-- player attributes "Upgrade_<Id>" hold the replicated level of each upgrade
UpgradesConfig.AttributePrefix = "Upgrade_"

UpgradesConfig.Order = { "WaterCollectionSpeed", "WateringSpeed" }

UpgradesConfig.Upgrades = {
	WaterCollectionSpeed = {
		DisplayName = "Water Collection Speed",
		Description = "Your watering can fills up faster",
		Icon = PLACEHOLDER_ICON, -- TODO: icon
		Effect = "FillSpeed",
		EffectName = "Fill speed",
		BasePrice = 50,
		PriceGrowth = 1.35,
		BonusPerLevel = 0.15,
	},
	WateringSpeed = {
		DisplayName = "Watering Speed",
		Description = "You pour water onto plants faster",
		Icon = PLACEHOLDER_ICON, -- TODO: icon
		Effect = "PourSpeed",
		EffectName = "Pour speed",
		BasePrice = 75,
		PriceGrowth = 1.4,
		BonusPerLevel = 0.15,
	},
}

---- The shop in the world
UpgradesConfig.Shop = {
	Path = { "Garden", "UpgradeShop", "MainHouse" },
	PromptName = "UpgradeShopPrompt",
	ObjectText = "Upgrade Shop",
	ActionText = "Open Shop",
	MaxActivationDistance = 12,
	KeyboardKeyCode = Enum.KeyCode.E,
	GamepadKeyCode = Enum.KeyCode.ButtonX,
	-- extra studs of leeway for server-side purchase checks (the shop also closes itself when you walk away)
	DistanceTolerance = 10,
}

---- Shop camera / blur
UpgradesConfig.Camera = {
	ZoomOutStuds = 14, -- how much further the camera moves back while the shop is open
	FieldOfViewIncrease = 6,
	BlurSize = 22,
}

---- Accessors

function UpgradesConfig.GetDefaults()
	local defaults = {}
	for _, id in ipairs(UpgradesConfig.Order) do
		defaults[id] = 0
	end
	return defaults
end

function UpgradesConfig.GetAttributeName(upgradeId)
	return UpgradesConfig.AttributePrefix .. upgradeId
end

--- Price of the NEXT level for a player currently at `level`.
function UpgradesConfig.GetPrice(upgradeId, level)
	local config = UpgradesConfig.Upgrades[upgradeId]
	-- exponential growth, clamped only so absurdly high levels can never overflow to infinity
	return math.floor(math.min(config.BasePrice * config.PriceGrowth ^ level, 2 ^ 53) + 0.5)
end

--- Speed multiplier granted by an upgrade at `level` (1 = no bonus).
function UpgradesConfig.GetMultiplier(upgradeId, level)
	local config = UpgradesConfig.Upgrades[upgradeId]
	return 1 + config.BonusPerLevel * level
end

return UpgradesConfig
