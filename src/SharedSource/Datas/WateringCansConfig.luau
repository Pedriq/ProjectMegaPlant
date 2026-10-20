--[[
	Watering can definitions. To add a can: drop a model with the same name into
	ReplicatedStorage/Assets/WateringCans and add one entry to `Cans`.
	Equip a can with Water_Service:SetCan(player, canId).

	Can fields:
		DisplayName
		ModelName     name of the model in the WateringCans folder (defaults to the can id)
		FillRate      water units per second collected while holding a water source prompt
		PourRate      water units per second poured onto the plant
		MinScale      model scale when the can is nearly empty
		MaxScale      model scale when the can is full
		HoverGap      studs between the top of the head and the bottom of the can (a fixed distance, it doesn't grow with the can)
		RotationOffset  degrees (X, Y, Z) to align the model: its front (spout side) must point at -Z
		SpoutOffset   spout tip relative to the model pivot at scale 1, in the ALIGNED frame (after RotationOffset, so
		              the spout is on -Z). Used when the model has no part/attachment named "Spout".
		PourTilt      degrees the can tilts forward while pouring
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BalanceConfig = require(ReplicatedStorage.SharedSource.Datas.BalanceConfig)

local WateringCansConfig = {}

WateringCansConfig.AssetFolderNames = { "Assets", "Aseets" }
WateringCansConfig.FolderName = "WateringCans"
WateringCansConfig.Default = "BasicWateringCan"

WateringCansConfig.Cans = {
	BasicWateringCan = {
		DisplayName = "Basic Watering Can",
		FillRate = 6,
		PourRate = 3.5,
		MinScale = 0.6,
		MaxScale = 1.6,
		HoverGap = 0.6,
		-- the BasicWateringCan template has its pivot turned 45 degrees and its spout on a diagonal of the mesh: 270
		-- degrees about Y puts the spout on -Z (handle at the back), the way WateringCanVisual_Controller expects
		RotationOffset = Vector3.new(0, 270, 0),
		-- spout tip (measured): about one stud out in front of the pivot, a bit above the middle
		SpoutOffset = Vector3.new(0, 0.25, -1),
		PourTilt = 35,
	},
}

--- Scale of the carried can for the water it holds (BalanceConfig.CanSize): MinScale plus Coefficient * water ^ Exponent
--- (big already at a little water), up to SlowdownWater. Past that the growth slows down (logarithmic), so the can never stops
--- growing but gets harder to enlarge the bigger it is.
function WateringCansConfig.GetWaterScale(config, water)
	local balance = BalanceConfig.CanSize
	local slowdown = balance.SlowdownWater
	local scale = config.MinScale + balance.Coefficient * math.min(water, slowdown) ^ balance.Exponent
	local extra = water - slowdown
	if extra > 0 then
		-- continues with the slope the curve has at SlowdownWater, then flattens
		local slope = balance.Coefficient * balance.Exponent * slowdown ^ (balance.Exponent - 1)
		scale += slope * slowdown * math.log(1 + extra / slowdown)
	end
	return scale
end

--- Returns the config for a can, falling back to the default can.
function WateringCansConfig.Get(canId)
	return WateringCansConfig.Cans[canId] or WateringCansConfig.Cans[WateringCansConfig.Default]
end

--- Returns the model template for a can, or nil if it's missing.
function WateringCansConfig.GetTemplate(canId)
	local config = WateringCansConfig.Cans[canId]
	if not config then
		return nil
	end
	for _, folderName in ipairs(WateringCansConfig.AssetFolderNames) do
		local assets = ReplicatedStorage:FindFirstChild(folderName)
		local folder = assets and assets:FindFirstChild(WateringCansConfig.FolderName)
		local template = folder and folder:FindFirstChild(config.ModelName or canId)
		if template then
			return template
		end
	end
	return nil
end

return WateringCansConfig
