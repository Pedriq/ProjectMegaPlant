local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local WaterConfig = require(ReplicatedStorage.SharedSource.Datas.WaterConfig)
local WateringCansConfig = require(ReplicatedStorage.SharedSource.Datas.WateringCansConfig)
local StatsConfig = require(ReplicatedStorage.SharedSource.Datas.StatsConfig)

local ATTR = WaterConfig.Attributes

--[[
	Owns how much water each player carries and which watering can they have equipped.
	The amount lives on the server (float, so slow fills accumulate); the rounded value is
	replicated through the player's `Water` attribute for UI and visuals.
	The maximum is the watering can capacity derived from the player's Strength stat
	(StatsConfig.GetCapacity).
]]
local Water_Service = Knit.CreateService({
	Name = "Water_Service",
	Client = {},

	-- (player, newAmount, oldAmount)
	WaterChanged = Signal.new(),
})

local Stats_Service

local water = {} -- [player] = float

local function publish(player)
	player:SetAttribute(ATTR.Water, math.floor((water[player] or 0) + 0.0001))
end

---- Public API

function Water_Service:GetCapacity(player)
	local strength = Stats_Service and Stats_Service:GetStat(player, "Strength")
	return StatsConfig.GetCapacity(strength or StatsConfig.ByKey.Strength.Default)
end

function Water_Service:GetWater(player)
	return water[player] or 0
end

--- Sets the water amount, clamped to [0, capacity]. Returns the stored value.
function Water_Service:SetWater(player, amount)
	if water[player] == nil or typeof(amount) ~= "number" or amount ~= amount then
		return nil
	end
	local old = water[player]
	local new = math.clamp(amount, 0, Water_Service:GetCapacity(player))
	if new == old then
		return new
	end
	water[player] = new
	publish(player)
	Water_Service.WaterChanged:Fire(player, new, old)
	return new
end

--- Adds water (up to capacity). Returns how much was actually added.
function Water_Service:AddWater(player, amount)
	if typeof(amount) ~= "number" or amount <= 0 then
		return 0
	end
	local old = water[player]
	if old == nil then
		return 0
	end
	return (Water_Service:SetWater(player, old + amount) or old) - old
end

--- Removes water (down to zero). Returns how much was actually removed.
function Water_Service:RemoveWater(player, amount)
	if typeof(amount) ~= "number" or amount <= 0 then
		return 0
	end
	local old = water[player]
	if old == nil then
		return 0
	end
	return old - (Water_Service:SetWater(player, old - amount) or old)
end

function Water_Service:IsFull(player)
	return Water_Service:GetWater(player) >= Water_Service:GetCapacity(player)
end

--- Config of the player's equipped can.
function Water_Service:GetCan(player)
	return WateringCansConfig.Get(player:GetAttribute(ATTR.Can))
end

--- Equips a different watering can (clients swap the model automatically).
function Water_Service:SetCan(player, canId)
	assert(WateringCansConfig.Cans[canId], "Unknown watering can: " .. tostring(canId))
	player:SetAttribute(ATTR.Can, canId)
end

---- Lifecycle

local function onPlayerAdded(player)
	water[player] = 0
	player:SetAttribute(ATTR.Can, WateringCansConfig.Default)
	player:SetAttribute(ATTR.Filling, false)
	player:SetAttribute(ATTR.Watering, false)
	publish(player)
end

function Water_Service:KnitStart()
	Stats_Service = Knit.GetService("Stats_Service")

	-- strength changed: capacity may have changed, never carry more than the new capacity
	Stats_Service.StatChanged:Connect(function(player, statKey)
		if statKey == "Strength" and water[player] then
			Water_Service:SetWater(player, water[player])
		end
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		water[player] = nil
	end)
end

function Water_Service:KnitInit() end

return Water_Service
