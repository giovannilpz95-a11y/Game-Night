-- Daily rewards: login streak and calendar, the day's three challenges, and resetting daily counters.
-- Pure: the day number, the list of games and the Random are passed in.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Economy = require(ReplicatedStorage.Shared.Economy)
local Season = require(ReplicatedStorage.Shared.Season)
local Profile = require(script.Parent.Profile)
local Quests = require(script.Parent.Quests)

local Daily = {}

export type GameInfo = Quests.GameInfo

-- Picks the day's quests:
--   1. something for any game: finish 3 games, play 20 minutes, win 2, or 2 different games
--   2. the game you play most: its own quest ("Capture 6 pieces in Chess") or a win in it
--   3. the game you've played least: "Try Checkers today"
-- Each pays Economy.ChallengeGems, Season.DailyQuestStars and Season.DailyQuestXp. (The
-- pass's bonus quest is added by Core/SeasonPass.)
function Daily.makeChallenges(data: Profile.Data, games: { GameInfo }, rng: Random): { Profile.Challenge }
	local challenges: { Profile.Challenge } = {}
	local general = {
		Quests.make("play3", "play", 3, "Finish 3 games"),
		Quests.make("d_minutes20", "minutes", 20, "Play for 20 minutes"),
		Quests.make("play3", "play", 3, "Finish 3 games"),
		Quests.make("d_win2any", "win", 2, "Win 2 games"),
		Quests.make("d_variety2any", "variety", 2, "Play 2 different games"),
	}
	table.insert(challenges, general[rng:NextInteger(1, #general)])

	if #games > 0 then
		local function played(info: GameInfo): number
			local s = data.stats.games[info.id]
			return if s then s.played else 0
		end

		-- Least played game (ties broken at random) gets the "try" quest, the most played
		-- one its own quest.
		local order = table.clone(games)
		for i = #order, 2, -1 do
			local j = rng:NextInteger(1, i)
			order[i], order[j] = order[j], order[i]
		end
		table.sort(order, function(a, b)
			return played(a) < played(b)
		end)
		local tryGame = order[1]
		local mainGame = order[#order]
		if #order > 1 and mainGame.id == tryGame.id then
			mainGame = order[2]
		end

		if Quests.GameGoals[mainGame.id] and rng:NextNumber() < 0.65 then
			table.insert(challenges, Quests.gameGoal(mainGame, "daily", "goal_"))
		else
			table.insert(challenges, Quests.make(`win_{mainGame.id}`, "win", 1, `Win a game of {mainGame.name}`, { gameId = mainGame.id }))
		end
		if tryGame.id ~= mainGame.id then
			table.insert(challenges, Quests.make(`try_{tryGame.id}`, "play", 1, `Try {tryGame.name} today: finish a game`, { gameId = tryGame.id }))
		end
	end
	while #challenges > Economy.ChallengesPerDay do
		table.remove(challenges)
	end
	for _, challenge in challenges do
		challenge.gems = Economy.ChallengeGems
		challenge.stars = Season.DailyQuestStars
		challenge.xp = Season.DailyQuestXp
	end
	return challenges
end

-- Starts a new day's counters and challenges if the day changed. Returns true if it did.
function Daily.roll(data: Profile.Data, day: number, games: { GameInfo }, rng: Random): boolean
	if data.daily.day == day then
		return false
	end
	data.daily = Profile.newDaily(day)
	data.daily.challenges = Daily.makeChallenges(data, games, rng)
	return true
end

export type LoginReward = {
	streak: number, -- days in a row, including today
	streakDay: number, -- position in Economy.DailyCalendar (1-7)
	gems: number, -- total Gems paid today (calendar + milestone)
	coins: number,
	coinKey: string?, -- which Coins, when coins > 0
	milestoneGems: number, -- part of `gems` from reaching a streak milestone
}

local function calendarDay(streak: number): number
	return ((math.max(streak, 1) - 1) % #Economy.DailyCalendar) + 1
end
Daily.calendarDay = calendarDay

-- Claims today's login reward if not claimed yet. Returns nil if it was already claimed.
-- Coin days pay Universal Coins. VIP doubles the calendar reward.
function Daily.login(data: Profile.Data, day: number, vip: boolean): LoginReward?
	local login = data.login
	if login.lastDay == day then
		return nil
	end
	login.streak = if login.lastDay == day - 1 then login.streak + 1 else 1
	login.lastDay = day
	login.best = math.max(login.best or 0, login.streak)

	local streakDay = calendarDay(login.streak)
	local entry = Economy.DailyCalendar[streakDay]
	local multiplier = if vip then Economy.VipDailyLoginMultiplier else 1
	local gems = (entry.gems or 0) * multiplier
	local coins = (entry.coins or 0) * multiplier
	local key = Economy.UniversalCoin.key
	local milestone = Economy.StreakMilestones[login.streak] or 0

	Profile.addGems(data, gems + milestone)
	if coins > 0 then
		Profile.addCoins(data, key, coins)
	end
	return {
		streak = login.streak,
		streakDay = streakDay,
		gems = gems + milestone,
		coins = coins,
		coinKey = if coins > 0 then key else nil,
		milestoneGems = milestone,
	}
end

-- Days until the next streak milestone and what it pays, or nil when none are left.
function Daily.nextMilestone(streak: number): (number?, number?)
	local bestAt = nil
	for at in Economy.StreakMilestones do
		if at > streak and (bestAt == nil or at < bestAt) then
			bestAt = at
		end
	end
	if bestAt == nil then
		return nil, nil
	end
	return bestAt - streak, Economy.StreakMilestones[bestAt]
end

-- Counts a finished match toward today's quests. Returns the quests it completed.
function Daily.recordMatch(data: Profile.Data, event: Quests.Event): { Profile.Challenge }
	return Quests.progress(data.daily.challenges, event)
end

return Daily
