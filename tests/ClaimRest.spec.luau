-- Claim the rest of the tricks (Trickster Cards) in Spades, Hearts and Oh Hell.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Games = ReplicatedStorage.Shared.Games
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)

return function(T)
	local S, H, D, C = 1, 2, 3, 4
	local function c(rank: number, suit: number): number
		return PlayingCards.make(rank, suit)
	end
	local function play(rules, s, seat, move)
		local ok, err = rules.validateMove(s, seat, move)
		assert(ok, err)
		rules.applyMove(s, seat, move)
	end

	-- Puts a 4-seat game mid-hand: seat 1 to lead the last 2 tricks with `mine`.
	local function lateHand(s, mine, others)
		s.hands = { mine, others[1], others[2], others[3] }
		s.trick = {}
		s.phase = "play"
		s.turn = 1
		s.tricksPlayed = 11
	end

	T.test("Spades: claim with top spades takes the last tricks", function()
		local Spades = require(Games.Spades)
		local s = Spades.new(4, { botLevel = "medium" }, T.Random.new(1))
		s.bids = { 3, 3, 3, 3 }
		lateHand(s, { c(1, S), c(13, S) }, { { c(2, H), c(3, H) }, { c(4, D), c(5, D) }, { c(6, C), c(7, C) } })
		s.tricks = { 2, 3, 3, 3 }
		T.eq(Spades.canClaim(s, 1), true)
		T.eq(Spades.getView(s, 1).canClaim, true)
		T.eq(Spades.getView(s, 2).canClaim, false)
		T.eq((Spades.validateMove(s, 2, { kind = "claim" })), false, "not your lead")
		play(Spades, s, 1, { kind = "claim" })
		T.eq(s.tricks[1], 4)
		T.eq(s.claim.tricks, 2)
		T.eq(#Spades.getView(s, 3).claim.cards, 2, "the claimer's cards are shown")
		Spades.onTimeout(s) -- the trick pause ends: score the hand
		T.ok(s.phase == "round" or s.phase == "done", "the hand is scored")
	end)

	T.test("Spades: no claim when someone could ruff or beat you", function()
		local Spades = require(Games.Spades)
		local s = Spades.new(4, { botLevel = "medium" }, T.Random.new(2))
		s.bids = { 3, 3, 3, 3 }
		lateHand(s, { c(1, H), c(13, H) }, { { c(2, S), c(3, D) }, { c(4, D), c(5, D) }, { c(6, C), c(7, C) } })
		T.eq(Spades.canClaim(s, 1), false, "a spade could ruff the hearts")
		T.eq((Spades.validateMove(s, 1, { kind = "claim" })), false)
	end)

	T.test("Hearts: the claimer takes every point left", function()
		local Hearts = require(Games.Hearts)
		local s = Hearts.new(4, { botLevel = "medium" }, T.Random.new(3))
		lateHand(s, { c(1, H), c(1, C) }, { { c(5, H), c(2, C) }, { c(12, S), c(3, C) }, { c(4, D), c(9, H) } })
		s.taken = { 0, 0, 0, 0 }
		T.eq(Hearts.canClaim(s, 1), true)
		play(Hearts, s, 1, { kind = "claim" })
		T.eq(s.taken[1], 3 + 13, "three hearts and the Queen of Spades")
		T.eq(s.claim.points, 16)
	end)

	T.test("Oh Hell: claim respects the trump suit", function()
		local OhHell = require(Games.OhHell)
		local s = OhHell.new(4, { botLevel = "medium" }, T.Random.new(4))
		s.handSize = 13
		s.bids = { 1, 1, 1, 1 }
		s.tricks = { 0, 0, 0, 0 }
		s.trump = D
		lateHand(s, { c(1, H), c(13, H) }, { { c(2, D), c(3, C) }, { c(4, C), c(5, C) }, { c(6, C), c(7, C) } })
		T.eq(OhHell.canClaim(s, 1), false, "a diamond could ruff")
		s.trump = nil
		T.eq(OhHell.canClaim(s, 1), true, "no trump this round")
		play(OhHell, s, 1, { kind = "claim" })
		T.eq(s.tricks[1], 2)
	end)
end
