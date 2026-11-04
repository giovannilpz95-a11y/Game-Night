-- Bot audit: many bot-only games per title and bot level, plus hard-vs-easy matches.
-- Not part of `npm test` (it's slow); run `npm run bot-audit [GameModule ...] [-- games=N]`.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local GameCatalog = require(Shared.GameCatalog)
local HouseRules = require(Shared.HouseRules)
local BotSim = require(script.Parent.BotSim)
local Dictionary = require(game:GetService("ServerScriptService").Server.Core.Dictionary)

local function seatCounts(entry)
	local out = { entry.minSeats }
	local mid = math.floor((entry.minSeats + entry.maxSeats) / 2)
	if mid ~= entry.minSeats then
		table.insert(out, mid)
	end
	if entry.maxSeats ~= mid then
		table.insert(out, entry.maxSeats)
	end
	return out
end

local function fmtTime(s)
	return string.format("%dm%02ds", s // 60, math.floor(s % 60))
end

return function(args: { string })
	local only, games, onlySeats, vsOnly = {}, 12, nil, false
	for _, a in args do
		local n = string.match(a, "^games=(%d+)$")
		local seatsArg = string.match(a, "^seats=(%d+)$")
		if n then
			games = tonumber(n) :: number
		elseif seatsArg then
			onlySeats = tonumber(seatsArg)
		elseif a == "vs" then
			vsOnly = true -- only the hard-vs-easy matches
		else
			only[a] = true
		end
	end
	local problems = 0
	for _, entry in GameCatalog.entries do
		if not entry.module or (next(only) and not only[entry.module]) then
			continue
		end
		local rules = require(Shared.Games[entry.module])
		if rules.useDictionary then
			rules.useDictionary(Dictionary.get) -- the server does this at startup
		end
		local ruleValues = HouseRules.resolve(entry, nil)
		print(`\n== {entry.module} ({entry.status}) ==`)
		for _, seats in if onlySeats then { onlySeats } else seatCounts(entry) do
			for _, level in if vsOnly then {} else { "easy", "medium", "hard" } do
				local done, moves, maxMoves, time, maxTime, timeouts, seat1 = 0, 0, 0, 0, 0, 0, 0
				local rejected, errors, stuck, draws, delaySum, delayN = 0, {}, {}, 0, 0, 0
				local reasons = {}
				local maxCpu = 0
				local clock = os.clock()
				for g = 1, games do
					local r = BotSim(rules, { seats = seats, levels = level, seed = g * 101 + seats, options = { rules = ruleValues } })
					rejected += r.rejected
					maxCpu = math.max(maxCpu, r.maxCpu)
					for _, e in r.errors do
						if #errors < 3 then
							table.insert(errors, e)
						end
					end
					if #r.rejectReasons > 0 and #errors < 3 then
						table.insert(errors, "rejected: " .. r.rejectReasons[1])
					end
					if r.stuck then
						table.insert(stuck, r.stuck)
					end
					if r.result then
						done += 1
						moves += r.moves
						maxMoves = math.max(maxMoves, r.moves)
						time += r.simSeconds
						maxTime = math.max(maxTime, r.simSeconds)
						timeouts += r.timeouts
						if r.result.isDraw or #r.result.winners == 0 then
							draws += 1
						elseif table.find(r.result.winners, 1) then
							seat1 += 1
						end
						local why = r.result.reason or "?"
						reasons[why] = (reasons[why] or 0) + 1
					end
					for _, d in r.delays do
						delaySum += d
						delayN += 1
					end
				end
				local reasonText = {}
				for why, n in reasons do
					table.insert(reasonText, `{why} x{n}`)
				end
				table.sort(reasonText)
				local flag = if done < games or rejected > 0 or #errors > 0 then "!!" else "  "
				if flag == "!!" then
					problems += 1
				end
				print(string.format(
					"%s %d seats %-6s done %d/%d  moves avg %d max %d  time avg %s max %s  timeouts %.1f  seat1 wins %d draws %d  think %.2fs  rej %d  (%.1fs cpu, slowest move %.2fs)",
					flag, seats, level, done, games, if done > 0 then moves // done else 0, maxMoves,
					fmtTime(if done > 0 then time / done else 0), fmtTime(maxTime),
					if done > 0 then timeouts / done else 0, seat1, draws,
					if delayN > 0 then delaySum / delayN else 0, rejected, os.clock() - clock, maxCpu
				))
				print("     endings: " .. table.concat(reasonText, ", "))
				for _, e in errors do
					print("     ERR " .. e)
				end
				for i = 1, math.min(2, #stuck) do
					print("     STUCK " .. stuck[i])
				end
			end
			-- Hard vs easy: alternate which seats are hard.
			local hardWins, easyWins, n = 0, 0, 0
			for g = 1, games do
				local levels = {}
				for s = 1, seats do
					levels[s] = if (s + g) % 2 == 0 then "hard" else "easy"
				end
				local r = BotSim(rules, { seats = seats, levels = levels, seed = g * 977 + seats, options = { rules = ruleValues } })
				if r.result and not r.result.isDraw and #r.result.winners > 0 then
					n += 1
					local w = r.result.winners[1]
					if levels[w] == "hard" then
						hardWins += 1
					else
						easyWins += 1
					end
				end
			end
			print(string.format("   %d seats hard vs easy: hard won %d, easy won %d (of %d decided)", seats, hardWins, easyWins, n))
		end
	end
	print(`\n{problems} level/seat combos with problems`)
	return 0
end
