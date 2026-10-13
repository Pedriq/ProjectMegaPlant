local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local WaterConfig = require(ReplicatedStorage.SharedSource.Datas.WaterConfig)
local PlantsConfig = require(ReplicatedStorage.SharedSource.Datas.PlantsConfig)
local HoldSessions = require(ServerScriptService.ServerSource.Utilities.HoldSessions)
local PlantGoal = require(ServerScriptService.ServerSource.Utilities.PlantGoal)

local ATTR = WaterConfig.Attributes

--[[
	Watering the plant. A hold-to-water ProximityPrompt sits on Workspace/Garden/PlantBed.
	While held, water is taken from the player at the can's PourRate and converted into growth
	points for the current plant:
		points = water * PlantsConfig.Growth.PointsPerWater * plant growth multiplier (rarity/plant)
	Plant_Service turns points into size with diminishing returns (bigger = slower growth).
	Watering is only possible while the plant is in the Growing phase.
]]
local Watering_Service = Knit.CreateService({
	Name = "Watering_Service",
	Client = {
		-- (cycleId, totalWater) to everyone, only when the rounded total changed
		TotalWaterChanged = Knit.CreateSignal(),
		-- (cycleId, yourWater) only to the player it belongs to, only when it changed
		ContributionChanged = Knit.CreateSignal(),
	},

	-- (player, amountPoured, dt, cycleState) every frame a player pours; rewards hook in here
	Poured = Signal.new(),
	-- (player) when a player stops pouring
	PourStopped = Signal.new(),
})

local Water_Service, Plant_Service, PlantCycle_Service, Upgrade_Service

local sessions = HoldSessions.new()
local prompt, bedPart
local pendingPoints = 0
local sinceFlush = 0
local contributions = {} -- [cycleId] = { [userId] = water poured }
local names = {} -- [userId] = username, remembered so the leaderboard can name players who already left
local cycleTotals = {} -- [cycleId] = total water poured by everyone

-- replication bookkeeping (see broadcastTotals)
local sinceBroadcast = 0
local dirtyTotal = false
local dirtyPlayers = {} -- [player] = true
local lastSentTotal = 0
local lastSentMine = {} -- [player] = number

local function round(value)
	return math.floor(value + 0.5)
end

local function getAnchorPart(instance)
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function canWater()
	local state = PlantCycle_Service:GetState()
	return state.Phase == "Growing" and Plant_Service:GetPlant() ~= nil
end

local function isInRange(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or not bedPart then
		return false
	end
	local maxDistance = WaterConfig.PlantPrompt.MaxActivationDistance + WaterConfig.DistanceTolerance
	return (root.Position - bedPart.Position).Magnitude <= maxDistance
end

local function flushGrowth()
	if pendingPoints > 0 then
		local points = pendingPoints
		pendingPoints = 0
		Plant_Service:AddGrowth(points)
	end
end

local function startWatering(player)
	if not canWater() or not isInRange(player) or Water_Service:GetWater(player) <= 0 then
		return
	end

	local can = Water_Service:GetCan(player)

	player:SetAttribute(ATTR.Watering, true)
	sessions:Start(player, function(dt)
		if not canWater() or not isInRange(player) then
			return false
		end

		local state = PlantCycle_Service:GetState()
		local plantId = state.PlantId
		-- the Watering Speed upgrade is read every tick, so a purchase applies immediately
		local pourRate = can.PourRate * Upgrade_Service:GetMultiplier(player, "PourSpeed")
		local poured = Water_Service:RemoveWater(player, pourRate * dt)
		if poured > 0 then
			pendingPoints += poured
				* PlantsConfig.Growth.PointsPerWater
				* PlantsConfig.GetGrowthMultiplier(plantId, PlantGoal.GetGoal(plantId, state.CycleId))

			local cycle = contributions[state.CycleId]
			if not cycle then
				cycle = {}
				contributions[state.CycleId] = cycle
			end
			cycle[player.UserId] = (cycle[player.UserId] or 0) + poured
			names[player.UserId] = player.Name
			cycleTotals[state.CycleId] = (cycleTotals[state.CycleId] or 0) + poured
			dirtyTotal = true
			dirtyPlayers[player] = true
			Watering_Service.Poured:Fire(player, poured, dt, state)
		end

		return Water_Service:GetWater(player) > 0
	end, function()
		player:SetAttribute(ATTR.Watering, false)
		Watering_Service.PourStopped:Fire(player)
	end)
end

---- Public API

--- Total water the player poured on the plant during a cycle (for the future reward system).
function Watering_Service:GetContribution(cycleId, player)
	local cycle = contributions[cycleId]
	return cycle and cycle[player.UserId] or 0
end

--- Username of a player who poured water (also after they left).
function Watering_Service:GetName(userId)
	return names[userId]
end

function Watering_Service:GetContributions(cycleId)
	return contributions[cycleId] and table.clone(contributions[cycleId]) or {}
end

--- Total water poured by everyone into the plant of a cycle.
function Watering_Service:GetTotalWater(cycleId)
	return cycleTotals[cycleId] or 0
end

--- Current totals for a joining client (later changes arrive through the signals).
function Watering_Service.Client:GetWaterTotals(player)
	local cycleId = PlantCycle_Service:GetState().CycleId
	return {
		CycleId = cycleId,
		Total = round(Watering_Service:GetTotalWater(cycleId)),
		Mine = round(Watering_Service:GetContribution(cycleId, player)),
	}
end

--- Sends changed totals. One broadcast message for the shared total, plus one small message only to
--- each player whose own contribution changed (players who aren't watering cost nothing).
local function broadcastTotals()
	local cycleId = PlantCycle_Service:GetState().CycleId

	if dirtyTotal then
		dirtyTotal = false
		local total = round(Watering_Service:GetTotalWater(cycleId))
		if total ~= lastSentTotal then
			lastSentTotal = total
			Watering_Service.Client.TotalWaterChanged:FireAll(cycleId, total)
		end
	end

	for player in pairs(dirtyPlayers) do
		dirtyPlayers[player] = nil
		if player.Parent then
			local mine = round(Watering_Service:GetContribution(cycleId, player))
			if mine ~= lastSentMine[player] then
				lastSentMine[player] = mine
				Watering_Service.Client.ContributionChanged:Fire(player, cycleId, mine)
			end
		end
	end
end

---- Lifecycle

local function setupPrompt()
	local instance = workspace
	for _, name in ipairs(WaterConfig.PlantPrompt.Path) do
		instance = instance and instance:WaitForChild(name, 30)
	end
	bedPart = instance and getAnchorPart(instance)
	if not bedPart then
		warn("Watering_Service: plant bed not found: Workspace/" .. table.concat(WaterConfig.PlantPrompt.Path, "/"))
		return
	end

	prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WaterPlantPrompt"
	prompt.ObjectText = WaterConfig.PlantPrompt.ObjectText
	prompt.ActionText = WaterConfig.PlantPrompt.ActionText
	prompt.HoldDuration = WaterConfig.Prompt.HoldDuration
	prompt.KeyboardKeyCode = WaterConfig.Prompt.KeyboardKeyCode
	prompt.GamepadKeyCode = WaterConfig.Prompt.GamepadKeyCode
	prompt.RequiresLineOfSight = WaterConfig.Prompt.RequiresLineOfSight
	prompt.MaxActivationDistance = WaterConfig.PlantPrompt.MaxActivationDistance
	prompt.Enabled = canWater()
	prompt.Parent = bedPart

	prompt.PromptButtonHoldBegan:Connect(startWatering)
	prompt.PromptButtonHoldEnded:Connect(function(player)
		sessions:Stop(player)
	end)
end

function Watering_Service:KnitStart()
	Water_Service = Knit.GetService("Water_Service")
	Plant_Service = Knit.GetService("Plant_Service")
	PlantCycle_Service = Knit.GetService("PlantCycle_Service")
	Upgrade_Service = Knit.GetService("Upgrade_Service")


	-- apply accumulated growth in batches instead of once per player per frame
	game:GetService("RunService").Heartbeat:Connect(function(dt)
		sinceFlush += dt
		if sinceFlush >= WaterConfig.GrowthFlushInterval then
			sinceFlush = 0
			flushGrowth()
		end

		sinceBroadcast += dt
		if sinceBroadcast >= WaterConfig.StatsBroadcastInterval then
			sinceBroadcast = 0
			broadcastTotals()
		end
	end)

	PlantCycle_Service.PhaseChanged:Connect(function(state)
		if state.Phase ~= "Growing" then
			sessions:StopAll()
			flushGrowth()
		end
		pendingPoints = state.Phase == "Selecting" and 0 or pendingPoints
		if state.Phase == "Selecting" then
			-- new plant: totals start from zero (clients reset themselves on the same phase change)
			lastSentTotal = 0
			table.clear(lastSentMine)
			table.clear(dirtyPlayers)
			dirtyTotal = false
			-- keep only the last few cycles of contribution data
			contributions[state.CycleId - 3] = nil
			cycleTotals[state.CycleId - 3] = nil
		end
		if prompt then
			prompt.Enabled = state.Phase == "Growing"
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		sessions:Stop(player)
		dirtyPlayers[player] = nil
		lastSentMine[player] = nil
	end)

	task.spawn(setupPrompt)
end

function Watering_Service:KnitInit() end

return Watering_Service
