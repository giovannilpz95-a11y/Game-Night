local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Hearts = require(ReplicatedStorage.Shared.Games.Hearts)
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local sim = require(script.Parent.CardSim)

return function(T)
	local C = PlayingCards.make
	local S, H, D, CL = 1, 2, 3, 4

	local function playing(hands)
		local s = Hearts.new(4, { botLevel = "medium" }, T.Random.new(1))
		s.hands = hands
		s.phase = "play"
		s.passing = {}
		s.trick = {}
		s.tricksPlayed = 1
		s.heartsBroken = false
		s.turn = 1
		return s
	end

	local function apply(s, seat, move)
		local ok, err = Hearts.validateMove(s, seat, move)
		assert(ok, err)
		Hearts.applyMove(s, seat, move)
	end

	T.test("everyone passes 3 cards left in round 1", function()
		local s = Hearts.new(4, nil, T.Random.new(2))
		T.eq(s.phase, "pass")
		T.eq(#Hearts.getActiveSeats(s), 4)
		local passes = {}
		for seat = 1, 4 do
			local h = s.hands[seat]
			passes[seat] = { h[1], h[2], h[3] }
		end
		T.eq((Hearts.validateMove(s, 1, { kind = "pass", cards = { passes[1][1], passes[1][2] } })), false, "needs 3")
		T.eq((Hearts.validateMove(s, 1, { kind = "pass", cards = passes[2] })), false, "not yours")
		for seat = 1, 4 do
			apply(s, seat, { kind = "pass", cards = passes[seat] })
		end
		T.eq(s.phase, "play")
		T.ok(table.find(s.hands[2], passes[1][1]) ~= nil, "seat 1 passed to seat 2")
		T.ok(table.find(s.hands[s.turn], Hearts.TWO_OF_CLUBS) ~= nil, "2 of clubs leads")
	end)

	T.test("follow suit, and hearts can't be led until broken", function()
		local s = playing({ { C(5, H), C(9, D) }, { C(3, D), C(4, S) }, { C(7, D) }, { C(8, D) } })
		T.eq((Hearts.validateMove(s, 1, { kind = "play", card = C(5, H) })), false, "hearts not broken")
		apply(s, 1, { kind = "play", card = C(9, D) })
		T.eq((Hearts.validateMove(s, 2, { kind = "play", card = C(4, S) })), false, "follow suit")
		apply(s, 2, { kind = "play", card = C(3, D) })
		apply(s, 3, { kind = "play", card = C(7, D) })
		apply(s, 4, { kind = "play", card = C(8, D) })
		T.eq(s.lastTrick.winner, 1)
		T.eq(s.phase, "trick")
		Hearts.onTimeout(s)
		T.eq(s.turn, 1)
	end)

	T.test("no points on the first trick", function()
		local s = playing({ { C(2, CL) }, { C(12, S), C(3, D) }, { C(5, CL) }, { C(6, CL) } })
		s.tricksPlayed = 0
		apply(s, 1, { kind = "play", card = C(2, CL) })
		T.eq((Hearts.validateMove(s, 2, { kind = "play", card = C(12, S) })), false)
		T.ok(Hearts.validateMove(s, 2, { kind = "play", card = C(3, D) }))
	end)

	T.test("points add up and shooting the moon flips them", function()
		local s = playing({ {}, {}, {}, {} })
		s.tricksPlayed = 13
		s.taken = { 26, 0, 0, 0 }
		s.phase = "trick"
		Hearts.onTimeout(s)
		T.eq(s.scores[1], 0)
		T.eq(s.scores[2], 26)
		T.eq(s.moon, 1)
		local normal = playing({ {}, {}, {}, {} })
		normal.tricksPlayed = 13
		normal.taken = { 13, 5, 8, 0 }
		normal.phase = "trick"
		Hearts.onTimeout(normal)
		T.eq(normal.scores[1], 13)
		T.eq(normal.scores[4], 0)
	end)

	T.test("reaching the target ends it, lowest wins", function()
		local s = playing({ {}, {}, {}, {} })
		s.target = 50
		s.scores = { 40, 20, 10, 30 }
		s.tricksPlayed = 13
		s.taken = { 13, 0, 0, 13 }
		s.phase = "trick"
		Hearts.onTimeout(s)
		local result = Hearts.getResult(s) :: any
		T.eq(result.winners[1], 3)
	end)

	T.test("the default game ends at 100 and keeps a score sheet", function()
		local s = playing({ {}, {}, {}, {} })
		T.eq(s.target, 100)
		s.tricksPlayed = 13
		s.taken = { 13, 5, 8, 0 }
		s.phase = "trick"
		Hearts.onTimeout(s)
		local view = Hearts.getView(s, 1)
		T.eq(#view.history, 1)
		T.eq(view.history[1].points[3], 8)
	end)

	T.test("a tie for the lowest score plays one more hand", function()
		local s = playing({ {}, {}, {}, {} })
		s.target = 50
		s.scores = { 20, 20, 40, 45 }
		s.tricksPlayed = 13
		s.taken = { 0, 0, 13, 13 }
		s.phase = "trick"
		Hearts.onTimeout(s)
		T.eq(Hearts.getResult(s), nil, "tied on 20: play on")
		T.eq(s.phase, "round")
		T.eq(Hearts.getView(s, 1).tied, true)
	end)

	T.test("smart moon: the shooter takes -26 when +26 for the others would lose them the game", function()
		local s = playing({ {}, {}, {}, {} })
		s.target = 100
		s.scores = { 45, 30, 50, 50 }
		s.tricksPlayed = 13
		s.taken = { 26, 0, 0, 0 }
		s.phase = "trick"
		Hearts.onTimeout(s)
		T.eq(s.scores[1], 45, "others +26 is safe here")
		T.eq(s.scores[2], 56)
		local lose = playing({ {}, {}, {}, {} })
		lose.target = 100
		lose.scores = { 80, 50, 75, 90 }
		lose.tricksPlayed = 13
		lose.taken = { 26, 0, 0, 0 }
		lose.phase = "trick"
		Hearts.onTimeout(lose)
		T.eq(lose.scores[1], 54, "shooter takes -26 instead")
		T.eq(lose.scores[4], 90)
	end)

	T.test("first trick with only point cards: hearts, never the Queen", function()
		local s = playing({ { C(2, CL) }, { C(12, S), C(5, H) }, { C(5, CL) }, { C(6, CL) } })
		s.tricksPlayed = 0
		apply(s, 1, { kind = "play", card = C(2, CL) })
		T.eq((Hearts.validateMove(s, 2, { kind = "play", card = C(12, S) })), false)
		T.ok(Hearts.validateMove(s, 2, { kind = "play", card = C(5, H) }))
		local loose = Hearts.new(4, { rules = { firstTrickPoints = true } }, T.Random.new(1))
		loose.hands = { { C(2, CL) }, { C(12, S), C(3, D) }, { C(5, CL) }, { C(6, CL) } }
		loose.phase, loose.passing, loose.trick, loose.tricksPlayed, loose.turn = "play", {}, {}, 0, 1
		apply(loose, 1, { kind = "play", card = C(2, CL) })
		T.ok(Hearts.validateMove(loose, 2, { kind = "play", card = C(12, S) }), "house rule allows it")
	end)

	T.test("pass patterns", function()
		local nohold = Hearts.new(4, { rules = { passing = "nohold" } }, T.Random.new(1))
		local passes = {}
		for round = 1, 4 do
			table.insert(passes, Hearts.getView(nohold, 1).pass)
			nohold.round = round
			nohold.phase = "round"
			Hearts.onTimeout(nohold)
		end
		T.eq(table.concat(passes, ","), "left,right,across,left")
		local left = Hearts.new(4, { rules = { passing = "left" } }, T.Random.new(1))
		left.round = 1
		left.phase = "round"
		Hearts.onTimeout(left)
		T.eq(Hearts.getView(left, 1).pass, "left")
		local off = Hearts.new(4, { rules = { passing = false } }, T.Random.new(1))
		T.eq(off.phase, "play")
	end)

	T.test("bot games always finish", function()
		for _, level in { "easy", "medium", "hard" } do
			for seed = 1, 3 do
				local rng = T.Random.new(seed * 17 + #level)
				local s = Hearts.new(4, { botLevel = level }, rng)
				sim(Hearts, s, rng, 20000)
				T.ok(Hearts.getResult(s) ~= nil, `{level} game should finish`)
			end
		end
	end)
end
