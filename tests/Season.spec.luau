local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Season = require(ReplicatedStorage.Shared.Season)
local Economy = require(ReplicatedStorage.Shared.Economy)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local Reactions = require(ReplicatedStorage.Shared.Reactions)
local Showtime = require(ReplicatedStorage.Shared.Showtime)
local Core = ServerScriptService.Server.Core
local Profile = require(Core.Profile)
local Daily = require(Core.Daily)
local Rewards = require(Core.Rewards)
local Quests = require(Core.Quests)
local SeasonPass = require(Core.SeasonPass)
local Weekly = require(Core.Weekly)

local GAMES = {
	{ id = "Chess", name = "Chess", category = "Strategy" },
	{ id = "Checkers", name = "Checkers", category = "Strategy" },
	{ id = "Hearts", name = "Hearts", category = "Cards" },
	{ id = "Spades", name = "Spades", category = "Cards" },
}
local START = Season.Epoch + 3 * 86400 + 3600 -- Thursday of the first week, season 1
local U = Economy.UniversalCoin.key

return function(T)
	local function fresh(now: number?)
		local at = now or START
		local data = Profile.new(at)
		Daily.roll(data, Profile.today(at), GAMES, T.Random.new(1))
		SeasonPass.roll(data, at, GAMES, T.Random.new(2))
		return data
	end

	local function match(overrides: any?)
		local ctx = {
			gameId = "Chess",
			category = "Strategy",
			coinKey = "chess",
			typicalMinutes = 15,
			minMinutes = 1,
			minMoves = 10,
			minutes = 10,
			moves = 40,
			won = false,
			isDraw = false,
			humanOpponents = { 99 },
			vip = false,
			now = START,
		}
		for k, v in overrides or {} do
			ctx[k] = v
		end
		return ctx
	end

	-- Data checks ------------------------------------------------------------------

	T.test("seasons are 4 weeks, start on a Monday and line up with weekly quests", function()
		T.eq(Season.Days % 7, 0)
		T.eq(Weekly.startsAt(Weekly.week(Season.Epoch)), Season.Epoch, "season 1 starts when a week starts")
		T.eq(Season.number(Season.Epoch - 1), 0)
		T.eq(Season.number(Season.Epoch), 1)
		T.eq(Season.number(Season.endsAt(1) - 1), 1)
		T.eq(Season.number(Season.endsAt(1)), 2)
		T.ok(not Season.isFinalWeek(START))
		T.ok(Season.isFinalWeek(Season.endsAt(1) - 3600))
	end)

	T.test("later seasons rerun the last track until a new one is written", function()
		local track, rerun = Season.track(#Season.Tracks + 1)
		T.eq(track, Season.Tracks[#Season.Tracks])
		T.ok(rerun)
		local first, firstRerun = Season.track(1)
		T.eq(first, Season.Tracks[1])
		T.ok(not firstRerun)
	end)

	T.test("every track is complete and its items are real, pass-only shop items", function()
		for n, track in Season.Tracks do
			for tier = 1, Season.Tiers do
				T.ok(track.premium[tier] ~= nil, `season {n}: premium tier {tier} is empty`)
			end
			for _, list in { track.free, track.premium } do
				for tier, reward in list do
					T.ok(tier >= 1 and tier <= Season.Tiers, `season {n}: tier {tier} out of range`)
					local kinds = (if reward.gems then 1 else 0) + (if reward.universal then 1 else 0) + (if reward.item then 1 else 0)
					T.eq(kinds, 1, `season {n} tier {tier}: one reward each`)
					if reward.item then
						local item = ShopCatalog.get(reward.item)
						T.ok(item ~= nil, `{reward.item} is not in the shop catalog`)
						if item then
							T.ok(item.notForSale == true, `{item.id} is a pass reward, never sold`)
							T.ok(item.season ~= nil, `{item.id} needs its season`)
							T.eq(item.shop, "hub", item.id)
						end
					end
				end
			end
		end
		-- Every season item is on a track, so nothing is unobtainable.
		local onTrack = {}
		for _, track in Season.Tracks do
			for _, list in { track.free, track.premium } do
				for _, reward in list do
					if reward.item then
						onTrack[reward.item] = true
					end
				end
			end
		end
		for _, item in ShopCatalog.items do
			if item.season then
				T.ok(onTrack[item.id], `{item.id} isn't on any track`)
			end
		end
	end)

	T.test("pass rewards hook into reactions and Showtime", function()
		T.ok(Reactions.pack("reactions_premiere") ~= nil)
		T.ok(#(Reactions.pack("reactions_premiere") :: any).reactions >= 6)
		T.eq(Showtime.kind("pose_spotlight"), "pose")
		T.eq(Showtime.kind("pose_redcarpet"), "pose")
		T.eq(Showtime.kind("win_showstopper"), "victory")
		T.ok(not ShopCatalog.isFree("win_showstopper"))
		T.ok(table.find(Economy.ReactionBundle.items, "reactions_premiere") == nil, "not in the Robux bundle")
	end)

	T.test("premium pays back fewer Gems than it costs", function()
		local track = Season.Tracks[1]
		local premiumGems = 0
		for _, reward in track.premium do
			premiumGems += reward.gems or 0
		end
		T.ok(premiumGems < Season.Premium.gems, `{premiumGems} Gems back vs {Season.Premium.gems}`)
	end)

	T.test("a regular player finishes the track in a season, a casual one gets halfway", function()
		-- Active: about 45 minutes of rewarded play on 6 days a week, all daily and weekly quests.
		local perDay = 4.5 * SeasonPass.matchStars(10, false, false, false) + 2 * Season.WinStars + 3 * Season.DailyQuestStars
		local active = 24 * perDay + 4 * Season.WeeklyQuests * Season.WeeklyQuestStars
		T.ok(Season.tierFor(active) >= Season.Tiers - 2, `active player reaches {Season.tierFor(active)}`)
		-- Casual: 20 minutes on 3 days a week, two daily quests, three weekly quests a week.
		local casual = 12 * (2 * SeasonPass.matchStars(10, false, false, false) + 2 * Season.DailyQuestStars) + 4 * 3 * Season.WeeklyQuestStars
		local tier = Season.tierFor(casual)
		T.ok(tier >= 10 and tier < Season.Tiers, `casual player reaches {tier}`)
	end)

	-- Quests -----------------------------------------------------------------------

	T.test("quest kinds count the right things", function()
		local list = {
			Quests.make("a", "play", 2, "Play 2", { category = "Cards" }),
			Quests.make("b", "win", 1, "Win 1", { humans = true }),
			Quests.make("c", "minutes", 20, "20 min"),
			Quests.make("d", "variety", 2, "2 games"),
			Quests.make("e", "react", 2, "React"),
		}
		Quests.progress(list, { kind = "match", gameId = "Chess", category = "Strategy", won = true, minutes = 12, vsHumans = false })
		T.eq(list[1].progress, 0, "wrong category")
		T.eq(list[2].progress, 0, "needs people")
		T.eq(list[3].progress, 12)
		T.eq(list[4].progress, 1)
		Quests.progress(list, { kind = "match", gameId = "Chess", category = "Strategy", won = true, minutes = 12, vsHumans = true })
		T.eq(list[2].progress, 1)
		T.ok(list[2].done and list[3].done)
		T.eq(list[3].progress, 20, "capped at the target")
		T.eq(list[4].progress, 1, "same game twice is one")
		local done = Quests.progress(list, { kind = "match", gameId = "Hearts", category = "Cards", won = false, minutes = 5, vsHumans = false })
		T.eq(list[1].progress, 1)
		T.ok(list[4].done)
		T.eq(#done, 1)
		Quests.progress(list, { kind = "react" })
		Quests.progress(list, { kind = "react" })
		T.ok(list[5].done)
		T.eq(list[1].progress, 1, "reactions don't count as games")
	end)

	T.test("daily quests pay Gems and Stars; the week gets five mixed quests", function()
		local data = fresh()
		for _, quest in data.daily.challenges do
			T.eq(quest.gems, Economy.ChallengeGems)
			T.eq(quest.stars, Season.DailyQuestStars)
		end
		T.eq(#data.season.weekly.quests, Season.WeeklyQuests)
		local ids = {}
		for _, quest in data.season.weekly.quests do
			T.ok(not ids[quest.id], "no duplicates")
			ids[quest.id] = true
			T.eq(quest.stars, Season.WeeklyQuestStars)
		end
		T.ok(ids.w_play15)
	end)

	T.test("a new week brings new weekly quests, the same week keeps progress", function()
		local data = fresh()
		data.season.weekly.quests[1].progress = 3
		SeasonPass.roll(data, START + 3600, GAMES, T.Random.new(5))
		T.eq(data.season.weekly.quests[1].progress, 3)
		SeasonPass.roll(data, START + 7 * 86400, GAMES, T.Random.new(5))
		T.eq(data.season.weekly.week, Weekly.week(START + 7 * 86400))
		T.eq(data.season.weekly.quests[1].progress, 0)
	end)

	T.test("one free reroll a day swaps an unfinished daily quest", function()
		local data = fresh()
		local day = Profile.today(START)
		local first = data.daily.challenges[1]
		local ok = SeasonPass.reroll(data, day, first.id, GAMES, T.Random.new(9))
		T.ok(ok)
		T.ok(data.daily.challenges[1].id ~= first.id)
		T.eq(data.daily.challenges[1].gems, Economy.ChallengeGems, "keeps the reward")
		T.eq(data.daily.challenges[1].stars, Season.DailyQuestStars)
		T.ok(not SeasonPass.reroll(data, day, data.daily.challenges[2].id, GAMES, T.Random.new(9)), "once a day")
		T.ok(not SeasonPass.reroll(data, day, "nope", GAMES, T.Random.new(9)))
	end)

	-- Stars and tiers --------------------------------------------------------------

	T.test("matches give Stars; quests add theirs; tiers come up in the payout", function()
		local data = fresh()
		local payout = Rewards.applyMatch(data, match({ won = true }))
		T.ok(payout.stars >= 10 * 10 + Season.WinStars)
		T.eq(data.season.stars, payout.stars)
		local loss = Rewards.applyMatch(data, match({ gameId = "Spades", category = "Cards" }))
		T.eq(loss.stars, 10 * 10, "a loss with no quest done: just the minutes")
		-- Finishing three games completes "Finish 3 games" (+200 Stars, +5 Gems).
		local third = Rewards.applyMatch(data, match())
		T.ok(table.find(third.challenges, "Finish 3 games") ~= nil)
		T.ok(third.stars >= 100 + Season.DailyQuestStars)
		local lines = Rewards.describe(third)
		local found = false
		for _, line in lines do
			if string.find(line, "Pass Stars", 1, true) then
				found = true
			end
		end
		T.ok(found, "the results screen shows Stars")
	end)

	T.test("resigned, too short and past-the-limit matches give no match Stars", function()
		local data = fresh()
		T.eq(Rewards.applyMatch(data, match({ resigned = true })).stars, 0)
		T.eq(Rewards.applyMatch(data, match({ moves = 2 })).stars, 0)
		data.daily.botMatches = Economy.BotMatchesPerDay
		T.eq(Rewards.applyMatch(data, match({ humanOpponents = {} })).stars, 0)
	end)

	T.test("bots give half, VIP a quarter more, the final week doubles", function()
		T.eq(SeasonPass.matchStars(10, false, true, false), 50)
		T.eq(SeasonPass.matchStars(10, false, false, true), 125)
		local late = Season.endsAt(1) - 3 * 86400
		local data = fresh(late)
		local added = SeasonPass.addStars(data, late, 100)
		T.eq(added, 200)
	end)

	T.test("weekly quests complete from matches", function()
		local data = fresh()
		for _, quest in data.season.weekly.quests do
			if quest.id == "w_play15" then
				quest.progress = 14
			end
		end
		local payout = Rewards.applyMatch(data, match())
		T.ok(table.find(payout.weeklyQuests, "Finish 15 games") ~= nil)
		T.ok(payout.stars >= Season.WeeklyQuestStars)
	end)

	-- Claiming ---------------------------------------------------------------------

	T.test("claim free rewards you've reached, once", function()
		local data = fresh()
		T.ok(not (SeasonPass.claim(data, START, "free", 1)), "tier 1 not reached")
		SeasonPass.addStars(data, START, Season.TierStars * 5)
		local ok, line = SeasonPass.claim(data, START, "free", 1)
		T.ok(ok, line)
		T.eq(Profile.coins(data, U), 100)
		T.ok(not (SeasonPass.claim(data, START, "free", 1)), "only once")
		T.ok(not (SeasonPass.claim(data, START, "free", 2)), "tier 2 has no free reward")
		T.ok(not (SeasonPass.claim(data, START, "premium", 1)), "premium needs the pass")
		T.ok(not (SeasonPass.claim(data, START, "free", 0 / 0)))
		T.ok(not (SeasonPass.claim(data, START, "free", 1.5)))
		T.ok(not (SeasonPass.claim(data, START, "bogus", 1)))
		local lines = SeasonPass.claimAll(data, START)
		T.eq(#lines, 2, "tiers 3 and 5")
		T.ok(data.owned.season1_title_opening)
		T.eq(#SeasonPass.unclaimed(data), 0)
	end)

	T.test("buying premium mid-season unlocks the premium tiers already reached", function()
		local data = fresh()
		SeasonPass.addStars(data, START, Season.TierStars * 10)
		T.ok(not SeasonPass.buyPremium(data, START), "not enough Gems")
		Profile.addGems(data, Season.Premium.gems)
		T.ok(SeasonPass.buyPremium(data, START, GAMES, T.Random.new(3)))
		T.eq(data.gems, 0)
		T.ok(not SeasonPass.buyPremium(data, START), "only once a season")
		T.eq(#SeasonPass.unclaimed(data), 10 + 6) -- 10 premium + free tiers 1,3,5,7,9,10
		SeasonPass.claimAll(data, START)
		T.ok(data.owned.season1_chair_velvet)
		T.ok(data.owned.pose_redcarpet)
		T.ok(data.owned.pose_spotlight)
	end)

	T.test("premium adds a bonus daily quest", function()
		local data = fresh()
		local before = #data.daily.challenges
		SeasonPass.setPremium(data, START, GAMES, T.Random.new(4))
		T.eq(#data.daily.challenges, before + 1)
		local bonus = data.daily.challenges[before + 1]
		T.ok(bonus.bonus)
		T.eq(bonus.stars, Season.BonusQuestStars)
		T.ok(not SeasonPass.addBonusQuest(data, GAMES, T.Random.new(4)), "only one")
		-- And it comes back the next day.
		local tomorrow = START + 86400
		Daily.roll(data, Profile.today(tomorrow), GAMES, T.Random.new(1))
		SeasonPass.roll(data, tomorrow, GAMES, T.Random.new(1))
		local found = false
		for _, quest in data.daily.challenges do
			found = found or quest.bonus == true
		end
		T.ok(found)
	end)

	T.test("tier skips cost Gems and stop at the last tier", function()
		local data = fresh()
		Profile.addGems(data, 1000)
		T.ok(SeasonPass.buyTiers(data, START, 2))
		T.eq(SeasonPass.tier(data), 2)
		T.eq(data.gems, 1000 - 2 * Season.TierSkipGems)
		T.ok(not SeasonPass.buyTiers(data, START, 0))
		T.ok(not SeasonPass.buyTiers(data, START, Season.Tiers), "past the end")
		data.season.stars = Season.Tiers * Season.TierStars
		T.ok(not SeasonPass.buyTiers(data, START, 1))
	end)

	T.test("an item you already own pays Universal Coins instead", function()
		local data = fresh()
		data.owned.season1_title_opening = true
		local line = SeasonPass.grant(data, { item = "season1_title_opening" })
		T.eq(Profile.coins(data, U), Season.OwnedRefund.Common)
		T.ok(string.find(line, "already", 1, true) ~= nil)
	end)

	T.test("a new season gives last season's unclaimed rewards and starts fresh", function()
		local data = fresh()
		data.season.premium = true
		SeasonPass.addStars(data, START, Season.TierStars * 2)
		SeasonPass.claim(data, START, "free", 1)
		local nextSeason = Season.endsAt(1) + 3600
		Daily.roll(data, Profile.today(nextSeason), GAMES, T.Random.new(1))
		local lines = SeasonPass.roll(data, nextSeason, GAMES, T.Random.new(1))
		T.eq(#lines, 2, "premium 1 and 2; free 1 was claimed")
		T.ok(data.owned.season1_chair_velvet)
		T.eq(data.season.id, 2)
		T.eq(data.season.stars, 0)
		T.ok(not data.season.premium)
		T.eq(#SeasonPass.roll(data, nextSeason, GAMES, T.Random.new(1)), 0, "only once")
	end)

	T.test("old saves get the pass, and old daily quests still pay their Gems", function()
		local data: any = Profile.new(START)
		data.season = nil
		data.daily = Profile.newDaily(Profile.today(START))
		data.daily.challenges = { { id = "play3", kind = "play", target = 1, progress = 0, done = false, text = "Finish 3 games" } }
		data = Profile.reconcile(data, START)
		T.eq(data.season.id, 0)
		SeasonPass.roll(data, START, GAMES, T.Random.new(1))
		T.eq(data.season.id, 1)
		local payout = Rewards.applyMatch(data, match())
		T.eq(payout.gems >= Economy.ChallengeGems, true)
	end)

	T.test("the view for the Pass window", function()
		local data = fresh()
		local view = SeasonPass.view(data, START)
		T.eq(view.number, 1)
		T.eq(#view.weekly, Season.WeeklyQuests)
		T.eq(view.unclaimed, 0)
		T.ok(not view.premium)
		T.ok(not view.rerollUsed)
	end)
end
