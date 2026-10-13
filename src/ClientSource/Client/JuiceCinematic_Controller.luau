local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local JuiceConfig = require(ReplicatedStorage.SharedSource.Datas.JuiceConfig)
local Effects = require(ReplicatedStorage.ClientSource.UI.Effects)
local ShopCamera = require(ReplicatedStorage.ClientSource.UI.ShopCamera)

--[[
	Client side of the "plant finished" sequence (see JuiceConfig / JuicePool_Service):

	  - orbits the camera around the launched plant, then back to the player
	  - launch trail, explosion burst, screen flash, camera shake
	  - gives the juice pools a gentle pulse and announces the pool appearing
	  - announces the boost when the local player steps into a pool

	Everything is timed from the server's start time, so all players see the same moment of explosion.
	The camera is always handed back to the normal camera script, even if something goes wrong.
]]
local JuiceCinematic_Controller = Knit.CreateController({
	Name = "JuiceCinematic_Controller",
})

local player = Players.LocalPlayer
local Audio_Controller, Banner_Controller

local BINDING = "JuiceCinematic"
local running = false

local pools = {} -- [model] = { Juice, Core, CoreBase, Phase }

local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

---- Effects

local function flash(color)
	local gui = Instance.new("ScreenGui")
	gui.Name = "JuiceFlash"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.ResetOnSpawn = false

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.7)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Active = false -- never block input
	frame.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")

	local tween = TweenService:Create(frame, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	})
	tween.Completed:Once(function()
		gui:Destroy()
	end)
	tween:Play()
end

local function explode(data, center)
	local color = data.Color
	local strength = JuiceConfig.GetStrength(data.Multiplier)
	local amount = 1 + strength

	Effects.Burst(center, { Color = color, Count = math.floor(150 * amount), Speed = 55, Size = 2.2, Lifetime = 1.8 })
	Effects.Burst(center, { Color = Color3.new(1, 1, 1), Count = math.floor(70 * amount), Speed = 80, Size = 1.4, Lifetime = 1.2 })
	Effects.Shockwave(center, { Color = color, Size = 40 + 40 * strength, Duration = 1 })
	Effects.Shockwave(center, { Color = Color3.new(1, 1, 1), Size = 22 + 20 * strength, Duration = 0.6 })
	Audio_Controller:Play("PlantExplode", { Pitch = 1 - strength * 0.2 })
	flash(color)
end

---- Camera sequence

local function play(data)
	if running then
		return
	end
	running = true

	local cinematic = JuiceConfig.Cinematic
	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	local useCamera = camera ~= nil
		and root ~= nil
		and (root.Position - data.Position).Magnitude <= cinematic.CameraRange
		and not ShopCamera.IsActive()

	local startCFrame, startFov, startOffset, baseAngle, humanoid
	if useCamera then
		startCFrame = camera.CFrame
		startFov = camera.FieldOfView
		startOffset = startCFrame.Position - root.Position
		humanoid = character:FindFirstChildOfClass("Humanoid")
		baseAngle = math.atan2(startCFrame.Position.Z - data.Position.Z, startCFrame.Position.X - data.Position.X)
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local exploded = false
	local lastTrail = 0
	local lastCenter = data.Position

	local function finish()
		RunService:UnbindFromRenderStep(BINDING)
		running = false
		if useCamera and camera and camera.Parent then
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = startFov
			if humanoid and humanoid.Parent then
				camera.CameraSubject = humanoid
			end
		end
	end

	local function step()
		local elapsed = workspace:GetServerTimeNow() - data.StartTime
		if elapsed >= JuiceConfig.TotalTime then
			finish()
			return
		end

		local height = JuiceConfig.GetLaunchHeight(data.Size.Y, math.min(elapsed, JuiceConfig.ExplosionAt))
		local center = data.Position + Vector3.new(0, height + data.Size.Y / 2, 0)
		lastCenter = center

		-- rising trail
		if elapsed < JuiceConfig.ExplosionAt and elapsed - lastTrail > 0.12 then
			lastTrail = elapsed
			Effects.Burst(center - Vector3.new(0, data.Size.Y / 2, 0), {
				Color = data.Color,
				Count = 6,
				Speed = 9,
				Size = 0.9,
				Lifetime = 0.7,
			})
		end

		if not exploded and elapsed >= JuiceConfig.ExplosionAt then
			exploded = true
			explode(data, center)
		end

		if not useCamera then
			return
		end
		local currentRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not currentRoot then
			useCamera = false
			camera.CameraType = Enum.CameraType.Custom
			return
		end

		-- orbit: a slow circle around the plant that widens a little while it climbs
		local orbit = math.clamp(elapsed / JuiceConfig.ExplosionAt, 0, 1)
		local angle = baseAngle + orbit * cinematic.OrbitTurns * math.pi * 2
		if elapsed > JuiceConfig.ExplosionAt then
			angle += (elapsed - JuiceConfig.ExplosionAt) * 0.12
		end
		local radius = math.max(cinematic.OrbitRadiusMin, data.Size.Magnitude * cinematic.OrbitRadiusPerSize)
		radius *= 1 + 0.25 * orbit
		local lift = radius * (0.12 + 0.2 * math.sin(orbit * math.pi))
		local position = center + Vector3.new(math.cos(angle) * radius, lift, math.sin(angle) * radius)

		-- shake and a field-of-view punch right after the explosion
		local punch = 0
		local shake = Vector3.zero
		if elapsed >= JuiceConfig.ExplosionAt then
			punch = math.max(0, 1 - (elapsed - JuiceConfig.ExplosionAt) / 0.9)
			shake = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2.4 * punch
		end
		local cframe = CFrame.lookAt(position + shake, center)

		-- smooth entry from wherever the player's camera was
		cframe = startCFrame:Lerp(cframe, smooth(elapsed / cinematic.BlendIn))

		-- smooth exit back behind the player
		local outroStart = JuiceConfig.ExplosionAt + 0.9
		if elapsed > outroStart then
			local s = smooth((elapsed - outroStart) / (JuiceConfig.TotalTime - outroStart))
			local rootPosition = currentRoot.Position
			local follow = CFrame.lookAt(rootPosition + startOffset, rootPosition + Vector3.new(0, 2, 0))
			cframe = cframe:Lerp(follow, s)
		end

		camera.CFrame = cframe
		camera.FieldOfView = startFov + 14 * punch
	end

	if (workspace:GetServerTimeNow() - data.StartTime) < 0.6 then
		Audio_Controller:Play("PlantLaunch")
		Effects.Shockwave(data.Position, { Color = data.Color, Size = 16, Duration = 0.7 })
	end

	-- right after the default camera script, so ours wins this frame
	RunService:BindToRenderStep(BINDING, Enum.RenderPriority.Camera.Value + 1, function()
		local ok, err = pcall(step)
		if not ok then
			warn("JuiceCinematic: " .. tostring(err))
			finish()
		end
	end)
end

---- Pools

local function trackPool(model, announce)
	local juice = model:WaitForChild("Juice", 5)
	local core = model:WaitForChild("Core", 5)
	if not juice or not core or pools[model] then
		return
	end
	pools[model] = { Juice = juice, Core = core, CoreBase = core.Transparency, Phase = math.random() * 6 }
	model.Destroying:Once(function()
		pools[model] = nil
	end)

	if announce then
		local radius = model:GetAttribute("Radius") or 8
		local color = model:GetAttribute("Color") or Color3.new(1, 1, 1)
		local center = juice.Position
		Audio_Controller:Play("PoolAppear")
		Effects.Burst(center + Vector3.new(0, 2, 0), { Color = color, Count = 60, Speed = 20, Lifetime = 1.4 })
		Effects.Shockwave(center, { Color = color, Size = radius * 2.4, Duration = 0.9 })
	end
end

local function announceBoost(multiplier)
	local color = Color3.fromRGB(120, 200, 140)
	for model in pairs(pools) do
		color = model:GetAttribute("Color") or color
	end
	Audio_Controller:Play("JuiceEnter")
	Banner_Controller:Show({
		Title = ("JUICE BOOST x%.1f"):format(multiplier),
		Subtitle = "All stats are growing at once!",
		Color = color,
		BorderColor = color:Lerp(Color3.new(0, 0, 0), 0.35),
		Duration = 2,
	})
end

---- Occasional splashes

local SPLASH_VIEW_DISTANCE = 140 -- only pools near the camera splash, so it stays cheap

local function splashRandomly()
	local camera = workspace.CurrentCamera
	for model, pool in pairs(pools) do
		local juice = pool.Juice
		if camera and juice.Parent then
			local radius = model:GetAttribute("Radius") or 10
			local center = juice.Position
			if (camera.CFrame.Position - center).Magnitude - radius < SPLASH_VIEW_DISTANCE then
				local strength = model:GetAttribute("Strength") or 0
				local angle = math.random() * math.pi * 2
				local distance = math.sqrt(math.random()) * radius * 0.88
				local surface = center + Vector3.new(math.cos(angle) * distance, juice.Size.X / 2, math.sin(angle) * distance)
				local big = math.random() < 0.15 + 0.15 * strength
				Effects.Splash(surface, {
					Color = model:GetAttribute("Color") or Color3.new(1, 1, 1),
					Count = (big and 14 or 7) + math.floor(strength * 5),
					Ripple = big and 6 or 3.5,
				})
			end
		end
	end
end

---- Lifecycle

function JuiceCinematic_Controller:KnitStart()
	Audio_Controller = Knit.GetController("Audio_Controller")
	Banner_Controller = Knit.GetController("Banner_Controller")

	local service = Knit.GetService("JuicePool_Service")
	service.Cinematic:Connect(function(data)
		task.spawn(play, data)
	end)

	-- pools that already exist when joining are tracked silently, new ones are announced
	local tag = JuiceConfig.Pool.Tag
	for _, model in ipairs(CollectionService:GetTagged(tag)) do
		task.spawn(trackPool, model, false)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(model)
		task.spawn(trackPool, model, true)
	end)

	-- now and then a pool splashes (a couple of times per second at most, per pool)
	task.spawn(function()
		while true do
			task.wait(0.45 + math.random() * 0.7)
			splashRandomly()
		end
	end)

	-- a gentle living pulse on the juice
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for _, pool in pairs(pools) do
			if pool.Juice.Parent then
				pool.Juice.Transparency = 0.2 + 0.07 * math.sin(t * 2.2 + pool.Phase)
				pool.Core.Transparency = math.clamp(pool.CoreBase + 0.1 * math.sin(t * 3.1 + pool.Phase), 0, 1)
			end
		end
	end)

	-- stepping into a pool
	local attribute = JuiceConfig.BoostAttribute
	local wasInside = player:GetAttribute(attribute) ~= nil
	player:GetAttributeChangedSignal(attribute):Connect(function()
		local multiplier = player:GetAttribute(attribute)
		if multiplier and not wasInside then
			announceBoost(multiplier)
		end
		wasInside = multiplier ~= nil
	end)
end

function JuiceCinematic_Controller:KnitInit() end

return JuiceCinematic_Controller
