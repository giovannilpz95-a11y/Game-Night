-- Thirty-One table: players along the top with their lives as hearts, the stock and the
-- discard pile on the felt, your 3 cards (and their value) at the bottom. Your turn: tap
-- the stock or the discard pile (or Knock), then tap a card to throw away. The showdown
-- shows every hand.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Parent.UI.Kit)
local PlayingCard = require(script.Parent.Parent.UI.PlayingCard)
local CardTable = require(script.Parent.Parent.UI.CardTable)
local Theme = Kit.Theme

local _ = ReplicatedStorage
local ThirtyOne = {}

function ThirtyOne.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local ui = CardTable.layout(container)

	local function nameOf(seat: number?): string
		return CardTable.nameOf(snapshot, seat)
	end

	local function hearts(n: number): string
		return if n <= 0 then "Out" else string.rep("♥", n)
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
				table.insert(chips, { seat = seat, lines = { hearts(view.lives[seat]), line2 }, turn = view.turn == seat and not showdown, dim = view.lives[seat] <= 0 })
			end
		end
		CardTable.seatChips(ui.seats, snapshot, chips)

		Kit.clear(ui.content)
		if showdown then
			local title = if showdown.blitz then `{nameOf(showdown.blitz)} hit 31! Blitz!` else "Showdown"
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
		elseif view.lives[me] <= 0 then
			ui.prompt.Text = "You're out of lives"
		elseif drawing then
			ui.prompt.Text = `Take from the stock or the discard pile{if view.canKnock then ", or knock" else ""}{valueText}`
		elseif discarding then
			ui.prompt.Text = `Tap a card to throw away{valueText}`
		elseif showdown then
			ui.prompt.Text = "Next deal soon..."
		else
			ui.prompt.Text = `{nameOf(view.turn)}'s turn{valueText}`
		end

		local cards = {}
		for _, id in view.hand or {} do
			local can = discarding and id ~= view.taken
			table.insert(cards, { id = id, raised = id == view.taken, glow = can, enabled = can })
		end
		PlayingCard.renderHand(ui.hand, cards, function(id: number)
			if discarding and id ~= view.taken then
				sendMove({ kind = "discard", card = id })
			end
		end)
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			render()
		end,
		destroy = function()
			ui.root:Destroy()
		end,
	}
end

return ThirtyOne
