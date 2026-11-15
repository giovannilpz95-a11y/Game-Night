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
		T.eq(s.phase, "upcard")
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

	T.test("the first upcard: non-dealer, then dealer may take it; both pass means stock only", function()
		local s = GinRummy.new(2, nil, T.Random.new(5))
		T.eq(s.phase, "upcard")
		local first = s.turn
		T.eq(first, 3 - s.dealer)
		T.eq((GinRummy.validateMove(s, first, { kind = "draw", from = "stock" })), false, "decide on the upcard first")
		T.eq((GinRummy.validateMove(s, first, { kind = "upcard", take = "yes" })), false)
		T.eq((GinRummy.validateMove(s, s.dealer, { kind = "upcard", take = true })), false, "not the dealer's turn yet")
		apply(s, first, { kind = "upcard", take = false })
		T.eq(s.turn, s.dealer)
		T.eq(s.phase, "upcard")
		apply(s, s.dealer, { kind = "upcard", take = false })
		T.eq(s.turn, first)
		T.eq(s.phase, "draw")
		T.eq((GinRummy.validateMove(s, first, { kind = "draw", from = "discard" })), false, "both passed: stock only")
		T.eq(#GinRummy.getLegalMoves(s, first), 1)
		apply(s, first, { kind = "draw", from = "stock" })
		T.eq(s.stockOnly, false)

		-- Taking it: it's your card, and you discard next (not that card).
		local t = GinRummy.new(2, nil, T.Random.new(6))
		local up = t.discard[#t.discard]
		local who = t.turn
		apply(t, who, { kind = "upcard", take = true })
		T.eq(t.phase, "discard")
		T.ok(table.find(t.hands[who], up) ~= nil)
		T.eq((GinRummy.validateMove(t, who, { kind = "discard", card = up })), false)
	end)

	T.test("after a wash the same dealer deals again", function()
		local s = setup({ filler(10), filler(10) }, { C(13, D) }, { C(5, D), C(6, D), C(7, D) })
		local dealer = s.dealer
		apply(s, 1, { kind = "draw", from = "stock" })
		apply(s, 1, { kind = "discard", card = s.hands[1][1] })
		T.eq(s.showdown.kind, "wash")
		GinRummy.onTimeout(s)
		T.eq(s.dealer, dealer)
	end)

	T.test("the hand limit grows with the target", function()
		T.eq(GinRummy.handLimit(50), 15)
		T.eq(GinRummy.handLimit(100), 25)
		T.eq(GinRummy.handLimit(150), 35)
		local s = GinRummy.new(2, { rules = { target = 150 } }, T.Random.new(1))
		T.eq(s.maxHands, 35)
	end)

	T.test("Oklahoma: a spade upcard doubles the hand", function()
		local knocker = { C(1, S), C(2, S), C(3, S), C(9, H), C(9, D), C(9, CL), C(5, H), C(6, H), C(7, H), C(4, D) }
		local defender = { C(8, H), C(9, S), C(10, D), C(10, CL), C(10, H), C(2, D), C(3, CL), C(13, D), C(13, CL), C(12, S) }
		local s = setup({ knocker, defender }, { C(6, CL) }, filler(20))
		s.doubled = true
		apply(s, 1, { kind = "draw", from = "stock" })
		apply(s, 1, { kind = "knock", card = s.hands[1][11] })
		T.eq(s.scores[1], 62, "31 doubled")
		T.eq(s.showdown.doubled, true)
		-- And the deal sets it from the upcard's suit.
		for seed = 1, 20 do
			local o = GinRummy.new(2, { rules = { oklahoma = true } }, T.Random.new(seed))
			T.eq(o.doubled, PlayingCards.suit(o.discard[1]) == S)
		end
	end)

	T.test("classic bonuses: game bonus, 25 per hand won, shutout doubles", function()
		local gin = { C(1, S), C(2, S), C(3, S), C(9, H), C(9, D), C(9, CL), C(5, H), C(6, H), C(7, H), C(8, H) }
		local s = setup({ gin, { C(2, D), C(3, CL), C(4, H), C(10, D), C(10, CL), C(10, H), C(10, S), C(13, S), C(12, CL), C(11, D) } }, { C(13, D) }, filler(20))
		s.scores = { 40, 0 }
		s.handsWon = { 2, 0 }
		apply(s, 1, { kind = "draw", from = "stock" })
		apply(s, 1, { kind = "knock", card = s.hands[1][11] })
		T.ok(s.over)
		local f = s.final
		T.eq(f[1].points, 104)
		T.eq(f[1].boxes, 75)
		T.eq(f[1].shutout, true)
		T.eq(f[1].total, (104 + 75) * 2 + 100)
		T.eq(f[2].total, 0)
		T.eq(GinRummy.getResult(s).winners[1], 1)
		T.ok(GinRummy.getView(s, 2).final ~= nil)
		-- Off: no tally.
		local o = GinRummy.new(2, { rules = { bonuses = false } }, T.Random.new(1))
		T.eq(o.bonuses, false)
	end)

	T.test("the knocker's melds are laid out to block lay offs", function()
		-- The 7S can sit in the run (4-5-6-7S + 7H 7D 7C) or in the set (4-5-6S + four 7s):
		-- no deadwood either way. Holding the 8S, the defender could lay off on the long run,
		-- so the knocker shows the four 7s and the short run.
		local options = Melds.bestOptions({ C(4, S), C(5, S), C(6, S), C(7, S), C(7, H), C(7, D), C(7, CL) })
		T.ok(#options >= 2, "several equal arrangements")
		for _, o in options do
			T.eq(o.value, 0)
		end
		local knocker = { C(4, S), C(5, S), C(6, S), C(7, S), C(7, H), C(7, D), C(7, CL), C(1, D), C(2, CL), C(1, CL) }
		local defender = { C(8, S), C(10, D), C(10, CL), C(10, H), C(2, D), C(3, CL), C(13, D), C(13, CL), C(12, S), C(11, H) }
		local s = setup({ knocker, defender }, { C(6, CL) }, { C(9, H), C(12, D), C(9, D) })
		apply(s, 1, { kind = "draw", from = "stock" }) -- the 9 of diamonds
		apply(s, 1, { kind = "knock", card = C(9, D) })
		local d = s.showdown.hands["2"]
		T.eq(#d.layoffs, 0, "the 8S has nowhere to go")
		T.eq(s.showdown.hands["1"].value, 4)
	end)

	T.test("big gin: all 11 cards melded after drawing goes out without a discard", function()
		-- A-2-3-4 spades, 9 9 9, 5-6-7 hearts; drawing the 8 of hearts melds all 11.
		local hand = { C(1, S), C(2, S), C(3, S), C(4, S), C(9, H), C(9, D), C(9, CL), C(5, H), C(6, H), C(7, H) }
		local defender = { C(13, D), C(13, CL), C(12, S), C(2, D), C(3, CL), C(10, D), C(11, CL), C(6, D), C(4, CL), C(8, D) }
		local s = setup({ hand, defender }, { C(8, H) }, filler(20))
		T.eq((GinRummy.validateMove(s, 1, { kind = "bigGin" })), false, "draw first")
		apply(s, 1, { kind = "draw", from = "discard" })
		T.eq(GinRummy.canBigGin(s, 1), true)
		T.eq(GinRummy.getView(s, 1).canBigGin, true)
		T.eq(GinRummy.chooseBotMove(s, 1, T.Random.new(3)).kind, "bigGin")
		local before = #s.discard
		apply(s, 1, { kind = "bigGin" })
		T.eq(#s.discard, before, "no discard")
		T.eq(s.showdown.kind, "bigGin")
		local dw = Melds.best(defender).value
		T.eq(s.showdown.points, GinRummy.BIG_GIN_BONUS + dw)
		T.eq(s.scores[1], GinRummy.BIG_GIN_BONUS + dw)
		T.eq(#s.showdown.hands["2"].layoffs, 0, "no laying off against gin")
	end)

	T.test("big gin: not with deadwood, and off by house rule", function()
		local hand = { C(1, S), C(2, S), C(3, S), C(4, S), C(9, H), C(9, D), C(9, CL), C(5, H), C(6, H), C(7, H) }
		local s = setup({ hand, filler(10) }, { C(13, D) }, filler(20))
		apply(s, 1, { kind = "draw", from = "discard" })
		T.eq((GinRummy.validateMove(s, 1, { kind = "bigGin" })), false, "the king is deadwood")
		local off = GinRummy.new(2, { botLevel = "medium", rules = { bigGin = false } }, T.Random.new(1))
		off.hands = { table.clone(hand), filler(10) }
		off.discard = { C(8, H) }
		off.stock = filler(20)
		off.turn, off.phase, off.taken = 1, "draw", nil
		apply(off, 1, { kind = "draw", from = "discard" })
		T.eq(GinRummy.canBigGin(off, 1), false)
		T.eq((GinRummy.validateMove(off, 1, { kind = "bigGin" })), false)
	end)
end
