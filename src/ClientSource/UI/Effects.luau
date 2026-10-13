--[[
	Small reusable world-space effects (all client side, all cleaned up automatically):
		Effects.FloatText(position, text, options)   rising, popping, fading text
		Effects.Burst(position, options)             a burst of sparkles
		Effects.Shockwave(position, options)         an expanding glowing ring
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Effects = {}

local folder

local function getFolder()
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "ClientEffects"
		folder.Parent = workspace
	end
	return folder
end

local function newAnchor(position, name)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.Position = position
	part.Parent = getFolder()
	return part
end

--- Text that pops in, rises and fades. options:
---   Color, StrokeColor, Height (studs, text size), Rise (studs), Duration (s), Pop (extra pop-in overshoot)
function Effects.FloatText(position, text, options)
	options = options or {}
	local height = options.Height or 2
	local duration = options.Duration or 1.1
	local rise = options.Rise or 4

	local anchor = newAnchor(position, "FloatText")

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(height * 4, height)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 150
	billboard.Adornee = anchor
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = options.Color or Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = options.StrokeColor or Color3.fromRGB(40, 30, 10)
	label.TextStrokeTransparency = 0
	label.Parent = billboard

	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = label

	-- pop in with overshoot, rise, then fade out
	TweenService:Create(
		scale,
		TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 + (options.Pop or 0.15) }
	):Play()
	TweenService:Create(billboard, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = Vector3.new(0, rise, 0),
	}):Play()
	task.delay(duration * 0.55, function()
		if label.Parent then
			local fade = TweenInfo.new(duration * 0.45)
			TweenService:Create(label, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			TweenService:Create(scale, fade, { Scale = 0.9 }):Play()
		end
	end)

	Debris:AddItem(anchor, duration + 0.2)
	return label
end

--- A burst of sparkles. options: Color (Color3), Count, Speed, Size, Lifetime
function Effects.Burst(position, options)
	options = options or {}
	local anchor = newAnchor(position, "Burst")

	local color = options.Color or Color3.fromRGB(255, 220, 90)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	emitter.LightEmission = 0.7
	emitter.Lifetime = NumberRange.new((options.Lifetime or 1) * 0.6, options.Lifetime or 1)
	emitter.Speed = NumberRange.new((options.Speed or 22) * 0.5, options.Speed or 22)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -18, 0)
	emitter.Drag = 2
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, options.Size or 1.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Rate = 0
	emitter.Parent = anchor
	emitter:Emit(options.Count or 40)

	Debris:AddItem(anchor, (options.Lifetime or 1) + 0.5)
end

--- An expanding, fading glowing ring/sphere. options: Color, Size (final diameter), Duration
function Effects.Shockwave(position, options)
	options = options or {}
	local duration = options.Duration or 0.7

	local part = newAnchor(position, "Shockwave")
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.Color = options.Color or Color3.fromRGB(255, 220, 90)
	part.Transparency = 0.3
	part.Size = Vector3.one * 0.5

	local size = options.Size or 14
	TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * size,
		Transparency = 1,
	}):Play()
	Debris:AddItem(part, duration + 0.2)
end

return Effects
