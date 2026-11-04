-- I Doubt It at the table: hands face down, the growing pile in the middle, and the
-- cards turned over after a doubt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local Cheat = {}

function Cheat.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		for seat, count in view.handCounts or {} do
			Scene.hand(folder, boardCF, layout, seat, count)
		end
		Scene.pile(folder, Cards.center(boardCF, 0) * CFrame.Angles(0, math.rad(12), 0), view.pileCount or 0, true)
		local reveal = view.reveal
		if reveal and view.phase == "reveal" then
			for i, id in reveal.cards or {} do
				Scene.card(folder, Cards.center(boardCF, (i - (#reveal.cards + 1) / 2) * 0.8, 1.1), Scene.playingFront(PlayingCards, id))
			end
		end
	end)
end

return Cheat
