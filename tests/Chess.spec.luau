local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Chess = require(ReplicatedStorage.Shared.Games.Chess)
local GameModule = require(ReplicatedStorage.Shared.GameModule)

return function(T)
	-- Perft: count every legal move sequence to a depth and compare with known totals.
	-- This is the standard way to catch castling, en passant and promotion bugs.
	local PERFT = {
		{ name = "start position", fen = Chess.START_FEN, counts = { 20, 400, 8902 } },
		{
			name = "kiwipete (castling, pins, ep)",
			fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
			counts = { 48, 2039 },
		},
		{ name = "position 3 (ep, checks)", fen = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", counts = { 14, 191, 2812 } },
		{
			name = "position 4 (promotions)",
			fen = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
			counts = { 6, 264, 9467 },
		},
		{
			name = "position 5",
			fen = "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
			counts = { 44, 1486 },
		},
		-- Chess960 positions from the published Chess960 perft tables (Shredder-FEN rights).
		{ name = "chess960 #1", fen = "bqnb1rkr/pp3ppp/3ppn2/2p5/5P2/P2P4/NPP1P1PP/BQ1BNRKR w HFhf - 2 9", counts = { 21, 528, 12189 } },
		{ name = "chess960 #2", fen = "2nnrbkr/p1qppppp/8/1ppb4/6PP/3PP3/PPP2P2/BQNNRBKR w HEhe - 1 9", counts = { 21, 807, 18002 } },
		{ name = "chess960 #3", fen = "b1q1rrkb/pppppppp/3nn3/8/P7/1PPP4/4PPPP/BQNNRKRB w GE - 1 9", counts = { 20, 479, 10471 } },
	}
	for _, case in PERFT do
		T.test(`perft {case.name}`, function()
			local pos = Chess.fromFen(case.fen)
			for depth, expected in case.counts do
				T.eq(Chess.perft(pos, depth), expected, `depth {depth}`)
			end
			T.eq(Chess.toFen(pos), case.fen, "position restored after search")
		end)
	end

	local function play(state, seat, from, to, promotion)
		local move = { from = from, to = to, promotion = promotion }
		local ok, err = Chess.validateMove(state, seat, move)
		assert(ok, `{from}-{to}: {err}`)
		Chess.applyMove(state, seat, move)
	end

	T.test("fool's mate is checkmate for Black", function()
		local s = Chess.new(2)
		play(s, 1, "f2", "f3")
		play(s, 2, "e7", "e5")
		play(s, 1, "g2", "g4")
		play(s, 2, "d8", "h4")
		local result = Chess.getResult(s)
		T.ok(result, "game should be over")
		T.eq(result.winners[1], 2)
		T.eq(result.reason, "Checkmate")
		T.eq(s.moveList[4], "Qh4#")
	end)

	T.test("stalemate is a draw", function()
		local s = Chess.new(2, { fen = "7k/8/6Q1/8/8/8/8/K7 w - - 0 1" })
		play(s, 1, "g6", "f7")
		local result = Chess.getResult(s)
		T.ok(result and result.isDraw, "draw")
		T.eq(result.reason, "Stalemate")
	end)

	T.test("rejects illegal and out-of-turn moves", function()
		local s = Chess.new(2)
		T.eq((Chess.validateMove(s, 2, { from = "e7", to = "e5" })), false, "black can't go first")
		T.eq((Chess.validateMove(s, 1, { from = "e2", to = "e5" })), false, "pawn can't jump 3")
		T.eq((Chess.validateMove(s, 1, { from = "z9", to = "e4" })), false, "bad square")
		T.eq((Chess.validateMove(s, 1, "e4")), false, "not a table")
	end)

	T.test("can't move into check (pinned piece)", function()
		local s = Chess.new(2, { fen = "4k3/4r3/8/8/8/8/4N3/4K3 w - - 0 1" })
		T.eq((Chess.validateMove(s, 1, { from = "e2", to = "c3" })), false)
	end)

	T.test("castling moves the rook and is blocked through check", function()
		local s = Chess.new(2, { fen = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1" })
		play(s, 1, "e1", "g1")
		T.eq(s.pos.board[5], Chess.Pieces.ROOK, "rook on f1")
		T.eq(s.pos.board[7], 0, "h1 empty")
		local blocked = Chess.new(2, { fen = "r3k2r/8/8/8/8/8/5r2/R3K2R w KQkq - 0 1" })
		T.eq((Chess.validateMove(blocked, 1, { from = "e1", to = "g1" })), false, "f-file attacked")
	end)

	T.test("en passant captures the pawn", function()
		local s = Chess.new(2, { fen = "4k3/3p4/8/4P3/8/8/8/4K3 b - - 0 1" })
		play(s, 2, "d7", "d5")
		play(s, 1, "e5", "d6")
		T.eq(s.pos.board[Chess.parseSquare("d5")], 0, "captured pawn removed")
		T.eq(s.moveList[2], "exd6")
	end)

	T.test("promotion defaults to queen and accepts underpromotion", function()
		local s = Chess.new(2, { fen = "4k3/1P6/8/8/8/8/8/4K3 w - - 0 1" })
		play(s, 1, "b7", "b8")
		T.eq(s.pos.board[Chess.parseSquare("b8")], Chess.Pieces.QUEEN)
		local u = Chess.new(2, { fen = "4k3/1P6/8/8/8/8/8/4K3 w - - 0 1" })
		play(u, 1, "b7", "b8", "n")
		T.eq(u.pos.board[Chess.parseSquare("b8")], Chess.Pieces.KNIGHT)
	end)

	T.test("threefold repetition is a draw", function()
		local s = Chess.new(2)
		for _ = 1, 2 do
			play(s, 1, "g1", "f3")
			play(s, 2, "g8", "f6")
			play(s, 1, "f3", "g1")
			play(s, 2, "f6", "g8")
		end
		local result = Chess.getResult(s)
		T.ok(result and result.isDraw, "draw")
		T.eq(result.reason, "Threefold repetition")
	end)

	T.test("king vs king is a draw", function()
		local s = Chess.new(2, { fen = "4k3/8/8/8/8/8/3q4/4K3 w - - 0 1" })
		play(s, 1, "e1", "d2")
		T.eq(Chess.getResult(s).reason, "Not enough pieces to checkmate")
	end)

	T.test("bot finds mate in one", function()
		local s = Chess.new(2, { fen = "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1", botLevel = "medium" })
		local move = Chess.chooseBotMove(s, 1, T.Random.new(3))
		T.eq(move.to, "a8")
	end)

	T.test("bot takes a free queen", function()
		local s = Chess.new(2, { fen = "4k3/8/8/3q4/8/8/8/3RK3 w - - 0 1", botLevel = "hard" })
		local move = Chess.chooseBotMove(s, 1, T.Random.new(3))
		T.eq(move.from .. move.to, "d1d5")
	end)

	T.test("easy bots vs medium bots play legal games to the end", function()
		local rng = T.Random.new(11)
		local s = Chess.new(2, { botLevel = "easy" })
		local plies = 0
		while not Chess.getResult(s) and plies < 60 do
			local seat = Chess.getActiveSeats(s)[1]
			local move = GameModule.chooseBotMove(Chess, s, seat, rng)
			T.ok(Chess.validateMove(s, seat, move), "bot made an illegal move")
			Chess.applyMove(s, seat, move)
			plies += 1
		end
		T.ok(plies > 0)
	end)

	T.test("view hides nothing but only lists moves for the side to move", function()
		local s = Chess.new(2)
		T.eq(#Chess.getView(s, 1).legalMoves, 20)
		T.eq(Chess.getView(s, 2).legalMoves, nil)
		T.eq(Chess.getView(s, 1).board[1], Chess.Pieces.ROOK, "a1 is a white rook")
	end)

	local function playOut(fen: string, level: string, maxPlies: number, seed: number)
		local rng = T.Random.new(seed)
		local s = Chess.new(2, { fen = fen, botLevel = level })
		local plies = 0
		while not Chess.getResult(s) and plies < maxPlies do
			local seat = Chess.getActiveSeats(s)[1]
			local move = GameModule.chooseBotMove(Chess, s, seat, rng)
			T.ok(Chess.validateMove(s, seat, move), "bot made an illegal move")
			Chess.applyMove(s, seat, move)
			plies += 1
		end
		return Chess.getResult(s), plies
	end

	T.test("hard and medium bots mate with king and queen against a king", function()
		for _, case in { { "hard", "8/8/8/4k3/8/8/8/4K2Q w - - 0 1" }, { "medium", "8/8/3k4/8/8/8/8/Q3K3 w - - 0 1" } } do
			local result = playOut(case[2], case[1], 100, 3)
			T.ok(result ~= nil and result.reason == "Checkmate" and result.winners[1] == 1, `{case[1]}: {result and result.reason}`)
		end
	end)

	T.test("the hard bot mates with king and rook against a king", function()
		local result = playOut("8/8/8/3k4/8/8/8/R3K3 w - - 0 1", "hard", 100, 5)
		T.ok(result ~= nil and result.reason == "Checkmate" and result.winners[1] == 1, result and result.reason)
	end)

	T.test("castling can be premoved with pawns in front of the king", function()
		local fen = "r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 4 4"
		local found = false
		for _, m in Chess.premoves(fen, 1) do
			if m.from == "e1" and m.to == "g1" then
				found = true
			end
		end
		T.ok(found, "e1-g1 is offered")
		-- Premoves ignore blockers like Lichess: the a1 rook can queue a1-a8.
		local through = false
		for _, m in Chess.premoves(Chess.START_FEN, 1) do
			if m.from == "a1" and m.to == "a5" then
				through = true
			end
		end
		T.ok(through, "sliders premove through pieces")
	end)

	T.test("promotion must be q, r, b, n or missing", function()
		local s = Chess.new(2, { fen = "8/4P2k/8/8/8/8/8/K7 w - - 0 1" })
		T.eq((Chess.validateMove(s, 1, { from = "e7", to = "e8", promotion = "x" })), false)
		T.eq((Chess.validateMove(s, 1, { from = "e7", to = "e8", promotion = { 1 } })), false)
		T.eq((Chess.validateMove(s, 1, { from = "e7", to = "e8", promotion = "k" })), false)
		T.eq((Chess.validateMove(s, 1, { from = "e7", to = "e8", promotion = "Q" })), false)
		T.eq((Chess.validateMove(s, 1, { from = "e7", to = "e8", promotion = "n" })), true)
		T.eq((Chess.validateMove(s, 1, { from = "e7", to = "e8" })), true)
	end)

	T.test("the material lead counts promotions", function()
		local s = Chess.new(2, { fen = "8/4P2k/8/8/8/8/8/K7 w - - 0 1" })
		Chess.applyMove(s, 1, { from = "e7", to = "e8" })
		local view = Chess.getView(s, 1)
		T.eq(view.lead[1], 9, "a new queen against a bare king")
		T.eq(view.lead[2], 0)
	end)

	T.test("PGN export numbers the moves and adds the result", function()
		local text = Chess.pgn({ "f3", "e5", "g4", "Qh4#" }, nil, "0-1", "Ann", "Bob")
		T.ok(string.find(text, '[White "Ann"]', 1, true) ~= nil)
		T.ok(string.find(text, "1. f3 e5 2. g4 Qh4# 0-1", 1, true) ~= nil, text)
		local fromFen = Chess.pgn({ "Kb7" }, "8/8/8/8/8/8/8/K6k b - - 0 12", "*")
		T.ok(string.find(fromFen, "12... Kb7 *", 1, true) ~= nil, fromFen)
		T.ok(string.find(fromFen, '[SetUp "1"]', 1, true) ~= nil)
	end)
	T.test("chess960 castling: king onto its rook, ends on g/c with the rook on f/d", function()
		local s = Chess.new(2, { fen = "rk2r3/pppppppp/8/8/8/8/PPPPPPPP/RK2R3 w EAea - 0 1" })
		play(s, 1, "b1", "e1") -- O-O: king takes its own rook
		T.eq(s.moveList[1], "O-O")
		T.eq(Chess.toFen(s.pos), "rk2r3/pppppppp/8/8/8/8/PPPPPPPP/R4RK1 b ea - 1 1")
		play(s, 2, "b8", "c8") -- a plain king step, not castling
		T.eq(string.match(Chess.toFen(s.pos), "^%S+"), "r1k1r3/pppppppp/8/8/8/8/PPPPPPPP/R4RK1")
		T.eq(string.match(Chess.toFen(s.pos), " (%S+) %S+ %S+ %S+$"), "-", "the king moved: no rights left")
		local q = Chess.new(2, { fen = "rk2r3/pppppppp/8/8/8/8/PPPPPPPP/RK2R3 w EAea - 0 1" })
		play(q, 1, "b1", "a1") -- O-O-O
		T.eq(q.moveList[1], "O-O-O")
		T.eq(string.match(Chess.toFen(q.pos), "([^/]+) b "), "2KRR3")
		-- The king's end square works too when it isn't also a plain king move.
		local g = Chess.new(2, { fen = "rk2r3/pppppppp/8/8/8/8/PPPPPPPP/RK2R3 w EAea - 0 1" })
		play(g, 1, "b1", "g1")
		T.eq(g.moveList[1], "O-O")
		-- Blocked or attacked paths stop it.
		local blocked = Chess.new(2, { fen = "rk2r3/pppppppp/8/8/8/8/PPPPPPPP/RKN1R3 w EAea - 0 1" })
		T.eq((Chess.validateMove(blocked, 1, { from = "b1", to = "e1" })), false, "c1 is in the way")
		local attacked = Chess.new(2, { fen = "rk4r1/pppppp1p/8/8/8/8/PPPPPP1P/RK2R3 w EAa - 0 1" })
		T.eq((Chess.validateMove(attacked, 1, { from = "b1", to = "e1" })), false, "g1 is attacked by the g8 rook")
		-- Moving a castling rook loses only that side.
		local r = Chess.new(2, { fen = "rk2r3/pppppppp/8/8/8/8/PPPPPPPP/RK2R3 w EAea - 0 1" })
		play(r, 1, "e1", "f1")
		T.eq(string.match(Chess.toFen(r.pos), " (%S+) %S+ %S+ %S+$"), "Aea")
		T.ok(Chess.findLegal(Chess.fromFen(Chess.toFen(r.pos)), { from = "b8", to = "e8" }) ~= nil, "black can still castle")
	end)

	T.test("shuffle start keeps castling rights and both colours can castle", function()
		for seed = 1, 30 do
			local s = Chess.new(2, { rules = { shuffle = true } }, Random.new(seed))
			local fen = Chess.toFen(s.pos)
			local rights = string.match(fen, "^%S+ %S+ (%S+)")
			T.eq(#rights, 4, fen)
			T.eq(rights, string.upper(string.sub(rights, 3, 4)) .. string.sub(rights, 3, 4))
			-- Premoves include the king onto each of its rooks.
			local kingSq = nil
			for sq = 0, 7 do
				if s.pos.board[sq] == 6 then
					kingSq = Chess.squareName(sq)
				end
			end
			local onRook = 0
			for _, m in Chess.premoves(fen, 1) do
				if m.from == kingSq and s.pos.board[Chess.parseSquare(m.to) :: number] == 4 then
					onRook += 1
				end
			end
			T.eq(onRook, 2, fen)
		end
	end)
end
