-- Color Clash table: the draw pile and the discard pile in the middle, your hand fanned
-- along the bottom (playable cards lift up, the rest dim). Tap a card to play it; Wild
-- cards open a 4-color picker. Draw / Pass buttons sit beside the piles.
-- Cards are drawn in code with our own look (Coral, Honey, Teal, Violet).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Rules = require(ReplicatedStorage.Shared.Games.ColorClash)
local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = Kit.Theme

local ColorClash = {}

local COLORS = {
	Color3.fromRGB(240, 110, 100), -- Coral
	Color3.fromRGB(245, 190, 70), -- Honey
	Color3.fromRGB(60, 190, 170), -- Teal
	Color3.fromRGB(150, 110, 230), -- Violet
}
local WILD_COLOR = Color3.fromRGB(40, 36, 56)
local SYMBOLS = { skip = "⊘", reverse = "⇄", draw2 = "+2", wild = "★", wild4 = "+4" }
local CARD_RATIO = 0.68 -- width / height

local function cardLabel(card: Rules.Card): string
	if card.kind == "number" then
		return tostring(card.value)
	end
	return SYMBOLS[card.kind]
end

-- One card face. `id` nil draws a card back.
local function cardVisual(id: number?): Frame
	local card = id and Rules.cards[id]
	local face = Kit.new("Frame", {
		BackgroundColor3 = if card == nil then Color3.fromRGB(54, 44, 90) elseif card.color == 0 then WILD_COLOR else COLORS[card.color],
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, {
		Kit.new("UICorner", { CornerRadius = UDim.new(0.12, 0) }),
		Kit.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	})
	local oval = Kit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = if card then 0 else 0.85,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.78, 0.55),
		Rotation = -20,
		Parent = face,
	}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	if not card then
		Kit.label("CLASH", {
			Font = Theme.FontBold,
			TextScaled = true,
			TextColor3 = Theme.Accent,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.8, 0.25),
			Rotation = -20,
			Parent = face,
		})
		return face
	end
	if card.color == 0 then
		-- Wild: the four colors in the oval.
		oval.BackgroundTransparency = 1
		for i, color in COLORS do
			Kit.new("Frame", {
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(((i - 1) % 2) * 0.5, if i <= 2 then 0 else 0.5),
				Size = UDim2.fromScale(0.5, 0.5),
				Parent = oval,
			}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		end
	end
	local text = cardLabel(card)
	Kit.label(text, {
		Font = Theme.FontBold,
		TextScaled = true,
		TextColor3 = if card.color == 0 then Color3.new(1, 1, 1) else COLORS[card.color],
		TextStrokeTransparency = if card.color == 0 then 0.2 else 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 0.38),
		Parent = face,
	})
	for _, corner in { { 0.06, 0.03, 0 }, { 0.64, 0.79, 180 } } do
		Kit.label(text, {
			Font = Theme.FontBold,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromScale(corner[1], corner[2]),
			Size = UDim2.fromScale(0.3, 0.18),
			Rotation = corner[3],
			Parent = face,
		})
	end
	return face
end

function ColorClash.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local shownTop: number? = nil
	local topVisual: GuiObject? = nil

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })

	-- Table felt in the middle.
	local felt = Kit.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(34, 74, 70),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0.58, 0),
		Parent = root,
	}, { Kit.corner(24) })
	local colorRing = Kit.new("UIStroke", { Thickness = 6, Color = COLORS[1], Parent = felt })

	local pileHeight = 0.62
	local function pileSlot(xScale: number): Frame
		return Kit.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(xScale, 0.5),
			Size = UDim2.fromScale(1, pileHeight),
			Parent = felt,
		}, { Kit.new("UIAspectRatioConstraint", { AspectRatio = CARD_RATIO }) })
	end
	local drawSlot = pileSlot(0.36)
	local discardSlot = pileSlot(0.56)
	cardVisual(nil).Parent = drawSlot
	local drawButton = Kit.new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = drawSlot })
	local deckCount = Kit.label("", {
		TextSize = 14,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 1, 4),
		Parent = drawSlot,
	})

	local directionLabel = Kit.label("", {
		TextSize = 18,
		Font = Theme.FontBold,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0.7, 0, 0.5, -40),
		Size = UDim2.new(0.25, 0, 0, 40),
		Parent = felt,
	})
	local colorLabel = Kit.label("", {
		TextSize = 16,
		Font = Theme.FontBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0.7, 0, 0.5, 4),
		Size = UDim2.new(0.25, 0, 0, 22),
		Parent = felt,
	})
	local lastLabel = Kit.label("", {
		TextSize = 15,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 10),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = felt,
	})
	local pendingLabel = Kit.label("", {
		TextSize = 20,
		Font = Theme.FontBold,
		TextColor3 = Theme.Bad,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 1, -34),
		Size = UDim2.new(1, 0, 0, 26),
		Parent = felt,
	})

	-- Action buttons between the felt and the hand.
	local actions = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0.6, 0),
		Size = UDim2.new(1, 0, 0, 40),
		Parent = root,
	})
	local actionList = Kit.list(10, true)
	actionList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	actionList.Parent = actions
	local drawAction = Kit.button("Draw a card", function()
		sendMove({ kind = "draw" })
	end, { Size = UDim2.new(0, 170, 1, 0), LayoutOrder = 1, Parent = actions })
	local passAction = Kit.button("Keep it & pass", function()
		sendMove({ kind = "pass" })
	end, { Size = UDim2.new(0, 170, 1, 0), BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, LayoutOrder = 2, Parent = actions })
	drawButton.Activated:Connect(function()
		if drawAction.Visible then
			sendMove({ kind = "draw" })
		end
	end)

	-- Your hand.
	local hand = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0.6, 48),
		Size = UDim2.new(1, 0, 0.4, -48),
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 6,
		Parent = root,
	})
	-- Cards overlap a little, like a fan. Left-aligned when scrolling: a centered list wider
	-- than the frame would push cards off the left edge, where scrolling can't reach them.
	local handList = Kit.list(-18, true)
	handList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	handList.VerticalAlignment = Enum.VerticalAlignment.Bottom
	handList.Parent = hand
	-- Size the canvas ourselves: AutomaticCanvasSize doesn't grow with the overlapping
	-- (negative padding) list, so the right end of a big hand couldn't be scrolled to.
	local function fitHand()
		hand.CanvasSize = UDim2.fromOffset(handList.AbsoluteContentSize.X + 48, 0)
	end
	handList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitHand)
	fitHand()
	-- Big hands squeeze together first (down to about a third of each card showing) and
	-- only scroll after that, so on a phone you rarely have to scroll to find a card.
	local function squeezeHand()
		local count = 0
		for _, child in hand:GetChildren() do
			if child:IsA("Frame") then
				count += 1
			end
		end
		local cardW = hand.AbsoluteSize.Y * 0.9 * CARD_RATIO
		local room = hand.AbsoluteSize.X - 48
		if count < 2 or cardW <= 0 or room <= 0 then
			handList.Padding = UDim.new(0, -18)
			handList.HorizontalAlignment = Enum.HorizontalAlignment.Center
			return
		end
		local gap = math.min(-18, (room - cardW) / (count - 1) - cardW)
		gap = math.max(gap, -cardW * 0.65)
		handList.Padding = UDim.new(0, math.floor(gap))
		local fits = count * cardW + (count - 1) * gap <= room + 1
		-- Centered when it all fits; left-aligned when scrolling, so the first cards stay reachable.
		handList.HorizontalAlignment = if fits then Enum.HorizontalAlignment.Center else Enum.HorizontalAlignment.Left
	end
	hand:GetPropertyChangedSignal("AbsoluteSize"):Connect(squeezeHand)
	-- One padding for the hand (a second UIPadding would be ignored). The bottom keeps
	-- the cards clear of the scroll bar.
	Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 24), PaddingRight = UDim.new(0, 24), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 10), Parent = hand })

	-- Wild color picker.
	local picker = Kit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.new(0, 340, 0, 150),
		BackgroundColor3 = Theme.PanelLight,
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})
	Kit.label("Pick a color", { Font = Theme.FontBold, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 21, Parent = picker })
	local pendingWild: number? = nil
	for i, color in COLORS do
		Kit.button(Rules.colorNames[i], function()
			if pendingWild then
				sendMove({ kind = "play", card = pendingWild, color = i })
			end
			pendingWild = nil
			picker.Visible = false
		end, {
			BackgroundColor3 = color,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.5,
			Position = UDim2.new((i - 1) / 4, 4, 0, 36),
			Size = UDim2.new(0.25, -8, 0, 70),
			ZIndex = 21,
			Parent = picker,
		})
	end
	Kit.button("Cancel", function()
		pendingWild = nil
		picker.Visible = false
	end, { BackgroundTransparency = 1, TextColor3 = Theme.SubText, Position = UDim2.new(0, 0, 1, -24), Size = UDim2.new(1, 0, 0, 24), ZIndex = 21, Parent = picker })

	local function nameOf(seat: number): string
		if seat == snapshot.yourSeat then
			return "You"
		end
		local s = snapshot.seats[seat]
		return if s then s.name else "?"
	end

	local function describe(action: any): string
		if not action then
			return ""
		end
		local who = nameOf(action.seat)
		if action.kind == "play" then
			local card = Rules.cards[action.card]
			local what = if card.kind == "number" then `a {Rules.colorNames[card.color]} {card.value}`
				elseif card.kind == "wild" then `a Wild ({Rules.colorNames[action.color]})`
				elseif card.kind == "wild4" then `a Wild +4 ({Rules.colorNames[action.color]})`
				else `a {Rules.colorNames[card.color]} {({ skip = "Skip", reverse = "Reverse", draw2 = "+2" })[card.kind]}`
			return `{who} played {what}`
		elseif action.kind == "draw" then
			return if action.count == 1 then `{who} drew a card` else `{who} drew {action.count} cards`
		elseif action.kind == "pass" then
			return `{who} passed`
		end
		return ""
	end

	local function render()
		local view = snapshot.view
		local myTurn = table.find(snapshot.activeSeats, snapshot.yourSeat) ~= nil

		-- Discard pile: animate a new top card dropping in.
		if shownTop ~= view.topCard then
			shownTop = view.topCard
			-- Replace only the card (Kit.clear would also drop the slot's aspect constraint).
			if topVisual then
				topVisual:Destroy()
			end
			local top = cardVisual(view.topCard)
			topVisual = top
			top.Parent = discardSlot
			top.Rotation = (view.topCard % 7) * 3 - 9
			top.Position = UDim2.fromScale(0, -0.25)
			TweenService:Create(top, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0, 0) }):Play()
		end
		deckCount.Text = `{view.deckCount} left`
		colorRing.Color = COLORS[view.color] or Theme.Accent
		colorLabel.Text = Rules.colorNames[view.color] or ""
		colorLabel.TextColor3 = COLORS[view.color] or Theme.Text
		directionLabel.Text = if view.direction == 1 then "Normal order" else "⇄ Reversed"
		lastLabel.Text = describe(view.lastAction)
		pendingLabel.Text = if view.pendingDraw > 0 then `+{view.pendingDraw} waiting! Stack a draw card or take them.` else ""

		drawAction.Visible = myTurn and not view.canPass
		drawAction.Text = if view.pendingDraw > 0 then `Take {view.pendingDraw} cards` else "Draw a card"
		passAction.Visible = myTurn and view.canPass
		if not myTurn then
			picker.Visible = false
			pendingWild = nil
		end

		-- Hand.
		Kit.clear(hand)
		local playable = {}
		for _, id in view.playable or {} do
			playable[id] = true
		end
		for index, id in view.hand or {} do
			local canPlay = myTurn and playable[id] == true
			-- Width comes from the hand's height (RelativeYY), so cards keep their shape.
			local slot = Kit.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(0.9 * CARD_RATIO, 0, 0.9, 0),
				SizeConstraint = Enum.SizeConstraint.RelativeYY,
				LayoutOrder = index,
				Parent = hand,
			})
			local face = cardVisual(id)
			face.Parent = slot
			face.Position = if canPlay then UDim2.fromScale(0, -0.08) else UDim2.fromScale(0, 0)
			if myTurn and not canPlay then
				Kit.new("Frame", {
					BackgroundColor3 = Color3.new(0, 0, 0),
					BackgroundTransparency = 0.5,
					BorderSizePixel = 0,
					Size = UDim2.fromScale(1, 1),
					ZIndex = 3,
					Parent = face,
				}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.12, 0) }) })
			end
			if id == view.drawnCard then
				Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 5, Parent = face })
			end
			local button = Kit.new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = slot })
			button.Activated:Connect(function()
				if not canPlay then
					return
				end
				local card = Rules.cards[id]
				if card.kind == "wild" or card.kind == "wild4" then
					pendingWild = id
					picker.Visible = true
				else
					sendMove({ kind = "play", card = id })
				end
			end)
		end
		squeezeHand()
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			render()
		end,
		-- Table view docks the bottom of the board (MatchView.DOCK): the piles and the
		-- current color are on the 3D table, so only the buttons and your hand show. The
		-- "+2 waiting" warning isn't on the table, so it moves just above the buttons, and
		-- the wild color picker moves down into the dock.
		setDocked = function(docked: boolean)
			felt.Visible = not docked
			if docked then
				pendingLabel.Parent = root
				pendingLabel.Position = UDim2.new(0, 0, 0.6, -28)
				picker.Position = UDim2.fromScale(0.5, 0.8)
			else
				pendingLabel.Parent = felt
				pendingLabel.Position = UDim2.new(0, 0, 1, -34)
				picker.Position = UDim2.fromScale(0.5, 0.42)
			end
		end,
		destroy = function()
			root:Destroy()
		end,
	}
end

return ColorClash
