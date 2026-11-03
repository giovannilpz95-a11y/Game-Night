local ReplicatedStorage = game:GetService("ReplicatedStorage")
local War = require(ReplicatedStorage.Shared.Games.War)
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)

return function(T)
	local C = PlayingCards.make

	local function flipAll(s)
		for _, seat in War.getActiveSeats(s) do
			T.ok(War.validateMove(s, seat, { kind = "flip" }))
			War.applyMove(s, seat, { kind = "flip" })
		end
	end

	T.test("deal splits the deck", function()
		local s = War.new(2, nil, T.Random.new(1))
		T.eq(#s.piles[1], 26)
		T.eq(#s.piles[2], 26)
		local three = War.new(3, nil, T.Random.new(1))
		T.eq(#three.piles[1], 17)
	end)

	T.test("battle waits for everyone, then highest card (Ace high) wins the pot", function()
		local s = War.new(2, nil, T.Random.new(2))
		s.piles = { { C(1, 1), C(2, 1) }, { C(13, 1), C(3, 1) } }
		War.applyMove(s, 1, { kind = "flip" })
		T.eq(s.lastBattle, nil, "not resolved yet")
		T.eq((War.validateMove(s, 1, { kind = "flip" })), false, "can't flip twice")
		War.applyMove(s, 2, { kind = "flip" })
		T.eq(s.lastBattle.winner, 1)
		T.eq(#s.piles[1], 3)
		T.eq(#s.piles[2], 1)
	end)

	T.test("a tie starts a war", function()
		local s = War.new(2, nil, T.Random.new(3))
		s.piles = {
			{ C(7, 1), C(2, 1), C(2, 2), C(2, 3), C(12, 1), C(4, 1) },
			{ C(7, 2), C(3, 1), C(3, 2), C(3, 3), C(5, 1), C(4, 2) },
		}
		flipAll(s)
		T.eq(s.lastBattle.wars, 1)
		T.eq(s.lastBattle.winner, 1, "Queen beats 5")
		T.eq(#s.piles[1], 11)
	end)

	T.test("running out of cards in a war loses", function()
		local s = War.new(2, nil, T.Random.new(4))
		s.piles = { { C(7, 1), C(9, 1) }, { C(7, 2) } }
		flipAll(s)
		local result = War.getResult(s)
		T.ok(result ~= nil)
		T.eq(result.winners[1], 1)
	end)

	T.test("bad moves are rejected", function()
		local s = War.new(2, nil, T.Random.new(5))
		T.eq((War.validateMove(s, 1, "flip")), false)
		T.eq((War.validateMove(s, 1, { kind = "play" })), false)
	end)

	T.test("games always end (battle limit)", function()
		for seats = 2, 4 do
			for game = 1, 10 do
				local s = War.new(seats, nil, T.Random.new(game + seats * 100))
				local n = 0
				while not War.getResult(s) and n < 1000 do
					n += 1
					flipAll(s)
				end
				T.ok(War.getResult(s) ~= nil, `{seats}-seat game should end`)
				T.ok(s.battles <= War.BATTLE_LIMIT)
			end
		end
	end)
end
