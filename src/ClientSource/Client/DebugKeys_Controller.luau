local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)

--[[
	Developer keyboard shortcuts. They only exist in Roblox Studio (RunService:IsStudio()), never in the live game,
	and are the no-chat way to run DebugCommands_Service commands (chat is blocked in some regions).
		F6          restart the tutorial
		Shift+F7    reset ALL your saved data to a new player's (it is saved to the real DataStore!)
	A toast confirms each one.
]]
local DebugKeys_Controller = Knit.CreateController({
	Name = "DebugKeys_Controller",
})

local DebugCommands_Service, Notification_Controller

local function run(command, message)
	DebugCommands_Service:RunCommand(command)
		:andThen(function(ok)
			Notification_Controller:Push({
				Type = ok and "Info" or "Error",
				Title = ok and message or "Debug command refused",
				Sound = false,
			})
		end)
		:catch(warn)
end

function DebugKeys_Controller:KnitStart()
	if not RunService:IsStudio() then
		return
	end
	DebugCommands_Service = Knit.GetService("DebugCommands_Service")
	Notification_Controller = Knit.GetController("Notification_Controller")

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F6 then
			run("Tutorial", "Tutorial restarted")
		elseif input.KeyCode == Enum.KeyCode.F7 and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
			run("ResetData", "Data reset - stop and press Play again")
		end
	end)
end

function DebugKeys_Controller:KnitInit() end

return DebugKeys_Controller
