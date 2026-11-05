-- Chess, full FIDE rules: castling, en passant, promotion, check, checkmate, stalemate,
-- threefold repetition, the 50-move rule and insufficient material.
-- House rule "kingOfTheHill": a king that reaches d4, e4, d5 or e5 also wins.
--
-- Squares are 0..63: a1 = 0, h1 = 7, a8 = 56, h8 = 63 (file = sq % 8, rank = sq // 8).
-- Pieces are numbers: 1 pawn, 2 knight, 3 bishop, 4 rook, 5 queen, 6 king.
-- White pieces are positive, black negative. Seat 1 plays White, seat 2 Black.
--
-- Move (over the network): { from = "e2", to = "e4", promotion = "q" | "r" | "b" | "n" | nil }
-- Takebacks: right after your move, { kind = "takeback" } asks to take it back (out of
-- turn: getInterruptSeats). The other player can { kind = "acceptTakeback" } on their
-- turn; moving on declines. TAKEBACKS per player per game.

local GameModule = require(script.Parent.Parent.GameModule)
local BotThink = require(script.Parent.Parent.BotThink)

local Chess = {}

Chess.id = "Chess"
Chess.minSeats = 2
Chess.maxSeats = 2

local PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING = 1, 2, 3, 4, 5, 6
Chess.Pieces = { PAWN = PAWN, KNIGHT = KNIGHT, BISHOP = BISHOP, ROOK = ROOK, QUEEN = QUEEN, KING = KING }

local WK, WQ, BK, BQ = 1, 2, 4, 8 -- castling right bits

local KNIGHT_STEPS = { { 1, 2 }, { 2, 1 }, { 2, -1 }, { 1, -2 }, { -1, -2 }, { -2, -1 }, { -2, 1 }, { -1, 2 } }
local KING_STEPS = { { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 } }
local DIAGONALS = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
local STRAIGHTS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local LETTER_TO_PIECE = { p = PAWN, n = KNIGHT, b = BISHOP, r = ROOK, q = QUEEN, k = KING }
local PIECE_TO_LETTER = { "p", "n", "b", "r", "q", "k" }
local FILES = "abcdefgh"

export type Pos = {
	board: { [number]: number },
	side: number, -- 1 white, -1 black
	castle: number,
	ep: number, -- en passant target square, or -1
	halfmove: number,
	fullmove: number,
	kings: { [number]: number },
}

export type Move = {
	from: number,
	to: number,
	piece: number,
	captured: number,
	promo: number?, -- piece type (unsigned)
	flag: string?, -- "ep" | "double" | "castleK" | "castleQ"
}

-- Square helpers ------------------------------------------------------------

local function sqAt(file: number, rank: number): number?
	if file < 0 or file > 7 or rank < 0 or rank > 7 then
		return nil
	end
	return rank * 8 + file
end

function Chess.squareName(sq: number): string
	return string.sub(FILES, sq % 8 + 1, sq % 8 + 1) .. tostring(sq // 8 + 1)
end

function Chess.parseSquare(name: any): number?
	if type(name) ~= "string" or #name ~= 2 then
		return nil
	end
	local file = string.find(FILES, string.sub(name, 1, 1), 1, true)
	local rank = tonumber(string.sub(name, 2, 2))
	if not file or not rank or rank < 1 or rank > 8 then
		return nil
	end
	return (rank - 1) * 8 + (file - 1)
end

-- FEN -------------------------------------------------------------------------

local START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
Chess.START_FEN = START_FEN

function Chess.fromFen(fen: string): Pos
	local parts = string.split(fen, " ")
	local board = {}
	for sq = 0, 63 do
		board[sq] = 0
	end
	local kings = { [1] = -1, [-1] = -1 }
	local rank, file = 7, 0
	for i = 1, #parts[1] do
		local ch = string.sub(parts[1], i, i)
		if ch == "/" then
			rank -= 1
			file = 0
		elseif tonumber(ch) then
			file += tonumber(ch) :: number
		else
			local lower = string.lower(ch)
			local color = if ch == lower then -1 else 1
			local piece = LETTER_TO_PIECE[lower]
			local sq = rank * 8 + file
			board[sq] = piece * color
			if piece == KING then
				kings[color] = sq
			end
			file += 1
		end
	end
	local castle = 0
	local rights = parts[3] or "-"
	if string.find(rights, "K", 1, true) then
		castle += WK
	end
	if string.find(rights, "Q", 1, true) then
		castle += WQ
	end
	if string.find(rights, "k", 1, true) then
		castle += BK
	end
	if string.find(rights, "q", 1, true) then
		castle += BQ
	end
	return {
		board = board,
		side = if parts[2] == "b" then -1 else 1,
		castle = castle,
		ep = if parts[4] and parts[4] ~= "-" then (Chess.parseSquare(parts[4]) or -1) else -1,
		halfmove = tonumber(parts[5]) or 0,
		fullmove = tonumber(parts[6]) or 1,
		kings = kings,
	}
end

function Chess.toFen(pos: Pos): string
	local rows = {}
	for rank = 7, 0, -1 do
		local row, empty = "", 0
		for file = 0, 7 do
			local v = pos.board[rank * 8 + file]
			if v == 0 then
				empty += 1
			else
				if empty > 0 then
					row ..= tostring(empty)
					empty = 0
				end
				local letter = PIECE_TO_LETTER[math.abs(v)]
				row ..= if v > 0 then string.upper(letter) else letter
			end
		end
		if empty > 0 then
			row ..= tostring(empty)
		end
		table.insert(rows, row)
	end
	local rights = ""
	if bit32.btest(pos.castle, WK) then
		rights ..= "K"
	end
	if bit32.btest(pos.castle, WQ) then
		rights ..= "Q"
	end
	if bit32.btest(pos.castle, BK) then
		rights ..= "k"
	end
	if bit32.btest(pos.castle, BQ) then
		rights ..= "q"
	end
	return table.concat({
		table.concat(rows, "/"),
		if pos.side == 1 then "w" else "b",
		if rights == "" then "-" else rights,
		if pos.ep >= 0 then Chess.squareName(pos.ep) else "-",
		tostring(pos.halfmove),
		tostring(pos.fullmove),
	}, " ")
end

-- Attacks ---------------------------------------------------------------------

-- Is `sq` attacked by any piece of color `by`?
local function attacked(board, sq: number, by: number): boolean
	local file, rank = sq % 8, sq // 8
	-- Pawns: a white pawn attacks diagonally upward, so look one rank below.
	local pawnRank = rank - by
	for _, df in { -1, 1 } do
		local from = sqAt(file + df, pawnRank)
		if from and board[from] == PAWN * by then
			return true
		end
	end
	for _, d in KNIGHT_STEPS do
		local from = sqAt(file + d[1], rank + d[2])
		if from and board[from] == KNIGHT * by then
			return true
		end
	end
	for _, d in KING_STEPS do
		local from = sqAt(file + d[1], rank + d[2])
		if from and board[from] == KING * by then
			return true
		end
	end
	for _, d in DIAGONALS do
		local f, r = file + d[1], rank + d[2]
		while f >= 0 and f <= 7 and r >= 0 and r <= 7 do
			local v = board[r * 8 + f]
			if v ~= 0 then
				if v == BISHOP * by or v == QUEEN * by then
					return true
				end
				break
			end
			f += d[1]
			r += d[2]
		end
	end
	for _, d in STRAIGHTS do
		local f, r = file + d[1], rank + d[2]
		while f >= 0 and f <= 7 and r >= 0 and r <= 7 do
			local v = board[r * 8 + f]
			if v ~= 0 then
				if v == ROOK * by or v == QUEEN * by then
					return true
				end
				break
			end
			f += d[1]
			r += d[2]
		end
	end
	return false
end

function Chess.inCheck(pos: Pos, side: number?): boolean
	local s = side or pos.side
	return attacked(pos.board, pos.kings[s], -s)
end

-- Move generation -------------------------------------------------------------

local function addPawnMove(moves: { Move }, from: number, to: number, piece: number, captured: number, flag: string?)
	local rank = to // 8
	if rank == 7 or rank == 0 then
		for _, promo in { QUEEN, ROOK, BISHOP, KNIGHT } do
			table.insert(moves, { from = from, to = to, piece = piece, captured = captured, promo = promo })
		end
	else
		table.insert(moves, { from = from, to = to, piece = piece, captured = captured, flag = flag })
	end
end

-- Moves that follow piece movement rules but may leave your own king in check.
-- With capturesOnly, quiet moves (and castling) are skipped; used by the bot's search.
local function pseudoMoves(pos: Pos, capturesOnly: boolean?): { Move }
	local board, side = pos.board, pos.side
	local moves: { Move } = {}
	for from = 0, 63 do
		local v = board[from]
		if v ~= 0 and (v > 0) == (side > 0) then
			local kind = math.abs(v)
			local file, rank = from % 8, from // 8
			if kind == PAWN then
				local one = sqAt(file, rank + side)
				if one and board[one] == 0 then
					if not capturesOnly or one // 8 == 7 or one // 8 == 0 then
						addPawnMove(moves, from, one, v, 0)
					end
					local startRank = if side == 1 then 1 else 6
					local two = sqAt(file, rank + 2 * side)
					if not capturesOnly and rank == startRank and two and board[two] == 0 then
						table.insert(moves, { from = from, to = two, piece = v, captured = 0, flag = "double" })
					end
				end
				for _, df in { -1, 1 } do
					local to = sqAt(file + df, rank + side)
					if to then
						local target = board[to]
						if target ~= 0 and (target > 0) ~= (side > 0) then
							addPawnMove(moves, from, to, v, target)
						elseif to == pos.ep then
							table.insert(moves, { from = from, to = to, piece = v, captured = -PAWN * side, flag = "ep" })
						end
					end
				end
			elseif kind == KNIGHT or kind == KING then
				for _, d in (if kind == KNIGHT then KNIGHT_STEPS else KING_STEPS) do
					local to = sqAt(file + d[1], rank + d[2])
					if to then
						local target = board[to]
						if target == 0 then
							if not capturesOnly then
								table.insert(moves, { from = from, to = to, piece = v, captured = 0 })
							end
						elseif (target > 0) ~= (side > 0) then
							table.insert(moves, { from = from, to = to, piece = v, captured = target })
						end
					end
				end
				if kind == KING and not capturesOnly then
					-- Castling: rights, empty squares, rook in place, and no attacked squares on the king's path.
					local home = if side == 1 then 4 else 60
					local kBit = if side == 1 then WK else BK
					local qBit = if side == 1 then WQ else BQ
					if from == home and not attacked(board, home, -side) then
						if bit32.btest(pos.castle, kBit) and board[home + 1] == 0 and board[home + 2] == 0
							and board[home + 3] == ROOK * side
							and not attacked(board, home + 1, -side) and not attacked(board, home + 2, -side)
						then
							table.insert(moves, { from = from, to = home + 2, piece = v, captured = 0, flag = "castleK" })
						end
						if bit32.btest(pos.castle, qBit) and board[home - 1] == 0 and board[home - 2] == 0
							and board[home - 3] == 0 and board[home - 4] == ROOK * side
							and not attacked(board, home - 1, -side) and not attacked(board, home - 2, -side)
						then
							table.insert(moves, { from = from, to = home - 2, piece = v, captured = 0, flag = "castleQ" })
						end
					end
				end
			else
				local dirs = if kind == BISHOP then DIAGONALS elseif kind == ROOK then STRAIGHTS else KING_STEPS
				for _, d in dirs do
					local f, r = file + d[1], rank + d[2]
					while f >= 0 and f <= 7 and r >= 0 and r <= 7 do
						local to = r * 8 + f
						local target = board[to]
						if target == 0 then
							if not capturesOnly then
								table.insert(moves, { from = from, to = to, piece = v, captured = 0 })
							end
						else
							if (target > 0) ~= (side > 0) then
								table.insert(moves, { from = from, to = to, piece = v, captured = target })
							end
							break
						end
						f += d[1]
						r += d[2]
					end
				end
			end
		end
	end
	return moves
end

-- Castling rights lost when a piece leaves or lands on these squares.
local CASTLE_MASK = { [0] = WQ, [4] = WK + WQ, [7] = WK, [56] = BQ, [60] = BK + BQ, [63] = BK }

type Undo = { castle: number, ep: number, halfmove: number }

local function makeMove(pos: Pos, m: Move): Undo
	local board = pos.board
	local undo = { castle = pos.castle, ep = pos.ep, halfmove = pos.halfmove }
	local side = pos.side
	board[m.from] = 0
	if m.flag == "ep" then
		board[m.to - 8 * side] = 0
	end
	board[m.to] = if m.promo then m.promo * side else m.piece
	if m.flag == "castleK" then
		board[m.to + 1] = 0
		board[m.to - 1] = ROOK * side
	elseif m.flag == "castleQ" then
		board[m.to - 2] = 0
		board[m.to + 1] = ROOK * side
	end
	if math.abs(m.piece) == KING then
		pos.kings[side] = m.to
	end
	local lost = (CASTLE_MASK[m.from] or 0) + (CASTLE_MASK[m.to] or 0)
	if lost > 0 then
		pos.castle = bit32.band(pos.castle, bit32.bnot(lost))
	end
	pos.ep = if m.flag == "double" then m.from + 8 * side else -1
	if math.abs(m.piece) == PAWN or m.captured ~= 0 then
		pos.halfmove = 0
	else
		pos.halfmove += 1
	end
	if side == -1 then
		pos.fullmove += 1
	end
	pos.side = -side
	return undo
end

local function unmakeMove(pos: Pos, m: Move, undo: Undo)
	local board = pos.board
	local side = -pos.side
	pos.side = side
	if side == -1 then
		pos.fullmove -= 1
	end
	pos.castle, pos.ep, pos.halfmove = undo.castle, undo.ep, undo.halfmove
	board[m.from] = m.piece
	if m.flag == "ep" then
		board[m.to] = 0
		board[m.to - 8 * side] = m.captured
	else
		board[m.to] = m.captured
	end
	if m.flag == "castleK" then
		board[m.to - 1] = 0
		board[m.to + 1] = ROOK * side
	elseif m.flag == "castleQ" then
		board[m.to + 1] = 0
		board[m.to - 2] = ROOK * side
	end
	if math.abs(m.piece) == KING then
		pos.kings[side] = m.from
	end
end

local function legalMoves(pos: Pos, capturesOnly: boolean?): { Move }
	local out = {}
	local side = pos.side
	for _, m in pseudoMoves(pos, capturesOnly) do
		local undo = makeMove(pos, m)
		if not attacked(pos.board, pos.kings[side], -side) then
			table.insert(out, m)
		end
		unmakeMove(pos, m, undo)
	end
	return out
end

Chess.legalMoves = legalMoves
Chess.makeMove = makeMove
Chess.unmakeMove = unmakeMove

function Chess.perft(pos: Pos, depth: number): number
	if depth == 0 then
		return 1
	end
	local moves = legalMoves(pos)
	if depth == 1 then
		return #moves
	end
	local total = 0
	for _, m in moves do
		local undo = makeMove(pos, m)
		total += Chess.perft(pos, depth - 1)
		unmakeMove(pos, m, undo)
	end
	return total
end

-- Draw helpers ----------------------------------------------------------------

local function insufficientMaterial(board): boolean
	local minors = {}
	for sq = 0, 63 do
		local kind = math.abs(board[sq])
		if kind == PAWN or kind == ROOK or kind == QUEEN then
			return false
		elseif kind == KNIGHT or kind == BISHOP then
			table.insert(minors, { kind = kind, sq = sq, color = if board[sq] > 0 then 1 else -1 })
		end
	end
	if #minors <= 1 then
		return true -- K v K, K+minor v K
	end
	-- Only bishops, all on the same square color: no mate is possible.
	local shade = nil
	for _, m in minors do
		if m.kind ~= BISHOP then
			return false
		end
		local s = (m.sq % 8 + m.sq // 8) % 2
		if shade == nil then
			shade = s
		elseif shade ~= s then
			return false
		end
	end
	return true
end

-- Repetition key: placement, side, castling and (only when capturable) the ep square.
local function positionKey(pos: Pos): string
	local fen = Chess.toFen(pos)
	local parts = string.split(fen, " ")
	local ep = "-"
	if pos.ep >= 0 then
		for _, m in legalMoves(pos, true) do
			if m.flag == "ep" then
				ep = parts[4]
				break
			end
		end
	end
	return table.concat({ parts[1], parts[2], parts[3], ep }, " ")
end

-- Notation --------------------------------------------------------------------

local function sanFor(pos: Pos, m: Move, all: { Move }): string
	local san
	if m.flag == "castleK" then
		san = "O-O"
	elseif m.flag == "castleQ" then
		san = "O-O-O"
	else
		local kind = math.abs(m.piece)
		local capture = m.captured ~= 0
		local to = Chess.squareName(m.to)
		if kind == PAWN then
			san = if capture then string.sub(FILES, m.from % 8 + 1, m.from % 8 + 1) .. "x" .. to else to
			if m.promo then
				san ..= "=" .. string.upper(PIECE_TO_LETTER[m.promo])
			end
		else
			local letter = string.upper(PIECE_TO_LETTER[kind])
			local sameFile, sameRank, ambiguous = false, false, false
			for _, other in all do
				if other ~= m and other.piece == m.piece and other.to == m.to and other.from ~= m.from then
					ambiguous = true
					if other.from % 8 == m.from % 8 then
						sameFile = true
					end
					if other.from // 8 == m.from // 8 then
						sameRank = true
					end
				end
			end
			local disambiguation = ""
			if ambiguous then
				local fromName = Chess.squareName(m.from)
				if not sameFile then
					disambiguation = string.sub(fromName, 1, 1)
				elseif not sameRank then
					disambiguation = string.sub(fromName, 2, 2)
				else
					disambiguation = fromName
				end
			end
			san = letter .. disambiguation .. (if capture then "x" else "") .. to
		end
	end
	local undo = makeMove(pos, m)
	if Chess.inCheck(pos) then
		san ..= if #legalMoves(pos) == 0 then "#" else "+"
	end
	unmakeMove(pos, m, undo)
	return san
end

-- Game module -------------------------------------------------------------------

local HILL = { [27] = true, [28] = true, [35] = true, [36] = true } -- d4, e4, d5, e5

local function seatToSide(seat: number): number
	return if seat == 1 then 1 else -1
end

function Chess.new(seatCount: number, options: any?, _rng: Random?)
	assert(seatCount == 2, "Chess needs exactly 2 seats")
	local pos = Chess.fromFen((options and options.fen) or START_FEN)
	local state = {
		pos = pos,
		history = {} :: { [string]: number },
		moveList = {} :: { string },
		lastMove = nil :: { from: string, to: string }?,
		captured = { [1] = {}, [2] = {} } :: { [number]: { number } }, -- piece types each seat has taken
		winner = nil :: number?,
		isDraw = false,
		reason = nil :: string?,
		botLevel = (options and options.botLevel) or "medium",
		kingOfTheHill = options ~= nil and options.rules ~= nil and options.rules.kingOfTheHill == true,
		-- Draw offers: made along with a move (offerDraw = true); the other player can
		-- accept on their turn ({ kind = "acceptDraw" }), and any move declines it.
		drawOffer = nil :: number?, -- the seat offering
		drawDeclined = nil :: number?, -- the seat whose offer was just turned down
		lastOffer = {} :: { [number]: number }, -- #moveList when each seat last offered
		-- Takebacks: what each ply changed, so the last one can be undone.
		undo = {} :: { { fen: string, lastMove: any, seat: number, took: boolean } },
		takebackAsk = nil :: number?, -- the seat asking to take its last move back
		takebackDeclined = nil :: number?,
		takebacks = { [1] = 0, [2] = 0 } :: { [number]: number }, -- granted per seat
	}
	state.history[positionKey(pos)] = 1
	return state
end

local function isOver(state): boolean
	return state.winner ~= nil or state.isDraw
end

local function sideToSeat(side: number): number
	return if side == 1 then 1 else 2
end

function Chess.getActiveSeats(state): { number }
	return if isOver(state) then {} else { sideToSeat(state.pos.side) }
end

local function toWire(m: Move): any
	return {
		from = Chess.squareName(m.from),
		to = Chess.squareName(m.to),
		promotion = if m.promo then PIECE_TO_LETTER[m.promo] else nil,
	}
end

-- A seat may offer a draw again only after a few moves each, so it can't be spammed.
local OFFER_GAP = 10 -- plies
function Chess.canOfferDraw(state, seat: number): boolean
	local last = state.lastOffer[seat]
	return not isOver(state) and seatToSide(seat) == state.pos.side and (last == nil or #state.moveList - last >= OFFER_GAP)
end

-- Takebacks: only the move you just made, a few times a game, one request at a time.
local TAKEBACKS = 3
function Chess.canAskTakeback(state, seat: number): boolean
	local last = state.undo[#state.undo]
	return not isOver(state)
		and last ~= nil
		and last.seat == seat
		and seatToSide(seat) ~= state.pos.side
		and state.takebackAsk == nil
		and state.takebackDeclined ~= seat
		and (state.takebacks[seat] or 0) < TAKEBACKS
end

local function takebackPendingFor(state, seat: number): boolean
	return state.takebackAsk ~= nil and state.takebackAsk ~= seat and not isOver(state) and seatToSide(seat) == state.pos.side
end

-- The seat that may ask for a takeback right now moves out of turn (see Match).
function Chess.getInterruptSeats(state): { number }
	for seat = 1, 2 do
		if Chess.canAskTakeback(state, seat) then
			return { seat }
		end
	end
	return {}
end

local function offerPendingFor(state, seat: number): boolean
	return state.drawOffer ~= nil and state.drawOffer ~= seat and not isOver(state) and seatToSide(seat) == state.pos.side
end

function Chess.getLegalMoves(state, seat: number): { any }
	if isOver(state) then
		return {}
	end
	if seatToSide(seat) ~= state.pos.side then
		return if Chess.canAskTakeback(state, seat) then { { kind = "takeback" } } else {}
	end
	local out = {}
	if takebackPendingFor(state, seat) then
		table.insert(out, { kind = "acceptTakeback" })
	end
	if offerPendingFor(state, seat) then
		table.insert(out, { kind = "acceptDraw" })
	end
	for _, m in legalMoves(state.pos) do
		table.insert(out, toWire(m))
	end
	return out
end

local function findMove(state, move: any): Move?
	if type(move) ~= "table" then
		return nil
	end
	local from, to = Chess.parseSquare(move.from), Chess.parseSquare(move.to)
	if not from or not to then
		return nil
	end
	local promo = if type(move.promotion) == "string" then LETTER_TO_PIECE[string.lower(move.promotion)] else nil
	for _, m in legalMoves(state.pos) do
		if m.from == from and m.to == to then
			if m.promo == nil then
				return m
			elseif m.promo == (promo or QUEEN) then
				return m
			end
		end
	end
	return nil
end

function Chess.validateMove(state, seat: number, move: any): (boolean, string?)
	if isOver(state) then
		return false, "The game is over"
	end
	if type(move) == "table" and move.kind == "takeback" then
		if not Chess.canAskTakeback(state, seat) then
			return false, "You can't take that back"
		end
		return true
	end
	if seatToSide(seat) ~= state.pos.side then
		return false, "It's not your turn"
	end
	if type(move) == "table" and move.kind == "acceptTakeback" then
		if not takebackPendingFor(state, seat) then
			return false, "No takeback was asked for"
		end
		return true
	end
	if type(move) == "table" and move.kind == "acceptDraw" then
		if not offerPendingFor(state, seat) then
			return false, "No draw was offered"
		end
		return true
	end
	if type(move) == "table" and move.offerDraw ~= nil then
		if type(move.offerDraw) ~= "boolean" then
			return false, "Bad move"
		end
		if move.offerDraw and not Chess.canOfferDraw(state, seat) then
			return false, "You offered a draw a moment ago"
		end
	end
	if not findMove(state, move) then
		return false, "That move isn't allowed"
	end
	return true
end

-- Undoes the last ply: back to the position before it, with its move, capture and
-- repetition count gone.
local function undoLast(state)
	local entry = table.remove(state.undo)
	if not entry then
		return
	end
	local key = positionKey(state.pos)
	state.history[key] = math.max(0, (state.history[key] or 1) - 1)
	state.pos = Chess.fromFen(entry.fen)
	table.remove(state.moveList)
	if entry.took then
		table.remove(state.captured[entry.seat])
	end
	state.lastMove = entry.lastMove
end

function Chess.applyMove(state, seat: number, move: any)
	if move.kind == "takeback" then
		state.takebackAsk = seat
		return
	elseif move.kind == "acceptTakeback" then
		local asker = state.takebackAsk :: number
		state.takebackAsk = nil
		state.takebackDeclined = nil
		state.takebacks[asker] = (state.takebacks[asker] or 0) + 1
		state.drawOffer = nil
		undoLast(state)
		state.tookBack = { seat = asker, count = #state.moveList }
		return
	end
	if move.kind == "acceptDraw" then
		state.isDraw = true
		state.reason = "Draw agreed"
		state.drawOffer = nil
		return
	end
	-- Moving on turns down an offer that was waiting for you.
	state.drawDeclined = if state.drawOffer and state.drawOffer ~= seat then state.drawOffer else nil
	state.drawOffer = nil
	-- ...and a takeback request. (Your own next move clears your declined flag.)
	state.takebackDeclined = if state.takebackAsk and state.takebackAsk ~= seat then state.takebackAsk else nil
	state.takebackAsk = nil
	state.tookBack = nil
	if move.offerDraw == true then
		state.drawOffer = seat
		state.lastOffer[seat] = #state.moveList
	end
	local pos = state.pos
	local m = findMove(state, move) :: Move
	table.insert(state.undo, { fen = Chess.toFen(pos), lastMove = state.lastMove, seat = seat, took = m.captured ~= 0 })
	table.insert(state.moveList, sanFor(pos, m, legalMoves(pos)))
	if m.captured ~= 0 then
		table.insert(state.captured[seat], math.abs(m.captured))
	end
	makeMove(pos, m)
	state.lastMove = { from = Chess.squareName(m.from), to = Chess.squareName(m.to) }

	local key = positionKey(pos)
	state.history[key] = (state.history[key] or 0) + 1

	-- pos.side has flipped, so the side that just moved is -pos.side.
	if state.kingOfTheHill and HILL[pos.kings[-pos.side]] then
		state.winner = seat
		state.reason = "King of the hill"
	elseif #legalMoves(pos) == 0 then
		if Chess.inCheck(pos) then
			state.winner = seat
			state.reason = "Checkmate"
		else
			state.isDraw = true
			state.reason = "Stalemate"
		end
	elseif state.history[key] >= 3 then
		state.isDraw = true
		state.reason = "Threefold repetition"
	elseif pos.halfmove >= 100 then
		state.isDraw = true
		state.reason = "50-move rule"
	elseif insufficientMaterial(pos.board) then
		state.isDraw = true
		state.reason = "Not enough pieces to checkmate"
	end
end

function Chess.getResult(state): GameModule.Result?
	if state.winner then
		return { winners = { state.winner }, isDraw = false, reason = state.reason }
	elseif state.isDraw then
		return { winners = {}, isDraw = true, reason = state.reason }
	end
	return nil
end

function Chess.getView(state, seat: number?): any
	local pos = state.pos
	local board = table.create(64, 0)
	for sq = 0, 63 do
		board[sq + 1] = pos.board[sq]
	end
	local view = {
		board = board, -- 1-based copy: board[sq + 1]
		turn = sideToSeat(pos.side),
		inCheck = Chess.inCheck(pos),
		kingSquare = Chess.squareName(pos.kings[pos.side]),
		lastMove = GameModule.copy(state.lastMove),
		moveList = table.clone(state.moveList),
		captured = GameModule.copy(state.captured),
		fen = Chess.toFen(pos),
		drawOffer = state.drawOffer,
		drawDeclined = state.drawDeclined,
		canOfferDraw = seat ~= nil and Chess.canOfferDraw(state, seat),
		takebackAsk = state.takebackAsk,
		takebackDeclined = state.takebackDeclined,
		tookBack = GameModule.copy(state.tookBack),
		canAskTakeback = seat ~= nil and Chess.canAskTakeback(state, seat),
		takebacksLeft = if seat then TAKEBACKS - (state.takebacks[seat] or 0) else 0,
	}
	if seat and not isOver(state) and seatToSide(seat) == pos.side then
		view.legalMoves = Chess.getLegalMoves(state, seat)
	end
	return view
end

-- Bot ---------------------------------------------------------------------------
-- Negamax with alpha-beta, quiescence search on captures, MVV-LVA move ordering,
-- iterative deepening under a time budget. Material + piece-square tables.

local VALUE = { 100, 320, 330, 500, 900, 0 }

-- Piece-square tables from White's point of view, written rank 8 first (index 1 = a8).
local PST = {
	[PAWN] = {
		0, 0, 0, 0, 0, 0, 0, 0,
		50, 50, 50, 50, 50, 50, 50, 50,
		10, 10, 20, 30, 30, 20, 10, 10,
		5, 5, 10, 25, 25, 10, 5, 5,
		0, 0, 0, 20, 20, 0, 0, 0,
		5, -5, -10, 0, 0, -10, -5, 5,
		5, 10, 10, -20, -20, 10, 10, 5,
		0, 0, 0, 0, 0, 0, 0, 0,
	},
	[KNIGHT] = {
		-50, -40, -30, -30, -30, -30, -40, -50,
		-40, -20, 0, 0, 0, 0, -20, -40,
		-30, 0, 10, 15, 15, 10, 0, -30,
		-30, 5, 15, 20, 20, 15, 5, -30,
		-30, 0, 15, 20, 20, 15, 0, -30,
		-30, 5, 10, 15, 15, 10, 5, -30,
		-40, -20, 0, 5, 5, 0, -20, -40,
		-50, -40, -30, -30, -30, -30, -40, -50,
	},
	[BISHOP] = {
		-20, -10, -10, -10, -10, -10, -10, -20,
		-10, 0, 0, 0, 0, 0, 0, -10,
		-10, 0, 5, 10, 10, 5, 0, -10,
		-10, 5, 5, 10, 10, 5, 5, -10,
		-10, 0, 10, 10, 10, 10, 0, -10,
		-10, 10, 10, 10, 10, 10, 10, -10,
		-10, 5, 0, 0, 0, 0, 5, -10,
		-20, -10, -10, -10, -10, -10, -10, -20,
	},
	[ROOK] = {
		0, 0, 0, 0, 0, 0, 0, 0,
		5, 10, 10, 10, 10, 10, 10, 5,
		-5, 0, 0, 0, 0, 0, 0, -5,
		-5, 0, 0, 0, 0, 0, 0, -5,
		-5, 0, 0, 0, 0, 0, 0, -5,
		-5, 0, 0, 0, 0, 0, 0, -5,
		-5, 0, 0, 0, 0, 0, 0, -5,
		0, 0, 0, 5, 5, 0, 0, 0,
	},
	[QUEEN] = {
		-20, -10, -10, -5, -5, -10, -10, -20,
		-10, 0, 0, 0, 0, 0, 0, -10,
		-10, 0, 5, 5, 5, 5, 0, -10,
		-5, 0, 5, 5, 5, 5, 0, -5,
		0, 0, 5, 5, 5, 5, 0, -5,
		-10, 5, 5, 5, 5, 5, 0, -10,
		-10, 0, 5, 0, 0, 0, 0, -10,
		-20, -10, -10, -5, -5, -10, -10, -20,
	},
	[KING] = {
		-30, -40, -40, -50, -50, -40, -40, -30,
		-30, -40, -40, -50, -50, -40, -40, -30,
		-30, -40, -40, -50, -50, -40, -40, -30,
		-30, -40, -40, -50, -50, -40, -40, -30,
		-20, -30, -30, -40, -40, -30, -30, -20,
		-10, -20, -20, -20, -20, -20, -20, -10,
		20, 20, 0, 0, 0, 0, 20, 20,
		20, 30, 10, 0, 0, 10, 30, 20,
	},
}

local function evaluate(pos: Pos): number
	local score = 0
	local board = pos.board
	for sq = 0, 63 do
		local v = board[sq]
		if v ~= 0 then
			local kind = math.abs(v)
			local file, rank = sq % 8, sq // 8
			if v > 0 then
				score += VALUE[kind] + PST[kind][(7 - rank) * 8 + file + 1]
			else
				score -= VALUE[kind] + PST[kind][rank * 8 + file + 1]
			end
		end
	end
	return score * pos.side
end

local function orderMoves(moves: { Move }, first: Move?)
	local function key(m: Move): number
		if first and m.from == first.from and m.to == first.to and m.promo == first.promo then
			return 100000
		end
		local k = 0
		if m.captured ~= 0 then
			k += 10 * VALUE[math.abs(m.captured)] - VALUE[math.abs(m.piece)] + 1000
		end
		if m.promo then
			k += VALUE[m.promo]
		end
		return k
	end
	table.sort(moves, function(a, b)
		return key(a) > key(b)
	end)
end

local MATE = 100000

type Search = { nodes: number, deadline: number, outOfTime: boolean }

local function quiesce(s: Search, pos: Pos, alpha: number, beta: number, depthLeft: number): number
	s.nodes += 1
	if s.nodes % 256 == 0 and os.clock() > s.deadline then
		s.outOfTime = true
	end
	local standPat = evaluate(pos)
	if standPat >= beta then
		return beta
	end
	if standPat > alpha then
		alpha = standPat
	end
	if depthLeft <= 0 or s.outOfTime then
		return alpha
	end
	local moves = legalMoves(pos, true)
	orderMoves(moves)
	for _, m in moves do
		local undo = makeMove(pos, m)
		local score = -quiesce(s, pos, -beta, -alpha, depthLeft - 1)
		unmakeMove(pos, m, undo)
		if score >= beta then
			return beta
		end
		if score > alpha then
			alpha = score
		end
	end
	return alpha
end

local function search(s: Search, pos: Pos, depth: number, alpha: number, beta: number, ply: number): number
	s.nodes += 1
	if s.nodes % 256 == 0 and os.clock() > s.deadline then
		s.outOfTime = true
	end
	if s.outOfTime then
		return 0
	end
	if pos.halfmove >= 100 then
		return 0
	end
	local moves = legalMoves(pos)
	if #moves == 0 then
		return if Chess.inCheck(pos) then -MATE + ply else 0
	end
	if depth <= 0 then
		return quiesce(s, pos, alpha, beta, 4)
	end
	orderMoves(moves)
	for _, m in moves do
		local undo = makeMove(pos, m)
		local score = -search(s, pos, depth - 1, -beta, -alpha, ply + 1)
		unmakeMove(pos, m, undo)
		if score >= beta then
			return beta
		end
		if score > alpha then
			alpha = score
		end
	end
	return alpha
end

-- seconds caps the search: it runs on the server in one go, so every table on the server
-- waits while a bot thinks. Keep it well under a second.
local LEVELS = {
	easy = { depth = 1, seconds = 0.08, slack = 120 },
	medium = { depth = 3, seconds = 0.25, slack = 10 },
	hard = { depth = 6, seconds = 0.45, slack = 0 },
}

-- Scores every legal move for the side to move, best first.
-- With exact = false only the best move's score is exact (others are just "worse"),
-- which is much faster. Easy bots need exact scores to pick a "close enough" move.
function Chess.rankMoves(pos: Pos, maxDepth: number, seconds: number, exact: boolean?): { { move: Move, score: number } }
	local moves = legalMoves(pos)
	local s: Search = { nodes = 0, deadline = os.clock() + seconds, outOfTime = false }
	local ranked: { { move: Move, score: number } } = {}
	for _, m in moves do
		table.insert(ranked, { move = m, score = 0 })
	end
	local bestFirst: Move? = nil
	for depth = 1, maxDepth do
		orderMoves(moves, bestFirst)
		local current = {}
		local alpha = -MATE - 1
		for _, m in moves do
			local undo = makeMove(pos, m)
			local score = -search(s, pos, depth - 1, -MATE - 1, -alpha, 1)
			unmakeMove(pos, m, undo)
			if not exact then
				if score > alpha then
					alpha = score
				elseif #current > 0 then
					score = alpha - 1 -- failed low: worse than the best so far
				end
			end
			if s.outOfTime then
				break
			end
			table.insert(current, { move = m, score = score })
		end
		if s.outOfTime and depth > 1 then
			break
		end
		if s.outOfTime and #current > 0 then
			-- Not even depth 1 finished: rank the moves we did look at rather than
			-- falling back to all-equal scores (a random move).
			table.sort(current, function(a, b)
				return a.score > b.score
			end)
			ranked = current
			break
		end
		if #current == #moves then
			table.sort(current, function(a, b)
				return a.score > b.score
			end)
			ranked = current
			bestFirst = current[1].move
			if current[1].score >= MATE - 100 then
				break -- found a forced mate
			end
		end
		if s.outOfTime then
			break
		end
	end
	return ranked
end

local TAKEBACK_YES = { easy = 1, medium = 0.75, hard = 0.35 }

function Chess.chooseBotMove(state, seat: number, rng: Random): any?
	if isOver(state) or seatToSide(seat) ~= state.pos.side then
		return nil
	end
	-- A takeback request: friendly bots say yes, sharp ones less often.
	if takebackPendingFor(state, seat) and rng:NextNumber() < (TAKEBACK_YES[state.botLevel] or 0.75) then
		return { kind = "acceptTakeback" }
	end
	-- A draw offer: take it when losing, or in a long, level game.
	if offerPendingFor(state, seat) then
		local score = evaluate(state.pos)
		if score < -150 or (#state.moveList >= 80 and math.abs(score) < 40) then
			return { kind = "acceptDraw" }
		end
	end
	local level = LEVELS[state.botLevel] or LEVELS.medium
	local ranked = Chess.rankMoves(state.pos, level.depth, level.seconds, level.slack > 0)
	if #ranked == 0 then
		return nil
	end
	local best = ranked[1].score
	-- When ahead, don't walk into a repeated position (a draw by repetition throws the
	-- win away). Only the best score is exact, so re-rank shallowly with exact scores and
	-- take the best new position that isn't much worse.
	local function repeats(m: Move): boolean
		local undo = makeMove(state.pos, m)
		local seen = state.history[positionKey(state.pos)] or 0
		unmakeMove(state.pos, m, undo)
		return seen > 0
	end
	if best > 50 and best < MATE - 100 and repeats(ranked[1].move) then
		local alt = Chess.rankMoves(state.pos, 2, 0.1, true)
		local altBest = if alt[1] then alt[1].score else 0
		for _, entry in alt do
			if entry.score < altBest - 100 then
				break
			end
			if not repeats(entry.move) then
				return toWire(entry.move)
			end
		end
	end
	local pool = {}
	for _, entry in ranked do
		if entry.score >= best - level.slack then
			table.insert(pool, entry.move)
		end
	end
	return toWire(pool[rng:NextInteger(1, #pool)])
end

-- Stats for the profile (see shared/StatsCatalog.luau).
function Chess.getMatchStats(state): { [number]: { [string]: number } }
	local out = {}
	for seat = 1, 2 do
		out[seat] = {
			captures = #state.captured[seat],
			checkmates = if state.winner == seat and state.reason == "Checkmate" then 1 else 0,
		}
	end
	return out
end

-- A natural pause before a bot moves: quick when forced, longer for a real choice.
function Chess.getBotDelay(state, seat: number, rng: Random): number
	return BotThink.delay(rng, #Chess.getLegalMoves(state, seat), { base = 0.8, perDoubling = 0.2, jitter = 0.8, ponder = 0.15, max = 3.0 })
end

return Chess
