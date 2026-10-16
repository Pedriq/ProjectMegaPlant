local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Vide = require(ReplicatedStorage.Packages.Vide)
local UpgradesConfig = require(ReplicatedStorage.SharedSource.Datas.UpgradesConfig)
local RobloxKit = require(ReplicatedStorage.ClientSource.UI.RobloxKit)

local create = Vide.create
local source = Vide.source
local cleanup = Vide.cleanup

--[[
	Custom ProximityPrompts in the Upgrade Shop style. Every prompt in the game is switched to
	Style = Custom on this client only (the servers' prompts and their logic are untouched) and drawn as a
	card above its part:

	  [ E ]  Object text                 (icon)
	         ACTION TEXT
	         [=========-----]   <- only for short holds (e.g. training)

	Each task has its own color and icon (STYLES, by prompt name). Prompts whose ActionText is "Locked"
	(TrainingLock_Controller) turn grey with a lock. Holds of "hold as long as you want" prompts (filling
	the can, watering the plant) show a pulsing glow instead of a progress bar.
	Keyboard shows the key, gamepad the button image, touch "TAP"; on touch the card can be tapped.
	On PC/console the card has no button, so it never catches the mouse.
]]
local Prompt_Controller = Knit.CreateController({
	Name = "Prompt_Controller",
})

local player = Players.LocalPlayer
local rgb = RobloxKit.rgb
local Vertical = RobloxKit.Vertical
local Box = RobloxKit.Box
local Text = RobloxKit.Text
local Corner = RobloxKit.Corner

---- Per-task look (by prompt.Name)

local STYLES = {
	-- Workspace/Garden/WaterSource (WaterSource_Service)
	FillWaterPrompt = { Colors = Vertical(rgb(111, 208, 255), rgb(30, 127, 216)), Icon = "💧" },
	-- Workspace/Garden/PlantBed (Watering_Service)
	WaterPlantPrompt = { Colors = Vertical(rgb(102, 236, 98), rgb(15, 157, 45)), Icon = "🌱" },
	-- training stations (Training_Service)
	TrainingPrompt = { Colors = Vertical(rgb(255, 179, 71), rgb(232, 100, 26)), Icon = "💪" },
	-- the upgrade shop (Upgrade_Service)
	[UpgradesConfig.Shop.PromptName] = { Colors = Vertical(rgb(255, 224, 74), rgb(242, 140, 0)), Icon = "🛒" },
}
-- any prompt added later without its own entry
local DEFAULT_STYLE = { Colors = Vertical(rgb(201, 142, 255), rgb(123, 63, 211)), Icon = "✨" }
-- TrainingLock_Controller writes this ActionText on zones the player hasn't unlocked yet
local LOCKED_ACTION = "Locked"
local LOCKED_STYLE = { Colors = Vertical(rgb(200, 200, 200), rgb(110, 110, 110)), Icon = "🔒" }

local KEY_COLORS = Vertical(rgb(255, 255, 255), rgb(189, 189, 189))
local BAR_COLORS = Vertical(rgb(182, 255, 74), rgb(63, 178, 30))
local KEY_TEXT = rgb(26, 26, 26)

---- Layout (design pixels)

local CARD_W = 300
local CARD_H = 78
local TEXT_X = 76
local TEXT_W = 160
-- holds longer than this are "hold as long as you want" (water prompts use 3600 s): no progress bar
local LONG_HOLD = 30
local OPEN_TIME = 0.15

---- Card

local function keyContent(prompt, inputType)
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		local image = UserInputService:GetImageForKeyCode(prompt.GamepadKeyCode)
		if image and image ~= "" then
			return create("ImageLabel")({
				Name = "Button",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(36, 36),
				BackgroundTransparency = 1,
				Image = image,
			})
		end
	end

	local label
	if inputType == Enum.ProximityPromptInputType.Touch then
		label = "TAP"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		label = prompt.GamepadKeyCode.Name:gsub("^Button", "")
	else
		label = UserInputService:GetStringForKeyCode(prompt.KeyboardKeyCode)
		if label == "" then
			label = prompt.KeyboardKeyCode.Name
		end
	end
	return Text({
		Name = "Key",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(40, #label > 1 and 22 or 32),
		XAlignment = Enum.TextXAlignment.Center,
		Text = label,
		Color = KEY_TEXT,
	})
end

local function PromptCard(prompt, inputType, closing)
	local actionText = source(prompt.ActionText)
	local objectText = source(prompt.ObjectText)
	local opened = source(false)
	local pressed = source(false)
	local holding = source(false)
	local progress = source(0)
	local glow = source(1) -- transparency of the "holding" glow (1 = hidden)

	local holdDuration = prompt.HoldDuration
	local timed = holdDuration > 0 and holdDuration <= LONG_HOLD
	local holdStart = 0

	local function style()
		if actionText() == LOCKED_ACTION then
			return LOCKED_STYLE
		end
		return STYLES[prompt.Name] or DEFAULT_STYLE
	end

	-- screen size of the card: a bit smaller on small screens
	local camera = workspace.CurrentCamera
	local fit = math.clamp(camera.ViewportSize.Y / 900, 0.7, 1.1)

	local scale = Vide.spring(function()
		if closing() or not opened() then
			return 0
		end
		return pressed() and 0.94 or 1
	end, OPEN_TIME, 0.7)

	local connections = {
		prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
			actionText(prompt.ActionText)
		end),
		prompt:GetPropertyChangedSignal("ObjectText"):Connect(function()
			objectText(prompt.ObjectText)
		end),
		prompt.PromptButtonHoldBegan:Connect(function()
			holdStart = os.clock()
			holding(true)
			pressed(true)
		end),
		prompt.PromptButtonHoldEnded:Connect(function()
			holding(false)
			pressed(false)
			progress(0)
			glow(1)
		end),
		prompt.Triggered:Connect(function()
			-- short "click" on instant prompts (the shop)
			pressed(true)
			task.delay(0.1, function()
				pressed(false)
			end)
		end),
		RunService.RenderStepped:Connect(function()
			if not holding() then
				return
			end
			local elapsed = os.clock() - holdStart
			if timed then
				progress(math.clamp(elapsed / holdDuration, 0, 1))
			else
				glow(0.45 + 0.3 * math.cos(elapsed * 6))
			end
		end),
	}
	cleanup(function()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
	end)
	task.defer(opened, true)

	-- texts sit a bit lower when there is no progress bar
	local objectY = timed and 11 or 16
	local actionY = timed and 28 or 33

	local touch = inputType == Enum.ProximityPromptInputType.Touch

	local adornee = prompt.Parent
	if not (adornee and (adornee:IsA("BasePart") or adornee:IsA("Attachment") or adornee:IsA("Model"))) then
		adornee = nil
	end

	return create("BillboardGui")({
		Name = "Prompt_" .. prompt.Name,
		Adornee = adornee,
		AlwaysOnTop = true,
		ResetOnSpawn = false,
		-- only touch needs to tap the card; on PC/console the card must never catch the mouse
		-- (holding the right mouse button to turn the camera has to pass right through it)
		Active = touch,
		ClipsDescendants = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Size = UDim2.fromOffset(CARD_W * fit + 16, CARD_H * fit + 16),
		StudsOffset = Vector3.new(0, 1, 0),

		create("Frame")({
			Name = "Root",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(CARD_W, CARD_H),
			BackgroundTransparency = 1,

			create("UIScale")({
				Scale = function()
					return fit * math.max(scale(), 0.001)
				end,
			}),

			-- pulsing white glow around the card while a long hold is going on
			create("Frame")({
				Name = "Glow",
				Position = UDim2.fromOffset(-5, -5),
				Size = UDim2.new(1, 10, 1, 10),
				BackgroundColor3 = RobloxKit.White,
				BackgroundTransparency = glow,
				BorderSizePixel = 0,
				ZIndex = 0,

				Corner(10),
			}),

			Box({
				Name = "Card",
				Size = UDim2.fromScale(1, 1),
				Colors = function()
					return style().Colors
				end,
				Stroke = 3,
				Corner = 6,
				Pattern = true,
				Sheen = 0.3,
				SheenHeight = 26,
				Children = {
					-- the key / button to press
					Box({
						Name = "KeyCap",
						Position = UDim2.fromOffset(12, 12),
						Size = UDim2.fromOffset(54, 54),
						Colors = KEY_COLORS,
						Stroke = 3,
						Corner = 4,
						Sheen = 0.6,
						SheenHeight = 20,
						Children = { keyContent(prompt, inputType) },
					}),

					Text({
						Name = "ObjectText",
						Position = UDim2.fromOffset(TEXT_X, objectY),
						Size = UDim2.fromOffset(TEXT_W, 16),
						Text = objectText,
						Font = RobloxKit.FontBold,
						Transparency = 0.1,
						Shadow = 1,
						ShadowTransparency = 0.65,
					}),
					Text({
						Name = "ActionText",
						Position = UDim2.fromOffset(TEXT_X, actionY),
						Size = UDim2.fromOffset(TEXT_W, 26),
						Text = actionText,
						Stroke = 2,
						Shadow = 2,
					}),

					-- hold progress (short holds only)
					timed and Box({
						Name = "HoldBar",
						Position = UDim2.fromOffset(TEXT_X, 60),
						Size = UDim2.fromOffset(TEXT_W, 9),
						BackgroundColor = Color3.new(0, 0, 0),
						BackgroundTransparency = 0.55,
						Stroke = 1.5,
						Corner = 3,
						Children = {
							Box({
								Name = "Fill",
								Size = function()
									return UDim2.fromScale(progress(), 1)
								end,
								Colors = BAR_COLORS,
								Corner = 3,
							}),
						},
					}) or nil,

					-- task icon
					create("Frame")({
						Name = "Icon",
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -12, 0.5, 0),
						Size = UDim2.fromOffset(44, 44),
						BackgroundColor3 = Color3.new(0, 0, 0),
						BackgroundTransparency = 0.75,
						BorderSizePixel = 0,

						create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
						create("TextLabel")({
							Name = "Glyph",
							AnchorPoint = Vector2.new(0.5, 0.5),
							Position = UDim2.fromScale(0.5, 0.5),
							Size = UDim2.fromOffset(28, 28),
							BackgroundTransparency = 1,
							Text = function()
								return style().Icon
							end,
							TextScaled = true,
						}),
					}),

					-- touch only: tapping the card works like holding the key. No button at all on PC/console,
					-- so the card never blocks the mouse (camera turning with the right button stays smooth).
					touch and create("TextButton")({
						Name = "Hit",
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Text = "",
						ZIndex = 10,
						InputBegan = function(input)
							if input.UserInputType == Enum.UserInputType.Touch then
								prompt:InputHoldBegin()
							end
						end,
						InputEnded = function(input)
							if input.UserInputType == Enum.UserInputType.Touch then
								prompt:InputHoldEnd()
							end
						end,
					}) or nil,
				},
			}),
		}),
	})
end

---- Showing / hiding

local shown = {} -- [prompt] = { Destroy = fn, Closing = source }

local function hide(prompt)
	local entry = shown[prompt]
	if not entry then
		return
	end
	shown[prompt] = nil
	entry.Closing(true)
	task.delay(OPEN_TIME + 0.1, entry.Destroy)
end

local function show(prompt, inputType)
	if shown[prompt] then
		shown[prompt].Destroy()
		shown[prompt] = nil
	end
	local closing = source(false)
	local destroy = Vide.mount(function()
		return PromptCard(prompt, inputType, closing)
	end, player:WaitForChild("PlayerGui"))
	shown[prompt] = { Destroy = destroy, Closing = closing }
	prompt.Destroying:Once(function()
		hide(prompt)
	end)
end

--- Hides Roblox's default prompt UI (on this client only).
local function makeCustom(instance)
	if instance:IsA("ProximityPrompt") then
		instance.Style = Enum.ProximityPromptStyle.Custom
	end
end

---- Lifecycle

function Prompt_Controller:KnitStart()
	-- prompts are created by the server and stream in at any time
	workspace.DescendantAdded:Connect(makeCustom)
	for _, descendant in ipairs(workspace:GetDescendants()) do
		makeCustom(descendant)
	end

	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		makeCustom(prompt)
		show(prompt, inputType)
	end)
	ProximityPromptService.PromptHidden:Connect(hide)
end

function Prompt_Controller:KnitInit() end

return Prompt_Controller
