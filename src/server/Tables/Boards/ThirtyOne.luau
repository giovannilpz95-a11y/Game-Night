-- Thirty-One at the table: 3-card hands, the stock and the discard pile, and every hand
-- face up during the showdown.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local ThirtyOne = {}

function ThirtyOne.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	local history = Cards.pileHistory()
	local round = nil
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		local showdown = if view.phase == "reveal" or view.phase == "done" then view.showdown else nil
		for seat, count in view.handCounts or {} do
			local shown = showdown and showdown.hands and showdown.hands[tostring(seat)]
			if shown then
				for i, id in shown do
					Scene.card(folder, Scene.seatSpot(boardCF, layout, seat, 1.2, (i - 2) * 0.7) * CFrame.new(0, (i - 1) * Scene.STACK, 0), Scene.playingFront(PlayingCards, id))
				end
				-- "27  -1 ♥" over each hand, so Table view shows why hearts were lost.
				local key = tostring(seat)
				local lost = showdown.lost and showdown.lost[key]
				local label = tostring(showdown.values and showdown.values[key] or "")
				if lost and not showdown.replay then
					label ..= `  -{lost} ♥`
				end
				Scene.floatText(folder, Scene.seatSpot(boardCF, layout, seat, 1.2, 0) * CFrame.new(0, 0.8, 0), 2.4, 0.5, label, {
					TextColor3 = if lost and not showdown.replay then Color3.fromRGB(255, 120, 130) else Color3.new(1, 1, 1),
					TextStrokeColor3 = Color3.fromRGB(20, 18, 30),
					TextStrokeTransparency = 0.2,
				})
			else
				Scene.hand(folder, boardCF, layout, seat, count)
			end
		end
		if view.lastAction and view.lastAction.kind == "knock" then
			Cards.speech(folder, boardCF, layout, view.lastAction.seat, "Knock knock!", Color3.fromRGB(255, 226, 160))
		end
		-- The knocker keeps a marker until the showdown: everyone else is on a last turn.
		if view.knocker and not showdown then
			Scene.floatText(folder, Scene.seatSpot(boardCF, layout, view.knocker, 0.4, 0) * CFrame.new(0, 1.6, 0), 2.2, 0.45, "KNOCKED", {
				TextColor3 = Color3.fromRGB(255, 226, 160),
				TextStrokeColor3 = Color3.fromRGB(20, 18, 30),
				TextStrokeTransparency = 0.2,
			})
		end
		Scene.pile(folder, Cards.center(boardCF, -0.5), view.stockCount or 0, false, true)
		-- The discard pile: messy, each card turned toward whoever threw it away.
		local action = view.lastAction
		if history.seen(Cards.actionKey(action, view.round)) then
			if action.kind == "discard" then
				history.add(action.seat, { action.card })
			elseif action.kind == "draw" and action.from == "discard" then
				history.take(1)
			end
		end
		if round ~= view.round then
			round = view.round
			history.clear()
		end
		if view.discardTop then
			if #history.items == 0 then
				history.add(nil, { view.discardTop }) -- the upcard
			end
			history.setTop({ view.discardTop })
		else
			history.clear()
		end
		Cards.messyPile(folder, boardCF, layout, Cards.center(boardCF, 0.5), history.items, function(id)
			return Scene.playingFront(PlayingCards, id)
		end)
	end, Color3.fromRGB(36, 96, 84))
end

return ThirtyOne
