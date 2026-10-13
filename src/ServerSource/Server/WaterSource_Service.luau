local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local WaterConfig = require(ReplicatedStorage.SharedSource.Datas.WaterConfig)
local HoldSessions = require(ServerScriptService.ServerSource.Utilities.HoldSessions)

local ATTR = WaterConfig.Attributes

--[[
	Water sources (see WaterConfig.Sources). Each one gets a hold-to-fill ProximityPrompt.
	While the player holds it, their can fills at the can's FillRate until they release the
	prompt, run away, or the can is full. Everything is validated on the server.
]]
local WaterSource_Service = Knit.CreateService({
	Name = "WaterSource_Service",
	Client = {},
})

local Water_Service, Upgrade_Service
local sessions = HoldSessions.new()

local function resolvePath(path)
	local instance = workspace
	for _, name in ipairs(path) do
		instance = instance and instance:WaitForChild(name, 30)
	end
	return instance
end

--- A BasePart to hang a prompt on (the instance itself, a model's primary part, or its first part).
local function getAnchorPart(instance)
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function isInRange(player, part, maxDistance)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	return (root.Position - part.Position).Magnitude <= maxDistance + WaterConfig.DistanceTolerance
end

local function startFilling(player, part, source)
	if Water_Service:IsFull(player) then
		return
	end

	local can = Water_Service:GetCan(player)
	local baseRate = can.FillRate * (source.FillMultiplier or 1)

	player:SetAttribute(ATTR.Filling, true)
	sessions:Start(player, function(dt)
		if not isInRange(player, part, source.MaxActivationDistance) then
			return false
		end
		-- the Water Collection Speed upgrade is read every tick, so a purchase applies immediately
		Water_Service:AddWater(player, baseRate * Upgrade_Service:GetMultiplier(player, "FillSpeed") * dt)
		return not Water_Service:IsFull(player)
	end, function()
		player:SetAttribute(ATTR.Filling, false)
	end)
end

local function setupSource(source)
	local instance = resolvePath(source.Path)
	local part = instance and getAnchorPart(instance)
	if not part then
		warn("WaterSource_Service: water source not found: Workspace/" .. table.concat(source.Path, "/"))
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FillWaterPrompt"
	prompt.ObjectText = source.ObjectText
	prompt.ActionText = source.ActionText
	prompt.HoldDuration = WaterConfig.Prompt.HoldDuration
	prompt.KeyboardKeyCode = WaterConfig.Prompt.KeyboardKeyCode
	prompt.GamepadKeyCode = WaterConfig.Prompt.GamepadKeyCode
	prompt.RequiresLineOfSight = WaterConfig.Prompt.RequiresLineOfSight
	prompt.MaxActivationDistance = source.MaxActivationDistance
	prompt.Parent = part

	prompt.PromptButtonHoldBegan:Connect(function(player)
		if isInRange(player, part, source.MaxActivationDistance) then
			startFilling(player, part, source)
		end
	end)
	prompt.PromptButtonHoldEnded:Connect(function(player)
		sessions:Stop(player)
	end)
end

function WaterSource_Service:KnitStart()
	Water_Service = Knit.GetService("Water_Service")
	Upgrade_Service = Knit.GetService("Upgrade_Service")

	Players.PlayerRemoving:Connect(function(player)
		sessions:Stop(player)
	end)

	for _, source in ipairs(WaterConfig.Sources) do
		task.spawn(setupSource, source)
	end
end

function WaterSource_Service:KnitInit() end

return WaterSource_Service
