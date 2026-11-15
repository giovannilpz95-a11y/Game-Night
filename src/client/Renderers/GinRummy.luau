-- Gin Rummy table: your opponent on top (cards and score), the stock and the discard pile
-- on the felt (tap one to draw), your hand at the bottom sorted into melds with the
-- deadwood last. After drawing, tap a card to throw it away, or press Knock first and
-- then tap the card to knock with. The showdown lays both hands out on the felt.
-- Drag a card along the hand to put it where you like (Gin Rummy Plus style); new
-- cards join on the right. A fresh deal goes back to the sorted order.
-- Each hand starts with the upcard offer: Take or Pass. In Table view (no felt) a small
-- card on the left keeps the score, target and what the other player picked up, and the
-- showdown and the end-of-game tally come up as panels over the hand.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Kit = require(script.Parent.Parent.UI.Kit)
local PlayingCard = require(script.Parent.Parent.UI.PlayingCard)
local CardTable = require(script.Parent.Parent.UI.CardTable)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local CardFx = require(script.Parent.Parent.UI.CardFx)
local Theme = Kit.Theme

local GinRummy = {}

local function meldText(meld: { number }): string
	local parts = {}
	for _, id in meld do
		table.insert(parts, PlayingCards.short(id))
	end
	return table.concat(parts, " ")
end

function GinRummy.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local ui = CardTable.layout(container)
	local knocking = false
	local render: () -> ()
	-- Your own card order once you've dragged one (nil = the server's sorted order).
	local myOrder: { number }? = nil
	local drag: { id: number, start: Vector2 }? = nil
	local connections: { RBXScriptConnection } = {}

	local function ordered(hand: { number }): { number }
		if not myOrder then
			return hand
		end
		local inHand = {}
		for _, id in hand do
			inHand[id] = true
		end
		local out, seen = {}, {}
		for _, id in myOrder do
			if inHand[id] then
				table.insert(out, id)
				seen[id] = true
			end
		end
		-- Most of the hand is new: a fresh deal, so go back to sorted.
		if #out < #hand / 2 then
			myOrder = nil
			return hand
		end
		for _, id in hand do
			if not seen[id] then
				table.insert(out, id)
			end
		end
		myOrder = out
		return out
	end

	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		local d = drag
		if not d or (input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch) then
			return
		end
		drag = nil
		local point = Vector2.new(input.Position.X, input.Position.Y)
		if math.abs(point.X - d.start.X) < 16 or not snapshot or not snapshot.view.hand then
			return
		end
		point += Vector2.new(0, GuiService:GetGuiInset().Y)
		-- Drop between the cards whose middles are either side of the pointer.
		local current = ordered(snapshot.view.hand)
		local slots = {}
		for _, slot in ui.hand:GetChildren() do
			if slot:IsA("Frame") and current[slot.LayoutOrder] then
				table.insert(slots, slot)
			end
		end
		table.sort(slots, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		local to = #slots
		for i, slot in slots do
			if point.X < slot.AbsolutePosition.X + slot.AbsoluteSize.X / 2 then
				to = i
				break
			end
		end
		local from = table.find(current, d.id)
		if not from then
			return
		end
		local list = table.clone(current)
		table.remove(list, from)
		table.insert(list, math.clamp(if to > from then to - 1 else to, 1, #list + 1), d.id)
		myOrder = list
		render()
	end))
	local calledRound: any = nil -- the hand whose showdown was already called out
	local piles: CardFx.StockPiles = {}
	local afterHand = CardFx.stockAndDiscard(ui.root, function(id: number)
		sendMove({ kind = "discard", card = id })
	end)

	local function nameOf(seat: number?): string
		return CardTable.nameOf(snapshot, seat)
	end

	-- One hand laid out in a row on the felt: melds, then deadwood (dimmed).
	-- `laidOn` = the other player's cards laid off on these melds (outlined).
	local function handRow(hand: any, y: number, label: string, laidOn: { number }?)
		local ids, dead, laid = {}, {}, {}
		for _, meld in hand.melds or {} do
			for _, id in meld do
				table.insert(ids, id)
			end
		end
		for _, id in laidOn or {} do
			table.insert(ids, id)
			laid[id] = true
		end
		for _, id in hand.deadwood or {} do
			table.insert(ids, id)
			dead[id] = true
		end
		Kit.label(label, { TextSize = 13, Font = Theme.FontBold, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0, 10, y, 0), Size = UDim2.new(0.3, 0, 0, 16), ZIndex = 6, Parent = ui.content })
		local row = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0.02, 0, y, 16), Size = UDim2.new(0.96, 0, 0.36, -16), ZIndex = 6, Parent = ui.content })
		local cards = {}
		for _, id in ids do
			table.insert(cards, { id = id, dim = dead[id] == true, glow = laid[id] == true })
		end
		PlayingCard.renderHand(row, cards, nil)
	end

	local function cardList(ids: { number }?): string
		local parts = {}
		for _, id in ids or {} do
			table.insert(parts, PlayingCards.short(id))
		end
		return table.concat(parts, " ")
	end

	-- The classic end-of-game tally (house rule Classic bonuses), in both views.
	local function openTally()
		local view = snapshot.view
		local final = view.final
		if not final then
			return
		end
		local rows = {}
		local function row(label: string, key: string, fmt: ((any) -> string)?)
			local r = { label }
			for seat = 1, 2 do
				local v = final[seat][key]
				table.insert(r, if fmt then fmt(v) else tostring(v))
			end
			table.insert(rows, r)
		end
		row("Points", "points")
		row(`Hands won (+{25} each)`, "boxes", function(v)
			return `+{v}`
		end)
		row("Game bonus", "game", function(v)
			return if v > 0 then `+{v}` else "-"
		end)
		row("Shutout", "shutout", function(v)
			return if v then "x2" else "-"
		end)
		CardTable.scoreSheet(ui, "Final tally", { "", nameOf(1), nameOf(2) }, rows, { "Total", tostring(final[1].total), tostring(final[2].total) })
	end

	local canDrawStock = false -- your turn to draw (the stock on the table is clickable)
	local tallied = false -- the end-of-game tally opened once by itself
	function render()
		local view = snapshot.view
		local me = snapshot.yourSeat
		local active = CardTable.isActive(snapshot, me)
		local offered = active and view.phase == "upcard"
		local drawing = active and view.phase == "draw"
		canDrawStock = drawing == true
		local discarding = active and view.phase == "discard"
		local them = if me then 3 - me else 2
		local you = if me then me else 1
		local knockable = {}
		for _, id in view.knockCards or {} do
			knockable[id] = true
		end
		if not discarding or next(knockable) == nil then
			knocking = false
		end

		CardTable.seatChips(ui.seats, snapshot, {
			{
				seat = them,
				bigLine = { text = `{view.scores[them]} pts` },
				lines = { `{view.handCounts[them]} cards · {view.handsWon[them]} hands won` },
				turn = view.turn == them and (view.phase == "upcard" or view.phase == "draw" or view.phase == "discard"),
			},
		})

		Kit.clear(ui.content)
		local scoreLine = `{if me then "You" else nameOf(1)} {view.scores[you]} · {nameOf(them)} {view.scores[them]} · to {view.target}`
		Kit.label(scoreLine, { TextSize = 12, TextColor3 = Theme.SubText, Position = UDim2.new(0, 10, 0, 6), Size = UDim2.new(0.5, 0, 0, 16), ZIndex = 6, Parent = ui.content })

		local show = view.showdown
		-- Gin, Undercut and Knock each get their big moment (Table view hides the felt).
		if show and show.kind ~= "wash" and calledRound ~= view.round then
			calledRound = view.round
			local text = if show.kind == "bigGin" then "BIG GIN!" elseif show.kind == "gin" then "GIN!" elseif show.kind == "undercut" then "UNDERCUT!" else "KNOCK!"
			HudKit.callout(ui.root, `{text}  {nameOf(show.winner)} +{show.points}` .. (if show.doubled then " (doubled)" else ""), if show.kind == "knock" then nil else Color3.fromRGB(120, 220, 150))
			-- And off the table in Table view.
			CardFx.pop(text, if show.kind == "knock" then Theme.Accent else Color3.fromRGB(120, 220, 150))
		end
		piles = {}
		if show then
			local title
			if show.kind == "wash" then
				title = "Stock ran out: no score this hand"
			else
				local who = nameOf(show.winner)
				if show.kind == "bigGin" then
					title = `{nameOf(show.knocker)} went Big Gin with all 11 cards! {who} +{show.points}`
				elseif show.kind == "gin" then
					title = `{nameOf(show.knocker)} went Gin! {who} +{show.points}`
				elseif show.kind == "undercut" then
					title = `Undercut! {who} +{show.points}`
				else
					title = `{nameOf(show.knocker)} knocked. {who} +{show.points}`
				end
			end
			CardTable.feltText(ui.content, title, 0.1, 17).TextColor3 = Theme.Accent
			if show.hands then
				-- The defender's lay offs sit with the knocker's melds, outlined.
				local order = { them, you }
				for i, seat in order do
					local hand = show.hands[tostring(seat)]
					if hand then
						local otherHand = show.hands[tostring(3 - seat)]
						local laidOn = if seat == show.knocker and otherHand then otherHand.layoffs else nil
						local laid = if hand.layoffs and #hand.layoffs > 0 then ` · laid off {#hand.layoffs}` else ""
						handRow(hand, if i == 1 then 0.24 else 0.62, `{nameOf(seat)}: {hand.value} deadwood{laid}`, laidOn)
					end
				end
			end
		else
			local stock = PlayingCard.slot({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.38, 0.55), Size = UDim2.fromScale(1, 0.62), Parent = ui.content })
			PlayingCard.show(stock, nil, true)
			local discard = PlayingCard.slot({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.62, 0.55), Size = UDim2.fromScale(1, 0.62), Parent = ui.content })
			piles = { stock = stock, discard = discard }
			if view.discardTop then
				local face = PlayingCard.show(discard, view.discardTop)
				if offered or (drawing and not view.stockOnly) then
					Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 4, Parent = face })
				end
			else
				PlayingCard.empty(discard)
			end
			if drawing then
				Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 4, Parent = stock:FindFirstChildWhichIsA("Frame") })
			end
			for _, pair in { { stock, "stock", `Stock {view.stockCount}` }, { discard, "discard", "Discard" } } do
				Kit.label(pair[3], { TextSize = 13, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 0, 1, 2), ZIndex = 6, Parent = pair[1] })
				local button = Kit.new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = pair[1] })
				Kit.onPress(button, function()
					if offered and pair[2] == "discard" then
						sendMove({ kind = "upcard", take = true })
					elseif drawing and (pair[2] == "stock" or (view.discardTop and not view.stockOnly)) then
						sendMove({ kind = "draw", from = pair[2] })
					end
				end)
			end
			local a = view.lastAction
			local text = ""
			if a and a.seat ~= me then
				if a.kind == "draw" then
					text = if a.from == "discard" then `{nameOf(a.seat)} took the {PlayingCards.name(a.card)}` else `{nameOf(a.seat)} drew from the stock`
				elseif a.kind == "discard" then
					text = `{nameOf(a.seat)} threw away the {PlayingCards.name(a.card)}`
				elseif a.kind == "pass" then
					text = `{nameOf(a.seat)} passed on the upcard`
				end
			end
			CardTable.feltText(ui.content, text, 0.12, 14)
			-- Your melds, so you can read the hand at a glance.
			local melds = {}
			for _, meld in view.melds or {} do
				table.insert(melds, meldText(meld))
			end
			if me then
				Kit.label(if #melds > 0 then `Melds: {table.concat(melds, "  |  ")}` else "No melds yet", { TextSize = 12, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.new(0, 8, 1, -20), Size = UDim2.new(1, -16, 0, 16), ZIndex = 6, Parent = ui.content })
			end
		end

		local buttons = {}
		if offered and view.discardTop then
			table.insert(buttons, { text = `Take {PlayingCards.short(view.discardTop)}`, color = Theme.Good, onClick = function()
				sendMove({ kind = "upcard", take = true })
			end })
			table.insert(buttons, { text = "Pass", color = Theme.PanelLight, onClick = function()
				sendMove({ kind = "upcard", take = false })
			end })
		end
		if drawing then
			-- Also as buttons, so Table view (which only keeps the bottom on screen) can draw.
			table.insert(buttons, { text = "Draw from stock", onClick = function()
				sendMove({ kind = "draw", from = "stock" })
			end })
			if view.discardTop and not view.stockOnly then
				table.insert(buttons, { text = `Take {PlayingCards.short(view.discardTop)}`, color = Theme.PanelLight, onClick = function()
					sendMove({ kind = "draw", from = "discard" })
				end })
			end
		end
		if discarding and view.canBigGin then
			-- All 11 cards are in melds: go out without throwing a card away.
			table.insert(buttons, { text = "Big Gin!", color = Theme.Good, onClick = function()
				knocking = false
				sendMove({ kind = "bigGin" })
			end })
		end
		if discarding and next(knockable) ~= nil then
			table.insert(buttons, {
				text = if knocking then "Cancel knock" elseif view.deadwood and view.deadwood == 0 then "Gin!" else "Knock",
				color = if knocking then Theme.PanelLight else Theme.Good,
				onClick = function()
					knocking = not knocking
					render()
				end,
			})
		end
		if view.final then
			table.insert(buttons, { text = "Final tally", color = Theme.PanelLight, onClick = openTally })
		end
		CardTable.buttons(ui.buttons, buttons)

		local dw = if view.deadwood then ` · deadwood {view.deadwood}` else ""
		if not me then
			ui.prompt.Text = "Watching"
		elseif snapshot.result then
			ui.prompt.Text = ""
		elseif offered then
			ui.prompt.Text = (if view.upcardPasses > 0 then `{nameOf(3 - me)} passed. ` else "") .. `Take the upcard or pass{dw}`
		elseif drawing and view.stockOnly then
			ui.prompt.Text = `You both passed: draw from the stock{dw}`
		elseif drawing then
			ui.prompt.Text = `Take the stock or the discard{dw}`
		elseif discarding and knocking then
			ui.prompt.Text = "Tap the card to knock with"
		elseif discarding then
			ui.prompt.Text = `Tap a card to throw away{dw}` .. (if view.canBigGin then " · all 11 melded: Big Gin!" elseif next(knockable) ~= nil then " · you can knock!" else "")
		elseif view.phase == "reveal" then
			ui.prompt.Text = "Next hand soon..."
		elseif view.phase == "upcard" then
			ui.prompt.Text = `{nameOf(view.turn)} is deciding on the upcard{dw}`
		else
			ui.prompt.Text = `{nameOf(view.turn)}'s turn{dw}`
		end

		-- Table view: the felt is hidden, so the running lines and the showdown go on top.
		local info = {
			`{if me then "You" else nameOf(you)} {view.scores[you]} · {nameOf(them)} {view.scores[them]}`,
			`Play to {view.target} · hand {view.round} of {view.maxHands} max`,
			if view.knockLimit == 0 then "Gin only this hand" else `Knock at {view.knockLimit} or less`,
		}
		if view.doubled then
			table.insert(info, "Spade upcard: this hand counts double")
		end
		local theirPicks = view.picked and view.picked[them]
		if theirPicks and #theirPicks > 0 then
			table.insert(info, `{nameOf(them)} picked up {cardList(theirPicks)}`)
		end
		local a = view.lastAction
		if a and a.seat == them and not show then
			if a.kind == "draw" then
				table.insert(info, if a.from == "discard" then `Just took the {PlayingCards.short(a.card)}` else "Just drew from the stock")
			elseif a.kind == "discard" then
				table.insert(info, `Just threw the {PlayingCards.short(a.card)}`)
			elseif a.kind == "pass" then
				table.insert(info, "Passed on the upcard")
			end
		end
		CardTable.info(ui, info)
		if show and show.kind == "wash" then
			CardTable.notice(ui, "Wash: no score", { "The stock ran down to 2 cards.", "The same dealer deals again." })
		elseif show and show.hands then
			local lines = {}
			for _, seat in { show.knocker, 3 - show.knocker } do
				local hand = show.hands[tostring(seat)]
				if hand then
					local laid = if hand.layoffs and #hand.layoffs > 0 then `, laid off {cardList(hand.layoffs)}` else ""
					local dead = if hand.deadwood and #hand.deadwood > 0 then ` ({cardList(hand.deadwood)})` else ""
					table.insert(lines, `{nameOf(seat)}: {hand.value} deadwood{dead}{laid}`)
				end
			end
			table.insert(lines, `{nameOf(show.winner)} +{show.points}` .. (if show.doubled then " (spade upcard: doubled)" else ""))
			local title = if show.kind == "bigGin" then `{nameOf(show.knocker)} went Big Gin!` elseif show.kind == "gin" then `{nameOf(show.knocker)} went Gin!` elseif show.kind == "undercut" then `Undercut! {nameOf(show.winner)} {if show.winner == snapshot.yourSeat then "win" else "wins"} the hand` else `{nameOf(show.knocker)} knocked`
			CardTable.notice(ui, title, lines, if show.kind == "knock" then nil else Theme.Good)
		else
			CardTable.notice(ui, nil)
		end
		if snapshot.result and view.final and not tallied then
			tallied = true
			openTally()
		end

		local inMeld = {}
		for _, meld in view.melds or {} do
			for _, id in meld do
				inMeld[id] = true
			end
		end
		local cards = {}
		for _, id in ordered(view.hand or {}) do
			local can = discarding and id ~= view.taken and (not knocking or knockable[id] == true)
			table.insert(cards, { id = id, raised = id == view.taken, glow = can, dim = discarding and not can, enabled = can })
		end
		local faces = PlayingCard.renderHand(ui.hand, cards, function(id: number)
			if not discarding or id == view.taken then
				return
			end
			if knocking then
				if knockable[id] then
					knocking = false
					sendMove({ kind = "knock", card = id })
				end
			else
				sendMove({ kind = "discard", card = id })
			end
		end)
		afterHand(snapshot, faces, piles, discarding and not knocking, function(id: number)
			return id ~= view.taken
		end)
		-- Press a card to drag it along the hand.
		for _, slot in ui.hand:GetChildren() do
			local entry = slot:IsA("Frame") and cards[slot.LayoutOrder]
			if entry then
				slot.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						drag = { id = entry.id, start = Vector2.new(input.Position.X, input.Position.Y) }
					end
				end)
			end
		end
		-- A thin bar under each card that's in a meld.
		for _, slot in ui.hand:GetChildren() do
			if slot:IsA("Frame") and cards[slot.LayoutOrder] and inMeld[cards[slot.LayoutOrder].id] then
				Kit.new("Frame", { BackgroundColor3 = Theme.Good, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.88, 2), Size = UDim2.new(0.8, 0, 0, 5), ZIndex = 6, Parent = slot })
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
		-- Table view: click the stock on the table to draw from it (it glows a little
		-- while you can). Table3D/SceneTap.
		tapTable = function(id: any)
			if id == "draw" and canDrawStock then
				sendMove({ kind = "draw", from = "stock" })
			end
		end,
		canTap = function(id: any): boolean
			return id == "draw" and canDrawStock
		end,
		tableMarks = function(): { [any]: any }?
			return if canDrawStock then { draw = "target" } else nil
		end,
		destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			ui.root:Destroy()
		end,
	}
end

return GinRummy
