-- Four in a Row: drop discs into a 7x6 grid, first to line up four wins.
-- grid[column][row], row 1 is the bottom. 0 = empty, else the seat (1 or 2).
-- Move: { column = 1..7 }  |  { column = 1..7, pop = true }
-- House rule "popOut" (Pop Out): on your turn you may instead pull one of your own discs
-- out of the bottom of a column; everything above drops down a row. If a pop lines up
-- four for both players, the player who popped wins. The full board isn't a draw (you can
-- still pop); a game with no moves left, or POP_LIMIT moves, is.
-- Takebacks, draw offers and abort work like Chess (shared/Offers): { type = "offer" | ... }.

local GameModule = require(script.Parent.Parent.GameModule)
local BotThink = require(script.Parent.Parent.BotThink)
local Offers = require(script.Parent.Parent.Offers)

local FourInARow = {}

FourInARow.id = "FourInARow"
FourInARow.minSeats = 2
FourInARow.maxSeats = 2

local COLS, ROWS = 7, 6
FourInARow.columns = COLS
FourInARow.rows = ROWS

FourInARow.POP_LIMIT = 120

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
	popOut: boolean?,
}

function FourInARow.new(seatCount: number, options: any?, _rng: Random?): State
	assert(seatCount == 2, "Four in a Row needs exactly 2 seats")
	local grid = {}
	for c = 1, COLS do
		grid[c] = table.create(ROWS, 0)
	end
	local state = {
		grid = grid,
		heights = table.create(COLS, 0),
		turn = 1,
		moveCount = 0,
		lastMove = nil,
		winner = nil,
		winningCells = nil,
		isDraw = false,
		reason = nil :: string?,
		botLevel = (options and options.botLevel) or "medium",
		popOut = options ~= nil and type(options.rules) == "table" and options.rules.popOut == true,
	}
	Offers.init(state) -- state.offer, state.undo (one snapshot per move), takebacks
	return state :: any
end

local SIDE_NAMES = { "Red", "Blue" }

-- Pop Out: can `seat` pull their disc out of the bottom of column c?
function FourInARow.canPop(state: any, seat: number, c: number): boolean
	return state.popOut == true and state.grid[c] ~= nil and state.grid[c][1] == seat
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

local function turnSeat(state: any): number?
	return if isOver(state) then nil else state.turn
end

function FourInARow.getActiveSeats(state: any): { number }
	return if isOver(state) then {} else { Offers.answerer(state) or state.turn }
end

-- Right after your move you may ask to take it back or offer a draw (Offers).
function FourInARow.getInterruptSeats(state: any): { number }
	return Offers.interruptSeats(state, turnSeat(state))
end

function FourInARow.getTurnKey(state: any): any
	return #state.undo
end

local function undoOne(state: any)
	local entry = table.remove(state.undo)
	if not entry then
		return
	end
	state.grid = entry.grid
	state.heights = entry.heights
	state.turn = entry.turn
	state.moveCount = entry.moveCount
	state.lastMove = entry.lastMove
end

function FourInARow.getLegalMoves(state: any, seat: number): { any }
	if state.offer and not isOver(state) then
		if seat ~= Offers.answerer(state) then
			return {}
		end
		return { { type = "answer", accept = true }, { type = "answer", accept = false } }
	end
	if isOver(state) or seat ~= state.turn then
		return {}
	end
	local moves = {}
	for c = 1, COLS do
		if state.heights[c] < ROWS then
			table.insert(moves, { column = c })
		end
	end
	if state.popOut then
		for c = 1, COLS do
			if FourInARow.canPop(state, seat, c) then
				table.insert(moves, { column = c, pop = true })
			end
		end
	end
	return moves
end

function FourInARow.validateMove(state: State, seat: number, move: any): (boolean, string?)
	if isOver(state) then
		return false, "The game is over"
	end
	if Offers.isMove(move) then
		return Offers.validate(state, seat, move, turnSeat(state))
	end
	if (state :: any).offer then
		return false, "Waiting for an answer"
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
	if move.pop ~= nil then
		if move.pop ~= true or not state.popOut then
			return false, "Bad move"
		end
		if not FourInARow.canPop(state, seat, c) then
			return false, "You can only pop your own disc from the bottom"
		end
		return true
	end
	if state.heights[c] >= ROWS then
		return false, "That column is full"
	end
	return true
end

local function popMove(state: State, seat: number, c: number)
	local col = state.grid[c]
	for r = 1, ROWS - 1 do
		col[r] = col[r + 1]
	end
	col[ROWS] = 0
	state.heights[c] -= 1
	state.moveCount += 1
	state.lastMove = { column = c, row = 1, pop = true } :: any
	-- Every disc in the column moved, so check lines through each of them.
	local lines: { [number]: { { number } } } = {}
	for r = 1, state.heights[c] do
		local who = col[r]
		if not lines[who] then
			lines[who] = lineThrough(state.grid, c, r, who) :: any
		end
	end
	local winner = if lines[seat] then seat elseif lines[3 - seat] then 3 - seat else nil
	if winner then
		state.winner = winner
		state.winningCells = lines[winner]
	elseif state.moveCount >= FourInARow.POP_LIMIT then
		state.isDraw = true
	else
		state.turn = 3 - seat
		if #FourInARow.getLegalMoves(state, state.turn) == 0 then
			state.isDraw = true
		end
	end
end

function FourInARow.applyMove(state: State, seat: number, move: any)
	local st = state :: any
	if Offers.isMove(move) then
		local accepted = Offers.apply(st, seat, move, undoOne, turnSeat(state))
		if accepted == "draw" then
			state.isDraw = true
			st.reason = "Draw agreed"
		elseif accepted == "abort" then
			state.isDraw = true
			st.reason = "Game aborted"
		end
		return
	end
	table.insert(st.undo, {
		grid = GameModule.copy(state.grid),
		heights = table.clone(state.heights),
		turn = state.turn,
		moveCount = state.moveCount,
		lastMove = state.lastMove,
	})
	if move.pop == true then
		popMove(state, seat, move.column)
		return
	end
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
	elseif state.popOut and state.moveCount >= FourInARow.POP_LIMIT then
		state.isDraw = true
	elseif not state.popOut and state.moveCount >= COLS * ROWS then
		state.isDraw = true
	else
		state.turn = 3 - seat
		if state.popOut and #FourInARow.getLegalMoves(state, state.turn) == 0 then
			state.isDraw = true
		end
	end
end

function FourInARow.getResult(state: State): GameModule.Result?
	if state.winner then
		return { winners = { state.winner }, isDraw = false, reason = "Four in a row" }
	elseif state.isDraw then
		return { winners = {}, isDraw = true, reason = (state :: any).reason or (if state.popOut then "No way to win" else "The board is full") }
	end
	return nil
end

function FourInARow.getView(state: State, seat: number?): any
	local undo = (state :: any).undo
	;(state :: any).undo = nil
	local view = GameModule.copy(state)
	;(state :: any).undo = undo
	view.undo = nil
	view.plies = #undo
	Offers.addToView(view, state, seat, turnSeat(state), function(s)
		return SIDE_NAMES[s]
	end)
	return view
end

-- Bot ---------------------------------------------------------------------
-- Negamax with alpha-beta, a transposition table (Zobrist hashing), iterative deepening,
-- forced blocks, and an evaluation that knows Connect-4 "parity": a threat (a cell that
-- would finish four) on an odd row is worth more to the first player and one on an even
-- row to the second, because of who gets to fill that row when the board runs out.
-- Pop Out moves are part of the search too.

local WIN_SCORE = 1000000
FourInARow.WIN_SCORE = WIN_SCORE

-- Two 32-bit Zobrist keys per (seat, cell), from a fixed xorshift so every server agrees.
local KEY_HI: { { number } } = { {}, {} }
local KEY_LO: { { number } } = { {}, {} }
local SIDE_HI, SIDE_LO
do
	local x = 0x2545F491
	local function nextKey(): number
		x = bit32.bxor(x, bit32.lshift(x, 13))
		x = bit32.bxor(x, bit32.rshift(x, 17))
		x = bit32.bxor(x, bit32.lshift(x, 5))
		return x
	end
	for seat = 1, 2 do
		for i = 1, COLS * 8 do
			KEY_HI[seat][i] = nextKey()
			KEY_LO[seat][i] = nextKey()
		end
	end
	SIDE_HI, SIDE_LO = nextKey(), nextKey()
end

local function cellKey(c: number, r: number): number
	return c * 8 + r - 8
end

type Search = {
	grid: { { number } },
	heights: { number },
	hi: number,
	lo: number,
	nodes: number,
	deadline: number,
	outOfTime: boolean,
	popOut: boolean,
	first: number, -- the seat that moved first (parity)
	tt: { [number]: { number } }, -- lo -> { hi, depth, score, flag, move }
	ttCount: number,
}

local TT_MAX = 150000
local EXACT, LOWER, UPPER = 0, 1, 2

local function hashOf(grid: { { number } }, turn: number): (number, number)
	local hi, lo = 0, 0
	for c = 1, COLS do
		for r = 1, ROWS do
			local v = grid[c][r]
			if v ~= 0 then
				hi = bit32.bxor(hi, KEY_HI[v][cellKey(c, r)])
				lo = bit32.bxor(lo, KEY_LO[v][cellKey(c, r)])
			end
		end
	end
	if turn == 2 then
		hi, lo = bit32.bxor(hi, SIDE_HI), bit32.bxor(lo, SIDE_LO)
	end
	return hi, lo
end

local function toggle(s: Search, who: number, c: number, r: number)
	s.hi = bit32.bxor(s.hi, KEY_HI[who][cellKey(c, r)])
	s.lo = bit32.bxor(s.lo, KEY_LO[who][cellKey(c, r)])
end

local function flipSide(s: Search)
	s.hi, s.lo = bit32.bxor(s.hi, SIDE_HI), bit32.bxor(s.lo, SIDE_LO)
end

-- Would `who` complete four by having a disc at (c, r)? (The cell itself may be empty.)
local function wins(grid: { { number } }, c: number, r: number, who: number): boolean
	for _, d in DIRECTIONS do
		local count = 1
		for _, sign in { 1, -1 } do
			local x, y = c + d[1] * sign, r + d[2] * sign
			while x >= 1 and x <= COLS and y >= 1 and y <= ROWS and grid[x][y] == who do
				count += 1
				x += d[1] * sign
				y += d[2] * sign
			end
		end
		if count >= 4 then
			return true
		end
	end
	return false
end

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

-- Static score of the grid for `me`. `first` is the seat that moved first.
local function evaluate(grid: { { number } }, heights: { number }, me: number, first: number): number
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
	-- Threats above the stacks, weighted by parity.
	for c = 1, COLS do
		for r = heights[c] + 2, ROWS do -- not the playable cell: the search sees those
			for who = 1, 2 do
				if wins(grid, c, r, who) then
					local good = if who == first then r % 2 == 1 else r % 2 == 0
					local value = if good then 16 else 6
					score += if who == me then value else -value
				end
			end
		end
	end
	return score
end

local function checkTime(s: Search)
	s.nodes += 1
	if s.nodes % 256 == 0 and os.clock() > s.deadline then
		s.outOfTime = true
	end
end

-- Pops the bottom disc of column c (Pop Out); returns the popped seat.
local function doPop(s: Search, c: number): number
	local col = s.grid[c]
	local h = s.heights[c]
	local popped = col[1]
	for r = 1, h do
		toggle(s, col[r], c, r)
	end
	for r = 1, h - 1 do
		col[r] = col[r + 1]
	end
	col[h] = 0
	s.heights[c] = h - 1
	for r = 1, h - 1 do
		toggle(s, col[r], c, r)
	end
	return popped
end

local function undoPop(s: Search, c: number, popped: number)
	local col = s.grid[c]
	local h = s.heights[c]
	for r = 1, h do
		toggle(s, col[r], c, r)
	end
	for r = h, 1, -1 do
		col[r + 1] = col[r]
	end
	col[1] = popped
	s.heights[c] = h + 1
	for r = 1, h + 1 do
		toggle(s, col[r], c, r)
	end
end

-- After popping column c: who has four now? (The popper wins ties.)
local function popResult(s: Search, c: number, me: number): number?
	local col = s.grid[c]
	local found = { false, false }
	for r = 1, s.heights[c] do
		local who = col[r]
		if not found[who] and wins(s.grid, c, r, who) then
			found[who] = true
		end
	end
	if found[me] then
		return me
	elseif found[3 - me] then
		return 3 - me
	end
	return nil
end

-- Moves are encoded as c (drop) or -c (pop).
local function negamax(s: Search, depth: number, alpha: number, beta: number, me: number, ply: number, filled: number): number
	checkTime(s)
	if s.outOfTime then
		return 0
	end
	local grid, heights = s.grid, s.heights
	-- Win right now?
	for c = 1, COLS do
		local h = heights[c]
		if h < ROWS and wins(grid, c, h + 1, me) then
			return WIN_SCORE - ply
		end
	end
	if not s.popOut and filled >= COLS * ROWS then
		return 0
	end
	-- Must block: the other side wins next move in these columns.
	local forced: number? = nil
	for c = 1, COLS do
		local h = heights[c]
		if h < ROWS and wins(grid, c, h + 1, 3 - me) then
			if forced and not s.popOut then
				return -(WIN_SCORE - ply - 1) -- two threats: can't block both
			end
			forced = c
		end
	end
	if depth <= 0 then
		return evaluate(grid, heights, me, s.first)
	end

	local alpha0 = alpha
	local entry = s.tt[s.lo]
	local ttMove = 0
	if entry and entry[1] == s.hi then
		ttMove = entry[5]
		if entry[2] >= depth then
			local score, flag = entry[3], entry[4]
			if flag == EXACT then
				return score
			elseif flag == LOWER then
				alpha = math.max(alpha, score)
			else
				beta = math.min(beta, score)
			end
			if alpha >= beta then
				return score
			end
		end
	end

	local moves: { number } = {}
	if forced and not s.popOut then
		moves[1] = forced
	else
		if ttMove ~= 0 then
			table.insert(moves, ttMove)
		end
		for _, c in CENTER_FIRST do
			if heights[c] < ROWS and c ~= ttMove then
				-- Playing right under the other side's winning cell hands it to them: try it last.
				table.insert(moves, c)
			end
		end
		if s.popOut then
			for c = 1, COLS do
				if grid[c][1] == me and -c ~= ttMove then
					table.insert(moves, -c)
				end
			end
		end
	end

	local best, bestMove = -math.huge, 0
	for _, m in moves do
		local score
		if m > 0 then
			local r = heights[m] + 1
			grid[m][r] = me
			heights[m] = r
			toggle(s, me, m, r)
			flipSide(s)
			score = -negamax(s, depth - 1, -beta, -alpha, 3 - me, ply + 1, filled + 1)
			flipSide(s)
			toggle(s, me, m, r)
			grid[m][r] = 0
			heights[m] = r - 1
		else
			local c = -m
			local popped = doPop(s, c)
			local winner = popResult(s, c, me)
			if winner == me then
				score = WIN_SCORE - ply
			elseif winner then
				score = -(WIN_SCORE - ply)
			else
				flipSide(s)
				score = -negamax(s, depth - 1, -beta, -alpha, 3 - me, ply + 1, filled - 1)
				flipSide(s)
			end
			undoPop(s, c, popped)
		end
		if s.outOfTime then
			return 0
		end
		if score > best then
			best, bestMove = score, m
		end
		if best > alpha then
			alpha = best
		end
		if alpha >= beta then
			break
		end
	end
	if best == -math.huge then
		return 0 -- no move at all (Pop Out): a draw
	end

	if s.ttCount >= TT_MAX then
		table.clear(s.tt)
		s.ttCount = 0
	end
	if not s.tt[s.lo] then
		s.ttCount += 1
	end
	local flag = if best <= alpha0 then UPPER elseif best >= beta then LOWER else EXACT
	s.tt[s.lo] = { s.hi, depth, best, flag, bestMove }
	return best
end

local LEVELS = {
	easy = { depth = 1, randomChance = 0.35, seconds = 0.05 },
	medium = { depth = 4, randomChance = 0.05, seconds = 0.2 },
	hard = { depth = 24, randomChance = 0, seconds = 0.5 }, -- the search blocks the server: keep it short
}
FourInARow.LEVELS = LEVELS

-- Scores every legal move for `seat`: [c] for a drop, [-c] for a pop. Iterative deepening
-- keeps the last finished depth.
function FourInARow.scoreColumns(state: State, seat: number, maxDepth: number, seconds: number): { [number]: number }
	local hi, lo = hashOf(state.grid, seat)
	local s: Search = {
		grid = GameModule.copy(state.grid),
		heights = table.clone(state.heights),
		hi = hi,
		lo = lo,
		nodes = 0,
		deadline = os.clock() + seconds,
		outOfTime = false,
		popOut = state.popOut == true,
		first = 1,
		tt = {},
		ttCount = 0,
	}
	local filled = 0
	for c = 1, COLS do
		filled += state.heights[c]
	end
	local moves = {}
	for _, c in CENTER_FIRST do
		if s.heights[c] < ROWS then
			table.insert(moves, c)
		end
	end
	if s.popOut then
		for c = 1, COLS do
			if s.grid[c][1] == seat then
				table.insert(moves, -c)
			end
		end
	end
	local finished: { [number]: number } = {}
	for depth = 1, maxDepth do
		local scores = {}
		for _, m in moves do
			if m > 0 then
				local r = s.heights[m] + 1
				if wins(s.grid, m, r, seat) then
					scores[m] = WIN_SCORE
				else
					s.grid[m][r] = seat
					s.heights[m] = r
					toggle(s, seat, m, r)
					flipSide(s)
					scores[m] = -negamax(s, depth - 1, -math.huge, math.huge, 3 - seat, 1, filled + 1)
					flipSide(s)
					toggle(s, seat, m, r)
					s.grid[m][r] = 0
					s.heights[m] = r - 1
				end
			else
				local c = -m
				local popped = doPop(s, c)
				local winner = popResult(s, c, seat)
				if winner == seat then
					scores[m] = WIN_SCORE
				elseif winner then
					scores[m] = -WIN_SCORE
				else
					flipSide(s)
					scores[m] = -negamax(s, depth - 1, -math.huge, math.huge, 3 - seat, 1, filled - 1)
					flipSide(s)
				end
				undoPop(s, c, popped)
			end
			if s.outOfTime then
				break
			end
		end
		if s.outOfTime then
			break
		end
		finished = scores
		-- Solved: every move is a known win or loss, deeper search won't change it.
		local settled = true
		for _, score in scores do
			if math.abs(score) < WIN_SCORE - 100 then
				settled = false
				break
			end
		end
		if settled then
			break
		end
		-- Search the best move first next time.
		table.sort(moves, function(a, b)
			return (scores[a] or -math.huge) > (scores[b] or -math.huge)
		end)
	end
	return finished
end

function FourInARow.chooseBotMove(state: State, seat: number, rng: Random): any?
	local st = state :: any
	if st.offer and not isOver(state) then
		if seat ~= Offers.answerer(st) then
			return nil
		end
		-- Bots allow takebacks, and take a draw when they're not ahead.
		if st.offer.kind == "takeback" then
			return { type = "answer", accept = true }
		end
		local scores = FourInARow.scoreColumns(state, state.turn, 4, 0.1)
		local best = -math.huge
		for _, score in scores do
			best = math.max(best, score)
		end
		local forBot = if state.turn == seat then best else -best
		return { type = "answer", accept = forBot <= 0 }
	end
	if isOver(state) or seat ~= state.turn then
		return nil
	end
	local level = LEVELS[state.botLevel] or LEVELS.medium
	local moves = FourInARow.getLegalMoves(state, seat)
	if #moves == 0 then
		return nil
	end
	if rng:NextNumber() < level.randomChance then
		return moves[rng:NextInteger(1, #moves)]
	end
	-- Hard knows the opening: the centre first, and the centre in reply.
	if state.botLevel == "hard" and state.moveCount <= 1 and state.heights[4] < ROWS then
		local others = 0
		for c = 1, COLS do
			if c ~= 4 then
				others += state.heights[c]
			end
		end
		if others == 0 then
			return { column = 4 }
		end
	end
	local scores = FourInARow.scoreColumns(state, seat, level.depth, level.seconds)
	local bestScore, best = -math.huge, {}
	for m, score in scores do
		if score > bestScore then
			bestScore, best = score, { m }
		elseif score == bestScore then
			table.insert(best, m)
		end
	end
	if #best == 0 then
		return moves[rng:NextInteger(1, #moves)]
	end
	-- Ties: hard prefers the centre-most drop; others pick at random among them.
	table.sort(best, function(a, b)
		return math.abs(math.abs(a) - 4) < math.abs(math.abs(b) - 4) or (math.abs(math.abs(a) - 4) == math.abs(math.abs(b) - 4) and a > b)
	end)
	local m = if state.botLevel == "hard" then best[1] else best[rng:NextInteger(1, #best)]
	if m < 0 then
		return { column = -m, pop = true }
	end
	return { column = m }
end

-- A natural pause before a bot moves: quick when forced, longer for a real choice.
function FourInARow.getBotDelay(state, seat: number, rng: Random): number
	return BotThink.delay(rng, #FourInARow.getLegalMoves(state, seat), { base = 0.8, perDoubling = 0.2, max = 2.4 })
end

return FourInARow
