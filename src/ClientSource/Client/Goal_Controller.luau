local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Vide = require(ReplicatedStorage.Packages.Vide)
local StatsConfig = require(ReplicatedStorage.SharedSource.Datas.StatsConfig)
local TrainingConfig = require(ReplicatedStorage.SharedSource.Datas.TrainingConfig)
local Plastic = require(ReplicatedStorage.ClientSource.UI.Plastic)
local WaitFor = require(ReplicatedStorage.ClientSource.Utilities.WaitFor)

local create = Vide.create
local source = Vide.source

--[[
	"Next goal" tracker (right side of the screen). Always shows the progression goal the player is
	closest to finishing, with a progress bar:
	  - the next Strength threshold that gives a bigger watering can
	  - the plants-grown count that unlocks the next training zone
	A visible "almost there" target is what keeps people playing one more round.
]]
local Goal_Controller = Knit.CreateController({
	Name = "Goal_Controller",
})

local player = Players.LocalPlayer

--- Returns { Text, Progress (0-1) } for the goal closest to completion, or nil if everything is done.
local function computeGoal(strength, plantsGrown)
	local best

	local function consider(text, progress)
		if not best or progress > best.Progress then
			best = { Text = text, Progress = math.clamp(progress, 0, 1) }
		end
	end

	-- next capacity threshold
	local previous = 0
	for _, threshold in ipairs(StatsConfig.Capacity.Thresholds) do
		if strength < threshold.Strength then
			consider(
				("Strength %d / %d  -  bigger can!"):format(strength, threshold.Strength),
				(strength - previous) / (threshold.Strength - previous)
			)
			break
		end
		previous = threshold.Strength
	end

	-- first still-locked training zone
	for _, zoneId in ipairs(TrainingConfig.GetZoneOrder()) do
		local unlock = TrainingConfig.GetUnlock(zoneId)
		if unlock and unlock.Stat == "PlantsGrown" and plantsGrown < unlock.Amount then
			consider(
				("%s: %d / %d plants grown"):format(TrainingConfig.Zones[zoneId].DisplayName, plantsGrown, unlock.Amount),
				plantsGrown / unlock.Amount
			)
			break
		end
	end

	return best
end

local function GoalUI(strength, plantsGrown)
	local goal = function()
		return computeGoal(strength(), plantsGrown())
	end
	local progress = Vide.spring(function()
		local current = goal()
		return current and current.Progress or 1
	end, 0.4, 1)
	local shimmer = source(-1)
	task.spawn(function()
		while true do
			shimmer((os.clock() * 0.5 % 2) - 1)
			task.wait()
		end
	end)

	return create("ScreenGui")({
		Name = "GoalHUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1,

		create("Frame")({
			Name = "Root",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.992, 0.5),
			Size = UDim2.fromScale(0.24, 0.17),
			BackgroundTransparency = 1,

			create("UIAspectRatioConstraint")({
				AspectRatio = 2.5,
				AspectType = Enum.AspectType.FitWithinMaxSize,
				DominantAxis = Enum.DominantAxis.Width,
			}),

			Plastic.Panel({
				Name = "Panel",
				Size = UDim2.fromScale(1, 1),
				BodyColor = Color3.fromRGB(255, 176, 76),
				BorderColor = Color3.fromRGB(150, 80, 20),
				Corner = 0.22,
				Children = {
					Plastic.Label({
						Name = "Title",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.07),
						Size = UDim2.fromScale(0.8, 0.22),
						Text = "NEXT GOAL",
					}),
					Plastic.Label({
						Name = "Goal",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.31),
						Size = UDim2.fromScale(0.92, 0.26),
						Text = function()
							local current = goal()
							return current and current.Text or "All goals complete!"
						end,
					}),
					Plastic.Bar({
						Name = "Bar",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.64),
						Size = UDim2.fromScale(0.9, 0.26),
						Progress = progress,
						Shimmer = shimmer,
						FillColor = Plastic.Colors.FillGold,
					}),
				},
			}),
		}),
	})
end

local function bindStat(statKey, sourceValue)
	local definition = StatsConfig.ByKey[statKey]
	local leaderstats = WaitFor.Child(player, StatsConfig.Folder)
	local valueObject = leaderstats and WaitFor.Child(leaderstats, definition.DisplayName, 60)
	if not valueObject then
		return
	end
	sourceValue(valueObject.Value)
	valueObject.Changed:Connect(function(newValue)
		sourceValue(newValue)
	end)
end

function Goal_Controller:KnitStart()
	local strength = source(StatsConfig.ByKey.Strength.Default)
	local plantsGrown = source(StatsConfig.ByKey.PlantsGrown.Default)

	Vide.mount(function()
		return GoalUI(strength, plantsGrown)
	end, player:WaitForChild("PlayerGui"))

	task.spawn(bindStat, "Strength", strength)
	task.spawn(bindStat, "PlantsGrown", plantsGrown)
end

function Goal_Controller:KnitInit() end

return Goal_Controller
