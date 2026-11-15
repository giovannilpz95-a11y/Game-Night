--[[
	Chess Game Review, like chess.com's Game Review and Lichess's computer analysis.
	Pure Luau (the client runs it after a game, one move per frame).

	For every move it finds the engine's best move in the position before it, scores the
	position after it, and labels the move by how much winning chance it gave away:

	  Book        a move that stays on a named opening line (Lichess's opening list)
	  Forced      the only legal move
	  Best        the engine's top move (or as good as it)
	  Excellent   lost almost nothing (under 2% winning chance)
	  Good        under 5%
	  Inaccuracy  under 10%
	  Mistake     under 20%
	  Blunder     20% or more

	Winning chance and accuracy use the published Lichess formulas:
	  win% = 50 + 50 * (2 / (1 + exp(-0.00368208 * cp)) - 1)
	  move accuracy = 103.1668 * exp(-0.04354 * (win% before - win% after)) - 3.1669
	A side's game accuracy is Lichess's: the average of a volatility-weighted mean and the
	harmonic mean of its move accuracies (evals capped at +-10 pawns).

	Usage:
	  local review = ChessReview.new(startFen, plies, { seconds = 0.25, depth = 5 })
	  while not review:step() do task.wait() end   -- one move per call
	  -- or { depth = 6, nodes = 12000, tick = function() coroutine.yield() end } inside a
	  -- coroutine, resumed once a frame, for a deeper review that never hitches
	  review.moves[i]  -> { san, label, symbol, bestSan, bestFrom, bestTo, evalAfter, side }
	  review.accuracy  -> { [1] = white%, [2] = black% }
	  review.counts    -> { [1] = { Best = 3, ... }, [2] = { ... } }

	plies is a list of { fen = <position after the move>, from, to } (the view's `past`).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Chess = require(ReplicatedStorage.Shared.Games.Chess)

local ChessReview = {}

ChessReview.LABELS = { "Book", "Forced", "Best", "Excellent", "Good", "Inaccuracy", "Mistake", "Blunder" }
-- What chess.com and Lichess put next to a move.
ChessReview.SYMBOLS = {
	Book = "📖",
	Forced = "→",
	Best = "★",
	Excellent = "!",
	Good = "✓",
	Inaccuracy = "?!",
	Mistake = "?",
	Blunder = "??",
}
ChessReview.COLORS = {
	Book = Color3.fromRGB(168, 136, 101),
	Forced = Color3.fromRGB(150, 150, 150),
	Best = Color3.fromRGB(129, 182, 76),
	Excellent = Color3.fromRGB(96, 168, 70),
	Good = Color3.fromRGB(119, 145, 92),
	Inaccuracy = Color3.fromRGB(247, 198, 49),
	Mistake = Color3.fromRGB(255, 167, 89),
	Blunder = Color3.fromRGB(250, 65, 45),
}

-- Win-chance drop (0..1) at or under which a move gets each label.
local THRESHOLDS = {
	{ "Excellent", 0.02 },
	{ "Good", 0.05 },
	{ "Inaccuracy", 0.10 },
	{ "Mistake", 0.20 },
}

local CP_CAP = 1000 -- evals are capped at +-10 pawns (mates too), as Lichess does

-- Opening book: every position on the 3,800+ named lines of lichess-org/chess-openings
-- (CC0), built by tools/build-chess-openings.py. Positions are matched by piece placement
-- and side to move, so transpositions (1.Nf3 d5 2.d4) find the same opening as the main
-- move order. A move is "Book" while every position so far is on a book line.
local NAMES = require(ReplicatedStorage.Shared.ChessData.ChessOpeningNames)
local BOOK_DATA = require(ReplicatedStorage.Shared.ChessData.ChessOpeningBook)

local DIGITS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local DIGIT_VALUE = {}
for i = 1, #DIGITS do
	DIGIT_VALUE[string.byte(DIGITS, i)] = i - 1
end

local function fnv1a(text: string, reverse: boolean): number
	local h = 2166136261
	local n = #text
	for i = 1, n do
		local byte = string.byte(text, if reverse then n - i + 1 else i)
		h = bit32.bxor(h, byte)
		-- h * 16777619 mod 2^32, split so the product stays exact in a double.
		h = (bit32.lshift(h, 24) + h * 403) % 4294967296
	end
	return h
end

local function b64(value: number, width: number): string
	local out = table.create(width, "")
	for i = width, 1, -1 do
		local d = value % 64
		out[i] = string.sub(DIGITS, d + 1, d + 1)
		value = value // 64
	end
	return table.concat(out)
end

local book: { [string]: number }? = nil -- key -> name index (0 = on a line, no name)

local function loadBook(): { [string]: number }
	if book then
		return book
	end
	local out = {}
	for i = 1, #BOOK_DATA, 14 do
		local a, b = string.byte(BOOK_DATA, i + 12, i + 13)
		out[string.sub(BOOK_DATA, i, i + 11)] = DIGIT_VALUE[a] * 64 + DIGIT_VALUE[b]
	end
	book = out
	return out
end

-- The book key of a position: placement + side to move ("w"/"b"), hashed.
function ChessReview.bookKey(fen: string): string
	local placement, side = string.match(fen, "^(%S+)%s+(%S)")
	local text = `{placement or fen} {side or "w"}`
	return b64(fnv1a(text, false), 6) .. b64(fnv1a(text, true), 6)
end

-- Is this position on a book line, and the opening's name if a line ends here.
function ChessReview.bookInfo(fen: string): (boolean, string?)
	local index = loadBook()[ChessReview.bookKey(fen)]
	if index == nil then
		return false, nil
	end
	return true, if index > 0 then NAMES[index] else nil
end

-- The opening name for a list of positions (FEN after each move), plus how many of the
-- moves are still on a book line. The name is the last named book position reached.
function ChessReview.openingFromFens(fens: { string }): (string?, number)
	local name, bookPlies = nil, 0
	for i, fen in fens do
		local inBook, here = ChessReview.bookInfo(fen)
		if not inBook then
			break
		end
		bookPlies = i
		if here then
			name = here
		end
	end
	return name, bookPlies
end

local function strip(san: string): string
	return (string.gsub(san, "[+#]", ""))
end

-- The same from moves in standard notation, played from the normal start (or startFen).
function ChessReview.opening(sans: { string }, startFen: string?): (string?, number)
	local pos = Chess.fromFen(startFen or Chess.START_FEN)
	local fens = {}
	for _, san in sans do
		local found = nil
		local wanted = strip(san)
		for _, m in Chess.legalMoves(pos) do
			if strip(Chess.san(pos, m)) == wanted then
				found = m
				break
			end
		end
		if not found then
			break
		end
		Chess.makeMove(pos, found)
		table.insert(fens, Chess.toFen(pos))
		if #fens >= 40 then
			break -- no book line is longer than this
		end
	end
	return ChessReview.openingFromFens(fens)
end

-- Centipawns for the side to move -> that side's winning chance, 0..100.
function ChessReview.winPercent(cp: number): number
	cp = math.clamp(cp, -CP_CAP, CP_CAP)
	return 50 + 50 * (2 / (1 + math.exp(-0.00368208 * cp)) - 1)
end

function ChessReview.moveAccuracy(winBefore: number, winAfter: number): number
	local drop = math.max(0, winBefore - winAfter)
	return math.clamp(103.1668 * math.exp(-0.04354 * drop) - 3.1669, 0, 100)
end

function ChessReview.classify(winDrop: number, isBest: boolean): string
	if isBest then
		return "Best"
	end
	for _, t in THRESHOLDS do
		if winDrop <= t[2] then
			return t[1]
		end
	end
	return "Blunder"
end

-- The engine move matching a played move (from/to and the position it led to).
local function playedMove(pos, from: string, to: string, fenAfter: string): any?
	local placement = string.match(fenAfter, "^%S+")
	local fallback = nil
	for _, m in Chess.legalMoves(pos) do
		if Chess.squareName(m.from) == from and Chess.squareName(m.to) == to then
			fallback = fallback or m
			local undo = Chess.makeMove(pos, m)
			local same = string.match(Chess.toFen(pos), "^%S+") == placement
			Chess.unmakeMove(pos, m, undo)
			if same then
				return m
			end
		end
	end
	return fallback
end

-- Best score (centipawns, side to move) and best move in pos. Ended positions score
-- as mate or 0.
local function bestIn(pos, depth: number, seconds: number, opts: any?): (number, any?)
	local moves = Chess.legalMoves(pos)
	if #moves == 0 then
		return (if Chess.inCheck(pos) then -Chess.MATE else 0), nil
	end
	local ranked = Chess.rankMoves(pos, depth, seconds, false, opts)
	if not ranked[1] then
		return 0, moves[1]
	end
	return ranked[1].score, ranked[1].move
end

function ChessReview.new(startFen: string, plies: { any }, opts: any?)
	local self = {
		startFen = startFen,
		plies = plies,
		depth = (opts and opts.depth) or 5,
		seconds = (opts and opts.seconds) or 0.25,
		-- Optional: a node budget per position instead of seconds, and a tick the search
		-- calls every few hundred nodes (run step() in a coroutine and yield there to
		-- spread a deep review over many frames).
		searchOpts = if opts and (opts.nodes or opts.tick) then { nodes = opts.nodes, tick = opts.tick } else nil,
		moves = {},
		done = false,
		progress = 0, -- moves reviewed
		accuracy = { 0, 0 },
		counts = { {}, {} },
		opening = nil :: string?,
		bookPlies = 0,
	}
	-- Positions before each move: before[1] = start, before[i + 1] = after move i.
	self.before = { startFen }
	for _, p in plies do
		table.insert(self.before, p.fen)
	end
	-- Standard notation for every move, for the opening book.
	local sans = {}
	for i, p in plies do
		local pos = Chess.fromFen(self.before[i])
		local m = playedMove(pos, p.from, p.to, p.fen)
		sans[i] = if m then Chess.san(pos, m) else `{p.from}-{p.to}`
	end
	self.sans = sans
	local fens = {}
	for _, p in plies do
		table.insert(fens, p.fen)
	end
	self.opening, self.bookPlies = ChessReview.openingFromFens(fens)
	-- Score of the position before move i (side to move there); filled one ahead.
	self.scores = {}
	self.best = {}
	return setmetatable(self, { __index = ChessReview })
end

-- Reviews the next move. Returns true once every move is done.
function ChessReview.step(self): boolean
	if self.done then
		return true
	end
	local i = self.progress + 1
	if i > #self.plies then
		self:finish()
		return true
	end
	local function scoreAt(k: number)
		if self.scores[k] == nil then
			local pos = Chess.fromFen(self.before[k])
			local score, move = bestIn(pos, self.depth, self.seconds, self.searchOpts)
			self.scores[k] = score
			self.best[k] = if move then { move = move, san = Chess.san(pos, move) } else false
		end
		return self.scores[k]
	end
	local before = scoreAt(i)
	local after = -scoreAt(i + 1) -- the next position is scored for the other side
	local pos = Chess.fromFen(self.before[i])
	local side = if pos.side == 1 then 1 else 2
	local legal = Chess.legalMoves(pos)
	local p = self.plies[i]
	local m = playedMove(pos, p.from, p.to, p.fen)
	local best = self.best[i]
	local isBest = best and m ~= nil and best.move.from == m.from and best.move.to == m.to and best.move.promo == m.promo
	if isBest then
		after = math.max(after, before) -- same move: don't blame search noise on it
	end
	local winBefore = ChessReview.winPercent(before)
	local winAfter = ChessReview.winPercent(after)
	local label
	if #legal == 1 then
		label = "Forced"
	elseif i <= self.bookPlies then
		label = "Book"
	else
		label = ChessReview.classify((winBefore - winAfter) / 100, isBest == true)
	end
	local accuracy = if label == "Book" or label == "Forced" then 100 else ChessReview.moveAccuracy(winBefore, winAfter)
	local whiteEval = if side == 1 then after else -after
	-- Book and forced moves don't get a "better was..." arrow: there's nothing to improve.
	local suggest = best and not isBest and label ~= "Book" and label ~= "Forced"
	self.moves[i] = {
		san = self.sans[i],
		label = label,
		symbol = ChessReview.SYMBOLS[label],
		side = side,
		accuracy = accuracy,
		bestSan = if suggest then best.san else nil,
		bestFrom = if suggest then Chess.squareName(best.move.from) else nil,
		bestTo = if suggest then Chess.squareName(best.move.to) else nil,
		evalAfter = math.clamp(whiteEval, -CP_CAP, CP_CAP), -- centipawns for White
		mateAfter = math.abs(after) >= Chess.MATE - 500,
		-- Moves to mate (positive = White mates), for an "M3" on the eval bar.
		mateIn = if math.abs(after) >= Chess.MATE - 500
			then (if whiteEval > 0 then 1 else -1) * math.max(1, math.ceil((Chess.MATE - math.abs(after)) / 2))
			else nil,
		winWhite = ChessReview.winPercent(whiteEval), -- White's winning chance after the move
	}
	self.progress = i
	if i == #self.plies then
		self:finish()
		return true
	end
	return false
end

local function stdDev(xs: { number }): number
	local mean = 0
	for _, x in xs do
		mean += x
	end
	mean /= #xs
	local var = 0
	for _, x in xs do
		var += (x - mean) ^ 2
	end
	return math.sqrt(var / #xs)
end

-- Lichess's game accuracy: each move is weighted by how volatile the game was around it
-- (the standard deviation of White's winning chances over a sliding window, 0.5..12),
-- and the side's score is the average of that weighted mean and the harmonic mean.
-- winsWhite[1] is the start, winsWhite[i + 1] after move i.
function ChessReview.gameAccuracy(winsWhite: { number }, accuracies: { number }, sides: { number }): { number }
	local count = #accuracies
	local out = { 100, 100 }
	if count == 0 then
		return out
	end
	local windowSize = math.clamp(count // 10, 2, 8)
	local windows = {}
	local firstWindow = table.move(winsWhite, 1, math.min(windowSize, #winsWhite), 1, {})
	for _ = 1, math.min(windowSize, #winsWhite) - 2 do
		table.insert(windows, firstWindow)
	end
	for start = 1, #winsWhite - windowSize + 1 do
		table.insert(windows, table.move(winsWhite, start, start + windowSize - 1, 1, {}))
	end
	for s = 1, 2 do
		local weighted, weights, harmonic, n = 0, 0, 0, 0
		for i = 1, count do
			if sides[i] == s then
				local window = windows[i]
				local weight = if window then math.clamp(stdDev(window), 0.5, 12) else 0.5
				weighted += accuracies[i] * weight
				weights += weight
				harmonic += 1 / math.max(1, accuracies[i])
				n += 1
			end
		end
		if n > 0 then
			local value = (weighted / weights + n / harmonic) / 2
			out[s] = math.floor(value * 10 + 0.5) / 10
		end
	end
	return out
end

function ChessReview.finish(self)
	self.counts = { {}, {} }
	local startScore = self.scores[1] or 0
	local startWhite = if Chess.fromFen(self.startFen).side == 1 then startScore else -startScore
	local winsWhite = { ChessReview.winPercent(startWhite) }
	local accuracies, sides = {}, {}
	for i, mv in self.moves do
		self.counts[mv.side][mv.label] = (self.counts[mv.side][mv.label] or 0) + 1
		winsWhite[i + 1] = mv.winWhite
		accuracies[i] = mv.accuracy
		sides[i] = mv.side
	end
	self.accuracy = ChessReview.gameAccuracy(winsWhite, accuracies, sides)
	self.done = true
end

-- Runs the whole review at once (tests, small games).
function ChessReview.run(startFen: string, plies: { any }, opts: any?)
	local review = ChessReview.new(startFen, plies, opts)
	while not review:step() do
	end
	return review
end

-- A one-line coach note for a reviewed move, like "Qh5?? is a blunder. Best was Nf3."
function ChessReview.describe(mv: any): string
	local text = ({
		Book = "is a book move",
		Forced = "was the only move",
		Best = "is the best move",
		Excellent = "is excellent",
		Good = "is good",
		Inaccuracy = "is an inaccuracy",
		Mistake = "is a mistake",
		Blunder = "is a blunder",
	})[mv.label] or ""
	local line = `{mv.san} {text}.`
	if mv.bestSan and (mv.label == "Inaccuracy" or mv.label == "Mistake" or mv.label == "Blunder" or mv.label == "Good" or mv.label == "Excellent") then
		line ..= ` Best was {mv.bestSan}.`
	end
	return line
end

return ChessReview
