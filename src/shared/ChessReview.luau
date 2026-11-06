--[[
	Chess Game Review, like chess.com's Game Review and Lichess's computer analysis.
	Pure Luau (the client runs it after a game, one move per frame).

	For every move it finds the engine's best move in the position before it, scores the
	position after it, and labels the move by how much winning chance it gave away:

	  Book        an opening move from the book below
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
	A side's accuracy is the average over its moves.

	Usage:
	  local review = ChessReview.new(startFen, plies, { seconds = 0.25, depth = 5 })
	  while not review:step() do task.wait() end   -- one move per call
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

local CP_CAP = 1500 -- mates count as +-15 pawns for winning chances

-- Opening book: moves in standard notation without + or #. The longest match names the
-- opening; a move is "Book" while the game is still on one of these lines.
ChessReview.OPENINGS = {
	{ "e4", "King's Pawn Opening" },
	{ "d4", "Queen's Pawn Opening" },
	{ "c4", "English Opening" },
	{ "Nf3", "Zukertort Opening" },
	{ "g3", "Hungarian Opening" },
	{ "b3", "Nimzo-Larsen Attack" },
	{ "f4", "Bird's Opening" },
	{ "e4 e5", "Open Game" },
	{ "e4 e5 Nf3", "King's Knight Opening" },
	{ "e4 e5 Nf3 Nc6", "King's Knight Opening" },
	{ "e4 e5 Nf3 Nc6 Bb5", "Ruy Lopez" },
	{ "e4 e5 Nf3 Nc6 Bb5 a6", "Ruy Lopez: Morphy Defense" },
	{ "e4 e5 Nf3 Nc6 Bb5 Nf6", "Ruy Lopez: Berlin Defense" },
	{ "e4 e5 Nf3 Nc6 Bc4", "Italian Game" },
	{ "e4 e5 Nf3 Nc6 Bc4 Bc5", "Italian Game: Giuoco Piano" },
	{ "e4 e5 Nf3 Nc6 Bc4 Nf6", "Italian Game: Two Knights Defense" },
	{ "e4 e5 Nf3 Nc6 Bc4 Bc5 b4", "Evans Gambit" },
	{ "e4 e5 Nf3 Nc6 Bc4 Nf6 Ng5", "Two Knights: Fried Liver line" },
	{ "e4 e5 Nf3 Nc6 d4", "Scotch Game" },
	{ "e4 e5 Nf3 Nc6 Nc3", "Three Knights Game" },
	{ "e4 e5 Nf3 Nc6 Nc3 Nf6", "Four Knights Game" },
	{ "e4 e5 Nf3 Nf6", "Petrov's Defense" },
	{ "e4 e5 Nf3 d6", "Philidor Defense" },
	{ "e4 e5 Nf3 f5", "Latvian Gambit" },
	{ "e4 e5 f4", "King's Gambit" },
	{ "e4 e5 f4 exf4", "King's Gambit Accepted" },
	{ "e4 e5 Nc3", "Vienna Game" },
	{ "e4 e5 Bc4", "Bishop's Opening" },
	{ "e4 e5 Qh5", "Wayward Queen Attack" },
	{ "e4 e5 d4 exd4 c3", "Danish Gambit" },
	{ "e4 c5", "Sicilian Defense" },
	{ "e4 c5 Nf3 d6", "Sicilian Defense" },
	{ "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6", "Sicilian: Najdorf Variation" },
	{ "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6", "Sicilian: Dragon Variation" },
	{ "e4 c5 Nf3 Nc6", "Sicilian Defense: Old Sicilian" },
	{ "e4 c5 Nf3 e6", "Sicilian Defense: French Variation" },
	{ "e4 c5 Nc3", "Sicilian: Closed" },
	{ "e4 c5 c3", "Sicilian: Alapin Variation" },
	{ "e4 c5 d4 cxd4 c3", "Smith-Morra Gambit" },
	{ "e4 e6", "French Defense" },
	{ "e4 e6 d4 d5", "French Defense" },
	{ "e4 e6 d4 d5 e5", "French Defense: Advance Variation" },
	{ "e4 e6 d4 d5 exd5", "French Defense: Exchange Variation" },
	{ "e4 e6 d4 d5 Nc3", "French Defense: Paulsen Variation" },
	{ "e4 c6", "Caro-Kann Defense" },
	{ "e4 c6 d4 d5", "Caro-Kann Defense" },
	{ "e4 c6 d4 d5 e5", "Caro-Kann: Advance Variation" },
	{ "e4 d5", "Scandinavian Defense" },
	{ "e4 d5 exd5 Qxd5", "Scandinavian: Main Line" },
	{ "e4 d6", "Pirc Defense" },
	{ "e4 g6", "Modern Defense" },
	{ "e4 Nf6", "Alekhine's Defense" },
	{ "e4 Nc6", "Nimzowitsch Defense" },
	{ "d4 d5", "Closed Game" },
	{ "d4 d5 c4", "Queen's Gambit" },
	{ "d4 d5 c4 dxc4", "Queen's Gambit Accepted" },
	{ "d4 d5 c4 e6", "Queen's Gambit Declined" },
	{ "d4 d5 c4 c6", "Slav Defense" },
	{ "d4 d5 c4 e5", "Albin Countergambit" },
	{ "d4 d5 Bf4", "London System" },
	{ "d4 d5 Nf3 Nf6 Bf4", "London System" },
	{ "d4 Nf6 Bf4", "London System" },
	{ "d4 d5 e3", "Colle System" },
	{ "d4 Nf6", "Indian Defense" },
	{ "d4 Nf6 c4 g6", "King's Indian Defense" },
	{ "d4 Nf6 c4 g6 Nc3 d5", "Grünfeld Defense" },
	{ "d4 Nf6 c4 e6", "Indian Defense: East Indian" },
	{ "d4 Nf6 c4 e6 Nc3 Bb4", "Nimzo-Indian Defense" },
	{ "d4 Nf6 c4 e6 Nf3 b6", "Queen's Indian Defense" },
	{ "d4 Nf6 c4 c5", "Benoni Defense" },
	{ "d4 Nf6 c4 c5 d5 b5", "Benko Gambit" },
	{ "d4 Nf6 Bg5", "Trompowsky Attack" },
	{ "d4 f5", "Dutch Defense" },
	{ "d4 e5", "Englund Gambit" },
	{ "c4 e5", "English Opening: Reversed Sicilian" },
	{ "c4 c5", "English Opening: Symmetrical" },
	{ "c4 Nf6", "English Opening: Anglo-Indian" },
	{ "Nf3 d5 g3", "King's Indian Attack" },
	{ "Nf3 d5 c4", "Réti Opening" },
}

local BOOK: { [string]: string } = {}
for _, entry in ChessReview.OPENINGS do
	BOOK[entry[1]] = entry[2]
end

local function strip(san: string): string
	return (string.gsub(san, "[+#]", ""))
end

-- The opening name for a list of moves (standard notation), or nil, plus how many of the
-- moves are still on a book line.
function ChessReview.opening(sans: { string }): (string?, number)
	local name, bookPlies = nil, 0
	local line = ""
	for i, san in sans do
		line = if i == 1 then strip(san) else line .. " " .. strip(san)
		local hit = BOOK[line]
		local onLine = hit ~= nil
		if not onLine then
			-- Still a prefix of some longer book line?
			for key in BOOK do
				if string.sub(key, 1, #line + 1) == line .. " " then
					onLine = true
					break
				end
			end
		end
		if not onLine then
			break
		end
		bookPlies = i
		if hit then
			name = hit
		end
	end
	return name, bookPlies
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
local function bestIn(pos, depth: number, seconds: number): (number, any?)
	local moves = Chess.legalMoves(pos)
	if #moves == 0 then
		return (if Chess.inCheck(pos) then -Chess.MATE else 0), nil
	end
	local ranked = Chess.rankMoves(pos, depth, seconds, false)
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
	self.opening, self.bookPlies = ChessReview.opening(sans)
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
			local score, move = bestIn(pos, self.depth, self.seconds)
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
	self.moves[i] = {
		san = self.sans[i],
		label = label,
		symbol = ChessReview.SYMBOLS[label],
		side = side,
		accuracy = accuracy,
		bestSan = if best and not isBest then best.san else nil,
		bestFrom = if best and not isBest then Chess.squareName(best.move.from) else nil,
		bestTo = if best and not isBest then Chess.squareName(best.move.to) else nil,
		evalAfter = math.clamp(whiteEval, -CP_CAP, CP_CAP), -- centipawns for White
		mateAfter = math.abs(after) >= Chess.MATE - 500,
	}
	self.progress = i
	if i == #self.plies then
		self:finish()
		return true
	end
	return false
end

function ChessReview.finish(self)
	local sums, n = { 0, 0 }, { 0, 0 }
	self.counts = { {}, {} }
	for _, mv in self.moves do
		sums[mv.side] += mv.accuracy
		n[mv.side] += 1
		self.counts[mv.side][mv.label] = (self.counts[mv.side][mv.label] or 0) + 1
	end
	for s = 1, 2 do
		self.accuracy[s] = if n[s] > 0 then math.floor(sums[s] / n[s] * 10 + 0.5) / 10 else 100
	end
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
