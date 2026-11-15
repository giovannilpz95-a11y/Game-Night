local ReplicatedStorage = game:GetService("ReplicatedStorage")
local President = require(ReplicatedStorage.Shared.Games.President)
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local sim = require(script.Parent.CardSim)

return function(T)
	local C = PlayingCards.make

	local function setup(hands)
		local s = President.new(#hands, { botLevel = "medium" }, T.Random.new(1))
		s.hands = hands
		s.turn = 1
		s.pile = nil
		s.passed = {}
		s.finished = {}
		s.mustPlay = nil
		return s
	end

	local function apply(s, seat, move)
		local ok, err = President.validateMove(s, seat, move)
		assert(ok, err)
		President.applyMove(s, seat, move)
	end

	T.test("the 3 of clubs leads the first round", function()
		local s = President.new(4, nil, T.Random.new(3))
		T.ok(table.find(s.hands[s.turn], C(3, 4)) ~= nil)
	end)

	T.test("2s are high, then Aces", function()
		T.ok(President.power(C(2, 1)) > President.power(C(1, 1)))
		T.ok(President.power(C(1, 1)) > President.power(C(13, 1)))
		T.ok(President.power(C(3, 1)) < President.power(C(4, 1)))
	end)

	T.test("must match the count and beat the rank", function()
		local s = setup({ { C(5, 1), C(5, 2), C(9, 1) }, { C(6, 1), C(6, 2), C(4, 1), C(7, 1) }, { C(3, 1), C(8, 1) } })
		T.eq((President.validateMove(s, 1, { kind = "pass" })), false, "leader can't pass")
		T.eq((President.validateMove(s, 1, { kind = "play", cards = { C(5, 1), C(9, 1) } })), false, "mixed ranks")
		apply(s, 1, { kind = "play", cards = { C(5, 1), C(5, 2) } })
		T.eq((President.validateMove(s, 2, { kind = "play", cards = { C(7, 1) } })), false, "wrong count")
		T.eq((President.validateMove(s, 2, { kind = "play", cards = { C(4, 1), C(6, 1) } })), false)
		apply(s, 2, { kind = "play", cards = { C(6, 1), C(6, 2) } })
		T.eq(s.turn, 3)
	end)

	T.test("when everyone passes the last player leads", function()
		local s = setup({ { C(5, 1), C(9, 1) }, { C(4, 1), C(7, 1) }, { C(3, 1), C(8, 1) } })
		apply(s, 1, { kind = "play", cards = { C(9, 1) } })
		apply(s, 2, { kind = "pass" })
		apply(s, 3, { kind = "pass" })
		T.eq(s.pile, nil)
		T.eq(s.turn, 1)
	end)

	T.test("going out records the place and the round ends with one left", function()
		local s = setup({ { C(9, 1) }, { C(4, 1), C(7, 1) }, { C(3, 1), C(8, 1) } })
		s.rounds = 1
		apply(s, 1, { kind = "play", cards = { C(9, 1) } })
		T.eq(s.finished[1], 1)
		apply(s, 2, { kind = "pass" })
		apply(s, 3, { kind = "pass" })
		T.eq(s.turn, 2, "next player still in leads")
		apply(s, 2, { kind = "play", cards = { C(4, 1) } })
		apply(s, 3, { kind = "play", cards = { C(8, 1) } })
		apply(s, 2, { kind = "pass" }) -- a 7 can't beat the 8
		apply(s, 3, { kind = "play", cards = { C(3, 1) } })
		local result = President.getResult(s) :: any
		T.ok(result ~= nil)
		T.eq(s.order[1], 1)
		T.eq(s.order[2], 3)
		T.eq(s.order[3], 2)
		T.eq(result.winners[1], 1)
	end)

	T.test("the Beggar's best cards go to the President", function()
		local s = President.new(4, { rules = { rounds = 2 } }, T.Random.new(5))
		s.order = { 2, 1, 4, 3 }
		s.round = 1
		s.phase = "between"
		-- Redeal and swap: the new hands are random, so check the swap itself.
		President.onTimeout(s)
		T.eq(#s.exchange, 2)
		T.eq(s.exchange[1].from, 3)
		T.eq(s.exchange[1].to, 2)
		T.eq(s.turn, 3, "the Beggar leads")
		T.ok(table.find(s.hands[2], s.exchange[1].gave[1]) ~= nil)
		T.eq(President.getView(s, 1).exchange[1].gave, nil, "others don't see the cards")
		-- The President and Vice President pick what to give back, at the same time.
		T.eq(s.phase, "giveback")
		local active = President.getActiveSeats(s)
		T.eq(#active, 2)
		T.eq((President.validateMove(s, 3, { kind = "pass" })), false, "no plays during the swap")
		local high = PlayingCards.sortBy(s.hands[2], President.power)
		local back = { high[#high], high[#high - 1] }
		T.eq((President.validateMove(s, 2, { kind = "giveback", cards = { back[1] } })), false, "2 cards")
		apply(s, 2, { kind = "giveback", cards = back })
		T.ok(table.find(s.hands[3], back[1]) ~= nil, "the Beggar gets the chosen cards")
		T.eq(s.phase, "giveback")
		local vp = s.hands[1][1]
		apply(s, 1, { kind = "giveback", cards = { vp } })
		T.eq(s.phase, "play")
		T.eq(#s.hands[2], 13)
		T.eq(#s.hands[3], 13)
	end)

	T.test("house rules: no lockout, 3 of clubs, single 2 on anything, led 2s, revolution 3s", function()
		local s = setup({ { C(9, 1), C(10, 1) }, { C(4, 1), C(13, 1) }, { C(3, 1), C(12, 1) } })
		s.lockout = false
		apply(s, 1, { kind = "play", cards = { C(9, 1) } })
		apply(s, 2, { kind = "pass" })
		apply(s, 3, { kind = "play", cards = { C(12, 1) } })
		T.eq(s.turn, 1)
		apply(s, 1, { kind = "pass" })
		T.eq(s.turn, 2, "a pass doesn't lock you out")
		apply(s, 2, { kind = "play", cards = { C(13, 1) } })

		local first = President.new(4, nil, T.Random.new(3))
		local leader = first.turn
		local other = nil
		for _, id in first.hands[leader] do
			if id ~= C(3, 4) then
				other = id
			end
		end
		T.eq((President.validateMove(first, leader, { kind = "play", cards = { other } })), false, "must lead the 3 of clubs")

		local two = setup({ { C(2, 1), C(2, 2), C(5, 1) }, { C(9, 1), C(9, 2), C(4, 1) }, { C(3, 1), C(8, 1) } })
		two.twoClears = true
		apply(two, 1, { kind = "play", cards = { C(2, 1) } })
		T.ok(two.pile ~= nil, "a led 2 doesn't clear")
		local pair = setup({ { C(2, 1), C(5, 1) }, { C(9, 1), C(9, 2), C(4, 1) }, { C(3, 1), C(8, 1) } })
		pair.twoClears = true
		pair.turn = 2
		apply(pair, 2, { kind = "play", cards = { C(9, 1), C(9, 2) } })
		apply(pair, 3, { kind = "pass" })
		apply(pair, 1, { kind = "play", cards = { C(2, 1) } })
		T.eq(pair.pile, nil, "a single 2 clears a pair")
		T.eq(pair.turn, 1)

		local rev = setup({ { C(3, 2), C(5, 1) }, { C(9, 1), C(4, 1) }, { C(6, 1), C(8, 1) } })
		rev.twoClears = true
		rev.revolution = true
		rev.turn = 2
		apply(rev, 2, { kind = "play", cards = { C(9, 1) } })
		apply(rev, 3, { kind = "play", cards = { C(6, 1) } })
		apply(rev, 1, { kind = "play", cards = { C(3, 2) } })
		T.eq(rev.pile, nil, "in a revolution 3s clear")
	end)

	T.test("house rules: same rank skips, 8s clear, downfall; ties go to the last round's order", function()
		local s = setup({ { C(9, 1), C(5, 1) }, { C(9, 2), C(4, 1) }, { C(10, 3), C(8, 1) }, { C(11, 1), C(6, 1) } })
		s.sameRankSkips = true
		apply(s, 1, { kind = "play", cards = { C(9, 1) } })
		apply(s, 2, { kind = "play", cards = { C(9, 2) } })
		T.eq(s.turn, 4, "seat 3 is skipped")

		local e = setup({ { C(8, 1), C(5, 1) }, { C(4, 1), C(13, 1) }, { C(3, 1), C(12, 1) } })
		e.eightClears = true
		apply(e, 1, { kind = "play", cards = { C(8, 1) } })
		T.eq(e.pile, nil)
		T.eq(e.turn, 1)

		local d = setup({ { C(9, 1) }, { C(4, 1), C(13, 1) }, { C(3, 1), C(12, 1) } })
		d.downfall = true
		d.order = { 2, 3, 1 } -- seat 2 was President
		d.rounds = 5
		apply(d, 1, { kind = "play", cards = { C(9, 1) } })
		T.eq(#d.hands[2], 0, "the President fell")
		T.eq(d.phase, "between", "only one player still holds cards")
		T.eq(d.order[3], 2, "fell to Beggar")

		local t = setup({ {}, {}, {} })
		t.over = true
		t.points = { 4, 4, 1 }
		t.order = { 2, 1, 3 }
		local result = President.getResult(t) :: any
		T.eq(result.isDraw, false)
		T.eq(result.winners[1], 2)
	end)

	T.test("bot games always finish", function()
		for _, level in { "easy", "medium", "hard" } do
			for seats = 3, 8 do
				local rng = T.Random.new(seats * 11 + #level)
				local s = President.new(seats, { botLevel = level }, rng)
				sim(President, s, rng, 20000)
				T.ok(President.getResult(s) ~= nil, `{level} {seats}-seat game should finish`)
				T.eq(s.round, 3)
			end
		end
	end)
end
