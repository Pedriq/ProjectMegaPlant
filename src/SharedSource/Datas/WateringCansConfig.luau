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
		HoverGap      studs between the top of the head and the bottom of the can (at scale 1)
		RotationOffset  degrees (X, Y, Z) to align the model: its front (spout side) must point at -Z
		SpoutOffset   spout position relative to the model pivot at scale 1 (used when the model has
		              no part/attachment named "Spout")
		PourTilt      degrees the can tilts forward while pouring
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
		RotationOffset = Vector3.new(0, 0, 0),
		SpoutOffset = Vector3.new(0, 0, -1.5),
		PourTilt = 35,
	},
}

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
