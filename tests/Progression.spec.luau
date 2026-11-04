local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local StatsCatalog = require(ReplicatedStorage.Shared.StatsCatalog)
local Badges = require(ReplicatedStorage.Shared.Badges)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Chess = require(ReplicatedStorage.Shared.Games.Chess)
local Checkers = require(ReplicatedStorage.Shared.Games.Checkers)
local WordTiles = require(ReplicatedStorage.Shared.Games.WordTiles)
local Core = ServerScriptService.Server.Core
local Profile = require(Core.Profile)
local Stats = require(Core.Stats)
local Weekly = require(Core.Weekly)
local Rewards = require(Core.Rewards)
local Daily = require(Core.Daily)
local Match = require(Core.Match)

-- 2026-11-04 (a Wednesday) at noon UTC
local NOW = 1793793600
local DAY = math.floor(NOW / 86400)

return function(T)
	local function fresh()
		local data = Profile.new(NOW)
		Daily.roll(data, DAY, { { id = "Chess", name = "Chess" } }, T.Random.new(1))
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
		}
		for k, v in overrides or {} do
			out[k] = v
		end
		return out
	end

	-- Stats ---------------------------------------------------------------------------

	T.test("match stats: wins, losses, draws, streaks and fastest win", function()
		local data = fresh()
		Stats.recordMatch(data, info({ won = true, minutes = 12 }))
		Stats.recordMatch(data, info({ won = true, minutes = 8 }))
		Stats.recordMatch(data, info({ isDraw = true }))
		Stats.recordMatch(data, info({ won = true, vsHumans = false }))
		local row = data.stats.games.Chess
		T.eq(row.played, 4)
		T.eq(row.wins, 3)
		T.eq(row.draws, 1)
		T.eq(row.losses, 0)
		T.eq(row.streak, 3, "a draw keeps the streak")
		T.eq(row.fastestWin, 8)
		T.eq(row.humanWins, 2)
		Stats.recordMatch(data, info({}))
		T.eq(row.streak, 0)
		T.eq(row.bestStreak, 3)
		T.eq(data.stats.losses, 1)
		T.eq(data.stats.bestStreak, 3)
		T.eq(data.stats.humanMatches, 4)
		T.eq(data.stats.botMatches, 1)
		T.eq(data.stats.daysPlayed, 1)
		Stats.recordMatch(data, info({ now = NOW + 86400 }))
		T.eq(data.stats.daysPlayed, 2)
	end)

	T.test("game stats keep only catalog keys: sums add up, bests keep the max", function()
		local data = fresh()
		Stats.recordMatch(data, info({ gameId = "WordTiles", extra = { words = 5, bestWord = 30, junk = 99 }, score = 210 }))
		Stats.recordMatch(data, info({ gameId = "WordTiles", extra = { words = 7, bestWord = 12, bingos = -3 }, score = 180 }))
		Stats.recordMatch(data, info({ gameId = "WordTiles", extra = { words = 0 / 0, bestWord = "40" } }))
		local row = data.stats.games.WordTiles
		T.eq(row.extra.words, 12)
		T.eq(row.extra.bestWord, 30)
		T.eq(row.extra.junk, nil)
		T.eq(row.extra.bingos, nil, "negative values are ignored")
		T.eq(row.bestScore, 210)
	end)

	T.test("low-score games keep the lowest score; games without a score keep none", function()
		local data = fresh()
		Stats.recordMatch(data, info({ gameId = "Hearts", score = 60 }))
		Stats.recordMatch(data, info({ gameId = "Hearts", score = 25 }))
		Stats.recordMatch(data, info({ gameId = "War", score = 52 }))
		T.eq(data.stats.games.Hearts.bestScore, 25)
		T.eq(data.stats.games.War.bestScore, nil)
	end)

	T.test("old saves get the new stats, with losses worked out", function()
		local old = { gems = 3, stats = { matches = 10, wins = 4, minutes = 50, games = { Chess = { played = 6, wins = 2 } } } }
		local data = Profile.reconcile(old, NOW)
		T.eq(data.stats.losses, 6)
		T.eq(data.stats.currency.gemsEarned, 0)
		T.eq(data.stats.social.invitesSent, 0)
		T.ok(data.badges ~= nil and data.weekly ~= nil)
		local row = Stats.gameRow(data, "Chess")
		T.eq(row.losses, 4)
		T.eq(row.bestStreak, 0)
		T.ok(row.extra ~= nil)
	end)

	T.test("currency: earned, bought and spent are kept apart", function()
		local data = fresh()
		Stats.recordCurrency(data, { flow = "Source", currency = "Gems", amount = 5, transaction = "Gameplay" })
		Stats.recordCurrency(data, { flow = "Source", currency = "Gems", amount = 110, transaction = "IAP" })
		Stats.recordCurrency(data, { flow = "Sink", currency = "Gems", amount = 40, transaction = "Shop" })
		Stats.recordCurrency(data, { flow = "Source", currency = "chess", amount = 30, transaction = "Gameplay" })
		Stats.recordCurrency(data, { flow = "Sink", currency = "chess", amount = 20, transaction = "Shop" })
		Stats.recordCurrency(data, { flow = "Source", currency = "cards", amount = -5, transaction = "Gameplay" })
		local c = data.stats.currency
		T.eq(c.gemsEarned, 5)
		T.eq(c.gemsBought, 110)
		T.eq(c.gemsSpent, 40)
		T.eq(c.coinsEarned.chess, 30)
		T.eq(c.coinsSpent.chess, 20)
		T.eq(c.coinsEarned.cards, nil)
		local mine = Stats.view(data, true)
		T.eq(mine.currency.coinsEarned, 30)
		T.eq(mine.currency.coins.chess.spent, 20)
		local theirs = Stats.view(data, false)
		T.eq(theirs.currency.coins, nil, "other players don't see the wallet history")
		T.eq(theirs.currency.gemsBought, nil)
	end)

	T.test("social counters", function()
		local data = fresh()
		Stats.addSocial(data, "invitesSent")
		Stats.addSocial(data, "friendsJoined", 2)
		Stats.addSocial(data, "nonsense")
		T.eq(data.stats.social.invitesSent, 1)
		T.eq(data.stats.social.friendsJoined, 2)
		T.eq(data.stats.social.nonsense, nil)
	end)

	-- Weekly boards -------------------------------------------------------------------

	T.test("weeks start Monday 00:00 UTC", function()
		local week = Weekly.week(NOW)
		local monday = Weekly.startsAt(week)
		T.eq(os.date("!%A %H:%M", monday), "Monday 00:00")
		T.ok(monday <= NOW and NOW < Weekly.endsAt(week))
		T.eq(Weekly.week(monday - 1), week - 1)
		T.eq(Weekly.week(Weekly.endsAt(week)), week + 1)
	end)

	T.test("weekly points", function()
		T.eq(Weekly.points({ won = true, isDraw = false, vsHumans = true, rewarded = true, botCapped = false }), 3)
		T.eq(Weekly.points({ won = false, isDraw = true, vsHumans = true, rewarded = true, botCapped = false }), 1)
		T.eq(Weekly.points({ won = false, isDraw = false, vsHumans = true, rewarded = true, botCapped = false }), 0)
		T.eq(Weekly.points({ won = true, isDraw = false, vsHumans = false, rewarded = true, botCapped = false }), 1)
		T.eq(Weekly.points({ won = true, isDraw = false, vsHumans = false, rewarded = true, botCapped = true }), 0)
		T.eq(Weekly.points({ won = true, isDraw = false, vsHumans = true, rewarded = false, botCapped = false }), 0)
	end)

	T.test("a new week starts the points over", function()
		local data = fresh()
		Weekly.add(data, NOW, "Chess", 3)
		Weekly.add(data, NOW, "Hearts", 1)
		T.eq(data.weekly.points.Chess, 3)
		T.eq(data.weekly.points[Weekly.Overall], 4)
		Weekly.add(data, NOW + 7 * 86400, "Chess", 1)
		T.eq(data.weekly.points.Chess, 1)
		T.eq(data.weekly.points.Hearts, nil)
	end)

	T.test("ranking sorts by points, then user id", function()
		local rows = Weekly.rank({ { userId = 5, points = 3 }, { userId = 2, points = 9 }, { userId = 1, points = 3 } })
		T.eq(rows[1].userId, 2)
		T.eq(rows[2].userId, 1)
		T.eq(rows[3].rank, 3)
	end)

	T.test("match payouts add weekly points, except resigned, short and capped games", function()
		local data = fresh()
		local payout = Rewards.applyMatch(data, ctx())
		T.eq(payout.weeklyPoints, 3)
		T.eq(data.weekly.points.Chess, 3)
		T.eq(Rewards.applyMatch(data, ctx({ resigned = true })).weeklyPoints, 0)
		T.eq(Rewards.applyMatch(data, ctx({ moves = 2 })).weeklyPoints, 0)
		T.eq(Rewards.applyMatch(data, ctx({ won = false })).weeklyPoints, 0)
		-- Beating the same person again and again stops counting with the Coins.
		local again = 0
		for _ = 1, Economy.WinsVsSameHumanPerDay + 2 do
			again = Rewards.applyMatch(data, ctx({ humanOpponents = { 7 } })).weeklyPoints
		end
		T.eq(again, 0)
		-- Bot wins count until the daily bot limit.
		data.daily.botMatches = Economy.BotMatchesPerDay
		T.eq(Rewards.applyMatch(data, ctx({ humanOpponents = {} })).weeklyPoints, 0)
		T.eq(data.stats.games.Chess.played, 6 + Economy.WinsVsSameHumanPerDay + 2 - 1)
	end)

	T.test("payouts record the game's own stats and best score", function()
		local data = fresh()
		Rewards.applyMatch(data, ctx({ gameId = "WordTiles", coinKey = "wordtiles", extra = { words = 4 }, score = 150 }))
		T.eq(data.stats.games.WordTiles.extra.words, 4)
		T.eq(data.stats.games.WordTiles.bestScore, 150)
	end)

	-- Catalogs ------------------------------------------------------------------------

	T.test("every ready game has a stats entry, and every stats entry is a game", function()
		for _, entry in GameCatalog.entries do
			if entry.status == "ready" then
				T.ok(StatsCatalog.games[entry.id] ~= nil, `{entry.id} is missing from StatsCatalog`)
			end
		end
		for gameId, def in StatsCatalog.games do
			T.ok(GameCatalog.get(gameId) ~= nil, `{gameId} is not in GameCatalog`)
			local seen = {}
			for _, stat in def.extra or {} do
				T.ok(not seen[stat.key], `{gameId}.{stat.key} listed twice`)
				seen[stat.key] = true
				T.ok(stat.kind == "sum" or stat.kind == "max", `{gameId}.{stat.key} kind`)
			end
		end
	end)

	T.test("every badge reads a stat that exists", function()
		local data = fresh()
		local view = Stats.view(data, false)
		local ids = {}
		for _, badge in Badges.list do
			T.ok(not ids[badge.id], `duplicate badge {badge.id}`)
			ids[badge.id] = true
			T.ok(badge.tier >= 1 and badge.tier <= 3 and Economy.BadgeGems[badge.tier] ~= nil, `{badge.id} tier`)
			T.ok(badge.goal >= 1, `{badge.id} goal`)
			local parts = string.split(badge.stat, ".")
			if parts[1] == "games" then
				T.ok(GameCatalog.get(parts[2]) ~= nil, `{badge.id}: unknown game {parts[2]}`)
				if parts[3] == "extra" then
					T.ok(StatsCatalog.def(parts[2], parts[4]) ~= nil, `{badge.id}: {parts[2]} has no stat {parts[4]}`)
				else
					T.ok(Stats.gameRow(fresh(), parts[2])[parts[3]] ~= nil, `{badge.id}: no game stat {parts[3]}`)
				end
			elseif #parts == 1 then
				T.ok(type(view[parts[1]]) == "number", `{badge.id}: no stat {badge.stat}`)
			else
				T.ok(type(view[parts[1]]) == "table" and type(view[parts[1]][parts[2]]) == "number", `{badge.id}: no stat {badge.stat}`)
			end
		end
	end)

	T.test("badges are earned once their goal is reached", function()
		local data = fresh()
		T.eq(#Badges.newlyEarned(Stats.view(data, false), data.badges), 0)
		Stats.recordMatch(data, info({ won = true }))
		local earned = Badges.newlyEarned(Stats.view(data, false), data.badges)
		local names = {}
		for _, badge in earned do
			names[badge.id] = true
			data.badges[badge.id] = NOW
		end
		T.ok(names.first_game and names.first_win)
		T.eq(#Badges.newlyEarned(Stats.view(data, false), data.badges), 0, "never twice")
		T.eq(Badges.value(Stats.view(data, false), "games.Chess.wins"), 1)
		T.eq(Badges.value(Stats.view(data, false), "games.Nope.wins"), 0)
		local current, goal = Badges.progress(Stats.view(data, false), Badges.get("wins_10") :: any)
		T.eq(current, 1)
		T.eq(goal, 10)
	end)

	-- Games report their stats ----------------------------------------------------------

	T.test("chess reports checkmates and captures", function()
		local m = Match.new("m", Chess, { { kind = "player", userId = 1, name = "A" }, { kind = "player", userId = 2, name = "B" } }, nil, T.Random.new(1))
		for _, mv in { { 1, "f2", "f3" }, { 2, "e7", "e5" }, { 1, "g2", "g4" }, { 2, "d8", "h4" } } do
			T.ok(m:submitMove(mv[1], { from = mv[2], to = mv[3] }))
		end
		local stats = m:getMatchStats()
		T.eq(stats[2].checkmates, 1)
		T.eq(stats[1].checkmates, 0)
		T.eq(stats[1].captures, 0)
	end)

	T.test("checkers reports captures and kings from a bot game", function()
		local m = Match.new("m", Checkers, { { kind = "bot", name = "A" }, { kind = "bot", name = "B" } }, { botLevel = "easy" }, T.Random.new(3))
		local guard = 0
		while not m:isOver() and guard < 2000 do
			m:playForSeat(m:getActiveSeats()[1])
			guard += 1
		end
		local stats = m:getMatchStats()
		T.ok(stats[1].captures >= 0 and stats[1].captures <= 12)
		T.ok(stats[1].captures + stats[2].captures > 0)
		T.ok(m.result ~= nil)
	end)

	T.test("word tiles counts words played", function()
		local m = Match.new("m", WordTiles, { { kind = "bot", name = "A" }, { kind = "bot", name = "B" } }, { botLevel = "easy" }, T.Random.new(5))
		for _ = 1, 6 do
			if m:isOver() then
				break
			end
			m:playForSeat(m:getActiveSeats()[1])
		end
		local stats = m:getMatchStats()
		local words = (stats[1].words or 0) + (stats[2].words or 0)
		T.ok(words >= 0)
		for seat = 1, 2 do
			if stats[seat].words then
				T.ok(stats[seat].bestWord ~= nil and stats[seat].bestWord > 0)
			end
		end
	end)
end
