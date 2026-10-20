local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local TrainingConfig = require(ReplicatedStorage.SharedSource.Datas.TrainingConfig)

--[[
	When the local player trains at a station, the other players training at the SAME station are hidden, so only
	the local character is seen there (TrainingConfig.OtherTraineeTransparency, 1 = invisible). Hidden with them:
	  - their particle effects, trails and beams, and their overhead name tag
	  - the barbell they hold (TrainingBarbells/TrainingBarbell, tagged with OwnerUserId by BarbellRig)
	Purely local: nothing is replicated and no one else's view changes.

	Original values are remembered per instance and restored as soon as the other player stops training, leaves,
	respawns, or the local player stops training.
]]
local TrainingTransparency_Controller = Knit.CreateController({
	Name = "TrainingTransparency_Controller",
})

local localPlayer = Players.LocalPlayer
local ATTRIBUTE = TrainingConfig.Attribute
local BARBELLS_FOLDER = "TrainingBarbells"

-- [player] = { Character, Originals = { [instance] = { Property, Value } }, Connections = {} }
local faded = {}

-- the property that hides each kind of instance
local function hiddenProperty(instance)
	if instance:IsA("BasePart") or instance:IsA("Decal") then
		return "Transparency", math.max(instance.Transparency, TrainingConfig.OtherTraineeTransparency)
	elseif instance:IsA("ParticleEmitter") or instance:IsA("Trail") or instance:IsA("Beam") then
		return "Enabled", false
	elseif instance:IsA("BillboardGui") or instance:IsA("SurfaceGui") then
		return "Enabled", false
	elseif instance:IsA("Humanoid") then
		return "DisplayDistanceType", Enum.HumanoidDisplayDistanceType.None
	end
	return nil
end

local function fadeInstance(record, instance)
	if record.Originals[instance] ~= nil then
		return
	end
	local property, hidden = hiddenProperty(instance)
	if not property then
		return
	end
	-- never make something *less* hidden (e.g. the invisible HumanoidRootPart stays invisible): Transparency uses
	-- math.max above, the other properties only ever turn things off
	record.Originals[instance] = { Property = property, Value = instance[property] }
	instance[property] = hidden
end

local function restore(player)
	local record = faded[player]
	if not record then
		return
	end
	faded[player] = nil
	for _, connection in ipairs(record.Connections) do
		connection:Disconnect()
	end
	for instance, original in pairs(record.Originals) do
		if instance.Parent then
			instance[original.Property] = original.Value
		end
	end
end

local function fade(player)
	local character = player.Character
	if not character then
		return
	end

	local record = faded[player]
	if record and record.Character ~= character then
		restore(player) -- old character is gone, start over with the new one
		record = nil
	end
	if record then
		return
	end

	record = { Character = character, Originals = {}, Connections = {} }
	faded[player] = record
	for _, descendant in ipairs(character:GetDescendants()) do
		fadeInstance(record, descendant)
	end
	-- accessories / tools / effects that appear later
	table.insert(record.Connections, character.DescendantAdded:Connect(function(descendant)
		fadeInstance(record, descendant)
	end))

	-- the barbell(s) this player holds: the existing ones, and the ones that are created while they train
	local function hideBar(bar)
		if bar:GetAttribute("OwnerUserId") == player.UserId then
			for _, descendant in ipairs(bar:GetDescendants()) do
				fadeInstance(record, descendant)
			end
			fadeInstance(record, bar)
		end
	end
	local folder = workspace:FindFirstChild(BARBELLS_FOLDER)
	if folder then
		for _, bar in ipairs(folder:GetChildren()) do
			hideBar(bar)
		end
		table.insert(record.Connections, folder.ChildAdded:Connect(function(bar)
			-- the owner attribute is set right after the clone is created, so give it a frame
			task.defer(hideBar, bar)
		end))
	end
end

--- Decides for one other player whether they should currently be faded.
local function refresh(player)
	if player == localPlayer then
		return
	end
	local mine = localPlayer:GetAttribute(ATTRIBUTE)
	if mine ~= nil and player:GetAttribute(ATTRIBUTE) == mine and player.Character then
		fade(player)
	else
		restore(player)
	end
end

local function refreshAll()
	for _, player in ipairs(Players:GetPlayers()) do
		refresh(player)
	end
end

local function watch(player)
	if player == localPlayer then
		return
	end
	player:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
		refresh(player)
	end)
	player.CharacterAdded:Connect(function()
		restore(player)
		task.defer(refresh, player) -- let the character finish loading first
	end)
	refresh(player)
end

function TrainingTransparency_Controller:KnitStart()
	localPlayer:GetAttributeChangedSignal(ATTRIBUTE):Connect(refreshAll)

	Players.PlayerAdded:Connect(watch)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end

	Players.PlayerRemoving:Connect(restore)
end

--- Hides / shows a player's character and barbell by hand, whatever station they are at (debug / tests).
function TrainingTransparency_Controller:SetHidden(player, hidden)
	if hidden then
		fade(player)
	else
		restore(player)
	end
end

function TrainingTransparency_Controller:KnitInit() end

return TrainingTransparency_Controller
