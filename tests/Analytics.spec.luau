local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Economy = require(ReplicatedStorage.Shared.Economy)
local Core = ServerScriptService.Server.Core
local AnalyticsEvents = require(Core.AnalyticsEvents)
local Profile = require(Core.Profile)
local Rewards = require(Core.Rewards)
local Shop = require(Core.Shop)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)

return function(T)
	T.test("onboarding steps are numbered in order and sent once per session", function()
		local session = AnalyticsEvents.newSession()
		T.eq(AnalyticsEvents.takeOnboarding(session, "Joined"), 1)
		T.eq(AnalyticsEvents.takeOnboarding(session, "Joined"), nil, "second time is skipped")
		T.eq(AnalyticsEvents.takeOnboarding(session, "SecondMatch"), 8)
		T.ok(not pcall(AnalyticsEvents.takeOnboarding, session, "Nope"), "unknown step errors")
	end)

	T.test("shop funnel: a new session per open, each step once", function()
		local session = AnalyticsEvents.newSession()
		local n = 0
		local function newId()
			n += 1
			return `id{n}`
		end
		AnalyticsEvents.openShop(session, "a")
		local id, step = AnalyticsEvents.takeShopStep(session, "Opened", newId)
		T.eq(id, "a")
		T.eq(step, 1)
		T.eq((AnalyticsEvents.takeShopStep(session, "Opened", newId)), nil)
		local _, checkout = AnalyticsEvents.takeShopStep(session, "Checkout", newId)
		T.eq(checkout, 4)
		AnalyticsEvents.openShop(session, "b")
		id, step = AnalyticsEvents.takeShopStep(session, "Checkout", newId)
		T.eq(id, "b", "reopening starts over")
		T.eq(step, 4)
		local fresh = AnalyticsEvents.newSession()
		id = AnalyticsEvents.takeShopStep(fresh, "ViewedItem", newId)
		T.eq(id, "id1", "a server step with no open shop starts a session")
	end)

	T.test("client reports are checked", function()
		T.eq(AnalyticsEvents.parseClientReport(nil), nil)
		T.eq(AnalyticsEvents.parseClientReport({ kind = "onboarding", step = "Joined" }), nil, "server-only step")
		T.eq(AnalyticsEvents.parseClientReport({ kind = "onboarding", step = "SawLobby" }).step, "SawLobby")
		T.eq(AnalyticsEvents.parseClientReport({ kind = "shop", step = "Checkout", tab = "hub" }), nil)
		T.eq(AnalyticsEvents.parseClientReport({ kind = "shop", step = "ViewedTab", tab = "chess" }).tab, "chess")
		T.eq(AnalyticsEvents.parseClientReport({ kind = "shop", step = "ViewedTab", tab = "<script>" }).tab, "other")
	end)

	T.test("custom fields: at most three, short strings", function()
		local f = AnalyticsEvents.fields("Chess", nil, 3) :: any
		T.eq(f.CustomField01, "Chess")
		T.eq(f.CustomField02, nil)
		T.eq(f.CustomField03, "3")
		T.eq(AnalyticsEvents.fields(), nil)
		T.eq(#AnalyticsEvents.fields(string.rep("x", 80)).CustomField01, 50)
	end)

	T.test("match lineup and outcome", function()
		local seats = {
			{ kind = "player", userId = 1 },
			{ kind = "bot", userId = 2, left = true }, -- a player who left
			{ kind = "bot" },
		}
		local humans, bots = AnalyticsEvents.countSeats(seats)
		T.eq(humans, 2)
		T.eq(bots, 1)
		T.eq(AnalyticsEvents.lineup(2, 1, "hard"), "2h+1b hard")
		T.eq(AnalyticsEvents.lineup(4, 0, "hard"), "4h")
		T.eq(AnalyticsEvents.outcome({ winners = { 2 }, isDraw = false }, 2), "won")
		T.eq(AnalyticsEvents.outcome({ winners = { 2 }, isDraw = false }, 1), "lost")
		T.eq(AnalyticsEvents.outcome({ winners = {}, isDraw = true }, 1), "draw")
		T.eq(AnalyticsEvents.minutes(4.26), 4.3)
	end)

	T.test("wallet diff: one entry per changed currency, with the ending balance", function()
		local data = Profile.new(0)
		data.gems = 100
		data.coins.chess = 500
		local before = AnalyticsEvents.snapshot(data)
		local item
		for _, candidate in ShopCatalog.forShop("chess") do
			if candidate.coins and candidate.coins <= 500 and not candidate.notForSale then
				item = candidate
				break
			end
		end
		T.ok(item, "test needs a chess item that costs 500 Coins or less")
		T.ok(Shop.buy(data, item.id, "coins", false))
		local entries = AnalyticsEvents.walletDiff(before, AnalyticsEvents.snapshot(data), "Shop", item.id)
		T.eq(#entries, 1)
		T.eq(entries[1].flow, "Sink")
		T.eq(entries[1].currency, "chess")
		T.eq(entries[1].amount, item.coins)
		T.eq(entries[1].balance, 500 - item.coins)
		T.eq(entries[1].sku, item.id)

		local both = AnalyticsEvents.walletDiff({ gems = 5, coins = {} }, { gems = 2, coins = { arcade = 7 } }, "Gameplay")
		T.eq(#both, 2)
		T.eq(both[1].currency, "Gems")
		T.eq(both[1].flow, "Sink")
		T.eq(both[2].currency, "arcade")
		T.eq(both[2].amount, 7)
	end)

	T.test("payout entries add up to what Rewards paid", function()
		local data = Profile.new(0)
		data.xp = Economy.xpForLevel(1) - 1 -- the next match levels up
		local before = AnalyticsEvents.snapshot(data)
		local payout = Rewards.applyMatch(data, {
			gameId = "Chess",
			coinKey = "chess",
			typicalMinutes = 10,
			minMinutes = 0,
			minMoves = 0,
			minutes = 8,
			moves = 40,
			won = true,
			isDraw = false,
			humanOpponents = { 99 },
			vip = false,
		})
		T.ok(#payout.levelUps >= 1, "leveled up")
		local entries = AnalyticsEvents.payoutEntries(data, payout)
		local gems, coins = 0, 0
		local last = {}
		for _, entry in entries do
			T.eq(entry.flow, "Source")
			T.eq(entry.transaction, "Gameplay")
			if entry.currency == "Gems" then
				gems += entry.amount
			else
				coins += entry.amount
			end
			last[entry.currency] = entry.balance
		end
		T.eq(gems, data.gems - before.gems)
		T.eq(coins, data.coins.chess - (before.coins.chess or 0))
		T.eq(last.Gems, data.gems, "last Gems entry ends on the real balance")
		T.eq(entries[#entries].sku, "LevelUp")
	end)
end
