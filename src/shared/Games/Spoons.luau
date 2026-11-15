-- Spoons: pass cards fast, collect four of a kind, grab a spoon. 3-8 seats.
--
-- There is one spoon fewer than players. Everyone holds 4 cards plus the card coming in,
-- and passes one of their 5 to the left; the dealer draws from the deck, the last player
-- passes to the discard pile.
-- Free passing (default, like a real table): no turns. Pass whenever you hold 5; your card
-- waits face down in front of the next player until they're ready for it. A player who sits
-- on their cards while the others keep passing (or when nobody passes for the pass clock)
-- has a card passed for them.
-- Together (house rule): everyone passes at once; the next pass starts when all have.
-- Four of a kind? Grab a spoon, quietly: the first grab shows only as a spoon missing from
-- the middle. Anyone may grab once a spoon is gone. A second grab, or QUIET_SECONDS, and
-- everyone knows: the scramble. Whoever is left without a spoon is out (or gets a letter).
-- Fresh deal, one spoon fewer, until one player (two, with "Two winners") is left.
-- House rule "False grab": grabbing with no four of a kind before any spoon is gone loses
-- you the round on the spot.
--
-- The deck uses as many ranks as players + 2 (4 cards each), so sets come together at
-- a good pace with any table size.
--
-- A round can jam: say two players each hold a pair of 7s and a pair of 10s, so nobody can
-- ever get four. After STALL_PASSES passes bots start breaking a pair now and then, and
-- after MAX_PASSES passes without a grab the round is dealt again (nobody is out).
--
-- Moves:
--   { kind = "pass", card = id }   (pass phase)
--   { kind = "grab" }              (with four of a kind, or once the scramble starts)

local GameModule = require(script.Parent.Parent.GameModule)
local PlayingCards = require(script.Parent.Parent.Cards.PlayingCards)

local Spoons = {}

Spoons.id = "Spoons"
Spoons.minSeats = 3
Spoons.maxSeats = 8

Spoons.PASS_SECONDS = 8 -- house rule "passSeconds" can change it
Spoons.SCRAMBLE_SECONDS = 5
Spoons.REVEAL_SECONDS = 4
Spoons.STALL_PASSES = 12 -- passes in a round before bots start giving up a pair
Spoons.MAX_PASSES = 60 -- passes in a round before a fresh deal (free passing: the dealer's)
Spoons.QUIET_SECONDS = 2 -- the first grab stays quiet this long, unless a second grab comes
Spoons.IDLE_PASS_TIME = 1.3 -- free passing: about how long one pass takes, for the idle limit

local rank = PlayingCards.rank

local function shuffle(list: { number }, rng: Random)
	PlayingCards.shuffle(list, rng)
end

local function aliveSeats(state): { number }
	local out = {}
	for seat = 1, state.seatCount do
		if not state.out[seat] then
			table.insert(out, seat)
		end
	end
	return out
end

-- The next seat still in, going left (up in seat number).
local function nextAlive(state, seat: number): number
	for i = 1, state.seatCount do
		local s = (seat - 1 + i) % state.seatCount + 1
		if not state.out[s] then
			return s
		end
	end
	return seat
end

local function prevAlive(state, seat: number): number
	for i = 1, state.seatCount do
		local s = (seat - 1 - i) % state.seatCount + 1
		if not state.out[s] then
			return s
		end
	end
	return seat
end

local function drawOne(state): number?
	if #state.deck == 0 then
		state.deck = state.discard
		state.discard = {}
		shuffle(state.deck, state.rng)
	end
	return table.remove(state.deck)
end

local function hasFour(hand: { number }): number?
	for r, n in PlayingCards.rankCounts(hand) do
		if n >= 4 then
			return r
		end
	end
	return nil
end
Spoons.hasFour = hasFour

-- Deal a fresh round for the players still in.
local function deal(state)
	local alive = aliveSeats(state)
	local ranks = {}
	local all = {}
	for r = 1, 13 do
		table.insert(all, r)
	end
	shuffle(all, state.rng)
	for i = 1, math.min(13, #alive + 2) do
		table.insert(ranks, all[i])
	end
	state.deck = PlayingCards.newDeck(state.rng, ranks)
	state.discard = {}
	state.hands = {}
	for _, seat in alive do
		local hand = {}
		for _ = 1, 4 do
			table.insert(hand, table.remove(state.deck) :: number)
		end
		-- Everyone starts the first pass with a fifth card from the deck.
		table.insert(hand, drawOne(state) :: number)
		state.hands[seat] = hand
	end
	state.passed = {}
	state.queue = {} -- free passing: queue[seat] = cards waiting for them, oldest first
	state.idle = {} -- free passing: passes by others while this seat sat on 5 cards
	for _, seat in alive do
		state.queue[seat] = {}
		state.idle[seat] = 0
	end
	state.spoons = {} -- spoons[seat] = order they grabbed it in
	state.spoonsLeft = #alive - 1
	state.phase = "pass"
	state.quiet = false
	state.falseGrab = nil
	state.round += 1
	state.passNumber = 1
	state.phaseId += 1
end

function Spoons.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= 3 and seatCount <= 8, "Spoons needs 3-8 seats")
	local state = {
		seatCount = seatCount,
		rng = rng or Random.new(),
		out = {}, -- out[seat] = the round they were knocked out in
		dealer = 1,
		round = 0,
		phaseId = 0,
		phase = "pass", -- "pass" | "scramble" | "reveal"
		passNumber = 0,
		hands = {},
		passed = {},
		spoons = {},
		spoonsLeft = 0,
		deck = {},
		discard = {},
		firstGrab = nil, -- { seat, rank } of whoever started the scramble
		lastOut = nil,
		winner = nil,
		botLevel = (options and options.botLevel) or "medium",
		passSeconds = Spoons.PASS_SECONDS,
		acted = {}, -- acted[seat] = move count at their last move (who's paying attention)
		moves = 0,
	}
	local rules = if options and type(options.rules) == "table" then options.rules else {}
	state.free = rules.passing ~= "together"
	state.falseGrabRule = rules.falseGrab == true
	state.twoWinners = rules.twoWinners == true and seatCount >= 3
	if type(rules.passSeconds) == "number" and rules.passSeconds > 0 then
		state.passSeconds = rules.passSeconds
	end
	-- Letters mode: losing a round earns the next letter of the word; spell it and you're out.
	if rules.letters == "PIG" or rules.letters == "SPOON" then
		state.word = rules.letters
		state.letters = {} -- letters[seat] = how many letters they have
	end
	deal(state)
	return state
end

local function finishPass(state)
	-- Cards move all at once, as if everyone slid them over together.
	local dealer = state.dealer
	local last = prevAlive(state, dealer)
	local incoming = {}
	for seat, card in state.passed do
		if seat == last then
			table.insert(state.discard, card)
		else
			incoming[nextAlive(state, seat)] = card
		end
	end
	incoming[dealer] = drawOne(state)
	for seat, card in incoming do
		table.insert(state.hands[seat], card)
	end
	state.passed = {}
	state.passNumber += 1
	state.phaseId += 1
	if state.passNumber > Spoons.MAX_PASSES then
		-- Jammed: nobody has got four in all this time. Deal again; nobody goes out.
		deal(state)
		state.round -= 1 -- it's the same round, dealt again
		state.freshDeals = (state.freshDeals or 0) + 1
	end
end

local function grabCount(state): number
	local n = 0
	for _ in state.spoons do
		n += 1
	end
	return n
end

local function endRound(state)
	local loser = state.falseGrab
	if not loser then
		for _, seat in aliveSeats(state) do
			if not state.spoons[seat] then
				loser = seat
			end
		end
	end
	state.lastOut = nil
	state.lastLetter = nil
	state.lastFalseGrab = state.falseGrab
	if loser and state.word then
		state.letters[loser] = (state.letters[loser] or 0) + 1
		state.lastLetter = loser
		if state.letters[loser] >= #state.word then
			state.out[loser] = state.round
			state.lastOut = loser
		end
	elseif loser then
		state.out[loser] = state.round
		state.lastOut = loser
	end
	local alive = aliveSeats(state)
	if #alive <= 1 or (state.twoWinners and #alive <= 2) then
		state.winner = alive[1]
		state.winners = alive
		state.phase = "done"
		return
	end
	state.phase = "reveal"
	state.quiet = false
	state.phaseId += 1
end

local function grab(state, seat: number)
	local count = grabCount(state)
	if count == 0 and state.phase == "pass" and not hasFour(state.hands[seat]) then
		-- A false grab (house rule): you lose the round on the spot.
		state.falseGrab = seat
		state.firstGrab = nil
		endRound(state)
		return
	end
	state.spoons[seat] = count + 1
	state.spoonsLeft -= 1
	if count == 0 then
		-- Quiet: only a spoon missing from the middle gives it away, for a moment.
		state.firstGrab = { seat = seat, rank = hasFour(state.hands[seat]) }
		state.quiet = true
		state.phaseId += 1
	elseif state.phase == "pass" then
		-- A second grab: now everyone knows.
		state.phase = "scramble"
		state.quiet = false
		state.phaseId += 1
	end
	if state.spoonsLeft <= 0 then
		endRound(state)
	end
end

-- Free passing: the card a seat passes goes into the next player's queue, and anyone
-- holding 4 picks up the next card waiting for them (the dealer draws from the deck).
local function pickUp(state, seat: number)
	if #state.hands[seat] >= 5 then
		return
	end
	if seat == state.dealer then
		local card = drawOne(state)
		if card then
			table.insert(state.hands[seat], card)
			state.idle[seat] = 0
		end
	elseif #state.queue[seat] > 0 then
		table.insert(state.hands[seat], table.remove(state.queue[seat], 1) :: number)
		state.idle[seat] = 0
	end
end

local function idleLimit(state): number
	local others = #aliveSeats(state) - 1
	return math.max(8, math.ceil((state.passSeconds or Spoons.PASS_SECONDS) * others / Spoons.IDLE_PASS_TIME))
end

local passFree

-- Passes one card for a seat that isn't keeping up (the clock, or everyone else moving on).
local function passFor(state, seat: number)
	local hand = state.hands[seat]
	if #hand < 5 then
		return
	end
	passFree(state, seat, Spoons._worstCard(hand, state.rng))
end

function passFree(state, seat: number, card: number)
	local hand = state.hands[seat]
	table.remove(hand, table.find(hand, card) :: number)
	local last = prevAlive(state, state.dealer)
	local nextSeat = nextAlive(state, seat)
	if seat == last then
		table.insert(state.discard, card)
	else
		table.insert(state.queue[nextSeat], card)
	end
	state.phaseId += 1
	if seat == state.dealer then
		state.passNumber += 1
	end
	pickUp(state, seat)
	if seat ~= last then
		pickUp(state, nextSeat)
	end
	-- The deck may have run dry with every card in hand; a discard refills it.
	pickUp(state, state.dealer)
	if state.passNumber > Spoons.MAX_PASSES then
		deal(state)
		state.round -= 1
		state.freshDeals = (state.freshDeals or 0) + 1
		return
	end
	-- Everyone else sitting on 5 cards waited one more pass.
	local limit = idleLimit(state)
	local slow = {}
	for _, s in aliveSeats(state) do
		if s ~= seat and #state.hands[s] >= 5 then
			state.idle[s] += 1
			if state.idle[s] >= limit and not hasFour(state.hands[s]) and not state.spoons[s] then
				table.insert(slow, s)
			end
		end
	end
	for _, s in slow do
		if state.phase == "pass" and #state.hands[s] >= 5 then
			state.idle[s] = 0
			passFor(state, s)
		end
	end
end

function Spoons.getActiveSeats(state): { number }
	if state.winner or state.phase == "done" or state.phase == "reveal" then
		return {}
	end
	local out = {}
	local spoonGone = grabCount(state) > 0
	for _, seat in aliveSeats(state) do
		if state.phase == "scramble" then
			if not state.spoons[seat] then
				table.insert(out, seat)
			end
		elseif state.spoons[seat] then
			continue -- safe: nothing left to do this round
		elseif hasFour(state.hands[seat]) or spoonGone then
			table.insert(out, seat)
		elseif state.free then
			if #state.hands[seat] >= 5 then
				table.insert(out, seat)
			end
		elseif not state.passed[seat] then
			table.insert(out, seat)
		end
	end
	return out
end

-- Anyone still in may reach for a spoon at any time (a false grab is refused, or costs the
-- round with the house rule).
function Spoons.getInterruptSeats(state): { number }
	if state.winner or state.phase ~= "pass" then
		return {}
	end
	local active = Spoons.getActiveSeats(state)
	local out = {}
	for _, seat in aliveSeats(state) do
		if not state.spoons[seat] and not table.find(active, seat) then
			table.insert(out, seat)
		end
	end
	return out
end

local function canPass(state, seat: number): boolean
	if state.phase ~= "pass" or state.spoons[seat] then
		return false
	end
	if state.free then
		return #state.hands[seat] >= 5
	end
	return not state.passed[seat]
end

function Spoons.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if not table.find(Spoons.getActiveSeats(state), seat) then
		return moves
	end
	if state.phase == "scramble" or hasFour(state.hands[seat]) or grabCount(state) > 0 then
		table.insert(moves, { kind = "grab" })
	end
	if canPass(state, seat) then
		for _, card in state.hands[seat] do
			table.insert(moves, { kind = "pass", card = card })
		end
	end
	return moves
end

function Spoons.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.winner then
		return false, "The game is over"
	end
	if type(move) ~= "table" then
		return false, "Bad move"
	end
	if state.out[seat] then
		return false, "You're out"
	end
	if state.phase == "reveal" then
		return false, "Next round coming up"
	end
	if move.kind == "grab" then
		if state.spoons[seat] then
			return false, "You already have a spoon"
		end
		if state.phase == "pass" and grabCount(state) == 0 and not hasFour(state.hands[seat]) and not state.falseGrabRule then
			return false, "You need four of a kind first"
		end
		return true
	elseif move.kind == "pass" then
		if state.phase ~= "pass" then
			return false, "Grab a spoon!"
		end
		if state.spoons[seat] then
			return false, "You have a spoon: you're safe"
		end
		if not canPass(state, seat) then
			return false, if state.free then "Wait for the next card" else "Waiting for the others"
		end
		if not PlayingCards.isCardId(move.card) or not table.find(state.hands[seat], move.card) then
			return false, "That card isn't in your hand"
		end
		return true
	end
	return false, "Bad move"
end

function Spoons.applyMove(state, seat: number, move: any)
	state.moves += 1
	state.acted[seat] = state.moves
	if move.kind == "grab" then
		grab(state, seat)
		return
	end
	if state.free then
		passFree(state, seat, move.card)
		return
	end
	local hand = state.hands[seat]
	table.remove(hand, table.find(hand, move.card) :: number)
	state.passed[seat] = move.card
	local everyone = true
	for _, s in aliveSeats(state) do
		if not state.passed[s] then
			everyone = false
		end
	end
	if everyone then
		finishPass(state)
	end
end

-- A sensible card to pass: one of the rank we hold fewest of. In a jammed round (two
-- pairs each, nobody getting anywhere) sometimes give up a pair instead.
local function worstCard(hand: { number }, rng: Random, stalled: boolean?): number
	local counts = PlayingCards.rankCounts(hand)
	if stalled and rng:NextNumber() < 0.5 then
		local most = 0
		for _, n in counts do
			most = math.max(most, n)
		end
		if most <= 2 then
			local pairs = {}
			for _, card in hand do
				if counts[rank(card)] == 2 then
					table.insert(pairs, card)
				end
			end
			if #pairs > 0 then
				return pairs[rng:NextInteger(1, #pairs)]
			end
		end
	end
	local best, bestScore = hand[1], math.huge
	for _, card in hand do
		local score = counts[rank(card)] + rng:NextNumber() * 0.5
		if score < bestScore then
			best, bestScore = card, score
		end
	end
	return best
end
Spoons._worstCard = worstCard

function Spoons.getTimer(state): { id: number, seconds: number }?
	if state.winner or state.phase == "done" then
		return nil
	end
	local seconds = if state.phase == "pass" and state.quiet then Spoons.QUIET_SECONDS
		elseif state.phase == "pass" then (state.passSeconds or Spoons.PASS_SECONDS)
		elseif state.phase == "scramble" then Spoons.SCRAMBLE_SECONDS
		else Spoons.REVEAL_SECONDS
	return { id = state.phaseId, seconds = seconds }
end

function Spoons.onTimeout(state)
	if state.phase == "pass" and state.quiet then
		-- The quiet grab is out: everyone scrambles.
		state.quiet = false
		state.phase = "scramble"
		state.phaseId += 1
	elseif state.phase == "pass" and state.free then
		-- Nobody passed for a whole pass clock: pass for everyone sitting on 5 cards.
		for _, seat in aliveSeats(state) do
			if state.phase == "pass" and #(state.hands[seat] or {}) >= 5 and not hasFour(state.hands[seat]) then
				passFor(state, seat)
			end
		end
		state.phaseId += 1
	elseif state.phase == "pass" then
		for _, seat in aliveSeats(state) do
			if not state.passed[seat] then
				local hand = state.hands[seat]
				local card = worstCard(hand, state.rng)
				table.remove(hand, table.find(hand, card) :: number)
				state.passed[seat] = card
			end
		end
		finishPass(state)
	elseif state.phase == "scramble" then
		-- Out of time: the spoons left go to the players who were moving most recently, so
		-- whoever looked away is the one left out.
		local waiting = {}
		for _, seat in aliveSeats(state) do
			if not state.spoons[seat] then
				table.insert(waiting, seat)
			end
		end
		shuffle(waiting, state.rng)
		table.sort(waiting, function(a, b)
			return (state.acted[a] or 0) > (state.acted[b] or 0)
		end)
		for i = 1, math.max(0, state.spoonsLeft) do
			local seat = waiting[i]
			if seat then
				state.spoons[seat] = grabCount(state) + 1
			end
		end
		state.spoonsLeft = 0
		endRound(state)
	elseif state.phase == "reveal" then
		state.dealer = nextAlive(state, state.dealer)
		state.firstGrab = nil
		state.lastFalseGrab = nil
		deal(state)
	end
end

function Spoons.getResult(state): GameModule.Result?
	if state.winners and #state.winners > 1 then
		return { winners = table.clone(state.winners), isDraw = false, reason = "The last two holding spoons" }
	end
	if state.winner then
		return { winners = { state.winner }, isDraw = false, reason = "Last one holding a spoon" }
	end
	return nil
end

function Spoons.getView(state, seat: number?)
	local spoonHolders = {}
	for s, order in state.spoons do
		spoonHolders[tostring(s)] = order
	end
	local outSeats = {}
	for s, roundOut in state.out do
		outSeats[tostring(s)] = roundOut
	end
	local hand = if seat and state.hands[seat] and not state.out[seat] then PlayingCards.sortHand(state.hands[seat]) else nil
	local revealHand = nil
	if state.phase ~= "pass" and state.firstGrab and state.hands[state.firstGrab.seat] then
		-- Everyone gets to see the winning set once the spoons are flying.
		revealHand = PlayingCards.sortHand(state.hands[state.firstGrab.seat])
	end
	local handCounts, queueCounts = {}, {}
	for s = 1, state.seatCount do
		handCounts[s] = if state.hands[s] and not state.out[s] then #state.hands[s] else 0
		queueCounts[s] = if state.queue and state.queue[s] then #state.queue[s] else 0
	end
	-- A quiet grab shows only as a missing spoon (and the spoon in their hand on the table).
	local firstGrab = if state.quiet and not (seat and state.firstGrab and state.firstGrab.seat == seat) then nil else GameModule.copy(state.firstGrab)
	return {
		phase = state.phase,
		quiet = state.quiet,
		free = state.free,
		handCounts = handCounts,
		queueCounts = queueCounts,
		canPass = seat ~= nil and state.hands[seat] ~= nil and not state.out[seat] and canPass(state, seat),
		spoonGone = grabCount(state) > 0,
		falseGrabRule = state.falseGrabRule,
		lastFalseGrab = state.lastFalseGrab,
		twoWinners = state.twoWinners,
		round = state.round,
		passNumber = state.passNumber,
		hand = hand,
		youPassed = seat ~= nil and state.passed[seat] ~= nil,
		passedSeats = (function()
			local list = {}
			for s in state.passed do
				table.insert(list, s)
			end
			return list
		end)(),
		hasFour = hand ~= nil and hasFour(hand) ~= nil,
		spoonsLeft = state.spoonsLeft,
		spoonHolders = spoonHolders,
		youHaveSpoon = seat ~= nil and state.spoons[seat] ~= nil,
		out = outSeats,
		youAreOut = seat ~= nil and state.out[seat] ~= nil,
		dealer = state.dealer,
		firstGrab = firstGrab,
		revealHand = revealHand,
		lastOut = state.lastOut,
		word = state.word,
		letters = (function()
			local list = {}
			for s, n in state.letters or {} do
				list[tostring(s)] = string.sub(state.word, 1, n)
			end
			return list
		end)(),
		lastLetter = state.lastLetter,
		freshDeals = state.freshDeals or 0, -- how many jammed rounds were dealt again
	}
end

function Spoons.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		local letters = if state.word and state.letters and (state.letters[seat] or 0) > 0 then string.sub(state.word, 1, state.letters[seat]) .. " · " else ""
		if state.out[seat] then
			info[seat] = "Out"
		elseif state.spoons[seat] then
			info[seat] = letters .. "Got a spoon!"
		elseif state.phase == "pass" and not state.free and state.passed[seat] then
			info[seat] = letters .. "Passed"
		else
			info[seat] = letters .. (if seat == state.dealer then "Dealer" else "In")
		end
	end
	return info
end

-- How long each player lasted: higher is better.
function Spoons.getScores(state): { [number]: number }
	local scores = {}
	for seat = 1, state.seatCount do
		scores[seat] = if state.out[seat] then state.out[seat] else state.round + 1
	end
	return scores
end

-- Bots ------------------------------------------------------------------------

-- Reaction times for grabbing (seconds): [first grab, scramble grab]
local GRAB = { easy = { 2.2, 1.6 }, medium = { 1.3, 1.1 }, hard = { 0.6, 0.6 } }

function Spoons.getBotDelay(state, seat: number, rng: Random): number
	local g = GRAB[state.botLevel] or GRAB.medium
	if state.phase == "scramble" then
		return 0.35 + rng:NextNumber() * g[2]
	end
	if state.hands[seat] and hasFour(state.hands[seat]) then
		return 0.3 + rng:NextNumber() * g[1]
	end
	if grabCount(state) > 0 then
		-- A quiet grab: it takes a moment to notice the missing spoon.
		return 0.6 + rng:NextNumber() * g[1] * 1.4
	end
	return 0.7 + rng:NextNumber() * 1.3 -- passing
end

function Spoons.chooseBotMove(state, seat: number, rng: Random): any?
	if state.phase == "scramble" then
		return { kind = "grab" }
	end
	local hand = state.hands[seat]
	if not hand then
		return nil
	end
	if state.spoons[seat] then
		return nil
	end
	if hasFour(hand) or grabCount(state) > 0 then
		return { kind = "grab" }
	end
	if not canPass(state, seat) then
		return nil
	end
	if state.botLevel == "easy" and rng:NextNumber() < 0.35 then
		return { kind = "pass", card = hand[rng:NextInteger(1, #hand)] }
	end
	return { kind = "pass", card = worstCard(hand, rng, state.passNumber > Spoons.STALL_PASSES) }
end

return Spoons
