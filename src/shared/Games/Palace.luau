-- Palace: shed your hand, then your table cards, before anyone else. 2-5 seats.
--
-- Everyone gets 3 face-down table cards, 3 face-up cards on top of them, and 3 in hand.
-- The rest is the draw pile. Before play everyone may swap hand cards with their face-up
-- cards, then says ready.
-- On your turn play one or more cards of the same rank that are equal to or higher than
-- the top of the pile (3 low ... King, Ace high). Then draw back up to 3 while the draw
-- pile lasts. Can't play? Pick up the whole pile.
-- Special cards: a 2 can go on anything and resets the pile (anything may follow it).
-- A 10 can go on anything and burns the pile (it's cleared away) and you go again.
-- Four of the same rank in a row on top also burns the pile, and you go again.
-- With your hand empty and the draw pile gone, play your face-up cards; after those,
-- flip a face-down card blind: if it can't be played, you pick up the pile with it.
-- First player out of cards wins. After TURN_LIMIT turns, fewest cards left wins.
--
-- Moves: { kind = "swap", hand = id, up = id }  |  { kind = "ready" }   (setup, everyone)
--        { kind = "play", cards = { id, ... } }  (from your hand, or face-up when it's empty)
--        { kind = "pickup" }  (only when you can't play)
--        { kind = "blind", index = 1..3 }  (hand and face-up empty)

local GameModule = require(script.Parent.Parent.GameModule)
local BotThink = require(script.Parent.Parent.BotThink)
local PlayingCards = require(script.Parent.Parent.Cards.PlayingCards)

local Palace = {}

Palace.id = "Palace"
Palace.minSeats = 2
Palace.maxSeats = 5 -- 9 cards each: 6 players would need a second deck

Palace.HAND = 3
Palace.TURN_LIMIT = 500

local rank = PlayingCards.rank

-- 3 = 3 ... King = 13, Ace = 14. 2 and 10 are special (see canPlay).
local function power(id: number): number
	local r = rank(id)
	return if r == 1 then 14 else r
end
Palace.power = power

local function isSpecial(id: number): boolean
	local r = rank(id)
	return r == 2 or r == 10
end

local function sorted(hand: { number }): { number }
	return PlayingCards.sortBy(hand, power)
end

function Palace.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= 2 and seatCount <= 5, "Palace needs 2-5 seats")
	local random = rng or Random.new()
	local deck = PlayingCards.newDeck(random)
	local hands, up, down, ready = {}, {}, {}, {}
	for seat = 1, seatCount do
		down[seat], up[seat], hands[seat] = {}, {}, {}
		for _ = 1, 3 do
			table.insert(down[seat], table.remove(deck) :: number)
		end
		for _ = 1, 3 do
			table.insert(up[seat], table.remove(deck) :: number)
		end
		for _ = 1, Palace.HAND do
			table.insert(hands[seat], table.remove(deck) :: number)
		end
		ready[seat] = false
	end
	return {
		seatCount = seatCount,
		rng = random,
		hands = hands,
		up = up, -- face-up table cards (public)
		down = down, -- face-down table cards (nobody sees them); false marks a used slot
		draw = deck,
		pile = {},
		burned = 0,
		ready = ready,
		phase = "setup", -- "setup" | "play"
		turn = 1,
		turns = 0,
		lastAction = nil,
		winners = nil,
		reason = nil,
		botLevel = (options and options.botLevel) or "medium",
	}
end

local function top(state): number?
	return state.pile[#state.pile]
end

-- Can a card of this rank go on the pile right now?
function Palace.canPlay(state, id: number): boolean
	if isSpecial(id) then
		return true
	end
	local t = top(state)
	if t == nil or rank(t) == 2 then
		return true
	end
	return power(id) >= power(t)
end

local function downLeft(state, seat: number): number
	local n = 0
	for _, id in state.down[seat] do
		if id then
			n += 1
		end
	end
	return n
end

local function cardsLeft(state, seat: number): number
	return #state.hands[seat] + #state.up[seat] + downLeft(state, seat)
end

-- Where `seat` plays from now: "hand", "up" or "down".
function Palace.source(state, seat: number): string
	if #state.hands[seat] > 0 then
		return "hand"
	elseif #state.up[seat] > 0 then
		return "up"
	end
	return "down"
end

local function startPlay(state)
	state.phase = "play"
	-- The lowest ordinary card in hand starts.
	local best, low = 1, math.huge
	for seat = 1, state.seatCount do
		for _, id in state.hands[seat] do
			if not isSpecial(id) and power(id) < low then
				best, low = seat, power(id)
			end
		end
	end
	state.turn = best
end

local function refill(state, seat: number)
	while #state.hands[seat] < Palace.HAND and #state.draw > 0 do
		table.insert(state.hands[seat], table.remove(state.draw) :: number)
	end
end

local function burns(state): boolean
	local n = #state.pile
	if n == 0 then
		return false
	end
	if rank(state.pile[n]) == 10 then
		return true
	end
	if n >= 4 then
		local r = rank(state.pile[n])
		for i = n - 3, n - 1 do
			if rank(state.pile[i]) ~= r then
				return false
			end
		end
		return true
	end
	return false
end

local function nextTurn(state, seat: number)
	state.turns += 1
	if cardsLeft(state, seat) == 0 then
		state.winners = { seat }
		state.reason = "Out of cards first"
		return
	end
	if state.turns >= Palace.TURN_LIMIT then
		local best, low = {}, math.huge
		for s = 1, state.seatCount do
			local n = cardsLeft(state, s)
			if n < low then
				best, low = { s }, n
			elseif n == low then
				table.insert(best, s)
			end
		end
		state.winners = best
		state.reason = "Fewest cards after a long game"
		return
	end
	state.turn = seat % state.seatCount + 1
end

-- Put cards on the pile; burn if needed. Returns true if the player goes again.
local function putDown(state, seat: number, cards: { number }): boolean
	for _, id in cards do
		table.insert(state.pile, id)
	end
	if burns(state) then
		state.burned += #state.pile
		state.pile = {}
		return true
	end
	return false
end

local function pickUp(state, seat: number)
	for _, id in state.pile do
		table.insert(state.hands[seat], id)
	end
	state.pile = {}
end

local function canPlayFrom(state, cards: { number }): boolean
	for _, id in cards do
		if Palace.canPlay(state, id) then
			return true
		end
	end
	return false
end

function Palace.getActiveSeats(state): { number }
	if state.winners then
		return {}
	end
	if state.phase == "setup" then
		local out = {}
		for seat = 1, state.seatCount do
			if not state.ready[seat] then
				table.insert(out, seat)
			end
		end
		return out
	end
	return { state.turn }
end

function Palace.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if state.winners then
		return moves
	end
	if state.phase == "setup" then
		if not state.ready[seat] then
			table.insert(moves, { kind = "ready" })
		end
		return moves
	end
	if seat ~= state.turn then
		return moves
	end
	local source = Palace.source(state, seat)
	if source == "down" then
		for i, id in state.down[seat] do
			if id then
				table.insert(moves, { kind = "blind", index = i })
			end
		end
		return moves
	end
	local cards = if source == "hand" then state.hands[seat] else state.up[seat]
	local byRank = {}
	for _, id in sorted(cards) do
		if Palace.canPlay(state, id) then
			local r = rank(id)
			byRank[r] = byRank[r] or {}
			table.insert(byRank[r], id)
		end
	end
	for _, ids in byRank do
		table.insert(moves, { kind = "play", cards = ids })
		if #ids > 1 then
			table.insert(moves, { kind = "play", cards = { ids[1] } })
		end
	end
	if #moves == 0 then
		table.insert(moves, { kind = "pickup" })
	end
	return moves
end

function Palace.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.winners then
		return false, "The game is over"
	end
	if type(move) ~= "table" then
		return false, "Bad move"
	end
	if state.phase == "setup" then
		if state.ready[seat] then
			return false, "You're ready: waiting for the others"
		end
		if move.kind == "ready" then
			return true
		elseif move.kind == "swap" then
			if not PlayingCards.isCardId(move.hand) or not table.find(state.hands[seat], move.hand) then
				return false, "Pick a card from your hand"
			end
			if not PlayingCards.isCardId(move.up) or not table.find(state.up[seat], move.up) then
				return false, "Pick one of your face-up cards"
			end
			return true
		end
		return false, "Swap cards or say ready"
	end
	if seat ~= state.turn then
		return false, "It's not your turn"
	end
	local source = Palace.source(state, seat)
	if move.kind == "play" then
		if source == "down" then
			return false, "Flip one of your face-down cards"
		end
		if not PlayingCards.isCardList(move.cards, 4) then
			return false, "Play 1 to 4 cards"
		end
		local from = if source == "hand" then state.hands[seat] else state.up[seat]
		if not PlayingCards.holdsAll(from, move.cards) then
			return false, if source == "hand" then "Those cards aren't in your hand" else "Play your face-up cards now"
		end
		if not PlayingCards.sameRank(move.cards) then
			return false, "Cards must all be the same rank"
		end
		if not Palace.canPlay(state, move.cards[1]) then
			return false, "Too low: play higher, a 2, a 10, or pick up"
		end
		return true
	elseif move.kind == "pickup" then
		if source == "down" then
			return false, "Flip one of your face-down cards"
		end
		if #state.pile == 0 then
			return false, "There's nothing to pick up"
		end
		local from = if source == "hand" then state.hands[seat] else state.up[seat]
		if canPlayFrom(state, from) then
			return false, "You can play, so you can't pick up"
		end
		return true
	elseif move.kind == "blind" then
		if source ~= "down" then
			return false, "Play your other cards first"
		end
		local i = move.index
		if type(i) ~= "number" or i % 1 ~= 0 or i < 1 or i > 3 or not state.down[seat][i] then
			return false, "Pick a face-down card"
		end
		return true
	end
	return false, "Bad move"
end

function Palace.applyMove(state, seat: number, move: any)
	if move.kind == "ready" then
		state.ready[seat] = true
		for s = 1, state.seatCount do
			if not state.ready[s] then
				return
			end
		end
		startPlay(state)
		return
	elseif move.kind == "swap" then
		local hand, up = state.hands[seat], state.up[seat]
		local hi, ui = table.find(hand, move.hand) :: number, table.find(up, move.up) :: number
		hand[hi], up[ui] = move.up, move.hand
		return
	elseif move.kind == "pickup" then
		local n = #state.pile
		pickUp(state, seat)
		state.lastAction = { kind = "pickup", seat = seat, count = n }
		nextTurn(state, seat)
		return
	elseif move.kind == "blind" then
		local id = state.down[seat][move.index] :: number
		state.down[seat][move.index] = false
		if Palace.canPlay(state, id) then
			local again = putDown(state, seat, { id })
			state.lastAction = { kind = "blind", seat = seat, card = id, ok = true, burned = again }
			if again and cardsLeft(state, seat) > 0 then
				return
			end
		else
			table.insert(state.pile, id)
			local n = #state.pile
			pickUp(state, seat)
			state.lastAction = { kind = "blind", seat = seat, card = id, ok = false, count = n }
		end
		nextTurn(state, seat)
		return
	end
	-- Play.
	local source = Palace.source(state, seat)
	PlayingCards.removeCards(if source == "hand" then state.hands[seat] else state.up[seat], move.cards)
	local again = putDown(state, seat, move.cards)
	refill(state, seat)
	state.lastAction = { kind = "play", seat = seat, cards = table.clone(move.cards), burned = again, from = source }
	if again and cardsLeft(state, seat) > 0 then
		state.turns += 1
		return
	end
	nextTurn(state, seat)
end

function Palace.getResult(state): GameModule.Result?
	if not state.winners then
		return nil
	end
	return { winners = table.clone(state.winners), isDraw = #state.winners > 1, reason = state.reason }
end

function Palace.getView(state, seat: number?)
	local counts, ups, downs, ready = {}, {}, {}, {}
	for s = 1, state.seatCount do
		counts[s] = #state.hands[s]
		ups[s] = sorted(state.up[s])
		local slots = {}
		for i = 1, 3 do
			slots[i] = state.down[s][i] ~= false
		end
		downs[s] = slots
		ready[s] = state.ready[s]
	end
	local pileTop = {}
	for i = math.max(1, #state.pile - 3), #state.pile do
		table.insert(pileTop, state.pile[i])
	end
	local playable = {}
	if seat and state.phase == "play" and seat == state.turn and not state.winners then
		local source = Palace.source(state, seat)
		if source ~= "down" then
			for _, id in (if source == "hand" then state.hands[seat] else state.up[seat]) do
				if Palace.canPlay(state, id) then
					playable[tostring(id)] = true
				end
			end
		end
	end
	return {
		hand = if seat and state.hands[seat] then sorted(state.hands[seat]) else nil,
		handCounts = counts,
		up = ups,
		down = downs, -- down[seat][i] = true while that face-down card is still there
		ready = ready,
		drawCount = #state.draw,
		pileTop = pileTop,
		pileCount = #state.pile,
		burned = state.burned,
		source = if seat then Palace.source(state, seat) else nil,
		playable = playable,
		turn = state.turn,
		phase = state.phase,
		lastAction = GameModule.copy(state.lastAction),
	}
end

function Palace.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		info[seat] = `{#state.hands[seat]} in hand · {#state.up[seat] + downLeft(state, seat)} on table`
	end
	return info
end

function Palace.getScores(state): { [number]: number }
	local scores = {}
	for seat = 1, state.seatCount do
		scores[seat] = -cardsLeft(state, seat)
	end
	return scores
end

-- Bots ------------------------------------------------------------------------

-- How much we'd like a card face up (good cards to have late in the game).
local function keepUp(id: number): number
	local r = rank(id)
	if r == 10 then
		return 16
	elseif r == 2 then
		return 15
	end
	return power(id)
end

function Palace.chooseBotMove(state, seat: number, rng: Random): any?
	if state.winners then
		return nil
	end
	if state.phase == "setup" then
		if state.ready[seat] then
			return nil
		end
		if state.botLevel ~= "easy" then
			-- Swap our best hand card up if it beats our worst face-up card.
			local hand, up = state.hands[seat], state.up[seat]
			local bestHand, worstUp = hand[1], up[1]
			for _, id in hand do
				if keepUp(id) > keepUp(bestHand) then
					bestHand = id
				end
			end
			for _, id in up do
				if keepUp(id) < keepUp(worstUp) then
					worstUp = id
				end
			end
			if bestHand and worstUp and keepUp(bestHand) > keepUp(worstUp) then
				return { kind = "swap", hand = bestHand, up = worstUp }
			end
		end
		return { kind = "ready" }
	end
	if seat ~= state.turn then
		return nil
	end
	local moves = Palace.getLegalMoves(state, seat)
	if #moves == 0 then
		return nil
	end
	if moves[1].kind ~= "play" then
		return moves[rng:NextInteger(1, #moves)]
	end
	-- Easy bots often play a random card, and judge the rest roughly. (Fully random
	-- play wasted their 2s and 10s and made 2-player games drag on for 10 minutes.)
	local easy = state.botLevel == "easy"
	if easy and rng:NextNumber() < 0.3 then
		return moves[rng:NextInteger(1, #moves)]
	end
	local best, bestScore = nil, math.huge
	for _, move in moves do
		if move.kind == "play" then
			local id = move.cards[1]
			local score = power(id)
			if isSpecial(id) then
				-- Save 2s and 10s; a 10 is worth it on a big pile.
				score = if rank(id) == 10 then (if #state.pile >= 6 then 0 else 30) else 25
			end
			-- Play every copy of a rank at once.
			score -= #move.cards * 0.5
			score += rng:NextNumber() * (if easy then 4 else 0.3)
			if score < bestScore then
				best, bestScore = move, score
			end
		end
	end
	return best
end

-- A natural pause before a bot moves: quick when forced, longer for a real choice.
function Palace.getBotDelay(state, seat: number, rng: Random): number
	return BotThink.delay(rng, #Palace.getLegalMoves(state, seat))
end

return Palace
