local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Conquest = require(ReplicatedStorage.Shared.Games.Conquest)
local GameModule = require(ReplicatedStorage.Shared.GameModule)

return function(T)
	local N = #Conquest.territories

	local function idOf(name: string): number
		for t, territory in Conquest.territories do
			if territory.name == name then
				return t
			end
		end
		error(`No territory {name}`)
	end

	local function play(s, seat, move)
		local ok, err = Conquest.validateMove(s, seat, move)
		assert(ok, err)
		Conquest.applyMove(s, seat, move)
	end

	local function rejects(s, seat, move, message)
		local ok = Conquest.validateMove(s, seat, move)
		T.eq(ok, false, message)
	end

	-- Dice that come out in a fixed order.
	local function scripted(values)
		local i = 0
		return {
			NextInteger = function(_, lo, hi)
				i += 1
				local v = values[i]
				assert(v, "ran out of scripted dice")
				return math.clamp(v, lo, hi)
			end,
			NextNumber = function()
				return 0.5
			end,
		}
	end

	-- A 2-seat game where seat 1 owns everything listed and seat 2 owns the rest.
	local function fixedGame(mine: { [string]: number }, theirs: { [string]: number }?)
		local s = Conquest.new(2, { botLevel = "medium" }, T.Random.new(1))
		for t = 1, N do
			s.owner[t] = 2
			s.armies[t] = 1
		end
		for name, armies in mine do
			s.owner[idOf(name)] = 1
			s.armies[idOf(name)] = armies
		end
		for name, armies in theirs or {} do
			s.armies[idOf(name)] = armies
		end
		s.turn = 1
		s.phase = "attack"
		s.reinforcements = 0
		return s
	end

	T.test("the map is connected and links are two-way", function()
		T.eq(N, 24)
		local seen = { [1] = true }
		local queue = { 1 }
		while #queue > 0 do
			local t = table.remove(queue)
			for _, n in Conquest.neighbors[t] do
				T.ok(Conquest.areNeighbors(n, t), "links go both ways")
				if not seen[n] then
					seen[n] = true
					table.insert(queue, n)
				end
			end
		end
		for t = 1, N do
			T.ok(seen[t], `{Conquest.territories[t].name} is reachable`)
		end
		local total = 0
		for _, members in Conquest.regionMembers do
			total += #members
		end
		T.eq(total, N)
	end)

	T.test("setup deals every territory and gives each seat the same armies", function()
		for seats = 2, 6 do
			local s = Conquest.new(seats, {}, T.Random.new(seats))
			local armies = {}
			for t = 1, N do
				T.ok(s.owner[t] >= 1 and s.owner[t] <= seats)
				T.ok(s.armies[t] >= 1)
				armies[s.owner[t]] = (armies[s.owner[t]] or 0) + s.armies[t]
			end
			for seat = 2, seats do
				T.eq(armies[seat], armies[1])
			end
			T.eq(s.phase, "reinforce")
			T.eq(s.reinforcements, Conquest.income(s.owner, 1))
		end
	end)

	T.test("income: territories / 3 (min 3) plus whole regions", function()
		local owner = table.create(N, 2)
		for t = 1, 12 do
			owner[t] = 3
		end
		owner[13] = 1
		-- 1 territory (well under the average of 8): 3, plus the catch-up rally
		T.ok(Conquest.isRallying(owner, 1))
		T.eq(Conquest.income(owner, 1), 3 + Conquest.RALLY_ARMIES)
		-- 12 of 24 with two players: no rally, 12 / 3 = 4
		T.eq(Conquest.isRallying(owner, 3), false)
		T.eq(Conquest.income(owner, 3), 4 + Conquest.regions[1].bonus + Conquest.regions[2].bonus)
		local two = table.create(N, 2)
		for t = 1, 12 do
			two[t] = 1
		end
		T.eq(Conquest.income(two, 1), 4 + Conquest.regions[1].bonus + Conquest.regions[2].bonus, "even split, no rally")
	end)

	T.test("card sets", function()
		local v = Conquest.setValues
		T.eq(Conquest.setValue({ "sword", "sword", "sword" }), v.sword)
		T.eq(Conquest.setValue({ "crown", "crown", "crown" }), v.crown)
		T.eq(Conquest.setValue({ "sword", "shield", "crown" }), v.mixed)
		T.eq(Conquest.setValue({ "sword", "wild", "crown" }), v.mixed)
		T.eq(Conquest.setValue({ "crown", "crown", "wild" }), v.crown, "two of a kind plus a wild is three of a kind")
		T.eq(Conquest.setValue({ "sword", "sword", "crown" }), nil)
		T.eq(Conquest.setValue({ "sword", "sword" }), nil)
		T.eq(Conquest.setValue({ "sword", "sword", "bogus" }), nil)
		-- Any 5 cards hold a set.
		local idx = Conquest.bestSet({ "sword", "sword", "shield", "shield", "crown" })
		T.ok(idx ~= nil)
	end)

	T.test("placing armies, then attacking", function()
		local s = Conquest.new(2, {}, T.Random.new(3))
		local mine
		for t = 1, N do
			if s.owner[t] == 1 then
				mine = t
			end
		end
		local enemy = if s.owner[1] == 2 then 1 else nil
		rejects(s, 2, { kind = "place", territory = mine, count = 1 }, "not their turn")
		if enemy then
			rejects(s, 1, { kind = "place", territory = enemy, count = 1 }, "enemy territory")
		end
		rejects(s, 1, { kind = "place", territory = mine, count = s.reinforcements + 1 }, "too many")
		rejects(s, 1, { kind = "place", territory = mine, count = 0.5 }, "fractions")
		rejects(s, 1, { kind = "endTurn" }, "must place first")
		rejects(s, 1, { kind = "place", territory = "1", count = 1 }, "types")
		local before = s.armies[mine]
		local n = s.reinforcements
		play(s, 1, { kind = "place", territory = mine, count = n })
		T.eq(s.armies[mine], before + n)
		T.eq(s.phase, "attack")
	end)

	T.test("attack rules and dice", function()
		local s = fixedGame({ ["Elder Grove"] = 4, ["Icefang"] = 1 })
		local eg, moss, ice = idOf("Elder Grove"), idOf("Mossbrook"), idOf("Icefang")
		rejects(s, 1, { kind = "attack", from = ice, to = idOf("Snowmere") }, "needs 2 armies")
		rejects(s, 1, { kind = "attack", from = eg, to = idOf("Ashpeak") }, "not a neighbour")
		rejects(s, 1, { kind = "attack", from = moss, to = eg }, "not your territory")
		s.armies[moss] = 2
		-- Attacker rolls 3 (6,6,1), defender 2 (5,6): 6>6? no (tie, defender), 6>5 yes.
		-- Sorted: attacker 6,6,1 vs defender 6,5 -> 6 vs 6 defender wins, 6 vs 5 attacker wins.
		s.rng = scripted({ 6, 6, 1, 5, 6 })
		play(s, 1, { kind = "attack", from = eg, to = moss })
		T.eq(s.armies[eg], 3)
		T.eq(s.armies[moss], 1)
		T.eq(s.lastBattle.attackerLost, 1)
		T.eq(s.lastBattle.defenderLost, 1)
		T.eq(s.owner[moss], 2)
	end)

	T.test("conquering: occupy choice, then a card at the end of the turn", function()
		local s = fixedGame({ ["Elder Grove"] = 6 })
		local eg, moss = idOf("Elder Grove"), idOf("Mossbrook")
		s.rng = scripted({ 6, 6, 6, 1 })
		play(s, 1, { kind = "attack", from = eg, to = moss })
		T.eq(s.owner[moss], 1)
		T.eq(s.phase, "occupy")
		T.eq(s.occupy.min, 3)
		T.eq(s.occupy.max, 5)
		rejects(s, 1, { kind = "occupy", count = 2 }, "at least the dice rolled")
		rejects(s, 1, { kind = "endTurn" }, "occupy first")
		play(s, 1, { kind = "occupy", count = 4 })
		T.eq(s.armies[moss], 4)
		T.eq(s.armies[eg], 2)
		T.eq(s.phase, "attack")
		local cards = #s.hands[1]
		play(s, 1, { kind = "endTurn" })
		T.eq(#s.hands[1], cards + 1)
		T.eq(s.turn, 2)
	end)

	T.test("blitz rolls until the territory falls or the attacker runs out", function()
		local s = fixedGame({ ["Elder Grove"] = 2 }, { ["Mossbrook"] = 3 })
		local eg, moss = idOf("Elder Grove"), idOf("Mossbrook")
		-- 1 die vs 2 dice; attacker always loses
		s.rng = scripted({ 1, 6, 6 })
		play(s, 1, { kind = "attack", from = eg, to = moss, blitz = true })
		T.eq(s.armies[eg], 1)
		T.eq(s.lastBattle.rolls, 1)
		rejects(s, 1, { kind = "attack", from = eg, to = moss, blitz = true }, "down to 1")
	end)

	T.test("fortify only through your own land, and it ends the turn", function()
		local s = fixedGame({ ["Icefang"] = 5, ["Snowmere"] = 1, ["Whitepine"] = 1, ["Saltcliff"] = 3 })
		local ice, white, salt = idOf("Icefang"), idOf("Whitepine"), idOf("Saltcliff")
		rejects(s, 1, { kind = "fortify", from = ice, to = salt, count = 1 }, "not connected")
		rejects(s, 1, { kind = "fortify", from = ice, to = white, count = 5 }, "one stays")
		play(s, 1, { kind = "fortify", from = ice, to = white, count = 4 })
		T.eq(s.armies[white], 5)
		T.eq(s.armies[ice], 1)
		T.eq(s.turn, 2)
		T.eq(s.phase, "reinforce")
	end)

	T.test("five cards force a trade before placing", function()
		local s = Conquest.new(2, {}, T.Random.new(5))
		s.hands[1] = { "sword", "sword", "shield", "crown", "crown" }
		local mine
		for t = 1, N do
			if s.owner[t] == 1 then
				mine = t
			end
		end
		rejects(s, 1, { kind = "place", territory = mine, count = 1 }, "must trade")
		rejects(s, 1, { kind = "trade", cards = { 1, 2, 5 } }, "not a set")
		rejects(s, 1, { kind = "trade", cards = { 1, 1, 3 } }, "same card twice")
		local before = s.reinforcements
		play(s, 1, { kind = "trade", cards = { 1, 3, 4 } })
		T.eq(s.reinforcements, before + Conquest.setValues.mixed)
		T.eq(#s.hands[1], 2)
		play(s, 1, { kind = "place", territory = mine, count = s.reinforcements })
		T.eq(s.phase, "attack")
	end)

	T.test("knocking a player out takes their cards and can win the game", function()
		local s = Conquest.new(3, {}, T.Random.new(9))
		for t = 1, N do
			s.owner[t] = 1
			s.armies[t] = 1
		end
		local eg, moss, ice = idOf("Elder Grove"), idOf("Mossbrook"), idOf("Icefang")
		s.owner[moss] = 2
		s.owner[ice] = 3
		s.armies[eg] = 4
		s.hands[2] = { "sword", "shield" }
		s.turn, s.phase = 1, "attack"
		s.rng = scripted({ 6, 6, 6, 1 })
		play(s, 1, { kind = "attack", from = eg, to = moss })
		T.ok(s.eliminated[2])
		T.eq(#s.hands[1], 2)
		T.eq(Conquest.getResult(s), nil)
		-- With 3 armies left on Elder Grove and 3 dice rolled, all 3 can't move: auto-occupy.
		T.eq(s.phase, "attack")
		local snow = idOf("Snowmere")
		s.armies[snow] = 3
		s.rng = scripted({ 6, 6, 1 })
		play(s, 1, { kind = "attack", from = snow, to = ice })
		local result = Conquest.getResult(s)
		T.ok(result ~= nil)
		T.eq(result.winners[1], 1)
		T.eq(#Conquest.getActiveSeats(s), 0)
	end)

	T.test("eliminated seats are skipped", function()
		local s = Conquest.new(3, {}, T.Random.new(2))
		s.eliminated[2] = true
		for t = 1, N do
			if s.owner[t] == 2 then
				s.owner[t] = 3
			end
		end
		s.phase = "attack"
		play(s, 1, { kind = "endTurn" })
		T.eq(s.turn, 3)
	end)

	T.test("the round limit ends the game: most territories wins", function()
		local s = Conquest.new(2, {}, T.Random.new(4))
		s.round = s.maxRounds
		s.turn = 2
		s.phase = "attack"
		s.owner[1], s.owner[2], s.owner[3] = 2, 2, 2
		play(s, 2, { kind = "endTurn" })
		local result = Conquest.getResult(s)
		T.ok(result ~= nil)
		local counts = Conquest.getScores(s)
		local best = if counts[1] > counts[2] then 1 else 2
		if counts[1] ~= counts[2] then
			T.eq(result.winners[1], best)
		end
	end)

	T.test("the turn clock finishes the turn for you", function()
		local s = Conquest.new(2, {}, T.Random.new(6))
		local timer = Conquest.getTimer(s)
		T.ok(timer ~= nil)
		local id = timer.id
		Conquest.onTimeout(s)
		T.eq(s.turn, 2)
		T.ok(Conquest.getTimer(s).id ~= id)
		-- Nothing is lost: every army placed.
		local total = 0
		for t = 1, N do
			total += s.armies[t]
		end
		T.ok(total > 0)
	end)

	T.test("the view hides other hands", function()
		local s = Conquest.new(3, {}, T.Random.new(7))
		s.hands[2] = { "crown" }
		local view = Conquest.getView(s, 1)
		T.eq(#view.hand, 0)
		T.eq(view.handCounts[2], 1)
		T.eq(view.rng, nil)
		T.eq(Conquest.getView(s, nil).hand, nil)
	end)

	T.test("bot-only games always finish, with no army or card lost", function()
		for _, level in { "easy", "medium", "hard" } do
			for seed = 1, 5 do
				local seats = 2 + (seed - 1) % 5
				local rng = T.Random.new(seed * 17 + #level)
				local s = Conquest.new(seats, { botLevel = level }, rng)
				local moves = 0
				while not Conquest.getResult(s) do
					local seat = Conquest.getActiveSeats(s)[1]
					local move = GameModule.chooseBotMove(Conquest, s, seat, rng)
					assert(move, `bot had no move in phase {s.phase}`)
					local ok, err = Conquest.validateMove(s, seat, move)
					assert(ok, `{level} bot made a bad {move.kind}: {err}`)
					Conquest.applyMove(s, seat, move)
					moves += 1
					assert(moves < 20000, "game never ended")
					for t = 1, N do
						assert(s.armies[t] >= 1 or s.phase == "occupy", "a territory was left empty")
						assert(not s.eliminated[s.owner[t]], "a knocked-out seat still owns land")
					end
					local cards = #s.deck + #s.discard
					for seat2 = 1, seats do
						cards += #s.hands[seat2]
					end
					assert(cards == 26, "cards went missing")
				end
				T.ok(#Conquest.getResult(s).winners >= 1)
			end
		end
	end)
end
