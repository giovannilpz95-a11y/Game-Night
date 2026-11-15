local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tricks = require(ReplicatedStorage.Shared.Cards.Tricks)
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)

return function(T)
	local S, H, D, C = 1, 2, 3, 4
	local function c(rank: number, suit: number): number
		return PlayingCards.make(rank, suit)
	end

	T.test("claim the rest: only when every card is a sure winner", function()
		-- Seat 1 holds the top hearts and diamonds; nobody can ruff (no trump).
		local hands = {
			{ c(1, H), c(13, H), c(1, D) },
			{ c(5, H), c(2, D), c(3, C) },
			{ c(9, H), c(12, D), c(4, C) },
		}
		T.eq(Tricks.canClaim(hands, 1, nil), true)
		T.eq(Tricks.canClaim(hands, 2, nil), false, "lower cards can't claim")
		-- Someone holds a higher heart: no claim.
		hands[3][1] = c(1, S)
		hands[1][1] = c(12, H)
		hands[2][1] = c(13, H)
		T.eq(Tricks.canClaim(hands, 1, nil), false)
	end)

	T.test("claim the rest: trumps can ruff your side suits", function()
		local hands = {
			{ c(1, H), c(13, H) },
			{ c(2, S), c(5, D) }, -- void in hearts with a spade
			{ c(3, H), c(4, H) },
			{ c(6, H), c(7, D) },
		}
		T.eq(Tricks.canClaim(hands, 1, S), false, "a trump could ruff")
		T.eq(Tricks.canClaim(hands, 1, nil), true, "no trump this round")
		hands[1] = { c(1, S), c(13, S) }
		T.eq(Tricks.canClaim(hands, 1, S), true, "top trumps always win")
		hands[2][1] = c(5, C)
		hands[1] = { c(1, S), c(1, H) }
		T.eq(Tricks.canClaim(hands, 1, S), true, "nobody else has a trump")
		T.eq(Tricks.canClaim({ {}, { c(2, S) } }, 1, S), false, "nothing to claim")
	end)
end
