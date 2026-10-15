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

--- Visual growth (0 = seedling) of the model: strictly proportional to the points up to the full-growth point
--- (BalanceConfig.PointsAtGoal = 175,000 water), reaching Growth.VisualGrowthAtFull there. Beyond it the slope
--- starts at SlowdownRate of the proportional slope and keeps shrinking (logarithmic), but never reaches zero.
local function getVisualGrowth(points)
	local growth = PlantsConfig.Growth
	points = math.max(points, 0)
	local fullPoints = BalanceConfig.PointsAtGoal
	local slope = growth.VisualGrowthAtFull / fullPoints
	if points <= fullPoints then
		return slope * points
	end
	local excess = points - fullPoints
	-- slope(excess) = slope * SlowdownRate * (1 + excess / fullPoints) ^ -TailDecay: a gentle, endless decay
	local keep = 1 - growth.TailDecay
	return growth.VisualGrowthAtFull
		+ slope * growth.SlowdownRate * fullPoints * ((1 + excess / fullPoints) ^ keep - 1) / keep
end

--- Visual scale of the model (the seedling has SeedlingScale).
function PlantGrowth.GetScale(points)
	return PlantsConfig.Growth.SeedlingScale * (1 + getVisualGrowth(points))
end

--- Abstract weight (kg) of a plant after the given growth points. A fresh plant weighs its base weight and
--- gets heavier as it grows (with the same diminishing returns as its size).
function PlantGrowth.GetWeight(plantId, points)
	return PlantsConfig.GetBaseWeight(plantId) * getRatio(points)
end

return PlantGrowth
