local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Vide = require(ReplicatedStorage.Packages.Vide)
local Plastic = require(ReplicatedStorage.ClientSource.UI.Plastic)

local create = Vide.create
local source = Vide.source

--[[
	"Top Gardeners": the three players who poured the most into the plant that just finished growing.
	The ranking is computed on the server (JuicePool_Service) and arrives with the finish sequence; this
	controller only displays it:

		Leaderboard_Controller:Show(leaders, showDelay, hideDelay)
			leaders = { { UserId, Name, Amount, Percent }, ... }  (already sorted, at most 3)

	It slides in at the right edge, away from the camera focus, the HUD and the notifications.
	First place is bigger and golden, second silver, third bronze; fewer than 3 entries show fewer rows.
]]
local Leaderboard_Controller = Knit.CreateController({
	Name = "Leaderboard_Controller",
})

local player = Players.LocalPlayer

local board = source({})
local shown = source(false)
local token = 0

local RANKS = {
	{ Medal = "🥇", Place = "1st", Color = Color3.fromRGB(246, 196, 70), Height = 0.29, Y = 0.165 },
	{ Medal = "🥈", Place = "2nd", Color = Color3.fromRGB(190, 202, 214), Height = 0.215, Y = 0.475 },
	{ Medal = "🥉", Place = "3rd", Color = Color3.fromRGB(212, 142, 90), Height = 0.215, Y = 0.71 },
}

local function Row(rank)
	local style = RANKS[rank]
	local function entry()
		return board()[rank]
	end

	return create("Frame")({
		Name = "Row" .. rank,
		Position = UDim2.fromScale(0, style.Y),
		Size = UDim2.fromScale(1, style.Height),
		BackgroundTransparency = 1,
		Visible = function()
			return entry() ~= nil
		end,

		Plastic.Panel({
			Name = "Panel",
			Size = UDim2.fromScale(1, 1),
			BodyColor = style.Color,
			Style = "Accent",
			Corner = 0.3,
			Children = {
				Plastic.Label({
					Name = "Medal",
					Position = UDim2.fromScale(0.03, 0.06),
					Size = UDim2.fromScale(0.17, 0.58),
					Text = style.Medal,
				}),
				Plastic.Label({
					Name = "Place",
					Position = UDim2.fromScale(0.03, 0.64),
					Size = UDim2.fromScale(0.17, 0.28),
					Color = Color3.fromRGB(255, 255, 255),
					Text = style.Place,
				}),
				Plastic.Label({
					Name = "Name",
					Position = UDim2.fromScale(0.22, 0.12),
					Size = UDim2.fromScale(0.44, 0.76),
					XAlignment = Enum.TextXAlignment.Left,
					Color = function()
						local current = entry()
						-- your own row is tinted so you spot yourself quickly
						return current and current.UserId == player.UserId and Color3.fromRGB(255, 250, 190)
							or Color3.fromRGB(255, 255, 255)
					end,
					Text = function()
						local current = entry()
						return current and current.Name or ""
					end,
				}),
				Plastic.Label({
					Name = "Percent",
					Position = UDim2.fromScale(0.67, 0.08),
					Size = UDim2.fromScale(0.3, 0.52),
					XAlignment = Enum.TextXAlignment.Right,
					Text = function()
						local current = entry()
						return current and ("%d%%"):format(current.Percent) or ""
					end,
				}),
				Plastic.Label({
					Name = "Amount",
					Position = UDim2.fromScale(0.62, 0.62),
					Size = UDim2.fromScale(0.35, 0.28),
					XAlignment = Enum.TextXAlignment.Right,
					Color = Color3.fromRGB(235, 245, 255),
					Text = function()
						local current = entry()
						return current and ("%d water"):format(current.Amount) or ""
					end,
				}),
			},
		}),
	})
end

local function LeaderboardUI()
	local alpha = Vide.spring(function()
		return shown() and 1 or 0
	end, 0.32, 0.8)

	return create("ScreenGui")({
		Name = "Leaderboard",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 8,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = function()
			return shown() or alpha() > 0.01
		end,

		create("Frame")({
			Name = "Root",
			AnchorPoint = Vector2.new(1, 0.5),
			-- slides in from beyond the right edge
			Position = function()
				return UDim2.fromScale(0.99 + 0.3 * (1 - alpha()), 0.4)
			end,
			Size = UDim2.fromScale(0.19, 0.34),
			BackgroundTransparency = 1,
			Active = false, -- never blocks input

			create("UIAspectRatioConstraint")({
				AspectRatio = 0.9,
				AspectType = Enum.AspectType.FitWithinMaxSize,
			}),

			Plastic.Panel({
				Name = "Header",
				Size = UDim2.fromScale(1, 0.14),
				Corner = 0.4,
				Children = {
					Plastic.Label({
						Name = "Title",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromScale(0.9, 0.72),
						Text = "TOP GARDENERS",
					}),
				},
			}),
			Row(1),
			Row(2),
			Row(3),
		}),
	})
end

--- leaders: sorted list of { UserId, Name, Amount, Percent }. Appears after showDelay seconds and
--- disappears hideDelay seconds from now.
function Leaderboard_Controller:Show(leaders, showDelay, hideDelay)
	if type(leaders) ~= "table" or #leaders == 0 then
		return
	end
	token += 1
	local mine = token

	task.delay(math.max(showDelay or 0, 0), function()
		if token == mine then
			board(leaders)
			shown(true)
		end
	end)
	task.delay(math.max(hideDelay or 0, 0), function()
		if token == mine then
			shown(false)
		end
	end)
end

function Leaderboard_Controller:KnitStart()
	Vide.mount(function()
		return LeaderboardUI()
	end, player:WaitForChild("PlayerGui"))
end

function Leaderboard_Controller:KnitInit() end

return Leaderboard_Controller
