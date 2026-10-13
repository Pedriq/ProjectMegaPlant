local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local WaterConfig = require(ReplicatedStorage.SharedSource.Datas.WaterConfig)
local WaterState = require(ReplicatedStorage.ClientSource.Utilities.WaterState)

--[[
	Water collection effect, visible to everyone: while a player is refilling (the server's
	`Filling` attribute is true), glowing mint-green bubbles spiral from the nearest water source
	up into their can, pulse rings ripple out of the can, and sparkles bubble out of both ends.

	It is intentionally different from the pouring effect (WaterStream_Controller): pouring is a solid
	deep-blue ribbon of water falling onto the plant, collecting is a floating spiral of light
	aqua bubbles. Different colour, shape and motion, so the two are never confused.

	It is driven only by the `Filling` attribute, which the server clears the moment the player lets go
	of the prompt, walks away, or the can is full. The effect then fades out in a fraction of a second.
]]
local WaterCollect_Controller = Knit.CreateController({
	Name = "WaterCollect_Controller",
})

local BUBBLES = 16
local SPIRAL_RADIUS = 1.3 -- studs at the source; narrows toward the can
local SPIRAL_TURNS = 2.5
local FLOW_SPEED = 0.7 -- bubbles travel this fraction of the way per second
local RING_COUNT = 2
local RING_PERIOD = 0.8 -- seconds for a ring to expand and fade
local RING_MAX_SIZE = 6.5
local FADE_SPEED = 16 -- fast: the effect must stop right when filling stops
local FOLLOW_SPEED = 20

local MINT = Color3.fromRGB(120, 255, 214)
local MINT_LIGHT = Color3.fromRGB(214, 255, 244)
local SPARKLE_COLOR = ColorSequence.new(MINT_LIGHT, MINT)

local WateringCanVisual_Controller

local folder
local effects = {} -- [player] = effect
local sourceParts = {} -- resolved water source parts

---- Water sources

local function resolveSources()
	for index, source in ipairs(WaterConfig.Sources) do
		local part = sourceParts[index]
		if not (part and part:IsDescendantOf(workspace)) then
			local instance = workspace
			for _, name in ipairs(source.Path) do
				instance = instance and instance:FindFirstChild(name)
			end
			if instance and instance:IsA("Model") then
				instance = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
			end
			sourceParts[index] = instance and instance:IsA("BasePart") and instance or nil
		end
	end
end

--- Point on the closest water source (raised a bit) where the bubbles start, or nil.
local function getSourcePoint(fromPosition)
	local bestPoint, bestDistance
	for _, part in pairs(sourceParts) do
		local point = part:GetClosestPointOnSurface(fromPosition)
		local distance = (point - fromPosition).Magnitude
		if not bestDistance or distance < bestDistance then
			bestPoint, bestDistance = point, distance
		end
	end
	return bestPoint and (bestPoint + Vector3.new(0, 1.2, 0))
end

---- Effect objects

local function newAnchoredPart(name, size)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size
	part.Parent = folder
	return part
end

local function newSparkleEmitter(parent, speed, acceleration)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = SPARKLE_COLOR
	emitter.LightEmission = 0.8
	emitter.Lifetime = NumberRange.new(0.5, 1)
	emitter.Speed = speed
	emitter.SpreadAngle = Vector2.new(40, 40)
	emitter.Acceleration = acceleration
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Rate = 0
	emitter.Parent = parent
	return emitter
end

local function createEffect()
	-- bubbles that spiral from the source into the can
	local bubbles = {}
	for i = 1, BUBBLES do
		local bubble = newAnchoredPart("Bubble" .. i, Vector3.one * 0.4)
		bubble.Shape = Enum.PartType.Ball
		bubble.Material = Enum.Material.Neon
		bubble.Color = i % 3 == 0 and MINT_LIGHT or MINT
		bubble.Transparency = 0.25
		bubbles[i] = bubble
	end

	-- flat rings that ripple out of the can
	local rings = {}
	for i = 1, RING_COUNT do
		local ring = newAnchoredPart("Ring" .. i, Vector3.new(0.12, 1, 1))
		ring.Shape = Enum.PartType.Cylinder
		ring.Material = Enum.Material.Neon
		ring.Color = MINT
		rings[i] = ring
	end

	local canPart = newAnchoredPart("CollectCan", Vector3.one * 0.2)
	local canSparkles = newSparkleEmitter(canPart, NumberRange.new(4, 7), Vector3.new(0, 3, 0))

	local sourcePart = newAnchoredPart("CollectSource", Vector3.one * 0.2)
	local sourceSparkles = newSparkleEmitter(sourcePart, NumberRange.new(2, 5), Vector3.new(0, 6, 0))

	return {
		Bubbles = bubbles,
		Rings = rings,
		CanPart = canPart,
		CanSparkles = canSparkles,
		SourcePart = sourcePart,
		SourceSparkles = sourceSparkles,
		Visibility = 0,
		Start = nil,
		End = nil,
	}
end

local function destroyEffect(player)
	local effect = effects[player]
	if not effect then
		return
	end
	effects[player] = nil
	for _, bubble in ipairs(effect.Bubbles) do
		bubble:Destroy()
	end
	for _, ring in ipairs(effect.Rings) do
		ring:Destroy()
	end
	effect.CanPart:Destroy()
	effect.SourcePart:Destroy()
end

---- Per-frame update

--- Where the bubbles end up: the can, or above the head if the can isn't visible yet.
local function getTarget(player, root)
	local top = WateringCanVisual_Controller:GetTopPosition(player)
	if top then
		return top
	end
	local head = player.Character and player.Character:FindFirstChild("Head")
	return (head and head.Position or root.Position) + Vector3.new(0, 3.5, 0)
end

local function update(player, dt)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local wanted = WaterState.IsFilling(player) and root ~= nil

	local startPoint = wanted and getSourcePoint(root.Position)
	wanted = wanted and startPoint ~= nil

	local effect = effects[player]
	if not effect then
		if not wanted then
			return
		end
		effect = createEffect()
		effects[player] = effect
	end

	effect.Visibility += ((wanted and 1 or 0) - effect.Visibility) * (1 - math.exp(-FADE_SPEED * dt))
	if not wanted and effect.Visibility < 0.03 then
		destroyEffect(player)
		return
	end
	local visibility = effect.Visibility

	-- the ends ease toward their targets so the effect stays smooth when the player moves
	if wanted then
		local follow = 1 - math.exp(-FOLLOW_SPEED * dt)
		local target = getTarget(player, root)
		effect.Start = effect.Start and effect.Start:Lerp(startPoint, follow) or startPoint
		effect.End = effect.End and effect.End:Lerp(target, follow) or target
	end
	local start, finish = effect.Start, effect.End
	if not (start and finish) then
		return
	end

	-- basis around the source -> can axis for the spiral
	local axis = finish - start
	local length = math.max(axis.Magnitude, 0.01)
	local direction = axis / length
	local side = direction:Cross(Vector3.yAxis)
	if side.Magnitude < 0.05 then
		side = direction:Cross(Vector3.xAxis)
	end
	side = side.Unit
	local lift = direction:Cross(side)

	local clock = os.clock()
	local arcHeight = math.clamp(length * 0.2, 0.8, 4)

	for i, bubble in ipairs(effect.Bubbles) do
		local t = (clock * FLOW_SPEED + (i - 1) / BUBBLES) % 1
		local angle = t * SPIRAL_TURNS * math.pi * 2 + i * 1.7
		local radius = SPIRAL_RADIUS * (1 - t * 0.85) * math.sin(math.min(t * 6, 1) * math.pi / 2)
		local position = start:Lerp(finish, t)
			+ Vector3.new(0, math.sin(t * math.pi) * arcHeight, 0)
			+ (side * math.cos(angle) + lift * math.sin(angle)) * radius
		bubble.Position = position
		-- pop in near the source, shrink as they dive into the can
		local size = (0.18 + 0.32 * math.sin(math.clamp(t, 0, 1) * math.pi) ^ 0.6) * visibility
		bubble.Size = Vector3.one * size
	end

	-- rings expand and fade, staggered
	for i, ring in ipairs(effect.Rings) do
		local phase = (clock / RING_PERIOD + (i - 1) / RING_COUNT) % 1
		local diameter = 0.8 + phase * RING_MAX_SIZE
		ring.Size = Vector3.new(0.12, diameter, diameter)
		ring.Transparency = 1 - (1 - phase) * 0.7 * visibility
		-- lie flat (the cylinder's axis is X, so tilt it upright)
		ring.CFrame = CFrame.new(finish) * CFrame.Angles(0, 0, math.pi / 2)
	end

	effect.SourcePart.Position = start
	effect.CanPart.Position = finish
	effect.SourceSparkles.Rate = 18 * visibility
	effect.CanSparkles.Rate = 30 * visibility
end

function WaterCollect_Controller:KnitStart()
	WateringCanVisual_Controller = Knit.GetController("WateringCanVisual_Controller")

	folder = Instance.new("Folder")
	folder.Name = "WaterCollectEffects"
	folder.Parent = workspace

	local sinceResolve = 0
	RunService.RenderStepped:Connect(function(dt)
		-- (re)resolve the source parts occasionally: they may stream in or be replaced
		sinceResolve += dt
		if sinceResolve > 2 or next(sourceParts) == nil then
			sinceResolve = 0
			resolveSources()
		end

		for _, player in ipairs(Players:GetPlayers()) do
			update(player, dt)
		end
	end)

	Players.PlayerRemoving:Connect(destroyEffect)
end

function WaterCollect_Controller:KnitInit() end

return WaterCollect_Controller
