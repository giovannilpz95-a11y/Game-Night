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
		T.eq((Palace.validateMove(s, 1, { kind = "pickup" })), true, "you may pick up even when you could play")
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

	T.test("the lowest card in hand or face up starts; in hand it must be played first", function()
		local s = Palace.new(2, nil, T.Random.new(3))
		s.hands = { { C(9, 1), C(4, 2), C(4, 3) }, { C(5, 1), C(6, 1), C(7, 1) } }
		s.up = { { C(12, 1), C(13, 1), C(1, 2) }, { C(3, 1), C(11, 2), C(12, 2) } }
		apply(s, 1, { kind = "ready" })
		apply(s, 2, { kind = "ready" })
		T.eq(s.turn, 2, "the face-up 3 is the lowest card")
		T.eq(s.mustPlay, nil, "a face-up card can't be played yet")
		local t = Palace.new(2, nil, T.Random.new(3))
		t.hands = { { C(9, 1), C(4, 2), C(4, 3) }, { C(5, 1), C(6, 1), C(7, 1) } }
		t.up = { { C(12, 1), C(13, 1), C(1, 2) }, { C(8, 1), C(11, 2), C(12, 2) } }
		apply(t, 1, { kind = "ready" })
		apply(t, 2, { kind = "ready" })
		T.eq(t.turn, 1)
		T.eq((Palace.validateMove(t, 1, { kind = "play", cards = { C(9, 1) } })), false, "start with a 4")
		for _, move in Palace.getLegalMoves(t, 1) do
			T.eq(PlayingCards.rank(move.cards[1]), 4)
		end
		apply(t, 1, { kind = "play", cards = { C(4, 3) } })
		T.eq(t.mustPlay, nil)
	end)

	T.test("house rules: lower card, 8 skips, invisible 3, gamble on the deck", function()
		local s = playing({ { C(4, 1), C(9, 1) }, { C(6, 1) } }, { {}, {} }, { { false, false, false }, { false, false, false } })
		s.lowerRank = 5
		s.pile = { C(5, 3) }
		T.eq(Palace.canPlay(s, C(4, 1)), true)
		T.eq(Palace.canPlay(s, C(9, 1)), false)
		T.eq(Palace.canPlay(s, C(10, 1)), true)
		s.lowerRank = 9
		s.pile = { C(9, 3) }
		T.eq(Palace.canPlay(s, C(4, 1)), true)
		T.eq(Palace.canPlay(s, C(12, 1)), false)
		T.eq(Palace.new(2, { rules = { sevenLower = true } }, T.Random.new(1)).lowerRank, 7)

		-- 8 skips: in 3 players, two 8s skip both others: back to you.
		local e = playing({ { C(8, 1), C(8, 2), C(13, 1) }, { C(6, 1) }, { C(7, 1) } }, { {}, {}, {} }, { { false, false, false }, { false, false, false }, { false, false, false } })
		e.eightSkips = true
		apply(e, 1, { kind = "play", cards = { C(8, 1) } })
		T.eq(e.turn, 3, "one 8 skips seat 2")
		local e2 = playing({ { C(8, 1), C(8, 2), C(13, 1) }, { C(6, 1) }, { C(7, 1) } }, { {}, {}, {} }, { { false, false, false }, { false, false, false }, { false, false, false } })
		e2.eightSkips = true
		apply(e2, 1, { kind = "play", cards = { C(8, 1), C(8, 2) } })
		T.eq(e2.turn, 1, "two 8s skip both")

		-- Invisible 3: the 9 under it still counts.
		local v = playing({ { C(5, 1), C(3, 2) }, { C(6, 1) } }, { {}, {} }, { { false, false, false }, { false, false, false } })
		v.invisibleThree = true
		v.pile = { C(9, 3) }
		T.eq(Palace.canPlay(v, C(3, 2)), true)
		apply(v, 1, { kind = "play", cards = { C(3, 2) } })
		T.eq(Palace.top(v), C(9, 3))
		T.eq(Palace.canPlay(v, C(6, 1)), false)

		-- Gamble: stuck with a hand, flip the deck's top.
		local g = playing({ { C(4, 1) }, { C(6, 1) } }, { {}, {} }, { { false, false, false }, { false, false, false } }, { C(5, 4), C(13, 2) })
		g.gamble = true
		g.pile = { C(12, 3) }
		T.ok(Palace.canGamble(g, 1))
		apply(g, 1, { kind = "gamble" })
		T.eq(g.pile[#g.pile], C(13, 2), "the King fits")
		T.eq(g.turn, 2)
		local g2 = playing({ { C(4, 1) }, { C(6, 1) } }, { {}, {} }, { { false, false, false }, { false, false, false } }, { C(5, 4) })
		g2.gamble = true
		g2.pile = { C(12, 3) }
		apply(g2, 1, { kind = "gamble" })
		T.eq(#g2.pile, 0)
		T.eq(#g2.hands[1], 3, "picked up the Queen and the 5")
		T.eq((Palace.validateMove(playing({ { C(4, 1) }, { C(6, 1) } }, { {}, {} }, { { false, false, false }, { false, false, false } }, { C(5, 4) }), 1, { kind = "gamble" })), false, "house rule off")
	end)

	T.test("face-up cards keep their table slots; setup AFK just readies", function()
		local s = Palace.new(2, nil, T.Random.new(4))
		local slots = table.clone(s.upSlots[1])
		local h, u = s.hands[1][1], s.up[1][2]
		apply(s, 1, { kind = "swap", hand = h, up = u })
		T.eq(s.upSlots[1][2], h)
		T.eq(s.upSlots[1][1], slots[1])
		T.eq(Palace.getTurnKey(s), "setup")
		T.eq(Palace.chooseAfkMove(s, 2, T.Random.new(1)).kind, "ready")
		apply(s, 1, { kind = "ready" })
		apply(s, 2, { kind = "ready" })
		T.eq(Palace.chooseAfkMove(s, s.turn, T.Random.new(1)), nil)
		-- Play a face-up card: its slot empties, the others stay.
		local p = Palace.new(2, nil, T.Random.new(4))
		p.phase = "play"
		p.turn = 1
		p.hands[1] = {}
		p.draw = {}
		p.pile = {}
		local first = p.up[1][1]
		local others = { p.upSlots[1][2], p.upSlots[1][3] }
		apply(p, 1, { kind = "play", cards = { first } })
		T.eq(p.upSlots[1][1], false)
		T.eq(p.upSlots[1][2], others[1])
		T.eq(p.upSlots[1][3], others[2])
	end)
end
