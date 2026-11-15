-- Thirty-One table: players along the top with their lives as hearts, the stock and the
-- discard pile on the felt, your 3 cards (and their value) at the bottom. Your turn: tap
-- the stock or the discard pile (or Knock), then tap a card to throw away. The showdown
-- shows every hand. In Table view (no felt) a small card on the left keeps the lives,
-- who knocked and the turns left, and the showdown comes up as a panel over the hand.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Kit = require(script.Parent.Parent.UI.Kit)
local PlayingCard = require(script.Parent.Parent.UI.PlayingCard)
local CardTable = require(script.Parent.Parent.UI.CardTable)
local CardFx = require(script.Parent.Parent.UI.CardFx)
local Theme = Kit.Theme

local ThirtyOne = {}

function ThirtyOne.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local ui = CardTable.layout(container)
	local piles: CardFx.StockPiles = {}
	local afterHand = CardFx.stockAndDiscard(ui.root, function(id: number)
		sendMove({ kind = "discard", card = id })
	end)
	local knocks = CardFx.watch()
	local blitzes = CardFx.watch()

	local function nameOf(seat: number?): string
		return CardTable.nameOf(snapshot, seat)
	end

	local function hearts(view: any, seat: number): string
		local n = view.lives[seat]
		if view.out and view.out[seat] then
			return "Out"
		end
		return if n <= 0 then "County" else string.rep("♥", n)
	end

	local function isOut(view: any, seat: number): boolean
		if view.out then
			return view.out[seat] == true
		end
		return view.lives[seat] <= 0
	end

	local function render()
		local view = snapshot.view
		local me = snapshot.yourSeat
		local active = CardTable.isActive(snapshot, me)
		local drawing = active and view.phase == "draw"
		local discarding = active and view.phase == "discard"
		local showdown = if view.phase == "reveal" or view.phase == "done" then view.showdown else nil

		local chips = {}
		for seat = 1, #snapshot.seats do
			if seat ~= me then
				local line2 = ""
				if showdown and showdown.values[tostring(seat)] then
					local lost = showdown.lost[tostring(seat)]
					line2 = `{showdown.values[tostring(seat)]}` .. (if lost then ` · -{lost} ♥` else "")
				elseif view.knocker == seat then
					line2 = "knocked!"
				end
				if line2 == "" and not isOut(view, seat) and view.lives[seat] <= 0 then
					line2 = "on the county"
				end
				table.insert(chips, { seat = seat, bigLine = { text = hearts(view, seat), color = Color3.fromRGB(240, 80, 100) }, lines = { line2 }, turn = view.turn == seat and not showdown, dim = isOut(view, seat) })
			end
		end
		CardTable.seatChips(ui.seats, snapshot, chips)

		Kit.clear(ui.content)
		piles = {}
		if knocks(if view.knocker then tostring(view.knocker) .. ":" .. tostring(view.round) else "none") and view.knocker then
			CardFx.pop("KNOCK!", Theme.Accent, ui.root)
		end
		if blitzes(if showdown and showdown.blitz then tostring(showdown.blitz) .. ":" .. tostring(view.round) else "none") and showdown and showdown.blitz then
			CardFx.pop("31!", Color3.fromRGB(120, 220, 150), ui.root)
		end
		if showdown then
			local title = if showdown.replay then "Everyone would go out: replay the hand" elseif showdown.blitz then `{nameOf(showdown.blitz)} hit 31! Blitz!` else "Showdown"
			CardTable.feltText(ui.content, title, 0.03, 18).TextColor3 = Theme.Accent
			local lines = {}
			for seat = 1, #snapshot.seats do
				local v = showdown.values[tostring(seat)]
				if v then
					local lost = showdown.lost[tostring(seat)]
					table.insert(lines, `{nameOf(seat)}: {v}` .. (if lost then `  (loses {lost} ♥)` else ""))
				end
			end
			Kit.label(table.concat(lines, "\n"), { TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromScale(0.05, 0.2), Size = UDim2.fromScale(0.9, 0.78), ZIndex = 6, Parent = ui.content })
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
				Kit.onPress(button, function()
					if drawing then
						sendMove({ kind = "draw", from = pair[2] })
					end
				end)
			end
			local a = view.lastAction
			local text = ""
			if view.knocker then
				text = `{nameOf(view.knocker)} knocked: last turns!`
			elseif a and a.kind == "discard" then
				text = if a.from == "discard" then `{nameOf(a.seat)} took from the discard pile` else `{nameOf(a.seat)} drew from the stock`
			end
			CardTable.feltText(ui.content, text, 0.03, 15)
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
		if drawing and view.canKnock then
			table.insert(buttons, { text = "Knock", color = Theme.Good, onClick = function()
				sendMove({ kind = "knock" })
			end })
		end
		CardTable.buttons(ui.buttons, buttons)

		local valueText = if view.handValue then ` · your hand: {view.handValue}` else ""
		if not me then
			ui.prompt.Text = "Watching"
		elseif snapshot.result then
			ui.prompt.Text = ""
		elseif isOut(view, me) then
			ui.prompt.Text = "You're out"
		elseif drawing and view.knocker then
			ui.prompt.Text = `Last turn! {nameOf(view.knocker)} knocked{valueText}`
		elseif drawing then
			ui.prompt.Text = `Take from the stock or the discard pile{if view.canKnock then ", or knock" else ""}{valueText}`
		elseif discarding then
			ui.prompt.Text = `Tap a card to throw away{valueText}`
		elseif showdown then
			ui.prompt.Text = "Next deal soon..."
		else
			ui.prompt.Text = `{nameOf(view.turn)}'s turn{valueText}`
		end

		-- Table view: the running lines on the left, the showdown over the hand.
		local info = {}
		if me then
			table.insert(info, `You: {hearts(view, me)}` .. (if not isOut(view, me) and view.lives[me] <= 0 then " (on the county)" else ""))
		end
		if view.knocker and not showdown then
			table.insert(info, `{nameOf(view.knocker)} knocked · {view.lastTurns or 0} turn{if view.lastTurns == 1 then "" else "s"} left`)
		elseif not showdown then
			table.insert(info, if view.canKnock then "You can knock" else "Knocking opens after one lap")
		end
		local others = {}
		for seat = 1, #snapshot.seats do
			if seat ~= me and not isOut(view, seat) then
				table.insert(others, `{nameOf(seat)} {hearts(view, seat)}`)
			end
		end
		if #others > 0 and #others <= 4 then
			for _, line in others do
				table.insert(info, line)
			end
		end
		CardTable.info(ui, info)
		if showdown then
			local lines = {}
			local order = {}
			for seat = 1, #snapshot.seats do
				if showdown.values[tostring(seat)] then
					table.insert(order, seat)
				end
			end
			table.sort(order, function(a, b)
				return showdown.values[tostring(a)] > showdown.values[tostring(b)]
			end)
			for _, seat in order do
				local lost = showdown.lost[tostring(seat)]
				local tag = ""
				if seat == showdown.knocker then
					tag ..= " (knocked)"
				end
				if lost and not showdown.replay then
					tag ..= `  -{lost} ♥`
					if table.find(showdown.out or {}, seat) then
						tag ..= ", out"
					elseif view.lives[seat] <= 0 then
						tag ..= ", on the county"
					end
				end
				table.insert(lines, `{nameOf(seat)}: {showdown.values[tostring(seat)]}{tag}`)
			end
			local title = if showdown.replay then "Everyone would go out: replay!" elseif showdown.blitz then `{nameOf(showdown.blitz)} hit 31! Blitz!` else "Showdown"
			CardTable.notice(ui, title, lines, if showdown.blitz then Theme.Good else nil)
		else
			CardTable.notice(ui, nil)
		end

		local cards = {}
		for _, id in view.hand or {} do
			local can = discarding and id ~= view.taken
			table.insert(cards, { id = id, raised = id == view.taken, glow = can, enabled = can })
		end
		local faces = PlayingCard.renderHand(ui.hand, cards, function(id: number)
			if discarding and id ~= view.taken then
				sendMove({ kind = "discard", card = id })
			end
		end)
		afterHand(snapshot, faces, piles, discarding, function(id: number)
			return id ~= view.taken
		end)
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

return ThirtyOne
