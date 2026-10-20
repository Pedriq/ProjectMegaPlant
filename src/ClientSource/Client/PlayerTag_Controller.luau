local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local PlayerTagConfig = require(ReplicatedStorage.SharedSource.Datas.PlayerTagConfig)
local StatsConfig = require(ReplicatedStorage.SharedSource.Datas.StatsConfig)
local WaitFor = require(ReplicatedStorage.ClientSource.Utilities.WaitFor)

--[[
	The custom billboard above every player's head (see PlayerTagConfig for what it shows):
	plants grown, nickname (+ Roblox Plus badge) and a rank title that gets cooler with every plant.

	  - built on the client for every player, from replicated data only: the "Plants Grown" leaderstat and
	    Player.HasRobloxSubscription (Roblox Plus). Nothing is sent just for this.
	  - Roblox's own name tag is switched off locally.
	  - it rides above the carried watering can (the can grows with Strength and would hide it otherwise).
	  - it is a BillboardGui inside the character, so TrainingTransparency_Controller hides the tag of the other
	    trainees together with their character.
]]
local PlayerTag_Controller = Knit.CreateController({
	Name = "PlayerTag_Controller",
})

local FONT = Enum.Font.GothamBold
local GOLD = Color3.fromRGB(255, 214, 72)
local STROKE = Color3.fromRGB(20, 30, 24)
local BASE_HEIGHT = 2.1 -- studs above the middle of the head, with no can
local CAN_CLEARANCE = 1.1 -- studs above the top of the can
local FOLLOW_SPEED = 10

local WateringCanVisual_Controller
local plantsDefinition = StatsConfig.ByKey.PlantsGrown

local tags = {} -- [player] = { Gui, Plants, Heights, Title, Gradient, Animated, Name, Plus }
local animatedGradients = {} -- [gradient] = true, spun every frame

---- UI pieces

local function formatNumber(value)
	local text = tostring(math.floor(value + 0.5))
	return (text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function label(name, size, color)
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.AutomaticSize = Enum.AutomaticSize.XY
	text.Size = UDim2.fromOffset(0, 0)
	text.Font = FONT
	text.TextSize = size
	text.TextColor3 = color or Color3.new(1, 1, 1)
	text.TextStrokeColor3 = STROKE
	text.TextStrokeTransparency = 0.1
	text.RichText = false
	return text
end

local function row(name, order, height)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.LayoutOrder = order
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, height)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 5)
	layout.Parent = frame
	return frame
end

--- The Roblox Plus badge: the configured icon, or a drawn gold "+" until there is one.
local function plusBadge()
	local size = 30
	if PlayerTagConfig.PlusIconImage ~= "" then
		local image = Instance.new("ImageLabel")
		image.Name = "Plus"
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromOffset(size, size)
		image.Image = PlayerTagConfig.PlusIconImage
		image.ScaleType = Enum.ScaleType.Fit
		return image
	end
	local badge = Instance.new("Frame")
	badge.Name = "Plus"
	badge.Size = UDim2.fromOffset(size, size)
	badge.BackgroundColor3 = GOLD
	badge.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = badge
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(150, 96, 12)
	stroke.Parent = badge
	local plus = Instance.new("TextLabel")
	plus.BackgroundTransparency = 1
	plus.Size = UDim2.fromScale(1, 1)
	plus.Font = FONT
	plus.Text = "+"
	plus.TextScaled = true
	plus.TextColor3 = Color3.fromRGB(110, 64, 6)
	plus.Parent = badge
	return badge
end

local function buildGui(player)
	local gui = Instance.new("BillboardGui")
	gui.Name = "PlayerTag"
	gui.Size = UDim2.fromOffset(360, 112)
	gui.SizeOffset = Vector2.new(0, 0.5) -- the bottom edge sits on the anchor point, the tag grows upward
	gui.StudsOffsetWorldSpace = Vector3.new(0, BASE_HEIGHT, 0)
	gui.MaxDistance = PlayerTagConfig.MaxDistance
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ClipsDescendants = false
	gui.Active = false
	gui.ResetOnSpawn = false

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 1)
	layout.Parent = gui

	-- 1. plants grown
	local plantsRow = row("PlantsRow", 1, 38)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.LayoutOrder = 1
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(36, 36)
	icon.Image = plantsDefinition.Icon
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = plantsRow
	local plants = label("Count", 30)
	plants.LayoutOrder = 2
	plants.Text = "0"
	plants.Parent = plantsRow

	-- 2. nickname + Roblox Plus
	local nameRow = row("NameRow", 2, 40)
	local nick = label("Nickname", 32)
	nick.LayoutOrder = 1
	nick.Text = player.DisplayName
	nick.Parent = nameRow
	local plus = plusBadge()
	plus.LayoutOrder = 2
	plus.Visible = false
	plus.Parent = nameRow

	-- 3. title (gradient text)
	local titleRow = row("TitleRow", 3, 30)
	local title = label("Title", 26)
	title.LayoutOrder = 1
	title.Parent = titleRow
	local gradient = Instance.new("UIGradient")
	gradient.Parent = title

	plantsRow.Parent = gui
	nameRow.Parent = gui
	titleRow.Parent = gui

	return {
		Gui = gui,
		Plants = plants,
		Nickname = nick,
		Plus = plus,
		Title = title,
		Gradient = gradient,
		TitleIndex = 0,
		Height = BASE_HEIGHT,
	}
end

---- Data -> tag

local function refresh(player)
	local tag = tags[player]
	if not tag then
		return
	end
	local leaderstats = player:FindFirstChild(StatsConfig.Folder)
	local value = leaderstats and leaderstats:FindFirstChild(plantsDefinition.DisplayName)
	local count = value and value.Value or 0

	tag.Plants.Text = formatNumber(count)
	tag.Nickname.Text = player.DisplayName
	tag.Plus.Visible = player.HasRobloxSubscription

	local title, index = PlayerTagConfig.GetTitle(count)
	if index ~= tag.TitleIndex then
		tag.TitleIndex = index
		tag.Title.Text = title.Name
		tag.Gradient.Color = PlayerTagConfig.GetColorSequence(title)
		tag.Gradient.Rotation = 0
		animatedGradients[tag.Gradient] = title.Animated and true or nil
	end
end

local function removeTag(player)
	local tag = tags[player]
	if not tag then
		return
	end
	tags[player] = nil
	animatedGradients[tag.Gradient] = nil
	tag.Gui:Destroy()
end

local function attach(player, character)
	removeTag(player)
	local head = character:WaitForChild("Head", 10)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not head or not humanoid or player.Character ~= character then
		return
	end
	-- Roblox's default name tag is replaced by this one
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	local tag = buildGui(player)
	tags[player] = tag
	tag.Gui.Adornee = head
	tag.Gui.Parent = head
	refresh(player)
end

local function watch(player)
	player.CharacterAdded:Connect(function(character)
		attach(player, character)
	end)
	if player.Character then
		task.spawn(attach, player, player.Character)
	end

	-- the stat appears once the server has loaded the profile, and changes whenever a plant is harvested
	task.spawn(function()
		local leaderstats = WaitFor.Child(player, StatsConfig.Folder, 60)
		local value = leaderstats and WaitFor.Child(leaderstats, plantsDefinition.DisplayName, 60)
		if value then
			value.Changed:Connect(function()
				refresh(player)
			end)
			refresh(player)
		end
	end)
	player:GetPropertyChangedSignal("DisplayName"):Connect(function()
		refresh(player)
	end)
end

---- Per frame: ride above the can, spin the rainbow

local function updateHeights(dt)
	local blend = 1 - math.exp(-FOLLOW_SPEED * dt)
	for player, tag in pairs(tags) do
		local head = tag.Gui.Adornee
		if head and head.Parent then
			local target = BASE_HEIGHT
			local canTop = WateringCanVisual_Controller:GetTopPosition(player)
			if canTop then
				target = math.max(BASE_HEIGHT, canTop.Y - head.Position.Y + CAN_CLEARANCE)
			end
			tag.Height += (target - tag.Height) * blend
			tag.Gui.StudsOffsetWorldSpace = Vector3.new(0, tag.Height, 0)
		end
	end
end

function PlayerTag_Controller:KnitStart()
	WateringCanVisual_Controller = Knit.GetController("WateringCanVisual_Controller")

	Players.PlayerAdded:Connect(watch)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerRemoving:Connect(removeTag)

	RunService.RenderStepped:Connect(function(dt)
		updateHeights(dt)
		local rotation = (os.clock() * 40) % 360
		for gradient in pairs(animatedGradients) do
			gradient.Rotation = rotation
		end
	end)
end

function PlayerTag_Controller:KnitInit() end

return PlayerTag_Controller
