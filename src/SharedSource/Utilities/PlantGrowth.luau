--[[
	Growth math. Growth points (earned through watering) map to the plant's scale.
	The exponent is < 1, so every additional point makes the plant grow less than the last:
	the plant can grow indefinitely, but more and more slowly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlantsConfig = require(ReplicatedStorage.SharedSource.Datas.PlantsConfig)

local PlantGrowth = {}

function PlantGrowth.GetScale(points)
	local growth = PlantsConfig.Growth
	return growth.SeedlingScale * (1 + (math.max(points, 0) * growth.Coefficient) ^ growth.Exponent)
end

return PlantGrowth
