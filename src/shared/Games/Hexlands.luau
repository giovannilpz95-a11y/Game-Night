-- Hexlands: an island-settling trading game for 2-4 seats (the "roll for resources, build
-- roads and towns, trade with friends" family), with our own names and look.
--
-- The island is 19 hexes in a 3-4-5-4-3 layout: 4 Forest (Lumber), 3 Clay Pits (Clay),
-- 4 Meadows (Wool), 4 Fields (Grain), 3 Quarries (Stone) and 1 Dunes. Number tokens 2-12
-- (no 7) go on the land with no two red numbers (6, 8) touching. Nine harbors sit on the
-- coast: four 3:1 and one 2:1 for each resource.
--
-- Setup: in snake order (1, 2, ... n, n, ... 2, 1) everyone places a camp and a road next
-- to it. Your second camp hands you one card per hex around it.
--
-- A turn: roll two dice; every hex with that number pays its corners (camp 1, town 2).
-- A 7 pays nothing: anyone holding more than 7 cards discards half, and the roller moves
-- the Bandit to a new hex (it stops that hex paying) and takes a random card from someone
-- next to it. Then trade (with players, or the bank at 4:1 or your harbor's rate) and build:
--   road = 1 Lumber + 1 Clay                camp = Lumber + Clay + Wool + Grain
--   town = 2 Grain + 3 Stone (upgrades a camp)   action card = Wool + Grain + Stone
-- Action cards: Guard (move the Bandit), Monument (1 point, hidden), Road Crew (2 free roads),
-- Harvest (any 2 cards from the bank), Hoard (everyone gives you all of one resource).
-- One action card a turn, not one bought this turn. Longest Road (5+) and Biggest Guard
-- (3+ Guards played) are worth 2 points each.
--
-- First to Hexlands.TARGET_POINTS on their own turn wins. After MAX_ROUNDS (by seat count)
-- the most points wins.
--
-- Moves (all tables, checked field by field in validateMove):
--   { kind = "place", vertex = v }             { kind = "road", edge = e }   (setup / Road Crew / build)
--   { kind = "camp", vertex = v }              { kind = "town", vertex = v }
--   { kind = "roll" }                          { kind = "endTurn" }
--   { kind = "buyCard" }
--   { kind = "play", card = "guard" | "roadcrew" | "harvest" | "hoard", res = { r1, r2 } | r }
--   { kind = "bandit", hex = h, victim = seat? }
--   { kind = "discard", cards = { [res] = n } }
--   { kind = "bank", give = res, get = res }
--   { kind = "offer", to = seat, give = { [res] = n }, get = { [res] = n } }
--   { kind = "accept" }  { kind = "reject" }   (the trade's target answers)
--   { kind = "doneRoads" }                     (stop using Road Crew early)

local GameModule = require(script.Parent.Parent.GameModule)

local Hexlands = {}

Hexlands.id = "Hexlands"
Hexlands.minSeats = 2
Hexlands.maxSeats = 4

Hexlands.TARGET_POINTS = 8
-- Round limit by seat count, to keep a match around 20-30 minutes. Most games end on
-- points first (bot tests: about 16 rounds with 4 seats, 26 with 2); otherwise the most
-- points wins when the limit is reached.
Hexlands.MAX_ROUNDS = { [2] = 40, [3] = 27, [4] = 20 } -- about the same number of turns each
Hexlands.BANK_EACH = 19
Hexlands.HAND_LIMIT = 7 -- more than this when a 7 is rolled: discard half
Hexlands.TRADES_PER_TURN = 3
Hexlands.PIECES = { road = 15, camp = 5, town = 4 }
local MOVE_LIMIT = 6000

-- Resources in display order. `key` is internal; `name` is what players see.
Hexlands.resources = {
	{ key = "lumber", name = "Lumber", land = "Forest", icon = "🌲", color = Color3.fromRGB(58, 130, 70) },
	{ key = "clay", name = "Clay", land = "Clay Pits", icon = "🧱", color = Color3.fromRGB(196, 98, 58) },
	{ key = "wool", name = "Wool", land = "Meadow", icon = "🐑", color = Color3.fromRGB(150, 210, 100) },
	{ key = "grain", name = "Grain", land = "Fields", icon = "🌾", color = Color3.fromRGB(236, 196, 70) },
	{ key = "stone", name = "Stone", land = "Quarry", icon = "⛏", color = Color3.fromRGB(140, 140, 155) },
}
Hexlands.DUNES = { name = "Dunes", icon = "🏜", color = Color3.fromRGB(226, 208, 150) }
local RES: { string } = {}
local isRes: { [string]: boolean } = {}
Hexlands.resourceInfo = {}
for _, r in Hexlands.resources do
	table.insert(RES, r.key)
	isRes[r.key] = true
	Hexlands.resourceInfo[r.key] = r
end
Hexlands.RES = RES

Hexlands.costs = {
	road = { lumber = 1, clay = 1 },
	camp = { lumber = 1, clay = 1, wool = 1, grain = 1 },
	town = { grain = 2, stone = 3 },
	card = { wool = 1, grain = 1, stone = 1 },
}

Hexlands.cards = {
	guard = { name = "Guard", text = "Move the Bandit and take a card. 3+ Guards played: Biggest Guard.", count = 14 },
	monument = { name = "Monument", text = "Worth 1 point. Kept secret until the game ends.", count = 5 },
	roadcrew = { name = "Road Crew", text = "Build 2 roads for free.", count = 2 },
	harvest = { name = "Harvest", text = "Take any 2 cards from the bank.", count = 2 },
	hoard = { name = "Hoard", text = "Name a resource: everyone gives you all of theirs.", count = 2 },
}
local CARD_ORDER = { "guard", "monument", "roadcrew", "harvest", "hoard" }
Hexlands.CARD_ORDER = CARD_ORDER

-- Dice odds as dots ("pips"): 6 and 8 are the best numbers.
local PIPS = { [2] = 1, [3] = 2, [4] = 3, [5] = 4, [6] = 5, [8] = 5, [9] = 4, [10] = 3, [11] = 2, [12] = 1 }
Hexlands.PIPS = PIPS

-- Geometry ----------------------------------------------------------------------
-- Pointy-top hexes in axial coordinates (q, r), radius 2. Positions are in hex-radius
-- units with y pointing down, so the renderer can draw straight from them.
local SQRT3 = math.sqrt(3)
local hexes = {} -- [h] = { q, r, x, y }
for r = -2, 2 do
	for q = -2, 2 do
		if math.abs(q + r) <= 2 then
			table.insert(hexes, { q = q, r = r, x = SQRT3 * (q + r / 2), y = 1.5 * r })
		end
	end
end

local vertices = {} -- [v] = { x, y, hexes = { h }, edges = { e }, near = { v } }
local edges = {} -- [e] = { a = v, b = v, hexes = { h } }
local hexVertices = {} -- [h] = { v x6 }, clockwise from the right-hand upper corner
local hexEdges = {} -- [h] = { e x6 }
do
	local vertexAt: { [string]: number } = {}
	local edgeAt: { [string]: number } = {}
	for h, hex in hexes do
		local corners = {}
		for i = 0, 5 do
			local angle = math.rad(60 * i - 30)
			local x, y = hex.x + math.cos(angle), hex.y + math.sin(angle)
			local key = `{math.floor(x * 100 + 0.5)},{math.floor(y * 100 + 0.5)}`
			local v = vertexAt[key]
			if not v then
				table.insert(vertices, { x = x, y = y, hexes = {}, edges = {}, near = {} })
				v = #vertices
				vertexAt[key] = v
			end
			table.insert(vertices[v].hexes, h)
			table.insert(corners, v)
		end
		hexVertices[h] = corners
		hexEdges[h] = {}
		for i = 1, 6 do
			local a, b = corners[i], corners[i % 6 + 1]
			local lo, hi = math.min(a, b), math.max(a, b)
			local key = `{lo}-{hi}`
			local e = edgeAt[key]
			if not e then
				table.insert(edges, { a = lo, b = hi, hexes = {} })
				e = #edges
				edgeAt[key] = e
				table.insert(vertices[lo].edges, e)
				table.insert(vertices[hi].edges, e)
				table.insert(vertices[lo].near, hi)
				table.insert(vertices[hi].near, lo)
			end
			table.insert(edges[e].hexes, h)
			table.insert(hexEdges[h], e)
		end
	end
end
Hexlands.hexes = hexes
Hexlands.vertices = vertices
Hexlands.edges = edges
Hexlands.hexVertices = hexVertices
Hexlands.hexEdges = hexEdges

-- Harbor slots: 9 coast edges spread evenly around the island (never sharing a corner).
local harborEdges: { number } = {}
do
	local coast = {}
	for e, edge in edges do
		if #edge.hexes == 1 then
			local a, b = vertices[edge.a], vertices[edge.b]
			table.insert(coast, { e = e, angle = math.atan2((a.y + b.y) / 2, (a.x + b.x) / 2) })
		end
	end
	table.sort(coast, function(x, y)
		return x.angle < y.angle
	end)
	for i = 1, 9 do
		table.insert(harborEdges, coast[math.floor((i - 1) * #coast / 9) + 1].e)
	end
end
Hexlands.harborEdges = harborEdges

local function otherEnd(e: number, v: number): number
	local edge = edges[e]
	return if edge.a == v then edge.b else edge.a
end

local function neighborsOfHex(h: number): { number }
	local out = {}
	local hex = hexes[h]
	for other, o in hexes do
		local dq, dr = o.q - hex.q, o.r - hex.r
		if other ~= h and math.max(math.abs(dq), math.abs(dr), math.abs(dq + dr)) == 1 then
			table.insert(out, other)
		end
	end
	return out
end
local hexNeighbors = {}
for h in hexes do
	hexNeighbors[h] = neighborsOfHex(h)
end

-- Helpers -----------------------------------------------------------------------

local function emptyHand(): { [string]: number }
	local hand = {}
	for _, r in RES do
		hand[r] = 0
	end
	return hand
end

local function handSize(hand: { [string]: number }): number
	local n = 0
	for _, r in RES do
		n += hand[r]
	end
	return n
end

local function canPay(hand: { [string]: number }, cost: { [string]: number }): boolean
	for r, n in cost do
		if (hand[r] or 0) < n then
			return false
		end
	end
	return true
end

local function pay(state: any, seat: number, cost: { [string]: number })
	local hand = state.players[seat].hand
	for r, n in cost do
		hand[r] -= n
		state.bank[r] += n
	end
end

local function shuffle(list: { any }, rng: any)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

-- `target` is a second seat the client names after the text ("took a card from Ava").
local function log(state: any, seat: number?, text: string, target: number?)
	table.insert(state.log, { seat = seat, text = text, target = target })
	while #state.log > 8 do
		table.remove(state.log, 1)
	end
end

local function resName(r: string): string
	return Hexlands.resourceInfo[r].name
end

local function listCards(cards: { [string]: number }): string
	local parts = {}
	for _, r in RES do
		local n = cards[r] or 0
		if n > 0 then
			table.insert(parts, `{n} {resName(r)}`)
		end
	end
	return if #parts > 0 then table.concat(parts, ", ") else "nothing"
end

-- Reads a { [res] = n } table from the network: only resource keys, whole numbers >= 0.
local function readCards(value: any): { [string]: number }?
	if type(value) ~= "table" then
		return nil
	end
	local out = emptyHand()
	local count = 0
	for k, n in value do
		count += 1
		if count > 5 or type(k) ~= "string" or not isRes[k] then
			return nil
		end
		if type(n) ~= "number" or n ~= n or n < 0 or n > 99 or n % 1 ~= 0 then
			return nil
		end
		out[k] = n
	end
	return out
end

-- Map ---------------------------------------------------------------------------

local function makeMap(rng: any): ({ any }, { any })
	local lands = {}
	for _, pair in { { "lumber", 4 }, { "clay", 3 }, { "wool", 4 }, { "grain", 4 }, { "stone", 3 }, { "dunes", 1 } } do
		for _ = 1, pair[2] do
			table.insert(lands, pair[1])
		end
	end
	local tiles
	for _ = 1, 500 do
		shuffle(lands, rng)
		local numbers = { 2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11, 12 }
		shuffle(numbers, rng)
		tiles = {}
		local i = 0
		for h = 1, #hexes do
			if lands[h] == "dunes" then
				tiles[h] = { land = "dunes", number = 0 }
			else
				i += 1
				tiles[h] = { land = lands[h], number = numbers[i] }
			end
		end
		local fair = true
		for h, t in tiles do
			if t.number == 6 or t.number == 8 then
				for _, n in hexNeighbors[h] do
					if tiles[n].number == 6 or tiles[n].number == 8 then
						fair = false
					end
				end
			end
		end
		if fair then
			break
		end
	end
	local kinds = { "any", "any", "any", "any", "lumber", "clay", "wool", "grain", "stone" }
	shuffle(kinds, rng)
	local harbors = {}
	for i, e in harborEdges do
		harbors[i] = { edge = e, kind = kinds[i] }
	end
	return tiles, harbors
end

-- State ---------------------------------------------------------------------------

function Hexlands.new(seatCount: number, options: any, rng: any)
	local tiles, harbors = makeMap(rng)
	local bandit = 1
	for h, t in tiles do
		if t.land == "dunes" then
			bandit = h
		end
	end
	local deck = {}
	for _, kind in CARD_ORDER do
		for _ = 1, Hexlands.cards[kind].count do
			table.insert(deck, kind)
		end
	end
	shuffle(deck, rng)

	local players = {}
	for seat = 1, seatCount do
		players[seat] = {
			hand = emptyHand(),
			cards = {}, -- { { kind, bought = turn number } }
			guards = 0, -- Guards played
			roads = Hexlands.PIECES.road,
			camps = Hexlands.PIECES.camp,
			towns = Hexlands.PIECES.town,
			roadLength = 0,
		}
	end
	local setupOrder = {}
	for seat = 1, seatCount do
		table.insert(setupOrder, seat)
	end
	for seat = seatCount, 1, -1 do
		table.insert(setupOrder, seat)
	end
	local bank = emptyHand()
	for _, r in RES do
		bank[r] = Hexlands.BANK_EACH
	end
	local harborOf = {}
	for _, harbor in harbors do
		harborOf[edges[harbor.edge].a] = harbor.kind
		harborOf[edges[harbor.edge].b] = harbor.kind
	end
	local bots = {}
	for _, seat in (options and options.bots) or {} do
		bots[seat] = true
	end
	local state = {
		seatCount = seatCount,
		botLevel = (options and options.botLevel) or "medium",
		bots = bots,
		rng = rng,
		tiles = tiles,
		harbors = harbors,
		harborOf = harborOf, -- [vertex] = "any" | res
		bandit = bandit,
		owner = {}, -- [vertex] = seat
		town = {}, -- [vertex] = true
		road = {}, -- [edge] = seat
		players = players,
		bank = bank,
		deck = deck,
		phase = "setup", -- setup | roll | discard | bandit | main | trade | roads | over
		setupOrder = setupOrder,
		setupIndex = 1,
		setupStep = "place", -- place | road
		lastPlaced = nil, -- setup: the camp the next road must touch
		turn = 1,
		turnNumber = 0, -- counts every turn after setup (for "bought this turn")
		round = 1,
		maxRounds = Hexlands.MAX_ROUNDS[seatCount] or 20,
		dice = nil,
		discards = {}, -- [seat] = cards still to discard
		banditReturn = "main",
		cardPlayed = false,
		tradesThisTurn = 0,
		trade = nil,
		freeRoads = 0,
		longestRoad = nil, -- seat
		biggestGuard = nil, -- seat
		winner = nil,
		endReason = nil,
		moves = 0,
		log = {},
		botOffered = false,
		tradeId = 0,
	}
	log(state, nil, "Place your first camp and road")
	return state
end

-- Points --------------------------------------------------------------------------

local function publicPoints(state: any, seat: number): number
	local points = 0
	for v, owner in state.owner do
		if owner == seat then
			points += if state.town[v] then 2 else 1
		end
	end
	if state.longestRoad == seat then
		points += 2
	end
	if state.biggestGuard == seat then
		points += 2
	end
	return points
end

local function monuments(state: any, seat: number): number
	local n = 0
	for _, card in state.players[seat].cards do
		if card.kind == "monument" then
			n += 1
		end
	end
	return n
end

local function points(state: any, seat: number): number
	return publicPoints(state, seat) + monuments(state, seat)
end
Hexlands.points = points

local function checkWin(state: any, seat: number)
	if state.winner == nil and state.phase ~= "setup" and points(state, seat) >= Hexlands.TARGET_POINTS then
		state.winner = { seat }
		state.endReason = `{Hexlands.TARGET_POINTS} points`
		state.phase = "over"
	end
end

-- Longest Road -------------------------------------------------------------------

local function roadLength(state: any, seat: number): number
	local best = 0
	local used = {}
	local function walk(v: number, length: number)
		if length > best then
			best = length
		end
		local owner = state.owner[v]
		if length > 0 and owner ~= nil and owner ~= seat then
			return -- someone else's camp breaks the road here
		end
		for _, e in vertices[v].edges do
			if state.road[e] == seat and not used[e] then
				used[e] = true
				walk(otherEnd(e, v), length + 1)
				used[e] = false
			end
		end
	end
	for v in vertices do
		for _, e in vertices[v].edges do
			if state.road[e] == seat then
				walk(v, 0)
				break
			end
		end
	end
	return best
end
Hexlands.roadLength = roadLength

local function updateLongestRoad(state: any)
	local lengths = {}
	local most = 0
	for seat = 1, state.seatCount do
		lengths[seat] = roadLength(state, seat)
		state.players[seat].roadLength = lengths[seat]
		most = math.max(most, lengths[seat])
	end
	local holder = state.longestRoad
	if holder and lengths[holder] >= 5 and lengths[holder] >= most then
		return -- the holder keeps it on a tie
	end
	local leaders = {}
	for seat = 1, state.seatCount do
		if lengths[seat] == most then
			table.insert(leaders, seat)
		end
	end
	local newHolder = if most >= 5 and #leaders == 1 then leaders[1] else nil
	if newHolder ~= holder then
		state.longestRoad = newHolder
		if newHolder then
			log(state, newHolder, `took Longest Road ({most})`)
		end
	end
end

-- Placement checks ---------------------------------------------------------------

local function validVertex(v: any): boolean
	return type(v) == "number" and v % 1 == 0 and vertices[v] ~= nil
end

local function validEdge(e: any): boolean
	return type(e) == "number" and e % 1 == 0 and edges[e] ~= nil
end

-- Distance rule: the corner and every corner next to it are empty.
local function openSpot(state: any, v: number): boolean
	if state.owner[v] ~= nil then
		return false
	end
	for _, n in vertices[v].near do
		if state.owner[n] ~= nil then
			return false
		end
	end
	return true
end

local function touchesOwnRoad(state: any, seat: number, v: number): boolean
	for _, e in vertices[v].edges do
		if state.road[e] == seat then
			return true
		end
	end
	return false
end

function Hexlands.canCamp(state: any, seat: number, v: number): boolean
	return openSpot(state, v) and touchesOwnRoad(state, seat, v)
end

function Hexlands.canRoad(state: any, seat: number, e: number): boolean
	if state.road[e] ~= nil then
		return false
	end
	for _, v in { edges[e].a, edges[e].b } do
		local owner = state.owner[v]
		if owner == seat then
			return true
		end
		if owner == nil then
			for _, other in vertices[v].edges do
				if other ~= e and state.road[other] == seat then
					return true
				end
			end
		end
	end
	return false
end

function Hexlands.canTown(state: any, seat: number, v: number): boolean
	return state.owner[v] == seat and not state.town[v]
end

-- Best bank rate for giving `r`: 4, 3 with any 3:1 harbor, 2 with that resource's harbor.
function Hexlands.rate(state: any, seat: number, r: string): number
	local rate = 4
	for v, kind in state.harborOf do
		if state.owner[v] == seat then
			if kind == r then
				return 2
			elseif kind == "any" then
				rate = 3
			end
		end
	end
	return rate
end

local function legalVertices(state: any, seat: number, check: (any, number, number) -> boolean): { number }
	local out = {}
	for v in vertices do
		if check(state, seat, v) then
			table.insert(out, v)
		end
	end
	return out
end

local function legalEdges(state: any, seat: number): { number }
	local out = {}
	for e in edges do
		if Hexlands.canRoad(state, seat, e) then
			table.insert(out, e)
		end
	end
	return out
end

local function setupSpots(state: any): { number }
	local out = {}
	for v in vertices do
		if openSpot(state, v) then
			table.insert(out, v)
		end
	end
	return out
end

local function setupRoads(state: any): { number }
	local out = {}
	for _, e in vertices[state.lastPlaced].edges do
		if state.road[e] == nil then
			table.insert(out, e)
		end
	end
	return out
end

local function banditVictims(state: any, seat: number, h: number): { number }
	local out = {}
	for _, v in hexVertices[h] do
		local owner = state.owner[v]
		if owner and owner ~= seat and not table.find(out, owner) and handSize(state.players[owner].hand) > 0 then
			table.insert(out, owner)
		end
	end
	table.sort(out)
	return out
end
Hexlands.banditVictims = banditVictims

local function playableCard(state: any, seat: number, kind: string): boolean
	if state.cardPlayed or kind == "monument" then
		return false
	end
	for _, card in state.players[seat].cards do
		if card.kind == kind and card.bought < state.turnNumber then
			return true
		end
	end
	return false
end
Hexlands.playableCard = playableCard

-- Turn flow -------------------------------------------------------------------------

local function produce(state: any, roll: number)
	for _, r in RES do
		local want = {}
		local total, takers = 0, 0
		for h, tile in state.tiles do
			if tile.number == roll and tile.land == r and h ~= state.bandit then
				for _, v in hexVertices[h] do
					local owner = state.owner[v]
					if owner then
						local n = if state.town[v] then 2 else 1
						if not want[owner] then
							takers += 1
						end
						want[owner] = (want[owner] or 0) + n
						total += n
					end
				end
			end
		end
		if total > 0 then
			if total > state.bank[r] and takers > 1 then
				log(state, nil, `The bank is out of {resName(r)}`)
			else
				for seat, n in want do
					n = math.min(n, state.bank[r])
					state.players[seat].hand[r] += n
					state.bank[r] -= n
				end
			end
		end
	end
end

local function nextTurn(state: any)
	state.turn = state.turn % state.seatCount + 1
	if state.turn == 1 then
		state.round += 1
	end
	state.turnNumber += 1
	state.phase = "roll"
	state.dice = nil
	state.cardPlayed = false
	state.tradesThisTurn = 0
	state.botOffered = false
	if state.round > state.maxRounds then
		local best, winners = -1, {}
		for seat = 1, state.seatCount do
			local p = points(state, seat)
			if p > best then
				best, winners = p, { seat }
			elseif p == best then
				table.insert(winners, seat)
			end
		end
		state.winner = winners
		state.endReason = "Most points after the last round"
		state.phase = "over"
	end
end

local function startBandit(state: any, returnPhase: string)
	state.phase = "bandit"
	state.banditReturn = returnPhase
end

local function afterRollSeven(state: any)
	state.discards = {}
	local any = false
	for seat = 1, state.seatCount do
		local n = handSize(state.players[seat].hand)
		if n > Hexlands.HAND_LIMIT then
			state.discards[seat] = n // 2
			any = true
		end
	end
	if any then
		state.phase = "discard"
	else
		startBandit(state, "main")
	end
end

-- Contract --------------------------------------------------------------------------

function Hexlands.getActiveSeats(state: any): { number }
	if state.phase == "over" then
		return {}
	elseif state.phase == "setup" then
		return { state.setupOrder[state.setupIndex] }
	elseif state.phase == "discard" then
		local out = {}
		for seat = 1, state.seatCount do
			if state.discards[seat] then
				table.insert(out, seat)
			end
		end
		return out
	elseif state.phase == "trade" then
		return { state.trade.to }
	end
	return { state.turn }
end

local function currentSeat(state: any): number
	return if state.phase == "setup" then state.setupOrder[state.setupIndex] else state.turn
end

function Hexlands.validateMove(state: any, seat: number, move: any): (boolean, string?)
	if type(move) ~= "table" or type(move.kind) ~= "string" then
		return false, "Bad move"
	end
	local phase = state.phase
	local kind = move.kind
	if phase == "over" then
		return false, "The game is over"
	end
	if not table.find(Hexlands.getActiveSeats(state), seat) then
		return false, "It's not your turn"
	end
	local p = state.players[seat]

	if phase == "setup" then
		if state.setupStep == "place" then
			if kind ~= "place" or not validVertex(move.vertex) then
				return false, "Place a camp on a corner"
			end
			if not openSpot(state, move.vertex) then
				return false, "Camps need a free corner with no camp next to it"
			end
			return true
		end
		if kind ~= "road" or not validEdge(move.edge) then
			return false, "Place a road next to your camp"
		end
		if not table.find(setupRoads(state), move.edge) then
			return false, "The road has to touch the camp you just placed"
		end
		return true
	end

	if phase == "discard" then
		if kind ~= "discard" then
			return false, "Discard first"
		end
		local cards = readCards(move.cards)
		if not cards then
			return false, "Bad discard"
		end
		if handSize(cards) ~= state.discards[seat] then
			return false, `Discard exactly {state.discards[seat]} cards`
		end
		if not canPay(p.hand, cards) then
			return false, "You don't have those cards"
		end
		return true
	end

	if phase == "bandit" then
		if kind ~= "bandit" then
			return false, "Move the Bandit first"
		end
		local h = move.hex
		if type(h) ~= "number" or h % 1 ~= 0 or not hexes[h] then
			return false, "Pick a hex"
		end
		if h == state.bandit then
			return false, "The Bandit has to move to a new hex"
		end
		local victims = banditVictims(state, seat, h)
		if #victims > 0 then
			if not table.find(victims, move.victim) then
				return false, "Pick who to take a card from"
			end
		elseif move.victim ~= nil then
			return false, "Nobody there to take from"
		end
		return true
	end

	if phase == "trade" then
		if kind ~= "accept" and kind ~= "reject" then
			return false, "Answer the trade"
		end
		if kind == "accept" then
			local t = state.trade
			if not canPay(p.hand, t.get) then
				return false, "You don't have those cards"
			end
			if not canPay(state.players[t.from].hand, t.give) then
				return false, "They no longer have those cards"
			end
		end
		return true
	end

	if phase == "roads" then
		if kind == "doneRoads" then
			return true
		end
		if kind ~= "road" or not validEdge(move.edge) then
			return false, "Place your free roads"
		end
		if not Hexlands.canRoad(state, seat, move.edge) then
			return false, "Roads must connect to your roads or camps"
		end
		return true
	end

	if kind == "play" then
		if phase ~= "roll" and phase ~= "main" then
			return false, "You can't play that now"
		end
		local card = move.card
		if type(card) ~= "string" or not Hexlands.cards[card] then
			return false, "Bad card"
		end
		if phase == "roll" and card ~= "guard" then
			return false, "Roll first (only Guards can be played before rolling)"
		end
		if state.cardPlayed then
			return false, "One action card per turn"
		end
		if not playableCard(state, seat, card) then
			return false, "You don't have that card (or bought it this turn)"
		end
		if card == "harvest" then
			local res = move.res
			if type(res) ~= "table" or #res ~= 2 or not isRes[res[1]] or not isRes[res[2]] then
				return false, "Pick 2 resources"
			end
			local need = { [res[1]] = 1 }
			need[res[2]] = (need[res[2]] or 0) + 1
			if not canPay(state.bank, need) then
				return false, "The bank doesn't have those"
			end
		elseif card == "hoard" then
			if type(move.res) ~= "string" or not isRes[move.res] then
				return false, "Pick a resource"
			end
		elseif card == "roadcrew" then
			if p.roads <= 0 or #legalEdges(state, seat) == 0 then
				return false, "Nowhere to build a road"
			end
		end
		return true
	end

	if phase == "roll" then
		if kind ~= "roll" then
			return false, "Roll the dice first"
		end
		return true
	end

	-- main
	if kind == "endTurn" then
		return true
	elseif kind == "road" then
		if not validEdge(move.edge) then
			return false, "Bad road"
		end
		if p.roads <= 0 then
			return false, "No roads left"
		end
		if not canPay(p.hand, Hexlands.costs.road) then
			return false, "A road costs 1 Lumber and 1 Clay"
		end
		if not Hexlands.canRoad(state, seat, move.edge) then
			return false, "Roads must connect to your roads or camps"
		end
		return true
	elseif kind == "camp" then
		if not validVertex(move.vertex) then
			return false, "Bad corner"
		end
		if p.camps <= 0 then
			return false, "No camps left (upgrade one to a town)"
		end
		if not canPay(p.hand, Hexlands.costs.camp) then
			return false, "A camp costs Lumber, Clay, Wool and Grain"
		end
		if not Hexlands.canCamp(state, seat, move.vertex) then
			return false, "Camps need your road and no camp next door"
		end
		return true
	elseif kind == "town" then
		if not validVertex(move.vertex) then
			return false, "Bad corner"
		end
		if p.towns <= 0 then
			return false, "No towns left"
		end
		if not canPay(p.hand, Hexlands.costs.town) then
			return false, "A town costs 2 Grain and 3 Stone"
		end
		if not Hexlands.canTown(state, seat, move.vertex) then
			return false, "Upgrade one of your camps"
		end
		return true
	elseif kind == "buyCard" then
		if #state.deck == 0 then
			return false, "No action cards left"
		end
		if not canPay(p.hand, Hexlands.costs.card) then
			return false, "An action card costs Wool, Grain and Stone"
		end
		return true
	elseif kind == "bank" then
		if not isRes[move.give] or not isRes[move.get] or move.give == move.get then
			return false, "Pick what to give and what to get"
		end
		local rate = Hexlands.rate(state, seat, move.give)
		if p.hand[move.give] < rate then
			return false, `You need {rate} {resName(move.give)}`
		end
		if state.bank[move.get] < 1 then
			return false, "The bank is out of that"
		end
		return true
	elseif kind == "offer" then
		if state.tradesThisTurn >= Hexlands.TRADES_PER_TURN then
			return false, `Only {Hexlands.TRADES_PER_TURN} trade offers a turn`
		end
		local to = move.to
		if type(to) ~= "number" or to % 1 ~= 0 or to == seat or not state.players[to] then
			return false, "Pick a player to trade with"
		end
		local give, get = readCards(move.give), readCards(move.get)
		if not give or not get or handSize(give) == 0 or handSize(get) == 0 then
			return false, "Each side has to give something"
		end
		for _, r in RES do
			if give[r] > 0 and get[r] > 0 then
				return false, "Don't trade a resource for itself"
			end
		end
		if not canPay(p.hand, give) then
			return false, "You don't have those cards"
		end
		return true
	end
	return false, "You can't do that now"
end

local function finishSetupStep(state: any)
	state.setupIndex += 1
	state.setupStep = "place"
	state.lastPlaced = nil
	if state.setupIndex > #state.setupOrder then
		state.phase = "roll"
		state.turn = 1
		state.turnNumber = 1
		log(state, nil, "Setup done. Roll the dice!")
	end
end

function Hexlands.applyMove(state: any, seat: number, move: any)
	state.moves += 1
	local kind = move.kind
	local p = state.players[seat]

	if state.phase == "setup" then
		if kind == "place" then
			state.owner[move.vertex] = seat
			p.camps -= 1
			state.lastPlaced = move.vertex
			state.setupStep = "road"
			if state.setupIndex > state.seatCount then
				local got = emptyHand()
				for _, h in vertices[move.vertex].hexes do
					local land = state.tiles[h].land
					if isRes[land] and state.bank[land] > 0 then
						p.hand[land] += 1
						state.bank[land] -= 1
						got[land] += 1
					end
				end
				log(state, seat, `placed a camp and got {listCards(got)}`)
			else
				log(state, seat, "placed a camp")
			end
		else
			state.road[move.edge] = seat
			p.roads -= 1
			finishSetupStep(state)
			updateLongestRoad(state)
		end
		return
	end

	if kind == "discard" then
		local cards = readCards(move.cards) :: any
		pay(state, seat, cards)
		state.discards[seat] = nil
		log(state, seat, `discarded {handSize(cards)}`)
		if next(state.discards) == nil then
			startBandit(state, "main")
		end
	elseif kind == "bandit" then
		state.bandit = move.hex
		local victim = move.victim
		if victim then
			local hand = state.players[victim].hand
			local pool = {}
			for _, r in RES do
				for _ = 1, hand[r] do
					table.insert(pool, r)
				end
			end
			local r = pool[state.rng:NextInteger(1, #pool)]
			hand[r] -= 1
			p.hand[r] += 1
			log(state, seat, "moved the Bandit and took a card from", victim)
			state.lastSteal = { from = victim, to = seat, res = r, n = state.moves }
		else
			log(state, seat, "moved the Bandit")
		end
		state.phase = state.banditReturn
	elseif kind == "roll" then
		local a, b = state.rng:NextInteger(1, 6), state.rng:NextInteger(1, 6)
		state.dice = { a, b }
		log(state, seat, `rolled {a + b}`)
		if a + b == 7 then
			afterRollSeven(state)
		else
			produce(state, a + b)
			state.phase = "main"
		end
	elseif kind == "endTurn" or kind == "doneRoads" then
		if kind == "doneRoads" then
			state.phase = "main"
		else
			nextTurn(state)
		end
	elseif kind == "road" then
		if state.phase == "roads" then
			state.freeRoads -= 1
		else
			pay(state, seat, Hexlands.costs.road)
		end
		state.road[move.edge] = seat
		p.roads -= 1
		updateLongestRoad(state)
		if state.phase == "roads" and (state.freeRoads <= 0 or p.roads <= 0 or #legalEdges(state, seat) == 0) then
			state.phase = "main"
		end
	elseif kind == "camp" then
		pay(state, seat, Hexlands.costs.camp)
		state.owner[move.vertex] = seat
		p.camps -= 1
		log(state, seat, "built a camp")
		updateLongestRoad(state) -- a camp can cut someone's road
	elseif kind == "town" then
		pay(state, seat, Hexlands.costs.town)
		state.town[move.vertex] = true
		p.towns -= 1
		p.camps += 1
		log(state, seat, "built a town")
	elseif kind == "buyCard" then
		pay(state, seat, Hexlands.costs.card)
		local card = table.remove(state.deck) :: string
		table.insert(p.cards, { kind = card, bought = state.turnNumber })
		log(state, seat, "bought an action card")
	elseif kind == "play" then
		local card = move.card
		for i, c in p.cards do
			if c.kind == card and c.bought < state.turnNumber then
				table.remove(p.cards, i)
				break
			end
		end
		state.cardPlayed = true
		log(state, seat, `played {Hexlands.cards[card].name}`)
		if card == "guard" then
			p.guards += 1
			local holder = state.biggestGuard
			if p.guards >= 3 and holder ~= seat and (holder == nil or p.guards > state.players[holder].guards) then
				state.biggestGuard = seat
				log(state, seat, "took Biggest Guard")
			end
			startBandit(state, state.phase)
		elseif card == "roadcrew" then
			state.freeRoads = 2
			state.phase = "roads"
		elseif card == "harvest" then
			for _, r in move.res do
				p.hand[r] += 1
				state.bank[r] -= 1
			end
		elseif card == "hoard" then
			local r = move.res
			local total = 0
			for other, op in state.players do
				if other ~= seat then
					total += op.hand[r]
					p.hand[r] += op.hand[r]
					op.hand[r] = 0
				end
			end
			log(state, seat, `collected {total} {resName(r)}`)
		end
	elseif kind == "bank" then
		local rate = Hexlands.rate(state, seat, move.give)
		p.hand[move.give] -= rate
		state.bank[move.give] += rate
		p.hand[move.get] += 1
		state.bank[move.get] -= 1
		log(state, seat, `traded {rate} {resName(move.give)} for 1 {resName(move.get)}`)
	elseif kind == "offer" then
		state.tradesThisTurn += 1
		state.tradeId += 1
		state.trade = { from = seat, to = move.to, give = readCards(move.give), get = readCards(move.get) }
		state.phase = "trade"
		log(state, seat, "offered a trade to", move.to)
	elseif kind == "accept" then
		local t = state.trade
		local from = state.players[t.from]
		for _, r in RES do
			from.hand[r] += t.get[r] - t.give[r]
			p.hand[r] += t.give[r] - t.get[r]
		end
		state.trade = nil
		state.phase = "main"
		log(state, seat, "accepted the trade")
	elseif kind == "reject" then
		state.trade = nil
		state.phase = "main"
		log(state, seat, "turned down the trade")
	end

	checkWin(state, state.turn)
	if state.winner == nil and state.moves >= MOVE_LIMIT then
		state.winner = {}
		state.endReason = "Out of time"
		state.phase = "over"
	end
end

function Hexlands.getResult(state: any): any
	if state.winner == nil then
		return nil
	end
	return {
		winners = state.winner,
		isDraw = #state.winner ~= 1,
		reason = state.endReason,
	}
end

-- What the seat could do right now, for highlights and buttons.
local function options(state: any, seat: number?): any
	local out = { vertices = {}, edges = {}, towns = {}, hexes = {} }
	if seat == nil or not table.find(Hexlands.getActiveSeats(state), seat) then
		return out
	end
	local p = state.players[seat]
	if state.phase == "setup" then
		if state.setupStep == "place" then
			out.vertices = setupSpots(state)
		else
			out.edges = setupRoads(state)
		end
	elseif state.phase == "roads" then
		out.edges = legalEdges(state, seat)
	elseif state.phase == "bandit" then
		for h in hexes do
			if h ~= state.bandit then
				table.insert(out.hexes, h)
			end
		end
	elseif state.phase == "main" then
		if p.roads > 0 and canPay(p.hand, Hexlands.costs.road) then
			out.edges = legalEdges(state, seat)
		end
		if p.camps > 0 and canPay(p.hand, Hexlands.costs.camp) then
			out.vertices = legalVertices(state, seat, Hexlands.canCamp)
		end
		if p.towns > 0 and canPay(p.hand, Hexlands.costs.town) then
			out.towns = legalVertices(state, seat, Hexlands.canTown)
		end
	end
	return out
end

function Hexlands.getLegalMoves(state: any, seat: number): { any }
	local moves = {}
	local phase = state.phase
	if phase == "over" or not table.find(Hexlands.getActiveSeats(state), seat) then
		return moves
	end
	local opt = options(state, seat)
	if phase == "setup" then
		for _, v in opt.vertices do
			table.insert(moves, { kind = "place", vertex = v })
		end
		for _, e in opt.edges do
			table.insert(moves, { kind = "road", edge = e })
		end
	elseif phase == "discard" then
		-- One fair discard: take from the biggest piles.
		local hand = table.clone(state.players[seat].hand)
		local cards = emptyHand()
		for _ = 1, state.discards[seat] do
			local best = RES[1]
			for _, r in RES do
				if hand[r] > hand[best] then
					best = r
				end
			end
			hand[best] -= 1
			cards[best] += 1
		end
		table.insert(moves, { kind = "discard", cards = cards })
	elseif phase == "bandit" then
		for _, h in opt.hexes do
			local victims = banditVictims(state, seat, h)
			if #victims == 0 then
				table.insert(moves, { kind = "bandit", hex = h })
			end
			for _, v in victims do
				table.insert(moves, { kind = "bandit", hex = h, victim = v })
			end
		end
	elseif phase == "trade" then
		table.insert(moves, { kind = "reject" })
		if canPay(state.players[seat].hand, state.trade.get) then
			table.insert(moves, { kind = "accept" })
		end
	elseif phase == "roads" then
		table.insert(moves, { kind = "doneRoads" })
		for _, e in opt.edges do
			table.insert(moves, { kind = "road", edge = e })
		end
	elseif phase == "roll" then
		table.insert(moves, { kind = "roll" })
		if playableCard(state, seat, "guard") then
			table.insert(moves, { kind = "play", card = "guard" })
		end
	else
		table.insert(moves, { kind = "endTurn" })
		for _, e in opt.edges do
			table.insert(moves, { kind = "road", edge = e })
		end
		for _, v in opt.vertices do
			table.insert(moves, { kind = "camp", vertex = v })
		end
		for _, v in opt.towns do
			table.insert(moves, { kind = "town", vertex = v })
		end
		if #state.deck > 0 and canPay(state.players[seat].hand, Hexlands.costs.card) then
			table.insert(moves, { kind = "buyCard" })
		end
		for _, give in RES do
			for _, get in RES do
				local m = { kind = "bank", give = give, get = get }
				if give ~= get and Hexlands.validateMove(state, seat, m) then
					table.insert(moves, m)
				end
			end
		end
	end
	return moves
end

-- Views ----------------------------------------------------------------------------

local function dense(map: { [number]: any }, size: number, empty: any): { any }
	local out = table.create(size, empty)
	for k, v in map do
		out[k] = v
	end
	return out
end

function Hexlands.getView(state: any, seat: number?): any
	local players = {}
	for s, p in state.players do
		local entry: any = {
			cards = handSize(p.hand),
			actionCards = #p.cards,
			guards = p.guards,
			roadLength = p.roadLength,
			points = publicPoints(state, s),
			roads = p.roads,
			camps = p.camps,
			towns = p.towns,
		}
		-- Monuments stay hidden from everyone (yourself included, see you.secret) until the
		-- end, so this matches the seat bar, which everyone sees.
		if state.phase == "over" then
			entry.points = points(state, s)
		end
		players[s] = entry
	end
	local you = nil
	if seat and state.players[seat] then
		local p = state.players[seat]
		local cards = {}
		for _, card in p.cards do
			table.insert(cards, { kind = card.kind, ready = card.bought < state.turnNumber })
		end
		local rates = {}
		for _, r in RES do
			rates[r] = Hexlands.rate(state, seat, r)
		end
		you = { hand = table.clone(p.hand), cards = cards, rates = rates, secret = if state.phase == "over" then 0 else monuments(state, seat) }
	end
	local trade = nil
	if state.trade then
		trade = { from = state.trade.from, to = state.trade.to, give = table.clone(state.trade.give), get = table.clone(state.trade.get) }
	end
	local steal = nil
	if state.lastSteal and seat and (state.lastSteal.from == seat or state.lastSteal.to == seat) then
		steal = table.clone(state.lastSteal)
	end
	local opt = options(state, seat)
	local canPlay = {}
	if seat then
		for _, kind in CARD_ORDER do
			canPlay[kind] = table.find(Hexlands.getActiveSeats(state), seat) ~= nil
				and seat == state.turn
				and (state.phase == "main" or (state.phase == "roll" and kind == "guard"))
				and playableCard(state, seat, kind)
		end
	end
	return {
		phase = state.phase,
		setupStep = state.setupStep,
		turn = currentSeat(state),
		round = state.round,
		maxRounds = state.maxRounds,
		target = Hexlands.TARGET_POINTS,
		tiles = GameModule.copy(state.tiles),
		harbors = GameModule.copy(state.harbors),
		bandit = state.bandit,
		-- Dense lists (0 / false for empty): sparse number keys turn into strings on
		-- the way through a RemoteEvent.
		owner = dense(state.owner, #vertices, 0),
		town = dense(state.town, #vertices, false),
		road = dense(state.road, #edges, 0),
		players = players,
		bank = table.clone(state.bank),
		deckLeft = #state.deck,
		dice = state.dice and table.clone(state.dice),
		discards = dense(state.discards, state.seatCount, 0),
		trade = trade,
		tradesLeft = Hexlands.TRADES_PER_TURN - state.tradesThisTurn,
		freeRoads = state.freeRoads,
		longestRoad = state.longestRoad,
		biggestGuard = state.biggestGuard,
		log = GameModule.copy(state.log),
		you = you,
		steal = steal,
		options = opt,
		canPlay = canPlay,
		cardPlayed = state.cardPlayed,
	}
end

function Hexlands.getSeatInfo(state: any): { [number]: string }
	local out = {}
	for seat, p in state.players do
		local shown = if state.phase == "over" then points(state, seat) else publicPoints(state, seat)
		out[seat] = `{shown} pts · {handSize(p.hand)} cards`
	end
	return out
end

function Hexlands.getScores(state: any): { [number]: number }
	local out = {}
	for seat in state.players do
		out[seat] = points(state, seat)
	end
	return out
end

-- A trade offer waits TRADE_SECONDS for an answer, then counts as turned down. Other
-- phases use the normal per-turn clock.
Hexlands.TRADE_SECONDS = 20
function Hexlands.getTimer(state: any): any
	if state.phase == "trade" then
		return { id = state.tradeId, seconds = Hexlands.TRADE_SECONDS }
	end
	return nil
end

function Hexlands.onTimeout(state: any)
	if state.phase == "trade" then
		state.trade = nil
		state.phase = "main"
		log(state, nil, "The trade offer ran out of time")
	end
end

function Hexlands.getBotDelay(state: any, seat: number, rng: any): number
	if state.phase == "trade" then
		return 1.2 -- time to read the offer
	elseif state.phase == "roll" or state.phase == "bandit" then
		return 0.8 + rng:NextNumber() * 0.3
	end
	return 0.35 + rng:NextNumber() * 0.25 -- builds and trades in a quick sequence
end

-- Bots -------------------------------------------------------------------------------
-- Rule-based: value corners by dice odds and variety, build town > camp > card > road,
-- trade with the bank to finish a build, and block the leader with the Bandit.

local function vertexValue(state: any, seat: number, v: number, have: { [string]: number }?): number
	local value = 0
	local kinds = {}
	for _, h in vertices[v].hexes do
		local tile = state.tiles[h]
		if isRes[tile.land] then
			local pips = PIPS[tile.number] or 0
			if h == state.bandit then
				pips *= 0.4
			end
			local weight = 1
			if have and (have[tile.land] or 0) == 0 then
				weight = 1.4 -- a resource we don't make yet
			end
			if tile.land == "clay" or tile.land == "lumber" then
				weight *= 1.1 -- roads early on
			end
			value += pips * weight
			kinds[tile.land] = true
		end
	end
	local variety = 0
	for _ in kinds do
		variety += 1
	end
	value += variety * 0.8
	local harbor = state.harborOf[v]
	if harbor then
		value += if harbor == "any" then 1.5 else (if have and (have[harbor] or 0) >= 4 then 3 else 1)
	end
	return value
end

-- Dice pips of each resource this seat makes.
local function production(state: any, seat: number): { [string]: number }
	local out = emptyHand()
	for v, owner in state.owner do
		if owner == seat then
			for _, h in vertices[v].hexes do
				local tile = state.tiles[h]
				if isRes[tile.land] and h ~= state.bandit then
					out[tile.land] += (PIPS[tile.number] or 0) * (if state.town[v] then 2 else 1)
				end
			end
		end
	end
	return out
end

local function pickTop(list: { any }, score: (any) -> number, level: string, rng: any): any?
	if #list == 0 then
		return nil
	end
	local scored = {}
	for _, item in list do
		table.insert(scored, { item = item, score = score(item) })
	end
	table.sort(scored, function(a, b)
		return a.score > b.score
	end)
	local top = if level == "easy" then 6 elseif level == "medium" then 2 else 1
	return scored[rng:NextInteger(1, math.min(top, #scored))].item
end

local function missing(hand: { [string]: number }, cost: { [string]: number }): number
	local n = 0
	for r, need in cost do
		n += math.max(0, need - (hand[r] or 0))
	end
	return n
end

-- How far a hand is from something useful (lower is better). Used to judge trades.
local function handNeed(state: any, seat: number, hand: { [string]: number }): number
	local p = state.players[seat]
	local best = 99
	if p.towns > 0 and #legalVertices(state, seat, Hexlands.canTown) > 0 then
		best = math.min(best, missing(hand, Hexlands.costs.town) - 0.5)
	end
	if p.camps > 0 and #legalVertices(state, seat, Hexlands.canCamp) > 0 then
		best = math.min(best, missing(hand, Hexlands.costs.camp) - 0.3)
	end
	if #state.deck > 0 then
		best = math.min(best, missing(hand, Hexlands.costs.card) + 0.4)
	end
	if p.roads > 0 then
		best = math.min(best, missing(hand, Hexlands.costs.road) + 0.8)
	end
	return best
end

-- A bank trade that gets us closer to `cost`, using only cards the cost doesn't need.
local function bankTradeToward(state: any, seat: number, cost: { [string]: number }): any?
	local hand = state.players[seat].hand
	local short = nil
	for _, r in RES do
		if (cost[r] or 0) > hand[r] and state.bank[r] > 0 then
			short = r
			break
		end
	end
	if not short then
		return nil
	end
	local spare = nil
	local spareExtra = 0
	for _, r in RES do
		local rate = Hexlands.rate(state, seat, r)
		local extra = hand[r] - (cost[r] or 0) - rate
		if extra >= 0 and (spare == nil or extra > spareExtra) then
			spare, spareExtra = r, extra
		end
	end
	if not spare then
		return nil
	end
	-- Only worth it if the trades can finish the build.
	local need = missing(hand, cost)
	local trades = 0
	local sim = table.clone(hand)
	for _, r in RES do
		sim[r] -= cost[r] or 0
	end
	for _, r in RES do
		while sim[r] >= Hexlands.rate(state, seat, r) do
			sim[r] -= Hexlands.rate(state, seat, r)
			trades += 1
		end
	end
	-- sim only counted cards beyond the cost; negative piles are what's missing.
	if trades < need then
		return nil
	end
	return { kind = "bank", give = spare, get = short }
end

local function leader(state: any, except: number): (number?, number)
	local best, bestSeat = -1, nil
	for seat = 1, state.seatCount do
		if seat ~= except then
			local p = publicPoints(state, seat)
			if p > best then
				best, bestSeat = p, seat
			end
		end
	end
	return bestSeat, best
end

local function bestBandit(state: any, seat: number, rng: any): any
	local lead = leader(state, seat)
	local move = pickTop(Hexlands.getLegalMoves(state, seat), function(m)
		local score = 0
		local tile = state.tiles[m.hex]
		local pips = PIPS[tile.number] or 0
		for _, v in hexVertices[m.hex] do
			local owner = state.owner[v]
			local weight = if state.town[v] then 2 else 1
			if owner == seat then
				score -= pips * weight * 2
			elseif owner then
				score += pips * weight * (if owner == lead then 1.6 else 1)
			end
		end
		if m.victim then
			score += handSize(state.players[m.victim].hand) * 0.3 + publicPoints(state, m.victim) * 0.5
		end
		return score
	end, state.botLevel, rng)
	return move
end

local function bestRoad(state: any, seat: number, edgesToTry: { number }, rng: any): number?
	if #edgesToTry == 0 then
		return nil
	end
	local have = production(state, seat)
	return pickTop(edgesToTry, function(e)
		local best = 0
		for _, v in { edges[e].a, edges[e].b } do
			if openSpot(state, v) then
				best = math.max(best, vertexValue(state, seat, v, have) + 2)
			end
			for _, n in vertices[v].near do
				if openSpot(state, n) then
					best = math.max(best, vertexValue(state, seat, n, have) * 0.7)
				end
			end
		end
		return best + rng:NextNumber() * 0.5
	end, state.botLevel, rng)
end

local function chooseMain(state: any, seat: number, rng: any): any
	local p = state.players[seat]
	local hand = p.hand
	local level = state.botLevel
	local have = production(state, seat)

	-- Play an action card when it helps.
	if not state.cardPlayed then
		if playableCard(state, seat, "hoard") then
			-- Name the resource the others hold most of.
			local best, bestN = nil, 0
			for _, r in RES do
				local n = 0
				for other, op in state.players do
					if other ~= seat then
						n += op.hand[r]
					end
				end
				if n > bestN then
					best, bestN = r, n
				end
			end
			if best and bestN >= 3 then
				return { kind = "play", card = "hoard", res = best }
			end
		end
		if playableCard(state, seat, "harvest") then
			local want = {}
			local goal = if p.towns > 0 and #legalVertices(state, seat, Hexlands.canTown) > 0 then Hexlands.costs.town else Hexlands.costs.camp
			for _, r in RES do
				for _ = 1, math.max(0, (goal[r] or 0) - hand[r]) do
					if #want < 2 and state.bank[r] > #want then
						table.insert(want, r)
					end
				end
			end
			while #want < 2 do
				table.insert(want, RES[rng:NextInteger(1, #RES)])
			end
			if Hexlands.validateMove(state, seat, { kind = "play", card = "harvest", res = want }) then
				return { kind = "play", card = "harvest", res = want }
			end
		end
		if playableCard(state, seat, "roadcrew") and p.roads >= 1 and #legalEdges(state, seat) > 0 then
			return { kind = "play", card = "roadcrew" }
		end
		if playableCard(state, seat, "guard") then
			local onUs = false
			for _, v in hexVertices[state.bandit] do
				if state.owner[v] == seat then
					onUs = true
				end
			end
			-- Guards are free tempo: chase Biggest Guard (Easy only when it's on us).
			if onUs or level ~= "easy" or rng:NextNumber() < 0.4 then
				return { kind = "play", card = "guard" }
			end
		end
	end

	-- Build: town > camp.
	if p.towns > 0 and canPay(hand, Hexlands.costs.town) then
		local v = pickTop(legalVertices(state, seat, Hexlands.canTown), function(v)
			return vertexValue(state, seat, v, nil)
		end, level, rng)
		if v then
			return { kind = "town", vertex = v }
		end
	end
	local campSpots = if p.camps > 0 then legalVertices(state, seat, Hexlands.canCamp) else {}
	if #campSpots > 0 and canPay(hand, Hexlands.costs.camp) then
		local v = pickTop(campSpots, function(v)
			return vertexValue(state, seat, v, have)
		end, level, rng)
		return { kind = "camp", vertex = v }
	end

	-- Bank trades toward the best goal.
	local goals = {}
	if p.towns > 0 and #legalVertices(state, seat, Hexlands.canTown) > 0 then
		table.insert(goals, Hexlands.costs.town)
	end
	if #campSpots > 0 then
		table.insert(goals, Hexlands.costs.camp)
	end
	if p.roads > 0 and #campSpots == 0 then
		table.insert(goals, Hexlands.costs.road)
	end
	if #state.deck > 0 then
		table.insert(goals, Hexlands.costs.card)
	end
	if level ~= "easy" or rng:NextNumber() < 0.5 then
		for _, goal in goals do
			local trade = bankTradeToward(state, seat, goal)
			if trade then
				return trade
			end
		end
	end

	-- Offer another player a 1-for-1 when one card short of a camp or town.
	if not state.botOffered and state.tradesThisTurn < Hexlands.TRADES_PER_TURN and level ~= "easy" then
		for _, goal in goals do
			if missing(hand, goal) == 1 then
				local want = nil
				for _, r in RES do
					if (goal[r] or 0) > hand[r] then
						want = r
					end
				end
				local spare = nil
				for _, r in RES do
					if hand[r] - (goal[r] or 0) >= 1 and r ~= want then
						spare = r
					end
				end
				if want and spare then
					local others = {}
					for other, op in state.players do
						if other ~= seat and op.hand[want] > 0 then
							table.insert(others, other)
						end
					end
					state.botOffered = true
					if #others > 0 then
						return { kind = "offer", to = others[rng:NextInteger(1, #others)], give = { [spare] = 1 }, get = { [want] = 1 } }
					end
				end
				break
			end
		end
	end

	-- Roads to reach new camp spots (keep two open spots ahead), or chasing Longest Road.
	if p.roads > 0 and canPay(hand, Hexlands.costs.road) then
		local chase = level ~= "easy" and state.longestRoad ~= seat and p.roadLength >= 3 and p.roads > 4
		local wantSpots = p.camps > 0 and #campSpots < (if level == "easy" then 1 else 2)
		if wantSpots or chase then
			local e = bestRoad(state, seat, legalEdges(state, seat), rng)
			if e then
				return { kind = "road", edge = e }
			end
		end
	end
	if #state.deck > 0 and canPay(hand, Hexlands.costs.card) then
		local saveForTown = p.towns > 0 and #legalVertices(state, seat, Hexlands.canTown) > 0 and hand.stone < 4 and hand.grain < 3
		if not saveForTown or handSize(hand) >= 6 then
			return { kind = "buyCard" }
		end
	end
	return { kind = "endTurn" }
end

function Hexlands.chooseBotMove(state: any, seat: number, rng: any): any?
	local phase = state.phase
	local level = state.botLevel
	if phase == "setup" then
		if state.setupStep == "place" then
			local have = production(state, seat)
			local v = pickTop(setupSpots(state), function(v)
				return vertexValue(state, seat, v, have)
			end, level, rng)
			return { kind = "place", vertex = v }
		end
		return { kind = "road", edge = bestRoad(state, seat, setupRoads(state), rng) }
	elseif phase == "discard" then
		local moves = Hexlands.getLegalMoves(state, seat)
		return moves[1]
	elseif phase == "bandit" then
		return bestBandit(state, seat, rng)
	elseif phase == "trade" then
		local t = state.trade
		local hand = state.players[seat].hand
		if not canPay(hand, t.get) then
			return { kind = "reject" }
		end
		local after = table.clone(hand)
		for _, r in RES do
			after[r] += t.give[r] - t.get[r]
		end
		local before = handNeed(state, seat, hand)
		local now = handNeed(state, seat, after)
		local _, leadPoints = leader(state, t.from)
		local fromPoints = publicPoints(state, t.from)
		local helpsLeader = fromPoints >= Hexlands.TARGET_POINTS - 2 and fromPoints >= leadPoints
		local good = now < before or (now == before and handSize(t.give) > handSize(t.get))
		if level == "easy" then
			good = good or rng:NextNumber() < 0.3
		end
		if good and not helpsLeader then
			return { kind = "accept" }
		end
		return { kind = "reject" }
	elseif phase == "roads" then
		local e = bestRoad(state, seat, legalEdges(state, seat), rng)
		return if e then { kind = "road", edge = e } else { kind = "doneRoads" }
	elseif phase == "roll" then
		if playableCard(state, seat, "guard") then
			for _, v in hexVertices[state.bandit] do
				if state.owner[v] == seat then
					return { kind = "play", card = "guard" }
				end
			end
		end
		return { kind = "roll" }
	elseif phase == "main" then
		return chooseMain(state, seat, rng)
	end
	return nil
end

return Hexlands
