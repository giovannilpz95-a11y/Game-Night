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

	T.test("the hand limit scales with the target and is in the view", function()
		T.eq(Spades.maxRoundsFor(200), 20)
		T.eq(Spades.maxRoundsFor(300), 30)
		T.eq(Spades.maxRoundsFor(500), 50)
		T.eq(Spades.maxRoundsFor(100), 15, "never under 15")
		local s = Spades.new(4, { rules = { target = 500 } }, T.Random.new(1))
		T.eq(Spades.getView(s, 1).maxRounds, 50)
	end)

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

	T.test("blind nil: only when 100 behind, before looking, worth 200", function()
		local s = Spades.new(4, { rules = { blindNil = true } }, T.Random.new(2))
		local bidder = s.turn
		T.eq(Spades.canBlindNil(s, bidder), false, "scores level: no blind nil")
		T.eq((Spades.validateMove(s, bidder, { kind = "bid", bid = 0, blind = true })), false)
		s.scores[3 - Spades.teamOf(bidder)] = 150
		T.ok(Spades.canBlindNil(s, bidder), "100+ behind")
		local view = Spades.getView(s, bidder)
		T.eq(#view.hand, 0, "cards stay face down")
		T.ok(view.faceDown)
		T.eq((Spades.validateMove(s, bidder, { kind = "bid", bid = 2, blind = true })), false, "only nil is blind")
		apply(s, bidder, { kind = "bid", bid = 0, blind = true })
		T.ok(s.blind[bidder])
		T.eq(#Spades.getView(s, bidder).hand, 13, "cards turn up after bidding")
		-- Looking first rules it out.
		local t = Spades.new(4, { rules = { blindNil = true } }, T.Random.new(3))
		local seat = t.turn
		t.scores[3 - Spades.teamOf(seat)] = 200
		apply(t, seat, { kind = "look" })
		T.eq(Spades.canBlindNil(t, seat), false)
		T.eq(#Spades.getView(t, seat).hand, 13)
		-- Off by default.
		local u = Spades.new(4, nil, T.Random.new(4))
		u.scores[3 - Spades.teamOf(u.turn)] = 300
		T.eq(Spades.canBlindNil(u, u.turn), false)
	end)

	T.test("blind nil scores 200 made or lost", function()
		local s = Spades.new(4, { rules = { blindNil = true } }, T.Random.new(5))
		s.bids = { 0, 3, 4, 3 }
		s.blind = { [1] = true }
		s.tricks = { 0, 3, 4, 6 }
		s.tricksPlayed = 13
		local before = s.scores[1]
		local summary = Spades._scoreTeam(s, 1)
		T.eq(summary.points, 200 + 40, "blind nil made + partner's 4")
		s.tricks[1] = 1
		T.eq(Spades._scoreTeam(s, 1).points, -200 + 40)
		T.eq(s.scores[1], before)
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
