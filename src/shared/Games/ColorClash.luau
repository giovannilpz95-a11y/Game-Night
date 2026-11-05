-- Color Clash: a shedding card game for 2-8 seats (the Crazy Eights family).
--
-- Deck (108 cards): 4 colors (Coral, Honey, Teal, Violet), each with one 0, two each of
-- 1-9, two Skip, two Reverse and two Draw Two. Plus 4 Wild and 4 Wild Draw Four.
-- Cards are ids 1..108; ColorClash.cards[id] says what each one is.
--
-- A turn: play a card that matches the current color, or the top card's number or
-- symbol, or play a Wild. Or draw one: if it can be played you may play it right away,
-- otherwise (or if you pass) the turn moves on.
-- Stacking: a Draw Two can answer a Draw Two, a Wild Draw Four can answer either. The
-- player who can't (or won't) stack draws the whole pile of penalties and is skipped.
-- House rules (options.rules): stacking = false (a draw card can't be answered, the next
-- player just takes it), drawUntilPlayable = true (keep drawing until a card fits),
-- handSize = 5 | 7 | 10.
-- First to empty their hand wins. If the game drags past TURN_LIMIT turns, the fewest
-- cards wins.
--
-- Moves:
--   { kind = "play", card = id, color = 1..4 }  (color only for Wild cards)
--   { kind = "draw" }
--   { kind = "pass" }                            (only after drawing a playable card)

local GameModule = require(script.Parent.Parent.GameModule)
local BotThink = require(script.Parent.Parent.BotThink)

local ColorClash = {}

ColorClash.id = "ColorClash"
ColorClash.minSeats = 2
ColorClash.maxSeats = 8

ColorClash.colorNames = { "Coral", "Honey", "Teal", "Violet" }

local HAND_SIZE = 7
local TURN_LIMIT = 600

export type Card = {
	color: number, -- 1..4, 0 for Wild cards
	kind: "number" | "skip" | "reverse" | "draw2" | "wild" | "wild4",
	value: number?, -- 0..9 for number cards
}

-- Built once; the same for every game.
local cards: { Card } = {}
do
	for color = 1, 4 do
		table.insert(cards, { color = color, kind = "number", value = 0 })
		for value = 1, 9 do
			table.insert(cards, { color = color, kind = "number", value = value })
			table.insert(cards, { color = color, kind = "number", value = value })
		end
		for _, kind in { "skip", "reverse", "draw2" } do
			table.insert(cards, { color = color, kind = kind :: any })
			table.insert(cards, { color = color, kind = kind :: any })
		end
	end
	for _ = 1, 4 do
		table.insert(cards, { color = 0, kind = "wild" })
	end
	for _ = 1, 4 do
		table.insert(cards, { color = 0, kind = "wild4" })
	end
end
ColorClash.cards = cards
ColorClash.deckSize = #cards

local function isWild(card: Card): boolean
	return card.kind == "wild" or card.kind == "wild4"
end

local function shuffle(list: { number }, rng: Random)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

local function nextSeat(state, from: number, steps: number): number
	return (from - 1 + state.direction * steps) % state.seatCount + 1
end

function ColorClash.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= 2 and seatCount <= 8, "Color Clash needs 2-8 seats")
	local random = rng or Random.new()
	local deck = {}
	for id = 1, #cards do
		deck[id] = id
	end
	shuffle(deck, random)

	local rules = (options and options.rules) or {}
	local handSize = if rules.handSize == 5 or rules.handSize == 10 then rules.handSize else HAND_SIZE
	local hands = {}
	for seat = 1, seatCount do
		hands[seat] = {}
		for _ = 1, handSize do
			table.insert(hands[seat], table.remove(deck) :: number)
		end
	end

	-- The first card of the discard pile is always a number card.
	local first
	repeat
		first = table.remove(deck) :: number
		if cards[first].kind ~= "number" then
			table.insert(deck, 1, first)
			first = nil
		end
	until first

	return {
		seatCount = seatCount,
		rng = random,
		deck = deck,
		discard = { first },
		discardBy = { 0 }, -- who played each discard card (0: the starting card)
		hands = hands,
		turn = 1,
		direction = 1,
		color = cards[first].color,
		pendingDraw = 0, -- stacked Draw Two / Draw Four penalties waiting
		drawnCard = nil, -- the card the current player just drew (they may play only it)
		turns = 0,
		lastAction = nil,
		winner = nil,
		reason = nil,
		botLevel = (options and options.botLevel) or "medium",
		stacking = rules.stacking ~= false,
		drawUntilPlayable = rules.drawUntilPlayable == true,
		-- "Last card!": say it as you go down to one card, or the next player can catch you
		-- (you draw 2). exposed is the seat that forgot, until the next player moves.
		lastCall = rules.lastCard ~= false,
		-- 7-0 (off by default): a 7 swaps hands with a player you pick, a 0 passes every
		-- hand along the way play goes.
		sevenZero = rules.sevenZero == true,
		exposed = nil,
	}
end

-- The last few cards on the discard pile, oldest first, with who played them (seat 0 for
-- the starting card), so the table can draw a messy pile turned toward each player.
local RECENT = 6
local function recentPlays(state): { { card: number, seat: number } }
	local out = {}
	local by = state.discardBy or {}
	for i = math.max(1, #state.discard - RECENT + 1), #state.discard do
		table.insert(out, { card = state.discard[i], seat = by[i] or 0 })
	end
	return out
end

local function topCard(state): Card
	return cards[state.discard[#state.discard]]
end

-- Can this card go on the pile right now (ignoring whose hand it is)?
local function canPlay(state, id: number): boolean
	local card = cards[id]
	local top = topCard(state)
	if state.pendingDraw > 0 then
		if not state.stacking then
			return false
		end
		return card.kind == "wild4" or (card.kind == "draw2" and top.kind == "draw2")
	end
	if isWild(card) then
		return true
	end
	if card.color == state.color then
		return true
	end
	if card.kind == "number" then
		return top.kind == "number" and top.value == card.value
	end
	return card.kind == top.kind
end
ColorClash.canPlay = canPlay

local function drawOne(state, seat: number): number?
	if #state.deck == 0 then
		-- Shuffle the discard pile (all but the top card) back in.
		local by = state.discardBy or {}
		local topBy = by[#state.discard] or 0
		local top = table.remove(state.discard) :: number
		state.deck = state.discard
		state.discard = { top }
		state.discardBy = { topBy }
		shuffle(state.deck, state.rng)
	end
	local id = table.remove(state.deck)
	if id then
		table.insert(state.hands[seat], id)
	end
	return id
end

local function endTurn(state, steps: number)
	state.drawnCard = nil
	state.turns += 1
	state.turn = nextSeat(state, state.turn, steps)
	if state.winner == nil and state.turns >= TURN_LIMIT then
		-- Safety valve so a stuck game still ends: fewest cards wins.
		local best, bestCount = 1, math.huge
		for seat = 1, state.seatCount do
			if #state.hands[seat] < bestCount then
				best, bestCount = seat, #state.hands[seat]
			end
		end
		state.winner = best
		state.reason = "Out of time: fewest cards left"
	end
end

function ColorClash.getActiveSeats(state): { number }
	if state.winner then
		return {}
	end
	return { state.turn }
end

function ColorClash.getPlayable(state, seat: number): { number }
	local out = {}
	if state.winner or seat ~= state.turn then
		return out
	end
	if state.drawnCard then
		if canPlay(state, state.drawnCard) then
			table.insert(out, state.drawnCard)
		end
		return out
	end
	for _, id in state.hands[seat] do
		if canPlay(state, id) then
			table.insert(out, id)
		end
	end
	return out
end

-- 7-0: a 7 needs someone to swap hands with.
function ColorClash.needsTarget(state, id: number): boolean
	local card = cards[id]
	return state.sevenZero == true and card ~= nil and card.kind == "number" and card.value == 7
end

-- The player on turn can catch whoever just went down to one card without calling it.
function ColorClash.canCatch(state, seat: number): boolean
	local target = state.exposed
	return target ~= nil and not state.winner and seat == state.turn and seat ~= target and #state.hands[target] == 1
end

function ColorClash.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if state.winner or seat ~= state.turn then
		return moves
	end
	-- Going down to one card: the legal plays say "Last card!" too.
	local call = if state.lastCall and #state.hands[seat] == 2 then true else nil
	for _, id in ColorClash.getPlayable(state, seat) do
		if isWild(cards[id]) then
			for color = 1, 4 do
				table.insert(moves, { kind = "play", card = id, color = color, call = call })
			end
		elseif ColorClash.needsTarget(state, id) then
			for target = 1, state.seatCount do
				if target ~= seat then
					table.insert(moves, { kind = "play", card = id, target = target, call = call })
				end
			end
		else
			table.insert(moves, { kind = "play", card = id, call = call })
		end
	end
	if ColorClash.canCatch(state, seat) then
		table.insert(moves, { kind = "catch" })
	end
	if state.drawnCard then
		table.insert(moves, { kind = "pass" })
	else
		table.insert(moves, { kind = "draw" })
	end
	return moves
end

function ColorClash.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.winner then
		return false, "The game is over"
	end
	if seat ~= state.turn then
		return false, "It's not your turn"
	end
	if type(move) ~= "table" then
		return false, "Bad move"
	end
	if move.call ~= nil and type(move.call) ~= "boolean" then
		return false, "Bad move"
	end
	if move.kind == "catch" then
		if not ColorClash.canCatch(state, seat) then
			return false, "Nobody to catch"
		end
		return true
	elseif move.kind == "draw" then
		if state.drawnCard then
			return false, "You already drew. Play that card or pass."
		end
		return true
	elseif move.kind == "pass" then
		if not state.drawnCard then
			return false, "Draw a card first"
		end
		return true
	elseif move.kind == "play" then
		local id = move.card
		if type(id) ~= "number" or id ~= id or id % 1 ~= 0 or not cards[id] then
			return false, "Bad card"
		end
		if not table.find(state.hands[seat], id) then
			return false, "That card isn't in your hand"
		end
		if state.drawnCard and id ~= state.drawnCard then
			return false, "You can only play the card you just drew"
		end
		if not canPlay(state, id) then
			if state.pendingDraw > 0 then
				if not state.stacking then
					return false, `Draw to take the {state.pendingDraw} cards`
				end
				return false, `Stack a draw card or take {state.pendingDraw} cards`
			end
			return false, "That card doesn't match"
		end
		if isWild(cards[id]) then
			local color = move.color
			if type(color) ~= "number" or color % 1 ~= 0 or color < 1 or color > 4 then
				return false, "Pick a color"
			end
		end
		if ColorClash.needsTarget(state, id) then
			local target = move.target
			if type(target) ~= "number" or target % 1 ~= 0 or target < 1 or target > state.seatCount or target == seat then
				return false, "Pick someone to swap hands with"
			end
		end
		return true
	end
	return false, "Bad move"
end

function ColorClash.applyMove(state, seat: number, move: any)
	if move.kind == "catch" then
		-- Caught! They draw 2, and it's still the catcher's turn.
		local target = state.exposed :: number
		state.exposed = nil
		for _ = 1, 2 do
			drawOne(state, target)
		end
		state.lastAction = { seat = seat, kind = "catch", target = target }
		GameModule.addStat(state, seat, "catches")
		return
	end
	-- Any other move lets a forgotten call go.
	state.exposed = nil
	if move.kind == "draw" then
		if state.pendingDraw > 0 then
			local count = state.pendingDraw
			for _ = 1, count do
				drawOne(state, seat)
			end
			state.pendingDraw = 0
			state.lastAction = { seat = seat, kind = "draw", count = count }
			endTurn(state, 1)
			return
		end
		local id = drawOne(state, seat)
		local count = if id then 1 else 0
		if state.drawUntilPlayable then
			-- Keep drawing until something fits (or the cards run out).
			while id and not canPlay(state, id) do
				id = drawOne(state, seat)
				if id then
					count += 1
				end
			end
		end
		state.lastAction = { seat = seat, kind = "draw", count = count }
		if id and canPlay(state, id) then
			state.drawnCard = id -- they may play it now, or pass
		else
			endTurn(state, 1)
		end
		return
	elseif move.kind == "pass" then
		state.lastAction = { seat = seat, kind = "pass" }
		endTurn(state, 1)
		return
	end

	-- Play a card.
	local id = move.card
	local hand = state.hands[seat]
	table.remove(hand, table.find(hand, id) :: number)
	table.insert(state.discard, id)
	state.discardBy = state.discardBy or {}
	state.discardBy[#state.discard] = seat
	local card = cards[id]
	state.color = if isWild(card) then move.color else card.color
	state.lastAction = { seat = seat, kind = "play", card = id, color = state.color }
	GameModule.addStat(state, seat, "cards")
	if isWild(card) then
		GameModule.addStat(state, seat, "wilds")
	end

	if #hand == 1 and state.lastCall then
		if move.call == true then
			state.lastAction.called = true
		else
			state.lastAction.forgot = true
			state.exposed = seat
		end
	end

	if #hand == 0 then
		state.winner = seat
		state.reason = "Played their last card"
		state.drawnCard = nil
		return
	end

	-- 7-0 swaps (after the win check: going out on a 7 or 0 just wins).
	if ColorClash.needsTarget(state, id) then
		local target = move.target :: number
		state.hands[seat], state.hands[target] = state.hands[target], state.hands[seat]
		state.lastAction.swap = target
	elseif state.sevenZero and card.kind == "number" and card.value == 0 then
		local old = table.clone(state.hands)
		for s = 1, state.seatCount do
			state.hands[nextSeat(state, s, 1)] = old[s]
		end
		state.lastAction.rotate = state.direction
	end
	if state.lastAction.swap or state.lastAction.rotate then
		-- Whoever forgot to call may not be the one holding a single card any more.
		state.exposed = nil
		state.lastAction.forgot = nil
	end

	-- Who it hits: the skipped player, or whoever must stack or take the cards.
	if card.kind == "skip" or card.kind == "draw2" or card.kind == "wild4" or (card.kind == "reverse" and state.seatCount == 2) then
		state.lastAction.victim = nextSeat(state, seat, 1)
	end
	if card.kind == "skip" then
		endTurn(state, 2)
	elseif card.kind == "reverse" then
		if state.seatCount == 2 then
			endTurn(state, 2) -- with two players Reverse works like Skip
		else
			state.direction = -state.direction
			endTurn(state, 1)
		end
	elseif card.kind == "draw2" then
		state.pendingDraw += 2
		endTurn(state, 1)
	elseif card.kind == "wild4" then
		state.pendingDraw += 4
		endTurn(state, 1)
	else
		endTurn(state, 1)
	end
end

function ColorClash.getResult(state): GameModule.Result?
	if state.winner then
		return { winners = { state.winner }, isDraw = false, reason = state.reason }
	end
	return nil
end

function ColorClash.getView(state, seat: number?)
	local counts = {}
	for s = 1, state.seatCount do
		counts[s] = #state.hands[s]
	end
	local hand = nil
	if seat and state.hands[seat] then
		hand = table.clone(state.hands[seat])
		-- Sort by color, then kind/value, so the hand reads nicely.
		table.sort(hand, function(a, b)
			local ca, cb = cards[a], cards[b]
			if ca.color ~= cb.color then
				return (if ca.color == 0 then 5 else ca.color) < (if cb.color == 0 then 5 else cb.color)
			end
			local va = if ca.kind == "number" then ca.value :: number else 10 + (table.find({ "skip", "reverse", "draw2", "wild", "wild4" }, ca.kind) :: number)
			local vb = if cb.kind == "number" then cb.value :: number else 10 + (table.find({ "skip", "reverse", "draw2", "wild", "wild4" }, cb.kind) :: number)
			if va ~= vb then
				return va < vb
			end
			return a < b
		end)
	end
	local yourTurn = seat ~= nil and seat == state.turn and not state.winner
	return {
		hand = hand,
		handCounts = counts,
		topCard = state.discard[#state.discard],
		recent = recentPlays(state),
		color = state.color,
		direction = state.direction,
		pendingDraw = state.pendingDraw,
		deckCount = #state.deck,
		lastAction = GameModule.copy(state.lastAction),
		drawnCard = if yourTurn then state.drawnCard else nil,
		playable = if yourTurn then ColorClash.getPlayable(state, seat :: number) else {},
		canPass = yourTurn and state.drawnCard ~= nil,
		lastCall = state.lastCall,
		sevenZero = state.sevenZero,
		exposed = state.exposed,
		canCatch = seat ~= nil and ColorClash.canCatch(state, seat),
		winner = state.winner,
	}
end

function ColorClash.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		local n = #state.hands[seat]
		info[seat] = if n == 1 then "1 card left!" else `{n} cards`
	end
	return info
end

-- Bots ------------------------------------------------------------------------

local function colorCounts(state, seat: number): { number }
	local counts = { 0, 0, 0, 0 }
	for _, id in state.hands[seat] do
		local c = cards[id].color
		if c > 0 then
			counts[c] += 1
		end
	end
	return counts
end

local function bestColor(state, seat: number, rng: Random): number
	local counts = colorCounts(state, seat)
	local best, bestCount = rng:NextInteger(1, 4), -1
	for c = 1, 4 do
		if counts[c] > bestCount then
			best, bestCount = c, counts[c]
		end
	end
	return best
end

local CATCH_CHANCE = { easy = 0.4, medium = 0.75, hard = 1 }
local CALL_CHANCE = { easy = 0.7, medium = 0.9, hard = 1 }

function ColorClash.chooseBotMove(state, seat: number, rng: Random): any?
	if ColorClash.canCatch(state, seat) and rng:NextNumber() < (CATCH_CHANCE[state.botLevel] or 0.75) then
		return { kind = "catch" }
	end
	local move = ColorClash.chooseBotPlay(state, seat, rng)
	if move and move.kind == "play" and state.lastCall and #state.hands[seat] == 2 then
		move.call = rng:NextNumber() < (CALL_CHANCE[state.botLevel] or 0.9)
	end
	return move
end

function ColorClash.chooseBotPlay(state, seat: number, rng: Random): any?
	local playable = ColorClash.getPlayable(state, seat)
	local fallback = if state.drawnCard then { kind = "pass" } else { kind = "draw" }
	if #playable == 0 then
		return fallback
	end

	local function playMove(id: number)
		if isWild(cards[id]) then
			local color = if state.botLevel == "easy" then rng:NextInteger(1, 4) else bestColor(state, seat, rng)
			return { kind = "play", card = id, color = color }
		end
		if ColorClash.needsTarget(state, id) then
			-- Swap with whoever holds the fewest cards (easy: anyone).
			local target, fewest = nil, math.huge
			for other = 1, state.seatCount do
				if other ~= seat then
					local n = #state.hands[other] + (if state.botLevel == "easy" then rng:NextInteger(0, 20) else rng:NextNumber())
					if n < fewest then
						target, fewest = other, n
					end
				end
			end
			return { kind = "play", card = id, target = target }
		end
		return { kind = "play", card = id }
	end

	if state.botLevel == "easy" then
		return playMove(playable[rng:NextInteger(1, #playable)])
	end

	-- Medium/hard: score each playable card and pick the best.
	local counts = colorCounts(state, seat)
	local nextUp = nextSeat(state, state.turn, 1)
	local nextCards = #state.hands[nextUp]
	local bestId, bestScore = nil, -math.huge
	for _, id in playable do
		local card = cards[id]
		local score = rng:NextNumber() * 0.5
		if isWild(card) then
			-- Save Wilds for when nothing else works...
			score -= 5
			if card.kind == "wild4" then
				score -= 1
			end
		else
			-- ...and play the color we hold most, so we keep options open.
			score += counts[card.color]
		end
		if card.kind == "skip" or card.kind == "reverse" or card.kind == "draw2" or card.kind == "wild4" then
			if state.botLevel == "hard" and nextCards <= 2 then
				score += 8 -- slow down whoever is about to win
			else
				score += 0.5
			end
		end
		if state.pendingDraw > 0 then
			score += 20 -- stacking beats eating the cards
		end
		if score > bestScore then
			bestId, bestScore = id, score
		end
	end
	return playMove(bestId :: number)
end

-- A natural pause before a bot moves: quick when forced, longer for a real choice.
function ColorClash.getBotDelay(state, seat: number, rng: Random): number
	return BotThink.delay(rng, #ColorClash.getLegalMoves(state, seat))
end

return ColorClash
