-- Snap: the quick-eyes matching game. Win every card. 2-6 seats.
--
-- The deck is dealt out face down. In turn, each player flips their top card onto their
-- own face-up pile in front of them. When the top cards of any two face-up piles match
-- (same rank, or same rank and color with the "match" house rule), the first player to
-- call SNAP! wins both of those piles (all matching piles if more than two match) and
-- puts them under their face-down pile. Anyone with cards may snap, not just the owners.
-- A wrong snap puts your whole face-up pile in the middle as the Snap Pool (Pagat); when a
-- top card matches the pool's top card, the first to snap wins the pool. House rules make a
-- wrong snap cost 1 or 2 cards to the player on your left instead, or let only the owners
-- of the matching piles snap.
-- When your face-down pile runs out, your face-up pile is turned over to make a new one
-- (shuffled once the game runs long, so stalemates break up).
-- A player with no cards at all is out. Last player with cards wins; after the host's flip
-- limit (250, 500 or none) the player with the most cards wins.
-- After a snap, play goes on from the player left of whoever flipped last.
--
-- Moves: { kind = "flip" } (your turn)  |  { kind = "snap" } (anyone with cards, any time)

local GameModule = require(script.Parent.Parent.GameModule)
local PlayingCards = require(script.Parent.Parent.Cards.PlayingCards)

local Snap = {}

Snap.id = "Snap"
Snap.minSeats = 2
Snap.maxSeats = 6

Snap.FLIP_LIMIT = 500 -- default; the "length" house rule picks 250, 500 or none (0)
Snap.SHUFFLE_AFTER = 300 -- from here on a turned-over pile is shuffled
Snap.WON_SECONDS = 1 -- a short pause after a good snap, so everyone sees who got it

local rank = PlayingCards.rank

function Snap.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= 2 and seatCount <= 6, "Snap needs 2-6 seats")
	local random = rng or Random.new()
	local deck = PlayingCards.newDeck(random)
	local down, up = {}, {}
	for seat = 1, seatCount do
		down[seat] = {}
		up[seat] = {}
	end
	for i, id in deck do
		table.insert(down[(i - 1) % seatCount + 1], id)
	end
	local rules = if options and type(options.rules) == "table" then options.rules else {}
	return {
		seatCount = seatCount,
		rng = random,
		down = down, -- face-down piles: top card is the last one
		up = up, -- face-up piles: top card is the last one
		turn = 1,
		flips = 0,
		pause = false, -- true for a moment after a good snap
		phaseId = 0,
		lastAction = nil,
		winners = nil,
		reason = nil,
		color = rules.match == "color",
		-- house rule: what a wrong snap costs ("pool" = your face-up pile to the Snap Pool)
		penalty = if rules.penalty == 1 or rules.penalty == 2 then rules.penalty else "pool",
		pool = {}, -- the Snap Pool in the middle: top card is the last one
		limit = if type(rules.length) == "number" and rules.length >= 0 then rules.length else Snap.FLIP_LIMIT,
		ownersOnly = rules.owners == true,
		botLevel = (options and options.botLevel) or "medium",
	}
end

local function total(state, seat: number): number
	return #state.down[seat] + #state.up[seat]
end
Snap.total = total

local function nextWithCards(state, seat: number): number?
	for i = 1, state.seatCount do
		local s = (seat - 1 + i) % state.seatCount + 1
		if total(state, s) > 0 then
			return s
		end
	end
	return nil
end

local function same(state, a: number, b: number): boolean
	if rank(a) ~= rank(b) then
		return false
	end
	return not state.color or PlayingCards.isRed(a) == PlayingCards.isRed(b)
end

-- Seats whose face-up top card matches another seat's top card.
function Snap.matching(state): { number }
	local out = {}
	for a = 1, state.seatCount do
		local ta = state.up[a][#state.up[a]]
		if ta then
			for b = 1, state.seatCount do
				local tb = state.up[b][#state.up[b]]
				if b ~= a and tb and same(state, ta, tb) then
					table.insert(out, a)
					break
				end
			end
		end
	end
	return out
end

-- Seats whose face-up top card matches the Snap Pool's top card.
function Snap.poolMatching(state): { number }
	local out = {}
	local top = state.pool and state.pool[#state.pool]
	if not top then
		return out
	end
	for s = 1, state.seatCount do
		local t = state.up[s][#state.up[s]]
		if t and same(state, t, top) then
			table.insert(out, s)
		end
	end
	return out
end

-- Would a snap from `seat` be right? (With "owners only", your own pile has to be in it.)
function Snap.canSnap(state, seat: number?): boolean
	if state.pause then
		return false
	end
	local piles, pool = Snap.matching(state), Snap.poolMatching(state)
	if seat and state.ownersOnly then
		return table.find(piles, seat) ~= nil or table.find(pool, seat) ~= nil
	end
	return #piles > 0 or #pool > 0
end

local function checkEnd(state)
	local alive = {}
	for seat = 1, state.seatCount do
		if total(state, seat) > 0 then
			table.insert(alive, seat)
		end
	end
	if #alive <= 1 then
		state.winners = alive
		state.reason = "Won every card"
	elseif state.limit > 0 and state.flips >= state.limit then
		local best, top = {}, -1
		for seat = 1, state.seatCount do
			local n = total(state, seat)
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

-- Only the flipper is on the turn clock; everyone else may snap out of turn. So a
-- person who looks away is flipped for, never snapped for.
function Snap.getActiveSeats(state): { number }
	if state.winners or total(state, state.turn) == 0 then
		return {}
	end
	return { state.turn }
end

function Snap.getInterruptSeats(state): { number }
	local out = {}
	if state.winners then
		return out
	end
	for seat = 1, state.seatCount do
		if seat ~= state.turn and total(state, seat) > 0 then
			table.insert(out, seat)
		end
	end
	return out
end

function Snap.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if state.winners or total(state, seat) == 0 then
		return moves
	end
	if Snap.canSnap(state, seat) then
		table.insert(moves, { kind = "snap" })
	end
	if seat == state.turn and not state.pause then
		table.insert(moves, { kind = "flip" })
	end
	return moves
end

function Snap.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.winners then
		return false, "The game is over"
	end
	if type(move) ~= "table" then
		return false, "Bad move"
	end
	if total(state, seat) == 0 then
		return false, "You're out of cards"
	end
	if state.pause then
		return false, "Wait a moment"
	end
	if move.kind == "flip" then
		if seat ~= state.turn then
			return false, "It's not your turn to flip"
		end
		return true
	elseif move.kind == "snap" then
		return true -- a wrong snap is allowed, it just costs a card
	end
	return false, "Bad move"
end

function Snap.applyMove(state, seat: number, move: any)
	if move.kind == "snap" then
		local matched = Snap.matching(state)
		local poolHits = Snap.poolMatching(state)
		if state.ownersOnly and not Snap.canSnap(state, seat) then
			matched, poolHits = {}, {}
		end
		if #matched > 0 or #poolHits > 0 then
			local won = 0
			for _, s in matched do
				for _, id in state.up[s] do
					table.insert(state.down[seat], 1, id)
					won += 1
				end
				state.up[s] = {}
			end
			local poolWon = 0
			if #poolHits > 0 then
				for _, id in state.pool do
					table.insert(state.down[seat], 1, id)
					poolWon += 1
				end
				state.pool = {}
			end
			state.lastAction = { kind = "snap", seat = seat, count = won + poolWon, piles = matched, pool = poolWon > 0 }
			GameModule.addStat(state, seat, "snaps")
			state.pause = true
			state.phaseId += 1
		elseif state.penalty == "pool" then
			-- Wrong snap: your face-up pile goes to the middle (or one card, if it's empty).
			local paid = 0
			if #state.up[seat] > 0 then
				for _, id in state.up[seat] do
					table.insert(state.pool, id)
					paid += 1
				end
				state.up[seat] = {}
			elseif #state.down[seat] > 0 then
				table.insert(state.pool, table.remove(state.down[seat]) :: number)
				paid = 1
			end
			state.lastAction = { kind = "badSnap", seat = seat, count = paid, pool = true }
			if total(state, seat) == 0 and state.turn == seat then
				state.turn = nextWithCards(state, seat) or seat
			end
		else
			-- Wrong snap: pay cards to the player on your left.
			local left = nil
			for i = 1, state.seatCount - 1 do
				local s = (seat - 1 + i) % state.seatCount + 1
				if total(state, s) > 0 then
					left = s
					break
				end
			end
			if not left then
				return
			end
			local paid = 0
			for _ = 1, state.penalty or 1 do
				if total(state, seat) == 0 then
					break
				end
				local pile = if #state.down[seat] > 0 then state.down[seat] else state.up[seat]
				local card = table.remove(pile, if pile == state.up[seat] then 1 else #pile) :: number
				table.insert(state.down[left], 1, card)
				paid += 1
			end
			state.lastAction = { kind = "badSnap", seat = seat, to = left, count = paid }
			if total(state, seat) == 0 and state.turn == seat then
				state.turn = nextWithCards(state, seat) or seat
			end
		end
		checkEnd(state)
		return
	end

	-- Flip. An empty face-down pile is refilled from the face-up pile first.
	if #state.down[seat] == 0 then
		local up = state.up[seat]
		for i = #up, 1, -1 do
			table.insert(state.down[seat], up[i])
		end
		state.up[seat] = {}
		if state.flips >= Snap.SHUFFLE_AFTER then
			-- A long game: shuffle the turned-over pile so the same cards stop meeting.
			local pile = state.down[seat]
			for i = #pile, 2, -1 do
				local j = state.rng:NextInteger(1, i)
				pile[i], pile[j] = pile[j], pile[i]
			end
		end
	end
	local card = table.remove(state.down[seat]) :: number
	table.insert(state.up[seat], card)
	state.flips += 1
	state.lastAction = { kind = "flip", seat = seat, card = card }
	state.turn = nextWithCards(state, seat) or seat
	checkEnd(state)
end

function Snap.getTimer(state): { id: number, seconds: number }?
	if state.pause and not state.winners then
		return { id = state.phaseId, seconds = Snap.WON_SECONDS }
	end
	return nil
end

function Snap.onTimeout(state)
	if state.pause then
		state.pause = false
		-- Play goes on from the player left of whoever flipped last (Pagat).
		if total(state, state.turn) == 0 then
			state.turn = nextWithCards(state, state.turn) or state.turn
		end
		state.phaseId += 1
		checkEnd(state)
	end
end

function Snap.getResult(state): GameModule.Result?
	if not state.winners then
		return nil
	end
	return { winners = table.clone(state.winners), isDraw = #state.winners ~= 1, reason = state.reason }
end

function Snap.getView(state, _seat: number?)
	local downCounts, upCounts, tops = {}, {}, {}
	for s = 1, state.seatCount do
		downCounts[s] = #state.down[s]
		upCounts[s] = #state.up[s]
		tops[tostring(s)] = state.up[s][#state.up[s]]
	end
	return {
		downCounts = downCounts,
		upCounts = upCounts,
		tops = tops, -- tops["seat"] = face-up top card (missing when the pile is empty)
		turn = state.turn,
		pause = state.pause,
		color = state.color,
		lastAction = GameModule.copy(state.lastAction),
		flips = state.flips,
		limit = state.limit, -- 0 = no limit
		poolCount = #state.pool,
		poolTop = state.pool[#state.pool],
		ownersOnly = state.ownersOnly,
		penalty = state.penalty,
	}
end

function Snap.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		local n = total(state, seat)
		info[seat] = if n == 0 then "Out" else `{n} cards`
	end
	return info
end

function Snap.getScores(state): { [number]: number }
	local scores = {}
	for seat = 1, state.seatCount do
		scores[seat] = total(state, seat)
	end
	return scores
end

-- Bots ------------------------------------------------------------------------
-- Levels differ by reaction time; easy bots also miss about one match in five and now and
-- then snap on a near miss, which feeds the Snap Pool.

local REACTION = { easy = { 1.2, 0.9 }, medium = { 0.7, 0.5 }, hard = { 0.4, 0.3 } }
local MISS = { easy = 0.2, medium = 0.05, hard = 0 }
local FALSE_SNAP = { easy = 0.06, medium = 0.01, hard = 0 }

-- Two face-up tops one rank apart: what a hasty eye takes for a match.
local function nearMiss(state): boolean
	local tops = {}
	for s = 1, state.seatCount do
		local t = state.up[s][#state.up[s]]
		if t then
			table.insert(tops, rank(t))
		end
	end
	for i = 1, #tops do
		for j = i + 1, #tops do
			if math.abs(tops[i] - tops[j]) == 1 then
				return true
			end
		end
	end
	return false
end

function Snap.getBotDelay(state, seat: number, rng: Random): number
	if Snap.canSnap(state, seat) then
		local r = REACTION[state.botLevel] or REACTION.medium
		return r[1] + rng:NextNumber() * r[2]
	end
	if seat == state.turn then
		return 0.7 + rng:NextNumber() * 0.5
	end
	return 0.4
end

function Snap.chooseBotMove(state, seat: number, rng: Random): any?
	if state.winners or total(state, seat) == 0 or state.pause then
		return nil
	end
	-- Bots get one look each time the table changes.
	if Snap.canSnap(state, seat) then
		if rng:NextNumber() >= (MISS[state.botLevel] or 0) then
			return { kind = "snap" }
		end
	elseif not Snap.canSnap(state) and nearMiss(state) and rng:NextNumber() < (FALSE_SNAP[state.botLevel] or 0) then
		return { kind = "snap" }
	end
	if seat == state.turn then
		return { kind = "flip" }
	end
	return nil
end

-- A person who looked away is flipped for on their turn, and never snaps.
function Snap.chooseAfkMove(state, seat: number, _rng: Random): any?
	if state.winners or state.pause or seat ~= state.turn or total(state, seat) == 0 then
		return nil
	end
	return { kind = "flip" }
end

return Snap
