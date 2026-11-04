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
end
