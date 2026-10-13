local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Vide = require(ReplicatedStorage.Packages.Vide)

--[[
	Client mirror of the server's growing cycle.
		State        Vide source holding the latest cycle state
		StateChanged Signal fired (state) on every phase change
	State = { Phase, CycleId, PlantId, PhaseStart, PhaseEnd } (times are server timestamps)
]]
local PlantCycle_Controller = Knit.CreateController({
	Name = "PlantCycle_Controller",
})

PlantCycle_Controller.State = Vide.source({
	Phase = "Idle",
	CycleId = 0,
	PlantId = nil,
	PhaseStart = 0,
	PhaseEnd = 0,
})
PlantCycle_Controller.StateChanged = Signal.new()

local function apply(newState)
	if not newState then
		return
	end
	local current = PlantCycle_Controller.State()
	-- ignore stale snapshots (e.g. a slow GetState reply arriving after a newer signal)
	if newState.PhaseStart < current.PhaseStart then
		return
	end
	if newState.PhaseStart == current.PhaseStart and newState.Phase == current.Phase then
		return
	end
	PlantCycle_Controller.State(newState)
	PlantCycle_Controller.StateChanged:Fire(newState)
end

function PlantCycle_Controller:KnitStart()
	local service = Knit.GetService("PlantCycle_Service")
	service.StateChanged:Connect(apply)
	service:GetState():andThen(apply):catch(warn)
end

function PlantCycle_Controller:KnitInit() end

return PlantCycle_Controller
