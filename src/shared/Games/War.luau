-- War: the classic luck-of-the-flip card game for 2-4 seats.
--
-- The deck is dealt out face down. Each battle, every player still in flips their top
-- card (all at once). Highest rank wins all the flipped cards; Aces are high.
-- A tie for highest starts a war: the tied players each put up to 3 cards face down and
-- flip one more, and the highest of those takes everything. Wars can chain.
-- Won cards go to the bottom of the winner's pile (shuffled, so games don't loop).
-- A player with no cards is out. Last one holding cards wins. Classic War can run very
-- long, so after BATTLE_LIMIT battles whoever holds the most cards wins.
--
-- Moves: { kind = "flip" }. Every player still in must flip before the battle resolves;
-- slow players are flipped for by the turn timer.

local GameModule = require(script.Parent.Parent.GameModule)
local PlayingCards = require(script.Parent.Parent.Cards.PlayingCards)

local War = {}

War.id = "War"
War.minSeats = 2
War.maxSeats = 4

War.BATTLE_LIMIT = 60
local WAR_FACE_DOWN = 3

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
	local perSeat = #deck // seatCount
	for i = 1, perSeat * seatCount do
		table.insert(piles[(i - 1) % seatCount + 1], deck[i])
	end
	return {
		seatCount = seatCount,
		rng = random,
		piles = piles, -- piles[seat][1] is the top card
		flipped = {}, -- seats that flipped this battle
		battles = 0,
		lastBattle = nil,
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
	if state.battles >= War.BATTLE_LIMIT then
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

-- Everyone flipped: play out the battle (and any wars) in one go.
local function resolve(state)
	local pot = {}
	local battle = { flips = {}, wars = 0, winner = nil }
	local contenders = seatsIn(state)
	while true do
		local best, bestPower = {}, -1
		local flips = {}
		for _, seat in contenders do
			local card = table.remove(state.piles[seat], 1)
			if card then
				table.insert(pot, card)
				flips[seat] = card
				local p = power(card)
				if p > bestPower then
					best, bestPower = { seat }, p
				elseif p == bestPower then
					table.insert(best, seat)
				end
			end
		end
		battle.flips = flips
		if #best <= 1 then
			battle.winner = best[1]
			break
		end
		-- War between the tied players. Each needs at least one card left to flip;
		-- a player who can't keep going drops out of this war.
		battle.wars += 1
		local next = {}
		for _, seat in best do
			local pile = state.piles[seat]
			local down = math.min(WAR_FACE_DOWN, #pile - 1)
			for _ = 1, down do
				table.insert(pot, table.remove(pile, 1) :: number)
			end
			if #pile > 0 then
				table.insert(next, seat)
			end
		end
		if #next == 0 then
			-- Every tied player is out of cards: the pot goes to nobody.
			break
		end
		if #next == 1 then
			battle.winner = next[1]
			break
		end
		contenders = next
	end
	battle.potSize = #pot
	if battle.winner then
		PlayingCards.shuffle(pot, state.rng)
		for _, card in pot do
			table.insert(state.piles[battle.winner], card)
		end
	end
	state.battles += 1
	state.flipped = {}
	state.lastBattle = battle
	checkEnd(state)
end

function War.getActiveSeats(state): { number }
	if state.winners then
		return {}
	end
	local out = {}
	for _, seat in seatsIn(state) do
		if not state.flipped[seat] then
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
	if type(move) ~= "table" or move.kind ~= "flip" then
		return false, "Bad move"
	end
	if not inGame(state, seat) then
		return false, "You're out of cards"
	end
	if state.flipped[seat] then
		return false, "Waiting for the others to flip"
	end
	return true
end

function War.applyMove(state, seat: number, _move: any)
	state.flipped[seat] = true
	if #War.getActiveSeats(state) == 0 then
		resolve(state)
	end
end

function War.getResult(state): GameModule.Result?
	if not state.winners then
		return nil
	end
	return { winners = table.clone(state.winners), isDraw = #state.winners ~= 1, reason = state.reason }
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
		local flips = {}
		for s, card in battle.flips do
			flips[tostring(s)] = card
		end
		battle.flips = flips
	end
	return {
		pileCounts = counts,
		flipped = flipped,
		battles = state.battles,
		battleLimit = War.BATTLE_LIMIT,
		lastBattle = battle,
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

function War.getBotDelay(state, _seat: number, rng: Random): number
	-- Bots flip quickly so a battle feels snappy; a little jitter keeps it human.
	return 0.6 + rng:NextNumber() * 0.6
end

function War.chooseBotMove(_state, _seat: number, _rng: Random): any?
	return { kind = "flip" }
end

return War
