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
-- is a draw, and so is the same position (and side to move) coming up three times.
-- House rule "forcedCaptures" = false: jumping is allowed but not required (a jump that
-- is started still has to be finished).
-- House rule "flyingKings": kings slide any distance along a diagonal and can jump a
-- piece from far away, landing on any empty square beyond it (international draughts).
-- Jumped pieces stay on the board until the capture ends, so none is taken twice, and the
-- king must land where the capture can go on if it can.
-- House rule "backCaptures": men may jump backward too (they still step forward only).

local GameModule = require(script.Parent.Parent.GameModule)
local BotThink = require(script.Parent.Parent.BotThink)
local Offers = require(script.Parent.Parent.Offers)

local Checkers = {}

Checkers.id = "Checkers"
Checkers.minSeats = 2
Checkers.maxSeats = 2

local SIZE = 8
local NO_PROGRESS_LIMIT = 80 -- plies (40 moves each)

export type Square = { number }
export type Move = { from: Square, path: { Square }, crowned: boolean? }

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

-- Zobrist keys (two 32-bit keys) for the transposition table and repetitions.
local zSeed = 0x1F2E3D4C
local function rand32(): number
	zSeed = bit32.bxor(zSeed, bit32.lshift(zSeed, 13))
	zSeed = bit32.bxor(zSeed, bit32.rshift(zSeed, 17))
	zSeed = bit32.bxor(zSeed, bit32.lshift(zSeed, 5))
	return zSeed
end
local Z1, Z2 = {}, {}
for v = 1, 4 do
	Z1[v], Z2[v] = {}, {}
	for sq = 1, SIZE * SIZE do
		Z1[v][sq], Z2[v][sq] = rand32(), rand32()
	end
end
local ZTURN1, ZTURN2 = rand32(), rand32()

local function hashBoard(board, seat: number): (number, number)
	local h1, h2 = 0, 0
	for r = 1, SIZE do
		local row = board[r]
		for c = 1, SIZE do
			local v = row[c]
			if v > 0 then
				local sq = (r - 1) * SIZE + c
				h1 = bit32.bxor(h1, Z1[v][sq])
				h2 = bit32.bxor(h2, Z2[v][sq])
			end
		end
	end
	if seat == 2 then
		h1, h2 = bit32.bxor(h1, ZTURN1), bit32.bxor(h2, ZTURN2)
	end
	return h1, h2
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
	local state = {
		board = board,
		turn = 1,
		quietPlies = 0,
		lastMove = nil,
		winner = nil,
		isDraw = false,
		reason = nil,
		botLevel = (options and options.botLevel) or "medium",
		optionalCaptures = options ~= nil and options.rules ~= nil and options.rules.forcedCaptures == false,
		flyingKings = options ~= nil and options.rules ~= nil and options.rules.flyingKings == true,
		backCaptures = options ~= nil and options.rules ~= nil and options.rules.backCaptures == true,
	}
	-- How often each position (board + side to move) has come up: three times is a draw.
	state.history = { [(hashBoard(board, 1))] = 1 }
	Offers.init(state)
	return state
end

type Opts = { optional: boolean?, flying: boolean?, backward: boolean? }

local function optsOf(state): Opts
	return { optional = state.optionalCaptures, flying = state.flyingKings, backward = state.backCaptures }
end

local ALL_DIRECTIONS = { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }

local function directions(v: number): { { number } }
	local f = forward(owner(v))
	if isKing(v) then
		return ALL_DIRECTIONS
	end
	return { { f, -1 }, { f, 1 } }
end

-- Directions a piece may capture in (men capture backward with "backCaptures").
local function captureDirections(v: number, opts: Opts?): { { number } }
	if opts and opts.backward then
		return ALL_DIRECTIONS
	end
	return directions(v)
end

-- A piece already jumped in this capture (flying kings only). It stays on the board until
-- the capture ends, the way International and Russian draughts play it: it blocks the
-- king's path and can't be jumped a second time.
local DEAD = -1

-- All jump sequences for the piece at (r, c). `board` is modified during the search
-- and restored before returning.
local function jumpsFrom(board, r: number, c: number, v: number, path: { Square }, out: { Move }, origin: Square, opts: Opts?)
	local found = false
	local seat = owner(v)
	local flying = opts ~= nil and opts.flying == true and isKing(v)
	for _, d in captureDirections(v, opts) do
		-- Find the piece to jump: next door, or (flying king) the first piece along the line.
		local mr, mc = r + d[1], c + d[2]
		if flying then
			while onBoard(mr, mc) and board[mr][mc] == 0 do
				mr, mc = mr + d[1], mc + d[2]
			end
		end
		if not onBoard(mr, mc) then
			continue
		end
		local middle = board[mr][mc]
		if middle == 0 or middle == DEAD or owner(middle) == seat then
			continue
		end
		local lr, lc = mr + d[1], mc + d[2]
		if flying then
			-- Every empty square past the piece is a landing spot, but if the capture can go
			-- on from some of them, the king has to land on one of those.
			local landings = {}
			while onBoard(lr, lc) and board[lr][lc] == 0 do
				table.insert(landings, { lr, lc })
				lr, lc = lr + d[1], lc + d[2]
			end
			if #landings == 0 then
				continue
			end
			found = true
			board[mr][mc] = DEAD
			board[r][c] = 0
			local results = {}
			local anyGoesOn = false
			for _, land in landings do
				local newPath = table.clone(path)
				table.insert(newPath, land)
				local further: { Move } = {}
				board[land[1]][land[2]] = v
				local goesOn = jumpsFrom(board, land[1], land[2], v, newPath, further, origin, opts)
				board[land[1]][land[2]] = 0
				anyGoesOn = anyGoesOn or goesOn
				table.insert(results, { goesOn = goesOn, further = further, path = newPath })
			end
			board[r][c] = v
			board[mr][mc] = middle
			for _, result in results do
				if result.goesOn then
					table.move(result.further, 1, #result.further, #out + 1, out)
				elseif not anyGoesOn then
					table.insert(out, { from = origin, path = result.path })
				end
			end
			continue
		end
		if onBoard(lr, lc) and board[lr][lc] == 0 then
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
				if not jumpsFrom(board, lr, lc, v, newPath, out, origin, opts) then
					table.insert(out, { from = origin, path = newPath })
				end
				board[lr][lc] = 0
			end
			board[r][c] = v
			board[mr][mc] = middle
		end
	end
	return found
end

-- Returns the legal moves and whether a jump is required. With optional captures the
-- jumps and steps come back together and nothing is required.
local function generate(board, seat: number, opts: Opts?): ({ Move }, boolean)
	local optional = opts ~= nil and opts.optional == true
	local jumps: { Move } = {}
	for r = 1, SIZE do
		for c = 1, SIZE do
			local v = board[r][c]
			if v ~= 0 and owner(v) == seat then
				jumpsFrom(board, r, c, v, {}, jumps, { r, c }, opts)
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
				local slide = opts ~= nil and opts.flying == true and isKing(v)
				for _, d in directions(v) do
					local nr, nc = r + d[1], c + d[2]
					while onBoard(nr, nc) and board[nr][nc] == 0 do
						table.insert(steps, { from = { r, c }, path = { { nr, nc } } })
						if not slide then
							break
						end
						nr, nc = nr + d[1], nc + d[2]
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
		-- Clear any piece passed over on the way (a flying king's jump can be long).
		local dr, dc = if sq[1] > r then 1 else -1, if sq[2] > c then 1 else -1
		local pr, pc = r + dr, c + dc
		while pr ~= sq[1] and onBoard(pr, pc) do
			if board[pr][pc] ~= 0 then
				board[pr][pc] = 0
				capture = true
			end
			pr, pc = pr + dr, pc + dc
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
	return if isOver(state) then {} else { Offers.answerer(state) or state.turn }
end

-- Right after your move you may offer a draw or ask to undo it (Offers).
function Checkers.getInterruptSeats(state): { number }
	return Offers.interruptSeats(state, if isOver(state) then nil else state.turn)
end

-- One turn per move: draw offers and their answers don't restart the turn clock.
function Checkers.getTurnKey(state): any
	return #state.undo
end

local function cloneBoard(board)
	local out = {}
	for r, row in board do
		out[r] = table.clone(row)
	end
	return out
end

-- Puts the game back to before its last move (takebacks).
local function undoOne(state)
	local entry = table.remove(state.undo)
	if entry then
		local key = hashBoard(state.board, state.turn)
		if state.history[key] then
			state.history[key] = math.max(0, state.history[key] - 1)
		end
		if entry.crowned and state.matchStats and state.matchStats[entry.crowned] then
			-- The crowning is taken back too.
			local row = state.matchStats[entry.crowned]
			row.kings = math.max(0, (row.kings or 1) - 1)
		end
		state.board = entry.board
		state.turn = entry.turn
		state.quietPlies = entry.quietPlies
		state.lastMove = entry.lastMove
	end
end

function Checkers.getLegalMoves(state, seat: number): { any }
	if state.offer and not isOver(state) then
		if seat ~= Offers.answerer(state) then
			return {}
		end
		return { { type = "answer", accept = true }, { type = "answer", accept = false } }
	end
	if isOver(state) or seat ~= state.turn then
		return {}
	end
	return (generate(state.board, seat, optsOf(state)))
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
	if Offers.isMove(move) then
		return Offers.validate(state, seat, move, state.turn)
	end
	if type(move) ~= "table" then
		return false, "That move isn't allowed"
	end
	if state.offer then
		return false, "Waiting for an answer"
	end
	if seat ~= state.turn then
		return false, "It's not your turn"
	end
	local moves, mustJump = generate(state.board, seat, optsOf(state))
	for _, legal in moves do
		if sameMove(legal, move) then
			return true
		end
	end
	return false, if mustJump then "You have to jump when you can" else "That move isn't allowed"
end

function Checkers.applyMove(state, seat: number, move: any)
	if Offers.isMove(move) then
		local accepted = Offers.apply(state, seat, move, undoOne, state.turn)
		if accepted == "draw" then
			state.isDraw = true
			state.reason = "Draw agreed"
		elseif accepted == "abort" then
			state.isDraw = true
			state.reason = "Game aborted"
		end
		return
	end
	table.insert(state.undo, {
		board = cloneBoard(state.board),
		turn = state.turn,
		quietPlies = state.quietPlies,
		lastMove = state.lastMove,
	})
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
		clean.crowned = true -- the crowning moment (the table sparkles)
		GameModule.addStat(state, seat, "kings")
		state.undo[#state.undo].crowned = seat
	end
	if capture or not isKing(piece) then
		state.quietPlies = 0
	else
		state.quietPlies += 1
	end

	local nextSeat = 3 - seat
	local replies = generate(state.board, nextSeat, optsOf(state))
	local key = hashBoard(state.board, nextSeat)
	state.history[key] = (state.history[key] or 0) + 1
	if #replies == 0 then
		state.winner = seat
		local left = 0
		for r = 1, SIZE do
			for c = 1, SIZE do
				if owner(state.board[r][c]) == nextSeat then
					left += 1
				end
			end
		end
		state.reason = if left == 0 then "All pieces captured" else "No moves left"
	elseif state.quietPlies >= NO_PROGRESS_LIMIT then
		state.isDraw = true
		state.reason = "40 moves without progress"
	elseif state.history[key] >= 3 then
		state.isDraw = true
		state.reason = "Threefold repetition"
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
	local undo, asked, history = state.undo, state.asked, state.history
	state.undo, state.asked, state.history = nil, nil, nil
	local view = GameModule.copy(state)
	state.undo, state.asked, state.history = undo, asked, history
	view.offer = nil
	view.takebacks = nil
	view.drawBlocked = nil
	view.matchStats = nil
	view.moveCount = #undo
	if seat and not isOver(state) and not state.offer and seat == state.turn then
		local moves, mustJump = generate(state.board, seat, optsOf(state))
		view.legalMoves = moves
		view.mustJump = mustJump
	end
	Offers.addToView(view, state, seat, if isOver(state) then nil else state.turn, function(s)
		return if s == 1 then "Dark" else "Light"
	end)
	return view
end

-- Bot ---------------------------------------------------------------------
-- Negamax with alpha-beta at every level (the root too), captures and the previous best
-- move searched first, killer moves, a transposition table, iterative deepening under a
-- time budget, and the 40-move rule and repetitions seen inside the search. In the
-- endgame a side that is ahead hunts the other side's pieces with its kings and pulls a
-- lone king out of the double corner, so 2 kings v 1 gets won.

local DOUBLE_CORNER = { [1 * 10 + 2] = true, [2 * 10 + 1] = true, [7 * 10 + 8] = true, [8 * 10 + 7] = true }

local function evaluate(board, me: number): number
	local score = 0
	local count = { 0, 0 }
	local material = { 0, 0 }
	for r = 1, SIZE do
		for c = 1, SIZE do
			local v = board[r][c]
			if v > 0 then
				local seat = owner(v)
				count[seat] += 1
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
				material[seat] += if isKing(v) then 160 else 100
				if c >= 3 and c <= 6 and r >= 3 and r <= 6 then
					value += 4
				end
				score += if seat == me then value else -value
			end
		end
	end
	-- Endgame: the side ahead closes in with its kings; the side behind wants the double
	-- corner (where a lone king can't be trapped by two kings without help).
	if count[1] + count[2] <= 8 and material[1] ~= material[2] then
		local winner = if material[1] > material[2] then 1 else 2
		local bonus = 0
		for r = 1, SIZE do
			for c = 1, SIZE do
				local v = board[r][c]
				if v > 0 and owner(v) ~= winner then
					if DOUBLE_CORNER[r * 10 + c] then
						bonus -= 12
					end
					-- Edges are where pieces get trapped.
					if r == 1 or r == SIZE or c == 1 or c == SIZE then
						bonus += 4
					end
					for r2 = 1, SIZE do
						for c2 = 1, SIZE do
							local w = board[r2][c2]
							if w > 0 and owner(w) == winner and isKing(w) then
								local distance = math.max(math.abs(r - r2), math.abs(c - c2))
								bonus += (8 - distance) * 3
							end
						end
					end
				end
			end
		end
		score += if winner == me then bonus else -bonus
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

local function moveKey(m: Move): string
	local parts = { `{m.from[1]},{m.from[2]}` }
	for _, sq in m.path do
		table.insert(parts, `{sq[1]},{sq[2]}`)
	end
	return table.concat(parts, ">")
end

local TT_EXACT, TT_LOWER, TT_UPPER = 0, 1, 2
local ttCheck: { [number]: number } = {}
local ttDepth: { [number]: number } = {}
local ttScore: { [number]: number } = {}
local ttFlag: { [number]: number } = {}
local ttMove: { [number]: string } = {}
local ttCount = 0
local TT_MAX = 150000

type Search = {
	nodes: number,
	deadline: number,
	outOfTime: boolean,
	opts: Opts,
	seen: { [number]: number },
	killers: { [number]: string },
}

local function orderMoves(moves: { Move }, first: string?, killer: string?)
	local keys = {}
	for _, m in moves do
		local key = moveKey(m)
		local k = 0
		if key == first then
			k = 100000
		elseif key == killer then
			k = 50
		end
		k += #m.path * 10 -- longer jumps first
		keys[m] = k
	end
	table.sort(moves, function(a, b)
		return keys[a] > keys[b]
	end)
end

local function negamax(s: Search, board, seat: number, depth: number, alpha: number, beta: number, ply: number, quiet: number): number
	s.nodes += 1
	if s.nodes % 64 == 0 and os.clock() > s.deadline then
		s.outOfTime = true
	end
	if s.outOfTime then
		return 0
	end
	if quiet >= NO_PROGRESS_LIMIT then
		return 0 -- the 40-move rule
	end
	local h1, h2 = hashBoard(board, seat)
	if ply > 0 and (s.seen[h1] or 0) > 0 then
		return 0 -- heading for a repetition
	end
	local first = nil
	if ttCheck[h1] == h2 then
		first = ttMove[h1]
		if ttDepth[h1] >= depth and ply > 0 then
			local score, flag = ttScore[h1], ttFlag[h1]
			if score > WIN - 1000 then
				score -= ply
			elseif score < -WIN + 1000 then
				score += ply
			end
			if flag == TT_EXACT or (flag == TT_LOWER and score >= beta) or (flag == TT_UPPER and score <= alpha) then
				return score
			end
		end
	end
	local moves, mustJump = generate(board, seat, s.opts)
	if #moves == 0 then
		return -WIN + ply
	end
	-- Keep searching forced jump sequences so the bot doesn't stop mid-trade.
	if depth <= 0 and not mustJump then
		return evaluate(board, seat)
	end
	orderMoves(moves, first, s.killers[ply])
	local alphaStart = alpha
	local best, bestMove = -math.huge, nil
	s.seen[h1] = (s.seen[h1] or 0) + 1
	for _, move in moves do
		local piece = board[move.from[1]][move.from[2]]
		local child = copyBoard(board)
		local captured = apply(child, move)
		local nextQuiet = if captured or not isKing(piece) then 0 else quiet + 1
		local score = -negamax(s, child, 3 - seat, depth - 1, -beta, -alpha, ply + 1, nextQuiet)
		if s.outOfTime then
			break
		end
		if score > best then
			best, bestMove = score, move
		end
		if best > alpha then
			alpha = best
		end
		if alpha >= beta then
			if not captured then
				s.killers[ply] = moveKey(move)
			end
			break
		end
	end
	s.seen[h1] -= 1
	if s.outOfTime then
		return 0
	end
	local flag = if best <= alphaStart then TT_UPPER elseif best >= beta then TT_LOWER else TT_EXACT
	if ttCheck[h1] == nil then
		ttCount += 1
		if ttCount > TT_MAX then
			ttCheck, ttDepth, ttScore, ttFlag, ttMove = {}, {}, {}, {}, {}
			ttCount = 1
		end
	end
	local stored = best
	if stored > WIN - 1000 then
		stored += ply
	elseif stored < -WIN + 1000 then
		stored -= ply
	end
	ttCheck[h1], ttDepth[h1], ttScore[h1], ttFlag[h1], ttMove[h1] = h2, depth, stored, flag, if bestMove then moveKey(bestMove) else ""
	return best
end

local LEVELS = {
	easy = { depth = 2, seconds = 0.05, slack = 60 },
	medium = { depth = 5, seconds = 0.25, slack = 0 },
	hard = { depth = 14, seconds = 0.45, slack = 0 }, -- the search blocks the server: keep it short
}
Checkers.LEVELS = LEVELS

-- Scores every move for `seat` (best first); with exact = false only the best is exact.
function Checkers.rankMoves(state, seat: number, maxDepth: number, seconds: number, exact: boolean): { { move: Move, score: number } }
	local opts = optsOf(state)
	local moves = generate(state.board, seat, opts)
	local s: Search = { nodes = 0, deadline = os.clock() + seconds, outOfTime = false, opts = opts, seen = {}, killers = {} }
	-- Positions already seen in this game count as repetitions inside the search.
	for key, n in state.history or {} do
		if n > 0 and type(key) == "number" then
			s.seen[key] = n
		end
	end
	local rootH1 = hashBoard(state.board, seat)
	s.seen[rootH1] = (s.seen[rootH1] or 0) + 1
	local ranked = {}
	for _, m in moves do
		table.insert(ranked, { move = m, score = 0 })
	end
	local bestFirst: string? = nil
	for depth = 1, maxDepth do
		orderMoves(moves, bestFirst, nil)
		local current = {}
		local alpha = -math.huge
		for _, move in moves do
			local piece = state.board[move.from[1]][move.from[2]]
			local child = copyBoard(state.board)
			local captured = apply(child, move)
			local quiet = if captured or not isKing(piece) then 0 else state.quietPlies + 1
			local score = -negamax(s, child, 3 - seat, depth - 1, -math.huge, if exact then math.huge else -alpha, 1, quiet)
			if s.outOfTime then
				break
			end
			if not exact then
				if score > alpha then
					alpha = score
				elseif #current > 0 then
					score = alpha - 1
				end
			end
			table.insert(current, { move = move, score = score })
		end
		if #current == #moves then
			table.sort(current, function(a, b)
				return a.score > b.score
			end)
			ranked = current
			bestFirst = moveKey(current[1].move)
			if current[1].score >= WIN - 100 then
				break
			end
		end
		if s.outOfTime then
			break
		end
	end
	return ranked
end

function Checkers.chooseBotMove(state, seat: number, rng: Random): any?
	if state.offer and not isOver(state) then
		if seat ~= Offers.answerer(state) then
			return nil
		end
		-- Takebacks are fine. A draw only once the game has gone a while (no early draws)
		-- and the bot isn't clearly ahead, or straight away when it is clearly behind.
		local score = evaluate(state.board, seat)
		local accept = state.offer.kind == "takeback" or (#state.undo >= 30 and score < 60) or score < -150
		return { type = "answer", accept = accept }
	end
	if isOver(state) or seat ~= state.turn then
		return nil
	end
	local level = LEVELS[state.botLevel] or LEVELS.medium
	local moves = generate(state.board, seat, optsOf(state))
	if #moves == 0 then
		return nil
	end
	if #moves == 1 then
		return moves[1]
	end
	local ranked = Checkers.rankMoves(state, seat, level.depth, level.seconds, level.slack > 0)
	if #ranked == 0 then
		return moves[rng:NextInteger(1, #moves)]
	end
	local bestScore = ranked[1].score
	-- Easy bots pick among moves that are "close enough", so they make mistakes.
	local pool = {}
	for _, entry in ranked do
		if entry.score >= bestScore - level.slack then
			table.insert(pool, entry.move)
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

-- A natural pause before a bot moves: quick when forced, longer for a real choice.
function Checkers.getBotDelay(state, seat: number, rng: Random): number
	return BotThink.delay(rng, #Checkers.getLegalMoves(state, seat), { base = 0.9, perDoubling = 0.25, jitter = 0.7, max = 3.0 })
end

return Checkers
