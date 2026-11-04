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
		s.scores = { 40, 20, 10, 30 }
		s.tricksPlayed = 13
		s.taken = { 13, 0, 0, 13 }
		s.phase = "trick"
		Hearts.onTimeout(s)
		local result = Hearts.getResult(s) :: any
		T.eq(result.winners[1], 3)
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
