-- War at the table: each player's pile in front of them, the last battle's flipped cards
-- face up just inside, and a crossed-swords badge in the middle of the mat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Models = require(script.Parent.Parent.Models)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local War = {}

function War.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		local badge = Cards.center(boardCF, 0)
		Models.cyl(folder, "Badge", 1.1, 0.03, badge, Models.WALNUT, Enum.Material.Wood)
		for _, side in { 45, -45 } do
			local sword = badge * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, math.rad(side), 0)
			Models.block(folder, "Blade", Vector3.new(0.09, 0.03, 0.9), sword, Models.STEEL)
			Models.block(folder, "Guard", Vector3.new(0.3, 0.06, 0.06), sword * CFrame.new(0, 0.01, 0.28), Models.GOLD)
		end
		local flips = view.lastBattle and view.lastBattle.flips or {}
		for seat, count in view.pileCounts or {} do
			Scene.pile(folder, Scene.seatSpot(boardCF, layout, seat, 0.9), count, true)
			local card = flips[tostring(seat)]
			if card then
				Scene.card(folder, Scene.seatSpot(boardCF, layout, seat, 2.6), Scene.playingFront(PlayingCards, card))
			end
		end
	end, Color3.fromRGB(120, 44, 44))
end

return War
