local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Palace = require(ReplicatedStorage.Shared.Games.Palace)
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local sim = require(script.Parent.CardSim)

return function(T)
	local C = PlayingCards.make

	local function playing(hands, ups, downs, draw)
		local s = Palace.new(#hands, { botLevel = "medium" }, T.Random.new(1))
		s.hands = hands
		s.up = ups
		s.down = downs
		s.draw = draw or {}
		s.pile = {}
		s.phase = "play"
		s.turn = 1
		return s
	end

	local function apply(s, seat, move)
		local ok, err = Palace.validateMove(s, seat, move)
		assert(ok, err)
		Palace.applyMove(s, seat, move)
	end

	T.test("setup: swap with face-up cards, play starts when everyone is ready", function()
		local s = Palace.new(2, nil, T.Random.new(2))
		local h, u = s.hands[1][1], s.up[1][1]
		apply(s, 1, { kind = "swap", hand = h, up = u })
		T.ok(table.find(s.up[1], h) ~= nil)
		T.eq((Palace.validateMove(s, 1, { kind = "swap", hand = h, up = u })), false, "h is face up now")
		apply(s, 1, { kind = "ready" })
		T.eq(s.phase, "setup")
		apply(s, 2, { kind = "ready" })
		T.eq(s.phase, "play")
	end)

	T.test("play equal or higher, or pick up", function()
		local s = playing({ { C(5, 1), C(5, 2), C(9, 1) }, { C(4, 1), C(6, 1) } }, { {}, {} }, { { false, false, false }, { false, false, false } })
		s.pile = { C(7, 3) }
		T.eq((Palace.validateMove(s, 1, { kind = "play", cards = { C(5, 1) } })), false, "too low")
		T.eq((Palace.validateMove(s, 1, { kind = "pickup" })), false, "you can play the 9")
		apply(s, 1, { kind = "play", cards = { C(9, 1) } })
		T.eq(s.turn, 2)
		T.eq((Palace.validateMove(s, 2, { kind = "play", cards = { C(6, 1) } })), false)
		apply(s, 2, { kind = "pickup" })
		T.eq(#s.hands[2], 4)
		T.eq(#s.pile, 0)
	end)

	T.test("a 2 resets, a 10 burns and you go again", function()
		local s = playing({ { C(2, 1), C(10, 1), C(4, 1), C(8, 1) }, { C(3, 1), C(6, 1) } }, { {}, {} }, { { false, false, false }, { false, false, false } })
		s.pile = { C(13, 3) }
		apply(s, 1, { kind = "play", cards = { C(2, 1) } })
		T.eq(s.turn, 2)
		T.ok(Palace.validateMove(s, 2, { kind = "play", cards = { C(3, 1) } }), "anything on a 2")
		s.turn = 1
		apply(s, 1, { kind = "play", cards = { C(10, 1) } })
		T.eq(#s.pile, 0)
		T.eq(s.turn, 1, "goes again")
	end)

	T.test("four of a kind burns", function()
		local s = playing({ { C(8, 3), C(8, 4), C(5, 1) }, { C(3, 1) } }, { {}, {} }, { { false, false, false }, { false, false, false } })
		s.pile = { C(8, 1), C(8, 2) }
		apply(s, 1, { kind = "play", cards = { C(8, 3), C(8, 4) } })
		T.eq(#s.pile, 0)
		T.eq(s.turn, 1)
	end)

	T.test("face-up cards after the hand, then blind flips", function()
		local s = playing({ {}, { C(3, 1) } }, { { C(9, 1) }, {} }, { { C(4, 2), false, false }, { false, false, false } })
		s.pile = { C(6, 3) }
		T.eq(Palace.source(s, 1), "up")
		apply(s, 1, { kind = "play", cards = { C(9, 1) } })
		s.turn = 1
		T.eq(Palace.source(s, 1), "down")
		T.eq((Palace.validateMove(s, 1, { kind = "blind", index = 2 })), false, "used slot")
		apply(s, 1, { kind = "blind", index = 1 })
		T.eq(s.lastAction.ok, false, "a 4 can't go on a 9")
		T.eq(#s.hands[1], 3, "picked up the pile with it")
	end)

	T.test("out of cards wins", function()
		local s = playing({ {}, { C(3, 1) } }, { {}, {} }, { { C(9, 2), false, false }, { false, false, false } })
		apply(s, 1, { kind = "blind", index = 1 })
		T.eq((Palace.getResult(s) :: any).winners[1], 1)
	end)

	T.test("bot games always finish", function()
		for _, level in { "easy", "medium", "hard" } do
			for seats = 2, 5 do
				local rng = T.Random.new(seats * 19 + #level)
				local s = Palace.new(seats, { botLevel = level }, rng)
				sim(Palace, s, rng, 20000)
				T.ok(Palace.getResult(s) ~= nil, `{level} {seats}-seat game should finish`)
			end
		end
	end)
end
