local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local StatsConfig = require(ReplicatedStorage.SharedSource.Datas.StatsConfig)
local TrainingConfig = require(ReplicatedStorage.SharedSource.Datas.TrainingConfig)
local WaitFor = require(ReplicatedStorage.ClientSource.Utilities.WaitFor)

--[[
	Shows which training zones are locked for the local player by changing the prompt texts locally
	("Locked" + the requirement). This is purely cosmetic: the server validates the unlock itself
	every time training starts, so a locked zone can never be used.
]]
local TrainingLock_Controller = Knit.CreateController({
	Name = "TrainingLock_Controller",
})

local player = Players.LocalPlayer

local prompts = {} -- [prompt] = { ZoneId, ObjectText, ActionText }

local function getStat(statKey)
	local definition = StatsConfig.ByKey[statKey]
	local leaderstats = player:FindFirstChild(StatsConfig.Folder)
	local value = definition and leaderstats and leaderstats:FindFirstChild(definition.DisplayName)
	return value and value.Value or 0
end

local function refresh(prompt)
	local info = prompts[prompt]
	if not info then
		return
	end
	if TrainingConfig.IsUnlocked(info.ZoneId, getStat) then
		prompt.ObjectText = info.ObjectText
		prompt.ActionText = info.ActionText
	else
		prompt.ObjectText = ("%s - %s"):format(info.ObjectText, TrainingConfig.GetUnlockText(info.ZoneId) or "")
		prompt.ActionText = "Locked"
	end
end

local function register(instance)
	if not (instance:IsA("ProximityPrompt") and instance.Name == "TrainingPrompt") then
		return
	end
	local zoneId = instance:GetAttribute("ZoneId")
	if not zoneId then
		-- attribute not replicated yet
		instance:GetAttributeChangedSignal("ZoneId"):Once(function()
			register(instance)
		end)
		return
	end
	if prompts[instance] then
		return
	end
	prompts[instance] = {
		ZoneId = zoneId,
		ObjectText = instance.ObjectText,
		ActionText = instance.ActionText,
	}
	instance.Destroying:Once(function()
		prompts[instance] = nil
	end)
	refresh(instance)
end

local function refreshAll()
	for prompt in pairs(prompts) do
		refresh(prompt)
	end
end

function TrainingLock_Controller:KnitStart()
	-- re-evaluate whenever the stats that can unlock zones change
	local leaderstats = WaitFor.Child(player, StatsConfig.Folder)
	if not leaderstats then
		return
	end
	local function watchStat(valueObject)
		valueObject.Changed:Connect(refreshAll)
	end
	for _, valueObject in ipairs(leaderstats:GetChildren()) do
		watchStat(valueObject)
	end
	leaderstats.ChildAdded:Connect(function(valueObject)
		watchStat(valueObject)
		refreshAll()
	end)

	-- prompts are created by the server and may stream in at any time
	workspace.DescendantAdded:Connect(register)
	for _, descendant in ipairs(workspace:GetDescendants()) do
		register(descendant)
	end
end

function TrainingLock_Controller:KnitInit() end

return TrainingLock_Controller
