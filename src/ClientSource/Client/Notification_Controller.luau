local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local NotificationConfig = require(ReplicatedStorage.SharedSource.Datas.NotificationConfig)
local TutorialConfig = require(ReplicatedStorage.SharedSource.Datas.TutorialConfig)
local Plastic = require(ReplicatedStorage.ClientSource.UI.Plastic)

--[[
	Draws the notifications (see NotificationConfig) as a stack of toasts above the banner area:

		Notification_Controller:Notify("NoWater")                      -- an id from NotificationConfig.Messages
		Notification_Controller:Push({ Type = "Info", Title = "..." })  -- a one-off message, no config entry needed

	Server code does not call this: it uses Notification_Service:Notify(player, id, params), which arrives here.

	  - newest toast at the bottom, older ones above it; at most Display.MaxVisible at once
	  - the same message again does not stack: the existing toast pulses, shows "x2", "x3"... and stays longer
	  - everything is Scale-based and the stack has a min / max pixel width, so it reads on phones and big monitors
	  - it never takes input (Active = false), so it can't block the camera or the prompts
]]
local Notification_Controller = Knit.CreateController({
	Name = "Notification_Controller",
})

local player = Players.LocalPlayer

local Notification_Service, Audio_Controller

local TOAST_ASPECT = 5.2 -- width / height of one toast
local ENTER_TIME, EXIT_TIME = 0.25, 0.16

local list -- Frame that holds the toasts
local active = {} -- [key] = toast record
local ordered = {} -- records, oldest first
local layoutCounter = 0

---- Toast

local function tween(instance, time, goal, style, direction)
	TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
		:Play()
end

local function buildToast(info)
	local hasHint = info.Hint ~= nil and info.Hint ~= ""

	local scale = Instance.new("UIScale")
	scale.Scale = 0.5

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = TOAST_ASPECT
	aspect.DominantAxis = Enum.DominantAxis.Width
	-- the toast's own height is 0: the height must come from the width (FitWithinMaxSize would collapse it to 0x0)
	aspect.AspectType = Enum.AspectType.ScaleWithParentSize

	local title = Plastic.Label({
		Name = "Title",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.21, hasHint and 0.32 or 0.5),
		Size = UDim2.fromScale(0.62, hasHint and 0.46 or 0.58),
		Text = info.Title,
		XAlignment = Enum.TextXAlignment.Left,
	})
	local hint = Plastic.Label({
		Name = "Hint",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.21, 0.74),
		Size = UDim2.fromScale(0.62, 0.28),
		Text = info.Hint or "",
		XAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 0.12,
	})
	hint.Visible = hasHint

	local count = Plastic.Label({
		Name = "Count",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.96, 0.5),
		Size = UDim2.fromScale(0.14, 0.4),
		Text = "",
		XAlignment = Enum.TextXAlignment.Right,
	})
	count.Visible = false

	-- round glyph chip on the left
	local chipAspect = Instance.new("UIAspectRatioConstraint")
	chipAspect.AspectRatio = 1
	chipAspect.DominantAxis = Enum.DominantAxis.Height
	local chip = Plastic.Panel({
		Name = "Chip",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.04, 0.5),
		Size = UDim2.fromScale(0.16, 0.66),
		BodyColor = info.Color,
		Style = "Accent",
		Corner = 0.5,
		Studs = false,
		RootChildren = { chipAspect },
		Children = {
			Plastic.Label({
				Name = "Glyph",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.62, 0.62),
				Text = info.Glyph,
			}),
		},
	})

	local panel = Plastic.Panel({
		Name = "Toast",
		Size = UDim2.fromScale(1, 0),
		BodyColor = info.Color,
		Corner = 0.35,
		RootChildren = { aspect, scale },
		Children = { chip, title, hint, count },
	})
	panel.LayoutOrder = layoutCounter

	return { Panel = panel, Scale = scale, Count = count, Hint = hint, Title = title, Counter = 1, Token = 0 }
end

local function remove(record, immediately)
	if record.Dead then
		return
	end
	record.Dead = true
	if active[record.Key] == record then
		active[record.Key] = nil
	end
	local index = table.find(ordered, record)
	if index then
		table.remove(ordered, index)
	end
	if immediately then
		record.Panel:Destroy()
		return
	end
	tween(record.Scale, EXIT_TIME, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(EXIT_TIME + 0.02, function()
		record.Panel:Destroy()
	end)
end

--- (Re)starts the time a toast stays on screen.
local function startTimer(record, duration)
	record.Token += 1
	local token = record.Token
	task.delay(duration, function()
		if record.Token == token then
			remove(record, false)
		end
	end)
end

---- Public API

--- Shows a one-off notification: { Type = "Error"|"Warning"|"Info"|"Success", Title, Hint?, Duration?, Sound?, Key? }.
function Notification_Controller:Push(options)
	if not list then
		return
	end
	local style = NotificationConfig.Types[options.Type] or NotificationConfig.Types.Info
	local info = {
		Type = options.Type or "Info",
		Title = options.Title or "",
		Hint = options.Hint,
		Color = options.Color or style.Color,
		Glyph = options.Glyph or style.Glyph,
		Duration = options.Duration or NotificationConfig.Display.Duration,
		Sound = options.Sound,
	}
	local key = options.Key or ("%s|%s|%s"):format(info.Type, info.Title, info.Hint or "")

	local sound = info.Sound
	if sound and Audio_Controller then
		Audio_Controller:Play(sound)
	end

	local record = active[key]
	if record then
		-- same message again: pulse, count and keep it longer instead of stacking a copy
		record.Counter += 1
		record.Count.Text = "x" .. record.Counter
		record.Count.Visible = true
		layoutCounter += 1
		record.Panel.LayoutOrder = layoutCounter
		record.Scale.Scale = 1.08
		tween(record.Scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		startTimer(record, info.Duration)
		return
	end

	layoutCounter += 1
	record = buildToast(info)
	record.Key = key
	active[key] = record
	table.insert(ordered, record)

	-- too many: the oldest one leaves at once
	while #ordered > NotificationConfig.Display.MaxVisible do
		remove(ordered[1], true)
	end

	record.Panel.Parent = list
	tween(record.Scale, ENTER_TIME, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	startTimer(record, info.Duration)
end

--- Shows a notification from NotificationConfig.Messages on this client.
function Notification_Controller:Notify(id, params)
	-- during the first-time tutorial only the tutorial's own messages are shown (ids "TutorialStep", "TutorialDone"):
	-- anything else would bury the objective, and the tutorial already explains what the player has to do
	if (player:GetAttribute(TutorialConfig.StepAttribute) or 0) > 0 and not id:find("^Tutorial") then
		return
	end
	local info = NotificationConfig.Resolve(id, params)
	if not info then
		warn("Notification_Controller: unknown notification '" .. tostring(id) .. "'")
		return
	end
	self:Push({
		Type = info.Type,
		Title = info.Title,
		Hint = info.Hint,
		Duration = info.Duration,
		Sound = info.Sound,
		Key = id .. "|" .. info.Title,
	})
end

---- Lifecycle

local function buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "NotificationHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30 -- above the banners (20)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local root = Instance.new("Frame")
	root.Name = "Stack"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.fromScale(0.5, 0.76)
	root.Size = UDim2.fromScale(0.3, 0.34)
	root.BackgroundTransparency = 1
	root.Active = false
	root.Parent = gui

	local limits = Instance.new("UISizeConstraint")
	limits.MinSize = Vector2.new(250, 0)
	limits.MaxSize = Vector2.new(440, math.huge)
	limits.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = root

	gui.Parent = player:WaitForChild("PlayerGui")
	return root
end

function Notification_Controller:KnitStart()
	Audio_Controller = Knit.GetController("Audio_Controller")
	Notification_Service = Knit.GetService("Notification_Service")

	list = buildGui()

	Notification_Service.Notification:Connect(function(id, params)
		Notification_Controller:Notify(id, params)
	end)
end

function Notification_Controller:KnitInit() end

return Notification_Controller
