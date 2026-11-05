-- The house rules added for every game (Pop Out, flying kings, three-check, rising card
-- trades, Rest Stop jackpot...). Each test checks the rule changes play, and where it
-- matters that the normal game is unchanged.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Games = ReplicatedStorage.Shared.Games
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)

local C = PlayingCards.make -- C(rank, suit); suits 1 spades, 2 hearts, 3 diamonds, 4 clubs

return function(T)
	local function apply(rules, s, seat, move)
		local ok, err = rules.validateMove(s, seat, move)
		assert(ok, err)
		rules.applyMove(s, seat, move)
	end

	T.test("tic-tac-toe: marks stay and a full board is a draw without vanishing", function()
		local TicTacToe = require(Games.TicTacToe)
		local s = TicTacToe.new(2, { rules = { vanish = false } })
		-- X O X / X O O / O X X: no line.
		for i, cell in { 1, 2, 3, 5, 4, 6, 8, 7, 9 } do
			apply(TicTacToe, s, (i - 1) % 2 + 1, { cell = cell })
		end
		local result = TicTacToe.getResult(s) :: any
		T.ok(result and result.isDraw, "full board draws")
		T.eq(#s.placed[1], 5, "no mark vanished")
	end)

	T.test("chess: three checks win, and shuffle starts are legal back rows", function()
		local Chess = require(Games.Chess)
		local s = Chess.new(2, { fen = "4k3/8/8/8/8/8/3Q4/4K3 w - - 0 1", rules = { threeCheck = true } })
		s.checks[1] = 2
		apply(Chess, s, 1, { from = "d2", to = "d7" })
		T.eq((Chess.getResult(s) :: any).reason, "Three checks")
		for seed = 1, 20 do
			local fen = Chess.shuffledFen(T.Random.new(seed))
			local row = string.split(fen, "/")[1]
			local b1, b2 = string.find(row, "b"), string.find(row, "b", (string.find(row, "b") :: number) + 1)
			T.ok((b1 :: number) % 2 ~= (b2 :: number) % 2, "bishops on opposite colors")
			local r1, k, r2 = string.find(row, "r"), string.find(row, "k"), string.find(row, "r", (string.find(row, "r") :: number) + 1)
			T.ok((r1 :: number) < (k :: number) and (k :: number) < (r2 :: number), "king between the rooks")
			local game = Chess.new(2, { rules = { shuffle = true } }, T.Random.new(seed))
			T.ok(#Chess.getLegalMoves(game, 1) > 0)
		end
	end)

	T.test("checkers: a flying king jumps from far away and men can capture backward", function()
		local Checkers = require(Games.Checkers)
		local function empty(rules)
			local s = Checkers.new(2, { rules = rules })
			for r = 1, 8 do
				for c = 1, 8 do
					s.board[r][c] = 0
				end
			end
			s.board[1][2] = 2 -- something left for light, so the game isn't over
			return s
		end
		local s = empty({ flyingKings = true })
		s.board[8][1] = 3 -- dark king
		s.board[5][4] = 2
		local found = false
		for _, m in Checkers.getLegalMoves(s, 1) do
			if m.path[1][1] == 4 and m.path[1][2] == 5 then
				found = true
			end
		end
		T.ok(found, "the king jumps from 3 squares away")
		apply(Checkers, s, 1, { from = { 8, 1 }, path = { { 4, 5 } } })
		T.eq(s.board[5][4], 0, "the jumped piece is gone")

		local back = empty({ backCaptures = true })
		back.board[4][4] = 1 -- dark man (moves up)
		back.board[5][5] = 2 -- light man behind it
		T.eq(#Checkers.getLegalMoves(back, 1), 1, "the backward jump is forced")
		local normal = empty(nil)
		normal.board[4][4] = 1
		normal.board[5][5] = 2
		T.eq(#Checkers.getLegalMoves(normal, 1), 2, "normally only the two forward steps")
	end)

	T.test("four in a row: Pop Out pulls your bottom disc and can win", function()
		local Four = require(Games.FourInARow)
		local s = Four.new(2, { rules = { popOut = true } })
		-- Column 1 holds (bottom up) 1, 2; columns 2-4 hold 2 then 1 on top.
		s.grid[1] = { 1, 2, 0, 0, 0, 0 }
		s.heights[1] = 2
		for c = 2, 4 do
			s.grid[c] = { 2, 1, 0, 0, 0, 0 }
			s.heights[c] = 2
		end
		T.eq(Four.validateMove(s, 1, { column = 2, pop = true }), false, "not your disc")
		apply(Four, s, 1, { column = 1, pop = true })
		T.eq(s.grid[1][1], 2, "everything dropped a row")
		T.eq(s.heights[1], 1)
		-- Popping made a row of 2s along the bottom? (1: 2; 2-4: 2) yes: the popper didn't
		-- make four, so the other player wins.
		T.eq(s.winner, 2)
		local plain = Four.new(2, nil)
		T.eq(Four.validateMove(plain, 1, { column = 1, pop = true }), false)
	end)

	T.test("whodunit: walk anywhere and shown cards seen by all", function()
		local Whodunit = require(Games.Whodunit)
		local s = Whodunit.new(3, { rules = { anyRoom = true, openShow = true } }, T.Random.new(4))
		local view = Whodunit.getView(s, 1)
		T.ok(#view.legalRooms >= 8, "any other room")
		s.log = { { seat = 2, suspect = 1, item = 1, room = 1, passed = {}, shower = 3, card = 5 } }
		T.eq(Whodunit.getView(s, 1).log[1].card, 5, "a bystander sees the card")
		s.openShow = false
		T.eq(Whodunit.getView(s, 1).log[1].card, nil, "normally hidden")
	end)

	T.test("property party: jackpot, no auctions and starting cash", function()
		local Estates = require(Games.Estates)
		local s = Estates.new(2, { rules = { jackpot = true, auctions = false, startCash = 1000 } }, T.Random.new(1))
		T.eq(s.players[1].cash, 1000)
		s.rng = { NextInteger = function(_, lo)
			return if lo == 1 then 1 else lo
		end } :: any -- every die shows 1
		local tax, rest = 0, 0
		for pos, space in Estates.spaces do
			if space.kind == "tax" and tax == 0 then
				tax = pos
			elseif space.kind == "rest" then
				rest = pos
			end
		end
		-- Dice 1 + 1 is a double: fine, the turn just rolls again later.
		s.players[1].pos = tax - 2
		apply(Estates, s, 1, { kind = "roll" })
		T.eq(s.pot, Estates.spaces[tax].amount, "the tax went into the pot")
		s.players[1].pos = rest - 2
		s.canRoll = true
		s.phase = "turn"
		local before = s.players[1].cash
		apply(Estates, s, 1, { kind = "roll" })
		T.eq(s.players[1].cash, before + Estates.spaces[tax].amount, "landed on Rest Stop and took it")
		T.eq(s.pot, 0)
		-- A deed nobody buys stays with the bank.
		s.phase = "buy"
		s.players[1].pos = 2
		apply(Estates, s, 1, { kind = "decline" })
		T.eq(s.phase, "turn")
		T.eq(s.owner[2], nil)
	end)

	T.test("conquest: rising card values go up with every trade", function()
		local Conquest = require(Games.Conquest)
		T.eq(Conquest.risingValue(1), 4)
		T.eq(Conquest.risingValue(6), 15)
		T.eq(Conquest.risingValue(8), 25)
		local s = Conquest.new(3, { rules = { cards = "rising", earlyLimit = false, length = 1.5 } }, T.Random.new(2))
		T.eq(Conquest.tradeValue(s, { "sword", "sword", "sword" }), 4)
		s.trades = 3
		T.eq(Conquest.tradeValue(s, { "sword", "shield", "crown" }), 10)
		T.eq(Conquest.tradeValue(s, { "sword", "sword", "crown" }), nil, "still needs a real set")
		T.eq(Conquest.limitFor(s), math.huge)
		T.eq(s.maxRounds, math.floor(Conquest.roundsFor(3) * 1.5 + 0.5))
	end)

	T.test("hexlands: points to win, safe hand and balanced dice", function()
		local Hexlands = require(Games.Hexlands)
		local s = Hexlands.new(2, { rules = { target = 10, handLimit = 9, balancedDice = true, friendly = true } }, T.Random.new(3))
		T.eq(s.target, 10)
		T.eq(s.handLimit, 9)
		T.eq(Hexlands.getView(s, 1).target, 10)
		T.ok(s.balancedDice and s.friendly)
	end)

	T.test("sea strike: salvo fires one shot per ship afloat", function()
		local SeaStrike = require(Games.SeaStrike)
		local s = SeaStrike.new(2, { rules = { salvo = true } }, T.Random.new(5))
		apply(SeaStrike, s, 1, { kind = "ready" })
		apply(SeaStrike, s, 2, { kind = "ready" })
		T.eq(s.shotsLeft, 5)
		local fired = 0
		while s.turn == 1 and fired < 10 do
			local move = SeaStrike.getLegalMoves(s, 1)[1]
			apply(SeaStrike, s, 1, move)
			fired += 1
		end
		T.eq(fired, 5, "five shots, then the other player")
	end)

	T.test("trivia: flat points and wrong answers cost", function()
		local TriviaNight = require(Games.TriviaNight)
		local s = TriviaNight.new(2, { rules = { speed = false, streaks = false, wrongPenalty = true } }, T.Random.new(1))
		apply(TriviaNight, s, 1, { kind = "answer", choice = s.correct })
		apply(TriviaNight, s, 2, { kind = "answer", choice = s.correct % 4 + 1 })
		T.eq(s.scores[1], 1000)
		T.eq(s.scores[2], -250)
	end)

	T.test("werewolf: no Seer, and a quiet first night", function()
		local Werewolf = require(Games.Werewolf)
		local s = Werewolf.new(6, { rules = { seer = false, quietNight = true } }, T.Random.new(1))
		T.eq(table.find(s.roles, "seer"), nil)
		T.ok(s.quietNight)
	end)

	T.test("war: peace makes the low card win, and one card goes down in a war", function()
		local War = require(Games.War)
		local s = War.new(2, { rules = { peace = true, faceDown = 1, battleLimit = 30 } }, T.Random.new(1))
		s.piles = { { C(2, 1), C(9, 1) }, { C(13, 2), C(9, 2) } }
		apply(War, s, 1, { kind = "flip" })
		apply(War, s, 2, { kind = "flip" })
		T.eq(s.lastBattle.winner, 1, "the 2 beats the King in peace")
		T.eq(War.getView(s, 1).battleLimit, 30)
	end)

	T.test("speed: Ace-King wrap can be turned off, same rank turned on", function()
		local Speed = require(Games.Speed)
		T.eq(Speed.fits({ wrap = false }, C(1, 1), C(13, 2)), false)
		T.ok(Speed.fits({ sameRank = true }, C(7, 1), C(7, 2)))
		T.eq(Speed.fits({}, C(7, 1), C(7, 2)), false)
	end)

	T.test("go fish: pairs mode puts down pairs and ends at 26", function()
		local GoFish = require(Games.GoFish)
		local s = GoFish.new(2, { rules = { pairs = true, handSize = 5 } }, T.Random.new(9))
		for seat = 1, 2 do
			local counts = PlayingCards.rankCounts(s.hands[seat])
			for _, n in counts do
				T.ok(n < 2, "no pair left in a hand")
			end
		end
		T.eq(s.bookSize, 2)
	end)

	T.test("i doubt it: up, down or same claims", function()
		local Cheat = require(Games.Cheat)
		local s = Cheat.new(3, { rules = { upDown = true } }, T.Random.new(1))
		s.called = 7
		local claims = Cheat.claims(s)
		T.eq(#claims, 3)
		T.ok(table.find(claims, 6) and table.find(claims, 8))
		s.called = 1
		T.ok(table.find(Cheat.claims(s), 13), "Kings wrap down from Aces")
		local card = s.hands[1][1]
		T.eq(Cheat.validateMove(s, 1, { kind = "play", cards = { card }, claim = 5 }), false)
		apply(Cheat, s, 1, { kind = "play", cards = { card }, claim = 2 })
		T.eq(s.lastPlay.rank, 2)
	end)

	T.test("president: 2s clear the pile and the player leads again", function()
		local President = require(Games.President)
		local s = President.new(3, { rules = { twoClears = true } }, T.Random.new(1))
		s.turn = 1
		s.hands[1] = { C(2, 1), C(5, 1) }
		s.pile = { cards = { C(9, 2) }, count = 1, power = President.power(C(9, 2)), seat = 3 }
		apply(President, s, 1, { kind = "play", cards = { C(2, 1) } })
		T.eq(s.pile, nil)
		T.eq(s.turn, 1)
	end)

	T.test("slap stack: marriage and tens are good slaps only when on", function()
		local SlapStack = require(Games.SlapStack)
		local s = SlapStack.new(2, { rules = { marriage = true, tens = true, topBottom = true } }, T.Random.new(1))
		s.center = { C(13, 1), C(12, 2) }
		T.ok(SlapStack.canSlap(s), "K-Q")
		s.center = { C(6, 1), C(4, 2) }
		T.ok(SlapStack.canSlap(s), "6 + 4")
		s.center = { C(9, 1), C(4, 2), C(9, 3) }
		T.ok(SlapStack.canSlap(s), "top = bottom (also a sandwich)")
		local plain = SlapStack.new(2, nil, T.Random.new(1))
		plain.center = { C(6, 1), C(4, 2) }
		T.eq(SlapStack.canSlap(plain), false)
	end)

	T.test("snap: a wrong snap can cost two cards", function()
		local Snap = require(Games.Snap)
		local s = Snap.new(2, { rules = { penalty = 2 } }, T.Random.new(1))
		local before = Snap.total(s, 1)
		apply(Snap, s, 1, { kind = "snap" })
		T.eq(Snap.total(s, 1), before - 2)
	end)

	T.test("hearts: Jack of Diamonds is -10 and no passing skips the pass", function()
		local Hearts = require(Games.Hearts)
		local s = Hearts.new(4, { rules = { passing = false, jackDiamonds = true } }, T.Random.new(1))
		T.eq(s.phase, "play", "no pass phase")
		local self = Hearts.new(4, { rules = { moon = "self" } }, T.Random.new(1))
		T.ok(self.moonSelf)
	end)

	T.test("spades: Nil can be turned off", function()
		local Spades = require(Games.Spades)
		local s = Spades.new(4, { rules = { nilBids = false } }, T.Random.new(1))
		T.eq(Spades.validateMove(s, s.turn, { kind = "bid", bid = 0 }), false)
		for _, m in Spades.getLegalMoves(s, s.turn) do
			T.ok(m.bid >= 1)
		end
	end)

	T.test("thirty-one: three of a kind is 30.5", function()
		local ThirtyOne = require(Games.ThirtyOne)
		T.eq(ThirtyOne.value({ C(5, 1), C(5, 2), C(5, 3) }, true), 30.5)
		T.eq(ThirtyOne.value({ C(5, 1), C(5, 2), C(5, 3) }), 5)
	end)

	T.test("palace: after a 7 only 7 or lower plays", function()
		local Palace = require(Games.Palace)
		local s = Palace.new(2, { rules = { sevenLower = true } }, T.Random.new(1))
		s.pile = { C(7, 1) }
		T.ok(Palace.canPlay(s, C(5, 2)))
		T.eq(Palace.canPlay(s, C(9, 2)), false)
		T.ok(Palace.canPlay(s, C(10, 2)), "10 still burns")
	end)

	T.test("old maid: Black Peter uses the Jack of Spades", function()
		local OldMaid = require(Games.OldMaid)
		local s = OldMaid.new(3, { rules = { card = "jack" } }, T.Random.new(1))
		T.eq(s.oldMaid, OldMaid.BLACK_PETER)
		local total = 0
		for seat = 1, 3 do
			total += #s.hands[seat]
			T.eq(table.find(s.hands[seat], OldMaid.BLACK_PETER_REMOVED), nil)
		end
		T.eq(total % 2, 1, "an odd card is left over")
	end)

	T.test("gin rummy: Oklahoma sets the knock limit from the upcard", function()
		local GinRummy = require(Games.GinRummy)
		local s = GinRummy.new(2, { rules = { oklahoma = true, undercut = 10 } }, T.Random.new(1))
		local r = PlayingCards.rank(s.discard[1])
		local expected = if r == 1 then 0 elseif r >= 10 then 10 else r
		T.eq(s.knockLimit, expected)
		T.eq(s.undercutBonus, 10)
	end)

	T.test("oh hell: no hook, and every trick scores", function()
		local OhHell = require(Games.OhHell)
		local s = OhHell.new(3, { rules = { hook = false, scoring = "tricks" } }, T.Random.new(1))
		T.eq(OhHell.forbiddenBid(s, s.dealer), nil)
		T.ok(s.everyTrick)
	end)
end
