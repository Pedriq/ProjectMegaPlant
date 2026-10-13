--[[
	Shared UI kit: a clean, minimal look inspired by Grow a Garden. Light, saturated flat surfaces with a thin outline in a
	deeper shade of the accent color, and a very faint Stud-material texture for depth.
	Everything is Scale-based; outlines are built from nested frames instead of pixel strokes.
	(The module is still called Plastic so existing requires keep working.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vide = require(ReplicatedStorage.Packages.Vide)
local create = Vide.create

local Plastic = {}

Plastic.Font = Enum.Font.GothamBold

-- Roblox "Stud" material texture, used as a faint overlay on surfaces
Plastic.StudTexture = "rbxassetid://139348939021356"
-- texture density only (not layout): size of one tile in pixels
local STUD_TILE = UDim2.fromOffset(64, 64)

Plastic.Colors = {
	PanelBody = Color3.fromRGB(146, 194, 138),
	PanelBorder = Color3.fromRGB(88, 134, 90),
	TrackBorder = Color3.fromRGB(84, 120, 88),
	TrackBody = Color3.fromRGB(116, 150, 116),
	FillGreen = Color3.fromRGB(178, 222, 126),
	FillGold = Color3.fromRGB(238, 204, 108),
	Text = Color3.fromRGB(255, 255, 255),
	TextStroke = Color3.fromRGB(38, 68, 48),
	Gold = Color3.fromRGB(242, 208, 118),
}

-- accents are pulled towards this soft neutral to get natural pastel tones (less saturated, a bit calmer)
local PASTEL_BASE = Color3.fromRGB(196, 204, 192)
local NEUTRAL_BORDER = Plastic.Colors.PanelBorder
local BLACK = Color3.new(0, 0, 0)

--- Applies `transform` to a color that may be nil, a Color3 or a reactive function.
local function map(value, transform)
	if type(value) == "function" then
		return function()
			return transform(value())
		end
	end
	return transform(value)
end

--- Appends `child` (an instance or a list of them) to the props table used by `create`.
local function append(props, children)
	if children then
		for _, child in ipairs(children) do
			props[#props + 1] = child
		end
	end
	return props
end

--- The faint stud texture, clipped to the rounded shape it sits in.
local function studs(corner, transparency)
	return create("ImageLabel")({
		Name = "Studs",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = Plastic.StudTexture,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = STUD_TILE,
		ImageTransparency = transparency,

		create("UICorner")({ CornerRadius = UDim.new(corner, 0) }),
	})
end

--- Flat two-layer panel: thin outline + bright body, with a faint stud texture.
--- props: Name, AnchorPoint, Position, Size, BodyColor (the accent), BorderColor (only used if there is no
---        BodyColor), Style ("Surface" default: lightly brightened accent;
---        "Accent": the exact accent color, for buttons and chips), Corner (0-0.5, default 0.28),
---        Studs (default true), ZIndex, LayoutOrder, Children (list)
--- Children are parented to the body; RootChildren (list) to the outer outline frame (e.g. a UIScale).
function Plastic.Panel(props)
	local corner = (props.Corner or 0.28) * 0.65
	local solid = props.Style == "Accent"
	local accent = props.BodyColor ~= nil and props.BodyColor or props.BorderColor

	local bodyColor = map(accent, function(color)
		if not color then
			return Plastic.Colors.PanelBody
		end
		return color:Lerp(PASTEL_BASE, solid and 0.22 or 0.32)
	end)
	local borderColor = map(accent, function(color)
		if not color then
			return NEUTRAL_BORDER
		end
		-- thin outline: a deeper shade of the same hue
		return color:Lerp(PASTEL_BASE, solid and 0.22 or 0.32):Lerp(BLACK, 0.34)
	end)

	local body = {
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.986, 0.95),
		BackgroundColor3 = bodyColor,
		BorderSizePixel = 0,

		create("UICorner")({ CornerRadius = UDim.new(corner, 0) }),
	}

	if props.Studs ~= false then
		body[#body + 1] = studs(corner, solid and 0.76 or 0.8)
	end

	append(body, props.Children)

	local root = {
		Name = props.Name or "Panel",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		ZIndex = props.ZIndex,
		LayoutOrder = props.LayoutOrder,
		BackgroundColor3 = borderColor,
		BorderSizePixel = 0,

		create("UICorner")({ CornerRadius = UDim.new(corner, 0) }),
		create("Frame")(body),
	}
	return create("Frame")(append(root, props.RootChildren))
end

--- Clean white text with a soft outline, fitted to its box (TextScaled).
--- props: Name, Text (string or function), AnchorPoint, Position, Size, XAlignment, Color, ZIndex
function Plastic.Label(props)
	return create("TextLabel")({
		Name = props.Name or "Label",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		ZIndex = props.ZIndex,
		BackgroundTransparency = 1,
		Text = props.Text,
		TextScaled = true,
		Font = Plastic.Font,
		TextColor3 = props.Color or Plastic.Colors.Text,
		TextStrokeColor3 = Plastic.Colors.TextStroke,
		TextStrokeTransparency = 0.2,
		TextXAlignment = props.XAlignment or Enum.TextXAlignment.Center,
		TextTransparency = props.TextTransparency,
	})
end

--- Flat progress bar with a faint stud texture on the fill and an optional shimmer.
--- props: Name, AnchorPoint, Position, Size, Progress (function -> 0..1), FillColor (function or Color3),
---        Shimmer (function -> number used as gradient offset -1..1), Children (overlay, e.g. a timer label)
function Plastic.Bar(props)
	local fill = {
		Name = "Fill",
		Size = function()
			return UDim2.fromScale(math.clamp(props.Progress(), 0, 1), 1)
		end,
		BackgroundColor3 = props.FillColor or Plastic.Colors.FillGreen,
		BorderSizePixel = 0,

		create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
		studs(0.5, 0.74),
	}

	if props.Shimmer then
		fill[#fill + 1] = create("Frame")({
			Name = "Shimmer",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BorderSizePixel = 0,

			create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
			create("UIGradient")({
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.4, 1),
					NumberSequenceKeypoint.new(0.5, 0.65),
					NumberSequenceKeypoint.new(0.6, 1),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Offset = function()
					return Vector2.new(props.Shimmer(), 0)
				end,
			}),
		})
	end

	local inner = {
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.99, 0.86),
		BackgroundColor3 = Plastic.Colors.TrackBody,
		BorderSizePixel = 0,
		ClipsDescendants = true,

		create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
		create("Frame")(fill),
	}
	append(inner, props.Children)

	return create("Frame")({
		Name = props.Name or "Bar",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		Rotation = props.Rotation,
		BackgroundColor3 = Plastic.Colors.TrackBorder,
		BorderSizePixel = 0,

		create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
		create("Frame")(inner),
	})
end

return Plastic
