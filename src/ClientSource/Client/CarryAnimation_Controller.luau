local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local WaterState = require(ReplicatedStorage.ClientSource.Utilities.WaterState)

--[[
	Raises the arms of every player who is carrying water, as if holding the can overhead.
	Done procedurally on the shoulder Motor6D `C0` (animations only write `Transform`, so the
	default Animate script keeps working on top). Each client animates every character from
	replicated attributes, so no animation assets are needed.
]]
local CarryAnimation_Controller = Knit.CreateController({
	Name = "CarryAnimation_Controller",
})

local R15_RAISE = math.rad(158) -- rotation of R15 shoulders (around X) to point the arms up/forward
local R6_RAISE = 2.8 -- radians, like Motor6D.DesiredAngle for R6 shoulders
local SPEED = 9 -- blend speed (1/s)

local states = {} -- [player] = { Character, Alpha, Motors = { { Motor, C0, Build } } }

--- Finds the shoulder motors of a character (R15 or R6) with a function that builds the raised C0.
local function findMotors(character)
	local motors = {}

	local function add(motor, build)
		if motor and motor:IsA("Motor6D") then
			table.insert(motors, { Motor = motor, C0 = motor.C0, Build = build })
		end
	end

	local rightUpperArm = character:FindFirstChild("RightUpperArm")
	local leftUpperArm = character:FindFirstChild("LeftUpperArm")
	if rightUpperArm and leftUpperArm then -- R15
		local function raise(alpha)
			return CFrame.Angles(R15_RAISE * alpha, 0, 0)
		end
		add(rightUpperArm:FindFirstChild("RightShoulder"), raise)
		add(leftUpperArm:FindFirstChild("LeftShoulder"), raise)
	else
		local torso = character:FindFirstChild("Torso")
		if torso then -- R6
			add(torso:FindFirstChild("Right Shoulder"), function(alpha)
				return CFrame.Angles(0, 0, R6_RAISE * alpha)
			end)
			add(torso:FindFirstChild("Left Shoulder"), function(alpha)
				return CFrame.Angles(0, 0, -R6_RAISE * alpha)
			end)
		end
	end
	return motors
end

local function restore(state)
	for _, entry in ipairs(state.Motors) do
		if entry.Motor.Parent then
			entry.Motor.C0 = entry.C0
		end
	end
end

local function update(player, dt)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local alive = humanoid ~= nil and humanoid.Health > 0

	local state = states[player]
	if state and state.Character ~= character then
		states[player] = nil -- new character: old motors are gone
		state = nil
	end

	local carrying = alive and WaterState.GetWater(player) > 0
	if not state then
		if not carrying then
			return
		end
		local motors = findMotors(character)
		if #motors == 0 then
			return
		end
		state = { Character = character, Alpha = 0, Motors = motors }
		states[player] = state
	end

	local target = carrying and 1 or 0
	state.Alpha += (target - state.Alpha) * (1 - math.exp(-SPEED * dt))

	if target == 0 and state.Alpha < 0.01 then
		restore(state)
		states[player] = nil
		return
	end

	for _, entry in ipairs(state.Motors) do
		if entry.Motor.Parent then
			entry.Motor.C0 = entry.C0 * entry.Build(state.Alpha)
		end
	end
end

function CarryAnimation_Controller:KnitStart()
	RunService.Stepped:Connect(function(_, dt)
		for _, player in ipairs(Players:GetPlayers()) do
			update(player, dt)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

function CarryAnimation_Controller:KnitInit() end

return CarryAnimation_Controller
