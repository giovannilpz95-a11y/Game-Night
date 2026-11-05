local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ColorClash = require(ReplicatedStorage.Shared.Games.ColorClash)
local GameModule = require(ReplicatedStorage.Shared.GameModule)

return function(T)
	local cards = ColorClash.cards

	-- Finds a card id matching a test.
	local function find(pred): number
		for id, card in cards do
			if pred(card) then
				return id
			end
		end
		error("no such card")
	end

	-- A game with chosen hands and top card; the deck holds everything else.
	local function setup(seatCount, hands, top, color)
		local s = ColorClash.new(seatCount, { botLevel = "medium" }, T.Random.new(1))
		local used = { [top] = true }
		for seat = 1, seatCount do
			s.hands[seat] = hands[seat] or {}
			for _, id in s.hands[seat] do
				used[id] = true
			end
		end
		s.deck = {}
		for id = 1, #cards do
			if not used[id] then
				table.insert(s.deck, id)
			end
		end
		s.discard = { top }
		s.color = color or cards[top].color
		s.turn = 1
		return s
	end

	local function play(s, seat, move)
		local ok, err = ColorClash.validateMove(s, seat, move)
		assert(ok, err)
		ColorClash.applyMove(s, seat, move)
	end

	local coral5 = find(function(c) return c.color == 1 and c.value == 5 end)
	local honey5 = find(function(c) return c.color == 2 and c.value == 5 end)
	local honey7 = find(function(c) return c.color == 2 and c.value == 7 end)
	local teal3 = find(function(c) return c.color == 3 and c.value == 3 end)
	local coralSkip = find(function(c) return c.color == 1 and c.kind == "skip" end)
	local coralReverse = find(function(c) return c.color == 1 and c.kind == "reverse" end)
	local coralDraw2 = find(function(c) return c.color == 1 and c.kind == "draw2" end)
	local tealDraw2 = find(function(c) return c.color == 3 and c.kind == "draw2" end)
	local wild = find(function(c) return c.kind == "wild" end)
	local wild4 = find(function(c) return c.kind == "wild4" end)

	T.test("the view lists the last plays with who played them", function()
		local coral9 = find(function(c) return c.color == 1 and c.value == 9 end)
		local s = setup(3, { { coral5, honey7 }, { honey5, teal3 }, { coralSkip } }, coral9)
		play(s, 1, { kind = "play", card = coral5 })
		play(s, 2, { kind = "play", card = honey5 })
		local recent = ColorClash.getView(s, nil).recent
		T.eq(#recent, 3)
		T.eq(recent[1].seat, 0)
		T.eq(recent[2].card, coral5)
		T.eq(recent[2].seat, 1)
		T.eq(recent[3].card, honey5)
		T.eq(recent[3].seat, 2)
	end)

	T.test("chain anything: a Draw Two answers a Draw Four", function()
		local s = setup(3, { { wild4, coral5 }, { coralDraw2, teal3 }, { honey7 } }, coral5)
		s.discard = { honey5 }
		s.color = 2
		play(s, 1, { kind = "play", card = wild4, color = 1 })
		T.eq(ColorClash.validateMove(s, 2, { kind = "play", card = coralDraw2 }), false)
		s.chainAnything = true
		play(s, 2, { kind = "play", card = coralDraw2 })
		T.eq(s.pendingDraw, 6)
	end)

	T.test("force play: a drawn card that fits can't be kept", function()
		local s = setup(2, { { teal3 }, { honey7 } }, coral5)
		s.forcePlay = true
		s.deck = { coralSkip }
		play(s, 1, { kind = "draw" })
		T.eq(s.drawnCard, coralSkip)
		T.eq(ColorClash.validateMove(s, 1, { kind = "pass" }), false)
		T.eq(ColorClash.getView(s, 1).canPass, false)
		local moves = ColorClash.getLegalMoves(s, 1)
		T.eq(#moves, 1)
		T.eq(moves[1].card, coralSkip)
	end)

	T.test("7-0: a 7 swaps hands with the chosen player, a 0 passes hands along", function()
		local coral7 = find(function(c) return c.color == 1 and c.value == 7 end)
		local coral0 = find(function(c) return c.color == 1 and c.value == 0 end)
		local s = setup(3, { { coral7, coral0, teal3 }, { honey5 }, { honey7, coralSkip } }, coral5)
		s.sevenZero = true
		T.eq(ColorClash.validateMove(s, 1, { kind = "play", card = coral7 }), false)
		T.eq(ColorClash.validateMove(s, 1, { kind = "play", card = coral7, target = 1 }), false)
		play(s, 1, { kind = "play", card = coral7, target = 3 })
		T.eq(#s.hands[1], 2) -- seat 3's two cards
		T.ok(table.find(s.hands[1], honey7) ~= nil)
		T.ok(table.find(s.hands[3], coral0) ~= nil)
		for _, move in ColorClash.getLegalMoves(s, 2) do
			T.ok(move.kind ~= "play" or move.target == nil or move.target ~= 2)
		end
		-- Seat 3 now holds the 0: everyone's hand moves one seat along.
		s.turn = 3
		local before = { table.clone(s.hands[1]), table.clone(s.hands[2]) }
		play(s, 3, { kind = "play", card = coral0 })
		T.eq(table.concat(s.hands[2], ","), table.concat(before[1], ","))
		T.eq(table.concat(s.hands[3], ","), table.concat(before[2], ","))
		-- A bot picks a target on its own.
		local b = setup(3, { { coral7, teal3 }, { honey5 }, { honey7, coralSkip } }, coral5)
		b.sevenZero = true
		local move = ColorClash.chooseBotMove(b, 1, T.Random.new(2))
		if move.card == coral7 then
			T.eq(move.target, 2)
		end
	end)

	T.test("deck has 108 cards and everyone gets 7", function()
		T.eq(ColorClash.deckSize, 108)
		local s = ColorClash.new(4, nil, T.Random.new(3))
		local total = #s.deck + #s.discard
		for seat = 1, 4 do
			T.eq(#s.hands[seat], 7)
			total += #s.hands[seat]
		end
		T.eq(total, 108)
		T.eq(cards[s.discard[1]].kind, "number", "starts on a number card")
	end)

	T.test("match by color or number, not neither", function()
		local s = setup(3, { { honey5, honey7, teal3 } }, coral5)
		T.ok(ColorClash.validateMove(s, 1, { kind = "play", card = honey5 }), "same number")
		T.eq((ColorClash.validateMove(s, 1, { kind = "play", card = honey7 })), false)
		T.eq((ColorClash.validateMove(s, 1, { kind = "play", card = coral5 })), false, "not in hand")
		T.eq((ColorClash.validateMove(s, 2, { kind = "play", card = honey5 })), false, "not your turn")
		play(s, 1, { kind = "play", card = honey5 })
		T.eq(s.color, 2)
		T.eq(s.turn, 2)
	end)

	T.test("wild needs a color and sets it", function()
		local s = setup(2, { { wild, teal3 }, { honey7 } }, coral5)
		T.eq((ColorClash.validateMove(s, 1, { kind = "play", card = wild })), false)
		T.eq((ColorClash.validateMove(s, 1, { kind = "play", card = wild, color = 9 })), false)
		play(s, 1, { kind = "play", card = wild, color = 3 })
		T.eq(s.color, 3)
		T.eq(s.turn, 2)
	end)

	T.test("skip and reverse", function()
		local s = setup(4, { { coralSkip, teal3 }, {}, {}, {} }, coral5)
		play(s, 1, { kind = "play", card = coralSkip })
		T.eq(s.turn, 3, "seat 2 skipped")
		local r = setup(4, { { coralReverse, teal3 }, {}, {}, {} }, coral5)
		play(r, 1, { kind = "play", card = coralReverse })
		T.eq(r.direction, -1)
		T.eq(r.turn, 4, "goes the other way")
		local two = setup(2, { { coralReverse, teal3 }, { honey7 } }, coral5)
		play(two, 1, { kind = "play", card = coralReverse })
		T.eq(two.turn, 1, "with two players reverse is a skip")
	end)

	T.test("draw two stacks, then someone eats the pile", function()
		local s = setup(3, { { coralDraw2, teal3 }, { tealDraw2, honey7 }, { honey5 } }, coral5)
		play(s, 1, { kind = "play", card = coralDraw2 })
		T.eq(s.pendingDraw, 2)
		T.eq((ColorClash.validateMove(s, 2, { kind = "play", card = honey7 })), false, "must stack or draw")
		play(s, 2, { kind = "play", card = tealDraw2 })
		T.eq(s.pendingDraw, 4)
		T.eq(s.turn, 3)
		play(s, 3, { kind = "draw" })
		T.eq(#s.hands[3], 5)
		T.eq(s.pendingDraw, 0)
		T.eq(s.turn, 1, "the player who drew is skipped")
	end)

	T.test("wild draw four stacks on a draw two", function()
		local s = setup(2, { { coralDraw2, teal3 }, { wild4, honey7 } }, coral5)
		play(s, 1, { kind = "play", card = coralDraw2 })
		play(s, 2, { kind = "play", card = wild4, color = 2 })
		T.eq(s.pendingDraw, 6)
		play(s, 1, { kind = "draw" })
		T.eq(#s.hands[1], 7)
	end)

	T.test("drawing a playable card lets you play it or pass", function()
		local s = setup(2, { { teal3 }, { honey7 } }, coral5)
		-- Put a playable card on top of the deck.
		local i = table.find(s.deck, coralSkip) :: number
		table.remove(s.deck, i)
		table.insert(s.deck, coralSkip)
		play(s, 1, { kind = "draw" })
		T.eq(s.turn, 1, "still your turn")
		T.eq(s.drawnCard, coralSkip)
		T.eq((ColorClash.validateMove(s, 1, { kind = "play", card = teal3 })), false, "only the drawn card")
		T.eq((ColorClash.validateMove(s, 1, { kind = "draw" })), false, "one draw per turn")
		play(s, 1, { kind = "pass" })
		T.eq(s.turn, 2)
	end)

	T.test("empty deck reshuffles the discard pile", function()
		local s = setup(2, { { teal3 }, { honey7 } }, coral5)
		s.discard = {}
		for _, id in s.deck do
			table.insert(s.discard, id)
		end
		table.insert(s.discard, coral5)
		s.deck = {}
		play(s, 1, { kind = "draw" })
		T.eq(#s.hands[1] >= 2, true)
		T.eq(s.discard[#s.discard], coral5, "top card stays")
	end)

	T.test("emptying your hand wins", function()
		local s = setup(2, { { honey5 }, { honey7 } }, coral5)
		play(s, 1, { kind = "play", card = honey5 })
		local result = ColorClash.getResult(s)
		T.ok(result)
		T.eq(result.winners[1], 1)
		T.eq(#ColorClash.getActiveSeats(s), 0)
	end)

	T.test("views hide other hands", function()
		local s = ColorClash.new(3, nil, T.Random.new(5))
		local view = ColorClash.getView(s, 2)
		T.eq(#view.hand, 7)
		T.eq(view.handCounts[1], 7)
		T.eq(view.drawnCard, nil)
		T.eq(ColorClash.getView(s, nil).hand, nil, "spectators see no hand")
	end)

	T.test("going down to one card without calling it can be caught by the next player", function()
		local coral9 = find(function(c) return c.color == 1 and c.value == 9 end)
		local s = setup(3, { { coral5, honey7 }, { honey5, teal3 }, { coralSkip } }, coral9)
		play(s, 1, { kind = "play", card = coral5 })
		T.eq(s.exposed, 1)
		T.ok(s.lastAction.forgot)
		T.eq((ColorClash.validateMove(s, 3, { kind = "catch" })), false, "only the player on turn")
		T.ok(ColorClash.getView(s, 2).canCatch)
		play(s, 2, { kind = "catch" })
		T.eq(#s.hands[1], 3)
		T.eq(s.lastAction.kind, "catch")
		T.eq(s.lastAction.target, 1)
		T.eq(s.turn, 2, "catching doesn't use your turn")
		T.eq((ColorClash.validateMove(s, 2, { kind = "catch" })), false, "only once")
	end)

	T.test("calling last card is safe, and the chance to catch passes with the next move", function()
		local coral9 = find(function(c) return c.color == 1 and c.value == 9 end)
		local s = setup(3, { { coral5, honey7 }, { honey5, teal3 }, { coralSkip } }, coral9)
		T.eq((ColorClash.validateMove(s, 1, { kind = "play", card = coral5, call = "yes" })), false)
		local legal = ColorClash.getLegalMoves(s, 1)
		T.eq(legal[1].call, true, "bots and fuzzers see the call too")
		play(s, 1, { kind = "play", card = coral5, call = true })
		T.eq(s.exposed, nil)
		T.ok(s.lastAction.called)
		T.eq((ColorClash.validateMove(s, 2, { kind = "catch" })), false)

		local t = setup(3, { { coral5, honey7 }, { honey5, teal3 }, { coralSkip } }, coral9)
		play(t, 1, { kind = "play", card = coral5 })
		play(t, 2, { kind = "play", card = honey5, call = true })
		T.eq(t.exposed, nil, "too late now")
	end)

	T.test("the last card call can be turned off", function()
		local coral9 = find(function(c) return c.color == 1 and c.value == 9 end)
		local s = setup(3, { { coral5, honey7 }, { honey5, teal3 }, { coralSkip } }, coral9)
		s.lastCall = false
		play(s, 1, { kind = "play", card = coral5 })
		T.eq(s.exposed, nil)
	end)

	T.test("7-0: a 7 swaps hands with the player you pick, a 0 passes every hand along", function()
		local coral7 = find(function(c) return c.color == 1 and c.value == 7 end)
		local coral0 = find(function(c) return c.color == 1 and c.value == 0 end)
		local coral9 = find(function(c) return c.color == 1 and c.value == 9 end)
		local s = setup(3, { { coral7, honey7, teal3 }, { honey5 }, { coralSkip, coral0 } }, coral9)
		s.sevenZero = true
		T.eq((ColorClash.validateMove(s, 1, { kind = "play", card = coral7 })), false, "needs a target")
		T.eq((ColorClash.validateMove(s, 1, { kind = "play", card = coral7, target = 1 })), false, "not yourself")
		play(s, 1, { kind = "play", card = coral7, target = 2 })
		T.eq(#s.hands[1], 1)
		T.eq(s.hands[1][1], honey5)
		T.eq(#s.hands[2], 2, "they got the rest of yours")
		T.eq(s.lastAction.swap, 2)
		-- Seat 2 has no coral; seat 3 plays the 0 after a draw-free pass round.
		s.turn = 3
		play(s, 3, { kind = "play", card = coral0 })
		T.eq(s.hands[1][1], coralSkip, "seat 3's hand moved on to seat 1")
		T.eq(s.hands[3][1], honey7, "seat 2's hand moved on to seat 3")
		T.eq(s.lastAction.rotate, 1)
	end)

	T.test("skips and draw cards name who they hit", function()
		local coral9 = find(function(c) return c.color == 1 and c.value == 9 end)
		local s = setup(3, { { coralSkip, honey7 }, { honey5, teal3 }, { coral5, coralDraw2 } }, coral9)
		play(s, 1, { kind = "play", card = coralSkip, call = true })
		T.eq(s.lastAction.victim, 2)
		play(s, 3, { kind = "play", card = coralDraw2, call = true })
		T.eq(s.lastAction.victim, 1)
	end)

	T.test("rejects junk moves from the network", function()
		local s = ColorClash.new(2, nil, T.Random.new(2))
		T.eq((ColorClash.validateMove(s, 1, "x")), false)
		T.eq((ColorClash.validateMove(s, 1, { kind = "play", card = 0.5 })), false)
		T.eq((ColorClash.validateMove(s, 1, { kind = "play", card = 999 })), false)
		T.eq((ColorClash.validateMove(s, 1, { kind = "play", card = 0 / 0 })), false)
		T.eq((ColorClash.validateMove(s, 1, { kind = "pass" })), false)
		T.eq((ColorClash.validateMove(s, 1, { kind = "nope" })), false)
	end)

	T.test("bots finish legal games at every level and table size", function()
		for _, level in { "easy", "medium", "hard" } do
			for seats = 2, 8, 3 do
				local rng = T.Random.new(seats * 10 + #level)
				-- Every other game with 7-0 on, so swaps get played out too.
				local s = ColorClash.new(seats, { botLevel = level, rules = { sevenZero = seats % 2 == 0 } }, rng)
				local plies = 0
				while not ColorClash.getResult(s) and plies < 2000 do
					local seat = ColorClash.getActiveSeats(s)[1]
					local move = GameModule.chooseBotMove(ColorClash, s, seat, rng)
					T.ok(ColorClash.validateMove(s, seat, move), "bot made an illegal move")
					ColorClash.applyMove(s, seat, move)
					plies += 1
				end
				T.ok(ColorClash.getResult(s) ~= nil, `{level} {seats}-seat game should finish`)
				-- No card was lost or duplicated.
				local seen, total = {}, 0
				for _, list in { s.deck, s.discard, table.unpack(s.hands) } do
					for _, id in list do
						T.ok(not seen[id], "duplicate card")
						seen[id] = true
						total += 1
					end
				end
				T.eq(total, 108)
			end
		end
	end)
end
