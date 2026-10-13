local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local PlantsConfig = require(ReplicatedStorage.SharedSource.Datas.PlantsConfig)
local PlantSelector = require(ReplicatedStorage.SharedSource.Utilities.PlantSelector)

--[[
	The growing cycle:
		Selecting -> Growing -> Finished -> (next plant) Selecting -> ...

	Selecting: plant is rolled on the server, clients play the carousel animation.
	Growing:   plant is on the PlantBed until its (rarity based) grow time ends.
	Finished:  fully grown; a reward will be granted here later (see PlantGrown).
	           After Cycle.FinishedDuration a new plant is selected.

	All times are Workspace:GetServerTimeNow() timestamps, so clients can render
	countdowns without extra network traffic.
]]
local PlantCycle_Service = Knit.CreateService({
	Name = "PlantCycle_Service",
	Client = {
		-- (state) fired to everyone whenever the phase changes
		StateChanged = Knit.CreateSignal(),
	},

	-- (state) server-side hook for other services
	PhaseChanged = Signal.new(),
	-- (cycleId, plantId) the timer expired; hook the reward system here later
	PlantGrown = Signal.new(),
})

local Plant_Service

local random = Random.new()
local skipRequested = false

local state = {
	Phase = "Idle", -- Idle | Selecting | Growing | Finished
	CycleId = 0,
	PlantId = nil,
	PhaseStart = 0,
	PhaseEnd = 0,
}

local function beginPhase(phase, plantId, duration)
	local now = workspace:GetServerTimeNow()
	state = {
		Phase = phase,
		CycleId = state.CycleId + (phase == "Selecting" and 1 or 0),
		PlantId = plantId,
		PhaseStart = now,
		PhaseEnd = now + duration,
	}
	PlantCycle_Service.PhaseChanged:Fire(state)
	PlantCycle_Service.Client.StateChanged:FireAll(state)
end

local function waitForPhaseEnd()
	while workspace:GetServerTimeNow() < state.PhaseEnd and not skipRequested do
		task.wait(0.1)
	end
	skipRequested = false
end

local function runCycle()
	local selection = PlantsConfig.Selection

	-- 1. Selecting
	local plantId = PlantSelector.Roll(random)
	Plant_Service:Clear()
	beginPhase("Selecting", plantId, selection.ScrollTime + selection.RevealTime)
	waitForPhaseEnd()

	-- 2. Growing
	Plant_Service:Spawn(plantId)
	beginPhase("Growing", plantId, PlantsConfig.GetGrowTime(plantId))
	waitForPhaseEnd()

	-- 3. Finished (reward hook)
	beginPhase("Finished", plantId, PlantsConfig.Cycle.FinishedDuration)
	PlantCycle_Service.PlantGrown:Fire(state.CycleId, plantId)
	waitForPhaseEnd()

	Plant_Service:Clear()
end

---- Public API

function PlantCycle_Service:GetState()
	return state
end

--- Testing helper: jumps to the end of the current phase.
function PlantCycle_Service:ForceNextPhase()
	skipRequested = true
end

function PlantCycle_Service.Client:GetState()
	return state
end

function PlantCycle_Service:KnitStart()
	Plant_Service = Knit.GetService("Plant_Service")

	task.spawn(function()
		if #Players:GetPlayers() == 0 then
			Players.PlayerAdded:Wait()
		end
		task.wait(PlantsConfig.Cycle.FirstCycleDelay)

		while true do
			local ok, err = pcall(runCycle)
			if not ok then
				warn("PlantCycle_Service: cycle failed: " .. tostring(err))
				skipRequested = false
				task.wait(2)
			end
		end
	end)
end

function PlantCycle_Service:KnitInit() end

return PlantCycle_Service
