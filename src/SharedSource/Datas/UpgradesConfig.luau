--[[
	Coin upgrades sold in the Upgrade Shop (Workspace/Garden/UpgradeShop/MainHouse).
	To add an upgrade: add an id to `Order`, an entry to `Upgrades`, and apply its `Effect` where the
	game reads it (Upgrade_Service:GetMultiplier(player, effect)).

	Upgrade fields:
		DisplayName / Description / Icon
		Effect         what it improves: "FillSpeed" (water collection), "PourSpeed" (watering) or "CritChance" (Luck)
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

UpgradesConfig.Order = { "WaterCollectionSpeed", "WateringSpeed", "Luck" }

UpgradesConfig.Upgrades = {
	WaterCollectionSpeed = {
		DisplayName = "Water Collection",
		Description = "Your can fills up faster",
		Accent = Color3.fromRGB(96, 168, 232), -- sky blue
		Glyph = "💧", -- shown in the icon plate until IconImage is set
		IconImage = nil, -- TODO: real icon (rbxassetid)
		Effect = "FillSpeed",
		EffectName = "Fill speed",
		Curve = BalanceConfig.Upgrades.WaterCollectionSpeed,
	},
	WateringSpeed = {
		DisplayName = "Watering Speed",
		Description = "You pour onto plants faster",
		Accent = Color3.fromRGB(84, 186, 164), -- teal
		Glyph = "🚿",
		IconImage = nil, -- TODO: real icon (rbxassetid)
		Effect = "PourSpeed",
		EffectName = "Pour speed",
		Curve = BalanceConfig.Upgrades.WateringSpeed,
	},
	Luck = {
		DisplayName = "Luck",
		Description = "More lucky pours (crits)",
		Accent = Color3.fromRGB(170, 132, 226), -- violet
		Glyph = "🍀",
		IconImage = nil, -- TODO: real icon (rbxassetid)
		Effect = "CritChance",
		EffectName = "Crit chance",
		-- shown as a percentage: base chance * multiplier, never above Max
		Percent = { Base = BalanceConfig.Luck.BaseCritChance, Max = BalanceConfig.Luck.MaxCritChance },
		Curve = BalanceConfig.Upgrades.Luck,
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

--- The value an upgrade gives at `level`: the speed multiplier, or for percentage upgrades (Luck) the
--- resulting probability (0-1, capped).
function UpgradesConfig.GetValue(upgradeId, level)
	local config = UpgradesConfig.Upgrades[upgradeId]
	local multiplier = UpgradesConfig.GetMultiplier(upgradeId, level)
	if config.Percent then
		return math.min(config.Percent.Base * multiplier, config.Percent.Max)
	end
	return multiplier
end

--- The pieces of an upgrade's effect line: { Current = "x1.24", Next = "x1.45" } (speed) or
--- { Current = "10.0%", Next = "11.7%" } (Luck).
function UpgradesConfig.GetEffectParts(upgradeId, level)
	local config = UpgradesConfig.Upgrades[upgradeId]
	local current = UpgradesConfig.GetValue(upgradeId, level)
	local nextValue = UpgradesConfig.GetValue(upgradeId, level + 1)
	if config.Percent then
		return { Current = ("%.1f%%"):format(current * 100), Next = ("%.1f%%"):format(nextValue * 100) }
	end
	return { Current = ("x%.2f"):format(current), Next = ("x%.2f"):format(nextValue) }
end

--- "Fill speed x1.24 -> x1.45" or "Crit chance 10.0% -> 11.7%" as one plain string.
function UpgradesConfig.GetEffectText(upgradeId, level)
	local config = UpgradesConfig.Upgrades[upgradeId]
	local parts = UpgradesConfig.GetEffectParts(upgradeId, level)
	return ("%s %s -> %s"):format(config.EffectName, parts.Current, parts.Next)
end

return UpgradesConfig
