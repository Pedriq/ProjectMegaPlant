local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Vide = require(ReplicatedStorage.Packages.Vide)
local Plastic = require(ReplicatedStorage.ClientSource.UI.Plastic)

local create = Vide.create
local source = Vide.source

--[[
	Compact notifications ("Blooming!", "Juice boost", "Bigger can!"...) near the bottom of the screen.
	They are queued and shown one at a time, so important moments never overlap and gameplay stays visible.

		Banner:Show({ Title = "...", Subtitle = "...", Color = Color3, BorderColor = Color3, Duration = 2.2 })
]]
local Banner_Controller = Knit.CreateController({
	Name = "Banner_Controller",
})

local player = Players.LocalPlayer

local DEFAULT_DURATION = 2
local GAP = 0.15

local queue = {}
local running = false

local data = source({ Title = "", Subtitle = "", Color = Plastic.Colors.PanelBody, BorderColor = Plastic.Colors.PanelBorder })
local shown = source(false)

local function BannerUI()
	local scale = Vide.spring(function()
		return shown() and 1 or 0
	end, 0.28, 0.75)

	return create("ScreenGui")({
		Name = "BannerHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = function()
			return scale() > 0.02 or shown()
		end,

		create("Frame")({
			Name = "Root",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.86),
			Size = UDim2.fromScale(0.27, 0.075),
			BackgroundTransparency = 1,

			create("UIAspectRatioConstraint")({
				AspectRatio = 5.2,
				AspectType = Enum.AspectType.FitWithinMaxSize,
			}),
			create("UIScale")({
				Scale = function()
					return math.max(scale(), 0.001)
				end,
			}),

			Plastic.Panel({
				Name = "Panel",
				Size = UDim2.fromScale(1, 1),
				Corner = 0.35,
				BodyColor = function()
					return data().Color
				end,
				BorderColor = function()
					return data().BorderColor
				end,
				Children = {
					Plastic.Label({
						Name = "Title",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.08),
						Size = UDim2.fromScale(0.92, 0.52),
						Text = function()
							return data().Title
						end,
					}),
					Plastic.Label({
						Name = "Subtitle",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.62),
						Size = UDim2.fromScale(0.92, 0.28),
						Text = function()
							return data().Subtitle
						end,
					}),
				},
			}),
		}),
	})
end

local function run()
	if running then
		return
	end
	running = true
	task.spawn(function()
		while #queue > 0 do
			local banner = table.remove(queue, 1)
			data(banner)
			shown(true)
			-- when many banners are waiting, show each one for less time
			local duration = (banner.Duration or DEFAULT_DURATION) / (1 + math.min(#queue, 3) * 0.35)
			task.wait(duration)
			shown(false)
			task.wait(GAP + 0.25)
		end
		running = false
	end)
end

function Banner_Controller:Show(banner)
	table.insert(queue, {
		Title = banner.Title or "",
		Subtitle = banner.Subtitle or "",
		Color = banner.Color or Plastic.Colors.PanelBody,
		BorderColor = banner.BorderColor or Plastic.Colors.PanelBorder,
		Duration = banner.Duration,
	})
	run()
end

function Banner_Controller:KnitStart()
	Vide.mount(function()
		return BannerUI()
	end, player:WaitForChild("PlayerGui"))
end

function Banner_Controller:KnitInit() end

return Banner_Controller
