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
		pileFrom = {}, -- pileFrom[i] = who put pile[i] down (bots remember their own cards)
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
	state.pileFrom = {}
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
		state.pileFrom = state.pileFrom or {}
		for _, id in move.cards do
			table.insert(state.pile, id)
			state.pileFrom[#state.pile] = seat
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

-- How many of our own turns until we're asked for `r` (0 = it's called now). We play
-- every seatCount plays, so with 5 seats we're asked for every 5th rank, not the next one.
local function distance(state, r: number): number
	local wanted = state.called
	for k = 0, 12 do
		if wanted == r then
			return k
		end
		wanted = (wanted - 1 + state.seatCount) % 13 + 1
	end
	return 13
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

local function choose(n: number, k: number): number
	if k < 0 or k > n then
		return 0
	end
	local out = 1
	for i = 1, k do
		out = out * (n - k + i) / i
	end
	return out
end

-- Rough odds that a player with no card of the called rank bluffs with n cards, and
-- that a player slips one extra card in with honest ones. (Bots play like this; people
-- mostly do too.)
local BLUFF_SIZE = { 0.85, 0.2, 0.05, 0.03 }
local SNEAK = 0.15

-- Chance the last play was honest, from what this seat knows: its own hand and (hard
-- bots only) the cards it put on the pile itself. Players lay down every card of the
-- called rank they hold, so a claim of `count` is honest when they held exactly that
-- many of the ranks we can't see, and a lie when they held none (a bluff) or one fewer
-- (an extra card slipped in).
function Cheat.honestChance(state, seat: number): number
	local claim = state.lastPlay
	local known = 0
	local seen = #state.hands[seat]
	for _, id in state.hands[seat] do
		if rank(id) == claim.rank then
			known += 1
		end
	end
	if state.botLevel == "hard" and state.pileFrom then
		for i, id in state.pile do
			if state.pileFrom[i] == seat then
				seen += 1
				if rank(id) == claim.rank then
					known += 1
				end
			end
		end
	end
	local count = claim.count
	if known + count > 4 then
		return 0
	end
	local left = 4 - known -- of that rank, somewhere we can't see
	local unseen = math.max(1, 52 - seen)
	local had = math.min(unseen, #state.hands[claim.seat] + count) -- their hand before the play
	local total = choose(unseen, had)
	if total <= 0 then
		return 0.5
	end
	local function held(x: number): number -- P(they held exactly x of that rank)
		return choose(left, x) * choose(unseen - left, had - x) / total
	end
	local honest = held(count)
	local lie = BLUFF_SIZE[count] * held(0) + (if count >= 2 then SNEAK * held(count - 1) else 0)
	if honest + lie <= 0 then
		return 0.5
	end
	return honest / (honest + lie)
end

local function shouldDoubt(state, seat: number, rng: Random): boolean
	local claim = state.lastPlay
	local level = state.botLevel
	-- Their last cards: if it's true they win anyway, so doubting costs nothing.
	if #state.hands[claim.seat] == 0 then
		return level ~= "easy" or rng:NextNumber() < 0.6
	end
	local honest = Cheat.honestChance(state, seat)
	if honest <= 0 then
		return level ~= "easy" or rng:NextNumber() < 0.6
	end
	if level == "easy" then
		return rng:NextNumber() < 0.12
	end
	-- Short of a sure thing, a doubt is close to a coin flip (simulations put lies at
	-- about 40% whatever the odds look like), and being wrong means taking the pile while
	-- being right only hurts one rival. So smart bots doubt only when it's cheap or when
	-- the player is about to win.
	local lie = 1 - honest
	local left = #state.hands[claim.seat]
	-- At a big table hands are small, so "nearly out" means less (and a rival will
	-- probably doubt anyway).
	if left <= (if state.seatCount >= 6 then 1 else 2) and #state.pile <= 8 then
		return lie >= (if level == "hard" then 0.3 else 0.4)
	end
	-- A small pile is cheap to take, but catching one rival is worth less the more
	-- rivals there are.
	if #state.pile <= 2 and state.seatCount <= 4 then
		return lie >= 0.6 and (level == "hard" or rng:NextNumber() < 0.5)
	end
	return false
end

function Cheat.chooseBotMove(state, seat: number, rng: Random): any?
	if state.winners then
		return nil
	end
	local level = state.botLevel
	if state.phase == "play" then
		if seat ~= state.turn then
			return nil
		end
		local hand = state.hands[seat]
		local honest, others = {}, {}
		for _, id in hand do
			if rank(id) == state.called then
				table.insert(honest, id)
			else
				table.insert(others, id)
			end
		end
		-- Getting caught costs the whole pile, so smart bots only take risks while it's small.
		-- Each extra rival is another chance to be doubted, so bluff less at a big table.
		local smallPile = #state.pile <= (if state.seatCount <= 4 then 2 else 0)
		if #honest > 0 then
			local cards = table.clone(honest)
			-- Sometimes slip in one extra card with the honest ones.
			local sneak = if level == "hard" then 0.3 elseif level == "medium" then 0.15 else 0
			if #cards < Cheat.MAX_CARDS and #others > 0 and smallPile and rng:NextNumber() < sneak then
				table.insert(cards, chooseBluff(state, others, rng))
			end
			return { kind = "play", cards = cards }
		end
		local first = chooseBluff(state, hand, rng)
		local cards = { first }
		if #hand > 2 and level ~= "easy" and smallPile and rng:NextNumber() < 0.25 then
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
		return { kind = if shouldDoubt(state, seat, rng) then "doubt" else "pass" }
	end
	return nil
end

return Cheat
