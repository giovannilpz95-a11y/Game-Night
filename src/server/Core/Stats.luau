-- Every stat Game Night keeps about a player: per-game records, overall totals, Gems and
-- Coins earned and spent, and party invites. Pure (no services) so it is unit tested.
--
-- Rewards.applyMatch calls recordMatch for each finished match; AnalyticsService calls
-- recordCurrency for every logged wallet change (so the stats always match analytics) and
-- addSocial for invites. view() builds what the stats profile window shows.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StatsCatalog = require(ReplicatedStorage.Shared.StatsCatalog)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)

local Stats = {}

export type GameRow = {
	played: number,
	wins: number,
	losses: number,
	draws: number,
	streak: number, -- current win streak (a draw keeps it, a loss resets it)
	bestStreak: number,
	minutes: number,
	humanWins: number, -- wins with at least one other person at the table
	fastestWin: number, -- minutes; 0 = no win yet
	bestScore: number?, -- only games with a `score` in StatsCatalog
	lastPlayed: number, -- os.time()
	extra: { [string]: number }, -- the game's own stats (StatsCatalog extra)
}

export type MatchInfo = {
	gameId: string,
	won: boolean,
	isDraw: boolean,
	minutes: number,
	vsHumans: boolean,
	extra: { [string]: any }?, -- what the game reported for this seat
	score: number?,
	now: number,
}

local function num(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return math.clamp(value, -StatsCatalog.MaxValue, StatsCatalog.MaxValue)
end

-- Fills in fields older saves don't have yet. Rows from before this module only had
-- played and wins, so their losses are a best guess (draws weren't counted).
function Stats.gameRow(data: any, gameId: string): GameRow
	local games = data.stats.games
	local row = games[gameId]
	if type(row) ~= "table" then
		row = { played = 0, wins = 0 }
		games[gameId] = row
	end
	row.played = row.played or 0
	row.wins = row.wins or 0
	if row.losses == nil then
		row.losses = math.max(0, row.played - row.wins)
	end
	row.draws = row.draws or 0
	row.streak = row.streak or 0
	row.bestStreak = row.bestStreak or 0
	row.minutes = row.minutes or 0
	row.humanWins = row.humanWins or 0
	row.fastestWin = row.fastestWin or 0
	row.lastPlayed = row.lastPlayed or 0
	row.extra = row.extra or {}
	return row
end

local function today(now: number): number
	return math.floor(now / 86400)
end

-- One finished match for one player. Counts every finished match, rewarded or not.
function Stats.recordMatch(data: any, info: MatchInfo)
	local stats = data.stats
	local row = Stats.gameRow(data, info.gameId)

	stats.matches += 1
	stats.minutes += info.minutes
	row.played += 1
	row.minutes += info.minutes
	row.lastPlayed = info.now

	if info.vsHumans then
		stats.humanMatches += 1
	else
		stats.botMatches += 1
	end

	if info.won then
		stats.wins += 1
		row.wins += 1
		row.streak += 1
		stats.streak += 1
		if info.vsHumans then
			stats.humanWins += 1
			row.humanWins += 1
		end
		if info.minutes > 0 and (row.fastestWin == 0 or info.minutes < row.fastestWin) then
			row.fastestWin = info.minutes
		end
	elseif info.isDraw then
		stats.draws += 1
		row.draws += 1
	else
		stats.losses += 1
		row.losses += 1
		row.streak = 0
		stats.streak = 0
	end
	row.bestStreak = math.max(row.bestStreak, row.streak)
	stats.bestStreak = math.max(stats.bestStreak, stats.streak)

	local day = today(info.now)
	if stats.lastDay ~= day then
		stats.lastDay = day
		stats.daysPlayed += 1
	end

	-- The game's own stats: only keys StatsCatalog lists, only sane numbers.
	local catalog = StatsCatalog.get(info.gameId)
	if type(info.extra) == "table" then
		for _, def in catalog.extra or {} do
			local value = num(info.extra[def.key])
			if value and value >= 0 then
				value = math.floor(value)
				local old = row.extra[def.key]
				if def.kind == "max" then
					row.extra[def.key] = math.max(old or 0, value)
				else
					row.extra[def.key] = (old or 0) + value
				end
			end
		end
	end
	local score = num(info.score)
	if catalog.score and score then
		score = math.floor(score)
		local best = row.bestScore
		if best == nil then
			row.bestScore = score
		elseif catalog.score.lower then
			row.bestScore = math.min(best, score)
		else
			row.bestScore = math.max(best, score)
		end
	end
end

-- One wallet change, as AnalyticsService logs it ({ flow, currency, amount, transaction }).
-- Robux Gem packs count as bought, not earned.
function Stats.recordCurrency(data: any, entry: { flow: string, currency: string, amount: number, transaction: string? })
	local amount = num(entry.amount)
	if not amount or amount <= 0 then
		return
	end
	amount = math.floor(amount)
	local currency = data.stats.currency
	if entry.currency == "Gems" then
		if entry.flow == "Sink" then
			currency.gemsSpent += amount
		elseif entry.transaction == "IAP" then
			currency.gemsBought += amount
		else
			currency.gemsEarned += amount
		end
	else
		local bucket = if entry.flow == "Sink" then currency.coinsSpent else currency.coinsEarned
		bucket[entry.currency] = (bucket[entry.currency] or 0) + amount
	end
end

-- Social counters: invitesSent, friendsJoined (people who joined your party from your
-- invite), partiesJoined (invites you accepted).
function Stats.addSocial(data: any, key: string, amount: number?)
	local social = data.stats.social
	if type(social[key]) == "number" then
		social[key] += amount or 1
	end
end

local function sum(map: { [string]: number }): number
	local total = 0
	for _, value in map do
		total += value
	end
	return total
end

-- What the stats window shows. `private` = false leaves out the wallet history (when
-- someone else looks at your profile).
function Stats.view(data: any, private: boolean): any
	local stats = data.stats
	local games = {}
	local tried = 0
	local cardWins = 0
	for gameId in stats.games do
		local row = Stats.gameRow(data, gameId)
		if row.played > 0 then
			tried += 1
		end
		local entry = GameCatalog.get(gameId)
		if entry and entry.coin == "cards" then
			cardWins += row.wins
		end
		local copy = table.clone(row)
		copy.extra = table.clone(row.extra)
		games[gameId] = copy
	end
	local view: any = {
		level = data.level,
		xp = data.xp,
		joined = data.createdAt,
		totals = {
			matches = stats.matches,
			wins = stats.wins,
			losses = stats.losses,
			draws = stats.draws,
			minutes = stats.minutes,
			streak = stats.streak,
			bestStreak = stats.bestStreak,
			humanMatches = stats.humanMatches,
			humanWins = stats.humanWins,
			botMatches = stats.botMatches,
			gamesTried = tried,
			cardWins = cardWins,
			daysPlayed = stats.daysPlayed,
			loginStreak = data.login.streak,
			bestLoginStreak = math.max(data.login.best or 0, data.login.streak),
		},
		social = table.clone(stats.social),
		games = games,
		badges = table.clone(data.badges),
		weekly = { week = data.weekly.week, points = table.clone(data.weekly.points) },
	}
	-- Totals are public (badges read them); the per-coin breakdown is yours only.
	local currency = stats.currency
	view.currency = {
		gemsEarned = currency.gemsEarned,
		gemsSpent = currency.gemsSpent,
		coinsEarned = sum(currency.coinsEarned),
		coinsSpent = sum(currency.coinsSpent),
	}
	if private then
		view.currency.gemsBought = currency.gemsBought
		view.currency.coins = {}
		for key, value in currency.coinsEarned do
			view.currency.coins[key] = { earned = value, spent = currency.coinsSpent[key] or 0 }
		end
		for key, value in currency.coinsSpent do
			view.currency.coins[key] = view.currency.coins[key] or { earned = 0, spent = value }
		end
	end
	return view
end

return Stats
