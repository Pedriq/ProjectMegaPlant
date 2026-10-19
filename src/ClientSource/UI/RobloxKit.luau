--[[
	UI kit for the "Roblox shop" look (Figma: Task-UIKIT, "Upgrade Shop · Roblox · Ref Style"):
	vertical gradients, thick black outlines drawn inside the shapes, glossy sheens, a tiled stud pattern and
	white Nunito text with a black outline and a hard drop shadow.

	Everything is laid out in design pixels; wrap the result in a UIScale to fit it to the screen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vide = require(ReplicatedStorage.Packages.Vide)
local create = Vide.create

local RobloxKit = {}

RobloxKit.Font = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.ExtraBold)
RobloxKit.FontBold = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Bold)

RobloxKit.White = Color3.new(1, 1, 1)
RobloxKit.Black = Color3.fromRGB(10, 10, 10)

-- Roblox "Stud" texture used as a faint pattern on surfaces
RobloxKit.Pattern = "rbxassetid://139348939021356"

local WHITE = RobloxKit.White
local BLACK = RobloxKit.Black

function RobloxKit.rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

--- Vertical gradient colors, light on top.
function RobloxKit.Vertical(top, bottom)
	return ColorSequence.new(top, bottom)
end

local function append(props, children)
	if children then
		for _, child in ipairs(children) do
			props[#props + 1] = child
		end
	end
	return props
end
RobloxKit.append = append

local function read(value)
	if type(value) == "function" then
		return value()
	end
	return value
end
RobloxKit.read = read

function RobloxKit.Corner(px)
	return create("UICorner")({ CornerRadius = UDim.new(0, px) })
end
local Corner = RobloxKit.Corner

function RobloxKit.Gradient(colors)
	return create("UIGradient")({ Rotation = 90, Color = colors })
end
local Gradient = RobloxKit.Gradient

--- Black outline drawn inside the shape (like Figma's "Inside" stroke).
function RobloxKit.Outline(thickness)
	return create("UIStroke")({
		Thickness = thickness,
		Color = BLACK,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		BorderStrokePosition = Enum.BorderStrokePosition.Inner,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end
local Outline = RobloxKit.Outline

--- Glossy band over the top of a surface: white fading out downwards, behind the surface's content.
function RobloxKit.Sheen(alpha, inset, height, corner)
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
local Sheen = RobloxKit.Sheen

--- Tiled stud texture inside a surface, under all of its content (and inside its outline).
function RobloxKit.PatternLayer(inset, corner, tile, transparency)
	return create("ImageLabel")({
		Name = "Pattern",
		Position = UDim2.fromOffset(inset, inset),
		Size = UDim2.new(1, -inset * 2, 1, -inset * 2),
		BackgroundTransparency = 1,
		Image = RobloxKit.Pattern,
		ImageTransparency = transparency or 0.8,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(tile or 100, tile or 100),
		ZIndex = 0,

		Corner(corner),
	})
end
local PatternLayer = RobloxKit.PatternLayer

--- Surface with a vertical gradient (or a flat color), a thick black outline, an optional pattern and sheen.
--- props: Name, AnchorPoint, Position, Size, LayoutOrder, ZIndex, Colors (ColorSequence or function; omit for
---        a flat BackgroundColor), BackgroundColor (default white), BackgroundTransparency, Stroke (px),
---        Corner (px, default 4), Pattern (bool), PatternTile (px), PatternTransparency, Sheen (alpha),
---        SheenHeight (px), Children
function RobloxKit.Box(props)
	local corner = props.Corner or 4
	local inset = props.Stroke or 0
	local frame = {
		Name = props.Name,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		BackgroundColor3 = props.BackgroundColor or WHITE,
		BackgroundTransparency = props.BackgroundTransparency,
		BorderSizePixel = 0,

		Corner(corner),
	}
	if props.Colors then
		frame[#frame + 1] = Gradient(props.Colors)
	end
	if props.Stroke then
		frame[#frame + 1] = Outline(props.Stroke)
	end
	if props.Pattern then
		frame[#frame + 1] =
			PatternLayer(inset, math.max(corner - 1, 0), props.PatternTile, props.PatternTransparency)
	end
	if props.Sheen then
		frame[#frame + 1] = Sheen(props.Sheen, inset, props.SheenHeight or 30, math.max(corner - 2, 1))
	end
	return create("Frame")(append(frame, props.Children))
end

--- Text that scales to fill its box (TextScaled), with an optional black outline and a hard drop shadow.
--- The box height is the text size; long texts shrink to the box width.
--- props: Name, AnchorPoint, Position, Size, LayoutOrder, Text, Font, Color, Transparency, Stroke, Shadow,
---        ShadowTransparency, XAlignment
function RobloxKit.Text(props)
	local function label(isShadow)
		local children = {}
		if props.Stroke then
			children[1] = create("UIStroke")({
				Thickness = props.Stroke,
				Color = BLACK,
				LineJoinMode = Enum.LineJoinMode.Round,
				Transparency = isShadow and (props.ShadowTransparency or 0) or 0,
			})
		end
		return create("TextLabel")(append({
			Name = isShadow and "Shadow" or "Text",
			Position = isShadow and UDim2.fromOffset(0, props.Shadow) or UDim2.new(),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			FontFace = props.Font or RobloxKit.Font,
			Text = props.Text,
			TextScaled = true,
			TextColor3 = isShadow and BLACK or (props.Color or WHITE),
			TextTransparency = isShadow and (props.ShadowTransparency or 0) or (props.Transparency or 0),
			TextXAlignment = props.XAlignment or Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = isShadow and 1 or 2,
		}, children))
	end

	return create("Frame")({
		Name = props.Name or "Label",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		LayoutOrder = props.LayoutOrder,
		BackgroundTransparency = 1,

		props.Shadow and label(true) or nil,
		label(false),
	})
end

return RobloxKit
