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
