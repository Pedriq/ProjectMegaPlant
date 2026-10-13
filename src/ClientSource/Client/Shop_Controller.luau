local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Vide = require(ReplicatedStorage.Packages.Vide)
local StatsConfig = require(ReplicatedStorage.SharedSource.Datas.StatsConfig)
local UpgradesConfig = require(ReplicatedStorage.SharedSource.Datas.UpgradesConfig)
local Plastic = require(ReplicatedStorage.ClientSource.UI.Plastic)
local ShopCamera = require(ReplicatedStorage.ClientSource.UI.ShopCamera)
local WaitFor = require(ReplicatedStorage.ClientSource.Utilities.WaitFor)

local create = Vide.create
local source = Vide.source

--[[
	The upgrade shop. Activating the ProximityPrompt on Workspace/Garden/UpgradeShop/MainHouse opens a panel
	with one card per upgrade (stacked top to bottom). While it is open the background is blurred and the
	camera zooms out; closing it (X button, walking away, respawning) restores everything.

	Levels come from the replicated player attributes, coins from leaderstats, and a purchase is just a
	request: Upgrade_Service decides whether it succeeds.
]]
local Shop_Controller = Knit.CreateController({
	Name = "Shop_Controller",
})

local player = Players.LocalPlayer

local Upgrade_Service, Audio_Controller

local isOpen = source(false)
local shopPart -- the part the open shop belongs to (for the "walked away" check)
local shopPrompt
local distanceConnection

local BUY_READY = Color3.fromRGB(88, 184, 110)
local BUY_READY_BORDER = Color3.fromRGB(36, 120, 48)
local BUY_DISABLED = Color3.fromRGB(160, 172, 164)
local BUY_DISABLED_BORDER = Color3.fromRGB(78, 82, 96)
local BUY_MAX = Color3.fromRGB(240, 196, 94)
local BUY_MAX_BORDER = Color3.fromRGB(170, 100, 20)

local function formatNumber(value)
	local text = tostring(math.floor(value + 0.5))
	return (text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

---- UI

--- One upgrade card. Layout (all Scale):
---   [icon]  Name                 [LV n]   |  [ 💰 price ]
---           caption (what it does)        |  [  UPGRADE  ]
---           x1.24  ➜  x1.45  (big)
--- Every upgrade has its own accent color and glyph (UpgradesConfig), so the cards are told apart at a glance.
local function UpgradeCard(upgradeId, layoutOrder, level, coins, onBuy)
	local config = UpgradesConfig.Upgrades[upgradeId]
	local accent = config.Accent or Plastic.Colors.PanelBody

	local function price()
		return UpgradesConfig.GetPrice(upgradeId, level())
	end
	local function affordable()
		return coins() >= price()
	end
	local function parts()
		return UpgradesConfig.GetEffectParts(upgradeId, level())
	end

	local icon
	if config.IconImage then
		icon = create("ImageLabel")({
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.78, 0.78),
			BackgroundTransparency = 1,
			Image = config.IconImage,
			ScaleType = Enum.ScaleType.Fit,
		})
	else
		icon = Plastic.Label({
			Name = "Glyph",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.72, 0.72),
			Text = config.Glyph or "?",
		})
	end

	return Plastic.Panel({
		Name = upgradeId,
		LayoutOrder = layoutOrder,
		-- the cards share the height of the list (4% gaps), whatever the number of upgrades
		Size = UDim2.fromScale(1, (1 - 0.04 * (#UpgradesConfig.Order - 1)) / #UpgradesConfig.Order),
		BodyColor = accent,
		Corner = 0.2,
		Children = {
			-- icon plate in a deeper shade of the accent
			Plastic.Panel({
				Name = "IconPlate",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0.025, 0.5),
				Size = UDim2.fromScale(0.15, 0.68),
				BodyColor = accent:Lerp(Color3.new(0, 0, 0), 0.18),
				Style = "Accent",
				Corner = 0.3,
				Studs = false,
				Children = {
					create("UIAspectRatioConstraint")({ AspectRatio = 1 }),
					icon,
				},
			}),

			-- 1) name (the strongest text of the card)
			Plastic.Label({
				Name = "Name",
				Position = UDim2.fromScale(0.2, 0.08),
				Size = UDim2.fromScale(0.34, 0.3),
				XAlignment = Enum.TextXAlignment.Left,
				Text = config.DisplayName,
			}),
			-- 2) current level, a small chip next to the name
			Plastic.Panel({
				Name = "LevelChip",
				Position = UDim2.fromScale(0.555, 0.11),
				Size = UDim2.fromScale(0.095, 0.24),
				BodyColor = accent:Lerp(Color3.new(0, 0, 0), 0.25),
				Style = "Accent",
				Corner = 0.5,
				Studs = false,
				Children = {
					Plastic.Label({
						Name = "Level",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromScale(0.86, 0.66),
						Text = function()
							return ("LV %d"):format(level())
						end,
					}),
				},
			}),
			-- 3) what it improves, small and quiet
			Plastic.Label({
				Name = "Caption",
				Position = UDim2.fromScale(0.2, 0.4),
				Size = UDim2.fromScale(0.45, 0.17),
				XAlignment = Enum.TextXAlignment.Left,
				Color = Color3.fromRGB(236, 244, 240),
				Text = function()
					return config.Description
				end,
			}),
			-- 4) THE benefit: current value big, the next level in green
			Plastic.Label({
				Name = "Benefit",
				Position = UDim2.fromScale(0.2, 0.6),
				Size = UDim2.fromScale(0.45, 0.32),
				XAlignment = Enum.TextXAlignment.Left,
				RichText = true,
				Text = function()
					local effect = parts()
					return ('%s  <font color="#c6ffd0">➜  %s</font>'):format(effect.Current, effect.Next)
				end,
			}),

			-- thin divider: information on the left, buying on the right
			create("Frame")({
				Name = "Divider",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.672, 0.5),
				Size = UDim2.fromScale(0.004, 0.66),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.7,
				BorderSizePixel = 0,
			}),

			-- buy block: price on top, the action below
			Plastic.Panel({
				Name = "BuyButton",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(0.975, 0.5),
				Size = UDim2.fromScale(0.28, 0.72),
				Corner = 0.3,
				Style = "Accent",
				BodyColor = function()
					return affordable() and BUY_READY or BUY_DISABLED
				end,
				Children = {
					Plastic.Label({
						Name = "Price",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.08),
						Size = UDim2.fromScale(0.86, 0.5),
						Color = function()
							return affordable() and Color3.new(1, 1, 1) or Color3.fromRGB(255, 226, 226)
						end,
						Text = function()
							return "💰 " .. formatNumber(price())
						end,
					}),
					Plastic.Label({
						Name = "Action",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.6),
						Size = UDim2.fromScale(0.7, 0.28),
						Color = Color3.fromRGB(240, 248, 240),
						Text = "UPGRADE",
					}),
					-- hit area; the server decides if the purchase works
					create("TextButton")({
						Name = "Hit",
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Text = "",
						ZIndex = 10,
						Activated = function()
							onBuy(upgradeId)
						end,
					}),
				},
			}),
		},
	})
end

local function ShopUI(levels, coins, onBuy, onClose)
	local scale = Vide.spring(function()
		return isOpen() and 1 or 0
	end, 0.3, 0.6)
	local shownCoins = Vide.spring(function()
		return coins()
	end, 0.3, 1)

	local cards = {}
	for index, upgradeId in ipairs(UpgradesConfig.Order) do
		cards[index] = UpgradeCard(upgradeId, index, levels[upgradeId], coins, onBuy)
	end

	return create("ScreenGui")({
		Name = "UpgradeShop",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 30,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = function()
			return isOpen() or scale() > 0.02
		end,

		create("Frame")({
			Name = "Root",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.56, 0.78),
			BackgroundTransparency = 1,

			create("UIAspectRatioConstraint")({
				AspectRatio = 1.12,
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
				Corner = 0.1,
				BodyColor = Color3.fromRGB(104, 204, 86),
				BorderColor = Color3.fromRGB(38, 94, 52),
				Children = {
					Plastic.Label({
						Name = "Title",
						AnchorPoint = Vector2.new(0, 0),
						Position = UDim2.fromScale(0.04, 0.03),
						Size = UDim2.fromScale(0.45, 0.1),
						XAlignment = Enum.TextXAlignment.Left,
						Text = "Upgrade Shop",
					}),

					-- coin balance
					Plastic.Panel({
						Name = "Coins",
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.fromScale(0.86, 0.035),
						Size = UDim2.fromScale(0.3, 0.085),
						BodyColor = Color3.fromRGB(240, 196, 94),
						BorderColor = Color3.fromRGB(170, 100, 20),
						Corner = 0.5,
						Children = {
							Plastic.Label({
								Name = "Amount",
								AnchorPoint = Vector2.new(0.5, 0.5),
								Position = UDim2.fromScale(0.5, 0.5),
								Size = UDim2.fromScale(0.86, 0.7),
								Text = function()
									return formatNumber(shownCoins())
								end,
							}),
						},
					}),

					-- close button
					Plastic.Panel({
						Name = "Close",
						Style = "Accent",
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.fromScale(0.97, 0.025),
						Size = UDim2.fromScale(0.09, 0.1),
						BodyColor = Color3.fromRGB(226, 112, 108),
						BorderColor = Color3.fromRGB(150, 36, 52),
						Corner = 0.35,
						Children = {
							create("UIAspectRatioConstraint")({ AspectRatio = 1 }),
							Plastic.Label({
								Name = "X",
								AnchorPoint = Vector2.new(0.5, 0.5),
								Position = UDim2.fromScale(0.5, 0.5),
								Size = UDim2.fromScale(0.7, 0.7),
								Text = "X",
							}),
							create("TextButton")({
								Name = "Hit",
								Size = UDim2.fromScale(1, 1),
								BackgroundTransparency = 1,
								Text = "",
								ZIndex = 10,
								Activated = onClose,
							}),
						},
					}),

					-- the upgrade cards, stacked from top to bottom
					create("Frame")({
						Name = "Cards",
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.fromScale(0.5, 0.97),
						Size = UDim2.fromScale(0.92, 0.77),
						BackgroundTransparency = 1,

						create("UIListLayout")({
							FillDirection = Enum.FillDirection.Vertical,
							SortOrder = Enum.SortOrder.LayoutOrder,
							VerticalAlignment = Enum.VerticalAlignment.Top,
							Padding = UDim.new(0.04, 0),
						}),
						cards,
					}),
				},
			}),
		}),
	})
end

---- Opening / closing

local function close()
	if not isOpen() then
		return
	end
	isOpen(false)
	ShopCamera.SetOpen(false)
	if distanceConnection then
		distanceConnection:Disconnect()
		distanceConnection = nil
	end
	Audio_Controller:Play("UiClick")
end

local function open(prompt)
	if isOpen() then
		return
	end
	shopPrompt = prompt
	shopPart = prompt.Parent
	isOpen(true)
	ShopCamera.SetOpen(true)
	Audio_Controller:Play("ShopOpen")

	-- walking away closes the shop (the server also checks the distance on every purchase)
	distanceConnection = RunService.Heartbeat:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not shopPart or not shopPart.Parent then
			close()
			return
		end
		local limit = shopPrompt.MaxActivationDistance + UpgradesConfig.Shop.DistanceTolerance - 2
		if (root.Position - shopPart.Position).Magnitude > limit then
			close()
		end
	end)
end

---- Lifecycle

function Shop_Controller:KnitStart()
	Upgrade_Service = Knit.GetService("Upgrade_Service")
	Audio_Controller = Knit.GetController("Audio_Controller")

	-- replicated upgrade levels
	local levels = {}
	for _, upgradeId in ipairs(UpgradesConfig.Order) do
		local attribute = UpgradesConfig.GetAttributeName(upgradeId)
		levels[upgradeId] = source(player:GetAttribute(attribute) or 0)
		player:GetAttributeChangedSignal(attribute):Connect(function()
			levels[upgradeId](player:GetAttribute(attribute) or 0)
		end)
	end

	-- coins (leaderstats)
	local coins = source(StatsConfig.ByKey.Coins.Default)
	task.spawn(function()
		local leaderstats = WaitFor.Child(player, StatsConfig.Folder)
		local value = leaderstats and WaitFor.Child(leaderstats, StatsConfig.ByKey.Coins.DisplayName, 60)
		if value then
			coins(value.Value)
			value.Changed:Connect(function(newValue)
				coins(newValue)
			end)
		end
	end)

	local function onBuy(upgradeId)
		Upgrade_Service:Purchase(upgradeId)
			:andThen(function(result)
				if result.Success then
					Audio_Controller:Play("Purchase", { Pitch = 1 + result.Level * 0.02 })
				else
					Audio_Controller:Play("PurchaseFail")
				end
			end)
			:catch(warn)
	end

	Vide.mount(function()
		return ShopUI(levels, coins, onBuy, close)
	end, player:WaitForChild("PlayerGui"))

	ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
		if triggeringPlayer == player and prompt.Name == UpgradesConfig.Shop.PromptName then
			open(prompt)
		end
	end)

	-- a respawn always closes the shop and restores the camera
	player.CharacterAdded:Connect(close)
end

function Shop_Controller:KnitInit() end

return Shop_Controller
