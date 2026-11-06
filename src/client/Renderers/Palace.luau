-- Palace table: other players along the top (hand size, table cards), the draw pile and
-- the play pile on the felt, your face-down and face-up table cards in a row above your
-- hand. Setup: tap a hand card, then one of your face-up cards to swap them, then Ready.
-- Play: tap cards of one rank and press Play (or Pick up). Blind: tap a face-down card.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Kit = require(script.Parent.Parent.UI.Kit)
local PlayingCard = require(script.Parent.Parent.UI.PlayingCard)
local CardTable = require(script.Parent.Parent.UI.CardTable)
local CardFx = require(script.Parent.Parent.UI.CardFx)
local Rules = require(ReplicatedStorage.Shared.Games.Palace)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local Theme = Kit.Theme

local Palace = {}

function Palace.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local shownBurn: string? = nil
	local selected: { number } = {}
	local swapFrom: number? = nil
	local ui = CardTable.layout(container)
	local render: () -> ()
	local arrivals = CardFx.arrivals()
	local moves = CardFx.watch()
	local drawSlot: Frame? = nil
	local tableRow: Frame? = nil
	local lastDrawCount: number? = nil

	local function nameOf(seat: number?): string
		return CardTable.nameOf(snapshot, seat)
	end

	local function tableCards(view, seat: number): number
		local n = #view.up[seat]
		for _, here in view.down[seat] do
			if here then
				n += 1
			end
		end
		return n
	end

	-- New cards fly into your hand from where they came from (the draw pile, the pile you
	-- picked up, your own table cards in setup); other players' pick-ups and refills fly to
	-- them; burns and pick-ups pop off the table.
	local function effects(view: any, me: number?, faces: { [any]: GuiObject })
		local a = view.lastAction
		local mine = a and a.seat == me
		local from
		if view.phase == "setup" then
			from = CardFx.seatOnScreen(snapshot, me) or CardFx.guiOnScreen(tableRow)
		elseif mine and (a.kind == "pickup" or (a.kind == "blind" and not a.ok)) then
			from = CardFx.middleOnScreen() or CardFx.guiOnScreen(ui.felt)
		else
			from = CardFx.pileOnScreen() or CardFx.guiOnScreen(drawSlot)
		end
		arrivals.update(faces, from)
		local drew = if lastDrawCount then math.max(0, lastDrawCount - (view.drawCount or 0)) else 0
		lastDrawCount = view.drawCount
		if not moves(CardFx.key(a, #(view.pileTop or {}))) or not a then
			return
		end
		if a.burned then
			CardFx.pop("🔥 BURN!", Color3.fromRGB(255, 140, 60))
		elseif a.kind == "pickup" or (a.kind == "blind" and not a.ok) then
			CardFx.pop(`+{a.count or 0}`, Theme.Bad)
		end
		if a.seat ~= me then
			if a.kind == "pickup" or (a.kind == "blind" and not a.ok) then
				CardFx.dealTo(snapshot, a.seat, a.count or 0, CardFx.middlePoint())
			elseif drew > 0 then
				CardFx.dealTo(snapshot, a.seat, drew)
			end
		end
	end

	function render()
		local view = snapshot.view
		local me = snapshot.yourSeat
		local active = CardTable.isActive(snapshot, me)
		local setup = active and view.phase == "setup"
		local myTurn = active and view.phase == "play"
		local source = view.source
		if not myTurn then
			selected = {}
		end
		if not setup then
			swapFrom = nil
		end

		local chips = {}
		for seat = 1, #snapshot.seats do
			if seat ~= me then
				local ups = {}
				for _, id in view.up[seat] do
					table.insert(ups, PlayingCards.short(id))
				end
				local line1 = if view.phase == "setup" then (if view.ready[seat] then "ready" else "arranging...") else `{view.handCounts[seat]} in hand · {tableCards(view, seat)} on table`
				table.insert(chips, { seat = seat, lines = { line1, `up: {table.concat(ups, " ")}` }, turn = view.phase == "play" and view.turn == seat })
			end
		end
		CardTable.seatChips(ui.seats, snapshot, chips)

		Kit.clear(ui.content)
		local draw = PlayingCard.slot({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.25, 0.52), Size = UDim2.fromScale(1, 0.55), Parent = ui.content })
		drawSlot = draw
		tableRow = nil
		if view.drawCount > 0 then
			PlayingCard.show(draw, nil, true)
		else
			PlayingCard.empty(draw)
		end
		Kit.label(`Draw {view.drawCount}`, { TextSize = 13, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 0, 1, 2), ZIndex = 6, Parent = draw })
		if #view.pileTop > 0 then
			CardTable.cardRow(ui.content, view.pileTop, { Position = UDim2.fromScale(0.42, 0.25), Size = UDim2.fromScale(0.5, 0.55) })
		else
			local empty = PlayingCard.slot({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.66, 0.52), Size = UDim2.fromScale(1, 0.55), Parent = ui.content })
			PlayingCard.empty(empty)
		end
		Kit.label(`Pile {view.pileCount} · burned {view.burned}`, { TextSize = 13, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0.42, 0, 0.84, 0), Size = UDim2.new(0.5, 0, 0, 16), ZIndex = 6, Parent = ui.content })
		local a = view.lastAction
		-- The burn moment, once per burn.
		local burnKey = if a and a.burned then `{a.seat}|{view.burned}` else nil
		if burnKey and burnKey ~= shownBurn and shownBurn ~= nil then
			HudKit.callout(ui.root, `🔥 BURN!  {nameOf(a.seat)} goes again`, Color3.fromRGB(235, 120, 40))
		end
		shownBurn = burnKey or shownBurn or ""
		local text = ""
		if a and a.kind == "play" then
			text = `{nameOf(a.seat)} played {#a.cards} × {PlayingCards.rankShort[PlayingCards.rank(a.cards[1])]}` .. (if a.burned then ". Burn! Goes again." else "")
		elseif a and a.kind == "pickup" then
			text = `{nameOf(a.seat)} picked up {a.count}`
		elseif a and a.kind == "blind" then
			text = if a.ok then `{nameOf(a.seat)} flipped {PlayingCards.short(a.card)}: it plays!` else `{nameOf(a.seat)} flipped {PlayingCards.short(a.card)} and picked up {a.count}`
		end
		CardTable.feltText(ui.content, text, 0.02, 14)

		-- Your table cards: face-down slots with face-up cards on top, along the felt bottom.
		if me then
			local row = Kit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromScale(0.5, 0.3), ZIndex = 6, Parent = ui.content })
			tableRow = row
			local list = Kit.list(6, true)
			list.HorizontalAlignment = Enum.HorizontalAlignment.Center
			list.Parent = row
			local ups = view.up[me] or {}
			for i, here in view.down[me] or {} do
				local up = ups[i]
				local slot = PlayingCard.slot({ Size = UDim2.fromScale(1, 1), SizeConstraint = Enum.SizeConstraint.RelativeYY, LayoutOrder = i, Parent = row })
				if up then
					local face = PlayingCard.show(slot, up)
					local picked = table.find(selected, up) ~= nil or swapFrom ~= nil
					if (myTurn and source == "up" and view.playable[tostring(up)]) or (setup and swapFrom) then
						Kit.new("UIStroke", { Color = Theme.Accent, Thickness = if picked then 4 else 2, Parent = face })
					end
				elseif here then
					local back = PlayingCard.show(slot, nil, true)
					if myTurn and source == "down" then
						Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 4, Parent = back })
					end
				else
					PlayingCard.empty(slot)
				end
				local button = Kit.new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 9, Parent = slot })
				button.Activated:Connect(function()
					if setup and swapFrom and up then
						sendMove({ kind = "swap", hand = swapFrom, up = up })
						swapFrom = nil
					elseif myTurn and source == "up" and up and view.playable[tostring(up)] then
						if #selected > 0 and PlayingCards.rank(selected[1]) ~= PlayingCards.rank(up) then
							selected = {}
						end
						CardTable.toggle(selected, up, 4)
						render()
					elseif myTurn and source == "down" and here then
						sendMove({ kind = "blind", index = i })
					end
				end)
			end
		end

		local buttons = {}
		if setup then
			table.insert(buttons, { text = "Ready", color = Theme.Good, onClick = function()
				sendMove({ kind = "ready" })
			end })
		elseif myTurn and source ~= "down" then
			local anyPlayable = next(view.playable) ~= nil
			if anyPlayable then
				table.insert(buttons, { text = if #selected == 0 then "Pick cards" else `Play {#selected}`, enabled = #selected > 0, onClick = function()
					sendMove({ kind = "play", cards = selected })
					selected = {}
				end })
			else
				table.insert(buttons, { text = `Pick up {view.pileCount}`, color = Theme.Bad, onClick = function()
					sendMove({ kind = "pickup" })
				end })
			end
		end
		CardTable.buttons(ui.buttons, buttons)

		if not me then
			ui.prompt.Text = "Watching"
		elseif snapshot.result then
			ui.prompt.Text = ""
		elseif setup then
			ui.prompt.Text = if swapFrom then "Now tap one of your face-up cards to swap" else "Swap: tap a hand card, then a face-up card. Press Ready when done."
		elseif view.phase == "setup" then
			ui.prompt.Text = "Waiting for everyone to get ready..."
		elseif myTurn then
			local top = view.pileTop[#view.pileTop]
			local need = if top and PlayingCards.rank(top) ~= 2 then `{PlayingCards.rankShort[PlayingCards.rank(top)]} or higher (or a 2 or 10)` else "anything"
			if top and view.sevenLower and PlayingCards.rank(top) == 7 then
				need = "7 or lower (or a 2 or 10)"
			end
			ui.prompt.Text = if source == "down" then "Flip one of your face-down cards!" elseif next(view.playable) == nil then "Nothing plays. Pick up the pile." else `Your turn: play {need}`
		else
			ui.prompt.Text = `{nameOf(view.turn)}'s turn`
		end

		local cards = {}
		for _, id in view.hand or {} do
			local can = myTurn and source == "hand" and view.playable[tostring(id)] == true
			table.insert(cards, {
				id = id,
				raised = table.find(selected, id) ~= nil or swapFrom == id,
				glow = can or (setup and swapFrom == id),
				dim = myTurn and source == "hand" and not can,
				enabled = can or setup,
			})
		end
		-- Off your turn: all dimmed, the cards that would go on the pile lifted.
		if me and view.phase == "play" and not myTurn and not snapshot.result then
			local pileTop = view.pileTop or {}
			CardFx.offTurn(cards, function(id: number): boolean
				return Rules.canPlay({ pile = pileTop, sevenLower = view.sevenLower }, id)
			end)
		end
		local faces = PlayingCard.renderHand(ui.hand, cards, function(id: number)
			if setup then
				swapFrom = if swapFrom == id then nil else id
				render()
			elseif myTurn and view.playable[tostring(id)] then
				if #selected > 0 and PlayingCards.rank(selected[1]) ~= PlayingCards.rank(id) then
					selected = {}
				end
				CardTable.toggle(selected, id, 4)
				render()
			end
		end)
		effects(view, me, faces)
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

return Palace
