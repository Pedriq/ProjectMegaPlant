local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local PlantsConfig = require(ReplicatedStorage.SharedSource.Datas.PlantsConfig)
local TrainingConfig = require(ReplicatedStorage.SharedSource.Datas.TrainingConfig)
local JuiceConfig = require(ReplicatedStorage.SharedSource.Datas.JuiceConfig)
local PlantGrowth = require(ReplicatedStorage.SharedSource.Utilities.PlantGrowth)

--[[
	What happens when a plant finishes growing (see JuiceConfig):

	  1. Launch     the server lifts the plant into the air (clients orbit the camera around it)
	  2. Explosion  the plant is removed; clients play the effects at the same server time
	  3. Pool       a juice pool rises where the plant stood. Its multiplier comes from the plant's rarity and
	                final size. Standing in it grows EVERY stat of JuiceConfig.Pool.Stats at once.

	Zone logic is fully server-side and idempotent: every CheckInterval each player is tested against the
	one active pool and their "JuiceBoost" attribute is SET (never added) to the pool's multiplier or cleared,
	so nothing can stack. The pool is removed when the next plant is selected.
]]
local JuicePool_Service = Knit.CreateService({
	Name = "JuicePool_Service",
	Client = {
		-- to everyone: ({ CycleId, PlantId, Position, Size, StartTime, Color, RarityName, Multiplier, Radius })
		Cinematic = Knit.CreateSignal(),
	},
})

local Plant_Service, PlantCycle_Service, Stats_Service

local pool -- { Model, Center, Radius, Multiplier } while a pool exists
local activeCycle -- cycle id whose sequence is running / whose pool exists
local inside = {} -- [player] = true while standing in the pool
local gainRemainder = {} -- [player] = fractional stat points not paid out yet
local sinceCheck, sinceApply = 0, 0

local config = JuiceConfig.Pool

---- Pool construction

local function newCylinder(name, parent, center, diameter, thickness, color, material, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Color = color
	part.Material = material
	part.Transparency = transparency
	-- a cylinder's axis is its X axis: rotate it so it lies flat
	part.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2)
	part.Size = Vector3.new(0.05, 0.5, 0.5) -- grows to its final size
	part.Parent = parent
	return part, Vector3.new(thickness, diameter, diameter)
end

local function buildLabel(parent, multiplier, rarityName, radius, color)
	local anchor = Instance.new("Part")
	anchor.Name = "LabelAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = parent.Position + Vector3.new(0, 4 + radius * 0.35, 0)
	anchor.Parent = parent.Parent

	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromScale(11, 4) -- scale in a BillboardGui is in studs
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.Parent = anchor

	local function line(name, position, size, text, textColor)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Position = position
		label.Size = size
		label.Text = text
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = textColor
		label.TextStrokeColor3 = color:Lerp(Color3.new(0, 0, 0), 0.65)
		label.TextStrokeTransparency = 0.25
		label.Parent = gui
	end
	line("Multiplier", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.58), ("x%.1f  ALL STATS"):format(multiplier), Color3.new(1, 1, 1))
	line("Rarity", UDim2.fromScale(0, 0.6), UDim2.fromScale(1, 0.3), rarityName .. " Juice", color:Lerp(Color3.new(1, 1, 1), 0.35))
end

local function createPool(center, radius, multiplier, rarity)
	local strength = JuiceConfig.GetStrength(multiplier)
	local color, dark = rarity.Color, rarity.DarkColor

	local model = Instance.new("Model")
	model.Name = config.Name
	model:SetAttribute("Multiplier", multiplier)
	model:SetAttribute("Radius", radius)
	model:SetAttribute("Strength", strength)
	model:SetAttribute("Color", color)

	local rim, rimSize = newCylinder(
		"Rim",
		model,
		center,
		radius * 2 + config.RimExtra,
		config.Thickness * 0.8,
		dark,
		Enum.Material.SmoothPlastic,
		0
	)
	local juice, juiceSize = newCylinder(
		"Juice",
		model,
		center + Vector3.new(0, 0.06, 0),
		radius * 2,
		config.Thickness,
		color,
		Enum.Material.Neon,
		0.2
	)
	-- a faint inner glow disc: bigger multipliers glow more
	local core, coreSize = newCylinder(
		"Core",
		model,
		center + Vector3.new(0, 0.2, 0),
		radius * 1.1,
		config.Thickness * 0.5,
		color:Lerp(Color3.new(1, 1, 1), 0.45),
		Enum.Material.Neon,
		0.55 - 0.3 * strength
	)

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 14 + radius * 1.5
	light.Brightness = 1.5 + strength * 3
	light.Parent = core

	-- Gentle ambient particles. Everything is slow and short-lived, so it hugs the surface; rates follow the
	-- pool's area (capped) and strength, and the colors follow the juice.
	local area = math.pi * radius * radius
	local light = color:Lerp(Color3.new(1, 1, 1), 0.55)
	local function emitter(name, texture, rate, props)
		local particles = Instance.new("ParticleEmitter")
		particles.Name = name
		particles.Texture = texture
		particles.Rate = rate
		particles.Shape = Enum.ParticleEmitterShape.Cylinder
		particles.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		particles.EmissionDirection = Enum.NormalId.Right -- the part's local +X points up
		particles.LightInfluence = 0
		particles.LockedToPart = false
		for key, value in pairs(props) do
			particles[key] = value
		end
		particles.Parent = juice
		return particles
	end

	-- soft bubbles that rise a little and fade
	emitter("Bubbles", "rbxasset://textures/particles/smoke_main.dds", math.min(area * 0.03 * (0.7 + strength * 0.6), 80), {
		Color = ColorSequence.new(light, color),
		LightEmission = 0.6,
		Lifetime = NumberRange.new(1, 1.9),
		Speed = NumberRange.new(0.4, 1.4),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.3, 0.45 + strength * 0.25),
			NumberSequenceKeypoint.new(1, 0.2),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})

	-- small droplets that hop up and fall back
	emitter("Droplets", "rbxasset://textures/particles/sparkles_main.dds", math.min(area * 0.012 * (0.7 + strength * 0.8), 40), {
		Color = ColorSequence.new(light, color),
		LightEmission = 0.5,
		Lifetime = NumberRange.new(0.7, 1.2),
		Speed = NumberRange.new(2.5, 5 + strength * 2),
		SpreadAngle = Vector2.new(18, 18),
		Acceleration = Vector3.new(0, -22, 0),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})

	-- rarer / stronger pools get a few extra glints on the surface
	if strength >= 0.4 then
		emitter("Glints", "rbxasset://textures/particles/sparkles_main.dds", math.min(area * 0.004 * strength * 2, 14), {
			Color = ColorSequence.new(Color3.new(1, 1, 1), light),
			LightEmission = 1,
			Lifetime = NumberRange.new(0.5, 0.9),
			Speed = NumberRange.new(0, 0.3),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0.8),
				NumberSequenceKeypoint.new(1, 0),
			}),
		})
	end

	buildLabel(juice, multiplier, rarity.DisplayName, radius, color)

	model.PrimaryPart = juice
	model.Parent = workspace
	CollectionService:AddTag(model, config.Tag)

	-- rise out of the ground
	local info = TweenInfo.new(config.RiseTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(rim, info, { Size = rimSize }):Play()
	TweenService:Create(juice, info, { Size = juiceSize }):Play()
	TweenService:Create(core, info, { Size = coreSize }):Play()

	return model
end

---- Ground

--- The surface height under the plant's original position, measured with rays that hit ONLY the lawn
--- (several points across the pool, median), so the pool sits flush with it. Falls back to any solid
--- surface (never a player) and finally to the bed's top.
local function findGround(bedTop, radius)
	local garden = workspace:FindFirstChild(PlantsConfig.GardenName)
	local lawn = garden and garden:FindFirstChild(config.LawnName)

	if lawn then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { lawn }

		local heights = {}
		local offsets = { Vector3.zero }
		for i = 1, 8 do
			local angle = i / 8 * math.pi * 2
			local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
			table.insert(offsets, direction * radius * 0.5)
			table.insert(offsets, direction * radius * 0.95)
		end
		for _, offset in ipairs(offsets) do
			local origin = bedTop + offset + Vector3.new(0, 40, 0)
			local hit = workspace:Raycast(origin, Vector3.new(0, -80, 0), params)
			if hit then
				table.insert(heights, hit.Position.Y)
			end
		end
		if #heights > 0 then
			table.sort(heights)
			return Vector3.new(bedTop.X, heights[math.ceil(#heights / 2)], bedTop.Z)
		end
	end

	local ignore = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(bedTop + Vector3.new(0, 3, 0), Vector3.new(0, -10, 0), params)
	if hit and math.abs(hit.Position.Y - bedTop.Y) <= 4 then
		return Vector3.new(bedTop.X, hit.Position.Y, bedTop.Z)
	end
	return bedTop
end

---- Pool state

local function setBoost(player, multiplier)
	local current = player:GetAttribute(JuiceConfig.BoostAttribute)
	if current ~= multiplier then
		player:SetAttribute(JuiceConfig.BoostAttribute, multiplier)
	end
end

local function removePool()
	if pool and pool.Model then
		pool.Model:Destroy()
	end
	pool = nil
	table.clear(inside)
	table.clear(gainRemainder)
	for _, player in ipairs(Players:GetPlayers()) do
		setBoost(player, nil)
	end
end

local function isInsidePool(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local delta = root.Position - pool.Center
	local flat = Vector3.new(delta.X, 0, delta.Z).Magnitude
	return flat <= pool.Radius + config.RadiusLeeway and delta.Y >= -config.ReachBelow and delta.Y <= config.ReachAbove
end

local function refreshPlayers()
	for _, player in ipairs(Players:GetPlayers()) do
		local now = isInsidePool(player)
		if now ~= (inside[player] == true) then
			inside[player] = now or nil
			if not now then
				gainRemainder[player] = nil
			end
		end
		setBoost(player, now and pool.Multiplier or nil)
	end
end

local function payOut(dt)
	local perSecond = TrainingConfig.BaseGainPerSecond * pool.Multiplier
	for player in pairs(inside) do
		gainRemainder[player] = (gainRemainder[player] or 0) + perSecond * dt
	end
	sinceApply += dt
	if sinceApply < config.ApplyInterval then
		return
	end
	sinceApply = 0
	for player, remainder in pairs(gainRemainder) do
		local whole = math.floor(remainder)
		if whole >= 1 and inside[player] then
			gainRemainder[player] = remainder - whole
			-- every stat grows at the same time
			for _, statKey in ipairs(config.Stats) do
				Stats_Service:AddStat(player, statKey, whole)
			end
		end
	end
end

---- The sequence

local function runSequence(cycleId, plantId, model)
	local cinematic = JuiceConfig.Cinematic
	local bedTop = model:GetAttribute("BedTop") or model:GetPivot().Position
	local extents = model:GetExtentsSize()
	local points = Plant_Service:GetGrowthPoints()
	local sizeRatio = PlantGrowth.GetScale(points) / PlantGrowth.GetScale(0)
	local rarityKey = PlantsConfig.GetPlant(plantId).Rarity
	local rarity = PlantsConfig.GetRarity(plantId)
	local multiplier = JuiceConfig.GetMultiplier(rarityKey, sizeRatio)
	local radius = JuiceConfig.GetRadius(sizeRatio)

	removePool()
	activeCycle = cycleId
	Plant_Service:Freeze()

	local startServerTime = workspace:GetServerTimeNow()
	JuicePool_Service.Client.Cinematic:FireAll({
		CycleId = cycleId,
		PlantId = plantId,
		Position = bedTop,
		Size = extents,
		StartTime = startServerTime,
		Color = rarity.Color,
		RarityName = rarity.DisplayName,
		Multiplier = multiplier,
		Radius = radius,
	})

	-- 1. launch: lift and spin the plant
	local basePivot = model:GetPivot()
	local startClock = os.clock()
	while activeCycle == cycleId and model.Parent do
		local elapsed = os.clock() - startClock
		if elapsed >= JuiceConfig.ExplosionAt then
			break
		end
		local height, launchProgress = JuiceConfig.GetLaunchHeight(extents.Y, elapsed)
		local spin = launchProgress * cinematic.SpinTurns * math.pi * 2
		local shake = Vector3.zero
		if elapsed > cinematic.LaunchTime then
			-- trembling just before the explosion, getting stronger
			local k = (elapsed - cinematic.LaunchTime) / cinematic.HoldTime
			shake = Vector3.new(math.sin(elapsed * 90), math.sin(elapsed * 77 + 1), math.cos(elapsed * 83)) * (0.15 + 0.5 * k)
		end
		model:PivotTo(
			CFrame.new(basePivot.Position + Vector3.new(0, height, 0) + shake)
				* CFrame.Angles(0, spin, 0)
				* basePivot.Rotation
		)
		RunService.Heartbeat:Wait()
	end

	if activeCycle ~= cycleId or not model.Parent then
		return -- the cycle moved on (or the plant was removed): nothing more to do
	end

	-- 2. explosion: the plant is gone, clients play the effects at this very server time
	Plant_Service:Clear()
	task.wait(config.AppearDelay)
	if activeCycle ~= cycleId then
		return
	end

	-- 3. the pool, flat on the ground where the plant stood
	local center = findGround(bedTop, radius)
	pool = {
		Model = createPool(center, radius, multiplier, rarity),
		Center = center,
		Radius = radius,
		Multiplier = multiplier,
	}
end

local function onPlantGrown(cycleId, plantId)
	local model = Plant_Service:GetPlant()
	if not model then
		return
	end
	task.spawn(runSequence, cycleId, plantId, model)
end

---- Lifecycle

function JuicePool_Service:KnitStart()
	Plant_Service = Knit.GetService("Plant_Service")
	PlantCycle_Service = Knit.GetService("PlantCycle_Service")
	Stats_Service = Knit.GetService("Stats_Service")

	PlantCycle_Service.PlantGrown:Connect(onPlantGrown)

	-- the pool lives until the next plant starts growing, then the pool is removed
	PlantCycle_Service.PhaseChanged:Connect(function(state)
		if state.Phase == "Growing" then
			activeCycle = nil
			removePool()
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		if not pool then
			return
		end
		sinceCheck += dt
		if sinceCheck >= config.CheckInterval then
			sinceCheck = 0
			refreshPlayers()
		end
		payOut(dt)
	end)

	Players.PlayerRemoving:Connect(function(player)
		inside[player] = nil
		gainRemainder[player] = nil
	end)
end

function JuicePool_Service:KnitInit() end

return JuicePool_Service
