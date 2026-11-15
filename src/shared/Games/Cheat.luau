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
-- House rule "twoDecksAt": with that many seats or more (6 by default) two decks are
-- shuffled together, as the official rules suggest for big tables.
--
-- House rule "upDown" (up, down or same): instead of the next rank in order, each play
-- may claim the same rank as the last claim, or one above or below it. The very first play
-- is still Aces.
-- House rule "anyRank" (Chinese style): whoever leads names any rank, and everyone follows
-- it until a doubt; then the next leader names a new one.
-- House rule "allowPass": pass instead of playing. If everyone passes in a row, the pile is
-- set aside and the next player leads fresh.
-- House rule "discardFours": four of a kind in your hand (dealt or picked up) is put aside.
-- House rule "rounds" (1, 3 or 5): penalty points per round (first out 0, the next fewest
-- cards 1, the most cards 3, everyone else 2); after the last round fewest points wins.
--
-- Moves:
--   { kind = "play", cards = { id, ... }, claim = rank? }  (your turn: 1-4 cards, claimed
--       as the called rank; with upDown, claim picks one of Cheat.claims)
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
Cheat.TWO_DECKS_AT = 6 -- seats; house rule "twoDecksAt" (0 = never)
Cheat.ROUND_SECONDS = 5 -- the pause between rounds

local rank = PlayingCards.rank

-- Deals a round: the whole deck (or two) out to everyone.
local function dealRound(state)
	local deck = PlayingCards.newDeck(state.rng, nil, state.decks)
	for seat = 1, state.seatCount do
		state.hands[seat] = {}
	end
	local start = (state.round - 1) % state.seatCount
	for i, id in deck do
		table.insert(state.hands[(i - 1 + start) % state.seatCount + 1], id)
	end
	state.pile = {}
	state.pileFrom = {}
	state.called = if state.anyRank then nil else 1
	state.turn = start + 1
	state.phase = "play"
	state.phaseId += 1
	state.lastPlay = nil
	state.lastCards = nil
	state.passed = {}
	state.reveal = nil
	state.passes = 0
	state.plays = 0
	state.discards = {}
	if state.discardFours then
		for seat = 1, state.seatCount do
			Cheat._discardFours(state, seat)
		end
	end
end

function Cheat.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= 3 and seatCount <= 8, "I Doubt It needs 3-8 seats")
	local random = rng or Random.new()
	local rules = if options and type(options.rules) == "table" then options.rules else {}
	local at = if type(rules.twoDecksAt) == "number" then rules.twoDecksAt else Cheat.TWO_DECKS_AT
	local decks = if at > 0 and seatCount >= at then 2 else 1
	local points = {}
	for seat = 1, seatCount do
		points[seat] = 0
	end
	local state = {
		seatCount = seatCount,
		decks = decks,
		rng = random,
		hands = {},
		pile = {}, -- face down, newest last
		pileFrom = {}, -- pileFrom[i] = who put pile[i] down (bots remember their own cards)
		called = 1, -- the rank the next play must claim (1 = Aces; nil = the leader names it)
		turn = 1,
		phase = "play", -- "play" | "doubt" | "reveal" | "roundOver"
		phaseId = 1,
		lastPlay = nil, -- { seat, count, rank }: public
		lastCards = nil, -- the real cards of the last play: hidden until doubted
		passed = {}, -- passed[seat] = true in the doubt phase
		reveal = nil, -- { seat, doubter, cards, honest, loser, count }
		plays = 0,
		passes = 0, -- turns passed in a row (allowPass)
		winners = nil,
		reason = nil,
		upDown = rules.upDown == true,
		anyRank = rules.anyRank == true,
		allowPass = rules.allowPass == true,
		discardFours = rules.discardFours == true,
		discards = {}, -- ranks put aside as four of a kind: { seat, rank }
		rounds = if rules.rounds == 3 or rules.rounds == 5 then rules.rounds else 1,
		round = 1,
		points = points,
		roundResult = nil,
		doubtSeconds = if type(rules.doubtSeconds) == "number" and rules.doubtSeconds > 0 then rules.doubtSeconds else Cheat.DOUBT_SECONDS,
		botLevel = (options and options.botLevel) or "medium",
	}
	dealRound(state)
	return state
end

-- Four of a kind is put aside (house rule).
function Cheat._discardFours(state, seat: number)
	local counts = PlayingCards.rankCounts(state.hands[seat])
	for r, n in counts do
		while n >= 4 do
			local drop = 4
			local keep = {}
			for _, id in state.hands[seat] do
				if rank(id) == r and drop > 0 then
					drop -= 1
				else
					table.insert(keep, id)
				end
			end
			state.hands[seat] = keep
			table.insert(state.discards, { seat = seat, rank = r })
			n -= 4
		end
	end
end

-- Ranks the next play may claim: the called rank, plus one above and one below with the
-- "up, down or same" house rule (Kings and Aces wrap around).
function Cheat.claims(state): { number }
	local c = state.called
	if c == nil then
		-- The leader names any rank (house rule "anyRank").
		local all = {}
		for r = 1, 13 do
			table.insert(all, r)
		end
		return all
	end
	if not state.upDown or state.plays == 0 then
		return { c }
	end
	return { (c - 2) % 13 + 1, c, c % 13 + 1 }
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
	Cheat._endRound(state, best, "Fewest cards left")
end

-- A round is over: one round ends the game; with "rounds", score penalty points by place
-- (first out 0, the next fewest cards 1, the most cards 3, everyone else 2).
function Cheat._endRound(state, first: { number }, reason: string)
	if state.rounds <= 1 then
		state.winners = first
		state.reason = reason
		return
	end
	local order = {}
	for seat = 1, state.seatCount do
		table.insert(order, seat)
	end
	table.sort(order, function(a, b)
		local fa, fb = table.find(first, a) ~= nil, table.find(first, b) ~= nil
		if fa ~= fb then
			return fa
		end
		if #state.hands[a] ~= #state.hands[b] then
			return #state.hands[a] < #state.hands[b]
		end
		return a < b
	end)
	local added = {}
	local most = #state.hands[order[#order]]
	for i, seat in order do
		local pts
		if table.find(first, seat) then
			pts = 0
		elseif #state.hands[seat] == most then
			pts = 3
		elseif i == #first + 1 then
			pts = 1
		else
			pts = 2
		end
		added[seat] = pts
		state.points[seat] += pts
	end
	state.roundResult = { round = state.round, first = table.clone(first), added = added, reason = reason }
	if state.round >= state.rounds then
		local best, low = {}, math.huge
		for seat = 1, state.seatCount do
			local p = state.points[seat]
			if p < low then
				best, low = { seat }, p
			elseif p == low then
				table.insert(best, seat)
			end
		end
		state.winners = best
		state.reason = `Fewest points after {state.rounds} rounds`
		return
	end
	state.phase = "roundOver"
	state.phaseId += 1
end

-- Play moves on to the next player, the next rank is called.
local function advance(state)
	local player = state.lastPlay.seat
	if #state.hands[player] == 0 then
		Cheat._endRound(state, { player }, "Got rid of every card")
		return
	end
	if state.plays >= Cheat.PLAY_LIMIT then
		fewestCards(state)
		return
	end
	if state.anyRank then
		-- Follow the named rank until a doubt; after one, the next player leads fresh.
		state.called = if state.reveal then nil else state.lastPlay.rank
	elseif state.upDown then
		state.called = state.lastPlay.rank
	else
		state.called = (state.called or state.lastPlay.rank) % 13 + 1
	end
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
	local before = #state.discards
	if state.discardFours then
		Cheat._discardFours(state, loser)
	end
	state.reveal = {
		seat = player,
		doubter = doubter,
		cards = table.clone(state.lastCards),
		honest = honest,
		loser = loser,
		count = count,
		discarded = if #state.discards > before then state.discards[#state.discards].rank else nil,
	}
	state.phase = "reveal"
	state.phaseId += 1
	-- An honest last play wins on the spot.
	if honest and #state.hands[player] == 0 then
		Cheat._endRound(state, { player }, "Got rid of every card")
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
		if state.allowPass and state.lastPlay ~= nil and state.called ~= nil then
			table.insert(moves, { kind = "pass" })
		end
		local hand = state.hands[seat]
		for _, claim in Cheat.claims(state) do
			local honest = {}
			for _, id in hand do
				table.insert(moves, { kind = "play", cards = { id }, claim = claim })
				if rank(id) == claim then
					table.insert(honest, id)
				end
			end
			while #honest > Cheat.MAX_CARDS do
				table.remove(honest)
			end
			if #honest > 1 then
				table.insert(moves, { kind = "play", cards = honest, claim = claim })
			end
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
	if state.phase == "roundOver" then
		return false, "Next round coming up"
	end
	if move.kind == "pass" and state.phase == "play" then
		if seat ~= state.turn then
			return false, "It's not your turn"
		end
		if not state.allowPass then
			return false, "You have to play"
		end
		if state.lastPlay == nil or state.called == nil then
			return false, "You're leading: play something"
		end
		return true
	end
	if move.kind == "play" then
		if state.phase ~= "play" or seat ~= state.turn then
			return false, "It's not your turn"
		end
		if not PlayingCards.isCardList(move.cards, Cheat.MAX_CARDS, state.decks) then
			return false, "Play 1 to 4 cards"
		end
		if not PlayingCards.holdsAll(state.hands[seat], move.cards) then
			return false, "Those cards aren't in your hand"
		end
		if move.claim ~= nil and not table.find(Cheat.claims(state), move.claim) then
			return false, "You can't claim that rank now"
		end
		if move.claim == nil and state.called == nil then
			return false, "Name a rank"
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
	if move.kind == "pass" and state.phase == "play" then
		state.passes += 1
		state.lastPass = seat
		if state.passes >= state.seatCount then
			-- Everyone passed: the pile is set aside and the next player leads fresh.
			state.pile = {}
			state.pileFrom = {}
			state.passes = 0
			state.called = if state.anyRank then nil else (state.called :: number) % 13 + 1
		end
		state.turn = nextSeat(state, seat)
		state.phaseId += 1
		return
	end
	if move.kind == "play" then
		state.passes = 0
		state.lastPass = nil
		PlayingCards.removeCards(state.hands[seat], move.cards)
		state.pileFrom = state.pileFrom or {}
		for _, id in move.cards do
			table.insert(state.pile, id)
			state.pileFrom[#state.pile] = seat
		end
		state.plays += 1
		state.lastPlay = { seat = seat, count = #move.cards, rank = if move.claim ~= nil then move.claim else state.called :: number }
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
	elseif state.phase == "roundOver" then
		return { id = state.phaseId, seconds = Cheat.ROUND_SECONDS }
	end
	return nil
end

function Cheat.onTimeout(state)
	if state.phase == "doubt" or state.phase == "reveal" then
		advance(state)
	elseif state.phase == "roundOver" and not state.winners then
		state.round += 1
		dealRound(state)
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
	-- The header during a doubt window: everyone may act, so it would say "Your turn!"
	-- to all of them. It says what the moment is instead.
	local status: string? = nil
	if state.phase == "doubt" and seat and state.lastPlay then
		status = if seat == state.lastPlay.seat then "Waiting to see if anyone doubts you..."
			elseif state.passed[seat] then "You believed it · waiting..."
			else "Doubt it or believe it?"
	end
	return {
		status = status,
		hand = if seat and state.hands[seat] then PlayingCards.sortHand(state.hands[seat]) else nil,
		handCounts = counts,
		pileCount = #state.pile,
		called = state.called,
		claims = Cheat.claims(state),
		turn = state.turn,
		phase = state.phase,
		lastPlay = GameModule.copy(state.lastPlay),
		reveal = GameModule.copy(state.reveal),
		passed = passed,
		doubtSeconds = state.doubtSeconds,
		decks = state.decks,
		anyRank = state.anyRank,
		allowPass = state.allowPass,
		passes = state.passes,
		lastPass = state.lastPass,
		discards = GameModule.copy(state.discards),
		rounds = state.rounds,
		round = state.round,
		points = table.clone(state.points),
		roundResult = GameModule.copy(state.roundResult),
		-- Your next ranks in the plain order (every seatCount-th rank), to plan bluffs.
		yourNext = if seat and not state.anyRank and not state.upDown and state.called then Cheat._nextRanks(state, seat) else nil,
	}
end

-- The ranks you'll be asked for on your next turns (plain order only).
function Cheat._nextRanks(state, seat: number): { number }
	local out = {}
	local steps = (seat - state.turn) % state.seatCount
	local r = ((state.called :: number) - 1 + steps) % 13 + 1
	for _ = 1, 3 do
		table.insert(out, r)
		r = (r - 1 + state.seatCount) % 13 + 1
	end
	return out
end

function Cheat.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		local n = #state.hands[seat]
		info[seat] = `{n} {if n == 1 then "card" else "cards"}`
		if state.rounds > 1 then
			info[seat] = `{state.points[seat]} pts · ` .. info[seat]
		end
	end
	return info
end

function Cheat.getScores(state): { [number]: number }
	local scores = {}
	for seat = 1, state.seatCount do
		scores[seat] = if state.rounds > 1 then -state.points[seat] else -#state.hands[seat]
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
	if wanted == nil then
		return 0
	end
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
	local perRank = 4 * (state.decks or 1)
	if known + count > perRank then
		return 0
	end
	local left = perRank - known -- of that rank, somewhere we can't see
	local unseen = math.max(1, 52 * (state.decks or 1) - seen)
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
		-- Up, down or same (or leading with any rank): claim the allowed rank we hold most of.
		local claim, most = state.called or rank(hand[1]), -1
		for _, r in Cheat.claims(state) do
			local n = 0
			for _, id in hand do
				if rank(id) == r then
					n += 1
				end
			end
			if n > most or (n == most and r == state.called) then
				claim, most = r, n
			end
		end
		local honest, others = {}, {}
		for _, id in hand do
			if rank(id) == claim then
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
			while #cards > Cheat.MAX_CARDS do -- two decks can hold up to 8 of a rank
				table.remove(cards)
			end
			-- Sometimes slip in one extra card with the honest ones.
			local sneak = if level == "hard" then 0.3 elseif level == "medium" then 0.15 else 0
			if #cards < Cheat.MAX_CARDS and #others > 0 and smallPile and rng:NextNumber() < sneak then
				table.insert(cards, chooseBluff(state, others, rng))
			end
			return { kind = "play", cards = cards, claim = claim }
		end
		-- No honest card and a big pile: pass if the table allows it.
		if state.allowPass and state.lastPlay ~= nil and state.called ~= nil and level ~= "easy" and #state.pile >= 4 and rng:NextNumber() < 0.7 then
			return { kind = "pass" }
		end
		local first = chooseBluff(state, hand, rng)
		local cards = { first }
		if #hand > 2 and level ~= "easy" and smallPile and rng:NextNumber() < 0.25 then
			local rest = table.clone(hand)
			table.remove(rest, table.find(rest, first) :: number)
			table.insert(cards, chooseBluff(state, rest, rng))
		end
		return { kind = "play", cards = cards, claim = claim }
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
