-- War at the table: each player's pile in front of them, and the last battle's flipped
-- cards face up just inside.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local War = {}

function War.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		local flips = view.lastBattle and view.lastBattle.flips or {}
		for seat, count in view.pileCounts or {} do
			Scene.pile(folder, Scene.seatSpot(boardCF, layout, seat, 0.9), count, true)
			local card = flips[tostring(seat)]
			if card then
				Scene.card(folder, Scene.seatSpot(boardCF, layout, seat, 2.6), Scene.playingFront(PlayingCards, card))
			end
		end
	end)
end

return War
