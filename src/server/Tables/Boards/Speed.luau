-- Speed at the table: two center piles face up on their own trays, the side piles, and
-- each player's hand and draw pile in front of them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Models = require(script.Parent.Parent.Models)
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
			local tray = Cards.center(boardCF, x)
			Models.block(folder, "Tray", Vector3.new(Scene.CARD_W + 0.16, 0.02, Scene.CARD_H + 0.16), tray * CFrame.new(0, 0.01, 0), Models.GOLD)
			Scene.pile(folder, Cards.center(boardCF, x * 3.2), (view.sideCounts or {})[pile] or 0, false)
			local top = (view.tops or {})[pile]
			if top then
				Scene.card(folder, tray * CFrame.new(0, 0.02, 0), Scene.playingFront(PlayingCards, top))
			end
		end
	end)
end

return Speed
