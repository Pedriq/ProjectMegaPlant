local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local TrainingConfig = require(ReplicatedStorage.SharedSource.Datas.TrainingConfig)

--[[
	When the local player trains at a station, the other players training at the SAME station are
	drawn more transparent so the local character stays prominent. Purely local: nothing is
	replicated and no one else's view changes.

	Original transparencies are remembered per instance and restored as soon as the other player
	stops training, leaves, respawns, or the local player stops training.
]]
local TrainingTransparency_Controller = Knit.CreateController({
	Name = "TrainingTransparency_Controller",
})

local localPlayer = Players.LocalPlayer
local ATTRIBUTE = TrainingConfig.Attribute

-- [player] = { Character, Originals = { [instance] = original transparency }, Connection }
local faded = {}

local function isFadeable(instance)
	return instance:IsA("BasePart") or instance:IsA("Decal")
end

local function fadeInstance(record, instance)
	if not isFadeable(instance) or record.Originals[instance] ~= nil then
		return
	end
	local original = instance.Transparency
	record.Originals[instance] = original
	-- never make something *less* transparent (e.g. the invisible HumanoidRootPart stays invisible)
	instance.Transparency = math.max(original, TrainingConfig.OtherTraineeTransparency)
end

local function restore(player)
	local record = faded[player]
	if not record then
		return
	end
	faded[player] = nil
	if record.Connection then
		record.Connection:Disconnect()
	end
	for instance, original in pairs(record.Originals) do
		if instance.Parent then
			instance.Transparency = original
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

	record = { Character = character, Originals = {}, Connection = nil }
	faded[player] = record
	for _, descendant in ipairs(character:GetDescendants()) do
		fadeInstance(record, descendant)
	end
	-- accessories / tools that appear later
	record.Connection = character.DescendantAdded:Connect(function(descendant)
		fadeInstance(record, descendant)
	end)
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

function TrainingTransparency_Controller:KnitInit() end

return TrainingTransparency_Controller
