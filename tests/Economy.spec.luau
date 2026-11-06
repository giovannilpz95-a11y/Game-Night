local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Economy = require(ReplicatedStorage.Shared.Economy)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local Core = ServerScriptService.Server.Core
local Profile = require(Core.Profile)
local Daily = require(Core.Daily)
local Rewards = require(Core.Rewards)
local Shop = require(Core.Shop)
local SessionLock = require(Core.SessionLock)

local DAY = 20000
local GAMES = {
	{ id = "Chess", name = "Chess" },
	{ id = "Checkers", name = "Checkers" },
	{ id = "TicTacToe", name = "Tic-Tac-Toe" },
}

return function(T)
	local function fresh()
		local data = Profile.new(DAY * 86400)
		Daily.roll(data, DAY, GAMES, T.Random.new(1))
		return data
	end

	local function chessMatch(overrides: any?)
		local ctx = {
			gameId = "Chess",
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
		}
		for k, v in overrides or {} do
			ctx[k] = v
		end
		return ctx
	end

	-- Profiles ------------------------------------------------------------------

	T.test("reconcile fills fields missing from older saves and keeps balances", function()
		local old = { gems = 42, coins = { chess = 7 }, stats = { matches = 3 } }
		local data = Profile.reconcile(old, 0)
		T.eq(data.gems, 42)
		T.eq(data.coins.chess, 7)
		T.eq(data.stats.matches, 3)
		T.eq(data.stats.wins, 0)
		T.ok(data.daily ~= nil and data.login ~= nil and data.receipts ~= nil)
		T.eq(data.version, Profile.Version)
	end)

	T.test("balances never go negative or fractional", function()
		local data = fresh()
		Profile.addGems(data, 10.9)
		T.eq(data.gems, 10)
		Profile.addGems(data, -50)
		T.eq(data.gems, 0)
		Profile.addCoins(data, "chess", -5)
		T.eq(Profile.coins(data, "chess"), 0)
	end)

	T.test("receipts are remembered and capped", function()
		local data = fresh()
		for i = 1, Profile.MaxReceipts + 5 do
			Profile.addReceipt(data, `p{i}`)
		end
		T.eq(#data.receipts, Profile.MaxReceipts)
		T.ok(Profile.hasReceipt(data, `p{Profile.MaxReceipts + 5}`))
		T.ok(not Profile.hasReceipt(data, "p1"))
	end)

	-- Daily -----------------------------------------------------------------------

	T.test("login calendar pays its 7 days, then repeats, and resets after a missed day", function()
		local data = fresh()
		local gems, coins = 0, 0
		for d = 1, 7 do
			local reward = Daily.login(data, DAY + d, false)
			T.ok(reward ~= nil)
			T.eq(reward.streakDay, d)
			T.eq(reward.streak, d)
			gems += reward.gems
			coins += reward.coins
			if reward.coins > 0 then
				T.eq(reward.coinKey, Economy.UniversalCoin.key)
			end
		end
		local wantGems, wantCoins = 0, 0
		for _, entry in Economy.DailyCalendar do
			wantGems += entry.gems or 0
			wantCoins += entry.coins or 0
		end
		T.eq(gems, wantGems)
		T.eq(coins, wantCoins)
		T.eq(data.gems, wantGems)
		T.eq(data.coins[Economy.UniversalCoin.key], wantCoins)
		T.eq(Daily.login(data, DAY + 7, false), nil, "same day pays once")
		local day8 = Daily.login(data, DAY + 8, false)
		T.eq(day8.streak, 8)
		T.eq(day8.streakDay, 1, "calendar repeats")
		local again = Daily.login(data, DAY + 10, false)
		T.eq(again.streak, 1, "missed a day")
		T.eq(again.streakDay, 1)
		T.eq(data.login.best, 8)
	end)

	T.test("VIP doubles the calendar reward", function()
		local data = fresh()
		local reward = Daily.login(data, DAY, true)
		T.eq(reward.coins, (Economy.DailyCalendar[1].coins or 0) * Economy.VipDailyLoginMultiplier)
		local day2 = Daily.login(data, DAY + 1, true)
		T.eq(day2.gems, (Economy.DailyCalendar[2].gems or 0) * Economy.VipDailyLoginMultiplier)
	end)

	T.test("streak milestones pay extra Gems once, on the day they're reached", function()
		local data = fresh()
		local milestoneDays = {}
		for at in Economy.StreakMilestones do
			table.insert(milestoneDays, at)
		end
		table.sort(milestoneDays)
		local first = milestoneDays[1]
		local paid = 0
		for d = 1, first + 1 do
			local reward = Daily.login(data, DAY + d, false)
			if reward.milestoneGems > 0 then
				T.eq(reward.streak, first)
				paid += reward.milestoneGems
			end
		end
		T.eq(paid, Economy.StreakMilestones[first])
		local inDays, gems = Daily.nextMilestone(first)
		T.eq(inDays, milestoneDays[2] - first)
		T.eq(gems, Economy.StreakMilestones[milestoneDays[2]])
		T.eq((Daily.nextMilestone(100000)), nil)
	end)

	T.test("Universal Coins turn into any game's Coins, one way", function()
		local data = fresh()
		local U = Economy.UniversalCoin.key
		T.eq(Economy.Coins[U], nil, "not a game coin, so no shop of its own")
		Profile.addCoins(data, U, 100)
		T.ok(Shop.convertUniversal(data, "chess", 60))
		T.eq(Profile.coins(data, U), 40)
		T.eq(Profile.coins(data, "chess"), 60)
		T.ok(not Shop.convertUniversal(data, "chess", 41), "not more than you have")
		T.ok(not Shop.convertUniversal(data, U, 10), "can't convert into itself")
		T.ok(not Shop.convertUniversal(data, "nope", 10))
		T.ok(not Shop.convertUniversal(data, "chess", 0))
		T.ok(not Shop.convertUniversal(data, "chess", 1.5))
		T.ok(not Shop.convertUniversal(data, "chess", 0 / 0))
		T.ok(not Shop.convertUniversal(data, "chess", "10"))
		T.eq(Profile.coins(data, U), 40)
		T.eq(Profile.coins(data, "chess"), 60)
		T.eq(Economy.coinName(U), Economy.UniversalCoin.name)
	end)

	T.test("reaction packs can be bought with Universal Coins", function()
		local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
		local U = Economy.UniversalCoin.key
		local priced = 0
		for _, item in ShopCatalog.items do
			if item.slot == "reactions" and not item.notForSale then
				T.ok(item.universal ~= nil, `{item.id} has no Universal price`)
				priced += 1
			end
		end
		T.ok(priced > 0)
		local data = fresh()
		Profile.addCoins(data, U, 1499)
		T.ok(not Shop.buy(data, "reactions_party", "universal", false), "not enough")
		Profile.addCoins(data, U, 1)
		T.ok(Shop.buy(data, "reactions_party", "universal", false))
		T.eq(Profile.coins(data, U), 0)
		T.ok(data.owned.reactions_party)
		T.ok(not Shop.buy(data, "hub_neon_table", "universal", false), "only items with a Universal price")
	end)

	T.test("three challenges, one of them a game you haven't played", function()
		local data = fresh()
		data.stats.games.Chess = { played = 10, wins = 2 }
		data.stats.games.TicTacToe = { played = 5, wins = 1 }
		Daily.roll(data, DAY + 1, GAMES, T.Random.new(3))
		T.eq(#data.daily.challenges, Economy.ChallengesPerDay)
		local try = data.daily.challenges[3]
		T.eq(try.gameId, "Checkers")
		T.eq(data.daily.challenges[2].gameId, "Chess")
	end)

	T.test("a new day resets daily counters", function()
		local data = fresh()
		data.daily.firstWin = true
		data.daily.botMatches = 12
		T.ok(Daily.roll(data, DAY + 1, GAMES, T.Random.new(1)))
		T.eq(data.daily.firstWin, false)
		T.eq(data.daily.botMatches, 0)
		T.eq((Daily.roll(data, DAY + 1, GAMES, T.Random.new(1))), false)
	end)

	-- Match rewards -----------------------------------------------------------------

	T.test("a 10 minute chess loss vs a human pays 50 coins and 100 XP", function()
		local data = fresh()
		local payout = Rewards.applyMatch(data, chessMatch())
		T.eq(payout.coins, 50)
		T.eq(Profile.coins(data, "chess"), 50)
		T.eq(payout.xp, 100)
		T.eq(data.level, 2, "100 XP reaches level 2")
		T.eq(data.stats.games.Chess.played, 1)
	end)

	T.test("a win pays +50% and the first win of the day pays Gems", function()
		local data = fresh()
		local payout = Rewards.applyMatch(data, chessMatch({ won = true }))
		T.eq(payout.coins, 75)
		T.ok(payout.gems >= Economy.FirstWinGems)
		T.ok(data.daily.firstWin)
		local second = Rewards.applyMatch(data, chessMatch({ won = true, humanOpponents = { 98 } }))
		T.eq(second.coins, 80, "second win in a row gets +10% streak: 50 * 1.6")
		T.eq(#second.levelUps + #second.challenges, 0)
		T.eq(second.gems, 0, "first-win Gems only once a day")
	end)

	T.test("streak bonus is capped at +50%", function()
		local data = fresh()
		data.winStreak.chess = 20
		local payout = Rewards.applyMatch(data, chessMatch({ won = true, humanOpponents = { 7 } }))
		T.eq(payout.coins, 100) -- 50 * (1 + 0.5 + 0.5)
	end)

	T.test("long matches only pay up to 1.5x the typical length", function()
		local data = fresh()
		local payout = Rewards.applyMatch(data, chessMatch({ minutes = 90 }))
		T.eq(payout.coins, math.floor(5 * 22.5 + 0.5))
	end)

	T.test("bot matches pay half and stop after the daily limit", function()
		local data = fresh()
		local payout = Rewards.applyMatch(data, chessMatch({ humanOpponents = {} }))
		T.eq(payout.coins, 25)
		data.daily.botMatches = Economy.BotMatchesPerDay
		local capped = Rewards.applyMatch(data, chessMatch({ humanOpponents = {} }))
		T.eq(capped.coins, 0)
		T.ok(#capped.notes > 0)
	end)

	T.test("too-short matches pay nothing", function()
		local data = fresh()
		local payout = Rewards.applyMatch(data, chessMatch({ won = true, moves = 4 }))
		T.eq(payout.coins, 0)
		T.eq(payout.gems, 0)
		T.eq(data.daily.firstWin, false)
	end)

	T.test("a player who let bots and the turn timer play for them earns nothing", function()
		local data = fresh()
		local idle = Rewards.applyMatch(data, chessMatch({ won = true, ownMoves = 0 }))
		T.eq(idle.coins + idle.gems + idle.xp + idle.stars, 0)
		T.eq(data.daily.firstWin, false)
		-- Trivia asks for 3 answers of your own; 2 isn't enough, 3 is.
		local trivia = { gameId = "TriviaNight", coinKey = "party", typicalMinutes = 8, minMinutes = 1, minMoves = 5, minOwnMoves = 3, minutes = 4, moves = 40, won = true, isDraw = false, humanOpponents = {}, vip = false }
		trivia.ownMoves = 2
		T.eq(Rewards.applyMatch(data, trivia).coins, 0)
		trivia.ownMoves = 3
		T.ok(Rewards.applyMatch(data, trivia).coins > 0, "3 answers pay")
		-- Callers that don't count own moves (nil) are not checked.
		T.ok(Rewards.applyMatch(fresh(), chessMatch({ won = true })).coins > 0)
	end)

	T.test("resigning earns no Coins, Gems, XP or challenge progress", function()
		local data = fresh()
		for _ = 1, 5 do
			local payout = Rewards.applyMatch(data, chessMatch({ resigned = true }))
			T.eq(payout.coins + payout.gems + payout.xp, 0)
			T.eq(#payout.challenges + #payout.levelUps, 0)
		end
		T.eq(data.gems, 0)
		T.eq(data.xp, 0)
		for _, challenge in data.daily.challenges do
			T.eq(challenge.progress, 0, challenge.text)
		end
		T.eq(data.stats.games.Chess.played, 5, "still counted as played")
	end)

	T.test("matches under the minimum don't count toward challenges or XP", function()
		local data = fresh()
		for _ = 1, 5 do
			Rewards.applyMatch(data, chessMatch({ minutes = 0.5 }))
		end
		T.eq(data.xp, 0)
		for _, challenge in data.daily.challenges do
			T.eq(challenge.progress, 0, challenge.text)
		end
	end)

	T.test("beating the same human more than 3 times a day stops paying", function()
		local data = fresh()
		for _ = 1, Economy.WinsVsSameHumanPerDay do
			T.ok(Rewards.applyMatch(data, chessMatch({ won = true, humanOpponents = { 5 } })).coins > 0)
		end
		T.eq(Rewards.applyMatch(data, chessMatch({ won = true, humanOpponents = { 5 } })).coins, 0)
		T.ok(Rewards.applyMatch(data, chessMatch({ won = true, humanOpponents = { 6 } })).coins > 0)
	end)

	T.test("VIP gets +25% coins", function()
		local data = fresh()
		T.eq(Rewards.applyMatch(data, chessMatch({ vip = true })).coins, 63) -- 62.5 rounds up
	end)

	T.test("finishing 3 games completes the play challenge and pays Gems", function()
		local data = fresh()
		local done = {}
		for _ = 1, 3 do
			for _, text in Rewards.applyMatch(data, chessMatch()).challenges do
				table.insert(done, text)
			end
		end
		T.ok(table.find(done, "Finish 3 games") ~= nil)
	end)

	T.test("losing resets the streak, a draw keeps it", function()
		local data = fresh()
		data.winStreak.chess = 3
		Rewards.applyMatch(data, chessMatch({ isDraw = true }))
		T.eq(data.winStreak.chess, 3)
		Rewards.applyMatch(data, chessMatch())
		T.eq(data.winStreak.chess, 0)
	end)

	T.test("every ready game has economy settings and a known coin", function()
		for _, entry in GameCatalog.entries do
			T.ok(entry.coin == nil or Economy.Coins[entry.coin] ~= nil, `{entry.id} has an unknown coin`)
			if entry.status == "ready" then
				T.ok(entry.typicalMinutes ~= nil, `{entry.id} needs typicalMinutes`)
			end
		end
	end)

	-- Shop --------------------------------------------------------------------------

	T.test("coin items also show a Gem price at 1 Gem = 10 Coins", function()
		local item = ShopCatalog.get("chess_walnut_board") :: any
		T.eq(Shop.coinPrice(item), 400)
		T.eq(Shop.gemPrice(item, false), 40)
		T.eq(Shop.gemPrice(item, true), 36, "VIP gets 10% off")
	end)

	T.test("earned-only items can't be bought with Gems, Legendary can't be bought with Coins", function()
		T.eq(Shop.gemPrice(ShopCatalog.get("chess_tournament_board") :: any, false), nil)
		T.eq(Shop.coinPrice(ShopCatalog.get("chess_crystal_pieces") :: any), nil)
	end)

	T.test("buying with coins spends that game's coins only", function()
		local data = fresh()
		Profile.addCoins(data, "checkers", 1000)
		local ok = Shop.buy(data, "chess_walnut_board", "coins", false)
		T.eq(ok, false, "checkers coins can't buy chess items")
		Profile.addCoins(data, "chess", 450)
		T.ok(Shop.buy(data, "chess_walnut_board", "coins", false))
		T.eq(Profile.coins(data, "chess"), 50)
		T.eq(Profile.coins(data, "checkers"), 1000)
		T.ok(data.owned.chess_walnut_board)
		T.eq((Shop.buy(data, "chess_walnut_board", "coins", false)), false, "can't buy twice")
	end)

	T.test("buying with gems, and rejecting bad requests", function()
		local data = fresh()
		Profile.addGems(data, 200)
		T.eq((Shop.buy(data, "hub_nameplate_gold", "gems", false)), false, "not enough gems")
		T.ok(Shop.buy(data, "hub_comfy_chair", "gems", false))
		T.eq(data.gems, 50)
		T.eq((Shop.buy(data, "hub_cozy_cabin", "gems", false)), false, "starter-only item")
		T.eq((Shop.buy(data, "nope", "gems", false)), false)
		T.eq((Shop.buy(data, { "hub_comfy_chair" }, "gems", false)), false)
		T.eq((Shop.buy(data, "hub_title_night_owl", "robux", false)), false)
		T.eq(data.gems, 50)
	end)

	T.test("equip toggles an owned item in its slot", function()
		local data = fresh()
		T.eq((Shop.toggleEquip(data, "hub_comfy_chair")), false, "not owned")
		Shop.grant(data, { "hub_comfy_chair", "not_an_item" })
		T.eq(data.owned.not_an_item, nil)
		T.ok(Shop.toggleEquip(data, "hub_comfy_chair"))
		T.eq(data.equipped.hub.chair, "hub_comfy_chair")
		T.ok(Shop.toggleEquip(data, "hub_comfy_chair"))
		T.eq(data.equipped.hub.chair, nil)
	end)

	T.test("every shop item is in a known shop and has a way to get it", function()
		for _, item in ShopCatalog.items do
			T.ok(item.shop == "hub" or Economy.Coins[item.shop] ~= nil, `{item.id} has an unknown shop`)
			T.ok(item.notForSale or item.free or Shop.coinPrice(item) or Shop.gemPrice(item, false), `{item.id} has no price`)
		end
		for _, id in Economy.StarterPack.items do
			T.ok(ShopCatalog.get(id) ~= nil, `starter item {id} missing`)
		end
	end)

	T.test("every coin a game pays has a shop with items", function()
		for _, entry in GameCatalog.entries do
			local coin = entry.coin or Economy.DefaultCoin
			T.ok(#ShopCatalog.forShop(coin) > 0, `{entry.id} pays {coin} but that shop is empty`)
		end
	end)

	T.test("reconcile keeps a newer save's version (rollback to an older build)", function()
		local newer = Profile.new(1000)
		newer.version = Profile.Version + 3
		newer.futureField = { kept = true }
		local loaded = Profile.reconcile(newer, 2000)
		T.eq(loaded.version, Profile.Version + 3)
		T.eq((loaded :: any).futureField.kept, true, "fields it doesn't know survive")
		local old = Profile.new(1000)
		old.version = 0
		T.eq(Profile.reconcile(old, 2000).version, Profile.Version)
		local broken = Profile.new(1000)
		broken.version = 0 / 0
		T.eq(Profile.reconcile(broken, 2000).version, Profile.Version)
	end)

	-- Session lock --------------------------------------------------------------------

	T.test("a server can claim a free profile and another server can't take it", function()
		local record, status = SessionLock.claim(nil, "A", 1000)
		T.eq(status, "ok")
		local _, other = SessionLock.claim(record, "B", 1010)
		T.eq(other, "locked")
		local _, again = SessionLock.claim(record, "A", 1010)
		T.eq(again, "ok", "the owner can re-claim")
	end)

	T.test("a stale lock from a crashed server can be taken over", function()
		local record = SessionLock.claim(nil, "A", 1000)
		local _, status = SessionLock.claim(record, "B", 1000 + SessionLock.StaleSeconds + 1)
		T.eq(status, "ok")
	end)

	T.test("saving releases the lock, and a server that lost the lock can't overwrite", function()
		local record = SessionLock.claim(nil, "A", 1000)
		local saved, status = SessionLock.save(record, "A", 1001, { gems = 5 }, true)
		T.eq(status, "ok")
		T.eq((saved :: any).lock, nil)
		T.eq((saved :: any).profile.gems, 5)
		local taken = SessionLock.claim(saved, "B", 1002)
		local lost, lostStatus = SessionLock.save(taken, "A", 1003, { gems = 999 }, false)
		T.eq(lost, nil)
		T.eq(lostStatus, "lost")
	end)
end
