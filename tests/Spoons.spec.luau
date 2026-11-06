local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Spoons = require(ReplicatedStorage.Shared.Games.Spoons)
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)

return function(T)
	local C = PlayingCards.make

	T.test("everyone starts with 5 cards and there is one spoon fewer than players", function()
		local s = Spoons.new(5, nil, T.Random.new(1))
		for seat = 1, 5 do
			T.eq(#s.hands[seat], 5)
		end
		T.eq(s.spoonsLeft, 4)
		T.eq(#Spoons.getActiveSeats(s), 5)
		T.eq(#s.deck + #s.discard + 25, 4 * 7, "players + 2 ranks")
	end)

	T.test("passing moves cards left once everyone has passed", function()
		local s = Spoons.new(3, nil, T.Random.new(2))
		local passed = {}
		for seat = 1, 3 do
			passed[seat] = s.hands[seat][1]
			Spoons.applyMove(s, seat, { kind = "pass", card = passed[seat] })
			if seat < 3 then
				T.eq(#s.hands[seat], 4, "waiting for the others")
			end
		end
		for seat = 1, 3 do
			T.eq(#s.hands[seat], 5)
		end
		T.ok(table.find(s.hands[2], passed[1]) ~= nil, "seat 1 passed to seat 2")
		T.ok(table.find(s.hands[3], passed[2]) ~= nil)
		T.eq(s.discard[#s.discard], passed[3], "the last player discards")
		T.eq((Spoons.validateMove(s, 1, { kind = "pass", card = 999 })), false)
	end)

	T.test("you need four of a kind to grab the first spoon", function()
		local s = Spoons.new(3, nil, T.Random.new(3))
		s.hands[1] = { C(5, 1), C(5, 2), C(5, 3), C(9, 1), C(2, 1) }
		T.eq((Spoons.validateMove(s, 1, { kind = "grab" })), false)
		s.hands[1] = { C(5, 1), C(5, 2), C(5, 3), C(5, 4), C(2, 1) }
		T.ok(Spoons.validateMove(s, 1, { kind = "grab" }))
		Spoons.applyMove(s, 1, { kind = "grab" })
		T.eq(s.phase, "scramble")
		T.ok(Spoons.validateMove(s, 2, { kind = "grab" }), "now anyone can grab")
		T.eq((Spoons.validateMove(s, 1, { kind = "grab" })), false, "one spoon each")
		Spoons.applyMove(s, 2, { kind = "grab" })
		T.eq(s.out[3], 1, "the player without a spoon is out")
		T.eq(s.phase, "reveal")
		Spoons.onTimeout(s)
		T.eq(s.phase, "pass")
		T.eq(s.spoonsLeft, 1)
		T.eq(s.hands[3], nil, "out players get no cards")
	end)

	T.test("the scramble clock hands out the last spoons at random", function()
		local s = Spoons.new(4, nil, T.Random.new(4))
		s.hands[2] = { C(5, 1), C(5, 2), C(5, 3), C(5, 4), C(2, 1) }
		Spoons.applyMove(s, 2, { kind = "grab" })
		Spoons.onTimeout(s)
		local out = 0
		for _ in s.out do
			out += 1
		end
		T.eq(out, 1)
		T.eq(s.out[2], nil)
	end)

	T.test("letters mode: losing a round earns a letter, spelling the word puts you out", function()
		local s = Spoons.new(3, { rules = { letters = "PIG" } }, T.Random.new(6))
		for round = 1, 3 do
			s.hands[1] = { C(5, 1), C(5, 2), C(5, 3), C(5, 4), C(2, 1) }
			Spoons.applyMove(s, 1, { kind = "grab" })
			Spoons.applyMove(s, 2, { kind = "grab" })
			if round < 3 then
				T.eq(s.out[3], nil, "only a letter so far")
				T.eq(Spoons.getView(s, 1).letters["3"], string.sub("PIG", 1, round))
				T.eq(s.lastLetter, 3)
				Spoons.onTimeout(s)
				T.eq(s.spoonsLeft, 2, "still three players")
			end
		end
		T.eq(s.out[3], s.round, "spelled PIG: out")
		T.eq(s.lastOut, 3)
	end)

	T.test("other hands stay hidden", function()
		local s = Spoons.new(3, nil, T.Random.new(5))
		local view = Spoons.getView(s, 1)
		T.eq(#view.hand, 5)
		T.eq(view.hands, nil)
		T.eq(Spoons.getView(s, nil).hand, nil)
	end)

	T.test("bot games always end with one winner", function()
		for _, level in { "easy", "medium", "hard" } do
			for seats = 3, 8 do
				local rng = T.Random.new(seats * 31)
				local s = Spoons.new(seats, { botLevel = level }, rng)
				local steps = 0
				while not Spoons.getResult(s) and steps < 20000 do
					steps += 1
					local active = Spoons.getActiveSeats(s)
					local moved = false
					if #active > 0 then
						local seat = active[rng:NextInteger(1, #active)]
						local move = Spoons.chooseBotMove(s, seat, rng)
						if move then
							T.ok(Spoons.validateMove(s, seat, move), "bot made an illegal move")
							Spoons.applyMove(s, seat, move)
							moved = true
						end
					end
					if not moved then
						Spoons.onTimeout(s)
					end
				end
				local result = Spoons.getResult(s)
				T.ok(result ~= nil, `{level} {seats}-seat game should finish`)
				T.eq(#result.winners, 1)
			end
		end
	end)
end
