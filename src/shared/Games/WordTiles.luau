--[[
	Word Tiles: a crossword tile game for 2-4 seats. Players take turns laying letter tiles
	in one row or column to make words that join the ones already on the board. The
	display name is set only in GameCatalog.luau.

	Boards (options.board, checked here):
	  "quick"   11x11, 60 tiles. The default: about 15 minutes, which suits Roblox.
	  "classic" 15x15, 100 tiles.
	Both use our own premium-square layout (Boards below), with the center square as a
	double word. Letter counts and values follow the usual English set.

	A turn is one of:
	  { kind = "place", tiles = { { row, col, letter = "a".."z", blank = true? } } }
	      1-7 tiles from your rack, all in one row or column with no gaps, touching the
	      tiles already down (the first word covers the center). Every word made, the main
	      one and any crossing ones, must be in the word list. Blank tiles say which letter
	      they stand for and score 0.
	  { kind = "exchange", letters = { "q", "?", ... } }   ("?" is a blank) Needs 7+ in the bag.
	  { kind = "pass" }

	Scoring: letter values, times any letter premium under a new tile, times any word
	premium under a new tile. Every word made scores. Using all 7 tiles adds 50.
	The game ends when someone uses their last tile with the bag empty (they gain what's
	left on everyone else's racks, and the others lose it), or after SCORELESS_LIMIT turns
	in a row without points (everyone loses what's left on their rack). Top score wins.

	The word list is not part of this module (it's big and only the server needs it).
	The server calls WordTiles.useDictionary(...) with a WordTrie; tests pass a small one.
	Clients can still call WordTiles.evaluate without a dictionary for a score preview.
]]

local GameModule = require(script.Parent.Parent.GameModule)
local WordTrie = require(script.Parent.Parent.WordTrie)

local WordTiles = {}

WordTiles.id = "WordTiles"
WordTiles.minSeats = 2
WordTiles.maxSeats = 4

local RACK_SIZE = 7
local BINGO_BONUS = 50
local EXCHANGE_MIN_BAG = 7
local TURN_LIMIT = 400 -- safety valve
local SCORELESS_LIMIT = 6 -- turns in a row with no points (at least two full rounds)

WordTiles.rackSize = RACK_SIZE
WordTiles.bingoBonus = BINGO_BONUS
WordTiles.exchangeMinBag = EXCHANGE_MIN_BAG

WordTiles.values = {
	a = 1, b = 3, c = 3, d = 2, e = 1, f = 4, g = 2, h = 4, i = 1, j = 8, k = 5, l = 1, m = 3,
	n = 1, o = 1, p = 3, q = 10, r = 1, s = 1, t = 1, u = 1, v = 4, w = 4, x = 8, y = 4, z = 10,
	["?"] = 0,
}
local VALUES = WordTiles.values

-- Premium squares, as one character per cell:
--   W triple word   w double word   L triple letter   l double letter   * center (double word)
local LETTER_MULT = { L = 3, l = 2 }
local WORD_MULT = { W = 3, w = 2, ["*"] = 2 }
WordTiles.premiumNames = { W = "Triple word", w = "Double word", L = "Triple letter", l = "Double letter", ["*"] = "Start (double word)" }

-- Our own layout. Each list gives cells in one eighth of the board (0-based row <= col,
-- counted from the top-left corner); they're mirrored to all eight symmetric spots.
local function buildPremium(size: number, spec: { [string]: { { number } } }): { { string } }
	local rows = {}
	for r = 1, size do
		rows[r] = table.create(size, ".")
	end
	for _, kind in { "W", "w", "L", "l" } do
		for _, rc in spec[kind] or {} do
			for _, p in { { rc[1], rc[2] }, { rc[2], rc[1] } } do
				for _, rr in { p[1], size - 1 - p[1] } do
					for _, cc in { p[2], size - 1 - p[2] } do
						rows[rr + 1][cc + 1] = kind
					end
				end
			end
		end
	end
	local mid = (size + 1) // 2
	rows[mid][mid] = "*"
	return rows
end

local function bagFrom(counts: { [string]: number }): { string }
	local bag = {}
	for letter, n in counts do
		for _ = 1, n do
			table.insert(bag, letter)
		end
	end
	table.sort(bag) -- same order every time before the shuffle
	return bag
end

WordTiles.boards = {
	quick = {
		name = "Quick board",
		size = 11,
		premium = buildPremium(11, {
			W = { { 0, 3 } },
			w = { { 1, 1 }, { 3, 3 } },
			L = { { 0, 0 }, { 2, 4 } },
			l = { { 1, 3 }, { 4, 4 }, { 0, 5 } },
		}),
		-- 60 tiles: the usual mix, scaled down so the bag runs out on a smaller board.
		bag = {
			a = 5, b = 1, c = 1, d = 2, e = 7, f = 1, g = 2, h = 1, i = 5, j = 1, k = 1, l = 2, m = 1,
			n = 4, o = 5, p = 1, q = 1, r = 4, s = 3, t = 4, u = 2, v = 1, w = 1, x = 1, y = 1, z = 1,
			["?"] = 1,
		},
	},
	classic = {
		name = "Classic board",
		size = 15,
		premium = buildPremium(15, {
			W = { { 0, 4 } },
			w = { { 1, 1 }, { 3, 3 }, { 2, 7 } },
			L = { { 0, 0 }, { 2, 5 }, { 5, 5 } },
			l = { { 0, 7 }, { 1, 4 }, { 3, 6 }, { 6, 6 } },
		}),
		bag = {
			a = 9, b = 2, c = 2, d = 4, e = 12, f = 2, g = 3, h = 2, i = 9, j = 1, k = 1, l = 4, m = 2,
			n = 6, o = 8, p = 2, q = 1, r = 6, s = 4, t = 6, u = 4, v = 2, w = 2, x = 1, y = 2, z = 1,
			["?"] = 2,
		},
	},
}
WordTiles.defaultBoard = "quick"

-- Dictionary ----------------------------------------------------------------------

local dictionary: WordTrie.Trie? = nil
local dictionaryLoader: (() -> WordTrie.Trie)? = nil

-- Sets the word list: a WordTrie, or a function that returns one (called on first use).
function WordTiles.useDictionary(source: any)
	if type(source) == "function" then
		dictionary = nil
		dictionaryLoader = source
	else
		dictionary = source
		dictionaryLoader = nil
	end
end

local function getDictionary(): WordTrie.Trie?
	if not dictionary and dictionaryLoader then
		dictionary = dictionaryLoader()
	end
	return dictionary
end

function WordTiles.isWord(word: string): boolean
	local dict = getDictionary()
	return dict ~= nil and dict:has(word)
end

-- Board helpers (shared with the client) --------------------------------------------

export type Board = { { string? } } -- [row][col] = "a".."z", or "A".."Z" for a blank tile

export type PlacedTile = { row: number, col: number, letter: string, blank: boolean? }

-- Turns the view's row strings ("..cat.....", uppercase = blank) back into a Board.
function WordTiles.boardFromRows(rows: { string }): Board
	local board = {}
	for r, line in rows do
		board[r] = {}
		for c = 1, #line do
			local ch = string.sub(line, c, c)
			if ch ~= "." then
				board[r][c] = ch
			end
		end
	end
	return board
end

local function rowsOf(board: Board, size: number): { string }
	local rows = {}
	for r = 1, size do
		local chars = table.create(size, ".")
		for c = 1, size do
			chars[c] = board[r][c] or "."
		end
		rows[r] = table.concat(chars)
	end
	return rows
end

local function rackValue(rack: { string }): number
	local total = 0
	for _, letter in rack do
		total += VALUES[letter] or 0
	end
	return total
end

--[[
	Checks a placement's shape and scores it. Shared by the server (with isWord) and the
	client's live preview (without). Returns either
	  { score, bingo, words = { { word, score, cells = { {row, col} } } } }
	or nil plus a message for the player.
]]
function WordTiles.evaluate(board: Board, premium: { { string } }, tiles: { PlacedTile }, isWord: ((string) -> boolean)?): (any?, string?)
	local size = #premium
	if #tiles == 0 then
		return nil, "Place some tiles first"
	end
	local placed: { [number]: string } = {}
	local sameRow, sameCol = true, true
	for _, t in tiles do
		placed[t.row * 32 + t.col] = if t.blank then string.upper(t.letter) else t.letter
		if t.row ~= tiles[1].row then
			sameRow = false
		end
		if t.col ~= tiles[1].col then
			sameCol = false
		end
	end
	if not sameRow and not sameCol then
		return nil, "Tiles must go in one row or one column"
	end

	local function at(r: number, c: number): string?
		if r < 1 or c < 1 or r > size or c > size then
			return nil
		end
		return placed[r * 32 + c] or board[r][c]
	end

	local mid = (size + 1) // 2
	local firstMove = board[mid][mid] == nil

	local dr, dc = 0, 1
	if #tiles == 1 then
		local t = tiles[1]
		if not (at(t.row, t.col - 1) or at(t.row, t.col + 1)) and (at(t.row - 1, t.col) or at(t.row + 1, t.col)) then
			dr, dc = 1, 0
		end
	elseif sameCol then
		dr, dc = 1, 0
	end

	-- No gaps between the first and last new tile.
	local lo, hi = math.huge, -math.huge
	for _, t in tiles do
		local index = if dr == 0 then t.col else t.row
		lo = math.min(lo, index)
		hi = math.max(hi, index)
	end
	local touches = false
	for index = lo, hi do
		local r = if dr == 0 then tiles[1].row else index
		local c = if dr == 0 then index else tiles[1].col
		if not at(r, c) then
			return nil, "Leave no gaps between your tiles"
		end
		if board[r][c] then
			touches = true
		end
	end

	if firstMove then
		if not placed[mid * 32 + mid] then
			return nil, "The first word must cover the center star"
		end
	elseif not touches then
		for _, t in tiles do
			for _, d in { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } } do
				local r, c = t.row + d[1], t.col + d[2]
				if r >= 1 and c >= 1 and r <= size and c <= size and board[r][c] then
					touches = true
				end
			end
		end
		if not touches then
			return nil, "Your word must join the tiles already on the board"
		end
	end

	local function wordThrough(r: number, c: number, wr: number, wc: number)
		while at(r - wr, c - wc) do
			r -= wr
			c -= wc
		end
		local letters, cells = {}, {}
		local sum, wordMult = 0, 1
		while true do
			local ch = at(r, c)
			if not ch then
				break
			end
			local letter = string.lower(ch)
			local value = if ch ~= letter then 0 else VALUES[letter]
			if placed[r * 32 + c] then
				local p = premium[r][c]
				value *= LETTER_MULT[p] or 1
				wordMult *= WORD_MULT[p] or 1
			end
			sum += value
			table.insert(letters, letter)
			table.insert(cells, { r, c })
			r += wr
			c += wc
		end
		return { word = table.concat(letters), score = sum * wordMult, cells = cells }
	end

	local words = {}
	local main = wordThrough(tiles[1].row, tiles[1].col, dr, dc)
	if #main.word >= 2 then
		table.insert(words, main)
	end
	for _, t in tiles do
		local cross = wordThrough(t.row, t.col, dc, dr)
		if #cross.word >= 2 then
			table.insert(words, cross)
		end
	end
	if #words == 0 then
		return nil, "Make a word of at least two letters"
	end
	if isWord then
		for _, w in words do
			if not isWord(w.word) then
				return nil, `{string.upper(w.word)} isn't in the word list`
			end
		end
	end

	local score = 0
	for _, w in words do
		score += w.score
	end
	local bingo = #tiles == RACK_SIZE
	if bingo then
		score += BINGO_BONUS
	end
	return { score = score, bingo = bingo, words = words }
end

-- State ------------------------------------------------------------------------------

local function shuffle(list: { any }, rng: Random)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

local function refill(state, seat: number)
	local rack = state.racks[seat]
	while #rack < RACK_SIZE and #state.bag > 0 do
		table.insert(rack, table.remove(state.bag) :: string)
	end
end

function WordTiles.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= 2 and seatCount <= 4, "Word Tiles needs 2-4 seats")
	local random = rng or Random.new()
	-- The board comes from options.board or the "board" house rule.
	local wanted = options and (options.board or (type(options.rules) == "table" and options.rules.board))
	local boardKey = if wanted == "classic" then "classic" else WordTiles.defaultBoard
	local def = WordTiles.boards[boardKey]
	local bag = bagFrom(def.bag)
	shuffle(bag, random)

	local board = {}
	for r = 1, def.size do
		board[r] = {}
	end
	local state = {
		seatCount = seatCount,
		rng = random,
		boardKey = boardKey,
		size = def.size,
		premium = def.premium,
		board = board,
		bag = bag,
		racks = {},
		scores = {},
		turn = 1,
		turns = 0,
		scoreless = 0,
		lastPlay = nil,
		log = {}, -- recent plays, newest last
		finished = false,
		reason = nil,
		botLevel = (options and options.botLevel) or "medium",
		-- Hindsight, like Words With Friends and Scrabble GO: after each of your plays,
		-- the best play your rack had. Only you see yours. Bots don't need it.
		bots = {} :: { [number]: boolean },
		hindsight = {} :: { [number]: any }, -- seat -> { word, score, played }
		biggestMiss = {} :: { [number]: any }, -- seat -> the play that left most on the table
	}
	for _, seat in (options and options.bots) or {} do
		state.bots[seat] = true
	end
	for seat = 1, seatCount do
		state.racks[seat] = {}
		state.scores[seat] = 0
		refill(state, seat)
	end
	return state
end

function WordTiles.getActiveSeats(state): { number }
	if state.finished then
		return {}
	end
	return { state.turn }
end

function WordTiles.getLegalMoves(state, seat: number): { any }
	-- Placements are far too many to list; the bot finds them itself (chooseBotMove).
	if state.finished or seat ~= state.turn then
		return {}
	end
	return { { kind = "pass" } }
end

local function isInteger(v: any, lo: number, hi: number): boolean
	return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi
end

local function rackCounts(rack: { string }): { [string]: number }
	local counts = {}
	for _, letter in rack do
		counts[letter] = (counts[letter] or 0) + 1
	end
	return counts
end

-- Checks a placement's fields against the board and the seat's rack. Returns clean tiles.
local function readTiles(state, seat: number, list: any): ({ PlacedTile }?, string?)
	if type(list) ~= "table" or #list < 1 or #list > RACK_SIZE then
		return nil, "Place between 1 and 7 tiles"
	end
	local counts = rackCounts(state.racks[seat])
	local seen = {}
	local tiles = {}
	for i = 1, #list do
		local t = list[i]
		if type(t) ~= "table" or not isInteger(t.row, 1, state.size) or not isInteger(t.col, 1, state.size) then
			return nil, "That tile is off the board"
		end
		if type(t.letter) ~= "string" or not string.match(t.letter, "^[a-z]$") then
			return nil, "Pick a letter for every tile"
		end
		if t.blank ~= nil and type(t.blank) ~= "boolean" then
			return nil, "That tile isn't right"
		end
		local key = t.row * 32 + t.col
		if seen[key] or state.board[t.row][t.col] then
			return nil, "That square is taken"
		end
		seen[key] = true
		local rackLetter = if t.blank then "?" else t.letter
		if (counts[rackLetter] or 0) < 1 then
			return nil, if t.blank then "You don't have a blank tile" else `You don't have a {string.upper(t.letter)}`
		end
		counts[rackLetter] -= 1
		table.insert(tiles, { row = t.row, col = t.col, letter = t.letter, blank = t.blank == true })
	end
	return tiles
end

local function checkPlacement(state, seat: number, move: any): (any?, { PlacedTile }?, string?)
	local tiles, err = readTiles(state, seat, move.tiles)
	if not tiles then
		return nil, nil, err
	end
	local dict = getDictionary()
	if not dict then
		return nil, nil, "The word list is still loading. Try again in a moment."
	end
	local result, why = WordTiles.evaluate(state.board, state.premium, tiles, function(word)
		return dict:has(word)
	end)
	if not result then
		return nil, nil, why
	end
	return result, tiles
end

function WordTiles.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.finished then
		return false, "The game is over"
	end
	if seat ~= state.turn then
		return false, "It's not your turn"
	end
	if type(move) ~= "table" then
		return false, "Bad move"
	end
	if move.kind == "pass" then
		return true
	elseif move.kind == "exchange" then
		if #state.bag < EXCHANGE_MIN_BAG then
			return false, `You can swap only while {EXCHANGE_MIN_BAG} or more tiles are in the bag`
		end
		local letters = move.letters
		if type(letters) ~= "table" or #letters < 1 or #letters > RACK_SIZE then
			return false, "Pick the tiles to swap"
		end
		local counts = rackCounts(state.racks[seat])
		for i = 1, #letters do
			local letter = letters[i]
			if type(letter) ~= "string" or (counts[letter] or 0) < 1 then
				return false, "You don't have those tiles"
			end
			counts[letter] -= 1
		end
		return true
	elseif move.kind == "place" then
		local result, _, err = checkPlacement(state, seat, move)
		if not result then
			return false, err
		end
		return true
	end
	return false, "Bad move"
end

local function takeFromRack(rack: { string }, letter: string)
	local index = table.find(rack, letter)
	if index then
		table.remove(rack, index)
	end
end

local function finish(state, reason: string)
	state.finished = true
	state.reason = reason
end

local function addLog(state, entry)
	table.insert(state.log, entry)
	while #state.log > 8 do
		table.remove(state.log, 1)
	end
end

function WordTiles.applyMove(state, seat: number, move: any)
	local rack = state.racks[seat]
	local play: any = { seat = seat, kind = move.kind, score = 0 }

	if move.kind == "place" then
		local result, tiles = checkPlacement(state, seat, move)
		assert(result and tiles, "applyMove called with an invalid placement")
		WordTiles._hindsight(state, seat, result)
		play.cells = {}
		for _, t in tiles do
			state.board[t.row][t.col] = if t.blank then string.upper(t.letter) else t.letter
			takeFromRack(rack, if t.blank then "?" else t.letter)
			table.insert(play.cells, { t.row, t.col })
		end
		play.score = result.score
		play.bingo = result.bingo
		play.words = {}
		for _, w in result.words do
			table.insert(play.words, { word = w.word, score = w.score })
			GameModule.addStat(state, seat, "words")
			GameModule.maxStat(state, seat, "bestWord", w.score)
		end
		if result.bingo then
			GameModule.addStat(state, seat, "bingos")
		end
		state.scores[seat] += result.score
		refill(state, seat)
	elseif move.kind == "exchange" then
		local returned = {}
		for i = 1, #move.letters do
			takeFromRack(rack, move.letters[i])
			table.insert(returned, move.letters[i])
		end
		play.count = #returned
		refill(state, seat) -- draw first, then the swapped tiles go back in
		for _, letter in returned do
			table.insert(state.bag, letter)
		end
		shuffle(state.bag, state.rng)
	end

	state.lastPlay = play
	addLog(state, play)
	state.turns += 1
	if play.score > 0 then
		state.scoreless = 0
	else
		state.scoreless += 1
	end

	if move.kind == "place" and #rack == 0 and #state.bag == 0 then
		-- Out of tiles: collect what's left on everyone else's rack.
		local bonus = 0
		for other = 1, state.seatCount do
			if other ~= seat then
				local left = rackValue(state.racks[other])
				state.scores[other] -= left
				bonus += left
			end
		end
		state.scores[seat] += bonus
		finish(state, "Out of tiles")
		return
	end
	if state.scoreless >= math.max(SCORELESS_LIMIT, state.seatCount * 2) or state.turns >= TURN_LIMIT then
		for other = 1, state.seatCount do
			state.scores[other] -= rackValue(state.racks[other])
		end
		finish(state, "No one could score")
		return
	end
	state.turn = state.turn % state.seatCount + 1
end

function WordTiles.getResult(state): GameModule.Result?
	if not state.finished then
		return nil
	end
	local best = -math.huge
	for seat = 1, state.seatCount do
		best = math.max(best, state.scores[seat])
	end
	local winners = {}
	for seat = 1, state.seatCount do
		if state.scores[seat] == best then
			table.insert(winners, seat)
		end
	end
	return {
		winners = winners,
		isDraw = #winners == state.seatCount,
		reason = `{state.reason}. Top score: {best} points`,
	}
end

function WordTiles.getScores(state): { [number]: number }
	return table.clone(state.scores)
end

function WordTiles.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		info[seat] = `{state.scores[seat]} pts · {#state.racks[seat]} tiles`
	end
	return info
end

-- Tiles you can't see yet (in the bag or on other racks), like Woogles' unseen-tiles
-- list: the board's full set minus the letters on the board and on your rack. Board rows
-- use upper case for blanks. Returns { [letter or "?"] = count }.
function WordTiles.unseen(boardKey: string, rows: { string }, rack: { string }?): { [string]: number }
	local def = WordTiles.boards[boardKey]
	local left = table.clone(def and def.bag or {})
	local function take(letter: string)
		if (left[letter] or 0) > 0 then
			left[letter] -= 1
		end
	end
	for _, row in rows do
		for i = 1, #row do
			local ch = string.sub(row, i, i)
			if string.match(ch, "%l") then
				take(ch)
			elseif string.match(ch, "%u") then
				take("?")
			end
		end
	end
	for _, letter in rack or {} do
		take(letter)
	end
	return left
end

function WordTiles.getView(state, seat: number?)
	local counts = {}
	for s = 1, state.seatCount do
		counts[s] = #state.racks[s]
	end
	return {
		board = state.boardKey,
		rows = rowsOf(state.board, state.size),
		rack = if seat and state.racks[seat] then table.clone(state.racks[seat]) else nil,
		rackCounts = counts,
		bagCount = #state.bag,
		scores = table.clone(state.scores),
		canExchange = #state.bag >= EXCHANGE_MIN_BAG,
		lastPlay = GameModule.copy(state.lastPlay),
		log = GameModule.copy(state.log),
		-- Your own hindsight only: it is made from your rack.
		hindsight = if seat then GameModule.copy(state.hindsight[seat]) else nil,
		biggestMiss = if seat and state.finished then GameModule.copy(state.biggestMiss[seat]) else nil,
	}
end

function WordTiles.getBotDelay(_state, _seat: number, rng: Random): number
	return 1.8 + rng:NextNumber() * 1.5
end

-- Bot ----------------------------------------------------------------------------------
--
-- Finds every placement the rack can make with the classic anchor-square method (Appel &
-- Jacobson, 1988): for each empty square next to a tile, build words through it letter by
-- letter while walking the dictionary trie, so only real words are ever tried. Crossing
-- words are handled with precomputed "which letters fit here" masks.
--   easy:   a random lower-scoring play, short words preferred
--   medium: words of 6 letters or fewer, never all 7 tiles, picked from the top 8-30% of what it finds
--   hard:   best score plus a bonus for keeping a good rack (blanks, an S, no clunky Q)

local ALL_LETTERS = 2 ^ 26 - 1
local SEARCH_BUDGET = 250000 -- extend steps per direction; keeps one turn's thinking bounded
local MAX_STORED = 5000

local LETTER_OF = {}
for i = 1, 26 do
	LETTER_OF[i] = string.char(96 + i)
end
local VALUE_OF = {}
for i = 1, 26 do
	VALUE_OF[i] = VALUES[LETTER_OF[i]]
end
local VOWEL = { [1] = true, [5] = true, [9] = true, [15] = true, [21] = true }

local function leaveValue(counts: { number }, blanks: number): number
	local value = blanks * 7
	local vowels, total = 0, 0
	for l = 1, 26 do
		local n = counts[l]
		if n > 0 then
			total += n
			if VOWEL[l] then
				vowels += n
			end
			if n > 1 then
				value -= (n - 1) * 2.5
			end
		end
	end
	if counts[19] > 0 then
		value += 3 -- an S
	end
	if counts[17] > 0 and counts[21] == 0 then
		value -= 6 -- a Q with no U
	end
	total += blanks
	if total > 0 then
		value -= math.abs(vowels - total * 0.4) * 1.5
	end
	return value
end

-- Every placement for `rack` on `state.board`. Returns a list of { score, leave, tiles, length }.
local function findPlays(state, rack: { string }, dict: WordTrie.Trie): { any }
	local size = state.size
	local board = state.board
	local premium = state.premium
	local mid = (size + 1) // 2
	local empty = board[mid][mid] == nil

	local counts = table.create(26, 0)
	local blanks = 0
	for _, letter in rack do
		if letter == "?" then
			blanks += 1
		else
			local l = string.byte(letter) - 96
			counts[l] += 1
		end
	end

	local plays = {}
	local bestIndex = 0
	local bagEmpty = #state.bag == 0

	-- dir 1 = across (line = row), dir 2 = down (line = column).
	for dir = 1, 2 do
		-- Line view of the board: A[i][j] letter 1..26 (0 empty), B[i][j] true if a blank.
		local A, B, P = {}, {}, {}
		for i = 1, size do
			A[i], B[i], P[i] = table.create(size, 0), {}, {}
			for j = 1, size do
				local r, c = if dir == 1 then i else j, if dir == 1 then j else i
				local ch = board[r][c]
				if ch then
					local lower = string.lower(ch)
					A[i][j] = string.byte(lower) - 96
					B[i][j] = ch ~= lower
				end
				P[i][j] = premium[r][c]
			end
		end

		-- Cross checks: which letters can go in each empty square without breaking the
		-- word that crosses it, and how much that crossing word is worth.
		local mask, crossSum, anchor = {}, {}, {}
		for i = 1, size do
			mask[i], crossSum[i], anchor[i] = table.create(size, ALL_LETTERS), table.create(size, -1), {}
			for j = 1, size do
				if A[i][j] == 0 then
					local up, down = i - 1, i + 1
					while up >= 1 and A[up][j] ~= 0 do
						up -= 1
					end
					while down <= size and A[down][j] ~= 0 do
						down += 1
					end
					if up < i - 1 or down > i + 1 then
						local sum = 0
						local node = WordTrie.ROOT
						for k = up + 1, i - 1 do
							if not B[k][j] then
								sum += VALUE_OF[A[k][j]]
							end
							if node ~= 0 then
								node = dict:child(node, A[k][j])
							end
						end
						for k = i + 1, down - 1 do
							if not B[k][j] then
								sum += VALUE_OF[A[k][j]]
							end
						end
						local m = 0
						if node ~= 0 then
							local child = dict:firstChild(node)
							while child ~= 0 do
								local n = child
								for k = i + 1, down - 1 do
									n = dict:child(n, A[k][j])
									if n == 0 then
										break
									end
								end
								if n ~= 0 and dict:isTerminal(n) then
									m = bit32.bor(m, bit32.lshift(1, dict:letterOf(child) - 1))
								end
								child = dict:nextSibling(child)
							end
						end
						mask[i][j] = m
						crossSum[i][j] = sum
					end
					if empty then
						anchor[i][j] = i == mid and j == mid
					else
						anchor[i][j] = (i > 1 and A[i - 1][j] ~= 0)
							or (i < size and A[i + 1][j] ~= 0)
							or (j > 1 and A[i][j - 1] ~= 0)
							or (j < size and A[i][j + 1] ~= 0)
					end
				end
			end
		end

		-- The word being built: stack[k] is the letter at position start + k - 1.
		local stackLetter, stackBlank, stackNew = {}, {}, {}
		local depth, newCount = 0, 0
		local steps = 0
		local line = 0

		local function record(start: number)
			local mainSum, wordMult, cross = 0, 1, 0
			local tiles = {}
			for k = 1, depth do
				local j = start + k - 1
				local l = stackLetter[k]
				local value = if stackBlank[k] then 0 else VALUE_OF[l]
				if stackNew[k] then
					local p = P[line][j]
					local lm = LETTER_MULT[p] or 1
					local wm = WORD_MULT[p] or 1
					mainSum += value * lm
					wordMult *= wm
					if crossSum[line][j] >= 0 then
						cross += (crossSum[line][j] + value * lm) * wm
					end
					table.insert(tiles, {
						row = if dir == 1 then line else j,
						col = if dir == 1 then j else line,
						letter = LETTER_OF[l],
						blank = stackBlank[k],
					})
				else
					mainSum += value
				end
			end
			local score = mainSum * wordMult + cross + (if newCount == RACK_SIZE then BINGO_BONUS else 0)
			local leave = if bagEmpty then 0 else leaveValue(counts, blanks)
			local play = { score = score, leave = leave, tiles = tiles, length = depth }
			if #plays < MAX_STORED then
				table.insert(plays, play)
				if bestIndex == 0 or score + leave > plays[bestIndex].score + plays[bestIndex].leave then
					bestIndex = #plays
				end
			elseif score + leave > plays[bestIndex].score + plays[bestIndex].leave then
				plays[bestIndex] = play
			end
		end

		local function push(l: number, isBlank: boolean, isNew: boolean)
			depth += 1
			stackLetter[depth], stackBlank[depth], stackNew[depth] = l, isBlank, isNew
			if isNew then
				newCount += 1
			end
		end
		local function pop()
			if stackNew[depth] then
				newCount -= 1
			end
			depth -= 1
		end

		local function extendRight(node: number, pos: number, start: number, anchorPos: number)
			steps += 1
			if steps > SEARCH_BUDGET then
				return
			end
			if pos > size or A[line][pos] == 0 then
				if pos > anchorPos and newCount > 0 and dict:isTerminal(node) then
					record(start)
				end
				if pos > size then
					return
				end
				local allowed = mask[line][pos]
				local child = dict:firstChild(node)
				while child ~= 0 do
					local l = dict:letterOf(child)
					if bit32.btest(allowed, bit32.lshift(1, l - 1)) then
						if counts[l] > 0 then
							counts[l] -= 1
							push(l, false, true)
							extendRight(child, pos + 1, start, anchorPos)
							pop()
							counts[l] += 1
						elseif blanks > 0 then
							blanks -= 1
							push(l, true, true)
							extendRight(child, pos + 1, start, anchorPos)
							pop()
							blanks += 1
						end
					end
					child = dict:nextSibling(child)
				end
			else
				local l = A[line][pos]
				local child = dict:child(node, l)
				if child ~= 0 then
					push(l, B[line][pos] == true, false)
					extendRight(child, pos + 1, start, anchorPos)
					pop()
				end
			end
		end

		local function leftPart(node: number, limit: number, anchorPos: number)
			extendRight(node, anchorPos, anchorPos - depth, anchorPos)
			if limit <= 0 then
				return
			end
			local child = dict:firstChild(node)
			while child ~= 0 do
				local l = dict:letterOf(child)
				if counts[l] > 0 then
					counts[l] -= 1
					push(l, false, true)
					leftPart(child, limit - 1, anchorPos)
					pop()
					counts[l] += 1
				elseif blanks > 0 then
					blanks -= 1
					push(l, true, true)
					leftPart(child, limit - 1, anchorPos)
					pop()
					blanks += 1
				end
				child = dict:nextSibling(child)
			end
		end

		for i = 1, size do
			line = i
			for j = 1, size do
				if anchor[i][j] then
					depth, newCount = 0, 0
					if j > 1 and A[i][j - 1] ~= 0 then
						-- Tiles already to the left are a fixed start of the word.
						local start = j - 1
						while start > 1 and A[i][start - 1] ~= 0 do
							start -= 1
						end
						local node = WordTrie.ROOT
						for k = start, j - 1 do
							node = dict:child(node, A[i][k])
							if node == 0 then
								break
							end
							push(A[i][k], B[i][k] == true, false)
						end
						if node ~= 0 then
							extendRight(node, j, start, j)
						end
					else
						local limit = 0
						local k = j - 1
						while k >= 1 and A[i][k] == 0 and not anchor[i][k] do
							limit += 1
							k -= 1
						end
						leftPart(WordTrie.ROOT, math.min(limit, RACK_SIZE - 1), j)
					end
				end
			end
		end
		if empty then
			break -- the board is symmetric, so across covers every opening play
		end
	end

	return plays
end
WordTiles._findPlays = findPlays -- for tests

-- Before a play lands: what was the highest-scoring play on that rack? Saved for the
-- player (view.hindsight) and kept if it's the most they left on the table all game.
function WordTiles._hindsight(state, seat: number, result: any)
	local dict = getDictionary()
	if state.bots[seat] or not dict then
		return
	end
	local best = nil
	for _, play in findPlays(state, state.racks[seat], dict) do
		if best == nil or play.score > best.score then
			best = play
		end
	end
	if best == nil or best.score <= result.score then
		state.hindsight[seat] = { best = true, played = result.score, turn = state.turns + 1 }
		return
	end
	local found = WordTiles.evaluate(state.board, state.premium, best.tiles)
	local word = if found and found.words[1] then string.upper(found.words[1].word) else "?"
	local cells = {}
	for _, t in best.tiles do
		table.insert(cells, { t.row, t.col })
	end
	local entry = { word = word, score = best.score, played = result.score, cells = cells, turn = state.turns + 1 }
	state.hindsight[seat] = entry
	local miss = state.biggestMiss[seat]
	if miss == nil or entry.score - entry.played > miss.score - miss.played then
		state.biggestMiss[seat] = entry
	end
end

-- Swaps the clunky tiles (keeps blanks and one S).
local function exchangeMove(rack: { string })
	local letters = {}
	local keptS = false
	for _, letter in rack do
		if letter == "?" or (letter == "s" and not keptS) then
			keptS = keptS or letter == "s"
		else
			table.insert(letters, letter)
		end
	end
	if #letters == 0 then
		letters = { rack[1] }
	end
	return { kind = "exchange", letters = letters }
end

function WordTiles.chooseBotMove(state, seat: number, rng: Random)
	local dict = getDictionary()
	if state.finished or seat ~= state.turn or not dict then
		return { kind = "pass" }
	end
	local rack = state.racks[seat]
	local plays = findPlays(state, rack, dict)
	if #plays == 0 then
		if #state.bag >= EXCHANGE_MIN_BAG then
			return exchangeMove(rack)
		end
		return { kind = "pass" }
	end

	local level = state.botLevel
	local choice
	if level == "easy" then
		table.sort(plays, function(a, b)
			return a.score < b.score
		end)
		local pool = {}
		local cut = math.max(1, math.ceil(#plays * 0.6))
		for k = 1, cut do
			if plays[k].length <= 5 then
				table.insert(pool, plays[k])
			end
		end
		if #pool == 0 then
			for k = 1, cut do
				table.insert(pool, plays[k])
			end
		end
		choice = pool[rng:NextInteger(1, #pool)]
	elseif level == "hard" then
		choice = plays[1]
		for _, play in plays do
			if play.score + play.leave > choice.score + choice.leave then
				choice = play
			end
		end
	else
		-- A decent casual player: everyday-length words (up to 6 letters, never all 7
		-- tiles), and a solid play rather than the very best one.
		local pool = {}
		for _, play in plays do
			if play.length <= 6 and #play.tiles < RACK_SIZE then
				table.insert(pool, play)
			end
		end
		if #pool == 0 then
			pool = plays
		end
		table.sort(pool, function(a, b)
			return a.score > b.score
		end)
		local from = math.max(1, math.ceil(#pool * 0.08))
		local to = math.max(from, math.ceil(#pool * 0.3))
		choice = pool[rng:NextInteger(from, to)]
	end
	return { kind = "place", tiles = choice.tiles }
end

return WordTiles
