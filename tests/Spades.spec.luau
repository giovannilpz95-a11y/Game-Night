local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Spades = require(ReplicatedStorage.Shared.Games.Spades)
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local sim = require(script.Parent.CardSim)

return function(T)
	local C = PlayingCards.make
	local S, H, D = 1, 2, 3

	local function playing(hands)
		local s = Spades.new(4, { botLevel = "medium" }, T.Random.new(1))
		s.hands = hands
		s.phase = "play"
		s.bids = { 3, 3, 3, 3 }
		s.trick = {}
		s.turn = 1
		s.spadesBroken = false
		return s
	end

	local function apply(s, seat, move)
		local ok, err = Spades.validateMove(s, seat, move)
		assert(ok, err)
		Spades.applyMove(s, seat, move)
	end

	T.test("partners sit across", function()
		T.eq(Spades.teamOf(1), Spades.teamOf(3))
		T.eq(Spades.teamOf(2), Spades.teamOf(4))
		T.eq(Spades.partnerOf(1), 3)
		T.eq(Spades.partnerOf(4), 2)
	end)

	T.test("bidding goes around once, then left of the dealer leads", function()
		local s = Spades.new(4, nil, T.Random.new(3))
		local first = s.turn
		T.eq((Spades.validateMove(s, first, { kind = "bid", bid = 14 })), false)
		T.eq((Spades.validateMove(s, first, { kind = "bid", bid = 2.5 })), false)
		for i = 0, 3 do
			apply(s, (first - 1 + i) % 4 + 1, { kind = "bid", bid = 3 })
		end
		T.eq(s.phase, "play")
		T.eq(s.turn, first)
	end)

	T.test("spades can't be led until broken, and trump wins", function()
		local s = playing({ { C(4, S), C(9, H) }, { C(2, S), C(5, D) }, { C(13, H) }, { C(3, H) } })
		T.eq((Spades.validateMove(s, 1, { kind = "play", card = C(4, S) })), false)
		apply(s, 1, { kind = "play", card = C(9, H) })
		apply(s, 2, { kind = "play", card = C(2, S) }) -- void in hearts: trump
		apply(s, 3, { kind = "play", card = C(13, H) })
		apply(s, 4, { kind = "play", card = C(3, H) })
		T.eq(s.lastTrick.winner, 2)
		T.ok(s.spadesBroken)
	end)

	T.test("scoring: made bids, bags, sets and nil", function()
		local s = playing({ {}, {}, {}, {} })
		s.bids = { 4, 0, 3, 5 }
		s.tricks = { 5, 0, 3, 5 } -- team 1 bid 7 took 8; seat 2 nil made; team 2 contract 5 took 5
		s.tricksPlayed = 13
		s.phase = "trick"
		Spades.onTimeout(s)
		T.eq(s.scores[1], 71)
		T.eq(s.bags[1], 1)
		T.eq(s.scores[2], 150)
		local set = playing({ {}, {}, {}, {} })
		set.bids = { 6, 2, 6, 2 }
		set.tricks = { 4, 3, 3, 3 }
		set.tricksPlayed = 13
		set.phase = "trick"
		Spades.onTimeout(set)
		T.eq(set.scores[1], -120)
		T.eq(set.scores[2], 42)
	end)

	T.test("ten bags cost 100", function()
		local s = playing({ {}, {}, {}, {} })
		s.bags = { 9, 0 }
		s.bids = { 1, 6, 1, 6 }
		s.tricks = { 2, 5, 1, 5 }
		s.tricksPlayed = 13
		s.phase = "trick"
		Spades.onTimeout(s)
		T.eq(s.scores[1], 21 - 100)
		T.eq(s.bags[1], 0)
	end)

	T.test("reaching the target wins for the team", function()
		local s = playing({ {}, {}, {}, {} })
		s.scores = { 280, 100 }
		s.bids = { 2, 2, 2, 2 }
		s.tricks = { 4, 2, 4, 3 }
		s.tricksPlayed = 13
		s.phase = "trick"
		Spades.onTimeout(s)
		local result = Spades.getResult(s) :: any
		T.ok(table.find(result.winners, 1) ~= nil and table.find(result.winners, 3) ~= nil)
	end)

	T.test("bot games always finish", function()
		for _, level in { "easy", "medium", "hard" } do
			for seed = 1, 3 do
				local rng = T.Random.new(seed * 23 + #level)
				local s = Spades.new(4, { botLevel = level }, rng)
				sim(Spades, s, rng, 20000)
				T.ok(Spades.getResult(s) ~= nil, `{level} game should finish`)
			end
		end
	end)
end
