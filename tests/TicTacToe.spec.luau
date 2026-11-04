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

	T.test("a fourth mark removes the oldest, so the board never fills", function()
		local s = TicTacToe.new(2)
		-- X: 1, 6, 8   O: 2, 4, 9  (no lines)
		for _, step in { { 1, 1 }, { 2, 2 }, { 1, 6 }, { 2, 4 }, { 1, 8 } } do
			play(s, step[1], step[2])
		end
		T.eq(s.fading[1], 1, "X's oldest is flagged once it has 3")
		T.eq(s.fading[2], 0, "O only has 2")
		play(s, 2, 9)
		T.eq(s.fading[2], 2)
		play(s, 1, 3) -- X's 4th: cell 1 goes
		T.eq(s.board[1], 0, "oldest X removed")
		T.eq(s.board[3], 1)
		T.eq(s.fading[1], 6, "next X to go")
		T.eq(#s.placed[1], 3)
		T.eq(TicTacToe.getResult(s), nil, "no draw, game goes on")
		-- The freed square is open to the opponent.
		T.ok(TicTacToe.validateMove(s, 2, { cell = 1 }))
	end)

	T.test("the vanishing mark can't complete a line", function()
		local s = TicTacToe.new(2)
		-- X: 1, 2, 9 then X plays 3. Cell 1 leaves first, so 1-2-3 isn't a line.
		for _, step in { { 1, 1 }, { 2, 4 }, { 1, 2 }, { 2, 5 }, { 1, 9 }, { 2, 7 } } do
			play(s, step[1], step[2])
		end
		-- O blocked nothing; O has 4, 5, 7. X plays 3.
		play(s, 1, 3)
		T.eq(TicTacToe.getResult(s), nil, "1-2-3 doesn't count once 1 is gone")
		T.eq(s.board[1], 0)
	end)

	T.test("move cap ends a game that never finishes", function()
		local s = TicTacToe.new(2)
		s.moves = TicTacToe.maxMoves - 1
		play(s, 1, 5)
		local result = TicTacToe.getResult(s)
		T.ok(result and result.isDraw, "cap ends the game")
		T.eq(#TicTacToe.getActiveSeats(s), 0)
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
				T.ok(moves <= TicTacToe.maxMoves, "too many moves")
			end
		end
	end)

	T.test("bot vs bot almost always ends with a winner", function()
		local capped, total = 0, 0
		for seed = 1, 200 do
			local rng = T.Random.new(seed)
			local s = TicTacToe.new(2)
			while not TicTacToe.getResult(s) do
				local seat = TicTacToe.getActiveSeats(s)[1]
				TicTacToe.applyMove(s, seat, GameModule.chooseBotMove(TicTacToe, s, seat, rng))
			end
			total += s.moves
			if s.isDraw then
				capped += 1
			end
		end
		T.ok(capped <= 10, `{capped} of 200 games hit the move cap`)
	end)

	T.test("bot blocks a threat even when it has to give up a mark", function()
		local s = TicTacToe.new(2)
		-- X has 2, 6, 8 (oldest 2). O has 1 and 4.
		s.board = { 2, 1, 0, 2, 0, 1, 0, 1, 0 }
		s.placed = { { 2, 6, 8 }, { 1, 4 } }
		s.fading = { 2, 0 }
		s.turn = 1
		-- O threatens 7 (1-4-7). X must block 7; moving frees 2, which doesn't help O.
		local blocked = 0
		for seed = 1, 50 do
			if TicTacToe.chooseBotMove(s, 1, T.Random.new(seed)).cell == 7 then
				blocked += 1
			end
		end
		-- It blunders now and then on purpose, but should block nearly every time.
		T.ok(blocked >= 40, `blocked {blocked} of 50`)
	end)
end
