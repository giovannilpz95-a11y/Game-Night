-- Oh Hell table: the other players along the top (score, bid, tricks won), the round, hand
-- size and trump card in the felt's corner, the trick in the middle (each card in front of
-- whoever played it), your hand at the bottom. Bidding: - / Bid N / +, with the dealer's
-- banned number greyed out. Playing: tap a glowing card.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Kit = require(script.Parent.Parent.UI.Kit)
local PlayingCard = require(script.Parent.Parent.UI.PlayingCard)
local CardTable = require(script.Parent.Parent.UI.CardTable)
local Theme = Kit.Theme

local OhHell = {}

function OhHell.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local bid = 1
	local bidRound = -1
	local ui = CardTable.layout(container)
	local render: () -> ()

	local function nameOf(seat: number?): string
		return CardTable.nameOf(snapshot, seat)
	end

	function render()
		local view = snapshot.view
		local me = snapshot.yourSeat
		local n = #snapshot.seats
		local active = CardTable.isActive(snapshot, me)
		local bidding = active and view.phase == "bid"
		local myTurn = active and view.phase == "play"

		if view.round ~= bidRound then
			bidRound = view.round
			bid = math.min(1, view.handSize)
		end
		bid = math.clamp(bid, 0, view.handSize)

		local chips = {}
		for i = 1, if me then n - 1 else n do
			local seat = ((me or n) - 1 + i) % n + 1
			local b = view.bids[tostring(seat)]
			table.insert(chips, {
				seat = seat,
				bigLine = { text = `{view.scores[seat]} pts` },
				lines = { `{if b == nil then "bidding" else `bid {b}`} · won {view.tricks[seat]}` .. (if seat == view.dealer then " · D" else "") },
				turn = view.turn == seat and (view.phase == "bid" or view.phase == "play"),
			})
		end
		CardTable.seatChips(ui.seats, snapshot, chips)

		Kit.clear(ui.content)
		-- Round info and the trump card, top left.
		Kit.label(`Round {view.round}/{view.rounds} · {view.handSize} {if view.handSize == 1 then "card" else "cards"}\nTrump {PlayingCards.suitSymbols[view.trump]} {PlayingCards.suitNames[view.trump]}`, {
			TextSize = 12,
			TextColor3 = Theme.SubText,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.new(0, 10, 0, 8),
			Size = UDim2.new(0.32, 0, 0, 32),
			ZIndex = 6,
			Parent = ui.content,
		})
		if view.phase ~= "round" and view.phase ~= "done" then
			local trumpSlot = PlayingCard.slot({ Position = UDim2.new(0, 10, 0, 44), Size = UDim2.new(0.3, 0, 0.5, -44), Parent = ui.content })
			PlayingCard.show(trumpSlot, view.trumpCard)
		end
		if me then
			local myBid = view.bids[tostring(me)]
			Kit.label(`You: {view.scores[me]} pts\n{if myBid == nil then "no bid yet" else `bid {myBid} · won {view.tricks[me]}`}`, {
				TextSize = 12,
				TextColor3 = Theme.Text,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextYAlignment = Enum.TextYAlignment.Top,
				Position = UDim2.new(0.68, -10, 0, 8),
				Size = UDim2.new(0.32, 0, 0, 32),
				ZIndex = 6,
				Parent = ui.content,
			})
		end

		if view.phase == "round" or view.phase == "done" then
			local lines = {}
			for seat = 1, n do
				local s = (view.roundSummary or {})[tostring(seat)]
				if s then
					local made = if s.bid == s.took then `made {s.bid} → +{s.points}` else `bid {s.bid}, took {s.took} → 0`
					table.insert(lines, `{nameOf(seat)}: {made}`)
				end
			end
			local title = if view.phase == "done" then "Final round over" else `Round {view.round} over · next: {view.nextHandSize or "?"} cards`
			CardTable.feltText(ui.content, title, 0.06, 18).TextColor3 = Theme.Accent
			Kit.label(table.concat(lines, "\n"), { TextSize = if n > 5 then 13 else 15, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromScale(0.05, 0.22), Size = UDim2.fromScale(0.9, 0.76), ZIndex = 6, Parent = ui.content })
		elseif view.phase == "bid" then
			local total = 0
			for _, b in view.bids do
				total += b
			end
			CardTable.feltText(ui.content, "Bidding", 0.3, 22).TextColor3 = Theme.Accent
			CardTable.feltText(ui.content, `Bids so far: {total} of {view.handSize} tricks`, 0.52, 16)
		else
			local plays = view.trick
			local winner = nil
			if #plays == 0 and view.phase == "trick" and view.lastTrick then
				plays = view.lastTrick.plays
				winner = view.lastTrick.winner
			end
			CardTable.trick(ui.content, snapshot, plays, winner, n)
			if winner then
				CardTable.feltText(ui.content, `{nameOf(winner)} {if winner == me then "win" else "wins"} the trick`, 0.9, 15)
			end
		end

		local buttons = {}
		if bidding then
			local banned = view.forbidden
			table.insert(buttons, { text = "-", color = Theme.PanelLight, onClick = function()
				bid = math.max(0, bid - 1)
				render()
			end })
			table.insert(buttons, {
				text = if bid == banned then `Can't bid {bid}` else `Bid {bid}`,
				enabled = bid ~= banned,
				onClick = function()
					sendMove({ kind = "bid", bid = bid })
				end,
			})
			table.insert(buttons, { text = "+", color = Theme.PanelLight, onClick = function()
				bid = math.min(view.handSize, bid + 1)
				render()
			end })
		end
		CardTable.buttons(ui.buttons, buttons)

		if not me then
			ui.prompt.Text = "Watching"
		elseif snapshot.result then
			ui.prompt.Text = ""
		elseif bidding then
			ui.prompt.Text = if view.forbidden ~= nil then `How many tricks will you take? (Dealer can't bid {view.forbidden})` else "How many tricks will you take? Exactly!"
		elseif myTurn then
			local need = (view.bids[tostring(me)] or 0) - (view.tricks[me] or 0)
			local goal = if need > 0 then `you need {need} more` elseif need == 0 then "take no more!" else "you're over your bid"
			ui.prompt.Text = (if #view.trick == 0 then "Your lead" else "Your turn: follow suit") .. ` · {goal}`
		elseif view.phase == "bid" or view.phase == "play" then
			ui.prompt.Text = `{nameOf(view.turn)}'s turn`
		else
			ui.prompt.Text = ""
		end

		local playable = {}
		for _, id in view.playable or {} do
			playable[id] = true
		end
		local cards = {}
		for _, id in view.hand or {} do
			local can = myTurn and playable[id] == true
			table.insert(cards, { id = id, glow = can, dim = myTurn and not can, enabled = can })
		end
		PlayingCard.renderHand(ui.hand, cards, function(id: number)
			if myTurn and playable[id] then
				sendMove({ kind = "play", card = id })
			end
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

return OhHell
