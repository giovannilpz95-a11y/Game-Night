-- Spoons: pass cards fast, collect four of a kind, grab a spoon. 3-8 seats.
--
-- There is one spoon fewer than players. Everyone holds 4 cards. Each "pass", every
-- player gets one new card (the dealer from the deck, everyone else from the player on
-- their right) and picks one of their 5 cards to pass left. The last player's pass goes
-- to the discard pile. All players pass at once; the next pass starts when everyone has
-- passed (or the pass clock runs out and a card is passed for the slow players).
-- Four of a kind? Grab a spoon! The moment the first spoon goes, everyone can grab one.
-- Whoever is left without a spoon is out. Fresh deal, one spoon fewer, until one player
-- is left: they win.
--
-- The deck uses as many ranks as players + 2 (4 cards each), so sets come together at
-- a good pace with any table size.
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
	state.spoons = {} -- spoons[seat] = order they grabbed it in
	state.spoonsLeft = #alive - 1
	state.phase = "pass"
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
	}
	local rules = if options and type(options.rules) == "table" then options.rules else {}
	if type(rules.passSeconds) == "number" and rules.passSeconds > 0 then
		state.passSeconds = rules.passSeconds
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
end

local function grabCount(state): number
	local n = 0
	for _ in state.spoons do
		n += 1
	end
	return n
end

local function endRound(state)
	local loser = nil
	for _, seat in aliveSeats(state) do
		if not state.spoons[seat] then
			loser = seat
		end
	end
	state.lastOut = loser
	if loser then
		state.out[loser] = state.round
	end
	local alive = aliveSeats(state)
	if #alive <= 1 then
		state.winner = alive[1]
		state.phase = "done"
		return
	end
	state.phase = "reveal"
	state.phaseId += 1
end

local function grab(state, seat: number)
	local first = grabCount(state) == 0
	state.spoons[seat] = grabCount(state) + 1
	state.spoonsLeft -= 1
	if first then
		state.firstGrab = { seat = seat, rank = hasFour(state.hands[seat]) }
		state.phase = "scramble"
		state.phaseId += 1
	end
	if state.spoonsLeft <= 0 then
		endRound(state)
	end
end

function Spoons.getActiveSeats(state): { number }
	if state.winner or state.phase == "done" or state.phase == "reveal" then
		return {}
	end
	local out = {}
	for _, seat in aliveSeats(state) do
		if state.phase == "scramble" then
			if not state.spoons[seat] then
				table.insert(out, seat)
			end
		elseif not state.passed[seat] or hasFour(state.hands[seat]) then
			table.insert(out, seat)
		end
	end
	return out
end

function Spoons.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if not table.find(Spoons.getActiveSeats(state), seat) then
		return moves
	end
	if state.phase == "scramble" or hasFour(state.hands[seat]) then
		table.insert(moves, { kind = "grab" })
	end
	if state.phase == "pass" and not state.passed[seat] then
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
		if state.phase == "pass" and not hasFour(state.hands[seat]) then
			return false, "You need four of a kind first"
		end
		return true
	elseif move.kind == "pass" then
		if state.phase ~= "pass" then
			return false, "Grab a spoon!"
		end
		if state.passed[seat] then
			return false, "Waiting for the others"
		end
		if not PlayingCards.isCardId(move.card) or not table.find(state.hands[seat], move.card) then
			return false, "That card isn't in your hand"
		end
		return true
	end
	return false, "Bad move"
end

function Spoons.applyMove(state, seat: number, move: any)
	if move.kind == "grab" then
		grab(state, seat)
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

-- A sensible card to pass: one of the rank we hold fewest of.
local function worstCard(hand: { number }, rng: Random): number
	local counts = PlayingCards.rankCounts(hand)
	local best, bestScore = hand[1], math.huge
	for _, card in hand do
		local score = counts[rank(card)] + rng:NextNumber() * 0.5
		if score < bestScore then
			best, bestScore = card, score
		end
	end
	return best
end

function Spoons.getTimer(state): { id: number, seconds: number }?
	if state.winner or state.phase == "done" then
		return nil
	end
	local seconds = if state.phase == "pass" then (state.passSeconds or Spoons.PASS_SECONDS)
		elseif state.phase == "scramble" then Spoons.SCRAMBLE_SECONDS
		else Spoons.REVEAL_SECONDS
	return { id = state.phaseId, seconds = seconds }
end

function Spoons.onTimeout(state)
	if state.phase == "pass" then
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
		-- Out of time: the spoons left go to random players who hadn't grabbed one.
		local waiting = {}
		for _, seat in aliveSeats(state) do
			if not state.spoons[seat] then
				table.insert(waiting, seat)
			end
		end
		shuffle(waiting, state.rng)
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
		deal(state)
	end
end

function Spoons.getResult(state): GameModule.Result?
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
	if state.phase ~= "pass" and state.firstGrab then
		-- Everyone gets to see the winning set once the spoons are flying.
		revealHand = PlayingCards.sortHand(state.hands[state.firstGrab.seat])
	end
	return {
		phase = state.phase,
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
		firstGrab = GameModule.copy(state.firstGrab),
		revealHand = revealHand,
		lastOut = state.lastOut,
	}
end

function Spoons.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		if state.out[seat] then
			info[seat] = "Out"
		elseif state.spoons[seat] then
			info[seat] = "Got a spoon!"
		elseif state.phase == "pass" and state.passed[seat] then
			info[seat] = "Passed"
		else
			info[seat] = if seat == state.dealer then "Dealer" else "In"
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
	if hasFour(hand) then
		return { kind = "grab" }
	end
	if state.passed[seat] then
		return nil
	end
	if state.botLevel == "easy" and rng:NextNumber() < 0.35 then
		return { kind = "pass", card = hand[rng:NextInteger(1, #hand)] }
	end
	return { kind = "pass", card = worstCard(hand, rng) }
end

return Spoons
