local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local AudioConfig = require(ReplicatedStorage.SharedSource.Datas.AudioConfig)

--[[
	All sound playback goes through here, by slot name (see AudioConfig):

		Audio:Play("CoinBeat", { Pitch = 1.3, Volume = 0.8 })   -- one-shot, multipliers are optional
		Audio:SetLoop("PourLoop", true)                         -- looped sound with smooth fade in/out

	A slot with an empty / missing Id is silently skipped, so unfinished audio never errors.
]]
local Audio_Controller = Knit.CreateController({
	Name = "Audio_Controller",
})

local group
local loops = {} -- [name] = Sound

local function getDefinition(name)
	local definition = AudioConfig.Sounds[name]
	if not definition or definition.Id == nil or definition.Id == "" then
		return nil
	end
	return definition
end

--- Plays a one-shot sound. options: Pitch (multiplier), Volume (multiplier), Parent (3D sound source)
function Audio_Controller:Play(name, options)
	local definition = getDefinition(name)
	if not definition or definition.Loop then
		return
	end
	options = options or {}

	local sound = Instance.new("Sound")
	sound.SoundId = definition.Id
	sound.Volume = definition.Volume * (options.Volume or 1) * AudioConfig.MasterVolume
	sound.PlaybackSpeed = definition.Pitch * (options.Pitch or 1)
	sound.RollOffMaxDistance = 120
	sound.SoundGroup = group
	sound.Parent = options.Parent or group
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	Debris:AddItem(sound, 8) -- in case Ended never fires
end

--- Starts / stops a looped slot, fading the volume smoothly.
function Audio_Controller:SetLoop(name, active)
	local definition = getDefinition(name)
	if not definition then
		return
	end

	local sound = loops[name]
	if active then
		if not sound then
			sound = Instance.new("Sound")
			sound.SoundId = definition.Id
			sound.Looped = true
			sound.Volume = 0
			sound.PlaybackSpeed = definition.Pitch
			sound.SoundGroup = group
			sound.Parent = group
			loops[name] = sound
			sound:Play()
		end
		TweenService:Create(sound, TweenInfo.new(0.15), {
			Volume = definition.Volume * AudioConfig.MasterVolume,
		}):Play()
	elseif sound then
		loops[name] = nil
		local fade = TweenService:Create(sound, TweenInfo.new(0.2), { Volume = 0 })
		fade.Completed:Once(function()
			sound:Destroy()
		end)
		fade:Play()
	end
end

function Audio_Controller:KnitStart() end

function Audio_Controller:KnitInit()
	group = Instance.new("SoundGroup")
	group.Name = "GameSFX"
	group.Parent = SoundService
end

return Audio_Controller
