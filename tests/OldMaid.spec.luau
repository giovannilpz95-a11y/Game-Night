local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OldMaid = require(ReplicatedStorage.Shared.Games.OldMaid)
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local sim = require(script.Parent.CardSim)

return function(T)
	local C = PlayingCards.make
	local QS = OldMaid.OLD_MAID

	local function setup(hands)
		local s = OldMaid.new(#hands, { botLevel = "medium" }, T.Random.new(1))
		s.hands = hands
		for seat = 1, #hands do
			s.pairs[seat] = {}
		end
		s.turn = 1
		s.target = 2
		s.over = false
		s.loser = nil
		return s
	end

	local function apply(s, seat, move)
		local ok, err = OldMaid.validateMove(s, seat, move)
		assert(ok, err)
		OldMaid.applyMove(s, seat, move)
	end

	T.test("the deal has 51 cards, no pairs left in any hand, and one Old Maid", function()
		for seats = 2, 6 do
			local s = OldMaid.new(seats, nil, T.Random.new(seats))
			local total, maids = 0, 0
			for seat = 1, seats do
				local others = table.clone(s.hands[seat])
				PlayingCards.removeCards(others, { QS }) -- she never pairs
				local counts = PlayingCards.rankCounts(others)
				for _, n in counts do
					T.ok(n < 2, "no pairs in a dealt hand")
				end
				total += #s.hands[seat] + #s.pairs[seat] * 2
				if table.find(s.hands[seat], QS) then
					maids += 1
				end
				T.eq(table.find(s.hands[seat], OldMaid.REMOVED), nil)
			end
			T.eq(total, 51)
			T.eq(maids, 1)
		end
	end)

	T.test("only the turn player draws, and only a real position", function()
		local s = setup({ { C(5, 1), C(9, 2) }, { C(5, 2), QS }, { C(9, 3) } })
		T.eq((OldMaid.validateMove(s, 2, { kind = "draw", index = 1 })), false)
		T.eq((OldMaid.validateMove(s, 1, { kind = "draw", index = 3 })), false)
		T.eq((OldMaid.validateMove(s, 1, { kind = "draw", index = 1.5 })), false)
		T.eq((OldMaid.validateMove(s, 1, { kind = "draw" })), false)
		T.eq((OldMaid.validateMove(s, 1, "draw")), false)
	end)

	T.test("a drawn match goes down as a pair, then the giver draws next", function()
		local s = setup({ { C(5, 1), C(9, 2) }, { C(5, 2) }, { C(9, 3), QS } })
		apply(s, 1, { kind = "draw", index = 1 })
		T.eq(#s.hands[1], 1)
		T.eq(s.pairs[1][1], 5)
		T.eq(#s.hands[2], 0, "seat 2 is safe")
		-- Seat 2 is out, so seat 3 is next and draws from seat 1.
		T.eq(s.turn, 3)
		T.eq(s.target, 1)
		local view = OldMaid.getView(s, 2)
		T.eq(view.lastDrawn.card, C(5, 2), "the giver sees what was taken")
		T.eq(OldMaid.getView(s, 3).lastDrawn, nil, "others don't")
	end)

	T.test("whoever is left with the Old Maid loses", function()
		local s = setup({ { C(9, 2) }, { C(9, 3), QS } })
		s.hands[2] = { C(9, 3), QS }
		apply(s, 1, { kind = "draw", index = 1 })
		T.eq(#s.hands[1], 0)
		local result = OldMaid.getResult(s) :: any
		T.ok(result ~= nil)
		T.eq(#result.winners, 1)
		T.eq(result.winners[1], 1)
		T.eq(s.loser, 2)
	end)

	T.test("bot games always finish with one loser", function()
		for _, level in { "easy", "medium", "hard" } do
			for seats = 2, 6 do
				local rng = T.Random.new(seats * 13 + #level)
				local s = OldMaid.new(seats, { botLevel = level }, rng)
				sim(OldMaid, s, rng, 5000)
				local result = OldMaid.getResult(s) :: any
				T.ok(result ~= nil, `{level} {seats}-seat game should finish`)
				T.eq(#result.winners, seats - 1)
				T.ok(table.find(s.hands[s.loser], QS) ~= nil)
			end
		end
	end)
	T.test("you draw from the player on your right; the turn passes left", function()
		local s = OldMaid.new(4, nil, T.Random.new(31))
		s.hands = { { C(2, 1), C(3, 1) }, { C(4, 1), C(5, 1) }, { C(6, 1), C(7, 1) }, { C(8, 1), C(9, 1) } }
		s.turn = 1
		s.target = 4
		local view = OldMaid.getView(s, 1)
		T.eq(view.target, 4)
		apply(s, 1, { kind = "draw", index = 1 })
		T.eq(s.turn, 2, "the turn passes left")
		T.eq(s.target, 1, "and seat 2 draws from the player who just drew")
		local fresh = OldMaid.new(3, nil, T.Random.new(32))
		T.eq(fresh.target, if #fresh.hands[3] > 0 then 3 else 2)
	end)

	T.test("mystery card: a random card comes out and nobody knows the odd one until the end", function()
		for seed = 1, 5 do
			local s = OldMaid.new(3, { rules = { card = "mystery" } }, T.Random.new(seed))
			T.eq(s.oldMaid, OldMaid.NO_ODD)
			local total, odd = 0, 0
			for seat = 1, 3 do
				total += #s.hands[seat] + #s.pairs[seat] * 2
				local counts = PlayingCards.rankCounts(s.hands[seat])
				for r, n in counts do
					T.ok(n < 2, "no pairs in hand")
					if r == PlayingCards.rank(s.removed) then
						odd += n
					end
				end
			end
			T.eq(total, 51)
			T.eq(odd, 1, "the removed card's rank has one card left unpaired")
			T.eq(OldMaid.getView(s, 1).removed, nil, "secret")
			T.eq(OldMaid.getView(s, 1).oldMaid, OldMaid.NO_ODD)
			local rng = T.Random.new(seed)
			sim(OldMaid, s, rng, 5000)
			T.ok(OldMaid.getResult(s) ~= nil)
			T.eq(OldMaid.getView(s, 1).removed, s.removed, "shown at the end")
		end
	end)

	T.test("to 6 points: finishing order scores penalty points, rounds go on until someone has 6", function()
		local s = OldMaid.new(3, { rules = { target = 6 } }, T.Random.new(33))
		s.hands = { { C(9, 2) }, { C(4, 1) }, { C(9, 3), QS, C(4, 2) } }
		s.pairs = { {}, {}, {} }
		s.finished = {}
		s.turn = 1
		s.target = 3
		apply(s, 1, { kind = "draw", index = 1 }) -- the 9: seat 1 is out first
		T.eq(s.finished[1], 1)
		T.eq(s.turn, 2)
		s.hands[3] = { QS, C(4, 2) }
		s.target = 3
		local four = table.find(s.hands[3], C(4, 2)) :: number
		apply(s, 2, { kind = "draw", index = four }) -- seat 2 pairs its 4 and is out
		T.ok(s.roundOver, "round over")
		T.eq(OldMaid.getResult(s), nil, "the game goes on")
		T.eq(s.points[1], 0)
		T.eq(s.points[2], 1)
		T.eq(s.points[3], 2, "the loser scores the most")
		T.eq(#OldMaid.getActiveSeats(s), 0)
		OldMaid.onTimeout(s)
		T.eq(s.round, 2)
		T.eq(s.roundOver, false)
		local cards = 0
		for seat = 1, 3 do
			cards += #s.hands[seat] + #s.pairs[seat] * 2
		end
		T.eq(cards, 51, "a fresh deal")
		local rng = T.Random.new(34)
		sim(OldMaid, s, rng, 50000)
		local result = OldMaid.getResult(s) :: any
		T.ok(result ~= nil)
		local top = 0
		for seat = 1, 3 do
			top = math.max(top, s.points[seat])
		end
		T.ok(top >= 6)
	end)

	T.test("Black Peter: the giver bot teases while holding the Jack of Spades, not the Queen", function()
		local teased, wrong = 0, 0
		for seed = 1, 100 do
			local s = OldMaid.new(2, { botLevel = "hard", rules = { card = "jack" } }, T.Random.new(seed))
			local giver = s.target
			s.hands[giver] = { OldMaid.BLACK_PETER, C(3, 1), C(5, 1) }
			if OldMaid.chooseBotMove(s, giver, T.Random.new(seed)) then
				teased += 1
			end
			s.hands[giver] = { QS, C(3, 1), C(5, 1) }
			s.giverMoves = 0
			if OldMaid.chooseBotMove(s, giver, T.Random.new(seed)) then
				wrong += 1
			end
		end
		T.ok(teased > 30, "teases holding Black Peter")
		T.eq(wrong, 0, "the Queen is a normal card here")
	end)

	T.test("the player being drawn from can shuffle or lift a card, a few times per draw", function()
		local s = OldMaid.new(3, nil, T.Random.new(4))
		local drawer, giver = s.turn, s.target
		T.eq(OldMaid.getInterruptSeats(s)[1], giver)
		T.eq((OldMaid.validateMove(s, drawer, { kind = "shuffle" })), false, "only the one being drawn from")
		T.eq((OldMaid.validateMove(s, giver, { kind = "lift", index = 99 })), false)
		OldMaid.applyMove(s, giver, { kind = "lift", index = 2 })
		T.eq(OldMaid.getView(s, drawer).lifted, 2)
		T.ok(OldMaid.getView(s, giver).offering ~= nil, "the giver sees their order")
		T.eq(OldMaid.getView(s, drawer).offering, nil, "nobody else does")
		local before = #s.hands[giver]
		OldMaid.applyMove(s, giver, { kind = "shuffle" })
		T.eq(s.lifted, nil)
		T.eq(#s.hands[giver], before)
		T.eq(OldMaid.getView(s, drawer).shuffles, 1)
		OldMaid.applyMove(s, giver, { kind = "shuffle" })
		OldMaid.applyMove(s, giver, { kind = "shuffle" })
		T.eq((OldMaid.validateMove(s, giver, { kind = "shuffle" })), false, "enough for one draw")
		OldMaid.applyMove(s, drawer, { kind = "draw", index = 1 })
		T.eq(s.giverMoves, 0, "a new draw, a new chance")
	end)
end
