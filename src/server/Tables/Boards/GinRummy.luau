-- Gin Rummy at the table: both hands in their holders, the stock and the discard pile in
-- the middle, and both hands face up in front of each player at the showdown.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local GinRummy = {}

function GinRummy.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	local history = Cards.pileHistory()
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		local showdown = view.showdown
		for seat, count in view.handCounts or {} do
			local shown = showdown and showdown.hands and showdown.hands[tostring(seat)]
			if shown then
				local cards = {}
				for _, meld in shown.melds or {} do
					for _, id in meld do
						table.insert(cards, id)
					end
				end
				for _, id in shown.deadwood or {} do
					table.insert(cards, id)
				end
				for i, id in cards do
					Scene.card(folder, Scene.seatSpot(boardCF, layout, seat, 1.3, (i - (#cards + 1) / 2) * 0.42) * CFrame.new(0, i * 0.004, 0), Scene.playingFront(PlayingCards, id))
				end
			else
				Scene.hand(folder, boardCF, layout, seat, count)
			end
		end
		Scene.pile(folder, Cards.center(boardCF, -0.6), view.stockCount or 0, true)
		-- The discard pile: messy, each card turned toward whoever threw it away.
		local action = view.lastAction
		local count = if view.discardTop then math.max(1, view.discardCount or 1) else 0
		if history.seen(Cards.actionKey(action, view.round)) and action.kind == "discard" and count > #history.items then
			history.add(action.seat, { action.card })
		end
		history.fit(count)
		if view.discardTop then
			history.setTop({ view.discardTop })
		end
		Cards.messyPile(folder, boardCF, layout, Cards.center(boardCF, 0.6), history.items, function(id)
			return Scene.playingFront(PlayingCards, id)
		end)
	end, Color3.fromRGB(40, 70, 110))
end

return GinRummy
