local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

--[[
	Mirror of the player's saved data on the client. The server (ProfileService) pushes every change through
	the UpdateSpecificData remote; nothing listened to it before, which made Roblox log
	"Remote event invocation queue exhausted ... UpdateSpecificData". Listening here fixes that and gives
	the client read-only access to its data:

		Data_Controller:Get("Stats", "Coins")   -- nil until the data arrived
		Data_Controller.Changed:Connect(function(path, value) end)

	Only for display; the server never trusts anything from here.
]]
local Signal = require(ReplicatedStorage.Packages.Signal)

local Data_Controller = Knit.CreateController({
	Name = "Data_Controller",
})

Data_Controller.Data = {}
Data_Controller.Changed = Signal.new() -- (path, value)

function Data_Controller:Get(...)
	local value = Data_Controller.Data
	for _, key in ipairs({ ... }) do
		if type(value) ~= "table" then
			return nil
		end
		value = value[key]
	end
	return value
end

local function apply(path, value)
	local target = Data_Controller.Data
	for i = 1, #path - 1 do
		local nextTarget = target[path[i]]
		if type(nextTarget) ~= "table" then
			nextTarget = {}
			target[path[i]] = nextTarget
		end
		target = nextTarget
	end
	target[path[#path]] = value
end

function Data_Controller:KnitStart()
	local profileService = Knit.GetService("ProfileService")

	profileService.UpdateSpecificData:Connect(function(path, value)
		if type(path) == "table" and #path > 0 then
			apply(path, value)
			Data_Controller.Changed:Fire(path, value)
		end
	end)

	-- the full data set, in case the client wants the initial state
	profileService.GetData:Connect(function(data)
		if type(data) == "table" then
			Data_Controller.Data = data
		end
	end)
	profileService.GetData:Fire()
end

function Data_Controller:KnitInit() end

return Data_Controller
