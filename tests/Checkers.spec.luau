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

	local function flyingBoard()
		local s = Checkers.new(2, { rules = { flyingKings = true } })
		for r = 1, 8 do
			for c = 1, 8 do
				s.board[r][c] = 0
			end
		end
		s.board[1][2] = 2 -- something left for light, so the game isn't over
		return s
	end

	local function pathText(m): string
		local parts = {}
		for _, sq in m.path do
			table.insert(parts, `{sq[1]},{sq[2]}`)
		end
		return table.concat(parts, " ")
	end

	T.test("flying kings: a jumped piece blocks the way until the capture ends", function()
		local s = flyingBoard()
		s.board[5][4] = 3 -- dark king
		s.board[4][5] = 2
		s.board[6][3] = 2
		local paths = {}
		for _, m in Checkers.getLegalMoves(s, 1) do
			table.insert(paths, pathText(m))
		end
		table.sort(paths)
		-- Either piece can be taken, landing anywhere past it, but the king can't turn
		-- back over the piece it just took to reach the other one.
		T.eq(table.concat(paths, " | "), "1,8 | 2,7 | 3,6 | 7,2 | 8,1")
	end)

	T.test("flying kings: the king must land where the capture goes on", function()
		local s = flyingBoard()
		s.board[4][7] = 3 -- dark king
		s.board[5][6] = 2
		s.board[7][2] = 2
		local moves = Checkers.getLegalMoves(s, 1)
		T.eq(#moves, 1)
		T.eq(pathText(moves[1]), "8,3 6,1")
		T.eq((Checkers.validateMove(s, 1, { from = { 4, 7 }, path = { { 7, 4 } } })), false, "stopping early")
	end)

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
		T.eq(Checkers.getView(s, 2).lastMove.crowned, true, "the table shows the crowning")
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

	local function playOut(s, maxPlies, seed)
		local rng = T.Random.new(seed)
		local plies = 0
		while not Checkers.getResult(s) and plies < maxPlies do
			local seat = Checkers.getActiveSeats(s)[1]
			local move = GameModule.chooseBotMove(Checkers, s, seat, rng)
			T.ok(Checkers.validateMove(s, seat, move), "bot made an illegal move")
			Checkers.applyMove(s, seat, move)
			plies += 1
		end
		return Checkers.getResult(s)
	end

	T.test("the hard bot wins two kings against one", function()
		for i, start in { { { 5, 4 }, { 4, 7 }, { 1, 2 } }, { { 6, 5 }, { 7, 2 }, { 8, 7 } } } do
			local s = empty("hard")
			s.board[start[1][1]][start[1][2]] = 3
			s.board[start[2][1]][start[2][2]] = 3
			s.board[start[3][1]][start[3][2]] = 4
			local result = playOut(s, 80, i)
			T.ok(result ~= nil and result.winners[1] == 1, `start {i}: {result and result.reason or "not finished"}`)
		end
	end)

	T.test("the same position three times is a draw", function()
		local s = empty("medium")
		s.board[8][1] = 3
		s.board[1][8] = 4
		s.board[1][2] = 2 -- a man so light isn't stuck
		local function go(seat, from, to)
			if Checkers.getResult(s) then
				return
			end
			local move = { from = from, path = { to } }
			T.ok(Checkers.validateMove(s, seat, move))
			Checkers.applyMove(s, seat, move)
		end
		for _ = 1, 3 do
			go(1, { 8, 1 }, { 7, 2 })
			go(2, { 1, 8 }, { 2, 7 })
			go(1, { 7, 2 }, { 8, 1 })
			go(2, { 2, 7 }, { 1, 8 })
		end
		local result = Checkers.getResult(s)
		T.ok(result and result.isDraw, "drawn")
		T.eq(result.reason, "Threefold repetition")
	end)

	T.test("offers: undo your own move on their turn, abort at the start, draw cool-down", function()
		local s = Checkers.new(2)
		T.eq(Checkers.getView(s, 1).menuActions[1].label, "Abort game")
		local first = Checkers.getLegalMoves(s, 1)[1]
		Checkers.applyMove(s, 1, first)
		-- Dark asks to take back their move while Light thinks: one ply comes off.
		T.eq(Checkers.getInterruptSeats(s)[1], 1)
		T.ok(Checkers.validateMove(s, 1, { type = "offer", kind = "takeback" }))
		Checkers.applyMove(s, 1, { type = "offer", kind = "takeback" })
		T.eq(Checkers.getActiveSeats(s)[1], 2)
		Checkers.applyMove(s, 2, { type = "answer", accept = true })
		T.eq(#s.undo, 0)
		T.eq(s.turn, 1)
		-- Abort before the first moves ends with no winner.
		T.ok(Checkers.validateMove(s, 1, { type = "abort" }))
		Checkers.applyMove(s, 1, { type = "abort" })
		T.eq(Checkers.getResult(s).reason, "Game aborted")
		-- A declined draw offer can't be repeated for a while.
		local d = Checkers.new(2)
		for _ = 1, 2 do
			local seat = d.turn
			Checkers.applyMove(d, seat, Checkers.getLegalMoves(d, seat)[1])
		end
		Checkers.applyMove(d, 1, { type = "offer", kind = "draw" })
		Checkers.applyMove(d, 2, { type = "answer", accept = false })
		for _ = 1, 4 do
			local seat = d.turn
			Checkers.applyMove(d, seat, Checkers.getLegalMoves(d, seat)[1])
		end
		T.eq((Checkers.validateMove(d, 1, { type = "offer", kind = "draw" })), false)
	end)

	T.test("a takeback takes the crowning stat back too", function()
		local s = empty("medium")
		s.board[2][3] = 1
		s.board[8][1] = 2
		s.board[7][8] = 2
		Checkers.applyMove(s, 1, { from = { 2, 3 }, path = { { 1, 2 } } })
		T.eq(s.matchStats[1].kings, 1)
		Checkers.applyMove(s, 1, { type = "offer", kind = "takeback" })
		Checkers.applyMove(s, 2, { type = "answer", accept = true })
		T.eq(s.matchStats[1].kings, 0)
	end)

	T.test("taking the last piece says so", function()
		local s = empty("medium")
		s.board[5][4] = 1
		s.board[4][5] = 2
		Checkers.applyMove(s, 1, { from = { 5, 4 }, path = { { 3, 6 } } })
		T.eq(Checkers.getResult(s).reason, "All pieces captured")
	end)
end
