local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Vide = require(ReplicatedStorage.Packages.Vide)
local StatsConfig = require(ReplicatedStorage.SharedSource.Datas.StatsConfig)
local WaterConfig = require(ReplicatedStorage.SharedSource.Datas.WaterConfig)

local create = Vide.create
local source = Vide.source

local HUD_Controller = Knit.CreateController({
	Name = "HUD_Controller",
})

local player = Players.LocalPlayer

-- All layout values are Scale only (no pixel offsets) so the HUD adapts to any screen.
local STAT_COUNT = #StatsConfig.Order
local ROW_HEIGHT = 1 / STAT_COUNT
local CONTAINER_ASPECT = 2.2 -- width / height of the whole stat column

local function formatNumber(value)
	if value ~= value then
		return "0"
	end
	local text
	if value == math.floor(value) then
		text = tostring(math.floor(value))
	else
		text = ("%.1f"):format(value)
	end
	-- thousands separators on the integer part
	local sign, integer, fraction = text:match("^(-?)(%d+)(%.?%d*)$")
	if not integer then
		return text
	end
	integer = integer:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return sign .. integer .. fraction
end

--- `formatter` (optional) replaces the default number text with a custom function returning a string.
local function StatRow(definition, value, layoutOrder, formatter)
	return create("Frame")({
		Name = definition.Key,
		LayoutOrder = layoutOrder,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, ROW_HEIGHT),

		create("Frame")({
			Name = "Pill",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromScale(1, 0.94),
			BackgroundTransparency = 1,

			create("ImageLabel")({
				Name = "Icon",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.fromScale(0.3, 1),
				BackgroundTransparency = 1,
				Image = definition.Icon,
				ScaleType = Enum.ScaleType.Fit,

				create("UIAspectRatioConstraint")({ AspectRatio = 1 }),
			}),

			create("TextLabel")({
				Name = "Value",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0.12, 0.5),
				Size = UDim2.fromScale(0.86, 0.85),
				BackgroundTransparency = 1,
				Text = formatter or function()
					return formatNumber(value())
				end,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.FredokaOne,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextStrokeTransparency = 0,
				TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
			}),
		}),
	})
end

local function StatsHUD(values, formatters)
	local rows = {}
	for index, definition in ipairs(StatsConfig.Order) do
		rows[index] = StatRow(definition, values[definition.Key], index, formatters[definition.Key])
	end

	return create("ScreenGui")({
		Name = "HUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,

		create("Frame")({
			Name = "Stats",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.01, 0.5),
			Size = UDim2.fromScale(0.36, 0.66),
			BackgroundTransparency = 1,

			create("UIAspectRatioConstraint")({
				AspectRatio = CONTAINER_ASPECT,
				AspectType = Enum.AspectType.FitWithinMaxSize,
			}),
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Top,
			}),

			rows,
		}),
	})
end

-- Mirrors the server-owned leaderstats values into Vide sources.
local function bindStat(leaderstats, definition, values)
	local valueObject = leaderstats:WaitForChild(definition.DisplayName, 30)
	if not valueObject then
		warn("HUD_Controller: missing leaderstat " .. definition.DisplayName)
		return
	end
	values[definition.Key](valueObject.Value)
	valueObject.Changed:Connect(function(newValue)
		values[definition.Key](newValue)
	end)
end

function HUD_Controller:KnitStart()
	local values = {}
	for _, definition in ipairs(StatsConfig.Order) do
		values[definition.Key] = source(definition.Default)
	end

	-- water currently carried (replicated attribute), shown as "current / capacity" on the can row
	local waterAttribute = WaterConfig.Attributes.Water
	local water = source(player:GetAttribute(waterAttribute) or 0)
	player:GetAttributeChangedSignal(waterAttribute):Connect(function()
		water(player:GetAttribute(waterAttribute) or 0)
	end)

	local formatters = {
		Capacity = function()
			return ("%s / %s"):format(formatNumber(water()), formatNumber(values.Capacity()))
		end,
	}

	Vide.mount(function()
		return StatsHUD(values, formatters)
	end, player:WaitForChild("PlayerGui"))

	local leaderstats = player:WaitForChild(StatsConfig.Folder)
	for _, definition in ipairs(StatsConfig.Order) do
		task.spawn(bindStat, leaderstats, definition, values)
	end
end

function HUD_Controller:KnitInit() end

return HUD_Controller
