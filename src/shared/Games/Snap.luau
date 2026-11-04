-- Snap: the quick-eyes matching game. Win every card. 2-6 seats.
--
-- The deck is dealt out face down. In turn, each player flips their top card onto their
-- own face-up pile in front of them. When the top cards of any two face-up piles match
-- (same rank, or same rank and color with the "match" house rule), the first player to
-- call SNAP! wins both of those piles (all matching piles if more than two match) and
-- puts them under their face-down pile. Anyone with cards may snap, not just the owners.
-- A wrong snap costs a card: your top face-down card goes to the player on your left.
-- When your face-down pile runs out, your face-up pile is turned over to make a new one.
-- A player with no cards at all is out. Last player with cards wins; after FLIP_LIMIT
-- flips the player with the most cards wins.
--
-- Moves: { kind = "flip" } (your turn)  |  { kind = "snap" } (anyone with cards, any time)

local GameModule = require(script.Parent.Parent.GameModule)
local PlayingCards = require(script.Parent.Parent.Cards.PlayingCards)

local Snap = {}

Snap.id = "Snap"
Snap.minSeats = 2
Snap.maxSeats = 6

Snap.FLIP_LIMIT = 500
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

function Snap.canSnap(state): boolean
	return not state.pause and #Snap.matching(state) > 0
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
	elseif state.flips >= Snap.FLIP_LIMIT then
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

function Snap.getActiveSeats(state): { number }
	if state.winners then
		return {}
	end
	local out = {}
	for seat = 1, state.seatCount do
		if total(state, seat) > 0 then
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
	if Snap.canSnap(state) then
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
		if #matched > 0 then
			local won = 0
			for _, s in matched do
				for _, id in state.up[s] do
					table.insert(state.down[seat], 1, id)
					won += 1
				end
				state.up[s] = {}
			end
			state.lastAction = { kind = "snap", seat = seat, count = won, piles = matched }
			GameModule.addStat(state, seat, "snaps")
			state.pause = true
			state.phaseId += 1
		else
			-- Wrong snap: pay one card to the player on your left.
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
			local pile = if #state.down[seat] > 0 then state.down[seat] else state.up[seat]
			local card = table.remove(pile, if pile == state.up[seat] then 1 else #pile) :: number
			table.insert(state.down[left], 1, card)
			state.lastAction = { kind = "badSnap", seat = seat, to = left }
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
		-- The snapper flips next.
		local a = state.lastAction
		if a and a.kind == "snap" and total(state, a.seat) > 0 then
			state.turn = a.seat
		elseif total(state, state.turn) == 0 then
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
-- Bots always spot a match; levels differ by reaction time, so a quick human beats them.

local REACTION = { easy = { 1.2, 0.9 }, medium = { 0.7, 0.5 }, hard = { 0.4, 0.3 } }

function Snap.getBotDelay(state, seat: number, rng: Random): number
	if Snap.canSnap(state) then
		local r = REACTION[state.botLevel] or REACTION.medium
		return r[1] + rng:NextNumber() * r[2]
	end
	if seat == state.turn then
		return 0.7 + rng:NextNumber() * 0.5
	end
	return 0.4
end

function Snap.chooseBotMove(state, seat: number, _rng: Random): any?
	if state.winners or total(state, seat) == 0 or state.pause then
		return nil
	end
	if Snap.canSnap(state) then
		return { kind = "snap" }
	end
	if seat == state.turn then
		return { kind = "flip" }
	end
	return nil
end

return Snap
