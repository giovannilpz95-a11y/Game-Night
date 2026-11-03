local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Speed = require(ReplicatedStorage.Shared.Games.Speed)
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local GameModule = require(ReplicatedStorage.Shared.GameModule)

return function(T)
	local C = PlayingCards.make

	T.test("deal uses all 52 cards", function()
		local s = Speed.new(2, nil, T.Random.new(1))
		local n = 0
		for seat = 1, 2 do
			n += #s.hands[seat] + #s.draws[seat] + #s.sides[seat] + #s.centers[seat]
		end
		T.eq(n, 52)
		T.eq(#s.hands[1], 5)
	end)

	T.test("cards play one rank up or down, and K-A wraps", function()
		T.ok(Speed.fits(C(5, 1), C(6, 2)))
		T.ok(Speed.fits(C(7, 1), C(6, 2)))
		T.ok(Speed.fits(C(1, 1), C(13, 2)), "Ace on King")
		T.ok(Speed.fits(C(13, 1), C(1, 2)), "King on Ace")
		T.eq(Speed.fits(C(8, 1), C(6, 2)), false)
		T.eq(Speed.fits(C(6, 1), C(6, 2)), false)
	end)

	T.test("both players are active, illegal plays are rejected, hand refills", function()
		local s = Speed.new(2, nil, T.Random.new(2))
		s.hands[1] = { C(5, 1), C(9, 1), C(2, 2), C(2, 3), C(2, 4) }
		s.hands[2] = { C(11, 1), C(11, 2), C(11, 3), C(11, 4), C(12, 1) }
		s.centers = { { C(6, 2) }, { C(3, 1) } }
		s.stuck = false
		T.eq(#Speed.getActiveSeats(s), 2)
		T.eq((Speed.validateMove(s, 1, { kind = "play", card = C(9, 1), pile = 1 })), false)
		T.eq((Speed.validateMove(s, 1, { kind = "play", card = C(5, 1), pile = 3 })), false)
		T.eq((Speed.validateMove(s, 1, { kind = "play", card = C(11, 1), pile = 1 })), false, "not your card")
		T.eq((Speed.validateMove(s, 1, { kind = "play", card = 0.5, pile = 1 })), false)
		T.eq((Speed.validateMove(s, 1, "x")), false)
		local before = #s.draws[1]
		T.ok(Speed.validateMove(s, 1, { kind = "play", card = C(5, 1), pile = 1 }))
		Speed.applyMove(s, 1, { kind = "play", card = C(5, 1), pile = 1 })
		T.eq(#s.hands[1], 5, "refilled")
		T.eq(#s.draws[1], before - 1)
	end)

	T.test("when nobody can play, the flip timer turns new center cards", function()
		local s = Speed.new(2, nil, T.Random.new(3))
		s.hands[1] = { C(9, 1) }
		s.hands[2] = { C(9, 2) }
		s.centers = { { C(2, 1) }, { C(2, 2) } }
		s.sides = { { C(8, 3) }, { C(4, 3) } }
		Speed._checkStuck(s)
		T.ok(s.stuck)
		T.eq(#Speed.getActiveSeats(s), 0)
		local timer = Speed.getTimer(s)
		T.ok(timer ~= nil)
		Speed.onTimeout(s)
		T.eq(s.centers[1][#s.centers[1]], C(8, 3))
		T.eq(s.stuck, false, "9 now fits on the 8")
	end)

	T.test("side piles rebuild from the center piles", function()
		local s = Speed.new(2, nil, T.Random.new(4))
		s.hands[1] = { C(9, 1) }
		s.hands[2] = { C(9, 2) }
		s.centers = { { C(2, 1), C(3, 1) }, { C(2, 2), C(3, 2) } }
		s.sides = { {}, {} }
		Speed._checkStuck(s)
		Speed.onTimeout(s)
		T.eq(#s.centers[1] + #s.centers[2] + #s.sides[1] + #s.sides[2], 4)
	end)

	T.test("playing your last card wins", function()
		local s = Speed.new(2, nil, T.Random.new(5))
		s.hands[1] = { C(5, 1) }
		s.draws[1] = {}
		s.centers = { { C(6, 2) }, { C(3, 1) } }
		s.stuck = false
		Speed.applyMove(s, 1, { kind = "play", card = C(5, 1), pile = 1 })
		local result = Speed.getResult(s)
		T.ok(result ~= nil)
		T.eq(result.winners[1], 1)
	end)

	T.test("other hands stay hidden", function()
		local s = Speed.new(2, nil, T.Random.new(6))
		local view = Speed.getView(s, 1)
		T.eq(#view.hand, 5)
		T.eq(view.hands, nil)
		T.eq(Speed.getView(s, nil).hand, nil)
	end)

	T.test("bot races always finish", function()
		for _, level in { "easy", "medium", "hard" } do
			for game = 1, 15 do
				local rng = T.Random.new(game * 7)
				local s = Speed.new(2, { botLevel = level }, rng)
				local steps = 0
				while not Speed.getResult(s) and steps < 3000 do
					steps += 1
					local active = Speed.getActiveSeats(s)
					if #active == 0 then
						Speed.onTimeout(s)
					else
						local seat = active[rng:NextInteger(1, #active)]
						local move = Speed.chooseBotMove(s, seat, rng)
						if move == nil then
							local other = if seat == 1 then 2 else 1
							move = Speed.chooseBotMove(s, other, rng)
							seat = other
						end
						if move then
							T.ok(Speed.validateMove(s, seat, move), "bot made an illegal move")
							Speed.applyMove(s, seat, move)
						end
					end
				end
				T.ok(Speed.getResult(s) ~= nil, `{level} game {game} should finish`)
			end
		end
		local _ = GameModule
	end)
end
