local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local UpgradesConfig = require(ReplicatedStorage.SharedSource.Datas.UpgradesConfig)
local BalanceConfig = require(ReplicatedStorage.SharedSource.Datas.BalanceConfig)

--[[
	Coin upgrades (see UpgradesConfig). Levels are saved in the player's profile (Upgrades) and
	replicated through the player attributes "Upgrade_<Id>" so the shop UI can show them.

	The server alone decides purchases: the id must exist, the level must be below the max, the
	player must be near the shop and able to afford it. Coins are only removed after all checks pass.
]]
local Upgrade_Service = Knit.CreateService({
	Name = "Upgrade_Service",
	Client = {},

	-- (player, upgradeId, newLevel)
	UpgradeChanged = Signal.new(),
})

local PURCHASE_COOLDOWN = 0.15

local ProfileService, Stats_Service, Notification_Service
local shopPart
local lastPurchase = {} -- [player] = os.clock() of the last purchase request

---- Levels

local function getUpgradesData(player)
	local _, data = ProfileService:GetProfile(player)
	return data and data.Upgrades
end

local function publish(player, upgradeId, level)
	player:SetAttribute(UpgradesConfig.GetAttributeName(upgradeId), level)
end

function Upgrade_Service:GetLevel(player, upgradeId)
	local data = getUpgradesData(player)
	return data and data[upgradeId] or 0
end

--- Speed multiplier from every upgrade that has this effect ("FillSpeed", "PourSpeed"). 1 = no bonus.
function Upgrade_Service:GetMultiplier(player, effect)
	local data = getUpgradesData(player)
	local multiplier = 1
	for upgradeId, config in pairs(UpgradesConfig.Upgrades) do
		if config.Effect == effect then
			local level = data and data[upgradeId] or 0
			multiplier += UpgradesConfig.GetMultiplier(upgradeId, level) - 1
		end
	end
	return multiplier
end

--- Chance of a lucky (critical) pour for this player: the base chance raised by the Luck upgrade, capped.
function Upgrade_Service:GetCritChance(player)
	local luck = BalanceConfig.Luck
	return math.min(luck.BaseCritChance * Upgrade_Service:GetMultiplier(player, "CritChance"), luck.MaxCritChance)
end

---- Purchasing

local function isNearShop(player)
	if not shopPart then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local maxDistance = UpgradesConfig.Shop.MaxActivationDistance + UpgradesConfig.Shop.DistanceTolerance
	return (root.Position - shopPart.Position).Magnitude <= maxDistance
end

--- Buys the next level of an upgrade. Returns { Success, Reason?, Level? }.
function Upgrade_Service:Purchase(player, upgradeId)
	local config = typeof(upgradeId) == "string" and UpgradesConfig.Upgrades[upgradeId]
	if not config then
		return { Success = false, Reason = "Unknown upgrade" }
	end

	-- ignore request spam
	local now = os.clock()
	if lastPurchase[player] and now - lastPurchase[player] < PURCHASE_COOLDOWN then
		return { Success = false, Reason = "Too fast" }
	end
	lastPurchase[player] = now

	local data = getUpgradesData(player)
	if not data then
		return { Success = false, Reason = "Data not loaded" }
	end
	if not isNearShop(player) then
		return { Success = false, Reason = "Too far from the shop" }
	end

	-- no level cap: every level can always be bought and keeps adding its bonus
	local level = data[upgradeId] or 0

	local price = UpgradesConfig.GetPrice(upgradeId, level)
	if not Stats_Service:CanAfford(player, price) or not Stats_Service:SpendCoins(player, price) then
		Notification_Service:Notify(player, "NotEnoughCoins")
		return { Success = false, Reason = "Not enough coins", Level = level }
	end

	local newLevel = level + 1
	ProfileService:ChangeData(player, { "Upgrades", upgradeId }, newLevel)
	publish(player, upgradeId, newLevel)
	Upgrade_Service.UpgradeChanged:Fire(player, upgradeId, newLevel)

	return { Success = true, Level = newLevel }
end

--- DEBUG: sets an upgrade to an exact level without paying (see DebugCommands_Service). Returns the level.
function Upgrade_Service:DebugSetLevel(player, upgradeId, level)
	if not UpgradesConfig.Upgrades[upgradeId] or typeof(level) ~= "number" or level ~= level then
		return nil
	end
	if not getUpgradesData(player) then
		return nil
	end
	level = math.max(math.floor(level), 0)
	ProfileService:ChangeData(player, { "Upgrades", upgradeId }, level)
	publish(player, upgradeId, level)
	Upgrade_Service.UpgradeChanged:Fire(player, upgradeId, level)
	return level
end

function Upgrade_Service.Client:Purchase(player, upgradeId)
	return Upgrade_Service:Purchase(player, upgradeId)
end

---- Lifecycle

local function setupPlayer(player)
	local data = getUpgradesData(player)
	if not data then
		return
	end
	for _, upgradeId in ipairs(UpgradesConfig.Order) do
		publish(player, upgradeId, data[upgradeId] or 0)
	end
end

local function setupShop()
	local instance = workspace
	for _, name in ipairs(UpgradesConfig.Shop.Path) do
		instance = instance and instance:WaitForChild(name, 30)
	end
	if not (instance and instance:IsA("BasePart")) then
		warn("Upgrade_Service: shop part not found: Workspace/" .. table.concat(UpgradesConfig.Shop.Path, "/"))
		return
	end
	shopPart = instance

	-- The prompt only opens the shop UI (clients listen to it); purchases are validated separately.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = UpgradesConfig.Shop.PromptName
	prompt.ObjectText = UpgradesConfig.Shop.ObjectText
	prompt.ActionText = UpgradesConfig.Shop.ActionText
	prompt.HoldDuration = 0
	prompt.KeyboardKeyCode = UpgradesConfig.Shop.KeyboardKeyCode
	prompt.GamepadKeyCode = UpgradesConfig.Shop.GamepadKeyCode
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = UpgradesConfig.Shop.MaxActivationDistance
	prompt.Parent = shopPart
end

function Upgrade_Service:KnitStart()
	ProfileService = Knit.GetService("ProfileService")
	Stats_Service = Knit.GetService("Stats_Service")
	Notification_Service = Knit.GetService("Notification_Service")

	ProfileService.ProfileLoaded:Connect(setupPlayer)
	for player in pairs(ProfileService.Profiles) do
		task.spawn(setupPlayer, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastPurchase[player] = nil
	end)

	task.spawn(setupShop)
end

function Upgrade_Service:KnitInit() end

return Upgrade_Service
