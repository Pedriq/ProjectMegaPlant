local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Vide = require(ReplicatedStorage.Packages.Vide)
local PlantsConfig = require(ReplicatedStorage.SharedSource.Datas.PlantsConfig)
local PlantSelector = require(ReplicatedStorage.SharedSource.Utilities.PlantSelector)
local Plastic = require(ReplicatedStorage.ClientSource.UI.Plastic)
local PlantIcon = require(ReplicatedStorage.ClientSource.UI.PlantIcon)
local Anim = require(ReplicatedStorage.ClientSource.UI.Anim)

local create = Vide.create
local source = Vide.source

--[[
	Plays the plant selection animation: dark overlay, a spinning carousel of plants that slows down
	smoothly onto the winner, then a reveal with name, rarity, chance and grow time.

	The winner comes from the server (state.PlantId). The filler cards are generated from a seed
	derived from the cycle id, so every player sees the exact same carousel. Players who join in the
	middle of the animation fast-forward to the current moment.
]]
local PlantSelection_Controller = Knit.CreateController({
	Name = "PlantSelection_Controller",
})

local player = Players.LocalPlayer

local FADE_IN = 0.4
local FADE_OUT = 0.5
local REVEAL_IN = 0.5

local activeStop -- function that tears down the animation currently playing

---- UI

local function PlantCard(plantId, winnerScale)
	local rarity = PlantsConfig.GetRarity(plantId)
	local cardChildren = {
		PlantIcon(plantId, {
			Position = UDim2.fromScale(0.5, 0.05),
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromScale(0.84, 0.46),
		}),
		Plastic.Label({
			Name = "Name",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromScale(0.92, 0.14),
			Text = PlantsConfig.GetDisplayName(plantId),
		}),
		Plastic.Label({
			Name = "Rarity",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.67),
			Size = UDim2.fromScale(0.8, 0.1),
			Text = rarity and rarity.DisplayName or "",
		}),
		create("Frame")({
			Name = "ChancePill",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.8),
			Size = UDim2.fromScale(0.62, 0.14),
			BackgroundColor3 = Color3.fromRGB(48, 80, 58),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,

			create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
			Plastic.Label({
				Name = "Chance",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.86, 0.78),
				Text = PlantSelector.FormatChance(PlantSelector.GetChance(plantId)),
			}),
		}),
	}

	local rootChildren
	if winnerScale then
		rootChildren = {
			create("UIScale")({
				Scale = function()
					return winnerScale()
				end,
			}),
		}
	end

	return Plastic.Panel({
		Name = plantId,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.92, 0.9),
		BodyColor = rarity and rarity.Color,
		BorderColor = rarity and rarity.DarkColor,
		Corner = 0.14,
		Children = cardChildren,
		RootChildren = rootChildren,
	})
end

local function Diamond(positionY)
	return create("Frame")({
		Name = "Marker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, positionY),
		Size = UDim2.fromScale(0.04, 0.04),
		Rotation = 45,
		BackgroundColor3 = Plastic.Colors.Gold,
		BorderSizePixel = 0,

		create("UIAspectRatioConstraint")({ AspectRatio = 1 }),
		create("UICorner")({ CornerRadius = UDim.new(0.2, 0) }),
	})
end

local function SelectionOverlay(reel, winnerId, values)
	local selection = PlantsConfig.Selection
	local cardWidth = 1 / selection.VisibleCards
	local count = #reel
	local rarity = PlantsConfig.GetRarity(winnerId)

	local cards = {}
	for index, plantId in ipairs(reel) do
		cards[index] = create("Frame")({
			Name = "Slot" .. index,
			LayoutOrder = index,
			Size = UDim2.fromScale(1 / count, 1),
			BackgroundTransparency = 1,

			PlantCard(plantId, index == selection.WinnerIndex and values.winnerScale or nil),
		})
	end

	local reelFrame = create("Frame")({
		Name = "Reel",
		Position = function()
			return UDim2.fromScale(0.5 - (values.card() + 0.5) * cardWidth, 0)
		end,
		Size = UDim2.fromScale(count * cardWidth, 1),
		BackgroundTransparency = 1,

		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		cards,
	})

	local gui = create("ScreenGui")({
		Name = "PlantSelection",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 50,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,

		create("Frame")({
			Name = "Dim",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(70, 100, 80),
			BackgroundTransparency = function()
				return 1 - 0.45 * values.alpha()
			end,
			BorderSizePixel = 0,
			Active = false, -- never sink input: the overlay must not interfere with camera/controls
		}),

		create("CanvasGroup")({
			Name = "Content",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			GroupTransparency = function()
				return 1 - values.alpha()
			end,

			Plastic.Label({
				Name = "Title",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.11),
				Size = UDim2.fromScale(0.5, 0.09),
				Text = "Choosing your plant!",
				Color = Plastic.Colors.Gold,
			}),

			Plastic.Panel({
				Name = "Carousel",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.45),
				Size = UDim2.fromScale(0.82, 0.44),
				BodyColor = Color3.fromRGB(122, 186, 130),
				BorderColor = Plastic.Colors.PanelBorder,
				Corner = 0.1,
				Gloss = false,
				Children = {
					create("Frame")({
						Name = "Viewport",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromScale(0.97, 0.94),
						BackgroundTransparency = 1,
						ClipsDescendants = true,

						reelFrame,

						-- center highlight
						create("Frame")({
							Name = "Highlight",
							AnchorPoint = Vector2.new(0.5, 0.5),
							Position = UDim2.fromScale(0.5, 0.5),
							Size = UDim2.fromScale(cardWidth, 1),
							BackgroundColor3 = Color3.fromRGB(255, 255, 255),
							BackgroundTransparency = 0.88,
							BorderSizePixel = 0,

							create("Frame")({
								Name = "Left",
								Size = UDim2.fromScale(0.03, 1),
								BackgroundColor3 = Plastic.Colors.Gold,
								BorderSizePixel = 0,
							}),
							create("Frame")({
								Name = "Right",
								AnchorPoint = Vector2.new(1, 0),
								Position = UDim2.fromScale(1, 0),
								Size = UDim2.fromScale(0.03, 1),
								BackgroundColor3 = Plastic.Colors.Gold,
								BorderSizePixel = 0,
							}),
						}),
					}),
				},
			}),

			Diamond(0.23),
			Diamond(0.67),

			-- Reveal
			create("CanvasGroup")({
				Name = "Reveal",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.71),
				Size = UDim2.fromScale(0.6, 0.26),
				BackgroundTransparency = 1,
				GroupTransparency = function()
					return 1 - values.reveal()
				end,

				create("UIScale")({
					Scale = function()
						return 0.8 + 0.2 * values.reveal()
					end,
				}),
				Plastic.Label({
					Name = "WinnerName",
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.fromScale(0.5, 0),
					Size = UDim2.fromScale(0.9, 0.42),
					Text = PlantsConfig.GetDisplayName(winnerId),
				}),
				Plastic.Label({
					Name = "WinnerRarity",
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.fromScale(0.5, 0.45),
					Size = UDim2.fromScale(0.7, 0.26),
					Color = rarity and rarity.Color or Plastic.Colors.Text,
					Text = ("%s  -  %s"):format(
						rarity and rarity.DisplayName or "?",
						PlantSelector.FormatChance(PlantSelector.GetChance(winnerId))
					),
				}),
				Plastic.Label({
					Name = "GrowTime",
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.fromScale(0.5, 0.74),
					Size = UDim2.fromScale(0.5, 0.2),
					Text = "Grows in " .. Anim.FormatTime(PlantsConfig.GetGrowTime(winnerId)),
				}),
			}),
		}),
	})

	-- Vide does not destroy instances when a root is destroyed, so register the ScreenGui explicitly
	Vide.cleanup(gui)
	return gui
end

---- Playback

local function removeLeftoverOverlays()
	local playerGui = player:FindFirstChild("PlayerGui")
	local leftover = playerGui and playerGui:FindFirstChild("PlantSelection")
	while leftover do
		leftover:Destroy()
		leftover = playerGui:FindFirstChild("PlantSelection")
	end
end

local function stop()
	if activeStop then
		activeStop()
		activeStop = nil
	end
end

local function play(state)
	stop()
	removeLeftoverOverlays()

	local selection = PlantsConfig.Selection
	local total = selection.ScrollTime + selection.RevealTime
	if workspace:GetServerTimeNow() - state.PhaseStart >= total then
		return -- joined after the animation ended
	end
	if not PlantsConfig.GetPlant(state.PlantId) then
		return
	end

	-- identical reel for everyone: seeded by the cycle id
	local reel = PlantSelector.BuildReel(
		state.PlantId,
		selection.ReelLength,
		selection.WinnerIndex,
		Random.new(state.CycleId * 7919 + 13)
	)

	local values = {
		alpha = source(0), -- overlay visibility
		card = source(0), -- carousel position, in cards (0 = first card centered)
		reveal = source(0), -- winner reveal progress
		winnerScale = source(1),
	}

	local destroyUi = Vide.mount(function()
		return SelectionOverlay(reel, state.PlantId, values)
	end, player:WaitForChild("PlayerGui"))

	local audio = Knit.GetController("Audio_Controller")
	local plant = PlantsConfig.GetPlant(state.PlantId)
	local lastCard = 0
	local revealed = false

	local connection
	local tornDown = false
	local function teardown()
		if tornDown then
			return
		end
		tornDown = true
		if connection then
			connection:Disconnect()
			connection = nil
		end
		destroyUi() -- destroys the ScreenGui (registered with Vide.cleanup) and all its effects
		removeLeftoverOverlays() -- safety net
	end

	connection = RunService.RenderStepped:Connect(function()
		local t = workspace:GetServerTimeNow() - state.PhaseStart
		if t >= total then
			teardown()
			if activeStop == teardown then
				activeStop = nil
			end
			return
		end

		Vide.batch(function()
			values.alpha(math.min(math.clamp(t / FADE_IN, 0, 1), math.clamp((total - t) / FADE_OUT, 0, 1)))

			-- easeOutQuart: fast start, long smooth slowdown onto the winner
			local scroll = math.clamp(t / selection.ScrollTime, 0, 1)
			local card = Anim.EaseOutQuart(scroll) * (selection.WinnerIndex - 1)
			values.card(card)

			-- tick every time a card passes the marker (slower and lower as the reel slows down)
			local passed = math.floor(card + 0.5)
			if passed ~= lastCard then
				lastCard = passed
				audio:Play("CardTick", { Pitch = 1.25 - 0.5 * scroll })
			end
			-- the winner is revealed: a sting that gets bigger with the rarity
			if not revealed and t >= selection.ScrollTime then
				revealed = true
				audio:Play("Reveal" .. (plant and plant.Rarity or "Common"))
			end

			local reveal = math.clamp((t - selection.ScrollTime) / REVEAL_IN, 0, 1)
			values.reveal(reveal)
			values.winnerScale(1 + 0.12 * Anim.EaseOutBack(reveal))
		end)
	end)

	activeStop = teardown
end

function PlantSelection_Controller:KnitStart()
	local cycle = Knit.GetController("PlantCycle_Controller")

	cycle.StateChanged:Connect(function(state)
		if state.Phase == "Selecting" then
			play(state)
		else
			stop()
		end
	end)

	local current = cycle.State()
	if current.Phase == "Selecting" then
		play(current)
	end
end

function PlantSelection_Controller:KnitInit() end

return PlantSelection_Controller
