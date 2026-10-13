--[[
	The "shop opening" effect: while the shop is open the background is blurred and the camera smoothly
	zooms out; closing it eases everything back and then restores the player's original camera settings.

	It drives the camera only through Player.CameraMin/MaxZoomDistance and Camera.FieldOfView, so the
	normal camera script keeps working (rotation, collisions) and nothing is left modified afterwards.

		ShopCamera.SetOpen(true)   -- blur in + zoom out
		ShopCamera.SetOpen(false)  -- blur out + zoom back, then restore the original settings
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UpgradesConfig = require(ReplicatedStorage.SharedSource.Datas.UpgradesConfig)

local ShopCamera = {}

local SPEED = 7 -- easing speed (1/s)
local BINDING = "ShopCameraEffect"

local player = Players.LocalPlayer

local target = 0 -- 1 = fully open
local alpha = 0 -- current eased progress
local running = false
local saved, blur, startDistance

local function restore()
	if blur then
		blur:Destroy()
		blur = nil
	end
	local camera = workspace.CurrentCamera
	if saved then
		player.CameraMaxZoomDistance = saved.Max
		player.CameraMinZoomDistance = saved.Min
		if camera then
			camera.FieldOfView = saved.FieldOfView
		end
		saved = nil
	end
end

local function step(dt)
	local camera = workspace.CurrentCamera
	if not camera or not saved then
		return
	end

	alpha += (target - alpha) * (1 - math.exp(-SPEED * dt))
	local settings = UpgradesConfig.Camera

	-- smooth zoom: both limits follow the same distance, which moves the camera back
	local distance = startDistance + settings.ZoomOutStuds * alpha
	player.CameraMaxZoomDistance = distance
	player.CameraMinZoomDistance = distance
	camera.FieldOfView = saved.FieldOfView + settings.FieldOfViewIncrease * alpha

	if blur then
		blur.Size = settings.BlurSize * alpha
	end

	-- fully closed again: give everything back and stop
	if target == 0 and alpha < 0.004 then
		running = false
		alpha = 0
		RunService:UnbindFromRenderStep(BINDING)
		restore()
	end
end

function ShopCamera.SetOpen(open)
	target = open and 1 or 0
	if not open or running then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	running = true
	saved = {
		Min = player.CameraMinZoomDistance,
		Max = player.CameraMaxZoomDistance,
		FieldOfView = camera.FieldOfView,
	}
	startDistance = math.clamp((camera.CFrame.Position - camera.Focus.Position).Magnitude, saved.Min, saved.Max)

	blur = Instance.new("BlurEffect")
	blur.Name = "ShopBlur"
	blur.Size = 0
	blur.Parent = Lighting

	-- just before the default camera script, so it already sees our zoom limits this frame
	RunService:BindToRenderStep(BINDING, Enum.RenderPriority.Camera.Value - 1, step)
end

--- True while the effect is active (opening, open or closing).
function ShopCamera.IsActive()
	return running
end

return ShopCamera
