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
		T.eq(s.turn, 3, "the snapper flips next")
	end)

	T.test("the color house rule needs the same color too", function()
		local s = setup({ { C(7, 2) }, { C(3, 1) } }, { {}, { C(7, 1) } }, { rules = { match = "color" } })
		apply(s, 1, { kind = "flip" })
		T.eq(Snap.canSnap(s), false, "red 7 and black 7")
		local t = setup({ { C(7, 2) }, { C(3, 1) } }, { {}, { C(7, 3) } }, { rules = { match = "color" } })
		apply(t, 1, { kind = "flip" })
		T.ok(Snap.canSnap(t), "two red 7s")
	end)

	T.test("a wrong snap gives a card to the player on your left", function()
		local s = setup({ { C(2, 1), C(5, 2) }, { C(9, 3) } }, { {}, {} })
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

	T.test("bot games always finish", function()
		for _, level in { "easy", "medium", "hard" } do
			for seats = 2, 6 do
				local rng = T.Random.new(seats * 7 + #level)
				local s = Snap.new(seats, { botLevel = level }, rng)
				sim(Snap, s, rng, 20000)
				T.ok(Snap.getResult(s) ~= nil, `{level} {seats}-seat game should finish`)
				local total = 0
				for seat = 1, seats do
					total += Snap.total(s, seat)
				end
				T.eq(total, 52, "no cards lost")
			end
		end
	end)
end
