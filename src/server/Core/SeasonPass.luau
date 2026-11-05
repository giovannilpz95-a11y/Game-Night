-- The Game Night Pass on a profile: Stars, tiers, claiming rewards, premium, weekly quests,
-- the premium bonus daily quest and the daily reroll. Pure (no services) so it's unit
-- tested in tests/Season.spec.luau; the numbers and the reward track are in shared/Season.
--
-- Rules we keep (Roblox's season pass guidance, vault "05 Research/Quests and Season Pass"):
--   * every reward is shown up front; nothing is random
--   * buying premium mid-season unlocks the premium rewards of tiers already reached
--   * rewards are claimed with a button, and anything left unclaimed when the season ends
--     is given automatically the next time the player is seen
--   * Stars only come from matches that pay rewards, so the anti-farm limits apply

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Season = require(ReplicatedStorage.Shared.Season)
local Economy = require(ReplicatedStorage.Shared.Economy)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local Profile = require(script.Parent.Profile)
local Quests = require(script.Parent.Quests)
local Weekly = require(script.Parent.Weekly)
local Shop = require(script.Parent.Shop)

local SeasonPass = {}

local function itemName(id: string): string?
	local item = ShopCatalog.get(id)
	return if item then item.name else nil
end
SeasonPass.itemName = itemName

local function key(tier: number): string
	return tostring(tier)
end

local function current(data: Profile.Data, now: number): boolean
	local n = Season.number(now)
	return n >= 1 and data.season.id == n
end

-- Gives one reward. An item the player already owns pays Universal Coins instead.
-- Returns a line for the reward toast.
function SeasonPass.grant(data: Profile.Data, reward: Season.Reward): string
	if reward.gems then
		Profile.addGems(data, reward.gems)
		return `+{reward.gems} {Economy.GemsName}`
	elseif reward.universal then
		Profile.addCoins(data, Economy.UniversalCoin.key, reward.universal)
		return `+{reward.universal} {Economy.UniversalCoin.name}`
	elseif reward.item then
		local item = ShopCatalog.get(reward.item)
		if item and data.owned[item.id] then
			local refund = Season.OwnedRefund[item.tier] or 100
			Profile.addCoins(data, Economy.UniversalCoin.key, refund)
			return `{item.name} (already yours): +{refund} {Economy.UniversalCoin.name}`
		end
		Shop.grant(data, { reward.item })
		return `Unlocked: {if item then item.name else reward.item}`
	end
	return ""
end

-- Tiers reached so far this season.
function SeasonPass.tier(data: Profile.Data): number
	return Season.tierFor(data.season.stars)
end

-- Rewards the player could claim right now: { { track, tier } }.
function SeasonPass.unclaimed(data: Profile.Data): { { track: string, tier: number } }
	local out = {}
	local track = Season.track(data.season.id)
	local reached = SeasonPass.tier(data)
	for tier = 1, reached do
		if track.free[tier] and not data.season.free[key(tier)] then
			table.insert(out, { track = "free", tier = tier })
		end
		if data.season.premium and track.premium[tier] and not data.season.paid[key(tier)] then
			table.insert(out, { track = "premium", tier = tier })
		end
	end
	return out
end

-- Claims one reward. Returns (ok, line or error).
function SeasonPass.claim(data: Profile.Data, now: number, trackName: any, tier: any): (boolean, string)
	if not current(data, now) then
		return false, "The season just changed. Try again."
	end
	if trackName ~= "free" and trackName ~= "premium" then
		return false, "Unknown reward"
	end
	if type(tier) ~= "number" or tier ~= math.floor(tier) or tier < 1 or tier > Season.Tiers then
		return false, "Unknown reward"
	end
	local track = Season.track(data.season.id)
	local reward = if trackName == "free" then track.free[tier] else track.premium[tier]
	if not reward then
		return false, "No reward on that tier"
	end
	if tier > SeasonPass.tier(data) then
		return false, `Reach tier {tier} first`
	end
	if trackName == "premium" and not data.season.premium then
		return false, "That reward is on the premium pass"
	end
	local claimed = if trackName == "free" then data.season.free else data.season.paid
	if claimed[key(tier)] then
		return false, "Already claimed"
	end
	claimed[key(tier)] = true
	return true, SeasonPass.grant(data, reward)
end

-- Claims everything waiting. Returns the toast lines.
function SeasonPass.claimAll(data: Profile.Data, now: number): { string }
	local lines = {}
	if not current(data, now) then
		return lines
	end
	for _, entry in SeasonPass.unclaimed(data) do
		local ok, line = SeasonPass.claim(data, now, entry.track, entry.tier)
		if ok then
			table.insert(lines, line)
		end
	end
	return lines
end

-- The premium pass's extra daily quest, if the player has premium and today's list
-- doesn't have it yet. Returns true if one was added.
function SeasonPass.addBonusQuest(data: Profile.Data, games: { Quests.GameInfo }, rng: Random): boolean
	if not data.season.premium then
		return false
	end
	local taken = {}
	for _, quest in data.daily.challenges do
		if quest.bonus then
			return false
		end
		taken[quest.id] = true
	end
	local quest = Quests.pickSmall(games, rng, taken)
	if not quest then
		return false
	end
	quest.bonus = true
	quest.stars = Season.BonusQuestStars
	table.insert(data.daily.challenges, quest)
	return true
end

-- Keeps the pass up to date: a new season (the old one's unclaimed rewards are given
-- automatically), a new week's quests, and the premium bonus quest for today. Call it
-- after Daily.roll. Returns the lines for the "season ended" toast (empty if none).
function SeasonPass.roll(data: Profile.Data, now: number, games: { Quests.GameInfo }, rng: Random): { string }
	local lines = {}
	local n = Season.number(now)
	if n < 1 then
		return lines
	end
	if data.season.id ~= n then
		if data.season.id >= 1 then
			-- Unclaimed rewards from the season that ended.
			local old = data.season
			local track = Season.track(old.id)
			for tier = 1, Season.tierFor(old.stars) do
				if track.free[tier] and not old.free[key(tier)] then
					table.insert(lines, SeasonPass.grant(data, track.free[tier]))
				end
				if old.premium and track.premium[tier] and not old.paid[key(tier)] then
					table.insert(lines, SeasonPass.grant(data, track.premium[tier]))
				end
			end
		end
		data.season = Profile.newSeason(n)
	end
	local week = Weekly.week(now)
	if data.season.weekly.week ~= week then
		data.season.weekly = { week = week, quests = Quests.makeWeekly(games, rng, (Season.track(n)).weekly) }
	end
	SeasonPass.addBonusQuest(data, games, rng)
	return lines
end

-- Adds Stars (doubled in the season's last week). Returns (Stars added, new tiers reached).
function SeasonPass.addStars(data: Profile.Data, now: number, amount: number): (number, { number })
	local reached = {}
	if not current(data, now) or amount <= 0 then
		return 0, reached
	end
	local multiplier = if Season.isFinalWeek(now) then Season.FinalWeekMultiplier else 1
	local added = math.floor(amount * multiplier + 0.5)
	local before = SeasonPass.tier(data)
	data.season.stars += added
	for tier = before + 1, SeasonPass.tier(data) do
		table.insert(reached, tier)
	end
	return added, reached
end

-- Stars for one rewarded match (before the final-week double).
function SeasonPass.matchStars(paidMinutes: number, won: boolean, vsBots: boolean, vip: boolean): number
	local stars = Season.StarsPerMinute * paidMinutes + (if won then Season.WinStars else 0)
	if vsBots then
		stars *= Season.BotRate
	end
	if vip then
		stars *= 1 + Season.VipStarBonus
	end
	return math.floor(stars + 0.5)
end

-- Counts a match toward this week's quests. Returns the ones it completed.
function SeasonPass.recordWeekly(data: Profile.Data, now: number, event: Quests.Event): { Profile.Challenge }
	if not current(data, now) or data.season.weekly.week ~= Weekly.week(now) then
		return {}
	end
	return Quests.progress(data.season.weekly.quests, event)
end

export type QuestResult = {
	completed: { string }, -- quest texts
	gems: number,
	stars: number,
	tiers: { number },
}

-- Pays the quests an event completed: their Gems and Stars.
function SeasonPass.payQuests(data: Profile.Data, now: number, quests: { Profile.Challenge }, gemMultiplier: number?): QuestResult
	local result = { completed = {}, gems = 0, stars = 0, tiers = {} }
	local stars = 0
	for _, quest in quests do
		table.insert(result.completed, quest.text)
		-- Daily quests saved before the pass have neither field: they paid the old Gems.
		local questGems = quest.gems or (if quest.stars == nil then Economy.ChallengeGems else 0)
		result.gems += math.floor(questGems * (gemMultiplier or 1) + 0.5)
		stars += quest.stars or 0
	end
	Profile.addGems(data, result.gems)
	result.stars, result.tiers = SeasonPass.addStars(data, now, stars)
	return result
end

-- A reaction sent at a table: counts toward "react" quests (daily and weekly).
function SeasonPass.recordReaction(data: Profile.Data, now: number): QuestResult
	local event: Quests.Event = { kind = "react" }
	local done = Quests.progress(data.daily.challenges, event)
	if current(data, now) and data.season.weekly.week == Weekly.week(now) then
		for _, quest in Quests.progress(data.season.weekly.quests, event) do
			table.insert(done, quest)
		end
	end
	return SeasonPass.payQuests(data, now, done)
end

-- Premium for this season (from Robux or Gems). Returns false if already premium.
function SeasonPass.setPremium(data: Profile.Data, now: number, games: { Quests.GameInfo }?, rng: Random?): boolean
	local n = Season.number(now)
	if n < 1 then
		return false
	end
	if data.season.id ~= n then
		data.season = Profile.newSeason(n)
	end
	if data.season.premium then
		return false
	end
	data.season.premium = true
	if games and rng and data.daily.day == Profile.today(now) then
		SeasonPass.addBonusQuest(data, games, rng)
	end
	return true
end

-- Buys premium with Gems. Returns (ok, error).
function SeasonPass.buyPremium(data: Profile.Data, now: number, games: { Quests.GameInfo }?, rng: Random?): (boolean, string?)
	if Season.number(now) < 1 then
		return false, "The first season hasn't started yet"
	end
	if current(data, now) and data.season.premium then
		return false, "You already have the premium pass"
	end
	local price = Season.Premium.gems
	if data.gems < price then
		return false, `You need {price - data.gems} more {Economy.GemsName}`
	end
	Profile.addGems(data, -price)
	SeasonPass.setPremium(data, now, games, rng)
	return true, nil
end

-- Skips `count` tiers for Gems. Returns (ok, error).
function SeasonPass.buyTiers(data: Profile.Data, now: number, count: any): (boolean, string?)
	if not current(data, now) then
		return false, "The season just changed. Try again."
	end
	if type(count) ~= "number" or count ~= math.floor(count) or count < 1 then
		return false, "Pick how many tiers"
	end
	local left = Season.Tiers - SeasonPass.tier(data)
	if left <= 0 then
		return false, "You've reached the last tier"
	end
	if count > left then
		return false, `Only {left} tiers left`
	end
	local price = count * Season.TierSkipGems
	if data.gems < price then
		return false, `You need {price - data.gems} more {Economy.GemsName}`
	end
	Profile.addGems(data, -price)
	data.season.stars = math.min(data.season.stars + count * Season.TierStars, Season.Tiers * Season.TierStars)
	return true, nil
end

-- Swaps one unfinished daily quest for another (once a day, free). Returns (ok, error).
function SeasonPass.reroll(data: Profile.Data, day: number, questId: any, games: { Quests.GameInfo }, rng: Random): (boolean, string?)
	if data.daily.day ~= day then
		return false, "A new day just started. Try again."
	end
	if data.season.rerollDay == day then
		return false, "You've used today's swap. New quests tomorrow!"
	end
	local index = nil
	local taken = {}
	for i, quest in data.daily.challenges do
		taken[quest.id] = true
		if quest.id == questId then
			index = i
		end
	end
	if not index then
		return false, "Unknown quest"
	end
	local old = data.daily.challenges[index]
	if old.done then
		return false, "That quest is already done"
	end
	local quest = Quests.pickSmall(games, rng, taken)
	if not quest then
		return false, "No other quests to swap in"
	end
	quest.gems = old.gems
	quest.stars = old.stars
	quest.bonus = old.bonus
	data.daily.challenges[index] = quest
	data.season.rerollDay = day
	return true, nil
end

-- What the 🎟️ Pass window needs (it reads the track and numbers from shared/Season).
function SeasonPass.view(data: Profile.Data, now: number): any
	local n = Season.number(now)
	local s = data.season
	local here = current(data, now)
	return {
		number = n,
		stars = if here then s.stars else 0,
		premium = here and s.premium,
		free = if here then s.free else {},
		paid = if here then s.paid else {},
		weekly = if here and s.weekly.week == Weekly.week(now) then s.weekly.quests else {},
		weekEndsAt = Weekly.endsAt(Weekly.week(now)),
		rerollUsed = s.rerollDay == Profile.today(now),
		unclaimed = if here then #SeasonPass.unclaimed(data) else 0,
		finalWeek = Season.isFinalWeek(now),
		now = now,
	}
end

return SeasonPass
