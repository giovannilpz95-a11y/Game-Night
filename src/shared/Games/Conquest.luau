--[[
	Conquest Isles: a world-conquest strategy game for 2-6 seats on our own map, the
	Shattered Isles (24 territories in 6 regions). Pure rules, see shared/GameModule.luau.

	A turn:
	  1. reinforce  Get max(3, territories / 3) armies plus the bonus of every region you
	                hold whole. Trade sets of 3 cards for more (you must while holding 5+).
	                Place them on your own territories.
	  2. attack     Attack a neighbour from a territory with 2+ armies. The attacker rolls up
	                to 3 dice (one less than its armies), the defender up to 2. Highest dice
	                are compared in pairs; ties go to the defender. "Blitz" keeps rolling
	                until the territory falls or you're down to 1 army.
	     occupy     After a conquest, choose how many armies move in (at least the number
	                of dice you rolled) when there's a choice.
	  3. end        Either end the turn, or make one move of armies between two of your
	                territories joined by your own land, which also ends the turn.
	Conquer at least one territory in a turn to draw a card. Knock a player out and you
	take their cards (with 6+ you trade right away).

	Speed rules so a game fits in 20-30 minutes: territories and starting armies are dealt
	automatically, card sets have fixed values, attacks can blitz, each turn has a clock,
	and after Conquest.roundsFor(seats) rounds the player with the most territories wins.

	The map is data (regions, territories, links) so new maps are a content swap.
]]

local GameModule = require(script.Parent.Parent.GameModule)

local Conquest = {}

Conquest.id = "Conquest"
Conquest.minSeats = 2
Conquest.maxSeats = 6

Conquest.TURN_SECONDS = 90 -- the whole turn, not each move (house rule "turnLength" can change it)
Conquest.HAND_LIMIT = 5 -- holding this many cards forces a trade
Conquest.LOG_SIZE = 8

-- Rounds before the game is scored, by seat count. Tuned so most games take 20-30 min.
local ROUNDS = { [2] = 20, [3] = 16, [4] = 14, [5] = 11, [6] = 9 }
function Conquest.roundsFor(seats: number): number
	return ROUNDS[seats] or 12
end

-- Most territories one player may take in a turn, by round. Stops an early runaway
-- (one player sweeping half the map in the first rounds) so games reach the limit.
function Conquest.conquestLimit(round: number): number
	if round <= 2 then
		return 1
	elseif round <= 5 then
		return 2
	end
	return 3
end

-- Starting armies per player (one goes on each territory, the rest are spread at random).
local STARTING_ARMIES = { [2] = 30, [3] = 24, [4] = 20, [5] = 17, [6] = 15 }

---------------------------------------------------------------------------------------
-- The map: the Shattered Isles. x/y are 0..1 positions on a 3:2 map; labelX/labelY is
-- where a region's name sits (in open sea next to it).

Conquest.mapName = "The Shattered Isles"

Conquest.regions = {
	{ name = "Frostreach", bonus = 1, color = Color3.fromRGB(172, 214, 240), labelX = 0.15, labelY = 0.11 },
	{ name = "Sunspire Sands", bonus = 2, color = Color3.fromRGB(236, 204, 120), labelX = 0.63, labelY = 0.07 },
	{ name = "Heartwood", bonus = 2, color = Color3.fromRGB(116, 184, 104), labelX = 0.43, labelY = 0.24 },
	{ name = "Ironcoast", bonus = 1, color = Color3.fromRGB(156, 156, 172), labelX = 0.15, labelY = 0.91 },
	{ name = "Coral Keys", bonus = 1, color = Color3.fromRGB(122, 214, 204), labelX = 0.56, labelY = 0.93 },
	{ name = "Emberfall", bonus = 1, color = Color3.fromRGB(226, 116, 84), labelX = 0.87, labelY = 0.76 },
}

Conquest.territories = {
	-- Frostreach
	{ name = "Icefang", region = 1, x = 0.147, y = 0.204 },
	{ name = "Snowmere", region = 1, x = 0.285, y = 0.172 },
	{ name = "Glacier Gate", region = 1, x = 0.165, y = 0.364 },
	{ name = "Whitepine", region = 1, x = 0.302, y = 0.316 },
	-- Sunspire Sands
	{ name = "Oasis", region = 2, x = 0.560, y = 0.292 },
	{ name = "Dunehold", region = 2, x = 0.629, y = 0.164 },
	{ name = "Mirage Wells", region = 2, x = 0.767, y = 0.180 },
	{ name = "Sandstone", region = 2, x = 0.853, y = 0.316 },
	{ name = "Scorpion Pass", region = 2, x = 0.706, y = 0.348 },
	-- Heartwood
	{ name = "Elder Grove", region = 3, x = 0.431, y = 0.388 },
	{ name = "Mossbrook", region = 3, x = 0.543, y = 0.468 },
	{ name = "Thornwick", region = 3, x = 0.448, y = 0.572 },
	{ name = "Fernhollow", region = 3, x = 0.337, y = 0.484 },
	-- Ironcoast
	{ name = "Gullrock", region = 4, x = 0.216, y = 0.548 },
	{ name = "Anchor Bay", region = 4, x = 0.122, y = 0.636 },
	{ name = "Rustport", region = 4, x = 0.259, y = 0.708 },
	{ name = "Saltcliff", region = 4, x = 0.147, y = 0.812 },
	-- Coral Keys
	{ name = "Turtle Key", region = 5, x = 0.380, y = 0.780 },
	{ name = "Pearl Lagoon", region = 5, x = 0.491, y = 0.716 },
	{ name = "Shellbeach", region = 5, x = 0.577, y = 0.828 },
	-- Emberfall
	{ name = "Obsidian Bay", region = 6, x = 0.646, y = 0.588 },
	{ name = "Ashpeak", region = 6, x = 0.784, y = 0.500 },
	{ name = "Cinder Vale", region = 6, x = 0.870, y = 0.668 },
	{ name = "Lava Falls", region = 6, x = 0.732, y = 0.772 },
}

-- Borders. `sea = true` marks a sea lane (drawn dashed-looking and thinner).
Conquest.links = {
	-- Frostreach
	{ 1, 2 }, { 1, 3 }, { 2, 4 }, { 3, 4 },
	-- Sunspire Sands
	{ 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 9 }, { 9, 5 }, { 6, 9 },
	-- Heartwood
	{ 10, 11 }, { 10, 13 }, { 11, 12 }, { 12, 13 }, { 10, 12 },
	-- Ironcoast
	{ 14, 15 }, { 14, 16 }, { 15, 16 }, { 15, 17 }, { 16, 17 },
	-- Coral Keys
	{ 18, 19 }, { 19, 20 }, { 18, 20 },
	-- Emberfall
	{ 21, 22 }, { 22, 23 }, { 23, 24 }, { 24, 21 },
	-- Between regions
	{ 4, 10 }, { 4, 13 }, { 3, 14 }, { 2, 6, sea = true },
	{ 5, 10 }, { 5, 11 }, { 9, 22 }, { 8, 22 },
	{ 11, 21 }, { 12, 19 }, { 13, 14 },
	{ 16, 18 }, { 17, 18, sea = true },
	{ 19, 21 }, { 20, 24 },
}

Conquest.neighbors = {} :: { [number]: { number } }
Conquest.regionMembers = {} :: { [number]: { number } }
do
	for t = 1, #Conquest.territories do
		Conquest.neighbors[t] = {}
	end
	for _, link in Conquest.links do
		table.insert(Conquest.neighbors[link[1]], link[2])
		table.insert(Conquest.neighbors[link[2]], link[1])
	end
	for r = 1, #Conquest.regions do
		Conquest.regionMembers[r] = {}
	end
	for t, territory in Conquest.territories do
		table.insert(Conquest.regionMembers[territory.region], t)
	end
end
local TERRITORY_COUNT = #Conquest.territories

function Conquest.areNeighbors(a: number, b: number): boolean
	return table.find(Conquest.neighbors[a], b) ~= nil
end

---------------------------------------------------------------------------------------
-- Cards. Three of a kind or one of each trades for armies; a wild stands in for any.

Conquest.cardKinds = { "sword", "shield", "crown" }
Conquest.cardNames = { sword = "Sword", shield = "Shield", crown = "Crown", wild = "Wild" }
Conquest.setValues = { sword = 3, shield = 4, crown = 5, mixed = 6 }
local CARDS_PER_KIND = 8
local WILD_CARDS = 2

-- Value of trading these three card kinds, or nil if they aren't a set.
function Conquest.setValue(kinds: { string }): number?
	if #kinds ~= 3 then
		return nil
	end
	local counts = { sword = 0, shield = 0, crown = 0, wild = 0 }
	for _, kind in kinds do
		if counts[kind] == nil then
			return nil
		end
		counts[kind] += 1
	end
	local best = nil
	-- Three of a kind (wilds fill in)
	for _, kind in Conquest.cardKinds do
		if counts[kind] + counts.wild == 3 then
			best = math.max(best or 0, Conquest.setValues[kind])
		end
	end
	-- One of each (wilds fill the gaps)
	local distinct = 0
	for _, kind in Conquest.cardKinds do
		if counts[kind] > 1 then
			distinct = -99
		elseif counts[kind] == 1 then
			distinct += 1
		end
	end
	if distinct >= 0 and distinct + counts.wild == 3 then
		best = math.max(best or 0, Conquest.setValues.mixed)
	end
	return best
end

-- The best set in a hand: (indices, value) or nil.
function Conquest.bestSet(hand: { string }): ({ number }?, number?)
	local bestIdx, bestValue = nil, nil
	for i = 1, #hand - 2 do
		for j = i + 1, #hand - 1 do
			for k = j + 1, #hand do
				local value = Conquest.setValue({ hand[i], hand[j], hand[k] })
				if value and (bestValue == nil or value > bestValue) then
					bestIdx, bestValue = { i, j, k }, value
				end
			end
		end
	end
	return bestIdx, bestValue
end

---------------------------------------------------------------------------------------
-- Helpers that work on any { owner, armies } pair (the client uses them on its view too).

function Conquest.countOwned(owner: { number }, seat: number): number
	local n = 0
	for t = 1, TERRITORY_COUNT do
		if owner[t] == seat then
			n += 1
		end
	end
	return n
end

-- Owner of a whole region, or nil.
function Conquest.regionOwner(owner: { number }, region: number): number?
	local first = nil
	for _, t in Conquest.regionMembers[region] do
		if first == nil then
			first = owner[t]
		elseif owner[t] ~= first then
			return nil
		end
	end
	return first
end

-- Catch-up: holding fewer territories than the average player still in the game.
Conquest.RALLY_ARMIES = 2

function Conquest.isRallying(owner: { number }, seat: number): boolean
	local counts = {}
	local players = 0
	for t = 1, TERRITORY_COUNT do
		local o = owner[t]
		if counts[o] == nil then
			counts[o] = 0
			players += 1
		end
		counts[o] += 1
	end
	local mine = counts[seat] or 0
	return mine > 0 and mine * players < TERRITORY_COUNT
end

function Conquest.income(owner: { number }, seat: number): number
	local armies = math.max(3, Conquest.countOwned(owner, seat) // 3)
	for r, region in Conquest.regions do
		if Conquest.regionOwner(owner, r) == seat then
			armies += region.bonus
		end
	end
	if Conquest.isRallying(owner, seat) then
		armies += Conquest.RALLY_ARMIES
	end
	return armies
end

-- Are a and b joined by a path through `seat`'s own territories?
function Conquest.connected(owner: { number }, seat: number, a: number, b: number): boolean
	if owner[a] ~= seat or owner[b] ~= seat then
		return false
	end
	local seen = { [a] = true }
	local queue = { a }
	local head = 1
	while queue[head] do
		local t = queue[head]
		head += 1
		if t == b then
			return true
		end
		for _, n in Conquest.neighbors[t] do
			if not seen[n] and owner[n] == seat then
				seen[n] = true
				table.insert(queue, n)
			end
		end
	end
	return false
end

local function hasEnemyNeighbor(owner: { number }, t: number): boolean
	for _, n in Conquest.neighbors[t] do
		if owner[n] ~= owner[t] then
			return true
		end
	end
	return false
end
Conquest.hasEnemyNeighbor = hasEnemyNeighbor

---------------------------------------------------------------------------------------
-- State

local function shuffle(list: { any }, rng: Random)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

-- Log lines name players by seat: the client puts "<seat name> " in front of the text
-- and swaps "{target}" for the other seat's name.
local function log(state, text: string, seat: number?, target: number?)
	table.insert(state.log, { text = text, seat = seat, target = target })
	while #state.log > Conquest.LOG_SIZE do
		table.remove(state.log, 1)
	end
end

local function territoryName(t: number): string
	return Conquest.territories[t].name
end

local function startTurn(state)
	local seat = state.turn
	state.phase = "reinforce"
	state.reinforcements = Conquest.income(state.owner, seat)
	state.conqueredThisTurn = false
	state.conquestsThisTurn = 0
	state.occupy = nil
	state.turnId += 1
end

function Conquest.new(seatCount: number, options: any?, rng: Random?)
	options = options or {}
	local random = rng or Random.new()
	local level = if type(options.botLevel) == "string" then options.botLevel else "medium"
	local rules = if type(options.rules) == "table" then options.rules else {}
	local turnSeconds = Conquest.TURN_SECONDS
	if type(rules.turnLength) == "number" and rules.turnLength > 0 then
		turnSeconds = rules.turnLength
	end

	local state = {
		seats = seatCount,
		turnSeconds = turnSeconds,
		rng = random,
		botLevel = level,
		owner = table.create(TERRITORY_COUNT, 0),
		armies = table.create(TERRITORY_COUNT, 0),
		hands = {},
		deck = {},
		discard = {},
		eliminated = {},
		turn = 1,
		round = 1,
		maxRounds = Conquest.roundsFor(seatCount),
		phase = "reinforce",
		reinforcements = 0,
		conqueredThisTurn = false,
		conquestsThisTurn = 0,
		occupy = nil,
		lastBattle = nil,
		turnId = 0,
		log = {},
		result = nil,
	}
	for seat = 1, seatCount do
		state.hands[seat] = {}
		state.eliminated[seat] = false
	end

	-- Deal territories evenly (the first seats get any spares).
	local order = {}
	for t = 1, TERRITORY_COUNT do
		order[t] = t
	end
	shuffle(order, random)
	for i, t in order do
		local seat = (i - 1) % seatCount + 1
		state.owner[t] = seat
		state.armies[t] = 1
	end
	-- Later seats got fewer territories, so they're dealt from the back: even it out by
	-- giving every seat the same number of armies.
	local total = STARTING_ARMIES[seatCount] or 15
	for seat = 1, seatCount do
		local mine = {}
		for t = 1, TERRITORY_COUNT do
			if state.owner[t] == seat then
				table.insert(mine, t)
			end
		end
		for _ = 1, total - #mine do
			local t = mine[random:NextInteger(1, #mine)]
			state.armies[t] += 1
		end
	end

	for _, kind in Conquest.cardKinds do
		for _ = 1, CARDS_PER_KIND do
			table.insert(state.deck, kind)
		end
	end
	for _ = 1, WILD_CARDS do
		table.insert(state.deck, "wild")
	end
	shuffle(state.deck, random)

	startTurn(state)
	log(state, `{Conquest.mapName}: {state.maxRounds} rounds. Most territories wins!`)
	return state
end

function Conquest.getActiveSeats(state): { number }
	if state.result then
		return {}
	end
	return { state.turn }
end

local function aliveSeats(state): { number }
	local out = {}
	for seat = 1, state.seats do
		if not state.eliminated[seat] then
			table.insert(out, seat)
		end
	end
	return out
end

local function totalArmies(state, seat: number): number
	local n = 0
	for t = 1, TERRITORY_COUNT do
		if state.owner[t] == seat then
			n += state.armies[t]
		end
	end
	return n
end

-- Ends the game on the round limit: most territories, then most armies.
local function scoreGame(state)
	local best = {}
	local bestKey = -1
	for _, seat in aliveSeats(state) do
		local key = Conquest.countOwned(state.owner, seat) * 1000 + totalArmies(state, seat)
		if key > bestKey then
			best, bestKey = { seat }, key
		elseif key == bestKey then
			table.insert(best, seat)
		end
	end
	state.result = {
		winners = best,
		isDraw = #best > 1,
		reason = `Most territories after {state.maxRounds} rounds`,
	}
	state.phase = "over"
end

local function endTurn(state)
	local seat = state.turn
	if state.conqueredThisTurn then
		if #state.deck == 0 then
			state.deck, state.discard = state.discard, {}
			shuffle(state.deck, state.rng)
		end
		local card = table.remove(state.deck)
		if card then
			table.insert(state.hands[seat], card)
		end
	end
	local nextSeat = seat
	repeat
		nextSeat = nextSeat % state.seats + 1
	until not state.eliminated[nextSeat] or nextSeat == seat
	if nextSeat <= seat then
		state.round += 1
		if state.round > state.maxRounds then
			scoreGame(state)
			return
		end
	end
	state.turn = nextSeat
	startTurn(state)
end

local function mustTrade(state, seat: number): boolean
	return #state.hands[seat] >= Conquest.HAND_LIMIT and Conquest.bestSet(state.hands[seat]) ~= nil
end

-- After placing or trading: move on to attacking once nothing is left to place.
local function checkReinforceDone(state)
	if state.phase == "reinforce" and state.reinforcements <= 0 and not mustTrade(state, state.turn) then
		state.phase = "attack"
	end
end

local function isInt(v: any, lo: number, hi: number): boolean
	return type(v) == "number" and v == v and v % 1 == 0 and v >= lo and v <= hi
end

---------------------------------------------------------------------------------------
-- Moves

function Conquest.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.result then
		return false, "The game is over"
	end
	if seat ~= state.turn then
		return false, "It's not your turn"
	end
	if type(move) ~= "table" or type(move.kind) ~= "string" then
		return false, "Bad move"
	end
	local kind = move.kind
	local phase = state.phase

	if kind == "trade" then
		if phase ~= "reinforce" then
			return false, "Trade cards at the start of your turn"
		end
		local cards = move.cards
		if type(cards) ~= "table" or #cards ~= 3 then
			return false, "Pick 3 cards"
		end
		local hand = state.hands[seat]
		local kinds = {}
		local seen = {}
		for i = 1, 3 do
			local index = cards[i]
			if not isInt(index, 1, #hand) or seen[index] then
				return false, "Pick 3 different cards"
			end
			seen[index] = true
			kinds[i] = hand[index]
		end
		if not Conquest.setValue(kinds) then
			return false, "Those cards aren't a set"
		end
		return true
	elseif kind == "place" then
		if phase ~= "reinforce" then
			return false, "Nothing to place now"
		end
		if mustTrade(state, seat) then
			return false, `You have {#state.hands[seat]} cards: trade a set first`
		end
		if not isInt(move.territory, 1, TERRITORY_COUNT) or state.owner[move.territory] ~= seat then
			return false, "Place armies on your own territory"
		end
		if not isInt(move.count, 1, state.reinforcements) then
			return false, `You have {state.reinforcements} to place`
		end
		return true
	elseif kind == "attack" then
		if phase ~= "attack" then
			return false, "You can't attack now"
		end
		local from, to = move.from, move.to
		if not isInt(from, 1, TERRITORY_COUNT) or not isInt(to, 1, TERRITORY_COUNT) then
			return false, "Bad territory"
		end
		if state.owner[from] ~= seat then
			return false, "Attack from your own territory"
		end
		if state.owner[to] == seat then
			return false, "That's already yours"
		end
		if not Conquest.areNeighbors(from, to) then
			return false, "You can only attack a neighbour"
		end
		if state.armies[from] < 2 then
			return false, "You need at least 2 armies to attack"
		end
		local limit = Conquest.conquestLimit(state.round)
		if state.conquestsThisTurn >= limit then
			return false, if limit == 1 then "You can take 1 territory a turn this round" else `You can take {limit} territories a turn this round`
		end
		if move.blitz ~= nil and type(move.blitz) ~= "boolean" then
			return false, "Bad move"
		end
		return true
	elseif kind == "occupy" then
		if phase ~= "occupy" or not state.occupy then
			return false, "Nothing to move in"
		end
		if not isInt(move.count, state.occupy.min, state.occupy.max) then
			return false, `Move between {state.occupy.min} and {state.occupy.max}`
		end
		return true
	elseif kind == "fortify" then
		if phase ~= "attack" then
			return false, "You can't move armies now"
		end
		local from, to = move.from, move.to
		if not isInt(from, 1, TERRITORY_COUNT) or not isInt(to, 1, TERRITORY_COUNT) or from == to then
			return false, "Bad territory"
		end
		if not Conquest.connected(state.owner, seat, from, to) then
			return false, "Armies can only move through your own land"
		end
		if not isInt(move.count, 1, state.armies[from] - 1) then
			return false, "At least 1 army has to stay behind"
		end
		return true
	elseif kind == "endTurn" then
		if phase ~= "attack" then
			return false, if phase == "occupy" then "Move in first" else "Place your armies first"
		end
		return true
	end
	return false, "Unknown move"
end

local function rollDice(rng: Random, n: number): { number }
	local dice = {}
	for i = 1, n do
		dice[i] = rng:NextInteger(1, 6)
	end
	table.sort(dice, function(a, b)
		return a > b
	end)
	return dice
end

local function eliminate(state, loser: number, by: number)
	state.eliminated[loser] = true
	GameModule.addStat(state, by, "knockouts")
	for _, card in state.hands[loser] do
		table.insert(state.hands[by], card)
	end
	state.hands[loser] = {}
	log(state, "is knocked out!", loser)
	local alive = aliveSeats(state)
	if #alive == 1 then
		state.result = { winners = { alive[1] }, isDraw = false, reason = "Conquered the Shattered Isles" }
		state.phase = "over"
	end
end

-- The attacker took `to`: move armies in, now or after an occupy choice.
local function finishConquest(state, from: number, to: number, dice: number)
	local seat = state.turn
	local defender = state.owner[to]
	state.owner[to] = seat
	state.armies[to] = 0
	state.conqueredThisTurn = true
	state.conquestsThisTurn += 1
	if Conquest.countOwned(state.owner, defender) == 0 then
		eliminate(state, defender, seat)
		if state.result then
			-- Everyone else is gone: fill the last territory and stop.
			state.armies[to] = state.armies[from] - 1
			state.armies[from] = 1
			return
		end
	end
	local max = state.armies[from] - 1
	local min = math.min(dice, max)
	if max > min then
		state.phase = "occupy"
		state.occupy = { from = from, to = to, min = min, max = max }
	else
		state.armies[to] = max
		state.armies[from] -= max
		state.phase = "attack"
	end
	-- Took a knocked-out player's cards and now holds too many: trade right away.
	if state.phase == "attack" and #state.hands[seat] > Conquest.HAND_LIMIT then
		state.phase = "reinforce"
		state.reinforcements = 0
	end
end

function Conquest.applyMove(state, seat: number, move: any)
	local kind = move.kind
	if kind == "trade" then
		local hand = state.hands[seat]
		local kinds = { hand[move.cards[1]], hand[move.cards[2]], hand[move.cards[3]] }
		local value = Conquest.setValue(kinds) :: number
		local indices = { move.cards[1], move.cards[2], move.cards[3] }
		table.sort(indices, function(a, b)
			return a > b
		end)
		for _, index in indices do
			table.insert(state.discard, table.remove(hand, index))
		end
		state.reinforcements += value
		log(state, `traded cards for {value} armies`, seat)
		checkReinforceDone(state)
	elseif kind == "place" then
		state.armies[move.territory] += move.count
		state.reinforcements -= move.count
		checkReinforceDone(state)
	elseif kind == "attack" then
		local from, to = move.from, move.to
		local defender = state.owner[to]
		local battle = {
			attacker = seat,
			defender = defender,
			from = from,
			to = to,
			attackerLost = 0,
			defenderLost = 0,
			rolls = 0,
			blitz = move.blitz == true,
			conquered = false,
			attackDice = {},
			defendDice = {},
		}
		local lastDice = 1
		repeat
			local aCount = math.min(3, state.armies[from] - 1)
			local dCount = math.min(2, state.armies[to])
			local a = rollDice(state.rng, aCount)
			local d = rollDice(state.rng, dCount)
			for i = 1, math.min(aCount, dCount) do
				if a[i] > d[i] then
					state.armies[to] -= 1
					battle.defenderLost += 1
				else
					state.armies[from] -= 1
					battle.attackerLost += 1
				end
			end
			battle.rolls += 1
			battle.attackDice, battle.defendDice = a, d
			lastDice = aCount
		until not battle.blitz or state.armies[to] == 0 or state.armies[from] < 2
		state.lastBattle = battle
		if state.armies[to] == 0 then
			battle.conquered = true
			log(state, "took " .. territoryName(to) .. " from {target}", seat, defender)
			finishConquest(state, from, to, lastDice)
		elseif battle.blitz then
			log(state, `was held off at {territoryName(to)}`, seat)
		end
	elseif kind == "occupy" then
		local occupy = state.occupy
		state.armies[occupy.to] += move.count
		state.armies[occupy.from] -= move.count
		state.occupy = nil
		state.phase = "attack"
		if #state.hands[seat] > Conquest.HAND_LIMIT then
			state.phase = "reinforce"
			state.reinforcements = 0
		end
	elseif kind == "fortify" then
		state.armies[move.from] -= move.count
		state.armies[move.to] += move.count
		log(state, `moved {move.count} to {territoryName(move.to)}`, seat)
		endTurn(state)
	elseif kind == "endTurn" then
		endTurn(state)
	end
end

function Conquest.getResult(state)
	return state.result
end

---------------------------------------------------------------------------------------
-- Clock: the whole turn has one timer. When it runs out the turn finishes itself.

function Conquest.getTimer(state)
	if state.result then
		return nil
	end
	return { id = state.turnId, seconds = state.turnSeconds or Conquest.TURN_SECONDS }
end

-- Where leftover armies go when nobody chose: the most threatened border.
local function weakestBorder(state, seat: number): number?
	local best, bestScore = nil, -math.huge
	for t = 1, TERRITORY_COUNT do
		if state.owner[t] == seat then
			local threat = 0
			for _, n in Conquest.neighbors[t] do
				if state.owner[n] ~= seat then
					threat += state.armies[n]
				end
			end
			local score = if threat > 0 then threat - state.armies[t] else -1000 - state.armies[t]
			if score > bestScore then
				best, bestScore = t, score
			end
		end
	end
	return best
end

function Conquest.onTimeout(state)
	if state.result then
		return
	end
	local seat = state.turn
	log(state, "ran out of time", seat)
	if state.phase == "occupy" then
		Conquest.applyMove(state, seat, { kind = "occupy", count = state.occupy.min })
	end
	if state.phase == "reinforce" then
		while mustTrade(state, seat) do
			local set = Conquest.bestSet(state.hands[seat])
			Conquest.applyMove(state, seat, { kind = "trade", cards = set })
		end
		if state.reinforcements > 0 then
			local t = weakestBorder(state, seat)
			if t then
				Conquest.applyMove(state, seat, { kind = "place", territory = t, count = state.reinforcements })
			end
		end
	end
	if not state.result then
		state.phase = "attack"
		endTurn(state)
	end
end

---------------------------------------------------------------------------------------
-- Legal moves (bots fall back to these)

function Conquest.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if state.result or seat ~= state.turn then
		return moves
	end
	local phase = state.phase
	if phase == "reinforce" then
		local set = Conquest.bestSet(state.hands[seat])
		if set then
			table.insert(moves, { kind = "trade", cards = set })
		end
		if not mustTrade(state, seat) and state.reinforcements > 0 then
			for t = 1, TERRITORY_COUNT do
				if state.owner[t] == seat then
					table.insert(moves, { kind = "place", territory = t, count = state.reinforcements })
				end
			end
		end
	elseif phase == "occupy" then
		table.insert(moves, { kind = "occupy", count = state.occupy.min })
		table.insert(moves, { kind = "occupy", count = state.occupy.max })
	elseif phase == "attack" then
		local canAttack = state.conquestsThisTurn < Conquest.conquestLimit(state.round)
		for t = 1, TERRITORY_COUNT do
			if canAttack and state.owner[t] == seat and state.armies[t] >= 2 then
				for _, n in Conquest.neighbors[t] do
					if state.owner[n] ~= seat then
						table.insert(moves, { kind = "attack", from = t, to = n, blitz = true })
					end
				end
			end
		end
		table.insert(moves, { kind = "endTurn" })
	end
	return moves
end

---------------------------------------------------------------------------------------
-- View

-- Header text for the seat whose turn it is. Others see "<name> is thinking...".
local function seatStatus(state, seat: number?): string?
	if state.result then
		return "Game over"
	end
	local who = state.turn
	local roundText = `Round {state.round}/{state.maxRounds}`
	if seat == who then
		if state.phase == "reinforce" then
			if mustTrade(state, who) then
				return `{roundText} · You have {#state.hands[who]} cards: trade a set`
			end
			return `{roundText} · Place {state.reinforcements} armies`
		elseif state.phase == "occupy" then
			return `{roundText} · Move armies into {territoryName(state.occupy.to)}`
		end
		return `{roundText} · Attack, move armies, or end your turn`
	end
	return nil
end

function Conquest.getView(state, seat: number?)
	local handCounts = {}
	for s = 1, state.seats do
		handCounts[s] = #state.hands[s]
	end
	local log = {}
	for i, entry in state.log do
		log[i] = { text = entry.text, seat = entry.seat, target = entry.target }
	end
	local battle = nil
	if state.lastBattle then
		battle = table.clone(state.lastBattle)
		battle.attackDice = table.clone(state.lastBattle.attackDice)
		battle.defendDice = table.clone(state.lastBattle.defendDice)
	end
	local occupy = if state.occupy then table.clone(state.occupy) else nil
	return {
		owner = table.clone(state.owner),
		armies = table.clone(state.armies),
		turn = state.turn,
		round = state.round,
		maxRounds = state.maxRounds,
		phase = state.phase,
		reinforcements = state.reinforcements,
		occupy = occupy,
		lastBattle = battle,
		eliminated = table.clone(state.eliminated),
		handCounts = handCounts,
		hand = if seat and state.hands[seat] then table.clone(state.hands[seat]) else nil,
		mustTrade = if seat == state.turn then mustTrade(state, state.turn) else false,
		turnId = state.turnId,
		conquestsLeft = math.max(0, Conquest.conquestLimit(state.round) - state.conquestsThisTurn),
		rallying = if seat then Conquest.isRallying(state.owner, seat) else false,
		log = log,
		status = seatStatus(state, seat),
	}
end

function Conquest.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seats do
		if state.eliminated[seat] then
			info[seat] = "Knocked out"
		else
			info[seat] = `{Conquest.countOwned(state.owner, seat)} lands · {totalArmies(state, seat)} armies · {#state.hands[seat]} 🃏`
		end
	end
	return info
end

function Conquest.getScores(state): { [number]: number }
	local scores = {}
	for seat = 1, state.seats do
		scores[seat] = Conquest.countOwned(state.owner, seat)
	end
	return scores
end

---------------------------------------------------------------------------------------
-- Bots

function Conquest.getBotDelay(state, _seat: number, rng: Random): number
	-- Slow enough that people can follow each attack on the map.
	if state.phase == "reinforce" then
		return 0.8 + rng:NextNumber() * 0.3
	end
	return 1.0 + rng:NextNumber() * 0.4
end

local function threatOn(state, t: number): number
	local seat = state.owner[t]
	local threat = 0
	for _, n in Conquest.neighbors[t] do
		if state.owner[n] ~= seat then
			threat += state.armies[n]
		end
	end
	return threat
end

-- The region a bot is trying to take: the one it holds most of (that isn't whole yet).
local function focusRegion(state, seat: number): number?
	local best, bestScore = nil, -math.huge
	for r, members in Conquest.regionMembers do
		local mine, theirArmies = 0, 0
		for _, t in members do
			if state.owner[t] == seat then
				mine += 1
			else
				theirArmies += state.armies[t]
			end
		end
		if mine > 0 and mine < #members then
			local score = mine / #members * 10 - theirArmies * 0.4 + Conquest.regions[r].bonus * 0.5
			if score > bestScore then
				best, bestScore = r, score
			end
		end
	end
	return best
end

local function botPlace(state, seat: number, rng: Random): any
	local level = state.botLevel
	local borders = {}
	for t = 1, TERRITORY_COUNT do
		if state.owner[t] == seat and hasEnemyNeighbor(state.owner, t) then
			table.insert(borders, t)
		end
	end
	if #borders == 0 then
		return nil
	end
	if level == "easy" then
		local t = borders[rng:NextInteger(1, #borders)]
		return { kind = "place", territory = t, count = rng:NextInteger(1, state.reinforcements) }
	end
	local focus = focusRegion(state, seat)
	local best, bestScore = borders[1], -math.huge
	for _, t in borders do
		local score = state.armies[t] * 0.3
		for _, n in Conquest.neighbors[t] do
			if state.owner[n] ~= seat and Conquest.territories[n].region == focus then
				score += 6
				break
			end
		end
		-- Hard bots guard regions they already hold.
		local region = Conquest.territories[t].region
		if level == "hard" and Conquest.regionOwner(state.owner, region) == seat then
			local gap = threatOn(state, t) - state.armies[t]
			if gap > 0 then
				score += 4 + gap * 0.5
			end
		end
		if score > bestScore then
			best, bestScore = t, score
		end
	end
	return { kind = "place", territory = best, count = state.reinforcements }
end

local function botAttack(state, seat: number, rng: Random): any?
	if state.conquestsThisTurn >= Conquest.conquestLimit(state.round) then
		return nil
	end
	local level = state.botLevel
	local focus = if level ~= "easy" then focusRegion(state, seat) else nil
	local threshold = if level == "hard" then 1.25 elseif level == "medium" then 1.5 else 1.0
	local best, bestScore = nil, -math.huge
	for from = 1, TERRITORY_COUNT do
		if state.owner[from] == seat and state.armies[from] >= 2 then
			for _, to in Conquest.neighbors[from] do
				local enemy = state.owner[to]
				if enemy ~= seat then
					local ratio = (state.armies[from] - 1) / state.armies[to]
					local score = ratio
					local region = Conquest.territories[to].region
					if region == focus then
						score += 0.6
					end
					if level == "hard" then
						if Conquest.regionOwner(state.owner, region) == enemy then
							score += 0.5 -- break their bonus
						end
						if Conquest.countOwned(state.owner, enemy) <= 2 then
							score += 0.8 -- knock them out for their cards
						end
					end
					local wanted = ratio >= threshold and state.armies[from] >= 3
					-- Grab one territory a turn for a card when the odds are fair.
					if not state.conqueredThisTurn and level ~= "easy" and ratio >= 1 and state.armies[from] >= 3 then
						wanted = true
					end
					if level == "easy" then
						wanted = ratio >= threshold and rng:NextNumber() < 0.6
					end
					if wanted and score > bestScore then
						best, bestScore = { kind = "attack", from = from, to = to, blitz = true }, score
					end
				end
			end
		end
	end
	return best
end

local function botFortify(state, seat: number): any?
	-- Move the biggest stack stuck inside to the most threatened border it can reach.
	local from, fromArmies = nil, 1
	for t = 1, TERRITORY_COUNT do
		if state.owner[t] == seat and state.armies[t] > fromArmies and not hasEnemyNeighbor(state.owner, t) then
			from, fromArmies = t, state.armies[t]
		end
	end
	if not from then
		return nil
	end
	local to, toScore = nil, -math.huge
	for t = 1, TERRITORY_COUNT do
		if t ~= from and state.owner[t] == seat and hasEnemyNeighbor(state.owner, t) and Conquest.connected(state.owner, seat, from, t) then
			local score = threatOn(state, t) - state.armies[t]
			if score > toScore then
				to, toScore = t, score
			end
		end
	end
	if not to then
		return nil
	end
	return { kind = "fortify", from = from, to = to, count = fromArmies - 1 }
end

function Conquest.chooseBotMove(state, seat: number, rng: Random): any?
	if state.result or seat ~= state.turn then
		return nil
	end
	local level = state.botLevel
	local phase = state.phase
	if phase == "reinforce" then
		local set = Conquest.bestSet(state.hands[seat])
		if set and (level ~= "easy" or mustTrade(state, seat)) then
			return { kind = "trade", cards = set }
		end
		return botPlace(state, seat, rng)
	elseif phase == "occupy" then
		local occupy = state.occupy
		if not hasEnemyNeighbor(state.owner, occupy.from) then
			return { kind = "occupy", count = occupy.max }
		end
		if level == "easy" then
			return { kind = "occupy", count = rng:NextInteger(occupy.min, occupy.max) }
		end
		local count = math.max(occupy.min, math.ceil(occupy.max * 0.66))
		return { kind = "occupy", count = math.min(count, occupy.max) }
	elseif phase == "attack" then
		local attack = botAttack(state, seat, rng)
		if attack then
			return attack
		end
		if level ~= "easy" then
			local fortify = botFortify(state, seat)
			if fortify then
				return fortify
			end
		end
		return { kind = "endTurn" }
	end
	return nil
end

return Conquest
