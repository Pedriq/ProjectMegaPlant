local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local FriendBoostConfig = require(ReplicatedStorage.SharedSource.Datas.FriendBoostConfig)
local Plastic = require(ReplicatedStorage.ClientSource.UI.Plastic)

--[[
	The "Friend Boost: 30%" label in the bottom-left corner. The server (FriendBoost_Service) counts the friends in the
	server and writes the result to player attributes; this controller only displays it (the money icon in the HUD
	shows the multiplier too, see HUD_Controller). The label pops when the bonus changes.
]]
local FriendBoost_Controller = Knit.CreateController({
	Name = "FriendBoost_Controller",
})

local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(255, 214, 72)
local DIM = Color3.fromRGB(205, 225, 210)

local label, scale

local function refresh(animate)
	local friends = player:GetAttribute(FriendBoostConfig.FriendsAttribute) or 0
	local percent = FriendBoostConfig.GetPercent(friends)
	label.Text = ("Friend Boost: %d%%"):format(percent)
	-- gold when it is active, quiet when there is no friend in the server
	label.TextColor3 = percent > 0 and GOLD or DIM
	if animate then
		scale.Scale = 1.15
		TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

function FriendBoost_Controller:KnitStart()
	local gui = Instance.new("ScreenGui")
	gui.Name = "FriendBoostHUD"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 3
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local frame = Instance.new("Frame")
	frame.Name = "Pill"
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = UDim2.fromScale(0.01, 0.985)
	frame.Size = UDim2.fromScale(0.2, 0.05)
	frame.BackgroundColor3 = Color3.fromRGB(24, 48, 34)
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	local limits = Instance.new("UISizeConstraint") -- readable on phones, not huge on big monitors
	limits.MinSize = Vector2.new(170, 30)
	limits.MaxSize = Vector2.new(320, 52)
	limits.Parent = frame
	scale = Instance.new("UIScale")
	scale.Parent = frame

	label = Instance.new("TextLabel")
	label.Name = "Text"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.88, 0.62)
	label.BackgroundTransparency = 1
	label.Font = Plastic.Font
	label.TextScaled = true
	label.TextColor3 = DIM
	label.TextStrokeColor3 = Color3.fromRGB(20, 40, 28)
	label.TextStrokeTransparency = 0.3
	label.Parent = frame

	gui.Parent = player:WaitForChild("PlayerGui")

	refresh(false)
	player:GetAttributeChangedSignal(FriendBoostConfig.FriendsAttribute):Connect(function()
		refresh(true)
	end)
end

function FriendBoost_Controller:KnitInit() end

return FriendBoost_Controller
