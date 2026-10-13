--[[
	Weighted plant selection. Pure logic, shared by the server (real roll)
	and the client (carousel filler cards + probability labels).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlantsConfig = require(ReplicatedStorage.SharedSource.Datas.PlantsConfig)

local PlantSelector = {}

local function buildEntries()
	local entries, total = {}, 0
	for plantId in pairs(PlantsConfig.Plants) do
		local weight = PlantsConfig.GetWeight(plantId)
		if weight > 0 then
			local rarity = PlantsConfig.GetRarity(plantId)
			table.insert(entries, { Id = plantId, Weight = weight, RarityOrder = rarity and rarity.Order or 0 })
			total += weight
		end
	end
	-- stable order: common first, then alphabetical
	table.sort(entries, function(a, b)
		if a.RarityOrder ~= b.RarityOrder then
			return a.RarityOrder < b.RarityOrder
		end
		return a.Id < b.Id
	end)
	for _, entry in ipairs(entries) do
		entry.Chance = entry.Weight / total
	end
	return entries, total
end

local entries, totalWeight = buildEntries()
local chances = {}
for _, entry in ipairs(entries) do
	chances[entry.Id] = entry.Chance
end

--- Ordered list of { Id, Weight, Chance, RarityOrder }.
function PlantSelector.GetEntries()
	return entries
end

--- Selection probability (0-1) of a plant.
function PlantSelector.GetChance(plantId)
	return chances[plantId] or 0
end

function PlantSelector.FormatChance(chance)
	local percent = chance * 100
	if percent >= 10 then
		return ("%d%%"):format(math.floor(percent + 0.5))
	end
	return ("%.1f%%"):format(percent)
end

--- Rolls a plant id according to the configured weights.
function PlantSelector.Roll(random)
	random = random or Random.new()
	local roll = random:NextNumber() * totalWeight
	for _, entry in ipairs(entries) do
		roll -= entry.Weight
		if roll < 0 then
			return entry.Id
		end
	end
	return entries[#entries].Id
end

--- Builds the carousel: `length` plant ids, weighted fillers, with `winnerId` at `winnerIndex` (1-based).
function PlantSelector.BuildReel(winnerId, length, winnerIndex, random)
	random = random or Random.new()
	local reel = table.create(length)
	for i = 1, length do
		reel[i] = PlantSelector.Roll(random)
	end
	reel[winnerIndex] = winnerId
	return reel
end

return PlantSelector
