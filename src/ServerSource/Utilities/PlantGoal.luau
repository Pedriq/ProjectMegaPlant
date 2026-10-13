local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BalanceConfig = require(ReplicatedStorage.SharedSource.Datas.BalanceConfig)
local PlantsConfig = require(ReplicatedStorage.SharedSource.Datas.PlantsConfig)

--[[
	The water goal of one specific plant cycle. The goal in PlantsConfig is made for a full server (100
	players); here it is scaled once, when the cycle first asks for it (= when the plant starts growing):

	  population factor = clamp(players / Reference.Players, Population.Min, 1)
	  difficulty        = Difficulty.EarlyFactor for the first plant of the server, up to 1 after RampCycles plants
	  goal              = full-server goal * population * difficulty

	The factors are locked per cycle, so the goal can't move while a plant is growing (players joining or
	leaving mid-plant don't change the numbers every client and service agree on).
]]
local PlantGoal = {}

local cache = {} -- [cycleId] = { Population, Difficulty, Players }

local function getEntry(cycleId)
	local entry = cache[cycleId]
	if not entry then
		local reference = BalanceConfig.Reference
		local players = math.max(#Players:GetPlayers(), 1)
		local difficultyConfig = BalanceConfig.Difficulty
		local ramp = math.clamp((cycleId - 1) / math.max(difficultyConfig.RampCycles, 1), 0, 1)
		entry = {
			Players = players,
			Population = math.clamp(players / reference.Players, BalanceConfig.Population.Min, 1),
			Difficulty = difficultyConfig.EarlyFactor + (1 - difficultyConfig.EarlyFactor) * ramp,
		}
		cache[cycleId] = entry
		cache[cycleId - 4] = nil -- only the last few cycles are needed
	end
	return entry
end

--- Total water (all players) that fully boosts this plant in this cycle.
function PlantGoal.GetGoal(plantId, cycleId)
	local entry = getEntry(cycleId)
	return math.max(math.floor(PlantsConfig.GetWaterGoal(plantId) * entry.Population * entry.Difficulty + 0.5), 1)
end

--- The most water one player counts for towards the boost / stages in this cycle.
function PlantGoal.GetPlayerCap(plantId, cycleId)
	local entry = getEntry(cycleId)
	local goal = PlantGoal.GetGoal(plantId, cycleId)
	local goalConfig = BalanceConfig.Goal
	return goal * math.max(goalConfig.PlayerCapFraction, goalConfig.CapShare / entry.Players)
end

--- 0.1-1: how full the server was when the plant started (scales the harvest pool).
function PlantGoal.GetPopulation(cycleId)
	return getEntry(cycleId).Population
end

return PlantGoal
