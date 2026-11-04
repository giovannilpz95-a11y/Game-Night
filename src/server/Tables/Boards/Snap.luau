-- Snap at the table: each player's face-down pile with its count, and their face-up pile
-- beside it with the top card showing, so everyone can spot a match.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local Snap = {}

function Snap.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		for seat, count in view.downCounts or {} do
			Scene.pile(folder, Scene.seatSpot(boardCF, layout, seat, 0.9, -0.55), count, true)
			local top = (view.tops or {})[tostring(seat)]
			if top then
				local under = math.max(0, ((view.upCounts or {})[seat] or 1) - 1)
				local cf = Scene.pile(folder, Scene.seatSpot(boardCF, layout, seat, 1.6, 0.55), under, false)
				Scene.card(folder, cf, Scene.playingFront(PlayingCards, top), 1.15)
			end
		end
	end, Color3.fromRGB(176, 120, 40))
end

return Snap
