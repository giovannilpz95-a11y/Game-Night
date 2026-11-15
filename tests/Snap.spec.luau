local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Snap = require(ReplicatedStorage.Shared.Games.Snap)
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local sim = require(script.Parent.CardSim)

return function(T)
	local C = PlayingCards.make

	-- piles are top-last
	local function setup(down, up, options)
		local s = Snap.new(#down, options or { botLevel = "medium" }, T.Random.new(1))
		s.down = down
		s.up = up
		s.turn = 1
		return s
	end

	local function apply(s, seat, move)
		local ok, err = Snap.validateMove(s, seat, move)
		assert(ok, err)
		Snap.applyMove(s, seat, move)
	end

	T.test("only the turn player flips, onto their own pile", function()
		local s = setup({ { C(5, 1) }, { C(6, 1) } }, { {}, {} })
		T.eq((Snap.validateMove(s, 2, { kind = "flip" })), false)
		T.eq((Snap.validateMove(s, 1, { kind = "nope" })), false)
		apply(s, 1, { kind = "flip" })
		T.eq(s.up[1][1], C(5, 1))
		T.eq(s.turn, 2)
	end)

	T.test("a match lets anyone snap both piles", function()
		local s = setup({ { C(2, 1), C(7, 2) }, { C(3, 1) }, { C(4, 4) } }, { {}, { C(7, 3) }, {} })
		apply(s, 1, { kind = "flip" })
		T.ok(Snap.canSnap(s))
		apply(s, 3, { kind = "snap" })
		T.eq(#s.up[1], 0)
		T.eq(#s.up[2], 0)
		T.eq(#s.down[3], 3)
		T.eq((Snap.validateMove(s, 1, { kind = "flip" })), false, "short pause")
		Snap.onTimeout(s)
		T.eq(s.turn, 2, "play goes on left of the last flipper")
	end)

	T.test("the color house rule needs the same color too", function()
		local s = setup({ { C(7, 2) }, { C(3, 1) } }, { {}, { C(7, 1) } }, { rules = { match = "color" } })
		apply(s, 1, { kind = "flip" })
		T.eq(Snap.canSnap(s), false, "red 7 and black 7")
		local t = setup({ { C(7, 2) }, { C(3, 1) } }, { {}, { C(7, 3) } }, { rules = { match = "color" } })
		apply(t, 1, { kind = "flip" })
		T.ok(Snap.canSnap(t), "two red 7s")
	end)

	T.test("house rule: a wrong snap gives a card to the player on your left", function()
		local s = setup({ { C(2, 1), C(5, 2) }, { C(9, 3) } }, { {}, {} }, { rules = { penalty = 1 } })
		apply(s, 1, { kind = "snap" })
		T.eq(#s.down[1], 1)
		T.eq(#s.down[2], 2)
		T.eq(s.down[2][1], C(5, 2), "under their pile")
	end)

	T.test("an empty face-down pile is refilled from the face-up pile", function()
		local s = setup({ {}, { C(9, 3) } }, { { C(2, 1), C(3, 1) }, {} })
		apply(s, 1, { kind = "flip" })
		T.eq(s.up[1][1], C(2, 1), "bottom of the old face-up pile comes up first")
		T.eq(#s.down[1], 1)
	end)

	T.test("last player with cards wins", function()
		local s = setup({ { C(4, 1) }, {} }, { {}, { C(4, 2) } })
		apply(s, 1, { kind = "flip" })
		apply(s, 1, { kind = "snap" })
		local result = Snap.getResult(s) :: any
		T.ok(result ~= nil)
		T.eq(result.winners[1], 1)
	end)

	T.test("a wrong snap sends your face-up pile to the Snap Pool, and a match with it wins the pool", function()
		local s = setup({ { C(2, 1), C(9, 2) }, { C(4, 3), C(9, 4) }, { C(6, 1) } }, { { C(5, 1), C(8, 1) }, {}, {} })
		apply(s, 2, { kind = "snap" }) -- nothing matches; seat 2 has no face-up pile, so one card goes
		T.eq(#s.pool, 1)
		T.eq(s.pool[1], C(9, 4))
		apply(s, 1, { kind = "snap" }) -- still wrong: seat 1's whole face-up pile goes in
		T.eq(#s.up[1], 0)
		T.eq(#s.pool, 3)
		T.eq(s.pool[#s.pool], C(8, 1), "their old top card is the pool's top")
		T.eq(s.lastAction.pool, true)
		apply(s, 1, { kind = "flip" }) -- 9 of seat 1 ... the pool shows an 8
		T.eq(Snap.canSnap(s), false)
		apply(s, 2, { kind = "flip" }) -- seat 2 flips a 4
		apply(s, 3, { kind = "flip" }) -- 6
		T.eq(Snap.canSnap(s), false)
		s.pool[#s.pool + 1] = C(6, 3) -- pretend the pool showed a 6
		T.ok(Snap.canSnap(s), "a top card matches the pool")
		local before = #s.down[2]
		apply(s, 2, { kind = "snap" })
		T.eq(#s.pool, 0)
		T.eq(#s.down[2], before + 4, "won the whole pool")
		T.eq(#s.up[3], 1, "the matching pile stays")
	end)

	T.test("owners only: a snap on someone else's match is a wrong snap", function()
		local s = setup({ { C(2, 1), C(7, 2) }, { C(3, 1) }, { C(4, 4), C(5, 4) } }, { {}, { C(7, 3) }, {} }, { rules = { owners = true } })
		apply(s, 1, { kind = "flip" })
		T.ok(Snap.canSnap(s, 2))
		T.eq(Snap.canSnap(s, 3), false)
		apply(s, 3, { kind = "snap" })
		T.eq(s.lastAction.kind, "badSnap")
		T.eq(#s.up[2], 1, "the piles stay")
		apply(s, 2, { kind = "snap" })
		T.eq(s.lastAction.kind, "snap")
	end)

	T.test("game length house rule and the long-game shuffle", function()
		local s = setup({ { C(2, 1) }, { C(3, 1) } }, { {}, {} }, { rules = { length = 0 } })
		s.flips = 5000
		apply(s, 1, { kind = "flip" })
		T.eq(Snap.getResult(s), nil, "no limit")
		local t = setup({ { C(2, 1) }, { C(3, 1) } }, { {}, {} }, { rules = { length = 250 } })
		t.flips = 249
		apply(t, 1, { kind = "flip" })
		T.ok(Snap.getResult(t) ~= nil, "ends at 250")
	end)

	T.test("idle: a person is flipped for on their turn and never snapped for", function()
		local s = setup({ { C(2, 1), C(7, 2) }, { C(3, 1) }, { C(4, 4) } }, { {}, { C(7, 3) }, {} })
		apply(s, 1, { kind = "flip" })
		T.ok(Snap.canSnap(s))
		T.eq(Snap.chooseAfkMove(s, 3, T.Random.new(1)), nil, "not their turn: no snap")
		local move = Snap.chooseAfkMove(s, 2, T.Random.new(1))
		T.eq(move.kind, "flip", "the flipper flips")
		T.eq(#Snap.getActiveSeats(s), 1)
		T.ok(table.find(Snap.getInterruptSeats(s), 3) ~= nil)
	end)

	T.test("bot games always finish", function()
		for _, level in { "easy", "medium", "hard" } do
			for seats = 2, 6 do
				local rng = T.Random.new(seats * 7 + #level)
				local s = Snap.new(seats, { botLevel = level }, rng)
				sim(Snap, s, rng, 20000)
				T.ok(Snap.getResult(s) ~= nil, `{level} {seats}-seat game should finish`)
				local total = #s.pool
				for seat = 1, seats do
					total += Snap.total(s, seat)
				end
				T.eq(total, 52, "no cards lost")
			end
		end
	end)
end
