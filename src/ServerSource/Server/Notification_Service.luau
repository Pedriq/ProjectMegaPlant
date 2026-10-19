local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local NotificationConfig = require(ReplicatedStorage.SharedSource.Datas.NotificationConfig)

--[[
	Tells a player something ("You have no water!") without the calling service knowing anything about UI:

		Notification_Service:Notify(player, "NoWater")
		Notification_Service:Notify(player, "ZoneLocked", { Zone = "Zone 3", Requirement = "Needs 3 plants grown" })

	The id must exist in NotificationConfig.Messages; the texts and look live there and are drawn by
	Notification_Controller. Only the id and the params travel to the client (params must be strings / numbers).
	The same message to the same player is ignored while it is on cooldown, so a prompt that retriggers every frame
	cannot flood the screen.
]]
local Notification_Service = Knit.CreateService({
	Name = "Notification_Service",
	Client = {
		-- (id, params) only to the player it is meant for
		Notification = Knit.CreateSignal(),
	},
})

local lastSent = {} -- [player] = { [id] = os.clock() }

--- Keeps only strings / numbers / booleans, so nothing unexpected is sent to the client.
local function sanitize(params)
	if type(params) ~= "table" then
		return nil
	end
	local clean = {}
	for key, value in pairs(params) do
		local kind = type(value)
		if type(key) == "string" and (kind == "string" or kind == "number" or kind == "boolean") then
			clean[key] = value
		end
	end
	return clean
end

--- Shows a notification to one player. Returns true if it was sent (false: unknown id, player gone, or cooldown).
function Notification_Service:Notify(player, id, params)
	if not NotificationConfig.Messages[id] then
		warn("Notification_Service: unknown notification '" .. tostring(id) .. "'")
		return false
	end
	if not player or player.Parent ~= Players then
		return false
	end

	local now = os.clock()
	local sent = lastSent[player]
	if not sent then
		sent = {}
		lastSent[player] = sent
	end
	if sent[id] and now - sent[id] < NotificationConfig.Display.Cooldown then
		return false
	end
	sent[id] = now

	Notification_Service.Client.Notification:Fire(player, id, sanitize(params))
	return true
end

--- Shows the same notification to everyone (not throttled per player, use it for rare events).
function Notification_Service:NotifyAll(id, params)
	if not NotificationConfig.Messages[id] then
		warn("Notification_Service: unknown notification '" .. tostring(id) .. "'")
		return
	end
	Notification_Service.Client.Notification:FireAll(id, sanitize(params))
end

function Notification_Service:KnitStart()
	Players.PlayerRemoving:Connect(function(player)
		lastSent[player] = nil
	end)
end

function Notification_Service:KnitInit() end

return Notification_Service
