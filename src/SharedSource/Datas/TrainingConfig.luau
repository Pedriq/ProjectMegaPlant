--[[
	Training zones: Workspace/Garden/TrainingZone/<Zone>/<Activity>/Main
	A ProximityPrompt is created on every Main part. To add a zone, add an entry to `Zones` (and build
	the matching folder in the world). To add an activity, add an entry to `Activities` (and a matching
	folder in each zone).

	Each zone is configured independently:
		Multiplier     stat points granted per tick (a tick is ApplyInterval = 0.5 s, so twice per second):
		               Zone1 x1, Zone2 x2, Zone3 x5, Zone4 x10, Zone5 x25, Zone6 x50, Zone7 x75, Zone8 x100.
		               E.g. x10 = 10 per tick = 20 per second.
		GainPerSecond  (optional) overrides the formula above. Either a number (same for every
		               activity of the zone) or a table per activity, e.g. { Strength = 2, Mobility = 1 }.
		Unlock         what the player needs before the zone can be used:
		               { Stat = "PlantsGrown", Amount = 10 }  (Amount 0 / no Unlock = always open)
		               Any stat from StatsConfig can be used here.
	The server validates the unlock every time training is started.
]]

local TrainingConfig = {}

-- player attribute set while training: the station id ("Zone1.Strength"), nil otherwise.
-- Replicated on purpose: clients use it to fade other trainees at the same station.
TrainingConfig.Attribute = "TrainingStation"

-- used only by the juice pools (JuicePool_Service); zone training grants `Multiplier` points per tick
TrainingConfig.BaseGainPerSecond = 3

TrainingConfig.RootPath = { "Garden", "TrainingZone" }

TrainingConfig.Zones = {
	Zone1 = {
		Order = 1,
		DisplayName = "Zone 1",
		Multiplier = 1,
		Unlock = { Stat = "PlantsGrown", Amount = 0 },
	},
	Zone2 = {
		Order = 2,
		DisplayName = "Zone 2",
		Multiplier = 2,
		Unlock = { Stat = "PlantsGrown", Amount = 1 },
	},
	Zone3 = {
		Order = 3,
		DisplayName = "Zone 3",
		Multiplier = 5,
		Unlock = { Stat = "PlantsGrown", Amount = 3 },
	},
	Zone4 = {
		Order = 4,
		DisplayName = "Zone 4",
		Multiplier = 10,
		Unlock = { Stat = "PlantsGrown", Amount = 8 },
	},
	Zone5 = {
		Order = 5,
		DisplayName = "Zone 5",
		Multiplier = 25,
		Unlock = { Stat = "PlantsGrown", Amount = 15 },
	},
	Zone6 = {
		Order = 6,
		DisplayName = "Zone 6",
		Multiplier = 50,
		Unlock = { Stat = "PlantsGrown", Amount = 25 },
	},
	Zone7 = {
		Order = 7,
		DisplayName = "Zone 7",
		Multiplier = 75,
		Unlock = { Stat = "PlantsGrown", Amount = 50 },
	},
	Zone8 = {
		Order = 8,
		DisplayName = "Zone 8",
		Multiplier = 100,
		Unlock = { Stat = "PlantsGrown", Amount = 100 },
	},
}

--[[
	Stat       the stat that grows
	Pose       "Lying" (on their back on Main) or "Standing" (upright on Main)
	YawOffset  (optional) degrees the character is turned about Y from the way Main faces. The Mobility treadmills are
	           built with Main facing AWAY from the console, so the runner is turned 180 to face it.
	Animation  looped animation played on the character, per rig type, or nil for none.
	           Strength has none yet: the character just stays lying down.
	Title      text shown above the Cancel button
]]
TrainingConfig.Activities = {
	Strength = {
		Stat = "Strength",
		ActionText = "Train Strength",
		Title = "Training Strength",
		Pose = "Lying",
		Animation = nil, -- TODO: weightlifting animation
	},
	Mobility = {
		Stat = "Mobility",
		ActionText = "Train Mobility",
		Title = "Training Mobility",
		Pose = "Standing",
		YawOffset = 180, -- Main faces away from the treadmill's console in every zone: run TOWARD the console
		Animation = {
			R15 = "rbxassetid://507767714", -- Roblox default R15 run
			R6 = "rbxassetid://180426354", -- Roblox default R6 run/walk
		},
	},
}

-- Training starts with a hold-prompt on each station's Main part. It ends with the Cancel button or by
-- jumping (Space / gamepad A) - see Training_Controller.
TrainingConfig.Prompt = {
	HoldDuration = 0.4,
	MaxActivationDistance = 10,
	KeyboardKeyCode = Enum.KeyCode.E,
	GamepadKeyCode = Enum.KeyCode.ButtonX,
	RequiresLineOfSight = false,
}

-- seconds between stat gains while training (whole points are applied in batches)
TrainingConfig.ApplyInterval = 0.5

-- extra studs of leeway for server-side distance checks
TrainingConfig.DistanceTolerance = 6

-- how far above the Main surface the body is placed
TrainingConfig.LyingHeight = 0.9

-- how transparent other trainees at the same station look to the local player (0-1)
TrainingConfig.OtherTraineeTransparency = 0.75

---- Accessors (use these instead of reading the tables directly)

--- Stat points per second earned in a zone for an activity.
function TrainingConfig.GetGainPerSecond(zoneId, activityId)
	local zone = TrainingConfig.Zones[zoneId]
	if not zone then
		return 0
	end
	local override = zone.GainPerSecond
	if type(override) == "table" then
		return override[activityId] or 0
	elseif override then
		return override
	end
	return (zone.Multiplier or 1) / TrainingConfig.ApplyInterval
end

--- The fixed multiplier of a zone (x1, x2, x5).
function TrainingConfig.GetMultiplier(zoneId)
	local zone = TrainingConfig.Zones[zoneId]
	return zone and zone.Multiplier or 1
end

--- Zone ids sorted by their Order (Zone1, Zone2, ...).
function TrainingConfig.GetZoneOrder()
	local ids = {}
	for zoneId in pairs(TrainingConfig.Zones) do
		table.insert(ids, zoneId)
	end
	table.sort(ids, function(a, b)
		return TrainingConfig.Zones[a].Order < TrainingConfig.Zones[b].Order
	end)
	return ids
end

--- The unlock requirement of a zone ({ Stat, Amount }), or nil if the zone is always open.
function TrainingConfig.GetUnlock(zoneId)
	local zone = TrainingConfig.Zones[zoneId]
	local unlock = zone and zone.Unlock
	if unlock and unlock.Amount and unlock.Amount > 0 then
		return unlock
	end
	return nil
end

--- True if the zone is open for a player. `getStat(statKey)` returns the player's stat value.
function TrainingConfig.IsUnlocked(zoneId, getStat)
	if not TrainingConfig.Zones[zoneId] then
		return false
	end
	local unlock = TrainingConfig.GetUnlock(zoneId)
	if not unlock then
		return true
	end
	return (getStat(unlock.Stat) or 0) >= unlock.Amount
end

--- Human readable requirement, e.g. "Needs 10 plants grown", or nil if the zone is always open.
function TrainingConfig.GetUnlockText(zoneId)
	local unlock = TrainingConfig.GetUnlock(zoneId)
	if not unlock then
		return nil
	end
	local names = { PlantsGrown = "plants grown" }
	return ("Needs %d %s"):format(unlock.Amount, names[unlock.Stat] or unlock.Stat)
end

return TrainingConfig
