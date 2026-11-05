-- I Doubt It at the table: hands face down, the growing pile in the middle, and the
-- cards turned over after a doubt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local Cheat = {}

function Cheat.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	local history = Cards.pileHistory()
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		for seat, count in view.handCounts or {} do
			Scene.hand(folder, boardCF, layout, seat, count)
		end
		-- The pile is face down and messy, each card turned toward whoever put it there.
		local play = view.lastPlay
		local count = view.pileCount or 0
		if play and history.seen(`{play.seat}|{play.count}|{play.rank}|{count}`) and count > #history.items then
			history.add(play.seat, count - #history.items)
		end
		history.fit(count)
		Cards.messyPile(folder, boardCF, layout, Cards.center(boardCF, 0), history.items, nil, true)
		local reveal = view.reveal
		if reveal and view.phase == "reveal" then
			Cards.speech(folder, boardCF, layout, reveal.doubter, "I doubt it!", Color3.fromRGB(255, 200, 200))
		elseif play and view.phase == "doubt" then
			-- The claim, said out loud: the whole game is whether you believe it.
			Cards.speech(folder, boardCF, layout, play.seat, Cards.rankSaid(play.rank, play.count))
			for i, id in reveal.cards or {} do
				Scene.card(folder, Cards.center(boardCF, (i - (#reveal.cards + 1) / 2) * 0.8, 1.1), Scene.playingFront(PlayingCards, id))
			end
		end
	end, Color3.fromRGB(70, 52, 110))
end

return Cheat
