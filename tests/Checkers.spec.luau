local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Checkers = require(ReplicatedStorage.Shared.Games.Checkers)
local GameModule = require(ReplicatedStorage.Shared.GameModule)

return function(T)
	local function empty(level)
		local s = Checkers.new(2, { botLevel = level })
		for r = 1, 8 do
			for c = 1, 8 do
				s.board[r][c] = 0
			end
		end
		return s
	end

	T.test("opening position has 7 moves for Dark", function()
		local s = Checkers.new(2)
		T.eq(#Checkers.getLegalMoves(s, 1), 7)
		T.eq(#Checkers.getLegalMoves(s, 2), 0, "not Light's turn")
	end)

	T.test("captures are forced", function()
		local s = empty()
		s.board[6][3] = 1
		s.board[5][4] = 2
		s.board[6][7] = 1
		s.board[1][2] = 2
		local moves = Checkers.getLegalMoves(s, 1)
		T.eq(#moves, 1, "only the jump is legal")
		T.eq(moves[1].path[1][1], 4)
		T.eq(moves[1].path[1][2], 5)
		local ok, err = Checkers.validateMove(s, 1, { from = { 6, 7 }, path = { { 5, 8 } } })
		T.eq(ok, false)
		T.eq(err, "You have to jump when you can")
	end)

	T.test("multi-jumps must continue and remove every jumped piece", function()
		local s = empty()
		s.board[7][2] = 1
		s.board[6][3] = 2
		s.board[4][5] = 2
		s.board[1][8] = 2
		local moves = Checkers.getLegalMoves(s, 1)
		T.eq(#moves, 1)
		T.eq(#moves[1].path, 2, "double jump")
		Checkers.applyMove(s, 1, moves[1])
		T.eq(s.board[6][3], 0)
		T.eq(s.board[4][5], 0)
		T.eq(s.board[3][6], 1)
	end)

	T.test("a man crowned mid-jump stops there", function()
		local s = empty()
		s.board[3][2] = 1
		s.board[2][3] = 2
		-- After landing on row 1 as a new king it could jump back over (2,5), but the turn ends.
		s.board[2][5] = 2
		local moves = Checkers.getLegalMoves(s, 1)
		T.eq(#moves, 1)
		T.eq(#moves[1].path, 1)
		Checkers.applyMove(s, 1, moves[1])
		T.eq(s.board[1][4], 3, "crowned")
	end)

	T.test("kings move backward", function()
		local s = empty()
		s.board[4][5] = 3
		s.board[8][1] = 2
		T.eq(#Checkers.getLegalMoves(s, 1), 4)
	end)

	T.test("no legal moves loses", function()
		local s = empty()
		s.board[6][3] = 1
		s.board[5][4] = 2
		Checkers.applyMove(s, 1, { from = { 6, 3 }, path = { { 4, 5 } } })
		local result = Checkers.getResult(s)
		T.ok(result, "game over")
		T.eq(result.winners[1], 1)
	end)

	T.test("rejects junk moves from the network", function()
		local s = Checkers.new(2)
		T.eq((Checkers.validateMove(s, 1, "hi")), false)
		T.eq((Checkers.validateMove(s, 1, { from = { 6, 1 }, path = { { 4, 3 } } })), false)
		T.eq((Checkers.validateMove(s, 1, { from = { 6, 1 }, path = { "x" } })), false)
	end)

	T.test("bot takes a double jump over a single", function()
		local s = empty("hard")
		s.board[7][2] = 1
		s.board[6][3] = 2
		s.board[4][5] = 2
		s.board[7][8] = 1
		s.board[6][7] = 2
		s.board[1][8] = 2
		s.board[1][2] = 2
		local move = Checkers.chooseBotMove(s, 1, T.Random.new(1))
		T.eq(#move.path, 2)
	end)

	T.test("bots finish legal games", function()
		for seed = 1, 3 do
			local rng = T.Random.new(seed)
			local s = Checkers.new(2, { botLevel = "easy" })
			local plies = 0
			while not Checkers.getResult(s) and plies < 300 do
				local seat = Checkers.getActiveSeats(s)[1]
				local move = GameModule.chooseBotMove(Checkers, s, seat, rng)
				T.ok(Checkers.validateMove(s, seat, move), "bot made an illegal move")
				Checkers.applyMove(s, seat, move)
				plies += 1
			end
			T.ok(Checkers.getResult(s) ~= nil, "game should finish")
		end
	end)
end
