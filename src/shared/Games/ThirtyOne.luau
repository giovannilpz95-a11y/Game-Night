-- Thirty-One: get as close to 31 in one suit as you can. 2-8 seats, played with lives.
--
-- Everyone has 3 cards. A hand is worth the total of its best suit: Aces 11, face cards
-- 10, others their number. On your turn take the top card of the stock or the discard
-- pile, then throw one card away (not the one you just took from the discard pile).
-- Instead of drawing you may knock (after the first time around): everyone else gets one
-- last turn, then all hands are shown. The lowest hand loses a life; if the knocker is
-- lowest they lose two. Hitting exactly 31 is a Blitz: hands are shown at once and
-- everyone else loses a life. No chips and no betting, only lives (shown as hearts).
-- Out of lives, out of the game. The last player standing wins.
--
-- Moves: { kind = "draw", from = "stock" | "discard" }  |  { kind = "knock" }
--        { kind = "discard", card = id }  (after drawing)

local GameModule = require(script.Parent.Parent.GameModule)
local BotThink = require(script.Parent.Parent.BotThink)
local PlayingCards = require(script.Parent.Parent.Cards.PlayingCards)

local ThirtyOne = {}

ThirtyOne.id = "ThirtyOne"
ThirtyOne.minSeats = 2
ThirtyOne.maxSeats = 8

ThirtyOne.LIVES = 3 -- house rule "lives" can change it
ThirtyOne.REVEAL_SECONDS = 5
ThirtyOne.ROUND_TURN_LIMIT = 60 -- a round that drags this long is shown down

local rank, suit = PlayingCards.rank, PlayingCards.suit

local function cardValue(id: number): number
	local r = rank(id)
	return if r == 1 then 11 elseif r >= 10 then 10 else r
end

-- Best single-suit total of a hand.
function ThirtyOne.value(hand: { number }): number
	local totals = { 0, 0, 0, 0 }
	for _, id in hand do
		totals[suit(id)] += cardValue(id)
	end
	return math.max(totals[1], totals[2], totals[3], totals[4])
end
local value = ThirtyOne.value

local function aliveSeats(state): { number }
	local out = {}
	for seat = 1, state.seatCount do
		if state.lives[seat] > 0 then
			table.insert(out, seat)
		end
	end
	return out
end

local function nextAlive(state, seat: number): number
	for i = 1, state.seatCount do
		local s = (seat - 1 + i) % state.seatCount + 1
		if state.lives[s] > 0 then
			return s
		end
	end
	return seat
end

local reveal: (any, number?) -> ()

local function deal(state)
	local deck = PlayingCards.newDeck(state.rng)
	state.hands = {}
	for _, seat in aliveSeats(state) do
		state.hands[seat] = { table.remove(deck), table.remove(deck), table.remove(deck) } :: { number }
	end
	state.stock = deck
	state.discard = { table.remove(state.stock) :: number }
	state.round += 1
	state.dealer = nextAlive(state, state.dealer)
	state.turn = nextAlive(state, state.dealer)
	state.phase = "draw"
	state.phaseId += 1
	state.knocker = nil
	state.lastTurns = 0
	state.turnsThisRound = 0
	state.taken = nil
	state.lastAction = nil
	state.showdown = nil
	-- A dealt 31 is a Blitz straight away.
	for _, seat in aliveSeats(state) do
		if value(state.hands[seat]) == 31 then
			reveal(state, seat)
			return
		end
	end
end

function ThirtyOne.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= 2 and seatCount <= 8, "Thirty-One needs 2-8 seats")
	local rules = if options and type(options.rules) == "table" then options.rules else {}
	local startLives = if type(rules.lives) == "number" and rules.lives >= 1 then math.floor(rules.lives) else ThirtyOne.LIVES
	local lives = {}
	for seat = 1, seatCount do
		lives[seat] = startLives
	end
	local state = {
		seatCount = seatCount,
		rng = rng or Random.new(),
		lives = lives,
		startLives = startLives,
		hands = {},
		stock = {},
		discard = {},
		round = 0,
		dealer = seatCount, -- seat 1 deals first
		turn = 1,
		phase = "draw", -- "draw" | "discard" | "reveal" | "done"
		phaseId = 0,
		knocker = nil,
		lastTurns = 0, -- turns left after a knock
		turnsThisRound = 0,
		taken = nil, -- the card just taken from the discard pile (can't throw it back)
		showdown = nil, -- { hands, values, lost, blitz, knocker }
		lastAction = nil,
		turnsTotal = 0,
		winners = nil,
		botLevel = (options and options.botLevel) or "medium",
	}
	deal(state)
	return state
end

-- Everyone shows their hand; lives are lost. blitz = the seat that hit 31, if any.
function reveal(state, blitz: number?)
	local alive = aliveSeats(state)
	local values, hands, lost = {}, {}, {}
	for _, seat in alive do
		values[tostring(seat)] = value(state.hands[seat])
		hands[tostring(seat)] = table.clone(state.hands[seat])
	end
	if blitz then
		for _, seat in alive do
			if seat ~= blitz then
				lost[tostring(seat)] = 1
			end
		end
	else
		local low = math.huge
		for _, seat in alive do
			low = math.min(low, value(state.hands[seat]))
		end
		for _, seat in alive do
			if value(state.hands[seat]) == low then
				lost[tostring(seat)] = if seat == state.knocker then 2 else 1
			end
		end
	end
	for key, n in lost do
		local seat = tonumber(key) :: number
		state.lives[seat] = math.max(0, state.lives[seat] - n)
	end
	state.showdown = { hands = hands, values = values, lost = lost, blitz = blitz, knocker = state.knocker }
	state.phase = "reveal"
	state.phaseId += 1
	local still = aliveSeats(state)
	if #still <= 1 then
		if #still == 1 then
			state.winners = still
		else
			-- Everyone went out together: they share the win.
			local shared = {}
			for _, seat in alive do
				table.insert(shared, seat)
			end
			state.winners = shared
		end
		state.phase = "done"
	end
end

local function endTurn(state, seat: number)
	state.turnsThisRound += 1
	state.turnsTotal += 1
	state.taken = nil
	if state.knocker then
		state.lastTurns -= 1
		if state.lastTurns <= 0 then
			reveal(state, nil)
			return
		end
	elseif state.turnsThisRound >= ThirtyOne.ROUND_TURN_LIMIT then
		reveal(state, nil)
		return
	end
	state.turn = nextAlive(state, seat)
	state.phase = "draw"
end

function ThirtyOne.canKnock(state, seat: number): boolean
	return state.phase == "draw"
		and seat == state.turn
		and state.knocker == nil
		and state.turnsThisRound >= #aliveSeats(state)
end

function ThirtyOne.getActiveSeats(state): { number }
	if state.winners or (state.phase ~= "draw" and state.phase ~= "discard") then
		return {}
	end
	return { state.turn }
end

function ThirtyOne.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if state.winners or seat ~= state.turn then
		return moves
	end
	if state.phase == "draw" then
		table.insert(moves, { kind = "draw", from = "stock" })
		if #state.discard > 0 then
			table.insert(moves, { kind = "draw", from = "discard" })
		end
		if ThirtyOne.canKnock(state, seat) then
			table.insert(moves, { kind = "knock" })
		end
	elseif state.phase == "discard" then
		for _, id in state.hands[seat] do
			if id ~= state.taken then
				table.insert(moves, { kind = "discard", card = id })
			end
		end
	end
	return moves
end

function ThirtyOne.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.winners then
		return false, "The game is over"
	end
	if type(move) ~= "table" then
		return false, "Bad move"
	end
	if seat ~= state.turn or (state.phase ~= "draw" and state.phase ~= "discard") then
		return false, "It's not your turn"
	end
	if move.kind == "draw" then
		if state.phase ~= "draw" then
			return false, "Throw a card away first"
		end
		if move.from ~= "stock" and move.from ~= "discard" then
			return false, "Draw from the stock or the discard pile"
		end
		if move.from == "discard" and #state.discard == 0 then
			return false, "The discard pile is empty"
		end
		return true
	elseif move.kind == "knock" then
		if not ThirtyOne.canKnock(state, seat) then
			return false, if state.knocker then "Someone already knocked" else "You can't knock yet"
		end
		return true
	elseif move.kind == "discard" then
		if state.phase ~= "discard" then
			return false, "Draw a card first"
		end
		if not PlayingCards.isCardId(move.card) or not table.find(state.hands[seat], move.card) then
			return false, "That card isn't in your hand"
		end
		if move.card == state.taken then
			return false, "You can't throw back the card you just took"
		end
		return true
	end
	return false, "Bad move"
end

function ThirtyOne.applyMove(state, seat: number, move: any)
	if move.kind == "knock" then
		state.knocker = seat
		state.lastTurns = #aliveSeats(state) - 1
		state.lastAction = { kind = "knock", seat = seat }
		state.turnsThisRound += 1
		state.turnsTotal += 1
		state.turn = nextAlive(state, seat)
		return
	elseif move.kind == "draw" then
		local id
		if move.from == "discard" then
			id = table.remove(state.discard) :: number
			state.taken = id
		else
			if #state.stock == 0 then
				-- Shuffle the discard pile (all but its top card) into a new stock.
				local top = table.remove(state.discard)
				state.stock = state.discard
				PlayingCards.shuffle(state.stock, state.rng)
				state.discard = { top :: number }
			end
			id = table.remove(state.stock) :: number
			state.taken = nil
		end
		table.insert(state.hands[seat], id)
		state.lastAction = { kind = "draw", seat = seat, from = move.from, card = if move.from == "discard" then id else nil }
		state.phase = "discard"
		return
	end
	local hand = state.hands[seat]
	table.remove(hand, table.find(hand, move.card) :: number)
	table.insert(state.discard, move.card)
	local prev = state.lastAction
	state.lastAction = { kind = "discard", seat = seat, card = move.card, from = prev and prev.from, took = prev and prev.card }
	if value(hand) == 31 then
		reveal(state, seat)
		return
	end
	endTurn(state, seat)
end

function ThirtyOne.getTimer(state): { id: number, seconds: number }?
	if state.phase == "reveal" and not state.winners then
		return { id = state.phaseId, seconds = ThirtyOne.REVEAL_SECONDS }
	end
	return nil
end

function ThirtyOne.onTimeout(state)
	if state.phase == "reveal" then
		deal(state)
	end
end

function ThirtyOne.getResult(state): GameModule.Result?
	if not state.winners then
		return nil
	end
	return {
		winners = table.clone(state.winners),
		isDraw = #state.winners > 1,
		reason = if #state.winners > 1 then "Everyone left went out together" else "Last one with lives",
	}
end

function ThirtyOne.getView(state, seat: number?)
	local counts = {}
	for s = 1, state.seatCount do
		counts[s] = if state.hands[s] then #state.hands[s] else 0
	end
	local hand = if seat and state.hands[seat] and state.lives[seat] > 0 then table.clone(state.hands[seat]) else nil
	if state.phase == "done" and seat and state.hands[seat] then
		hand = table.clone(state.hands[seat])
	end
	return {
		hand = hand,
		handValue = if hand then value(hand) else nil,
		handCounts = counts,
		lives = table.clone(state.lives),
		startLives = state.startLives,
		discardTop = state.discard[#state.discard],
		stockCount = #state.stock,
		turn = state.turn,
		phase = state.phase,
		knocker = state.knocker,
		canKnock = seat ~= nil and ThirtyOne.canKnock(state, seat),
		taken = if seat == state.turn then state.taken else nil,
		showdown = GameModule.copy(state.showdown),
		lastAction = GameModule.copy(state.lastAction),
		round = state.round,
	}
end

function ThirtyOne.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		local n = state.lives[seat]
		info[seat] = if n == 0 then "Out" else string.rep("♥", n)
	end
	return info
end

function ThirtyOne.getScores(state): { [number]: number }
	return table.clone(state.lives)
end

-- Bots ------------------------------------------------------------------------

-- Best hand value after taking `extra` and throwing one card away (not `keep`).
local function bestAfter(hand: { number }, extra: number, keep: number?): (number, number)
	local four = table.clone(hand)
	table.insert(four, extra)
	local best, throw = -1, four[1]
	for i, id in four do
		if id ~= keep then
			local rest = table.clone(four)
			table.remove(rest, i)
			local v = value(rest)
			if v > best then
				best, throw = v, id
			end
		end
	end
	return best, throw
end

local KNOCK_AT = { easy = 28, medium = 26, hard = 25 }

function ThirtyOne.chooseBotMove(state, seat: number, rng: Random): any?
	if state.winners or seat ~= state.turn then
		return nil
	end
	local hand = state.hands[seat]
	if state.phase == "draw" then
		local now = value(hand)
		if ThirtyOne.canKnock(state, seat) then
			local at = KNOCK_AT[state.botLevel] or 26
			if state.botLevel == "hard" and state.lives[seat] == 1 then
				at += 2 -- careful on the last life
			end
			if now >= at and (state.botLevel ~= "easy" or rng:NextNumber() < 0.7) then
				return { kind = "knock" }
			end
		end
		local top = state.discard[#state.discard]
		if top then
			local after = bestAfter(hand, top, top)
			local margin = if state.botLevel == "easy" then 4 else 1
			if after >= now + margin then
				return { kind = "draw", from = "discard" }
			end
		end
		return { kind = "draw", from = "stock" }
	elseif state.phase == "discard" then
		if state.botLevel == "easy" and rng:NextNumber() < 0.3 then
			local moves = ThirtyOne.getLegalMoves(state, seat)
			return moves[rng:NextInteger(1, #moves)]
		end
		local three = table.clone(hand)
		local extra = table.remove(three) :: number
		local _, throw = bestAfter(three, extra, state.taken)
		return { kind = "discard", card = throw }
	end
	return nil
end

-- A natural pause before a bot moves: quick when forced, longer for a real choice.
function ThirtyOne.getBotDelay(state, seat: number, rng: Random): number
	return BotThink.delay(rng, #ThirtyOne.getLegalMoves(state, seat))
end

return ThirtyOne
