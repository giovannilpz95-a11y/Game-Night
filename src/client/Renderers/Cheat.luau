-- I Doubt It table: players along the top, the face-down pile and the called rank in the
-- middle, your hand at the bottom. On your turn tap 1-4 cards and press Play (they're
-- claimed as the called rank, true or not). After someone plays, press "I doubt it!" or
-- "Believe" before the clock runs out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Kit = require(script.Parent.Parent.UI.Kit)
local PlayingCard = require(script.Parent.Parent.UI.PlayingCard)
local CardTable = require(script.Parent.Parent.UI.CardTable)
local CardFx = require(script.Parent.Parent.UI.CardFx)
local Theme = Kit.Theme

local Cheat = {}

function Cheat.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local selected: { number } = {}
	local ui = CardTable.layout(container)
	local arrivals = CardFx.arrivals()
	local reveals = CardFx.watch()

	local render: () -> ()

	local function nameOf(seat: number?): string
		return CardTable.nameOf(snapshot, seat)
	end

	function render()
		local view = snapshot.view
		local me = snapshot.yourSeat
		local active = CardTable.isActive(snapshot, me)
		local myTurn = active and view.phase == "play"
		local canDoubt = active and view.phase == "doubt"
		local plural = PlayingCards.rankPlural[view.called]
		local claims = view.claims or { view.called }
		if not myTurn then
			selected = {}
		end

		local chips = {}
		for seat = 1, #snapshot.seats do
			if seat ~= me then
				local status = ""
				if view.phase == "doubt" and view.lastPlay then
					status = if seat == view.lastPlay.seat then "played" elseif view.passed[tostring(seat)] then "believes" else "deciding..."
				end
				table.insert(chips, { seat = seat, lines = { `{view.handCounts[seat]} cards`, status }, turn = view.phase == "play" and view.turn == seat })
			end
		end
		CardTable.seatChips(ui.seats, snapshot, chips)

		Kit.clear(ui.content)
		local pile = PlayingCard.slot({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.22, 0.55), Size = UDim2.fromScale(1, 0.6), Parent = ui.content })
		if view.pileCount > 0 then
			PlayingCard.show(pile, nil, true)
		else
			PlayingCard.empty(pile)
		end
		Kit.label(`Pile: {view.pileCount}`, { TextSize = 13, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 0, 1, 2), ZIndex = 6, Parent = pile })

		local claim = view.lastPlay
		local reveal = view.reveal
		if view.phase == "reveal" and reveal then
			local verdict = if reveal.honest then `Honest! {nameOf(reveal.doubter)} picks up {reveal.count}.` else `Caught bluffing! {nameOf(reveal.seat)} picks up {reveal.count}.`
			CardTable.feltText(ui.content, `{nameOf(reveal.doubter)}: "I doubt it!"`, 0.04, 16)
			CardTable.feltText(ui.content, verdict, 0.16, 18).TextColor3 = if reveal.honest then Theme.Good else Theme.Bad
			local cards = {}
			for _, id in reveal.cards do
				table.insert(cards, id)
			end
			CardTable.cardRow(ui.content, cards, { Position = UDim2.fromScale(0.42, 0.34), Size = UDim2.fromScale(0.54, 0.6) })
		else
			CardTable.feltText(ui.content, if #claims > 1 then `Now playing: {PlayingCards.rankPlural[claims[1]]}, {plural} or {PlayingCards.rankPlural[claims[3]]}` else `Now playing: {plural}`, 0.06, 22).TextColor3 = Theme.Accent
			if claim then
				local n = claim.count
				CardTable.feltText(ui.content, `{nameOf(claim.seat)} played {n} {if n == 1 then "card" else "cards"} as {PlayingCards.rankPlural[claim.rank]}`, 0.26, 16)
			end
			if view.phase == "doubt" and claim then
				CardTable.feltText(ui.content, "Believe it?", 0.42, 16).TextColor3 = Theme.SubText
			end
		end

		local buttons = {}
		if myTurn and #claims > 1 then
			-- Up, down or same: one button per rank you may claim.
			local n = #selected
			for _, r in claims do
				table.insert(buttons, {
					text = if n == 0 then PlayingCards.rankPlural[r] else `{n} as {PlayingCards.rankPlural[r]}`,
					enabled = n > 0,
					onClick = function()
						if #selected > 0 then
							sendMove({ kind = "play", cards = selected, claim = r })
							selected = {}
						end
					end,
				})
			end
		elseif myTurn then
			local n = #selected
			table.insert(buttons, {
				text = if n == 0 then `Pick cards to play as {plural}` else `Play {n} as {plural}`,
				enabled = n > 0,
				onClick = function()
					if #selected > 0 then
						sendMove({ kind = "play", cards = selected })
						selected = {}
					end
				end,
			})
		elseif canDoubt then
			table.insert(buttons, { text = "I doubt it!", color = Theme.Bad, onClick = function()
				sendMove({ kind = "doubt" })
			end })
			table.insert(buttons, { text = "Believe", color = Theme.Good, onClick = function()
				sendMove({ kind = "pass" })
			end })
		end
		CardTable.buttons(ui.buttons, buttons)

		if not me then
			ui.prompt.Text = "Watching"
		elseif snapshot.result then
			ui.prompt.Text = ""
		elseif myTurn and #claims > 1 then
			ui.prompt.Text = `Your turn: play 1-4 cards as {PlayingCards.rankPlural[claims[1]]}, {plural} or {PlayingCards.rankPlural[claims[3]]}`
		elseif myTurn then
			ui.prompt.Text = `Your turn: play 1-4 cards as {plural}. Bluff if you have to!`
		elseif canDoubt then
			ui.prompt.Text = `Did {nameOf(claim and claim.seat)} really play {claim and claim.count or 0} {PlayingCards.rankPlural[claim and claim.rank or view.called]}?`
		elseif view.phase == "play" then
			ui.prompt.Text = `{nameOf(view.turn)} is playing {plural}...`
		else
			ui.prompt.Text = ""
		end

		local cards = {}
		for _, id in view.hand or {} do
			local isCalled = table.find(claims, PlayingCards.rank(id)) ~= nil
			table.insert(cards, { id = id, raised = table.find(selected, id) ~= nil, glow = myTurn and isCalled, enabled = myTurn })
		end
		local faces = PlayingCard.renderHand(ui.hand, cards, function(id: number)
			CardTable.toggle(selected, id, 4)
			render()
		end)
		-- Picking up the pile (or a new deal): the cards fly in from the middle.
		arrivals.update(faces, CardFx.middleOnScreen() or CardFx.guiOnScreen(pile))
		-- The doubt is settled: LIAR! or TRUTH! pops off the table, and whoever lost takes
		-- the pile.
		local r = view.reveal
		local key = if view.phase == "reveal" and r then `{r.seat}|{r.doubter}|{r.count}|{view.pileCount}|{#(view.hand or {})}` else nil
		if reveals(key or "none") and r and key then
			if r.honest then
				CardFx.pop("TRUTH!", Theme.Good, ui.root)
			else
				CardFx.pop("LIAR!", Theme.Bad, ui.root)
			end
			if r.loser ~= me then
				CardFx.dealTo(snapshot, r.loser, r.count, CardFx.middlePoint())
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

return Cheat
