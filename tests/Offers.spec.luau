local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Chess = require(ReplicatedStorage.Shared.Games.Chess)
local Checkers = require(ReplicatedStorage.Shared.Games.Checkers)

local function play(rules, state, seat, move)
	local ok, err = rules.validateMove(state, seat, move)
	assert(ok, err)
	rules.applyMove(state, seat, move)
end

return function(T)
	T.test("chess takeback undoes both moves and gives the turn back", function()
		local state = Chess.new(2)
		local start = Chess.toFen(state.pos)
		play(Chess, state, 1, { from = "e2", to = "e4" })
		play(Chess, state, 2, { from = "d7", to = "d5" })
		play(Chess, state, 1, { from = "e4", to = "d5" })
		play(Chess, state, 2, { from = "d8", to = "d5" })
		T.eq(#state.captured[1], 1)
		-- White asks; only Black can act until they answer.
		T.ok(Chess.validateMove(state, 1, { type = "offer", kind = "takeback" }))
		play(Chess, state, 1, { type = "offer", kind = "takeback" })
		T.eq(Chess.getActiveSeats(state)[1], 2)
		T.eq(Chess.validateMove(state, 1, { from = "b1", to = "c3" }), false)
		T.eq(Chess.getView(state, 2).ask.choices[1].label, "Accept")
		play(Chess, state, 2, { type = "answer", accept = true })
		T.eq(Chess.getActiveSeats(state)[1], 1)
		T.eq(#state.moveList, 2)
		T.eq(#state.captured[1], 0)
		T.eq(state.takebacks[1], 2)
		T.eq(state.lastMove.to, "d5")
		-- Back to the start twice more is a real position again, not a repetition.
		play(Chess, state, 1, { type = "offer", kind = "takeback" })
		play(Chess, state, 2, { type = "answer", accept = true })
		T.eq(Chess.toFen(state.pos), start)
	end)

	T.test("chess draw offer: decline, can't re-ask until a move, accept ends the game", function()
		local state = Chess.new(2)
		play(Chess, state, 1, { from = "e2", to = "e4" })
		play(Chess, state, 2, { from = "e7", to = "e5" })
		play(Chess, state, 1, { type = "offer", kind = "draw" })
		play(Chess, state, 2, { type = "answer", accept = false })
		T.eq(Chess.getActiveSeats(state)[1], 1)
		T.eq(Chess.validateMove(state, 1, { type = "offer", kind = "draw" }), false)
		T.eq(#Chess.getView(state, 1).menuActions, 1) -- takeback only
		play(Chess, state, 1, { from = "g1", to = "f3" })
		play(Chess, state, 2, { type = "offer", kind = "draw" })
		play(Chess, state, 1, { type = "answer", accept = true })
		local result = Chess.getResult(state)
		T.ok(result and result.isDraw)
		T.eq(result.reason, "Draw agreed")
	end)

	T.test("chess bots answer offers", function()
		local state = Chess.new(2, { botLevel = "easy" })
		play(Chess, state, 1, { from = "e2", to = "e4" })
		play(Chess, state, 2, { from = "e7", to = "e5" })
		play(Chess, state, 1, { type = "offer", kind = "takeback" })
		local answer = Chess.chooseBotMove(state, 2, Random.new(1))
		T.eq(answer.type, "answer")
		T.eq(answer.accept, true)
		T.ok(Chess.validateMove(state, 2, answer))
	end)

	T.test("chess premoves include recaptures onto your own pieces", function()
		local state = Chess.new(2)
		play(Chess, state, 1, { from = "e2", to = "e4" })
		play(Chess, state, 2, { from = "d7", to = "d5" })
		-- White is on move; Black may queue ...Qxd5 as if White had taken there.
		local found = false
		for _, m in Chess.premoves(Chess.toFen(state.pos), 2) do
			if m.from == "d8" and m.to == "d5" then
				found = true
			end
		end
		T.ok(found, "Qd8-d5 premove")
	end)

	T.test("chess view lists past positions for the move list", function()
		local state = Chess.new(2)
		play(Chess, state, 1, { from = "e2", to = "e4" })
		play(Chess, state, 2, { from = "e7", to = "e5" })
		local view = Chess.getView(state, 1)
		T.eq(#view.past, 2)
		T.eq(view.past[1].to, "e4")
		T.eq(view.past[2].fen, view.fen)
		T.eq(view.startFen, Chess.START_FEN)
	end)

	T.test("checkers takeback restores the board", function()
		local state = Checkers.new(2)
		local before = Checkers.getView(state, 1).board
		local a = Checkers.getLegalMoves(state, 1)[1]
		play(Checkers, state, 1, a)
		local b = Checkers.getLegalMoves(state, 2)[1]
		play(Checkers, state, 2, b)
		play(Checkers, state, 1, { type = "offer", kind = "takeback" })
		T.eq(Checkers.getActiveSeats(state)[1], 2)
		play(Checkers, state, 2, { type = "answer", accept = true })
		T.eq(state.turn, 1)
		local after = Checkers.getView(state, 1)
		for r = 1, 8 do
			for c = 1, 8 do
				T.eq(after.board[r][c], before[r][c])
			end
		end
		T.eq(after.undo, nil)
		T.eq(after.takebacksLeft, 2)
	end)
end
