-- The game picker's bot previews: every ready game plays on its own, keeps changing,
-- and deals a new game after one ends, without the rules or bots throwing.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local GameArt = require(ReplicatedStorage.Shared.GameArt)
local PreviewSim = require(ReplicatedStorage.Shared.PreviewSim)

return function(T)
	for _, entry in GameCatalog.entries do
		local module = entry.module and ReplicatedStorage.Shared.Games:FindFirstChild(entry.module)
		if not module then
			continue
		end
		T.test(`{entry.id} preview plays by itself`, function()
			local rules = require(module)
			local setup = GameArt.preview(entry.id, entry.minSeats, entry.maxSeats)
			local sim = PreviewSim.new(rules, { gameId = entry.id, seats = setup.seats :: number, seed = 3, botLevel = "easy" })
			sim:warm(setup.warm)
			local still = sim:snapshot(setup.seat)
			T.ok(still.view ~= nil and #still.seats == setup.seats, "still picture has a view and seats")
			local changes = 0
			for _ = 1, 240 do -- 60 seconds in quarter-second frames
				if sim:advance(0.25) then
					changes += 1
				end
			end
			local snap = sim:snapshot(setup.seat)
			T.ok(snap.view ~= nil, "view after a minute")
			T.ok(changes >= 5, `only {changes} changes in a minute`)
			T.ok(#sim.errors == 0, table.concat(sim.errors, "; "))
		end)
	end

	T.test("a finished preview holds, then deals a new game", function()
		local rules = require(ReplicatedStorage.Shared.Games.TicTacToe)
		local sim = PreviewSim.new(rules, { gameId = "TicTacToe", seats = 2, seed = 1, botLevel = "easy" })
		local guard = 0
		while not sim.result and guard < 5000 do
			sim:advance(0.5)
			guard += 1
		end
		T.ok(sim.result ~= nil or sim.games > 1, "game ended")
		local games = sim.games
		for _ = 1, 20 do
			sim:advance(0.5)
		end
		T.ok(sim.games > games or games > 1, "new game dealt")
	end)
end
