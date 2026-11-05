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

	T.test("a draw offer goes with a move; the other side accepts or moves on", function()
		local s = Chess.new(2)
		T.eq((Chess.validateMove(s, 1, { from = "e2", to = "e4", offerDraw = "yes" })), false)
		Chess.applyMove(s, 1, { from = "e2", to = "e4", offerDraw = true })
		T.eq(Chess.getView(s, 2).drawOffer, 1)
		T.eq((Chess.validateMove(s, 1, { kind = "acceptDraw" })), false, "not your own offer")
		T.ok(Chess.validateMove(s, 2, { kind = "acceptDraw" }))
		T.eq(Chess.getLegalMoves(s, 2)[1].kind, "acceptDraw")
		-- Moving on declines it, and you can't offer again straight away.
		Chess.applyMove(s, 2, { from = "e7", to = "e5" })
		T.eq(s.drawOffer, nil)
		T.eq(s.drawDeclined, 1)
		T.eq((Chess.validateMove(s, 1, { kind = "acceptDraw" })), false)
		T.eq((Chess.validateMove(s, 1, { from = "g1", to = "f3", offerDraw = true })), false, "too soon")
		T.eq(Chess.getView(s, 1).canOfferDraw, false)

		local t = Chess.new(2)
		Chess.applyMove(t, 1, { from = "e2", to = "e4", offerDraw = true })
		Chess.applyMove(t, 2, { kind = "acceptDraw" })
		local result = Chess.getResult(t) :: any
		T.ok(result.isDraw)
		T.eq(result.reason, "Draw agreed")
	end)

	T.test("a losing bot takes a draw, a winning one plays on", function()
		local losing = Chess.new(2, { fen = "4k3/8/8/8/8/8/8/QQ2K3 w - - 0 1" })
		Chess.applyMove(losing, 1, { from = "e1", to = "f2", offerDraw = true })
		T.eq(Chess.chooseBotMove(losing, 2, T.Random.new(1)).kind, "acceptDraw")
		local winning = Chess.new(2, { fen = "qq2k3/8/8/8/8/8/8/4K3 w - - 0 1" })
		Chess.applyMove(winning, 1, { from = "e1", to = "f2", offerDraw = true })
		T.eq(Chess.chooseBotMove(winning, 2, T.Random.new(1)).kind, nil)
	end)

	T.test("view hides nothing but only lists moves for the side to move", function()
		local s = Chess.new(2)
		T.eq(#Chess.getView(s, 1).legalMoves, 20)
		T.eq(Chess.getView(s, 2).legalMoves, nil)
		T.eq(Chess.getView(s, 1).board[1], Chess.Pieces.ROOK, "a1 is a white rook")
	end)
end
