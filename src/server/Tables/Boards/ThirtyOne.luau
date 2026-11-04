-- Thirty-One at the table: 3-card hands, the stock and the discard pile, and every hand
-- face up during the showdown.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local ThirtyOne = {}

function ThirtyOne.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		local showdown = if view.phase == "reveal" or view.phase == "done" then view.showdown else nil
		for seat, count in view.handCounts or {} do
			local shown = showdown and showdown.hands and showdown.hands[tostring(seat)]
			if shown then
				for i, id in shown do
					Scene.card(folder, Scene.seatSpot(boardCF, layout, seat, 1.2, (i - 2) * 0.7), Scene.playingFront(PlayingCards, id))
				end
			else
				Scene.hand(folder, boardCF, layout, seat, count)
			end
		end
		Scene.pile(folder, Cards.center(boardCF, -0.5), view.stockCount or 0, false)
		if view.discardTop then
			Scene.card(folder, Cards.center(boardCF, 0.5), Scene.playingFront(PlayingCards, view.discardTop))
		end
	end)
end

return ThirtyOne
