-- Snap at the table: each player's face-down pile with its count, and their face-up pile
-- beside it with the top card showing, so everyone can spot a match, plus the Snap Pool in
-- the middle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local Snap = {}

function Snap.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		local said = view.lastAction
		if said and said.kind == "snap" then
			Cards.speech(folder, boardCF, layout, said.seat, "SNAP!", Color3.fromRGB(255, 226, 140))
		elseif said and said.kind == "badSnap" then
			Cards.speech(folder, boardCF, layout, said.seat, "Oops!", Color3.fromRGB(255, 190, 190))
		end
		-- The Snap Pool in the middle: wrong snaps go here, a match with its top wins it.
		local poolCount = view.poolCount or 0
		if poolCount > 0 then
			local cf = Scene.pile(folder, Cards.center(boardCF, 0), math.max(0, poolCount - 1), false)
			if view.poolTop then
				Scene.card(folder, cf, Scene.playingFront(PlayingCards, view.poolTop), 1.15)
			end
			Scene.floatText(folder, Cards.center(boardCF, 0) * CFrame.new(0, 1.1, 0), 2.6, 0.7, `Snap Pool · {poolCount}`, {
				TextColor3 = Color3.fromRGB(200, 205, 255),
				TextStrokeColor3 = Color3.fromRGB(20, 18, 30),
				TextStrokeTransparency = 0.2,
			})
		end
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
