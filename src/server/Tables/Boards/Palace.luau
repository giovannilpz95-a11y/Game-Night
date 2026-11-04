-- Palace at the table: everyone's three face-down cards with the face-up cards on top,
-- hands, the draw pile and the play pile.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local Palace = {}

function Palace.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		for seat, count in view.handCounts or {} do
			Scene.hand(folder, boardCF, layout, seat, count)
			local ups = (view.up or {})[seat] or {}
			for i, slot in (view.down or {})[seat] or {} do
				local spot = Scene.seatSpot(boardCF, layout, seat, 2.1, (i - 2) * 0.7)
				if slot then
					Scene.card(folder, spot, nil)
				end
				local up = ups[i]
				if up then
					Scene.card(folder, spot * CFrame.new(0, 0.03, 0.15), Scene.playingFront(PlayingCards, up))
				end
			end
		end
		Scene.pile(folder, Cards.center(boardCF, -0.6), view.drawCount or 0, false)
		local top = view.pileTop or {}
		local cf = Scene.pile(folder, Cards.center(boardCF, 0.5), math.max(0, (view.pileCount or 0) - #top), false)
		for i, id in top do
			Scene.card(folder, cf * CFrame.new(0, i * 0.01, (i - #top) * 0.2), Scene.playingFront(PlayingCards, id))
		end
	end)
end

return Palace
