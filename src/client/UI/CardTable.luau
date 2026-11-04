-- Shared layout for the card-game screens (I Doubt It, President, Slap Stack, Hearts,
-- Spades, Thirty-One, Palace): a row of seat chips on top, the felt in the middle, a
-- prompt and action buttons, and your hand along the bottom.

local Kit = require(script.Parent.Kit)
local PlayingCard = require(script.Parent.PlayingCard)
local Theme = Kit.Theme

local CardTable = {}

local BIG_LINE = 22 -- px for a chip's bigLine

export type Layout = {
	root: Frame,
	seats: Frame,
	felt: Frame,
	content: Frame, -- inside the felt; safe to clear and redraw
	prompt: TextLabel,
	buttons: Frame,
	hand: Frame,
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
		Size = UDim2.new(1, 0, 0, 22),
		Parent = root,
	})
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
	return { root = root, seats = seats, felt = felt, content = content, prompt = prompt, buttons = buttons, hand = hand }
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
	local height = math.min(math.max(24, frame.AbsoluteSize.Y - 4), 10 + 17 + big + lines * 15 + 2)
	for i, chip in chips do
		local clickable = chip.onClick ~= nil
		local color = if clickable then Theme.Accent elseif chip.turn then Theme.PanelLight else Theme.Panel
		local box = Kit.new("TextButton", {
			Text = "",
			AutoButtonColor = clickable,
			BackgroundColor3 = color,
			BackgroundTransparency = if chip.dim then 0.5 else 0,
			BorderSizePixel = 0,
			Size = UDim2.new(0, width, 0, height),
			LayoutOrder = i,
			Parent = frame,
		}, { Kit.corner(10), Kit.padding(5) })
		if chip.turn or chip.highlight then
			Kit.new("UIStroke", { Color = if chip.highlight then Theme.Good else Theme.Accent, Thickness = 3, Parent = box })
		end
		local textColor = if clickable then Theme.AccentText else Theme.Text
		Kit.label(CardTable.nameOf(snapshot, chip.seat), {
			Font = Theme.FontBold,
			TextSize = 14,
			TextColor3 = textColor,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Size = UDim2.new(1, 0, 0, 17),
			Parent = box,
		})
		if chip.bigLine then
			Kit.label(chip.bigLine.text, {
				Font = Theme.FontBold,
				TextSize = BIG_LINE - 2,
				TextColor3 = chip.bigLine.color or textColor,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.new(0, 0, 0, 17),
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
				Position = UDim2.new(0, 0, 0, 17 + (if chip.bigLine then BIG_LINE else 0) + (j - 1) * 15),
				Size = UDim2.new(1, 0, 0, 15),
				Parent = box,
			})
		end
		if clickable then
			box.Activated:Connect(chip.onClick)
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
	end
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

-- The cards of a 4-player trick, each in front of whoever played it: you at the bottom,
-- the next seat (your left) on the left, your partner across at the top.
local TRICK_SPOTS = { Vector2.new(0.5, 0.7), Vector2.new(0.3, 0.45), Vector2.new(0.5, 0.22), Vector2.new(0.7, 0.45) }
function CardTable.trick(parent: Instance, snapshot: any, plays: { any }, winner: number?)
	local me = snapshot.yourSeat or 1
	for _, play in plays do
		local spot = TRICK_SPOTS[(play.seat - me) % 4 + 1]
		local slot = PlayingCard.slot({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spot.X, spot.Y),
			Size = UDim2.fromScale(1, 0.42),
			Parent = parent,
		})
		local face = PlayingCard.show(slot, play.card)
		if play.seat == winner then
			Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 4, Parent = face })
		end
	end
end

return CardTable
