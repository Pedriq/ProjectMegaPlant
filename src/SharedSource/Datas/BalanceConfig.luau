--[[
	THE balance knobs of the whole game, in one place. Other configs read these numbers; change them
	here while testing. The design is "Build the Pyramid" style: ~100 players water ONE plant together.

	=== The economy in one page ===

	One average player (base can, no upgrades) cycles: fill the can -> walk -> pour. With the defaults:
	    fill  10 / 6   = 1.7 s
	    pour  10 / 3.5 = 2.9 s
	    walk           = 2.5 s          -> ~1.4 water per second, ~2 coins per second with combos.

	Three phases of progression (see the upgrade curves below):
	  HOOK     levels 1-12     cheap (x1.15 per level), every level is a clearly visible +15-25% speed.
	                           The first "Bigger Can!" (Strength 120) and the FIRST HARVEST bonus land in the first minutes.
	  PLATEAU  levels 13-35    price grows x1.26 per level, the speed curve flattens (diminishing returns).
	  MASTERY  levels 35+      prices keep exploding, the speed gain is only a thin linear tail. Real long-term
	                           power comes from bigger cans (Strength), juice pools and rare, large plants.

	Cooperation:
	  * The water goal of a plant is sized for ReferencePlayers (100) average players, so the grow timer
	    only reaches its minimum with a full server. 10 players barely shorten it.
	  * One player counts for at most PlayerCapFraction (5%) of the goal towards the timer boost and the
	    stage bonuses, so a single maxed player can never skip the plant.
	  * Harvest rewards follow each player's impact, but with a sub-linear exponent, so the top
	    contributors earn clearly more without taking everything.

	Everything is a plain number so it stays stable at very high levels (prices are clamped, the speed
	curve grows at most linearly).
]]

local BalanceConfig = {}

---- The reference population
BalanceConfig.Reference = {
	Players = 100, -- a full server
	ActiveFraction = 0.6, -- how many of them are watering at any moment
	WaterPerSecond = 1.5, -- water/s of an average (early-game) active player
}

---- Plant goal and growth
BalanceConfig.Goal = {
	-- goal = Players * ActiveFraction * WaterPerSecond * (real grow time) * Fill
	-- (Fill < 1: a full early-game server reaches the goal a bit before the plant would finish)
	Fill = 0.6,
	-- one player counts for at most this fraction of the goal towards the grow-timer boost and stages
	PlayerCapFraction = 0.05,
}

-- Growth points are normalised per plant: reaching the water goal always gives PointsAtGoal points, so the
-- plant has the same size at its goal whatever its rarity (the size curve itself is in PlantsConfig.Growth).
BalanceConfig.PointsAtGoal = 1000

---- Upgrade curves (see UpgradesConfig)
-- speed multiplier(level) = 1 + Bonus * (1 - e^(-level / Scale)) + Tail * level
--   Bonus/Scale: the fast, satisfying early gains that flatten out (diminishing returns)
--   Tail:        a thin linear gain that never stops, so every level keeps mattering a little
-- price(level)  = BasePrice * GrowthEarly^min(level, SoftLevel) * GrowthLate^max(level - SoftLevel, 0)
BalanceConfig.Upgrades = {
	WateringSpeed = {
		BasePrice = 30,
		Bonus = 2.4,
		Scale = 10,
		Tail = 0.01,
	},
	WaterCollectionSpeed = {
		BasePrice = 45,
		Bonus = 1.6,
		Scale = 10,
		Tail = 0.008,
	},
	GrowthEarly = 1.15,
	GrowthLate = 1.26,
	SoftLevel = 12, -- the HOOK phase ends here
	MaxPrice = 1e9, -- prices are clamped (coins are capped at 2^31-1 anyway), so absurd levels can never overflow
}

---- Harvest rewards
BalanceConfig.Harvest = {
	CoinsPerWater = 0.3, -- coins per unit of water the player poured into this plant
	-- the prize pool of a plant = its weight (kg) * PoolPerKg, split between contributors.
	-- An average contributor of a full server should get ~100-150 coins from the pool of a Common plant.
	PoolPerKg = 1500,
	-- shares use (water ^ ShareExponent): 1 = strictly proportional, lower = flatter (top players take less)
	ShareExponent = 0.75,
	FirstHarvestBonus = 250, -- the first plant a player ever helps to grow: a big early achievement
}

---- Plant rarity -> weight (kg) of a fresh plant. Rarer = heavier, but gently, so the pool stays sane.
BalanceConfig.BaseWeight = {
	Common = 1,
	Uncommon = 1.5,
	Rare = 2.2,
	Epic = 3.2,
	Legendary = 5,
}

return BalanceConfig
