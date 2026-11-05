-- Color Clash table: the draw pile and the discard pile in the middle, your hand fanned
-- along the bottom (playable cards lift up, the rest dim). Tap a card to play it; Wild
-- cards open a color wheel in the middle of the screen. A card you draw and can play is
-- held up in the middle with Play / Keep. Draw / Pass buttons sit beside the piles.
-- Cards are drawn in code with our own look (Coral, Honey, Teal, Violet).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Rules = require(ReplicatedStorage.Shared.Games.ColorClash)
local Kit = require(script.Parent.Parent.UI.Kit)
local PlayingCard = require(script.Parent.Parent.UI.PlayingCard)
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
-- Card height as a share of the hand strip: the rest is headroom for a hovered card to
-- rise into (the strip scrolls, so it clips anything above it).
local HAND_CARD = 0.76

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
	}, {
		Kit.corner(24),
		-- Lamp light over the middle of the table.
		Kit.new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(165, 175, 170)),
				ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 160, 155)),
			}),
		}),
	})
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
		local cardW = hand.AbsoluteSize.Y * HAND_CARD * CARD_RATIO
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
	local handHover = PlayingCard.hover(hand)
	-- One padding for the hand (a second UIPadding would be ignored). The bottom keeps
	-- the cards clear of the scroll bar.
	Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 24), PaddingRight = UDim.new(0, 24), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 10), Parent = hand })

	-- Overlays in the middle of the screen (the wild color picker, the card you just
	-- drew). They sit on the whole screen, not in this board: Table view docks only the
	-- bottom of the board, and the middle of the screen is the table.
	local overlay = Kit.new("Frame", {
		Name = "ColorClashOverlay",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		Visible = false,
		Parent = root,
	})
	local function showOverlay()
		local screen = container:FindFirstAncestorWhichIsA("ScreenGui")
		overlay.Parent = screen or root
		overlay.Visible = true
	end
	local pop = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local quick = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	-- Wild color picker: a round wheel of the four colors that bursts out of the middle
	-- of the table, each quarter its own button. Tap outside it to put the wild back.
	local pendingWild: number? = nil
	local pickerShade = Kit.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 51,
		Parent = overlay,
	})
	local picker = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.5, 0.5),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		Visible = false,
		ZIndex = 52,
		Parent = overlay,
	}, { Kit.new("UISizeConstraint", { MinSize = Vector2.new(220, 220), MaxSize = Vector2.new(420, 420) }) })
	local pickerScale = Kit.new("UIScale", { Scale = 1, Parent = picker })
	local GAP = 0.012 -- of the wheel's size, between the quarters
	-- Quarter i: which corner of the wheel it fills (x, y as 0 or 1).
	local QUARTERS = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } }
	local quarterRest: { [GuiObject]: UDim2 } = {}
	local quarterOut: { [GuiObject]: UDim2 } = {}
	local function closePicker()
		pendingWild = nil
		picker.Visible = false
		pickerShade.Visible = false
	end
	for i, color in COLORS do
		local qx, qy = QUARTERS[i][1], QUARTERS[i][2]
		local outX, outY = qx * 2 - 1, qy * 2 - 1 -- away from the middle
		local rest = UDim2.fromScale(qx * 0.5 + outX * GAP, qy * 0.5 + outY * GAP)
		-- A square that clips a full circle to the one quarter in its corner.
		local quarter = Kit.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Position = rest,
			Size = UDim2.fromScale(0.5, 0.5),
			ZIndex = 53,
			Parent = picker,
		})
		quarterRest[quarter] = rest
		quarterOut[quarter] = UDim2.fromScale(qx * 0.5 + outX * GAP * 4, qy * 0.5 + outY * GAP * 4)
		Kit.new("Frame", {
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			-- The circle's middle sits on the quarter's inner corner.
			Position = UDim2.fromScale(-qx, -qy),
			Size = UDim2.fromScale(2, 2),
			ZIndex = 53,
			Parent = quarter,
		}, {
			Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			Kit.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)) }),
		})
		Kit.label(Rules.colorNames[i], {
			Font = Theme.FontBold,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.4,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0.5),
			-- Toward the outside of the quarter, where it's widest.
			Position = UDim2.fromScale(if qx == 0 then 0.42 else 0.58, if qy == 0 then 0.42 else 0.58),
			Size = UDim2.fromScale(0.6, 0.2),
			ZIndex = 54,
			Parent = quarter,
		})
		quarter.MouseEnter:Connect(function()
			TweenService:Create(quarter, quick, { Position = quarterOut[quarter] }):Play()
		end)
		quarter.MouseLeave:Connect(function()
			TweenService:Create(quarter, quick, { Position = quarterRest[quarter] }):Play()
		end)
		quarter.Activated:Connect(function()
			if pendingWild then
				sendMove({ kind = "play", card = pendingWild, color = i })
			end
			closePicker()
		end)
	end
	-- A dark hub in the middle, like the pile under the wheel.
	Kit.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(28, 24, 40),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.22, 0.22),
		ZIndex = 55,
		Parent = picker,
	}, {
		Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Kit.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 3 }),
	})
	Kit.label("★", {
		Font = Theme.FontBold,
		TextScaled = true,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.12, 0.12),
		ZIndex = 56,
		Parent = picker,
	})
	pickerShade.Activated:Connect(closePicker)
	local function openPicker(id: number)
		pendingWild = id
		showOverlay()
		pickerShade.Visible = true
		picker.Visible = true
		picker.Rotation = -40
		pickerScale.Scale = 0.15
		for quarter, rest in quarterRest do
			quarter.Position = rest
		end
		TweenService:Create(pickerScale, pop, { Scale = 1 }):Play()
		TweenService:Create(picker, pop, { Rotation = 0 }):Play()
	end

	-- The card you just drew, when it can be played: held up in the middle with Play on
	-- one side and Keep on the other.
	local drawnBand = Kit.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(30, 26, 46),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.new(1, 0, 0.16, 0),
		Visible = false,
		ZIndex = 50,
		Parent = overlay,
	}, {
		Kit.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.1),
				NumberSequenceKeypoint.new(0.8, 0.1),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	local drawnSlot = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(CARD_RATIO * 1.9, 1.9),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = 52,
		Parent = drawnBand,
	})
	local drawnScale = Kit.new("UIScale", { Scale = 1, Parent = drawnSlot })
	local drawnShown: number? = nil
	local function bandButton(text: string, color: Color3, x: number, onClick: () -> ()): TextButton
		local button = Kit.button(text, onClick, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, 0.5),
			Size = UDim2.new(0.16, 0, 0.5, 0),
			BackgroundColor3 = color,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.5,
			TextScaled = true,
			ZIndex = 53,
			Parent = drawnBand,
		})
		Kit.new("UISizeConstraint", { MinSize = Vector2.new(110, 40), MaxSize = Vector2.new(240, 64), Parent = button })
		Kit.new("UITextSizeConstraint", { MaxTextSize = 26, Parent = button })
		Kit.new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), Parent = button })
		Kit.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Transparency = 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = button })
		return button
	end
	local function playDrawn()
		local id = drawnShown
		if not id then
			return
		end
		local card = Rules.cards[id]
		if card.kind == "wild" or card.kind == "wild4" then
			openPicker(id)
		else
			sendMove({ kind = "play", card = id })
		end
	end
	bandButton("Play it", Color3.fromRGB(70, 170, 100), 0.3, playDrawn)
	bandButton("Keep it", Color3.fromRGB(70, 110, 200), 0.7, function()
		sendMove({ kind = "pass" })
	end)
	local function showDrawn(id: number?)
		if id == drawnShown then
			return
		end
		drawnShown = id
		Kit.clear(drawnSlot)
		if not id then
			drawnBand.Visible = false
			return
		end
		cardVisual(id).Parent = drawnSlot
		showOverlay()
		drawnBand.Visible = true
		drawnScale.Scale = 0.3
		drawnSlot.Rotation = -12
		TweenService:Create(drawnScale, pop, { Scale = 1 }):Play()
		TweenService:Create(drawnSlot, pop, { Rotation = 0 }):Play()
	end

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
		-- After drawing a card you can play, it's shown in the middle with Play / Keep.
		local drawnPlayable = myTurn and view.canPass and view.drawnCard ~= nil
		showDrawn(if drawnPlayable then view.drawnCard else nil)
		passAction.Visible = myTurn and view.canPass and not drawnPlayable
		if not myTurn then
			closePicker()
		end

		-- Hand.
		Kit.clear(hand)
		handHover.clear()
		local playable = {}
		for _, id in view.playable or {} do
			playable[id] = true
		end
		local count = #(view.hand or {})
		for index, id in view.hand or {} do
			local canPlay = myTurn and playable[id] == true
			-- Held like real cards: fanned out, the outer cards turned and a little lower.
			local offset = index - (count + 1) / 2
			local spread = if count > 1 then math.min(4, 28 / (count - 1)) else 0
			-- Width comes from the hand's height (RelativeYY), so cards keep their shape.
			local slot = Kit.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(HAND_CARD * CARD_RATIO, 0, HAND_CARD, 0),
				SizeConstraint = Enum.SizeConstraint.RelativeYY,
				LayoutOrder = index,
				Parent = hand,
			})
			local face = cardVisual(id)
			face.Parent = slot
			local drop = (offset * spread / 28) ^ 2 * 0.5 -- the fan's curve, in card heights
			local rest = UDim2.fromScale(0, drop + (if canPlay then -0.08 else 0))
			face.Position = rest
			face.Rotation = offset * spread
			-- Cards you can't play now are only a touch darker: never looking switched off.
			local shade: Frame? = nil
			if myTurn and not canPlay then
				shade = Kit.new("Frame", {
					BackgroundColor3 = Color3.new(0, 0, 0),
					BackgroundTransparency = 0.8,
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
			-- Hover: the card comes up out of the hand, straightens, sits on top of its
			-- neighbours and shows at full brightness.
			local lift = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			-- One card at a time (PlayingCard.hover picks the top card under the mouse).
			handHover.add(slot, function()
				slot.ZIndex = 10
				if shade then
					shade.Visible = false
				end
				TweenService:Create(face, lift, { Position = UDim2.fromScale(0, -0.22), Rotation = 0 }):Play()
			end, function()
				slot.ZIndex = 1
				if shade then
					shade.Visible = true
				end
				TweenService:Create(face, lift, { Position = rest, Rotation = offset * spread }):Play()
			end)
			button.Activated:Connect(function()
				if not canPlay then
					return
				end
				local card = Rules.cards[id]
				if card.kind == "wild" or card.kind == "wild4" then
					openPicker(id)
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
		-- Docked, it's laid out like cards held in front of you at the table (the dock
		-- behind it is see-through): a big fan along the bottom edge, running a little off
		-- the screen, and the Draw / Pass buttons in the bottom-right corner.
		setDocked = function(docked: boolean)
			felt.Visible = not docked
			if docked then
				pendingLabel.Parent = root
				pendingLabel.Position = UDim2.new(0, 0, 0.58, 0)
				hand.Position = UDim2.new(0.14, 0, 0.6, 0)
				hand.Size = UDim2.new(0.72, 0, 0.47, 0)
				hand.ScrollBarThickness = 0
				actions.AnchorPoint = Vector2.new(1, 1)
				actions.Position = UDim2.new(1, -14, 1, -14)
				actions.Size = UDim2.new(0, 360, 0, 44)
				actionList.HorizontalAlignment = Enum.HorizontalAlignment.Right
			else
				pendingLabel.Parent = felt
				pendingLabel.Position = UDim2.new(0, 0, 1, -34)
				hand.Position = UDim2.new(0, 0, 0.6, 48)
				hand.Size = UDim2.new(1, 0, 0.4, -48)
				hand.ScrollBarThickness = 6
				actions.AnchorPoint = Vector2.new(0, 0)
				actions.Position = UDim2.new(0, 0, 0.6, 0)
				actions.Size = UDim2.new(1, 0, 0, 40)
				actionList.HorizontalAlignment = Enum.HorizontalAlignment.Center
			end
			squeezeHand()
		end,
		destroy = function()
			overlay:Destroy()
			root:Destroy()
		end,
	}
end

return ColorClash
