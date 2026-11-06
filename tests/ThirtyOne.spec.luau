local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ThirtyOne = require(ReplicatedStorage.Shared.Games.ThirtyOne)
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local sim = require(script.Parent.CardSim)

return function(T)
	local C = PlayingCards.make
	local S, H, D, CL = 1, 2, 3, 4

	local function setup(hands, discard, stock)
		local s = ThirtyOne.new(#hands, { botLevel = "medium" }, T.Random.new(1))
		s.hands = hands
		s.discard = discard
		s.stock = stock
		s.turn = 1
		s.phase = "draw"
		s.turnsThisRound = 0
		s.knocker = nil
		s.phase = "draw"
		return s
	end

	local function apply(s, seat, move)
		local ok, err = ThirtyOne.validateMove(s, seat, move)
		assert(ok, err)
		ThirtyOne.applyMove(s, seat, move)
	end

	T.test("hand value is the best single suit", function()
		T.eq(ThirtyOne.value({ C(1, S), C(13, S), C(9, H) }), 21)
		T.eq(ThirtyOne.value({ C(1, S), C(13, S), C(12, S) }), 31)
		T.eq(ThirtyOne.value({ C(2, S), C(3, H), C(4, D) }), 4)
	end)

	T.test("draw then discard; can't throw back the discard you took", function()
		local s = setup({ { C(2, S), C(3, S), C(4, S) }, { C(2, H), C(3, H), C(4, H) } }, { C(9, S) }, { C(5, D), C(6, D) })
		T.eq((ThirtyOne.validateMove(s, 1, { kind = "discard", card = C(2, S) })), false, "draw first")
		T.eq((ThirtyOne.validateMove(s, 1, { kind = "knock" })), false, "too early to knock")
		apply(s, 1, { kind = "draw", from = "discard" })
		T.eq((ThirtyOne.validateMove(s, 1, { kind = "discard", card = C(9, S) })), false)
		apply(s, 1, { kind = "discard", card = C(2, S) })
		T.eq(s.turn, 2)
		T.eq(s.discard[#s.discard], C(2, S))
	end)

	T.test("a knock gives everyone one more turn; lowest loses a life", function()
		local s = setup({ { C(1, S), C(13, S), C(9, S) }, { C(2, H), C(3, H), C(4, D) }, { C(10, D), C(11, D), C(5, CL) } }, { C(2, D) }, { C(3, CL), C(4, CL), C(6, CL) })
		s.turnsThisRound = 3
		apply(s, 1, { kind = "knock" })
		T.eq(s.knocker, 1)
		apply(s, 2, { kind = "draw", from = "stock" })
		apply(s, 2, { kind = "discard", card = C(6, CL) })
		T.eq(s.phase, "draw")
		apply(s, 3, { kind = "draw", from = "stock" })
		apply(s, 3, { kind = "discard", card = C(4, CL) })
		T.eq(s.phase, "reveal")
		T.eq(s.lives[2], 2)
		T.eq(s.lives[1], 3)
	end)

	T.test("a knocker with the lowest hand loses two lives", function()
		local s = setup({ { C(2, S), C(3, H), C(4, D) }, { C(1, H), C(13, H), C(4, H) } }, { C(2, D) }, { C(3, CL), C(5, CL) })
		s.turnsThisRound = 2
		apply(s, 1, { kind = "knock" })
		apply(s, 2, { kind = "draw", from = "stock" })
		apply(s, 2, { kind = "discard", card = C(5, CL) })
		T.eq(s.lives[1], 1)
	end)

	T.test("a knocker tied for lowest is safe; the others tied with them lose one", function()
		local s = setup({ { C(2, S), C(3, S), C(4, S) }, { C(2, H), C(3, H), C(4, H) }, { C(10, D), C(9, D), C(5, H) } }, { C(2, D) }, { C(5, CL), C(6, CL), C(7, CL) })
		s.turnsThisRound = 3
		apply(s, 1, { kind = "knock" })
		apply(s, 2, { kind = "draw", from = "stock" })
		apply(s, 2, { kind = "discard", card = C(7, CL) })
		apply(s, 3, { kind = "draw", from = "stock" })
		apply(s, 3, { kind = "discard", card = C(6, CL) })
		T.eq(s.phase, "reveal")
		T.eq(s.lives[1], 3, "the knocker tied for lowest keeps every life")
		T.eq(s.lives[2], 2, "the player tied with the knocker loses one")
		T.eq(s.lives[3], 3)
	end)

	T.test("hitting 31 is a Blitz: everyone else loses a life", function()
		local s = setup({ { C(1, S), C(13, S), C(2, H) }, { C(2, D), C(3, D), C(4, D) }, { C(5, H), C(6, H), C(7, H) } }, { C(12, S) }, { C(3, CL) })
		apply(s, 1, { kind = "draw", from = "discard" })
		apply(s, 1, { kind = "discard", card = C(2, H) })
		T.eq(s.showdown.blitz, 1)
		T.eq(s.lives[1], 3)
		T.eq(s.lives[2], 2)
		T.eq(s.lives[3], 2)
	end)

	T.test("last player with lives wins", function()
		local s = setup({ { C(2, S), C(3, H), C(4, D) }, { C(1, H), C(13, H), C(4, H) } }, { C(2, D) }, { C(3, CL), C(5, CL) })
		s.lives = { 1, 3 }
		s.turnsThisRound = 2
		apply(s, 1, { kind = "knock" })
		apply(s, 2, { kind = "draw", from = "stock" })
		apply(s, 2, { kind = "discard", card = C(5, CL) })
		T.eq((ThirtyOne.getResult(s) :: any).winners[1], 2)
	end)

	T.test("bot games always finish", function()
		for _, level in { "easy", "medium", "hard" } do
			for seats = 2, 8 do
				local rng = T.Random.new(seats * 3 + #level)
				local s = ThirtyOne.new(seats, { botLevel = level }, rng)
				sim(ThirtyOne, s, rng, 20000)
				T.ok(ThirtyOne.getResult(s) ~= nil, `{level} {seats}-seat game should finish`)
			end
		end
	end)
end
