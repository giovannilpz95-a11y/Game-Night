local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GinRummy = require(ReplicatedStorage.Shared.Games.GinRummy)
local Melds = require(ReplicatedStorage.Shared.Cards.Melds)
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local sim = require(script.Parent.CardSim)

return function(T)
	local C = PlayingCards.make
	local S, H, D, CL = 1, 2, 3, 4

	local function setup(hands, discard, stock)
		local s = GinRummy.new(2, { botLevel = "medium" }, T.Random.new(1))
		s.hands = hands
		s.discard = discard
		s.stock = stock
		s.turn = 1
		s.phase = "draw"
		s.taken = nil
		return s
	end

	local function apply(s, seat, move)
		local ok, err = GinRummy.validateMove(s, seat, move)
		assert(ok, err)
		GinRummy.applyMove(s, seat, move)
	end

	local function filler(n)
		local out = {}
		for i = 1, n do
			table.insert(out, C((i - 1) % 13 + 1, CL))
		end
		return out
	end

	T.test("melds: sets, runs (Ace low) and the least deadwood", function()
		local best = Melds.best({ C(1, S), C(2, S), C(3, S), C(7, H), C(7, D), C(7, CL), C(13, S), C(12, H) })
		T.eq(#best.melds, 2)
		T.eq(best.value, 20)
		local noWrap = Melds.best({ C(12, S), C(13, S), C(1, S) })
		T.eq(noWrap.value, 21, "Q-K-A is not a run")
		-- The 4th seven is better in the run 5-6-7 than in the set.
		local share = Melds.best({ C(7, S), C(7, H), C(7, D), C(7, CL), C(5, S), C(6, S) })
		T.eq(share.value, 0)
	end)

	T.test("draw then discard; can't throw back the card taken from the discard pile", function()
		local hand = { C(2, S), C(3, S), C(4, S), C(9, H), C(9, D), C(9, CL), C(13, H), C(12, D), C(11, CL), C(5, H) }
		local s = setup({ hand, filler(10) }, { C(10, S) }, filler(20))
		T.eq((GinRummy.validateMove(s, 1, { kind = "discard", card = C(2, S) })), false, "draw first")
		T.eq((GinRummy.validateMove(s, 2, { kind = "draw", from = "stock" })), false, "not your turn")
		T.eq((GinRummy.validateMove(s, 1, { kind = "draw", from = "elsewhere" })), false)
		apply(s, 1, { kind = "draw", from = "discard" })
		T.eq((GinRummy.validateMove(s, 1, { kind = "discard", card = C(10, S) })), false)
		T.eq((GinRummy.validateMove(s, 1, { kind = "discard", card = 99 })), false)
		apply(s, 1, { kind = "discard", card = C(13, H) })
		T.eq(s.turn, 2)
		T.eq(s.phase, "draw")
	end)

	T.test("you can only knock at 10 deadwood or less", function()
		local hand = { C(2, S), C(3, S), C(4, S), C(9, H), C(9, D), C(9, CL), C(13, H), C(12, D), C(11, CL), C(5, H) }
		local s = setup({ hand, filler(10) }, { C(1, D) }, filler(20))
		apply(s, 1, { kind = "draw", from = "stock" }) -- draws a Club filler
		T.eq((GinRummy.validateMove(s, 1, { kind = "knock", card = C(5, H) })), false, "30+ deadwood")
	end)

	T.test("knock: the defender lays off, the knocker scores the difference", function()
		-- Knocker after discarding the K: A-2-3 spades, 9 9 9, 5-6-7 hearts, 4 of diamonds (4 deadwood).
		local knocker = { C(1, S), C(2, S), C(3, S), C(9, H), C(9, D), C(9, CL), C(5, H), C(6, H), C(7, H), C(4, D) }
		-- Defender: 8 of hearts lays off on 5-6-7, 9 of spades onto the nines; 10 left over... plus a set.
		local defender = { C(8, H), C(9, S), C(10, D), C(10, CL), C(10, H), C(2, D), C(3, CL), C(13, D), C(13, CL), C(12, S) }
		local s = setup({ knocker, defender }, { C(6, CL) }, filler(20))
		apply(s, 1, { kind = "draw", from = "stock" })
		local drawn = s.hands[1][11]
		apply(s, 1, { kind = "knock", card = drawn })
		local show = s.showdown
		T.eq(show.kind, "knock")
		local d = show.hands["2"]
		T.eq(#d.layoffs, 2)
		-- Defender deadwood: 2 + 3 + 10 + 10 + 10 = 35. Knocker 4. Knocker scores 31.
		T.eq(d.value, 35)
		T.eq(s.scores[1], 31)
		T.eq(s.phase, "reveal")
		GinRummy.onTimeout(s)
		T.eq(s.phase, "draw")
		T.eq(#s.hands[1], 10)
		T.eq(s.turn, 2, "dealer swaps")
	end)

	T.test("gin scores 25 plus the other hand; an undercut pays the defender", function()
		local gin = { C(1, S), C(2, S), C(3, S), C(9, H), C(9, D), C(9, CL), C(5, H), C(6, H), C(7, H), C(8, H) }
		local s = setup({ gin, { C(2, D), C(3, CL), C(4, H), C(10, D), C(10, CL), C(10, H), C(10, S), C(13, S), C(12, CL), C(11, D) } }, { C(13, D) }, filler(20))
		apply(s, 1, { kind = "draw", from = "stock" })
		apply(s, 1, { kind = "knock", card = s.hands[1][11] })
		T.eq(s.showdown.kind, "gin")
		T.eq(s.scores[1], 25 + 2 + 3 + 4 + 30)

		local knocker = { C(1, S), C(2, S), C(3, S), C(9, H), C(9, D), C(9, CL), C(5, H), C(6, H), C(7, H), C(8, D) }
		local defender = { C(1, D), C(2, D), C(3, D), C(4, CL), C(4, H), C(4, S), C(11, CL), C(12, CL), C(13, CL), C(1, H) }
		local u = setup({ knocker, defender }, { C(13, D) }, filler(20))
		apply(u, 1, { kind = "draw", from = "stock" })
		apply(u, 1, { kind = "knock", card = u.hands[1][11] })
		T.eq(u.showdown.kind, "undercut")
		T.eq(u.scores[2], 25 + 8 - 1)
	end)

	T.test("a hand with 2 cards left in the stock is a wash", function()
		local s = setup({ filler(10), filler(10) }, { C(13, D) }, { C(5, D), C(6, D), C(7, D) })
		apply(s, 1, { kind = "draw", from = "stock" })
		apply(s, 1, { kind = "discard", card = s.hands[1][1] })
		T.eq(s.showdown.kind, "wash")
		T.eq(s.scores[1] + s.scores[2], 0)
	end)

	T.test("the view hides the other hand until the showdown", function()
		local s = GinRummy.new(2, nil, T.Random.new(3))
		local view = GinRummy.getView(s, 1)
		T.eq(#view.hand, 10)
		T.eq(view.showdown, nil)
		T.eq(GinRummy.getView(s, nil).hand, nil)
	end)

	T.test("bot games always finish", function()
		for _, level in { "easy", "medium", "hard" } do
			for seed = 1, 3 do
				local rng = T.Random.new(seed * 31 + #level)
				local s = GinRummy.new(2, { botLevel = level, rules = { target = 50 } }, rng)
				sim(GinRummy, s, rng, 20000)
				T.ok(GinRummy.getResult(s) ~= nil, `{level} game should finish`)
			end
		end
	end)
end
