-- Slap Stack (the slapping game known as Egyptian Ratscrew): win every card. 2-6 seats.
--
-- The deck is dealt out face down. Players take turns flipping their top card onto the
-- middle pile. A face card or Ace is a challenge: the next player has 1 try for a Jack,
-- 2 for a Queen, 3 for a King and 4 for an Ace to flip another face card or Ace. If they
-- do, the challenge passes on; if they run out of tries, the challenger takes the pile
-- (after a short moment where anyone can still slap).
-- Slaps: anyone may slap the pile any time the top two cards are the same rank (a double)
-- or the top and third cards are (a sandwich, a house rule that's on by default). The
-- first good slap takes the whole pile and flips next. A bad slap burns one card face
-- down under the pile, and you can't slap again until the next card is flipped.
-- Out of cards? You can still slap back in once (dinogame.gg): a good slap takes the pile
-- and you're back. Three bad slaps while out and you're out for good. When one player
-- holds every card, they flip 3 last-chance cards before winning, so the others get a last
-- shot at slapping in. House rule "slapIn" = "never": out for good straight away.
-- Last player with cards wins. After FLIP_LIMIT flips the player with the most cards wins.
--
-- More slap house rules (off by default): topBottom (top card matches the bottom card),
-- marriage (a King and Queen together), tens (two cards adding up to 10, Ace = 1, also
-- across one face card between them), run (four in a row up or down, K-A-2 wraps),
-- penalty (2: a bad slap burns two cards).
--
-- Moves: { kind = "flip" } (your turn)  |  { kind = "slap" } (anyone with cards, any time)

local GameModule = require(script.Parent.Parent.GameModule)
local PlayingCards = require(script.Parent.Parent.Cards.PlayingCards)

local SlapStack = {}

SlapStack.id = "SlapStack"
SlapStack.minSeats = 2
SlapStack.maxSeats = 6

SlapStack.FLIP_LIMIT = 1000
SlapStack.COLLECT_SECONDS = 1.2 -- the last chance to slap before a challenge is collected
SlapStack.LAST_CHANCE_FLIPS = 3 -- flips the last player makes before winning (slap-in)
SlapStack.OUT_STRIKES = 3 -- bad slaps while out before you're out for good

local rank = PlayingCards.rank

-- Tries the next player gets for each face card (nil = not a face card).
local TRIES = { [1] = 4, [11] = 1, [12] = 2, [13] = 3 }
SlapStack.TRIES = TRIES

function SlapStack.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= 2 and seatCount <= 6, "Slap Stack needs 2-6 seats")
	local random = rng or Random.new()
	local deck = PlayingCards.newDeck(random)
	local piles = {}
	for seat = 1, seatCount do
		piles[seat] = {}
	end
	-- 52 doesn't always split evenly; the first seats get the extra cards.
	for i, id in deck do
		table.insert(piles[(i - 1) % seatCount + 1], id)
	end
	local rules = if options and type(options.rules) == "table" then options.rules else {}
	return {
		seatCount = seatCount,
		rng = random,
		piles = piles, -- piles[seat]: top card is the last one
		center = {}, -- the middle pile: top card is the last one
		turn = 1,
		challenge = nil, -- { owner, tries, face }: the current face-card challenge
		collect = nil, -- seat about to take the pile (a challenge was won)
		phaseId = 0,
		flips = 0,
		lastAction = nil,
		winners = nil,
		reason = nil,
		sandwich = rules.sandwich ~= false,
		penalty = if rules.penalty == 2 then 2 else 1,
		topBottom = rules.topBottom == true,
		marriage = rules.marriage == true,
		tens = rules.tens == true,
		run = rules.run == true,
		slapIn = rules.slapIn ~= "never",
		under = {}, -- burned cards, face down under the pile (they go with it)
		slapIns = {}, -- slapIns[seat] = slap-ins used
		strikes = {}, -- strikes[seat] = bad slaps while out
		lockout = {}, -- lockout[seat] = flips count at their last bad slap
		lastChance = nil, -- flips left for the last player holding cards
		botLevel = (options and options.botLevel) or "medium",
	}
end

local function count(state, seat: number): number
	return #state.piles[seat]
end

local function nextWithCards(state, seat: number): number?
	for i = 1, state.seatCount do
		local s = (seat - 1 + i) % state.seatCount + 1
		if count(state, s) > 0 then
			return s
		end
	end
	return nil
end

-- Is there a good slap on the pile right now?
function SlapStack.canSlap(state): boolean
	local c = state.center
	local n = #c
	if n >= 2 and rank(c[n]) == rank(c[n - 1]) then
		return true
	end
	if state.sandwich and n >= 3 and rank(c[n]) == rank(c[n - 2]) then
		return true
	end
	if state.topBottom and n >= 3 and rank(c[n]) == rank(c[1]) then
		return true
	end
	if n >= 2 then
		local a, b = rank(c[n]), rank(c[n - 1])
		if state.marriage and ((a == 12 and b == 13) or (a == 13 and b == 12)) then
			return true
		end
		if state.tens and a <= 10 and b <= 10 and a + b == 10 then
			return true
		end
		-- Tens across one face card (Bicycle): A K 9.
		if state.tens and n >= 3 and b >= 11 then
			local c3 = rank(c[n - 2])
			if a <= 10 and c3 <= 10 and a + c3 == 10 then
				return true
			end
		end
	end
	-- Four in a row, up or down (K-A-2 wraps).
	if state.run and n >= 4 then
		for _, step in { 1, -1 } do
			local ok = true
			for i = 0, 2 do
				if (rank(c[n - i - 1]) - 1 + step) % 13 + 1 ~= rank(c[n - i]) then
					ok = false
					break
				end
			end
			if ok then
				return true
			end
		end
	end
	return false
end

-- Can this seat slap right now? Out of cards: only while a slap-in is left.
function SlapStack.canSlapIn(state, seat: number): boolean
	if not state.slapIn or #state.piles[seat] > 0 then
		return false
	end
	return (state.slapIns[seat] or 0) < 1 and (state.strikes[seat] or 0) < SlapStack.OUT_STRIKES
end

local function mayReach(state, seat: number): boolean
	return #state.piles[seat] > 0 or SlapStack.canSlapIn(state, seat)
end

-- May this seat slap now? Not twice between flips, and during the last-chance flips only
-- the players who are out slap.
local function maySlap(state, seat: number): boolean
	if (state.lockout[seat] or -1) >= state.flips then
		return false
	end
	if state.holder ~= nil and #state.piles[seat] > 0 then
		return false
	end
	return mayReach(state, seat)
end

-- Still in the game: holds cards, or is about to win a challenge.
local function inGame(state, seat: number): boolean
	return count(state, seat) > 0
		or state.collect == seat
		or state.holder == seat
		or (state.challenge ~= nil and state.challenge.owner == seat)
end

local take

local function checkEnd(state)
	local alive = {}
	for seat = 1, state.seatCount do
		if inGame(state, seat) then
			table.insert(alive, seat)
		end
	end
	if #alive == 1 then
		local seat = alive[1]
		local hopefuls = false
		for s = 1, state.seatCount do
			if s ~= seat and SlapStack.canSlapIn(state, s) then
				hopefuls = true
			end
		end
		if hopefuls then
			-- Anyone who can still slap in gets 3 last-chance flips (then one beat) first.
			if state.lastChance == nil then
				if count(state, seat) == 0 then
					take(state, seat)
				end
				state.lastChance = SlapStack.LAST_CHANCE_FLIPS
				state.holder = seat
				state.challenge = nil
				state.collect = nil
				state.turn = seat
				state.phaseId += 1
			end
			if (state.lastChance == 0 or count(state, seat) == 0) and not state.finalBeat then
				-- The last flip is down: one beat to slap it, then it's over.
				state.finalBeat = true
				state.phaseId += 1
			end
			return
		end
		-- Last one left takes whatever is in the middle.
		for _, id in state.center do
			table.insert(state.piles[seat], 1, id)
		end
		for _, id in state.under do
			table.insert(state.piles[seat], 1, id)
		end
		state.center = {}
		state.under = {}
		state.collect = nil
		state.challenge = nil
		state.lastChance = nil
		state.finalBeat = nil
		state.holder = nil
		state.winners = alive
		state.reason = "Won every card"
	elseif #alive == 0 then
		state.winners = {}
		state.reason = "Nobody has cards"
	elseif state.flips >= SlapStack.FLIP_LIMIT then
		local best, top = {}, -1
		for seat = 1, state.seatCount do
			local n = count(state, seat)
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

-- `seat` takes the middle pile (it goes under their own pile) and flips next.
function take(state, seat: number)
	for i = #state.center, 1, -1 do
		table.insert(state.piles[seat], 1, state.center[i])
	end
	for _, id in state.under do
		table.insert(state.piles[seat], 1, id)
	end
	state.center = {}
	state.under = {}
	state.challenge = nil
	state.collect = nil
	state.lastChance = nil
	state.finalBeat = nil
	state.holder = nil
	state.turn = seat
	state.phaseId += 1
end

-- Only the flipper is on the turn clock; everyone else slaps out of turn, so a person who
-- looks away is flipped for, never slapped for.
function SlapStack.getActiveSeats(state): { number }
	if state.winners or state.collect or state.finalBeat or count(state, state.turn) == 0 then
		return {}
	end
	return { state.turn }
end

function SlapStack.getInterruptSeats(state): { number }
	local out = {}
	if state.winners then
		return out
	end
	local active = SlapStack.getActiveSeats(state)
	for seat = 1, state.seatCount do
		if not table.find(active, seat) and mayReach(state, seat) then
			table.insert(out, seat)
		end
	end
	return out
end

-- The moves worth making: a good slap, or a flip on your turn. (A bad slap is allowed
-- too, it just costs a card.)
function SlapStack.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if state.winners or not mayReach(state, seat) then
		return moves
	end
	if SlapStack.canSlap(state) and maySlap(state, seat) then
		table.insert(moves, { kind = "slap" })
	end
	if count(state, seat) > 0 and seat == state.turn and not state.collect and not state.finalBeat then
		table.insert(moves, { kind = "flip" })
	end
	return moves
end

function SlapStack.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.winners then
		return false, "The game is over"
	end
	if type(move) ~= "table" then
		return false, "Bad move"
	end
	if move.kind == "flip" then
		if count(state, seat) == 0 then
			return false, "You're out of cards"
		end
		if seat ~= state.turn then
			return false, "It's not your turn to flip"
		end
		if state.collect or state.finalBeat then
			return false, "The pile is being collected"
		end
		return true
	elseif move.kind == "slap" then
		if not mayReach(state, seat) then
			return false, "You're out of cards"
		end
		if #state.center == 0 then
			return false, "Nothing to slap"
		end
		if (state.lockout[seat] or -1) >= state.flips then
			return false, "Wait for the next card"
		end
		if not maySlap(state, seat) then
			return false, "Only players who are out can slap now"
		end
		return true
	end
	return false, "Bad move"
end

function SlapStack.applyMove(state, seat: number, move: any)
	if move.kind == "slap" then
		if SlapStack.canSlap(state) then
			local n = #state.center + #state.under
			local slappedIn = count(state, seat) == 0
			if slappedIn then
				state.slapIns[seat] = (state.slapIns[seat] or 0) + 1
			end
			state.lastAction = { kind = "slap", seat = seat, count = n, slapIn = slappedIn or nil }
			take(state, seat)
		elseif count(state, seat) == 0 then
			-- A bad slap while out: a strike (three and you're out for good).
			state.strikes[seat] = (state.strikes[seat] or 0) + 1
			state.lockout[seat] = state.flips
			state.lastAction = { kind = "badSlap", seat = seat, count = 0, strike = state.strikes[seat] }
		else
			-- Bad slap: one card (two with the house rule) is burned face down under the pile,
			-- and you can't slap again until the next card is flipped.
			local burned = nil
			local n = 0
			for _ = 1, state.penalty or 1 do
				if count(state, seat) == 0 then
					break
				end
				burned = table.remove(state.piles[seat]) :: number
				table.insert(state.under, burned)
				n += 1
			end
			state.lockout[seat] = state.flips
			state.lastAction = { kind = "badSlap", seat = seat, count = n }
			if count(state, seat) == 0 and state.turn == seat and not state.collect then
				if state.challenge then
					-- Out of cards while answering a challenge: the challenger wins it.
					state.collect = state.challenge.owner
					state.challenge = nil
					state.phaseId += 1
				else
					state.turn = nextWithCards(state, seat) or seat
				end
			end
		end
		checkEnd(state)
		return
	end

	-- Flip.
	local card = table.remove(state.piles[seat]) :: number
	table.insert(state.center, card)
	state.flips += 1
	state.lastAction = { kind = "flip", seat = seat, card = card }
	if state.lastChance then
		-- Last-chance flips: no challenges, just cards for the others to slap in on.
		state.lastChance -= 1
		state.lastAction.lastChance = state.lastChance
		checkEnd(state)
		return
	end
	local tries = TRIES[rank(card)]
	if tries then
		state.challenge = { owner = seat, tries = tries, face = rank(card) }
		state.turn = nextWithCards(state, seat) or seat
	elseif state.challenge then
		state.challenge.tries -= 1
		if state.challenge.tries <= 0 or count(state, seat) == 0 then
			state.collect = state.challenge.owner
			state.challenge = nil
			state.phaseId += 1
		end
	else
		state.turn = nextWithCards(state, seat) or seat
	end
	checkEnd(state)
end

function SlapStack.getTimer(state): { id: number, seconds: number }?
	if (state.collect or state.finalBeat) and not state.winners then
		return { id = state.phaseId, seconds = SlapStack.COLLECT_SECONDS }
	end
	return nil
end

function SlapStack.onTimeout(state)
	if state.finalBeat then
		-- Nobody slapped in on the last chance: the last player wins.
		for s = 1, state.seatCount do
			if count(state, s) == 0 then
				state.strikes[s] = SlapStack.OUT_STRIKES
			end
		end
		state.finalBeat = nil
		checkEnd(state)
		return
	end
	if state.collect then
		local seat = state.collect
		state.lastAction = { kind = "collect", seat = seat, count = #state.center }
		take(state, seat)
		checkEnd(state)
	end
end

function SlapStack.getResult(state): GameModule.Result?
	if not state.winners then
		return nil
	end
	return { winners = table.clone(state.winners), isDraw = #state.winners ~= 1, reason = state.reason }
end

function SlapStack.getView(state, seat: number?)
	local counts = {}
	for s = 1, state.seatCount do
		counts[s] = count(state, s)
	end
	local top = {}
	for i = math.max(1, #state.center - 2), #state.center do
		table.insert(top, state.center[i])
	end
	return {
		pileCounts = counts,
		top = top, -- up to the top 3 cards, newest last
		centerCount = #state.center,
		turn = state.turn,
		challenge = GameModule.copy(state.challenge),
		collect = state.collect,
		sandwich = state.sandwich,
		topBottom = state.topBottom,
		marriage = state.marriage,
		tens = state.tens,
		run = state.run,
		lastAction = GameModule.copy(state.lastAction),
		flips = state.flips,
		underCount = #state.under,
		lastChance = state.lastChance,
		finalBeat = state.finalBeat,
		slapIn = state.slapIn,
		-- Out of cards: can you still slap back in?
		canSlapIn = if seat then SlapStack.canSlapIn(state, seat) else false,
		lockedOut = seat ~= nil and (state.lockout[seat] or -1) >= state.flips,
		holder = state.holder,
	}
end

function SlapStack.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		local n = count(state, seat)
		info[seat] = if n > 0 then `{n} cards` elseif SlapStack.canSlapIn(state, seat) then "Out · can slap in" else "Out"
	end
	return info
end

function SlapStack.getScores(state): { [number]: number }
	local scores = {}
	for seat = 1, state.seatCount do
		scores[seat] = count(state, seat)
	end
	return scores
end

-- Bots ------------------------------------------------------------------------
-- Levels differ by reaction time; easy and medium bots also miss some patterns, and easy
-- ones now and then slap a near miss (and burn a card for it).

local REACTION = { easy = { 1.3, 0.9 }, medium = { 0.75, 0.5 }, hard = { 0.42, 0.35 } }
local MISS = { easy = 0.3, medium = 0.1, hard = 0 }
local BAD_SLAP = { easy = 0.02, medium = 0.005, hard = 0 }

function SlapStack.getBotDelay(state, seat: number, rng: Random): number
	if SlapStack.canSlap(state) then
		local r = REACTION[state.botLevel] or REACTION.medium
		return r[1] + rng:NextNumber() * r[2]
	end
	if seat == state.turn then
		return 0.7 + rng:NextNumber() * 0.5
	end
	return 0.4
end

function SlapStack.chooseBotMove(state, seat: number, rng: Random): any?
	if state.winners or not mayReach(state, seat) then
		return nil
	end
	local level = state.botLevel
	-- One look each time the table changes: sometimes a bot just doesn't see it.
	if SlapStack.canSlap(state) and maySlap(state, seat) then
		if rng:NextNumber() >= (MISS[level] or 0) then
			return { kind = "slap" }
		end
	elseif count(state, seat) > 0 and #state.center >= 2 and maySlap(state, seat) and rng:NextNumber() < (BAD_SLAP[level] or 0) then
		return { kind = "slap" }
	end
	if count(state, seat) > 0 and seat == state.turn and not state.collect and not state.finalBeat then
		return { kind = "flip" }
	end
	return nil
end

-- A person who looked away is flipped for on their turn, and never slaps.
function SlapStack.chooseAfkMove(state, seat: number, _rng: Random): any?
	if state.winners or seat ~= state.turn or count(state, seat) == 0 or state.collect or state.finalBeat then
		return nil
	end
	return { kind = "flip" }
end

return SlapStack
