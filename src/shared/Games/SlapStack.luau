-- Slap Stack (the slapping game known as Egyptian Ratscrew): win every card. 2-6 seats.
--
-- The deck is dealt out face down. Players take turns flipping their top card onto the
-- middle pile. A face card or Ace is a challenge: the next player has 1 try for a Jack,
-- 2 for a Queen, 3 for a King and 4 for an Ace to flip another face card or Ace. If they
-- do, the challenge passes on; if they run out of tries, the challenger takes the pile
-- (after a short moment where anyone can still slap).
-- Slaps: anyone may slap the pile any time the top two cards are the same rank (a double)
-- or the top and third cards are (a sandwich, a house rule that's on by default). The
-- first good slap takes the whole pile and flips next. A bad slap costs one card, put
-- face up under the pile.
-- A player with no cards is out. Last player with cards wins. After FLIP_LIMIT flips the
-- player with the most cards wins.
--
-- More slap house rules (off by default): topBottom (top card matches the bottom card),
-- marriage (a King and Queen together), tens (the top two cards add up to 10, Ace = 1).
--
-- Moves: { kind = "flip" } (your turn)  |  { kind = "slap" } (anyone with cards, any time)

local GameModule = require(script.Parent.Parent.GameModule)
local PlayingCards = require(script.Parent.Parent.Cards.PlayingCards)

local SlapStack = {}

SlapStack.id = "SlapStack"
SlapStack.minSeats = 2
SlapStack.maxSeats = 6

SlapStack.FLIP_LIMIT = 600
SlapStack.COLLECT_SECONDS = 1.2 -- the last chance to slap before a challenge is collected

local rank = PlayingCards.rank

-- Tries the next player gets for each face card (nil = not a face card).
local TRIES = { [1] = 4, [11] = 1, [12] = 2, [13] = 3 }
SlapStack.TRIES = TRIES

function SlapStack.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= 2 and seatCount <= 6, "Slap Stack needs 2-6 seats")
	local random = rng or Random.new()
	local deck = PlayingCards.newDeck(random)
	local piles = {}
	for seat = 1, seatCount do
		piles[seat] = {}
	end
	-- 52 doesn't always split evenly; the first seats get the extra cards.
	for i, id in deck do
		table.insert(piles[(i - 1) % seatCount + 1], id)
	end
	local rules = if options and type(options.rules) == "table" then options.rules else {}
	return {
		seatCount = seatCount,
		rng = random,
		piles = piles, -- piles[seat]: top card is the last one
		center = {}, -- the middle pile: top card is the last one
		turn = 1,
		challenge = nil, -- { owner, tries, face }: the current face-card challenge
		collect = nil, -- seat about to take the pile (a challenge was won)
		phaseId = 0,
		flips = 0,
		lastAction = nil,
		winners = nil,
		reason = nil,
		sandwich = rules.sandwich ~= false,
		topBottom = rules.topBottom == true,
		marriage = rules.marriage == true,
		tens = rules.tens == true,
		botLevel = (options and options.botLevel) or "medium",
	}
end

local function count(state, seat: number): number
	return #state.piles[seat]
end

local function nextWithCards(state, seat: number): number?
	for i = 1, state.seatCount do
		local s = (seat - 1 + i) % state.seatCount + 1
		if count(state, s) > 0 then
			return s
		end
	end
	return nil
end

-- Is there a good slap on the pile right now?
function SlapStack.canSlap(state): boolean
	local c = state.center
	local n = #c
	if n >= 2 and rank(c[n]) == rank(c[n - 1]) then
		return true
	end
	if state.sandwich and n >= 3 and rank(c[n]) == rank(c[n - 2]) then
		return true
	end
	if state.topBottom and n >= 3 and rank(c[n]) == rank(c[1]) then
		return true
	end
	if n >= 2 then
		local a, b = rank(c[n]), rank(c[n - 1])
		if state.marriage and ((a == 12 and b == 13) or (a == 13 and b == 12)) then
			return true
		end
		if state.tens and a <= 10 and b <= 10 and a + b == 10 then
			return true
		end
	end
	return false
end

-- Still in the game: holds cards, or is about to win a challenge.
local function inGame(state, seat: number): boolean
	return count(state, seat) > 0 or state.collect == seat or (state.challenge ~= nil and state.challenge.owner == seat)
end

local function checkEnd(state)
	local alive = {}
	for seat = 1, state.seatCount do
		if inGame(state, seat) then
			table.insert(alive, seat)
		end
	end
	if #alive == 1 then
		-- Last one left takes whatever is in the middle.
		local seat = alive[1]
		for _, id in state.center do
			table.insert(state.piles[seat], 1, id)
		end
		state.center = {}
		state.collect = nil
		state.challenge = nil
		state.winners = alive
		state.reason = "Won every card"
	elseif #alive == 0 then
		state.winners = {}
		state.reason = "Nobody has cards"
	elseif state.flips >= SlapStack.FLIP_LIMIT then
		local best, top = {}, -1
		for seat = 1, state.seatCount do
			local n = count(state, seat)
			if n > top then
				best, top = { seat }, n
			elseif n == top then
				table.insert(best, seat)
			end
		end
		state.winners = best
		state.reason = "Most cards after a long game"
	end
end

-- `seat` takes the middle pile (it goes under their own pile) and flips next.
local function take(state, seat: number)
	for i = #state.center, 1, -1 do
		table.insert(state.piles[seat], 1, state.center[i])
	end
	state.center = {}
	state.challenge = nil
	state.collect = nil
	state.turn = seat
	state.phaseId += 1
end

function SlapStack.getActiveSeats(state): { number }
	if state.winners then
		return {}
	end
	local out = {}
	for seat = 1, state.seatCount do
		if count(state, seat) > 0 then
			table.insert(out, seat)
		end
	end
	return out
end

-- The moves worth making: a good slap, or a flip on your turn. (A bad slap is allowed
-- too, it just costs a card.)
function SlapStack.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if state.winners or count(state, seat) == 0 then
		return moves
	end
	if SlapStack.canSlap(state) then
		table.insert(moves, { kind = "slap" })
	end
	if seat == state.turn and not state.collect then
		table.insert(moves, { kind = "flip" })
	end
	return moves
end

function SlapStack.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.winners then
		return false, "The game is over"
	end
	if type(move) ~= "table" then
		return false, "Bad move"
	end
	if count(state, seat) == 0 then
		return false, "You're out of cards"
	end
	if move.kind == "flip" then
		if seat ~= state.turn then
			return false, "It's not your turn to flip"
		end
		if state.collect then
			return false, "The pile is being collected"
		end
		return true
	elseif move.kind == "slap" then
		if #state.center == 0 then
			return false, "Nothing to slap"
		end
		return true
	end
	return false, "Bad move"
end

function SlapStack.applyMove(state, seat: number, move: any)
	if move.kind == "slap" then
		if SlapStack.canSlap(state) then
			local n = #state.center
			state.lastAction = { kind = "slap", seat = seat, count = n }
			take(state, seat)
		else
			-- Bad slap: one card goes face up under the pile.
			local burned = table.remove(state.piles[seat]) :: number
			table.insert(state.center, 1, burned)
			state.lastAction = { kind = "badSlap", seat = seat, card = burned }
			if count(state, seat) == 0 and state.turn == seat and not state.collect then
				if state.challenge then
					-- Out of cards while answering a challenge: the challenger wins it.
					state.collect = state.challenge.owner
					state.challenge = nil
					state.phaseId += 1
				else
					state.turn = nextWithCards(state, seat) or seat
				end
			end
		end
		checkEnd(state)
		return
	end

	-- Flip.
	local card = table.remove(state.piles[seat]) :: number
	table.insert(state.center, card)
	state.flips += 1
	state.lastAction = { kind = "flip", seat = seat, card = card }
	local tries = TRIES[rank(card)]
	if tries then
		state.challenge = { owner = seat, tries = tries, face = rank(card) }
		state.turn = nextWithCards(state, seat) or seat
	elseif state.challenge then
		state.challenge.tries -= 1
		if state.challenge.tries <= 0 or count(state, seat) == 0 then
			state.collect = state.challenge.owner
			state.challenge = nil
			state.phaseId += 1
		end
	else
		state.turn = nextWithCards(state, seat) or seat
	end
	checkEnd(state)
end

function SlapStack.getTimer(state): { id: number, seconds: number }?
	if state.collect and not state.winners then
		return { id = state.phaseId, seconds = SlapStack.COLLECT_SECONDS }
	end
	return nil
end

function SlapStack.onTimeout(state)
	if state.collect then
		local seat = state.collect
		state.lastAction = { kind = "collect", seat = seat, count = #state.center }
		take(state, seat)
		checkEnd(state)
	end
end

function SlapStack.getResult(state): GameModule.Result?
	if not state.winners then
		return nil
	end
	return { winners = table.clone(state.winners), isDraw = #state.winners ~= 1, reason = state.reason }
end

function SlapStack.getView(state, _seat: number?)
	local counts = {}
	for s = 1, state.seatCount do
		counts[s] = count(state, s)
	end
	local top = {}
	for i = math.max(1, #state.center - 2), #state.center do
		table.insert(top, state.center[i])
	end
	return {
		pileCounts = counts,
		top = top, -- up to the top 3 cards, newest last
		centerCount = #state.center,
		turn = state.turn,
		challenge = GameModule.copy(state.challenge),
		collect = state.collect,
		sandwich = state.sandwich,
		topBottom = state.topBottom,
		marriage = state.marriage,
		tens = state.tens,
		lastAction = GameModule.copy(state.lastAction),
		flips = state.flips,
	}
end

function SlapStack.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		local n = count(state, seat)
		info[seat] = if n == 0 then "Out" else `{n} cards`
	end
	return info
end

function SlapStack.getScores(state): { [number]: number }
	local scores = {}
	for seat = 1, state.seatCount do
		scores[seat] = count(state, seat)
	end
	return scores
end

-- Bots ------------------------------------------------------------------------

local REACTION = { easy = { 1.3, 0.9 }, medium = { 0.75, 0.5 }, hard = { 0.42, 0.35 } }

function SlapStack.getBotDelay(state, seat: number, rng: Random): number
	if SlapStack.canSlap(state) then
		local r = REACTION[state.botLevel] or REACTION.medium
		return r[1] + rng:NextNumber() * r[2]
	end
	if seat == state.turn then
		return 0.7 + rng:NextNumber() * 0.5
	end
	return 0.4
end

function SlapStack.chooseBotMove(state, seat: number, _rng: Random): any?
	if state.winners or count(state, seat) == 0 then
		return nil
	end
	-- Bots are told apart by reaction time (getBotDelay), so a fast human beats them.
	if SlapStack.canSlap(state) then
		return { kind = "slap" }
	end
	if seat == state.turn and not state.collect then
		return { kind = "flip" }
	end
	return nil
end

return SlapStack
