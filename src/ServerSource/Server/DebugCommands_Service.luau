local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Knit = require(ReplicatedStorage.Packages.Knit)

--[[
	Developer chat commands. They only exist in Roblox Studio (RunService:IsStudio()), never in the live game.
		/water [amount]    gives you `amount` water (default 1,000,000), ignoring the can's capacity
		/wateringlevel [n] sets your Watering Speed upgrade to level n (default 10,000), free of charge
		/capacity [n]      sets your Strength so your watering can capacity is n (default 300)
]]
local DebugCommands_Service = Knit.CreateService({
	Name = "DebugCommands_Service",
	Client = {},
})

local DEFAULT_WATER = 1000000
local DEFAULT_WATERING_LEVEL = 10000

local DEFAULT_CAPACITY = 300
local MAX_INT_VALUE = 2147483647 -- Strength is an IntValue

local Water_Service, Upgrade_Service, Stats_Service

local function createCommand(name, alias, callback)
	local command = Instance.new("TextChatCommand")
	command.Name = name
	command.PrimaryAlias = alias
	command.Triggered:Connect(function(origin, text)
		local player = Players:GetPlayerByUserId(origin.UserId)
		if player then
			callback(player, text)
		end
	end)
	command.Parent = TextChatService
end

function DebugCommands_Service:KnitStart()
	if not RunService:IsStudio() then
		return
	end
	Water_Service = Knit.GetService("Water_Service")

	Upgrade_Service = Knit.GetService("Upgrade_Service")
	Stats_Service = Knit.GetService("Stats_Service")

	createCommand("DebugWaterCommand", "/water", function(player, text)
		local amount = tonumber(text:match("%S+%s+(%S+)")) or DEFAULT_WATER
		Water_Service:DebugSetWater(player, amount)
	end)

	createCommand("DebugWateringLevelCommand", "/wateringlevel", function(player, text)
		local level = tonumber(text:match("%S+%s+(%S+)")) or DEFAULT_WATERING_LEVEL
		Upgrade_Service:DebugSetLevel(player, "WateringSpeed", level)
	end)

	createCommand("DebugCapacityCommand", "/capacity", function(player, text)
		local capacity = tonumber(text:match("%S+%s+(%S+)")) or DEFAULT_CAPACITY
		-- inverse of StatsConfig.GetCapacity: the Strength needed for `capacity`, rounded up
		local strength = math.ceil(6.034 + 0.0057114874 * math.max(capacity, 1) ^ 3.3601)
		Stats_Service:SetStat(player, "Strength", math.min(strength, MAX_INT_VALUE))
	end)
end

function DebugCommands_Service:KnitInit() end

return DebugCommands_Service
