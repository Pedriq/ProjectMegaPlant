--[[
	Coin upgrades sold in the Upgrade Shop (Workspace/Garden/UpgradeShop/MainHouse).
	To add an upgrade: add an id to `Order`, an entry to `Upgrades`, and apply its `Effect` where the
	game reads it (Upgrade_Service:GetMultiplier(player, effect)).

	Upgrade fields:
		DisplayName / Description / Icon
		Effect         what it speeds up: "FillSpeed" (water collection) or "PourSpeed" (watering)
		EffectName     short label used in the shop
		(no max level: upgrades can be bought forever)
		Curve numbers (BasePrice, Bonus, Scale, Tail) come from BalanceConfig.Upgrades, where the three
		phases (hook / plateau / mastery) are explained:
		  price(level)      = BasePrice * GrowthEarly^min(level, SoftLevel) * GrowthLate^max(level - SoftLevel, 0)
		  multiplier(level) = 1 + Bonus * (1 - e^(-level / Scale)) + Tail * level
]]

local BalanceConfig = require(game:GetService("ReplicatedStorage").SharedSource.Datas.BalanceConfig)

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
		Curve = BalanceConfig.Upgrades.WaterCollectionSpeed,
	},
	WateringSpeed = {
		DisplayName = "Watering Speed",
		Description = "You pour water onto plants faster",
		Icon = PLACEHOLDER_ICON, -- TODO: icon
		Effect = "PourSpeed",
		EffectName = "Pour speed",
		Curve = BalanceConfig.Upgrades.WateringSpeed,
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

--- Price of the NEXT level for a player currently at `level`. Cheap and steady for the first levels, then
--- steeper; clamped to MaxPrice so it stays a sane integer at any level.
function UpgradesConfig.GetPrice(upgradeId, level)
	local config = UpgradesConfig.Upgrades[upgradeId]
	local economy = BalanceConfig.Upgrades
	level = math.max(level, 0)
	local early = math.min(level, economy.SoftLevel)
	local late = math.max(level - economy.SoftLevel, 0)
	local price = config.Curve.BasePrice * economy.GrowthEarly ^ early * economy.GrowthLate ^ late
	return math.floor(math.min(price, economy.MaxPrice) + 0.5)
end

--- Speed multiplier granted by an upgrade at `level` (1 = no bonus): big early gains that flatten out,
--- plus a thin linear tail so very high levels still matter a little (never overflows).
function UpgradesConfig.GetMultiplier(upgradeId, level)
	local curve = UpgradesConfig.Upgrades[upgradeId].Curve
	level = math.max(level, 0)
	return 1 + curve.Bonus * (1 - math.exp(-level / curve.Scale)) + curve.Tail * level
end

return UpgradesConfig
