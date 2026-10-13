local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local WaterConfig = require(ReplicatedStorage.SharedSource.Datas.WaterConfig)
local PlantsConfig = require(ReplicatedStorage.SharedSource.Datas.PlantsConfig)
local RewardConfig = require(ReplicatedStorage.SharedSource.Datas.RewardConfig)

--[[
	Everything the player earns from watering, decided on the server (see RewardConfig):

	  Pour beats   every half second of pouring pays coins; staying on the plant builds a combo;
	               each beat can be a LUCKY pour. The pourer gets a PourBeat message for popups/sounds.
	  Water goal   the more water the server pours into the plant, the shorter its grow timer.
	  Stages       milestones towards the water goal: server-wide celebration + bonus for contributors.
	  Harvest      when the timer ends: coins for contributors, +1 Plants Grown, a server-wide fanfare.

	Clients never decide or report any amount.
]]
local Reward_Service = Knit.CreateService({
	Name = "Reward_Service",
	Client = {
		-- to the pourer: (coins, lucky, combo, multiplier)
		PourBeat = Knit.CreateSignal(),
		-- to everyone: (stageIndex, stageName, bonusCoins, plantId)
		StageReached = Knit.CreateSignal(),
		-- to everyone: (plantId) the plant finished growing
		PlantFullyGrown = Knit.CreateSignal(),
		-- to each rewarded contributor: ({ PlantId, Coins, PlantsGrown, Water })
		PlantHarvested = Knit.CreateSignal(),
	},
})

local Watering_Service, PlantCycle_Service, Stats_Service, Plant_Service

local random = Random.new()
local pourState = {} -- [player] = { Water, Timer, Combo, LastBeat, Remainder }
local stageIndex = 0 -- stages already reached in the current cycle
local stageCycleId = 0
local sinceCheck = 0
local rewardedCycles = {} -- [cycleId] = true once the harvest was paid

---- Pour beats

local function getPourState(player)
	local state = pourState[player]
	if not state then
		state = { Water = 0, Timer = 0, Combo = 0, LastBeat = 0, Remainder = 0 }
		pourState[player] = state
	end
	return state
end

--- Pays the water poured since the last beat. `final` beats (the player let go) don't extend the combo
--- and can't be lucky, they just settle the remaining coins.
local function payBeat(player, final)
	local state = pourState[player]
	if not state or state.Water <= 0 then
		return
	end

	local config = RewardConfig.Pour
	local now = os.clock()
	if now - state.LastBeat > config.ComboGrace then
		state.Combo = 0
	end

	local multiplier = 1 + math.min(state.Combo, config.ComboMax) * config.ComboStep
	local lucky = not final and random:NextNumber() < config.CritChance
	if lucky then
		multiplier *= config.CritMultiplier
	end

	local coins = state.Water * WaterConfig.CoinsPerWater * multiplier + state.Remainder
	local whole = math.floor(coins)
	state.Remainder = coins - whole
	state.Water = 0
	state.Timer = 0
	if not final then
		state.Combo += 1
		state.LastBeat = now
	end

	if whole > 0 then
		Stats_Service:AddCoins(player, whole)
		Reward_Service.Client.PourBeat:Fire(player, whole, lucky, state.Combo, multiplier)
	end
end

local function onPoured(player, amount, dt)
	local state = getPourState(player)
	state.Water += amount
	state.Timer += dt
	if state.Timer >= RewardConfig.Pour.BeatInterval then
		payBeat(player, false)
	end
end

---- Water goal, boost and stages

local function checkGoal()
	local cycle = PlantCycle_Service:GetState()
	if cycle.Phase ~= "Growing" or not cycle.PlantId then
		return
	end

	-- new cycle: stages start over
	if stageCycleId ~= cycle.CycleId then
		stageCycleId = cycle.CycleId
		stageIndex = 0
	end

	local total = Watering_Service:GetTotalWater(cycle.CycleId)
	local fraction = total / math.max(PlantsConfig.GetWaterGoal(cycle.PlantId), 1)

	PlantCycle_Service:SetBoost(fraction)

	while stageIndex < #RewardConfig.Stages do
		local stage = RewardConfig.Stages[stageIndex + 1]
		if fraction < stage.Fraction then
			break
		end
		stageIndex += 1

		-- everyone who contributed shares the bonus
		for userId in pairs(Watering_Service:GetContributions(cycle.CycleId)) do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				Stats_Service:AddCoins(player, stage.BonusCoins)
			end
		end
		Reward_Service.Client.StageReached:FireAll(stageIndex, stage.Name, stage.BonusCoins, cycle.PlantId)
	end
end

---- Harvest

local function onPlantGrown(cycleId, plantId)
	if rewardedCycles[cycleId] then
		return
	end
	rewardedCycles[cycleId] = true
	rewardedCycles[cycleId - 5] = nil

	local rarity = PlantsConfig.GetPlant(plantId) and PlantsConfig.GetPlant(plantId).Rarity
	local harvest = RewardConfig.Harvest
	local baseCoins = harvest.BaseByRarity[rarity] or 0
	-- heavier plants pay more: the pool scales with the weight the plant reached
	local weight = Plant_Service:GetWeight()
	local pool = weight * harvest.PoolPerKg

	Reward_Service.Client.PlantFullyGrown:FireAll(plantId)

	local contributions = Watering_Service:GetContributions(cycleId)
	local totalPoured = 0
	for _, poured in pairs(contributions) do
		totalPoured += poured
	end

	for userId, poured in pairs(contributions) do
		local player = Players:GetPlayerByUserId(userId)
		if player and poured >= WaterConfig.MinWaterForPlantsGrown then
			local share = totalPoured > 0 and poured / totalPoured or 0
			local coins = math.floor(baseCoins + poured * harvest.CoinsPerWater + pool * share)
			Stats_Service:AddCoins(player, coins)
			local plantsGrown = Stats_Service:AddStat(player, "PlantsGrown", 1)
			Reward_Service.Client.PlantHarvested:Fire(player, {
				PlantId = plantId,
				Coins = coins,
				PlantsGrown = plantsGrown,
				Water = math.floor(poured + 0.5),
				Share = share,
				Weight = weight,
			})
		end
	end
end

---- Lifecycle

function Reward_Service:KnitStart()
	Watering_Service = Knit.GetService("Watering_Service")
	PlantCycle_Service = Knit.GetService("PlantCycle_Service")
	Stats_Service = Knit.GetService("Stats_Service")
	Plant_Service = Knit.GetService("Plant_Service")

	Watering_Service.Poured:Connect(onPoured)
	Watering_Service.PourStopped:Connect(function(player)
		payBeat(player, true)
	end)
	PlantCycle_Service.PlantGrown:Connect(onPlantGrown)

	RunService.Heartbeat:Connect(function(dt)
		sinceCheck += dt
		if sinceCheck >= RewardConfig.CheckInterval then
			sinceCheck = 0
			checkGoal()
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		payBeat(player, true) -- settle what the leaving player already earned
		pourState[player] = nil
	end)
end

function Reward_Service:KnitInit() end

return Reward_Service
