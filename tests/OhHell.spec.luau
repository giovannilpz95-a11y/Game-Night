local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OhHell = require(ReplicatedStorage.Shared.Games.OhHell)
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local sim = require(script.Parent.CardSim)

return function(T)
	local C = PlayingCards.make
	local S, H, D, CL = 1, 2, 3, 4

	local function playing(hands, trump)
		local s = OhHell.new(#hands, { botLevel = "medium" }, T.Random.new(1))
		s.hands = hands
		s.handSize = #hands[1]
		s.trump = trump or S
		s.dealer = #hands
		s.turn = 1
		s.phase = "play"
		s.trick = {}
		s.tricksPlayed = 0
		s.bids = {}
		for seat = 1, #hands do
			s.bids[seat] = 0
			s.tricks[seat] = 0
		end
		return s
	end

	local function apply(s, seat, move)
		local ok, err = OhHell.validateMove(s, seat, move)
		assert(ok, err)
		OhHell.applyMove(s, seat, move)
	end

	T.test("hand sizes for each schedule, capped at 51 cards dealt", function()
		T.eq(table.concat(OhHell.schedule("classic", 4), ","), "7,6,5,4,3,2,1")
		T.eq(table.concat(OhHell.schedule("short", 3), ","), "5,4,3,2,1")
		T.eq(table.concat(OhHell.schedule("updown", 3), ","), "1,2,3,4,5,6,7,6,5,4,3,2,1")
		T.eq(OhHell.schedule("classic", 7)[1], 7)
		local s = OhHell.new(5, nil, T.Random.new(2))
		T.eq(#s.hands[1], 7)
		T.ok(PlayingCards.isCardId(s.trumpCard))
	end)

	T.test("the dealer can't make the bids add up to the hand size", function()
		local s = OhHell.new(3, nil, T.Random.new(4)) -- 7 cards, seat 1 deals, seat 2 bids first
		T.eq(s.turn, 2)
		T.eq((OhHell.validateMove(s, 3, { kind = "bid", bid = 1 })), false, "not your turn")
		T.eq((OhHell.validateMove(s, 2, { kind = "bid", bid = 8 })), false)
		T.eq((OhHell.validateMove(s, 2, { kind = "bid", bid = 1.5 })), false)
		apply(s, 2, { kind = "bid", bid = 3 })
		apply(s, 3, { kind = "bid", bid = 2 })
		T.eq(OhHell.forbiddenBid(s, 1), 2)
		T.eq((OhHell.validateMove(s, 1, { kind = "bid", bid = 2 })), false, "hooked")
		apply(s, 1, { kind = "bid", bid = 0 })
		T.eq(s.phase, "play")
		T.eq(s.turn, 2, "left of the dealer leads")
	end)

	T.test("follow suit; trump wins; the winner leads next", function()
		local s = playing({ { C(5, H), C(2, CL) }, { C(13, H), C(3, CL) }, { C(2, S), C(9, H) } }, S)
		apply(s, 1, { kind = "play", card = C(5, H) })
		T.eq((OhHell.validateMove(s, 2, { kind = "play", card = C(3, CL) })), false, "must follow hearts")
		apply(s, 2, { kind = "play", card = C(13, H) })
		T.eq((OhHell.validateMove(s, 3, { kind = "play", card = C(2, S) })), false, "has a heart")
		apply(s, 3, { kind = "play", card = C(9, H) })
		T.eq(s.tricks[2], 1)
		OhHell.onTimeout(s)
		T.eq(s.turn, 2)
		apply(s, 2, { kind = "play", card = C(3, CL) })
		apply(s, 3, { kind = "play", card = C(2, S) })
		apply(s, 1, { kind = "play", card = C(2, CL) })
		T.eq(s.tricks[3], 1, "a low trump beats clubs")
	end)

	T.test("exact bids score 10 + bid, misses score nothing", function()
		local s = playing({ {}, {}, {} })
		s.handSize = 3
		s.round = 1
		s.bids = { 0, 2, 0 }
		s.tricks = { 0, 1, 2 }
		s.tricksPlayed = 3
		s.phase = "trick"
		OhHell.onTimeout(s)
		T.eq(s.scores[1], 10)
		T.eq(s.scores[2], 0)
		T.eq(s.scores[3], 0)
		T.eq(s.phase, "round")
	end)

	T.test("highest score after the last round wins", function()
		local s = playing({ {}, {}, {} })
		s.round = #s.schedule
		s.handSize = 1
		s.scores = { 30, 50, 20 }
		s.bids = { 1, 0, 0 }
		s.tricks = { 0, 0, 1 }
		s.tricksPlayed = 1
		s.phase = "trick"
		OhHell.onTimeout(s)
		local result = OhHell.getResult(s) :: any
		T.eq(result.winners[1], 2)
		T.eq(#result.winners, 1)
	end)

	T.test("bot games always finish", function()
		for _, level in { "easy", "medium", "hard" } do
			for seats = 3, 7 do
				local rng = T.Random.new(seats * 17 + #level)
				local s = OhHell.new(seats, { botLevel = level, rules = { rounds = if seats == 3 then "updown" else "classic" } }, rng)
				sim(OhHell, s, rng, 20000)
				T.ok(OhHell.getResult(s) ~= nil, `{level} {seats}-seat game should finish`)
			end
		end
	end)
end
