-- Speed: the two-player race card game (also called Spit). Both players play at once.
--
-- Setup (52 cards): each player gets a 5-card hand and a 15-card draw pile. Two side
-- piles of 5 sit face down, and two center piles start with one face-up card each.
-- Play: put a hand card on either center pile if it is one rank above or below the top
-- card (Ace and King connect, so K-A-2 works). Your hand refills to 5 from your draw
-- pile by itself. Nobody takes turns: whoever is faster plays.
-- Stuck: when neither player can play, after a short pause a new card flips from each
-- side pile onto the center piles. When the side piles are used up, the center piles
-- are shuffled into new side piles.
-- First to play every card in their hand and draw pile wins. A long stalemate ends the
-- game after FLIP_LIMIT flips: fewest cards left wins.
--
-- Moves: { kind = "play", card = id, pile = 1 | 2 }

local GameModule = require(script.Parent.Parent.GameModule)
local PlayingCards = require(script.Parent.Parent.Cards.PlayingCards)

local Speed = {}

Speed.id = "Speed"
Speed.minSeats = 2
Speed.maxSeats = 2

local HAND_SIZE = 5
local DRAW_SIZE = 15
local SIDE_SIZE = 5
Speed.FLIP_LIMIT = 40
Speed.STUCK_PAUSE = 1.5 -- seconds both players see "no moves" before the flip

local rank = PlayingCards.rank

local function fits(card: number, top: number): boolean
	local d = math.abs(rank(card) - rank(top))
	return d == 1 or d == 12
end
Speed.fits = fits

function Speed.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount == 2, "Speed is for 2 players")
	local random = rng or Random.new()
	local deck = PlayingCards.newDeck(random)
	local function take(n: number): { number }
		local out = {}
		for _ = 1, n do
			table.insert(out, table.remove(deck) :: number)
		end
		return out
	end
	local state = {
		rng = random,
		hands = { take(HAND_SIZE), take(HAND_SIZE) },
		draws = { take(DRAW_SIZE), take(DRAW_SIZE) },
		sides = { take(SIDE_SIZE), take(SIDE_SIZE) },
		centers = { take(1), take(1) }, -- centers[pile] top is the last card
		flips = 0,
		stuckId = 0, -- changes every time the game gets stuck (the flip timer's id)
		lastAction = nil,
		plays = { 0, 0 },
		winner = nil,
		reason = nil,
		botLevel = (options and options.botLevel) or "medium",
	}
	Speed._checkStuck(state)
	return state
end

local function top(state, pile: number): number
	local c = state.centers[pile]
	return c[#c]
end

local function canPlayAny(state, seat: number): boolean
	for _, card in state.hands[seat] do
		if fits(card, top(state, 1)) or fits(card, top(state, 2)) then
			return true
		end
	end
	return false
end

local function cardsLeft(state, seat: number): number
	return #state.hands[seat] + #state.draws[seat]
end

function Speed._checkStuck(state)
	if state.winner then
		state.stuck = false
		return
	end
	local wasStuck = state.stuck
	state.stuck = not canPlayAny(state, 1) and not canPlayAny(state, 2)
	if state.stuck and not wasStuck then
		state.stuckId += 1
	end
end

-- Flip one card from each side pile onto the center piles (rebuilding the side piles
-- from the center piles when they run out).
local function flip(state)
	if #state.sides[1] == 0 or #state.sides[2] == 0 then
		local pool = {}
		for pile = 1, 2 do
			for _, card in state.centers[pile] do
				table.insert(pool, card)
			end
			for _, card in state.sides[pile] do
				table.insert(pool, card)
			end
		end
		PlayingCards.shuffle(pool, state.rng)
		state.sides = { {}, {} }
		for i, card in pool do
			table.insert(state.sides[(i - 1) % 2 + 1], card)
		end
		state.centers = { {}, {} }
	end
	for pile = 1, 2 do
		local card = table.remove(state.sides[pile])
		if card then
			table.insert(state.centers[pile], card)
		end
	end
	state.flips += 1
	state.lastAction = { kind = "flip" }
	if state.flips >= Speed.FLIP_LIMIT then
		local a, b = cardsLeft(state, 1), cardsLeft(state, 2)
		state.winner = if a < b then 1 elseif b < a then 2 else 0
		state.reason = "Stalemate: fewest cards left"
	end
end

function Speed.getActiveSeats(state): { number }
	if state.winner or state.stuck then
		return {}
	end
	return { 1, 2 }
end

function Speed.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if state.winner or state.stuck or not state.hands[seat] then
		return moves
	end
	for _, card in state.hands[seat] do
		for pile = 1, 2 do
			if fits(card, top(state, pile)) then
				table.insert(moves, { kind = "play", card = card, pile = pile })
			end
		end
	end
	return moves
end

function Speed.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.winner then
		return false, "The game is over"
	end
	if state.stuck then
		return false, "Flipping new cards..."
	end
	if type(move) ~= "table" or move.kind ~= "play" then
		return false, "Bad move"
	end
	if not PlayingCards.isCardId(move.card) then
		return false, "Bad card"
	end
	if move.pile ~= 1 and move.pile ~= 2 then
		return false, "Pick a pile"
	end
	if not table.find(state.hands[seat], move.card) then
		return false, "That card isn't in your hand"
	end
	if not fits(move.card, top(state, move.pile)) then
		return false, "Too slow! That doesn't fit anymore"
	end
	return true
end

function Speed.applyMove(state, seat: number, move: any)
	local hand = state.hands[seat]
	table.remove(hand, table.find(hand, move.card) :: number)
	table.insert(state.centers[move.pile], move.card)
	local refill = table.remove(state.draws[seat])
	if refill then
		table.insert(hand, refill)
	end
	state.plays[seat] += 1
	state.lastAction = { kind = "play", seat = seat, card = move.card, pile = move.pile }
	if cardsLeft(state, seat) == 0 then
		state.winner = seat
		state.reason = "Played every card"
	end
	Speed._checkStuck(state)
end

function Speed.getTimer(state): { id: number, seconds: number }?
	if state.stuck and not state.winner then
		return { id = state.stuckId, seconds = Speed.STUCK_PAUSE }
	end
	return nil
end

function Speed.onTimeout(state)
	if not state.stuck then
		return
	end
	flip(state)
	state.stuck = false
	Speed._checkStuck(state)
end

function Speed.getResult(state): GameModule.Result?
	if state.winner == nil then
		return nil
	end
	if state.winner == 0 then
		return { winners = {}, isDraw = true, reason = state.reason }
	end
	return { winners = { state.winner }, isDraw = false, reason = state.reason }
end

function Speed.getView(state, seat: number?)
	local hand = if seat and state.hands[seat] then PlayingCards.sortHand(state.hands[seat]) else nil
	local playable = {}
	if hand and not state.stuck and not state.winner then
		for _, card in hand do
			local piles = {}
			for pile = 1, 2 do
				if fits(card, top(state, pile)) then
					table.insert(piles, pile)
				end
			end
			if #piles > 0 then
				playable[tostring(card)] = piles -- string keys survive remotes
			end
		end
	end
	return {
		hand = hand,
		playable = playable,
		tops = { top(state, 1), top(state, 2) },
		centerCounts = { #state.centers[1], #state.centers[2] },
		sideCounts = { #state.sides[1], #state.sides[2] },
		drawCounts = { #state.draws[1], #state.draws[2] },
		handCounts = { #state.hands[1], #state.hands[2] },
		stuck = state.stuck,
		flips = state.flips,
		lastAction = GameModule.copy(state.lastAction),
	}
end

function Speed.getSeatInfo(state): { [number]: string }
	return { `{cardsLeft(state, 1)} cards left`, `{cardsLeft(state, 2)} cards left` }
end

function Speed.getScores(state): { [number]: number }
	return { state.plays[1], state.plays[2] }
end

-- Bots ------------------------------------------------------------------------

local REACTION = { easy = { 1.8, 1.4 }, medium = { 1.15, 0.8 }, hard = { 0.7, 0.45 } }

function Speed.getBotDelay(state, _seat: number, rng: Random): number
	local r = REACTION[state.botLevel] or REACTION.medium
	return r[1] + rng:NextNumber() * r[2]
end

function Speed.chooseBotMove(state, seat: number, rng: Random): any?
	local moves = Speed.getLegalMoves(state, seat)
	if #moves == 0 then
		return nil
	end
	if state.botLevel ~= "hard" then
		return moves[rng:NextInteger(1, #moves)]
	end
	-- Hard: prefer a play that sets up another of our own cards next.
	local best, bestScore = moves[1], -1
	for _, move in moves do
		local score = rng:NextNumber() * 0.5
		for _, other in state.hands[seat] do
			if other ~= move.card and fits(other, move.card) then
				score += 1
			end
		end
		if score > bestScore then
			best, bestScore = move, score
		end
	end
	return best
end

-- Stats for the profile (see shared/StatsCatalog.luau).
function Speed.getMatchStats(state): { [number]: { [string]: number } }
	return { { cards = state.plays[1] }, { cards = state.plays[2] } }
end

return Speed
