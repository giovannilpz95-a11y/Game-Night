local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local StatsCatalog = require(ReplicatedStorage.Shared.StatsCatalog)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local Achievements = require(ReplicatedStorage.Shared.Achievements)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Season = require(ReplicatedStorage.Shared.Season)
local Core = ServerScriptService.Server.Core
local Profile = require(Core.Profile)
local Stats = require(Core.Stats)
local Daily = require(Core.Daily)
local Rewards = require(Core.Rewards)
local Levels = require(Core.Levels)
local Quests = require(Core.Quests)
local SeasonPass = require(Core.SeasonPass)
local AchievementRewards = require(Core.AchievementRewards)

-- 2026-11-04 (a Wednesday) at noon UTC, in Season 1
local NOW = 1793793600
local DAY = math.floor(NOW / 86400)

return function(T)
	local function games()
		local out = {}
		for _, entry in GameCatalog.entries do
			if entry.status == "ready" then
				table.insert(out, { id = entry.id, name = entry.name, category = entry.category })
			end
		end
		return out
	end

	local function fresh()
		local data = Profile.new(NOW)
		Daily.roll(data, DAY, games(), T.Random.new(1))
		SeasonPass.roll(data, NOW, games(), T.Random.new(1))
		return data
	end

	local function info(overrides: any?)
		local out = { gameId = "Chess", won = false, isDraw = false, minutes = 10, vsHumans = true, now = NOW }
		for k, v in overrides or {} do
			out[k] = v
		end
		return out
	end

	local function ctx(overrides: any?)
		local out = {
			gameId = "Chess",
			coinKey = "chess",
			typicalMinutes = 15,
			minMinutes = 1,
			minMoves = 10,
			minutes = 10,
			moves = 40,
			won = true,
			isDraw = false,
			humanOpponents = { 99 },
			vip = false,
			now = NOW,
			category = "Strategy",
		}
		for k, v in overrides or {} do
			out[k] = v
		end
		return out
	end

	-- Data ----------------------------------------------------------------------------------

	T.test("every achievement reads a stat that exists, with 1 to 5 rising goals", function()
		local data = fresh()
		local view = Stats.view(data, false)
		for _, a in Achievements.list do
			T.ok(#a.goals >= 1 and #a.goals <= Achievements.MaxTier, `{a.id}: {#a.goals} tiers`)
			for i = 2, #a.goals do
				T.ok(a.goals[i] > a.goals[i - 1], `{a.id}: tier {i} goal must be bigger than tier {i - 1}`)
			end
			T.ok(a.goals[1] >= 1, `{a.id} goal`)
			T.ok(string.find(a.desc, "{n}", 1, true) ~= nil, `{a.id}: desc needs {"{n}"}`)
			local parts = string.split(a.stat, ".")
			if parts[1] == "games" then
				T.ok(GameCatalog.get(parts[2]) ~= nil, `{a.id}: unknown game {parts[2]}`)
				if parts[3] == "extra" then
					T.ok(StatsCatalog.def(parts[2], parts[4]) ~= nil, `{a.id}: {parts[2]} has no stat {parts[4]}`)
				elseif parts[3] == "bestScore" then
					T.ok(StatsCatalog.get(parts[2]).score ~= nil, `{a.id}: {parts[2]} keeps no score`)
				else
					T.ok(Stats.gameRow(fresh(), parts[2])[parts[3]] ~= nil, `{a.id}: no game stat {parts[3]}`)
				end
			elseif parts[1] == "totals" and (parts[2] == "winsBy" or parts[2] == "playsBy") then
				local used = false
				for _, entry in GameCatalog.entries do
					used = used or entry.category == parts[3]
				end
				T.ok(used, `{a.id}: no game has category {parts[3]}`)
			elseif #parts == 1 then
				T.ok(type(view[parts[1]]) == "number", `{a.id}: no stat {a.stat}`)
			else
				T.ok(type(view[parts[1]]) == "table" and type(view[parts[1]][parts[2]]) == "number", `{a.id}: no stat {a.stat}`)
			end
			if a.title then
				local item = ShopCatalog.get(a.title)
				T.ok(item ~= nil and item.notForSale and item.slot == "title", `{a.id}: title {a.title}`)
			end
		end
	end)

	T.test("every ready game has its own achievements, and there are general ones", function()
		for _, entry in GameCatalog.entries do
			if entry.status == "ready" then
				T.ok(#Achievements.forGame(entry.id) >= 3, `{entry.id} has achievements`)
				local item = ShopCatalog.get(Achievements.masteryTitle(entry.id))
				T.ok(item ~= nil and item.notForSale, `{entry.id} mastery title`)
			end
		end
		T.ok(#Achievements.general() >= 15)
		T.ok(Achievements.AllGames > 20, "Explorer's top tier needs more than 20 games")
	end)

	T.test("rewards grow every tier and stay within the economy", function()
		local r = Economy.AchievementRewards
		for _, list in { r.general.gems, r.general.xp, r.game.coins, r.game.xp, Achievements.TierPoints } do
			T.eq(#list, Achievements.MaxTier)
			for i = 2, #list do
				T.ok(list[i] > list[i - 1], "each tier pays more than the last")
			end
		end
		for i = 2, #r.game.gems do
			T.ok(r.game.gems[i] >= r.game.gems[i - 1])
		end
		-- Every Gem the achievements can ever pay (most players never reach Diamond).
		local total = 0
		for _, a in Achievements.list do
			local gems = if a.gameId then r.game.gems else r.general.gems
			for tier = 1, #a.goals do
				total += gems[tier]
			end
		end
		T.ok(total < 9000, `achievements pay {total} Gems in all`)
	end)

	-- Earning ---------------------------------------------------------------------------------

	T.test("tiers are earned as goals are reached, two at once pays both, never twice", function()
		local data = fresh()
		T.eq(#AchievementRewards.award(data, Stats.view(data, false), NOW).unlocks, 0)
		Stats.recordMatch(data, info({ won = true }))
		local gemsBefore = data.gems
		local coinsBefore = data.coins.chess or 0
		local result = AchievementRewards.award(data, Stats.view(data, false), NOW)
		local got = {}
		for _, unlock in result.unlocks do
			got[`{unlock.id}#{unlock.tier}`] = true
		end
		T.ok(got["matches#1"] and got["wins#1"] and got["human_wins#1"] and got["Chess.played#1"] and got["Chess.wins#1"])
		T.eq(data.coins.chess - coinsBefore, Economy.AchievementRewards.game.coins[1] * 2, "Chess Regular I + Chess Winner I pay Chess Coins")
		T.ok(data.gems > gemsBefore)
		T.eq(#AchievementRewards.award(data, Stats.view(data, false), NOW).unlocks, 0, "never twice")
		-- Ten more wins jump Chess Winner to tier 2.
		for _ = 1, 9 do
			Stats.recordMatch(data, info({ won = true }))
		end
		result = AchievementRewards.award(data, Stats.view(data, false), NOW)
		got = {}
		for _, unlock in result.unlocks do
			got[`{unlock.id}#{unlock.tier}`] = true
		end
		T.ok(got["Chess.wins#2"] and got["wins#2"] and got["Chess.played#2"])
		T.ok(got["Chess.winstreak#1"] and got["Chess.winstreak#2"] and got["Chess.winstreak#3"] and got["Chess.winstreak#4"], "several tiers at once")
		T.eq(Achievements.earnedTier(data.achievements, "Chess.winstreak"), 4)
	end)

	T.test("progress shows the next tier's goal", function()
		local data = fresh()
		for _ = 1, 4 do
			Stats.recordMatch(data, info({ won = true }))
		end
		local view = Stats.view(data, false)
		local a = Achievements.get("wins") :: any
		local value, goal, nextTier = Achievements.progress(view, a, 1)
		T.eq(value, 4)
		T.eq(goal, 10)
		T.eq(nextTier, 2)
		T.eq(Achievements.describe(Achievements.get("Chess.wins") :: any, 3), "Win 50 games in Chess")
		local _, top, none = Achievements.progress(view, Achievements.get("Hearts.moons") :: any, 4)
		T.eq(top, 25)
		T.eq(none, nil)
	end)

	T.test("the top tier pays its title; mastering a game pays its title once", function()
		local data = fresh()
		data.stats.wins = 1000
		local result = AchievementRewards.award(data, Stats.view(data, false), NOW)
		T.ok(data.owned.ach_title_legend, "Winner V pays Title: Legend")
		local titled = false
		for _, unlock in result.unlocks do
			titled = titled or (unlock.id == "wins" and unlock.tier == 5 and unlock.title == "Title: Legend")
		end
		T.ok(titled)
		-- Master Tic-Tac-Toe: every achievement of the game at Gold.
		local row = Stats.gameRow(data, "TicTacToe")
		row.played, row.wins, row.bestStreak = 50, 50, 5
		result = AchievementRewards.award(data, Stats.view(data, false), NOW)
		T.ok(Achievements.mastered(data.achievements, "TicTacToe"))
		T.ok(data.owned[Achievements.masteryTitle("TicTacToe")])
		local mastery = 0
		for _, unlock in result.unlocks do
			if unlock.mastery == "TicTacToe" then
				mastery += 1
			end
		end
		T.eq(mastery, 1)
		-- Masters count toward Master of Games.
		result = AchievementRewards.award(data, Stats.view(data, false), NOW)
		T.eq(Achievements.earnedTier(data.achievements, "mastered"), 1)
		T.eq(#AchievementRewards.award(data, Stats.view(data, false), NOW).unlocks, 0)
	end)

	T.test("old one-tier badges become tiers without paying again", function()
		local data = fresh()
		data.badges = { wins_50 = NOW - 100, chess_mate = NOW - 50, tried_5 = NOW }
		data.stats.wins = 60
		T.ok(AchievementRewards.migrate(data) > 0)
		T.eq(Achievements.earnedTier(data.achievements, "wins"), 3, "Win 50 = Winner III")
		T.eq(Achievements.earnedTier(data.achievements, "Chess.checkmates"), 1)
		T.eq(Achievements.earnedTier(data.achievements, "tried"), 1, "5 games covers Explorer I (3) only")
		T.eq(AchievementRewards.migrate(data), 0, "runs once")
		local result = AchievementRewards.award(data, Stats.view(data, false), NOW)
		for _, unlock in result.unlocks do
			T.ok(unlock.id ~= "wins", "wins tiers 1-3 were already paid")
		end
		-- Old saves get the new fields.
		local old = Profile.reconcile({ gems = 1, badges = { first_win = NOW } }, NOW)
		T.ok(old.achievements ~= nil and old.questStreak ~= nil and old.stats.quests.daily == 0)
	end)

	T.test("trophy score adds up tier points", function()
		local earned = { wins = { t = 2, at = NOW }, matches = { t = 1, at = NOW } }
		local points, badges, total = Achievements.score(earned)
		T.eq(points, Achievements.TierPoints[1] * 2 + Achievements.TierPoints[2])
		T.eq(badges, 3)
		T.ok(total > 300, `{total} badges in all`)
	end)

	-- Levels ----------------------------------------------------------------------------------

	T.test("level milestones pay titles and Universal Coins once; old levels catch up", function()
		local data = fresh()
		local need = 0
		for level = 1, 4 do
			need += Economy.xpForLevel(level)
		end
		local result = Levels.addXp(data, need)
		T.eq(data.level, 5)
		T.ok(data.owned.level_title_5)
		T.eq(result.universal, Economy.LevelMilestones[5].universal)
		T.eq(Profile.coins(data, Economy.UniversalCoin.key), Economy.LevelMilestones[5].universal)
		-- A profile that reached level 12 before milestones existed.
		local old = fresh()
		old.level = 12
		local caught = Levels.catchUp(old)
		T.ok(old.owned.level_title_5 and old.owned.level_title_10)
		T.eq(caught.universal, Economy.LevelMilestones[5].universal + Economy.LevelMilestones[10].universal)
		T.eq(#Levels.catchUp(old).lines, 0, "only once")
		for level, reward in Economy.LevelMilestones do
			if reward.item then
				local item = ShopCatalog.get(reward.item)
				T.ok(item ~= nil and item.notForSale and item.level == level, `level {level} item`)
			end
		end
		T.eq((Economy.nextLevelMilestone(5)), 10)
	end)

	-- Quests -----------------------------------------------------------------------------------

	T.test("stat and streak quests count the right things", function()
		local list = {
			Quests.make("a", "stat", 6, "Capture 6", { gameId = "Chess", stat = "captures" }),
			Quests.make("b", "streak", 2, "2 in a row"),
		}
		Quests.progress(list, { kind = "match", gameId = "Chess", won = true, extra = { captures = 4 } })
		T.eq(list[1].progress, 4)
		T.eq(list[2].progress, 1)
		Quests.progress(list, { kind = "match", gameId = "Checkers", won = false, isDraw = true, extra = { captures = 9 } })
		T.eq(list[1].progress, 4, "other games don't count")
		T.eq(list[2].progress, 1, "a draw keeps the streak")
		Quests.progress(list, { kind = "match", gameId = "Chess", won = false, extra = { captures = 0 / 0 } })
		T.eq(list[1].progress, 4, "NaN ignored")
		T.eq(list[2].progress, 0, "a loss starts it again")
		local done = Quests.progress(list, { kind = "match", gameId = "Chess", won = true, extra = { captures = 3 } })
		T.ok(list[1].done)
		T.eq(#done, 1)
	end)

	T.test("every game's quests use stats it reports", function()
		for gameId, goals in Quests.GameGoals do
			T.ok(GameCatalog.get(gameId) ~= nil, `{gameId} unknown`)
			for slot, spec in goals do
				T.ok(string.find(spec.text, "{game}", 1, true) ~= nil, `{gameId} {slot} text`)
				if spec.kind == "stat" then
					local def = StatsCatalog.def(gameId, spec.stat)
					T.ok(def ~= nil and def.kind == "sum", `{gameId} {slot}: {spec.stat} must be a sum stat`)
				end
			end
		end
	end)

	T.test("quests pay Stars and XP; finishing every daily quest pays the sweep", function()
		local data = fresh()
		data.daily.challenges = {
			Quests.make("q1", "play", 1, "Play 1", { gems = 5, stars = Season.DailyQuestStars, xp = Season.DailyQuestXp }),
			Quests.make("q2", "win", 1, "Win 1", { gems = 5, stars = Season.DailyQuestStars, xp = Season.DailyQuestXp }),
		}
		local levelBefore, xpBefore = data.level, data.xp
		local payout = Rewards.applyMatch(data, ctx({ won = false }))
		T.eq(#payout.challenges, 1)
		T.eq(payout.questXp, Season.DailyQuestXp)
		T.eq(#payout.sweeps, 0)
		payout = Rewards.applyMatch(data, ctx({ won = true }))
		T.eq(#payout.challenges, 1)
		T.eq(payout.questXp, Season.DailyQuestXp + Season.DailySweep.xp)
		T.eq(#payout.sweeps, 1)
		T.ok(data.daily.swept)
		T.eq(data.stats.quests.daily, 2)
		T.eq(data.stats.quests.dailySweeps, 1)
		T.eq(data.questStreak.count, 1)
		T.ok(data.level > levelBefore or data.xp > xpBefore)
		-- The next day's sweep makes a 2-day streak with extra Stars.
		data.daily = Profile.newDaily(DAY + 1)
		data.daily.challenges = { Quests.make("q3", "play", 1, "Play 1", { stars = 0, xp = 0 }) }
		local stars = data.season.stars
		local result = SeasonPass.payQuests(data, NOW, Quests.progress(data.daily.challenges, { kind = "match", gameId = "Chess" }))
		T.eq(result.streak, 2)
		T.eq(data.season.stars - stars, Season.DailySweep.stars + Season.DailySweepStreakStars)
		T.eq(Stats.view(data, false).totals.questsDone, 3)
	end)

	T.test("the weekly sweep pays once when all five weekly quests are done", function()
		local data = fresh()
		for _, quest in data.season.weekly.quests do
			if quest ~= data.season.weekly.quests[1] then
				quest.done = true
				quest.progress = quest.target
			end
		end
		local first = data.season.weekly.quests[1]
		first.progress = first.target - 1
		first.kind, first.gameId, first.category, first.humans = "play", nil, nil, nil
		local done = Quests.progress(data.season.weekly.quests, { kind = "match", gameId = "Chess" })
		local result = SeasonPass.payQuests(data, NOW, done)
		T.eq(result.sweeps[#result.sweeps], "weekly")
		T.ok(data.season.weekly.swept)
		T.eq(#SeasonPass.payQuests(data, NOW, {}).sweeps, 0)
	end)

	T.test("daily quests point at your games and pay XP; the week can hold a game quest", function()
		local data = fresh()
		for _ = 1, 5 do
			Stats.recordMatch(data, info({ gameId = "ColorClash" }))
		end
		local sawGoal = false
		for seed = 1, 30 do
			local list = Daily.makeChallenges(data, games(), T.Random.new(seed))
			T.eq(#list, Economy.ChallengesPerDay)
			for _, quest in list do
				T.eq(quest.xp, Season.DailyQuestXp)
				T.eq(quest.stars, Season.DailyQuestStars)
				sawGoal = sawGoal or quest.id == "goal_ColorClash" or quest.id == "win_ColorClash"
			end
		end
		T.ok(sawGoal, "the most played game gets its own quest")
		local sawWeeklyGoal = false
		for seed = 1, 60 do
			for _, quest in Quests.makeWeekly(games(), T.Random.new(seed), nil) do
				T.eq(quest.xp, Season.WeeklyQuestXp)
				sawWeeklyGoal = sawWeeklyGoal or string.sub(quest.id, 1, 6) == "wgoal_"
			end
		end
		T.ok(sawWeeklyGoal)
	end)
end
