local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
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
local scaleTween, scaleValue

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
local function applyScale(model, bedTop, scale)
	model:ScaleTo(math.max(scale, 0.001))
	local cframe, size = model:GetBoundingBox()
	local shift = Vector3.new(
		bedTop.X - cframe.Position.X,
		bedTop.Y - (cframe.Position.Y - size.Y / 2),
		bedTop.Z - cframe.Position.Z
	)
	model:PivotTo(model:GetPivot() + shift)
end

local function stopScaleTween()
	if scaleTween then
		scaleTween:Cancel()
		scaleTween = nil
	end
	if scaleValue then
		scaleValue:Destroy()
		scaleValue = nil
	end
end

local function tweenToScale(model, bedTop, fromScale, toScale, time, style, direction)
	stopScaleTween()
	local value = Instance.new("NumberValue")
	value.Value = fromScale
	scaleValue = value
	value.Changed:Connect(function(newScale)
		if model.Parent then
			applyScale(model, bedTop, newScale)
		end
	end)
	scaleTween = TweenService:Create(value, TweenInfo.new(time, style, direction), { Value = toScale })
	scaleTween:Play()
end

---- Public API

function Plant_Service:GetPlant()
	return currentModel, currentPlantId
end

function Plant_Service:GetGrowthPoints()
	return growthPoints
end

function Plant_Service:Clear()
	stopScaleTween()
	if currentModel then
		currentModel:Destroy()
	end
	currentModel, currentPlantId = nil, nil
	growthPoints = 0
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
	tweenToScale(
		currentModel,
		currentModel:GetAttribute("BedTop"),
		fromScale,
		PlantGrowth.GetScale(growthPoints),
		PlantsConfig.Growth.TweenTime,
		Enum.EasingStyle.Quad,
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
