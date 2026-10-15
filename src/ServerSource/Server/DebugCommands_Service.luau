local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Knit = require(ReplicatedStorage.Packages.Knit)

--[[
	Developer chat commands. They only exist in Roblox Studio (RunService:IsStudio()), never in the live game.
		/water [amount]    gives you `amount` water (default 1,000,000), ignoring the can's capacity
		/wateringlevel [n] sets your Watering Speed upgrade to level n (default 10,000), free of charge
]]
local DebugCommands_Service = Knit.CreateService({
	Name = "DebugCommands_Service",
	Client = {},
})

local DEFAULT_WATER = 1000000
local DEFAULT_WATERING_LEVEL = 10000

local Water_Service, Upgrade_Service

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

	createCommand("DebugWaterCommand", "/water", function(player, text)
		local amount = tonumber(text:match("%S+%s+(%S+)")) or DEFAULT_WATER
		Water_Service:DebugSetWater(player, amount)
	end)

	createCommand("DebugWateringLevelCommand", "/wateringlevel", function(player, text)
		local level = tonumber(text:match("%S+%s+(%S+)")) or DEFAULT_WATERING_LEVEL
		Upgrade_Service:DebugSetLevel(player, "WateringSpeed", level)
	end)
end

function DebugCommands_Service:KnitInit() end

return DebugCommands_Service
