-- Shared layout for the card-game screens (I Doubt It, President, Slap Stack, Hearts,
-- Spades, Thirty-One, Palace, Old Maid, Snap, Gin Rummy, Oh Hell): a row of seat chips on
-- top, the felt in the middle, a prompt and action buttons, and your hand along the bottom.

local Kit = require(script.Parent.Kit)
local HudKit = require(script.Parent.HudKit)
local PlayingCard = require(script.Parent.PlayingCard)
local Theme = Kit.Theme

local CardTable = {}

-- Each layout's buttons frame -> its layout, so CardTable.buttons can place them.
local layoutOf: { [Instance]: any } = setmetatable({}, { __mode = "k" }) :: any

local BIG_LINE = 22 -- px for a chip's bigLine
local NAME_H = 22 -- px for a chip's name row (avatar + name)

export type Layout = {
	root: Frame,
	seats: Frame,
	felt: Frame,
	content: Frame, -- inside the felt; safe to clear and redraw
	prompt: TextLabel,
	buttons: Frame,
	hand: Frame,
	-- Table view: true lays the strip out like cards held at the table (see setDocked).
	setDocked: (docked: boolean) -> (),
	-- Set by the game: redraws the screen (called when the hand changes size or shape).
	refresh: (() -> ())?,
	bigButtons: { TextButton },
}

function CardTable.layout(container: Instance): Layout
	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
	local seats = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.17, 0), Parent = root })
	local list = Kit.list(6, true)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = seats
	local felt = PlayingCard.felt({ Position = UDim2.new(0, 0, 0.19, 0), Size = UDim2.new(1, 0, 0.42, 0), Parent = root })
	local content = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = felt })
	local prompt = Kit.label("", {
		TextSize = 16,
		Font = Theme.FontBold,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0.62, 0),
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, 22),
		ZIndex = 3,
		Parent = root,
	})
	-- A dark pill behind the prompt, sized to its text, so it reads over the felt and the
	-- 3D room alike. Hidden while there's nothing to say.
	local promptPill = Kit.new("Frame", {
		Name = "PromptPill",
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.62, -2),
		Visible = false,
		ZIndex = 2,
		Parent = root,
	}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), Kit.new("UIStroke", { Color = Theme.Accent, Transparency = 0.6 }) })
	local function fitPill()
		local width = math.min(prompt.TextBounds.X + 30, prompt.AbsoluteSize.X)
		promptPill.Size = UDim2.fromOffset(width, 26)
		promptPill.Visible = prompt.Text ~= ""
	end
	prompt:GetPropertyChangedSignal("TextBounds"):Connect(fitPill)
	prompt:GetPropertyChangedSignal("Text"):Connect(fitPill)
	prompt:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitPill)
	local buttons = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0.62, 24),
		Size = UDim2.new(1, 0, 0, 38),
		Parent = root,
	})
	local buttonList = Kit.list(8, true)
	buttonList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	buttonList.Parent = buttons
	local hand = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0.62, 66), Size = UDim2.new(1, 0, 0.38, -66), Parent = root })
	local ui: Layout
	-- Redraw once the hand has its new size (a docked layout, a resized screen), so the
	-- cards are measured against the right frame.
	local refreshQueued = false
	local function queueRefresh()
		if refreshQueued then
			return
		end
		refreshQueued = true
		task.defer(function()
			refreshQueued = false
			if ui.refresh and root.Parent then
				ui.refresh()
			end
		end)
	end
	hand:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueRefresh)

	-- Table view docks the bottom of this screen (MatchView.DOCK, held). The cards on the
	-- table are on the 3D table, so the seats and the felt go, and what's left is laid out
	-- like cards held in front of you: a big fan along the bottom edge running a little off
	-- the screen, the prompt just above it and the buttons in the bottom-right corner (or
	-- in a row over the hand when there are many, like bids).
	local function setDocked(docked: boolean)
		seats.Visible = not docked
		felt.Visible = not docked
		PlayingCard.setHeld(hand, docked)
		buttons:SetAttribute("Held", docked)
		local promptY = if docked then 0.555 else 0.62
		prompt.Position = UDim2.new(0, 0, promptY, 0)
		promptPill.Position = UDim2.new(0.5, 0, promptY, -2)
		if docked then
			hand.Size = UDim2.new(0.72, 0, 0.47, 0)
		else
			hand.Position = UDim2.new(0, 0, 0.62, 66)
			hand.Size = UDim2.new(1, 0, 0.38, -66)
		end
		for _, big in ui.bigButtons do
			big.AnchorPoint = if docked then Vector2.new(1, 1) else Vector2.new(1, 0.5)
			big.Position = if docked then UDim2.new(1, -14, 1, -66) else UDim2.new(0.97, 0, 0.81, 33)
		end
		CardTable.placeButtons(ui, #buttons:GetChildren() - 1)
		queueRefresh()
	end

	ui = {
		root = root,
		seats = seats,
		felt = felt,
		content = content,
		prompt = prompt,
		buttons = buttons,
		hand = hand,
		setDocked = setDocked,
		refresh = nil,
		bigButtons = {},
	}
	layoutOf[buttons] = ui
	return ui
end

-- Where the action buttons (and, held, the hand under them) go for `count` buttons.
function CardTable.placeButtons(ui: Layout, count: number)
	local frame = ui.buttons
	local list = frame:FindFirstChildOfClass("UIListLayout")
	local held = frame:GetAttribute("Held") == true
	local corner = held and count <= 2
	if corner then
		frame.AnchorPoint = Vector2.new(1, 1)
		frame.Position = UDim2.new(1, -14, 1, -14)
		frame.Size = UDim2.new(0, 360, 0, 44)
	elseif held then
		frame.AnchorPoint = Vector2.new(0, 0)
		frame.Position = UDim2.new(0, 0, 0.555, 26)
		frame.Size = UDim2.new(1, 0, 0, 38)
	else
		frame.AnchorPoint = Vector2.new(0, 0)
		frame.Position = UDim2.new(0, 0, 0.62, 24)
		frame.Size = UDim2.new(1, 0, 0, 38)
	end
	if list then
		list.HorizontalAlignment = if corner then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Center
	end
	if held then
		-- Just under the prompt, or under the row of buttons when they're over the hand.
		ui.hand.Position = UDim2.new(0.14, 0, 0.555, if corner or count == 0 then 30 else 68)
	end
end

function CardTable.nameOf(snapshot: any, seat: number?): string
	if seat == nil then
		return "?"
	end
	if seat == snapshot.yourSeat then
		return "You"
	end
	local s = snapshot.seats[seat]
	return if s then s.name else "?"
end

function CardTable.isActive(snapshot: any, seat: number?): boolean
	return seat ~= nil and table.find(snapshot.activeSeats, seat) ~= nil and snapshot.result == nil
end

-- chips: { { seat, lines = { string }, turn = bool?, highlight = bool?, dim = bool?, onClick = fn?,
--   bigLine = { text, color }? } } -- bigLine: one larger line under the name (lives, score)
function CardTable.seatChips(frame: Frame, snapshot: any, chips: { any })
	Kit.clear(frame)
	local width = math.clamp(math.floor((frame.AbsoluteSize.X - 6 * #chips) / math.max(1, #chips)), 90, 150)
	local lines, big = 0, 0
	for _, chip in chips do
		lines = math.max(lines, #(chip.lines or {}))
		if chip.bigLine then
			big = BIG_LINE
		end
	end
	-- As tall as the text in it (name plus its lines), not the whole strip.
	local height = math.min(math.max(24, frame.AbsoluteSize.Y - 4), 10 + NAME_H + big + lines * 15 + 2)
	for i, chip in chips do
		local clickable = chip.onClick ~= nil
		local seatColor = HudKit.seatColor(chip.seat or 0)
		local box = Kit.new("TextButton", {
			Text = "",
			AutoButtonColor = clickable,
			BorderSizePixel = 0,
			Size = UDim2.new(0, width, 0, height),
			LayoutOrder = i,
			Parent = frame,
		}, { Kit.corner(10), Kit.padding(5) })
		HudKit.glass(box, if chip.dim then 0.55 elseif chip.turn then 0 else 0.15)
		if clickable then
			-- Something to pick (who to ask, who to pass to): gold.
			box.HudGradient.Color = ColorSequence.new(Color3.fromRGB(255, 220, 110), Theme.Accent)
			box.Rim.Color = Color3.new(1, 1, 1)
			box.Rim.Transparency = 0.4
		elseif chip.turn then
			box.HudGradient.Color = ColorSequence.new(HudKit.shade(seatColor, 0.45), HudKit.shade(Theme.Panel, 0.1))
		end
		if chip.highlight then
			box.Rim.Color = Theme.Good
			box.Rim.Thickness = 3
			box.Rim.Transparency = 0
		elseif chip.turn then
			box.Rim.Color = Theme.Accent
			box.Rim.Thickness = 3
			HudKit.pulse(box.Rim, 0, 0.55)
		end
		local textColor = if clickable then Theme.AccentText else Theme.Text
		local seatInfo = chip.seat and snapshot.seats[chip.seat]
		if seatInfo then
			HudKit.avatar(chip.seat, seatInfo, {
				Position = UDim2.fromOffset(0, 1),
				Size = UDim2.fromOffset(NAME_H - 2, NAME_H - 2),
				ZIndex = box.ZIndex + 1,
				Parent = box,
			})
		end
		local nameX = if seatInfo then NAME_H + 2 else 0
		Kit.label(CardTable.nameOf(snapshot, chip.seat), {
			Font = Theme.FontBold,
			TextSize = 14,
			TextColor3 = textColor,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Position = UDim2.fromOffset(nameX, 0),
			Size = UDim2.new(1, -nameX, 0, NAME_H),
			Parent = box,
		})
		if chip.bigLine then
			Kit.label(chip.bigLine.text, {
				Font = Theme.FontBold,
				TextSize = BIG_LINE - 2,
				TextColor3 = chip.bigLine.color or textColor,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.new(0, 0, 0, NAME_H),
				Size = UDim2.new(1, 0, 0, BIG_LINE),
				Parent = box,
			})
		end
		for j, line in chip.lines or {} do
			Kit.label(line, {
				TextSize = 12,
				TextColor3 = if clickable then Theme.AccentText else Theme.SubText,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.new(0, 0, 0, NAME_H + (if chip.bigLine then BIG_LINE else 0) + (j - 1) * 15),
				Size = UDim2.new(1, 0, 0, 15),
				Parent = box,
			})
		end
		if clickable then
			box.Activated:Connect(chip.onClick)
			Kit.pressable(box)
		end
	end
end

-- list: { { text, onClick, enabled = bool?, color = Color3? } }
function CardTable.buttons(frame: Frame, list: { any })
	Kit.clear(frame)
	for i, b in list do
		local enabled = b.enabled ~= false
		local background = if not enabled then Theme.Panel else (b.color or Theme.Accent)
		-- Light text on dark buttons, dark text on light ones.
		local light = 0.299 * background.R + 0.587 * background.G + 0.114 * background.B > 0.55
		local textColor = if not enabled then Theme.SubText elseif light then Theme.AccentText else Theme.Text
		local button = Kit.button(b.text, function()
			if enabled then
				b.onClick()
			end
		end, {
			Size = UDim2.new(0, math.max(110, #b.text * 9 + 24), 1, 0),
			BackgroundColor3 = background,
			TextColor3 = textColor,
			AutoButtonColor = enabled,
			LayoutOrder = i,
			Parent = frame,
		})
		HudKit.pill(button)
		if enabled then
			-- A soft top light, like the lobby's buttons.
			HudKit.gradient(Color3.new(1, 1, 1), Color3.fromRGB(222, 222, 222)).Parent = button
		end
	end
	local ui = layoutOf[frame]
	if ui then
		CardTable.placeButtons(ui, #list)
	end
end

-- A big red action button (SNAP!, SLAP!) at the right end of the hand row, so it sits in
-- the bottom strip Table view keeps on screen. Text is scaled but padded off the edges.
function CardTable.bigButton(ui: Layout, text: string, onClick: () -> ()): TextButton
	local button = Kit.button(text, onClick, {
		-- Centered on the hand row (which starts 66 px under 62% and fills the rest). Parented
		-- to the root, because the hand row is cleared on every redraw.
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0.97, 0, 0.81, 33),
		Size = UDim2.new(0.24, 0, 0.33, -57),
		TextScaled = true,
		BackgroundColor3 = Theme.Bad,
		TextColor3 = Theme.Text,
		ZIndex = 7,
		Parent = ui.root,
	})
	Kit.new("UIPadding", {
		PaddingLeft = UDim.new(0.14, 0),
		PaddingRight = UDim.new(0.14, 0),
		PaddingTop = UDim.new(0.2, 0),
		PaddingBottom = UDim.new(0.2, 0),
		Parent = button,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 34, Parent = button })
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(220, 120), Parent = button })
	HudKit.gradient(Color3.new(1, 1, 1), Color3.fromRGB(215, 215, 215)).Parent = button
	Kit.new("UIStroke", { Color = Color3.fromRGB(255, 230, 230), Thickness = 3, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = button })
	table.insert(ui.bigButtons, button)
	return button
end

-- A row of cards on the felt (no clicks). cards: { id or false (face down) }
function CardTable.cardRow(parent: Instance, cards: { any }, props: { [string]: any }): Frame
	local row = Kit.new("Frame", { BackgroundTransparency = 1 })
	for key, value in props do
		(row :: any)[key] = value
	end
	row.Parent = parent
	local list = {}
	for _, id in cards do
		table.insert(list, { id = if id then id else nil })
	end
	PlayingCard.renderHand(row, list, nil)
	return row
end

-- A text line on the felt.
function CardTable.feltText(parent: Instance, text: string, y: number, size: number?): TextLabel
	return Kit.label(text, {
		TextSize = size or 16,
		Font = Theme.FontBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 8, y, 0),
		Size = UDim2.new(1, -16, 0, (size or 16) + 6),
		ZIndex = 6,
		Parent = parent,
	})
end

-- Toggles `id` in a selection list (keeps at most `max`).
function CardTable.toggle(selection: { number }, id: number, max: number)
	local i = table.find(selection, id)
	if i then
		table.remove(selection, i)
	elseif #selection < max then
		table.insert(selection, id)
	end
end

-- The cards of a trick, each in front of whoever played it: you at the bottom, the next
-- seat (your left) to the left, and so on round the table (with 4 seats, your partner is
-- across at the top). seatCount defaults to 4.
function CardTable.trick(parent: Instance, snapshot: any, plays: { any }, winner: number?, seatCount: number?)
	local me = snapshot.yourSeat or 1
	local n = seatCount or 4
	for _, play in plays do
		local angle = ((play.seat - me) % n) / n * math.pi * 2
		local slot = PlayingCard.slot({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 - 0.2 * math.sin(angle), 0.46 + 0.24 * math.cos(angle)),
			Size = UDim2.fromScale(1, if n > 5 then 0.36 else 0.42),
			Parent = parent,
		})
		local face = PlayingCard.show(slot, play.card)
		if play.seat == winner then
			Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 4, Parent = face })
		end
	end
end

return CardTable
