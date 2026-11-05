-- Speed at the table: two center piles face up on their own trays, the side piles, and
-- each player's hand and draw pile in front of them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Models = require(script.Parent.Parent.Models)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local Speed = {}

function Speed.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	local histories = { Cards.pileHistory(), Cards.pileHistory() }
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		for seat = 1, 2 do
			Scene.hand(folder, boardCF, layout, seat, (view.handCounts or {})[seat] or 0)
			local spot = Scene.seatSpot(boardCF, layout, seat, 0.9, 1.9)
			Scene.pile(folder, spot, (view.drawCounts or {})[seat] or 0, true)
		end
		-- The center row runs across seat 1's view (cards upright for the players, not
		-- turned sideways), and the face-up piles are drawn bigger: they're the game.
		local dir = if layout.seats[1] then layout.seats[1].dir else Vector3.zAxis
		local center = CFrame.lookAt(boardCF.Position, boardCF:PointToWorldSpace(-dir), boardCF.UpVector) * CFrame.new(0, 0.04, 0)
		local BIG = 1.45
		for pile = 1, 2 do
			local x = if pile == 1 then -0.75 else 0.75
			local tray = center * CFrame.new(x, 0, 0)
			Models.block(folder, "Tray", Vector3.new(Scene.CARD_W * BIG + 0.16, 0.02, Scene.CARD_H * BIG + 0.16), tray * CFrame.new(0, 0.01, 0), Models.GOLD)
			Scene.pile(folder, center * CFrame.new(x * 3, 0, 0), (view.sideCounts or {})[pile] or 0, false)
			-- Messy: each card turned toward whoever slapped it down.
			local history = histories[pile]
			local count = (view.centerCounts or {})[pile] or 0
			local action = view.lastAction
			if history.seen(Cards.actionKey(action, count)) and count > #history.items then
				history.add(if action.kind == "play" and action.pile == pile then action.seat else nil, count - #history.items)
			end
			history.fit(count)
			local top = (view.tops or {})[pile]
			if top then
				history.setTop({ top })
			end
			Cards.messyPile(folder, boardCF, layout, tray * CFrame.new(0, 0.02, 0), history.items, function(id)
				return Scene.playingFront(PlayingCards, id)
			end, false, BIG)
		end
	end)
end

return Speed
