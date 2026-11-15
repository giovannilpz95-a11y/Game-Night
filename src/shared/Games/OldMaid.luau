-- Old Maid: get rid of every card, and don't get stuck with the odd Queen. 2-6 seats.
--
-- One Queen (the Queen of Clubs) is taken out, and the Queen of Spades never pairs:
-- she's the Old Maid (the Queens of Hearts and Diamonds pair as usual). The other 51 cards are dealt out. Everyone puts down their pairs
-- (two cards of the same rank; with the "pairs" house rule, also the same color) straight
-- away. On your turn draw one face-down card from the player on your right who still has
-- cards; then the turn passes left, so the player who just drew is drawn from next (Bicycle,
-- Pagat). If it pairs with one of yours, the pair goes down. A player with no cards left is
-- safe. When only one player still holds cards, they're holding the Old Maid and lose.
--
-- House rules: "card" = "jack" (Black Peter) or "mystery" (one random card comes out face
-- down, so nobody knows which card won't pair until the end); "target" = 6 plays rounds:
-- finishing order scores penalty points (first out 0, then 1, 2...; the loser the most) and
-- the game ends when someone reaches 6: fewest points wins.
--
-- The giver's hand is shuffled after every draw, so where the Old Maid sits is never known.
--
-- While someone draws from you, you can play with them like at a real table (out of
-- turn, see getInterruptSeats): shuffle your hand in front of them, or lift one card up
-- out of the fan as bait (or a bluff). A few times per draw.
--
-- Moves: { kind = "draw", index = 1..#target hand }  (your turn)
--        { kind = "shuffle" }                         (the player being drawn from)
--        { kind = "lift", index = 0..#your hand }     (0 drops it back)

local GameModule = require(script.Parent.Parent.GameModule)
local PlayingCards = require(script.Parent.Parent.Cards.PlayingCards)

local OldMaid = {}

OldMaid.id = "OldMaid"
OldMaid.minSeats = 2
OldMaid.maxSeats = 6

OldMaid.DRAW_LIMIT = 600 -- safety cap; the Old Maid's holder loses when it's hit
OldMaid.OLD_MAID = PlayingCards.make(12, 1) -- Queen of Spades
OldMaid.REMOVED = PlayingCards.make(12, 4) -- Queen of Clubs
local GIVER_MOVES = 4 -- shuffles and lifts per draw
OldMaid.ROUND_SECONDS = 5 -- the pause between rounds in a game to 6 points
OldMaid.NO_ODD = 0 -- mystery mode: no known odd card
-- House rule "card" = "jack" plays Black Peter: the Jack of Spades is the odd card and
-- the Jack of Clubs comes out.
OldMaid.BLACK_PETER = PlayingCards.make(11, 1)
OldMaid.BLACK_PETER_REMOVED = PlayingCards.make(11, 4)

local rank = PlayingCards.rank

-- Takes every pair out of a hand. Returns the ranks paired. byColor: pairs must also
-- share a color (each rank has two black and two red cards, so all still pair up).
local function removePairs(hand: { number }, byColor: boolean?, odd: number?): { number }
	odd = odd or OldMaid.OLD_MAID
	local byRank = {}
	for _, id in hand do
		if id ~= odd then
			local r = rank(id) + (if byColor and PlayingCards.isRed(id) then 13 else 0)
			byRank[r] = byRank[r] or {}
			table.insert(byRank[r], id)
		end
	end
	local paired = {}
	for key = 1, 26 do
		local cards = byRank[key]
		if cards then
			while #cards >= 2 do
				PlayingCards.removeCards(hand, { cards[#cards], cards[#cards - 1] })
				cards[#cards] = nil
				cards[#cards] = nil
				table.insert(paired, (key - 1) % 13 + 1)
			end
		end
	end
	return paired
end
OldMaid.removePairs = removePairs

local function prevWithCards(state, seat: number): number?
	for i = 1, state.seatCount - 1 do
		local s = (seat - 1 - i) % state.seatCount + 1
		if #state.hands[s] > 0 then
			return s
		end
	end
	return nil
end

local function nextWithCards(state, seat: number): number?
	for i = 1, state.seatCount - 1 do
		local s = (seat - 1 + i) % state.seatCount + 1
		if #state.hands[s] > 0 then
			return s
		end
	end
	return nil
end

local function holding(state): { number }
	local out = {}
	for seat = 1, state.seatCount do
		if #state.hands[seat] > 0 then
			table.insert(out, seat)
		end
	end
	return out
end

local function checkEnd(state)
	local left = holding(state)
	local loser, done = nil, false
	if #left <= 1 then
		loser, done = left[1], true
	elseif state.draws >= OldMaid.DRAW_LIMIT then
		local most = -1
		for _, seat in left do
			if table.find(state.hands[seat], state.oldMaid) then
				loser = seat
				break
			end
			if #state.hands[seat] > most then
				loser, most = seat, #state.hands[seat]
			end
		end
		done = true
	end
	if not done then
		return
	end
	state.loser = loser
	if state.goal <= 0 then
		state.over = true
		return
	end
	-- A game to 6: penalty points by finishing order, the loser the most.
	local order = table.clone(state.finished)
	for _, seat in left do
		if seat ~= loser and not table.find(order, seat) then
			table.insert(order, seat)
		end
	end
	if loser then
		table.insert(order, loser)
	end
	local added = {}
	for i, seat in order do
		state.points[seat] += i - 1
		added[seat] = i - 1
	end
	state.roundResult = { loser = loser, added = added, round = state.round, odd = if loser then state.hands[loser][1] else nil }
	local top = 0
	for seat = 1, state.seatCount do
		top = math.max(top, state.points[seat])
	end
	if top >= state.goal then
		state.over = true
	else
		state.roundOver = true
		state.phaseId += 1
	end
end

-- Deals a round: the odd card's partner comes out, the rest are dealt, pairs go down.
local function dealRound(state)
	local deck = PlayingCards.newDeck(state.rng)
	if state.mystery then
		state.removed = table.remove(deck, state.rng:NextInteger(1, #deck))
	else
		state.removed = if state.oldMaid == OldMaid.BLACK_PETER then OldMaid.BLACK_PETER_REMOVED else OldMaid.REMOVED
		table.remove(deck, table.find(deck, state.removed) :: number)
	end
	for seat = 1, state.seatCount do
		state.hands[seat] = {}
		state.pairs[seat] = state.pairs[seat] or {}
		if state.round > 1 then
			state.pairs[seat] = {}
		end
	end
	local start = (state.round - 1) % state.seatCount
	for i, id in deck do
		table.insert(state.hands[(i - 1 + start) % state.seatCount + 1], id)
	end
	for seat = 1, state.seatCount do
		state.pairs[seat] = removePairs(state.hands[seat], state.byColor, state.oldMaid)
		PlayingCards.shuffle(state.hands[seat], state.rng)
	end
	state.finished = {}
	for seat = 1, state.seatCount do
		if #state.hands[seat] == 0 then
			table.insert(state.finished, seat)
		end
	end
	state.loser = nil
	state.lastAction = nil
	state.lastDrawn = nil
	state.lifted = nil
	state.giverMoves = 0
	state.draws = 0
end

-- Moves the turn on to someone with cards, and picks who they draw from.
local function settle(state, from: number)
	if state.over then
		return
	end
	if state.roundOver then
		return
	end
	local turn = if #state.hands[from] > 0 then from else nextWithCards(state, from)
	state.turn = turn :: number
	-- You draw from the player on your right.
	state.target = prevWithCards(state, state.turn) :: number
end

function OldMaid.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= 2 and seatCount <= 6, "Old Maid needs 2-6 seats")
	local random = rng or Random.new()
	local rules = if options and type(options.rules) == "table" then options.rules else {}
	local hands, pairs, points = {}, {}, {}
	for seat = 1, seatCount do
		hands[seat] = {}
		pairs[seat] = {}
		points[seat] = 0
	end
	local state = {
		oldMaid = if rules.card == "jack" then OldMaid.BLACK_PETER elseif rules.card == "mystery" then OldMaid.NO_ODD else OldMaid.OLD_MAID,
		mystery = rules.card == "mystery",
		removed = nil, -- the card taken out (secret in mystery mode until the end)
		seatCount = seatCount,
		rng = random,
		hands = hands, -- in a hidden order; the drawer picks a position
		pairs = pairs, -- pairs[seat] = { rank, ... } put down
		turn = 1,
		target = 2,
		draws = 0,
		lastAction = nil, -- { seat, from, rank? (when it made a pair), out = { seat }? }
		lastDrawn = nil, -- { seat, from, card }: only those two see the card
		over = false,
		loser = nil,
		byColor = rules.pairs == "color",
		lifted = nil, -- the position the player being drawn from lifted out of the fan
		shuffles = 0, -- how many times a giver has shuffled in front of the drawer
		giverMoves = 0, -- shuffles and lifts during this draw
		points = points, -- game to 6: penalty points
		round = 1,
		roundOver = false,
		roundResult = nil,
		finished = {}, -- seats in the order they got rid of their cards this round
		phaseId = 0,
		botLevel = (options and options.botLevel) or "medium",
	}
	state.goal = if type(rules.target) == "number" and rules.target > 0 then rules.target else 0
	dealRound(state)
	checkEnd(state)
	settle(state, 1)
	return state
end

function OldMaid.getActiveSeats(state): { number }
	if state.over or state.roundOver then
		return {}
	end
	return { state.turn }
end

function OldMaid.getTimer(state): { id: number, seconds: number }?
	if state.roundOver and not state.over then
		return { id = state.phaseId, seconds = OldMaid.ROUND_SECONDS }
	end
	return nil
end

function OldMaid.onTimeout(state)
	if not state.roundOver or state.over then
		return
	end
	state.roundOver = false
	state.round += 1
	state.phaseId += 1
	dealRound(state)
	checkEnd(state)
	settle(state, (state.round - 1) % state.seatCount + 1)
end

-- The player being drawn from may shuffle or lift a card while the drawer thinks.
local function canTease(state, seat: number): boolean
	return not state.over and not state.roundOver and seat == state.target and seat ~= state.turn and #state.hands[seat] > 1 and state.giverMoves < GIVER_MOVES
end

function OldMaid.getInterruptSeats(state): { number }
	return if canTease(state, state.target) then { state.target } else {}
end

function OldMaid.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if canTease(state, seat) then
		table.insert(moves, { kind = "shuffle" })
		for i = 0, #state.hands[seat] do
			table.insert(moves, { kind = "lift", index = i })
		end
		return moves
	end
	if state.over or state.roundOver or seat ~= state.turn then
		return moves
	end
	for i = 1, #state.hands[state.target] do
		table.insert(moves, { kind = "draw", index = i })
	end
	return moves
end

function OldMaid.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.over then
		return false, "The game is over"
	end
	if state.roundOver then
		return false, "Next round coming up"
	end
	if type(move) == "table" and (move.kind == "shuffle" or move.kind == "lift") then
		if not canTease(state, seat) then
			return false, "Not now"
		end
		if move.kind == "lift" then
			local index = move.index
			if type(index) ~= "number" or index ~= index or index % 1 ~= 0 or index < 0 or index > #state.hands[seat] then
				return false, "Pick one of your cards"
			end
		end
		return true
	end
	if type(move) ~= "table" or move.kind ~= "draw" then
		return false, "Bad move"
	end
	if seat ~= state.turn then
		return false, "It's not your turn"
	end
	local index = move.index
	if type(index) ~= "number" or index ~= index or index % 1 ~= 0 or index < 1 or index > #state.hands[state.target] then
		return false, "Pick one of their cards"
	end
	return true
end

function OldMaid.applyMove(state, seat: number, move: any)
	if move.kind == "shuffle" then
		PlayingCards.shuffle(state.hands[seat], state.rng)
		state.lifted = nil
		state.shuffles += 1
		state.giverMoves += 1
		return
	elseif move.kind == "lift" then
		state.lifted = if move.index > 0 then move.index else nil
		state.giverMoves += 1
		return
	end
	state.lifted = nil
	state.giverMoves = 0
	local from = state.target
	local card = table.remove(state.hands[from], move.index) :: number
	local hand = state.hands[seat]
	table.insert(hand, card)
	state.draws += 1
	local paired = removePairs(hand, state.byColor, state.oldMaid)
	for _, r in paired do
		table.insert(state.pairs[seat], r)
	end
	-- Nobody can track positions: both hands are mixed again.
	PlayingCards.shuffle(state.hands[from], state.rng)
	PlayingCards.shuffle(hand, state.rng)
	local out = {}
	for _, s in { from, seat } do
		if #state.hands[s] == 0 then
			table.insert(out, s)
			if not table.find(state.finished, s) then
				table.insert(state.finished, s)
			end
		end
	end
	state.lastAction = { seat = seat, from = from, rank = paired[1], out = out }
	state.lastDrawn = { seat = seat, from = from, card = card }
	checkEnd(state)
	settle(state, seat % state.seatCount + 1)
end

function OldMaid.getResult(state): GameModule.Result?
	if not state.over then
		return nil
	end
	local winners = {}
	for seat = 1, state.seatCount do
		if seat ~= state.loser then
			table.insert(winners, seat)
		end
	end
	if state.goal > 0 then
		-- Fewest penalty points wins (ties share it).
		local best = math.huge
		for seat = 1, state.seatCount do
			best = math.min(best, state.points[seat])
		end
		winners = {}
		for seat = 1, state.seatCount do
			if state.points[seat] == best then
				table.insert(winners, seat)
			end
		end
		return { winners = winners, isDraw = false, reason = `Fewest points when someone reached {state.goal}` }
	end
	return { winners = winners, isDraw = false, reason = if state.loser then "Everyone else got rid of their cards" else "Out of cards" }
end

function OldMaid.getView(state, seat: number?)
	local counts, pairs = {}, {}
	for s = 1, state.seatCount do
		counts[s] = #state.hands[s]
		pairs[s] = table.clone(state.pairs[s])
	end
	local drawn = state.lastDrawn
	local seen = nil
	if drawn and seat ~= nil and (seat == drawn.seat or seat == drawn.from) then
		seen = { seat = drawn.seat, from = drawn.from, card = drawn.card }
	end
	return {
		-- Your own hand sorted (it's your view, order doesn't matter); others are counts.
		hand = if seat and state.hands[seat] then PlayingCards.sortHand(state.hands[seat]) else nil,
		handCounts = counts,
		pairs = pairs,
		turn = state.turn,
		target = state.target,
		lastAction = GameModule.copy(state.lastAction),
		lastDrawn = seen,
		draws = state.draws,
		loser = state.loser,
		-- Mystery mode: nobody knows the odd card until the round is over.
		oldMaid = if state.mystery then (if (state.over or state.roundOver) and state.loser then state.hands[state.loser][1] else OldMaid.NO_ODD) else state.oldMaid,
		mystery = state.mystery,
		removed = if state.mystery and not (state.over or state.roundOver) then nil else state.removed,
		goal = state.goal,
		points = table.clone(state.points),
		round = state.round,
		roundOver = state.roundOver,
		roundResult = GameModule.copy(state.roundResult),
		byColor = state.byColor,
		over = state.over,
		lifted = state.lifted,
		shuffles = state.shuffles,
		-- Being drawn from: your hand in the order the drawer sees it (to lift a card).
		offering = if seat ~= nil and seat == state.target and not state.over then table.clone(state.hands[seat]) else nil,
		canTease = seat ~= nil and canTease(state, seat),
	}
end

function OldMaid.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		local n = #state.hands[seat]
		info[seat] = if n == 0 then "Safe!" else `{n} cards · {#state.pairs[seat]} pairs`
		if state.goal > 0 then
			info[seat] = `{state.points[seat]} pts · ` .. info[seat]
		end
	end
	return info
end

function OldMaid.getScores(state): { [number]: number }
	local scores = {}
	for seat = 1, state.seatCount do
		scores[seat] = if state.goal > 0 then -state.points[seat] else #state.pairs[seat]
	end
	return scores
end

-- Stats for the profile (see shared/StatsCatalog.luau).
function OldMaid.getMatchStats(state): { [number]: { [string]: number } }
	local out = {}
	for seat = 1, state.seatCount do
		out[seat] = { pairs = #state.pairs[seat], stuck = if seat == state.loser then 1 else 0 }
	end
	return out
end

-- Bots ------------------------------------------------------------------------
-- Old Maid is a game of luck: the giver's hand is shuffled before every draw, so no pick
-- is better than another. Bots differ only in how quickly they pick.

function OldMaid.getBotDelay(state, _seat: number, rng: Random): number
	local base = if state.botLevel == "easy" then 1.4 elseif state.botLevel == "hard" then 0.8 else 1.1
	return base + rng:NextNumber() * 0.6
end

function OldMaid.chooseBotMove(state, seat: number, rng: Random): any?
	if canTease(state, seat) then
		-- Once per draw at most: holding the Old Maid, shuffle her away or lift a decoy.
		if state.giverMoves > 0 or not table.find(state.hands[seat], state.oldMaid) or rng:NextNumber() > 0.6 then
			return nil
		end
		if state.botLevel == "hard" and rng:NextNumber() < 0.5 then
			for i, id in state.hands[seat] do
				if id ~= state.oldMaid then
					return { kind = "lift", index = i }
				end
			end
		end
		return { kind = "shuffle" }
	end
	if state.over or state.roundOver or seat ~= state.turn then
		return nil
	end
	-- A lifted card is tempting: easy bots go for it, hard ones smell a trap.
	local lifted = state.lifted
	if lifted and lifted <= #state.hands[state.target] then
		local bite = if state.botLevel == "easy" then 0.7 elseif state.botLevel == "hard" then 0.25 else 0.45
		if rng:NextNumber() < bite then
			return { kind = "draw", index = lifted }
		end
	end
	return { kind = "draw", index = rng:NextInteger(1, #state.hands[state.target]) }
end

return OldMaid
