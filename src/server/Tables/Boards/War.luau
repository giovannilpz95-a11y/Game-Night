-- War at the table: each player's pile in front of them, the battle's flipped cards face up
-- just inside, and a crossed-swords badge in the middle of the mat. In a war the tied cards
-- stay up, the face-down cards pile on the badge and the players in it call WAR!

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
		-- This battle's cards while it's on (the tie stays up during a war, with the face-down
		-- cards in the middle); the last battle's cards once it's settled.
		local war = view.war
		local current = view.flips or {}
		local inProgress = war ~= nil or next(current) ~= nil
		local lastRound = view.rounds and view.rounds[#view.rounds] or {}
		local flips = if inProgress then current else (view.lastBattle and view.lastBattle.flips or {})
		for seat, count in view.pileCounts or {} do
			Scene.pile(folder, Scene.seatSpot(boardCF, layout, seat, 0.9), count, true)
			local key = tostring(seat)
			local card = flips[key]
			if not card and war then
				card = war.carry[key] or (if table.find(war.seats, seat) then lastRound[key] else nil)
			end
			if card then
				Scene.card(folder, Scene.seatSpot(boardCF, layout, seat, 2.6), Scene.playingFront(PlayingCards, card))
			end
			if war and table.find(war.seats, seat) then
				Cards.speech(folder, boardCF, layout, seat, "WAR!", Color3.fromRGB(255, 170, 150))
			end
		end
		if (view.faceDownCount or 0) > 0 then
			-- The war's face-down cards, stacked on the badge.
			Scene.pile(folder, badge * CFrame.new(0, 0.07, 0), view.faceDownCount, true)
		end
	end, Color3.fromRGB(120, 44, 44))
end

return War
