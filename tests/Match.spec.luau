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

	T.test("interrupt seats may move out of turn (Color Clash jump-in)", function()
		local ColorClash = require(ReplicatedStorage.Shared.Games.ColorClash)
		local m = Match.new("m2", ColorClash, {
			{ kind = "player", userId = 10, name = "Gio" },
			{ kind = "player", userId = 11, name = "Sam" },
			{ kind = "bot", name = "Bot Ava" },
		}, { rules = { jumpIn = true } }, T.Random.new(3))
		local s = m.state
		local cards = ColorClash.cards
		local a, b
		for id, card in cards do
			if card.color == 2 and card.value == 4 then
				if a then
					b = id
					break
				end
				a = id
			end
		end
		s.discard = { a }
		s.color = 2
		s.turn = 1
		table.insert(s.hands[2], b)
		T.eq((m:submitMove(2, { kind = "draw" })), false, "still not their turn for anything else")
		T.ok(m:canMove(2))
		T.ok(m:submitMove(2, { kind = "jump", card = b }))
		T.eq(s.turn, 3)
		T.eq((m:playForSeat(1)), false, "seat 1 has nothing to jump with")
	end)

	T.test("an away player's clock turns down draw and takeback offers", function()
		for _, name in { "Checkers", "Chess" } do
			local rules = require(ReplicatedStorage.Shared.Games[name])
			for _, kind in { "draw", "takeback" } do
				local m = Match.new("m-" .. name, rules, {
					{ kind = "player", userId = 10, name = "Gio" },
					{ kind = "player", userId = 11, name = "Sam" },
				}, nil, T.Random.new(5))
				-- Two moves each so offers are allowed.
				for _ = 1, 4 do
					local seat = m:getActiveSeats()[1]
					local played = false
					for _, move in rules.getLegalMoves(m.state, seat) do
						if type(move) == "table" and move.type ~= "offer" and m:submitMove(seat, move) then
							played = true
							break
						end
					end
					T.ok(played, `{name}: a normal move`)
				end
				local asker = m:getActiveSeats()[1]
				T.ok(m:submitMove(asker, { type = "offer", kind = kind }), `{name}: {kind} offered`)
				local moves = m.moveNumber
				T.ok(m:playForSeat(3 - asker), `{name}: the clock answers`)
				T.ok(not m:isOver(), `{name}: an away player never agrees to a draw`)
				T.eq(m.state.offer, nil, `{name}: the offer is closed`)
				T.eq(m.moveNumber, moves + 1, `{name}: {kind} was turned down, no takeback`)
				T.eq(m:getActiveSeats()[1], asker, `{name}: back to the player who asked`)
			end
		end
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
			T.ok(guard <= TicTacToe.maxMoves)
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
