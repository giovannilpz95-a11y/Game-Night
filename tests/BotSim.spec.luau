-- Bot-only games for every title, run the way MatchService runs bots (see BotSim).
-- Every bot level must finish the game with no rejected moves, errors or stalls, with
-- sane think times. Deeper checks (many games, timings, win rates) live in the bot
-- audit: `npm run bot-audit`.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = ReplicatedStorage.Shared
local GameCatalog = require(Shared.GameCatalog)
local HouseRules = require(Shared.HouseRules)
local Dictionary = require(ServerScriptService.Server.Core.Dictionary)
local BotSim = require(script.Parent.BotSim)

-- Search bots (a time-capped tree search per move) are too slow to play whole games in
-- the test run, so they play the opening only.
local SEARCH = { Chess = true, Checkers = true, FourInARow = true }

local MAX_THINK = 6 -- seconds; longer looks like the bot froze

return function(T)
	for _, entry in GameCatalog.entries do
		if not entry.module then
			continue
		end
		local rules = require(Shared.Games[entry.module])
		local ruleValues = HouseRules.resolve(entry, nil)
		local seatCounts = { entry.minSeats }
		if entry.maxSeats ~= entry.minSeats then
			table.insert(seatCounts, entry.maxSeats)
		end
		for _, seats in seatCounts do
			for _, level in { "easy", "medium", "hard" } do
				T.test(`{entry.module} {seats} seats, {level} bots play cleanly`, function()
					if rules.useDictionary then
						rules.useDictionary(Dictionary.get)
					end
					local search = SEARCH[entry.module]
					for seed = 1, if search then 1 else 2 do
						local r = BotSim(rules, {
							seats = seats,
							levels = level,
							seed = seed * 31 + seats,
							options = { rules = ruleValues },
							maxEvents = if search then 24 else nil,
						})
						T.eq(#r.errors, 0, `error: {r.errors[1]}`)
						T.eq(r.rejected, 0, `bot move rejected: {r.rejectReasons[1]}`)
						T.eq(r.badDelays, 0, "getBotDelay returned a bad number")
						if search then
							T.ok(r.result or (r.stuck and string.find(r.stuck, "no result after", 1, true)), r.stuck)
						else
							T.ok(r.result, r.stuck)
						end
						for _, d in r.delays do
							T.ok(d <= MAX_THINK, `think time {d}s`)
						end
					end
				end)
			end
		end
	end

	-- Hard bots should clearly beat easy ones where skill matters. Seeds are fixed, so a
	-- drop here means a bot change made hard play worse.
	local function hardVsEasy(module: string, seats: number, games: number): (number, number)
		local entry = GameCatalog.get(module) :: any
		local rules = require(Shared.Games[module])
		if rules.useDictionary then
			rules.useDictionary(Dictionary.get)
		end
		local hard, easy = 0, 0
		for g = 1, games do
			local levels = {}
			for s = 1, seats do
				levels[s] = if (s + g) % 2 == 0 then "hard" else "easy"
			end
			local r = BotSim(rules, { seats = seats, levels = levels, seed = g * 977 + seats, options = { rules = HouseRules.resolve(entry, nil) } })
			if r.result and not r.result.isDraw and #r.result.winners > 0 then
				if levels[r.result.winners[1]] == "hard" then
					hard += 1
				else
					easy += 1
				end
			end
		end
		return hard, easy
	end

	for _, case in { { "Cheat", 3 }, { "Cheat", 6 }, { "President", 4 }, { "Hearts", 4 }, { "Whodunit", 4 }, { "WordTiles", 2 }, { "Palace", 3 } } do
		T.test(`hard bots beat easy ones at {case[1]} ({case[2]} seats)`, function()
			local hard, easy = hardVsEasy(case[1], case[2], 10)
			T.ok(hard >= easy * 2, `hard won {hard}, easy won {easy}`)
		end)
	end
end
