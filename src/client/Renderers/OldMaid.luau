-- Old Maid table: players along the top (cards left and pairs down), the hand being drawn
-- from on the felt, your hand at the bottom with the Old Maid outlined in red. On your
-- turn the two swap places: the cards you pick from move to the bottom row (the part
-- Table view keeps on screen) and your own hand moves up onto the felt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Kit = require(script.Parent.Parent.UI.Kit)
local PlayingCard = require(script.Parent.Parent.UI.PlayingCard)
local CardTable = require(script.Parent.Parent.UI.CardTable)
local CardFx = require(script.Parent.Parent.UI.CardFx)
local Theme = Kit.Theme

local OldMaid = {}

local MAID_RED = Color3.fromRGB(235, 70, 90)

function OldMaid.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local ui = CardTable.layout(container)
	local arrivals = CardFx.arrivals()
	local draws = CardFx.watch()
	local shownShuffles: number? = nil

	local function nameOf(seat: number?): string
		return CardTable.nameOf(snapshot, seat)
	end

	local function render()
		local view = snapshot.view
		local me = snapshot.yourSeat
		local myTurn = CardTable.isActive(snapshot, me) and view.turn == me
		local target = view.target

		local chips = {}
		for seat = 1, #snapshot.seats do
			if seat ~= me then
				local n = view.handCounts[seat] or 0
				local pairs = #(view.pairs[seat] or {})
				table.insert(chips, {
					seat = seat,
					bigLine = { text = if n == 0 then "Safe!" else `{n} cards`, color = if n == 0 then Theme.Good else nil },
					lines = { `{pairs} {if pairs == 1 then "pair" else "pairs"}` },
					turn = view.turn == seat and not view.over,
					highlight = myTurn and seat == target,
					dim = n == 0,
				})
			end
		end
		CardTable.seatChips(ui.seats, snapshot, chips)

		Kit.clear(ui.content)
		if view.over then
			local loserText = if view.loser == me then "You're left with the Old Maid!" elseif view.loser then `{nameOf(view.loser)} is left with the Old Maid!` else "Game over"
			CardTable.feltText(ui.content, loserText, 0.06, 20).TextColor3 = Theme.Accent
			local slot = PlayingCard.slot({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.6), Size = UDim2.fromScale(1, 0.62), Parent = ui.content })
			local face = PlayingCard.show(slot, view.oldMaid)
			Kit.new("UIStroke", { Color = MAID_RED, Thickness = 4, Parent = face })
		elseif myTurn then
			-- Your hand sits on the felt while you pick from the bottom row.
			CardTable.feltText(ui.content, "Your hand", 0.04, 15)
			local mine = {}
			for _, id in view.hand or {} do
				table.insert(mine, id)
			end
			CardTable.cardRow(ui.content, mine, { Position = UDim2.fromScale(0.04, 0.2), Size = UDim2.fromScale(0.92, 0.6), ZIndex = 6 })
		elseif target then
			-- The hand being drawn from, face down.
			local count = view.handCounts[target] or 0
			local picker = if view.turn == me then "Pick one of" else `{nameOf(view.turn)} picks from`
			local owner = if target == me then "your" else `{nameOf(target)}'s`
			CardTable.feltText(ui.content, `{picker} {owner} cards`, 0.04, 17).TextColor3 = if myTurn then Theme.Accent else Theme.Text
			local row = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromScale(0.04, 0.2), Size = UDim2.fromScale(0.92, 0.6), ZIndex = 6, Parent = ui.content })
			local backs = {}
			for _ = 1, count do
				table.insert(backs, false)
			end
			CardTable.cardRow(row, backs, { Size = UDim2.fromScale(1, 1) })
			if view.lifted and target ~= me then
				CardTable.feltText(ui.content, `☝ {nameOf(target)} lifted a card…`, 0.76, 14).TextColor3 = Theme.Accent
			end
		end

		-- Someone shuffled their hand in front of the drawer.
		if shownShuffles ~= nil and (view.shuffles or 0) > shownShuffles and not view.over then
			local who = if target == me then "You shuffle" else `{nameOf(target)} shuffles`
			CardFx.pop(`🔀 {who}!`, Theme.Accent, ui.root)
		end
		shownShuffles = view.shuffles or 0

		-- What just happened (the card itself only for the two players involved).
		local a = view.lastAction
		local seen = view.lastDrawn
		local text = ""
		if a and not view.over then
			if seen and seen.seat == me then
				text = `You took the {PlayingCards.name(seen.card)} from {nameOf(seen.from)}`
			elseif seen and seen.from == me then
				text = `{nameOf(seen.seat)} took your {PlayingCards.name(seen.card)}`
			else
				text = `{nameOf(a.seat)} took a card from {nameOf(a.from)}`
			end
			if a.rank then
				text ..= ` · pair of {PlayingCards.rankPlural[a.rank]}!`
			end
			for _, s in a.out or {} do
				text ..= ` · {nameOf(s)} {if s == me then "are" else "is"} safe`
			end
		end
		CardTable.feltText(ui.content, text, 0.84, 14)

		-- Being drawn from: shuffle in front of them (and tap a card below to lift it).
		CardTable.buttons(ui.buttons, if view.canTease then {
			{ text = "🔀 Shuffle", color = Theme.PanelLight, onClick = function()
				sendMove({ kind = "shuffle" })
			end },
		} else {})

		local holding = false
		for _, id in view.hand or {} do
			if id == view.oldMaid then
				holding = true
			end
		end
		local myCount = if me then view.handCounts[me] or 0 else 0
		if not me then
			ui.prompt.Text = "Watching"
		elseif snapshot.result then
			ui.prompt.Text = ""
		elseif myCount == 0 then
			ui.prompt.Text = "You're safe! Watch who ends up with the Old Maid"
		elseif myTurn then
			ui.prompt.Text = if view.lifted then `Your turn: {nameOf(target)} lifted a card. Bait or bluff?` else `Your turn: tap one of {nameOf(target)}'s cards below`
		elseif view.canTease then
			ui.prompt.Text = `{nameOf(view.turn)} is picking from you: shuffle, or tap a card to lift it as bait`
		else
			ui.prompt.Text = `{nameOf(view.turn)}'s turn` .. (if holding then " · you have the Old Maid, keep a straight face!" else "")
		end

		-- A pair pops off the table; other players' draws fly from the hand they took from.
		if draws(CardFx.key(a, `{view.turn}|{#(view.hand or {})}`)) and a and not view.over then
			if a.rank then
				CardFx.pop("PAIR!", Theme.Accent, ui.root)
			end
			if a.seat ~= me then
				CardFx.dealTo(snapshot, a.seat, 1, CardFx.seatPoint(snapshot, a.from, 0.78))
			end
		end

		if myTurn then
			-- The target's cards, face down, where your hand usually is: tap one to take it.
			local backs = {}
			for i = 1, view.handCounts[target] or 0 do
				table.insert(backs, { id = nil, key = i, glow = true, enabled = true, raised = view.lifted == i })
			end
			PlayingCard.renderHand(ui.hand, backs, function(index: number)
				sendMove({ kind = "draw", index = index })
			end)
			return
		end
		local cards = {}
		if view.offering and view.canTease then
			-- In the order they see it: tap a card to lift it out of the fan (tap again to
			-- drop it back).
			for i, id in view.offering do
				table.insert(cards, { id = id, enabled = true, raised = view.lifted == i })
			end
		else
			for _, id in view.hand or {} do
				table.insert(cards, { id = id, raised = id == view.oldMaid })
			end
		end
		local faces = PlayingCard.renderHand(ui.hand, cards, if view.canTease then function(id: number)
			local index = table.find(view.offering or {}, id)
			if index then
				sendMove({ kind = "lift", index = if view.lifted == index then 0 else index })
			end
		end else nil)
		-- The card you took flies in from that player's hand (the deal from the middle).
		local from = if seen and seen.seat == me then CardFx.seatOnScreen(snapshot, seen.from) else nil
		arrivals.update(faces, from or CardFx.middleOnScreen() or CardFx.guiOnScreen(ui.felt))
		-- Outline the Old Maid so you can't miss her.
		for _, slot in ui.hand:GetChildren() do
			if slot:IsA("Frame") and slot.LayoutOrder > 0 and cards[slot.LayoutOrder] and cards[slot.LayoutOrder].id == view.oldMaid then
				local face = slot:FindFirstChildWhichIsA("Frame")
				if face then
					Kit.new("UIStroke", { Color = MAID_RED, Thickness = 4, Parent = face })
				end
			end
		end
	end

	ui.refresh = function()
		if snapshot then
			render()
		end
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			render()
		end,
		setDocked = ui.setDocked,
		destroy = function()
			ui.root:Destroy()
		end,
	}
end

return OldMaid
