local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Vide = require(ReplicatedStorage.Packages.Vide)

--[[
	Client mirror of the water poured into the current plant (server-authoritative).
		Total  Vide source: water poured by all players this cycle
		Mine   Vide source: water poured by this player this cycle
	Both are reset when a new plant is being selected. Messages carry the cycle id, so stale
	messages from an older plant (or a slow initial request) can never overwrite newer data.
]]
local WaterTotals_Controller = Knit.CreateController({
	Name = "WaterTotals_Controller",
})

WaterTotals_Controller.Total = Vide.source(0)
WaterTotals_Controller.Mine = Vide.source(0)

local currentCycle = 0

--- Switches to `cycleId` (resetting values when it's newer). Returns false for stale data.
local function enterCycle(cycleId)
	if cycleId < currentCycle then
		return false
	end
	if cycleId > currentCycle then
		currentCycle = cycleId
		WaterTotals_Controller.Total(0)
		WaterTotals_Controller.Mine(0)
	end
	return true
end

function WaterTotals_Controller:KnitStart()
	local watering = Knit.GetService("Watering_Service")
	local cycle = Knit.GetController("PlantCycle_Controller")

	-- new plant selected: everything starts from zero again
	cycle.StateChanged:Connect(function(state)
		if state.Phase == "Selecting" then
			enterCycle(state.CycleId)
		end
	end)

	watering.TotalWaterChanged:Connect(function(cycleId, total)
		if enterCycle(cycleId) then
			-- the total only grows within a cycle; ignore out-of-order values
			WaterTotals_Controller.Total(math.max(WaterTotals_Controller.Total(), total))
		end
	end)

	watering.ContributionChanged:Connect(function(cycleId, mine)
		if enterCycle(cycleId) then
			WaterTotals_Controller.Mine(math.max(WaterTotals_Controller.Mine(), mine))
		end
	end)

	-- values for a player who joins mid-cycle
	watering:GetWaterTotals():andThen(function(totals)
		if enterCycle(totals.CycleId) then
			WaterTotals_Controller.Total(math.max(WaterTotals_Controller.Total(), totals.Total))
			WaterTotals_Controller.Mine(math.max(WaterTotals_Controller.Mine(), totals.Mine))
		end
	end):catch(warn)
end

function WaterTotals_Controller:KnitInit() end

return WaterTotals_Controller
