--[[
	Read-only helpers for the replicated water state (player attributes + leaderstats).
	Shared by the HUD, the watering can visuals, the arm animation and the water stream.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaterConfig = require(ReplicatedStorage.SharedSource.Datas.WaterConfig)
local PlantsConfig = require(ReplicatedStorage.SharedSource.Datas.PlantsConfig)
local StatsConfig = require(ReplicatedStorage.SharedSource.Datas.StatsConfig)

local ATTR = WaterConfig.Attributes
local strengthDefinition = StatsConfig.ByKey.Strength

local WaterState = {}

function WaterState.GetWater(player)
	return player:GetAttribute(ATTR.Water) or 0
end

--- Watering can capacity, derived from the replicated Strength stat.
function WaterState.GetCapacity(player)
	local leaderstats = player:FindFirstChild(StatsConfig.Folder)
	local value = leaderstats and leaderstats:FindFirstChild(strengthDefinition.DisplayName)
	return StatsConfig.GetCapacity(value and value.Value or strengthDefinition.Default)
end

function WaterState.GetCanId(player)
	return player:GetAttribute(ATTR.Can)
end

function WaterState.IsWatering(player)
	return player:GetAttribute(ATTR.Watering) == true
end

function WaterState.IsFilling(player)
	return player:GetAttribute(ATTR.Filling) == true
end

--- The plant model currently in the world, or nil.
function WaterState.GetPlantModel()
	for _, instance in ipairs(CollectionService:GetTagged(PlantsConfig.PlantTag)) do
		if instance:IsDescendantOf(workspace) then
			return instance
		end
	end
	return nil
end

--- World position the water stream aims at (upper part of the plant), or nil.
function WaterState.GetPlantTarget()
	local model = WaterState.GetPlantModel()
	if not model then
		return nil
	end
	local cframe, size = model:GetBoundingBox()
	return cframe.Position + Vector3.new(0, size.Y * 0.3, 0)
end

return WaterState
