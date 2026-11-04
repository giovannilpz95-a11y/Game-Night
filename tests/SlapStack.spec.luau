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

	T.test("a bad slap burns a card under the pile", function()
		local s = setup({ { C(2, 1), C(5, 2) }, { C(9, 3), C(6, 1) } }, { C(8, 1) })
		apply(s, 2, { kind = "slap" })
		T.eq(#s.piles[2], 1)
		T.eq(s.center[1], C(6, 1))
		T.eq(s.center[#s.center], C(8, 1))
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

	T.test("last player with cards wins", function()
		local s = setup({ { C(4, 1) }, { C(3, 2), C(9, 2) } })
		apply(s, 1, { kind = "flip" })
		local result = SlapStack.getResult(s) :: any
		T.eq(result.winners[1], 2)
		T.eq(#s.piles[2], 3, "winner takes the middle")
	end)

	T.test("bot games always finish", function()
		for _, level in { "easy", "medium", "hard" } do
			for seats = 2, 6 do
				local rng = T.Random.new(seats * 5 + #level)
				local s = SlapStack.new(seats, { botLevel = level }, rng)
				sim(SlapStack, s, rng, 20000)
				T.ok(SlapStack.getResult(s) ~= nil, `{level} {seats}-seat game should finish`)
				local total = #s.center
				for seat = 1, seats do
					total += #s.piles[seat]
				end
				T.eq(total, 52, "no cards lost")
			end
		end
	end)
end
