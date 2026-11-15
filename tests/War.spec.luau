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
		T.eq(s.lastBattle, nil, "the war is its own step")
		T.ok(s.war ~= nil)
		T.eq(s.lastAction.kind, "war")
		T.eq(#s.piles[1], 2, "3 cards went face down")
		T.eq(#s.pot, 8)
		flipAll(s)
		T.eq(s.lastBattle.wars, 1)
		T.eq(s.lastBattle.winner, 1, "Queen beats 5")
		T.eq(#s.piles[1], 11)
		T.eq(#s.lastBattle.rounds, 2, "the tie and the war are both kept")
	end)

	T.test("a tie on your last card: it stays as your war card (and can win)", function()
		local s = War.new(2, nil, T.Random.new(4))
		s.piles = { { C(7, 1), C(2, 1) }, { C(7, 2) } }
		flipAll(s)
		T.eq(s.war.carry[2], C(7, 2))
		T.eq(#War.getActiveSeats(s), 1)
		flipAll(s)
		T.eq(s.lastBattle.winner, 2, "their 7 beats the 2")
		T.eq(#s.piles[2], 3)
		T.eq(War.getResult(s).winners[1], 2)
	end)

	T.test("house rules: everyone joins the war, 2 face down, peace spells P-E-A-C-E", function()
		local s = War.new(3, { rules = { allIn = true, faceDown = 2 } }, T.Random.new(6))
		s.piles = {
			{ C(9, 1), C(2, 1), C(2, 2), C(4, 1), C(5, 1) },
			{ C(9, 2), C(3, 1), C(3, 2), C(6, 1), C(5, 2) },
			{ C(4, 3), C(8, 1), C(8, 2), C(13, 1), C(5, 3) },
		}
		flipAll(s)
		T.eq(#s.war.seats, 3, "the 4 joins in too")
		T.eq(#s.piles[3], 2, "2 cards down")
		flipAll(s)
		T.eq(s.lastBattle.winner, 3, "the King")
		local p = War.new(2, { rules = { peace = true } }, T.Random.new(7))
		T.eq(p.faceDown, 4)
	end)

	T.test("auto-flip flips for you after a beat; switch it any time", function()
		local s = War.new(2, nil, T.Random.new(8))
		s.piles = { { C(5, 1), C(6, 1) }, { C(9, 1), C(10, 1) } }
		T.eq(War.getTimer(s), nil)
		T.ok(War.validateMove(s, 1, { kind = "auto", on = true }))
		T.eq((War.validateMove(s, 1, { kind = "auto", on = "yes" })), false)
		War.applyMove(s, 1, { kind = "auto", on = true })
		T.ok(War.getTimer(s) ~= nil)
		War.onTimeout(s)
		T.ok(s.flipped[1], "flipped for you")
		T.eq(War.getTimer(s), nil, "nobody else has auto on")
		T.ok(table.find(War.getInterruptSeats(s), 1) ~= nil, "you can still switch it off")
		T.eq(War.chooseBotMove(s, 1, T.Random.new(1)), nil, "bots don't flip out of turn")
	end)

	T.test("no battle limit", function()
		local s = War.new(2, { rules = { battleLimit = 0 } }, T.Random.new(9))
		s.battles = 5000
		s.piles = { { C(5, 1), C(6, 1) }, { C(9, 1), C(10, 1) } }
		flipAll(s)
		T.eq(War.getResult(s), nil)
	end)

	T.test("a war card can lose too: then you are out", function()
		local s = War.new(2, nil, T.Random.new(4))
		s.piles = { { C(7, 1), C(9, 1) }, { C(7, 2) } }
		flipAll(s)
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
