-- President at the table: hands face down and the cards on top of the pile face up.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local President = {}

function President.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		for seat, count in view.handCounts or {} do
			Scene.hand(folder, boardCF, layout, seat, count)
		end
		local pile = view.pile
		if pile then
			for i, id in pile.cards or {} do
				Scene.card(folder, Cards.center(boardCF, (i - (#pile.cards + 1) / 2) * 0.55) * CFrame.Angles(0, math.rad((i - 2) * 8), 0), Scene.playingFront(PlayingCards, id))
			end
		end
	end, Color3.fromRGB(40, 56, 104))
end

return President
