-- President at the table: hands face down and the cards on top of the pile face up.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local President = {}

function President.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	local history = Cards.pileHistory()
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		for seat, count in view.handCounts or {} do
			Scene.hand(folder, boardCF, layout, seat, count)
		end
		-- Every play this round lands on one messy pile, turned toward whoever played it.
		local pile = view.pile
		local action = view.lastAction
		if not pile or #(pile.cards or {}) == 0 then
			history.clear()
		elseif history.seen(Cards.actionKey(action, view.round)) and action.kind == "play" then
			history.add(action.seat, action.cards or {})
		end
		if pile and #history.items == 0 then
			history.add(nil, pile.cards or {}) -- joined mid-round: just the top play
		end
		if pile then
			history.setTop(pile.cards or {})
		end
		Cards.messyPile(folder, boardCF, layout, Cards.center(boardCF, 0), history.items, function(id)
			return Scene.playingFront(PlayingCards, id)
		end)
	end, Color3.fromRGB(40, 56, 104))
end

return President
