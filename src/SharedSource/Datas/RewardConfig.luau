--[[
	Reward / "game feel" tuning for the watering loop. Everything here is server-authoritative
	(the client only displays what the server decided).

	Pour beats    While pouring, every BeatInterval the server pays coins for the water poured in that
	              beat. Staying on the plant builds a combo (more coins per beat) and every beat has a
	              chance to be a LUCKY pour (big multiplier). Quick surprises + a visible streak.
	Water goal    Every plant has a shared water goal (PlantsConfig.GetWaterGoal). The closer the whole
	              server gets to it, the shorter the plant's grow timer (up to Boost.MaxFraction).
	Stages        Milestones on the way to the goal; each one is a server-wide celebration that pays a
	              bonus to everyone who contributed.
	Harvest       When the timer ends, contributors get a payout based on rarity and how much they poured.
]]

local BalanceConfig = require(game:GetService("ReplicatedStorage").SharedSource.Datas.BalanceConfig)

local RewardConfig = {}

RewardConfig.Pour = {
	BeatInterval = 0.5, -- seconds of pouring per payout
	CritChance = BalanceConfig.Luck.BaseCritChance, -- base chance that a beat is a LUCKY pour (the Luck upgrade raises it)
	CritMultiplier = 3,
	ComboStep = 0.04, -- +4% coins per combo level
	ComboMax = 25, -- combo level cap (+100% at the cap)
	ComboGrace = 3, -- seconds after stopping before the combo is lost
}

-- The grow timer shrinks by up to this fraction when the water goal is reached.
RewardConfig.Boost = {
	MaxFraction = BalanceConfig.Goal.BoostMax,
	-- one player counts for at most this fraction of the water goal (towards the boost and the stages),
	-- so a single heavily upgraded player can't shorten the plant on their own
	PlayerCapFraction = BalanceConfig.Goal.PlayerCapFraction,
	MinSecondsChange = 1.5, -- the timer is only re-sent when it changes by at least this much
}

-- Fraction of the water goal at which each stage is reached.
RewardConfig.Stages = {
			{ Name = "Sprouting!", Fraction = 0.2, BonusCoins = 60 },
	{ Name = "Budding!", Fraction = 0.4, BonusCoins = 90 },
	{ Name = "Blooming!", Fraction = 0.6, BonusCoins = 135 },
	{ Name = "Thriving!", Fraction = 0.8, BonusCoins = 210 },
	{ Name = "MAX GROWTH!", Fraction = 1.0, BonusCoins = 360 },
}

RewardConfig.Harvest = {
	-- payout = participation (BaseByRarity) + own water * CoinsPerWater + the player's SHARE of the prize pool.
	-- The pool is the plant's weight (kg) * PoolPerKg. Shares are weighted by (water ^ ShareExponent): the more
	-- you pour the more you earn, but top contributors can't take the whole pool.
	CoinsPerWater = BalanceConfig.Harvest.CoinsPerWater,
	PoolPerKg = BalanceConfig.Harvest.PoolPerKg,
	ShareExponent = BalanceConfig.Harvest.ShareExponent,
	FirstHarvestBonus = BalanceConfig.Harvest.FirstHarvestBonus, -- the first plant a player helps to grow
	BaseByRarity = BalanceConfig.Harvest.BaseByRarity, -- everyone who helped gets this
}

-- how often the shared goal / stages are re-evaluated (seconds)
RewardConfig.CheckInterval = 0.25

return RewardConfig
