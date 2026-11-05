-- President table: players along the top (cards left, passed, role), the cards to beat
-- in the middle, your hand at the bottom. Tap cards of one rank and press Play, or Pass.
-- Between rounds the felt shows the standings and the card swap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local President = require(ReplicatedStorage.Shared.Games.President)
local Kit = require(script.Parent.Parent.UI.Kit)
local PlayingCard = require(script.Parent.Parent.UI.PlayingCard)
local CardTable = require(script.Parent.Parent.UI.CardTable)
local CardFx = require(script.Parent.Parent.UI.CardFx)
local Theme = Kit.Theme

local PresidentRenderer = {}

function PresidentRenderer.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local selected: { number } = {}
	local ui = CardTable.layout(container)
	local render: () -> ()
	local arrivals = CardFx.arrivals()
	local clears = CardFx.watch()

	local function nameOf(seat: number?): string
		return CardTable.nameOf(snapshot, seat)
	end

	function render()
		local view = snapshot.view
		local me = snapshot.yourSeat
		local myTurn = CardTable.isActive(snapshot, me)
		local n = #snapshot.seats
		if not myTurn then
			selected = {}
		end

		local chips = {}
		for seat = 1, n do
			if seat ~= me then
				local place = view.places[tostring(seat)]
				local status = if place then President.roleName(place, n) elseif view.passed[tostring(seat)] then "passed" else `{view.handCounts[seat]} cards`
				local role = view.roles[tostring(seat)]
				table.insert(chips, { seat = seat, lines = { status, `{view.points[seat]} pts` .. (if role then ` · {role}` else "") }, turn = view.turn == seat and view.phase == "play", dim = place ~= nil })
			end
		end
		CardTable.seatChips(ui.seats, snapshot, chips)

		Kit.clear(ui.content)
		CardTable.feltText(ui.content, `Round {view.round} of {view.rounds}`, 0.03, 14).TextColor3 = Theme.SubText
		if view.phase == "between" or view.phase == "done" then
			local lines = {}
			for place, seat in view.finished do
				table.insert(lines, `{place}. {nameOf(seat)}: {President.roleName(place, n)}`)
			end
			CardTable.feltText(ui.content, "Round over!", 0.14, 20).TextColor3 = Theme.Accent
			Kit.label(table.concat(lines, "\n"), {
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Top,
				Position = UDim2.fromScale(0.05, 0.3),
				Size = UDim2.fromScale(0.9, 0.68),
				ZIndex = 6,
				Parent = ui.content,
			})
		else
			local pile = view.pile
			if pile then
				CardTable.cardRow(ui.content, pile.cards, { Position = UDim2.fromScale(0.2, 0.25), Size = UDim2.fromScale(0.6, 0.6) })
				CardTable.feltText(ui.content, `{nameOf(pile.seat)} played. Beat it with {pile.count} higher.`, 0.86, 14)
			else
				CardTable.feltText(ui.content, if view.turn == me then "Your lead: play any single, pair, triple or four" else `{nameOf(view.turn)} leads`, 0.45, 17)
			end
			-- The card swap at the start of a round.
			for _, e in view.exchange do
				if me and (e.from == me or e.to == me) and e.gave and view.round > 1 then
					local gotText = {}
					for _, id in (if e.to == me then e.gave else e.got) do
						table.insert(gotText, PlayingCards.short(id))
					end
					CardTable.feltText(ui.content, `Card swap: you got {table.concat(gotText, " ")}`, 0.13, 14).TextColor3 = Theme.Good
				end
			end
		end

		local buttons = {}
		if myTurn then
			local ok = #selected > 0 and PlayingCards.sameRank(selected)
			if ok and view.pile then
				ok = #selected == view.pile.count and President.power(selected[1]) > view.pile.power
			end
			table.insert(buttons, { text = if #selected == 0 then "Pick cards" else `Play {#selected}`, enabled = ok, onClick = function()
				sendMove({ kind = "play", cards = selected })
				selected = {}
			end })
			if view.pile then
				table.insert(buttons, { text = "Pass", color = Theme.PanelLight, onClick = function()
					sendMove({ kind = "pass" })
				end })
			end
		end
		CardTable.buttons(ui.buttons, buttons)

		if not me then
			ui.prompt.Text = "Watching"
		elseif snapshot.result then
			ui.prompt.Text = ""
		elseif view.places[tostring(me)] then
			ui.prompt.Text = `You're out: {President.roleName(view.places[tostring(me)], n)}!`
		elseif myTurn then
			ui.prompt.Text = if view.pile then "Your turn: beat it or pass" else "Your lead"
		elseif view.phase == "play" then
			ui.prompt.Text = `{nameOf(view.turn)}'s turn`
		else
			ui.prompt.Text = "Next round soon..."
		end

		-- Cards that could beat the pile glow.
		local cards = {}
		local counts = {}
		for _, id in view.hand or {} do
			local p = President.power(id)
			counts[p] = (counts[p] or 0) + 1
		end
		for _, id in view.hand or {} do
			local p = President.power(id)
			local could = myTurn and (view.pile == nil or (p > view.pile.power and counts[p] >= view.pile.count))
			table.insert(cards, { id = id, raised = table.find(selected, id) ~= nil, glow = could, dim = myTurn and not could, enabled = myTurn })
		end
		-- Off your turn: all dimmed, the cards that could beat the pile lifted.
		local pile = view.pile
		if me and pile and not myTurn and view.phase == "play" and not snapshot.result then
			CardFx.offTurn(cards, function(id: number): boolean
				local p = President.power(id)
				return p > pile.power and counts[p] >= pile.count
			end)
		end
		local faces = PlayingCard.renderHand(ui.hand, cards, function(id: number)
			-- Picking a different rank starts a new selection.
			if #selected > 0 and PlayingCards.rank(selected[1]) ~= PlayingCards.rank(id) then
				selected = {}
			end
			CardTable.toggle(selected, id, 4)
			render()
		end)
		-- A new deal flies in from the middle; swapped cards from whoever gave them.
		local from = CardFx.middleOnScreen() or CardFx.guiOnScreen(ui.felt)
		for _, e in view.exchange or {} do
			if me and e.to == me and e.gave and e.from then
				from = CardFx.seatOnScreen(snapshot, e.from) or from
			end
		end
		arrivals.update(faces, from)
		-- The pile is cleared (everyone passed, or a 2): it pops off the table.
		local a = view.lastAction
		if clears(CardFx.key(a, view.round)) and a and a.kind == "clear" then
			CardFx.pop("CLEAR!", Theme.Accent, ui.root)
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

return PresidentRenderer
