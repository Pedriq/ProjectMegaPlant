local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Vide = require(ReplicatedStorage.Packages.Vide)
local TrainingConfig = require(ReplicatedStorage.SharedSource.Datas.TrainingConfig)
local Plastic = require(ReplicatedStorage.ClientSource.UI.Plastic)
local WaitFor = require(ReplicatedStorage.ClientSource.Utilities.WaitFor)

local create = Vide.create
local source = Vide.source

--[[
	Client side of training:
	  - disables the default player controls while the server says the player is training
	    (the server also freezes the character, this just hides the joystick / stops input)
	  - shows a Cancel button at the bottom of the screen
	The server decides everything; this only reacts to the replicated TrainingStation attribute,
	so the controls are restored whenever the attribute clears (cancel, death, respawn, ...).
]]
local Training_Controller = Knit.CreateController({
	Name = "Training_Controller",
})

local player = Players.LocalPlayer
local ATTRIBUTE = TrainingConfig.Attribute

---- Controls

local controls -- PlayerModule controls, loaded asynchronously
local controlsWanted = true

local function applyControls()
	if not controls then
		return
	end
	local ok, err = pcall(function()
		if controlsWanted then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
	if not ok then
		warn("Training_Controller: could not toggle controls: " .. tostring(err))
	end
end

local function setControlsEnabled(enabled)
	controlsWanted = enabled
	applyControls()
end

---- UI

local function activityOf(stationId)
	local activityId = stationId and stationId:match("%.(%w+)$")
	return activityId and TrainingConfig.Activities[activityId]
end

local function TrainingUI(station, onCancel)
	-- keep the last title while the panel animates out
	local lastTitle = source("")
	Vide.effect(function()
		local activity = activityOf(station())
		if activity then
			lastTitle(activity.Title)
		end
	end)

	local scale = Vide.spring(function()
		return station() and 1 or 0
	end, 0.25, 0.7)

	return create("ScreenGui")({
		Name = "TrainingHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = function()
			return scale() > 0.02 or station() ~= nil
		end,

		create("Frame")({
			Name = "Root",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.97),
			Size = UDim2.fromScale(0.4, 0.2),
			BackgroundTransparency = 1,

			create("UIAspectRatioConstraint")({
				AspectRatio = 3.6,
				AspectType = Enum.AspectType.FitWithinMaxSize,
			}),
			create("UIScale")({
				Scale = function()
					return math.max(scale(), 0.001)
				end,
			}),

			Plastic.Label({
				Name = "Title",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.fromScale(0.8, 0.3),
				Text = function()
					return lastTitle()
				end,
			}),

			Plastic.Panel({
				Name = "CancelButton",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 1),
				Size = UDim2.fromScale(0.5, 0.62),
				BodyColor = Color3.fromRGB(255, 104, 104),
				BorderColor = Color3.fromRGB(150, 36, 52),
				Corner = 0.35,
				Children = {
					Plastic.Label({
						Name = "Text",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromScale(0.7, 0.62),
						Text = "Cancel",
					}),
					-- invisible hit area covering the whole button
					create("TextButton")({
						Name = "Hit",
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Text = "",
						ZIndex = 10,
						Activated = onCancel,
					}),
				},
			}),
		}),
	})
end

---- Lifecycle

function Training_Controller:KnitStart()
	local training = Knit.GetService("Training_Service")

	local station = source(player:GetAttribute(ATTRIBUTE))

	local function onAttributeChanged()
		local value = player:GetAttribute(ATTRIBUTE)
		station(value)
		setControlsEnabled(value == nil)
	end
	player:GetAttributeChangedSignal(ATTRIBUTE):Connect(onAttributeChanged)

	-- a new character must never inherit disabled controls
	player.CharacterAdded:Connect(function()
		if player:GetAttribute(ATTRIBUTE) == nil then
			setControlsEnabled(true)
		end
	end)

	Vide.mount(function()
		return TrainingUI(station, function()
			training:CancelTraining():catch(warn)
		end)
	end, player:WaitForChild("PlayerGui"))

	-- the PlayerModule loads asynchronously
	task.spawn(function()
		local playerScripts = WaitFor.Child(player, "PlayerScripts")
		local moduleScript = playerScripts and WaitFor.Child(playerScripts, "PlayerModule", 60)
		if not moduleScript then
			warn("Training_Controller: PlayerModule not found, default controls can't be toggled")
			return
		end
		local ok, module = pcall(require, moduleScript)
		if ok then
			controls = module:GetControls()
			controlsWanted = player:GetAttribute(ATTRIBUTE) == nil
			applyControls()
		else
			warn("Training_Controller: PlayerModule unavailable: " .. tostring(module))
		end
	end)
end

function Training_Controller:KnitInit() end

return Training_Controller
