-- I Doubt It (the bluffing game also called Cheat): get rid of every card. 3-8 seats.
--
-- The whole deck is dealt out. Players take turns putting 1-4 cards face down on the
-- pile and saying they are the rank called for: Aces first, then 2s, 3s ... Kings, then
-- Aces again. You must play even if you hold none of that rank, so you bluff.
-- After each play everyone else gets a few seconds to shout "I doubt it!". The cards are
-- turned over: if any of them isn't the called rank, the player who bluffed picks up the
-- whole pile. If they were all honest, the doubter picks it up. Nobody doubts: play goes on.
-- The first player to empty their hand (and survive any doubt) wins. A very long game
-- ends after PLAY_LIMIT plays: fewest cards left wins.
--
-- Moves:
--   { kind = "play", cards = { id, ... } }  (your turn: 1-4 cards, claimed as the called rank)
--   { kind = "doubt" }                       (doubt phase, anyone but the player)
--   { kind = "pass" }                        (doubt phase: "I believe you")

local GameModule = require(script.Parent.Parent.GameModule)
local PlayingCards = require(script.Parent.Parent.Cards.PlayingCards)

local Cheat = {}

Cheat.id = "Cheat"
Cheat.minSeats = 3
Cheat.maxSeats = 8

Cheat.DOUBT_SECONDS = 5 -- house rule "doubtSeconds" can change it
Cheat.REVEAL_SECONDS = 2.5
Cheat.PLAY_LIMIT = 300
Cheat.MAX_CARDS = 4

local rank = PlayingCards.rank

function Cheat.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= 3 and seatCount <= 8, "I Doubt It needs 3-8 seats")
	local random = rng or Random.new()
	local deck = PlayingCards.newDeck(random)
	local hands = {}
	for seat = 1, seatCount do
		hands[seat] = {}
	end
	for i, id in deck do
		table.insert(hands[(i - 1) % seatCount + 1], id)
	end
	local rules = if options and type(options.rules) == "table" then options.rules else {}
	local state = {
		seatCount = seatCount,
		rng = random,
		hands = hands,
		pile = {}, -- face down, newest last
		called = 1, -- the rank the next play must claim (1 = Aces)
		turn = 1,
		phase = "play", -- "play" | "doubt" | "reveal"
		phaseId = 1,
		lastPlay = nil, -- { seat, count, rank }: public
		lastCards = nil, -- the real cards of the last play: hidden until doubted
		passed = {}, -- passed[seat] = true in the doubt phase
		reveal = nil, -- { seat, doubter, cards, honest, loser, count }
		plays = 0,
		winners = nil,
		reason = nil,
		doubtSeconds = if type(rules.doubtSeconds) == "number" and rules.doubtSeconds > 0 then rules.doubtSeconds else Cheat.DOUBT_SECONDS,
		botLevel = (options and options.botLevel) or "medium",
	}
	return state
end

local function nextSeat(state, seat: number): number
	return seat % state.seatCount + 1
end

local function fewestCards(state)
	local best, low = {}, math.huge
	for seat = 1, state.seatCount do
		local n = #state.hands[seat]
		if n < low then
			best, low = { seat }, n
		elseif n == low then
			table.insert(best, seat)
		end
	end
	state.winners = best
	state.reason = "Fewest cards left"
end

-- Play moves on to the next player, the next rank is called.
local function advance(state)
	local player = state.lastPlay.seat
	if #state.hands[player] == 0 then
		state.winners = { player }
		state.reason = "Got rid of every card"
		return
	end
	if state.plays >= Cheat.PLAY_LIMIT then
		fewestCards(state)
		return
	end
	state.called = state.called % 13 + 1
	state.turn = nextSeat(state, player)
	state.phase = "play"
	state.phaseId += 1
	state.passed = {}
	state.lastCards = nil
end

local function resolveDoubt(state, doubter: number)
	local player = state.lastPlay.seat
	local honest = true
	for _, id in state.lastCards do
		if rank(id) ~= state.lastPlay.rank then
			honest = false
		end
	end
	local loser = if honest then doubter else player
	local count = #state.pile
	for _, id in state.pile do
		table.insert(state.hands[loser], id)
	end
	state.pile = {}
	state.reveal = {
		seat = player,
		doubter = doubter,
		cards = table.clone(state.lastCards),
		honest = honest,
		loser = loser,
		count = count,
	}
	state.phase = "reveal"
	state.phaseId += 1
	-- An honest last play wins on the spot.
	if honest and #state.hands[player] == 0 then
		state.winners = { player }
		state.reason = "Got rid of every card"
	end
end

local function doubters(state): { number }
	local out = {}
	if state.phase ~= "doubt" then
		return out
	end
	for seat = 1, state.seatCount do
		if seat ~= state.lastPlay.seat and not state.passed[seat] then
			table.insert(out, seat)
		end
	end
	return out
end

function Cheat.getActiveSeats(state): { number }
	if state.winners then
		return {}
	end
	if state.phase == "play" then
		return { state.turn }
	end
	return doubters(state)
end

function Cheat.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if state.winners then
		return moves
	end
	if state.phase == "play" and seat == state.turn then
		local hand = state.hands[seat]
		local honest = {}
		for _, id in hand do
			table.insert(moves, { kind = "play", cards = { id } })
			if rank(id) == state.called then
				table.insert(honest, id)
			end
		end
		if #honest > 1 then
			table.insert(moves, { kind = "play", cards = honest })
		end
	elseif state.phase == "doubt" and table.find(doubters(state), seat) then
		table.insert(moves, { kind = "doubt" })
		table.insert(moves, { kind = "pass" })
	end
	return moves
end

function Cheat.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.winners then
		return false, "The game is over"
	end
	if type(move) ~= "table" then
		return false, "Bad move"
	end
	if move.kind == "play" then
		if state.phase ~= "play" or seat ~= state.turn then
			return false, "It's not your turn"
		end
		if not PlayingCards.isCardList(move.cards, Cheat.MAX_CARDS) then
			return false, "Play 1 to 4 cards"
		end
		if not PlayingCards.holdsAll(state.hands[seat], move.cards) then
			return false, "Those cards aren't in your hand"
		end
		return true
	elseif move.kind == "doubt" or move.kind == "pass" then
		if state.phase ~= "doubt" then
			return false, "Too late!"
		end
		if not table.find(doubters(state), seat) then
			return false, "You can't doubt this one"
		end
		return true
	end
	return false, "Bad move"
end

function Cheat.applyMove(state, seat: number, move: any)
	if move.kind == "play" then
		PlayingCards.removeCards(state.hands[seat], move.cards)
		for _, id in move.cards do
			table.insert(state.pile, id)
		end
		state.plays += 1
		state.lastPlay = { seat = seat, count = #move.cards, rank = state.called }
		state.lastCards = table.clone(move.cards)
		state.reveal = nil
		state.passed = {}
		state.phase = "doubt"
		state.phaseId += 1
	elseif move.kind == "doubt" then
		resolveDoubt(state, seat)
	elseif move.kind == "pass" then
		state.passed[seat] = true
		if #doubters(state) == 0 then
			advance(state)
		end
	end
end

function Cheat.getTimer(state): { id: number, seconds: number }?
	if state.winners then
		return nil
	end
	if state.phase == "doubt" then
		return { id = state.phaseId, seconds = state.doubtSeconds }
	elseif state.phase == "reveal" then
		return { id = state.phaseId, seconds = Cheat.REVEAL_SECONDS }
	end
	return nil
end

function Cheat.onTimeout(state)
	if state.phase == "doubt" or state.phase == "reveal" then
		advance(state)
	end
end

function Cheat.getResult(state): GameModule.Result?
	if not state.winners then
		return nil
	end
	return { winners = table.clone(state.winners), isDraw = #state.winners > 1, reason = state.reason }
end

function Cheat.getView(state, seat: number?)
	local counts = {}
	for s = 1, state.seatCount do
		counts[s] = #state.hands[s]
	end
	local passed = {}
	for s in state.passed do
		passed[tostring(s)] = true
	end
	return {
		hand = if seat and state.hands[seat] then PlayingCards.sortHand(state.hands[seat]) else nil,
		handCounts = counts,
		pileCount = #state.pile,
		called = state.called,
		turn = state.turn,
		phase = state.phase,
		lastPlay = GameModule.copy(state.lastPlay),
		reveal = GameModule.copy(state.reveal),
		passed = passed,
		doubtSeconds = state.doubtSeconds,
	}
end

function Cheat.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		local n = #state.hands[seat]
		info[seat] = `{n} {if n == 1 then "card" else "cards"}`
	end
	return info
end

function Cheat.getScores(state): { [number]: number }
	local scores = {}
	for seat = 1, state.seatCount do
		scores[seat] = -#state.hands[seat]
	end
	return scores
end

-- Bots ------------------------------------------------------------------------

function Cheat.getBotDelay(state, _seat: number, rng: Random): number
	if state.phase == "doubt" then
		return 0.8 + rng:NextNumber() * 1.6
	end
	return 1 + rng:NextNumber() * 0.8
end

-- How many plays until `r` is called again (0 = it's called now).
local function distance(state, r: number): number
	return (r - state.called) % 13
end

local function chooseBluff(state, hand: { number }, rng: Random): number
	if state.botLevel == "easy" then
		return hand[rng:NextInteger(1, #hand)]
	end
	-- Throw away the card we'll need last.
	local best, far = hand[1], -1
	for _, id in hand do
		local d = distance(state, rank(id)) + rng:NextNumber() * 0.5
		if d > far then
			best, far = id, d
		end
	end
	return best
end

function Cheat.chooseBotMove(state, seat: number, rng: Random): any?
	if state.winners then
		return nil
	end
	if state.phase == "play" then
		if seat ~= state.turn then
			return nil
		end
		local hand = state.hands[seat]
		local honest = {}
		for _, id in hand do
			if rank(id) == state.called then
				table.insert(honest, id)
			end
		end
		if #honest > 0 then
			local cards = table.clone(honest)
			-- Sometimes slip in one extra card with the honest ones.
			local sneak = if state.botLevel == "hard" then 0.3 elseif state.botLevel == "medium" then 0.15 else 0
			if #cards < Cheat.MAX_CARDS and #hand > #cards and rng:NextNumber() < sneak then
				local others = {}
				for _, id in hand do
					if rank(id) ~= state.called then
						table.insert(others, id)
					end
				end
				table.insert(cards, chooseBluff(state, others, rng))
			end
			return { kind = "play", cards = cards }
		end
		local first = chooseBluff(state, hand, rng)
		local cards = { first }
		if #hand > 2 and state.botLevel ~= "easy" and rng:NextNumber() < 0.25 then
			local rest = table.clone(hand)
			table.remove(rest, table.find(rest, first) :: number)
			table.insert(cards, chooseBluff(state, rest, rng))
		end
		return { kind = "play", cards = cards }
	end
	if state.phase == "doubt" then
		if not table.find(doubters(state), seat) then
			return nil
		end
		local claim = state.lastPlay
		local held = 0
		for _, id in state.hands[seat] do
			if rank(id) == claim.rank then
				held += 1
			end
		end
		-- Can't be true: we hold too many of that rank.
		if held + claim.count > 4 then
			return { kind = if state.botLevel == "easy" and rng:NextNumber() < 0.4 then "pass" else "doubt" }
		end
		local chance
		if state.botLevel == "easy" then
			chance = 0.12
		else
			chance = 0.05 + claim.count * 0.07 + held * 0.08
			if #state.hands[claim.seat] == 0 then
				chance = 0.9 -- they're about to win
			elseif #state.pile > 10 then
				chance *= if state.botLevel == "hard" then 0.5 else 0.8
			end
		end
		return { kind = if rng:NextNumber() < chance then "doubt" else "pass" }
	end
	return nil
end

return Cheat
