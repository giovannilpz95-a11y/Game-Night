-- Speed: the two-player race card game (also called Spit). Both players play at once.
--
-- Setup (52 cards): each player gets a 5-card hand and a 15-card draw pile. Two side
-- piles of 5 sit face down, and two center piles start with one face-up card each.
-- Play: put a hand card on either center pile if it is one rank above or below the top
-- card (Ace and King connect, so K-A-2 works). Your hand refills to 5 from your draw
-- pile by itself. Nobody takes turns: whoever is faster plays.
-- Start: a 3-2-1 countdown, then both center cards flip at once (GO!).
-- Stuck: when neither player can play, after a short pause a new card flips from each
-- side pile onto the center piles. When the side piles are used up, each center pile is
-- shuffled into a new side pile on its own side.
-- First to play every card in their hand and draw pile wins the deal. A long stalemate ends
-- it after FLIP_LIMIT flips: fewest cards left wins.
-- House rule "Match to 25" (Pagat): the deal's winner scores 1 point per card the other
-- player has left (hand and draw pile); deals go on until someone reaches 25.
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
Speed.COUNTDOWN = 3 -- 3-2-1, then GO!
Speed.DEAL_PAUSE = 4 -- between deals in a match to 25

local rank = PlayingCards.rank

-- One rank up or down. House rules: wrap (Ace and King connect, default on) and
-- sameRank (a card of the same rank also fits).
local function fits(state, card: number, top: number): boolean
	local d = math.abs(rank(card) - rank(top))
	return d == 1 or (d == 12 and state.wrap ~= false) or (d == 0 and state.sameRank == true)
end
Speed.fits = fits

local function deal(state)
	local deck = PlayingCards.newDeck(state.rng)
	local function take(n: number): { number }
		local out = {}
		for _ = 1, n do
			table.insert(out, table.remove(deck) :: number)
		end
		return out
	end
	state.hands = { take(HAND_SIZE), take(HAND_SIZE) }
	state.draws = { take(DRAW_SIZE), take(DRAW_SIZE) }
	state.sides = { take(SIDE_SIZE), take(SIDE_SIZE) }
	state.centers = { take(1), take(1) } -- centers[pile] top is the last card
	state.flips = 0
	state.stuck = false
	state.countdown = true -- center cards stay face down until GO!
	state.dealOver = nil
	state.timerId += 1
end

function Speed.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount == 2, "Speed is for 2 players")
	local random = rng or Random.new()
	local rules = if options and type(options.rules) == "table" then options.rules else {}
	local state = {
		rng = random,
		wrap = rules.wrap ~= false,
		sameRank = rules.sameRank == true,
		target = if type(rules.target) == "number" and rules.target > 0 then rules.target else 0, -- 0 = one deal
		scores = { 0, 0 },
		dealNumber = 1,
		timerId = 0, -- changes for every countdown, stuck pause and deal break
		stuckId = 0,
		lastAction = nil,
		plays = { 0, 0 },
		winner = nil,
		reason = nil,
		botLevel = (options and options.botLevel) or "medium",
	}
	deal(state)
	return state
end

local function top(state, pile: number): number
	local c = state.centers[pile]
	return c[#c]
end

local function canPlayAny(state, seat: number): boolean
	for _, card in state.hands[seat] do
		if fits(state, card, top(state, 1)) or fits(state, card, top(state, 2)) then
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
		state.timerId += 1
	end
end

-- Flip one card from each side pile onto the center piles (rebuilding the side piles
-- from the center piles when they run out).
local function flip(state)
	-- Each center pile is shuffled into a new side pile on its own side (any side cards
	-- still there go back in with it), so both sides always have cards.
	if #state.sides[1] == 0 or #state.sides[2] == 0 then
		for pile = 1, 2 do
			local pool = table.clone(state.centers[pile])
			for _, card in state.sides[pile] do
				table.insert(pool, card)
			end
			PlayingCards.shuffle(pool, state.rng)
			state.sides[pile] = pool
			state.centers[pile] = {}
		end
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
		Speed._endDeal(state, if a < b then 1 elseif b < a then 2 else 0, "Stalemate: fewest cards left")
	end
end

-- A deal is over. One deal: that's the game. Match to 25: score it, and deal again unless
-- someone got there.
function Speed._endDeal(state, winner: number, reason: string)
	state.stuck = false
	if state.target <= 0 then
		state.winner = winner
		state.reason = reason
		return
	end
	local points = 0
	if winner ~= 0 then
		points = cardsLeft(state, 3 - winner)
		state.scores[winner] += points
	end
	state.lastAction = { kind = "deal", seat = winner, points = points }
	if state.scores[1] >= state.target or state.scores[2] >= state.target then
		local a, b = state.scores[1], state.scores[2]
		state.winner = if a > b then 1 elseif b > a then 2 else 0
		state.reason = `First to {state.target} points`
		return
	end
	state.dealOver = { winner = winner, points = points, reason = reason }
	state.timerId += 1
end

function Speed.getActiveSeats(state): { number }
	if state.winner or state.stuck or state.countdown or state.dealOver then
		return {}
	end
	return { 1, 2 }
end

function Speed.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if state.winner or state.stuck or state.countdown or state.dealOver or not state.hands[seat] then
		return moves
	end
	for _, card in state.hands[seat] do
		for pile = 1, 2 do
			if fits(state, card, top(state, pile)) then
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
	if state.countdown then
		return false, "Wait for GO!"
	end
	if state.dealOver then
		return false, "Next deal coming up"
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
	if not fits(state, move.card, top(state, move.pile)) then
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
		Speed._endDeal(state, seat, "Played every card")
		return
	end
	Speed._checkStuck(state)
end

function Speed.getTimer(state): { id: number, seconds: number }?
	if state.winner then
		return nil
	end
	if state.dealOver then
		return { id = state.timerId, seconds = Speed.DEAL_PAUSE }
	elseif state.countdown then
		return { id = state.timerId, seconds = Speed.COUNTDOWN }
	elseif state.stuck then
		return { id = state.timerId, seconds = Speed.STUCK_PAUSE }
	end
	return nil
end

function Speed.onTimeout(state)
	if state.winner then
		return
	end
	if state.dealOver then
		state.dealNumber += 1
		deal(state)
		state.lastAction = { kind = "newDeal" }
		return
	end
	if state.countdown then
		state.countdown = false
		state.lastAction = { kind = "go" }
		Speed._checkStuck(state)
		return
	end
	if not state.stuck then
		return
	end
	flip(state)
	state.stuck = false
	if state.dealOver or state.winner then
		return
	end
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
	if hand and not state.stuck and not state.winner and not state.countdown and not state.dealOver then
		for _, card in hand do
			local piles = {}
			for pile = 1, 2 do
				if fits(state, card, top(state, pile)) then
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
		tops = if state.countdown then {} else { top(state, 1), top(state, 2) }, -- face down until GO!
		centerCounts = { #state.centers[1], #state.centers[2] },
		sideCounts = { #state.sides[1], #state.sides[2] },
		drawCounts = { #state.draws[1], #state.draws[2] },
		handCounts = { #state.hands[1], #state.hands[2] },
		stuck = state.stuck,
		countdown = state.countdown,
		flips = state.flips,
		flipLimit = Speed.FLIP_LIMIT,
		lastAction = GameModule.copy(state.lastAction),
		target = state.target,
		scores = table.clone(state.scores),
		dealNumber = state.dealNumber,
		dealOver = GameModule.copy(state.dealOver),
		wrap = state.wrap,
		sameRank = state.sameRank,
	}
end

function Speed.getSeatInfo(state): { [number]: string }
	local info = { `{cardsLeft(state, 1)} cards left`, `{cardsLeft(state, 2)} cards left` }
	if state.target > 0 then
		for seat = 1, 2 do
			info[seat] = `{state.scores[seat]} pts · ` .. info[seat]
		end
	end
	return info
end

-- One deal: cards played. Match to 25: points.
function Speed.getScores(state): { [number]: number }
	if state.target > 0 then
		return { state.scores[1], state.scores[2] }
	end
	return { state.plays[1], state.plays[2] }
end

-- Bots ------------------------------------------------------------------------

local REACTION = { easy = { 1.8, 1.4 }, medium = { 1.15, 0.8 }, hard = { 0.7, 0.45 } }

function Speed.getBotDelay(state, seat: number, rng: Random): number
	local r = REACTION[state.botLevel] or REACTION.medium
	local delay = r[1] + rng:NextNumber() * r[2]
	-- A combo: right after its own play, a bot that sees the next card goes quicker.
	local a = state.lastAction
	if a and a.kind == "play" and a.seat == seat and state.botLevel ~= "easy" then
		delay *= 0.6
	end
	return delay
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
			if other ~= move.card and fits(state, other, move.card) then
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
