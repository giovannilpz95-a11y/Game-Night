-- Daily rewards: login streak, the day's three challenges, and resetting daily counters.
-- Pure: the day number, the list of games and the Random are passed in.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Economy = require(ReplicatedStorage.Shared.Economy)
local Profile = require(script.Parent.Profile)

local Daily = {}

export type GameInfo = { id: string, name: string }

-- Picks the day's challenges: one "play any", one "win" in a game you play, and one that
-- points you at the game you've played least ("Try Checkers today").
function Daily.makeChallenges(data: Profile.Data, games: { GameInfo }, rng: Random): { Profile.Challenge }
	local challenges: { Profile.Challenge } = {}
	table.insert(challenges, {
		id = "play3",
		kind = "play",
		gameId = nil,
		target = 3,
		progress = 0,
		done = false,
		text = "Finish 3 games",
	})
	if #games == 0 then
		return challenges
	end

	local function played(info: GameInfo): number
		local s = data.stats.games[info.id]
		return if s then s.played else 0
	end

	-- Least played game (ties broken at random) gets the "try" challenge.
	local order = table.clone(games)
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	table.sort(order, function(a, b)
		return played(a) < played(b)
	end)
	local tryGame = order[1]
	local winGame = order[#order]
	if #order > 1 and winGame.id == tryGame.id then
		winGame = order[2]
	end

	table.insert(challenges, {
		id = `win_{winGame.id}`,
		kind = "win",
		gameId = winGame.id,
		target = 1,
		progress = 0,
		done = false,
		text = `Win a game of {winGame.name}`,
	})
	if tryGame.id ~= winGame.id then
		table.insert(challenges, {
			id = `try_{tryGame.id}`,
			kind = "play",
			gameId = tryGame.id,
			target = 1,
			progress = 0,
			done = false,
			text = `Try {tryGame.name} today: finish a game`,
		})
	end
	while #challenges > Economy.ChallengesPerDay do
		table.remove(challenges)
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

-- Claims today's login reward if not claimed yet. Returns the Gems given (0 if already
-- claimed) and the streak day (1-7).
function Daily.login(data: Profile.Data, day: number, vip: boolean): (number, number)
	local login = data.login
	if login.lastDay == day then
		return 0, ((login.streak - 1) % #Economy.DailyLoginGems) + 1
	end
	login.streak = if login.lastDay == day - 1 then login.streak + 1 else 1
	login.lastDay = day
	local streakDay = ((login.streak - 1) % #Economy.DailyLoginGems) + 1
	local gems = Economy.DailyLoginGems[streakDay]
	if vip then
		gems *= Economy.VipDailyLoginMultiplier
	end
	Profile.addGems(data, gems)
	return gems, streakDay
end

-- Counts a finished match toward today's challenges. Returns the challenges it completed.
function Daily.recordMatch(data: Profile.Data, gameId: string, won: boolean): { Profile.Challenge }
	local completed = {}
	for _, challenge in data.daily.challenges do
		if challenge.done then
			continue
		end
		if challenge.gameId ~= nil and challenge.gameId ~= gameId then
			continue
		end
		if challenge.kind == "win" and not won then
			continue
		end
		challenge.progress += 1
		if challenge.progress >= challenge.target then
			challenge.done = true
			table.insert(completed, challenge)
		end
	end
	return completed
end

return Daily
