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

	-- Seat 2 knocks; seats 3 and 1 take their last turns (drawing the stock's 7, 6 of clubs).
	local function knockRound(lives)
		local s = setup({ { C(2, S), C(3, H), C(4, D) }, { C(1, H), C(13, H), C(4, H) }, { C(10, D), C(11, D), C(5, CL) } }, { C(2, D) }, { C(6, CL), C(7, CL) })
		s.lives = lives
		s.turn = 2
		s.turnsThisRound = 3
		apply(s, 2, { kind = "knock" })
		apply(s, 3, { kind = "draw", from = "stock" })
		apply(s, 3, { kind = "discard", card = C(7, CL) })
		apply(s, 1, { kind = "draw", from = "stock" })
		apply(s, 1, { kind = "discard", card = C(6, CL) })
		return s
	end

	T.test("on the county: no hearts left still plays, the next loss is out", function()
		local s = knockRound({ 1, 3, 3 })
		T.eq(s.phase, "reveal")
		T.eq(s.lives[1], 0)
		T.eq(s.out[1], false, "on the county, still in")
		T.eq(ThirtyOne.getSeatInfo(s)[1], "On the county")
		ThirtyOne.onTimeout(s)
		T.ok(s.hands[1] ~= nil, "dealt in again")
		local t = knockRound({ 0, 3, 3 })
		T.eq(t.out[1], true)
		T.eq(ThirtyOne.getSeatInfo(t)[1], "Out")
		T.eq(t.showdown.out[1], 1)
		-- County off: out at 0.
		local u = ThirtyOne.new(3, { rules = { county = false } }, T.Random.new(2))
		T.eq(u.county, false)
	end)

	T.test("everyone left going out together replays the hand", function()
		-- Both on the county and tied for lowest.
		local s = setup({ { C(2, S), C(3, S), C(4, S) }, { C(2, H), C(3, H), C(4, H) } }, { C(2, D) }, { C(5, CL), C(6, CL) })
		s.lives = { 0, 0 }
		s.turnsThisRound = 2
		-- Seat 1 knocks; seat 2 ties: the knocker is safe, so seat 2 goes out and seat 1 wins.
		apply(s, 1, { kind = "knock" })
		apply(s, 2, { kind = "draw", from = "stock" })
		apply(s, 2, { kind = "discard", card = C(6, CL) })
		T.eq((ThirtyOne.getResult(s) :: any).winners[1], 1)
		-- A non-knocker showdown (the turn limit) with both tied on the county: replay.
		local t = setup({ { C(2, S), C(3, S), C(4, S) }, { C(2, H), C(3, H), C(4, H) } }, { C(2, D) }, { C(5, CL), C(6, CL) })
		t.lives = { 0, 0 }
		t.turnsThisRound = ThirtyOne.ROUND_TURN_LIMIT - 1
		apply(t, 1, { kind = "draw", from = "stock" })
		apply(t, 1, { kind = "discard", card = C(6, CL) })
		T.eq(t.phase, "reveal")
		T.eq(t.showdown.replay, true)
		T.eq(t.out[1], false)
		T.eq(t.out[2], false)
		T.eq(ThirtyOne.getResult(t), nil)
	end)

	T.test("everyone dealt 31 is spared", function()
		-- A stacked deck: seats are dealt three cards each from the end.
		local original = PlayingCards.newDeck
		PlayingCards.newDeck = function()
			return { C(5, CL), C(6, CL), C(2, D), C(3, D), C(4, D), C(1, H), C(13, H), C(12, H), C(1, S), C(13, S), C(12, S) }
		end
		local ok, s = pcall(ThirtyOne.new, 3, nil, T.Random.new(1))
		PlayingCards.newDeck = original
		assert(ok, s)
		T.eq(s.phase, "reveal")
		T.eq(s.showdown.lost["1"], nil)
		T.eq(s.showdown.lost["2"], nil)
		T.eq(s.showdown.lost["3"], 1)
		T.eq(#s.showdown.spared, 2)
	end)

	T.test("three of a kind: off, 30 or 30.5", function()
		local trips = { C(7, S), C(7, H), C(7, D) }
		T.eq(ThirtyOne.value(trips, false), 7)
		T.eq(ThirtyOne.value(trips, 30), 30)
		T.eq(ThirtyOne.value(trips, 30.5), 30.5)
		T.eq(ThirtyOne.value(trips, true), 30.5)
		T.eq(ThirtyOne.new(2, { rules = { trips = 30 } }, T.Random.new(1)).trips, 30)
		T.eq(ThirtyOne.new(2, { rules = { trips = true } }, T.Random.new(1)).trips, 30.5)
		T.eq(ThirtyOne.new(2, { rules = { trips = 99 } }, T.Random.new(1)).trips, false)
	end)

	T.test("house rule: knock on your first turn", function()
		local s = ThirtyOne.new(3, { rules = { firstKnock = true } }, T.Random.new(4))
		if s.phase == "draw" then
			T.ok(ThirtyOne.canKnock(s, s.turn))
		end
		local t = ThirtyOne.new(3, nil, T.Random.new(4))
		if t.phase == "draw" then
			T.eq(ThirtyOne.canKnock(t, t.turn), false)
		end
	end)
end
