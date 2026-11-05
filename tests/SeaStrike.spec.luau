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
end
