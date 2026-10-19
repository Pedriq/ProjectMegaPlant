local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local PlantsConfig = require(ReplicatedStorage.SharedSource.Datas.PlantsConfig)
local PlantGrowth = require(ReplicatedStorage.SharedSource.Utilities.PlantGrowth)
local JuiceConfig = require(ReplicatedStorage.SharedSource.Datas.JuiceConfig)

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

--- Y of the lawn surface right under `position`, or nil. The PlantBed part is an invisible block that sticks up
--- above the lawn (its top is ~1 stud higher), so planting on its top made small plants hover.
local function findLawnTop(position)
	local garden = workspace:FindFirstChild(PlantsConfig.GardenName)
	local lawn = garden and garden:FindFirstChild(JuiceConfig.Pool.LawnName)
	if not lawn then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { lawn }
	local hit = workspace:Raycast(position + Vector3.new(0, 5, 0), Vector3.new(0, -20, 0), params)
	return hit and hit.Position.Y or nil
end

--- World position of the middle of the bed's top surface, lowered to the lawn surface when the lawn is just
--- below it (at most MAX_BED_LIFT studs), so the plant stands on the ground.
local MAX_BED_LIFT = 3
local function getBedTop(bed)
	if not bed then
		return Vector3.zero
	end
	local top
	if bed:IsA("BasePart") then
		top = bed.Position + Vector3.new(0, bed.Size.Y / 2, 0)
	elseif bed:IsA("Model") then
		local cframe, size = bed:GetBoundingBox()
		top = cframe.Position + Vector3.new(0, size.Y / 2, 0)
	else
		return Vector3.zero
	end
	local lawnY = findLawnTop(top)
	if lawnY and lawnY <= top.Y and top.Y - lawnY <= MAX_BED_LIFT then
		return Vector3.new(top.X, lawnY, top.Z)
	end
	return top
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
			-- a model is a rigid group of parts: freeze all of them, and keep them out of physics / raycasts
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		elseif descendant:IsA("BaseScript") or descendant:IsA("Humanoid") then
			-- scripts / humanoids inside a fruit model would act on their own (or fight the scaling)
			descendant:Destroy()
		end
	end
	-- models made in Studio often have no PrimaryPart; the pivot (or the bounding box) is used instead,
	-- but give it one so tools that read PrimaryPart work too
	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
	end
end

--- Bottom center of the model in WORLD space: the lowest point of any part (world Y) under the middle of the
--- world-axis box. Model:GetBoundingBox is NOT used on purpose: its box follows the model's pivot / PrimaryPart
--- rotation, so for fruit meshes whose pivot is turned the "bottom" it reports is a side face and the plant
--- sank into the bed by up to 80% of its height.
local function measureBottom(model)
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxZ = -math.huge, -math.huge
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local cframe, half = part.CFrame, part.Size / 2
			for sx = -1, 1, 2 do
				for sy = -1, 1, 2 do
					for sz = -1, 1, 2 do
						local corner = cframe:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
						minX, maxX = math.min(minX, corner.X), math.max(maxX, corner.X)
						minY = math.min(minY, corner.Y)
						minZ, maxZ = math.min(minZ, corner.Z), math.max(maxZ, corner.Z)
					end
				end
			end
		end
	end
	return Vector3.new((minX + maxX) / 2, minY, (minZ + maxZ) / 2)
end

--- Scales the model and keeps its bottom centered on the bed's top surface.
-- The bottom is measured ONCE per plant (the model scales linearly around its pivot), after that the
-- placement is plain arithmetic: no extra measuring / property writes on every size step.
local function applyScale(model, bedTop, scale)
	if not bottomOffset then
		-- measured at the model's untouched size (before the first ScaleTo): at tiny scales Roblox clamps small
		-- parts to a minimum size, the box stops being proportional and the base would drift as the plant grows
		bottomOffset = model:GetPivot():PointToObjectSpace(measureBottom(model)) / model:GetScale() -- bottom center, scale 1
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
