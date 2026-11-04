local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local WordTiles = require(ReplicatedStorage.Shared.Games.WordTiles)
local WordTrie = require(ReplicatedStorage.Shared.WordTrie)
local GameModule = require(ReplicatedStorage.Shared.GameModule)
local Dictionary = require(ServerScriptService.Server.Core.Dictionary)

local SMALL = WordTrie.fromWords({
	"at", "cat", "cats", "act", "acts", "scat", "ta", "tat", "as", "sat", "ca", "ax", "ox", "tax",
	"taxes", "quiz", "qi", "it", "is", "si", "ti", "tic", "tics", "sic", "zit", "zits", "za",
})

local function rot13(s: string): string
	return (string.gsub(s, "%a", function(ch)
		local b = string.byte(ch) - 97
		return string.char((b + 13) % 26 + 97)
	end))
end

-- A fresh 2-seat quick game with chosen racks and an optional empty bag.
local function setup(racks: { { string } }, emptyBag: boolean?)
	local s = WordTiles.new(2, { botLevel = "hard" }, Random.new(3))
	for seat, rack in racks do
		for _, letter in s.racks[seat] do
			table.insert(s.bag, letter)
		end
		s.racks[seat] = table.clone(rack)
	end
	if emptyBag then
		table.clear(s.bag)
	end
	return s
end

local function tilesOf(row: number, col: number, word: string, down: boolean?)
	local tiles = {}
	for i = 1, #word do
		table.insert(tiles, {
			row = if down then row + i - 1 else row,
			col = if down then col else col + i - 1,
			letter = string.sub(word, i, i),
		})
	end
	return tiles
end

local function place(s, seat: number, tiles)
	local move = { kind = "place", tiles = tiles }
	local ok, err = WordTiles.validateMove(s, seat, move)
	assert(ok, err)
	WordTiles.applyMove(s, seat, move)
	return s.lastPlay
end

local function totalTiles(s): number
	local n = #s.bag
	for _, rack in s.racks do
		n += #rack
	end
	for r = 1, s.size do
		for c = 1, s.size do
			if s.board[r][c] then
				n += 1
			end
		end
	end
	return n
end

return function(T)
	T.test("word trie finds words and only words", function()
		T.ok(SMALL:has("cat") and SMALL:has("CATS") and SMALL:has("qi"), "words")
		T.ok(not SMALL:has("ca t") and not SMALL:has("catz") and not SMALL:has("c") and not SMALL:has(""), "non-words")
		T.eq(SMALL.words, 27)
	end)

	T.test("boards: sizes, symmetric premium squares, bag sizes", function()
		for key, def in WordTiles.boards do
			local size = def.size
			T.eq(#def.premium, size, key)
			for r = 1, size do
				for c = 1, size do
					local p = def.premium[r][c]
					T.eq(def.premium[c][r], p, `{key} transpose {r},{c}`)
					T.eq(def.premium[size + 1 - r][c], p, `{key} mirror {r},{c}`)
				end
			end
			local mid = (size + 1) // 2
			T.eq(def.premium[mid][mid], "*")
		end
		T.eq(#WordTiles.new(2, { board = "quick" }).bag + 14, 60)
		T.eq(#WordTiles.new(4, { board = "classic" }).bag + 28, 100)
		T.eq(WordTiles.new(2, { board = "nonsense" }).size, 11)
	end)

	T.test("first word must cover the center and be one connected line", function()
		WordTiles.useDictionary(SMALL)
		local s = setup({ { "c", "a", "t", "s", "x", "o", "i" }, { "a", "t", "a", "t", "a", "t", "a" } })
		local function rejects(tiles, why)
			T.eq((WordTiles.validateMove(s, 1, { kind = "place", tiles = tiles })), false, why)
		end
		rejects(tilesOf(1, 1, "cat"), "off center")
		rejects({ { row = 6, col = 5, letter = "c" }, { row = 6, col = 7, letter = "t" } }, "gap")
		rejects({ { row = 6, col = 6, letter = "c" }, { row = 7, col = 7, letter = "a" } }, "diagonal")
		rejects(tilesOf(6, 6, "tac"), "not a word")
		rejects(tilesOf(6, 6, "cab"), "no B on the rack")
		rejects({ { row = 6, col = 6, letter = "c" } }, "one letter")
		rejects({ { row = 6, col = 6, letter = "c" }, { row = 6, col = 6, letter = "a" } }, "same square")
		rejects({ { row = 6.5, col = 6, letter = "c" } }, "bad number")
		rejects({ { row = 6, col = 6, letter = "CA" } }, "bad letter")
		T.eq((WordTiles.validateMove(s, 2, { kind = "pass" })), false, "not your turn")
		T.ok(WordTiles.validateMove(s, 1, { kind = "place", tiles = tilesOf(6, 5, "cat") }), "valid")
	end)

	T.test("scores letters, premiums and every crossing word", function()
		WordTiles.useDictionary(SMALL)
		local s = setup({ { "c", "a", "t", "s", "x", "o", "i" }, { "t", "a", "x", "e", "s", "i", "q" } })
		-- CAT across row 6, cols 5-7; the center (6,6) doubles the word. Row 6 cols 5-7 has
		-- a double letter at col 5? Use the layout instead of guessing.
		local premium = s.premium
		local function lm(r, c)
			return ({ L = 3, l = 2 })[premium[r][c]] or 1
		end
		local function wm(r, c)
			return ({ W = 3, w = 2, ["*"] = 2 })[premium[r][c]] or 1
		end
		local play = place(s, 1, tilesOf(6, 5, "cat"))
		local expect = (3 * lm(6, 5) + 1 * lm(6, 6) + 1 * lm(6, 7)) * wm(6, 5) * wm(6, 6) * wm(6, 7)
		T.eq(play.score, expect, "CAT")
		T.eq(s.scores[1], expect)
		T.eq(#s.racks[1], 7, "refilled")
		T.eq(s.turn, 2)

		-- Seat 2 plays TAX down from the T of CAT: T(6,7) A(7,7) X(8,7).
		local tax = place(s, 2, { { row = 7, col = 7, letter = "a" }, { row = 8, col = 7, letter = "x" } })
		local expectTax = (1 + 1 * lm(7, 7) + 8 * lm(8, 7)) * wm(7, 7) * wm(8, 7)
		T.eq(tax.score, expectTax, "TAX")
		T.eq(#tax.words, 1)

		-- Seat 1 adds S to make CATS across, and nothing down (row 7 col 8 empty).
		local cats = place(s, 1, { { row = 6, col = 8, letter = "s" } })
		local expectCats = (3 + 1 + 1 + 1 * lm(6, 8)) * wm(6, 8)
		T.eq(cats.words[1].word, "cats")
		T.eq(cats.score, expectCats, "CATS")

		-- A tile that makes two words scores both: S at (9,7) under TAX makes... TAXS, not a word.
		T.eq((WordTiles.validateMove(s, 2, { kind = "place", tiles = { { row = 9, col = 7, letter = "s" } } })), false)
		-- Tiles that don't touch anything are refused.
		T.eq((WordTiles.validateMove(s, 2, { kind = "place", tiles = tilesOf(1, 1, "ax") })), false)
	end)

	T.test("blank tiles score zero and need a letter", function()
		WordTiles.useDictionary(SMALL)
		local s = setup({ { "q", "?", "a", "a", "a", "a", "a" }, { "a", "a", "a", "a", "a", "a", "a" } })
		local play = place(s, 1, { { row = 6, col = 6, letter = "q" }, { row = 6, col = 7, letter = "i", blank = true } })
		T.eq(s.board[6][7], "I", "blank shown as uppercase")
		local p = s.premium
		local lmQ = ({ L = 3, l = 2 })[p[6][6]] or 1
		T.eq(play.score, 10 * lmQ * 2, "QI with a blank I")
		T.eq(table.find(s.racks[1], "?"), nil, "blank used")
		local view = WordTiles.getView(s, 1)
		T.eq(string.sub(view.rows[6], 6, 7), "qI")
		T.eq(view.rack ~= nil and #view.rack, 7)
		T.eq(WordTiles.getView(s, nil).rack, nil, "spectators see no rack")
		T.eq(WordTiles.boardFromRows(view.rows)[6][7], "I")
	end)

	T.test("using all seven tiles adds the bonus", function()
		WordTiles.useDictionary(WordTrie.fromWords({ "catsitx", "cats" }))
		local s = setup({ { "c", "a", "t", "s", "i", "t", "x" }, { "a", "a", "a", "a", "a", "a", "a" } })
		local play = place(s, 1, tilesOf(6, 3, "catsitx"))
		T.ok(play.bingo, "bingo")
		local raw = 0
		for _, w in play.words do
			raw += w.score
		end
		T.eq(play.score, raw + WordTiles.bingoBonus)
	end)

	T.test("exchanges need enough tiles in the bag and tiles you hold", function()
		WordTiles.useDictionary(SMALL)
		local s = setup({ { "q", "q", "v", "a", "e", "i", "o" }, { "a", "a", "a", "a", "a", "a", "a" } })
		T.eq((WordTiles.validateMove(s, 1, { kind = "exchange", letters = { "z" } })), false)
		T.eq((WordTiles.validateMove(s, 1, { kind = "exchange", letters = { "q", "q", "q" } })), false)
		local before = totalTiles(s)
		local move = { kind = "exchange", letters = { "q", "q", "v" } }
		T.ok(WordTiles.validateMove(s, 1, move), "valid swap")
		WordTiles.applyMove(s, 1, move)
		T.eq(#s.racks[1], 7)
		T.eq(totalTiles(s), before, "no tiles lost")
		T.eq(s.turn, 2)

		while #s.bag >= WordTiles.exchangeMinBag do
			table.remove(s.bag)
		end
		T.eq((WordTiles.validateMove(s, 2, { kind = "exchange", letters = { "a" } })), false, "bag too small")
	end)

	T.test("going out ends the game and collects the other racks", function()
		WordTiles.useDictionary(SMALL)
		local s = setup({ { "c", "a", "t" }, { "q", "z" } }, true)
		place(s, 1, tilesOf(6, 5, "cat"))
		local result = WordTiles.getResult(s)
		T.ok(result, "finished")
		T.eq(result.winners[1], 1)
		T.eq(s.scores[2], -20)
		local cat = s.log[1].score
		T.eq(s.scores[1], cat + 20)
		T.eq(#WordTiles.getActiveSeats(s), 0)
	end)

	T.test("too many scoreless turns end the game", function()
		WordTiles.useDictionary(SMALL)
		local s = setup({ { "a" }, { "e" } }, true)
		for _ = 1, 6 do
			local seat = s.turn
			WordTiles.applyMove(s, seat, { kind = "pass" })
		end
		local result = WordTiles.getResult(s)
		T.ok(result and result.isDraw, "a tie on -1 each")
		T.eq(s.scores[1], -1)
	end)

	T.test("bot plays agree with the referee on every candidate", function()
		WordTiles.useDictionary(SMALL)
		local s = setup({ { "c", "a", "t", "s", "x", "i", "?" }, { "t", "a", "x", "e", "s", "i", "z" } })
		place(s, 1, tilesOf(6, 5, "cat"))
		local plays = WordTiles._findPlays(s, s.racks[2], SMALL)
		T.ok(#plays > 5, `found {#plays} plays`)
		for _, play in plays do
			local ok, err = WordTiles.validateMove(s, 2, { kind = "place", tiles = play.tiles })
			T.ok(ok, err)
			local result = WordTiles.evaluate(s.board, s.premium, play.tiles, function(w)
				return SMALL:has(w)
			end)
			T.eq(result.score, play.score, "bot's score")
		end
	end)

	T.test("full word list loads and leaves out blocked words", function()
		local dict = Dictionary.get()
		T.ok(dict.words > 160000, `{dict.words} words`)
		for _, w in { "cat", "quiz", "zebra", "aa", "jukebox", "class", "grape", "peacock", "therapist" } do
			T.ok(dict:has(w), w)
		end
		for _, coded in { "fuvg", "shpx", "jubers", "chffl" } do
			T.ok(not dict:has(rot13(coded)), "a blocked word got in")
		end
		T.ok(not dict:has("abcdefghijklmnop"), "too long")
	end)

	T.test("bots finish legal games at every level with the full word list", function()
		WordTiles.useDictionary(Dictionary.get)
		for _, setupCase in { { "easy", 2, "quick" }, { "medium", 3, "quick" }, { "hard", 2, "quick" }, { "hard", 2, "classic" } } do
			local rng = T.Random.new(11)
			local s = WordTiles.new(setupCase[2], { botLevel = setupCase[1], board = setupCase[3] }, rng)
			local total = totalTiles(s)
			local placedWords = 0
			while not WordTiles.getResult(s) do
				local seat = WordTiles.getActiveSeats(s)[1]
				local move = GameModule.chooseBotMove(WordTiles, s, seat, rng)
				local ok, err = WordTiles.validateMove(s, seat, move)
				T.ok(ok, `{setupCase[1]} bot made an illegal move: {err}`)
				WordTiles.applyMove(s, seat, move)
				if move.kind == "place" then
					placedWords += 1
				end
				T.eq(totalTiles(s), total, "tiles lost or duplicated")
			end
			T.ok(placedWords >= 8, `{setupCase[1]}/{setupCase[3]}: only {placedWords} plays`)
		end
	end)
end
