-- Speed at the table: two center piles face up, the side piles, and each player's hand
-- and draw pile in front of them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local Speed = {}

function Speed.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		for seat = 1, 2 do
			Scene.hand(folder, boardCF, layout, seat, (view.handCounts or {})[seat] or 0)
			local spot = Scene.seatSpot(boardCF, layout, seat, 0.9, 1.9)
			Scene.pile(folder, spot, (view.drawCounts or {})[seat] or 0, true)
		end
		for pile = 1, 2 do
			local x = if pile == 1 then -0.6 else 0.6
			Scene.pile(folder, Cards.center(boardCF, x * 3.2), (view.sideCounts or {})[pile] or 0, false)
			local top = (view.tops or {})[pile]
			if top then
				Scene.card(folder, Cards.center(boardCF, x), Scene.playingFront(PlayingCards, top))
			end
		end
	end)
end

return Speed
