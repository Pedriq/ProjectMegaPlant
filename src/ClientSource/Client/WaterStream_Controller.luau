local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local WaterState = require(ReplicatedStorage.ClientSource.Utilities.WaterState)

--[[
	Draws the water stream between a pouring player's can spout and the plant, plus a splash
	where it lands. The stream is a chain of short beams following a falling arc, so it is
	rebuilt every frame from the live spout and plant positions (it follows both).
	It fades/thickens in and out smoothly instead of popping.
]]
local WaterStream_Controller = Knit.CreateController({
	Name = "WaterStream_Controller",
})

local SEGMENTS = 12
local WIDTH_START = 0.38
local WIDTH_END = 0.26
local FADE_SPEED = 10
local FADE_OUT_SPEED = 22 -- the stream shuts off almost instantly when watering ends
local VIEW_DISTANCE = 160 -- streams further from the camera are not drawn
local CORE_COLOR = ColorSequence.new(Color3.fromRGB(245, 252, 255), Color3.fromRGB(170, 228, 255))
local GLOW_COLOR = Color3.fromRGB(150, 220, 255)
local DROPLET_POINTS = { 2, 5, 8, 11 } -- stream points that shed sparkling droplets
local FOLLOW_SPEED = 18
local WATER_COLOR = ColorSequence.new(Color3.fromRGB(150, 220, 255), Color3.fromRGB(70, 150, 255))

local WateringCanVisual_Controller

local folder
local streams = {} -- [player] = stream

local function createStream()
	local holder = Instance.new("Part")
	holder.Name = "StreamPoints"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.Parent = folder

	local attachments = {}
	for i = 0, SEGMENTS do
		local attachment = Instance.new("Attachment")
		attachment.Name = "P" .. i
		attachment.Parent = holder
		attachments[i] = attachment
	end

	local beams = {}
	for i = 1, SEGMENTS do
		local beam = Instance.new("Beam")
		beam.Name = "Segment" .. i
		beam.Attachment0 = attachments[i - 1]
		beam.Attachment1 = attachments[i]
		beam.Segments = 1
		beam.FaceCamera = true
		beam.LightEmission = 0.35
		beam.Color = WATER_COLOR
		beam.Transparency = NumberSequence.new(0.12)
		beam.Parent = holder
		beams[i] = beam
	end

	-- bright thin core on top of the ribbon: the "shimmer"
	local cores = {}
	for i = 1, SEGMENTS do
		local core = Instance.new("Beam")
		core.Name = "Core" .. i
		core.Attachment0 = attachments[i - 1]
		core.Attachment1 = attachments[i]
		core.Segments = 1
		core.FaceCamera = true
		core.LightEmission = 1
		core.Color = CORE_COLOR
		core.Transparency = NumberSequence.new(0.2)
		core.Parent = holder
		cores[i] = core
	end

	-- sparkling droplets shed along the stream
	local droplets = {}
	for _, index in ipairs(DROPLET_POINTS) do
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "Droplets"
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Color = ColorSequence.new(Color3.new(1, 1, 1), GLOW_COLOR)
		sparkle.LightEmission = 0.9
		sparkle.LightInfluence = 0
		sparkle.LockedToPart = false
		sparkle.Lifetime = NumberRange.new(0.3, 0.6)
		sparkle.Speed = NumberRange.new(0.6, 2.2)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Acceleration = Vector3.new(0, -16, 0)
		sparkle.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.28),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparkle.Rate = 0
		sparkle.Parent = attachments[index]
		table.insert(droplets, sparkle)
	end

	-- splash where the water lands
	local splashPart = Instance.new("Part")
	splashPart.Name = "Splash"
	splashPart.Anchored = true
	splashPart.CanCollide = false
	splashPart.CanQuery = false
	splashPart.CanTouch = false
	splashPart.Transparency = 1
	splashPart.Size = Vector3.one * 0.2
	splashPart.Parent = folder

	local splash = Instance.new("ParticleEmitter")
	splash.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	splash.Color = WATER_COLOR
	splash.LightEmission = 0.4
	splash.Lifetime = NumberRange.new(0.35, 0.7)
	splash.Speed = NumberRange.new(5, 9)
	splash.SpreadAngle = Vector2.new(55, 55)
	splash.Acceleration = Vector3.new(0, -26, 0)
	splash.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	splash.Rate = 0
	splash.LightInfluence = 0
	splash.Parent = splashPart

	-- soft mist puffing up at the impact
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(Color3.new(1, 1, 1), GLOW_COLOR)
	mist.LightEmission = 0.6
	mist.LightInfluence = 0
	mist.Lifetime = NumberRange.new(0.5, 0.9)
	mist.Speed = NumberRange.new(1.5, 3.5)
	mist.SpreadAngle = Vector2.new(80, 80)
	mist.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 2.2),
	})
	mist.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	mist.Rate = 0
	mist.Parent = splashPart

	-- faint glow around the impact
	local glow = Instance.new("PointLight")
	glow.Color = GLOW_COLOR
	glow.Range = 9
	glow.Brightness = 0
	glow.Parent = splashPart

	return {
		Holder = holder,
		Attachments = attachments,
		Beams = beams,
		Cores = cores,
		Droplets = droplets,
		Mist = mist,
		Glow = glow,
		SplashPart = splashPart,
		Splash = splash,
		Visibility = 0,
		End = nil,
	}
end

local function destroyStream(player)
	local stream = streams[player]
	if stream then
		stream.Holder:Destroy()
		stream.SplashPart:Destroy()
		streams[player] = nil
	end
end

local function update(player, dt, plantTarget)
	local spout = WateringCanVisual_Controller:GetSpoutPosition(player)
	local camera = workspace.CurrentCamera
	local wanted = WaterState.IsWatering(player) and spout ~= nil and plantTarget ~= nil
	if wanted and camera and (camera.CFrame.Position - spout).Magnitude > VIEW_DISTANCE then
		wanted = false
	end

	local stream = streams[player]
	if not stream then
		if not wanted then
			return
		end
		stream = createStream()
		streams[player] = stream
	end

	stream.Visibility += ((wanted and 1 or 0) - stream.Visibility) * (1 - math.exp(-(wanted and FADE_SPEED or FADE_OUT_SPEED) * dt))
	if not wanted then
		-- no new particles the moment watering ends
		stream.Splash.Rate = 0
		stream.Mist.Rate = 0
		stream.Glow.Brightness = stream.Visibility * 1.2
		for _, sparkle in ipairs(stream.Droplets) do
			sparkle.Rate = 0
		end
	end
	if not wanted and stream.Visibility < 0.02 then
		destroyStream(player)
		return
	end
	if not (spout and plantTarget) then
		return -- fading out: keep the last shape
	end

	-- the landing point eases toward the plant (it moves while the plant grows)
	stream.End = stream.End and stream.End:Lerp(plantTarget, 1 - math.exp(-FOLLOW_SPEED * dt)) or plantTarget
	local start, finish = spout, stream.End
	local length = (finish - start).Magnitude
	local time = os.clock()

	for i = 0, SEGMENTS do
		local t = i / SEGMENTS
		-- horizontal motion is linear; vertical motion accelerates (gravity)
		local position = start:Lerp(finish, t)
		position = Vector3.new(position.X, start.Y + (finish.Y - start.Y) * t * t, position.Z)
		-- subtle living ripple, zero at both ends
		local ripple = math.sin(time * 14 + t * 9) * 0.05 * math.sin(t * math.pi) * math.min(length / 6, 1)
		stream.Attachments[i].WorldPosition = position + Vector3.new(ripple, 0, ripple)
	end

	for i, beam in ipairs(stream.Beams) do
		local t = (i - 0.5) / SEGMENTS
		local width = (WIDTH_START + (WIDTH_END - WIDTH_START) * t) * stream.Visibility
		beam.Width0 = width
		beam.Width1 = width

		-- the bright core is thinner and shimmers
		local core = stream.Cores[i]
		local shimmer = 1 + 0.22 * math.sin(time * 18 + i * 1.7)
		core.Width0 = width * 0.42 * shimmer
		core.Width1 = width * 0.42 * shimmer
	end

	stream.SplashPart.Position = finish
	stream.Splash.Rate = (wanted and 34 or 0) * stream.Visibility
	stream.Mist.Rate = (wanted and 9 or 0) * stream.Visibility
	stream.Glow.Brightness = (0.9 + 0.25 * math.sin(time * 9)) * stream.Visibility
	for _, sparkle in ipairs(stream.Droplets) do
		sparkle.Rate = (wanted and 7 or 0) * stream.Visibility
	end
end

function WaterStream_Controller:KnitStart()
	WateringCanVisual_Controller = Knit.GetController("WateringCanVisual_Controller")

	folder = Instance.new("Folder")
	folder.Name = "WaterStreams"
	folder.Parent = workspace

	RunService.RenderStepped:Connect(function(dt)
		local plantTarget = WaterState.GetPlantTarget()
		for _, player in ipairs(Players:GetPlayers()) do
			update(player, dt, plantTarget)
		end
	end)

	Players.PlayerRemoving:Connect(destroyStream)
end

function WaterStream_Controller:KnitInit() end

return WaterStream_Controller
