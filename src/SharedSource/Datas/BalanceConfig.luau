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
--
-- GROW TIME: every rarity has a TARGET time: how long a full (100 player) server in the early game needs.
-- The plant's configured timer ("base time") is longer, because the water boost shortens it:
--     boosted time = base * (1 - BoostMax * goalFraction),   goalFraction = water / goal (capped at 1)
-- A reference server reaches 100% of the goal at Fill of the way, so  base = target * (1 + BoostMax / Fill).
-- Real servers land around the target: more / stronger players push towards 1 - BoostMax of the base time
-- (about 0.8 x target), a thin server needs up to the full base time (about 2 x target).
-- Rarer plants are faster, but heavier: they pay more per plant (see BaseWeight and Juice multipliers).
BalanceConfig.TargetTime = {
	Common = 1200, -- 20:00, the baseline: watering a plant is a long, shared effort
	Uncommon = 960, -- 16:00
	Rare = 720, -- 12:00
	Epic = 480, -- 8:00
	Legendary = 300, -- 5:00
}

-- the waiting time after a plant finished (the juice pool is open), before the next plant is selected
BalanceConfig.Cycle = {
	FinishedDuration = 180,
}

-- The water goal follows the population present when the plant starts, so a small group is not
-- stuck with a goal made for 100 players (and the harvest pool shrinks with it).
--   population factor = clamp(players / Reference.Players, Min, 1)
BalanceConfig.Population = {
	Min = 0.1, -- a lone player never gets a trivially small goal
}

-- The first plants of a server are easier (a lower goal), which gives a quick, rewarding start.
--   difficulty = EarlyFactor for the first plant, rising linearly to 1 after RampCycles plants
BalanceConfig.Difficulty = {
	EarlyFactor = 0.5,
	RampCycles = 8,
}

BalanceConfig.Goal = {
	-- how much the water goal can shorten the plant's timer (0.6 = up to 60%)
	BoostMax = 0.6,
	-- with few players a single player may count for more: cap = max(PlayerCapFraction, CapShare / players)
	CapShare = 1.25,
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

---- Strength -> watering can capacity (see StatsConfig) and its visual size (see WateringCansConfig)
-- capacity(S) = Base + Bonus * (1 - e^(-S / Scale)) + Tail * log10(1 + S / TailScale)
--   Bonus/Scale: fast, very visible early growth (10 -> ~17 after one minute of Zone 1, ~36 after five)
--   Tail:        an endless but slow logarithmic climb, so late game never explodes (S = 1,000,000 -> ~100)
-- A bigger can makes each trip longer but saves walking; the throughput of a player is capped anyway
-- (see the rate formula at the top), so capacity can't break the grow-time floor.
BalanceConfig.Capacity = {
	Base = 10,
	Bonus = 45,
	Scale = 300,
	Tail = 14,
	TailScale = 500,
	-- the "Bigger Can!" banner shows every time the capacity crosses a multiple of this
	Milestone = 5,
}

-- Visual scale of the carried can: 1 at base capacity, then
--   1 + Growth * (1 - e^(-(capacity - Base) / Scale))  ->  1.2 at 16, 1.5 at 25, 1.7 at 36, 1.9 at 100+
BalanceConfig.CanSize = {
	Growth = 0.9,
	Scale = 20,
}

---- Harvest rewards
BalanceConfig.Harvest = {
	CoinsPerWater = 0.15, -- coins per unit of water the player poured into this plant
	-- everyone who helped gets this on top (a "thank you" that scales with how long the plant takes)
	BaseByRarity = {
		Common = 90,
		Uncommon = 135,
		Rare = 210,
		Epic = 330,
		Legendary = 600,
	},
	-- the prize pool of a plant = its weight (kg) * PoolPerKg, split between contributors.
	-- An average contributor of a full server gets ~500-600 coins from the pool of a Common plant (a 20 minute
	-- effort), roughly a quarter of what they earn while pouring for it.
	PoolPerKg = 7500,
	-- shares use (water ^ ShareExponent): 1 = strictly proportional, lower = flatter (top players take less)
	ShareExponent = 0.75,
	FirstHarvestBonus = 600, -- the first plant a player ever helps to grow: a big early achievement
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
