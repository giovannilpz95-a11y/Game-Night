-- Thirty-One at the table: 3-card hands, the stock and the discard pile, and every hand
-- face up during the showdown.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local ThirtyOne = {}

function ThirtyOne.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	local history = Cards.pileHistory()
	local round = nil
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
		if view.lastAction and view.lastAction.kind == "knock" then
			Cards.speech(folder, boardCF, layout, view.lastAction.seat, "Knock knock!", Color3.fromRGB(255, 226, 160))
		end
		Scene.pile(folder, Cards.center(boardCF, -0.5), view.stockCount or 0, false)
		-- The discard pile: messy, each card turned toward whoever threw it away.
		local action = view.lastAction
		if history.seen(Cards.actionKey(action, view.round)) then
			if action.kind == "discard" then
				history.add(action.seat, { action.card })
			elseif action.kind == "draw" and action.from == "discard" then
				history.take(1)
			end
		end
		if round ~= view.round then
			round = view.round
			history.clear()
		end
		if view.discardTop then
			if #history.items == 0 then
				history.add(nil, { view.discardTop }) -- the upcard
			end
			history.setTop({ view.discardTop })
		else
			history.clear()
		end
		Cards.messyPile(folder, boardCF, layout, Cards.center(boardCF, 0.5), history.items, function(id)
			return Scene.playingFront(PlayingCards, id)
		end)
	end, Color3.fromRGB(36, 96, 84))
end

return ThirtyOne
