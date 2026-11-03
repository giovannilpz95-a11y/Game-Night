-- Each game's own house rules (options.rules), and Party Host word lists / quiz decks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Games = ReplicatedStorage.Shared.Games
local TicTacToe = require(Games.TicTacToe)
local Chess = require(Games.Chess)
local Checkers = require(Games.Checkers)
local ColorClash = require(Games.ColorClash)
local SketchGuess = require(Games.SketchGuess)
local TriviaNight = require(Games.TriviaNight)

return function(T)
	local function apply(rules, s, seat, move)
		local ok, err = rules.validateMove(s, seat, move)
		assert(ok, err)
		rules.applyMove(s, seat, move)
	end

	-- Tic-Tac-Toe -----------------------------------------------------------------

	T.test("upside down tic-tac-toe: making three in a row loses", function()
		local s = TicTacToe.new(2, { rules = { misere = true } })
		for _, step in { { 1, 1 }, { 2, 4 }, { 1, 2 }, { 2, 5 }, { 1, 3 } } do
			apply(TicTacToe, s, step[1], { cell = step[2] })
		end
		local result = TicTacToe.getResult(s) :: any
		T.eq(result.winners[1], 2)
	end)

	T.test("upside down bot never completes its own line when it has a choice", function()
		local s = TicTacToe.new(2, { rules = { misere = true } })
		s.board = { 2, 2, 0, 1, 1, 0, 0, 0, 0 }
		s.turn = 2
		for seed = 1, 20 do
			local move = TicTacToe.chooseBotMove(s, 2, T.Random.new(seed))
			T.ok(move.cell ~= 3, "cell 3 would make three O's")
		end
	end)

	T.test("normal tic-tac-toe is unchanged", function()
		local s = TicTacToe.new(2, nil)
		for _, step in { { 1, 1 }, { 2, 4 }, { 1, 2 }, { 2, 5 }, { 1, 3 } } do
			apply(TicTacToe, s, step[1], { cell = step[2] })
		end
		T.eq((TicTacToe.getResult(s) :: any).winners[1], 1)
	end)

	-- Chess -------------------------------------------------------------------------

	T.test("king of the hill: a king on a center square wins", function()
		local fen = "4k3/p7/8/8/8/4K3/P7/8 w - - 0 1" -- pawns so it isn't a dead draw
		local hill = Chess.new(2, { fen = fen, rules = { kingOfTheHill = true } })
		apply(Chess, hill, 1, { from = "e3", to = "e4" })
		local result = Chess.getResult(hill) :: any
		T.eq(result.winners[1], 1)
		T.eq(result.reason, "King of the hill")

		local normal = Chess.new(2, { fen = fen })
		apply(Chess, normal, 1, { from = "e3", to = "e4" })
		T.eq(Chess.getResult(normal), nil)
	end)

	-- Checkers ----------------------------------------------------------------------

	local function jumpPosition(rules)
		local s = Checkers.new(2, { rules = rules })
		for r = 1, 8 do
			for c = 1, 8 do
				s.board[r][c] = 0
			end
		end
		s.board[6][3] = 1
		s.board[5][4] = 2
		s.board[6][7] = 1
		s.board[1][2] = 2
		return s
	end

	T.test("must jump off: steps are legal even when a jump is open", function()
		local forced = jumpPosition(nil)
		T.eq(#Checkers.getLegalMoves(forced, 1), 1)
		local optional = jumpPosition({ forcedCaptures = false })
		local moves = Checkers.getLegalMoves(optional, 1)
		T.ok(#moves > 1, "jump plus steps")
		apply(Checkers, optional, 1, { from = { 6, 7 }, path = { { 5, 8 } } })
		T.eq(optional.board[5][4], 2, "didn't have to take")
		T.ok(Checkers.chooseBotMove(optional, 2, T.Random.new(1)) ~= nil)
	end)

	-- Color Clash -------------------------------------------------------------------

	local cards = ColorClash.cards
	local function find(pred, skip): number
		for id, card in cards do
			if pred(card) and id ~= skip then
				return id
			end
		end
		error("no such card")
	end

	T.test("starting hand size follows the rule", function()
		for _, size in { 5, 7, 10 } do
			local s = ColorClash.new(4, { rules = { handSize = size } }, T.Random.new(size))
			T.eq(#s.hands[1], size)
			T.eq(#s.hands[4], size)
		end
		local s = ColorClash.new(2, { rules = { handSize = 99 } }, T.Random.new(1))
		T.eq(#s.hands[1], 7, "odd values fall back")
	end)

	T.test("stacking off: a Draw Two can't be answered", function()
		local s = ColorClash.new(2, { rules = { stacking = false } }, T.Random.new(3))
		local d1 = find(function(c)
			return c.kind == "draw2" and c.color == 1
		end)
		local d2 = find(function(c)
			return c.kind == "draw2" and c.color == 1
		end, d1)
		s.hands[1] = { d1, find(function(c)
			return c.kind == "number" and c.color == 2
		end) }
		s.hands[2] = { d2, find(function(c)
			return c.kind == "number" and c.color == 3
		end) }
		s.discard = { find(function(c)
			return c.kind == "number" and c.color == 1 and c.value == 5
		end) }
		s.color = 1
		s.turn = 1
		apply(ColorClash, s, 1, { kind = "play", card = d1 })
		T.eq(s.pendingDraw, 2)
		local ok, err = ColorClash.validateMove(s, 2, { kind = "play", card = d2 })
		T.eq(ok, false)
		T.ok(string.find(err :: string, "Draw") ~= nil)
		local before = #s.hands[2]
		apply(ColorClash, s, 2, { kind = "draw" })
		T.eq(#s.hands[2], before + 2)
	end)

	T.test("draw until you can play keeps drawing until a card fits", function()
		local s = ColorClash.new(2, { rules = { drawUntilPlayable = true } }, T.Random.new(5))
		local top = find(function(c)
			return c.kind == "number" and c.color == 1 and c.value == 3
		end)
		s.discard = { top }
		s.color = 1
		s.turn = 1
		s.hands[1] = {}
		-- Deck (drawn from the end): playable card at the bottom, two misses on top.
		local fits = find(function(c)
			return c.kind == "number" and c.color == 1 and c.value == 7
		end)
		local miss1 = find(function(c)
			return c.kind == "number" and c.color == 2 and c.value == 8
		end)
		local miss2 = find(function(c)
			return c.kind == "number" and c.color == 3 and c.value == 9
		end)
		s.deck = { fits, miss1, miss2 }
		apply(ColorClash, s, 1, { kind = "draw" })
		T.eq(#s.hands[1], 3)
		T.eq(s.drawnCard, fits)
		T.eq(s.lastAction.count, 3)
	end)

	-- Sketch & Guess ----------------------------------------------------------------

	local custom = { "lighthouse", "submarine", "volcano", "teapot", "kangaroo", "rainbow" }

	T.test("host words replace ours, three different choices", function()
		local s = SketchGuess.new(4, { bots = { 3, 4 }, customWords = custom }, T.Random.new(2))
		T.eq(#s.choices, 3)
		local seen = {}
		for _, word in s.choices do
			T.ok(table.find(custom, word) ~= nil, `{word} isn't from the host's list`)
			T.ok(not seen[word], "choices are different")
			seen[word] = true
		end
	end)

	T.test("rounds and drawing time follow the rules", function()
		local one = SketchGuess.new(5, { bots = {}, rules = { rounds = 1, drawSeconds = 120 } }, T.Random.new(1))
		T.eq(one.totalTurns, 5)
		T.eq(one.drawSegments, 6)
		local three = SketchGuess.new(5, { bots = {}, rules = { rounds = 3, drawSeconds = 60 } }, T.Random.new(1))
		T.eq(three.totalTurns, 15)
		T.eq(three.drawSegments, 3)
		apply(SketchGuess, three, three.drawer, { kind = "choose", index = 1 })
		T.eq(SketchGuess.getTimer(three).displaySeconds, 60)
	end)

	-- Trivia Night ------------------------------------------------------------------

	local deck = {
		{ c = "Our family", q = "Who makes the best pancakes?", a = { "Grandma", "Dad", "Mom", "The dog" } },
		{ c = "Our family", q = "Where did we go last summer?", a = { "The beach", "Mars", "The mall", "Nowhere" } },
		{ c = "Our family", q = "What's the cat called?", a = { "Biscuit", "Rex", "Mittens", "Luna" } },
	}

	T.test("host quiz decks replace our questions", function()
		local s = TriviaNight.new(2, { customQuestions = deck }, T.Random.new(1))
		T.eq(#s.questions, 3, "a short deck plays every question once")
		local view = TriviaNight.getView(s, 1)
		T.eq(view.category, "Our family")
		local q = deck[s.questions[1]]
		T.eq(view.answers[s.correct], q.a[1])
	end)

	T.test("question count and answer time follow the rules", function()
		local s = TriviaNight.new(2, { rules = { questions = 5, answerSeconds = 25 } }, T.Random.new(1))
		T.eq(#s.questions, 5)
		T.eq(TriviaNight.getTimer(s).seconds, 25)
		local normal = TriviaNight.new(2, nil, T.Random.new(1))
		T.eq(#normal.questions, 10)
		T.eq(TriviaNight.getTimer(normal).seconds, 15)
	end)
end
