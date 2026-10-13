local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vide = require(ReplicatedStorage.Packages.Vide)
local PlantsConfig = require(ReplicatedStorage.SharedSource.Datas.PlantsConfig)

local create = Vide.create

--- Renders a plant model inside a ViewportFrame (used as its icon).
--- Falls back to a "?" label if the asset is missing or incompatible.
--- props: Name, AnchorPoint, Position, Size, ZIndex
return function(plantId, props)
	props = props or {}

	local viewport = create("ViewportFrame")({
		Name = props.Name or "PlantIcon",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size or UDim2.fromScale(1, 1),
		ZIndex = props.ZIndex,
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 200, 200),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-1, -1.2, -0.6),
	})

	local template = plantId and PlantsConfig.GetTemplate(plantId)
	local model
	if template and template:IsA("Model") then
		model = template:Clone()
	elseif template and template:IsA("BasePart") then
		model = Instance.new("Model")
		template:Clone().Parent = model
	end

	if not model then
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "?"
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.Parent = viewport
		return viewport
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		end
	end

	model:PivotTo(CFrame.new())
	local boxCFrame, boxSize = model:GetBoundingBox()
	model.Parent = viewport

	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	local radius = math.max(boxSize.Magnitude / 2, 0.1)
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.05
	local center = boxCFrame.Position
	camera.CFrame = CFrame.lookAt(center + Vector3.new(0.9, 0.55, 1).Unit * distance, center)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	return viewport
end
