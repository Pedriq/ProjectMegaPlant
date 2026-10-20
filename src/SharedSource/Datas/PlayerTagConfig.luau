--[[
	The billboard above every player (see PlayerTag_Controller), top to bottom:
	  1. [plant icon] number        plants the player has grown (the "Plants Grown" stat)
	  2. Nickname [+]               display name, with the Roblox Plus badge after it if the player is subscribed
	  3. Title                      a rank from how many plants they have grown, in colors from plain to legendary

	Titles: the highest entry whose `Min` the player has reached. THE NUMBERS ARE PLACEHOLDERS (to be balanced).
		Min        plants grown needed
		Name       the title shown
		Colors     the gradient of the title text, left to right (one color = flat)
		Animated   (optional) true = the gradient slowly spins (the top tier)
	The colors follow the plant rarities: plain -> green -> teal -> blue -> purple -> gold -> red-pink -> rainbow.
]]

local PlayerTagConfig = {}

PlayerTagConfig.Titles = {
	{ Min = 0, Name = "Seedling", Colors = { Color3.fromRGB(205, 210, 205), Color3.fromRGB(160, 168, 160) } },
	{ Min = 3, Name = "Sprout", Colors = { Color3.fromRGB(176, 226, 120), Color3.fromRGB(120, 196, 92) } },
	{ Min = 10, Name = "Gardener", Colors = { Color3.fromRGB(96, 214, 120), Color3.fromRGB(46, 160, 84) } },
	{ Min = 25, Name = "Botanist", Colors = { Color3.fromRGB(96, 226, 200), Color3.fromRGB(40, 170, 160) } },
	{ Min = 50, Name = "Green Thumb", Colors = { Color3.fromRGB(110, 190, 255), Color3.fromRGB(70, 120, 240) } },
	{ Min = 100, Name = "Plant Whisperer", Colors = { Color3.fromRGB(205, 140, 255), Color3.fromRGB(140, 90, 235) } },
	{ Min = 200, Name = "Bloom Master", Colors = { Color3.fromRGB(255, 226, 110), Color3.fromRGB(255, 168, 40) } },
	{ Min = 400, Name = "Harvest Legend", Colors = { Color3.fromRGB(255, 130, 150), Color3.fromRGB(255, 70, 110), Color3.fromRGB(255, 176, 90) } },
	{
		Min = 800,
		Name = "Megaplant Titan",
		Animated = true,
		Colors = {
			Color3.fromRGB(255, 110, 140),
			Color3.fromRGB(255, 190, 70),
			Color3.fromRGB(110, 230, 150),
			Color3.fromRGB(100, 170, 255),
			Color3.fromRGB(190, 120, 255),
			Color3.fromRGB(255, 110, 140),
		},
	},
}

-- the Roblox Plus badge: put the id of a real icon here ("rbxassetid://123"); while it is empty a gold "+" is drawn
PlayerTagConfig.PlusIconImage = ""

-- the tag disappears beyond this many studs, and fades a little before that
PlayerTagConfig.MaxDistance = 90

--- The title entry for a number of plants, and its index in `Titles`.
function PlayerTagConfig.GetTitle(plants)
	local best, bestIndex = PlayerTagConfig.Titles[1], 1
	for index, title in ipairs(PlayerTagConfig.Titles) do
		if plants >= title.Min then
			best, bestIndex = title, index
		end
	end
	return best, bestIndex
end

--- A ColorSequence evenly spread over a title's colors.
function PlayerTagConfig.GetColorSequence(title)
	local colors = title.Colors
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keypoints = {}
	for index, color in ipairs(colors) do
		table.insert(keypoints, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(keypoints)
end

return PlayerTagConfig
