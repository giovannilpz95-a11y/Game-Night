local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Match = require(ServerScriptService.Server.Core.Match)
local TicTacToe = require(ReplicatedStorage.Shared.Games.TicTacToe)

return function(T)
	local function newMatch(seed)
		return Match.new("m1", TicTacToe, {
			{ kind = "player", userId = 10, name = "Gio" },
			{ kind = "bot", name = "Bot Ava" },
		}, nil, T.Random.new(seed or 1))
	end

	T.test("players can only move on their turn", function()
		local m = newMatch()
		T.eq((m:submitMove(2, { cell = 1 })), false)
		T.ok(m:submitMove(1, { cell = 1 }))
		T.eq(m.moveNumber, 1)
		T.ok(m:isSeatActive(2))
	end)

	T.test("bot plays its turn", function()
		local m = newMatch()
		m:submitMove(1, { cell = 1 })
		T.ok(m:playForSeat(2))
		T.ok(m:isSeatActive(1))
		T.eq((m:playForSeat(2)), false, "not the bot's turn anymore")
	end)

	T.test("a full game against a bot ends with a result", function()
		local m = newMatch(7)
		local guard = 0
		while not m:isOver() do
			local seat = m:getActiveSeats()[1]
			T.ok(m:playForSeat(seat))
			guard += 1
			T.ok(guard <= 9)
		end
		T.ok(m.result ~= nil)
		T.eq(#m:getActiveSeats(), 0)
		T.eq((m:submitMove(1, { cell = 1 })), false, "no moves after the end")
	end)

	T.test("leaving player is replaced by a bot", function()
		local m = newMatch()
		T.eq(m:humanCount(), 1)
		m:replaceWithBot(1)
		T.eq(m:humanCount(), 0)
		T.ok(m:isBot(1))
		T.eq(m:seatOf(10), nil)
	end)

	T.test("snapshot shows seats and whose turn it is", function()
		local m = newMatch()
		local snap = m:getSnapshot(1)
		T.eq(snap.yourSeat, 1)
		T.eq(snap.seats[2].kind, "bot")
		T.eq(snap.activeSeats[1], 1)
		T.eq(snap.view.board[5], 0)
		-- The view is a copy: editing it must not change the real game.
		snap.view.board[5] = 2
		T.eq(m.state.board[5], 0)
	end)

	T.test("resigning gives the other seat the win", function()
		local m = newMatch()
		T.ok(m:resign(1))
		T.eq(m.result.winners[1], 2)
		T.eq(m.result.reason, "Gio resigned")
		T.eq((m:resign(2)), false, "already over")
	end)

	T.test("abort ends the match with no result", function()
		local m = newMatch()
		m:abort()
		T.ok(m:isOver())
		T.eq(m.result, nil)
	end)
end
