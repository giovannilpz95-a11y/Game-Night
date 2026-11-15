-- The safe AFK move (GameModule chooseAfkMove): what the clock plays for a person who
-- isn't there. It must keep the game moving without spending, agreeing or accusing.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Match = require(ServerScriptService.Server.Core.Match)

return function(T)
	-- Seat 1 is an absent person (every move from the AFK clock), the rest are bots.
	-- Returns every move seat 1 made and whether the game finished.
	local function playAway(gameId: string, seats: number, seed: number, maxMoves: number)
		local rules = require(ReplicatedStorage.Shared.Games[gameId])
		local list = { { kind = "player", userId = 10, name = "Gio" } }
		for i = 2, seats do
			table.insert(list, { kind = "bot", name = `Bot {i}` })
		end
		local m = Match.new("afk-" .. gameId, rules, list, { botLevel = "medium" }, T.Random.new(seed))
		local mine = {}
		for _ = 1, maxMoves do
			if m:isOver() then
				break
			end
			local moved = false
			for _, seat in m:getActiveSeats() do
				local before = m.moveNumber
				if m:playForSeat(seat, seat == 1) then
					moved = true
					if seat == 1 and m.lastMove and m.lastMove.number == before + 1 then
						table.insert(mine, m.lastMove.move)
					end
					break
				end
			end
			if not moved then
				-- Phase clocks (auctions, trade answers) run out.
				local timer = m:getTimer()
				if timer and m:timeout(timer.id) then
					moved = true
				end
			end
			if not moved then
				break
			end
		end
		return mine, m
	end

	T.test("Property Party: an away player only rolls, ends, declines and passes", function()
		local allowed = { roll = true, endTurn = true, decline = true, pass = true, reject = true, payDebt = true, sell = true, mortgage = true, bankrupt = true }
		for seed = 1, 4 do
			local mine = playAway("Estates", 3, seed, 3000)
			T.ok(#mine > 10, "the away seat kept playing")
			for _, move in mine do
				T.ok(allowed[move.kind], `never {move.kind} for an absent player`)
			end
		end
	end)

	T.test("Property Party: a trade offered to an away player is turned down", function()
		local Estates = require(ReplicatedStorage.Shared.Games.Estates)
		local s = Estates.new(2, { botLevel = "medium" }, T.Random.new(2))
		s.phase = "trade"
		s.trade = { from = 2, to = 1, give = { props = {}, cash = 500, cards = 0 }, get = { props = {}, cash = 0, cards = 0 } }
		T.eq(Estates.chooseAfkMove(s, 1, T.Random.new(1)).kind, "reject")
	end)

	T.test("Whodunit: the clock never accuses for an away player", function()
		for seed = 1, 6 do
			local mine, m = playAway("Whodunit", 3, seed, 3000)
			T.ok(#mine > 3, "the away seat kept playing")
			for _, move in mine do
				T.ok(move.kind ~= "accuse", "no accusation for an empty chair")
			end
			if m:isOver() then
				T.ok(not table.find(m.result.winners, 1), "an away player can't win by the clock")
			end
		end
	end)

	T.test("Hexlands: an away player's turn is rolled and ended, nothing built", function()
		local allowed = { place = true, road = true, roll = true, endTurn = true, discard = true, bandit = true, reject = true, cancel = true, doneRoads = true }
		for seed = 1, 3 do
			local mine = playAway("Hexlands", 3, seed, 4000)
			T.ok(#mine > 10, "the away seat kept playing")
			local roadsAfterSetup = 0
			for i, move in mine do
				T.ok(allowed[move.kind], `never {move.kind} for an absent player`)
				if move.kind == "road" and i > 4 then
					roadsAfterSetup += 1
				end
			end
			T.eq(roadsAfterSetup, 0, "only set-up roads")
		end
	end)

	T.test("Conquest runs its own turn clock", function()
		local Conquest = require(ReplicatedStorage.Shared.Games.Conquest)
		T.eq(Conquest.turnClock, true)
	end)

	T.test("away seats: the mark lives on the seat and shows in the snapshot", function()
		local TicTacToe = require(ReplicatedStorage.Shared.Games.TicTacToe)
		local m = Match.new("away", TicTacToe, {
			{ kind = "player", userId = 10, name = "Gio" },
			{ kind = "bot", name = "Bot Ava" },
		}, nil, T.Random.new(1))
		T.eq(m:isAway(1), false)
		m:setAway(1, true)
		T.eq(m:isAway(1), true)
		T.eq(m:getSnapshot(1).seats[1].away, true)
		m:setAway(2, true)
		T.eq(m:isAway(2), false, "bots are never away")
		m:setAway(1, false)
		T.eq(m:getSnapshot(1).seats[1].away, nil)
	end)
end
