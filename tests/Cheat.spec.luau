local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Cheat = require(ReplicatedStorage.Shared.Games.Cheat)
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local sim = require(script.Parent.CardSim)

return function(T)
	local C = PlayingCards.make

	local function setup(hands)
		local s = Cheat.new(#hands, { botLevel = "medium" }, T.Random.new(1))
		s.hands = hands
		s.pile = {}
		s.turn = 1
		s.called = 5
		return s
	end

	local function apply(s, seat, move)
		local ok, err = Cheat.validateMove(s, seat, move)
		assert(ok, err)
		Cheat.applyMove(s, seat, move)
	end

	T.test("deals the whole deck", function()
		local s = Cheat.new(5, nil, T.Random.new(4))
		local n = 0
		for seat = 1, 5 do
			n += #s.hands[seat]
		end
		T.eq(n, 52)
	end)

	T.test("rejects bad plays", function()
		local s = setup({ { C(5, 1), C(9, 1) }, { C(2, 1) }, { C(3, 1) } })
		T.eq((Cheat.validateMove(s, 2, { kind = "play", cards = { C(2, 1) } })), false, "not your turn")
		T.eq((Cheat.validateMove(s, 1, { kind = "play", cards = { C(2, 1) } })), false, "not your card")
		T.eq((Cheat.validateMove(s, 1, { kind = "play", cards = {} })), false)
		T.eq((Cheat.validateMove(s, 1, { kind = "play", cards = { C(5, 1), C(5, 1) } })), false, "duplicates")
		T.eq((Cheat.validateMove(s, 1, { kind = "play", cards = "x" })), false)
		T.eq((Cheat.validateMove(s, 1, { kind = "doubt" })), false, "nothing to doubt")
		T.ok(Cheat.validateMove(s, 1, { kind = "play", cards = { C(9, 1) } }), "bluffing is allowed")
	end)

	T.test("doubting a bluff hands the pile to the bluffer", function()
		local s = setup({ { C(9, 1), C(4, 1) }, { C(2, 1) }, { C(3, 1) } })
		s.pile = { C(7, 2) }
		apply(s, 1, { kind = "play", cards = { C(9, 1) } })
		T.eq(s.phase, "doubt")
		T.eq((Cheat.validateMove(s, 1, { kind = "doubt" })), false, "can't doubt yourself")
		apply(s, 2, { kind = "doubt" })
		T.eq(s.reveal.honest, false)
		T.eq(s.reveal.loser, 1)
		T.eq(#s.hands[1], 3)
		Cheat.onTimeout(s)
		T.eq(s.turn, 2)
		T.eq(s.called, 6)
	end)

	T.test("doubting the truth hands the pile to the doubter", function()
		local s = setup({ { C(5, 1), C(5, 2), C(4, 1) }, { C(2, 1) }, { C(3, 1) } })
		apply(s, 1, { kind = "play", cards = { C(5, 1), C(5, 2) } })
		apply(s, 3, { kind = "doubt" })
		T.eq(s.reveal.honest, true)
		T.eq(#s.hands[3], 3)
	end)

	T.test("an honest last play wins; nobody doubting also wins", function()
		local s = setup({ { C(5, 1) }, { C(2, 1) }, { C(3, 1) } })
		apply(s, 1, { kind = "play", cards = { C(5, 1) } })
		apply(s, 2, { kind = "doubt" })
		T.eq((Cheat.getResult(s) :: any).winners[1], 1)

		local quiet = setup({ { C(9, 1) }, { C(2, 1) }, { C(3, 1) } })
		apply(quiet, 1, { kind = "play", cards = { C(9, 1) } })
		apply(quiet, 2, { kind = "pass" })
		apply(quiet, 3, { kind = "pass" })
		T.eq((Cheat.getResult(quiet) :: any).winners[1], 1)
	end)

	T.test("other hands stay hidden; the reveal is public", function()
		local s = setup({ { C(9, 1), C(4, 1) }, { C(2, 1) }, { C(3, 1) } })
		apply(s, 1, { kind = "play", cards = { C(9, 1) } })
		local view = Cheat.getView(s, 2)
		T.eq(view.hand[1], C(2, 1))
		T.eq(view.lastPlay.count, 1)
		T.eq(view.reveal, nil)
		apply(s, 2, { kind = "doubt" })
		T.eq(Cheat.getView(s, 3).reveal.cards[1], C(9, 1))
	end)

	T.test("bot games always finish", function()
		for _, level in { "easy", "medium", "hard" } do
			for seats = 3, 8 do
				local rng = T.Random.new(seats * 7 + #level)
				local s = Cheat.new(seats, { botLevel = level }, rng)
				sim(Cheat, s, rng, 20000)
				T.ok(Cheat.getResult(s) ~= nil, `{level} {seats}-seat game should finish`)
			end
		end
	end)
end
