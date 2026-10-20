local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local TutorialConfig = require(ReplicatedStorage.SharedSource.Datas.TutorialConfig)
local UpgradesConfig = require(ReplicatedStorage.SharedSource.Datas.UpgradesConfig)
local WaterConfig = require(ReplicatedStorage.SharedSource.Datas.WaterConfig)

--[[
	The first-time tutorial (see TutorialConfig). The server alone decides when a step is done, from what the
	player really does (water level, pouring, coins, upgrades, training), so it cannot be skipped or faked.

	State lives in the profile (Tutorial = { Step, Done }) and is replicated to the client through two player
	attributes (TutorialConfig.StepAttribute / ProgressAttribute); Tutorial_Controller only draws them.
]]
local Tutorial_Service = Knit.CreateService({
	Name = "Tutorial_Service",
	Client = {},
})

local STEPS = TutorialConfig.Steps
local STEP_ATTR = TutorialConfig.StepAttribute
local PROGRESS_ATTR = TutorialConfig.ProgressAttribute

local ProfileService, Stats_Service, Water_Service, Watering_Service, Upgrade_Service, Notification_Service

local state = {} -- [player] = { Step, Poured, UpgradeBought }
local connected = {} -- [player] = true once their attribute listeners exist

---- Helpers

local function getData(player)
	local _, data = ProfileService:GetProfile(player)
	return data
end

local function save(player, step, done)
	local data = getData(player)
	if not (data and data.Tutorial) then
		return
	end
	ProfileService:ChangeData(player, { "Tutorial", "Step" }, step)
	ProfileService:ChangeData(player, { "Tutorial", "Done" }, done)
end

local function setProgress(player, progress)
	progress = math.floor(math.clamp(progress, 0, 1) * 100 + 0.5) / 100
	if player:GetAttribute(PROGRESS_ATTR) ~= progress then
		player:SetAttribute(PROGRESS_ATTR, progress)
	end
end

--- 0..1: how far the player is in `step`. 1 completes it.
local function progressOf(player, step, s)
	local kind = step.Kind
	if kind == "FillCan" then
		if Water_Service:IsFull(player) then
			return 1
		end
		return Water_Service:GetWater(player) / math.max(Water_Service:GetCapacity(player), 1)
	elseif kind == "Pour" then
		return s.Poured / step.Amount
	elseif kind == "Coins" then
		return (Stats_Service:GetStat(player, "Coins") or 0) / step.Amount
	elseif kind == "Upgrade" then
		return s.UpgradeBought and 1 or 0
	elseif kind == "Capacity" then
		return Water_Service:GetCapacity(player) / step.Amount
	end
	return 0
end

local evaluate

local function finish(player, silent)
	state[player] = nil
	player:SetAttribute(STEP_ATTR, 0)
	player:SetAttribute(PROGRESS_ATTR, 1)
	save(player, #STEPS + 1, true)
	if not silent then
		Notification_Service:Notify(player, "TutorialDone")
	end
end

local function enterStep(player, index)
	if index > #STEPS then
		finish(player, false)
		return
	end
	local s = state[player]
	s.Step, s.Poured, s.UpgradeBought = index, 0, false
	player:SetAttribute(STEP_ATTR, index)
	setProgress(player, 0)
	save(player, index, false)

	local step = STEPS[index]
	if step.Gift then
		-- make the shop step always possible: top the player up to the price of the first upgrade
		local missing = UpgradesConfig.GetPrice(nil, 0) - (Stats_Service:GetStat(player, "Coins") or 0)
		if missing > 0 then
			Stats_Service:AddCoins(player, missing)
		end
	end
	evaluate(player)
end

--- Updates the progress of the current step and moves on when it is complete.
function evaluate(player)
	local s = state[player]
	if not s then
		return
	end
	local step = STEPS[s.Step]
	local progress = progressOf(player, step, s)
	if progress < 0.995 then -- a hair under 1 counts (poured water is a float)
		setProgress(player, progress)
		return
	end
	setProgress(player, 1)
	local nextStep = STEPS[s.Step + 1]
	if nextStep then
		Notification_Service:Notify(player, "TutorialStep", { Next = nextStep.Title })
	end
	enterStep(player, s.Step + 1)
end

---- Players

local function hasProgress(player, data)
	if (data.Stats and (data.Stats.PlantsGrown or 0) > 0) then
		return true
	end
	for _, level in pairs(data.Upgrades or {}) do
		if type(level) == "number" and level > 0 then
			return true
		end
	end
	return false
end

--- Re-checks the current step whenever the player's water level changes.
local function connectPlayer(player)
	if connected[player] then
		return
	end
	connected[player] = true
	player:GetAttributeChangedSignal(WaterConfig.Attributes.Water):Connect(function()
		evaluate(player)
	end)
end

local function setupPlayer(player)
	if state[player] then
		return
	end
	connectPlayer(player)
	local data = getData(player)
	if not (data and data.Tutorial) then
		return
	end
	if data.Tutorial.Done or hasProgress(player, data) then
		-- finished, or a player who already knows the game
		player:SetAttribute(STEP_ATTR, 0)
		if not data.Tutorial.Done then
			save(player, #STEPS + 1, true)
		end
		return
	end
	state[player] = { Step = 1, Poured = 0, UpgradeBought = false }
	enterStep(player, math.clamp(data.Tutorial.Step or 1, 1, #STEPS))
end

---- Public API

--- True while the player is still in the tutorial.
function Tutorial_Service:IsActive(player)
	return state[player] ~= nil
end

--- DEBUG: restarts the tutorial from the first step (see DebugCommands_Service).
function Tutorial_Service:Restart(player)
	connectPlayer(player)
	state[player] = state[player] or { Step = 1, Poured = 0, UpgradeBought = false }
	enterStep(player, 1)
end

---- Lifecycle

function Tutorial_Service:KnitStart()
	ProfileService = Knit.GetService("ProfileService")
	Stats_Service = Knit.GetService("Stats_Service")
	Water_Service = Knit.GetService("Water_Service")
	Watering_Service = Knit.GetService("Watering_Service")
	Upgrade_Service = Knit.GetService("Upgrade_Service")
	Notification_Service = Knit.GetService("Notification_Service")

	ProfileService.ProfileLoaded:Connect(setupPlayer)
	for player in pairs(ProfileService.Profiles) do
		task.spawn(setupPlayer, player)
	end

	Watering_Service.Poured:Connect(function(player, amount)
		local s = state[player]
		if s and STEPS[s.Step].Kind == "Pour" then
			s.Poured += amount
			evaluate(player)
		end
	end)

	Stats_Service.StatChanged:Connect(function(player, statKey)
		-- coins for the earn step, Strength because it sets the can's capacity
		if statKey == "Coins" or statKey == "Strength" then
			evaluate(player)
		end
	end)

	Upgrade_Service.UpgradeChanged:Connect(function(player)
		local s = state[player]
		if s and STEPS[s.Step].Kind == "Upgrade" then
			s.UpgradeBought = true
			evaluate(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		state[player] = nil
		connected[player] = nil
	end)
end

function Tutorial_Service:KnitInit() end

return Tutorial_Service
