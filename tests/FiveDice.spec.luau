local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FiveDice = require(ReplicatedStorage.Shared.Games.FiveDice)

return function(T)
	local ALL_FALSE = { false, false, false, false, false }

	local function rolledState(seats: number?, rules: any?)
		local s = FiveDice.new(seats or 2, { rules = rules }, T.Random.new(7))
		FiveDice.applyMove(s, 1, { kind = "roll" })
		return s
	end

	T.test("box scores", function()
		T.eq(FiveDice.score("threes", { 3, 3, 1, 3, 6 }), 9)
		T.eq(FiveDice.score("three", { 2, 2, 2, 5, 6 }), 17)
		T.eq(FiveDice.score("three", { 2, 2, 1, 5, 6 }), 0)
		T.eq(FiveDice.score("four", { 4, 4, 4, 4, 1 }), 17)
		T.eq(FiveDice.score("house", { 3, 3, 5, 5, 5 }), 25)
		T.eq(FiveDice.score("house", { 5, 5, 5, 5, 5 }), 0, "five of a kind isn't a full house")
		T.eq(FiveDice.score("small", { 1, 2, 3, 4, 6 }), 30)
		T.eq(FiveDice.score("small", { 3, 4, 5, 6, 6 }), 30)
		T.eq(FiveDice.score("small", { 1, 2, 3, 5, 6 }), 0)
		T.eq(FiveDice.score("large", { 2, 3, 4, 5, 6 }), 40)
		T.eq(FiveDice.score("large", { 1, 2, 3, 4, 6 }), 0)
		T.eq(FiveDice.score("big", { 6, 6, 6, 6, 6 }), 50)
		T.eq(FiveDice.score("chance", { 1, 2, 3, 4, 6 }), 16)
	end)

	T.test("one turn keeps one turn key, so the AFK clock runs once per turn", function()
		local s = FiveDice.new(2, nil, T.Random.new(1))
		local key = FiveDice.getTurnKey(s)
		FiveDice.applyMove(s, 1, { kind = "roll" })
		FiveDice.applyMove(s, 1, { kind = "hold", held = { true, false, false, false, false } })
		FiveDice.applyMove(s, 1, { kind = "hold", held = { false, false, false, false, false } })
		FiveDice.applyMove(s, 1, { kind = "roll" })
		T.eq(FiveDice.getTurnKey(s), key, "rolls and holds are the same turn")
		FiveDice.applyMove(s, 1, { kind = "score", box = "chance" })
		T.ok(FiveDice.getTurnKey(s) ~= key, "scoring starts the next turn")
	end)

	T.test("turn order: roll first, three rolls, then score passes the turn", function()
		local s = FiveDice.new(2, nil, T.Random.new(1))
		T.eq((FiveDice.validateMove(s, 1, { kind = "score", box = "chance" })), false, "must roll first")
		T.eq((FiveDice.validateMove(s, 2, { kind = "roll" })), false, "not seat 2's turn")
		for _ = 1, 3 do
			T.ok(FiveDice.validateMove(s, 1, { kind = "roll", held = ALL_FALSE }))
			FiveDice.applyMove(s, 1, { kind = "roll", held = ALL_FALSE })
		end
		T.eq((FiveDice.validateMove(s, 1, { kind = "roll" })), false, "only three rolls")
		T.ok(FiveDice.validateMove(s, 1, { kind = "score", box = "chance" }))
		FiveDice.applyMove(s, 1, { kind = "score", box = "chance" })
		T.eq(FiveDice.getActiveSeats(s)[1], 2)
		T.eq(s.round, 1)
		FiveDice.applyMove(s, 2, { kind = "roll" })
		FiveDice.applyMove(s, 2, { kind = "score", box = "ones" })
		T.eq(s.round, 2)
		T.eq(FiveDice.getActiveSeats(s)[1], 1)
	end)

	T.test("held dice don't change", function()
		local s = rolledState()
		local before = table.clone(s.players[1].dice)
		local held = { true, false, true, false, false }
		FiveDice.applyMove(s, 1, { kind = "roll", held = held })
		T.eq(s.players[1].dice[1], before[1])
		T.eq(s.players[1].dice[3], before[3])
		T.eq((FiveDice.validateMove(s, 1, { kind = "roll", held = { true, true, true, true, true } })), false, "can't hold all and roll")
	end)

	T.test("bad moves from the network are rejected", function()
		local s = rolledState()
		for _, move in {
			{ kind = "roll", held = { true } },
			{ kind = "roll", held = { 1, 2, 3, 4, 5 } },
			{ kind = "roll", held = "yes" },
			{ kind = "hold", held = { true, false, false, false, false, true } },
			{ kind = "hold" },
			{ kind = "score", box = "nope" },
			{ kind = "score", box = 3 },
			{ kind = "score" },
			{ kind = "fly" },
			"roll",
		} do
			T.eq((FiveDice.validateMove(s, 1, move)), false)
		end
		FiveDice.applyMove(s, 1, { kind = "score", box = "chance" })
		FiveDice.applyMove(s, 2, { kind = "roll" })
		FiveDice.applyMove(s, 2, { kind = "score", box = "chance" })
		FiveDice.applyMove(s, 1, { kind = "roll" })
		T.eq((FiveDice.validateMove(s, 1, { kind = "score", box = "chance" })), false, "box already filled")
	end)

	T.test("upper bonus at 63", function()
		local s = FiveDice.new(1, nil, T.Random.new(1))
		local p = s.players[1]
		p.card = { ones = 3, twos = 6, threes = 9, fours = 12, fives = 15, sixes = 18 }
		T.eq(FiveDice.totals(s, p).upperBonus, 35)
		p.card.sixes = 12
		T.eq(FiveDice.totals(s, p).upperBonus, 0)
	end)

	T.test("extra Big Five: +100 and joker placement", function()
		local s = rolledState(1)
		local p = s.players[1]
		p.card.big = 50
		p.dice = { 4, 4, 4, 4, 4 }
		T.eq(table.concat(FiveDice.legalBoxes(s, 1), ","), "fours", "matching upper box first")
		FiveDice.applyMove(s, 1, { kind = "score", box = "fours" })
		T.eq(p.card.fours, 20)
		T.eq(p.bigBonus, 100)
		-- Next time fours is full: any lower box scores in full.
		FiveDice.applyMove(s, 1, { kind = "roll" })
		p.dice = { 4, 4, 4, 4, 4 }
		T.ok(not FiveDice.validateMove(s, 1, { kind = "score", box = "ones" }), "upper not allowed while lower boxes are open")
		T.ok(FiveDice.validateMove(s, 1, { kind = "score", box = "large" }))
		FiveDice.applyMove(s, 1, { kind = "score", box = "large" })
		T.eq(p.card.large, 40)
		T.eq(p.bigBonus, 200)
	end)

	T.test("zeroed Big Five box gives no bonus", function()
		local s = rolledState(1)
		local p = s.players[1]
		p.card.big = 0
		p.dice = { 2, 2, 2, 2, 2 }
		FiveDice.applyMove(s, 1, { kind = "score", box = "twos" })
		T.eq(p.bigBonus, 0)
	end)

	T.test("game ends after every box is filled; highest total wins", function()
		local s = FiveDice.new(2, { rules = { card = "quick" } }, T.Random.new(3))
		T.eq(s.rounds, 7)
		local guard = 0
		while not FiveDice.getResult(s) and guard < 200 do
			guard += 1
			local seat = FiveDice.getActiveSeats(s)[1]
			FiveDice.applyMove(s, seat, { kind = "roll" })
			local box = FiveDice.legalBoxes(s, seat)[1]
			FiveDice.applyMove(s, seat, { kind = "score", box = box })
		end
		local result = FiveDice.getResult(s)
		T.ok(result ~= nil)
		local scores = FiveDice.getScores(s)
		for _, w in result.winners do
			for seat = 1, 2 do
				T.ok(scores[w] >= scores[seat])
			end
		end
		T.eq(#FiveDice.getActiveSeats(s), 0)
	end)

	T.test("everyone rolls at once", function()
		local s = FiveDice.new(3, { rules = { together = true } }, T.Random.new(4))
		T.eq(#FiveDice.getActiveSeats(s), 3)
		FiveDice.applyMove(s, 2, { kind = "roll" })
		FiveDice.applyMove(s, 2, { kind = "score", box = "chance" })
		T.eq(#FiveDice.getActiveSeats(s), 2)
		T.eq((FiveDice.validateMove(s, 2, { kind = "roll" })), false, "already scored this round")
		for _, seat in { 1, 3 } do
			FiveDice.applyMove(s, seat, { kind = "roll" })
			FiveDice.applyMove(s, seat, { kind = "score", box = "chance" })
		end
		T.eq(s.round, 2)
		T.eq(#FiveDice.getActiveSeats(s), 3)
	end)

	T.test("view shows previews only to the seat that's rolling", function()
		local s = rolledState()
		local mine = FiveDice.getView(s, 1)
		T.ok(mine.preview ~= nil and mine.preview.chance ~= nil)
		T.eq(FiveDice.getView(s, 2).preview, nil)
		T.eq(FiveDice.getView(s, nil).preview, nil)
		T.eq(FiveDice.getView(s, nil).rng, nil)
	end)

	T.test("hard bot keeps a made Large straight", function()
		local s = rolledState(1)
		s.botLevel = "hard"
		s.players[1].dice = { 2, 3, 4, 5, 6 }
		local move = FiveDice.chooseBotMove(s, 1, T.Random.new(1))
		T.eq(move.kind, "score")
		T.eq(move.box, "large")
	end)

	T.test("hard bot holds four of a kind and rerolls the odd die", function()
		local s = rolledState(1)
		s.botLevel = "hard"
		s.players[1].dice = { 6, 6, 1, 6, 6 }
		local move = FiveDice.chooseBotMove(s, 1, T.Random.new(1))
		T.eq(move.kind, "roll")
		T.eq(move.held[3], false)
		T.eq(move.held[1] and move.held[2] and move.held[4] and move.held[5], true)
	end)
end
