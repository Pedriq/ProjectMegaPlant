local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local StatsConfig = require(ReplicatedStorage.SharedSource.Datas.StatsConfig)
local TrainingConfig = require(ReplicatedStorage.SharedSource.Datas.TrainingConfig)

local Stats_Service = Knit.CreateService({
	Name = "Stats_Service",
	Client = {},

	-- Fired (player, statKey, newValue, oldValue) after any stat changes
	StatChanged = Signal.new(),
})

local ProfileService -- resolved in KnitStart

local function clamp(definition, value)
	if definition.Min then
		value = math.max(definition.Min, value)
	end
	if definition.Max then
		value = math.min(definition.Max, value)
	end
	if definition.ValueClass == "IntValue" then
		-- IntValue is a 32-bit integer: never let a stat run past it
		value = math.min(math.floor(value + 0.5), 2147483647)
	end
	return value
end

local function getStatsData(player)
	local _, data = ProfileService:GetProfile(player)
	return data and data.Stats
end

---- leaderstats

local function getValueObject(player, definition)
	local folder = player:FindFirstChild(StatsConfig.Folder)
	return folder and folder:FindFirstChild(definition.DisplayName)
end

local function createLeaderstats(player, statsData)
	local folder = player:FindFirstChild(StatsConfig.Folder)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = StatsConfig.Folder
		folder.Parent = player
	end

	for _, definition in ipairs(StatsConfig.Order) do
		local valueObject = folder:FindFirstChild(definition.DisplayName)
		if not valueObject then
			valueObject = Instance.new(definition.ValueClass)
			valueObject.Name = definition.DisplayName
			valueObject.Parent = folder
		end
		valueObject.Value = statsData[definition.Key]
	end
end

---- Movement speed

--- Walk speed comes from the Mobility stat; it is 0 while the player is training.
local function applyMovementSpeed(player)
	local statsData = getStatsData(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and statsData then
		if player:GetAttribute(TrainingConfig.Attribute) then
			humanoid.WalkSpeed = 0
		else
			humanoid.WalkSpeed = StatsConfig.GetWalkSpeed(statsData.Mobility)
		end
	end
end

local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		applyMovementSpeed(player)
	end
end

---- Public API (server only)

--- Returns the stat's current value, or nil if the profile isn't available.
function Stats_Service:GetStat(player, statKey)
	assert(StatsConfig.ByKey[statKey], "Unknown stat: " .. tostring(statKey))
	local statsData = getStatsData(player)
	return statsData and statsData[statKey]
end

--- Sets a stat (clamped to its Min/Max). Returns the stored value, or nil on failure.
function Stats_Service:SetStat(player, statKey, value)
	local definition = StatsConfig.ByKey[statKey]
	assert(definition, "Unknown stat: " .. tostring(statKey))
	if typeof(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		warn(("Stats_Service: invalid value for %s: %s"):format(statKey, tostring(value)))
		return nil
	end

	local statsData = getStatsData(player)
	if not statsData then
		return nil
	end

	local oldValue = statsData[statKey]
	local newValue = clamp(definition, value)
	if newValue == oldValue then
		return newValue
	end

	ProfileService:ChangeData(player, { "Stats", statKey }, newValue)

	local valueObject = getValueObject(player, definition)
	if valueObject then
		valueObject.Value = newValue
	end
	if statKey == "Mobility" then
		applyMovementSpeed(player)
	end

	Stats_Service.StatChanged:Fire(player, statKey, newValue, oldValue)
	return newValue
end

--- Adds (or subtracts, with a negative amount) to a stat. Returns the new value or nil.
function Stats_Service:AddStat(player, statKey, amount)
	if typeof(amount) ~= "number" then
		warn("Stats_Service:AddStat expects a number amount")
		return nil
	end
	local current = Stats_Service:GetStat(player, statKey)
	if current == nil then
		return nil
	end
	return Stats_Service:SetStat(player, statKey, current + amount)
end

function Stats_Service:ResetStat(player, statKey)
	return Stats_Service:SetStat(player, statKey, StatsConfig.ByKey[statKey].Default)
end

function Stats_Service:CanAfford(player, amount)
	local coins = Stats_Service:GetStat(player, "Coins")
	return coins ~= nil and amount >= 0 and coins >= amount
end

--- Removes coins only if the player can afford it. Returns true on success.
function Stats_Service:SpendCoins(player, amount)
	if typeof(amount) ~= "number" or amount ~= amount or amount < 0 then
		return false
	end
	if not Stats_Service:CanAfford(player, amount) then
		return false
	end
	return Stats_Service:AddStat(player, "Coins", -amount) ~= nil
end

function Stats_Service:AddCoins(player, amount)
	return Stats_Service:AddStat(player, "Coins", amount)
end

--- Re-applies the walk speed derived from Mobility (call after changing movement restrictions).
function Stats_Service:ApplyMovementSpeed(player)
	applyMovementSpeed(player)
end

--- Returns a copy of all stats, or nil.
function Stats_Service:GetAllStats(player)
	local statsData = getStatsData(player)
	return statsData and table.clone(statsData)
end

---- Lifecycle

local function setupPlayer(player)
	local _, data = ProfileService:GetProfile(player)
	if not data or not player:IsDescendantOf(Players) then
		return
	end

	-- Clamp stored values in case config limits changed since last save
	for _, definition in ipairs(StatsConfig.Order) do
		local stored = data.Stats[definition.Key]
		data.Stats[definition.Key] = clamp(definition, typeof(stored) == "number" and stored or definition.Default)
	end

	createLeaderstats(player, data.Stats)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

function Stats_Service:KnitStart()
	ProfileService = Knit.GetService("ProfileService")

	ProfileService.ProfileLoaded:Connect(setupPlayer)
	-- Profiles that finished loading before this connection existed
	for player in pairs(ProfileService.Profiles) do
		task.spawn(setupPlayer, player)
	end
end

function Stats_Service:KnitInit() end

return Stats_Service
