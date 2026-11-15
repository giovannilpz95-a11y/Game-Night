local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SlapStack = require(ReplicatedStorage.Shared.Games.SlapStack)
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local sim = require(script.Parent.CardSim)

return function(T)
	local C = PlayingCards.make

	-- piles are top-last
	local function setup(piles, center, options)
		local s = SlapStack.new(#piles, options or { botLevel = "medium" }, T.Random.new(1))
		s.piles = piles
		s.center = center or {}
		s.turn = 1
		return s
	end

	local function apply(s, seat, move)
		local ok, err = SlapStack.validateMove(s, seat, move)
		assert(ok, err)
		SlapStack.applyMove(s, seat, move)
	end

	T.test("only the turn player flips", function()
		local s = setup({ { C(5, 1) }, { C(6, 1) } })
		T.eq((SlapStack.validateMove(s, 2, { kind = "flip" })), false)
		T.eq((SlapStack.validateMove(s, 1, { kind = "slap" })), false, "nothing to slap")
		apply(s, 1, { kind = "flip" })
		T.eq(s.turn, 2)
	end)

	T.test("a double or a sandwich takes the pile", function()
		local s = setup({ { C(2, 1), C(5, 2) }, { C(9, 3), C(6, 1) } }, { C(5, 1) })
		apply(s, 1, { kind = "flip" })
		apply(s, 2, { kind = "slap" })
		T.eq(#s.center, 0)
		T.eq(#s.piles[2], 4)
		T.eq(s.turn, 2)

		local sandwich = setup({ { C(2, 2), C(7, 2) }, { C(9, 3) } }, { C(7, 1), C(4, 1) })
		apply(sandwich, 1, { kind = "flip" })
		T.ok(SlapStack.canSlap(sandwich))
		local off = setup({ { C(7, 2) }, { C(9, 3) } }, { C(7, 1), C(4, 1) }, { rules = { sandwich = false } })
		apply(off, 1, { kind = "flip" })
		T.eq(SlapStack.canSlap(off), false, "sandwich house rule off")
	end)

	T.test("a bad slap burns a card face down under the pile and locks you out", function()
		local s = setup({ { C(2, 1), C(5, 2) }, { C(9, 3), C(6, 1) } }, { C(8, 1) })
		apply(s, 2, { kind = "slap" })
		T.eq(#s.piles[2], 1)
		T.eq(#s.center, 1, "the face-up pile is unchanged")
		T.eq(s.under[1], C(6, 1))
		T.eq((SlapStack.validateMove(s, 2, { kind = "slap" })), false, "locked out until the next flip")
		apply(s, 1, { kind = "flip" })
		-- 5 on 8: nothing, but seat 2 may try again
		local ok, err = SlapStack.validateMove(s, 2, { kind = "slap" })
		T.ok(ok, err)
		-- whoever takes the pile gets the burned card too
		local d = setup({ { C(3, 3), C(8, 2) }, { C(9, 3), C(6, 1) } }, { C(8, 1) })
		apply(d, 2, { kind = "slap" })
		apply(d, 1, { kind = "flip" })
		apply(d, 2, { kind = "slap" })
		T.eq(#d.piles[2], 4)
		T.eq(#d.under, 0)
	end)

	T.test("tens across a face card and a run of four", function()
		local s = setup({ { C(9, 1) }, { C(2, 2) } }, { C(1, 2), C(13, 3) }, { rules = { tens = true } })
		apply(s, 1, { kind = "flip" })
		T.ok(SlapStack.canSlap(s), "A K 9")
		local r = setup({ { C(1, 1) }, { C(2, 2) } }, { C(11, 2), C(12, 3), C(13, 4) }, { rules = { run = true } })
		apply(r, 1, { kind = "flip" })
		T.ok(SlapStack.canSlap(r), "J Q K A")
		local d = setup({ { C(6, 1) }, { C(2, 2) } }, { C(9, 2), C(8, 3), C(7, 4) }, { rules = { run = true } })
		apply(d, 1, { kind = "flip" })
		T.ok(SlapStack.canSlap(d), "9 8 7 6")
		local off = setup({ { C(6, 1) }, { C(2, 2) } }, { C(9, 2), C(8, 3), C(7, 4) })
		apply(off, 1, { kind = "flip" })
		T.eq(SlapStack.canSlap(off), false, "runs off by default")
	end)

	T.test("a face card challenge: run out of tries and the challenger collects", function()
		-- Seat 1 flips a Queen (2 tries); seat 2 flips two number cards.
		local s = setup({ { C(4, 1), C(12, 1) }, { C(3, 2), C(9, 2), C(8, 3) } })
		apply(s, 1, { kind = "flip" })
		T.eq(s.challenge.tries, 2)
		T.eq(s.turn, 2)
		apply(s, 2, { kind = "flip" })
		T.eq(s.turn, 2, "keeps trying")
		apply(s, 2, { kind = "flip" })
		T.eq(s.collect, 1)
		T.eq((SlapStack.validateMove(s, 2, { kind = "flip" })), false, "pile is being collected")
		SlapStack.onTimeout(s)
		T.eq(#s.piles[1], 4)
		T.eq(s.turn, 1)
	end)

	T.test("answering with a face card passes the challenge on", function()
		local s = setup({ { C(4, 1), C(12, 1) }, { C(3, 2), C(11, 2) } })
		apply(s, 1, { kind = "flip" })
		apply(s, 2, { kind = "flip" })
		T.eq(s.challenge.owner, 2)
		T.eq(s.challenge.tries, 1)
		T.eq(s.turn, 1)
	end)

	T.test("last player with cards wins (slap-in off)", function()
		local s = setup({ { C(4, 1) }, { C(3, 2), C(9, 2) } }, nil, { rules = { slapIn = "never" } })
		apply(s, 1, { kind = "flip" })
		local result = SlapStack.getResult(s) :: any
		T.eq(result.winners[1], 2)
		T.eq(#s.piles[2], 3, "winner takes the middle")
	end)

	T.test("out of cards: three last-chance flips, then the winner", function()
		local s = setup({ { C(4, 1) }, { C(3, 2), C(9, 2), C(6, 3), C(10, 1) } })
		apply(s, 1, { kind = "flip" })
		T.eq(SlapStack.getResult(s), nil)
		T.eq(s.lastChance, 3)
		T.eq(s.turn, 2)
		T.eq(SlapStack.getActiveSeats(s)[1], 2)
		T.ok(table.find(SlapStack.getInterruptSeats(s), 1) ~= nil, "seat 1 may still slap in")
		for _ = 1, 3 do
			apply(s, 2, { kind = "flip" })
		end
		T.ok(s.finalBeat, "one beat to slap the last card")
		T.eq(SlapStack.getResult(s), nil)
		SlapStack.onTimeout(s)
		local result = SlapStack.getResult(s) :: any
		T.eq(result.winners[1], 2)
		T.eq(#s.piles[2] + #s.center, 5)
	end)

	T.test("a good slap brings you back in, once", function()
		local s = setup({ { C(4, 1) }, { C(3, 2), C(9, 2), C(4, 3), C(10, 1) } })
		apply(s, 1, { kind = "flip" }) -- 4 down, seat 1 is out
		apply(s, 2, { kind = "flip" }) -- 10
		apply(s, 2, { kind = "flip" }) -- 4: sandwich 4-10-4
		T.eq((SlapStack.validateMove(s, 2, { kind = "slap" })), false, "the last player doesn't slap during the last chance")
		apply(s, 1, { kind = "slap" })
		T.eq(#s.piles[1], 3, "back in with the pile")
		T.eq(s.lastChance, nil)
		T.eq(s.turn, 1)
		T.eq(SlapStack.canSlapIn(s, 1), false, "no second slap-in")
	end)

	T.test("three bad slaps while out and you're out for good", function()
		local s = setup({ { C(4, 1) }, { C(3, 2), C(9, 2), C(6, 3), C(10, 1), C(2, 2), C(8, 3) } })
		apply(s, 1, { kind = "flip" })
		for i = 1, 3 do
			apply(s, 2, { kind = "flip" })
			if i < 3 then
				apply(s, 1, { kind = "slap" })
				T.eq(s.strikes[1], i)
			end
		end
		-- 2 strikes, last flip: the third strike ends it at once
		apply(s, 1, { kind = "slap" })
		local result = SlapStack.getResult(s) :: any
		T.ok(result ~= nil)
		T.eq(result.winners[1], 2)
	end)

	T.test("an away player is flipped for, never slapped for", function()
		local s = setup({ { C(2, 1), C(5, 2) }, { C(9, 3), C(5, 1) } }, { C(7, 1) })
		apply(s, 1, { kind = "flip" }) -- 5 on 7
		apply(s, 2, { kind = "flip" }) -- 5 on 5: a double
		T.ok(SlapStack.canSlap(s))
		T.eq(SlapStack.chooseAfkMove(s, 2, T.Random.new(1)), nil, "seat 2 isn't on turn and won't slap")
		T.eq(SlapStack.getActiveSeats(s)[1], 1)
		local move = SlapStack.chooseAfkMove(s, 1, T.Random.new(1)) :: any
		T.eq(move.kind, "flip")
	end)

	T.test("bot games always finish", function()
		for _, level in { "easy", "medium", "hard" } do
			for seats = 2, 6 do
				local rng = T.Random.new(seats * 5 + #level)
				local s = SlapStack.new(seats, { botLevel = level }, rng)
				sim(SlapStack, s, rng, 20000)
				T.ok(SlapStack.getResult(s) ~= nil, `{level} {seats}-seat game should finish`)
				local total = #s.center + #s.under
				for seat = 1, seats do
					total += #s.piles[seat]
				end
				T.eq(total, 52, "no cards lost")
			end
		end
	end)
end
