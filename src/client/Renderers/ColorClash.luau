-- Color Clash table: the draw pile and the discard pile in the middle, your hand fanned
-- along the bottom (playable cards lift up, the rest dim). Tap a card to play it; Wild
-- cards open a color wheel in the middle of the screen (colors up/right/down/left, so
-- arrows or a D-pad can pick one). A card you draw and can play is
-- held up in the middle with Play / Keep. Draw / Pass buttons sit beside the piles.
-- Cards are drawn in code with our own look (Coral, Honey, Teal, Violet).
-- Every card stays in full color: the ones you can play stand up out of the fan.
-- In Table view a small card on the left keeps the score, target and house rules, the
-- round summary comes up over the hand, and the final points open as a sheet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local Rules = require(ReplicatedStorage.Shared.Games.ColorClash)
local Kit = require(script.Parent.Parent.UI.Kit)
local Access = require(script.Parent.Parent.UI.Access)
local PlayingCard = require(script.Parent.Parent.UI.PlayingCard)
local Fx = require(script.Parent.ColorClashFx)
local Audio = require(script.Parent.Parent.Audio)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local CardTable = require(script.Parent.Parent.UI.CardTable)
local Theme = Kit.Theme

local ColorClash = {}

local COLORS = {
	Color3.fromRGB(240, 110, 100), -- Coral
	Color3.fromRGB(245, 190, 70), -- Honey
	Color3.fromRGB(60, 190, 170), -- Teal
	Color3.fromRGB(150, 110, 230), -- Violet
}
local WILD_COLOR = Color3.fromRGB(40, 36, 56)
-- Color-blind marks (Settings > Accessibility): a shape for each color, in the card's
-- free corners and on the color picker.
local MARKS = { "▲", "●", "■", "◆" }
local SYMBOLS = { skip = "⊘", reverse = "⇄", draw2 = "+2", wild = "★", wild4 = "+4", wild6 = "+6", skipall = "⊘⊘", discardall = "ALL" }
local KIND_NAMES = { skip = "Skip", reverse = "Reverse", draw2 = "+2", skipall = "Skip Everyone", discardall = "Discard All" }
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
	if card.color ~= 0 then
		-- Under each corner number, so it shows on a fanned hand too.
		-- Dark ink with a white rim reads on the color and on the white oval alike.
		for _, at in { { 0.2, 0.31, 0 }, { 0.8, 0.69, 180 } } do
			Access.mark(face, MARKS[card.color], {
				Position = UDim2.fromScale(at[1], at[2]),
				Size = UDim2.fromScale(0.32, 0.19),
				Rotation = at[3],
				TextColor3 = Color3.fromRGB(20, 16, 40),
				TextStrokeColor3 = Color3.new(1, 1, 1),
				TextStrokeTransparency = 0,
			})
		end
	end
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

-- The wild color picker filling `parent`: the four colors as round buttons pointing up,
-- right, down and left around a dark hub, so a controller's D-pad or the arrow keys can
-- pick one (see ColorClash.create). `z` is the lowest ZIndex it uses. Returns `light(i)`,
-- which pushes color i out as the highlighted one (nil lights none).
local DIRECTIONS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } } -- Coral up, Honey right, Teal down, Violet left
local ARROWS = { "▲", "▶", "▼", "◀" }
local PETAL = 0.4 -- of the picker's size
local PETAL_REACH = 0.29 -- petal middle from the picker's middle
local function buildWheel(parent: GuiObject, z: number, onPick: (number) -> ()): (number?) -> ()
	local quick = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	-- A dark ring behind the petals, so it still reads as one wheel.
	Kit.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(28, 24, 40),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.86),
		ZIndex = z,
		Parent = parent,
	}, {
		Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Kit.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Transparency = 0.5 }),
	})
	local petals = {}
	local hovered: number? = nil
	local lit: number? = nil
	local function settle(i: number)
		local petal = petals[i]
		local d = DIRECTIONS[i]
		local on = hovered == i or lit == i
		local reach = PETAL_REACH + (if on then 0.05 else 0)
		TweenService:Create(petal.button, quick, { Position = UDim2.fromScale(0.5 + d[1] * reach, 0.5 + d[2] * reach) }):Play()
		TweenService:Create(petal.scale, quick, { Scale = if on then 1.12 else 1 }):Play()
		petal.stroke.Thickness = if lit == i then 5 else 2
		petal.stroke.Transparency = if on then 0 else 0.35
	end
	for i, color in COLORS do
		local d = DIRECTIONS[i]
		local button = Kit.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + d[1] * PETAL_REACH, 0.5 + d[2] * PETAL_REACH),
			Size = UDim2.fromScale(PETAL, PETAL),
			ZIndex = z + 1,
			Parent = parent,
		}, {
			Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			Kit.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)) }),
		})
		local stroke = Kit.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Transparency = 0.35, Parent = button })
		local scale = Kit.new("UIScale", { Scale = 1, Parent = button })
		Kit.label(Rules.colorNames[i], {
			Font = Theme.FontBold,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.4,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.56),
			Size = UDim2.fromScale(0.8, 0.26),
			ZIndex = z + 2,
			Parent = button,
		})
		-- Which way to press for it.
		Kit.label(ARROWS[i], {
			Font = Theme.FontBold,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),
			TextTransparency = 0.25,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + d[1] * 0.3, 0.5 + d[2] * 0.3 - (if d[2] == 0 then 0.06 else 0)),
			Size = UDim2.fromScale(0.2, 0.2),
			ZIndex = z + 2,
			Parent = button,
		})
		-- Its color-blind mark, clear of the arrow.
		Access.mark(button, MARKS[i], {
			Position = UDim2.fromScale(0.5, if i == 1 then 0.8 else 0.25),
			Size = UDim2.fromScale(0.2, 0.18),
			ZIndex = z + 2,
		})
		petals[i] = { button = button, stroke = stroke, scale = scale }
		button.MouseEnter:Connect(function()
			hovered = i
			settle(i)
			Audio.hoverAt(i, 4) -- the four colors a rising chord
		end)
		button.MouseLeave:Connect(function()
			if hovered == i then
				hovered = nil
			end
			settle(i)
		end)
		Kit.onPress(button, function()
			onPick(i)
		end)
	end
	Kit.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(28, 24, 40),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.2, 0.2),
		ZIndex = z + 2,
		Parent = parent,
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
		Size = UDim2.fromScale(0.11, 0.11),
		ZIndex = z + 3,
		Parent = parent,
	})
	return function(i: number?)
		local before = lit
		lit = i
		for j in petals do
			if j == before or j == i then
				settle(j)
			end
		end
		if i and i ~= before then
			Audio.hoverAt(i, 4)
		end
	end
end

-- The mark that pops up off the table for each action card (and the 7-0 swaps).
local POP_MARKS = { skip = "⊘", reverse = "⇄", draw2 = "+2", wild = "★", wild4 = "+4", wild6 = "+6", skipall = "⊘⊘", discardall = "ALL" }

function ColorClash.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local docked = false
	local shownTop: number? = nil
	local topVisual: GuiObject? = nil
	-- "Last card!": armed with the button before playing your second-to-last card.
	local armed = false
	local canCall = false
	-- Jump-in: set while the card being played goes down out of turn.
	local jumping = false
	local function sendPlay(id: number, color: number?, target: number?)
		sendMove({ kind = if jumping then "jump" else "play", card = id, color = color, target = target, call = if canCall then armed else nil })
		armed = false
		jumping = false
	end

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
	-- For the shared Table-view pieces (info card, notices, score sheet).
	local tableUi: any = { root = root, extras = {}, docked = false }
	-- Hand order: by color (the server's order) or by number.
	local sortBy = "color"

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
	-- The 2D view's copy of the Table-view info card (score, target, house rules).
	local feltInfo = Kit.label("", {
		TextSize = 13,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Position = UDim2.new(0, 14, 0, 36),
		Size = UDim2.new(0.3, 0, 0, 60),
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
	-- Say it before you go down to one card, or the next player can catch you.
	local callAction: TextButton
	local function paintCall()
		callAction.Text = if lateCall then "Say it! LAST CARD!" elseif armed then "Last card! ✓" else "Last card!"
		callAction.BackgroundColor3 = if armed then Color3.fromRGB(70, 170, 100) elseif lateCall then Theme.Bad else Color3.fromRGB(235, 160, 40)
	end
	local lateCall = false -- you forgot: the button says it late instead of arming
	-- Big, round and pulsing beside your hand (UNO! mobile style), only while it matters.
	callAction = Kit.button("Last card!", function()
		if lateCall then
			sendMove({ kind = "call" })
			return
		end
		armed = not armed
		paintCall()
	end, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.13, 0, 1, -18),
		Size = UDim2.fromOffset(104, 104),
		BackgroundColor3 = Color3.fromRGB(235, 160, 40),
		TextColor3 = Color3.new(1, 1, 1),
		TextWrapped = true,
		TextSize = 20,
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})
	Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = callAction })
	HudKit.pulse(Kit.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = callAction }))
	-- Someone went down to one card without saying it: catch them before you move.
	local catchAction = Kit.button("CATCH!", function()
		sendMove({ kind = "catch" })
	end, { Size = UDim2.new(0, 190, 1, 0), BackgroundColor3 = Theme.Bad, TextColor3 = Color3.new(1, 1, 1), LayoutOrder = -1, Visible = false, Parent = actions })
	local catchStroke = Kit.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = catchAction })
	HudKit.pulse(catchStroke)
	-- Hit by a lone Wild +4: challenge it, like the official game (UNO! mobile's prompt).
	local challengeAction = Kit.button("Challenge the +4!", function()
		sendMove({ kind = "challenge" })
	end, { Size = UDim2.new(0, 190, 1, 0), BackgroundColor3 = Color3.fromRGB(150, 90, 230), TextColor3 = Color3.new(1, 1, 1), LayoutOrder = 3, Visible = false, Parent = actions })
	local render: () -> ()
	local sortAction = Kit.button("Sort: color", function()
		sortBy = if sortBy == "color" then "number" else "color"
		if snapshot then
			render()
		end
	end, { Size = UDim2.new(0, 120, 1, 0), BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, TextSize = 14, LayoutOrder = 9, Parent = actions })
	local shownAction: string? = nil
	local shownJump: string? = nil
	-- Call-outs float over the whole screen (in Table view this board is only the strip
	-- along the bottom). In a game picker preview they stay inside the tile.
	local function say(text: string, color: Color3?, y: number?)
		local screen = if Kit.inPreview(container) then nil else container:FindFirstAncestorWhichIsA("ScreenGui")
		HudKit.callout(screen or root, text, color, y)
	end
	Kit.onPress(drawButton, function()
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
	-- Scaled text in turned cards can come up empty when the cards are made before the
	-- hand has its size (the first deal), and stays empty until something redraws it (a
	-- hover). Re-scaling the labels once the hand is laid out fixes that.
	local function refitText()
		for _, d in hand:GetDescendants() do
			if d:IsA("TextLabel") and d.TextScaled then
				d.TextScaled = false
				d.TextScaled = true
			end
		end
	end
	local function refitSoon()
		task.defer(refitText)
		task.delay(0.25, function()
			if hand.Parent then
				refitText()
			end
		end)
	end
	hand:GetPropertyChangedSignal("AbsoluteSize"):Connect(refitSoon)
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
	Kit.hotkeyArea(overlay)
	local function showOverlay()
		-- A game picker preview keeps it in the tile.
		local screen = if Kit.inPreview(container) then nil else container:FindFirstAncestorWhichIsA("ScreenGui")
		overlay.Parent = screen or root
		overlay.Visible = true
	end
	local pop = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	-- Wild color picker: a round wheel of the four colors, each quarter its own button.
	-- In Table view it rises out of the middle of the table, tilted toward you
	-- (ColorClashFx.wheel), with a Back button under it; in the 2D view it bursts out of
	-- the middle of the screen, and tapping outside it puts the wild back.
	local pendingWild: number? = nil
	local pendingSeven: number? = nil
	local closeWheel3D: (() -> ())? = nil
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
	local backButton = Kit.button("Back", function() end, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.6),
		Size = UDim2.fromOffset(130, 40),
		BackgroundColor3 = Theme.PanelLight,
		TextColor3 = Theme.Text,
		Visible = false,
		ZIndex = 53,
		Parent = overlay,
	})

	-- Arrow keys / D-pad / left stick pick a direction on the wheel, A / Enter / Space
	-- plays it, B / Backspace puts the wild back. Bound only while the wheel is open, above
	-- the camera and movement controls so the arrows don't also move anything.
	local lights: { (number?) -> () } = {}
	local litColor: number? = nil
	local function light(i: number?)
		litColor = i
		for _, set in lights do
			set(i)
		end
	end
	local WHEEL_ACTION = "ColorClashWheel"
	local DIRECTION_KEYS = {
		[Enum.KeyCode.Up] = 1, [Enum.KeyCode.DPadUp] = 1, [Enum.KeyCode.W] = 1,
		[Enum.KeyCode.Right] = 2, [Enum.KeyCode.DPadRight] = 2, [Enum.KeyCode.D] = 2,
		[Enum.KeyCode.Down] = 3, [Enum.KeyCode.DPadDown] = 3, [Enum.KeyCode.S] = 3,
		[Enum.KeyCode.Left] = 4, [Enum.KeyCode.DPadLeft] = 4, [Enum.KeyCode.A] = 4,
	}
	local CONFIRM_KEYS = { [Enum.KeyCode.ButtonA] = true, [Enum.KeyCode.Return] = true, [Enum.KeyCode.KeypadEnter] = true, [Enum.KeyCode.Space] = true }
	local BACK_KEYS = { [Enum.KeyCode.ButtonB] = true, [Enum.KeyCode.Backspace] = true }
	local stickHeld = false
	local closePicker: () -> ()
	local pick: (color: number) -> ()
	local function onWheelInput(_: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			local p = input.Position
			if math.max(math.abs(p.X), math.abs(p.Y)) < 0.6 then
				stickHeld = false
			elseif not stickHeld then
				stickHeld = true
				-- The stick's Y is up-positive.
				light(if math.abs(p.Y) >= math.abs(p.X) then (if p.Y > 0 then 1 else 3) else (if p.X > 0 then 2 else 4))
			end
			return Enum.ContextActionResult.Sink
		end
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Sink
		end
		local direction = DIRECTION_KEYS[input.KeyCode]
		if direction then
			light(direction)
		elseif CONFIRM_KEYS[input.KeyCode] then
			if litColor then
				pick(litColor)
			end
		elseif BACK_KEYS[input.KeyCode] then
			closePicker()
		end
		return Enum.ContextActionResult.Sink
	end
	local wheelKeys = { Enum.KeyCode.Thumbstick1 }
	for key in DIRECTION_KEYS do
		table.insert(wheelKeys, key)
	end
	for key in CONFIRM_KEYS do
		table.insert(wheelKeys, key)
	end
	for key in BACK_KEYS do
		table.insert(wheelKeys, key)
	end

	function closePicker()
		pendingWild = nil
		ContextActionService:UnbindAction(WHEEL_ACTION)
		light(nil)
		stickHeld = false
		picker.Visible = false
		pickerShade.Visible = false
		backButton.Visible = false
		if closeWheel3D then
			closeWheel3D()
			closeWheel3D = nil
		end
	end
	function pick(color: number)
		if pendingWild then
			sendPlay(pendingWild, color)
		end
		closePicker()
	end
	table.insert(lights, buildWheel(picker, 53, pick))
	Kit.onPress(pickerShade, closePicker)
	Kit.onPress(backButton, closePicker)
	local function openPicker(id: number)
		closePicker()
		pendingWild = id
		showOverlay()
		-- A controller's selection would still sit on the wild in your hand; let go of it
		-- so A on the wheel doesn't also press that card again.
		GuiService.SelectedObject = nil
		ContextActionService:BindActionAtPriority(WHEEL_ACTION, onWheelInput, false, Enum.ContextActionPriority.High.Value + 10, table.unpack(wheelKeys))
		if docked then
			local lights3D: ((number?) -> ())? = nil
			local close3D = Fx.wheel(function(frame: Frame)
				lights3D = buildWheel(frame, 1, pick)
			end)
			if close3D and lights3D then
				local set = lights3D
				table.insert(lights, set)
				closeWheel3D = function()
					table.remove(lights, table.find(lights, set))
					close3D()
				end
			else
				closeWheel3D = close3D
			end
		end
		if closeWheel3D then
			backButton.Visible = true
			return
		end
		pickerShade.Visible = true
		picker.Visible = true
		picker.Rotation = -40
		pickerScale.Scale = 0.15
		TweenService:Create(pickerScale, pop, { Scale = 1 }):Play()
		TweenService:Create(picker, pop, { Rotation = 0 }):Play()
	end

	-- 7-0 rule: playing a 7 asks who to swap hands with (a row of players in the middle).
	local swapPanel = Kit.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(30, 26, 46),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(520, 130),
		Visible = false,
		ZIndex = 52,
		Parent = overlay,
	}, { Kit.corner(16), Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 2, Transparency = 0.3 }) })
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(9999, 9999), Parent = swapPanel })
	Kit.label("Swap hands with...", { Font = Theme.FontBold, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 26), ZIndex = 53, Parent = swapPanel })
	local swapRow = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 42), Size = UDim2.new(1, -20, 0, 44), ZIndex = 53, Parent = swapPanel })
	local swapList = Kit.list(8, true)
	swapList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	swapList.Parent = swapRow
	local function closeSwap()
		pendingSeven = nil
		swapPanel.Visible = false
	end
	Kit.button("Back", closeSwap, { BackgroundTransparency = 1, TextColor3 = Theme.SubText, Position = UDim2.new(0, 0, 1, -32), Size = UDim2.new(1, 0, 0, 28), ZIndex = 53, Parent = swapPanel })
	local openSwap: (id: number) -> ()

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
	-- Plays a card from your hand: Wilds ask for a color first, and with the 7-0 rule a 7
	-- asks who to swap hands with.
	local function playCard(id: number)
		local card = Rules.cards[id]
		if card.kind == "wild" or card.kind == "wild4" then
			openPicker(id)
		elseif snapshot.view.sevenZero and card.kind == "number" and card.value == 7 then
			openSwap(id)
		else
			sendPlay(id)
		end
	end
	local function playDrawn()
		if drawnShown then
			playCard(drawnShown)
		end
	end
	bandButton("Play it", Color3.fromRGB(70, 170, 100), 0.3, playDrawn)
	-- Force play (house rule): the card has to be played, so no Keep.
	local keepButton = bandButton("Keep it", Color3.fromRGB(70, 110, 200), 0.7, function()
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

	function openSwap(id: number)
		closeSwap()
		pendingSeven = id
		Kit.clear(swapRow)
		local view = snapshot.view
		local count = 0
		for seat = 1, #(view.handCounts or {}) do
			if seat ~= snapshot.yourSeat then
				count += 1
				local n = view.handCounts[seat]
				Kit.button(`{nameOf(seat)} ({n})`, function()
					if pendingSeven then
						sendPlay(pendingSeven, nil, seat)
					end
					closeSwap()
				end, { Size = UDim2.new(0, 150, 1, 0), TextSize = 15, LayoutOrder = seat, ZIndex = 54, Parent = swapRow })
			end
		end
		swapPanel.Size = UDim2.fromOffset(math.max(320, count * 158 + 20), 130)
		showOverlay()
		swapPanel.Visible = true
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
				elseif card.kind == "wild6" then `a Wild +6 ({Rules.colorNames[action.color]})`
				else `a {Rules.colorNames[card.color]} {KIND_NAMES[card.kind] or card.kind}`
			if action.bounced then
				return `{who} bounced the draw cards back with {what}`
			elseif action.discarded and action.discarded > 0 then
				return `{who} played {what} and {action.discarded} more`
			end
			if action.swap then
				return `{who} played {what} and swapped hands with {nameOf(action.swap)}`
			elseif action.rotate then
				return `{who} played {what}: every hand moves along`
			end
			return `{who} played {what}`
		elseif action.kind == "draw" then
			local text = if action.count == 1 then `{who} drew a card` else `{who} drew {action.count} cards`
			if action.mercy then
				text ..= `: {nameOf(action.mercy)} hit 25 and is out!`
			end
			return text
		elseif action.kind == "call" then
			return `{who} said "Last card!" just in time`
		elseif action.kind == "pass" then
			return `{who} passed`
		elseif action.kind == "catch" then
			return `{who} caught {nameOf(action.target)}: +2 cards`
		elseif action.kind == "challenge" then
			return if action.guilty then `{who} challenged {nameOf(action.target)}'s +4 and won: they draw 4` else `{who} challenged {nameOf(action.target)}'s +4 and lost: +6 cards`
		end
		return ""
	end

	-- Effects for what just happened (each change of lastAction, not the first look):
	-- action cards pop their mark up off the table, and drawn cards fly off the pile,
	-- into your hand (2D, card by card, flipping face up as they land) or to the other
	-- player's seat (3D card backs).
	local lastKey: string? = nil
	local knownHand: { [number]: boolean } = {}
	local function actionKey(view: any): string
		local a = view.lastAction
		if not a then
			return ""
		end
		local total = 0
		for _, n in view.handCounts or {} do
			total += n
		end
		return `{a.seat}:{a.kind}:{a.card or 0}:{a.count or 0}:{view.deckCount}:{total}`
	end
	-- Center of a GUI object, in the overlay's own pixels.
	local function centerIn(object: GuiObject): Vector2
		return object.AbsolutePosition + object.AbsoluteSize / 2 - overlay.AbsolutePosition
	end
	local function flyIn(id: number, target: GuiObject, wait: number, from: Vector2)
		target.Visible = false
		task.delay(wait, function()
			if not target.Parent then
				return
			end
			showOverlay()
			local size = target.AbsoluteSize
			local flyer = Kit.new("Frame", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(from.X, from.Y),
				Size = UDim2.fromOffset(size.X * 0.45, size.Y * 0.45),
				Rotation = -25,
				ZIndex = 60,
				Parent = overlay,
			})
			cardVisual(nil).Parent = flyer
			local to = centerIn(target)
			local travel = TweenService:Create(flyer, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(to.X, to.Y),
				Size = UDim2.fromOffset(size.X, size.Y),
				Rotation = target.Rotation,
			})
			travel.Completed:Once(function()
				-- Flip face up as it slots in.
				local shut = TweenService:Create(flyer, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.fromOffset(0, size.Y) })
				shut.Completed:Once(function()
					Kit.clear(flyer)
					cardVisual(id).Parent = flyer
					local open = TweenService:Create(flyer, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(size.X, size.Y) })
					open.Completed:Once(function()
						flyer:Destroy()
						if target.Parent then
							target.Visible = true
						end
					end)
					open:Play()
				end)
				shut:Play()
			end)
			travel:Play()
		end)
	end
	local function playEffects(view: any, slots: { [number]: { slot: Frame, face: GuiObject } })
		local key = actionKey(view)
		local first = lastKey == nil
		local changed = key ~= lastKey
		lastKey = key
		local before = knownHand
		knownHand = {}
		for _, id in view.hand or {} do
			knownHand[id] = true
		end
		if first or not changed then
			return
		end
		local a = view.lastAction
		if a.kind == "play" then
			local card = Rules.cards[a.card]
			local color = COLORS[a.color or (card and card.color) or 0] or Theme.Accent
			-- One call-out per hit: the pill over the table names the victim, so no 3D pop.
			if a.target then
				Fx.pop("⇆", color)
			elseif a.rotated then
				Fx.pop("⟳", color)
			elseif card and POP_MARKS[card.kind] and not a.victim then
				Fx.pop(POP_MARKS[card.kind], color)
			end
		elseif a.kind == "draw" and (a.count or 0) > 0 then
			if a.seat == snapshot.yourSeat then
				-- From the pile on the table (Table view) or on the felt (2D).
				local from = if docked then Fx.pileOnScreen() else nil
				if not from and drawSlot.AbsoluteSize.X > 0 and felt.Visible then
					from = centerIn(drawSlot)
				elseif from then
					from -= overlay.AbsolutePosition
				end
				if not from then
					return
				end
				local wait = 0
				for _, id in view.hand or {} do
					if not before[id] then
						local target: GuiObject? = if id == drawnShown then drawnSlot elseif slots[id] then slots[id].face else nil
						if target then
							flyIn(id, target, wait, from)
							wait += 0.14
						end
					end
				end
			elseif snapshot.table and snapshot.table.seats then
				local tableSeat = snapshot.table.seats[a.seat]
				if tableSeat then
					Fx.dealTo(tableSeat, a.count)
				end
			end
		end
	end

	-- The +4 proof: the challenger sees the other hand for a moment (official rule).
	local proofShown: string? = nil
	local function showProof(proof: any)
		local key = `{proof.by}|{#proof.hand}|{proof.guilty}`
		if key == proofShown then
			return
		end
		proofShown = key
		showOverlay()
		local panel = Kit.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(30, 26, 46),
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.38),
			Size = UDim2.new(0, math.clamp(#proof.hand * 58 + 40, 260, 760), 0, 170),
			ZIndex = 56,
			Parent = overlay,
		}, { Kit.corner(16), Kit.new("UIStroke", { Color = Color3.fromRGB(190, 120, 255), Thickness = 2 }) })
		Kit.label(`{nameOf(proof.by)}'s hand: {if proof.guilty then "they had the color!" else "no card of the color"}`, {
			Font = Theme.FontBold,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 24),
			ZIndex = 57,
			Parent = panel,
		})
		local row = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 40), Size = UDim2.new(1, -32, 0, 112), ZIndex = 57, Parent = panel })
		local list = Kit.list(6, true)
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.Parent = row
		for i, id in proof.hand do
			local slot = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(76, 112), LayoutOrder = i, ZIndex = 57, Parent = row })
			local face = cardVisual(id)
			face.ZIndex = 58
			for _, d in face:GetDescendants() do
				if d:IsA("GuiObject") then
					d.ZIndex = 59
				end
			end
			face.Parent = slot
		end
		Kit.popIn(panel)
		task.delay(3.2, function()
			if panel.Parent then
				panel:Destroy()
			end
		end)
	end

	-- Points: the round summary and the final standings (CC-1 / CC-2).
	local talliedRound: number? = nil
	local finalShown = false
	local function standings(view: any)
		local r = view.roundResult
		if not r then
			return
		end
		local rows = {}
		local order = {}
		for seat = 1, #(view.handCounts or {}) do
			table.insert(order, seat)
		end
		table.sort(order, function(a, b)
			if view.target > 0 and view.scores[a] ~= view.scores[b] then
				return view.scores[a] > view.scores[b]
			end
			local ha, hb = r.hands[a] or r.hands[tostring(a)], r.hands[b] or r.hands[tostring(b)]
			return ((ha and ha.points) or 0) < ((hb and hb.points) or 0)
		end)
		for place, seat in order do
			local h = r.hands[seat] or r.hands[tostring(seat)] or { count = 0, points = 0 }
			local row = { `{place}. {nameOf(seat)}`, if h.out then "out" else `{h.count} cards`, tostring(h.points) }
			if view.target > 0 then
				table.insert(row, tostring(view.scores[seat]))
			end
			table.insert(rows, row)
		end
		local columns = { "Player", "Left", "Points left" }
		if view.target > 0 then
			table.insert(columns, "Score")
		end
		local title = if view.target > 0 then `Final scores · played to {view.target}` else `{nameOf(r.winner)} went out: +{r.points}`
		CardTable.scoreSheet(tableUi, title, columns, rows)
	end

	function render()
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
		colorLabel.Text = if Rules.colorNames[view.color] and Access.colorMarks() then `{MARKS[view.color]} {Rules.colorNames[view.color]}` else Rules.colorNames[view.color] or ""
		colorLabel.TextColor3 = COLORS[view.color] or Theme.Text
		directionLabel.Text = if view.direction == 1 then "Normal order" else "⇄ Reversed"
		lastLabel.Text = describe(view.lastAction)
		-- The calls, out loud: "Last card!", getting caught, and who a hit card hits.
		local action = view.lastAction
		if action then
			local total = 0
			for _, n in view.handCounts or {} do
				total += n
			end
			local key = `{action.kind}|{action.seat}|{action.card}|{action.target}|{total}`
			if shownAction ~= nil and key ~= shownAction then
				if action.jumped then
					say(if action.seat == snapshot.yourSeat then "YOU JUMPED IN!" else `{string.upper(nameOf(action.seat))} JUMPED IN!`, Color3.fromRGB(255, 220, 60), 0.36)
				end
				if action.kind == "challenge" then
					local loser = if action.guilty then action.target else action.seat
					local you = loser == snapshot.yourSeat
					say(if action.guilty then `GUILTY! {if you then "You draw" else nameOf(loser) .. " draws"} 4` else `NOT GUILTY! {if you then "You draw" else nameOf(loser) .. " draws"} 6`, Color3.fromRGB(190, 120, 255))
				elseif action.kind == "catch" then
					say(if action.target == snapshot.yourSeat then "CAUGHT! You draw 2" else `CAUGHT! {nameOf(action.target)} draws 2`, Theme.Bad)
				elseif action.kind == "play" and action.victim then
					local card = Rules.cards[action.card]
					local hit = if action.bounced then "BOUNCED!"
						elseif card.kind == "skip" or card.kind == "reverse" then "SKIPPED!"
						elseif card.kind == "draw2" then "+2!"
						elseif card.kind == "wild6" then "+6!"
						else "+4!"
					local you = action.victim == snapshot.yourSeat
					say(if you then `{hit}  That's you` else `{hit}  {nameOf(action.victim)}`, if card.kind == "wild4" then Color3.fromRGB(190, 120, 255) else Theme.Bad)
				elseif action.swap or action.rotate then
					say(if action.rotate then "Hands move along!" else `SWAP! {nameOf(action.seat)} ⇄ {nameOf(action.swap)}`, Color3.fromRGB(120, 210, 255))
				elseif action.skipAll then
					say(if action.seat == snapshot.yourSeat then "EVERYONE SKIPPED!  Go again" else `EVERYONE SKIPPED!  {nameOf(action.seat)} goes again`, Theme.Bad)
				elseif action.discarded and action.discarded > 0 then
					say(`DISCARD ALL!  {nameOf(action.seat)} dumps {action.discarded + 1}`, Color3.fromRGB(120, 210, 255))
				end
				if action.mercy then
					say(if action.mercy == snapshot.yourSeat then "25 CARDS!  You're out" else `25 CARDS!  {nameOf(action.mercy)} is out`, Theme.Bad, 0.42)
				end
				if action.called then
					say(if action.seat == snapshot.yourSeat then "LAST CARD!" else `{nameOf(action.seat)}: LAST CARD!`, Color3.fromRGB(255, 200, 70), 0.3)
				end
			end
			shownAction = key
		elseif shownAction == nil then
			shownAction = "" -- the first render: say nothing about what came before
		end
		canCall = (myTurn or next(view.jumpIns or {}) ~= nil) and view.lastCall == true and #(view.hand or {}) == 2
		if not canCall then
			armed = false
		end
		lateCall = view.canCallLate == true
		callAction.Visible = canCall or lateCall
		paintCall()
		catchAction.Visible = view.canCatch == true
		challengeAction.Visible = view.canChallenge == true
		catchAction.Text = if view.exposed then `CATCH {string.upper(nameOf(view.exposed))}!` else "CATCH!"
		pendingLabel.Text = if view.canChallenge then `+4 waiting! Stack, take them, or challenge.` elseif view.pendingDraw > 0 then `+{view.pendingDraw} waiting! Stack a draw card or take them.` else ""

		drawAction.Visible = myTurn and not view.canPass
		drawAction.Text = if view.pendingDraw > 0 then `Take {view.pendingDraw} cards` else "Draw a card"
		-- After drawing a card you can play, it's shown in the middle with Play / Keep.
		-- (The server only keeps a drawn card when it fits.) Force play hides Keep.
		local drawnPlayable = myTurn and view.drawnCard ~= nil
		showDrawn(if drawnPlayable then view.drawnCard else nil)
		keepButton.Visible = view.canPass == true
		passAction.Visible = myTurn and view.canPass and not drawnPlayable
		local jumpable = {}
		for _, id in view.jumpIns or {} do
			jumpable[id] = true
		end
		local canJump = not myTurn and next(jumpable) ~= nil
		if myTurn then
			jumping = false
		end
		if not myTurn and not (jumping and canJump) then
			jumping = false
			closePicker()
			closeSwap()
		end
		-- Holding the same card as the top one: shout it, once per top card.
		local jumpKey = if canJump then `{view.topCard}|{#(view.recent or {})}|{view.deckCount}` else nil
		if jumpKey and jumpKey ~= shownJump then
			say("JUMP IN!  Slam the glowing card", Color3.fromRGB(255, 220, 60), 0.72)
		end
		shownJump = jumpKey

		-- Hand.
		Kit.clear(hand)
		handHover.clear()
		local playable = {}
		for _, id in view.playable or {} do
			playable[id] = true
		end
		-- The card on the Play / Keep prompt is that card: it isn't also in the fan.
		local held = {}
		for _, id in view.hand or {} do
			if not (drawnPlayable and id == view.drawnCard) then
				table.insert(held, id)
			end
		end
		if sortBy == "number" then
			-- Numbers low to high, then actions, then Wilds; color breaks ties.
			local RANK = { skip = 10, reverse = 11, draw2 = 12, skipall = 13, discardall = 14, wild = 20, wild4 = 21, wild6 = 22 }
			table.sort(held, function(a, b)
				local ca, cb = Rules.cards[a], Rules.cards[b]
				local ra = if ca.kind == "number" then ca.value :: number else RANK[ca.kind] or 30
				local rb = if cb.kind == "number" then cb.value :: number else RANK[cb.kind] or 30
				if ra ~= rb then
					return ra < rb
				end
				if ca.color ~= cb.color then
					return ca.color < cb.color
				end
				return a < b
			end)
		end
		sortAction.Text = if sortBy == "color" then "Sort: color" else "Sort: number"
		local slots: { [number]: { slot: Frame, face: GuiObject } } = {}
		-- Off your turn the server doesn't say what's playable, so match against the
		-- pile here: those cards stay lifted, so you can plan your next move.
		local function wouldFit(id: number): boolean
			local card = Rules.cards[id]
			local top = view.topCard and Rules.cards[view.topCard]
			if not card or not top then
				return false
			end
			if card.color == 0 or card.color == view.color then
				return true
			end
			if card.kind == "number" then
				return top.kind == "number" and top.value == card.value
			end
			return card.kind == top.kind
		end
		local count = #held
		for index, id in held do
			local canPlay = (myTurn and playable[id] == true) or (canJump and jumpable[id] == true)
			local lifted = canPlay or (not myTurn and wouldFit(id))
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
			slots[id] = { slot = slot, face = face }
			local drop = (offset * spread / 28) ^ 2 * 0.5 -- the fan's curve, in card heights
			-- Cards you can play stand well up out of the fan.
			local rest = UDim2.fromScale(0, drop + (if lifted then -0.18 else 0))
			face.Position = rest
			face.Rotation = offset * spread
			-- Nothing is grayed out (Giovanni's note): cards you can play stand up out of
			-- the fan and the rest stay down, all in full color.
			if id == view.drawnCard then
				Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 5, Parent = face })
			elseif canJump and jumpable[id] then
				-- The card you can jump in with glows.
				HudKit.pulse(Kit.new("UIStroke", { Color = Color3.fromRGB(255, 220, 60), Thickness = 5, Parent = face }))
			end
			local button = Kit.new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = slot })
			-- Hover: the card comes up out of the hand, straightens and sits on top of its
			-- neighbours.
			local lift = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			-- One card at a time (PlayingCard.hover picks the top card under the mouse).
			local function play()
				if not canPlay then
					return
				end
				jumping = not myTurn
				playCard(id)
			end
			handHover.add(slot, function()
				slot.ZIndex = 10
				TweenService:Create(face, lift, { Position = UDim2.fromScale(0, -0.22), Rotation = 0 }):Play()
			end, function()
				slot.ZIndex = 1
				TweenService:Create(face, lift, { Position = rest, Rotation = offset * spread }):Play()
			end, play)
			Kit.onPress(button, play)
		end
		squeezeHand()
		refitSoon()
		playEffects(view, slots)

		if view.proof then
			showProof(view.proof)
		end
		-- Table view: running lines on the left, the round summary over the hand.
		local info = {}
		if view.target > 0 then
			local me = snapshot.yourSeat
			table.insert(info, `Play to {view.target} · round {view.round}`)
			if me then
				table.insert(info, `You: {view.scores[me]} pts`)
			end
			local best, bestScore = nil, -1
			for seat, score in view.scores do
				if seat ~= me and score > bestScore then
					best, bestScore = seat, score
				end
			end
			if best then
				table.insert(info, `Leader: {nameOf(best)} {bestScore}`)
			end
		end
		if view.teams and view.partner then
			table.insert(info, `Partner: {nameOf(view.partner)} ({view.handCounts[view.partner]} cards)`)
		end
		local modes = {}
		if view.stackMode == "off" then
			table.insert(modes, "No stacking")
		elseif view.stackMode == "up" then
			table.insert(modes, "Stack +4 on +2")
		elseif view.stackMode == "any" then
			table.insert(modes, "Stack anything")
		end
		if view.chaos then
			table.insert(modes, "Chaos deck")
		end
		if view.reverseBounce then
			table.insert(modes, "Reverse bounces")
		end
		if view.noBluff then
			table.insert(modes, "No bluffing")
		end
		if #modes > 0 then
			table.insert(info, table.concat(modes, " · "))
		end
		if #info > 0 and view.target == 0 and not view.teams then
			table.insert(info, 1, "House rules")
		end
		CardTable.info(tableUi, if #info > 0 then info else nil)
		feltInfo.Text = table.concat(info, "\n")
		local r = view.roundResult
		if r and view.phase == "roundEnd" then
			local lines = { `+{r.points} points from the other hands` }
			if view.target > 0 then
				local me = snapshot.yourSeat
				if me then
					table.insert(lines, `You: {view.scores[me]} of {view.target}`)
				end
			end
			table.insert(lines, "Next round coming up...")
			CardTable.notice(tableUi, `{nameOf(r.winner)} won round {r.round}!`, lines, Color3.fromRGB(255, 220, 60))
			if talliedRound ~= r.round then
				talliedRound = r.round
				say(`ROUND {r.round}!  {string.upper(nameOf(r.winner))} +{r.points}`, Color3.fromRGB(255, 220, 60), 0.3)
			end
			lastLabel.Text = `{nameOf(r.winner)} won round {r.round}: +{r.points}. Next round soon...`
		else
			CardTable.notice(tableUi, nil)
		end
		if view.winner and r and not finalShown then
			finalShown = true
			task.delay(1.2, function()
				if root.Parent and snapshot then
					standings(snapshot.view)
				end
			end)
		end
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
		setDocked = function(value: boolean)
			docked = value
			tableUi.docked = value
			if docked then
				callAction.AnchorPoint = Vector2.new(1, 1)
				callAction.Position = UDim2.new(0.13, 0, 1, -18)
			else
				callAction.AnchorPoint = Vector2.new(0, 1)
				callAction.Position = UDim2.new(0, 14, 0.6, 40)
			end
			felt.Visible = not docked
			if docked then
				pendingLabel.Parent = root
				pendingLabel.Position = UDim2.new(0, 0, 0.58, 0)
				hand.Position = UDim2.new(0.14, 0, 0.6, 0)
				hand.Size = UDim2.new(0.72, 0, 0.47, 0)
				hand.ScrollBarThickness = 0
				actions.AnchorPoint = Vector2.new(1, 1)
				actions.Position = UDim2.new(1, -14, 1, -14)
				actions.Size = UDim2.new(0, 560, 0, 44)
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
		-- Table view: look at the draw pile on the table and click it to draw (it glows a
		-- little whenever drawing is something you can do). Table3D/SceneTap.
		tapTable = function(id: any)
			if id == "draw" and drawAction.Visible then
				sendMove({ kind = "draw" })
			end
		end,
		canTap = function(id: any): boolean
			return id == "draw" and drawAction.Visible
		end,
		tableMarks = function(): { [any]: any }?
			return if drawAction.Visible then { draw = "target" } else nil
		end,
		destroy = function()
			ContextActionService:UnbindAction(WHEEL_ACTION)
			overlay:Destroy()
			root:Destroy()
		end,
	}
end

return ColorClash
