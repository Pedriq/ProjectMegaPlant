local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local FriendBoostConfig = require(ReplicatedStorage.SharedSource.Datas.FriendBoostConfig)

--[[
	Friend Boost (see FriendBoostConfig): +10% money per friend who is in the same server.

	Friendships are checked with Player:IsFriendsWith once per pair when someone joins (it is a web call, so it
	runs in its own thread and can never block the game). The friend count and the resulting multiplier are written
	to two player attributes, so the client can show them, and Reward_Service asks :GetMultiplier(player) for the
	money it pays out. Everything updates live when a friend joins or leaves.
]]
local FriendBoost_Service = Knit.CreateService({
	Name = "FriendBoost_Service",
	Client = {},
})

local FRIENDS_ATTRIBUTE = FriendBoostConfig.FriendsAttribute
local MULTIPLIER_ATTRIBUTE = FriendBoostConfig.MultiplierAttribute

local friendsOf = {} -- [player] = { [otherPlayer] = true }
local fakeFriends = {} -- [player] = number: DEBUG, replaces the real count (Studio only)

local function countFriends(player)
	if fakeFriends[player] ~= nil then
		return fakeFriends[player]
	end
	local count = 0
	for _ in pairs(friendsOf[player] or {}) do
		count += 1
	end
	return count
end

local function publish(player)
	if player.Parent ~= Players then
		return
	end
	local friends = countFriends(player)
	player:SetAttribute(FRIENDS_ATTRIBUTE, friends)
	player:SetAttribute(MULTIPLIER_ATTRIBUTE, FriendBoostConfig.GetMultiplier(friends))
end

local function link(a, b)
	friendsOf[a] = friendsOf[a] or {}
	friendsOf[b] = friendsOf[b] or {}
	friendsOf[a][b] = true
	friendsOf[b][a] = true
	publish(a)
	publish(b)
end

local function onPlayerAdded(player)
	friendsOf[player] = friendsOf[player] or {}
	publish(player)
	-- the new player against everyone already here (each pair is checked exactly once, by the one who arrives later)
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			task.spawn(function()
				local ok, areFriends = pcall(function()
					return player:IsFriendsWith(other.UserId)
				end)
				if ok and areFriends and player.Parent == Players and other.Parent == Players then
					link(player, other)
				end
			end)
		end
	end
end

local function onPlayerRemoving(player)
	local friends = friendsOf[player]
	friendsOf[player] = nil
	fakeFriends[player] = nil
	for other in pairs(friends or {}) do
		if friendsOf[other] then
			friendsOf[other][player] = nil
			publish(other)
		end
	end
end

---- Public API

--- Number of friends the player currently has in this server.
function FriendBoost_Service:GetFriendCount(player)
	return countFriends(player)
end

--- Multiplier for the money this player earns: 1 = no bonus, 1.3 = three friends.
function FriendBoost_Service:GetMultiplier(player)
	return FriendBoostConfig.GetMultiplier(countFriends(player))
end

--- DEBUG: pretends the player has `count` friends (nil = back to the real count). Studio only: see DebugCommands_Service.
function FriendBoost_Service:DebugSetFriends(player, count)
	fakeFriends[player] = count
	publish(player)
end

function FriendBoost_Service:KnitStart()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end

function FriendBoost_Service:KnitInit() end

return FriendBoost_Service
