local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SeaStrike = require(ReplicatedStorage.Shared.Games.SeaStrike)

return function(T)
	local function fixedFleet(s, seat)
		-- Ships in rows 1-5 from column 1, all across.
		local row = 1
		for _, def in s.shipDefs do
			s.fleets[seat][def.id] = { id = def.id, len = def.len, row = row, col = 1, dir = "h", hits = 0, sunk = false }
			row += 1
		end
	end

	local function battle(rules: any?)
		local s = SeaStrike.new(2, { rules = rules }, T.Random.new(5))
		fixedFleet(s, 1)
		fixedFleet(s, 2)
		SeaStrike.applyMove(s, 1, { kind = "ready" })
		SeaStrike.applyMove(s, 2, { kind = "ready" })
		return s
	end

	T.test("random fleets fit and don't overlap", function()
		for seed = 1, 20 do
			local s = SeaStrike.new(2, nil, T.Random.new(seed))
			for seat = 1, 2 do
				local seen, count = {}, 0
				for _, ship in s.fleets[seat] do
					for _, c in SeaStrike.cellsOf(ship) do
						T.ok(c[1] >= 1 and c[1] <= 10 and c[2] >= 1 and c[2] <= 10, "on the grid")
						T.ok(not seen[c[1] * 100 + c[2]], "no overlap")
						seen[c[1] * 100 + c[2]] = true
						count += 1
					end
				end
				T.eq(count, 17)
			end
		end
	end)

	T.test("setup: move ships, overlap and edges rejected, battle starts when both ready", function()
		local s = SeaStrike.new(2, nil, T.Random.new(1))
		fixedFleet(s, 1)
		T.eq((SeaStrike.validateMove(s, 1, { kind = "place", ship = "destroyer", row = 1, col = 3, dir = "h" })), false, "overlaps the carrier")
		T.eq((SeaStrike.validateMove(s, 1, { kind = "place", ship = "carrier", row = 1, col = 8, dir = "h" })), false, "off the edge")
		T.eq((SeaStrike.validateMove(s, 1, { kind = "place", ship = "carrier", row = 1, col = 1, dir = "d" })), false)
		T.ok(SeaStrike.validateMove(s, 1, { kind = "place", ship = "destroyer", row = 9, col = 9, dir = "v" }))
		SeaStrike.applyMove(s, 1, { kind = "place", ship = "destroyer", row = 9, col = 9, dir = "v" })
		T.eq(s.fleets[1].destroyer.row, 9)
		T.eq((SeaStrike.validateMove(s, 1, { kind = "fire", row = 1, col = 1 })), false, "no firing in setup")
		SeaStrike.applyMove(s, 1, { kind = "ready" })
		T.eq(s.phase, "setup")
		T.eq((SeaStrike.validateMove(s, 1, { kind = "shuffle" })), false, "already ready")
		SeaStrike.applyMove(s, 2, { kind = "ready" })
		T.eq(s.phase, "battle")
		T.eq(SeaStrike.getTimer(s), nil)
	end)

	T.test("setup clock readies everyone", function()
		local s = SeaStrike.new(2, nil, T.Random.new(1))
		T.ok(SeaStrike.getTimer(s) ~= nil)
		SeaStrike.onTimeout(s)
		T.eq(s.phase, "battle")
	end)

	T.test("fire: miss passes the turn, repeat squares and bad input rejected", function()
		local s = battle()
		T.eq((SeaStrike.validateMove(s, 2, { kind = "fire", row = 9, col = 9 })), false, "not seat 2's turn")
		SeaStrike.applyMove(s, 1, { kind = "fire", row = 9, col = 9 })
		T.eq(s.shots[1][(9 - 1) * 10 + 9], SeaStrike.MISS)
		T.eq(s.turn, 2)
		SeaStrike.applyMove(s, 2, { kind = "fire", row = 10, col = 10 })
		T.eq((SeaStrike.validateMove(s, 1, { kind = "fire", row = 9, col = 9 })), false, "already fired there")
		for _, move in { { kind = "fire", row = 0, col = 1 }, { kind = "fire", row = 1.5, col = 1 }, { kind = "fire", row = "1", col = 1 }, { kind = "fire" }, { kind = "ready" }, 5 } do
			T.eq((SeaStrike.validateMove(s, 1, move)), false)
		end
	end)

	T.test("sinking a ship marks it sunk and reveals it; whole fleet wins", function()
		local s = battle()
		local n = 0
		local function seatTwoMisses()
			-- Rows 6-10 of seat 1's grid are empty water.
			SeaStrike.applyMove(s, 2, { kind = "fire", row = 6 + n // 10, col = n % 10 + 1 })
			n += 1
		end
		SeaStrike.applyMove(s, 1, { kind = "fire", row = 5, col = 1 })
		T.eq(s.lastShot.hit, true)
		seatTwoMisses()
		SeaStrike.applyMove(s, 1, { kind = "fire", row = 5, col = 2 })
		T.eq(s.lastShot.sunk, "destroyer")
		T.eq(s.shots[1][(5 - 1) * 10 + 1], SeaStrike.SUNK)
		local view = SeaStrike.getView(s, 1)
		T.eq(#view.boards[2].ships, 1, "the sunk destroyer is shown")
		T.eq(view.boards[2].left, 4)
		-- Sink the rest.
		for row = 1, 4 do
			for col = 1, s.fleets[2][s.shipDefs[row].id].len do
				if s.phase ~= "battle" then
					break
				end
				seatTwoMisses()
				SeaStrike.applyMove(s, 1, { kind = "fire", row = row, col = col })
			end
		end
		local result = SeaStrike.getResult(s)
		T.ok(result ~= nil)
		T.eq(result.winners[1], 1)
	end)

	T.test("hit again house rule keeps the turn on a hit", function()
		local s = battle({ streak = true })
		SeaStrike.applyMove(s, 1, { kind = "fire", row = 1, col = 1 })
		T.eq(s.turn, 1)
		SeaStrike.applyMove(s, 1, { kind = "fire", row = 9, col = 9 })
		T.eq(s.turn, 2)
	end)

	T.test("quick ocean is 8x8 with 4 ships", function()
		local s = SeaStrike.new(2, { rules = { size = 8 } }, T.Random.new(2))
		T.eq(s.size, 8)
		T.eq(#s.shipDefs, 4)
		T.eq(s.fleets[1].carrier, nil)
	end)

	T.test("views never show the other fleet before it sinks", function()
		local s = battle()
		local view = SeaStrike.getView(s, 1)
		T.eq(#view.fleet, 5, "your own ships")
		T.eq(#view.boards[2].ships, 0, "no enemy ships")
		local spectator = SeaStrike.getView(s, nil)
		T.eq(spectator.fleet, nil)
		T.eq(#spectator.boards[1].ships, 0)
		T.eq(spectator.rng, nil)
	end)

	T.test("bots follow up a hit", function()
		for _, level in { "medium", "hard" } do
			local s = battle()
			s.botLevel = level
			SeaStrike.applyMove(s, 1, { kind = "fire", row = 3, col = 2 }) -- hits the cruiser
			SeaStrike.applyMove(s, 2, { kind = "fire", row = 10, col = 10 })
			local move = SeaStrike.chooseBotMove(s, 1, T.Random.new(3))
			T.eq(move.kind, "fire")
			T.eq(math.abs(move.row - 3) + math.abs(move.col - 2), 1, `{level} fires next to the hit`)
		end
	end)

	T.test("no touching: random fleets keep a square apart, placement checks it", function()
		for seed = 1, 15 do
			local s = SeaStrike.new(2, { rules = { noTouch = true } }, T.Random.new(seed))
			for seat = 1, 2 do
				local owner = {}
				for _, ship in s.fleets[seat] do
					for _, c in SeaStrike.cellsOf(ship) do
						owner[c[1] * 100 + c[2]] = ship.id
					end
				end
				for key, id in owner do
					local r, c = key // 100, key % 100
					for dr = -1, 1 do
						for dc = -1, 1 do
							local other = owner[(r + dr) * 100 + (c + dc)]
							T.ok(other == nil or other == id, `seed {seed}: ships touch`)
						end
					end
				end
			end
		end
		local s = SeaStrike.new(2, { rules = { noTouch = true } }, T.Random.new(1))
		fixedFleet(s, 1) -- rows 1-5 touch each other
		-- Ships every other row; the destroyer can't go next to the sub, even corner to corner.
		for _, ship in s.fleets[1] do
			ship.row = ({ carrier = 1, battleship = 3, cruiser = 5, sub = 7, destroyer = 9 })[ship.id]
		end
		T.eq((SeaStrike.validateMove(s, 1, { kind = "place", ship = "destroyer", row = 8, col = 1, dir = "h" })), false, "touches the submarine")
		T.eq((SeaStrike.validateMove(s, 1, { kind = "place", ship = "destroyer", row = 8, col = 4, dir = "v" })), false, "diagonal touch")
		T.ok(SeaStrike.validateMove(s, 1, { kind = "place", ship = "destroyer", row = 9, col = 8, dir = "h" }))
	end)

	T.test("no touching: sinking a ship marks the water around it", function()
		local s = SeaStrike.new(2, { rules = { noTouch = true } }, T.Random.new(1))
		-- A legal no-touch fleet: every other row, from column 1.
		for seat = 1, 2 do
			local row = 1
			for _, def in s.shipDefs do
				s.fleets[seat][def.id] = { id = def.id, len = def.len, row = row, col = 1, dir = "h", hits = 0, sunk = false }
				row += 2
			end
		end
		SeaStrike.applyMove(s, 1, { kind = "ready" })
		SeaStrike.applyMove(s, 2, { kind = "ready" })
		-- Seat 2's destroyer is on row 9, columns 1-2.
		SeaStrike.applyMove(s, 1, { kind = "fire", row = 9, col = 1 })
		SeaStrike.applyMove(s, 2, { kind = "fire", row = 10, col = 10 })
		SeaStrike.applyMove(s, 1, { kind = "fire", row = 9, col = 2 })
		T.eq(s.lastShot.sunk, "destroyer")
		T.eq(s.shots[1][(10 - 1) * 10 + 1], SeaStrike.WATER, "below it")
		T.eq(s.shots[1][(8 - 1) * 10 + 3], SeaStrike.WATER, "diagonal")
		T.eq(s.shots[1][(9 - 1) * 10 + 3], SeaStrike.WATER, "end")
		T.eq(s.shots[1][(7 - 1) * 10 + 1], 0, "the submarine's row is untouched")
		T.eq(s.turn, 2)
		SeaStrike.applyMove(s, 2, { kind = "fire", row = 10, col = 9 })
		T.eq((SeaStrike.validateMove(s, 1, { kind = "fire", row = 10, col = 1 })), false, "known water can't be fired at")
		T.eq(SeaStrike.getScores(s)[1], 2, "water isn't a hit")
		T.eq(SeaStrike.getMatchStats(s)[1].accuracy, 100, "nor a shot: 2 for 2")
	end)

	T.test("salvo one at a time: a shot per ship left", function()
		local s = battle({ salvo = true })
		T.eq(s.shotsLeft, 5)
		SeaStrike.applyMove(s, 1, { kind = "fire", row = 9, col = 9 })
		T.eq(s.turn, 1)
		T.eq(s.shotsLeft, 4)
	end)

	T.test("salvo call them all: one move fires every square, then the turn passes", function()
		local s = battle({ salvo = "all" })
		T.eq(SeaStrike.volleySize(s, 1), 5)
		T.eq((SeaStrike.validateMove(s, 1, { kind = "fire", row = 9, col = 9 })), false, "single shots are off")
		local five = { { 5, 1 }, { 5, 2 }, { 9, 9 }, { 9, 8 }, { 10, 10 } }
		T.eq((SeaStrike.validateMove(s, 1, { kind = "salvo", shots = { { 9, 9 } } })), false, "too few")
		T.eq((SeaStrike.validateMove(s, 1, { kind = "salvo", shots = { { 9, 9 }, { 9, 9 }, { 9, 8 }, { 9, 7 }, { 9, 6 } } })), false, "repeats")
		T.eq((SeaStrike.validateMove(s, 1, { kind = "salvo", shots = { { 0, 9 }, { 9, 9 }, { 9, 8 }, { 9, 7 }, { 9, 6 } } })), false, "off the grid")
		T.eq((SeaStrike.validateMove(s, 1, { kind = "salvo", shots = "x" })), false)
		T.ok(SeaStrike.validateMove(s, 1, { kind = "salvo", shots = five }))
		SeaStrike.applyMove(s, 1, { kind = "salvo", shots = five })
		T.eq(#s.lastSalvo, 5)
		T.eq(s.fleets[2].destroyer.sunk, true, "both destroyer squares hit")
		T.eq(s.turn, 2)
		T.eq(SeaStrike.volleySize(s, 2), 4, "seat 2 lost its destroyer: four shots")
		local view = SeaStrike.getView(s, 2)
		T.eq(view.volley, 4)
		T.eq(#view.lastSalvo, 5)
		local legal = SeaStrike.getLegalMoves(s, 2)
		T.eq(#legal, 1)
		T.eq(legal[1].kind, "salvo")
		T.ok(SeaStrike.validateMove(s, 2, legal[1]))
		SeaStrike.applyMove(s, 2, legal[1])
		T.eq(s.turn, 1)
		T.eq(s.shotsLeft, 5, "seat 1 still has all five ships")
	end)

	T.test("salvo call them all: bots pick a full volley of different squares", function()
		for _, level in { "easy", "medium", "hard" } do
			local s = battle({ salvo = "all" })
			s.botLevel = level
			local move = SeaStrike.chooseBotMove(s, 1, T.Random.new(4))
			T.eq(move.kind, "salvo")
			T.eq(#move.shots, 5)
			T.ok(SeaStrike.validateMove(s, 1, move), `{level} volley is legal`)
			for _, code in s.shots[1] do
				T.eq(code, 0, "the bot's picks don't stay on the board")
			end
		end
	end)

	T.test("an away player fires at medium strength, even at a hard table", function()
		local s = battle()
		s.botLevel = "hard"
		SeaStrike.applyMove(s, 1, { kind = "fire", row = 3, col = 2 })
		SeaStrike.applyMove(s, 2, { kind = "fire", row = 10, col = 10 })
		local move = SeaStrike.chooseAfkMove(s, 1, T.Random.new(9))
		T.eq(move.kind, "fire")
		T.eq(math.abs(move.row - 3) + math.abs(move.col - 2), 1, "still follows up the hit")
		local fresh = SeaStrike.new(2, nil, T.Random.new(2))
		T.eq(SeaStrike.chooseAfkMove(fresh, 1, T.Random.new(1)).kind, "ready", "setup: keeps the fleet as it is")
	end)

	T.test("medium hunts on a grid as wide as the smallest ship left", function()
		local s = battle()
		s.botLevel = "medium"
		-- Sink seat 2's destroyer (row 5): the smallest left is then 3 long.
		s.fleets[2].destroyer.sunk = true
		s.shots[1][(5 - 1) * 10 + 1] = SeaStrike.SUNK
		s.shots[1][(5 - 1) * 10 + 2] = SeaStrike.SUNK
		for seed = 1, 20 do
			local move = SeaStrike.chooseBotMove(s, 1, T.Random.new(seed))
			T.eq((move.row + move.col) % 3, 0, "every third diagonal")
		end
	end)
end
