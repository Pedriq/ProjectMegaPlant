local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local TrainingConfig = require(ReplicatedStorage.SharedSource.Datas.TrainingConfig)

--[[
	Keeps the billboards above the training zones (Workspace/Garden/TrainingZone/<Zone>/SignAnchor/ZoneSign)
	in sync with TrainingConfig, so a changed requirement or multiplier never needs the signs edited by hand.

	Each ZoneSign is built in Studio with the attributes ZoneId ("Zone3") and RarityName ("Rare"). The rarity is
	not in the config: it is a property of the zone's colored base (Zone/RarityBase), so it is set by hand.
	This controller rewrites three labels of the sign:
		Panel/Title             "ZONE 3" (+ its outline copies)
		Panel/Pill/Meta         "RARE  •  x5"
		Panel/Requirement       "3 plants grown" / "Open for everyone" (+ its outline copies)
	Purely cosmetic and client-only: the server validates the unlock itself (see TrainingLock_Controller).
]]
local ZoneSign_Controller = Knit.CreateController({
	Name = "ZoneSign_Controller",
})

local SIGN_NAME = "ZoneSign"

-- how a stat is written in the requirement line
local STAT_PHRASE = {
	PlantsGrown = { One = "plant grown", Many = "plants grown" },
}

local function requirementText(zoneId)
	local unlock = TrainingConfig.GetUnlock(zoneId)
	if not unlock then
		return "Open for everyone"
	end
	local phrase = STAT_PHRASE[unlock.Stat]
	local noun = phrase and (unlock.Amount == 1 and phrase.One or phrase.Many) or unlock.Stat
	return ("%d %s"):format(unlock.Amount, noun)
end

local function metaText(sign, zoneId)
	local multiplier = ("x%g"):format(TrainingConfig.GetMultiplier(zoneId))
	local rarity = sign:GetAttribute("RarityName")
	if rarity and rarity ~= "" then
		return ("%s  •  %s"):format(rarity:upper(), multiplier)
	end
	return multiplier
end

local function refresh(sign)
	local zoneId = sign:GetAttribute("ZoneId")
	local zone = zoneId and TrainingConfig.Zones[zoneId]
	local panel = sign:FindFirstChild("Panel")
	if not (zone and panel) then
		return
	end
	local meta = panel:FindFirstChild("Pill") and panel.Pill:FindFirstChild("Meta")
	if meta then
		meta.Text = metaText(sign, zoneId)
	end
	-- the black text outlines are copies of the labels (TitleOutline1..8, RequirementOutline1..8) with the same text
	local texts = {
		Title = zone.DisplayName:upper(),
		Requirement = requirementText(zoneId),
	}
	for _, child in ipairs(panel:GetChildren()) do
		local text = child:IsA("TextLabel") and texts[child.Name:gsub("Outline%d+$", "")]
		if text then
			child.Text = text
		end
	end
end

local function register(instance)
	if not (instance:IsA("BillboardGui") and instance.Name == SIGN_NAME) then
		return
	end
	refresh(instance)
	instance:GetAttributeChangedSignal("ZoneId"):Connect(function()
		refresh(instance)
	end)
	instance:GetAttributeChangedSignal("RarityName"):Connect(function()
		refresh(instance)
	end)
end

function ZoneSign_Controller:KnitStart()
	-- the signs are part of the world and may stream in at any time
	workspace.DescendantAdded:Connect(register)
	for _, descendant in ipairs(workspace:GetDescendants()) do
		register(descendant)
	end
end

function ZoneSign_Controller:KnitInit() end

return ZoneSign_Controller
