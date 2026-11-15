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
local HudKit = require(script.Parent.Parent.UI.HudKit)
local Theme = Kit.Theme

local PresidentRenderer = {}

function PresidentRenderer.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local selected: { number } = {}
	local ui = CardTable.layout(container)
	local render: () -> ()
	local arrivals = CardFx.arrivals()
	local clears = CardFx.watch()
	local swapShown: number? = nil
	local autoPassKey: string? = nil

	local function nameOf(seat: number?): string
		return CardTable.nameOf(snapshot, seat)
	end

	local SETS = { "single", "pair", "triple", "four" }
	local function pileText(pile: any): string
		local r = PlayingCards.rankShort[PlayingCards.rank(pile.cards[1])]
		return if pile.count == 1 then `the {r}` else `the {SETS[pile.count]} of {r}s`
	end

	local function names(ids: { number }?): string
		local out = {}
		for _, id in ids or {} do
			table.insert(out, PlayingCards.short(id))
		end
		return table.concat(out, " ")
	end

	-- Every round's finishing order and points (BGA shows standings between rounds).
	local function openScores()
		local view = snapshot.view
		local n = #snapshot.seats
		local columns = { "Round" }
		for seat = 1, n do
			table.insert(columns, nameOf(seat))
		end
		local rows = {}
		for round, order in view.history or {} do
			local cells = { tostring(round) }
			for seat = 1, n do
				local place = table.find(order, seat)
				table.insert(cells, if place then `{President.roleName(place, n)} +{n - place}` else "")
			end
			table.insert(rows, cells)
		end
		local totals = { "Points" }
		for seat = 1, n do
			table.insert(totals, tostring(view.points[seat]))
		end
		CardTable.scoreSheet(ui, `Standings · round {view.round} of {view.rounds}`, columns, rows, totals)
	end

	function render()
		local view = snapshot.view
		local me = snapshot.yourSeat
		local active = CardTable.isActive(snapshot, me)
		local givingBack = active and view.phase == "giveback" and view.giveback ~= nil
		local myTurn = active and view.phase == "play"
		local n = #snapshot.seats
		if not myTurn and not givingBack then
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
		local summaryTitle, summaryLines = nil, nil
		if view.phase == "between" or view.phase == "done" then
			local lines = {}
			for place, seat in view.finished do
				table.insert(lines, `{place}. {nameOf(seat)}: {President.roleName(place, n)} (+{n - place}, {view.points[seat]} pts)`)
			end
			summaryTitle, summaryLines = "Round over!", lines
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
			local a = view.lastAction
			if pile then
				CardTable.cardRow(ui.content, pile.cards, { Position = UDim2.fromScale(0.2, 0.25), Size = UDim2.fromScale(0.6, 0.6) })
				CardTable.feltText(ui.content, `{nameOf(pile.seat)} played {pileText(pile)}. Beat it with {pile.count} higher.`, 0.86, 14)
			elseif a and a.cleared and a.cards then
				-- The 2s that cleared the pile stay in view for a moment.
				CardTable.cardRow(ui.content, a.cards, { Position = UDim2.fromScale(0.3, 0.3), Size = UDim2.fromScale(0.4, 0.45) })
				CardTable.feltText(ui.content, `{nameOf(a.seat)} cleared the pile and leads again`, 0.82, 15)
			else
				CardTable.feltText(ui.content, if view.turn == me then "Your lead: play any single, pair, triple or four" else `{nameOf(view.turn)} leads`, 0.45, 17)
			end
			-- The card swap at the start of a round.
			for _, e in view.exchange do
				if me and (e.from == me or e.to == me) and e.gave and view.round > 1 then
					local gave = if e.to == me then e.got else e.gave
					local got = if e.to == me then e.gave else e.got
					local text = `Card swap: you got {names(got)}` .. (if gave then `, you gave {names(gave)}` else "")
					CardTable.feltText(ui.content, text, 0.13, 14).TextColor3 = Theme.Good
				end
			end
		end
		-- The swap as a pop-up once both sides are known (the giver is told too).
		if me and view.phase == "play" and view.round > 1 and swapShown ~= view.round then
			for _, e in view.exchange do
				if (e.from == me or e.to == me) and e.gave and e.got then
					swapShown = view.round
					local gave = if e.to == me then e.got else e.gave
					local got = if e.to == me then e.gave else e.got
					HudKit.callout(ui.root, `You gave {names(gave)}, you got {names(got)}`, Theme.Good)
				end
			end
		end

		-- Table view: the felt is hidden, so the round, the pile to beat and the standings
		-- come up on screen instead.
		local info = { `Round {view.round} of {view.rounds}` }
		if view.phase == "play" then
			if view.pile then
				table.insert(info, `To beat: {pileText(view.pile)} ({nameOf(view.pile.seat)})`)
			else
				table.insert(info, `{nameOf(view.turn)} {if view.turn == me then "lead" else "leads"}`)
			end
			local passedNames = {}
			for key in view.passed do
				table.insert(passedNames, nameOf(tonumber(key)))
			end
			if #passedNames > 0 then
				table.insert(info, `Passed: {table.concat(passedNames, ", ")}`)
			end
		elseif view.phase == "giveback" then
			table.insert(info, "Card swap...")
		end
		if view.revolution then
			table.insert(info, "REVOLUTION: low beats high")
		end
		CardTable.info(ui, info)
		CardTable.notice(ui, summaryTitle, summaryLines)

		local playableSet = {}
		for _, id in view.playable or {} do
			playableSet[id] = true
		end
		local buttons = {}
		if #(view.history or {}) > 0 then
			table.insert(buttons, { text = "Standings", color = Theme.Panel, onClick = openScores })
		end
		if givingBack then
			table.insert(buttons, { text = `Give back {#selected}/{view.giveback}`, enabled = #selected == view.giveback, onClick = function()
				sendMove({ kind = "giveback", cards = selected })
				selected = {}
			end })
		elseif myTurn then
			local ok = #selected > 0 and PlayingCards.sameRank(selected) and playableSet[selected[1]] == true
			if ok and view.pile then
				local single = #selected == 1 and view.clearRank ~= nil and PlayingCards.rank(selected[1]) == view.clearRank
				ok = #selected == view.pile.count or single
			elseif ok and view.mustPlay then
				ok = table.find(selected, view.mustPlay) ~= nil
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
		elseif givingBack then
			ui.prompt.Text = `You got the Beggar's best cards. Pick {view.giveback} of yours to give back`
		elseif view.phase == "giveback" then
			ui.prompt.Text = "Card swap: waiting for the President to give cards back..."
		elseif myTurn and #(view.playable or {}) == 0 and view.pile then
			ui.prompt.Text = `Nothing beats {pileText(view.pile)}: passing...`
		elseif myTurn then
			ui.prompt.Text = (if view.revolution then "Revolution! Low beats high. " else "") .. (if view.pile then `Beat {pileText(view.pile)} or pass` elseif view.mustPlay then "Your lead: it must include the 3♣" else "Your lead")
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
			local could = myTurn and playableSet[id] == true
			table.insert(cards, { id = id, raised = table.find(selected, id) ~= nil, glow = could, dim = myTurn and not could, enabled = myTurn or givingBack })
		end
		-- Off your turn: all dimmed, the cards that could beat the pile lifted.
		local pile = view.pile
		if me and pile and not myTurn and view.phase == "play" and not snapshot.result then
			CardFx.offTurn(cards, function(id: number): boolean
				local p = President.power(id)
				return President.beats(p, pile.power, view.revolution) and counts[p] >= pile.count
			end)
		end
		local faces = PlayingCard.renderHand(ui.hand, cards, function(id: number)
			if givingBack then
				CardTable.toggle(selected, id, view.giveback)
				render()
				return
			end
			-- Picking a different rank starts a new selection.
			if #selected > 0 and PlayingCards.rank(selected[1]) ~= PlayingCards.rank(id) then
				selected = {}
			end
			CardTable.toggle(selected, id, 4)
			render()
		end)
		-- Nothing in your hand beats the pile: pass for you after a short beat (BGA's
		-- Automatic Turn Skip).
		if myTurn and view.pile and #(view.playable or {}) == 0 then
			local key = `{view.round}:{CardFx.key(view.lastAction, view.round) or ""}:{view.turn}`
			if autoPassKey ~= key then
				autoPassKey = key
				task.delay(1.4, function()
					if snapshot and snapshot.view and autoPassKey == key and CardTable.isActive(snapshot, snapshot.yourSeat) and snapshot.view.pile and #(snapshot.view.playable or {}) == 0 then
						sendMove({ kind = "pass" })
					end
				end)
			end
		end
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
		local fresh = clears(CardFx.key(a, view.round))
		if fresh and a and (a.kind == "clear" or a.cleared) then
			CardFx.pop("CLEAR!", Theme.Accent, ui.root)
		elseif fresh and a and a.skipped then
			CardFx.pop("SKIP!", Theme.Accent, ui.root)
		elseif fresh and a and a.downfall then
			HudKit.callout(ui.root, `Downfall! {nameOf(a.downfall)} drops to Beggar`, Color3.fromRGB(235, 87, 87))
		elseif fresh and a and a.flipped then
			-- Four of a kind: the order flips (Daifugō's revolution).
			HudKit.callout(ui.root, if a.revolution then "REVOLUTION! Low beats high" else "Counter-revolution! High beats low", Color3.fromRGB(235, 87, 87))
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
