local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ProfileTemplate = require(ReplicatedStorage.SharedSource.Datas.ProfileTemplate)
local StatsConfig = require(ReplicatedStorage.SharedSource.Datas.StatsConfig)
local UpgradesConfig = require(ReplicatedStorage.SharedSource.Datas.UpgradesConfig)
local WaterConfig = require(ReplicatedStorage.SharedSource.Datas.WaterConfig)

--[[
	Developer chat commands. They only exist in Roblox Studio (RunService:IsStudio()), never in the live game.
		/water [amount]    gives you `amount` water (default 1,000,000), ignoring the can's capacity
		/wateringlevel [n] sets your Watering Speed upgrade to level n (default 10,000), free of charge
		/capacity [n]      sets your Strength so your watering can capacity is n (default 300)
		/tutorial          restarts the first-time tutorial from step 1
		/resetdata         wipes YOUR saved data back to a new player (stats, upgrades, tutorial). Studio saves to the
		                   real DataStore, so this resets your real profile too. Rejoin afterwards.
	The last two also work WITHOUT chat (it is blocked in some regions) through DebugKeys_Controller:
		F6 = /tutorial,  Shift+F7 = /resetdata
]]
local DebugCommands_Service = Knit.CreateService({
	Name = "DebugCommands_Service",
	Client = {},
})

local DEFAULT_WATER = 1000000
local DEFAULT_WATERING_LEVEL = 10000

local DEFAULT_CAPACITY = 300
local MAX_INT_VALUE = 2147483647 -- Strength is an IntValue

local Water_Service, Upgrade_Service, Stats_Service, Tutorial_Service, ProfileService

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in pairs(value) do
		copy[key] = deepCopy(inner)
	end
	return copy
end

--- Puts the player's saved data (and the live values built from it) back to a brand new player's.
local function resetData(player)
	local _, data = ProfileService:GetProfile(player)
	if not data then
		return
	end
	for key, value in pairs(ProfileTemplate) do
		data[key] = deepCopy(value)
	end
	-- the profile already holds the defaults, so SetStat would see "no change": write the leaderstats directly
	local leaderstats = player:FindFirstChild(StatsConfig.Folder)
	for statKey, default in pairs(ProfileTemplate.Stats) do
		local definition = StatsConfig.ByKey[statKey]
		local valueObject = leaderstats and definition and leaderstats:FindFirstChild(definition.DisplayName)
		if valueObject then
			valueObject.Value = default
		end
	end
	Stats_Service:ApplyMovementSpeed(player)
	for _, upgradeId in ipairs(UpgradesConfig.Order) do
		player:SetAttribute(UpgradesConfig.GetAttributeName(upgradeId), 0)
	end
	player:SetAttribute(WaterConfig.Attributes.Water, 0)
	Tutorial_Service:Restart(player)
end

-- commands that can also be run from the client (DebugKeys_Controller), by name
local handlers = {
	Tutorial = function(player)
		Tutorial_Service:Restart(player)
	end,
	ResetData = resetData,
}

--- Studio only: the client asks for one of `handlers`. Anything else (or any call outside Studio) is refused.
function DebugCommands_Service.Client:RunCommand(player, name)
	if not RunService:IsStudio() then
		return false
	end
	local handler = type(name) == "string" and handlers[name]
	if not handler then
		return false
	end
	handler(player)
	return true
end

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
	Tutorial_Service = Knit.GetService("Tutorial_Service")
	ProfileService = Knit.GetService("ProfileService")

	createCommand("DebugWaterCommand", "/water", function(player, text)
		local amount = tonumber(text:match("%S+%s+(%S+)")) or DEFAULT_WATER
		Water_Service:DebugSetWater(player, amount)
	end)

	createCommand("DebugWateringLevelCommand", "/wateringlevel", function(player, text)
		local level = tonumber(text:match("%S+%s+(%S+)")) or DEFAULT_WATERING_LEVEL
		Upgrade_Service:DebugSetLevel(player, "WateringSpeed", level)
	end)

	createCommand("DebugTutorialCommand", "/tutorial", handlers.Tutorial)
	createCommand("DebugResetDataCommand", "/resetdata", handlers.ResetData)

	createCommand("DebugCapacityCommand", "/capacity", function(player, text)
		local capacity = tonumber(text:match("%S+%s+(%S+)")) or DEFAULT_CAPACITY
		-- inverse of StatsConfig.GetCapacity: the Strength needed for `capacity`, rounded up
		local strength = math.ceil(6.034 + 0.0057114874 * math.max(capacity, 1) ^ 3.3601)
		Stats_Service:SetStat(player, "Strength", math.min(strength, MAX_INT_VALUE))
	end)
end

function DebugCommands_Service:KnitInit() end

return DebugCommands_Service
