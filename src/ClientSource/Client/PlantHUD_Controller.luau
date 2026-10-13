local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Vide = require(ReplicatedStorage.Packages.Vide)
local PlantsConfig = require(ReplicatedStorage.SharedSource.Datas.PlantsConfig)
local WaterConfig = require(ReplicatedStorage.SharedSource.Datas.WaterConfig)
local Plastic = require(ReplicatedStorage.ClientSource.UI.Plastic)
local PlantIcon = require(ReplicatedStorage.ClientSource.UI.PlantIcon)
local Anim = require(ReplicatedStorage.ClientSource.UI.Anim)

local create = Vide.create
local source = Vide.source

local PlantHUD_Controller = Knit.CreateController({
	Name = "PlantHUD_Controller",
})

local player = Players.LocalPlayer
local PlantCycle_Controller

local PANEL_ASPECT = 3.7 -- width / height of the panel

local function formatCount(value)
	local text = tostring(math.floor(value + 0.5))
	return (text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

--- Label + value pill used for the water statistics.
local function StatPill(props)
	return Plastic.Panel({
		Name = props.Name,
		AnchorPoint = Vector2.new(0, 0),
		Position = props.Position,
		Size = UDim2.fromScale(0.465, 0.26),
		BodyColor = props.BodyColor,
		BorderColor = props.BorderColor,
		Corner = 0.4,
		Children = {
			Plastic.Label({
				Name = "Title",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0.05, 0.5),
				Size = UDim2.fromScale(0.5, 0.62),
				XAlignment = Enum.TextXAlignment.Left,
				Text = props.Title,
			}),
			Plastic.Label({
				Name = "Value",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(0.96, 0.5),
				Size = UDim2.fromScale(0.45, 0.8),
				XAlignment = Enum.TextXAlignment.Right,
				Text = props.Value,
			}),
		},
	})
end

local BAR_POSITION = Vector2.new(0.24, 0.37)

local function PlantHUD(cycle, now, shimmer, popTarget, totals, shake)
	local popScale = Vide.spring(popTarget, 0.35, 0.5)

	-- water numbers count up smoothly instead of jumping
	local totalWater = Vide.spring(function()
		return totals.Total()
	end, 0.3, 1)
	local myWater = Vide.spring(function()
		return totals.Mine()
	end, 0.3, 1)

	local function plantId()
		return cycle().PlantId
	end

	local function isSelecting()
		return cycle().Phase == "Selecting"
	end

	local function rarity()
		local id = plantId()
		return id and PlantsConfig.GetRarity(id)
	end

	-- test value: elapsed fraction of the grow time (no watering yet)
	local function rawProgress()
		local s = cycle()
		if s.Phase == "Growing" then
			return math.clamp((now() - s.PhaseStart) / math.max(s.PhaseEnd - s.PhaseStart, 0.001), 0, 1)
		elseif s.Phase == "Finished" then
			return 1
		end
		return 0
	end
	local progress = Vide.spring(rawProgress, 0.35, 1)

	local function timerText()
		local s = cycle()
		if s.Phase == "Growing" then
			return Anim.FormatTime(s.PhaseEnd - now())
		elseif s.Phase == "Finished" then
			return "Grown! Next plant in " .. Anim.FormatTime(s.PhaseEnd - now())
		elseif s.Phase == "Selecting" then
			return "Choosing a plant..."
		end
		return "Waiting for plants..."
	end

	return create("ScreenGui")({
		Name = "PlantHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1,

		create("Frame")({
			Name = "Root",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.006),
			Size = UDim2.fromScale(0.4, 0.17),
			BackgroundTransparency = 1,

			create("UIAspectRatioConstraint")({
				AspectRatio = PANEL_ASPECT,
				AspectType = Enum.AspectType.FitWithinMaxSize,
				DominantAxis = Enum.DominantAxis.Width,
			}),
			create("UIScale")({
				Scale = function()
					return popScale()
				end,
			}),

			Plastic.Panel({
				Name = "Panel",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				Children = {
					-- Plant icon plate
					Plastic.Panel({
						Name = "IconPlate",
						AnchorPoint = Vector2.new(0, 0),
						Position = UDim2.fromScale(0.025, 0.07),
						Size = UDim2.fromScale(0.16, 0.58),
						BodyColor = function()
							local r = rarity()
							return r and r.Color or Color3.fromRGB(150, 214, 92)
						end,
						BorderColor = function()
							local r = rarity()
							return r and r.DarkColor or Color3.fromRGB(58, 120, 46)
						end,
						Corner = 0.3,
						Children = {
							create("UIAspectRatioConstraint")({ AspectRatio = 1 }),
							-- rebuilt only when the selected plant changes
							function()
								if isSelecting() then
									return Plastic.Label({
										Name = "Unknown",
										AnchorPoint = Vector2.new(0.5, 0.5),
										Position = UDim2.fromScale(0.5, 0.5),
										Size = UDim2.fromScale(0.6, 0.6),
										Text = "?",
									})
								end
								return PlantIcon(plantId(), {
									AnchorPoint = Vector2.new(0.5, 0.5),
									Position = UDim2.fromScale(0.5, 0.5),
									Size = UDim2.fromScale(0.9, 0.9),
								})
							end,
						},
					}),

					-- Plant name
					Plastic.Label({
						Name = "PlantName",
						AnchorPoint = Vector2.new(0, 0),
						Position = UDim2.fromScale(0.24, 0.06),
						Size = UDim2.fromScale(0.45, 0.26),
						XAlignment = Enum.TextXAlignment.Left,
						Text = function()
							if isSelecting() or not plantId() then
								return "???"
							end
							return PlantsConfig.GetDisplayName(plantId())
						end,
					}),

					-- Rarity chip
					create("Frame")({
						Name = "RarityChip",
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.fromScale(0.97, 0.07),
						Size = UDim2.fromScale(0.26, 0.22),
						BackgroundTransparency = 1,
						Visible = function()
							return not isSelecting() and rarity() ~= nil
						end,

						Plastic.Panel({
							Name = "Chip",
							Size = UDim2.fromScale(1, 1),
							Corner = 0.5,
							BodyColor = function()
								local r = rarity()
								return r and r.Color or Color3.new(1, 1, 1)
							end,
							BorderColor = function()
								local r = rarity()
								return r and r.DarkColor or Color3.new(0.3, 0.3, 0.3)
							end,
							Children = {
								Plastic.Label({
									Name = "Rarity",
									AnchorPoint = Vector2.new(0.5, 0.5),
									Position = UDim2.fromScale(0.5, 0.5),
									Size = UDim2.fromScale(0.86, 0.72),
									Text = function()
										local r = rarity()
										return r and r.DisplayName or ""
									end,
								}),
							},
						}),
					}),

					-- Progress bar + timer
					Plastic.Bar({
						Name = "Progress",
						AnchorPoint = Vector2.new(0, 0),
						-- the bar only moves while the local player is watering (see shake in KnitStart)
						Position = function()
							local offset = shake.Offset()
							return UDim2.fromScale(BAR_POSITION.X + offset.X, BAR_POSITION.Y + offset.Y)
						end,
						Rotation = function()
							return shake.Rotation()
						end,
						Size = UDim2.fromScale(0.73, 0.27),
						Progress = progress,
						Shimmer = shimmer,
						FillColor = function()
							if cycle().Phase == "Finished" then
								return Plastic.Colors.FillGold
							end
							return Plastic.Colors.FillGreen
						end,
						Children = {
							Plastic.Label({
								Name = "Timer",
								AnchorPoint = Vector2.new(0.5, 0.5),
								Position = UDim2.fromScale(0.5, 0.5),
								Size = UDim2.fromScale(0.9, 0.78),
								ZIndex = 5,
								Text = timerText,
							}),
						},
					}),

					-- Water statistics: shared total + this player's own contribution
					StatPill({
						Name = "TotalWater",
						Position = UDim2.fromScale(0.03, 0.7),
						BodyColor = Color3.fromRGB(88, 170, 255),
						BorderColor = Color3.fromRGB(34, 78, 168),
						Title = "Total Water",
						Value = function()
							local goal = cycle().PlantId and PlantsConfig.GetWaterGoal(cycle().PlantId)
							if not goal then
								return formatCount(totalWater())
							end
							return ("%s / %s"):format(formatCount(totalWater()), formatCount(goal))
						end,
					}),
					StatPill({
						Name = "YourContribution",
						Position = UDim2.fromScale(0.505, 0.7),
						BodyColor = Color3.fromRGB(255, 200, 70),
						BorderColor = Color3.fromRGB(176, 104, 18),
						Title = "Your Contribution",
						Value = function()
							return formatCount(myWater())
						end,
					}),
				},
			}),
		}),
	})
end

function PlantHUD_Controller:KnitStart()
	PlantCycle_Controller = Knit.GetController("PlantCycle_Controller")
	local cycle = PlantCycle_Controller.State
	local totals = Knit.GetController("WaterTotals_Controller")

	local now = source(workspace:GetServerTimeNow())
	local shimmer = source(-1)
	local popTarget = source(1)

	-- The progress bar shakes and shimmers ONLY while the local player is pouring water on the plant;
	-- otherwise it is perfectly still.
	local shake = { Offset = source(Vector2.zero), Rotation = source(0) }
	local intensity = 0
	local wateringAttribute = WaterConfig.Attributes.Watering

	RunService.RenderStepped:Connect(function(dt)
		local watering = player:GetAttribute(wateringAttribute) == true

		-- eases in and out, so it starts and stops smoothly
		intensity += ((watering and 1 or 0) - intensity) * (1 - math.exp(-14 * dt))
		if not watering and intensity < 0.003 then
			intensity = 0
		end

		local t = os.clock()
		Vide.batch(function()
			now(workspace:GetServerTimeNow())

			if intensity > 0 then
				local nx = math.sin(t * 47) + math.sin(t * 31.7 + 1.3) * 0.7
				local ny = math.sin(t * 53 + 2.1) + math.sin(t * 37.3) * 0.7
				shake.Offset(Vector2.new(nx * 0.0035 * intensity, ny * 0.006 * intensity))
				shake.Rotation(math.sin(t * 41) * 1.1 * intensity)
				shimmer((t * 0.9 % 2) - 1)
			else
				shake.Offset(Vector2.zero)
				shake.Rotation(0)
				shimmer(-1) -- stripe parked off the bar
			end
		end)
	end)

	-- bounce the panel whenever a new plant shows up
	PlantCycle_Controller.StateChanged:Connect(function(state)
		if state.Phase == "Growing" then
			popTarget(1.12)
			task.delay(0.15, function()
				popTarget(1)
			end)
		end
	end)

	Vide.mount(function()
		return PlantHUD(cycle, now, shimmer, popTarget, totals, shake)
	end, player:WaitForChild("PlayerGui"))
end

function PlantHUD_Controller:KnitInit() end

return PlantHUD_Controller
