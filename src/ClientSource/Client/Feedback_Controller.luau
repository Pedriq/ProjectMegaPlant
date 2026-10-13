local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local StatsConfig = require(ReplicatedStorage.SharedSource.Datas.StatsConfig)
local TrainingConfig = require(ReplicatedStorage.SharedSource.Datas.TrainingConfig)
local WaterConfig = require(ReplicatedStorage.SharedSource.Datas.WaterConfig)
local PlantsConfig = require(ReplicatedStorage.SharedSource.Datas.PlantsConfig)
local JuiceConfig = require(ReplicatedStorage.SharedSource.Datas.JuiceConfig)
local RewardConfig = require(ReplicatedStorage.SharedSource.Datas.RewardConfig)
local Effects = require(ReplicatedStorage.ClientSource.UI.Effects)
local WaitFor = require(ReplicatedStorage.ClientSource.Utilities.WaitFor)
local WaterState = require(ReplicatedStorage.ClientSource.Utilities.WaterState)

--[[
	"Juice": turns what the server decides into sound, popups, banners and bursts on the client.
	Nothing here changes game state; it only reacts to
	  - Reward_Service messages (pour beats, growth stages, fully grown, harvest payout)
	  - the replicated stats / water attributes of the local player
]]
local Feedback_Controller = Knit.CreateController({
	Name = "Feedback_Controller",
})

local player = Players.LocalPlayer

local GOLD = Color3.fromRGB(255, 214, 72)
local LUCKY = Color3.fromRGB(255, 120, 200)
local CYAN = Color3.fromRGB(120, 235, 255)
local STRENGTH_COLOR = Color3.fromRGB(255, 140, 90)
local MOBILITY_COLOR = Color3.fromRGB(130, 240, 140)

local Audio_Controller, Banner_Controller, WateringCanVisual_Controller, WaterTotals_Controller

---- Positions

local function getHeadPosition()
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	return head and head.Position
end

--- Where popups for the local player appear: above the carried can (or above the head).
local function getPopupPosition(extraHeight)
	local top = WateringCanVisual_Controller:GetTopPosition(player)
	local head = getHeadPosition()
	local base = top or (head and head + Vector3.new(0, 3, 0))
	return base and base + Vector3.new(0, extraHeight or 1.5, 0)
end

local function getPlantPosition()
	return WaterState.GetPlantTarget()
end

local function formatNumber(value)
	local text = tostring(math.floor(value + 0.5))
	return (text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

---- Server messages

local function onPourBeat(coins, lucky, combo, multiplier)
	local position = getPopupPosition(1.5)
	if position then
		if lucky then
			Effects.FloatText(position, ("LUCKY! +%s"):format(formatNumber(coins)), {
				Color = LUCKY,
				Height = 3.4,
				Rise = 6,
				Duration = 1.5,
				Pop = 0.35,
			})
			Effects.Burst(position, { Color = LUCKY, Count = 36, Speed = 20 })
			Effects.Shockwave(position, { Color = LUCKY, Size = 9, Duration = 0.5 })
		else
			Effects.FloatText(position, "+" .. formatNumber(coins), {
				Color = GOLD,
				Height = 2.1 + math.min(combo, 25) * 0.025,
				Rise = 4.5,
			})
		end

		-- every 5th beat in a row: a combo callout
		if combo > 0 and combo % 5 == 0 then
			Effects.FloatText(position + Vector3.new(0, 2.6, 0), ("COMBO x%.2f"):format(multiplier), {
				Color = CYAN,
				Height = 1.7,
				Rise = 3,
				Duration = 1,
			})
		end
	end

	-- the coin sound climbs with the combo, like a musical scale
	Audio_Controller:Play(lucky and "CoinLucky" or "CoinBeat", {
		Pitch = 1 + math.min(combo, RewardConfig.Pour.ComboMax) * 0.035,
	})
end

local function onStageReached(stageIndex, stageName, bonusCoins, plantId)
	local contributed = WaterTotals_Controller.Mine() > 0
	local isFinal = stageIndex >= #RewardConfig.Stages

	Banner_Controller:Show({
		Title = stageName,
		Subtitle = contributed and ("+%d bonus coins for everyone who helped!"):format(bonusCoins)
			or "Water the plant to share the bonus!",
		Color = isFinal and Color3.fromRGB(255, 190, 60) or Color3.fromRGB(110, 210, 90),
		BorderColor = isFinal and Color3.fromRGB(160, 90, 10) or Color3.fromRGB(40, 110, 50),
		Duration = 2.2,
	})
	Audio_Controller:Play("StageUp", { Pitch = 1 + (stageIndex - 1) * 0.1 })

	local position = getPlantPosition()
	if position then
		Effects.Burst(position, { Color = GOLD, Count = 30 + stageIndex * 14, Speed = 24 })
		Effects.Shockwave(position, { Color = GOLD, Size = 10 + stageIndex * 4 })
	end

	if contributed then
		local popup = getPopupPosition(2)
		if popup then
			Effects.FloatText(popup, "+" .. bonusCoins .. " BONUS", { Color = GOLD, Height = 2.6, Rise = 5 })
		end
	end
end

local function onPlantFullyGrown(plantId)
	local name = PlantsConfig.GetDisplayName(plantId)
	Banner_Controller:Show({
		Title = "Fully Grown!",
		Subtitle = name .. " is ready!",
		Color = Color3.fromRGB(255, 190, 60),
		BorderColor = Color3.fromRGB(160, 90, 10),
		Duration = 2.2,
	})
	Audio_Controller:Play("FullyGrown")

	local position = getPlantPosition()
	if position then
		local rarity = PlantsConfig.GetRarity(plantId)
		local color = rarity and rarity.Color or GOLD
		Effects.Burst(position, { Color = color, Count = 120, Speed = 34, Lifetime = 1.6, Size = 1.8 })
		Effects.Shockwave(position, { Color = color, Size = 34, Duration = 0.9 })
		task.delay(0.25, function()
			Effects.Burst(position + Vector3.new(0, 4, 0), { Color = GOLD, Count = 80, Speed = 28, Lifetime = 1.4 })
			Effects.Shockwave(position, { Color = GOLD, Size = 24, Duration = 0.8 })
		end)
	end
end

local function onPlantHarvested(result)
	Banner_Controller:Show({
		Title = result.FirstHarvest and ("FIRST HARVEST! +%s"):format(formatNumber(result.Coins))
			or ("+%s coins!"):format(formatNumber(result.Coins)),
		Subtitle = ("%.1f kg  -  %d%% impact  -  %d grown"):format(
			result.Weight or 0,
			math.floor((result.Share or 0) * 100 + 0.5),
			result.PlantsGrown or 0
		),
		Color = Color3.fromRGB(255, 205, 80),
		BorderColor = Color3.fromRGB(170, 100, 20),
		Duration = 3,
	})
	Audio_Controller:Play("Harvest")

	local position = getPopupPosition(2)
	if position then
		Effects.FloatText(position, "+" .. formatNumber(result.Coins), {
			Color = GOLD,
			Height = 4,
			Rise = 8,
			Duration = 1.8,
			Pop = 0.4,
		})
		Effects.Burst(position, { Color = GOLD, Count = 70, Speed = 26 })
	end
end

---- Water attributes (local player)

local lastWater = 0

local function onWaterChanged()
	local water = WaterState.GetWater(player)
	local capacity = math.max(WaterState.GetCapacity(player), 1)

	if water > lastWater and WaterState.IsFilling(player) then
		-- ticks climb in pitch as the can fills up
		Audio_Controller:Play("FillTick", { Pitch = 0.8 + 1.2 * math.clamp(water / capacity, 0, 1) })
		if water >= capacity and lastWater < capacity then
			Audio_Controller:Play("FillFull")
			local position = getPopupPosition(2)
			if position then
				Effects.FloatText(position, "FULL!", { Color = CYAN, Height = 3, Rise = 5, Pop = 0.35 })
				Effects.Burst(position, { Color = CYAN, Count = 40 })
				Effects.Shockwave(position, { Color = CYAN, Size = 8, Duration = 0.5 })
			end
		end
	end
	lastWater = water
end

---- Stat progression

local trainingGain = {} -- [statKey] = points gained since the last popup
local trainingCombo = 0
local lastTrainingTick = 0

local TRAINING_POPUP_STATS = { "Strength", "Mobility" }

--- One popup with every stat that grew, each on its own line (so stats never overlap).
local function flushTrainingGains()
	local lines = {}
	for _, statKey in ipairs(TRAINING_POPUP_STATS) do
		local gained = trainingGain[statKey]
		trainingGain[statKey] = nil
		if gained and gained > 0 then
			local color = statKey == "Strength" and STRENGTH_COLOR or MOBILITY_COLOR
			table.insert(lines, ('<font color="#%s">+%d %s</font>'):format(color:ToHex(), gained, StatsConfig.ByKey[statKey].DisplayName))
		end
	end

	local position = getHeadPosition()
	if position and #lines > 0 then
		Effects.FloatText(position + Vector3.new(0, 2.5 + #lines * 0.8, 0), table.concat(lines, "\n"), {
			RichText = true,
			Height = 1.9 * #lines,
			Rise = 4,
			Duration = 1,
		})
	end
end

local function onStatChanged(statKey, newValue, oldValue)
	if newValue <= oldValue then
		return
	end

	-- training gains: batched popups + a rising tick
	if
		(statKey == "Strength" or statKey == "Mobility")
		and (player:GetAttribute(TrainingConfig.Attribute) or player:GetAttribute(JuiceConfig.BoostAttribute))
	then
		trainingGain[statKey] = (trainingGain[statKey] or 0) + (newValue - oldValue)
		local now = os.clock()
		trainingCombo = (now - lastTrainingTick < 1.2) and trainingCombo + 1 or 0
		lastTrainingTick = now
		Audio_Controller:Play("TrainTick", { Pitch = 1 + math.min(trainingCombo, 20) * 0.04 })
	end

	-- a Strength threshold was crossed: bigger watering can
	if statKey == "Strength" then
		local oldCapacity = StatsConfig.GetCapacity(oldValue)
		local newCapacity = StatsConfig.GetCapacity(newValue)
		if newCapacity > oldCapacity then
			Banner_Controller:Show({
				Title = "Bigger Can!",
				Subtitle = ("Capacity %d -> %d"):format(oldCapacity, newCapacity),
				Color = Color3.fromRGB(110, 190, 255),
				BorderColor = Color3.fromRGB(30, 80, 170),
				Duration = 2.6,
			})
			Audio_Controller:Play("CapacityUp")
			local position = getHeadPosition()
			if position then
				Effects.Burst(position, { Color = CYAN, Count = 60, Speed = 24 })
				Effects.Shockwave(position, { Color = CYAN, Size = 12 })
			end
		end
	end

	-- a training zone just unlocked
	if statKey == "PlantsGrown" then
		for _, zoneId in ipairs(TrainingConfig.GetZoneOrder()) do
			local unlock = TrainingConfig.GetUnlock(zoneId)
			if unlock and unlock.Stat == "PlantsGrown" and oldValue < unlock.Amount and newValue >= unlock.Amount then
				Banner_Controller:Show({
					Title = TrainingConfig.Zones[zoneId].DisplayName .. " Unlocked!",
					Subtitle = "Train faster in the new zone",
					Color = Color3.fromRGB(190, 120, 255),
					BorderColor = Color3.fromRGB(90, 40, 160),
					Duration = 2.8,
				})
				Audio_Controller:Play("ZoneUnlocked")
			end
		end
	end
end

local function watchStats()
	local leaderstats = WaitFor.Child(player, StatsConfig.Folder)
	if not leaderstats then
		return
	end
	for _, definition in ipairs(StatsConfig.Order) do
		local valueObject = WaitFor.Child(leaderstats, definition.DisplayName, 60)
		if valueObject then
			local last = valueObject.Value
			valueObject.Changed:Connect(function(newValue)
				local old = last
				last = newValue
				onStatChanged(definition.Key, newValue, old)
			end)
		end
	end
end

---- Lifecycle

function Feedback_Controller:KnitStart()
	Audio_Controller = Knit.GetController("Audio_Controller")
	Banner_Controller = Knit.GetController("Banner_Controller")
	WateringCanVisual_Controller = Knit.GetController("WateringCanVisual_Controller")
	WaterTotals_Controller = Knit.GetController("WaterTotals_Controller")

	local reward = Knit.GetService("Reward_Service")
	reward.PourBeat:Connect(onPourBeat)
	reward.StageReached:Connect(onStageReached)
	reward.PlantFullyGrown:Connect(onPlantFullyGrown)
	reward.PlantHarvested:Connect(onPlantHarvested)

	local attributes = WaterConfig.Attributes
	lastWater = WaterState.GetWater(player)
	player:GetAttributeChangedSignal(attributes.Water):Connect(onWaterChanged)
	player:GetAttributeChangedSignal(attributes.Watering):Connect(function()
		Audio_Controller:SetLoop("PourLoop", WaterState.IsWatering(player))
	end)
	player:GetAttributeChangedSignal(attributes.Filling):Connect(function()
		Audio_Controller:SetLoop("FillLoop", WaterState.IsFilling(player))
	end)

	-- batch training popups so they don't flood the screen
	task.spawn(function()
		while true do
			task.wait(1)
			flushTrainingGains()
		end
	end)

	task.spawn(watchStats)
end

function Feedback_Controller:KnitInit() end

return Feedback_Controller
