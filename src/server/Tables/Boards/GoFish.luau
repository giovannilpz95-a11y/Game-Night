-- Go Fish at the table: hands face down, the pond as a messy spread in the middle, and
-- each player's books face up beside them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local GoFish = {}

function GoFish.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	local rng = Random.new(7) -- same messy pond every redraw
	local spots = {}
	for i = 1, 52 do
		local a = rng:NextNumber() * math.pi * 2
		local d = math.sqrt(rng:NextNumber()) * 1.3
		spots[i] = CFrame.new(math.cos(a) * d, i * 0.004, math.sin(a) * d) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0)
	end
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		for seat, count in view.handCounts or {} do
			Scene.hand(folder, boardCF, layout, seat, count)
			for i, rank in (view.books or {})[seat] or {} do
				-- A book: one face-up card of that rank (spades), a little stack under it.
				local spot = Scene.seatSpot(boardCF, layout, seat, 2.4, (i - 2.5) * 0.55)
				Scene.pile(folder, spot, 3, false)
				Scene.card(folder, spot * CFrame.new(0, 0.06, 0), Scene.playingFront(PlayingCards, PlayingCards.make(rank, 1)))
			end
		end
		for i = 1, math.min(view.pondCount or 0, 52) do
			Scene.card(folder, Cards.center(boardCF, 0) * spots[i], nil)
		end
	end)
end

return GoFish
