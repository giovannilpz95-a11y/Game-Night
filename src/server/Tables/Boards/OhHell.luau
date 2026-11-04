-- Oh Hell at the table: the shared trick scene on a plum mat, with the turned-up trump
-- card lying beside the middle so everyone can see the trump suit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

return {
	create = require(script.Parent._Tricks).scene(Color3.fromRGB(86, 40, 78), function(folder, view, boardCF)
		if view.trumpCard and view.phase ~= "done" then
			Scene.card(folder, Cards.center(boardCF, 0, 0) * CFrame.Angles(0, math.rad(90), 0), Scene.playingFront(PlayingCards, view.trumpCard), 1.2)
		end
	end),
}
