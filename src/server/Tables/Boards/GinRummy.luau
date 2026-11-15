-- Gin Rummy at the table: both hands in their holders, the stock and the discard pile in
-- the middle, and both hands face up in front of each player at the showdown (the lay offs
-- next to the knocker's melds, deadwood grayed, totals floating above).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Scene = require(script.Parent.Parent.Scene)
local Cards = require(script.Parent._Cards)

local GinRummy = {}

function GinRummy.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	local history = Cards.pileHistory()
	return Cards.shell(boardCF, parent, layout, function(folder, view)
		local showdown = view.showdown
		for seat, count in view.handCounts or {} do
			local shown = showdown and showdown.hands and showdown.hands[tostring(seat)]
			if shown then
				-- Melds, then (on the knocker's side) the other player's lay offs, then the
				-- deadwood a little apart and grayed. "Deadwood 7" floats over each spread.
				local cards = {}
				for _, meld in shown.melds or {} do
					for _, id in meld do
						table.insert(cards, { id = id })
					end
				end
				local otherHand = showdown.hands[tostring(3 - seat)]
				if seat == showdown.knocker and otherHand then
					for _, id in otherHand.layoffs or {} do
						table.insert(cards, { id = id, laid = true })
					end
				end
				local gap = #cards
				for _, id in shown.deadwood or {} do
					table.insert(cards, { id = id, dead = true })
				end
				local width = (#cards - 1) * 0.42 + (if gap > 0 and gap < #cards then 0.3 else 0)
				for i, card in cards do
					local x = (i - 1) * 0.42 + (if card.dead and gap > 0 then 0.3 else 0) - width / 2
					local front = Scene.playingFront(PlayingCards, card.id)
					local cf = Scene.seatSpot(boardCF, layout, seat, 1.3, x) * CFrame.new(0, i * Scene.STACK, if card.laid then -0.25 else 0)
					Scene.card(folder, cf, if card.dead then { text = front.text, color = front.color, corner = front.corner, background = Color3.fromRGB(196, 196, 204) } else front)
				end
				local label = if (shown.value or 0) == 0 then "No deadwood" else `Deadwood {shown.value}`
				if shown.layoffs and #shown.layoffs > 0 then
					label ..= ` · laid off {#shown.layoffs}`
				end
				Scene.floatText(folder, Scene.seatSpot(boardCF, layout, seat, 1.3, 0) * CFrame.new(0, 0.9, 0), 3.2, 0.45, label, { TextColor3 = Color3.new(1, 1, 1), TextStrokeColor3 = Color3.fromRGB(20, 18, 30), TextStrokeTransparency = 0.2 })
			else
				Scene.hand(folder, boardCF, layout, seat, count)
			end
		end
		Scene.pile(folder, Cards.center(boardCF, -0.6), view.stockCount or 0, true, true)
		if view.lastAction and view.lastAction.kind == "pass" and view.phase ~= "reveal" then
			Cards.speech(folder, boardCF, layout, view.lastAction.seat, "Pass")
		end
		-- The discard pile: messy, each card turned toward whoever threw it away.
		local action = view.lastAction
		local count = if view.discardTop then math.max(1, view.discardCount or 1) else 0
		if history.seen(Cards.actionKey(action, view.round)) and action.kind == "discard" and count > #history.items then
			history.add(action.seat, { action.card })
		end
		history.fit(count)
		if view.discardTop then
			history.setTop({ view.discardTop })
		end
		Cards.messyPile(folder, boardCF, layout, Cards.center(boardCF, 0.6), history.items, function(id)
			return Scene.playingFront(PlayingCards, id)
		end)
	end, Color3.fromRGB(40, 70, 110))
end

return GinRummy
