-- Old Maid at the table: hands in their holders and each player's pairs as one small
-- stack beside them, the last pair's card face up on top.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local OldMaid = {}

function OldMaid.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		for seat, count in view.handCounts or {} do
			-- The player being picked from may push a card up as bait: everyone sees it.
			Scene.hand(folder, boardCF, layout, seat, count, if seat == view.target and not view.over then view.lifted else nil)
			local pairs = (view.pairs or {})[seat] or {}
			if #pairs > 0 then
				-- One stack for all the pairs (never a pile of separate cards).
				local top = Scene.pile(folder, Scene.seatSpot(boardCF, layout, seat, 2.2), #pairs * 2 - 1, false)
				Scene.card(folder, top, Scene.playingFront(PlayingCards, PlayingCards.make(pairs[#pairs], 2)))
			end
		end
		-- At the end, the Old Maid lies face up in the middle.
		if (view.over or view.roundOver) and view.loser and view.oldMaid and view.oldMaid ~= 0 then
			Scene.card(folder, Cards.center(boardCF, 0), Scene.playingFront(PlayingCards, view.oldMaid), 1.4)
		end
	end, Color3.fromRGB(120, 70, 120))
end

return OldMaid
