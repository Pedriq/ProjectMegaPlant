--[[
	Friend Boost: every friend who is in the same server as the player gives them a bonus to the money (coins) they
	earn (pour payouts, stage bonuses and harvests; see Reward_Service). It is worked out on the server
	(FriendBoost_Service) and replicated to the client through two player attributes.

		PerFriend    bonus per friend, as a fraction: 0.10 = +10% (so 3 friends = x1.3)
		MaxFriends   (optional) friends counted at most, nil = no limit
]]

local FriendBoostConfig = {}

FriendBoostConfig.PerFriend = 0.10
FriendBoostConfig.MaxFriends = nil

-- player attributes written by the server, read by the client UI
FriendBoostConfig.FriendsAttribute = "FriendBoostFriends" -- how many friends are in the server
FriendBoostConfig.MultiplierAttribute = "FriendBoostMultiplier" -- coins multiplier, 1 = no bonus

--- Coins multiplier for a number of friends (1.3 for 3 friends).
function FriendBoostConfig.GetMultiplier(friends)
	local counted = FriendBoostConfig.MaxFriends and math.min(friends, FriendBoostConfig.MaxFriends) or friends
	return 1 + FriendBoostConfig.PerFriend * math.max(counted, 0)
end

--- The bonus as a whole percentage ("30" for 3 friends).
function FriendBoostConfig.GetPercent(friends)
	return math.floor((FriendBoostConfig.GetMultiplier(friends) - 1) * 100 + 0.5)
end

return FriendBoostConfig
