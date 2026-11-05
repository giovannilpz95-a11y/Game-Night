-- Tic-Tac-Toe, "infinite" style: each player keeps at most 3 marks. Placing a 4th
-- removes that player's oldest mark, so the board never fills and someone wins.
-- The mark that will vanish on a player's next turn is listed in `fading` so boards
-- can show it fading the turn before it goes.
-- Board cells are numbered 1..9, left to right, top to bottom. 0 = empty, else the seat.
-- House rule "misere" (Upside down): whoever makes three in a row loses.
-- House rule "vanish" (on by default): off plays the classic game, where marks stay and a
-- full board is a draw.

local GameModule = require(script.Parent.Parent.GameModule)
local BotThink = require(script.Parent.Parent.BotThink)

local TicTacToe = {}

TicTacToe.id = "TicTacToe"
TicTacToe.minSeats = 2
TicTacToe.maxSeats = 2
TicTacToe.marks = { "X", "O" }
TicTacToe.maxMarks = 3
-- Safety net so a game can't run forever (two bots, or two players who only block).
-- 60 moves is 30 each, about 10 minutes at the 20 second turn clock.
TicTacToe.maxMoves = 60

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
	placed: { { number } }, -- per seat, its marks' cells, oldest first
	fading: { number }, -- per seat, the cell that vanishes on its next move (0 = none)
	turn: number,
	moves: number,
	winner: number?,
	winningLine: { number }?,
	isDraw: boolean, -- only when the move cap is hit
	misere: boolean,
	classic: boolean?,
	botLevel: string,
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

local function other(seat: number): number
	return if seat == 1 then 2 else 1
end

local function refreshFading(state: State)
	for seat = 1, 2 do
		local placed = state.placed[seat]
		state.fading[seat] = if not state.classic and #placed >= TicTacToe.maxMarks then placed[1] else 0
	end
end

function TicTacToe.new(seatCount: number, options: any?, _rng: Random?): State
	assert(seatCount == 2, "Tic-Tac-Toe needs exactly 2 seats")
	local rules = (options and options.rules) or {}
	return {
		board = table.create(9, 0),
		placed = { {}, {} },
		fading = { 0, 0 },
		turn = 1,
		moves = 0,
		winner = nil,
		winningLine = nil,
		isDraw = false,
		misere = rules.misere == true,
		classic = rules.vanish == false,
		botLevel = (options and options.botLevel) or "medium",
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
	local placed = state.placed[seat]
	-- The oldest mark leaves first, so it can't count toward the new line.
	if not state.classic and #placed >= TicTacToe.maxMarks then
		state.board[table.remove(placed, 1) :: number] = 0
	end
	state.board[move.cell] = seat
	table.insert(placed, move.cell)
	state.moves += 1
	refreshFading(state)

	local winner, line = findWinner(state.board)
	if winner then
		-- Upside down: the line's maker loses, so the other seat wins.
		state.winner = if state.misere then other(winner) else winner
		state.winningLine = line
	elseif state.moves >= TicTacToe.maxMoves or (state.classic and table.find(state.board, 0) == nil) then
		state.isDraw = true
	else
		state.turn = other(seat)
	end
end

function TicTacToe.getResult(state: State): GameModule.Result?
	if state.winner then
		local reason = if state.misere then "Made three in a row (upside down rules)" else "Three in a row"
		return { winners = { state.winner }, isDraw = false, reason = reason }
	elseif state.isDraw then
		return { winners = {}, isDraw = true, reason = if state.classic then "The board is full" else `No winner after {TicTacToe.maxMoves} moves` }
	end
	return nil
end

function TicTacToe.getView(state: State, _seat: number?): any
	-- Nothing is hidden in Tic-Tac-Toe.
	return GameModule.copy(state)
end

-- Bot ---------------------------------------------------------------------------
-- Looks one move ahead on a scratch copy: win if it can, never hand the opponent an
-- instant win (remember our own oldest mark leaves and frees its square), and prefer
-- moves that set up a win. A little randomness keeps two bots from looping forever.

local function simulate(state: State, seat: number, cell: number): State
	local s = {
		board = table.clone(state.board),
		placed = { table.clone(state.placed[1]), table.clone(state.placed[2]) },
		fading = table.clone(state.fading),
		turn = seat,
		moves = 0, -- the cap doesn't matter for look-ahead
		winner = nil,
		winningLine = nil,
		isDraw = false,
		misere = state.misere,
		classic = state.classic,
	}
	TicTacToe.applyMove(s :: any, seat, { cell = cell })
	return s :: any
end

-- Cells where `seat` would complete a line of its own (a win, or a loss upside down).
local function linesFor(state: State, seat: number): { number }
	local out = {}
	for cell = 1, 9 do
		if state.board[cell] == 0 then
			local s = simulate(state, seat, cell)
			if s.winningLine and s.board[s.winningLine[1]] == seat then
				table.insert(out, cell)
			end
		end
	end
	return out
end

-- Per bot level: CASUAL is the chance of a random safe move instead of the best one,
-- BLUNDER the chance of a random move that may ignore a threat. Even hard bots slip now
-- and then, so two bots (or a careful player) can't block each other forever.
local LEVELS = {
	easy = { casual = 0.5, blunder = 0.3 },
	medium = { casual = 0.25, blunder = 0.1 },
	hard = { casual = 0.1, blunder = 0.04 },
}

local function pick(rng: Random, pool: { number }): any
	return { cell = pool[rng:NextInteger(1, #pool)] }
end

function TicTacToe.chooseBotMove(state: State, seat: number, rng: Random): any?
	local level = LEVELS[state.botLevel] or LEVELS.medium
	local opponent = other(seat)
	local open = {}
	for c = 1, 9 do
		if state.board[c] == 0 then
			table.insert(open, c)
		end
	end
	if #open == 0 then
		return nil
	end

	if state.misere then
		-- Upside down: never finish a line of our own; anything else is fine.
		local mine = linesFor(state, seat)
		local safe = {}
		for _, c in open do
			if not table.find(mine, c) then
				table.insert(safe, c)
			end
		end
		if #safe == 0 or rng:NextNumber() < level.blunder then
			return pick(rng, open)
		end
		return pick(rng, safe)
	end

	local wins = linesFor(state, seat)
	if #wins > 0 and rng:NextNumber() >= level.blunder / 2 then
		return pick(rng, wins)
	end

	-- Safe moves leave the opponent no instant win; threats also set up our own win.
	-- (Forks can't happen here: after our oldest mark leaves, only two of ours remain.)
	local safe, threats = {}, {}
	for _, c in open do
		local s = simulate(state, seat, c)
		if #linesFor(s, opponent) == 0 then
			table.insert(safe, c)
			if #linesFor(s, seat) > 0 then
				table.insert(threats, c)
			end
		end
	end
	-- Now and then the bot misses the danger, like a person would. This keeps it
	-- beatable and stops two careful players blocking each other forever.
	if #safe == 0 or rng:NextNumber() < level.blunder then
		return pick(rng, open)
	end
	-- Some moves are "casual" safe moves so bots don't play the same loop forever.
	if rng:NextNumber() < level.casual then
		return pick(rng, safe)
	end
	if #threats > 0 then
		return pick(rng, threats)
	end
	if table.find(safe, 5) then
		return { cell = 5 }
	end
	for _, group in { { 1, 3, 7, 9 }, { 2, 4, 6, 8 } } do
		local pool = {}
		for _, c in group do
			if table.find(safe, c) then
				table.insert(pool, c)
			end
		end
		if #pool > 0 then
			return pick(rng, pool)
		end
	end
	return pick(rng, safe)
end

-- A natural pause before a bot moves: quick when forced, longer for a real choice.
function TicTacToe.getBotDelay(state, seat: number, rng: Random): number
	return BotThink.delay(rng, #TicTacToe.getLegalMoves(state, seat), { base = 0.7, perDoubling = 0.15, max = 2.0 })
end

return TicTacToe
