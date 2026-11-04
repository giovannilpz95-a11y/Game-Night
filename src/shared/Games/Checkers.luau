-- Checkers (American rules / English draughts) on an 8x8 board.
--
-- board[row][col], row 1 is the top of the board as seat 1 sees it. Pieces sit on dark
-- squares, where (row + col) is odd. Values: 0 empty, 1 dark man, 2 light man,
-- 3 dark king, 4 light king. Seat 1 is Dark: starts on rows 6-8, moves up, goes first.
--
-- Move: { from = { row, col }, path = { { row, col }, ... } }
--   A plain step has one square in `path`. A jump lists every landing square in order.
--
-- Rules: captures are forced (any capture, not the longest); a piece must keep jumping
-- while it can; a man that reaches the far row is crowned and its turn ends there.
-- A player with no legal moves loses. 40 moves each with no capture and no man moving
-- is a draw.
-- House rule "forcedCaptures" = false: jumping is allowed but not required (a jump that
-- is started still has to be finished).

local GameModule = require(script.Parent.Parent.GameModule)

local Checkers = {}

Checkers.id = "Checkers"
Checkers.minSeats = 2
Checkers.maxSeats = 2

local SIZE = 8
local NO_PROGRESS_LIMIT = 80 -- plies (40 moves each)

export type Square = { number }
export type Move = { from: Square, path: { Square } }

local function owner(v: number): number
	return if v == 0 then 0 else (v - 1) % 2 + 1
end

local function isKing(v: number): boolean
	return v > 2
end

local function forward(seat: number): number
	return if seat == 1 then -1 else 1
end

local function onBoard(r: number, c: number): boolean
	return r >= 1 and r <= SIZE and c >= 1 and c <= SIZE
end

local function crownRow(seat: number): number
	return if seat == 1 then 1 else SIZE
end

function Checkers.new(seatCount: number, options: any?, _rng: Random?)
	assert(seatCount == 2, "Checkers needs exactly 2 seats")
	local board = {}
	for r = 1, SIZE do
		board[r] = table.create(SIZE, 0)
		for c = 1, SIZE do
			if (r + c) % 2 == 1 then
				if r <= 3 then
					board[r][c] = 2
				elseif r >= 6 then
					board[r][c] = 1
				end
			end
		end
	end
	return {
		board = board,
		turn = 1,
		quietPlies = 0,
		lastMove = nil,
		winner = nil,
		isDraw = false,
		reason = nil,
		botLevel = (options and options.botLevel) or "medium",
		optionalCaptures = options ~= nil and options.rules ~= nil and options.rules.forcedCaptures == false,
	}
end

local function directions(v: number): { { number } }
	local f = forward(owner(v))
	if isKing(v) then
		return { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }
	end
	return { { f, -1 }, { f, 1 } }
end

-- All jump sequences for the piece at (r, c). `board` is modified during the search
-- and restored before returning.
local function jumpsFrom(board, r: number, c: number, v: number, path: { Square }, out: { Move }, origin: Square)
	local found = false
	local seat = owner(v)
	for _, d in directions(v) do
		local mr, mc = r + d[1], c + d[2]
		local lr, lc = r + 2 * d[1], c + 2 * d[2]
		if onBoard(lr, lc) and board[lr][lc] == 0 then
			local middle = board[mr][mc]
			if middle ~= 0 and owner(middle) ~= seat then
				found = true
				local newPath = table.clone(path)
				table.insert(newPath, { lr, lc })
				-- Remove the captured piece while searching so it can't be jumped twice.
				board[mr][mc] = 0
				board[r][c] = 0
				local crowned = not isKing(v) and lr == crownRow(seat)
				if crowned then
					table.insert(out, { from = origin, path = newPath })
				else
					board[lr][lc] = v
					if not jumpsFrom(board, lr, lc, v, newPath, out, origin) then
						table.insert(out, { from = origin, path = newPath })
					end
					board[lr][lc] = 0
				end
				board[r][c] = v
				board[mr][mc] = middle
			end
		end
	end
	return found
end

-- Returns the legal moves and whether a jump is required. With optional captures the
-- jumps and steps come back together and nothing is required.
local function generate(board, seat: number, optional: boolean?): ({ Move }, boolean)
	local jumps: { Move } = {}
	for r = 1, SIZE do
		for c = 1, SIZE do
			local v = board[r][c]
			if v ~= 0 and owner(v) == seat then
				jumpsFrom(board, r, c, v, {}, jumps, { r, c })
			end
		end
	end
	if #jumps > 0 and not optional then
		return jumps, true
	end
	local steps: { Move } = jumps
	for r = 1, SIZE do
		for c = 1, SIZE do
			local v = board[r][c]
			if v ~= 0 and owner(v) == seat then
				for _, d in directions(v) do
					local nr, nc = r + d[1], c + d[2]
					if onBoard(nr, nc) and board[nr][nc] == 0 then
						table.insert(steps, { from = { r, c }, path = { { nr, nc } } })
					end
				end
			end
		end
	end
	return steps, false
end

-- Applies a move that is known to be legal. Returns true if it captured anything.
local function apply(board, move: Move): boolean
	local r, c = move.from[1], move.from[2]
	local v = board[r][c]
	local capture = false
	board[r][c] = 0
	for _, sq in move.path do
		if math.abs(sq[1] - r) == 2 then
			board[(sq[1] + r) // 2][(sq[2] + c) // 2] = 0
			capture = true
		end
		r, c = sq[1], sq[2]
	end
	if not isKing(v) and r == crownRow(owner(v)) then
		v += 2
	end
	board[r][c] = v
	return capture
end

local function isOver(state): boolean
	return state.winner ~= nil or state.isDraw
end

function Checkers.getActiveSeats(state): { number }
	return if isOver(state) then {} else { state.turn }
end

function Checkers.getLegalMoves(state, seat: number): { any }
	if isOver(state) or seat ~= state.turn then
		return {}
	end
	return (generate(state.board, seat, state.optionalCaptures))
end

local function sameMove(a: Move, b: any): boolean
	if type(b) ~= "table" or type(b.from) ~= "table" or type(b.path) ~= "table" then
		return false
	end
	if b.from[1] ~= a.from[1] or b.from[2] ~= a.from[2] or #b.path ~= #a.path then
		return false
	end
	for i, sq in a.path do
		local other = b.path[i]
		if type(other) ~= "table" or other[1] ~= sq[1] or other[2] ~= sq[2] then
			return false
		end
	end
	return true
end

function Checkers.validateMove(state, seat: number, move: any): (boolean, string?)
	if isOver(state) then
		return false, "The game is over"
	end
	if seat ~= state.turn then
		return false, "It's not your turn"
	end
	local moves, mustJump = generate(state.board, seat, state.optionalCaptures)
	for _, legal in moves do
		if sameMove(legal, move) then
			return true
		end
	end
	return false, if mustJump then "You have to jump when you can" else "That move isn't allowed"
end

function Checkers.applyMove(state, seat: number, move: any)
	-- Store a clean copy (the move came from the network).
	local clean: Move = { from = { move.from[1], move.from[2] }, path = {} }
	for _, sq in move.path do
		table.insert(clean.path, { sq[1], sq[2] })
	end
	local piece = state.board[clean.from[1]][clean.from[2]]
	local capture = apply(state.board, clean)
	state.lastMove = clean
	local landed = clean.path[#clean.path]
	if landed and not isKing(piece) and isKing(state.board[landed[1]][landed[2]]) then
		GameModule.addStat(state, seat, "kings")
	end
	if capture or not isKing(piece) then
		state.quietPlies = 0
	else
		state.quietPlies += 1
	end

	local nextSeat = 3 - seat
	local replies = generate(state.board, nextSeat, state.optionalCaptures)
	if #replies == 0 then
		state.winner = seat
		state.reason = "No moves left"
	elseif state.quietPlies >= NO_PROGRESS_LIMIT then
		state.isDraw = true
		state.reason = "40 moves without progress"
	else
		state.turn = nextSeat
	end
end

function Checkers.getResult(state): GameModule.Result?
	if state.winner then
		return { winners = { state.winner }, isDraw = false, reason = state.reason }
	elseif state.isDraw then
		return { winners = {}, isDraw = true, reason = state.reason }
	end
	return nil
end

function Checkers.getView(state, seat: number?): any
	local view = GameModule.copy(state)
	if seat and not isOver(state) and seat == state.turn then
		local moves, mustJump = generate(state.board, seat, state.optionalCaptures)
		view.legalMoves = moves
		view.mustJump = mustJump
	end
	return view
end

-- Bot ---------------------------------------------------------------------

local function evaluate(board, me: number): number
	local score = 0
	for r = 1, SIZE do
		for c = 1, SIZE do
			local v = board[r][c]
			if v ~= 0 then
				local seat = owner(v)
				local value
				if isKing(v) then
					value = 160
				else
					local advanced = if seat == 1 then SIZE - r else r - 1
					value = 100 + advanced * 3
					if r == (if seat == 1 then SIZE else 1) then
						value += 8 -- back row guard
					end
				end
				if c >= 3 and c <= 6 and r >= 3 and r <= 6 then
					value += 4
				end
				score += if seat == me then value else -value
			end
		end
	end
	return score
end

local function copyBoard(board)
	local out = {}
	for r = 1, SIZE do
		out[r] = table.clone(board[r])
	end
	return out
end

local WIN = 100000

type Search = { nodes: number, deadline: number, outOfTime: boolean, optional: boolean }

local function negamax(s: Search, board, seat: number, depth: number, alpha: number, beta: number, ply: number): number
	s.nodes += 1
	if s.nodes % 256 == 0 and os.clock() > s.deadline then
		s.outOfTime = true
	end
	if s.outOfTime then
		return 0
	end
	local moves, mustJump = generate(board, seat, s.optional)
	if #moves == 0 then
		return -WIN + ply
	end
	-- Keep searching forced jump sequences so the bot doesn't stop mid-trade.
	if depth <= 0 and not mustJump then
		return evaluate(board, seat)
	end
	local best = -math.huge
	for _, move in moves do
		local child = copyBoard(board)
		apply(child, move)
		local score = -negamax(s, child, 3 - seat, depth - 1, -beta, -alpha, ply + 1)
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
	return best
end

local LEVELS = {
	easy = { depth = 2, seconds = 0.05, slack = 60 },
	medium = { depth = 5, seconds = 0.3, slack = 0 },
	hard = { depth = 9, seconds = 0.9, slack = 0 },
}

function Checkers.chooseBotMove(state, seat: number, rng: Random): any?
	local level = LEVELS[state.botLevel] or LEVELS.medium
	local moves = generate(state.board, seat, state.optionalCaptures)
	if #moves == 0 then
		return nil
	end
	if #moves == 1 then
		return moves[1]
	end
	local s: Search = { nodes = 0, deadline = os.clock() + level.seconds, outOfTime = false, optional = state.optionalCaptures }
	local scores: { number }? = nil
	for depth = 1, level.depth do
		local current = {}
		for i, move in moves do
			local child = copyBoard(state.board)
			apply(child, move)
			current[i] = -negamax(s, child, 3 - seat, depth - 1, -math.huge, math.huge, 1)
		end
		if s.outOfTime then
			break
		end
		scores = current
	end
	if not scores then
		return moves[rng:NextInteger(1, #moves)]
	end
	local bestScore = -math.huge
	for _, score in scores do
		bestScore = math.max(bestScore, score)
	end
	-- Easy bots pick among moves that are "close enough", so they make mistakes.
	local pool = {}
	for i, score in scores do
		if score >= bestScore - level.slack then
			table.insert(pool, moves[i])
		end
	end
	return pool[rng:NextInteger(1, #pool)]
end

-- Stats for the profile (see shared/StatsCatalog.luau): each side starts with 12 pieces.
function Checkers.getMatchStats(state): { [number]: { [string]: number } }
	local left = { 0, 0 }
	for r = 1, SIZE do
		for c = 1, SIZE do
			local v = state.board[r][c]
			if v ~= 0 then
				local who = owner(v)
				left[who] += 1
			end
		end
	end
	return { { captures = 12 - left[2] }, { captures = 12 - left[1] } }
end

return Checkers
