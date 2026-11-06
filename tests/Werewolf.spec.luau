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
		T.eq(s.phase, "lastWords", "last words before the end")
		T.eq(Werewolf.getActiveSeats(s)[1], 1)
		Werewolf.onTimeout(s)
		local result = Werewolf.getResult(s)
		T.ok(result)
		T.eq(#result.winners, 4)
		T.ok(table.find(result.winners, 4) ~= nil, "villagers who were caught still win with the village")
		T.eq(Werewolf.getView(s, nil).allRoles[1], "wolf")
	end)

	-- Runs a night where every seat picks `picks[seat]` (default: seat 1).
	local function night(s, picks)
		for seat = 1, s.seatCount do
			if s.alive[seat] then
				local t = picks[seat] or (if seat == 1 then 2 else 1)
				if t == seat and s.roles[seat] ~= "guardian" then
					t = if seat == 1 then 2 else 1
				end
				apply(s, seat, { kind = "night", target = t })
			end
		end
	end

	T.test("last words: the voted-out player gets the floor, filtered text only", function()
		local s = fixed(6)
		night(s, { [1] = 4, [3] = 3 })
		Werewolf.onTimeout(s) -- dawn -> day
		Werewolf.onTimeout(s) -- day -> vote
		for seat = 1, 6 do
			if s.alive[seat] then
				apply(s, seat, { kind = "vote", target = if seat == 5 then 6 else 5 })
			end
		end
		T.eq(s.lastVerdict.out, 5)
		Werewolf.onTimeout(s)
		T.eq(s.phase, "lastWords")
		T.eq((Werewolf.validateMove(s, 2, { kind = "lastWords", text = "hi" })), false, "only the one voted out")
		T.eq((Werewolf.validateMove(s, 5, { kind = "lastWords", text = string.rep("a", 500) })), false, "too long")
		apply(s, 5, { kind = "lastWords", text = "raw", shown = "It was seat 1!" })
		T.eq(s.lastWords.text, "It was seat 1!", "only the filtered text is kept")
		T.eq(Werewolf.getView(s, 2).lastWords.text, "It was seat 1!")
		T.eq(s.phase, "night")
	end)

	T.test("the Hunter takes someone down: at dawn and after a vote", function()
		local s = fixed(6)
		s.roles[4] = "hunter"
		night(s, { [1] = 4, [3] = 3 })
		T.eq(s.alive[4], false)
		Werewolf.onTimeout(s) -- dawn
		T.eq(s.phase, "hunter")
		T.eq(Werewolf.getActiveSeats(s)[1], 4)
		T.eq((Werewolf.validateMove(s, 4, { kind = "shoot", target = 4 })), false, "not yourself")
		apply(s, 4, { kind = "shoot", target = 1 })
		T.eq(s.alive[1], false)
		T.eq(s.lastShot.target, 1)
		T.eq(s.winner, "village", "shot the only wolf")

		-- Voted out: last words, then the shot, then night. Holstering is allowed.
		local t = fixed(6)
		t.roles[5] = "hunter"
		night(t, { [1] = 4, [3] = 3 })
		Werewolf.onTimeout(t) -- dawn -> day
		Werewolf.onTimeout(t) -- day -> vote
		for seat = 1, 6 do
			if t.alive[seat] then
				apply(t, seat, { kind = "vote", target = if seat == 5 then 6 else 5 })
			end
		end
		Werewolf.onTimeout(t) -- verdict -> last words
		Werewolf.onTimeout(t) -- last words run out
		T.eq(t.phase, "hunter")
		local bot = Werewolf.chooseBotMove(t, 5, T.Random.new(1))
		T.eq(bot.kind, "shoot")
		apply(t, 5, { kind = "shoot", target = 0 })
		T.eq(t.phase, "night")
		T.eq(t.lastShot.target, nil)
	end)

	T.test("the Witch: sees the victim once the wolves pick, saves or poisons once each", function()
		local s = fixed(7)
		s.roles[5] = "witch"
		s.roles[6] = "wolf"
		T.eq(Werewolf.getView(s, 5).witchSees, nil, "nothing to see yet")
		T.eq((Werewolf.validateMove(s, 5, { kind = "night", target = 4, potion = "heal" })), false)
		apply(s, 1, { kind = "night", target = 4 })
		apply(s, 6, { kind = "night", target = 4 })
		T.eq(Werewolf.getView(s, 5).witchSees, 4)
		T.eq(Werewolf.getView(s, 2).witchSees, nil, "only the Witch")
		apply(s, 5, { kind = "night", target = 4, potion = "heal" })
		for _, seat in { 2, 3, 4, 7 } do
			apply(s, seat, { kind = "night", target = if seat == 3 then 7 else 1 })
		end
		T.eq(s.alive[4], true, "saved")
		T.eq(s.potions.heal, false)
		-- Next night: no heal left; poison works on anyone.
		Werewolf.onTimeout(s) -- dawn -> day
		Werewolf.onTimeout(s) -- day -> vote
		for seat = 1, 7 do
			if s.alive[seat] then
				apply(s, seat, { kind = "vote", target = 0 })
			end
		end
		Werewolf.onTimeout(s) -- verdict: nobody out -> night 2
		T.eq(s.phase, "night")
		apply(s, 1, { kind = "night", target = 3 })
		apply(s, 6, { kind = "night", target = 3 })
		T.eq(Werewolf.getView(s, 5).witchSees, nil, "the heal is used up")
		T.eq((Werewolf.validateMove(s, 5, { kind = "night", target = 3, potion = "heal" })), false)
		apply(s, 5, { kind = "night", target = 6, potion = "poison" })
		apply(s, 2, { kind = "night", target = 7 })
		apply(s, 3, { kind = "night", target = 4 })
		apply(s, 4, { kind = "night", target = 1 })
		apply(s, 7, { kind = "night", target = 1 })
		T.eq(s.alive[6], false, "poisoned")
		T.eq(s.lastNight.poisoned, 6)
		T.eq(s.potions.poison, false)
	end)

	T.test("players who are out chat only with each other", function()
		local s = fixed(6)
		night(s, { [1] = 4, [3] = 3 })
		T.eq(Werewolf.getChatGroup(s, 4), "out")
		T.eq(Werewolf.getChatGroup(s, 2), nil)
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

	T.test("day 1: bots don't all pile onto the first player someone suspects", function()
		-- 8 seats; on day 1 seats 1 and 2 already said they suspect seat 8. How often do the
		-- other village bots name seat 8 too? It used to be every time on hard.
		for _, level in { "medium", "hard" } do
			local follow, total = 0, 0
			for seed = 1, 60 do
				local s = Werewolf.new(8, { botLevel = level }, T.Random.new(seed))
				s.roles = { "villager", "villager", "seer", "guardian", "villager", "villager", "wolf", "wolf" }
				Werewolf.onTimeout(s) -- roles -> night 1
				for seat = 1, 8 do
					apply(s, seat, { kind = "night", target = if seat >= 7 then 1 else 7 })
				end
				-- A guardian save and a night with nobody out, so it's a clean day 1.
				s.alive[1] = true
				Werewolf.onTimeout(s) -- dawn -> day
				T.eq(s.phase, "day")
				apply(s, 1, { kind = "accuse", target = 8 })
				apply(s, 2, { kind = "accuse", target = 8 })
				for _, seat in { 4, 5, 6 } do
					local move = Werewolf.chooseBotMove(s, seat, T.Random.new(seed * 10 + seat))
					if move and move.kind == "accuse" then
						total += 1
						if move.target == 8 then
							follow += 1
						end
					end
				end
			end
			T.ok(total > 20, `{level}: bots still accuse someone ({total})`)
			T.ok(follow / total < 0.7, `{level}: {follow} of {total} accusations followed the pile`)
		end
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
