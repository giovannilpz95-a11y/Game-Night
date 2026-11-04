-- Oh Hell: bid exactly how many tricks you'll take, then take exactly that many. 3-7 seats.
--
-- The hand size changes every round: 7 cards, then 6, down to 1 (house rule "rounds":
-- 5 down to 1, 7 down to 1, or 1 up to 7 and back down). Fewer seats can't go above 51
-- cards dealt. After the deal the next card is turned up: its suit is trump.
-- Bids go round from the dealer's left, 0 up to the hand size. The dealer bids last and
-- may not bid the number that makes the bids add up to the hand size (so someone always
-- misses). Left of the dealer leads; follow suit if you can, trump beats other suits.
-- Make your bid exactly for 10 + your bid; miss it by any amount and score nothing.
-- Highest score after the last round wins.
--
-- Moves: { kind = "bid", bid = 0..hand size }  (bid phase, in turn)
--        { kind = "play", card = id }          (your turn)

local GameModule = require(script.Parent.Parent.GameModule)
local PlayingCards = require(script.Parent.Parent.Cards.PlayingCards)
local Tricks = require(script.Parent.Parent.Cards.Tricks)

local OhHell = {}

OhHell.id = "OhHell"
OhHell.minSeats = 3
OhHell.maxSeats = 7

OhHell.TRICK_SECONDS = 1.4
OhHell.ROUND_SECONDS = 6
OhHell.EXACT_BONUS = 10

local suit = PlayingCards.suit
local power = PlayingCards.aceHigh

-- The hand size of every round for a schedule and seat count.
function OhHell.schedule(kind: string?, seatCount: number): { number }
	local cap = math.floor(51 / seatCount)
	local top = math.min(if kind == "short" then 5 else 7, cap)
	local out = {}
	if kind == "updown" then
		for n = 1, top do
			table.insert(out, n)
		end
		for n = top - 1, 1, -1 do
			table.insert(out, n)
		end
	else
		for n = top, 1, -1 do
			table.insert(out, n)
		end
	end
	return out
end

local function deal(state)
	state.round += 1
	local size = state.schedule[state.round]
	local deck = PlayingCards.newDeck(state.rng)
	for seat = 1, state.seatCount do
		state.hands[seat] = {}
		state.tricks[seat] = 0
		for _ = 1, size do
			table.insert(state.hands[seat], table.remove(deck) :: number)
		end
	end
	state.trumpCard = table.remove(deck) :: number
	state.trump = suit(state.trumpCard)
	state.handSize = size
	state.dealer = state.dealer % state.seatCount + 1
	state.bids = {}
	state.trick = {}
	state.lastTrick = nil
	state.tricksPlayed = 0
	state.turn = state.dealer % state.seatCount + 1
	state.phase = "bid"
	state.phaseId += 1
end

function OhHell.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= 3 and seatCount <= 7, "Oh Hell needs 3-7 seats")
	local rules = if options and type(options.rules) == "table" then options.rules else {}
	local kind = if rules.rounds == "short" or rules.rounds == "updown" then rules.rounds else "classic"
	local scores = {}
	for seat = 1, seatCount do
		scores[seat] = 0
	end
	local state = {
		seatCount = seatCount,
		rng = rng or Random.new(),
		schedule = OhHell.schedule(kind, seatCount),
		hands = {},
		tricks = {},
		bids = {},
		scores = scores,
		made = table.clone(scores), -- rounds where the bid was hit
		round = 0,
		handSize = 0,
		dealer = seatCount, -- seat 1 deals first after the bump in deal()
		trick = {},
		lastTrick = nil,
		tricksPlayed = 0,
		trump = 1,
		trumpCard = 1,
		roundSummary = nil,
		turn = 1,
		phase = "bid", -- "bid" | "play" | "trick" | "round" | "done"
		phaseId = 0,
		over = false,
		botLevel = (options and options.botLevel) or "medium",
	}
	deal(state)
	return state
end

-- The bid the dealer may not make (nil for everyone else, or when it can't add up).
function OhHell.forbiddenBid(state, seat: number): number?
	if seat ~= state.dealer then
		return nil
	end
	local sum = 0
	for _, b in state.bids do
		sum += b
	end
	local banned = state.handSize - sum
	return if banned >= 0 then banned else nil
end

function OhHell.playable(state, seat: number): { number }
	return Tricks.followable(state.hands[seat], state.trick)
end

function OhHell.getActiveSeats(state): { number }
	if state.over or (state.phase ~= "bid" and state.phase ~= "play") then
		return {}
	end
	return { state.turn }
end

function OhHell.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if state.over or seat ~= state.turn then
		return moves
	end
	if state.phase == "bid" then
		local banned = OhHell.forbiddenBid(state, seat)
		for bid = 0, state.handSize do
			if bid ~= banned then
				table.insert(moves, { kind = "bid", bid = bid })
			end
		end
	elseif state.phase == "play" then
		for _, id in OhHell.playable(state, seat) do
			table.insert(moves, { kind = "play", card = id })
		end
	end
	return moves
end

function OhHell.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.over then
		return false, "The game is over"
	end
	if type(move) ~= "table" then
		return false, "Bad move"
	end
	if seat ~= state.turn then
		return false, "It's not your turn"
	end
	if move.kind == "bid" then
		if state.phase ~= "bid" then
			return false, "Bidding is over"
		end
		local bid = move.bid
		if type(bid) ~= "number" or bid ~= bid or bid % 1 ~= 0 or bid < 0 or bid > state.handSize then
			return false, `Bid 0 to {state.handSize}`
		end
		if bid == OhHell.forbiddenBid(state, seat) then
			return false, `The dealer can't bid {bid}: the bids would add up to {state.handSize}`
		end
		return true
	elseif move.kind == "play" then
		if state.phase ~= "play" then
			return false, "Not yet"
		end
		if not PlayingCards.isCardId(move.card) or not table.find(state.hands[seat], move.card) then
			return false, "That card isn't in your hand"
		end
		if not table.find(OhHell.playable(state, seat), move.card) then
			return false, "Follow suit"
		end
		return true
	end
	return false, "Bad move"
end

local function endRound(state)
	local summary = {}
	for seat = 1, state.seatCount do
		local bid, took = state.bids[seat], state.tricks[seat]
		local points = if bid == took then OhHell.EXACT_BONUS + bid else 0
		state.scores[seat] += points
		if bid == took then
			state.made[seat] += 1
		end
		summary[tostring(seat)] = { bid = bid, took = took, points = points }
	end
	state.roundSummary = summary
	if state.round >= #state.schedule then
		state.over = true
		state.phase = "done"
	else
		state.phase = "round"
	end
	state.phaseId += 1
end

function OhHell.applyMove(state, seat: number, move: any)
	local n = state.seatCount
	if move.kind == "bid" then
		state.bids[seat] = move.bid
		if seat == state.dealer then
			state.phase = "play"
			state.turn = state.dealer % n + 1
			state.phaseId += 1
		else
			state.turn = seat % n + 1
		end
		return
	end
	local hand = state.hands[seat]
	table.remove(hand, table.find(hand, move.card) :: number)
	table.insert(state.trick, { seat = seat, card = move.card })
	if #state.trick < n then
		state.turn = seat % n + 1
		return
	end
	local winner = state.trick[Tricks.winningIndex(state.trick, state.trump)].seat
	state.tricks[winner] += 1
	state.lastTrick = { plays = Tricks.copy(state.trick), winner = winner }
	state.tricksPlayed += 1
	state.turn = winner
	state.phase = "trick"
	state.phaseId += 1
end

function OhHell.getTimer(state): { id: number, seconds: number }?
	if state.over then
		return nil
	end
	if state.phase == "trick" then
		return { id = state.phaseId, seconds = OhHell.TRICK_SECONDS }
	elseif state.phase == "round" then
		return { id = state.phaseId, seconds = OhHell.ROUND_SECONDS }
	end
	return nil
end

function OhHell.onTimeout(state)
	if state.phase == "trick" then
		state.trick = {}
		if state.tricksPlayed >= state.handSize then
			endRound(state)
		else
			state.phase = "play"
			state.phaseId += 1
		end
	elseif state.phase == "round" then
		deal(state)
	end
end

function OhHell.getResult(state): GameModule.Result?
	if not state.over then
		return nil
	end
	local best, winners = -1, {}
	for seat = 1, state.seatCount do
		local s = state.scores[seat]
		if s > best then
			best, winners = s, { seat }
		elseif s == best then
			table.insert(winners, seat)
		end
	end
	return { winners = winners, isDraw = #winners > 1, reason = if #winners > 1 then `Tied at {best}` else `Highest score ({best})` }
end

function OhHell.getView(state, seat: number?)
	local counts, bids = {}, {}
	for s = 1, state.seatCount do
		counts[s] = #state.hands[s]
		if state.bids[s] ~= nil then
			bids[tostring(s)] = state.bids[s]
		end
	end
	local yourTurn = seat ~= nil and seat == state.turn and not state.over
	return {
		hand = if seat and state.hands[seat] then PlayingCards.sortBySuit(state.hands[seat], power) else nil,
		playable = if yourTurn and state.phase == "play" then OhHell.playable(state, seat :: number) else {},
		forbidden = if yourTurn and state.phase == "bid" then OhHell.forbiddenBid(state, seat :: number) else nil,
		handCounts = counts,
		bids = bids,
		tricks = table.clone(state.tricks),
		trick = Tricks.copy(state.trick),
		lastTrick = GameModule.copy(state.lastTrick),
		scores = table.clone(state.scores),
		roundSummary = GameModule.copy(state.roundSummary),
		round = state.round,
		rounds = #state.schedule,
		handSize = state.handSize,
		nextHandSize = state.schedule[state.round + 1],
		trump = state.trump,
		trumpCard = state.trumpCard,
		dealer = state.dealer,
		turn = state.turn,
		phase = state.phase,
	}
end

function OhHell.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		local bid = state.bids[seat]
		info[seat] = `{state.scores[seat]} pts · {if bid == nil then "bidding" else `bid {bid}`} · {state.tricks[seat]} won`
	end
	return info
end

function OhHell.getScores(state): { [number]: number }
	return table.clone(state.scores)
end

-- Stats for the profile (see shared/StatsCatalog.luau).
function OhHell.getMatchStats(state): { [number]: { [string]: number } }
	local out = {}
	for seat = 1, state.seatCount do
		out[seat] = { exact = state.made[seat] }
	end
	return out
end

-- Bots ------------------------------------------------------------------------

-- A rough count of the tricks a hand will take with this trump and this many players.
function OhHell.estimate(hand: { number }, trump: number, seatCount: number): number
	local bySuit = { {}, {}, {}, {} }
	for _, id in hand do
		table.insert(bySuit[suit(id)], power(id))
	end
	local crowd = (seatCount - 3) * 0.08 -- more players, more chance a high card gets beaten
	local est = 0
	for s = 1, 4 do
		local n = #bySuit[s]
		for _, p in bySuit[s] do
			if s == trump then
				if p >= 13 then
					est += 1
				elseif p >= 11 then
					est += 0.55 - crowd
				elseif n >= 3 then
					est += 0.3
				end
			elseif p == 14 then
				est += 0.85 - crowd
			elseif p == 13 and n >= 2 then
				est += 0.45 - crowd
			end
		end
	end
	return math.max(0, est)
end

local function chooseBid(state, seat: number, rng: Random): number
	local est = OhHell.estimate(state.hands[seat], state.trump, state.seatCount)
	if state.botLevel == "easy" then
		est += rng:NextNumber() * 1.6 - 0.8
	end
	local bid = math.clamp(math.floor(est + 0.5), 0, state.handSize)
	local banned = OhHell.forbiddenBid(state, seat)
	if bid == banned then
		-- Hooked: go the way the estimate leans.
		if (est >= bid and bid < state.handSize) or bid == 0 then
			bid += 1
		else
			bid -= 1
		end
	end
	return bid
end

local function choosePlay(state, seat: number, rng: Random): number
	local cards = OhHell.playable(state, seat)
	if state.botLevel == "easy" or #cards == 1 then
		return cards[rng:NextInteger(1, #cards)]
	end
	local trump = state.trump
	local need = state.bids[seat] - state.tricks[seat]
	local trick = state.trick
	-- Hard bots count trumps as worth more than their face value.
	local function cost(id: number): number
		return power(id) + (if suit(id) == trump then 20 else 0)
	end
	local function cheapest(list: { number }): number
		local best = list[1]
		for _, id in list do
			if cost(id) < cost(best) then
				best = id
			end
		end
		return best
	end
	local function dearest(list: { number }): number
		local best = list[1]
		for _, id in list do
			if cost(id) > cost(best) then
				best = id
			end
		end
		return best
	end
	if #trick == 0 then
		-- Leading: want tricks, lead strength; don't, lead low.
		return if need > 0 then dearest(cards) else cheapest(cards)
	end
	local winners, losers = {}, {}
	for _, id in cards do
		if Tricks.wouldWin(trick, id, trump) then
			table.insert(winners, id)
		else
			table.insert(losers, id)
		end
	end
	if need > 0 then
		if #winners > 0 then
			-- Hard bots with players still to come win high, so the trick can't be taken
			-- back; otherwise win as cheaply as possible.
			if state.botLevel == "hard" and #trick < state.seatCount - 1 then
				return dearest(winners)
			end
			return cheapest(winners)
		end
		return cheapest(losers)
	end
	-- Bid made: stay under. Throw the biggest card that still loses.
	if #losers > 0 then
		return dearest(losers)
	end
	return cheapest(winners)
end

function OhHell.chooseBotMove(state, seat: number, rng: Random): any?
	if state.over or seat ~= state.turn then
		return nil
	end
	if state.phase == "bid" then
		return { kind = "bid", bid = chooseBid(state, seat, rng) }
	elseif state.phase == "play" then
		return { kind = "play", card = choosePlay(state, seat, rng) }
	end
	return nil
end

return OhHell
