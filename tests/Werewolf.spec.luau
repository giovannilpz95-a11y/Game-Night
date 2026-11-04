local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Werewolf = require(ReplicatedStorage.Shared.Games.Werewolf)
local BotSim = require(script.Parent.BotSim)

return function(T)
	local function apply(s, seat, move)
		local ok, err = Werewolf.validateMove(s, seat, move)
		assert(ok, err)
		Werewolf.applyMove(s, seat, move)
	end

	-- A game with known roles: seat 1 wolf, 2 seer, 3 guardian, 4-5 villagers.
	local function fixed(seats: number?, rules: any?)
		local s = Werewolf.new(seats or 5, { rules = rules }, T.Random.new(1))
		s.roles = { "wolf", "seer", "guardian", "villager", "villager" }
		for seat = 6, s.seatCount do
			s.roles[seat] = "villager"
		end
		Werewolf.onTimeout(s) -- roles -> night 1
		return s
	end

	local function seatsOf(s, role: string): { number }
		local out = {}
		for seat, r in s.roles do
			if r == role then
				table.insert(out, seat)
			end
		end
		return out
	end

	T.test("roles: the right mix for each table size", function()
		for seats = 5, 8 do
			local s = Werewolf.new(seats, nil, T.Random.new(seats))
			T.eq(#seatsOf(s, "wolf"), if seats >= 7 then 2 else 1)
			T.eq(#seatsOf(s, "seer"), 1)
			T.eq(#seatsOf(s, "guardian"), 1)
			T.eq(#s.roles, seats)
		end
		local s = Werewolf.new(8, { rules = { wolves = 1, guardian = false } }, T.Random.new(2))
		T.eq(#seatsOf(s, "wolf"), 1)
		T.eq(#seatsOf(s, "guardian"), 0)
	end)

	T.test("views keep roles secret; wolves see their pack", function()
		local s = Werewolf.new(8, nil, T.Random.new(3))
		local wolves = seatsOf(s, "wolf")
		for seat = 1, 8 do
			local v = Werewolf.getView(s, seat)
			T.eq(v.yourRole, s.roles[seat])
			for other = 1, 8 do
				T.eq(v.roles[other], false, "nobody's role shows at the start")
			end
			T.eq(v.allRoles, nil)
			if s.roles[seat] == "wolf" then
				T.eq(#v.pack, 1)
				T.ok(table.find(wolves, v.pack[1]) ~= nil)
			else
				T.eq(v.pack, nil)
			end
		end
		local spectator = Werewolf.getView(s, nil)
		T.eq(spectator.yourRole, nil)
		T.eq(spectator.pack, nil)
	end)

	T.test("everyone alive acts at night, so active seats give nothing away", function()
		local s = fixed()
		T.eq(s.phase, "night")
		T.eq(#Werewolf.getActiveSeats(s), 5)
		-- Each role has its own legal targets.
		T.eq((Werewolf.validateMove(s, 1, { kind = "night", target = 1 })), false, "a wolf can't catch a wolf")
		T.eq((Werewolf.validateMove(s, 2, { kind = "night", target = 2 })), false, "the seer can't check herself")
		T.eq((Werewolf.validateMove(s, 3, { kind = "night", target = 3 })), true, "the guardian may shield himself")
		T.eq((Werewolf.validateMove(s, 4, { kind = "night", target = 4 })), false)
		T.eq((Werewolf.validateMove(s, 1, { kind = "vote", target = 4 })), false, "wrong move for the phase")
	end)

	T.test("the wolves catch someone; the guardian can save them", function()
		local s = fixed()
		apply(s, 1, { kind = "night", target = 4 })
		apply(s, 2, { kind = "night", target = 1 })
		apply(s, 3, { kind = "night", target = 5 })
		apply(s, 4, { kind = "night", target = 2 })
		apply(s, 5, { kind = "night", target = 1 })
		T.eq(s.phase, "dawn")
		T.eq(s.alive[4], false)
		T.eq(s.lastNight.caught, 4)
		T.eq(Werewolf.getView(s, 2).peeks[1], true, "the seer learned seat 1 is a wolf")
		T.eq(Werewolf.getView(s, 3).peeks, nil, "only the seer sees checks")

		Werewolf.onTimeout(s) -- dawn -> day
		T.eq(s.phase, "day")
		for seat = 1, 5 do
			if s.alive[seat] then
				apply(s, seat, { kind = "pass" })
			end
		end
		T.eq(s.phase, "vote")
		for seat = 1, 5 do
			if s.alive[seat] then
				apply(s, seat, { kind = "vote", target = 0 })
			end
		end
		T.eq(s.phase, "verdict")
		T.eq(s.lastVerdict.out, nil, "all skipped: nobody out")
		Werewolf.onTimeout(s) -- night 2
		T.eq(s.phase, "night")
		T.eq((Werewolf.validateMove(s, 3, { kind = "night", target = 5 })), false, "no shielding the same player twice in a row")
		apply(s, 1, { kind = "night", target = 5 })
		apply(s, 2, { kind = "night", target = 3 })
		apply(s, 3, { kind = "night", target = 3 })
		apply(s, 5, { kind = "night", target = 1 })
		T.eq(s.alive[5], false)
	end)

	T.test("a shielded target survives and the guardian gets the save", function()
		local s = fixed()
		apply(s, 1, { kind = "night", target = 2 })
		apply(s, 2, { kind = "night", target = 4 })
		apply(s, 3, { kind = "night", target = 2 })
		apply(s, 4, { kind = "night", target = 1 })
		apply(s, 5, { kind = "night", target = 1 })
		T.eq(s.alive[2], true)
		T.eq(s.lastNight.saved, true)
		T.eq(s.matchStats[3].saves, 1)
	end)

	T.test("voting out the last wolf wins it for the village", function()
		local s = fixed()
		for seat = 1, 5 do
			apply(s, seat, { kind = "night", target = if seat == 1 then 4 elseif seat == 3 then 3 else 1 })
		end
		Werewolf.onTimeout(s)
		T.eq(s.phase, "day")
		apply(s, 2, { kind = "claim", target = 1, wolf = true })
		T.eq(Werewolf.getView(s, 5).statements[2].wolf, true, "statements are public")
		Werewolf.onTimeout(s) -- talk time runs out
		T.eq(s.phase, "vote")
		apply(s, 1, { kind = "vote", target = 2 })
		apply(s, 2, { kind = "vote", target = 1 })
		apply(s, 3, { kind = "vote", target = 1 })
		T.eq(Werewolf.getView(s, 5).votes[3], 1, "votes are public")
		apply(s, 5, { kind = "vote", target = 1 })
		T.eq(s.phase, "verdict")
		T.eq(s.lastVerdict.out, 1)
		T.eq(Werewolf.getView(s, nil).roles[1], "wolf", "roles show when out (default)")
		T.eq(Werewolf.getResult(s), nil, "the verdict shows before the game ends")
		Werewolf.onTimeout(s)
		local result = Werewolf.getResult(s)
		T.ok(result)
		T.eq(#result.winners, 4)
		T.ok(table.find(result.winners, 4) ~= nil, "villagers who were caught still win with the village")
		T.eq(Werewolf.getView(s, nil).allRoles[1], "wolf")
	end)

	T.test("ties and skips keep everyone in", function()
		local s = fixed()
		for seat = 1, 5 do
			apply(s, seat, { kind = "night", target = if seat == 1 then 4 elseif seat == 3 then 4 else 1 })
		end
		T.eq(s.alive[4], true, "the guardian saved seat 4")
		Werewolf.onTimeout(s)
		Werewolf.onTimeout(s)
		apply(s, 1, { kind = "vote", target = 2 })
		apply(s, 2, { kind = "vote", target = 1 })
		apply(s, 3, { kind = "vote", target = 0 })
		apply(s, 4, { kind = "vote", target = 0 })
		apply(s, 5, { kind = "vote", target = 0 })
		T.eq(s.lastVerdict.out, nil)
	end)

	T.test("the wolves win once they match the village", function()
		local s = fixed()
		s.alive[4], s.alive[5], s.alive[3] = false, false, false
		-- Two left: the wolf and the seer. The next dawn check ends it.
		apply(s, 1, { kind = "night", target = 2 })
		apply(s, 2, { kind = "night", target = 1 })
		Werewolf.onTimeout(s)
		local result = Werewolf.getResult(s)
		T.ok(result)
		T.eq(result.winners[1], 1)
		T.eq(s.winner, "wolves")
	end)

	T.test("with roles hidden, a player who is out shows no role", function()
		local s = fixed(5, { reveal = false })
		for seat = 1, 5 do
			apply(s, seat, { kind = "night", target = if seat == 1 then 4 elseif seat == 3 then 3 else 1 })
		end
		T.eq(Werewolf.getView(s, 5).roles[4], false)
		T.eq(Werewolf.getSeatInfo(s)[4], "Out")
	end)

	T.test("a sleepy night still moves on", function()
		local s = fixed()
		Werewolf.onTimeout(s) -- nobody picked: the pack catches someone anyway
		T.eq(s.phase, "dawn")
		T.ok(s.lastNight.caught ~= nil)
		T.ok(s.roles[s.lastNight.caught] ~= "wolf")
	end)

	T.test("bad moves are refused", function()
		local s = fixed()
		for _, bad in { { kind = "night", target = 0 }, { kind = "night", target = 9 }, { kind = "night", target = 1.5 }, { kind = "night" }, "x", {} } do
			T.eq((Werewolf.validateMove(s, 2, bad)), false)
		end
		apply(s, 2, { kind = "night", target = 4 })
		T.eq((Werewolf.validateMove(s, 2, { kind = "night", target = 5 })), false, "one pick a night")
		for seat = 1, 5 do
			if seat ~= 2 then
				apply(s, seat, { kind = "night", target = if seat == 1 then 5 else 1 })
			end
		end
		Werewolf.onTimeout(s)
		T.eq((Werewolf.validateMove(s, 5, { kind = "pass" })), false, "out players can't speak")
		T.eq((Werewolf.validateMove(s, 2, { kind = "claim", target = 1, wolf = "yes" })), false)
		T.eq((Werewolf.validateMove(s, 2, { kind = "accuse", target = 2 })), false, "no accusing yourself")
		T.eq((Werewolf.validateMove(s, 2, { kind = "accuse", target = 5 })), false, "no accusing the out")
	end)

	T.test("the village's bots beat the wolves more often on hard than on easy", function()
		local function villageWins(level: string): number
			local wins = 0
			for seed = 1, 40 do
				local r = BotSim(Werewolf, { seats = 7, levels = level, seed = seed })
				if r.state and r.state.winner == "village" then
					wins += 1
				end
			end
			return wins
		end
		local easy, hard = villageWins("easy"), villageWins("hard")
		T.ok(hard > easy, `hard village {hard}/40 vs easy {easy}/40`)
	end)
end
