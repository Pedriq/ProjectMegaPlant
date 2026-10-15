local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local PlantsConfig = require(ReplicatedStorage.SharedSource.Datas.PlantsConfig)
local PlantGrowth = require(ReplicatedStorage.SharedSource.Utilities.PlantGrowth)

--[[
	Owns the physical plant in the world: spawning it on Workspace/Garden/PlantBed,
	growing it, removing it. It knows nothing about the cycle/timer (see PlantCycle_Service).
]]
local Plant_Service = Knit.CreateService({
	Name = "Plant_Service",
	Client = {},
})

local currentModel -- Model currently in the world
local currentPlantId
local growthPoints = 0
local stepConnection -- Heartbeat connection of the running size animation (nil when idle)
local bottomOffset -- bottom center of the current model, in its pivot space at scale 1

---- Plant bed

local function findPlantBed()
	local garden = workspace:WaitForChild(PlantsConfig.GardenName, 10)
	local bed = garden and garden:WaitForChild(PlantsConfig.PlantBedName, 10)
	if not bed then
		warn(("Plant_Service: Workspace/%s/%s not found, planting at the origin"):format(
			PlantsConfig.GardenName,
			PlantsConfig.PlantBedName
		))
	end
	return bed
end

--- World position of the middle of the bed's top surface.
local function getBedTop(bed)
	if not bed then
		return Vector3.zero
	end
	if bed:IsA("BasePart") then
		return bed.Position + Vector3.new(0, bed.Size.Y / 2, 0)
	end
	if bed:IsA("Model") then
		local cframe, size = bed:GetBoundingBox()
		return cframe.Position + Vector3.new(0, size.Y / 2, 0)
	end
	return Vector3.zero
end

---- Model helpers

--- Builds a plant model from whatever the template is (Model, loose part, or nothing).
local function buildModel(plantId)
	local template = PlantsConfig.GetTemplate(plantId)

	if template and template:IsA("Model") then
		return template:Clone()
	end

	local model = Instance.new("Model")
	if template and template:IsA("BasePart") then
		local part = template:Clone()
		part.Parent = model
		model.PrimaryPart = part
	else
		-- Missing / incompatible asset: simple placeholder, clearly named
		warn("Plant_Service: no usable model for plant '" .. tostring(plantId) .. "', using a placeholder")
		local part = Instance.new("Part")
		part.Name = "PlaceholderPlant"
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(4, 4, 4)
		part.Color = Color3.fromRGB(120, 200, 90)
		part.Material = Enum.Material.SmoothPlastic
		part.Parent = model
		model.PrimaryPart = part
	end
	return model
end

local function prepareModel(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end
end

--- Scales the model and keeps its bottom centered on the bed's top surface.
-- The bounding box is measured ONCE per plant (the model scales linearly around its pivot), after that the
-- placement is plain arithmetic: no GetBoundingBox / extra property writes on every size step.
local function applyScale(model, bedTop, scale)
	if not bottomOffset then
		-- measured at the model's untouched size (before the first ScaleTo): at tiny scales Roblox clamps small
		-- parts to a minimum size, the box stops being proportional and the base would drift as the plant grows
		local cframe, size = model:GetBoundingBox()
		local bottom = Vector3.new(cframe.Position.X, cframe.Position.Y - size.Y / 2, cframe.Position.Z)
		bottomOffset = model:GetPivot():PointToObjectSpace(bottom) / model:GetScale() -- bottom center, scale 1
	end
	model:ScaleTo(math.max(scale, 0.001))
	local pivot = model:GetPivot()
	local actualScale = model:GetScale()
	local bottomNow = pivot:PointToWorldSpace(bottomOffset * actualScale)
	model:PivotTo(pivot + (bedTop - bottomNow))
end

local function stopScaleTween()
	if stepConnection then
		stepConnection:Disconnect()
		stepConnection = nil
	end
end

--- Eases the plant from one size to another in steps of 1 / Growth.StepRate seconds. The connection only
--- exists while an animation runs, so an idle plant (or a finished one) costs nothing.
local function tweenToScale(model, bedTop, fromScale, toScale, time, style, direction)
	stopScaleTween()
	local stepTime = 1 / math.max(PlantsConfig.Growth.StepRate, 1)
	local elapsed, sinceStep, lastScale = 0, stepTime, nil
	stepConnection = RunService.Heartbeat:Connect(function(dt)
		if not model.Parent then
			stopScaleTween()
			return
		end
		elapsed += dt
		sinceStep += dt
		local finished = elapsed >= time
		if not finished and sinceStep < stepTime then
			return
		end
		sinceStep = 0
		local alpha = finished and 1 or elapsed / time
		local scale = fromScale + (toScale - fromScale) * TweenService:GetValue(alpha, style, direction)
		-- skip imperceptible changes (still always land exactly on the target)
		if finished or not lastScale or math.abs(scale - lastScale) > lastScale * 0.001 then
			lastScale = scale
			applyScale(model, bedTop, scale)
		end
		if finished then
			stopScaleTween()
		end
	end)
end

---- Public API

function Plant_Service:GetPlant()
	return currentModel, currentPlantId
end

function Plant_Service:GetGrowthPoints()
	return growthPoints
end

--- Current abstract weight (kg) of the plant on the bed, 0 if there is none.
function Plant_Service:GetWeight()
	if not currentPlantId then
		return 0
	end
	return PlantGrowth.GetWeight(currentPlantId, growthPoints)
end

--- Replicates the weight (workspace attribute "PlantWeight") for the plant HUD.
local function publishWeight()
	local weight = currentPlantId and PlantGrowth.GetWeight(currentPlantId, growthPoints) or nil
	workspace:SetAttribute("PlantWeight", weight and math.floor(weight * 10 + 0.5) / 10 or nil)
	if currentModel then
		currentModel:SetAttribute("Weight", weight)
	end
end

--- Stops any running size animation (the finish sequence moves the plant on its own).
function Plant_Service:Freeze()
	stopScaleTween()
end

function Plant_Service:Clear()
	stopScaleTween()
	if currentModel then
		currentModel:Destroy()
	end
	currentModel, currentPlantId = nil, nil
	bottomOffset = nil
	growthPoints = 0
	publishWeight()
end

--- Spawns the seedling of `plantId` on the plant bed (replacing any current plant).
function Plant_Service:Spawn(plantId)
	assert(PlantsConfig.GetPlant(plantId), "Unknown plant: " .. tostring(plantId))
	Plant_Service:Clear()

	local bed = findPlantBed()
	local bedTop = getBedTop(bed)
	local model = buildModel(plantId)
	model.Name = plantId
	prepareModel(model)
	model:SetAttribute("PlantId", plantId)
	model:SetAttribute("GrowthPoints", 0)

	local seedlingScale = PlantGrowth.GetScale(0)
	applyScale(model, bedTop, 0.01)
	model.Parent = workspace
	currentModel, currentPlantId = model, plantId
	model:SetAttribute("BedTop", bedTop)
	CollectionService:AddTag(model, PlantsConfig.PlantTag)
	publishWeight()

	-- little pop-in
	tweenToScale(model, bedTop, 0.01, seedlingScale, 0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	return model
end

--- Sets growth points and animates the plant to the matching size.
--- Growth is diminishing: each extra point grows the plant less than the previous one.
function Plant_Service:SetGrowthPoints(points)
	if not currentModel then
		return
	end
	local fromScale = currentModel:GetScale()
	growthPoints = math.max(points, 0)
	currentModel:SetAttribute("GrowthPoints", growthPoints)
	publishWeight()
	tweenToScale(
		currentModel,
		currentModel:GetAttribute("BedTop"),
		fromScale,
		PlantGrowth.GetScale(growthPoints),
		PlantsConfig.Growth.TweenTime,
		-- watering retargets every flush (0.2 s): a linear glide stays smooth, an ease-out would pulse each time
		Enum.EasingStyle.Linear,
		Enum.EasingDirection.Out
	)
end

--- To be called by the (future) watering system.
function Plant_Service:AddGrowth(points)
	Plant_Service:SetGrowthPoints(growthPoints + points)
end

function Plant_Service:KnitStart() end

function Plant_Service:KnitInit() end

return Plant_Service
