-- Works out and pays what one player earns from one finished match: that game's Coins,
-- first-win-of-the-day Gems, XP and level-ups, and daily challenge Gems.
-- Pure: every input is in `ctx`, so the numbers are unit tested.
--
-- Games never hand out currency themselves; they declare typicalMinutes, minMinutes and
-- minMoves in GameCatalog and this module does the math.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Economy = require(ReplicatedStorage.Shared.Economy)
local Profile = require(script.Parent.Profile)
local Daily = require(script.Parent.Daily)
local Stats = require(script.Parent.Stats)
local Weekly = require(script.Parent.Weekly)

local Rewards = {}

export type MatchContext = {
	gameId: string,
	coinKey: string,
	typicalMinutes: number,
	minMinutes: number,
	minMoves: number,
	minutes: number, -- how long the match lasted
	moves: number, -- moves made by everyone
	won: boolean,
	isDraw: boolean,
	resigned: boolean?, -- this player gave up: no Coins, Gems, XP or challenge progress
	humanOpponents: { number }, -- user ids of the other humans at the table
	vip: boolean,
	extra: { [string]: any }?, -- the game's own stats for this seat (StatsCatalog)
	score: number?, -- this seat's final score, for games with getScores
	now: number?, -- os.time(); stats and the weekly board use it
}

export type Payout = {
	coinKey: string,
	coins: number,
	gems: number,
	xp: number,
	levelUps: { number }, -- new levels reached
	challenges: { string }, -- texts of challenges completed
	notes: { string }, -- why something was reduced ("Daily bot reward limit reached")
	weeklyPoints: number, -- added to this week's leaderboards (Core/Weekly)
}

local function round(x: number): number
	return math.floor(x + 0.5)
end

-- Adds XP and pays Gems for each level reached. Returns the new levels.
function Rewards.addXp(data: Profile.Data, xp: number): ({ number }, number)
	data.xp += math.max(0, math.floor(xp))
	local reached = {}
	local gems = 0
	while data.xp >= Economy.xpForLevel(data.level) do
		data.xp -= Economy.xpForLevel(data.level)
		data.level += 1
		table.insert(reached, data.level)
		gems += Economy.levelUpGems(data.level)
	end
	Profile.addGems(data, gems)
	return reached, gems
end

function Rewards.applyMatch(data: Profile.Data, ctx: MatchContext): Payout
	local payout: Payout = {
		coinKey = ctx.coinKey,
		coins = 0,
		gems = 0,
		xp = 0,
		levelUps = {},
		challenges = {},
		notes = {},
		weeklyPoints = 0,
	}
	local now = ctx.now or os.time()
	local daily = data.daily
	local vsBots = #ctx.humanOpponents == 0
	local playMultiplier = if ctx.vip then 1 + Economy.VipPlayBonus else 1

	-- Stats count every finished match, rewarded or not.
	Stats.recordMatch(data, {
		gameId = ctx.gameId,
		won = ctx.won,
		isDraw = ctx.isDraw,
		minutes = ctx.minutes,
		vsHumans = not vsBots,
		extra = ctx.extra,
		score = ctx.score,
		now = now,
	})
	Weekly.current(data, now)

	-- Win streaks: a loss resets, a draw keeps it.
	local streak = data.winStreak[ctx.coinKey] or 0
	if ctx.won then
		streak += 1
	elseif not ctx.isDraw then
		streak = 0
	end
	data.winStreak[ctx.coinKey] = streak

	if ctx.resigned then
		table.insert(payout.notes, "Resigned games don't earn rewards")
		return payout
	end
	if ctx.minutes < ctx.minMinutes or ctx.moves < ctx.minMoves then
		table.insert(payout.notes, "Too short for rewards")
		return payout
	end

	-- Coins
	local coinsAllowed = true
	if vsBots then
		daily.botMatches += 1
		if daily.botMatches > Economy.BotMatchesPerDay then
			coinsAllowed = false
			table.insert(payout.notes, "Daily bot reward limit reached. Play with friends for more!")
		end
	end
	if ctx.won and #ctx.humanOpponents == 1 then
		local key = tostring(ctx.humanOpponents[1])
		daily.winsVs[key] = (daily.winsVs[key] or 0) + 1
		if daily.winsVs[key] > Economy.WinsVsSameHumanPerDay then
			coinsAllowed = false
			table.insert(payout.notes, "No more rewards for beating the same player today")
		end
	end

	payout.weeklyPoints = Weekly.points({
		won = ctx.won,
		isDraw = ctx.isDraw,
		vsHumans = not vsBots,
		rewarded = coinsAllowed, -- the anti-farm limits above count here too
		botCapped = vsBots and daily.botMatches > Economy.BotMatchesPerDay,
	})
	Weekly.add(data, now, ctx.gameId, payout.weeklyPoints)

	local paidMinutes = math.min(ctx.minutes, ctx.typicalMinutes * Economy.MaxMinutesFactor)
	if coinsAllowed then
		local multiplier = 1
		if ctx.won then
			multiplier += Economy.WinBonus
			multiplier += math.min(Economy.StreakBonusMax, Economy.StreakBonusPerWin * (streak - 1))
		end
		if vsBots then
			multiplier *= Economy.BotRate
		end
		multiplier *= playMultiplier
		multiplier *= Economy.CoinMultipliers[ctx.coinKey] or 1
		payout.coins = math.max(1, round(Economy.CoinsPerMinute * paidMinutes * multiplier))
		Profile.addCoins(data, ctx.coinKey, payout.coins)
	end

	-- Gems: first win of the day, then challenges
	local gems = 0
	if ctx.won and not daily.firstWin then
		daily.firstWin = true
		gems += round(Economy.FirstWinGems * playMultiplier)
	end
	for _, challenge in Daily.recordMatch(data, ctx.gameId, ctx.won) do
		gems += round(Economy.ChallengeGems * playMultiplier)
		table.insert(payout.challenges, challenge.text)
	end
	Profile.addGems(data, gems)

	-- XP from time played; level-ups pay Gems too
	payout.xp = math.max(1, round(Economy.XpPerMinute * paidMinutes))
	local levels, levelGems = Rewards.addXp(data, payout.xp)
	payout.levelUps = levels
	payout.gems = gems + levelGems

	return payout
end

-- Short lines for the results screen: { "+40 Chess Coins", "+5 Gems", ... }
function Rewards.describe(payout: Payout): { string }
	local lines = {}
	if payout.coins > 0 then
		table.insert(lines, `+{payout.coins} {Economy.coinName(payout.coinKey)}`)
	end
	if payout.gems > 0 then
		table.insert(lines, `+{payout.gems} {Economy.GemsName}`)
	end
	for _, level in payout.levelUps do
		table.insert(lines, `Level up! You're level {level}`)
	end
	for _, text in payout.challenges do
		table.insert(lines, `Challenge done: {text}`)
	end
	if payout.weeklyPoints > 0 then
		table.insert(lines, `+{payout.weeklyPoints} weekly leaderboard points`)
	end
	for _, note in payout.notes do
		table.insert(lines, note)
	end
	return lines
end

return Rewards
