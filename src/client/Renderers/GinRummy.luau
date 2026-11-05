-- Gin Rummy table: your opponent on top (cards and score), the stock and the discard pile
-- on the felt (tap one to draw), your hand at the bottom sorted into melds with the
-- deadwood last. After drawing, tap a card to throw it away, or press Knock first and
-- then tap the card to knock with. The showdown lays both hands out on the felt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
	local calledRound: any = nil -- the hand whose showdown was already called out
	local piles: CardFx.StockPiles = {}
	local afterHand = CardFx.stockAndDiscard(ui.root, function(id: number)
		sendMove({ kind = "discard", card = id })
	end)

	local function nameOf(seat: number?): string
		return CardTable.nameOf(snapshot, seat)
	end

	-- One hand laid out in a row on the felt: melds, then deadwood (dimmed).
	local function handRow(hand: any, y: number, label: string)
		local ids, dead = {}, {}
		for _, meld in hand.melds or {} do
			for _, id in meld do
				table.insert(ids, id)
			end
		end
		for _, id in hand.deadwood or {} do
			table.insert(ids, id)
			dead[id] = true
		end
		for _, id in hand.layoffs or {} do
			table.insert(ids, id)
		end
		Kit.label(label, { TextSize = 13, Font = Theme.FontBold, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0, 10, y, 0), Size = UDim2.new(0.3, 0, 0, 16), ZIndex = 6, Parent = ui.content })
		local row = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0.02, 0, y, 16), Size = UDim2.new(0.96, 0, 0.36, -16), ZIndex = 6, Parent = ui.content })
		local cards = {}
		for _, id in ids do
			table.insert(cards, { id = id, dim = dead[id] == true })
		end
		PlayingCard.renderHand(row, cards, nil)
	end

	function render()
		local view = snapshot.view
		local me = snapshot.yourSeat
		local active = CardTable.isActive(snapshot, me)
		local drawing = active and view.phase == "draw"
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
				turn = view.turn == them and (view.phase == "draw" or view.phase == "discard"),
			},
		})

		Kit.clear(ui.content)
		local scoreLine = `{if me then "You" else nameOf(1)} {view.scores[you]} · {nameOf(them)} {view.scores[them]} · to {view.target}`
		Kit.label(scoreLine, { TextSize = 12, TextColor3 = Theme.SubText, Position = UDim2.new(0, 10, 0, 6), Size = UDim2.new(0.5, 0, 0, 16), ZIndex = 6, Parent = ui.content })

		local show = view.showdown
		-- Gin, Undercut and Knock each get their big moment (Table view hides the felt).
		if show and show.kind ~= "wash" and calledRound ~= view.round then
			calledRound = view.round
			local text = if show.kind == "gin" then "GIN!" elseif show.kind == "undercut" then "UNDERCUT!" else "KNOCK!"
			HudKit.callout(ui.root, `{text}  {nameOf(show.winner)} +{show.points}`, if show.kind == "knock" then nil else Color3.fromRGB(120, 220, 150))
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
				if show.kind == "gin" then
					title = `{nameOf(show.knocker)} went Gin! {who} +{show.points}`
				elseif show.kind == "undercut" then
					title = `Undercut! {who} +{show.points}`
				else
					title = `{nameOf(show.knocker)} knocked. {who} +{show.points}`
				end
			end
			CardTable.feltText(ui.content, title, 0.1, 17).TextColor3 = Theme.Accent
			if show.hands then
				local order = { them, you }
				for i, seat in order do
					local hand = show.hands[tostring(seat)]
					if hand then
						local laid = if hand.layoffs and #hand.layoffs > 0 then ` · laid off {#hand.layoffs}` else ""
						handRow(hand, if i == 1 then 0.24 else 0.62, `{nameOf(seat)}: {hand.value} deadwood{laid}`)
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
				if drawing then
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
				button.Activated:Connect(function()
					if drawing and (pair[2] == "stock" or view.discardTop) then
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
		if drawing then
			-- Also as buttons, so Table view (which only keeps the bottom on screen) can draw.
			table.insert(buttons, { text = "Draw from stock", onClick = function()
				sendMove({ kind = "draw", from = "stock" })
			end })
			if view.discardTop then
				table.insert(buttons, { text = `Take {PlayingCards.short(view.discardTop)}`, color = Theme.PanelLight, onClick = function()
					sendMove({ kind = "draw", from = "discard" })
				end })
			end
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
		CardTable.buttons(ui.buttons, buttons)

		local dw = if view.deadwood then ` · deadwood {view.deadwood}` else ""
		if not me then
			ui.prompt.Text = "Watching"
		elseif snapshot.result then
			ui.prompt.Text = ""
		elseif drawing then
			ui.prompt.Text = `Take the stock or the discard{dw}`
		elseif discarding and knocking then
			ui.prompt.Text = "Tap the card to knock with"
		elseif discarding then
			ui.prompt.Text = `Tap a card to throw away{dw}` .. (if next(knockable) ~= nil then " · you can knock!" else "")
		elseif view.phase == "reveal" then
			ui.prompt.Text = "Next hand soon..."
		else
			ui.prompt.Text = `{nameOf(view.turn)}'s turn{dw}`
		end

		local inMeld = {}
		for _, meld in view.melds or {} do
			for _, id in meld do
				inMeld[id] = true
			end
		end
		local cards = {}
		for _, id in view.hand or {} do
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
		destroy = function()
			ui.root:Destroy()
		end,
	}
end

return GinRummy
