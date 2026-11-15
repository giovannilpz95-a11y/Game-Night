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
		for id = 1, ColorClash.deckSize do
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

	T.test("stacking: same card only by default; \"+4 on +2\" lets a Wild +4 answer a Draw Two", function()
		local d = setup(2, { { coralDraw2, teal3 }, { wild4, honey7, tealDraw2 } }, coral5)
		play(d, 1, { kind = "play", card = coralDraw2 })
		T.eq((ColorClash.validateMove(d, 2, { kind = "play", card = wild4, color = 2 })), false, "same card only")
		play(d, 2, { kind = "play", card = tealDraw2 })
		T.eq(d.pendingDraw, 4)
		local s = setup(2, { { coralDraw2, teal3 }, { wild4, honey7 } }, coral5)
		s.stackMode = "up"
		play(s, 1, { kind = "play", card = coralDraw2 })
		play(s, 2, { kind = "play", card = wild4, color = 2 })
		T.eq(s.pendingDraw, 6)
		play(s, 1, { kind = "draw" })
		T.eq(#s.hands[1], 7)
	end)

	T.test("challenging a bluffed Wild +4 makes the player draw 4", function()
		-- Seat 1 holds a Coral card while Coral is in play: the +4 was a bluff.
		local s = setup(3, { { wild4, teal3, coralSkip }, { honey7 }, { honey5 } }, coral5)
		play(s, 1, { kind = "play", card = wild4, color = 3 })
		T.ok(ColorClash.canChallenge(s, 2))
		T.ok(ColorClash.getView(s, 2).canChallenge)
		T.eq(ColorClash.getView(s, 3).canChallenge, false)
		play(s, 2, { kind = "challenge" })
		T.eq(#s.hands[1], 2 + 4, "the bluffer draws 4")
		T.eq(#s.hands[2], 1, "the challenger draws nothing")
		T.eq(s.turn, 2, "and plays on")
		T.eq(s.pendingDraw, 0)
		T.ok(s.lastAction.guilty)
	end)

	T.test("challenging a fair Wild +4 costs the challenger 6", function()
		local s = setup(3, { { wild4, teal3, honey5 }, { honey7 }, { coralSkip } }, coral5)
		play(s, 1, { kind = "play", card = wild4, color = 3 })
		play(s, 2, { kind = "challenge" })
		T.eq(#s.hands[2], 1 + 6)
		T.eq(s.turn, 3, "the challenger loses the turn")
		T.eq(s.lastAction.guilty, false)
	end)

	T.test("only a lone Wild +4 can be challenged, and only right away", function()
		local s = setup(2, { { coralDraw2, teal3 }, { wild4, honey7 } }, coral5)
		s.stackMode = "up"
		play(s, 1, { kind = "play", card = coralDraw2 })
		play(s, 2, { kind = "play", card = wild4, color = 2 })
		T.eq(ColorClash.canChallenge(s, 1), false, "stacked on a +2")
		local t = setup(2, { { wild4, teal3, coralSkip }, { honey7, honey5 } }, coral5)
		play(t, 1, { kind = "play", card = wild4, color = 2 })
		play(t, 2, { kind = "draw" })
		T.eq(t.challengeable, nil, "taking the cards lets it go")
		local off = ColorClash.new(2, { rules = { challenge = false } }, T.Random.new(1))
		T.eq(off.challenge, false)
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

	T.test("going down to one card without calling it can be caught by anyone", function()
		local coral9 = find(function(c) return c.color == 1 and c.value == 9 end)
		local s = setup(3, { { coral5, honey7 }, { honey5, teal3 }, { coralSkip } }, coral9)
		play(s, 1, { kind = "play", card = coral5 })
		T.eq(s.exposed, 1)
		T.ok(s.lastAction.forgot)
		T.ok(ColorClash.validateMove(s, 3, { kind = "catch" }), "anyone, not only the player on turn")
		T.eq((ColorClash.validateMove(s, 1, { kind = "catch" })), false, "not yourself")
		T.ok(table.find(ColorClash.getInterruptSeats(s), 3) ~= nil)
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

	T.test("jump-in: an identical card goes down out of turn and play carries on", function()
		local coral5b = find(function(c) return c.color == 1 and c.value == 5 and c ~= cards[coral5] end)
		local coral9 = find(function(c) return c.color == 1 and c.value == 9 end)
		local s = setup(4, { { coral5, honey7 }, { teal3 }, { coral5b, honey5, wild } }, coral9)
		-- Off: nothing to jump.
		play(s, 1, { kind = "play", card = coral5 })
		T.eq(#ColorClash.getJumpIns(s, 3), 0, "rule off")
		T.eq((ColorClash.validateMove(s, 3, { kind = "jump", card = coral5b })), false)
		s.jumpIn = true
		T.eq(s.turn, 2)
		T.eq(ColorClash.getJumpIns(s, 3)[1], coral5b)
		T.eq(#ColorClash.getJumpIns(s, 2), 0, "your own turn: just play")
		T.ok(table.find(ColorClash.getInterruptSeats(s), 3) ~= nil)
		T.eq((ColorClash.validateMove(s, 3, { kind = "jump", card = honey5 })), false, "same number, other color")
		T.eq((ColorClash.validateMove(s, 3, { kind = "jump", card = wild })), false, "no wilds")
		T.eq((ColorClash.validateMove(s, 3, { kind = "play", card = coral5b })), false, "a normal play is still out of turn")
		play(s, 3, { kind = "jump", card = coral5b })
		T.eq(s.lastAction.jumped, true)
		T.eq(s.lastAction.seat, 3)
		T.eq(s.turn, 4, "play goes on from the jumper; seat 2 lost their turn")
		T.ok(not table.find(s.hands[3], coral5b))
		T.eq(ColorClash.getView(s, 1).jumpIns[1], nil)
	end)

	T.test("jump-in: a jumped Skip skips whoever is after the jumper", function()
		local coralSkipB = find(function(c) return c.color == 1 and c.kind == "skip" and c ~= cards[coralSkip] end)
		local s = setup(4, { { coralSkip, honey7 }, { teal3 }, { honey5 }, { coralSkipB, coral5 } }, find(function(c) return c.color == 1 and c.value == 9 end))
		s.jumpIn = true
		play(s, 1, { kind = "play", card = coralSkip })
		T.eq(s.turn, 3)
		play(s, 4, { kind = "jump", card = coralSkipB })
		T.eq(s.lastAction.victim, 1)
		T.eq(s.turn, 2)
	end)

	T.test("jump-in: bots sometimes jump and never move out of turn otherwise", function()
		local coral5b = find(function(c) return c.color == 1 and c.value == 5 and c ~= cards[coral5] end)
		local coral9 = find(function(c) return c.color == 1 and c.value == 9 end)
		local jumps = 0
		for i = 1, 40 do
			local s = setup(3, { { coral5, honey7 }, { teal3 }, { coral5b, honey5 } }, coral9)
			s.jumpIn = true
			play(s, 1, { kind = "play", card = coral5, call = true })
			local rng = T.Random.new(i)
			T.eq(ColorClash.chooseBotMove(s, 1, rng), nil, "nothing to jump with")
			local move = ColorClash.chooseBotMove(s, 3, rng)
			if move then
				T.ok(ColorClash.validateMove(s, 3, move))
				jumps += 1
			end
		end
		T.ok(jumps > 5 and jumps < 40, `bots jump some of the time ({jumps}/40)`)
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
				local s = ColorClash.new(seats, { botLevel = level, rules = { sevenZero = seats % 2 == 0, jumpIn = seats > 2 } }, rng)
				local plies = 0
				while not ColorClash.getResult(s) and plies < 2000 do
					local seat = ColorClash.getActiveSeats(s)[1]
					local move = nil
					-- Jump-ins get the first chance to slam a card down.
					for _, other in ColorClash.getInterruptSeats(s) do
						move = ColorClash.chooseBotMove(s, other, rng)
						if move then
							seat = other
							break
						end
					end
					move = move or GameModule.chooseBotMove(ColorClash, s, seat, rng)
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

	-- Plays a whole game with bots (out-of-turn moves first), dealing new rounds as the
	-- round timer runs out. Returns the plies played.
	local function botGame(s, rng, limit)
		local plies = 0
		while not ColorClash.getResult(s) and plies < limit do
			if ColorClash.getTimer(s) then
				ColorClash.onTimeout(s)
			else
				local seat = ColorClash.getActiveSeats(s)[1]
				local move = nil
				for _, other in ColorClash.getInterruptSeats(s) do
					move = ColorClash.chooseBotMove(s, other, rng)
					if move then
						seat = other
						break
					end
				end
				move = move or GameModule.chooseBotMove(ColorClash, s, seat, rng)
				local ok, err = ColorClash.validateMove(s, seat, move)
				assert(ok, `bot made an illegal move: {err}`)
				ColorClash.applyMove(s, seat, move)
			end
			plies += 1
		end
		return plies
	end

	local coral9 = find(function(c) return c.color == 1 and c.value == 9 end)

	T.test("a forgotten call can be said late, until someone catches it", function()
		local s = setup(3, { { coral5, honey7 }, { honey5, teal3 }, { coralSkip } }, coral9)
		play(s, 1, { kind = "play", card = coral5 })
		T.ok(ColorClash.getView(s, 1).canCallLate)
		T.ok(table.find(ColorClash.getInterruptSeats(s), 1) ~= nil)
		play(s, 1, { kind = "call" })
		T.eq(s.exposed, nil)
		T.eq(s.lastAction.late, true)
		T.eq((ColorClash.validateMove(s, 3, { kind = "catch" })), false, "safe now")
		T.eq(s.turn, 2, "still seat 2's turn")
		-- Caught first: too late to call.
		local t = setup(3, { { coral5, honey7 }, { honey5, teal3 }, { coralSkip } }, coral9)
		play(t, 1, { kind = "play", card = coral5 })
		play(t, 3, { kind = "catch" })
		T.eq(#t.hands[1], 3)
		T.eq((ColorClash.validateMove(t, 1, { kind = "call" })), false)
		T.eq(t.turn, 2, "an out-of-turn catch leaves the turn alone")
	end)

	T.test("a challenge keeps the chance to catch, and only the challenger sees the hand", function()
		local s = setup(3, { { wild4, teal3 }, { honey7, honey5 }, { coralSkip } }, coral5)
		play(s, 1, { kind = "play", card = wild4, color = 3 })
		T.eq(s.exposed, 1, "forgot to call")
		play(s, 2, { kind = "challenge" })
		T.eq(#s.hands[2], 2 + 6, "fair +4: the challenger draws 6")
		T.eq(s.exposed, 1, "the challenge didn't let them off")
		T.ok(ColorClash.getView(s, 2).proof ~= nil, "the challenger sees the hand")
		play(s, 3, { kind = "catch" })
		T.eq(ColorClash.getView(s, 2).proof, nil, "the next move clears it")
		local t = setup(3, { { wild4, teal3, coralSkip }, { honey7, honey5 }, { honey5 } }, coral5)
		play(t, 1, { kind = "play", card = wild4, color = 3, call = false })
		play(t, 2, { kind = "challenge" })
		local proof = ColorClash.getView(t, 2).proof
		T.ok(proof ~= nil)
		T.eq(#proof.hand, 2, "the +4 player's hand as it was")
		T.eq(proof.guilty, true)
		T.eq(ColorClash.getView(t, 3).proof, nil, "nobody else sees it")
	end)

	T.test("house rules: no bluffing, reverse bounces a draw", function()
		local s = setup(2, { { wild4, coral5 }, { honey7 } }, coral9)
		s.noBluff = true
		T.eq((ColorClash.validateMove(s, 1, { kind = "play", card = wild4, color = 2 })), false, "holding coral")
		T.ok(table.find(ColorClash.getPlayable(s, 1), wild4) == nil)
		local t = setup(2, { { wild4, teal3 }, { honey7 } }, coral9)
		t.noBluff = true
		T.ok(ColorClash.validateMove(t, 1, { kind = "play", card = wild4, color = 2 }))

		local coralReverseB = find(function(c) return c.color == 1 and c.kind == "reverse" end)
		local b = setup(3, { { coralDraw2, teal3, honey7 }, { coralReverseB, honey5 }, { teal3 } }, coral9)
		b.reverseBounce = true
		play(b, 1, { kind = "play", card = coralDraw2 })
		T.eq(b.turn, 2)
		play(b, 2, { kind = "play", card = coralReverseB })
		T.eq(b.lastAction.bounced, true)
		T.eq(b.turn, 1, "back to whoever played the +2")
		T.eq(b.pendingDraw, 2)
		play(b, 1, { kind = "draw" })
		T.eq(#b.hands[1], 2 + 2)
	end)

	T.test("jump-in: not on your own card", function()
		local coral5b = find(function(c) return c.color == 1 and c.value == 5 and c ~= cards[coral5] end)
		local s = setup(3, { { coral5, coral5b, honey7 }, { teal3 }, { honey5 } }, coral9)
		s.jumpIn = true
		play(s, 1, { kind = "play", card = coral5 })
		T.eq(#ColorClash.getJumpIns(s, 1), 0)
	end)

	T.test("points: going out scores the other hands, and a last +2 is still drawn", function()
		T.eq(ColorClash.points(coral5), 5)
		T.eq(ColorClash.points(coralSkip), 20)
		T.eq(ColorClash.points(wild4), 50)
		local s = setup(3, { { coralDraw2 }, { honey7, wild }, { teal3, coralSkip } }, coral9)
		play(s, 1, { kind = "play", card = coralDraw2 })
		T.ok(ColorClash.getResult(s) ~= nil)
		T.eq(#s.hands[2], 4, "seat 2 drew the 2 anyway")
		local r = s.roundResult
		T.eq(r.winner, 1)
		T.eq(r.points, ColorClash.handPoints(s.hands[2]) + 3 + 20)
		local scores = ColorClash.getScores(s)
		T.ok(scores[1] > scores[2] and scores[1] > scores[3])
	end)

	T.test("play to 250: rounds are dealt until someone reaches it", function()
		local s = setup(2, { { coral5 }, { honey7, wild } }, coral9)
		s.target = 250
		play(s, 1, { kind = "play", card = coral5 })
		T.eq(ColorClash.getResult(s), nil, "not yet")
		T.eq(s.phase, "roundEnd")
		T.eq(s.scores[1], 57)
		T.ok(ColorClash.getTimer(s) ~= nil)
		T.eq(#ColorClash.getActiveSeats(s), 0)
		T.eq((ColorClash.validateMove(s, 2, { kind = "draw" })), false)
		ColorClash.onTimeout(s)
		T.eq(s.phase, "play")
		T.eq(s.round, 2)
		T.eq(#s.hands[1], 7)
		T.eq(s.turn, 2, "the next player starts")
		s.scores[2] = 240
		s.hands[2] = { coral5 }
		s.discard = { coral9 }
		s.color = 1
		play(s, 2, { kind = "play", card = coral5 })
		T.eq(ColorClash.getResult(s).winners[1], 2)
		local rng = T.Random.new(5)
		local g = ColorClash.new(3, { botLevel = "medium", rules = { target = 250 } }, rng)
		botGame(g, rng, 20000)
		T.ok(ColorClash.getResult(g) ~= nil)
		T.ok(g.scores[ColorClash.getResult(g).winners[1]] >= 250)
	end)

	T.test("2v2 teams: either partner going out wins for both", function()
		local s = ColorClash.new(4, { rules = { teams = true } }, T.Random.new(3))
		T.eq(ColorClash.partnerOf(s, 1), 3)
		T.eq(ColorClash.partnerOf(s, 2), 4)
		s.hands[2] = { coral5 }
		s.discard = { coral9 }
		s.color = 1
		s.turn = 2
		s.exposed = nil
		play(s, 2, { kind = "play", card = coral5 })
		local result = ColorClash.getResult(s)
		T.ok(table.find(result.winners, 2) ~= nil and table.find(result.winners, 4) ~= nil)
		T.eq(#result.winners, 2)
		-- Partners don't catch each other.
		local t = ColorClash.new(4, { rules = { teams = true } }, T.Random.new(3))
		t.hands[1] = { coral5, honey7 }
		t.discard = { coral9 }
		t.color = 1
		play(t, 1, { kind = "play", card = coral5 })
		T.eq(ColorClash.canCatch(t, 3), false)
		T.ok(ColorClash.canCatch(t, 2))
		T.eq(ColorClash.new(3, { rules = { teams = true } }, T.Random.new(1)).teams, false, "4 seats only")
	end)

	T.test("chaos deck: Skip Everyone, Discard All, Wild +6 and the mercy rule", function()
		local c = ColorClash.new(3, { rules = { chaos = true } }, T.Random.new(4))
		local total = #c.deck + #c.discard
		for _, h in c.hands do
			total += #h
		end
		T.eq(total, #cards, "the chaos cards are in")
		local classic = ColorClash.new(3, nil, T.Random.new(4))
		local n = #classic.deck + #classic.discard
		for _, h in classic.hands do
			n += #h
		end
		T.eq(n, ColorClash.deckSize, "and not in the classic deck")

		local skipAll = find(function(card) return card.kind == "skipall" and card.color == 1 end)
		local discardAll = find(function(card) return card.kind == "discardall" and card.color == 1 end)
		local wild6 = find(function(card) return card.kind == "wild6" end)
		local s = setup(3, { { skipAll, teal3, coral5, honey7 }, { honey5 }, { teal3 } }, coral9)
		s.chaos = true
		play(s, 1, { kind = "play", card = skipAll })
		T.eq(s.turn, 1, "everyone skipped: play again")
		local d = setup(3, { { discardAll, coral5, coralSkip, honey7, teal3 }, { honey5 }, { teal3 } }, coral9)
		d.chaos = true
		play(d, 1, { kind = "play", card = discardAll })
		T.eq(#d.hands[1], 2, "both coral cards went too")
		T.eq(d.discard[#d.discard], discardAll, "the Discard All on top")
		T.eq(d.lastAction.discarded, 2)
		local w = setup(3, { { wild6, teal3 }, { honey5 }, { teal3 } }, coral9)
		w.chaos = true
		play(w, 1, { kind = "play", card = wild6, color = 2, call = true })
		T.eq(w.pendingDraw, 6)
		-- Mercy: taking cards up to 25 puts you out.
		local m = setup(3, { { coralDraw2, teal3 }, { honey5 }, { teal3 } }, coral9)
		m.chaos = true
		for _ = 1, 22 do
			table.insert(m.hands[2], table.remove(m.deck) :: number)
		end
		play(m, 1, { kind = "play", card = coralDraw2, call = true })
		play(m, 2, { kind = "draw" })
		T.eq(m.out[2], true)
		T.eq(#m.hands[2], 0)
		T.eq(m.turn, 3, "play skips the player who is out")
		T.eq(ColorClash.getSeatInfo(m)[2], "Out (mercy)")
		-- A whole chaos game with bots.
		for seed = 1, 3 do
			local rng = T.Random.new(seed)
			local g = ColorClash.new(4, { botLevel = "hard", rules = { chaos = true, sevenZero = true, jumpIn = true } }, rng)
			botGame(g, rng, 20000)
			T.ok(ColorClash.getResult(g) ~= nil, "chaos game should finish")
		end
	end)

	T.test("a timed-out player draws and passes; bots catch out of turn sometimes", function()
		local s = setup(2, { { teal3, honey7 }, { honey5 } }, coral9)
		T.eq(ColorClash.chooseAfkMove(s, 1, T.Random.new(1)).kind, "draw")
		s.drawnCard = s.hands[1][1]
		T.eq(ColorClash.chooseAfkMove(s, 1, T.Random.new(1)).kind, "pass")
		local catches = 0
		for i = 1, 60 do
			local t = setup(3, { { coral5, honey7 }, { honey5, teal3 }, { coralSkip } }, coral9)
			play(t, 1, { kind = "play", card = coral5 })
			local move = ColorClash.chooseBotMove(t, 3, T.Random.new(i))
			if move and move.kind == "catch" then
				catches += 1
			end
		end
		T.ok(catches > 5 and catches < 60, `out-of-turn catches {catches}/60`)
	end)

	T.test("out of time: fewest cards, then fewest points; a real tie is shared", function()
		local s = setup(3, { { coral5, honey7 }, { honey5, teal3 }, { coralSkip, wild, wild4 } }, coral9)
		s.turns = 599
		play(s, 1, { kind = "draw" })
		if s.drawnCard then
			play(s, 1, { kind = "pass" })
		end
		local r = ColorClash.getResult(s)
		T.ok(r ~= nil)
		T.eq(r.winners[1], 2, "2 cards worth 8 beats 3 cards")
	end)

	T.test("bots finish games with every new house rule", function()
		for seed = 1, 4 do
			local rng = T.Random.new(seed * 3)
			local rules = { stacking = ({ false, "same", "up", "any" })[seed], noBluff = seed % 2 == 0, reverseBounce = seed % 2 == 1, teams = true, target = if seed == 4 then 250 else 0 }
			local g = ColorClash.new(4, { botLevel = ({ "easy", "medium", "hard", "hard" })[seed], rules = rules }, rng)
			botGame(g, rng, 30000)
			T.ok(ColorClash.getResult(g) ~= nil, `game {seed} should finish`)
		end
	end)
end
