local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameClock = require(ReplicatedStorage.Shared.GameClock)
local Chess = require(ReplicatedStorage.Shared.Games.Chess)
local Checkers = require(ReplicatedStorage.Shared.Games.Checkers)

return function(T)
	T.test("time controls parse; casual and junk mean no clock", function()
		local base, inc = GameClock.parse("3+2")
		T.eq(base, 180)
		T.eq(inc, 2)
		T.eq(GameClock.new("casual"), nil)
		T.eq(GameClock.new("0+5"), nil, "no zero-minute clocks")
		T.eq(GameClock.new("999+0"), nil, "an hour at most")
		T.eq(GameClock.new(42), nil)
		for _, choice in GameClock.Choices do
			if choice.value ~= "casual" then
				T.ok(GameClock.new(choice.value), choice.value)
			end
		end
	end)

	T.test("each side's bank runs only on its turn and gets the increment", function()
		local clock = GameClock.new("3+2") :: GameClock.Clock
		T.eq(GameClock.timer(clock, 0, 1), nil, "no clock before both sides have moved")
		T.eq(GameClock.onMove(clock, 1, 100, 0), false)
		T.eq(GameClock.onMove(clock, 2, 130, 1), false)
		T.eq(clock.bank[2], 180, "the first moves are free")
		T.eq(GameClock.onMove(clock, 1, 140, 2), false)
		T.eq(clock.bank[1], 180 - 10 + 2)
		local timer = GameClock.timer(clock, 3, 2) :: any
		T.eq(timer.seconds, 180)
		T.eq(timer.id, 100003)
		T.eq(GameClock.onMove(clock, 2, 400, 3), true, "took 260 s with 180 left: flagged")
		T.eq(clock.bank[2], 0)
	end)

	T.test("offers settle the clock, and an unanswered offer is turned down", function()
		local clock = GameClock.new("1+0") :: GameClock.Clock
		GameClock.onMove(clock, 1, 0, 0)
		GameClock.onMove(clock, 2, 0, 1)
		T.eq(GameClock.settle(clock, 1, 15, 2), false)
		T.eq(clock.bank[1], 45)
		local timer = GameClock.timer(clock, 2, 1, true) :: any
		T.eq(timer.seconds, GameClock.OFFER_WAIT)
		T.eq(timer.id, 200002, "the offer clock has its own id")
		T.eq(GameClock.offerTimedOut(clock, 1), "decline")
		T.eq(clock.bank[1], 45 - GameClock.OFFER_WAIT)
		T.eq(clock.lastAt, 15 + GameClock.OFFER_WAIT)
		clock.bank[1] = 5
		T.eq(GameClock.offerTimedOut(clock, 1), "flag", "the bank ran out before the offer clock")
	end)

	T.test("clock text", function()
		T.eq(GameClock.format(245), "4:05")
		T.eq(GameClock.format(9.44), "0:09.4")
		T.eq(GameClock.format(-3), "0:00.0")
		T.eq(GameClock.format(600), "10:00")
	end)

	local function chessMove(state, seat, from, to, at)
		local move = { from = from, to = to, at = at }
		assert(Chess.validateMove(state, seat, move))
		Chess.applyMove(state, seat, move)
	end

	T.test("chess: out of time loses, and the timer follows the side to move", function()
		local s = Chess.new(2, { rules = { timeControl = "1+0" } })
		T.ok(Chess.clock, "Match stamps the moves")
		chessMove(s, 1, "e2", "e4", 0)
		T.eq(Chess.getTimer(s), nil, "the turn timer runs until both have moved")
		chessMove(s, 2, "e7", "e5", 5)
		local timer = Chess.getTimer(s) :: any
		T.eq(timer.seconds, 60)
		local view = Chess.getView(s, 1)
		T.eq(view.clock.running, 1)
		T.eq(view.clock.bank[1], 60)
		Chess.onTimeout(s)
		local result = Chess.getResult(s) :: any
		T.eq(result.winners[1], 2)
		T.eq(result.reason, "Time out")
	end)

	T.test("chess: a move after the flag fell loses, a draw if the winner can't mate", function()
		local s = Chess.new(2, { rules = { timeControl = "1+0" } })
		chessMove(s, 1, "e2", "e4", 0)
		chessMove(s, 2, "e7", "e5", 1)
		chessMove(s, 1, "g1", "f3", 70)
		T.eq((Chess.getResult(s) :: any).winners[1], 2, "White took 69 s of 60")

		local k = Chess.new(2, { fen = "4k3/8/8/8/8/8/8/R3K3 w - - 0 1", rules = { timeControl = "1+0" } })
		chessMove(k, 1, "a1", "a2", 0)
		chessMove(k, 2, "e8", "d8", 1)
		Chess.onTimeout(k) -- White flags, but Black has a lone king
		local result = Chess.getResult(k) :: any
		T.ok(result.isDraw)
		T.eq(result.reason, "Time out, but no mating material")
	end)

	T.test("chess: an unanswered draw offer is declined, not a flag", function()
		local s = Chess.new(2, { rules = { timeControl = "5+0" } })
		chessMove(s, 1, "e2", "e4", 0)
		chessMove(s, 2, "e7", "e5", 1)
		local offer = { type = "offer", kind = "draw", at = 11 }
		assert(Chess.validateMove(s, 1, offer))
		Chess.applyMove(s, 1, offer)
		T.eq(s.clock.bank[1], 290, "the offer settled White's time")
		T.eq((Chess.getTimer(s) :: any).id, 200002)
		Chess.onTimeout(s)
		T.eq(Chess.getResult(s), nil)
		T.eq(s.offer, nil, "turned down")
		T.eq((Chess.getTimer(s) :: any).id, 100002, "back to White's own clock")
		T.eq(s.clock.bank[1], 290 - GameClock.OFFER_WAIT)
	end)

	T.test("checkers: out of time loses", function()
		local s = Checkers.new(2, { rules = { timeControl = "3+2" } })
		T.ok(Checkers.clock)
		for i = 1, 2 do
			local seat = Checkers.getActiveSeats(s)[1]
			local move = table.clone(Checkers.getLegalMoves(s, seat)[1])
			move.at = i
			assert(Checkers.validateMove(s, seat, move))
			Checkers.applyMove(s, seat, move)
		end
		local timer = Checkers.getTimer(s) :: any
		T.eq(timer.seconds, 180)
		local loser = Checkers.getActiveSeats(s)[1]
		Checkers.onTimeout(s)
		local result = Checkers.getResult(s) :: any
		T.eq(result.winners[1], 3 - loser)
		T.ok(Checkers.getView(s, 1).clock, "the view carries both clocks")
	end)

	T.test("casual games have no clock", function()
		T.eq(Chess.getTimer(Chess.new(2)), nil)
		T.eq(Chess.getView(Chess.new(2), 1).clock, nil)
		T.eq(Checkers.getTimer(Checkers.new(2)), nil)
	end)
end
