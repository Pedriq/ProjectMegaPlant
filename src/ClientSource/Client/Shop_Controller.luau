local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Vide = require(ReplicatedStorage.Packages.Vide)
local StatsConfig = require(ReplicatedStorage.SharedSource.Datas.StatsConfig)
local UpgradesConfig = require(ReplicatedStorage.SharedSource.Datas.UpgradesConfig)
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

	Look: Figma "Upgrade Shop · Roblox · Ref Style" (Task-UIKIT, node 2560:1316). The panel is laid out in the
	design's pixels on a fixed canvas and a UIScale fits it to the screen, so outlines, gradients and text keep
	the exact proportions of the design on any resolution.
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

local function formatNumber(value)
	local text = tostring(math.floor(value + 0.5))
	return (text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

---- Style

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local FONT = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.ExtraBold)
local FONT_BOLD = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Bold)

local WHITE = Color3.new(1, 1, 1)
local BLACK = rgb(10, 10, 10)

-- Roblox "Stud" texture laid under the text of every card
local CARD_PATTERN = "rbxassetid://139348939021356"
local CARD_PATTERN_TILE = 100
local CARD_PATTERN_TRANSPARENCY = 0.8

-- vertical gradients, light on top (same stops as the Figma frame)
local Colors = {
	Panel = ColorSequence.new(rgb(107, 98, 72), rgb(75, 70, 50)),
	Header = ColorSequence.new({
		ColorSequenceKeypoint.new(0, rgb(114, 242, 95)),
		ColorSequenceKeypoint.new(0.5, rgb(39, 194, 63)),
		ColorSequenceKeypoint.new(1, rgb(12, 154, 45)),
	}),
	-- the lower half of Header on its own (used to square off the header's bottom corners)
	HeaderLower = ColorSequence.new(rgb(39, 194, 63), rgb(12, 154, 45)),
	Gold = ColorSequence.new(rgb(255, 224, 74), rgb(242, 140, 0)),
	Red = ColorSequence.new(rgb(232, 71, 95), rgb(142, 18, 48)),
	Lime = ColorSequence.new(rgb(182, 255, 74), rgb(63, 178, 30)),
	BuyReady = ColorSequence.new(rgb(124, 242, 90), rgb(24, 160, 52)),
	BuyDisabled = ColorSequence.new(rgb(228, 228, 228), rgb(140, 140, 140)),
	CoinFace = ColorSequence.new(rgb(255, 230, 110), rgb(232, 160, 20)),
}
local NEXT_VALUE_TEXT = rgb(20, 61, 10)
local DISABLED_TEXT = rgb(69, 69, 69)
local DEFAULT_ACCENT = rgb(96, 168, 232)

-- canvas layout, in design pixels (1:1 with the Figma frame, strokes are drawn inside the shapes)
local CANVAS_W = 620
local PANEL_STROKE = 4
local PANEL_CORNER = 24
local HEADER_W = CANVAS_W - PANEL_STROKE * 2
local HEADER_H = 84 -- green part; the black divider sits right below
local DIVIDER_H = 4
local BODY_Y = PANEL_STROKE + HEADER_H + DIVIDER_H
local PAD_X = 24
local PAD_TOP = 22
local CARD_W = CANVAS_W - PAD_X * 2
local CARD_H = 124
local CARD_GAP = 12
local HINT_GAP = 18
local HINT_H = 20
local PAD_BOTTOM = 22
local CARD_COUNT = #UpgradesConfig.Order
local CARDS_Y = BODY_Y + PAD_TOP
local CARDS_H = CARD_COUNT * CARD_H + (CARD_COUNT - 1) * CARD_GAP
local HINT_Y = CARDS_Y + CARDS_H + HINT_GAP
local CANVAS_H = HINT_Y + HINT_H + PAD_BOTTOM

-- the largest share of the screen the panel may take
local MAX_SCREEN_W = 0.56
local MAX_SCREEN_H = 0.84

---- UI kit (local to the shop)

local function append(props, children)
	if children then
		for _, child in ipairs(children) do
			props[#props + 1] = child
		end
	end
	return props
end

local function read(value)
	if type(value) == "function" then
		return value()
	end
	return value
end

local function Corner(px)
	return create("UICorner")({ CornerRadius = UDim.new(0, px) })
end

local function Gradient(colors)
	return create("UIGradient")({ Rotation = 90, Color = colors })
end

--- Black outline drawn inside the shape (like Figma's "Inside" stroke), so sizes match the design exactly.
local function Outline(thickness)
	return create("UIStroke")({
		Thickness = thickness,
		Color = BLACK,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		BorderStrokePosition = Enum.BorderStrokePosition.Inner,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

--- Glossy band over the top of a surface: white fading out downwards. Sits behind the surface's content.
local function Sheen(alpha, inset, height, corner)
	return create("Frame")({
		Name = "Sheen",
		Position = UDim2.fromOffset(inset, inset),
		Size = UDim2.new(1, -inset * 2, 0, height),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 0,

		Corner(corner),
		create("UIGradient")({
			Rotation = 90,
			Transparency = NumberSequence.new(1 - alpha, 1),
		}),
	})
end

--- Tiled stud texture inside a surface, under all of its content (and inside its outline).
local function Pattern(inset, corner, zIndex)
	return create("ImageLabel")({
		Name = "Pattern",
		Position = UDim2.fromOffset(inset, inset),
		Size = UDim2.new(1, -inset * 2, 1, -inset * 2),
		BackgroundTransparency = 1,
		Image = CARD_PATTERN,
		ImageTransparency = CARD_PATTERN_TRANSPARENCY,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(CARD_PATTERN_TILE, CARD_PATTERN_TILE),
		ZIndex = zIndex or 0,

		Corner(corner),
	})
end

--- Surface with a vertical gradient, a thick black outline and an optional sheen.
--- props: Name, AnchorPoint, Position, Size, LayoutOrder, Colors (ColorSequence or function),
---        Stroke (px), Corner (px, default 4), Sheen (alpha), SheenHeight (px), Pattern (bool), Children
local function Box(props)
	local corner = props.Corner or 4
	local inset = props.Stroke or 0
	local frame = {
		Name = props.Name,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		LayoutOrder = props.LayoutOrder,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = props.BackgroundTransparency or 0,
		BorderSizePixel = 0,

		Corner(corner),
		Gradient(props.Colors),
	}
	if props.Stroke then
		frame[#frame + 1] = Outline(props.Stroke)
	end
	if props.Pattern then
		frame[#frame + 1] = Pattern(inset, math.max(corner - 1, 0))
	end
	if props.Sheen then
		frame[#frame + 1] = Sheen(props.Sheen, inset, props.SheenHeight or 30, 1)
	end
	return create("Frame")(append(frame, props.Children))
end

-- rough glyph widths of Nunito ExtraBold, as a share of the text height (used to size boxes around numbers)
local GLYPH_WIDTH = {
	[","] = 0.28,
	["."] = 0.28,
	[" "] = 0.28,
	["%"] = 0.9,
	["x"] = 0.56,
	["L"] = 0.52,
	["V"] = 0.68,
}

--- Width of a box that fits `text` when it is drawn `height` px tall.
local function fitWidth(text, height)
	local width = 0
	for _, code in utf8.codes(text) do
		local char = utf8.char(code)
		width += GLYPH_WIDTH[char] or (char:match("%d") and 0.6 or 0.62)
	end
	return math.ceil(width * height) + 2
end

--- Text that scales to fill its box (TextScaled), with an optional black outline and a hard drop shadow.
--- The box height is the text size; long texts shrink to the box width.
--- props: Name, AnchorPoint, Position, Size (or Height + FitText: the width follows the text),
---        LayoutOrder, Text, Font, Color, Transparency, Stroke, Shadow, ShadowTransparency,
---        Outlined (function -> bool, toggles stroke+shadow), XAlignment
local function Text(props)
	local size = props.Size
	if props.FitText then
		size = function()
			return UDim2.fromOffset(fitWidth(read(props.Text), props.Height), props.Height)
		end
	end

	local function label(isShadow)
		local children = {}
		if props.Stroke then
			children[1] = create("UIStroke")({
				Thickness = props.Stroke,
				Color = BLACK,
				LineJoinMode = Enum.LineJoinMode.Round,
				Transparency = isShadow and (props.ShadowTransparency or 0) or 0,
				Enabled = props.Outlined,
			})
		end
		return create("TextLabel")(append({
			Name = isShadow and "Shadow" or "Text",
			Position = isShadow and UDim2.fromOffset(0, props.Shadow) or UDim2.new(),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			FontFace = props.Font or FONT,
			Text = props.Text,
			TextScaled = true,
			TextColor3 = isShadow and BLACK or (props.Color or WHITE),
			TextTransparency = isShadow and (props.ShadowTransparency or 0) or (props.Transparency or 0),
			TextXAlignment = props.XAlignment or Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			Visible = isShadow and props.Outlined or nil,
			ZIndex = isShadow and 1 or 2,
		}, children))
	end

	return create("Frame")({
		Name = props.Name or "Label",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = size,
		LayoutOrder = props.LayoutOrder,
		BackgroundTransparency = 1,

		props.Shadow and label(true) or nil,
		label(false),
	})
end

--- Round gold coin with a "$".
local function Coin(size, layoutOrder)
	return create("Frame")({
		Name = "Coin",
		Size = UDim2.fromOffset(size, size),
		LayoutOrder = layoutOrder,
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,

		create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
		Gradient(Colors.CoinFace),
		create("UIStroke")({ Thickness = 2, Color = rgb(122, 74, 0) }),
		create("TextLabel")({
			Name = "Sign",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.7, 0.7),
			BackgroundTransparency = 1,
			FontFace = FONT,
			Text = "$",
			TextScaled = true,
			TextColor3 = rgb(138, 90, 0),
		}),
	})
end

--- Horizontal row whose items are centered vertically.
local function Row(props)
	return create("Frame")(append({
		Name = props.Name or "Row",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		AutomaticSize = props.AutomaticSize,
		BackgroundTransparency = 1,

		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = props.HorizontalAlignment or Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, props.Gap or 8),
		}),
	}, props.Children))
end

local function HitButton(onActivated)
	return create("TextButton")({
		Name = "Hit",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 10,
		Activated = onActivated,
	})
end

---- UI

--- One upgrade card (572 x 124):
---   [ icon ]  Name                  [LV n]  |  [ $ price ]
---   [ 96px ]  caption (what it does)        |  [ UPGRADE ]
---   [ plate]  x1.24  →  [x1.45]
--- Every upgrade keeps its own accent color (UpgradesConfig), so the cards are told apart at a glance.
local function UpgradeCard(upgradeId, layoutOrder, level, coins, onBuy)
	local config = UpgradesConfig.Upgrades[upgradeId]
	local accent = config.Accent or DEFAULT_ACCENT

	local function price()
		return UpgradesConfig.GetPrice(upgradeId, level())
	end
	local function affordable()
		return coins() >= price()
	end
	local function parts()
		return UpgradesConfig.GetEffectParts(upgradeId, level())
	end
	local function nextValue()
		return parts().Next
	end

	-- the UPGRADE button itself reacts: it squashes when pressed and springs back with a little overshoot, and
	-- pops bigger when the level really goes up (same spring "bump" the HUD rows use)
	local buttonScale = source(1)
	local buttonScaleSpring = Vide.spring(function()
		return buttonScale()
	end, 0.22, 0.45)
	local function pressButton()
		task.defer(function()
			buttonScale(0.86)
			task.delay(0.09, function()
				buttonScale(1)
			end)
		end)
	end
	local lastLevel = level()
	Vide.effect(function()
		local current = level()
		if current > lastLevel then
			task.defer(function()
				buttonScale(1.2)
				task.delay(0.1, function()
					buttonScale(1)
				end)
			end)
		end
		lastLevel = current
	end)

	local icon
	if config.IconImage then
		icon = create("ImageLabel")({
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(48, 48),
			BackgroundTransparency = 1,
			Image = config.IconImage,
			ScaleType = Enum.ScaleType.Fit,
		})
	else
		icon = create("TextLabel")({
			Name = "Glyph",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(48, 48),
			BackgroundTransparency = 1,
			Text = config.Glyph or "?",
			TextScaled = true,
			TextColor3 = WHITE,
		})
	end

	return Box({
		Name = upgradeId,
		LayoutOrder = layoutOrder,
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		Colors = ColorSequence.new(accent:Lerp(WHITE, 0.35), accent:Lerp(BLACK, 0.2)),
		Stroke = 3,
		Corner = 4,
		Pattern = true,
		Children = {
			-- big square icon plate in a deeper shade of the accent
			Box({
				Name = "IconPlate",
				Position = UDim2.fromOffset(19, 14),
				Size = UDim2.fromOffset(96, 96),
				Colors = ColorSequence.new(accent:Lerp(BLACK, 0.05), accent:Lerp(BLACK, 0.45)),
				Stroke = 3,
				Corner = 4,
				Children = { icon },
			}),

			-- 1) name (the strongest text of the card)
			Text({
				Name = "Name",
				Position = UDim2.fromOffset(127, 15),
				Size = UDim2.fromOffset(236, 26),
				Text = config.DisplayName,
				Stroke = 2,
				Shadow = 2,
			}),
			-- 2) current level, a quiet chip at the end of the name line
			create("Frame")({
				Name = "LevelChip",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromOffset(439, 16),
				Size = UDim2.fromOffset(66, 24),
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.7,
				BorderSizePixel = 0,

				Corner(4),
				Text({
					Name = "Level",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.new(1, -12, 0, 14),
					XAlignment = Enum.TextXAlignment.Center,
					Text = function()
						return ("LV %d"):format(level())
					end,
					Transparency = 0.05,
				}),
			}),
			-- 3) what it improves, small and quiet (no outline)
			Text({
				Name = "Caption",
				Position = UDim2.fromOffset(127, 46),
				Size = UDim2.fromOffset(312, 17),
				Text = config.Description,
				Font = FONT_BOLD,
				Transparency = 0.1,
				Shadow = 1,
				ShadowTransparency = 0.65,
			}),
			-- 4) THE benefit: current value, then the next level on a lime chip
			Row({
				Name = "Benefit",
				Position = UDim2.fromOffset(127, 70),
				Size = UDim2.fromOffset(312, 34),
				Gap = 10,
				Children = {
					Text({
						Name = "Current",
						LayoutOrder = 1,
						FitText = true,
						Height = 25,
						Text = function()
							return parts().Current
						end,
						Font = FONT_BOLD,
						Transparency = 0.2,
						Shadow = 1,
						ShadowTransparency = 0.65,
					}),
					Text({
						Name = "Arrow",
						LayoutOrder = 2,
						Size = UDim2.fromOffset(20, 22),
						XAlignment = Enum.TextXAlignment.Center,
						Text = "→",
						Transparency = 0.15,
					}),
					Box({
						Name = "Next",
						LayoutOrder = 3,
						Size = function()
							return UDim2.fromOffset(fitWidth(nextValue(), 25) + 30, 32)
						end,
						Colors = Colors.Lime,
						Stroke = 2.5,
						Corner = 3,
						Children = {
							Text({
								Name = "Value",
								AnchorPoint = Vector2.new(0.5, 0.5),
								Position = UDim2.fromScale(0.5, 0.5),
								Size = UDim2.new(1, -30, 0, 25),
								XAlignment = Enum.TextXAlignment.Center,
								Text = nextValue,
								Color = NEXT_VALUE_TEXT,
							}),
						},
					}),
				},
			}),

			-- buy block: price on top, the action below; green when affordable, grey otherwise
			Box({
				Name = "BuyButton",
				-- anchored at its centre, so the press / pop scales it around the middle
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, -70, 0.5, 0),
				Size = UDim2.fromOffset(102, 88),
				Colors = function()
					return affordable() and Colors.BuyReady or Colors.BuyDisabled
				end,
				Stroke = 3,
				Corner = 3,
				Sheen = 0.45,
				SheenHeight = 30,
				Children = {
					Row({
						Name = "Price",
						Position = UDim2.fromOffset(6, 16),
						Size = UDim2.new(1, -12, 0, 30),
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						Gap = 5,
						Children = {
							Coin(22, 1),
							Text({
								Name = "Amount",
								LayoutOrder = 2,
								Height = 27,
								Size = function()
									-- never wider than the button (long prices just shrink)
									return UDim2.fromOffset(math.min(fitWidth(formatNumber(price()), 27), 62), 27)
								end,
								Text = function()
									return formatNumber(price())
								end,
								Color = function()
									return affordable() and WHITE or DISABLED_TEXT
								end,
								Stroke = 2,
								Shadow = 2,
								Outlined = affordable,
							}),
						},
					}),
					Text({
						Name = "Action",
						Position = UDim2.fromOffset(8, 53),
						Size = UDim2.new(1, -16, 0, 15),
						XAlignment = Enum.TextXAlignment.Center,
						Text = "UPGRADE",
						Color = function()
							return affordable() and WHITE or DISABLED_TEXT
						end,
						Stroke = 1.5,
						Shadow = 1,
						Outlined = affordable,
					}),
					-- hit area; the server decides if the purchase works
					HitButton(function()
						pressButton()
						onBuy(upgradeId)
					end),
					create("UIScale")({
						Scale = function()
							return buttonScaleSpring()
						end,
					}),
				},
			}),
		},
	})
end

local function Header(coins, onClose)
	local shownCoins = Vide.spring(function()
		return coins()
	end, 0.3, 1)
	local function coinsText()
		return formatNumber(shownCoins())
	end
	local innerCorner = PANEL_CORNER - PANEL_STROKE

	return create("Frame")({
		Name = "Header",
		Position = UDim2.fromOffset(PANEL_STROKE, PANEL_STROKE),
		Size = UDim2.fromOffset(HEADER_W, HEADER_H),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,

		-- top corners follow the panel's rounding
		Corner(innerCorner),
		Gradient(Colors.Header),

		create("Frame")({
			Name = "Background",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 0,

			-- squares off the bottom corners: same gradient as the header's lower half, without rounding
			create("Frame")({
				Name = "LowerHalf",
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.fromScale(1, 0.5),
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				ZIndex = 1,

				Gradient(Colors.HeaderLower),
			}),
			-- two thin diagonal shine streaks
			create("Frame")({
				Name = "Shine",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				ZIndex = 2,

				Corner(innerCorner),
				create("UIGradient")({
					-- the gradient is rotated in the frame's normalized space: 4 degrees here is ~28 on this wide strip
					Rotation = 4,
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 1),
						NumberSequenceKeypoint.new(0.47, 1),
						NumberSequenceKeypoint.new(0.471, 0.916),
						NumberSequenceKeypoint.new(0.551, 0.916),
						NumberSequenceKeypoint.new(0.552, 1),
						NumberSequenceKeypoint.new(0.574, 1),
						NumberSequenceKeypoint.new(0.575, 0.928),
						NumberSequenceKeypoint.new(0.6, 0.928),
						NumberSequenceKeypoint.new(0.601, 1),
						NumberSequenceKeypoint.new(1, 1),
					}),
				}),
			}),
		}),

		-- stud texture, like on the cards
		Pattern(0, innerCorner, 1),

		Text({
			Name = "Title",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 24, 0.5, 0),
			Size = UDim2.fromOffset(330, 42),
			Text = "Upgrade Shop",
			Stroke = 3,
			Shadow = 3,
		}),

		-- coin balance (grows to the left for big numbers)
		Box({
			Name = "Coins",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(0, HEADER_W - 24 - 40 - 12, 0.5, 0),
			Size = function()
				-- 18 + coin 24 + gap 10 + amount + 18, at least 100 wide
				return UDim2.fromOffset(math.max(100, 70 + fitWidth(coinsText(), 25)), 42)
			end,
			Colors = Colors.Gold,
			Stroke = 3,
			Corner = 3,
			Children = {
				Row({
					Name = "Content",
					Size = UDim2.fromScale(1, 1),
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Gap = 10,
					Children = {
						Coin(24, 1),
						Text({
							Name = "Amount",
							LayoutOrder = 2,
							FitText = true,
							Height = 25,
							Text = coinsText,
							Stroke = 2,
							Shadow = 2,
						}),
					},
				}),
			},
		}),

		-- close button
		Box({
			Name = "Close",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(0, HEADER_W - 24, 0.5, 0),
			Size = UDim2.fromOffset(40, 40),
			Colors = Colors.Red,
			Stroke = 3,
			Corner = 3,
			Children = {
				Text({
					Name = "X",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(24, 26),
					XAlignment = Enum.TextXAlignment.Center,
					Text = "X",
					Stroke = 2,
					Shadow = 2,
				}),
				HitButton(onClose),
			},
		}),
	})
end

local function ShopUI(levels, coins, onBuy, onClose)
	local scale = Vide.spring(function()
		return isOpen() and 1 or 0
	end, 0.3, 0.6)

	-- fit the fixed canvas into the screen
	local camera = workspace.CurrentCamera
	local viewport = source(camera.ViewportSize)
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		viewport(camera.ViewportSize)
	end)
	local function fit()
		local size = viewport()
		return math.min(size.X * MAX_SCREEN_W / CANVAS_W, size.Y * MAX_SCREEN_H / CANVAS_H)
	end

	local cards = {}
	for index, upgradeId in ipairs(UpgradesConfig.Order) do
		cards[index] = UpgradeCard(upgradeId, index, levels[upgradeId], coins, onBuy)
	end

	local function anyAffordable()
		for _, upgradeId in ipairs(UpgradesConfig.Order) do
			if coins() >= UpgradesConfig.GetPrice(upgradeId, levels[upgradeId]()) then
				return true
			end
		end
		return false
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
			Size = UDim2.fromOffset(CANVAS_W, CANVAS_H),
			BackgroundTransparency = 1,

			create("UIScale")({
				Scale = function()
					return fit() * math.max(scale(), 0.001)
				end,
			}),

			Box({
				Name = "Panel",
				Size = UDim2.fromScale(1, 1),
				Colors = Colors.Panel,
				Stroke = PANEL_STROKE,
				BackgroundTransparency = 0.15,
				Corner = PANEL_CORNER,
				Children = {
					Header(coins, onClose),
					-- thick black edge under the header
					create("Frame")({
						Name = "Divider",
						Position = UDim2.fromOffset(PANEL_STROKE, PANEL_STROKE + HEADER_H),
						Size = UDim2.fromOffset(HEADER_W, DIVIDER_H),
						BackgroundColor3 = BLACK,
						BorderSizePixel = 0,
					}),

					-- the upgrade cards, stacked from top to bottom
					create("Frame")({
						Name = "Cards",
						Position = UDim2.fromOffset(PAD_X, CARDS_Y),
						Size = UDim2.fromOffset(CARD_W, CARDS_H),
						BackgroundTransparency = 1,

						create("UIListLayout")({
							FillDirection = Enum.FillDirection.Vertical,
							SortOrder = Enum.SortOrder.LayoutOrder,
							VerticalAlignment = Enum.VerticalAlignment.Top,
							Padding = UDim.new(0, CARD_GAP),
						}),
						cards,
					}),

					Text({
						Name = "Hint",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromOffset(CANVAS_W / 2, HINT_Y),
						Size = UDim2.fromOffset(CARD_W, HINT_H - 4),
						XAlignment = Enum.TextXAlignment.Center,
						Text = function()
							return anyAffordable() and "Tap UPGRADE to level up"
								or "Earn coins to unlock your next upgrade"
						end,
						Font = FONT_BOLD,
						Transparency = 0.25,
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
