-- Visual shell only. All plant/cycle values are supplied by PlantHUD_Controller.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vide = require(ReplicatedStorage.Packages.Vide)
local PlantIcon = require(ReplicatedStorage.ClientSource.UI.PlantIcon)
local create = Vide.create

local C = {
	Body = Color3.fromRGB(182, 205, 160), Border = Color3.fromRGB(143, 174, 120),
	Text = Color3.fromRGB(36, 63, 38), Muted = Color3.fromRGB(69, 96, 59),
	Plate = Color3.fromRGB(230, 214, 153), Badge = Color3.fromRGB(213, 228, 189),
	Track = Color3.fromRGB(147, 175, 125), Fill = Color3.fromRGB(69, 110, 54),
	Water = Color3.fromRGB(199, 221, 224), You = Color3.fromRGB(229, 214, 157),
	Weight = Color3.fromRGB(204, 221, 181),
}


local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)

-- Panel colors for a plant rarity: the body is a light tint of the rarity color with dark ink, so the text always
-- keeps its contrast; the border, chip and progress bar carry the rarity's own colors. Common keeps the sage look.
local DEFAULT_THEME = {
	Body = C.Body, Border = C.Border, Text = C.Text, Muted = C.Muted,
	Plate = C.Plate, Track = C.Track, Fill = C.Fill, Chip = C.Badge, BorderThickness = 1,
}

local function themeOf(rarity)
	if not rarity or rarity.Order == 1 then
		return DEFAULT_THEME
	end
	local color, dark = rarity.Color, rarity.DarkColor
	return {
		Body = color:Lerp(WHITE, 0.72),
		Border = color,
		Text = dark:Lerp(BLACK, 0.55),
		Muted = dark:Lerp(BLACK, 0.25),
		Plate = color:Lerp(WHITE, 0.5),
		Track = color:Lerp(WHITE, 0.4),
		Fill = dark,
		Chip = color,
		BorderThickness = 1.5 + (rarity.Order - 1) * 0.6, -- rarer = bolder frame
	}
end

local function corner(radius)
	return create("UICorner")({ CornerRadius = UDim.new(radius, 0) })
end

local function texture(radius)
	return create("ImageLabel")({
		Name = "BackgroundTexture",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = "rbxassetid://139348939021356",
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(64, 64),
		ImageTransparency = 0.8,
		ZIndex = 1,
		corner(radius),
	})
end

local function label(name, value, x, y, w, h, color, alignment)
	return create("TextLabel")({
		Name = name, BackgroundTransparency = 1, ZIndex = 2,
		Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h),
		Text = value, TextScaled = true, TextWrapped = false,
		Font = Enum.Font.GothamBold, TextColor3 = color or C.Text,
		TextStrokeTransparency = 1,
		TextXAlignment = alignment or Enum.TextXAlignment.Left,
	})
end

local function stat(name, title, value, order, body, ink)
	return create("Frame")({
		Name = name, LayoutOrder = order,
		Size = UDim2.fromScale((1 - 16 / 396) / 3, 1),
		BackgroundColor3 = body, BorderSizePixel = 0,
		corner(11 / 50),
		texture(11 / 50),
		label("Title", title, 10 / 127, 7 / 50, 107 / 127, 12 / 50, ink),
		label("Value", value, 10 / 127, 22 / 50, 107 / 127, 20 / 50),
	})
end

return function(props)
	local function theme()
		return themeOf(props.Rarity())
	end

	return create("ScreenGui")({
		Name = "PlantHUD", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 1,
		create("Frame")({
			Name = "Root", AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.006), Size = UDim2.fromScale(0.4, 0.23),
			BackgroundTransparency = 1,
			create("UIAspectRatioConstraint")({ AspectRatio = 424 / 154,
				AspectType = Enum.AspectType.FitWithinMaxSize, DominantAxis = Enum.DominantAxis.Width }),
			create("UIScale")({ Scale = props.PopScale }),
			create("Frame")({
				Name = "Panel", Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = function() return theme().Body end, BackgroundTransparency = 0.12, BorderSizePixel = 0,
				corner(20 / 154),
				create("UIStroke")({
						Color = function() return theme().Border end,
						Thickness = function() return theme().BorderThickness end,
					}),
				create("Frame")({
					Name = "IconPlate", Position = UDim2.fromScale(14 / 424, 14 / 154),
					Size = UDim2.fromScale(64 / 424, 64 / 154),
					BackgroundColor3 = function() return theme().Plate end, BorderSizePixel = 0, corner(15 / 64),
					function()
						if props.IsSelecting() then
							return label("Unknown", "?", 0.2, 0.2, 0.6, 0.6, C.Text, Enum.TextXAlignment.Center)
						end
						return PlantIcon(props.PlantId(), {
							AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
							Size = UDim2.fromScale(52 / 64, 52 / 64),
						})
					end,
				}),
				label("PlantName", props.PlantName, 90 / 424, 14 / 154, 224 / 424, 28 / 154,
						function() return theme().Text end),
				create("Frame")({
					Name = "RarityChip", Position = UDim2.fromScale(330 / 424, 16 / 154),
					Size = UDim2.fromScale(80 / 424, 24 / 154), BorderSizePixel = 0,
					Visible = function() return not props.IsSelecting() and props.Rarity() ~= nil end,
					BackgroundColor3 = function() return theme().Chip end,
					corner(0.5),
					texture(0.5),
					label("Rarity", function()
						local rarity = props.Rarity()
						return rarity and rarity.DisplayName or ""
					end, 0.08, 0.18, 0.84, 0.64, function() return theme().Text end, Enum.TextXAlignment.Center),
				}),
				label("TimerCaption", function() return props.IsGrowing() and "Time left" or "" end,
					90 / 424, 48 / 154, 75 / 424, 15 / 154, function() return theme().Muted end),
				label("Timer", props.TimerText, 172 / 424, 48 / 154, 238 / 424, 16 / 154,
					function() return theme().Text end, Enum.TextXAlignment.Right),
				create("Frame")({
					Name = "Progress", Size = UDim2.fromScale(320 / 424, 8 / 154),
					Position = function()
						local offset = props.Shake.Offset()
						return UDim2.fromScale(90 / 424 + offset.X, 70 / 154 + offset.Y)
					end,
					Rotation = props.Shake.Rotation, BackgroundColor3 = function() return theme().Track end,
					BorderSizePixel = 0, ClipsDescendants = true, corner(0.5),
					create("Frame")({
						Name = "Fill", BorderSizePixel = 0,
						Size = function() return UDim2.fromScale(math.clamp(props.Progress(), 0, 1), 1) end,
						BackgroundColor3 = function()
							return props.IsFinished() and Color3.fromRGB(188, 148, 53) or theme().Fill
						end,
						corner(0.5),
						create("Frame")({
							Name = "Shimmer", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0,
							BackgroundColor3 = C.Badge, corner(0.5),
							create("UIGradient")({
								Transparency = NumberSequence.new({
									NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 1),
									NumberSequenceKeypoint.new(0.5, 0.65), NumberSequenceKeypoint.new(0.6, 1),
									NumberSequenceKeypoint.new(1, 1),
								}),
								Offset = function() return Vector2.new(props.Shimmer(), 0) end,
							}),
						}),
					}),
				}),
				create("Frame")({
					Name = "Stats", BackgroundTransparency = 1,
					Position = UDim2.fromScale(14 / 424, 90 / 154), Size = UDim2.fromScale(396 / 424, 50 / 154),
					create("UIListLayout")({ FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(8 / 396, 0) }),
					stat("TotalWater", "Water", props.TotalWater, 1, C.Water, Color3.fromRGB(54, 95, 107)),
					stat("YourContribution", "You", props.MyWater, 2, C.You, Color3.fromRGB(117, 90, 37)),
					stat("PlantWeight", "Weight", props.Weight, 3, C.Weight, Color3.fromRGB(77, 100, 59)),
				}),
			}),
		}),
	})
end
