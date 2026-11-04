-- Slap Stack at the table: each player's face-down pile and the middle pile with its
-- top cards fanned so everyone can spot a double or a sandwich.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local SlapStack = {}

function SlapStack.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		for seat, count in view.pileCounts or {} do
			Scene.pile(folder, Scene.seatSpot(boardCF, layout, seat, 0.9), count, true)
		end
		local top = view.top or {}
		local under = math.max(0, (view.centerCount or 0) - #top)
		local cf = Scene.pile(folder, Cards.center(boardCF, 0), under, false)
		for i, id in top do
			local angle = (i - #top) * 14
			Scene.card(folder, cf * CFrame.new(0, i * 0.01, 0) * CFrame.Angles(0, math.rad(angle), 0), Scene.playingFront(PlayingCards, id))
		end
	end, Color3.fromRGB(130, 46, 52))
end

return SlapStack
