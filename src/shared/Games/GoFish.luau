-- Go Fish: collect books (all four cards of a rank) for 2-6 seats.
--
-- Deal 7 cards each with 2-3 players, 5 with 4 or more. The rest is the pond.
-- On your turn ask another player for a rank you hold. If they have any, they hand them
-- all over and you go again. If not: "Go fish!" You draw one card; if it's the rank you
-- asked for you go again, otherwise the turn passes. Four of a kind is put down as a
-- book straight away. A player whose hand is empty draws a card on their turn (if the
-- pond is empty too, they sit out). When all 13 books are down, most books wins.
--
-- Moves: { kind = "ask", target = seat, rank = 1..13 }

local GameModule = require(script.Parent.Parent.GameModule)
local PlayingCards = require(script.Parent.Parent.Cards.PlayingCards)

local GoFish = {}

GoFish.id = "GoFish"
GoFish.minSeats = 2
GoFish.maxSeats = 6

local rank = PlayingCards.rank

function GoFish.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= 2 and seatCount <= 6, "Go Fish needs 2-6 seats")
	local random = rng or Random.new()
	local pond = PlayingCards.newDeck(random)
	local handSize = if seatCount <= 3 then 7 else 5
	local hands, books, asked = {}, {}, {}
	for seat = 1, seatCount do
		hands[seat] = {}
		books[seat] = {}
		asked[seat] = {}
		for _ = 1, handSize do
			table.insert(hands[seat], table.remove(pond) :: number)
		end
	end
	local state = {
		seatCount = seatCount,
		rng = random,
		pond = pond,
		hands = hands,
		books = books, -- books[seat] = { rank, ... }
		-- Public memory: ranks each seat has asked for (and so must still hold). Hard
		-- bots use it, the same way a sharp player would.
		asked = asked,
		turn = 1,
		lastAction = nil,
		lastDrawn = nil, -- { seat, card }: only that seat sees the card
		turns = 0,
		over = false,
		botLevel = (options and options.botLevel) or "medium",
	}
	-- A dealt hand can already hold a book.
	for seat = 1, seatCount do
		GoFish._collectBooks(state, seat)
	end
	GoFish._settleTurn(state)
	return state
end

local function totalBooks(state): number
	local n = 0
	for seat = 1, state.seatCount do
		n += #state.books[seat]
	end
	return n
end

function GoFish._collectBooks(state, seat: number): { number }
	local made = {}
	local counts = PlayingCards.rankCounts(state.hands[seat])
	for r, n in counts do
		if n == 4 then
			table.insert(made, r)
			table.insert(state.books[seat], r)
			state.asked[seat][r] = nil
			local keep = {}
			for _, id in state.hands[seat] do
				if rank(id) ~= r then
					table.insert(keep, id)
				end
			end
			state.hands[seat] = keep
		end
	end
	table.sort(made)
	return made
end

local function drawCard(state, seat: number): number?
	local id = table.remove(state.pond)
	if id then
		table.insert(state.hands[seat], id)
	end
	return id
end

local function someoneHasCards(state, except: number): boolean
	for seat = 1, state.seatCount do
		if seat ~= except and #state.hands[seat] > 0 then
			return true
		end
	end
	return false
end

-- Makes sure the player whose turn it is can ask someone, drawing or skipping as needed.
function GoFish._settleTurn(state)
	for _ = 1, state.seatCount * 2 + 2 do
		if totalBooks(state) >= 13 then
			state.over = true
			return
		end
		local seat = state.turn
		if #state.hands[seat] == 0 and #state.pond > 0 then
			local id = drawCard(state, seat)
			state.lastDrawn = { seat = seat, card = id }
			GoFish._collectBooks(state, seat)
		end
		if #state.hands[seat] > 0 and someoneHasCards(state, seat) then
			return
		end
		state.turn = state.turn % state.seatCount + 1
	end
	-- Nobody can ask anyone (shouldn't happen while books are missing): end it.
	state.over = true
end

local function nextTurn(state)
	state.turn = state.turn % state.seatCount + 1
	GoFish._settleTurn(state)
end

function GoFish.getActiveSeats(state): { number }
	if state.over then
		return {}
	end
	return { state.turn }
end

function GoFish.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if state.over or seat ~= state.turn then
		return moves
	end
	local counts = PlayingCards.rankCounts(state.hands[seat])
	for target = 1, state.seatCount do
		if target ~= seat and #state.hands[target] > 0 then
			for r in counts do
				table.insert(moves, { kind = "ask", target = target, rank = r })
			end
		end
	end
	return moves
end

function GoFish.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.over then
		return false, "The game is over"
	end
	if seat ~= state.turn then
		return false, "It's not your turn"
	end
	if type(move) ~= "table" or move.kind ~= "ask" then
		return false, "Bad move"
	end
	local target = move.target
	if type(target) ~= "number" or target % 1 ~= 0 or target < 1 or target > state.seatCount then
		return false, "Pick a player to ask"
	end
	if target == seat then
		return false, "You can't ask yourself"
	end
	if #state.hands[target] == 0 then
		return false, "They have no cards"
	end
	if not PlayingCards.isRank(move.rank) then
		return false, "Pick a rank"
	end
	if not PlayingCards.rankCounts(state.hands[seat])[move.rank] then
		return false, "You can only ask for a rank you hold"
	end
	return true
end

function GoFish.applyMove(state, seat: number, move: any)
	local target, r = move.target, move.rank
	state.turns += 1
	state.lastDrawn = nil
	local given, keep = {}, {}
	for _, id in state.hands[target] do
		if rank(id) == r then
			table.insert(given, id)
		else
			table.insert(keep, id)
		end
	end
	state.asked[seat][r] = true
	local action: any = { seat = seat, target = target, rank = r, got = #given }
	if #given > 0 then
		state.hands[target] = keep
		state.asked[target][r] = nil
		for _, id in given do
			table.insert(state.hands[seat], id)
		end
		action.books = GoFish._collectBooks(state, seat)
		state.lastAction = action
		-- Go again (settle handles an empty hand or an empty table).
		GoFish._settleTurn(state)
		return
	end
	-- Go fish!
	local id = drawCard(state, seat)
	action.fished = id ~= nil
	action.luckyFish = id ~= nil and rank(id) == r
	if id then
		state.lastDrawn = { seat = seat, card = id }
	end
	action.books = GoFish._collectBooks(state, seat)
	state.lastAction = action
	if action.luckyFish then
		GoFish._settleTurn(state)
	else
		nextTurn(state)
	end
end

function GoFish.getResult(state): GameModule.Result?
	if not state.over then
		return nil
	end
	local best, top = {}, -1
	for seat = 1, state.seatCount do
		local n = #state.books[seat]
		if n > top then
			best, top = { seat }, n
		elseif n == top then
			table.insert(best, seat)
		end
	end
	return {
		winners = best,
		isDraw = #best > 1,
		reason = if #best > 1 then `Tied with {top} books` else `Most books ({top})`,
	}
end

function GoFish.getView(state, seat: number?)
	local counts, books = {}, {}
	for s = 1, state.seatCount do
		counts[s] = #state.hands[s]
		books[s] = table.clone(state.books[s])
	end
	local hand = if seat and state.hands[seat] then PlayingCards.sortHand(state.hands[seat]) else nil
	local yourTurn = seat ~= nil and seat == state.turn and not state.over
	local askable = {}
	if yourTurn then
		for r in PlayingCards.rankCounts(state.hands[seat :: number]) do
			table.insert(askable, r)
		end
		table.sort(askable)
	end
	return {
		hand = hand,
		handCounts = counts,
		books = books,
		pondCount = #state.pond,
		turn = state.turn,
		lastAction = GameModule.copy(state.lastAction),
		-- Only the player who fished sees what they drew.
		drawnCard = if state.lastDrawn and state.lastDrawn.seat == seat then state.lastDrawn.card else nil,
		askableRanks = askable,
	}
end

function GoFish.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		local b = #state.books[seat]
		info[seat] = `{#state.hands[seat]} cards · {b} {if b == 1 then "book" else "books"}`
	end
	return info
end

function GoFish.getScores(state): { [number]: number }
	local scores = {}
	for seat = 1, state.seatCount do
		scores[seat] = #state.books[seat]
	end
	return scores
end

-- Bots ------------------------------------------------------------------------

function GoFish.chooseBotMove(state, seat: number, rng: Random): any?
	local moves = GoFish.getLegalMoves(state, seat)
	if #moves == 0 then
		return nil
	end
	if state.botLevel == "easy" then
		return moves[rng:NextInteger(1, #moves)]
	end
	local counts = PlayingCards.rankCounts(state.hands[seat])
	local bestMove, bestScore = nil, -math.huge
	for _, move in moves do
		local score = counts[move.rank] + rng:NextNumber() * 0.9
		if state.botLevel == "hard" and state.asked[move.target][move.rank] then
			score += 10 -- they asked for it, so they have it
		end
		score += #state.hands[move.target] * 0.05 -- bigger hands are better odds
		if score > bestScore then
			bestMove, bestScore = move, score
		end
	end
	return bestMove
end

-- Stats for the profile (see shared/StatsCatalog.luau).
function GoFish.getMatchStats(state): { [number]: { [string]: number } }
	local out = {}
	for seat = 1, state.seatCount do
		out[seat] = { books = #state.books[seat] }
	end
	return out
end

return GoFish
