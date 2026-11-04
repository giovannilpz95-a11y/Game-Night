local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TicTacToe = require(ReplicatedStorage.Shared.Games.TicTacToe)
local GameModule = require(ReplicatedStorage.Shared.GameModule)

return function(T)
	local function play(state, seat, cell)
		local ok, err = TicTacToe.validateMove(state, seat, { cell = cell })
		assert(ok, err)
		TicTacToe.applyMove(state, seat, { cell = cell })
	end

	T.test("starts empty with seat 1 to move", function()
		local s = TicTacToe.new(2)
		T.eq(#TicTacToe.getLegalMoves(s, 1), 9)
		T.eq(#TicTacToe.getLegalMoves(s, 2), 0)
		T.eq(TicTacToe.getActiveSeats(s)[1], 1)
	end)

	T.test("rejects bad and out-of-turn moves", function()
		local s = TicTacToe.new(2)
		T.eq((TicTacToe.validateMove(s, 2, { cell = 1 })), false, "out of turn")
		T.eq((TicTacToe.validateMove(s, 1, { cell = 0 })), false, "cell 0")
		T.eq((TicTacToe.validateMove(s, 1, { cell = 1.5 })), false, "fractional")
		T.eq((TicTacToe.validateMove(s, 1, "hack")), false, "not a table")
		play(s, 1, 5)
		T.eq((TicTacToe.validateMove(s, 2, { cell = 5 })), false, "taken")
	end)

	T.test("detects a win", function()
		local s = TicTacToe.new(2)
		play(s, 1, 1)
		play(s, 2, 4)
		play(s, 1, 2)
		play(s, 2, 5)
		play(s, 1, 3)
		local result = TicTacToe.getResult(s)
		T.ok(result, "should have a result")
		T.eq(result.winners[1], 1)
		T.eq(#TicTacToe.getActiveSeats(s), 0)
	end)

	T.test("detects a draw", function()
		local s = TicTacToe.new(2)
		-- X O X / X O O / O X X
		for _, step in { { 1, 1 }, { 2, 2 }, { 1, 3 }, { 2, 5 }, { 1, 4 }, { 2, 6 }, { 1, 8 }, { 2, 7 }, { 1, 9 } } do
			play(s, step[1], step[2])
		end
		local result = TicTacToe.getResult(s)
		T.ok(result and result.isDraw, "should be a draw")
	end)

	T.test("bot takes a win, then blocks", function()
		local s = TicTacToe.new(2)
		play(s, 1, 1)
		play(s, 2, 4)
		play(s, 1, 2)
		-- seat 2 must block cell 3
		T.eq(TicTacToe.chooseBotMove(s, 2, T.Random.new(1)).cell, 3)
		play(s, 2, 5)
		-- seat 1 to move; seat 1 can win on 3
		T.eq(TicTacToe.chooseBotMove(s, 1, T.Random.new(1)).cell, 3)
	end)

	T.test("bot vs bot always finishes with a legal game", function()
		for seed = 1, 50 do
			local rng = T.Random.new(seed)
			local s = TicTacToe.new(2)
			local moves = 0
			while not TicTacToe.getResult(s) do
				local seat = TicTacToe.getActiveSeats(s)[1]
				local move = GameModule.chooseBotMove(TicTacToe, s, seat, rng)
				T.ok(TicTacToe.validateMove(s, seat, move), "bot made an illegal move")
				TicTacToe.applyMove(s, seat, move)
				moves += 1
				T.ok(moves <= 9, "too many moves")
			end
			-- Two perfect-ish bots should never lose to each other's blunders... mostly draws.
		end
	end)
end
