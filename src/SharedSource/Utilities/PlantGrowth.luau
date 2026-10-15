--[[
	Growth math. Growth points (earned through watering) map to the plant's scale.
	The exponent is < 1, so every additional point makes the plant grow less than the last:
	the plant can grow indefinitely, but more and more slowly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BalanceConfig = require(ReplicatedStorage.SharedSource.Datas.BalanceConfig)
local PlantsConfig = require(ReplicatedStorage.SharedSource.Datas.PlantsConfig)

local PlantGrowth = {}

--- Size ratio (1 = seedling) after the given points: diminishing returns, no cap.
local function getRatio(points)
	local growth = PlantsConfig.Growth
	points = math.max(points, 0)
	-- past the water goal growth is slightly slower, but never stops
	local goalPoints = BalanceConfig.PointsAtGoal
	if points > goalPoints then
		points = goalPoints + (points - goalPoints) * growth.SlowdownRate
	end
	return 1 + (points * growth.Coefficient) ^ growth.Exponent
end

--- Growth ratio (1 = seedling) that drives juice and weight. Independent of the visual size boost.
function PlantGrowth.GetSizeRatio(points)
	return getRatio(points)
end

--- Visual scale of the model: the growth part is multiplied by Growth.VisualSizeBoost (the seedling is unchanged).
function PlantGrowth.GetScale(points)
	local growth = PlantsConfig.Growth
	return growth.SeedlingScale * (1 + (getRatio(points) - 1) * growth.VisualSizeBoost)
end

--- Abstract weight (kg) of a plant after the given growth points. A fresh plant weighs its base weight and
--- gets heavier as it grows (with the same diminishing returns as its size).
function PlantGrowth.GetWeight(plantId, points)
	return PlantsConfig.GetBaseWeight(plantId) * getRatio(points)
end

return PlantGrowth
