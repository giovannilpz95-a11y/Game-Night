-- President: the climbing card game. Be first to empty your hand, then rule the next round.
-- 3-8 seats.
--
-- Card order, low to high: 3 4 5 6 7 8 9 10 J Q K A 2. The whole deck is dealt out.
-- The leader plays a single, pair, triple or four of a kind. Going around, each player
-- must play the same number of cards of a higher rank, or pass. Once you pass you are out
-- until the pile is cleared. When everyone else has passed, the pile is cleared and the
-- last player to play leads again (if they just went out, the next player still in leads).
-- The first player out is President, then Vice President, Citizens, Vice Beggar, and the
-- last one holding cards is the Beggar.
-- Between rounds the Beggar hands their 2 best cards to the President, who gives back
-- their 2 worst (with 4+ players the Vice Beggar and Vice President swap 1). The Beggar
-- leads the next round; the holder of the 3 of Clubs leads the first.
-- Points each round: (players - place). After the last round the most points wins.
--
-- Moves: { kind = "play", cards = { id, ... } }  |  { kind = "pass" }

local GameModule = require(script.Parent.Parent.GameModule)
local BotThink = require(script.Parent.Parent.BotThink)
local PlayingCards = require(script.Parent.Parent.Cards.PlayingCards)

local President = {}

President.id = "President"
President.minSeats = 3
President.maxSeats = 8

President.ROUNDS = 3 -- house rule "rounds" can change it
President.BETWEEN_SECONDS = 5

local rank = PlayingCards.rank

-- 3 = 1 ... King = 11, Ace = 12, 2 = 13.
local function power(id: number): number
	local r = rank(id)
	return if r == 1 then 12 elseif r == 2 then 13 else r - 2
end
President.power = power

local function sorted(hand: { number }): { number }
	return PlayingCards.sortBy(hand, power)
end

local function deal(state)
	local deck = PlayingCards.newDeck(state.rng)
	for seat = 1, state.seatCount do
		state.hands[seat] = {}
	end
	for i, id in deck do
		table.insert(state.hands[(i - 1) % state.seatCount + 1], id)
	end
	state.round += 1
	state.finished = {}
	state.passed = {}
	state.pile = nil
	state.lastAction = nil
	state.exchange = {}
	if state.round == 1 or #state.order == 0 then
		local three = PlayingCards.make(3, 4)
		for seat = 1, state.seatCount do
			if table.find(state.hands[seat], three) then
				state.turn = seat
			end
		end
	else
		-- Card swap: the Beggar's best for the President's worst.
		local order, n = state.order, #state.order
		local function swap(low: number, high: number, count: number)
			local lowHand = sorted(state.hands[low])
			local give = {}
			for i = #lowHand, #lowHand - count + 1, -1 do
				table.insert(give, lowHand[i])
			end
			PlayingCards.removeCards(state.hands[low], give)
			local highHand = sorted(state.hands[high])
			local back = {}
			for i = 1, count do
				table.insert(back, highHand[i])
			end
			PlayingCards.removeCards(state.hands[high], back)
			for _, id in give do
				table.insert(state.hands[high], id)
			end
			for _, id in back do
				table.insert(state.hands[low], id)
			end
			table.insert(state.exchange, { from = low, to = high, gave = give, got = back })
		end
		swap(order[n], order[1], 2)
		if n >= 4 then
			swap(order[n - 1], order[2], 1)
		end
		state.turn = order[n]
	end
	state.phase = "play"
	state.phaseId += 1
end

function President.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= 3 and seatCount <= 8, "President needs 3-8 seats")
	local rules = if options and type(options.rules) == "table" then options.rules else {}
	local points = {}
	for seat = 1, seatCount do
		points[seat] = 0
	end
	local state = {
		seatCount = seatCount,
		rng = rng or Random.new(),
		hands = {},
		round = 0,
		rounds = if type(rules.rounds) == "number" and rules.rounds >= 1 then math.floor(rules.rounds) else President.ROUNDS,
		points = points,
		order = {}, -- last round's finishing order (roles)
		finished = {}, -- this round's finishing order so far
		passed = {},
		pile = nil, -- { cards, count, power, seat }
		turn = 1,
		phase = "play", -- "play" | "between" | "done"
		phaseId = 0,
		exchange = {},
		lastAction = nil,
		moves = 0,
		over = false,
		botLevel = (options and options.botLevel) or "medium",
	}
	deal(state)
	return state
end

local function hasCards(state, seat: number): boolean
	return #state.hands[seat] > 0
end

local function nextWithCards(state, seat: number): number?
	for i = 1, state.seatCount do
		local s = (seat - 1 + i) % state.seatCount + 1
		if hasCards(state, s) then
			return s
		end
	end
	return nil
end

-- Name for a finishing place with n players.
function President.roleName(place: number, n: number): string
	if place == 1 then
		return "President"
	elseif place == n then
		return "Beggar"
	elseif n >= 4 and place == 2 then
		return "Vice President"
	elseif n >= 4 and place == n - 1 then
		return "Vice Beggar"
	end
	return "Citizen"
end

local function endRound(state)
	local n = state.seatCount
	for place, seat in state.finished do
		state.points[seat] += n - place
	end
	state.order = table.clone(state.finished)
	if state.round >= state.rounds then
		state.over = true
		state.phase = "done"
		return
	end
	state.phase = "between"
	state.phaseId += 1
end

-- After a play or pass: who goes next, and does the pile clear?
local function advance(state, from: number)
	local stillIn = 0
	for seat = 1, state.seatCount do
		if hasCards(state, seat) then
			stillIn += 1
		end
	end
	if stillIn <= 1 then
		local last = nextWithCards(state, from)
		if last then
			table.insert(state.finished, last)
		end
		endRound(state)
		return
	end
	local owner = state.pile and state.pile.seat
	-- Anyone left who could still beat the pile?
	local seat = from
	for _ = 1, state.seatCount do
		seat = seat % state.seatCount + 1
		if seat == owner then
			break
		end
		if hasCards(state, seat) and not state.passed[seat] then
			state.turn = seat
			return
		end
	end
	-- Everyone passed: clear the pile, the last player to play leads.
	state.pile = nil
	state.passed = {}
	if owner and hasCards(state, owner) then
		state.turn = owner
	else
		state.turn = nextWithCards(state, owner or from) :: number
	end
	state.lastAction = { kind = "clear", seat = state.turn }
end

function President.getActiveSeats(state): { number }
	if state.over or state.phase ~= "play" then
		return {}
	end
	return { state.turn }
end

-- Groups of the hand by rank: { [power] = { ids } }
local function groups(hand: { number }): { [number]: { number } }
	local out = {}
	for _, id in sorted(hand) do
		local p = power(id)
		out[p] = out[p] or {}
		table.insert(out[p], id)
	end
	return out
end

function President.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if state.over or state.phase ~= "play" or seat ~= state.turn then
		return moves
	end
	for p, ids in groups(state.hands[seat]) do
		if state.pile == nil then
			for k = 1, #ids do
				table.insert(moves, { kind = "play", cards = table.move(ids, 1, k, 1, {}) })
			end
		elseif p > state.pile.power and #ids >= state.pile.count then
			table.insert(moves, { kind = "play", cards = table.move(ids, 1, state.pile.count, 1, {}) })
		end
	end
	if state.pile ~= nil then
		table.insert(moves, { kind = "pass" })
	end
	return moves
end

function President.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.over then
		return false, "The game is over"
	end
	if state.phase ~= "play" then
		return false, "Next round coming up"
	end
	if seat ~= state.turn then
		return false, "It's not your turn"
	end
	if type(move) ~= "table" then
		return false, "Bad move"
	end
	if move.kind == "pass" then
		if state.pile == nil then
			return false, "You're leading: play something"
		end
		return true
	elseif move.kind == "play" then
		if not PlayingCards.isCardList(move.cards, 4) then
			return false, "Play 1 to 4 cards"
		end
		if not PlayingCards.holdsAll(state.hands[seat], move.cards) then
			return false, "Those cards aren't in your hand"
		end
		if not PlayingCards.sameRank(move.cards) then
			return false, "Cards must all be the same rank"
		end
		if state.pile then
			if #move.cards ~= state.pile.count then
				return false, `Play {state.pile.count} {if state.pile.count == 1 then "card" else "cards"}`
			end
			if power(move.cards[1]) <= state.pile.power then
				return false, "Play a higher rank, or pass"
			end
		end
		return true
	end
	return false, "Bad move"
end

function President.applyMove(state, seat: number, move: any)
	state.moves += 1
	if move.kind == "pass" then
		state.passed[seat] = true
		state.lastAction = { kind = "pass", seat = seat }
		advance(state, seat)
		return
	end
	PlayingCards.removeCards(state.hands[seat], move.cards)
	state.pile = { cards = table.clone(move.cards), count = #move.cards, power = power(move.cards[1]), seat = seat }
	state.lastAction = { kind = "play", seat = seat, cards = table.clone(move.cards) }
	if not hasCards(state, seat) then
		table.insert(state.finished, seat)
		state.lastAction.out = #state.finished
	end
	advance(state, seat)
end

function President.getTimer(state): { id: number, seconds: number }?
	if state.phase == "between" and not state.over then
		return { id = state.phaseId, seconds = President.BETWEEN_SECONDS }
	end
	return nil
end

function President.onTimeout(state)
	if state.phase == "between" then
		deal(state)
	end
end

function President.getResult(state): GameModule.Result?
	if not state.over then
		return nil
	end
	local best, top = {}, -1
	for seat = 1, state.seatCount do
		local p = state.points[seat]
		if p > top then
			best, top = { seat }, p
		elseif p == top then
			table.insert(best, seat)
		end
	end
	return { winners = best, isDraw = #best > 1, reason = if #best > 1 then `Tied on {top} points` else `Most points ({top})` }
end

function President.getView(state, seat: number?)
	local counts, passed, roles, places = {}, {}, {}, {}
	for s = 1, state.seatCount do
		counts[s] = #state.hands[s]
	end
	for s in state.passed do
		passed[tostring(s)] = true
	end
	for place, s in state.order do
		roles[tostring(s)] = President.roleName(place, state.seatCount)
	end
	for place, s in state.finished do
		places[tostring(s)] = place
	end
	-- Only the two players in a swap see the cards.
	local exchange = {}
	for _, e in state.exchange do
		local mine = seat == e.from or seat == e.to
		table.insert(exchange, {
			from = e.from,
			to = e.to,
			count = #e.gave,
			gave = if mine then table.clone(e.gave) else nil,
			got = if mine then table.clone(e.got) else nil,
		})
	end
	return {
		hand = if seat and state.hands[seat] then sorted(state.hands[seat]) else nil,
		handCounts = counts,
		pile = GameModule.copy(state.pile),
		passed = passed,
		roles = roles, -- last round's roles
		places = places, -- this round's finishers
		finished = table.clone(state.finished),
		points = table.clone(state.points),
		round = state.round,
		rounds = state.rounds,
		turn = state.turn,
		phase = state.phase,
		exchange = exchange,
		lastAction = GameModule.copy(state.lastAction),
	}
end

function President.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		local place = table.find(state.finished, seat)
		local first = if place then President.roleName(place, state.seatCount) else `{#state.hands[seat]} cards`
		info[seat] = `{first} · {state.points[seat]} pts`
	end
	return info
end

function President.getScores(state): { [number]: number }
	return table.clone(state.points)
end

-- Bots ------------------------------------------------------------------------

function President.chooseBotMove(state, seat: number, rng: Random): any?
	local moves = President.getLegalMoves(state, seat)
	if #moves == 0 then
		return nil
	end
	if state.botLevel == "easy" then
		return moves[rng:NextInteger(1, #moves)]
	end
	local hand = state.hands[seat]
	local g = groups(hand)
	local best, bestScore = nil, math.huge
	for _, move in moves do
		local score
		if move.kind == "pass" then
			score = 100
		else
			local p = power(move.cards[1])
			score = p
			if state.pile == nil then
				-- Leading: dump low cards, as many of them as we have.
				score -= #move.cards * 0.6
				if #move.cards < #g[p] then
					score += 3 -- don't split a set when leading
				end
			else
				if #move.cards < #g[p] then
					score += if state.botLevel == "hard" then 6 else 2 -- breaking a pair/triple
				end
				-- Hard: hold back 2s and Aces while the hand is still big.
				if state.botLevel == "hard" and p >= 12 and #hand > 5 then
					score += 90
				end
			end
		end
		score += rng:NextNumber() * 0.5
		if score < bestScore then
			best, bestScore = move, score
		end
	end
	return best
end

-- A natural pause before a bot moves: quick when forced, longer for a real choice.
function President.getBotDelay(state, seat: number, rng: Random): number
	return BotThink.delay(rng, #President.getLegalMoves(state, seat))
end

return President
