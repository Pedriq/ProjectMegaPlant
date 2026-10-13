local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Vide = require(ReplicatedStorage.Packages.Vide)
local PlantsConfig = require(ReplicatedStorage.SharedSource.Datas.PlantsConfig)
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

local PANEL_ASPECT = 4.6 -- width / height of the panel

local function PlantHUD(cycle, now, shimmer, popTarget)
	local popScale = Vide.spring(popTarget, 0.35, 0.5)

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
			Size = UDim2.fromScale(0.4, 0.14),
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
						AnchorPoint = Vector2.new(0, 0.5),
						Position = UDim2.fromScale(0.02, 0.5),
						Size = UDim2.fromScale(0.2, 0.86),
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
						Position = UDim2.fromScale(0.25, 0.08),
						Size = UDim2.fromScale(0.45, 0.36),
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
						Position = UDim2.fromScale(0.97, 0.1),
						Size = UDim2.fromScale(0.26, 0.3),
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
						Position = UDim2.fromScale(0.25, 0.52),
						Size = UDim2.fromScale(0.72, 0.38),
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
				},
			}),
		}),
	})
end

function PlantHUD_Controller:KnitStart()
	PlantCycle_Controller = Knit.GetController("PlantCycle_Controller")
	local cycle = PlantCycle_Controller.State

	local now = source(workspace:GetServerTimeNow())
	local shimmer = source(-1)
	local popTarget = source(1)

	-- once per frame: timer text + shimmer position
	RunService.RenderStepped:Connect(function()
		Vide.batch(function()
			now(workspace:GetServerTimeNow())
			shimmer((os.clock() * 0.6 % 2) - 1)
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
		return PlantHUD(cycle, now, shimmer, popTarget)
	end, player:WaitForChild("PlayerGui"))
end

function PlantHUD_Controller:KnitInit() end

return PlantHUD_Controller
