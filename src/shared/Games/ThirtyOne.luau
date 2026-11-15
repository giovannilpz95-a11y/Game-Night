-- Thirty-One: get as close to 31 in one suit as you can. 2-8 seats, played with lives.
--
-- Everyone has 3 cards. A hand is worth the total of its best suit: Aces 11, face cards
-- 10, others their number. On your turn take the top card of the stock or the discard
-- pile, then throw one card away (not the one you just took from the discard pile).
-- Instead of drawing you may knock (after the first time around): everyone else gets one
-- last turn, then all hands are shown. The lowest hand loses a life; if the knocker is
-- lowest alone they lose two, and a knocker tied for lowest is safe. Hitting exactly 31
-- is a Blitz: hands are shown at once and everyone else loses a life (everyone dealt 31
-- is spared). No chips and no betting, only lives (shown as hearts).
-- With no hearts left you're "on the county": still playing, and the next loss puts you
-- out. The last player standing wins. If everyone left would go out on the same hand, the
-- hand is replayed instead.
--
-- House rules (options.rules): trips (three of a kind: false, 30 or 30.5; true = 30.5),
-- knockDouble (default on: a knocker with the lowest hand loses two lives), county
-- (default on), firstKnock (knocking allowed on your very first turn).
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
-- trips (house rule): three of a kind is worth 30 or 30.5 (true means 30.5).
function ThirtyOne.value(hand: { number }, trips: (boolean | number)?): number
	if trips and #hand == 3 and rank(hand[1]) == rank(hand[2]) and rank(hand[2]) == rank(hand[3]) then
		local tripsValue = if type(trips) == "number" then trips else 30.5
		local totals = { 0, 0, 0, 0 }
		for _, id in hand do
			totals[suit(id)] += cardValue(id)
		end
		return math.max(tripsValue, totals[1], totals[2], totals[3], totals[4])
	end
	local totals = { 0, 0, 0, 0 }
	for _, id in hand do
		totals[suit(id)] += cardValue(id)
	end
	return math.max(totals[1], totals[2], totals[3], totals[4])
end
local value = ThirtyOne.value

-- Still in the game: lives left, or on the county (0 lives, not out yet).
local function isAlive(state, seat: number): boolean
	return not state.out[seat]
end
ThirtyOne.isAlive = isAlive

local function aliveSeats(state): { number }
	local out = {}
	for seat = 1, state.seatCount do
		if isAlive(state, seat) then
			table.insert(out, seat)
		end
	end
	return out
end

local function nextAlive(state, seat: number): number
	for i = 1, state.seatCount do
		local s = (seat - 1 + i) % state.seatCount + 1
		if isAlive(state, s) then
			return s
		end
	end
	return seat
end

local reveal: (any, number?, { number }?) -> ()

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
	-- A dealt 31 is a Blitz straight away; everyone dealt 31 is spared.
	local dealt31 = {}
	for _, seat in aliveSeats(state) do
		if value(state.hands[seat], state.trips) == 31 then
			table.insert(dealt31, seat)
		end
	end
	if #dealt31 > 0 then
		reveal(state, dealt31[1], dealt31)
	end
end

function ThirtyOne.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= 2 and seatCount <= 8, "Thirty-One needs 2-8 seats")
	local rules = if options and type(options.rules) == "table" then options.rules else {}
	local startLives = if type(rules.lives) == "number" and rules.lives >= 1 then math.floor(rules.lives) else ThirtyOne.LIVES
	local lives, out = {}, {}
	for seat = 1, seatCount do
		lives[seat] = startLives
		out[seat] = false
	end
	local trips: (boolean | number) = false
	if rules.trips == true then
		trips = 30.5
	elseif rules.trips == 30 or rules.trips == 30.5 then
		trips = rules.trips
	end
	local state = {
		seatCount = seatCount,
		rng = rng or Random.new(),
		lives = lives,
		out = out, -- out of the game (lost with no hearts left)
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
		trips = trips,
		knockDouble = rules.knockDouble ~= false,
		county = rules.county ~= false,
		firstKnock = rules.firstKnock == true,
		botLevel = (options and options.botLevel) or "medium",
	}
	deal(state)
	return state
end

-- Everyone shows their hand; lives are lost. blitz = the seat that hit 31, if any;
-- spared = every seat dealt 31 (none of them lose).
function reveal(state, blitz: number?, spared: { number }?)
	local alive = aliveSeats(state)
	local values, hands, lost = {}, {}, {}
	for _, seat in alive do
		values[tostring(seat)] = value(state.hands[seat], state.trips)
		hands[tostring(seat)] = table.clone(state.hands[seat])
	end
	if blitz then
		local safe = spared or { blitz }
		for _, seat in alive do
			if not table.find(safe, seat) then
				lost[tostring(seat)] = 1
			end
		end
	else
		local low = math.huge
		for _, seat in alive do
			low = math.min(low, value(state.hands[seat], state.trips))
		end
		local lowest = {}
		for _, seat in alive do
			if value(state.hands[seat], state.trips) == low then
				table.insert(lowest, seat)
			end
		end
		-- The knocker pays double only when they're lowest alone. Tied for lowest, the
		-- knocker is safe and the others tied with them lose (Pagat, Wikipedia, CardzMania).
		for _, seat in lowest do
			if seat ~= state.knocker then
				lost[tostring(seat)] = 1
			elseif #lowest == 1 then
				lost[tostring(seat)] = if state.knockDouble ~= false then 2 else 1
			end
		end
	end
	local before = { lives = table.clone(state.lives), out = table.clone(state.out) }
	local wentOut = {}
	for key, n in lost do
		local seat = tonumber(key) :: number
		for _ = 1, n do
			if state.lives[seat] > 0 then
				state.lives[seat] -= 1
				if state.lives[seat] == 0 and not state.county then
					state.out[seat] = true
				end
			else
				-- On the county: this loss puts you out.
				state.out[seat] = true
			end
		end
		if state.out[seat] then
			table.insert(wentOut, seat)
		end
	end
	state.showdown = { hands = hands, values = values, lost = lost, blitz = blitz, knocker = state.knocker, out = wentOut, spared = if spared and #spared > 1 then spared else nil }
	state.phase = "reveal"
	state.phaseId += 1
	local still = aliveSeats(state)
	if #still == 0 then
		-- Everyone left would go out on the same hand: replay it (Pagat).
		state.lives = before.lives
		state.out = before.out
		state.showdown.replay = true
		state.showdown.out = {}
	elseif #still == 1 then
		state.winners = still
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
		and (state.firstKnock or state.turnsThisRound >= #aliveSeats(state))
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
	if value(hand, state.trips) == 31 then
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
		reason = if #state.winners > 1 then "Everyone left went out together" else "Last one standing",
	}
end

function ThirtyOne.getView(state, seat: number?)
	local counts = {}
	for s = 1, state.seatCount do
		counts[s] = if state.hands[s] then #state.hands[s] else 0
	end
	local hand = if seat and state.hands[seat] and isAlive(state, seat) then table.clone(state.hands[seat]) else nil
	if state.phase == "done" and seat and state.hands[seat] then
		hand = table.clone(state.hands[seat])
	end
	return {
		hand = hand,
		handValue = if hand then value(hand, state.trips) else nil,
		handCounts = counts,
		lives = table.clone(state.lives),
		out = table.clone(state.out),
		county = state.county,
		firstKnock = state.firstKnock,
		dealer = state.dealer,
		lastTurns = state.lastTurns,
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
		info[seat] = if state.out[seat] then "Out" elseif n == 0 then "On the county" else string.rep("♥", n)
	end
	return info
end

function ThirtyOne.getScores(state): { [number]: number }
	return table.clone(state.lives)
end

-- Bots ------------------------------------------------------------------------

-- Best hand value after taking `extra` and throwing one card away (not `keep`).
local function bestAfter(state, hand: { number }, extra: number, keep: number?): (number, number)
	local four = table.clone(hand)
	table.insert(four, extra)
	local best, throw = -1, four[1]
	for i, id in four do
		if id ~= keep then
			local rest = table.clone(four)
			table.remove(rest, i)
			local v = value(rest, state.trips)
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
		local now = value(hand, state.trips)
		if ThirtyOne.canKnock(state, seat) then
			local at = KNOCK_AT[state.botLevel] or 26
			if state.botLevel == "hard" then
				if state.lives[seat] <= 1 then
					at += 2 -- careful on the last life (or on the county)
				elseif state.lives[seat] >= 3 and #aliveSeats(state) <= 3 then
					at -= 1 -- lives to spare and few rivals: knock earlier
				end
			end
			if state.botLevel ~= "easy" and #aliveSeats(state) >= 6 then
				at += 1 -- a big table: someone usually beats a middling hand
			end
			if now >= at and (state.botLevel ~= "easy" or rng:NextNumber() < 0.7) then
				return { kind = "knock" }
			end
		end
		local top = state.discard[#state.discard]
		if top then
			local after = bestAfter(state, hand, top, top)
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
		local _, throw = bestAfter(state, three, extra, state.taken)
		return { kind = "discard", card = throw }
	end
	return nil
end

-- A natural pause before a bot moves: quick when forced, longer for a real choice.
function ThirtyOne.getBotDelay(state, seat: number, rng: Random): number
	return BotThink.delay(rng, #ThirtyOne.getLegalMoves(state, seat))
end

return ThirtyOne
