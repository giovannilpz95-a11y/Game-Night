--[[
	Sea Strike: the classic hidden-fleet guessing game (the public-domain "Salvo" pencil
	game family) for 2 seats.

	Setup: each player's fleet starts placed at random on their own grid. Both players
	can move or turn ships, or shuffle the whole fleet, then press Ready. The setup has a
	clock (getTimer); when it runs out everyone is made ready with the fleet they have.
	Battle: players take turns firing at one square of the other player's grid. The
	shooter learns hit or miss. When every square of a ship is hit, it sinks and its
	name and position are announced ("You sank my Cruiser!"). Sink the whole enemy
	fleet to win.

	House rules (options.rules):
	  size    10 (classic: 5 ships) or 8 (quick: 4 ships, no Carrier)
	  streak  a hit lets you fire again (off by default)
	  salvo   each turn you fire one shot for every ship you still have afloat: true = one
	          at a time (you see each result), "all" = call every square first, then they
	          all land at once (the paper game's way)
	  noTouch ships may not touch, not even at a corner (the Sea Battle rule); when a ship
	          sinks, the water around it is marked for the shooter (code WATER)

	Moves
	  setup:  { kind = "place", ship = id, row, col, dir = "h" | "v" }  move/turn one ship
	          { kind = "shuffle" }                                     random fleet
	          { kind = "ready" }
	  battle: { kind = "fire", row, col }
	          { kind = "salvo", shots = { { row, col }, ... } }  salvo "all": every shot at once

	Shot codes in a grid (index (row - 1) * size + col): 0 unknown, 1 miss, 2 hit, 3 sunk,
	4 water (known empty: next to a sunk ship under noTouch; never fired at).
]]

local GameModule = require(script.Parent.Parent.GameModule)
local BotThink = require(script.Parent.Parent.BotThink)

local SeaStrike = {}

SeaStrike.id = "SeaStrike"
SeaStrike.minSeats = 2
SeaStrike.maxSeats = 2
SeaStrike.SETUP_SECONDS = 60

SeaStrike.SHIPS = {
	{ id = "carrier", name = "Carrier", len = 5 },
	{ id = "battleship", name = "Battleship", len = 4 },
	{ id = "cruiser", name = "Cruiser", len = 3 },
	{ id = "sub", name = "Submarine", len = 3 },
	{ id = "destroyer", name = "Destroyer", len = 2 },
}
local SHIP = {}
for _, s in SeaStrike.SHIPS do
	SHIP[s.id] = s
end
SeaStrike.SHIP = SHIP

local MISS, HIT, SUNK, WATER = 1, 2, 3, 4
SeaStrike.MISS, SeaStrike.HIT, SeaStrike.SUNK, SeaStrike.WATER = MISS, HIT, SUNK, WATER

local function isInt(v: any, lo: number, hi: number): boolean
	return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi
end

local function cellsOf(ship: any): { { number } }
	local out = {}
	for i = 0, ship.len - 1 do
		if ship.dir == "h" then
			table.insert(out, { ship.row, ship.col + i })
		else
			table.insert(out, { ship.row + i, ship.col })
		end
	end
	return out
end
SeaStrike.cellsOf = cellsOf

local function fits(size: number, row: number, col: number, dir: string, len: number): boolean
	if row < 1 or col < 1 then
		return false
	end
	if dir == "h" then
		return row <= size and col + len - 1 <= size
	end
	return col <= size and row + len - 1 <= size
end

-- Does `ship` (row/col/dir/len) overlap any other ship in `ships` (skipping `skipId`)?
local function overlaps(ships: { [string]: any }, ship: any, skipId: string?): boolean
	local taken = {}
	for id, other in ships do
		if id ~= skipId then
			for _, c in cellsOf(other) do
				taken[c[1] * 100 + c[2]] = true
			end
		end
	end
	for _, c in cellsOf(ship) do
		if taken[c[1] * 100 + c[2]] then
			return true
		end
	end
	return false
end

-- No touching (house rule): does `ship` share a side or a corner with another ship?
local function touches(ships: { [string]: any }, ship: any, skipId: string?): boolean
	local near = {}
	for id, other in ships do
		if id ~= skipId then
			for _, c in cellsOf(other) do
				for dr = -1, 1 do
					for dc = -1, 1 do
						near[(c[1] + dr) * 100 + c[2] + dc] = true
					end
				end
			end
		end
	end
	for _, c in cellsOf(ship) do
		if near[c[1] * 100 + c[2]] then
			return true
		end
	end
	return false
end
SeaStrike.touches = touches

local function randomFleet(state, rng: Random): { [string]: any }
	-- With no touching a fleet can paint itself into a corner: start over a few times.
	local last = {}
	for attempt = 1, 60 do
		local strict = state.noTouch and attempt < 60
		local ships = {}
		local complete = true
		for _, def in state.shipDefs do
			local placed = false
			for _ = 1, 300 do
				local dir = if rng:NextInteger(0, 1) == 0 then "h" else "v"
				local row = rng:NextInteger(1, state.size)
				local col = rng:NextInteger(1, state.size)
				local ship = { id = def.id, len = def.len, row = row, col = col, dir = dir, hits = 0, sunk = false }
				if fits(state.size, row, col, dir, def.len) and not overlaps(ships, ship) and not (strict and touches(ships, ship)) then
					ships[def.id] = ship
					placed = true
					break
				end
			end
			if not placed then
				complete = false
				break
			end
		end
		last = ships
		if complete then
			return ships
		end
	end
	return last
end

local function readRules(options: any?)
	local rules = if options and type(options.rules) == "table" then options.rules else {}
	return {
		size = if rules.size == 8 then 8 else 10,
		streak = rules.streak == true,
		salvo = if rules.salvo == "all" then "all" elseif rules.salvo == true then true else false,
		noTouch = rules.noTouch == true,
	}
end

function SeaStrike.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount == 2, "Sea Strike needs 2 seats")
	local random = rng or Random.new()
	local r = readRules(options)
	local defs = {}
	for _, s in SeaStrike.SHIPS do
		if not (r.size == 8 and s.id == "carrier") then
			table.insert(defs, s)
		end
	end
	local state: any = {
		seatCount = 2,
		rng = random,
		botLevel = (options and options.botLevel) or "medium",
		size = r.size,
		streak = r.streak,
		salvo = r.salvo,
		noTouch = r.noTouch,
		shotsLeft = 1, -- shots left this turn (more than 1 only with salvo)
		lastSalvo = nil, -- salvo "all": every shot of the last volley
		shipDefs = defs,
		phase = "setup",
		setupId = 1,
		turn = 1,
		ready = { false, false },
		fleets = {},
		shots = {}, -- shots[seat] = codes on the OTHER player's grid (what seat has fired)
		shotCount = 0,
		lastShot = nil,
		winner = nil,
	}
	for seat = 1, 2 do
		state.fleets[seat] = randomFleet(state, random)
		state.shots[seat] = table.create(r.size * r.size, 0)
	end
	return state
end

local function other(seat: number): number
	return 3 - seat
end

local function idx(state, row: number, col: number): number
	return (row - 1) * state.size + col
end

function SeaStrike.getActiveSeats(state): { number }
	if state.phase == "setup" then
		local out = {}
		for seat = 1, 2 do
			if not state.ready[seat] then
				table.insert(out, seat)
			end
		end
		return out
	elseif state.phase == "battle" then
		return { state.turn }
	end
	return {}
end

local function isActive(state, seat: number): boolean
	return table.find(SeaStrike.getActiveSeats(state), seat) ~= nil
end

function SeaStrike.getLegalMoves(state, seat: number): { any }
	if not isActive(state, seat) then
		return {}
	end
	if state.phase == "setup" then
		return { { kind = "ready" }, { kind = "shuffle" } }
	end
	local moves = {}
	local shots = state.shots[seat]
	for row = 1, state.size do
		for col = 1, state.size do
			if shots[idx(state, row, col)] == 0 then
				table.insert(moves, { kind = "fire", row = row, col = col })
			end
		end
	end
	if state.salvo == "all" then
		-- One volley: the first open squares (the bots pick better ones).
		local picked = {}
		for k = 1, SeaStrike.volleySize(state, seat) do
			table.insert(picked, { moves[k].row, moves[k].col })
		end
		return { { kind = "salvo", shots = picked } }
	end
	return moves
end

function SeaStrike.validateMove(state, seat: number, move: any): (boolean, string?)
	if type(move) ~= "table" or type(move.kind) ~= "string" then
		return false, "Bad move"
	end
	if seat ~= 1 and seat ~= 2 then
		return false, "Not a player"
	end
	if not isActive(state, seat) then
		return false, if state.phase == "setup" then "You're ready: waiting for the other admiral" else "It's not your turn"
	end
	if state.phase == "setup" then
		if move.kind == "ready" or move.kind == "shuffle" then
			return true
		elseif move.kind == "place" then
			if type(move.ship) ~= "string" or not state.fleets[seat][move.ship] then
				return false, "Unknown ship"
			end
			if move.dir ~= "h" and move.dir ~= "v" then
				return false, "Bad direction"
			end
			if not isInt(move.row, 1, state.size) or not isInt(move.col, 1, state.size) then
				return false, "Off the grid"
			end
			local len = state.fleets[seat][move.ship].len
			if not fits(state.size, move.row, move.col, move.dir, len) then
				return false, "That doesn't fit on the grid"
			end
			local ship = { row = move.row, col = move.col, dir = move.dir, len = len }
			if overlaps(state.fleets[seat], ship, move.ship) then
				return false, "Ships can't overlap"
			end
			if state.noTouch and touches(state.fleets[seat], ship, move.ship) then
				return false, "Ships can't touch (house rule)"
			end
			return true
		end
		return false, "Place your fleet first"
	end
	if move.kind == "salvo" then
		if state.salvo ~= "all" then
			return false, "Fire one shot at a time"
		end
		if type(move.shots) ~= "table" then
			return false, "Bad salvo"
		end
		local want = SeaStrike.volleySize(state, seat)
		if #move.shots ~= want then
			return false, `Pick {want} squares`
		end
		local seen = {}
		for i = 1, want do
			local shot = move.shots[i]
			if type(shot) ~= "table" or not isInt(shot[1], 1, state.size) or not isInt(shot[2], 1, state.size) then
				return false, "Off the grid"
			end
			local k = idx(state, shot[1], shot[2])
			if state.shots[seat][k] ~= 0 or seen[k] then
				return false, "You already fired there"
			end
			seen[k] = true
		end
		return true
	end
	if move.kind ~= "fire" then
		return false, "Pick a square to fire at"
	end
	if state.salvo == "all" then
		return false, "Pick all your salvo squares, then fire"
	end
	if not isInt(move.row, 1, state.size) or not isInt(move.col, 1, state.size) then
		return false, "Off the grid"
	end
	if state.shots[seat][idx(state, move.row, move.col)] ~= 0 then
		return false, "You already fired there"
	end
	return true
end

-- Salvo "all": how many squares this volley needs (shots left, or fewer squares open).
function SeaStrike.volleySize(state, seat: number): number
	local open = 0
	for _, code in state.shots[seat] do
		if code == 0 then
			open += 1
		end
	end
	return math.min(state.shotsLeft or 1, open)
end

local function fleetLeft(fleet: { [string]: any }): number
	local n = 0
	for _, ship in fleet do
		if not ship.sunk then
			n += 1
		end
	end
	return n
end

-- Shots `seat` gets this turn: 1, or (salvo) one per ship still afloat.
local function shotsFor(state, seat: number): number
	return if state.salvo then math.max(1, fleetLeft(state.fleets[seat])) else 1
end

local function startBattle(state)
	state.phase = "battle"
	state.turn = 1
	state.shotsLeft = shotsFor(state, 1)
end

local function shipAt(fleet: { [string]: any }, row: number, col: number): any?
	for _, ship in fleet do
		for _, c in cellsOf(ship) do
			if c[1] == row and c[2] == col then
				return ship
			end
		end
	end
	return nil
end

function SeaStrike.applyMove(state, seat: number, move: any)
	if state.phase == "setup" then
		if move.kind == "ready" then
			state.ready[seat] = true
			if state.ready[1] and state.ready[2] then
				startBattle(state)
			end
		elseif move.kind == "shuffle" then
			state.fleets[seat] = randomFleet(state, state.rng)
		elseif move.kind == "place" then
			local ship = state.fleets[seat][move.ship]
			ship.row, ship.col, ship.dir = move.row, move.col, move.dir
		end
		return
	end
	if move.kind == "salvo" then
		-- Every shot lands, then the turn passes (no "hit again" with a volley).
		local volley = {}
		for k = 1, #move.shots do
			local shot = move.shots[k]
			SeaStrike._shoot(state, seat, shot[1], shot[2])
			table.insert(volley, table.clone(state.lastShot))
			if state.phase ~= "battle" then
				break
			end
		end
		state.lastSalvo = volley
		if state.phase == "battle" then
			local enemy = other(seat)
			state.turn = enemy
			state.shotsLeft = shotsFor(state, enemy)
		end
		return
	end
	state.lastSalvo = nil
	local target = SeaStrike._shoot(state, seat, move.row, move.col)
	if state.phase == "battle" then
		if not (target and state.streak) then
			state.shotsLeft = (state.shotsLeft or 1) - 1
		end
		if state.shotsLeft <= 0 then
			local enemy = other(seat)
			state.turn = enemy
			state.shotsLeft = shotsFor(state, enemy)
		end
	end
end

-- One shot by `seat` at (row, col): marks it, sinks ships, ends the game. Returns the ship hit.
function SeaStrike._shoot(state, seat: number, row: number, col: number): any?
	local move = { row = row, col = col }
	local enemy = other(seat)
	local i = idx(state, move.row, move.col)
	local target = shipAt(state.fleets[enemy], move.row, move.col)
	state.shotCount += 1
	GameModule.addStat(state, seat, "shots")
	local shot: any = { n = state.shotCount, seat = seat, row = move.row, col = move.col, hit = target ~= nil }
	if target then
		state.shots[seat][i] = HIT
		target.hits += 1
		GameModule.addStat(state, seat, "hits")
		if target.hits >= target.len then
			target.sunk = true
			shot.sunk = target.id
			GameModule.addStat(state, seat, "sunk")
			for _, c in cellsOf(target) do
				state.shots[seat][idx(state, c[1], c[2])] = SUNK
			end
			-- No touching: nothing can be next to a sunk ship, so mark that water.
			if state.noTouch then
				for _, c in cellsOf(target) do
					for dr = -1, 1 do
						for dc = -1, 1 do
							local r, cc = c[1] + dr, c[2] + dc
							if r >= 1 and cc >= 1 and r <= state.size and cc <= state.size and state.shots[seat][idx(state, r, cc)] == 0 then
								state.shots[seat][idx(state, r, cc)] = WATER
							end
						end
					end
				end
			end
			if fleetLeft(state.fleets[enemy]) == 0 then
				state.phase = "over"
				state.winner = seat
			end
		end
	else
		state.shots[seat][i] = MISS
	end
	state.lastShot = shot
	return target
end

function SeaStrike.getTimer(state)
	if state.phase == "setup" then
		return { id = state.setupId, seconds = SeaStrike.SETUP_SECONDS }
	end
	return nil
end

function SeaStrike.onTimeout(state)
	if state.phase == "setup" then
		state.ready = { true, true }
		startBattle(state)
	end
end

function SeaStrike.getResult(state)
	if state.phase ~= "over" then
		return nil
	end
	return { winners = { state.winner }, isDraw = false, reason = "Sank the whole fleet" }
end

local function shipCopy(ship: any)
	return { id = ship.id, len = ship.len, row = ship.row, col = ship.col, dir = ship.dir, sunk = ship.sunk, hits = ship.hits }
end

function SeaStrike.getView(state, seat: number?)
	local boards = {}
	for s = 1, 2 do
		local sunk = {}
		for _, def in state.shipDefs do
			local ship = state.fleets[s][def.id]
			if ship and (ship.sunk or state.phase == "over") then
				table.insert(sunk, shipCopy(ship))
			end
		end
		boards[s] = {
			-- Shots that landed on seat s's grid (fired by the other player): public.
			shotsAt = table.clone(state.shots[other(s)]),
			ships = sunk, -- sunk ships (every ship once the game is over)
			left = fleetLeft(state.fleets[s]),
		}
	end
	local view: any = {
		size = state.size,
		phase = state.phase,
		turn = if state.phase == "battle" then state.turn else nil,
		ready = table.clone(state.ready),
		streak = state.streak,
		salvo = state.salvo,
		noTouch = state.noTouch,
		shotsLeft = if state.phase == "battle" then state.shotsLeft else nil,
		volley = if state.phase == "battle" and state.salvo == "all" then SeaStrike.volleySize(state, state.turn) else nil,
		lastSalvo = if state.lastSalvo then GameModule.copy(state.lastSalvo) else nil,
		shipDefs = GameModule.copy(state.shipDefs),
		boards = boards,
		lastShot = if state.lastShot then table.clone(state.lastShot) else nil,
		setupSeconds = SeaStrike.SETUP_SECONDS,
	}
	if seat == 1 or seat == 2 then
		local fleet = {}
		for _, def in state.shipDefs do
			local ship = state.fleets[seat][def.id]
			if ship then
				table.insert(fleet, shipCopy(ship))
			end
		end
		view.fleet = fleet -- your own ships, always
	end
	return view
end

function SeaStrike.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, 2 do
		if state.phase == "setup" then
			info[seat] = if state.ready[seat] then "Ready" else "Placing ships"
		else
			info[seat] = `{fleetLeft(state.fleets[seat])} ships left`
		end
	end
	return info
end

function SeaStrike.getScores(state): { [number]: number }
	local scores = {}
	for seat = 1, 2 do
		local hits = 0
		for _, code in state.shots[seat] do
			if code == HIT or code == SUNK then
				hits += 1
			end
		end
		scores[seat] = hits
	end
	return scores
end

function SeaStrike.getMatchStats(state)
	local out = {}
	for seat = 1, 2 do
		local fired, hits = 0, 0
		for _, code in state.shots[seat] do
			if code ~= 0 and code ~= WATER then
				fired += 1
			end
			if code == HIT or code == SUNK then
				hits += 1
			end
		end
		out[seat] = { accuracy = if fired > 0 then math.floor(hits / fired * 100 + 0.5) else 0 }
	end
	return out
end

---------------------------------------------------------------- bots

-- Unsunk hits on the enemy grid, as { row, col }.
local function openHits(state, seat: number): { { number } }
	local out = {}
	local shots = state.shots[seat]
	for row = 1, state.size do
		for col = 1, state.size do
			if shots[idx(state, row, col)] == HIT then
				table.insert(out, { row, col })
			end
		end
	end
	return out
end

local function unknown(state, seat: number, row: number, col: number): boolean
	return row >= 1 and col >= 1 and row <= state.size and col <= state.size and state.shots[seat][idx(state, row, col)] == 0
end

local DIRS = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }

-- Squares next to open hits; when two hits line up, prefer extending that line.
local function targets(state, seat: number, hits: { { number } }): { { number } }
	local hitSet = {}
	for _, h in hits do
		hitSet[h[1] * 100 + h[2]] = true
	end
	local line, any = {}, {}
	for _, h in hits do
		for _, d in DIRS do
			local r, c = h[1] + d[1], h[2] + d[2]
			if unknown(state, seat, r, c) then
				table.insert(any, { r, c })
				if hitSet[(h[1] - d[1]) * 100 + (h[2] - d[2])] then
					table.insert(line, { r, c })
				end
			end
		end
	end
	return if #line > 0 then line else any
end

-- Hard: how many ways the enemy's remaining ships could cover each square.
local function density(state, seat: number): { number }
	local size = state.size
	local shots = state.shots[seat]
	local enemy = state.fleets[other(seat)]
	local lengths = {}
	for _, ship in enemy do
		if not ship.sunk then
			table.insert(lengths, ship.len) -- lengths left are public (sunk ships are announced)
		end
	end
	local score = table.create(size * size, 0)
	local targeting = #openHits(state, seat) > 0
	for _, len in lengths do
		for _, dir in { "h", "v" } do
			for row = 1, size do
				for col = 1, size do
					if fits(size, row, col, dir, len) then
						local ok, covered = true, 0
						for k = 0, len - 1 do
							local r = if dir == "v" then row + k else row
							local c = if dir == "h" then col + k else col
							local code = shots[(r - 1) * size + c]
							if code == MISS or code == SUNK or code == WATER then
								ok = false
								break
							elseif code == HIT then
								covered += 1
							end
						end
						if ok and (covered > 0 or not targeting) then
							local w = if covered > 0 then 1 + covered * 20 else 1
							for k = 0, len - 1 do
								local r = if dir == "v" then row + k else row
								local c = if dir == "h" then col + k else col
								local i = (r - 1) * size + c
								if shots[i] == 0 then
									score[i] += w
								end
							end
						end
					end
				end
			end
		end
	end
	return score
end

-- With `parity`, only every k-th diagonal, k = the shortest enemy ship still afloat
-- (a Destroyer fits in any two squares in a row; once it's gone, every third will do).
local function randomUnknown(state, seat: number, rng: Random, parity: boolean): { number }?
	local step = 2
	if parity then
		step = 99
		for _, ship in state.fleets[other(seat)] do
			if not ship.sunk then
				step = math.min(step, ship.len)
			end
		end
		if step == 99 then
			step = 2
		end
	end
	local options = {}
	for row = 1, state.size do
		for col = 1, state.size do
			if unknown(state, seat, row, col) and (not parity or (row + col) % step == 0) then
				table.insert(options, { row, col })
			end
		end
	end
	if #options == 0 then
		if parity then
			return randomUnknown(state, seat, rng, false)
		end
		return nil
	end
	return options[rng:NextInteger(1, #options)]
end

local PENDING = 5 -- a square already picked for this volley (bots only, never stored)

local chooseShot: (state: any, seat: number, rng: Random, level: string) -> { number }?

local function botMove(state, seat: number, rng: Random, level: string): any?
	if not isActive(state, seat) then
		return nil
	end
	if state.phase == "setup" then
		return { kind = "ready" }
	end
	if state.salvo == "all" then
		-- Pick the whole volley, one square at a time, each pick seeing the earlier ones.
		local shots = state.shots[seat]
		local picked = {}
		for _ = 1, SeaStrike.volleySize(state, seat) do
			local pick = chooseShot(state, seat, rng, level)
			if not pick then
				break
			end
			table.insert(picked, pick)
			shots[idx(state, pick[1], pick[2])] = PENDING
		end
		for _, pick in picked do
			shots[idx(state, pick[1], pick[2])] = 0
		end
		return { kind = "salvo", shots = picked }
	end
	local pick = chooseShot(state, seat, rng, level)
	if not pick then
		return nil
	end
	return { kind = "fire", row = pick[1], col = pick[2] }
end

function SeaStrike.chooseBotMove(state, seat: number, rng: Random): any?
	return botMove(state, seat, rng, state.botLevel)
end

-- A player who's away or out of time gets a medium-strength shot, never the table's
-- hard bot (and in setup, their fleet as it is).
function SeaStrike.chooseAfkMove(state, seat: number, rng: Random): any?
	return botMove(state, seat, rng, if state.botLevel == "easy" then "easy" else "medium")
end

function chooseShot(state, seat: number, rng: Random, level: string): { number }?
	local hits = openHits(state, seat)
	local pick: { number }? = nil
	if level == "hard" then
		local score = density(state, seat)
		local best, bestList = -1, {}
		for i, v in score do
			if state.shots[seat][i] == 0 then
				if v > best then
					best, bestList = v, { i }
				elseif v == best then
					table.insert(bestList, i)
				end
			end
		end
		if #bestList > 0 then
			local i = bestList[rng:NextInteger(1, #bestList)]
			pick = { (i - 1) // state.size + 1, (i - 1) % state.size + 1 }
		end
	elseif #hits > 0 and (level == "medium" or rng:NextNumber() < 0.45) then
		local list = targets(state, seat, hits)
		if level == "easy" then
			-- Easy doesn't follow lines: any square next to a hit.
			list = {}
			for _, h in hits do
				for _, d in DIRS do
					if unknown(state, seat, h[1] + d[1], h[2] + d[2]) then
						table.insert(list, { h[1] + d[1], h[2] + d[2] })
					end
				end
			end
		end
		if #list > 0 then
			pick = list[rng:NextInteger(1, #list)]
		end
	end
	if not pick then
		pick = randomUnknown(state, seat, rng, level == "medium")
	end
	return pick
end

function SeaStrike.getBotDelay(state, seat: number, rng: Random): number
	if state.phase == "setup" then
		return 2 + rng:NextNumber() * 3 -- "placing ships"
	end
	local hits = openHits(state, seat)
	return BotThink.delay(rng, if #hits > 0 then 3 else 8, { base = 0.8, max = 2.2 })
end

return SeaStrike
