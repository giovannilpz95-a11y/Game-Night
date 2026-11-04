local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FourInARow = require(ReplicatedStorage.Shared.Games.FourInARow)
local GameModule = require(ReplicatedStorage.Shared.GameModule)

return function(T)
	local function drop(state, seat, column)
		local ok, err = FourInARow.validateMove(state, seat, { column = column })
		assert(ok, err)
		FourInARow.applyMove(state, seat, { column = column })
	end

	T.test("discs stack from the bottom", function()
		local s = FourInARow.new(2)
		drop(s, 1, 4)
		drop(s, 2, 4)
		T.eq(s.grid[4][1], 1)
		T.eq(s.grid[4][2], 2)
		T.eq(s.heights[4], 2)
	end)

	T.test("full columns are rejected", function()
		local s = FourInARow.new(2)
		for i = 1, 6 do
			drop(s, if i % 2 == 1 then 1 else 2, 1)
		end
		T.eq((FourInARow.validateMove(s, 1, { column = 1 })), false)
		T.eq(#FourInARow.getLegalMoves(s, 1), 6)
	end)

	T.test("wins in every direction", function()
		-- horizontal
		local h = FourInARow.new(2)
		for _, c in { 1, 1, 2, 2, 3, 3, 4 } do
			drop(h, h.turn, c)
		end
		T.eq(h.winner, 1)
		-- vertical
		local v = FourInARow.new(2)
		for _, c in { 1, 2, 1, 2, 1, 2, 1 } do
			drop(v, v.turn, c)
		end
		T.eq(v.winner, 1)
		-- diagonal up-right
		local d = FourInARow.new(2)
		for _, c in { 1, 2, 2, 3, 3, 4, 3, 4, 4, 7, 4 } do
			drop(d, d.turn, c)
		end
		T.eq(d.winner, 1, "diagonal /")
		-- diagonal down-right
		local e = FourInARow.new(2)
		for _, c in { 7, 6, 6, 5, 5, 4, 5, 4, 4, 1, 4 } do
			drop(e, e.turn, c)
		end
		T.eq(e.winner, 1, "diagonal \\")
		T.eq(#e.winningCells, 4)
	end)

	T.test("a full board with no line is a draw", function()
		local s = FourInARow.new(2)
		-- Column pattern that never makes four: fill pairs of columns in a shifted order.
		local order = { 1, 2, 1, 2, 1, 2, 2, 1, 2, 1, 2, 1, 3, 4, 3, 4, 3, 4, 4, 3, 4, 3, 4, 3, 5, 6, 5, 6, 5, 6, 6, 5, 6, 5, 6, 5, 7, 7, 7, 7, 7, 7 }
		for _, c in order do
			drop(s, s.turn, c)
		end
		local result = FourInARow.getResult(s)
		T.ok(result and result.isDraw, "draw")
	end)

	T.test("bot wins when it can and blocks when it must", function()
		local s = FourInARow.new(2, { botLevel = "medium" })
		for _, c in { 1, 1, 2, 2, 3 } do
			drop(s, s.turn, c)
		end
		-- Seat 2 must block column 4.
		T.eq(FourInARow.chooseBotMove(s, 2, T.Random.new(5)).column, 4)
		drop(s, 2, 7)
		-- Seat 1 wins in column 4.
		T.eq(FourInARow.chooseBotMove(s, 1, T.Random.new(5)).column, 4)
	end)

	T.test("bots finish legal games at every level", function()
		for _, level in { "easy", "medium", "hard" } do
			local rng = T.Random.new(9)
			local s = FourInARow.new(2, { botLevel = level })
			while not FourInARow.getResult(s) do
				local seat = FourInARow.getActiveSeats(s)[1]
				local move = GameModule.chooseBotMove(FourInARow, s, seat, rng)
				T.ok(FourInARow.validateMove(s, seat, move), "bot made an illegal move")
				FourInARow.applyMove(s, seat, move)
			end
		end
	end)
end
