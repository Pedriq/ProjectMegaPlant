--[[
	Growth math. Growth points (earned through watering) map to the plant's scale.
	The exponent is < 1, so every additional point makes the plant grow less than the last:
	the plant can grow indefinitely, but more and more slowly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlantsConfig = require(ReplicatedStorage.SharedSource.Datas.PlantsConfig)

local PlantGrowth = {}

--- Size ratio (1 = seedling) after the given points: diminishing returns, no cap.
local function getRatio(points)
	local growth = PlantsConfig.Growth
	return 1 + (math.max(points, 0) * growth.Coefficient) ^ growth.Exponent
end

function PlantGrowth.GetScale(points)
	return PlantsConfig.Growth.SeedlingScale * getRatio(points)
end

--- Abstract weight (kg) of a plant after the given growth points. A fresh plant weighs its base weight and
--- gets heavier as it grows (with the same diminishing returns as its size).
function PlantGrowth.GetWeight(plantId, points)
	return PlantsConfig.GetBaseWeight(plantId) * getRatio(points)
end

return PlantGrowth
