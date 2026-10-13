local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local TrainingConfig = require(ReplicatedStorage.SharedSource.Datas.TrainingConfig)
local HoldSessions = require(ServerScriptService.ServerSource.Utilities.HoldSessions)

--[[
	Training zones (Workspace/Garden/TrainingZone/<Zone>/<Activity>/Main, see TrainingConfig).
	Every Main part gets a ProximityPrompt. Activating it:
	  - places the character on Main (lying down for Strength, standing/running for Mobility)
	  - freezes the character on the server (anchored root, no walking/jumping) so controls are
	    disabled even if a client misbehaves
	  - sets the replicated player attribute TrainingConfig.Attribute to the station id
	  - grows the activity's stat by the zone's GainPerSecond until training stops
	Training stops on cancel (the Cancel button or a jump, both call CancelTraining), death, respawn,
	leaving, or if the character disappears.
	Everything that was changed is restored by one function (stop), so controls always come back.
]]
local Training_Service = Knit.CreateService({
	Name = "Training_Service",
	Client = {},
})

local Stats_Service

local sessions = HoldSessions.new()
local active = {} -- [player] = training state

---- Helpers

local function getCharacterParts(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and humanoid and root) or humanoid.Health <= 0 then
		return nil
	end
	return character, humanoid, root
end

--- Flat (yaw only) rotation of a part, so tilted parts don't tilt the character.
local function getYaw(part)
	local look = part.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		return CFrame.new()
	end
	return CFrame.lookAt(Vector3.zero, flat.Unit)
end

local function getTrainingCFrame(station, humanoid, root)
	local main = station.Main
	local top = main.Position + Vector3.new(0, main.Size.Y / 2, 0)
	local yaw = getYaw(main)

	if station.Activity.Pose == "Lying" then
		-- on their back, head toward Main's look direction
		local height = TrainingConfig.LyingHeight
		return CFrame.new(top + Vector3.new(0, height, 0)) * yaw * CFrame.Angles(math.rad(90), 0, 0)
	end

	-- standing: feet on the surface
	local height = humanoid.HipHeight + root.Size.Y / 2
	return CFrame.new(top + Vector3.new(0, height, 0)) * yaw
end

local function playAnimation(humanoid, activity)
	local ids = activity.Animation
	if not ids then
		return nil
	end
	local id = humanoid.RigType == Enum.HumanoidRigType.R15 and ids.R15 or ids.R6
	if not id then
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok or not track then
		return nil
	end
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action
	track:Play(0.15)
	return track
end

---- Stop / start

--- Ends training and restores everything. Safe to call at any time, any number of times.
local function stopTraining(player)
	local state = active[player]
	if not state then
		return
	end
	active[player] = nil
	sessions:Stop(player)

	for _, connection in ipairs(state.Connections) do
		connection:Disconnect()
	end
	if state.Track then
		state.Track:Stop(0.1)
		state.Track:Destroy()
	end

	local humanoid, root = state.Humanoid, state.Root
	if humanoid and humanoid.Parent then
		humanoid.PlatformStand = state.Saved.PlatformStand
		humanoid.AutoRotate = state.Saved.AutoRotate
		humanoid.UseJumpPower = state.Saved.UseJumpPower
		humanoid.JumpPower = state.Saved.JumpPower
		humanoid.JumpHeight = state.Saved.JumpHeight
	end
	if root and root.Parent then
		-- stand the character up on top of the station and release it
		local position = root.Position + Vector3.new(0, 3, 0)
		root.CFrame = CFrame.new(position) * getYaw(root)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.Anchored = false
	end
	if humanoid and humanoid.Parent then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end

	player:SetAttribute(TrainingConfig.Attribute, nil)
	Stats_Service:ApplyMovementSpeed(player)
end

local function startTraining(player, station)
	if active[player] then
		return
	end
	local character, humanoid, root = getCharacterParts(player)
	if not character then
		return
	end
	-- locked zones can't be used, whatever the client claims
	local unlocked = TrainingConfig.IsUnlocked(station.ZoneId, function(statKey)
		return Stats_Service:GetStat(player, statKey)
	end)
	if not unlocked then
		return
	end
	local maxDistance = TrainingConfig.Prompt.MaxActivationDistance + TrainingConfig.DistanceTolerance
	if (root.Position - station.Main.Position).Magnitude > maxDistance then
		return
	end

	local state = {
		Station = station,
		Character = character,
		Humanoid = humanoid,
		Root = root,
		Connections = {},
		Saved = {
			PlatformStand = humanoid.PlatformStand,
			AutoRotate = humanoid.AutoRotate,
			UseJumpPower = humanoid.UseJumpPower,
			JumpPower = humanoid.JumpPower,
			JumpHeight = humanoid.JumpHeight,
		},
	}
	active[player] = state

	-- freeze the character (server side, so it can't be bypassed on the client)
	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.PlatformStand = station.Activity.Pose == "Lying"
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = getTrainingCFrame(station, humanoid, root)
	root.Anchored = true

	player:SetAttribute(TrainingConfig.Attribute, station.Id)
	state.Track = playAnimation(humanoid, station.Activity)

	-- anything that removes the character ends the training
	table.insert(state.Connections, humanoid.Died:Connect(function()
		stopTraining(player)
	end))
	table.insert(state.Connections, character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			stopTraining(player)
		end
	end))

	-- stat growth
	local gainPerSecond = TrainingConfig.GetGainPerSecond(station.ZoneId, station.ActivityId)
	local stat = station.Activity.Stat
	local accumulated, sinceApply = 0, 0
	sessions:Start(player, function(dt)
		if not active[player] then
			return false
		end
		accumulated += gainPerSecond * dt
		sinceApply += dt
		if sinceApply >= TrainingConfig.ApplyInterval then
			sinceApply = 0
			local whole = math.floor(accumulated)
			if whole >= 1 then
				accumulated -= whole
				Stats_Service:AddStat(player, stat, whole)
			end
		end
		return true
	end)
end

---- Setup

local function createPrompt(station)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TrainingPrompt"
	prompt.ObjectText = TrainingConfig.Zones[station.ZoneId].DisplayName
	prompt:SetAttribute("ZoneId", station.ZoneId) -- lets clients show the lock state
	prompt.ActionText = station.Activity.ActionText
	prompt.HoldDuration = TrainingConfig.Prompt.HoldDuration
	prompt.KeyboardKeyCode = TrainingConfig.Prompt.KeyboardKeyCode
	prompt.GamepadKeyCode = TrainingConfig.Prompt.GamepadKeyCode
	prompt.RequiresLineOfSight = TrainingConfig.Prompt.RequiresLineOfSight
	prompt.MaxActivationDistance = TrainingConfig.Prompt.MaxActivationDistance
	prompt.Parent = station.Main

	prompt.Triggered:Connect(function(player)
		startTraining(player, station)
	end)
end

local function setupStations()
	local root = workspace
	for _, name in ipairs(TrainingConfig.RootPath) do
		root = root and root:WaitForChild(name, 30)
	end
	if not root then
		warn("Training_Service: Workspace/" .. table.concat(TrainingConfig.RootPath, "/") .. " not found")
		return
	end

	for zoneId in pairs(TrainingConfig.Zones) do
		local zone = root:WaitForChild(zoneId, 10)
		for activityId, activity in pairs(TrainingConfig.Activities) do
			local folder = zone and zone:WaitForChild(activityId, 10)
			local main = folder and folder:WaitForChild("Main", 10)
			if main and main:IsA("BasePart") then
				createPrompt({
					Id = zoneId .. "." .. activityId,
					ZoneId = zoneId,
					ActivityId = activityId,
					Activity = activity,
					Main = main,
				})
			else
				warn(("Training_Service: %s/%s/Main not found"):format(zoneId, activityId))
			end
		end
	end
end

---- Public API / remotes

function Training_Service:IsTraining(player)
	return active[player] ~= nil
end

function Training_Service:Stop(player)
	stopTraining(player)
end

--- Called by the Cancel button.
function Training_Service.Client:CancelTraining(player)
	stopTraining(player)
end

function Training_Service:KnitStart()
	Stats_Service = Knit.GetService("Stats_Service")

	local function watch(player)
		-- a new character (respawn) always ends training and restores the player
		player.CharacterRemoving:Connect(function()
			stopTraining(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerRemoving:Connect(stopTraining)

	task.spawn(setupStations)
end

function Training_Service:KnitInit() end

return Training_Service
