-- Four in a Row: drop discs into a 7x6 grid, first to line up four wins.
-- grid[column][row], row 1 is the bottom. 0 = empty, else the seat (1 or 2).
-- Move: { column = 1..7 }

local GameModule = require(script.Parent.Parent.GameModule)

local FourInARow = {}

FourInARow.id = "FourInARow"
FourInARow.minSeats = 2
FourInARow.maxSeats = 2

local COLS, ROWS = 7, 6
FourInARow.columns = COLS
FourInARow.rows = ROWS

local DIRECTIONS = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 } }
local CENTER_FIRST = { 4, 3, 5, 2, 6, 1, 7 }

export type State = {
	grid: { { number } },
	heights: { number },
	turn: number,
	moveCount: number,
	lastMove: { column: number, row: number }?,
	winner: number?,
	winningCells: { { number } }?,
	isDraw: boolean,
	botLevel: string,
}

function FourInARow.new(seatCount: number, options: any?, _rng: Random?): State
	assert(seatCount == 2, "Four in a Row needs exactly 2 seats")
	local grid = {}
	for c = 1, COLS do
		grid[c] = table.create(ROWS, 0)
	end
	return {
		grid = grid,
		heights = table.create(COLS, 0),
		turn = 1,
		moveCount = 0,
		lastMove = nil,
		winner = nil,
		winningCells = nil,
		isDraw = false,
		botLevel = (options and options.botLevel) or "medium",
	}
end

local function isOver(state: State): boolean
	return state.winner ~= nil or state.isDraw
end

-- Cells of a four-in-a-row through (c, r) for `who`, or nil.
local function lineThrough(grid: { { number } }, c: number, r: number, who: number): { { number } }?
	for _, d in DIRECTIONS do
		local cells = { { c, r } }
		for _, sign in { 1, -1 } do
			local x, y = c + d[1] * sign, r + d[2] * sign
			while x >= 1 and x <= COLS and y >= 1 and y <= ROWS and grid[x][y] == who do
				table.insert(cells, { x, y })
				x += d[1] * sign
				y += d[2] * sign
			end
		end
		if #cells >= 4 then
			return cells
		end
	end
	return nil
end

function FourInARow.getActiveSeats(state: State): { number }
	return if isOver(state) then {} else { state.turn }
end

function FourInARow.getLegalMoves(state: State, seat: number): { any }
	if isOver(state) or seat ~= state.turn then
		return {}
	end
	local moves = {}
	for c = 1, COLS do
		if state.heights[c] < ROWS then
			table.insert(moves, { column = c })
		end
	end
	return moves
end

function FourInARow.validateMove(state: State, seat: number, move: any): (boolean, string?)
	if isOver(state) then
		return false, "The game is over"
	end
	if seat ~= state.turn then
		return false, "It's not your turn"
	end
	if type(move) ~= "table" or type(move.column) ~= "number" then
		return false, "Bad move"
	end
	local c = move.column
	if c ~= math.floor(c) or c < 1 or c > COLS then
		return false, "Bad column"
	end
	if state.heights[c] >= ROWS then
		return false, "That column is full"
	end
	return true
end

function FourInARow.applyMove(state: State, seat: number, move: any)
	local c = move.column
	local r = state.heights[c] + 1
	state.heights[c] = r
	state.grid[c][r] = seat
	state.moveCount += 1
	state.lastMove = { column = c, row = r }
	local cells = lineThrough(state.grid, c, r, seat)
	if cells then
		state.winner = seat
		state.winningCells = cells
	elseif state.moveCount >= COLS * ROWS then
		state.isDraw = true
	else
		state.turn = 3 - seat
	end
end

function FourInARow.getResult(state: State): GameModule.Result?
	if state.winner then
		return { winners = { state.winner }, isDraw = false, reason = "Four in a row" }
	elseif state.isDraw then
		return { winners = {}, isDraw = true, reason = "The board is full" }
	end
	return nil
end

function FourInARow.getView(state: State, _seat: number?): any
	return GameModule.copy(state)
end

-- Bot ---------------------------------------------------------------------

local WIN_SCORE = 1000000

local function scoreWindow(mine: number, theirs: number): number
	if mine > 0 and theirs > 0 then
		return 0
	end
	if mine == 3 then
		return 5
	elseif mine == 2 then
		return 2
	elseif theirs == 3 then
		return -4
	elseif theirs == 2 then
		return -1
	end
	return 0
end

local function evaluate(grid: { { number } }, me: number): number
	local score = 0
	for r = 1, ROWS do
		if grid[4][r] == me then
			score += 3
		elseif grid[4][r] ~= 0 then
			score -= 3
		end
	end
	for _, d in DIRECTIONS do
		for c = 1, COLS do
			for r = 1, ROWS do
				local endC, endR = c + d[1] * 3, r + d[2] * 3
				if endC >= 1 and endC <= COLS and endR >= 1 and endR <= ROWS then
					local mine, theirs = 0, 0
					for i = 0, 3 do
						local v = grid[c + d[1] * i][r + d[2] * i]
						if v == me then
							mine += 1
						elseif v ~= 0 then
							theirs += 1
						end
					end
					score += scoreWindow(mine, theirs)
				end
			end
		end
	end
	return score
end

type Search = { grid: { { number } }, heights: { number }, nodes: number, deadline: number, outOfTime: boolean }

local function negamax(s: Search, depth: number, alpha: number, beta: number, me: number, filled: number): number
	s.nodes += 1
	if s.nodes % 512 == 0 and os.clock() > s.deadline then
		s.outOfTime = true
	end
	if s.outOfTime then
		return 0
	end
	if filled >= COLS * ROWS then
		return 0
	end
	if depth == 0 then
		return evaluate(s.grid, me)
	end
	local best = -math.huge
	for _, c in CENTER_FIRST do
		local h = s.heights[c]
		if h < ROWS then
			local r = h + 1
			s.grid[c][r] = me
			s.heights[c] = r
			local score
			if lineThrough(s.grid, c, r, me) then
				score = WIN_SCORE + depth -- win sooner is better
			else
				score = -negamax(s, depth - 1, -beta, -alpha, 3 - me, filled + 1)
			end
			s.grid[c][r] = 0
			s.heights[c] = h
			if score > best then
				best = score
			end
			if best > alpha then
				alpha = best
			end
			if alpha >= beta then
				break
			end
		end
	end
	return best
end

local LEVELS = {
	easy = { depth = 1, randomChance = 0.35, seconds = 0.05 },
	medium = { depth = 4, randomChance = 0.05, seconds = 0.2 },
	hard = { depth = 8, randomChance = 0, seconds = 0.6 },
}

-- Scores every legal column for `seat`. Iterative deepening keeps the last finished depth.
function FourInARow.scoreColumns(state: State, seat: number, maxDepth: number, seconds: number): { [number]: number }
	local s: Search = {
		grid = GameModule.copy(state.grid),
		heights = table.clone(state.heights),
		nodes = 0,
		deadline = os.clock() + seconds,
		outOfTime = false,
	}
	local finished: { [number]: number } = {}
	for depth = 1, maxDepth do
		local scores = {}
		for _, c in CENTER_FIRST do
			local h = s.heights[c]
			if h < ROWS then
				local r = h + 1
				s.grid[c][r] = seat
				s.heights[c] = r
				if lineThrough(s.grid, c, r, seat) then
					scores[c] = WIN_SCORE + depth
				else
					scores[c] = -negamax(s, depth - 1, -math.huge, math.huge, 3 - seat, state.moveCount + 1)
				end
				s.grid[c][r] = 0
				s.heights[c] = h
			end
		end
		if s.outOfTime then
			break
		end
		finished = scores
	end
	return finished
end

function FourInARow.chooseBotMove(state: State, seat: number, rng: Random): any?
	local level = LEVELS[state.botLevel] or LEVELS.medium
	local moves = FourInARow.getLegalMoves(state, seat)
	if #moves == 0 then
		return nil
	end
	if rng:NextNumber() < level.randomChance then
		return moves[rng:NextInteger(1, #moves)]
	end
	local scores = FourInARow.scoreColumns(state, seat, level.depth, level.seconds)
	local bestScore, best = -math.huge, {}
	for c, score in scores do
		if score > bestScore then
			bestScore, best = score, { c }
		elseif score == bestScore then
			table.insert(best, c)
		end
	end
	if #best == 0 then
		return moves[rng:NextInteger(1, #moves)]
	end
	table.sort(best)
	return { column = best[rng:NextInteger(1, #best)] }
end

return FourInARow
