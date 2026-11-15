-- Awards achievement tiers (shared/Achievements) and pays them: Gems for general ones, the
-- game's Coins for a game's own (plus Gems from Gold up), account XP for every tier, a title
-- at the top tier of some, and a mastery title when every achievement of a game reaches
-- Gold. Pure (no services): ProgressionService passes the profile and its stats view.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Achievements = require(ReplicatedStorage.Shared.Achievements)
local Economy = require(ReplicatedStorage.Shared.Economy)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local Profile = require(script.Parent.Profile)
local Shop = require(script.Parent.Shop)
local Levels = require(script.Parent.Levels)

local AchievementRewards = {}

export type Unlock = {
	id: string, -- achievement id
	tier: number,
	name: string, -- "Chess · Winner"
	icon: string,
	desc: string, -- what this tier asked for
	reward: string, -- "+250 Chess Coins · +5 Gems · +200 XP"
	roblox: number?, -- Roblox badge to award, if this tier has one
	mastery: string?, -- a game id when this is a mastery moment instead of a tier
	title: string?, -- title item name it unlocked
}

export type Result = {
	unlocks: { Unlock },
	gems: number,
	coins: { [string]: number },
	xp: number,
	items: { string },
	levels: Levels.Result,
}

-- Marks the tiers an old one-tier badge covered as earned, without paying them again
-- (those badges already paid). Runs once per profile; returns how many tiers it marked.
function AchievementRewards.migrate(data: Profile.Data): number
	if data.grants.achievementsMigrated then
		return 0
	end
	data.grants.achievementsMigrated = true
	local marked = 0
	for badgeId, at in data.badges do
		local legacy = Achievements.Legacy[badgeId]
		if not legacy then
			continue
		end
		local stat, goal = legacy[1], legacy[2]
		for _, a in Achievements.withStat(stat) do
			local tier = Achievements.tierFor(a, goal)
			if tier > Achievements.earnedTier(data.achievements, a.id) then
				marked += tier - Achievements.earnedTier(data.achievements, a.id)
				data.achievements[a.id] = { t = tier, at = if type(at) == "number" then at else 0 }
			end
		end
	end
	return marked
end

local function coinKeyFor(gameId: string): string
	local entry = GameCatalog.get(gameId)
	return if entry and entry.coin then entry.coin else Economy.DefaultCoin
end

local function rewardText(gems: number, coins: number, coinKey: string?, xp: number): string
	local parts = {}
	if coins > 0 and coinKey then
		table.insert(parts, `+{Achievements.commas(coins)} {Economy.coinName(coinKey)}`)
	end
	if gems > 0 then
		table.insert(parts, `+{gems} {Economy.GemsName}`)
	end
	if xp > 0 then
		table.insert(parts, `+{xp} XP`)
	end
	return table.concat(parts, " · ")
end

local function grantTitle(data: Profile.Data, itemId: string?, result: Result): string?
	if not itemId or data.owned[itemId] then
		return nil
	end
	local item = ShopCatalog.get(itemId)
	if not item then
		return nil
	end
	Shop.grant(data, { itemId })
	table.insert(result.items, itemId)
	return item.name
end

-- Awards every tier `view` reaches that the profile doesn't have, and pays them. `view`
-- is Core/Stats.view(data). Call again after a level-up (achievement XP can reach a "Level
-- Up" tier): ProgressionService loops until nothing new is earned.
function AchievementRewards.award(data: Profile.Data, view: any, now: number): Result
	local result: Result = { unlocks = {}, gems = 0, coins = {}, xp = 0, items = {}, levels = Levels.addXp(data, 0) }
	local rewards = Economy.AchievementRewards
	for _, earned in Achievements.newlyEarned(view, data.achievements) do
		local a, tier = earned.achievement, earned.tier
		data.achievements[a.id] = { t = tier, at = now }
		local gems, coins, coinKey, xp
		if a.gameId then
			gems = rewards.game.gems[tier] or 0
			coins = rewards.game.coins[tier] or 0
			coinKey = coinKeyFor(a.gameId)
			xp = rewards.game.xp[tier] or 0
		else
			gems = rewards.general.gems[tier] or 0
			coins = 0
			xp = rewards.general.xp[tier] or 0
		end
		result.gems += gems
		result.xp += xp
		if coins > 0 and coinKey then
			result.coins[coinKey] = (result.coins[coinKey] or 0) + coins
		end
		local title = if tier == #a.goals then grantTitle(data, a.title, result) else nil
		table.insert(result.unlocks, {
			id = a.id,
			tier = tier,
			name = Achievements.fullName(a),
			icon = a.icon,
			desc = Achievements.describe(a, tier),
			reward = rewardText(gems, coins, coinKey, xp),
			roblox = a.roblox and a.roblox[tier] or nil,
			title = title,
		})
	end
	-- Mastery: every achievement of a game at Gold (checked after the tiers above).
	for _, entry in GameCatalog.entries do
		local key = `mastery_{entry.id}`
		if entry.status == "ready" and not data.grants[key] and Achievements.mastered(data.achievements, entry.id) then
			data.grants[key] = true
			local m = rewards.mastery
			result.gems += m.gems
			result.xp += m.xp
			local title = grantTitle(data, Achievements.masteryTitle(entry.id), result)
			table.insert(result.unlocks, {
				id = key,
				tier = Achievements.MasteryTier,
				name = `{entry.name} Master`,
				icon = "🎓",
				desc = `Every {entry.name} achievement at Gold`,
				reward = rewardText(m.gems, 0, nil, m.xp),
				mastery = entry.id,
				title = title,
			})
		end
	end
	Profile.addGems(data, result.gems)
	for key, amount in result.coins do
		Profile.addCoins(data, key, amount)
	end
	result.levels = Levels.addXp(data, result.xp)
	return result
end

return AchievementRewards
