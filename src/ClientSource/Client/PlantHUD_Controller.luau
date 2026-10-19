local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Vide = require(ReplicatedStorage.Packages.Vide)
local PlantsConfig = require(ReplicatedStorage.SharedSource.Datas.PlantsConfig)
local WaterConfig = require(ReplicatedStorage.SharedSource.Datas.WaterConfig)
local SagePlantHUD = require(ReplicatedStorage.ClientSource.UI.SagePlantHUD)
local Anim = require(ReplicatedStorage.ClientSource.UI.Anim)

local source = Vide.source

local PlantHUD_Controller = Knit.CreateController({
	Name = "PlantHUD_Controller",
})

local player = Players.LocalPlayer
local PlantCycle_Controller


local function formatCount(value)
	local text = tostring(math.floor(value + 0.5))
	return (text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function PlantHUD(cycle, now, shimmer, popTarget, totals, shake, plantWeight)
	local popScale = Vide.spring(popTarget, 0.35, 0.5)

	-- water numbers count up smoothly instead of jumping
	local totalWater = Vide.spring(function()
		return totals.Total()
	end, 0.3, 1)
	local myWater = Vide.spring(function()
		return totals.Mine()
	end, 0.3, 1)

	-- the weight eases to its new value like the water numbers
	local shownWeight = Vide.spring(function()
		return plantWeight()
	end, 0.3, 1)

	local function plantId()
		return cycle().PlantId
	end

	local function isSelecting()
		return cycle().Phase == "Selecting"
	end

	local function rarity()
		local id = plantId()
		return id and PlantsConfig.GetRarity(id)
	end

	-- test value: elapsed fraction of the grow time (no watering yet)
	local function rawProgress()
		local s = cycle()
		if s.Phase == "Growing" then
			return math.clamp((now() - s.PhaseStart) / math.max(s.PhaseEnd - s.PhaseStart, 0.001), 0, 1)
		elseif s.Phase == "Finished" then
			return 1
		end
		return 0
	end
	local progress = Vide.spring(rawProgress, 0.35, 1)

	local function timerText()
		local s = cycle()
		if s.Phase == "Growing" then
			return Anim.FormatTime(s.PhaseEnd - now())
		elseif s.Phase == "Finished" then
			return "Grown! Next plant in " .. Anim.FormatTime(s.PhaseEnd - now())
		elseif s.Phase == "Selecting" then
			return "Choosing a plant..."
		end
		return "Waiting for plants..."
	end

	return SagePlantHUD({
		PopScale = popScale,
		PlantId = plantId,
		IsSelecting = isSelecting,
		IsGrowing = function() return cycle().Phase == "Growing" end,
		IsFinished = function() return cycle().Phase == "Finished" end,
		Rarity = rarity,
		PlantName = function()
			if isSelecting() or not plantId() then return "???" end
			return PlantsConfig.GetDisplayName(plantId())
		end,
		TimerText = timerText,
		Progress = progress,
		Shimmer = shimmer,
		Shake = shake,
		TotalWater = function() return formatCount(totalWater()) end,
		MyWater = function() return formatCount(myWater()) end,
		Weight = function()
			local weight = shownWeight()
			return weight > 0 and ("%.1f kg"):format(weight) or "-"
		end,
	})
end

function PlantHUD_Controller:KnitStart()
	PlantCycle_Controller = Knit.GetController("PlantCycle_Controller")
	local cycle = PlantCycle_Controller.State
	local totals = Knit.GetController("WaterTotals_Controller")

	local now = source(workspace:GetServerTimeNow())
	local shimmer = source(-1)
	local popTarget = source(1)

	-- The progress bar shakes and shimmers ONLY while the local player is pouring water on the plant;
	-- otherwise it is perfectly still.
	local shake = { Offset = source(Vector2.zero), Rotation = source(0) }
	local intensity = 0
	local wateringAttribute = WaterConfig.Attributes.Watering

	RunService.RenderStepped:Connect(function(dt)
		local watering = player:GetAttribute(wateringAttribute) == true

		-- eases in and out, so it starts and stops smoothly
		intensity += ((watering and 1 or 0) - intensity) * (1 - math.exp(-14 * dt))
		if not watering and intensity < 0.003 then
			intensity = 0
		end

		local t = os.clock()
		Vide.batch(function()
			now(workspace:GetServerTimeNow())

			if intensity > 0 then
				local nx = math.sin(t * 47) + math.sin(t * 31.7 + 1.3) * 0.7
				local ny = math.sin(t * 53 + 2.1) + math.sin(t * 37.3) * 0.7
				shake.Offset(Vector2.new(nx * 0.0035 * intensity, ny * 0.006 * intensity))
				shake.Rotation(math.sin(t * 41) * 1.1 * intensity)
				shimmer((t * 0.9 % 2) - 1)
			else
				shake.Offset(Vector2.zero)
				shake.Rotation(0)
				shimmer(-1) -- stripe parked off the bar
			end
		end)
	end)

	-- bounce the panel whenever a new plant shows up
	PlantCycle_Controller.StateChanged:Connect(function(state)
		if state.Phase == "Growing" then
			popTarget(1.12)
			task.delay(0.15, function()
				popTarget(1)
			end)
		end
	end)

	-- abstract plant weight, replicated by the server as a workspace attribute
	local plantWeight = source(workspace:GetAttribute("PlantWeight") or 0)
	workspace:GetAttributeChangedSignal("PlantWeight"):Connect(function()
		plantWeight(workspace:GetAttribute("PlantWeight") or 0)
	end)

	Vide.mount(function()
		return PlantHUD(cycle, now, shimmer, popTarget, totals, shake, plantWeight)
	end, player:WaitForChild("PlayerGui"))
end

function PlantHUD_Controller:KnitInit() end

return PlantHUD_Controller

