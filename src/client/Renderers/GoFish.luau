-- Go Fish table: opponents along the top (cards and books), the pond in the middle,
-- your hand along the bottom. On your turn tap a card to pick its rank, then tap who to
-- ask. With one opponent the ask goes straight out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Kit = require(script.Parent.Parent.UI.Kit)
local PlayingCard = require(script.Parent.Parent.UI.PlayingCard)
local Theme = Kit.Theme

local GoFish = {}

function GoFish.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local selectedRank: number? = nil

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })

	local opponents = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.18, 0), Parent = root })
	local opponentList = Kit.list(8, true)
	opponentList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	opponentList.Parent = opponents

	local felt = PlayingCard.felt({ Position = UDim2.new(0, 0, 0.2, 0), Size = UDim2.new(1, 0, 0.44, 0), Parent = root })
	local pond = PlayingCard.slot({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.3, 0.55), Size = UDim2.fromScale(1, 0.6), Parent = felt })
	local pondLabel = Kit.label("", {
		TextSize = 13,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 1, 2),
		ZIndex = 6,
		Parent = pond,
	})
	local drawn = PlayingCard.slot({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.7, 0.55), Size = UDim2.fromScale(1, 0.6), Parent = felt })
	local drawnLabel = Kit.label("", {
		TextSize = 13,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 1, 2),
		ZIndex = 6,
		Parent = drawn,
	})
	local lastLabel = Kit.label("", {
		TextSize = 17,
		Font = Theme.FontBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 8, 0, 8),
		Size = UDim2.new(1, -16, 0, 44),
		Parent = felt,
	})

	local prompt = Kit.label("", {
		TextSize = 16,
		Font = Theme.FontBold,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0.65, 0),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = root,
	})
	local myBooks = Kit.label("", {
		TextSize = 14,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0.65, 22),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = root,
	})
	-- "Ask <name>" buttons in the same spot as your books line, once you've picked a rank,
	-- so Table view (which keeps only the bottom of the screen) can ask too.
	local askRow = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0.65, 22), Size = UDim2.new(1, 0, 0, 26), Visible = false, Parent = root })
	local askList = Kit.list(6, true)
	askList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	askList.Parent = askRow
	local hand = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0.74, 0), Size = UDim2.new(1, 0, 0.26, 0), Parent = root })

	local function nameOf(seat: number): string
		if seat == snapshot.yourSeat then
			return "You"
		end
		local s = snapshot.seats[seat]
		return if s then s.name else "?"
	end

	local function booksText(list: { number }): string
		if #list == 0 then
			return "no books yet"
		end
		local parts = {}
		for _, r in list do
			table.insert(parts, PlayingCards.rankShort[r])
		end
		return "books: " .. table.concat(parts, " ")
	end

	local function describe(action: any): string
		if not action then
			return "Ask for a rank you hold. Got any?"
		end
		local who = nameOf(action.seat)
		-- "You" leads a sentence; as the one being asked it's "you".
		local target = if action.target == snapshot.yourSeat then "you" else nameOf(action.target)
		local plural = PlayingCards.rankPlural[action.rank]
		local text
		if action.got > 0 then
			text = `{who} asked {target} for {plural} and got {action.got}!`
		elseif action.luckyFish then
			text = `{who} asked {target} for {plural}. Go fish... and fished one!`
		else
			text = `{who} asked {target} for {plural}. Go fish!`
		end
		if action.books and #action.books > 0 then
			local names = {}
			for _, r in action.books do
				table.insert(names, PlayingCards.rankPlural[r])
			end
			text ..= ` Book of {table.concat(names, ", ")}!`
		end
		return text
	end

	local render: () -> ()

	local function ask(target: number)
		if selectedRank then
			sendMove({ kind = "ask", target = target, rank = selectedRank })
			selectedRank = nil
		end
	end

	function render()
		local view = snapshot.view
		local me = snapshot.yourSeat
		local myTurn = me ~= nil and table.find(snapshot.activeSeats, me) ~= nil
		local askable = {}
		for _, r in view.askableRanks or {} do
			askable[r] = true
		end
		if not myTurn or (selectedRank and not askable[selectedRank]) then
			selectedRank = nil
		end

		-- Opponents: tappable once you've picked a rank.
		Kit.clear(opponents)
		local targets = {}
		for seat = 1, #snapshot.seats do
			if seat ~= me then
				table.insert(targets, seat)
				local canAsk = myTurn and selectedRank ~= nil and view.handCounts[seat] > 0
				local box = Kit.new("TextButton", {
					Text = "",
					AutoButtonColor = canAsk,
					BackgroundColor3 = if canAsk then Theme.Accent elseif view.turn == seat then Theme.PanelLight else Theme.Panel,
					BorderSizePixel = 0,
					Size = UDim2.new(0, 150, 0, 66),
					LayoutOrder = seat,
					Parent = opponents,
				}, { Kit.corner(10), Kit.padding(6) })
				local color = if canAsk then Theme.AccentText else Theme.Text
				Kit.label(nameOf(seat), { Font = Theme.FontBold, TextSize = 15, TextColor3 = color, Size = UDim2.new(1, 0, 0, 18), Parent = box })
				Kit.label(`{view.handCounts[seat]} cards`, { TextSize = 13, TextColor3 = color, Position = UDim2.new(0, 0, 0, 20), Size = UDim2.new(1, 0, 0, 16), Parent = box })
				Kit.label(booksText(view.books[seat]), { TextSize = 12, TextColor3 = color, Position = UDim2.new(0, 0, 0, 38), Size = UDim2.new(1, 0, 0, 16), Parent = box })
				box.Activated:Connect(function()
					if canAsk then
						ask(seat)
					end
				end)
			end
		end

		if view.pondCount > 0 then
			PlayingCard.show(pond, nil, true)
		else
			PlayingCard.empty(pond)
		end
		pondLabel.Text = `Pond: {view.pondCount}`
		if view.drawnCard then
			PlayingCard.show(drawn, view.drawnCard)
			drawnLabel.Text = "You fished"
		else
			PlayingCard.empty(drawn)
			drawnLabel.Text = ""
		end
		lastLabel.Text = describe(view.lastAction)

		if not me then
			prompt.Text = "Watching"
		elseif not myTurn then
			prompt.Text = `{nameOf(view.turn)} is asking...`
		elseif selectedRank then
			prompt.Text = `Who do you ask for {PlayingCards.rankPlural[selectedRank]}?`
		else
			prompt.Text = "Your turn! Tap a card to ask for that rank."
		end
		local myList = if me then view.books[me] or {} else {}
		myBooks.Text = if not me then "" elseif #myList == 0 then "You have no books yet" else `Your {booksText(myList)}`
		Kit.clear(askRow)
		local choosing = myTurn and selectedRank ~= nil
		if choosing then
			for _, seat in targets do
				if view.handCounts[seat] > 0 then
					Kit.button(`Ask {nameOf(seat)}`, function()
						ask(seat)
					end, {
						Size = UDim2.new(0, math.max(90, #nameOf(seat) * 8 + 50), 1, 0),
						TextSize = 14,
						LayoutOrder = seat,
						Parent = askRow,
					})
				end
			end
		end
		askRow.Visible = choosing
		myBooks.Visible = not choosing

		local cards = {}
		for _, id in view.hand or {} do
			local r = PlayingCards.rank(id)
			table.insert(cards, { id = id, raised = r == selectedRank, glow = r == selectedRank, enabled = myTurn })
		end
		PlayingCard.renderHand(hand, cards, function(id: number)
			local r = PlayingCards.rank(id)
			if not askable[r] then
				return
			end
			selectedRank = r
			-- One opponent with cards: no need to pick.
			local withCards = {}
			for _, seat in targets do
				if view.handCounts[seat] > 0 then
					table.insert(withCards, seat)
				end
			end
			if #withCards == 1 then
				ask(withCards[1])
			else
				render()
			end
		end)
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			render()
		end,
		destroy = function()
			root:Destroy()
		end,
	}
end

return GoFish
