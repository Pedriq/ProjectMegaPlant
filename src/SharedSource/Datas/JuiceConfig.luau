--[[
	The "juice pool": what a fully grown plant leaves behind.

	Sequence (server and clients share these timings, everything is relative to the server start time):
	  0 ............ LaunchTime   the plant lifts off and spins upwards, the camera orbits it
	  LaunchTime ... ExplosionAt  it hovers and trembles
	  ExplosionAt .. explosion, a pool of juice rises where the plant stood
	  ExplosionAt + OutroTime     the camera glides back to the player

	The pool is an upgrade zone: while a player stands in it, EVERY stat in Pool.Stats grows at
	TrainingConfig.BaseGainPerSecond * multiplier per second. The multiplier depends on the plant:
	  rarity -> a { min, max } range (Multipliers)
	  size   -> where inside that range it lands (0 = the plant never grew, 1 = SizeRatioForMax or bigger)
	The pool stays until the next plant is selected.
]]

local JuiceConfig = {}

---- Timeline / camera
JuiceConfig.Cinematic = {
	LaunchTime = 4.2, -- seconds of lift-off
	HoldTime = 1.2, -- seconds hovering before the explosion
	OutroTime = 2.2, -- camera blend back to the player after the explosion
	LiftBase = 10, -- studs the plant rises, plus LiftPerSize * its height
	LiftPerSize = 0.8,
	SpinTurns = 1.5, -- full turns the plant spins while rising
	OrbitTurns = 0.85, -- fraction of a full circle the camera travels before the explosion
	OrbitRadiusMin = 22,
	OrbitRadiusPerSize = 1.6, -- camera distance = max(min, plant size * this)
	CameraRange = 170, -- players further away than this keep their normal camera (they still see the effects)
	BlendIn = 0.9,
}

JuiceConfig.ExplosionAt = JuiceConfig.Cinematic.LaunchTime + JuiceConfig.Cinematic.HoldTime
JuiceConfig.TotalTime = JuiceConfig.ExplosionAt + JuiceConfig.Cinematic.OutroTime

-- the "Top Gardeners" board is visible from ShowAt until HideAt seconds into the sequence
JuiceConfig.Leaderboard = {
	ShowAt = 0.9,
	HideAt = JuiceConfig.TotalTime - 0.3,
	Size = 3, -- how many places are shown
}

---- Multiplier per rarity: { min, max }. A tiny plant gives the min, a plant of SizeRatioForMax+ gives the max.
JuiceConfig.Multipliers = {
	Common = { 1.5, 2.5 },
	Uncommon = { 2, 4 },
	Rare = { 3, 6 },
	Epic = { 5, 10 },
	Legendary = { 8, 16 },
}
-- size = scale / seedling scale at the end of the growth (see PlantGrowth); this ratio counts as "fully huge"
JuiceConfig.SizeRatioForMax = 12
-- the weakest / strongest multiplier in the table above, used to scale the visuals (glow, particles)
JuiceConfig.VisualMin = 1.5
JuiceConfig.VisualMax = 16

---- The pool in the world
JuiceConfig.Pool = {
	RadiusMin = 14, -- studs, for the smallest plant
	RadiusMax = 30, -- studs, for a huge plant
	Thickness = 0.32,
	RimExtra = 3.2, -- the rim is this much wider (diameter) than the juice
	RiseTime = 1.4,
	AppearDelay = 0.3, -- seconds after the explosion before the pool starts to rise
	Stats = { "Strength", "Mobility" }, -- every one of these grows at once
	CheckInterval = 0.2, -- seconds between inside/outside checks
	ApplyInterval = 0.5, -- seconds between stat payouts
	RadiusLeeway = 1, -- studs of tolerance at the edge
	ReachBelow = 4, -- vertical tolerance (studs) below / above the pool surface
	ReachAbove = 9,
	LawnName = "Lawn", -- Workspace/Garden/<LawnName>: the pool is laid flush on its surface
	Tag = "JuicePool",
	Name = "JuicePool",
}

-- replicated player attribute: the multiplier of the pool the player stands in (absent = not inside)
JuiceConfig.BoostAttribute = "JuiceBoost"

---- Helpers

--- 0..1: how big the plant ended up.
function JuiceConfig.GetSizeFactor(sizeRatio)
	return math.clamp((sizeRatio - 1) / (JuiceConfig.SizeRatioForMax - 1), 0, 1)
end

--- Multiplier of the pool for a rarity key ("Common"...) and the plant's size ratio. Rounded to 0.1.
function JuiceConfig.GetMultiplier(rarityKey, sizeRatio)
	local range = JuiceConfig.Multipliers[rarityKey] or JuiceConfig.Multipliers.Common
	local value = range[1] + (range[2] - range[1]) * JuiceConfig.GetSizeFactor(sizeRatio)
	return math.floor(value * 10 + 0.5) / 10
end

function JuiceConfig.GetRadius(sizeRatio)
	local pool = JuiceConfig.Pool
	return pool.RadiusMin + (pool.RadiusMax - pool.RadiusMin) * JuiceConfig.GetSizeFactor(sizeRatio)
end

--- 0..1: how strong a multiplier is overall (drives glow and particle amounts).
function JuiceConfig.GetStrength(multiplier)
	return math.clamp(
		(multiplier - JuiceConfig.VisualMin) / (JuiceConfig.VisualMax - JuiceConfig.VisualMin),
		0,
		1
	)
end

--- How high the plant has risen `elapsed` seconds into the sequence (same on server and clients).
function JuiceConfig.GetLaunchHeight(plantHeight, elapsed)
	local cinematic = JuiceConfig.Cinematic
	local lift = cinematic.LiftBase + plantHeight * cinematic.LiftPerSize
	local a = math.clamp(elapsed / cinematic.LaunchTime, 0, 1)
	local eased = -(math.cos(math.pi * a) - 1) / 2
	return lift * eased, a
end

return JuiceConfig
