local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

--[[
	The barbell of a strength station (the bench press). While a player trains Strength:
	  1. the barbell on the rack is hidden and a copy of it is lifted OFF the rack into the player's hands
	     (the copy flies to the live hand positions, so it arrives wherever the animation has them)
	  2. it is welded to the hand, so it follows the training animation (the arms push it up and down)
	  3. when training ends it is put back ON the rack and the rack's own barbell shows again

	Everything is server-side (the weld and the animation replicate), and several players can train at one
	bench: the rack's barbell stays hidden until the last one has put theirs back.

	BarbellRig.Start(character, main, trainingRoot, options) -> rig or nil (R6 characters have no hands)
	rig:Stop(immediate)   immediate = true skips the flight back (the player left / died)

	options.LiftTime / options.ReturnTime  seconds of the two flights (see TrainingConfig.Activities.Strength)
]]
local BarbellRig = {}
BarbellRig.__index = BarbellRig

local FOLDER_NAME = "TrainingBarbells"
local USERS_ATTRIBUTE = "BarbellUsers" -- on the rack's barbell: how many players currently use it
local ORIGINAL_ATTRIBUTE = "BarbellOriginalTransparency"
local DEFAULT_LIFT_TIME = 0.55
local DEFAULT_RETURN_TIME = 0.45
local MAX_BENCH_DISTANCE = 10 -- studs from the station's Main to the bench it belongs to

---- Finding the rack

--- The bench model that belongs to a station: the nearest one to its Main part. (Benches are matched by distance
--- on purpose: some are not parented to the zone they stand in.)
local function findBench(trainingRoot, main)
	local best, bestDistance
	local function consider(model)
		if model:IsA("Model") and model.Name:match("^Bench%d+$") then
			local delta = (model:GetPivot().Position - main.Position) * Vector3.new(1, 0, 1)
			if not bestDistance or delta.Magnitude < bestDistance then
				best, bestDistance = model, delta.Magnitude
			end
		end
	end
	for _, child in ipairs(trainingRoot:GetChildren()) do
		consider(child)
		if child:IsA("Model") and child.Name:match("^Zone%d+$") then
			for _, inner in ipairs(child:GetChildren()) do
				consider(inner)
			end
		end
	end
	if best and bestDistance <= MAX_BENCH_DISTANCE then
		return best
	end
	return nil
end

local function findRackBar(trainingRoot, main)
	local bench = findBench(trainingRoot, main)
	if not bench then
		return nil
	end
	for _, descendant in ipairs(bench:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name:match("Barbell$") then
			return descendant
		end
	end
	return nil
end

local function getFolder()
	local folder = workspace:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = workspace
	end
	return folder
end

---- Rig

function BarbellRig.Start(character, main, trainingRoot, options)
	options = options or {}
	local rightHand = character:FindFirstChild("RightHand")
	local leftHand = character:FindFirstChild("LeftHand")
	if not (rightHand and leftHand) then
		return nil
	end
	local rack = findRackBar(trainingRoot, main)
	if not rack then
		return nil
	end

	-- hide the rack's barbell for as long as somebody has it (remember its real transparency once)
	local users = rack:GetAttribute(USERS_ATTRIBUTE) or 0
	if users == 0 then
		rack:SetAttribute(ORIGINAL_ATTRIBUTE, rack.Transparency)
		rack.Transparency = 1
	end
	rack:SetAttribute(USERS_ATTRIBUTE, users + 1)

	local bar = rack:Clone()
	bar.Name = "TrainingBarbell"
	for _, descendant in ipairs(bar:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		end
	end
	bar.Transparency = rack:GetAttribute(ORIGINAL_ATTRIBUTE) or 0
	bar.Anchored = true -- flying by script first, welded to the hand afterwards
	bar.CanCollide = false
	bar.CanTouch = false
	bar.CanQuery = false
	bar.Massless = true
	bar.CFrame = rack.CFrame
	bar.Parent = getFolder()

	local self = setmetatable({
		Rack = rack,
		Bar = bar,
		RackCFrame = rack.CFrame,
		RightHand = rightHand,
		LeftHand = leftHand,
		ReturnTime = options.ReturnTime or DEFAULT_RETURN_TIME,
		Stopped = false,
	}, BarbellRig)

	-- the bar keeps its own orientation (it already lies across the bench); only its position follows the hands:
	-- the middle between them
	local rotation = rack.CFrame.Rotation
	local function gripCFrame()
		return CFrame.new((leftHand.Position + rightHand.Position) / 2) * rotation
	end

	local liftTime = options.LiftTime or DEFAULT_LIFT_TIME
	local startTime = os.clock()
	self.Connection = RunService.Heartbeat:Connect(function()
		if not (bar.Parent and rightHand.Parent and leftHand.Parent) then
			self.Connection:Disconnect()
			self.Connection = nil
			return
		end
		local alpha = math.clamp((os.clock() - startTime) / liftTime, 0, 1)
		local eased = TweenService:GetValue(alpha, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		bar.CFrame = self.RackCFrame:Lerp(gripCFrame(), eased)
		if alpha >= 1 then
			self.Connection:Disconnect()
			self.Connection = nil
			-- in the hands: from now on it moves with the animation
			local weld = Instance.new("WeldConstraint")
			weld.Name = "Grip"
			weld.Part0 = rightHand
			weld.Part1 = bar
			weld.Parent = bar
			bar.Anchored = false
		end
	end)

	return self
end

--- Puts the barbell back on the rack and shows the rack's own one again.
function BarbellRig:Stop(immediate)
	if self.Stopped then
		return
	end
	self.Stopped = true
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end

	local bar, rack = self.Bar, self.Rack
	local function finish()
		bar:Destroy()
		if rack.Parent then
			local users = (rack:GetAttribute(USERS_ATTRIBUTE) or 1) - 1
			if users <= 0 then
				rack.Transparency = rack:GetAttribute(ORIGINAL_ATTRIBUTE) or 0
				rack:SetAttribute(USERS_ATTRIBUTE, nil)
			else
				rack:SetAttribute(USERS_ATTRIBUTE, users)
			end
		end
	end

	if immediate or not bar.Parent then
		finish()
		return
	end
	local grip = bar:FindFirstChild("Grip")
	if grip then
		grip:Destroy()
	end
	bar.Anchored = true
	local tween = TweenService:Create(
		bar,
		TweenInfo.new(self.ReturnTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{ CFrame = self.RackCFrame }
	)
	tween.Completed:Once(finish)
	tween:Play()
end

return BarbellRig
