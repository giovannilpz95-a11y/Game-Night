-- President at the table: hands face down and the cards on top of the pile face up.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local President = {}

function President.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	local history = Cards.pileHistory()
	local clearedShown = false
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		for seat, count in view.handCounts or {} do
			Scene.hand(folder, boardCF, layout, seat, count)
		end
		-- Every play this round lands on one messy pile, turned toward whoever played it.
		-- Cards that clear the pile (2s, 8s) stay on it until the next play.
		local pile = view.pile
		local action = view.lastAction
		local fresh = history.seen(Cards.actionKey(action, view.round))
		if action and action.cleared and action.cards then
			if fresh then
				history.clear()
				history.add(action.seat, action.cards)
				clearedShown = true
			end
		elseif not pile or #(pile.cards or {}) == 0 then
			history.clear()
			clearedShown = false
		elseif fresh and action.kind == "play" then
			if clearedShown then
				history.clear()
				clearedShown = false
			end
			history.add(action.seat, action.cards or {})
		end
		if pile and #history.items == 0 then
			history.add(nil, pile.cards or {}) -- joined mid-round: just the top play
		end
		if pile then
			history.setTop(pile.cards or {})
		end
		-- Who passed gets a "Pass" bubble, like Thirty-One's knock.
		if action and action.kind == "pass" then
			Cards.speech(folder, boardCF, layout, action.seat, "Pass", Color3.fromRGB(220, 220, 235))
		end
		Cards.messyPile(folder, boardCF, layout, Cards.center(boardCF, 0), history.items, function(id)
			return Scene.playingFront(PlayingCards, id)
		end)
	end, Color3.fromRGB(40, 56, 104))
end

return President
