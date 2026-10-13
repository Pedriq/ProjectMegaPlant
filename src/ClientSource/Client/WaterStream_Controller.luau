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
	splash.Parent = splashPart

	return {
		Holder = holder,
		Attachments = attachments,
		Beams = beams,
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
	local wanted = WaterState.IsWatering(player) and spout ~= nil and plantTarget ~= nil

	local stream = streams[player]
	if not stream then
		if not wanted then
			return
		end
		stream = createStream()
		streams[player] = stream
	end

	stream.Visibility += ((wanted and 1 or 0) - stream.Visibility) * (1 - math.exp(-FADE_SPEED * dt))
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
	end

	stream.SplashPart.Position = finish
	stream.Splash.Rate = 38 * stream.Visibility
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
