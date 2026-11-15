-- Oh Hell: bid exactly how many tricks you'll take, then take exactly that many. 3-7 seats.
--
-- The hand size changes every round (house rule "rounds": 1 up to 7 and back down by
-- default; 5 down to 1; 7 down to 1; or the full game, Pagat's 10 down to 1 and back up,
-- starting at 10 cards for 3-5 players, 8 for 6, 7 for 7). Fewer seats can't go above
-- 51 cards dealt. After the deal the next card is turned up: its suit is trump.
-- The first dealer is picked at random, then it moves left.
-- Bids go round from the dealer's left, 0 up to the hand size. The dealer bids last and
-- may not bid the number that makes the bids add up to the hand size (so someone always
-- misses). Left of the dealer leads; follow suit if you can, trump beats other suits.
-- Scoring: every trick scores 1 and an exact bid adds 10 (cardgames.io, Trickster).
-- Highest score after the last round wins; tied, one more hand at the top size is played
-- (Pagat), up to 3 times.
--
-- House rules (options.rules): hook (default on: the dealer's banned bid above),
-- scoring ("tricks" as above; "exact": only an exact bid scores, 10 + the bid), miss
-- ("zero": a missed bid scores nothing extra; "minus5": a missed bid scores -5 per trick
-- off instead), noTrumpTop (no trump on the biggest hand), trumpBroken (trump can't be
-- led until one has been played, unless you hold only trumps).
--
-- Moves: { kind = "bid", bid = 0..hand size }  (bid phase, in turn)
--        { kind = "play", card = id }          (your turn)

local GameModule = require(script.Parent.Parent.GameModule)
local BotThink = require(script.Parent.Parent.BotThink)
local PlayingCards = require(script.Parent.Parent.Cards.PlayingCards)
local Tricks = require(script.Parent.Parent.Cards.Tricks)

local OhHell = {}

OhHell.id = "OhHell"
OhHell.minSeats = 3
OhHell.maxSeats = 7

OhHell.TRICK_SECONDS = 1.4
OhHell.ROUND_SECONDS = 6
OhHell.EXACT_BONUS = 10
OhHell.MAX_TIE_HANDS = 3

local suit = PlayingCards.suit
local power = PlayingCards.aceHigh

-- The hand size of every round for a schedule and seat count.
function OhHell.schedule(kind: string?, seatCount: number): { number }
	local cap = math.floor(51 / seatCount)
	local top = math.min(if kind == "short" then 5 else 7, cap)
	local out = {}
	if kind == "full" then
		-- Pagat: 10 cards with 3-5 players, 8 with 6, 7 with 7; down to 1 and back up.
		top = math.min(cap, if seatCount <= 5 then 10 elseif seatCount == 6 then 8 else 7)
		for n = top, 1, -1 do
			table.insert(out, n)
		end
		for n = 2, top do
			table.insert(out, n)
		end
		return out
	end
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
	-- House rule: the biggest hand of the game is played without trump.
	if state.noTrumpTop and size == state.topSize then
		state.trump = nil
	end
	state.trumpBrokenNow = false
	state.played = {}
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
	local kind = if rules.rounds == "short" or rules.rounds == "classic" or rules.rounds == "full" then rules.rounds else "updown"
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
		dealer = (rng or Random.new()):NextInteger(1, seatCount), -- deal() moves it on one
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
		hook = rules.hook ~= false,
		everyTrick = rules.scoring ~= "exact",
		missPenalty = rules.miss == "minus5",
		noTrumpTop = rules.noTrumpTop == true,
		trumpMustBreak = rules.trumpBroken == true,
		trumpBrokenNow = false,
		history = {}, -- one row per finished hand: { round, size, trump, rows = { [seat] = { bid, took, points } } }
		tieHands = 0,
		played = {},
		botLevel = (options and options.botLevel) or "medium",
	}
	local top = 0
	for _, n in state.schedule do
		top = math.max(top, n)
	end
	state.topSize = top
	deal(state)
	return state
end

-- The bid the dealer may not make (nil for everyone else, or when it can't add up).
function OhHell.forbiddenBid(state, seat: number): number?
	if seat ~= state.dealer or state.hook == false then
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
	local hand = state.hands[seat]
	if #state.trick == 0 and state.trumpMustBreak and state.trump and not state.trumpBrokenNow then
		local other = {}
		for _, id in hand do
			if suit(id) ~= state.trump then
				table.insert(other, id)
			end
		end
		if #other > 0 then
			return other
		end
	end
	return Tricks.followable(hand, state.trick)
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
			return false, if #state.trick == 0 then "Trump isn't broken yet" else "Follow suit"
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
		if state.everyTrick then
			points = took + (if bid == took then OhHell.EXACT_BONUS else 0)
		end
		if state.missPenalty and bid ~= took then
			points = -5 * math.abs(bid - took)
		end
		state.scores[seat] += points
		if bid == took then
			state.made[seat] += 1
		end
		summary[tostring(seat)] = { bid = bid, took = took, points = points }
	end
	state.roundSummary = summary
	table.insert(state.history, { round = state.round, size = state.handSize, trump = state.trump, rows = GameModule.copy(summary) })
	state.tied = false
	if state.round >= #state.schedule then
		local best, count = -math.huge, 0
		for seat = 1, state.seatCount do
			if state.scores[seat] > best then
				best, count = state.scores[seat], 1
			elseif state.scores[seat] == best then
				count += 1
			end
		end
		if count > 1 and state.tieHands < OhHell.MAX_TIE_HANDS then
			-- Tied at the top: one more hand at the top size (Pagat).
			state.tieHands += 1
			state.tied = true
			table.insert(state.schedule, state.topSize)
			state.phase = "round"
		else
			state.over = true
			state.phase = "done"
		end
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
	state.played[move.card] = true
	if state.trump and suit(move.card) == state.trump then
		state.trumpBrokenNow = true
	end
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
		noTrump = state.trump == nil,
		history = GameModule.copy(state.history),
		tied = state.tied == true,
		scoring = if state.everyTrick then "tricks" else "exact",
		missPenalty = state.missPenalty,
		trumpMustBreak = state.trumpMustBreak and state.trump ~= nil and not state.trumpBrokenNow,
		dealer = state.dealer,
		turn = state.turn,
		phase = state.phase,
	}
end

function OhHell.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		local bid = state.bids[seat]
		local dealer = if seat == state.dealer then " · D" else ""
		info[seat] = `{state.scores[seat]} pts · {if bid == nil then "bidding" else `bid {bid}`} · {state.tricks[seat]} won{dealer}`
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

-- A count of the tricks a hand should take with this trump and this many players. Each
-- card counts as its chance that nobody else holds a higher card of its suit (fewer cards
-- dealt, more of the high cards are still in the box), side cards a little less for the
-- risk of being trumped. Short side suits let spare trumps ruff.
function OhHell.estimate(hand: { number }, trump: number?, seatCount: number): number
	local size = #hand
	if size == 0 then
		return 0
	end
	local unseen = 52 - size - 1
	local others = math.min(unseen, (seatCount - 1) * size)
	local keep = 1 - others / unseen -- chance one unseen card is NOT in another hand
	local bySuit = { {}, {}, {}, {} }
	for _, id in hand do
		table.insert(bySuit[suit(id)], power(id))
	end
	local est = 0
	local spareTrumps = 0
	for s2 = 1, 4 do
		local cards = bySuit[s2]
		table.sort(cards, function(x, y)
			return x > y
		end)
		for i, p in cards do
			-- Higher cards of this suit we don't hold.
			local higher = (14 - p) - (i - 1)
			local chance = keep ^ math.max(0, higher)
			-- Low cards rarely get the lead to win: they count for much less.
			chance = chance ^ 1.8
			-- Our own higher cards in the suit take the same tricks first.
			if i > 1 then
				chance *= 0.6
			end
			if s2 == trump then
				est += chance
				if chance < 0.5 then
					spareTrumps += 1
				end
			else
				-- A side card can be trumped once someone runs out of the suit.
				local ruff = if trump then math.min(0.5, 0.06 * (seatCount - 1) * math.max(0, size - 3) / 3 + (i - 1) * 0.12) else 0
				est += chance * (1 - ruff)
			end
		end
	end
	if trump then
		-- Voids and singletons with spare low trumps: each can ruff a trick.
		for s2 = 1, 4 do
			if s2 ~= trump and spareTrumps > 0 and size >= 3 then
				local n = #bySuit[s2]
				if n == 0 then
					est += 0.55 * 3 / seatCount
					spareTrumps -= 1
				elseif n == 1 and spareTrumps > 0 then
					est += 0.3 * 3 / seatCount
					spareTrumps -= 1
				end
			end
		end
	end
	return math.clamp(est, 0, size)
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
	local hard = state.botLevel == "hard"
	local trump = state.trump
	local need = state.bids[seat] - state.tricks[seat]
	local trick = state.trick
	-- Trumps count as worth more than their face value.
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
		if need > 0 then
			-- Lead side Aces first and keep the trumps to ruff.
			local aces = {}
			for _, id in cards do
				if power(id) == 14 and suit(id) ~= trump then
					table.insert(aces, id)
				end
			end
			if #aces > 0 then
				return aces[1]
			end
			local side = {}
			for _, id in cards do
				if suit(id) ~= trump then
					table.insert(side, id)
				end
			end
			return dearest(if #side > 0 then side else cards)
		end
		return cheapest(cards)
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
			if hard and #trick < state.seatCount - 1 then
				-- The cheapest winner nobody can top in its suit (counting cards played).
				local safe = {}
				for _, id in winners do
					local boss = true
					for p = power(id) + 1, 14 do
						local other = PlayingCards.make(if p == 14 then 1 else p, suit(id))
						if not state.played[other] and not table.find(state.hands[seat], other) then
							boss = false
						end
					end
					if boss then
						table.insert(safe, id)
					end
				end
				return if #safe > 0 then cheapest(safe) else dearest(winners)
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

-- A natural pause before a bot moves: quick when forced, longer for a real choice.
function OhHell.getBotDelay(state, seat: number, rng: Random): number
	return BotThink.delay(rng, #OhHell.getLegalMoves(state, seat))
end

return OhHell
