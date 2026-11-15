local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GoFish = require(ReplicatedStorage.Shared.Games.GoFish)
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local GameModule = require(ReplicatedStorage.Shared.GameModule)

return function(T)
	local C = PlayingCards.make

	local function setup(hands, pond)
		local s = GoFish.new(#hands, { botLevel = "medium" }, T.Random.new(1))
		for seat, hand in hands do
			s.hands[seat] = hand
			s.books[seat] = {}
			s.asked[seat] = {}
			s.denied[seat] = {}
		end
		s.log = {}
		s.pond = pond
		s.turn = 1
		s.over = false
		return s
	end

	local function ask(s, seat, target, rank)
		local move = { kind = "ask", target = target, rank = rank }
		local ok, err = GoFish.validateMove(s, seat, move)
		assert(ok, err)
		GoFish.applyMove(s, seat, move)
	end

	T.test("deal: 7 cards for 2-3 players, 5 for 4+", function()
		T.eq(#GoFish.new(2, nil, T.Random.new(9)).hands[1] + #GoFish.new(2, nil, T.Random.new(9)).books[1] * 4, 7)
		T.eq(#GoFish.new(5, nil, T.Random.new(3)).hands[2] + #GoFish.new(5, nil, T.Random.new(3)).books[2] * 4, 5)
	end)

	T.test("you may only ask for a rank you hold, from someone else", function()
		local s = setup({ { C(5, 1) }, { C(5, 2), C(9, 1) } }, { C(2, 1) })
		T.eq((GoFish.validateMove(s, 1, { kind = "ask", target = 2, rank = 9 })), false)
		T.eq((GoFish.validateMove(s, 1, { kind = "ask", target = 1, rank = 5 })), false)
		T.eq((GoFish.validateMove(s, 1, { kind = "ask", target = 3, rank = 5 })), false)
		T.eq((GoFish.validateMove(s, 2, { kind = "ask", target = 1, rank = 5 })), false, "not your turn")
		T.eq((GoFish.validateMove(s, 1, { kind = "ask", target = 2, rank = 5.5 })), false)
		T.eq((GoFish.validateMove(s, 1, "x")), false)
	end)

	T.test("a hit hands over every card and you go again", function()
		local s = setup({ { C(5, 1), C(8, 1) }, { C(5, 2), C(5, 3), C(9, 1) } }, { C(2, 1), C(3, 1) })
		ask(s, 1, 2, 5)
		T.eq(s.lastAction.got, 2)
		T.eq(#s.hands[1], 4)
		T.eq(s.turn, 1, "go again")
	end)

	T.test("go fish passes the turn unless you fish what you asked for", function()
		local s = setup({ { C(5, 1) }, { C(9, 1) } }, { C(2, 1), C(3, 1) })
		ask(s, 1, 2, 5)
		T.eq(s.lastAction.got, 0)
		T.eq(s.turn, 2)
		local lucky = setup({ { C(5, 1) }, { C(9, 1) } }, { C(2, 1), C(5, 4) })
		ask(lucky, 1, 2, 5)
		T.ok(lucky.lastAction.luckyFish)
		T.eq(lucky.turn, 1)
	end)

	T.test("four of a kind becomes a book", function()
		local s = setup({ { C(5, 1), C(5, 2), C(5, 3), C(8, 1) }, { C(5, 4), C(9, 1) } }, { C(2, 1) })
		ask(s, 1, 2, 5)
		T.eq(s.books[1][1], 5)
		T.eq(#s.hands[1], 1)
	end)

	T.test("only the fisher sees the drawn card", function()
		local s = setup({ { C(5, 1) }, { C(9, 1) } }, { C(2, 1), C(3, 1) })
		ask(s, 1, 2, 5)
		T.eq(GoFish.getView(s, 1).drawnCard, C(3, 1))
		T.eq(GoFish.getView(s, 2).drawnCard, nil)
		T.eq(GoFish.getView(s, 2).hand[1], C(9, 1))
	end)

	T.test("taking someone's last cards: their hand refills at once and you keep asking", function()
		local s = setup({ { C(5, 1), C(8, 1) }, { C(5, 2) }, { C(9, 1) } }, { C(2, 1), C(3, 1), C(4, 1), C(6, 1), C(7, 1), C(10, 1), C(11, 1), C(12, 1) })
		s.handSize = 7
		ask(s, 1, 2, 5)
		T.eq(#s.hands[2], 7, "refilled to the starting size")
		T.eq(s.turn, 1, "your turn goes on")
		local off = setup({ { C(5, 1), C(8, 1) }, { C(5, 2) } }, { C(2, 1), C(3, 1) })
		off.refill = false
		ask(off, 1, 2, 5)
		T.eq(off.turn, 2, "house rule off: your turn ends and they draw one on theirs")
		T.eq(#off.hands[2], 1)
	end)

	T.test("a tie on books goes to the higher cards, then it's shared", function()
		local s = setup({ { C(2, 1) }, { C(3, 1) } }, {})
		s.books = { { 13, 2 }, { 12, 3 } }
		s.over = true
		local result = GoFish.getResult(s) :: any
		T.eq(#result.winners, 2, "K+2 and Q+3 are both worth 15")
		T.eq(result.isDraw, false, "a shared win")
		s.books = { { 1, 2 }, { 13, 3 } }
		result = GoFish.getResult(s) :: any
		T.eq(#result.winners, 1)
		T.eq(result.winners[1], 1, "the Ace counts 15")
	end)

	T.test("a lucky fish is shown to everyone; the log keeps the last asks", function()
		local s = setup({ { C(5, 1) }, { C(9, 1) } }, { C(2, 1), C(5, 4) })
		ask(s, 1, 2, 5)
		T.eq(GoFish.getView(s, 2).lastAction.card, C(5, 4))
		T.eq(#GoFish.getView(s, 2).log, 1)
		T.eq(GoFish.getView(s, 2).log[1].rank, 5)
		T.ok(s.denied[2][5], "seat 2 said go fish to 5s")
	end)

	T.test("house rules: the turn goes to the player you asked; a quick game ends when the pond runs out", function()
		local s = setup({ { C(5, 1) }, { C(9, 1) }, { C(10, 1) } }, { C(2, 1), C(3, 1) })
		s.askedNext = true
		ask(s, 1, 3, 5)
		T.eq(s.turn, 3)
		local q = setup({ { C(5, 1), C(6, 1) }, { C(9, 1) } }, { C(3, 1) })
		q.quick = true
		ask(q, 1, 2, 5)
		T.ok(q.over, "the pond is empty")
	end)

	T.test("bot games always finish with all 13 books", function()
		for _, level in { "easy", "medium", "hard" } do
			for seats = 2, 6 do
				local rng = T.Random.new(seats * 13)
				local s = GoFish.new(seats, { botLevel = level }, rng)
				local plies = 0
				while not GoFish.getResult(s) and plies < 2000 do
					plies += 1
					local seat = GoFish.getActiveSeats(s)[1]
					local move = GameModule.chooseBotMove(GoFish, s, seat, rng)
					T.ok(GoFish.validateMove(s, seat, move), "bot made an illegal move")
					GoFish.applyMove(s, seat, move)
				end
				T.ok(GoFish.getResult(s) ~= nil, `{level} {seats}-seat game should finish`)
				local books = 0
				for seat = 1, seats do
					books += #s.books[seat]
				end
				T.eq(books, 13)
			end
		end
	end)
end
