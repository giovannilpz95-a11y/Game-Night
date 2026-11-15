local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Cheat = require(ReplicatedStorage.Shared.Games.Cheat)
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local sim = require(script.Parent.CardSim)

return function(T)
	local C = PlayingCards.make

	local function setup(hands)
		local s = Cheat.new(#hands, { botLevel = "medium" }, T.Random.new(1))
		s.hands = hands
		s.pile = {}
		s.turn = 1
		s.called = 5
		return s
	end

	local function apply(s, seat, move)
		local ok, err = Cheat.validateMove(s, seat, move)
		assert(ok, err)
		Cheat.applyMove(s, seat, move)
	end

	T.test("deals the whole deck", function()
		local s = Cheat.new(5, nil, T.Random.new(4))
		local n = 0
		for seat = 1, 5 do
			n += #s.hands[seat]
		end
		T.eq(n, 52)
	end)

	T.test("rejects bad plays", function()
		local s = setup({ { C(5, 1), C(9, 1) }, { C(2, 1) }, { C(3, 1) } })
		T.eq((Cheat.validateMove(s, 2, { kind = "play", cards = { C(2, 1) } })), false, "not your turn")
		T.eq((Cheat.validateMove(s, 1, { kind = "play", cards = { C(2, 1) } })), false, "not your card")
		T.eq((Cheat.validateMove(s, 1, { kind = "play", cards = {} })), false)
		T.eq((Cheat.validateMove(s, 1, { kind = "play", cards = { C(5, 1), C(5, 1) } })), false, "duplicates")
		T.eq((Cheat.validateMove(s, 1, { kind = "play", cards = "x" })), false)
		T.eq((Cheat.validateMove(s, 1, { kind = "doubt" })), false, "nothing to doubt")
		T.ok(Cheat.validateMove(s, 1, { kind = "play", cards = { C(9, 1) } }), "bluffing is allowed")
	end)

	T.test("doubting a bluff hands the pile to the bluffer", function()
		local s = setup({ { C(9, 1), C(4, 1) }, { C(2, 1) }, { C(3, 1) } })
		s.pile = { C(7, 2) }
		apply(s, 1, { kind = "play", cards = { C(9, 1) } })
		T.eq(s.phase, "doubt")
		T.eq((Cheat.validateMove(s, 1, { kind = "doubt" })), false, "can't doubt yourself")
		apply(s, 2, { kind = "doubt" })
		T.eq(s.reveal.honest, false)
		T.eq(s.reveal.loser, 1)
		T.eq(#s.hands[1], 3)
		Cheat.onTimeout(s)
		T.eq(s.turn, 2)
		T.eq(s.called, 6)
	end)

	T.test("doubting the truth hands the pile to the doubter", function()
		local s = setup({ { C(5, 1), C(5, 2), C(4, 1) }, { C(2, 1) }, { C(3, 1) } })
		apply(s, 1, { kind = "play", cards = { C(5, 1), C(5, 2) } })
		apply(s, 3, { kind = "doubt" })
		T.eq(s.reveal.honest, true)
		T.eq(#s.hands[3], 3)
	end)

	T.test("an honest last play wins; nobody doubting also wins", function()
		local s = setup({ { C(5, 1) }, { C(2, 1) }, { C(3, 1) } })
		apply(s, 1, { kind = "play", cards = { C(5, 1) } })
		apply(s, 2, { kind = "doubt" })
		T.eq((Cheat.getResult(s) :: any).winners[1], 1)

		local quiet = setup({ { C(9, 1) }, { C(2, 1) }, { C(3, 1) } })
		apply(quiet, 1, { kind = "play", cards = { C(9, 1) } })
		apply(quiet, 2, { kind = "pass" })
		apply(quiet, 3, { kind = "pass" })
		T.eq((Cheat.getResult(quiet) :: any).winners[1], 1)
	end)

	T.test("other hands stay hidden; the reveal is public", function()
		local s = setup({ { C(9, 1), C(4, 1) }, { C(2, 1) }, { C(3, 1) } })
		apply(s, 1, { kind = "play", cards = { C(9, 1) } })
		local view = Cheat.getView(s, 2)
		T.eq(view.hand[1], C(2, 1))
		T.eq(view.lastPlay.count, 1)
		T.eq(view.reveal, nil)
		apply(s, 2, { kind = "doubt" })
		T.eq(Cheat.getView(s, 3).reveal.cards[1], C(9, 1))
	end)

	local function setupWith(hands, rules)
		local s = Cheat.new(#hands, { botLevel = "medium", rules = rules }, T.Random.new(1))
		s.hands = hands
		s.pile = {}
		s.pileFrom = {}
		s.turn = 1
		s.discards = {}
		return s
	end

	T.test("any rank: the leader names it, everyone follows until a doubt", function()
		local s = setupWith({ { C(9, 1), C(4, 1) }, { C(9, 2), C(3, 1) }, { C(2, 1), C(6, 1) } }, { anyRank = true })
		s.called = nil
		T.eq(#Cheat.claims(s), 13)
		T.eq((Cheat.validateMove(s, 1, { kind = "play", cards = { C(9, 1) } })), false, "name a rank")
		apply(s, 1, { kind = "play", cards = { C(9, 1) }, claim = 9 })
		Cheat.onTimeout(s) -- nobody doubts
		T.eq(s.called, 9, "follow the 9s")
		apply(s, 2, { kind = "play", cards = { C(3, 1) }, claim = 9 })
		apply(s, 3, { kind = "doubt" })
		Cheat.onTimeout(s)
		T.eq(s.called, nil, "after a doubt the next player leads fresh")
	end)

	T.test("allow pass: pass instead of playing; everyone passing sets the pile aside", function()
		local s = setupWith({ { C(9, 1), C(4, 1) }, { C(9, 2), C(3, 1) }, { C(2, 1), C(6, 1) } }, { allowPass = true })
		s.called = 5
		T.eq((Cheat.validateMove(s, 1, { kind = "pass" })), false, "the leader has to play")
		apply(s, 1, { kind = "play", cards = { C(4, 1) } })
		Cheat.onTimeout(s)
		T.eq(s.called, 6)
		apply(s, 2, { kind = "pass" })
		apply(s, 3, { kind = "pass" })
		T.eq(s.turn, 1)
		T.eq(#s.pile, 1)
		apply(s, 1, { kind = "pass" })
		T.eq(#s.pile, 0, "everyone passed: set aside")
		T.eq(s.called, 7)
		local off = setupWith({ { C(9, 1), C(4, 1) }, { C(9, 2) }, { C(2, 1) } })
		off.called = 5
		off.lastPlay = { seat = 3, count = 1, rank = 4 }
		T.eq((Cheat.validateMove(off, 1, { kind = "pass" })), false, "off by default")
	end)

	T.test("discard fours: four of a kind picked up is put aside", function()
		local s = setupWith({ { C(9, 1), C(9, 2), C(4, 1) }, { C(9, 3), C(9, 4), C(3, 1) }, { C(2, 1), C(6, 1) } }, { discardFours = true })
		s.called = 5
		apply(s, 1, { kind = "play", cards = { C(9, 1), C(9, 2) } }) -- claims 5s: a lie
		apply(s, 2, { kind = "doubt" })
		T.eq(s.reveal.loser, 1)
		T.eq(#s.hands[1], 3, "picked the two 9s back up")
		local t = setupWith({ { C(9, 1), C(4, 1) }, { C(9, 3), C(9, 4), C(9, 2), C(3, 1) }, { C(2, 1), C(6, 1) } }, { discardFours = true })
		t.called = 9
		apply(t, 1, { kind = "play", cards = { C(9, 1) } }) -- the truth
		apply(t, 2, { kind = "doubt" }) -- wrong: seat 2 takes the 9 and makes four
		T.eq(t.reveal.loser, 2)
		T.eq(t.reveal.discarded, 9)
		T.eq(#t.hands[2], 1, "the four 9s are put aside")
	end)

	T.test("rounds: places score penalty points, fewest after the last round wins", function()
		local s = setupWith({ { C(4, 1) }, { C(9, 2), C(3, 1) }, { C(2, 1), C(6, 1), C(7, 1) } }, { rounds = 3 })
		s.called = 4
		apply(s, 1, { kind = "play", cards = { C(4, 1) } })
		Cheat.onTimeout(s) -- nobody doubts: seat 1 is out first
		T.eq(s.phase, "roundOver")
		T.eq(Cheat.getResult(s), nil)
		T.eq(s.points[1], 0)
		T.eq(s.points[2], 1)
		T.eq(s.points[3], 3, "the most cards")
		Cheat.onTimeout(s)
		T.eq(s.round, 2)
		T.eq(s.phase, "play")
		local n = 0
		for seat = 1, 3 do
			n += #s.hands[seat]
		end
		T.eq(n, 52, "a fresh deal")
		local rng = T.Random.new(9)
		sim(Cheat, s, rng, 20000)
		T.ok(Cheat.getResult(s) ~= nil)
		T.eq(s.round, 3)
	end)

	T.test("up, down or same: the first play is still Aces", function()
		local s = Cheat.new(3, { rules = { upDown = true } }, T.Random.new(3))
		T.eq(#Cheat.claims(s), 1)
		T.eq(Cheat.claims(s)[1], 1)
	end)

	T.test("bot games always finish", function()
		for _, level in { "easy", "medium", "hard" } do
			for seats = 3, 8 do
				local rng = T.Random.new(seats * 7 + #level)
				local s = Cheat.new(seats, { botLevel = level }, rng)
				sim(Cheat, s, rng, 20000)
				T.ok(Cheat.getResult(s) ~= nil, `{level} {seats}-seat game should finish`)
			end
		end
	end)
	T.test("two decks at a big table: second-deck cards share the same faces", function()
		local s = Cheat.new(6, nil, T.Random.new(5))
		T.eq(s.decks, 2)
		local n, seen = 0, {}
		for seat = 1, 6 do
			for _, id in s.hands[seat] do
				n += 1
				T.ok(not seen[id], "every id once")
				seen[id] = true
			end
		end
		T.eq(n, 104)
		T.eq(PlayingCards.rank(52 + C(9, 3)), 9)
		T.eq(PlayingCards.suit(52 + C(9, 3)), 3)
		T.eq(PlayingCards.short(52 + C(1, 4)), PlayingCards.short(C(1, 4)))
		T.eq(Cheat.new(5, nil, T.Random.new(5)).decks, 1)
		T.eq(Cheat.new(8, { rules = { twoDecksAt = 0 } }, T.Random.new(5)).decks, 1)
		T.eq(Cheat.new(5, { rules = { twoDecksAt = 5 } }, T.Random.new(5)).decks, 2)
		-- Second-deck ids are valid only at a two-deck table.
		local big = setup({ { C(5, 1), 52 + C(5, 1), C(2, 2) }, { C(3, 3) }, { C(4, 4) }, { 1 }, { 2 }, { 3 } })
		big.decks = 2
		apply(big, 1, { kind = "play", cards = { C(5, 1), 52 + C(5, 1) } })
		T.eq(big.lastPlay.count, 2)
		local small = setup({ { C(5, 1), C(2, 2) }, { C(3, 3) }, { C(4, 4) } })
		T.eq((Cheat.validateMove(small, 1, { kind = "play", cards = { 52 + C(5, 1) } })), false)
		-- Never more than 4 cards in one play, even holding 8 of a rank.
		local eight = {}
		for d = 0, 1 do
			for suit = 1, 4 do
				table.insert(eight, d * 52 + C(5, suit))
			end
		end
		local s8 = setup({ eight, { C(3, 3) }, { C(4, 4) }, { 1 }, { 2 }, { 3 } })
		s8.decks = 2
		for _, m in Cheat.getLegalMoves(s8, 1) do
			T.ok(#m.cards <= Cheat.MAX_CARDS)
		end
		T.ok(#Cheat.chooseBotMove(s8, 1, T.Random.new(1)).cards <= Cheat.MAX_CARDS)
	end)
end
