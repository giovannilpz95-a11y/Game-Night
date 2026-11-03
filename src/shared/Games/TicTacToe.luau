-- Tic-Tac-Toe: the smallest real game, used to prove the table, turn and bot systems.
-- Board cells are numbered 1..9, left to right, top to bottom. 0 = empty, else the seat.

local GameModule = require(script.Parent.Parent.GameModule)

local TicTacToe = {}

TicTacToe.id = "TicTacToe"
TicTacToe.minSeats = 2
TicTacToe.maxSeats = 2
TicTacToe.marks = { "X", "O" }

local LINES = {
	{ 1, 2, 3 },
	{ 4, 5, 6 },
	{ 7, 8, 9 },
	{ 1, 4, 7 },
	{ 2, 5, 8 },
	{ 3, 6, 9 },
	{ 1, 5, 9 },
	{ 3, 5, 7 },
}

export type State = {
	board: { number },
	turn: number,
	winner: number?,
	winningLine: { number }?,
	isDraw: boolean,
}

local function findWinner(board: { number }): (number?, { number }?)
	for _, line in LINES do
		local a = board[line[1]]
		if a ~= 0 and a == board[line[2]] and a == board[line[3]] then
			return a, line
		end
	end
	return nil, nil
end

function TicTacToe.new(seatCount: number, _options: any?, _rng: Random?): State
	assert(seatCount == 2, "Tic-Tac-Toe needs exactly 2 seats")
	return {
		board = table.create(9, 0),
		turn = 1,
		winner = nil,
		winningLine = nil,
		isDraw = false,
	}
end

local function isOver(state: State): boolean
	return state.winner ~= nil or state.isDraw
end

function TicTacToe.getActiveSeats(state: State): { number }
	if isOver(state) then
		return {}
	end
	return { state.turn }
end

function TicTacToe.getLegalMoves(state: State, seat: number): { any }
	if isOver(state) or seat ~= state.turn then
		return {}
	end
	local moves = {}
	for cell = 1, 9 do
		if state.board[cell] == 0 then
			table.insert(moves, { cell = cell })
		end
	end
	return moves
end

function TicTacToe.validateMove(state: State, seat: number, move: any): (boolean, string?)
	if isOver(state) then
		return false, "The game is over"
	end
	if seat ~= state.turn then
		return false, "It's not your turn"
	end
	if type(move) ~= "table" or type(move.cell) ~= "number" then
		return false, "Bad move"
	end
	local cell = move.cell
	if cell ~= math.floor(cell) or cell < 1 or cell > 9 then
		return false, "Bad cell"
	end
	if state.board[cell] ~= 0 then
		return false, "That square is taken"
	end
	return true
end

function TicTacToe.applyMove(state: State, seat: number, move: any)
	state.board[move.cell] = seat
	local winner, line = findWinner(state.board)
	if winner then
		state.winner = winner
		state.winningLine = line
	elseif not table.find(state.board, 0) then
		state.isDraw = true
	else
		state.turn = if seat == 1 then 2 else 1
	end
end

function TicTacToe.getResult(state: State): GameModule.Result?
	if state.winner then
		return { winners = { state.winner }, isDraw = false, reason = "Three in a row" }
	elseif state.isDraw then
		return { winners = {}, isDraw = true, reason = "The board is full" }
	end
	return nil
end

function TicTacToe.getView(state: State, _seat: number?): any
	-- Nothing is hidden in Tic-Tac-Toe.
	return GameModule.copy(state)
end

-- Bot: win if it can, block if it must, else center, corner, edge (with a little randomness).
function TicTacToe.chooseBotMove(state: State, seat: number, rng: Random): any?
	local opponent = if seat == 1 then 2 else 1
	local board = state.board

	local function completingCell(who: number): number?
		for _, line in LINES do
			local mine, empty = 0, nil
			for _, cell in line do
				if board[cell] == who then
					mine += 1
				elseif board[cell] == 0 then
					empty = cell
				end
			end
			if mine == 2 and empty then
				return empty
			end
		end
		return nil
	end

	local cell = completingCell(seat) or completingCell(opponent)
	if cell then
		return { cell = cell }
	end
	if board[5] == 0 then
		return { cell = 5 }
	end
	for _, group in { { 1, 3, 7, 9 }, { 2, 4, 6, 8 } } do
		local open = {}
		for _, c in group do
			if board[c] == 0 then
				table.insert(open, c)
			end
		end
		if #open > 0 then
			return { cell = open[rng:NextInteger(1, #open)] }
		end
	end
	return nil
end

return TicTacToe
