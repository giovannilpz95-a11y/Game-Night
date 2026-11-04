-- Shared scene for trick-taking games (Hearts, Spades): hands face down and the cards of
-- the current trick face up in front of whoever played them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local Tricks = {}

-- Returns a create() that draws on a mat of `matColor`.
function Tricks.scene(matColor: Color3)
	return function(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
		return Cards.shell(boardCF, parent, layout, function(folder, view)
			for seat, count in view.handCounts or {} do
				Scene.hand(folder, boardCF, layout, seat, count)
			end
			local plays = view.trick or {}
			if #plays == 0 and view.lastTrick and view.phase == "trick" then
				plays = view.lastTrick.plays or {}
			end
			for _, play in plays do
				Scene.card(folder, Scene.seatSpot(boardCF, layout, play.seat, 2.5), Scene.playingFront(PlayingCards, play.card))
			end
		end, matColor)
	end
end

return Tricks
