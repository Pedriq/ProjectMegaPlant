local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Vide = require(ReplicatedStorage.Packages.Vide)
local StatsConfig = require(ReplicatedStorage.SharedSource.Datas.StatsConfig)
local WaterConfig = require(ReplicatedStorage.SharedSource.Datas.WaterConfig)
local WaitFor = require(ReplicatedStorage.ClientSource.Utilities.WaitFor)

local create = Vide.create
local source = Vide.source

local HUD_Controller = Knit.CreateController({
	Name = "HUD_Controller",
})

local player = Players.LocalPlayer

-- All layout values are Scale only (no pixel offsets) so the HUD adapts to any screen.
-- Rows can have different heights (StatsConfig HudHeight, default 1); everything is relative to the total.
local TOTAL_HEIGHT = 0
for _, definition in ipairs(StatsConfig.Order) do
	TOTAL_HEIGHT += definition.HudHeight or 1
end
local COLUMN_UNIT_ASPECT = 2.2 / 4 -- width / height of one row unit
local CONTAINER_ASPECT = COLUMN_UNIT_ASPECT * TOTAL_HEIGHT -- width / height of the whole stat column
local CONTAINER_HEIGHT = 0.66 * TOTAL_HEIGHT / 4

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

local TEXT_STROKE = Color3.fromRGB(0, 0, 0)

local function StatText(props)
	return create("TextLabel")({
		Name = props.Name,
		AnchorPoint = Vector2.new(0, 0),
		Position = props.Position,
		Size = props.Size,
		BackgroundTransparency = 1,
		Text = props.Text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.FredokaOne,
		TextColor3 = props.Color or Color3.fromRGB(255, 255, 255),
		TextStrokeTransparency = 0,
		TextStrokeColor3 = TEXT_STROKE,
	})
end

--- One HUD row: icon + number. If `secondary` is given, a smaller second line is shown under the number.
--- The number counts up smoothly when the stat changes.
local function StatRow(definition, value, layoutOrder, secondary)
	local displayed = Vide.spring(function()
		return value()
	end, 0.25, 1)

	-- the whole row bumps whenever its stat goes up
	local bump = source(1)
	local bumpScale = Vide.spring(function()
		return bump()
	end, 0.22, 0.45)
	local lastValue = definition.Default
	Vide.effect(function()
		local current = value()
		if current > lastValue then
			task.defer(function()
				bump(1.16)
				task.delay(0.1, function()
					bump(1)
				end)
			end)
		end
		lastValue = current
	end)

	local rowHeight = (definition.HudHeight or 1) / TOTAL_HEIGHT
	local hasSecondary = secondary ~= nil

	return create("Frame")({
		Name = definition.Key,
		LayoutOrder = layoutOrder,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, rowHeight),

		create("Frame")({
			Name = "Pill",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromScale(1, 0.94),
			BackgroundTransparency = 1,

			create("UIScale")({
				Scale = function()
					return bumpScale()
				end,
			}),

			create("ImageLabel")({
				Name = "Icon",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.fromScale(0.3, hasSecondary and 0.64 or 1),
				BackgroundTransparency = 1,
				Image = definition.Icon,
				ScaleType = Enum.ScaleType.Fit,

				create("UIAspectRatioConstraint")({ AspectRatio = 1 }),
			}),

			StatText({
				Name = "Value",
				Position = hasSecondary and UDim2.fromScale(0.12, 0.04) or UDim2.fromScale(0.12, 0.075),
				Size = hasSecondary and UDim2.fromScale(0.86, 0.56) or UDim2.fromScale(0.86, 0.85),
				Text = function()
					return formatNumber(math.floor(displayed() + 0.5))
				end,
			}),

			hasSecondary and StatText({
				Name = "Secondary",
				Position = UDim2.fromScale(0.12, 0.64),
				Size = UDim2.fromScale(0.62, 0.28),
				Color = Color3.fromRGB(190, 232, 255),
				Text = secondary,
			}) or nil,
		}),
	})
end

local function StatsHUD(values, secondaries)
	local rows = {}
	for index, definition in ipairs(StatsConfig.Order) do
		rows[index] = StatRow(definition, values[definition.Key], index, secondaries[definition.Key])
	end

	return create("ScreenGui")({
		Name = "HUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,

		create("Frame")({
			Name = "Stats",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.01, 0.5),
			Size = UDim2.fromScale(0.36, CONTAINER_HEIGHT),
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
	local valueObject = WaitFor.Child(leaderstats, definition.DisplayName, 60)
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

	-- water currently carried (replicated attribute), shown as "current / capacity" under Strength
	local waterAttribute = WaterConfig.Attributes.Water
	local water = source(player:GetAttribute(waterAttribute) or 0)
	player:GetAttributeChangedSignal(waterAttribute):Connect(function()
		water(player:GetAttribute(waterAttribute) or 0)
	end)

	-- capacity is derived from Strength, so it updates together with the stat
	local secondaries = {
		Strength = function()
			local capacity = StatsConfig.GetCapacity(values.Strength())
			return ("%s / %s"):format(formatNumber(water()), formatNumber(capacity))
		end,
	}

	Vide.mount(function()
		return StatsHUD(values, secondaries)
	end, player:WaitForChild("PlayerGui"))

	-- leaderstats are created by the server once the profile has loaded (can take a few seconds)
	local leaderstats = WaitFor.Child(player, StatsConfig.Folder)
	if not leaderstats then
		return
	end
	for _, definition in ipairs(StatsConfig.Order) do
		task.spawn(bindStat, leaderstats, definition, values)
	end
end

function HUD_Controller:KnitInit() end

return HUD_Controller
