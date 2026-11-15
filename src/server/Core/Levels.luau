-- Account level: XP in, levels out. XP comes from time played (Core/Rewards), quests
-- (Core/SeasonPass.payQuests) and achievements (Core/AchievementRewards). Every level pays
-- Economy.levelUpGems; milestone levels (Economy.LevelMilestones) also pay Universal Coins,
-- Gems and a title. Pure, so it's unit tested.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Economy = require(ReplicatedStorage.Shared.Economy)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local Profile = require(script.Parent.Profile)
local Shop = require(script.Parent.Shop)

local Levels = {}

export type Result = {
	reached: { number }, -- new levels
	gems: number, -- Gems paid for them (level-up + milestones)
	universal: number, -- Universal Coins from milestones
	items: { string }, -- title items from milestones
	lines: { string }, -- milestone lines for a toast
}

-- Pays one milestone level's reward. Items already owned are skipped.
local function milestone(data: Profile.Data, level: number, result: Result)
	local reward = Economy.LevelMilestones[level]
	local key = `levelMilestone{level}`
	if not reward or data.grants[key] then
		return
	end
	data.grants[key] = true
	if reward.gems then
		result.gems += reward.gems
		table.insert(result.lines, `Level {level} bonus: +{reward.gems} {Economy.GemsName}`)
	end
	if reward.universal then
		Profile.addCoins(data, Economy.UniversalCoin.key, reward.universal)
		result.universal += reward.universal
		table.insert(result.lines, `Level {level} bonus: +{reward.universal} {Economy.UniversalCoin.name}`)
	end
	if reward.item and not data.owned[reward.item] then
		local item = ShopCatalog.get(reward.item)
		if item then
			Shop.grant(data, { reward.item })
			table.insert(result.items, reward.item)
			table.insert(result.lines, `Unlocked: {item.name}`)
		end
	end
end

-- Adds XP and pays everything for the levels it reaches.
function Levels.addXp(data: Profile.Data, xp: number): Result
	local result: Result = { reached = {}, gems = 0, universal = 0, items = {}, lines = {} }
	data.xp += math.max(0, math.floor(xp))
	while data.xp >= Economy.xpForLevel(data.level) do
		data.xp -= Economy.xpForLevel(data.level)
		data.level += 1
		table.insert(result.reached, data.level)
		result.gems += Economy.levelUpGems(data.level)
		milestone(data, data.level, result)
	end
	Profile.addGems(data, result.gems)
	return result
end

-- Milestones a profile already passed but never got (it levelled up before milestones
-- existed). Called when the profile loads; pays them once.
function Levels.catchUp(data: Profile.Data): Result
	local result: Result = { reached = {}, gems = 0, universal = 0, items = {}, lines = {} }
	for level in Economy.LevelMilestones do
		if level <= data.level then
			milestone(data, level, result)
		end
	end
	Profile.addGems(data, result.gems)
	return result
end

return Levels
