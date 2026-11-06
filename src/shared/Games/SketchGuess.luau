-- Sketch & Guess: one player draws a secret word, everyone else races to guess it.
--
-- Turn flow (each a timed phase, see getTimer):
--   choose  the drawer picks 1 of 3 words (easy / medium / hard). Time out = first word.
--   draw    the drawer draws; guessers type guesses. Every DRAW_SEGMENT seconds a letter
--           of the hint is revealed. Ends early when everyone has guessed.
--   reveal  the word is shown to all for a few seconds, then the next drawer goes.
--   gallery after the last drawing: the most liked drawings of the game, for a few
--           seconds (skipped when there are none), then the game ends.
-- Seats that start as players take drawing turns. Bots join the rotation only when there
-- are fewer than three players, drawing simple doodles shape by shape (Data/SketchDoodles),
-- so someone alone with bots still gets drawings to guess. Each drawer draws ROUNDS times
-- (more when there are only one or two drawers).
-- House rules (options.rules): rounds = 1..3, drawSeconds = 60 | 80 | 120,
-- tools = "all" (brush and shapes) | "shapes" (lines, boxes and ovals only, no brush),
-- wordChoices = 1 | 3 | 5 (words the drawer picks from), hints = "none" | "normal" | "lots".
-- options.customWords: a Party Host's word list (already filtered by the server). When
-- set, every choice comes from it instead of our list.
--
-- Scoring: a correct guess earns more the earlier it comes (fewer hints shown, fewer
-- people ahead of you). The drawer earns DRAWER_POINTS per correct guesser.
--
-- Moderation: guessers can vote to skip a drawing (more than half of the players = wiped
-- and skipped) or report it (a report is also a skip vote; the client hides that player's
-- drawings for the reporter). A player whose drawings get skipped STRIKES times doesn't
-- draw again this match. Typed guesses are filtered by the server before anyone else sees
-- them (textField), and drawings are never saved.
--
-- Moves:
--   drawer, choose:  { kind = "choose", index = 1..3 }
--   drawer, draw:    { kind = "stroke", color = 1..#palette, size = 1..#sizes, points = "<encoded>",
--                      cont = true if it continues the previous chunk of the same line }
--                    { kind = "shape", shape = "line" | "rect" | "ellipse", color, size,
--                      points = "<2 encoded points: start and end / two corners>", fill = bool }
--                    { kind = "bucket", color, points = "<1 encoded point>" }   (fill an area)
--                    { kind = "undo" } | { kind = "clear" }
--   drawer, any:     { kind = "giveUp" }   (skip my turn; also what a bot drawer does)
--   guesser, draw:   { kind = "guess", text = "...", shown = "<filtered by the server>" }
--                    { kind = "voteSkip" } | { kind = "report" }
--   guessed, draw:   { kind = "chat", text = "...", shown }   (seen only by the drawer and
--                    the others who got it, like skribbl's green chat)
--   guesser, draw or reveal: { kind = "rate", up = bool }   (like / dislike the drawing)

local GameModule = require(script.Parent.Parent.GameModule)
local Words = require(script.Parent.Data.SketchWords)
local Doodles = require(script.Parent.Data.SketchDoodles)

local SketchGuess = {}

SketchGuess.id = "SketchGuess"
SketchGuess.minSeats = 3
SketchGuess.maxSeats = 8
SketchGuess.textField = "text"

local CHOOSE_SECONDS = 12
local DRAW_SEGMENT = 20 -- seconds between hint letters
local DRAW_SEGMENTS = 4 -- so a drawing lasts 80 seconds
local REVEAL_SECONDS = 5
local ROUNDS = 2
local MAX_TURNS = 16
local DRAWER_POINTS = 50
local MAX_FEED = 40
local MAX_GUESS = 40
local STRIKES = 2 -- drawings skipped by vote before a player stops drawing this match
local BOT_DRAWERS_BELOW = 3 -- bots take drawing turns when there are fewer players than this
local MAX_BUCKETS = 20 -- fill buckets per drawing (each one is a batch of Frames)
local GALLERY_SECONDS = 12
local GALLERY_SIZE = 4 -- drawings shown in the end-of-game gallery
local HINT_SHARE = { none = 0, normal = 0.5, lots = 0.7 } -- most letters a hint shows
-- Difficulty of each word choice, by how many choices there are.
local CHOICE_LEVELS = {
	[1] = { "medium" },
	[3] = { "easy", "medium", "hard" },
	[5] = { "easy", "easy", "medium", "medium", "hard" },
}
SketchGuess.choiceLevels = CHOICE_LEVELS

-- Drawing limits (they keep each snapshot small enough to send often).
SketchGuess.maxPointsPerStroke = 64
SketchGuess.maxPoints = 3000
SketchGuess.maxStrokes = 400
SketchGuess.resolution = 4095 -- points are integers 0..resolution on both axes

-- Brush colors as RGB (the renderer turns them into Color3).
SketchGuess.palette = {
	{ 30, 28, 36 }, -- ink
	{ 255, 255, 255 }, -- white (eraser)
	{ 150, 150, 160 },
	{ 235, 87, 87 },
	{ 255, 159, 64 },
	{ 255, 214, 80 },
	{ 88, 204, 120 },
	{ 46, 139, 87 },
	{ 80, 170, 255 },
	{ 60, 80, 200 },
	{ 160, 100, 230 },
	{ 255, 130, 190 },
	{ 140, 90, 50 },
	{ 245, 205, 160 },
}
SketchGuess.sizes = { 4, 9, 18, 36 } -- brush widths in pixels on a 600px canvas
SketchGuess.shapes = { "line", "rect", "ellipse" }

-- Point encoding: 2 characters per coordinate (base 64), x then y, so a point is 4 chars.
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local DIGIT = {}
for i = 1, #ALPHABET do
	DIGIT[string.sub(ALPHABET, i, i)] = i - 1
end

function SketchGuess.encodePoints(points: { number }): string
	local parts = table.create(#points)
	for i, v in points do
		local n = math.clamp(math.floor(v + 0.5), 0, SketchGuess.resolution)
		local hi, lo = n // 64, n % 64
		parts[i] = string.sub(ALPHABET, hi + 1, hi + 1) .. string.sub(ALPHABET, lo + 1, lo + 1)
	end
	return table.concat(parts)
end

-- Returns { x1, y1, x2, y2, ... } or nil if the string isn't valid.
function SketchGuess.decodePoints(encoded: string): { number }?
	if #encoded % 4 ~= 0 then
		return nil
	end
	local out = table.create(#encoded // 2)
	for i = 1, #encoded, 2 do
		local hi = DIGIT[string.sub(encoded, i, i)]
		local lo = DIGIT[string.sub(encoded, i + 1, i + 1)]
		if hi == nil or lo == nil then
			return nil
		end
		table.insert(out, hi * 64 + lo)
	end
	return out
end

-- Words ---------------------------------------------------------------------------

local function normalize(text: string): string
	local s = string.lower(text)
	s = string.gsub(s, "[^%a ]", "")
	s = string.gsub(s, "%s+", " ")
	s = string.gsub(s, "^ ", "")
	s = string.gsub(s, " $", "")
	return s
end
SketchGuess.normalize = normalize

local function parseEntry(entry: string): (string, { string })
	local answers = string.split(entry, "|")
	local normalized = {}
	for _, a in answers do
		table.insert(normalized, normalize(a))
	end
	return answers[1], normalized
end

local function editDistance(a: string, b: string): number
	if math.abs(#a - #b) > 2 then
		return 3
	end
	local prev = {}
	for j = 0, #b do
		prev[j] = j
	end
	for i = 1, #a do
		local cur = { [0] = i }
		for j = 1, #b do
			local cost = if string.byte(a, i) == string.byte(b, j) then 0 else 1
			cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
		end
		prev = cur
	end
	return prev[#b]
end

local function pickWord(list: { string }, used: { [string]: boolean }, rng: Random): string
	for _ = 1, 20 do
		local entry = list[rng:NextInteger(1, #list)]
		if not used[entry] then
			return entry
		end
	end
	return list[rng:NextInteger(1, #list)]
end

-- Bot doodles ----------------------------------------------------------------------

-- Doodles are drawn on a 400 x 300 canvas; moves use 0..resolution on both axes.
local function doodlePoint(x: number, y: number): (number, number)
	local res = SketchGuess.resolution
	return math.clamp(math.floor(x / 400 * res + 0.5), 0, res), math.clamp(math.floor(y / 300 * res + 0.5), 0, res)
end

local doodleCache: { [string]: { any } } = {}

-- The moves a bot makes to draw `word` (shape moves only, so they're fine in any mode),
-- or nil when we have no doodle for it.
function SketchGuess.doodleMoves(word: string?): { any }?
	if not word or not Doodles[word] then
		return nil
	end
	local cached = doodleCache[word]
	if cached then
		return cached
	end
	local moves = {}
	for _, op in Doodles[word] do
		if op[1] == "l" then
			local pts, color, size = op[2], op[3], op[4]
			for i = 1, #pts - 3, 2 do
				local x1, y1 = doodlePoint(pts[i], pts[i + 1])
				local x2, y2 = doodlePoint(pts[i + 2], pts[i + 3])
				table.insert(moves, { kind = "shape", shape = "line", color = color, size = size, fill = false, points = SketchGuess.encodePoints({ x1, y1, x2, y2 }) })
			end
		else
			local x1, y1 = doodlePoint(op[2], op[3])
			local x2, y2 = doodlePoint(op[4], op[5])
			table.insert(moves, {
				kind = "shape",
				shape = if op[1] == "e" then "ellipse" else "rect",
				color = op[6],
				size = op[7],
				fill = op[8] == true,
				points = SketchGuess.encodePoints({ x1, y1, x2, y2 }),
			})
		end
	end
	doodleCache[word] = moves
	return moves
end

local doodleWords: { string }? = nil
local function doodleWordList(): { string }
	if not doodleWords then
		local list = {}
		for _, entry in Words.easy do
			if Doodles[(parseEntry(entry))] then
				table.insert(list, entry)
			end
		end
		table.sort(list)
		doodleWords = list
	end
	return doodleWords :: { string }
end

-- Game ----------------------------------------------------------------------------

function SketchGuess.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= SketchGuess.minSeats and seatCount <= SketchGuess.maxSeats, "Sketch & Guess needs 3-8 seats")
	local random = rng or Random.new()
	local botSeats = {}
	if options and type(options.bots) == "table" then
		for _, seat in options.bots do
			botSeats[seat] = true
		end
	end
	local drawers = {}
	for seat = 1, seatCount do
		if not botSeats[seat] then
			table.insert(drawers, seat)
		end
	end
	if #drawers < BOT_DRAWERS_BELOW then
		-- Too few players to take turns drawing: bots draw their doodles too.
		drawers = {}
		for seat = 1, seatCount do
			table.insert(drawers, seat)
		end
	end
	local rules = (options and options.rules) or {}
	local baseRounds = if type(rules.rounds) == "number" then math.clamp(math.floor(rules.rounds), 1, 3) else ROUNDS
	local rounds = if #drawers <= 2 then baseRounds + 1 else baseRounds
	local drawSegments = DRAW_SEGMENTS
	if type(rules.drawSeconds) == "number" then
		drawSegments = math.clamp(math.floor(rules.drawSeconds / DRAW_SEGMENT + 0.5), 2, 6)
	end
	local tools = if rules.tools == "shapes" then "shapes" else "all"
	local wordChoices = if CHOICE_LEVELS[rules.wordChoices] then rules.wordChoices else 3
	local hintShare = HINT_SHARE[rules.hints] or HINT_SHARE.normal
	local customWords = nil
	if options and type(options.customWords) == "table" and #options.customWords >= 3 then
		customWords = table.clone(options.customWords)
	end
	local state = {
		seatCount = seatCount,
		rng = random,
		botLevel = (options and options.botLevel) or "medium",
		botSeats = botSeats,
		drawers = drawers,
		totalTurns = math.min(#drawers * rounds, MAX_TURNS),
		turnNumber = 0,
		phase = "choose",
		timerId = 0,
		drawer = 0,
		choices = {},
		word = nil, -- display form of the word
		answers = {}, -- normalized accepted answers
		revealed = {}, -- [letter index] = true for hint letters
		segment = 0,
		strokes = {},
		pointCount = 0,
		guessed = {}, -- [seat] = order they guessed in (1 = first)
		guessedCount = 0,
		skipVotes = {},
		scores = table.create(seatCount, 0),
		lastPoints = {}, -- points each seat won this turn, shown at the reveal
		feed = {},
		usedWords = {},
		drawSegments = drawSegments,
		customWords = customWords, -- nil = our built-in list
		tools = tools,
		wordChoices = wordChoices,
		choiceLevels = {}, -- difficulty of each choice ("easy"...), shown on the buttons
		hintShare = hintShare,
		likes = {}, -- [seat] = true (like) | false (dislike), this drawing
		buckets = 0, -- fill buckets in this drawing
		gallery = {}, -- finished drawings: { drawer, word, strokes, likes }
		strikes = {}, -- [seat] = drawings of theirs skipped by vote
		benched = {}, -- [seat] = true: no more drawing turns this match
		reports = {}, -- [seat] = true: reported this drawing
		endReason = nil,
		finished = false,
	}
	SketchGuess._startTurn(state)
	return state
end

local function addFeed(state, entry)
	table.insert(state.feed, entry)
	while #state.feed > MAX_FEED do
		table.remove(state.feed, 1)
	end
end

local function nextTimer(state)
	state.timerId += 1
end

function SketchGuess._startTurn(state)
	repeat
		state.turnNumber += 1
		if state.turnNumber > state.totalTurns then
			state.turnNumber = state.totalTurns
			state.drawer = 0
			if #SketchGuess.galleryOf(state) > 0 then
				state.phase = "gallery"
			else
				state.phase = "done"
				state.finished = true
			end
			nextTimer(state)
			return
		end
		state.drawer = state.drawers[(state.turnNumber - 1) % #state.drawers + 1]
	until not state.benched[state.drawer]
	state.phase = "choose"
	local count = state.wordChoices
	state.choiceLevels = table.clone(CHOICE_LEVELS[count])
	if state.botSeats[state.drawer] then
		-- Bots pick from the words they have a doodle for.
		local list = doodleWordList()
		local choices = {}
		for _ = 1, count do
			local entry
			for _ = 1, 10 do
				entry = pickWord(list, state.usedWords, state.rng)
				if not table.find(choices, entry) then
					break
				end
			end
			table.insert(choices, entry)
		end
		state.choices = choices
	elseif state.customWords then
		-- Different words from the host's list.
		state.choiceLevels = {}
		local choices = {}
		for _ = 1, count do
			local entry
			for _ = 1, 10 do
				entry = pickWord(state.customWords, state.usedWords, state.rng)
				if not table.find(choices, entry) then
					break
				end
			end
			table.insert(choices, entry)
		end
		state.choices = choices
	else
		local choices = {}
		for _, level in state.choiceLevels do
			local entry
			for _ = 1, 10 do
				entry = pickWord(Words[level], state.usedWords, state.rng)
				if not table.find(choices, entry) then
					break
				end
			end
			table.insert(choices, entry)
		end
		state.choices = choices
	end
	state.word = nil
	state.answers = {}
	state.revealed = {}
	state.segment = 0
	state.strokes = {}
	state.pointCount = 0
	state.guessed = {}
	state.guessedCount = 0
	state.skipVotes = {}
	state.reports = {}
	state.likes = {}
	state.buckets = 0
	state.lastPoints = {}
	state.endReason = nil
	nextTimer(state)
end

local function chooseWord(state, index: number)
	local entry = state.choices[index]
	state.usedWords[entry] = true
	state.word, state.answers = parseEntry(entry)
	state.phase = "draw"
	state.segment = 0
	addFeed(state, { kind = "system", text = "A new drawing has started!" })
	nextTimer(state)
end

local function guesserCount(state): number
	return state.seatCount - 1
end

local function endDrawing(state, reason: string)
	-- Finished drawings go in the end-of-game gallery. Not ones that were skipped,
	-- given up or reported by anyone.
	local finished = reason == "Time's up!" or reason == "Everyone guessed it!"
	if finished and #state.strokes > 0 and next(state.reports) == nil and state.word then
		table.insert(state.gallery, { drawer = state.drawer, word = state.word, strokes = state.strokes, likes = state.likes, turn = state.turnNumber })
	end
	state.phase = "reveal"
	state.endReason = reason
	state.choices = {}
	addFeed(state, { kind = "system", text = `The word was "{state.word or "?"}"` })
	nextTimer(state)
end

-- Reveal one more hint letter (never the last few, so it stays a guess).
local function revealLetter(state)
	local word = state.word
	if not word then
		return
	end
	local hidden = {}
	local letters = 0
	for i = 1, #word do
		if string.match(string.sub(word, i, i), "%a") then
			letters += 1
			if not state.revealed[i] then
				table.insert(hidden, i)
			end
		end
	end
	local shown = letters - #hidden
	if #hidden <= 1 or shown >= math.floor(letters * state.hintShare) then
		return
	end
	state.revealed[hidden[state.rng:NextInteger(1, #hidden)]] = true
end

function SketchGuess.hint(state): string
	local word = state.word
	if not word then
		return ""
	end
	local parts = {}
	for i = 1, #word do
		local ch = string.sub(word, i, i)
		if ch == " " then
			table.insert(parts, " ")
		elseif state.revealed[i] or not string.match(ch, "%a") then
			table.insert(parts, ch)
		else
			table.insert(parts, "_")
		end
	end
	return table.concat(parts, " ")
end

local function likeCount(likes: { [number]: boolean }): number
	local n = 0
	for _, up in likes do
		if up then
			n += 1
		end
	end
	return n
end

-- The drawings for the end-of-game gallery: most liked first (ties: the earlier one).
function SketchGuess.galleryOf(state): { any }
	local list = {}
	for _, entry in state.gallery do
		table.insert(list, { drawer = entry.drawer, word = entry.word, strokes = entry.strokes, likes = likeCount(entry.likes), turn = entry.turn })
	end
	table.sort(list, function(a, b)
		if a.likes ~= b.likes then
			return a.likes > b.likes
		end
		return a.turn < b.turn
	end)
	while #list > GALLERY_SIZE do
		table.remove(list)
	end
	return list
end

-- Seats that may move out of turn: players who already guessed can chat with each other
-- and rate the drawing; at the reveal anyone but the drawer can still rate it.
function SketchGuess.getInterruptSeats(state): { number }
	local seats = {}
	if state.phase == "draw" then
		for seat = 1, state.seatCount do
			if seat ~= state.drawer and state.guessed[seat] then
				table.insert(seats, seat)
			end
		end
	elseif state.phase == "reveal" then
		for seat = 1, state.seatCount do
			if seat ~= state.drawer then
				table.insert(seats, seat)
			end
		end
	end
	return seats
end

function SketchGuess.getActiveSeats(state): { number }
	if state.phase == "choose" then
		return { state.drawer }
	elseif state.phase == "draw" then
		local seats = { state.drawer }
		for seat = 1, state.seatCount do
			if seat ~= state.drawer and not state.guessed[seat] then
				table.insert(seats, seat)
			end
		end
		return seats
	end
	return {}
end

function SketchGuess.getLegalMoves(state, seat: number): { any }
	-- Used only for random bot fallback: give safe moves, never strokes.
	if state.phase == "choose" and seat == state.drawer then
		return { { kind = "choose", index = 1 }, { kind = "choose", index = 2 }, { kind = "choose", index = 3 } }
	elseif state.phase == "draw" and seat == state.drawer then
		if SketchGuess.doodleMoves(state.word) then
			return {} -- a bot that has finished its doodle just waits
		end
		return { { kind = "giveUp" } }
	end
	return {}
end

local function isInt(v: any, lo: number, hi: number): boolean
	return type(v) == "number" and v == v and v % 1 == 0 and v >= lo and v <= hi
end

function SketchGuess.validateMove(state, seat: number, move: any): (boolean, string?)
	if type(move) ~= "table" or type(move.kind) ~= "string" then
		return false, "Bad move"
	end
	local kind = move.kind
	if seat == state.drawer then
		if kind == "giveUp" then
			return state.phase == "choose" or state.phase == "draw", "Not now"
		elseif state.phase == "choose" then
			if kind == "choose" and isInt(move.index, 1, #state.choices) then
				return true
			end
			return false, "Pick a word"
		elseif state.phase == "draw" then
			if kind == "undo" or kind == "clear" then
				return true
			elseif kind == "bucket" then
				if not isInt(move.color, 1, #SketchGuess.palette) then
					return false, "Bad brush"
				end
				if type(move.points) ~= "string" or #move.points ~= 4 or not SketchGuess.decodePoints(move.points) then
					return false, "Bad fill"
				end
				if state.buckets >= MAX_BUCKETS then
					return false, `That's the most fills for one drawing ({MAX_BUCKETS})`
				end
				if #state.strokes >= SketchGuess.maxStrokes or state.pointCount + 2 > SketchGuess.maxPoints then
					return false, "The canvas is full. Undo or clear to keep drawing."
				end
				return true
			elseif kind == "shape" then
				if not table.find(SketchGuess.shapes, move.shape) then
					return false, "Bad shape"
				end
				if not isInt(move.color, 1, #SketchGuess.palette) or not isInt(move.size, 1, #SketchGuess.sizes) then
					return false, "Bad brush"
				end
				if move.fill ~= nil and type(move.fill) ~= "boolean" then
					return false, "Bad shape"
				end
				if type(move.points) ~= "string" or #move.points ~= 8 or not SketchGuess.decodePoints(move.points) then
					return false, "Bad shape"
				end
				if #state.strokes >= SketchGuess.maxStrokes or state.pointCount + 2 > SketchGuess.maxPoints then
					return false, "The canvas is full. Undo or clear to keep drawing."
				end
				return true
			elseif kind == "stroke" then
				if state.tools == "shapes" then
					return false, "Only shapes at this table: pick a line, box or oval"
				end
				if not isInt(move.color, 1, #SketchGuess.palette) or not isInt(move.size, 1, #SketchGuess.sizes) then
					return false, "Bad brush"
				end
				if type(move.points) ~= "string" or #move.points < 4 or #move.points > SketchGuess.maxPointsPerStroke * 4 then
					return false, "Bad stroke"
				end
				if not SketchGuess.decodePoints(move.points) then
					return false, "Bad stroke"
				end
				if #state.strokes >= SketchGuess.maxStrokes or state.pointCount + #move.points // 4 > SketchGuess.maxPoints then
					return false, "The canvas is full. Undo or clear to keep drawing."
				end
				return true
			end
		end
		return false, "Not now"
	end
	if kind == "rate" then
		if state.phase ~= "draw" and state.phase ~= "reveal" then
			return false, "Wait for the next drawing"
		end
		if type(move.up) ~= "boolean" then
			return false, "Bad move"
		end
		if state.likes[seat] == move.up then
			return false, if move.up then "You already liked it" else "You already disliked it"
		end
		return true
	end
	if state.phase ~= "draw" then
		return false, "Wait for the next drawing"
	end
	if kind == "chat" then
		if not state.guessed[seat] then
			return false, "Guess the word first"
		end
		if type(move.text) ~= "string" or #move.text == 0 or #move.text > MAX_GUESS or normalize(move.text) == "" then
			return false, "Type a message"
		end
		return true
	elseif kind == "voteSkip" then
		if state.skipVotes[seat] then
			return false, "You already voted to skip"
		end
		return true
	elseif kind == "report" then
		if state.reports[seat] then
			return false, "You already reported this drawing"
		end
		if state.botSeats[state.drawer] then
			return false, "Bots only draw our own doodles"
		end
		return true
	elseif kind == "guess" then
		if state.guessed[seat] then
			return false, "You already got it!"
		end
		if type(move.text) ~= "string" or #move.text == 0 or #move.text > MAX_GUESS then
			return false, "Type a guess"
		end
		if normalize(move.text) == "" then
			return false, "Type a guess"
		end
		return true
	end
	return false, "Bad move"
end

local function allGuessed(state): boolean
	return state.guessedCount >= guesserCount(state)
end

function SketchGuess.applyMove(state, seat: number, move: any)
	local kind = move.kind
	if kind == "giveUp" then
		if state.phase == "choose" then
			state.word = state.choices[1]
			state.word = (parseEntry(state.word))
		end
		endDrawing(state, "The drawer skipped their turn")
		return
	elseif kind == "choose" then
		chooseWord(state, move.index)
		return
	elseif kind == "stroke" then
		table.insert(state.strokes, { color = move.color, size = move.size, points = move.points, cont = move.cont == true })
		state.pointCount += #move.points // 4
		return
	elseif kind == "shape" then
		table.insert(state.strokes, { shape = move.shape, fill = move.fill == true, color = move.color, size = move.size, points = move.points, cont = false })
		state.pointCount += 2
		return
	elseif kind == "bucket" then
		table.insert(state.strokes, { shape = "bucket", color = move.color, size = 1, points = move.points, cont = false })
		state.pointCount += 2
		state.buckets += 1
		return
	elseif kind == "rate" then
		local first = state.likes[seat] == nil
		state.likes[seat] = move.up
		if move.up and first then
			addFeed(state, { kind = "like", seat = seat, text = "liked the drawing!" })
		end
		return
	elseif kind == "chat" then
		-- Only the drawer and players who got it see this (it may name the word).
		local shown = if type(move.shown) == "string" and move.shown ~= "" then move.shown else "(hidden)"
		addFeed(state, { kind = "chat", seat = seat, text = shown, secret = true })
		return
	elseif kind == "undo" then
		-- Remove the last whole line (one line can arrive as several chunks).
		while #state.strokes > 0 do
			local last = table.remove(state.strokes) :: any
			state.pointCount -= if last.shape then 2 else #last.points // 4
			if last.shape == "bucket" then
				state.buckets -= 1
			end
			if not last.cont then
				break
			end
		end
		return
	elseif kind == "clear" then
		state.strokes = {}
		state.pointCount = 0
		state.buckets = 0
		return
	elseif kind == "voteSkip" or kind == "report" then
		if kind == "report" then
			state.reports[seat] = true
			addFeed(state, { kind = "system", to = seat, text = "Thanks for reporting. Their drawings are hidden for you, and your report counts as a vote to skip." })
			if state.skipVotes[seat] then
				return
			end
		end
		state.skipVotes[seat] = true
		local votes = 0
		for _ in state.skipVotes do
			votes += 1
		end
		local voters = 0
		for s = 1, state.seatCount do
			if s ~= state.drawer and not state.botSeats[s] then
				voters += 1
			end
		end
		local needed = math.max(1, voters // 2 + 1)
		addFeed(state, { kind = "system", text = `Skip votes: {votes}/{needed}` })
		if votes >= needed then
			local drawer = state.drawer
			state.lastPoints = {}
			state.strokes = {}
			state.pointCount = 0
			state.strikes[drawer] = (state.strikes[drawer] or 0) + 1
			endDrawing(state, "Skipped by vote")
			if state.strikes[drawer] >= STRIKES and not state.botSeats[drawer] then
				state.benched[drawer] = true
				addFeed(state, { kind = "system", seat = drawer, text = "won't draw again this game (drawings skipped twice)." })
			end
		end
		return
	end

	-- A guess.
	local guess = normalize(move.text)
	if table.find(state.answers, guess) then
		state.guessedCount += 1
		state.guessed[seat] = state.guessedCount
		-- Up to 200 for guessing before any hint (less as hints appear), up to 200 for
		-- being among the first, and 100 for getting it at all.
		local timeLeft = math.max(0, state.drawSegments - state.segment) / state.drawSegments
		local points = 100 + math.floor(200 * timeLeft + 0.5) + math.max(0, 200 - 40 * (state.guessedCount - 1))
		state.scores[seat] += points
		state.lastPoints[seat] = (state.lastPoints[seat] or 0) + points
		state.scores[state.drawer] += DRAWER_POINTS
		state.lastPoints[state.drawer] = (state.lastPoints[state.drawer] or 0) + DRAWER_POINTS
		addFeed(state, { kind = "correct", seat = seat, text = "guessed the word!" })
		if allGuessed(state) then
			endDrawing(state, "Everyone guessed it!")
		end
		return
	end
	local shown = if type(move.shown) == "string" and move.shown ~= "" then move.shown else nil
	addFeed(state, { kind = "guess", seat = seat, text = shown or "(hidden)" })
	if #guess >= 4 then
		for _, answer in state.answers do
			if editDistance(guess, answer) == 1 then
				addFeed(state, { kind = "close", seat = seat, to = seat, text = `"{shown or "That"}" is close!` })
				break
			end
		end
	end
end

function SketchGuess.getTimer(state): { id: number, seconds: number }?
	if state.phase == "choose" then
		return { id = state.timerId, seconds = CHOOSE_SECONDS }
	elseif state.phase == "draw" then
		-- The clock ticks per hint, but players see the time left for the whole drawing.
		return {
			id = state.timerId,
			seconds = DRAW_SEGMENT,
			displaySeconds = DRAW_SEGMENT * (state.drawSegments - state.segment),
		}
	elseif state.phase == "reveal" then
		return { id = state.timerId, seconds = REVEAL_SECONDS }
	elseif state.phase == "gallery" then
		return { id = state.timerId, seconds = GALLERY_SECONDS }
	end
	return nil
end

function SketchGuess.onTimeout(state)
	if state.phase == "choose" then
		chooseWord(state, 1)
	elseif state.phase == "draw" then
		state.segment += 1
		if state.segment >= state.drawSegments then
			endDrawing(state, "Time's up!")
		else
			revealLetter(state)
			nextTimer(state)
		end
	elseif state.phase == "reveal" then
		SketchGuess._startTurn(state)
	elseif state.phase == "gallery" then
		state.phase = "done"
		state.finished = true
		nextTimer(state)
	end
end

function SketchGuess.getResult(state): GameModule.Result?
	if not state.finished then
		return nil
	end
	local best = -1
	for seat = 1, state.seatCount do
		best = math.max(best, state.scores[seat])
	end
	local winners = {}
	for seat = 1, state.seatCount do
		if state.scores[seat] == best then
			table.insert(winners, seat)
		end
	end
	return { winners = winners, isDraw = false, reason = `Top score: {best} points` }
end

function SketchGuess.getScores(state): { [number]: number }
	return table.clone(state.scores)
end

function SketchGuess.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		local tag = ""
		if state.phase ~= "done" and seat == state.drawer then
			tag = "  ✏️ drawing"
		elseif state.guessed[seat] then
			tag = "  ✓ guessed"
		end
		info[seat] = `{state.scores[seat]} pts{tag}`
	end
	return info
end

function SketchGuess.getView(state, seat: number?)
	local isDrawer = seat ~= nil and seat == state.drawer
	local knowsWord = isDrawer or state.phase == "reveal" or state.phase == "done" or (seat ~= nil and state.guessed[seat] ~= nil)
	local feed = {}
	for _, entry in state.feed do
		if (entry.to == nil or entry.to == seat) and (not entry.secret or knowsWord) then
			table.insert(feed, { kind = entry.kind, seat = entry.seat, text = entry.text })
		end
	end
	local status
	if state.phase == "choose" then
		status = if isDrawer then "Pick a word to draw!" else "The drawer is picking a word..."
	elseif state.phase == "draw" then
		status = if isDrawer then "Draw it!" elseif seat and state.guessed[seat] then "You got it! Waiting for the others..." else "Guess the word!"
	elseif state.phase == "reveal" then
		status = state.endReason or "Round over"
	elseif state.phase == "gallery" then
		status = "Best drawings of the game"
	else
		status = "Game over"
	end
	return {
		phase = state.phase,
		drawer = state.drawer,
		turnNumber = math.min(state.turnNumber, state.totalTurns),
		totalTurns = state.totalTurns,
		choices = if isDrawer and state.phase == "choose" then table.clone(state.choices) else nil,
		choiceLevels = if isDrawer and state.phase == "choose" then table.clone(state.choiceLevels) else nil,
		word = if knowsWord then state.word else nil,
		hint = if state.phase == "draw" then SketchGuess.hint(state) else nil,
		-- The gallery carries its own drawings, so the last one isn't sent twice.
		strokes = if state.phase == "gallery" or state.phase == "done" then {} else GameModule.copy(state.strokes),
		gallery = if state.phase == "gallery" then GameModule.copy(SketchGuess.galleryOf(state)) else nil,
		likes = likeCount(state.likes),
		youLiked = if seat ~= nil then state.likes[seat] else nil,
		buckets = state.buckets,
		maxBuckets = MAX_BUCKETS,
		pointCount = state.pointCount,
		guessed = table.clone(state.guessed),
		youGuessed = seat ~= nil and state.guessed[seat] ~= nil,
		youVotedSkip = seat ~= nil and state.skipVotes[seat] == true,
		youReported = seat ~= nil and state.reports[seat] == true,
		drawerIsBot = state.botSeats[state.drawer] == true,
		tools = state.tools,
		scores = table.clone(state.scores),
		lastPoints = if state.phase == "reveal" or state.phase == "done" then table.clone(state.lastPoints) else nil,
		feed = feed,
		status = status,
	}
end

-- Bots: never draw; as guessers they get more likely to be right as hints appear.
local GUESS_CHANCE = { easy = 0.08, medium = 0.15, hard = 0.25 }

function SketchGuess.getBotDelay(state, seat: number, rng: Random): number
	if seat == state.drawer then
		if state.phase == "draw" then
			-- A shape every second or so, after a moment to "think" about the first one.
			return if #state.strokes == 0 then rng:NextNumber(2, 3) else rng:NextNumber(0.6, 1.3)
		end
		return rng:NextNumber(1.5, 3)
	end
	return rng:NextNumber(4, 9)
end

-- A bot drawer picks a word it has a doodle for and draws it one shape at a time. A
-- player's seat taken over by a bot (they left) gives up when none of its words has one.
local function botDraw(state): any?
	if state.phase == "choose" then
		for i, entry in state.choices do
			if Doodles[(parseEntry(entry))] then
				return { kind = "choose", index = i }
			end
		end
		return { kind = "giveUp" }
	end
	local moves = SketchGuess.doodleMoves(state.word)
	if not moves then
		return { kind = "giveUp" }
	end
	local nextMove = moves[#state.strokes + 1]
	return if nextMove then table.clone(nextMove) else nil
end

function SketchGuess.chooseBotMove(state, seat: number, rng: Random): any?
	if seat == state.drawer then
		return botDraw(state)
	end
	if state.phase ~= "draw" then
		return nil
	end
	if state.guessed[seat] then
		-- Now and then a bot that got it likes the drawing.
		if state.likes[seat] == nil and rng:NextNumber() < 0.15 then
			return { kind = "rate", up = true }
		end
		return nil
	end
	if rng:NextNumber() < 0.3 then
		return nil -- just watching for now
	end
	-- Bots only get it right once there's something to look at: no chance on an empty
	-- canvas, full chance from about 150 points of drawing.
	-- (Shapes count as 2 points each, so they also count 12 for being on the canvas.)
	local drawn = math.clamp((state.pointCount + 12 * #state.strokes - 20) / 130, 0, 1)
	local chance = ((GUESS_CHANCE[state.botLevel] or 0.15) + 0.12 * state.segment) * drawn
	if rng:NextNumber() < chance then
		return { kind = "guess", text = state.word, shown = state.word }
	end
	local pools = { Words.easy, Words.medium, Words.hard }
	for _ = 1, 5 do
		local pool = pools[rng:NextInteger(1, 3)]
		local wrong = (parseEntry(pool[rng:NextInteger(1, #pool)]))
		if not table.find(state.answers, normalize(wrong)) then
			return { kind = "guess", text = wrong, shown = wrong }
		end
	end
	return nil
end

return SketchGuess
