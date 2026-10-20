local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local TutorialConfig = require(ReplicatedStorage.SharedSource.Datas.TutorialConfig)
local WaterConfig = require(ReplicatedStorage.SharedSource.Datas.WaterConfig)
local TrainingConfig = require(ReplicatedStorage.SharedSource.Datas.TrainingConfig)
local Plastic = require(ReplicatedStorage.ClientSource.UI.Plastic)

--[[
	Draws the first-time tutorial (see TutorialConfig / Tutorial_Service):
	  - an objective card in the top-left corner: step number, title, explanation and a progress bar
	  - a gold beam from the player to the target, and a bouncing arrow above it with its name and distance
	  - when the target is off screen, a direction arrow on the edge of the screen pointing to it
	The server decides everything; this controller only reads the player attributes it writes
	(TutorialConfig.StepAttribute / ProgressAttribute) and never changes game state.
]]
local Tutorial_Controller = Knit.CreateController({
	Name = "Tutorial_Controller",
})

local player = Players.LocalPlayer
local STEPS = TutorialConfig.Steps
local STEP_ATTR = TutorialConfig.StepAttribute
local PROGRESS_ATTR = TutorialConfig.ProgressAttribute

local GOLD = Color3.fromRGB(255, 214, 72)
local GOLD_DARK = Color3.fromRGB(110, 70, 10)
local CARD_COLOR = Color3.fromRGB(46, 92, 64)
-- the edge arrow stays inside this box (px from each screen side): clear of the stats column, the card and the plant HUD
local EDGE_LEFT, EDGE_RIGHT, EDGE_TOP, EDGE_BOTTOM = 190, 110, 230, 120
local STUDS_TO_METERS = 0.28
local BEAM_HIDE_DISTANCE = 14 -- the beam is hidden when the player is this close to the target

local card, cardScale, refs
local guideGui, edge, edgeArrow, edgeLabel
local guide -- { Arrow, Label, Beam, ToAttachment, Folder, Part, Key, Name }
local currentStep = 0

---- Targets

local function resolve(path)
	local instance = workspace
	for _, name in ipairs(path) do
		instance = instance and instance:FindFirstChild(name)
	end
	return instance
end

local function anchorPart(instance)
	if not instance then
		return nil
	end
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function clearGuide()
	if guide then
		guide.Arrow:Destroy()
		guide.Folder:Destroy()
		guide.ToAttachment:Destroy()
		guide = nil
	end
	if edge then
		edge.Visible = false
	end
end

local function styledLabel(name, size, position, font, color)
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.Size = size
	text.Position = position
	text.Font = font or Plastic.Font
	text.TextScaled = true
	text.TextColor3 = color or Color3.new(1, 1, 1)
	text.TextStrokeColor3 = GOLD_DARK
	text.TextStrokeTransparency = 0
	return text
end

local function buildGuide(part, placeKey, placeName)
	clearGuide()
	if not part then
		return
	end
	local arrow = Instance.new("BillboardGui")
	arrow.Name = "TutorialArrow"
	arrow.Adornee = part
	arrow.AlwaysOnTop = true
	arrow.LightInfluence = 0
	arrow.Size = UDim2.fromOffset(150, 100)
	arrow.MaxDistance = math.huge
	local glyph = styledLabel("Glyph", UDim2.fromScale(0.3, 0.55), UDim2.fromScale(0.35, 0), nil, GOLD)
	glyph.Text = "⬇️"
	glyph.Parent = arrow
	local label = styledLabel("Name", UDim2.fromScale(1, 0.3), UDim2.fromScale(0, 0.62))
	label.TextStrokeColor3 = Color3.fromRGB(20, 40, 28)
	label.Parent = arrow
	arrow.Parent = player:WaitForChild("PlayerGui")

	-- gold beam from the player to the target
	local folder = Instance.new("Folder")
	folder.Name = "TutorialGuide"
	folder.Parent = workspace
	local toAttachment = Instance.new("Attachment")
	toAttachment.Name = "TutorialBeamEnd"
	toAttachment.Parent = part
	local beam = Instance.new("Beam")
	beam.Name = "TutorialBeam"
	beam.Color = ColorSequence.new(GOLD)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Width0 = 0.5
	beam.Width1 = 0.5
	beam.Transparency = NumberSequence.new(0.35)
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Attachment1 = toAttachment
	beam.Enabled = false
	beam.Parent = folder

	guide = {
		Arrow = arrow,
		Label = label,
		Beam = beam,
		ToAttachment = toAttachment,
		Folder = folder,
		Part = part,
		Key = placeKey,
		Name = placeName,
	}
end

--- The place the arrow should point to right now (the water first while the can is empty).
local function wantedPlace()
	local step = STEPS[currentStep]
	if not step then
		return nil
	end
	local key = step.Target
	if step.EmptyTarget and (player:GetAttribute(WaterConfig.Attributes.Water) or 0) <= 0 then
		key = step.EmptyTarget
	end
	return key, TutorialConfig.Places[key]
end

local function updateGuide(now)
	local key, place = wantedPlace()
	-- no guidance while the player is already lying on a training station
	if not place or player:GetAttribute(TrainingConfig.Attribute) then
		clearGuide()
		return
	end
	if not guide or guide.Key ~= key or not guide.Part.Parent then
		buildGuide(anchorPart(resolve(place.Path)), key, place.Name)
		if not guide then
			return
		end
	end

	local part = guide.Part
	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local meters = root and math.floor((root.Position - part.Position).Magnitude * STUDS_TO_METERS + 0.5) or 0
	local text = ("%s  %dm"):format(guide.Name, meters)
	guide.Label.Text = text

	if root then
		local from = root:FindFirstChild("TutorialBeamStart")
		if not from then
			from = Instance.new("Attachment")
			from.Name = "TutorialBeamStart"
			from.Parent = root
		end
		guide.Beam.Attachment0 = from
		guide.Beam.Enabled = (root.Position - part.Position).Magnitude > BEAM_HIDE_DISTANCE
	else
		guide.Beam.Enabled = false
	end

	local bob = math.sin(now * 5) * 0.6
	guide.Arrow.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 3.5 + bob, 0)

	-- off screen: an arrow on the edge of the screen, pointing toward the target
	local viewport = camera.ViewportSize
	local point, onScreen = camera:WorldToViewportPoint(part.Position + Vector3.new(0, part.Size.Y / 2 + 3.5, 0))
	if onScreen then
		edge.Visible = false
		return
	end
	local direction = Vector2.new(point.X, point.Y) - viewport / 2
	if point.Z < 0 then
		direction = -direction
	end
	if direction.Magnitude < 1 then
		direction = Vector2.new(0, -1)
	end
	direction = direction.Unit
	-- follow the ray from the screen centre out to the edge of the allowed box
	local center = viewport / 2
	local limitX = direction.X >= 0 and (viewport.X - EDGE_RIGHT - center.X) or (center.X - EDGE_LEFT)
	local limitY = direction.Y >= 0 and (viewport.Y - EDGE_BOTTOM - center.Y) or (center.Y - EDGE_TOP)
	local k = math.min(limitX / math.max(math.abs(direction.X), 1e-4), limitY / math.max(math.abs(direction.Y), 1e-4))
	local position = center + direction * k
	edge.Position = UDim2.fromOffset(position.X, position.Y)
	edgeArrow.Rotation = math.deg(math.atan2(direction.Y, direction.X))
	edgeLabel.Text = text
	edge.Visible = true
end

---- Card

local function label(name, position, size)
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.Position = position
	text.Size = size
	text.Font = Plastic.Font
	text.TextScaled = true
	text.TextWrapped = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeColor3 = Color3.fromRGB(20, 40, 28)
	text.TextStrokeTransparency = 0.35
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Center
	return text
end

local function buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TutorialHUD"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 15
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.7
	aspect.DominantAxis = Enum.DominantAxis.Width
	aspect.AspectType = Enum.AspectType.ScaleWithParentSize
	local limits = Instance.new("UISizeConstraint")
	limits.MinSize = Vector2.new(240, 0)
	limits.MaxSize = Vector2.new(400, math.huge)
	cardScale = Instance.new("UIScale")
	cardScale.Scale = 0

	local tag = label("StepTag", UDim2.fromScale(0.06, 0.06), UDim2.fromScale(0.5, 0.11))
	tag.TextColor3 = GOLD
	local title = label("Title", UDim2.fromScale(0.06, 0.18), UDim2.fromScale(0.88, 0.18))
	local body = label("Body", UDim2.fromScale(0.06, 0.38), UDim2.fromScale(0.88, 0.36))
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextStrokeTransparency = 0.6

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.fromScale(0.06, 0.82)
	track.Size = UDim2.fromScale(0.88, 0.09)
	track.BackgroundColor3 = Color3.fromRGB(24, 48, 34)
	track.BorderSizePixel = 0
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0.5, 0)
	trackCorner.Parent = track
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = GOLD
	fill.BorderSizePixel = 0
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill
	fill.Parent = track

	card = Plastic.Panel({
		Name = "Card",
		Position = UDim2.fromScale(0.012, 0.03),
		Size = UDim2.fromScale(0.25, 0),
		BodyColor = CARD_COLOR,
		Style = "Accent",
		Corner = 0.22,
		RootChildren = { aspect, limits, cardScale },
		Children = { tag, title, body, track },
	})
	card.Parent = gui
	refs = { Tag = tag, Title = title, Body = body, Fill = fill }

	-- edge arrow: points toward a target that is not on screen
	edge = Instance.new("Frame")
	edge.Name = "EdgeIndicator"
	edge.AnchorPoint = Vector2.new(0.5, 0.5)
	edge.Size = UDim2.fromOffset(150, 80)
	edge.BackgroundTransparency = 1
	edge.Visible = false
	edgeArrow = styledLabel("Arrow", UDim2.fromOffset(46, 46), UDim2.fromScale(0.5, 0.3), nil, GOLD)
	edgeArrow.AnchorPoint = Vector2.new(0.5, 0.5)
	edgeArrow.Text = "➡️"
	edgeArrow.Parent = edge
	edgeLabel = styledLabel("Name", UDim2.fromScale(1, 0.32), UDim2.fromScale(0, 0.68))
	edgeLabel.TextStrokeColor3 = Color3.fromRGB(20, 40, 28)
	edgeLabel.Parent = edge
	edge.Parent = gui

	gui.Parent = player:WaitForChild("PlayerGui")
end

local function tween(instance, time, goal, style, direction)
	TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
		:Play()
end

local function refreshProgress()
	local progress = player:GetAttribute(PROGRESS_ATTR) or 0
	tween(refs.Fill, 0.25, { Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1) })
end

local function refreshStep()
	local index = player:GetAttribute(STEP_ATTR) or 0
	local previous = currentStep
	currentStep = index

	if index <= 0 or not STEPS[index] then
		-- tutorial finished (or never needed): slide the card away
		clearGuide()
		if previous > 0 then
			tween(cardScale, 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		end
		return
	end

	local step = STEPS[index]
	refs.Tag.Text = ("STEP %d / %d"):format(index, #STEPS)
	refs.Title.Text = step.Title
	refs.Body.Text = step.Text
	refs.Fill.Size = UDim2.fromScale(0, 1)
	refreshProgress()

	-- pop in (first step) or pulse (next step)
	cardScale.Scale = previous > 0 and 1.1 or 0.6
	tween(cardScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

function Tutorial_Controller:KnitStart()
	buildGui()

	player:GetAttributeChangedSignal(STEP_ATTR):Connect(refreshStep)
	player:GetAttributeChangedSignal(PROGRESS_ATTR):Connect(refreshProgress)
	refreshStep()

	RunService.RenderStepped:Connect(function()
		if currentStep > 0 then
			updateGuide(os.clock())
		end
	end)
end

function Tutorial_Controller:KnitInit() end

return Tutorial_Controller
