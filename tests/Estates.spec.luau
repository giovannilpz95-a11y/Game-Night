local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Estates = require(ReplicatedStorage.Shared.Games.Estates)
local GameModule = require(ReplicatedStorage.Shared.GameModule)
local Match = require(ServerScriptService.Server.Core.Match)

return function(T)
	local spaces = Estates.spaces

	local function posOf(name: string): number
		for pos, space in spaces do
			if space.name == name then
				return pos
			end
		end
		error(`no space {name}`)
	end

	-- A rng that hands out scripted dice first, then real random numbers.
	local function scripted(values: { number }, seed: number?)
		local real = T.Random.new(seed or 1)
		return {
			NextInteger = function(_, min, max)
				local v = table.remove(values, 1)
				if v then
					return v
				end
				return real:NextInteger(min, max)
			end,
			NextNumber = function()
				return real:NextNumber()
			end,
		}
	end

	local function newGame(seats: number, dice: { number }?)
		local s = Estates.new(seats, { botLevel = "medium" }, T.Random.new(1))
		s.rng = scripted(dice or {})
		return s
	end

	local function play(s, seat, move)
		local ok, err = Estates.validateMove(s, seat, move)
		assert(ok, err)
		Estates.applyMove(s, seat, move)
	end

	local function rejects(s, seat, move, message)
		local ok = Estates.validateMove(s, seat, move)
		T.eq(ok, false, message)
	end

	T.test("the board has 40 spaces, 28 deeds and 8 color sets", function()
		T.eq(#spaces, 40)
		local deeds, streets = 0, 0
		for pos = 1, #spaces do
			if Estates.isDeed(pos) then
				deeds += 1
			end
			if spaces[pos].kind == "street" then
				streets += 1
			end
		end
		T.eq(deeds, 28)
		T.eq(streets, 22)
		T.eq(#Estates.groupMembers, 8)
		T.eq(spaces[Estates.JAIL_POS].kind, "jail")
		T.eq(spaces[Estates.GO_TO_JAIL_POS].kind, "gotojail")
		local s = Estates.new(4, nil, T.Random.new(2))
		T.eq(s.players[3].cash, 1500)
		T.eq(s.maxRounds, 25)
	end)

	T.test("rolling moves you, and you can buy what you land on", function()
		local s = newGame(2, { 1, 2 })
		play(s, 1, { kind = "roll" })
		T.eq(s.players[1].pos, 4, "1 + 3")
		T.eq(s.phase, "buy")
		rejects(s, 1, { kind = "endTurn" }, "must decide first")
		play(s, 1, { kind = "buy" })
		T.eq(s.owner[4], 1)
		T.eq(s.players[1].cash, 1440)
		rejects(s, 2, { kind = "roll" }, "not seat 2's turn")
		play(s, 1, { kind = "endTurn" })
		T.eq(s.turn, 2)
	end)

	T.test("rent: base, doubled for a full set, then houses", function()
		local s = newGame(2)
		local pebble, acorn = posOf("Pebble Lane"), posOf("Acorn Street")
		s.owner[pebble] = 2
		T.eq(Estates.rentFor(s, pebble, 7), 2)
		s.owner[acorn] = 2
		T.eq(Estates.rentFor(s, pebble, 7), 4, "full set doubles bare rent")
		s.houses[pebble] = 3
		T.eq(Estates.rentFor(s, pebble, 7), 90)
		s.houses[pebble] = 5
		T.eq(Estates.rentFor(s, pebble, 7), 250, "hotel")
		s.mortgaged[acorn] = true
		T.eq(Estates.rentFor(s, acorn, 7), 0, "no rent on a mortgaged deed")
	end)

	T.test("stations and utilities", function()
		local s = newGame(2)
		s.owner[6] = 2
		T.eq(Estates.rentFor(s, 6, 7), 25)
		s.owner[16] = 2
		s.owner[26] = 2
		T.eq(Estates.rentFor(s, 6, 7), 100)
		T.eq(Estates.rentFor(s, 6, 7, "double"), 200)
		s.owner[13] = 2
		T.eq(Estates.rentFor(s, 13, 8), 32)
		s.owner[29] = 2
		T.eq(Estates.rentFor(s, 13, 8), 80)
	end)

	T.test("landing on someone's street pays them", function()
		local s = newGame(2, { 2, 3 })
		local birch = posOf("Birch Avenue")
		s.owner[birch] = 2
		s.players[1].pos = 5 -- City Tax, then 5 more is Birch Avenue
		play(s, 1, { kind = "roll" })
		T.eq(s.players[1].pos, birch)
		T.eq(s.players[1].cash, 1500 - 8)
		T.eq(s.players[2].cash, 1500 + 8)
	end)

	T.test("passing Start pays 200", function()
		local s = newGame(2, { 3, 4 })
		s.players[1].pos = 38
		play(s, 1, { kind = "roll" })
		T.eq(s.players[1].pos, 5, "City Tax")
		T.eq(s.players[1].cash, 1500 + 200 - 200)
	end)

	T.test("declining starts a live auction; the high bid wins", function()
		local s = newGame(3, { 1, 2 })
		play(s, 1, { kind = "roll" })
		play(s, 1, { kind = "decline" })
		T.eq(s.phase, "auction")
		T.eq(#Estates.getActiveSeats(s), 3, "everyone can bid at once, the decliner too")
		local clock = (Estates.getTimer(s) :: any).id
		rejects(s, 2, { kind = "bid", amount = 0 })
		rejects(s, 2, { kind = "bid", amount = 99999 }, "more than their cash")
		play(s, 2, { kind = "bid", amount = 20 })
		T.ok((Estates.getTimer(s) :: any).id ~= clock, "a bid restarts the countdown")
		rejects(s, 2, { kind = "bid", amount = 30 }, "the leader can't outbid themselves")
		rejects(s, 3, { kind = "bid", amount = 20 }, "must beat the high bid")
		play(s, 3, { kind = "bid", amount = 30 })
		play(s, 1, { kind = "pass" })
		rejects(s, 1, { kind = "bid", amount = 40 }, "passed is out")
		play(s, 2, { kind = "pass" })
		T.eq(s.phase, "turn")
		T.eq(s.owner[4], 3)
		T.eq(s.players[3].cash, 1470)
	end)

	T.test("the auction countdown sells to the leader", function()
		local s = newGame(3, { 1, 2 })
		play(s, 1, { kind = "roll" })
		play(s, 1, { kind = "decline" })
		play(s, 1, { kind = "bid", amount = 15 })
		T.eq(Estates.getTimer(s).seconds, Estates.AUCTION_SECONDS)
		Estates.onTimeout(s)
		T.eq(s.phase, "turn")
		T.eq(s.owner[4], 1)
		T.eq(s.players[1].cash, 1485)
		T.eq(Estates.getTimer(s), nil, "no clock outside auctions")
	end)

	T.test("nobody bidding leaves the deed with the bank", function()
		local s = newGame(2, { 1, 2 })
		play(s, 1, { kind = "roll" })
		play(s, 1, { kind = "decline" })
		play(s, 2, { kind = "pass" })
		play(s, 1, { kind = "pass" })
		T.eq(s.owner[4], nil)
		T.eq(s.phase, "turn")
	end)

	T.test("house rule: no auctions leaves a declined deed unsold", function()
		local s = Estates.new(2, { rules = { auctions = false } }, T.Random.new(1))
		s.rng = scripted({ 1, 2 })
		play(s, 1, { kind = "roll" })
		play(s, 1, { kind = "decline" })
		T.eq(s.phase, "turn")
		T.eq(s.owner[4], nil)
	end)

	T.test("house rule: fast mode deals deeds but never a whole set", function()
		for seed = 1, 20 do
			local s = Estates.new(4, { rules = { fast = true } }, T.Random.new(seed))
			for seat = 1, 4 do
				local n = 0
				for _, who in s.owner do
					if who == seat then
						n += 1
					end
				end
				T.eq(n, Estates.FAST_DEEDS)
				for g = 1, #Estates.groups do
					T.ok(not Estates.ownsGroup(s, seat, g), "no free color set")
				end
			end
			T.ok(s.maxRounds < Estates.roundsFor(4))
			T.eq(Estates.auctionSeconds(s), Estates.FAST_AUCTION_SECONDS)
		end
	end)

	T.test("house rule: jackpot collects taxes and fees on Rest Stop", function()
		local s = Estates.new(2, { rules = { jackpot = true } }, T.Random.new(1))
		s.rng = scripted({ 1, 3, 6, 5 })
		play(s, 1, { kind = "roll" }) -- City Tax 200
		T.eq(s.pot, 200)
		play(s, 1, { kind = "endTurn" })
		s.players[2].pos = 10
		play(s, 2, { kind = "roll" }) -- 10 + 11 = Rest Stop
		T.eq(s.players[2].pos, 21)
		T.eq(s.pot, 0)
		T.eq(s.players[2].cash, 1500 + 200)
	end)

	T.test("house rule: landing right on Start pays double", function()
		local s = Estates.new(2, { rules = { doubleStart = true } }, T.Random.new(1))
		s.rng = scripted({ 1, 2 })
		s.players[1].pos = 38
		play(s, 1, { kind = "roll" })
		T.eq(s.players[1].pos, 1)
		T.eq(s.players[1].cash, 1500 + 400)
	end)

	T.test("building needs the full set and goes evenly", function()
		local s = newGame(2)
		local maple, willow, birch = posOf("Maple Row"), posOf("Willow Way"), posOf("Birch Avenue")
		s.owner[maple] = 1
		s.owner[willow] = 1
		rejects(s, 1, { kind = "build", pos = maple }, "needs the whole set")
		s.owner[birch] = 1
		play(s, 1, { kind = "build", pos = maple })
		rejects(s, 1, { kind = "build", pos = maple }, "build evenly")
		play(s, 1, { kind = "build", pos = willow })
		play(s, 1, { kind = "build", pos = birch })
		play(s, 1, { kind = "build", pos = maple })
		T.eq(s.houses[maple], 2)
		T.eq(s.housesLeft, 32 - 4)
		T.eq(s.players[1].cash, 1500 - 200)
		rejects(s, 1, { kind = "sell", pos = willow }, "sell evenly")
		play(s, 1, { kind = "sell", pos = maple })
		T.eq(s.players[1].cash, 1500 - 200 + 25)
		rejects(s, 1, { kind = "mortgage", pos = maple }, "sell buildings first")
		rejects(s, 1, { kind = "build", pos = 1 }, "not a street")
		rejects(s, 1, { kind = "build", pos = 0.5 }, "bad position")
	end)

	T.test("hotels replace four houses and are limited", function()
		local s = newGame(2)
		local skyline, diamond = posOf("Skyline Tower"), posOf("Diamond Point")
		s.owner[skyline] = 1
		s.owner[diamond] = 1
		s.players[1].cash = 10000
		for _ = 1, 4 do
			play(s, 1, { kind = "build", pos = skyline })
			play(s, 1, { kind = "build", pos = diamond })
		end
		T.eq(s.housesLeft, 24)
		play(s, 1, { kind = "build", pos = skyline })
		T.eq(s.houses[skyline], 5)
		T.eq(s.housesLeft, 28)
		T.eq(s.hotelsLeft, 11)
		s.hotelsLeft = 0
		rejects(s, 1, { kind = "build", pos = diamond }, "out of hotels")
		s.hotelsLeft = 11
		s.housesLeft = 0
		local sky = posOf("Maple Row")
		s.owner[sky], s.owner[posOf("Willow Way")], s.owner[posOf("Birch Avenue")] = 1, 1, 1
		rejects(s, 1, { kind = "build", pos = sky }, "out of houses")
	end)

	T.test("mortgage pays half, paying it off costs 10% more", function()
		local s = newGame(2)
		local diamond = posOf("Diamond Point")
		s.owner[diamond] = 1
		play(s, 1, { kind = "mortgage", pos = diamond })
		T.eq(s.players[1].cash, 1700)
		rejects(s, 1, { kind = "mortgage", pos = diamond })
		play(s, 1, { kind = "unmortgage", pos = diamond })
		T.eq(s.players[1].cash, 1700 - 220)
		rejects(s, 1, { kind = "mortgage", pos = posOf("Pebble Lane") }, "not theirs")
	end)

	T.test("three doubles in a row is Jail; doubles get you out", function()
		local s = newGame(2, { 1, 1, 2, 2, 3, 3 })
		play(s, 1, { kind = "roll" })
		if s.phase == "buy" then
			play(s, 1, { kind = "decline" })
			play(s, 2, { kind = "pass" })
			play(s, 1, { kind = "pass" })
		end
		T.eq(s.canRoll, true, "doubles roll again")
		-- Don't let the next spaces send us anywhere else.
		s.players[1].pos = 1
		play(s, 1, { kind = "roll" })
		while s.phase ~= "turn" do
			if s.phase == "buy" then
				play(s, 1, { kind = "decline" })
			else
				play(s, Estates.getActiveSeats(s)[1], { kind = "pass" })
			end
		end
		s.players[1].pos = 1
		play(s, 1, { kind = "roll" })
		T.eq(s.players[1].inJail, true)
		T.eq(s.players[1].pos, Estates.JAIL_POS)
		T.eq(s.canRoll, false)
		play(s, 1, { kind = "endTurn" })
		play(s, 2, { kind = "roll" })
		while Estates.getActiveSeats(s)[1] ~= 1 or s.phase ~= "turn" do
			local seat = Estates.getActiveSeats(s)[1]
			play(s, seat, GameModule.chooseBotMove(Estates, s, seat, T.Random.new(1)))
		end
		T.eq(s.players[1].inJail, true)
		rejects(s, 1, { kind = "useCard" }, "no card")
		s.rng = scripted({ 4, 4 })
		play(s, 1, { kind = "roll" })
		T.eq(s.players[1].inJail, false)
		T.eq(s.players[1].pos, Estates.JAIL_POS + 8)
		T.eq(s.canRoll, false, "doubles out of Jail don't roll again")
	end)

	T.test("third failed Jail roll pays the fee and moves", function()
		local s = newGame(2, { 1, 2 })
		s.players[1].pos = Estates.JAIL_POS
		s.players[1].inJail = true
		s.players[1].jailTries = 2
		play(s, 1, { kind = "roll" })
		T.eq(s.players[1].inJail, false)
		T.eq(s.players[1].pos, Estates.JAIL_POS + 3)
		T.eq(s.players[1].cash, 1450)
	end)

	T.test("paying to leave Jail before rolling", function()
		local s = newGame(2, { 2, 3 })
		s.players[1].pos = Estates.JAIL_POS
		s.players[1].inJail = true
		play(s, 1, { kind = "payJail" })
		T.eq(s.players[1].inJail, false)
		play(s, 1, { kind = "roll" })
		T.eq(s.players[1].pos, Estates.JAIL_POS + 5)
	end)

	T.test("owing more than your cash: raise it, then pay", function()
		local s = newGame(2, { 2, 3 })
		local birch = posOf("Birch Avenue")
		local diamond = posOf("Diamond Point")
		s.owner[birch] = 2
		s.houses[birch] = 5
		s.owner[diamond] = 1
		s.players[1].pos = 5
		s.players[1].cash = 450
		play(s, 1, { kind = "roll" })
		T.eq(s.phase, "debt")
		T.eq(s.debt.amount, 600)
		rejects(s, 1, { kind = "payDebt" }, "not enough yet")
		rejects(s, 1, { kind = "endTurn" })
		rejects(s, 1, { kind = "build", pos = diamond })
		play(s, 1, { kind = "mortgage", pos = diamond })
		T.eq(s.players[1].cash, 650)
		play(s, 1, { kind = "payDebt" })
		T.eq(s.players[1].cash, 50)
		T.eq(s.players[2].cash, 2100)
		T.eq(s.phase, "turn")
	end)

	T.test("bankrupt to a player hands them everything; last one standing wins", function()
		local s = newGame(2, { 2, 3 })
		local birch = posOf("Birch Avenue")
		local pebble = posOf("Pebble Lane")
		s.owner[birch] = 2
		s.houses[birch] = 5
		s.hotelsLeft = 11
		s.owner[pebble] = 1
		s.players[1].pos = 5
		s.players[1].cash = 10
		play(s, 1, { kind = "roll" })
		T.eq(s.players[1].bankrupt, true, "can't raise 600, so bankrupt at once")
		T.eq(s.owner[pebble], 2)
		local result = Estates.getResult(s)
		T.ok(result)
		T.eq(result.winners[1], 2)
		T.eq(#Estates.getActiveSeats(s), 0)
	end)

	T.test("bankrupt to the bank frees the deeds; the game goes on", function()
		local s = newGame(3)
		local pebble = posOf("Pebble Lane")
		s.owner[pebble] = 1
		s.phase = "debt"
		s.debt = { amount = 5000, to = nil, why = "test" }
		play(s, 1, { kind = "bankrupt" })
		T.eq(s.owner[pebble], nil)
		T.eq(s.turn, 2)
		T.eq(Estates.getResult(s), nil)
	end)

	T.test("trades: offer, accept, and the rules for what can be traded", function()
		local s = newGame(3)
		local maple, willow, birch = posOf("Maple Row"), posOf("Willow Way"), posOf("Birch Avenue")
		s.owner[maple], s.owner[willow] = 1, 1
		s.owner[birch] = 2
		rejects(s, 1, { kind = "offer", to = 1, give = {}, get = {} }, "not with yourself")
		rejects(s, 1, { kind = "offer", to = 2, give = {}, get = {} }, "empty trade")
		rejects(s, 1, { kind = "offer", to = 2, give = { cash = 5000 }, get = { props = { birch } } }, "too much cash")
		rejects(s, 1, { kind = "offer", to = 2, give = { props = { birch } }, get = {} }, "not theirs")
		rejects(s, 1, { kind = "offer", to = 2, give = { props = "x" }, get = {} })
		rejects(s, 1, { kind = "offer", to = 2, give = { cash = -5 }, get = { props = { birch } } })
		play(s, 1, { kind = "offer", to = 2, give = { cash = 300 }, get = { props = { birch } } })
		T.eq(s.phase, "trade")
		T.eq(Estates.getActiveSeats(s)[1], 2)
		rejects(s, 1, { kind = "roll" }, "waiting on the answer")
		play(s, 2, { kind = "accept" })
		T.eq(s.owner[birch], 1)
		T.eq(s.players[1].cash, 1200)
		T.eq(s.players[2].cash, 1800)
		T.eq(s.phase, "turn")
		-- Streets in a color with buildings can't be traded.
		play(s, 1, { kind = "build", pos = maple })
		rejects(s, 1, { kind = "offer", to = 3, give = { props = { willow } }, get = { cash = 10 } })
	end)

	T.test("trades: a counter-offer goes back to the one who asked", function()
		local s = newGame(2)
		local maple, birch = posOf("Maple Row"), posOf("Birch Avenue")
		s.owner[maple] = 1
		s.owner[birch] = 2
		play(s, 1, { kind = "offer", to = 2, give = { cash = 100 }, get = { props = { birch } } })
		rejects(s, 2, { kind = "counter", give = { props = { maple } }, get = {} }, "can't give what isn't yours")
		rejects(s, 2, { kind = "counter", give = {}, get = {} }, "empty")
		play(s, 2, { kind = "counter", give = { props = { birch } }, get = { cash = 250 } })
		T.eq(Estates.getActiveSeats(s)[1], 1)
		T.eq(s.trade.from, 2)
		play(s, 1, { kind = "counter", give = { cash = 180 }, get = { props = { birch } } })
		rejects(s, 2, { kind = "counter", give = { props = { birch } }, get = { cash = 200 } }, "counters run out")
		play(s, 2, { kind = "accept" })
		T.eq(s.owner[birch], 1)
		T.eq(s.players[1].cash, 1320)
		T.eq(s.phase, "turn")
		T.eq(s.turn, 1)
	end)

	T.test("bots turn down trades that hand over a color set", function()
		local s = newGame(2)
		local maple, willow, birch = posOf("Maple Row"), posOf("Willow Way"), posOf("Birch Avenue")
		s.owner[maple], s.owner[willow] = 1, 1
		s.owner[birch] = 2
		play(s, 1, { kind = "offer", to = 2, give = { cash = 150 }, get = { props = { birch } } })
		T.eq(Estates.chooseBotMove(s, 2, T.Random.new(1)).kind, "reject")
		s.phase = "turn"
		s.trade = nil
		play(s, 1, { kind = "offer", to = 2, give = { props = { maple } }, get = { cash = 50 } })
		T.eq(Estates.chooseBotMove(s, 2, T.Random.new(1)).kind, "accept", "a 100 street for 50 is a good deal")
	end)

	T.test("bots turn down lopsided gifts", function()
		local s = newGame(2)
		play(s, 1, { kind = "offer", to = 2, give = { cash = 500 }, get = {} })
		T.eq(Estates.chooseBotMove(s, 2, T.Random.new(1)).kind, "reject", "free cash")
		play(s, 2, { kind = "reject" })
		local diamond = posOf("Diamond Point")
		s.owner[diamond] = 1
		play(s, 1, { kind = "offer", to = 2, give = { props = { diamond } }, get = { cash = 20 } })
		T.eq(Estates.chooseBotMove(s, 2, T.Random.new(1)).kind, "reject", "a $400 deed for $20")
	end)

	T.test("a bot offers cash for the street that finishes its set, and a human can answer", function()
		local s = Estates.new(2, { botLevel = "hard" }, T.Random.new(1))
		local maple, willow, birch = posOf("Maple Row"), posOf("Willow Way"), posOf("Birch Avenue")
		s.owner[maple], s.owner[willow] = 1, 1
		s.owner[birch] = 2
		local move = Estates.chooseBotMove(s, 1, T.Random.new(1))
		T.eq(move.kind, "offer")
		T.eq(move.to, 2)
		T.eq(move.get.props[1], birch)
		T.eq(move.give.cash, 216, "hard bots pay 1.8x")
		play(s, 1, move)
		T.eq(Estates.getActiveSeats(s)[1], 2)
		play(s, 2, { kind = "accept" })
		T.eq(s.owner[birch], 1)
		T.eq(s.phase, "turn")
		local again = Estates.chooseBotMove(s, 1, T.Random.new(1))
		T.eq(again.kind, "build", "with the set done it builds")
	end)

	T.test("bots build evenly up to hotels with spare cash", function()
		local s = Estates.new(2, { botLevel = "medium" }, T.Random.new(1))
		local skyline, diamond = posOf("Skyline Tower"), posOf("Diamond Point")
		s.owner[skyline], s.owner[diamond] = 1, 1
		s.players[1].cash = 5000
		for _ = 1, 10 do
			local move = Estates.chooseBotMove(s, 1, T.Random.new(1))
			T.eq(move.kind, "build")
			play(s, 1, move)
		end
		T.eq(s.houses[skyline], 5)
		T.eq(s.houses[diamond], 5)
		T.eq(s.hotelsLeft, 10)
		T.eq(s.housesLeft, 32)
		T.eq(Estates.chooseBotMove(s, 1, T.Random.new(1)).kind, "roll")
		T.eq(Estates.rentFor(s, diamond, 7), 2000)
	end)

	T.test("rent shows in the news only once it's paid", function()
		local s = newGame(2, { 2, 3 })
		local birch = posOf("Birch Avenue")
		local diamond = posOf("Diamond Point")
		s.owner[birch] = 2
		s.houses[birch] = 5
		s.owner[diamond] = 1
		s.players[1].pos = 5
		s.players[1].cash = 450
		play(s, 1, { kind = "roll" })
		local function newsHas(word)
			for _, entry in s.log do
				if string.find(entry.text, word, 1, true) then
					return true
				end
			end
			return false
		end
		T.eq(newsHas("paid $600 rent"), false)
		T.ok(newsHas("owes $600"))
		play(s, 1, { kind = "mortgage", pos = diamond })
		play(s, 1, { kind = "payDebt" })
		T.ok(newsHas("paid $600 (rent for Birch Avenue)"))
	end)

	T.test("only a few trade offers a turn", function()
		local s = newGame(2)
		for _ = 1, Estates.TRADES_PER_TURN do
			play(s, 1, { kind = "offer", to = 2, give = { cash = 1 }, get = {} })
			play(s, 2, { kind = "reject" })
		end
		rejects(s, 1, { kind = "offer", to = 2, give = { cash = 1 }, get = {} })
	end)

	T.test("cards: Get Out of Jail is kept and can be used", function()
		local s = newGame(2)
		local deck = s.decks.lucky
		for i, card in Estates.decks.lucky.cards do
			if card.kind == "jailFree" then
				table.remove(deck, table.find(deck, i) :: number)
				table.insert(deck, 1, i)
			end
		end
		s.rng = scripted({ 3, 4 }) -- 1 + 7 = Lucky Break
		play(s, 1, { kind = "roll" })
		T.eq(#s.players[1].cards, 1)
		T.eq(#deck, #Estates.decks.lucky.cards - 1, "held card leaves the deck")
		s.players[1].inJail = true
		s.canRoll = true
		play(s, 1, { kind = "useCard" })
		T.eq(s.players[1].inJail, false)
		T.eq(#deck, #Estates.decks.lucky.cards)
	end)

	T.test("the round limit ends the game: richest wins", function()
		local s = newGame(2)
		s.maxRounds = 1
		s.owner[posOf("Diamond Point")] = 2
		s.canRoll = false
		play(s, 1, { kind = "endTurn" })
		s.canRoll = false
		play(s, 2, { kind = "endTurn" })
		local result = Estates.getResult(s)
		T.ok(result)
		T.eq(result.winners[1], 2)
		T.eq(result.reason, "Round limit: richest player wins")
	end)

	T.test("bot-only games always finish, and money and houses add up", function()
		for _, level in { "easy", "medium", "hard" } do
			for seed = 1, 6 do
				local seats = 2 + (seed % 5)
				local rng = T.Random.new(seed * 31)
				local s = Estates.new(seats, { botLevel = level }, rng)
				local guard = 0
				while Estates.getResult(s) == nil do
					local seat = Estates.getActiveSeats(s)[1]
					local move = GameModule.chooseBotMove(Estates, s, seat, rng)
					local ok, err = Estates.validateMove(s, seat, move)
					assert(ok, `{level} bot made a bad move ({move.kind}): {err}`)
					Estates.applyMove(s, seat, move)
					guard += 1
					assert(guard < 5000, "game never ended")
					-- Buildings are conserved.
					local houses, hotels = 0, 0
					for pos = 1, #spaces do
						if s.houses[pos] == 5 then
							hotels += 1
						else
							houses += s.houses[pos]
						end
					end
					T.eq(houses + s.housesLeft, Estates.HOUSES, "houses")
					T.eq(hotels + s.hotelsLeft, Estates.HOTELS, "hotels")
					for p = 1, seats do
						T.ok(s.players[p].cash >= 0, "cash never goes negative")
					end
				end
				T.ok(#Estates.getResult(s).winners >= 1)
			end
		end
	end)

	T.test("runs under Match with bots, and views hide nothing that breaks", function()
		local seats = {
			{ kind = "player", userId = 1, name = "Gio" },
			{ kind = "bot", name = "Bot Ava" },
			{ kind = "bot", name = "Bot Milo" },
		}
		local m = Match.new("m", Estates, seats, { botLevel = "medium" }, T.Random.new(5))
		local guard = 0
		while not m:isOver() do
			local seat = m:getActiveSeats()[1]
			T.ok(m:playForSeat(seat))
			guard += 1
			T.ok(guard < 5000)
		end
		local snap = m:getSnapshot(1)
		T.eq(#snap.view.owner, 40)
		T.ok(snap.seatInfo[2] ~= nil)
		T.ok(m:getScores() ~= nil)
	end)
end
