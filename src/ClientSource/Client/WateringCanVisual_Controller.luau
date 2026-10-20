local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local WateringCansConfig = require(ReplicatedStorage.SharedSource.Datas.WateringCansConfig)
local WaterState = require(ReplicatedStorage.ClientSource.Utilities.WaterState)

--[[
	Shows each player's equipped watering can floating above their head while they carry water.
	  - hidden when the player has no water
	  - one big can that grows with the water carried (WateringCansConfig.GetWaterScale): linear up to 400 water, then slower
	  - turns toward the plant and tilts while the player is pouring
	Every client renders every player's can from replicated attributes; the model is anchored and
	moved per frame, so it never affects character physics.

	Other controllers can ask for the spout position through :GetSpoutPosition(player).
]]
local WateringCanVisual_Controller = Knit.CreateController({
	Name = "WateringCanVisual_Controller",
})

local SCALE_SMOOTHING = 12
local ROTATION_SMOOTHING = 10
local TILT_SMOOTHING = 8
local LEAN_SMOOTHING = 6
local FOLLOW_STIFFNESS = 30
local FOLLOW_DAMPING = 7

local entries = {} -- [player] = entry

---- Model building

local function buildModel(canId)
	local template = WateringCansConfig.GetTemplate(canId)

	local model
	if template and template:IsA("Model") then
		model = template:Clone()
	elseif template and template:IsA("BasePart") then
		model = Instance.new("Model")
		template:Clone().Parent = model
	else
		warn("WateringCanVisual_Controller: no usable model for can '" .. tostring(canId) .. "', using a placeholder")
		model = Instance.new("Model")
		local part = Instance.new("Part")
		part.Name = "PlaceholderCan"
		part.Size = Vector3.new(1.4, 1.2, 1.4)
		part.Color = Color3.fromRGB(70, 150, 255)
		part.Material = Enum.Material.SmoothPlastic
		part.Parent = model
	end

	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
		end
	end
	return model
end

local function destroyEntry(player)
	local entry = entries[player]
	if entry then
		entry.Model:Destroy()
		entries[player] = nil
	end
end

local function createEntry(player, canId)
	local model = buildModel(canId)
	local config = WateringCansConfig.Get(canId)
	local baseSize = model:GetExtentsSize()

	local entry = {
		CanId = canId,
		Config = config,
		Model = model,
		BaseHeight = baseSize.Y,
		-- where the middle of the model is relative to its pivot (at scale 1): the pivot is often not the center,
		-- so the can is placed by its middle to stay centered above the head
		CenterOffset = model:GetPivot():PointToObjectSpace(model:GetBoundingBox().Position),
		Spout = model:FindFirstChild("Spout", true),
		Scale = 0,
		Tilt = 0,
		Rotation = nil,
		Position = nil,
		Velocity = Vector3.zero,
		Lean = nil,
		SpoutPosition = nil,
		TopPosition = nil,
	}
	model.Name = "CarriedWateringCan"
	model:ScaleTo(0.01)
	model.Parent = workspace
	entries[player] = entry
	return entry
end

---- Per-frame update

local function update(player, dt, plantTarget)
	local canId = WaterState.GetCanId(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local alive = humanoid ~= nil and humanoid.Health > 0

	local water = WaterState.GetWater(player)
	local config = WateringCansConfig.Get(canId)

	local targetScale = 0
	if water > 0 and canId and head and root and alive then
		-- the more water carried, the bigger the can (growth slows down past BalanceConfig.CanSize.SlowdownWater)
		targetScale = WateringCansConfig.GetWaterScale(config, water)
	end

	local entry = entries[player]
	if entry and entry.CanId ~= canId then
		destroyEntry(player)
		entry = nil
	end
	if not entry then
		if targetScale <= 0 then
			return
		end
		entry = createEntry(player, canId)
	end

	-- smooth grow/shrink, remove once fully shrunk
	entry.Scale += (targetScale - entry.Scale) * (1 - math.exp(-SCALE_SMOOTHING * dt))
	if targetScale == 0 and entry.Scale < 0.03 then
		destroyEntry(player)
		return
	end
	if not (head and root) then
		return
	end

	local scale = math.max(entry.Scale, 0.01)
	entry.Model:ScaleTo(scale)

	local pouring = WaterState.IsWatering(player) and plantTarget ~= nil
	local t = os.clock() + player.UserId % 17
	local height = entry.BaseHeight * scale

	-- the middle of the can when resting straight above the head, its bottom a fixed gap over the top of the head
	local aboveHead = head.Position + Vector3.new(0, head.Size.Y / 2 + config.HoverGap + height / 2, 0)

	-- pet behaviour: the can drifts to a spot beside/behind the player and circles around it playfully;
	-- while pouring it settles right above the head so the stream starts from the spout
	local target
	if pouring then
		target = aboveHead + Vector3.new(0, math.sin(t * 3) * 0.12, 0)
	else
		local reach = 3 + height * 0.5
		local orbit = Vector3.new(
			math.sin(t * 1.7) * 0.6,
			math.sin(t * 2.3) * 0.7 + math.sin(t * 5) * 0.15,
			math.cos(t * 1.7) * 0.5
		)
		local local_ = Vector3.new(0, 0.8, reach) + orbit -- +Z is directly behind the character
		target = aboveHead + root.CFrame:VectorToWorldSpace(local_)
	end

	-- floaty underdamped spring toward the target (overshoots a little, like a pet catching up)
	if not entry.Position or (entry.Position - target).Magnitude > 80 then
		entry.Position = target
		entry.Velocity = Vector3.zero
	end
	local step = math.min(dt, 1 / 30)
	local accel = (target - entry.Position) * FOLLOW_STIFFNESS - entry.Velocity * FOLLOW_DAMPING
	entry.Velocity += accel * step
	entry.Position += entry.Velocity * step
	local position = entry.Position

	-- facing: follow the character, or turn toward the plant while pouring
	local desiredRotation = root.CFrame.Rotation
	if pouring then
		local flat = Vector3.new(plantTarget.X - position.X, 0, plantTarget.Z - position.Z)
		if flat.Magnitude > 0.01 then
			desiredRotation = CFrame.lookAt(Vector3.zero, flat).Rotation
		end
	end
	entry.Rotation = entry.Rotation and entry.Rotation:Lerp(desiredRotation, 1 - math.exp(-ROTATION_SMOOTHING * dt))
		or desiredRotation

	local desiredTilt = pouring and math.rad(config.PourTilt) or 0
	entry.Tilt += (desiredTilt - entry.Tilt) * (1 - math.exp(-TILT_SMOOTHING * dt))

	-- lean into the direction of travel, wobble a bit
	local localVel = entry.Rotation:VectorToObjectSpace(entry.Velocity)
	local desiredLean = Vector2.new(math.clamp(localVel.Z * 0.04, -0.5, 0.5), math.clamp(-localVel.X * 0.04, -0.5, 0.5))
	entry.Lean = entry.Lean and entry.Lean:Lerp(desiredLean, 1 - math.exp(-LEAN_SMOOTHING * dt)) or desiredLean

	-- "aligned" frame: where the can would be if its spout already pointed at -Z (turns with the player / toward the
	-- plant and tilts while pouring). RotationOffset only fixes the MODEL, so the spout is measured in this frame.
	local offset = config.RotationOffset
	local aligned = CFrame.new(position) * entry.Rotation * CFrame.Angles(-entry.Tilt, 0, 0)
	local cframe = aligned * CFrame.Angles(math.rad(offset.X), math.rad(offset.Y), math.rad(offset.Z))
	entry.Model:PivotTo(cframe)
	entry.TopPosition = position + Vector3.new(0, height * 0.4, 0)

	-- spout position (used by the water stream)
	local spout = entry.Spout
	if spout and spout:IsA("Attachment") then
		entry.SpoutPosition = spout.WorldPosition
	elseif spout and spout:IsA("BasePart") then
		entry.SpoutPosition = spout.Position
	else
		entry.SpoutPosition = (aligned * CFrame.new(config.SpoutOffset * scale)).Position
	end
end

---- Public API

--- World position of the player's can spout, or nil if no can is shown.
function WateringCanVisual_Controller:GetSpoutPosition(player)
	local entry = entries[player]
	return entry and entry.SpoutPosition
end

--- World position just above the opening of the player's can, or nil if no can is shown.
function WateringCanVisual_Controller:GetTopPosition(player)
	local entry = entries[player]
	return entry and entry.TopPosition
end

function WateringCanVisual_Controller:KnitStart()
	RunService.RenderStepped:Connect(function(dt)
		local plantTarget = WaterState.GetPlantTarget()
		for _, player in ipairs(Players:GetPlayers()) do
			update(player, dt, plantTarget)
		end
	end)

	Players.PlayerRemoving:Connect(destroyEntry)
end

function WateringCanVisual_Controller:KnitInit() end

return WateringCanVisual_Controller
