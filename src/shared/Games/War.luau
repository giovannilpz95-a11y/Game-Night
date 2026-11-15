-- War: the classic luck-of-the-flip card game for 2-4 seats.
--
-- The deck is dealt out face down. Each battle, every player still in flips their top
-- card. Highest rank wins all the flipped cards; Aces are high.
-- A tie for highest starts a war, as its own step so everyone sees it: the tied players
-- each put up to 3 cards face down, then flip one more, and the highest of those takes
-- everything. Wars can chain. A player whose last card tied keeps it face up as their war
-- card (Pagat), so they can still win.
-- Won cards go to the bottom of the winner's pile (shuffled, so games don't loop).
-- A player with no cards is out. Last one holding cards wins. Classic War can run very
-- long, so after the host's battle limit (200 by default, or none) the most cards wins.
--
-- House rules (options.rules): faceDown (cards put down in a war: 1, 2 or 3), peace (lowest
-- card wins; a tie spells P-E-A-C-E: 4 down, the 5th decides), allIn (everyone still in
-- joins a war, not just the tied players), battleLimit (0 = no limit).
--
-- Moves: { kind = "flip" } when it's your flip. { kind = "auto", on = bool } any time:
-- auto-flip flips for you after a short beat.

local GameModule = require(script.Parent.Parent.GameModule)
local PlayingCards = require(script.Parent.Parent.Cards.PlayingCards)

local War = {}

War.id = "War"
War.minSeats = 2
War.maxSeats = 4

War.BATTLE_LIMIT = 200
War.AUTO_SECONDS = 0.9
local WAR_FACE_DOWN = 3
local PEACE_FACE_DOWN = 4

-- War order: 2 low ... King, Ace high.
local function power(id: number): number
	local r = PlayingCards.rank(id)
	return if r == 1 then 14 else r
end
War.power = power

function War.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= 2 and seatCount <= 4, "War needs 2-4 seats")
	local random = rng or Random.new()
	local deck = PlayingCards.newDeck(random)
	local piles = {}
	for seat = 1, seatCount do
		piles[seat] = {}
	end
	-- 52 doesn't split evenly three ways; the extra card is put aside.
	local rules = if options and type(options.rules) == "table" then options.rules else {}
	local perSeat = #deck // seatCount
	for i = 1, perSeat * seatCount do
		table.insert(piles[(i - 1) % seatCount + 1], deck[i])
	end
	local peace = rules.peace == true
	local faceDown = if rules.faceDown == 1 or rules.faceDown == 2 then rules.faceDown else WAR_FACE_DOWN
	return {
		seatCount = seatCount,
		rng = random,
		piles = piles, -- piles[seat][1] is the top card
		flipped = {}, -- seats that flipped this round
		flips = {}, -- [seat] = card flipped this round
		rounds = {}, -- earlier rounds of this battle (the tie, then each war)
		pot = {}, -- every card in the middle right now
		war = nil, -- { seats, carry = { [seat] = card }, wars } while a war is on
		auto = {}, -- [seat] = true: auto-flip
		phaseId = 0,
		battles = 0,
		faceDown = if peace then PEACE_FACE_DOWN else faceDown,
		peace = peace,
		allIn = rules.allIn == true,
		battleLimit = if type(rules.battleLimit) == "number" and rules.battleLimit >= 0 then rules.battleLimit else War.BATTLE_LIMIT,
		lastBattle = nil,
		lastAction = nil,
		winners = nil,
		reason = nil,
		botLevel = (options and options.botLevel) or "medium",
	}
end

local function inGame(state, seat: number): boolean
	return #state.piles[seat] > 0
end

local function seatsIn(state): { number }
	local out = {}
	for seat = 1, state.seatCount do
		if inGame(state, seat) then
			table.insert(out, seat)
		end
	end
	return out
end

local function checkEnd(state)
	local alive = seatsIn(state)
	if #alive == 1 then
		state.winners = alive
		state.reason = "Won every card"
		return
	end
	if #alive == 0 then
		-- Everyone ran out in the same war: nobody wins.
		state.winners = {}
		state.reason = "Everyone ran out of cards"
		return
	end
	local limit = state.battleLimit or War.BATTLE_LIMIT
	if limit > 0 and state.battles >= limit then
		local best, top = {}, -1
		for _, seat in alive do
			local n = #state.piles[seat]
			if n > top then
				best, top = { seat }, n
			elseif n == top then
				table.insert(best, seat)
			end
		end
		state.winners = best
		state.reason = "Time's up: most cards wins"
	end
end

-- Who flips this round: everyone still in, or the players in the war.
local function contenders(state): { number }
	if state.war then
		local out = {}
		for _, seat in state.war.seats do
			if inGame(state, seat) and not state.war.carry[seat] then
				table.insert(out, seat)
			end
		end
		return out
	end
	return seatsIn(state)
end

local function strength(state, card: number): number
	return if state.peace then 15 - power(card) else power(card)
end

local function finishBattle(state, winner: number?)
	local battle = {
		rounds = state.rounds,
		flips = state.flips,
		wars = if state.war then state.war.wars else 0,
		winner = winner,
		potSize = #state.pot,
	}
	table.insert(battle.rounds, state.flips)
	if winner then
		PlayingCards.shuffle(state.pot, state.rng)
		for _, card in state.pot do
			table.insert(state.piles[winner], card)
		end
	end
	state.pot = {}
	state.flips = {}
	state.rounds = {}
	state.flipped = {}
	state.war = nil
	state.battles += 1
	state.lastBattle = battle
	state.lastAction = { kind = "won", seat = winner, count = battle.potSize, wars = battle.wars }
	checkEnd(state)
end

-- Everyone in this round has flipped: settle it, or start (another) war.
local function settle(state)
	local best, bestPower = {}, -1
	local inRound = {}
	for seat, card in state.flips do
		inRound[seat] = card
	end
	if state.war then
		for seat, card in state.war.carry do
			inRound[seat] = card
		end
	end
	for seat, card in inRound do
		local p = strength(state, card)
		if p > bestPower then
			best, bestPower = { seat }, p
		elseif p == bestPower then
			table.insert(best, seat)
		end
	end
	table.sort(best)
	if #best <= 1 then
		finishBattle(state, best[1])
		return
	end
	-- A war. The tied players (or everyone, with the house rule) put cards face down;
	-- whoever has none left keeps the card they just showed as their war card.
	local seats = best
	if state.allIn then
		seats = {}
		for seat in inRound do
			table.insert(seats, seat)
		end
		table.sort(seats)
	end
	local carry = {}
	local flipping = 0
	for _, seat in seats do
		local pile = state.piles[seat]
		if #pile == 0 then
			carry[seat] = inRound[seat]
		else
			local down = math.min(state.faceDown or WAR_FACE_DOWN, #pile - 1)
			for _ = 1, down do
				table.insert(state.pot, table.remove(pile, 1) :: number)
			end
			flipping += 1
		end
	end
	local wars = (if state.war then state.war.wars else 0) + 1
	if flipping == 0 then
		-- Nobody can flip again. With others still in, the best of their cards takes the pot
		-- (they didn't tie, so it goes to the highest of the rest); otherwise nobody wins it.
		local rest, restPower = nil, -1
		for seat, card in inRound do
			if not table.find(seats, seat) and inGame(state, seat) and strength(state, card) > restPower then
				rest, restPower = seat, strength(state, card)
			end
		end
		if not state.war then
			state.war = { seats = seats, carry = carry, wars = wars }
		end
		state.war.wars = wars
		finishBattle(state, rest)
		return
	end
	table.insert(state.rounds, state.flips)
	state.flips = {}
	state.flipped = {}
	state.war = { seats = seats, carry = carry, wars = wars }
	state.lastAction = { kind = "war", seats = best, wars = wars }
end

local function flip(state, seat: number)
	local card = table.remove(state.piles[seat], 1) :: number
	table.insert(state.pot, card)
	state.flips[seat] = card
	state.flipped[seat] = true
	state.phaseId += 1
	state.lastAction = { kind = "flip", seat = seat, card = card }
	for _, s in contenders(state) do
		if not state.flipped[s] then
			return
		end
	end
	settle(state)
end

function War.getActiveSeats(state): { number }
	if state.winners then
		return {}
	end
	local out = {}
	for _, seat in contenders(state) do
		if not state.flipped[seat] then
			table.insert(out, seat)
		end
	end
	return out
end

-- Everyone else still in may switch auto-flip on or off.
function War.getInterruptSeats(state): { number }
	if state.winners then
		return {}
	end
	local active = War.getActiveSeats(state)
	local out = {}
	for _, seat in seatsIn(state) do
		if not table.find(active, seat) then
			table.insert(out, seat)
		end
	end
	return out
end

function War.getLegalMoves(state, seat: number): { any }
	if table.find(War.getActiveSeats(state), seat) then
		return { { kind = "flip" } }
	end
	return {}
end

function War.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.winners then
		return false, "The game is over"
	end
	if type(move) ~= "table" then
		return false, "Bad move"
	end
	if not inGame(state, seat) then
		return false, "You're out of cards"
	end
	if move.kind == "auto" then
		if type(move.on) ~= "boolean" then
			return false, "Bad move"
		end
		return true
	end
	if move.kind ~= "flip" then
		return false, "Bad move"
	end
	if not table.find(War.getActiveSeats(state), seat) then
		return false, if state.war then "Only the players in the war flip" else "Waiting for the others to flip"
	end
	return true
end

function War.applyMove(state, seat: number, move: any)
	if move.kind == "auto" then
		state.auto[seat] = if move.on then true else nil
		state.phaseId += 1
		return
	end
	flip(state, seat)
end

-- Auto-flip: a short beat, then everyone who switched it on flips.
function War.getTimer(state): { id: number, seconds: number }?
	if state.winners then
		return nil
	end
	for _, seat in War.getActiveSeats(state) do
		if state.auto[seat] then
			return { id = state.phaseId, seconds = War.AUTO_SECONDS }
		end
	end
	return nil
end

function War.onTimeout(state)
	for _, seat in War.getActiveSeats(state) do
		if state.auto[seat] and not state.winners and table.find(War.getActiveSeats(state), seat) then
			flip(state, seat)
		end
	end
end

function War.getResult(state): GameModule.Result?
	if not state.winners then
		return nil
	end
	return { winners = table.clone(state.winners), isDraw = #state.winners ~= 1, reason = state.reason }
end

local function seatMap(map: { [number]: number }?): { [string]: number }
	local out = {}
	for s, card in map or {} do
		out[tostring(s)] = card
	end
	return out
end

function War.getView(state, seat: number?)
	local counts = {}
	for s = 1, state.seatCount do
		counts[s] = #state.piles[s]
	end
	-- Seat-keyed maps use string keys: sparse number keys don't survive remotes.
	local flipped = {}
	for s in state.flipped do
		flipped[tostring(s)] = true
	end
	local battle = GameModule.copy(state.lastBattle)
	if battle then
		battle.flips = seatMap(battle.flips)
		local rounds = {}
		for i, round in battle.rounds or {} do
			rounds[i] = seatMap(round)
		end
		battle.rounds = rounds
	end
	local rounds = {}
	for i, round in state.rounds do
		rounds[i] = seatMap(round)
	end
	local war = nil
	if state.war then
		war = { seats = table.clone(state.war.seats), carry = seatMap(state.war.carry), wars = state.war.wars }
	end
	local downCount = #state.pot
	for _ in state.flips do
		downCount -= 1
	end
	for _, round in state.rounds do
		for _ in round do
			downCount -= 1
		end
	end
	return {
		pileCounts = counts,
		flipped = flipped,
		battles = state.battles,
		battleLimit = state.battleLimit or War.BATTLE_LIMIT, -- 0 = no limit
		peace = state.peace,
		faceDown = state.faceDown,
		allIn = state.allIn,
		lastBattle = battle,
		lastAction = GameModule.copy(state.lastAction),
		flips = seatMap(state.flips), -- this round so far
		rounds = rounds, -- earlier rounds of this battle
		war = war,
		potCount = #state.pot,
		faceDownCount = math.max(0, downCount),
		auto = seat ~= nil and state.auto[seat] == true,
		canFlip = seat ~= nil and table.find(War.getActiveSeats(state), seat) ~= nil,
	}
end

function War.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		local n = #state.piles[seat]
		info[seat] = if n == 0 then "Out" else `{n} cards`
	end
	return info
end

function War.getScores(state): { [number]: number }
	local scores = {}
	for seat = 1, state.seatCount do
		scores[seat] = #state.piles[seat]
	end
	return scores
end

function War.getBotDelay(state, seat: number, rng: Random): number
	if not table.find(War.getActiveSeats(state), seat) then
		return 0.5
	end
	-- Bots flip quickly so a battle feels snappy; a little jitter keeps it human. A war
	-- gets a beat longer, so everyone sees the tie first.
	return (if state.war then 1.1 else 0.6) + rng:NextNumber() * 0.6
end

function War.chooseBotMove(state, seat: number, _rng: Random): any?
	if table.find(War.getActiveSeats(state), seat) then
		return { kind = "flip" }
	end
	return nil
end

function War.chooseAfkMove(state, seat: number, _rng: Random): any?
	return War.chooseBotMove(state, seat, _rng)
end

return War
