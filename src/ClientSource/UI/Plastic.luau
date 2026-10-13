--[[
	Shared "glossy plastic" look (Grow a Garden-inspired) used by the plant HUD and the selection animation.
	Everything is Scale-based; outlines are built from nested frames instead of pixel strokes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vide = require(ReplicatedStorage.Packages.Vide)
local create = Vide.create

local Plastic = {}

Plastic.Font = Enum.Font.FredokaOne

Plastic.Colors = {
	PanelBorder = Color3.fromRGB(38, 94, 52),
	PanelBody = Color3.fromRGB(104, 204, 86),
	TrackBorder = Color3.fromRGB(28, 58, 40),
	TrackBody = Color3.fromRGB(46, 84, 58),
	FillGreen = Color3.fromRGB(176, 255, 84),
	FillGold = Color3.fromRGB(255, 214, 72),
	Text = Color3.fromRGB(255, 255, 255),
	TextStroke = Color3.fromRGB(24, 52, 34),
	Gold = Color3.fromRGB(255, 206, 64),
}

--- Appends `child` (an instance or a list of them) to the props table used by `create`.
local function append(props, children)
	if children then
		for _, child in ipairs(children) do
			props[#props + 1] = child
		end
	end
	return props
end

--- Glossy two-layer panel: dark rim (thicker at the bottom for a 3D lip), colored body, white highlight.
--- props: Name, AnchorPoint, Position, Size, BodyColor, BorderColor, Corner (0-0.5, default 0.28),
---        Gloss (default true), ZIndex, LayoutOrder, Children (list)
--- Children are parented to the body; RootChildren (list) to the outer rim frame (e.g. a UIScale).
function Plastic.Panel(props)
	local corner = props.Corner or 0.28

	local body = {
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.97, 0.84),
		BackgroundColor3 = props.BodyColor or Plastic.Colors.PanelBody,
		BorderSizePixel = 0,

		create("UICorner")({ CornerRadius = UDim.new(corner, 0) }),
		create("UIGradient")({
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(196, 196, 196)),
			Rotation = 90,
		}),
	}

	if props.Gloss ~= false then
		body[#body + 1] = create("Frame")({
			Name = "Gloss",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.05),
			Size = UDim2.fromScale(0.94, 0.36),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 0.78,
			BorderSizePixel = 0,

			create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
		})
	end

	append(body, props.Children)

	local root = {
		Name = props.Name or "Panel",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		ZIndex = props.ZIndex,
		LayoutOrder = props.LayoutOrder,
		BackgroundColor3 = props.BorderColor or Plastic.Colors.PanelBorder,
		BorderSizePixel = 0,

		create("UICorner")({ CornerRadius = UDim.new(corner, 0) }),
		create("Frame")(body),
	}
	return create("Frame")(append(root, props.RootChildren))
end

--- White text with a dark outline, fitted to its box (TextScaled).
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
		TextStrokeTransparency = 0,
		TextXAlignment = props.XAlignment or Enum.TextXAlignment.Center,
		TextTransparency = props.TextTransparency,
	})
end

--- Progress bar with glossy fill and an animated shimmer.
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
		create("UIGradient")({
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 190, 190)),
			Rotation = 90,
		}),
		create("Frame")({
			Name = "Gloss",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.1),
			Size = UDim2.fromScale(0.94, 0.38),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,

			create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
		}),
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
					NumberSequenceKeypoint.new(0.5, 0.55),
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
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromScale(0.97, 0.78),
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
