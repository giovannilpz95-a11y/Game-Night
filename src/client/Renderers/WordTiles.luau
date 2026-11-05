-- Word Tiles table: the board on the left, your rack and buttons along the bottom, and a
-- side panel with the bag, a live score preview and recent plays.
--
-- Tap a rack tile, then tap a square to put it there (blanks ask which letter). Tap a tile
-- you just placed to take it back. You can lay tiles out while others are playing; Play
-- only works on your turn, and laid-out tiles go back to the rack whenever the board changes. The preview checks shape and score here, and the server checks
-- the words. Premium squares use our own layout and colors.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Rules = require(ReplicatedStorage.Shared.Games.WordTiles)
local Kit = require(script.Parent.Parent.UI.Kit)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local BoardGrid = require(script.Parent.Parent.UI.BoardGrid)
local Juice = require(script.Parent.Parent.UI.Juice)
local Audio = require(script.Parent.Parent.Audio)
local Theme = Kit.Theme

local WordTiles = {}

local SQUARE = Color3.fromRGB(58, 74, 92)
local PREMIUM = {
	W = { color = Color3.fromRGB(128, 76, 196), text = "3×\nWORD" },
	w = { color = Color3.fromRGB(232, 128, 92), text = "2×\nWORD" },
	L = { color = Color3.fromRGB(38, 150, 128), text = "3×\nLTR" },
	l = { color = Color3.fromRGB(214, 180, 82), text = "2×\nLTR" },
	["*"] = { color = Color3.fromRGB(232, 128, 92), text = "★" },
}
local TILE = Color3.fromRGB(250, 236, 204)
local TILE_TEXT = Color3.fromRGB(58, 40, 24)
local BLANK_TEXT = Color3.fromRGB(70, 110, 190)
local PENDING_STROKE = Theme.Accent
local LAST_STROKE = Color3.fromRGB(88, 204, 120)

-- One letter tile. letter "?" = an unassigned blank.
local function tileVisual(letter: string, isBlank: boolean, stroke: Color3?): Frame
	local tile = Kit.new("Frame", {
		BackgroundColor3 = TILE,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.92, 0.92),
	}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.18, 0) }) })
	if stroke then
		Kit.new("UIStroke", { Color = stroke, Thickness = 3, Parent = tile })
	end
	Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.8, 0.8),
		Position = UDim2.fromScale(0.06, 0.04),
		Text = if letter == "?" then "" else string.upper(letter),
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = if isBlank then BLANK_TEXT else TILE_TEXT,
		Parent = tile,
	})
	local value = if isBlank then 0 else Rules.values[letter] or 0
	if not isBlank then
		Kit.new("TextLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromScale(0.96, 0.98),
			Size = UDim2.fromScale(0.4, 0.36),
			Text = tostring(value),
			TextScaled = true,
			Font = Theme.FontBold,
			TextColor3 = TILE_TEXT,
			Parent = tile,
		})
	end
	return tile
end

function WordTiles.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local boardKey: string? = nil
	local grid: BoardGrid.Grid? = nil
	local premium: { { string } } = {}
	local board: Rules.Board = {}

	-- Your rack, with ids that stay put while you shuffle and place tiles.
	local rackKey = ""
	local rowsKey = ""
	local rack: { { id: number, letter: string } } = {}
	local order: { number } = {}
	local placed: { [number]: { row: number, col: number, letter: string } } = {} -- by tile id
	local selected: number? = nil
	local swapMode = false
	local swapPick: { [number]: boolean } = {}
	local passConfirm = false

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
	local calledPlay: string? = nil -- the last play already seen (nil until the first update)
	local boardArea = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.66, -8, 1, -96), Parent = root })

	local side = Kit.panel({ Position = UDim2.new(0.66, 8, 0, 0), Size = UDim2.new(0.34, -8, 1, -96), Parent = root })
	local sideList = Kit.list(8)
	sideList.Parent = side
	-- Score bar: every player's score, whose turn it is lit (like the word apps' top bar).
	local scoreBar = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 0, Parent = side })
	local scoreList = Kit.list(4, true)
	scoreList.Parent = scoreBar
	-- The bag: tap it to see which tiles you haven't seen yet.
	local bagLabel = Kit.button("", function() end, {
		Font = Theme.FontTitle,
		TextSize = 17,
		BackgroundColor3 = Theme.PanelLight,
		TextColor3 = Theme.Text,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 1,
		Parent = side,
	})
	local previewLabel = Kit.label("", { TextSize = 16, Size = UDim2.new(1, 0, 0, 64), TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 2, Parent = side })
	HudKit.heading("Recent plays", { size = 15, LayoutOrder = 3, Parent = side })
	local logLabel = Kit.label("", {
		TextSize = 14,
		Size = UDim2.new(1, 0, 1, -200),
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 4,
		Parent = side,
	})

	local bottom = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 1, -88), Size = UDim2.new(1, 0, 0, 88), Parent = root })
	local rackFrame = Kit.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(110, 76, 52),
		BorderSizePixel = 0,
		Size = UDim2.new(0.5, 0, 1, 0),
		Parent = bottom,
	}, {
		Kit.corner(12),
		Kit.padding(8),
		-- A wooden rack lit from above, with a dark rim (Kit's names, so Kit.clear keeps them).
		Kit.shade(0.35),
		Kit.stroke(Color3.fromRGB(50, 32, 20), 0.2, 2),
	})
	local rackList = Kit.list(6, true)
	rackList.VerticalAlignment = Enum.VerticalAlignment.Center
	rackList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rackList.Parent = rackFrame

	local buttons = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0.5, 10, 0, 0), Size = UDim2.new(0.5, -10, 1, 0), Parent = bottom })
	local grid2 = Kit.new("UIGridLayout", {
		CellSize = UDim2.new(1 / 3, -6, 0.5, -4),
		CellPadding = UDim2.new(0, 6, 0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	grid2.Parent = buttons

	local render: () -> ()
	local placeTile: (id: number, row: number, col: number) -> ()

	local function myTurn(): boolean
		return snapshot ~= nil and table.find(snapshot.activeSeats, snapshot.yourSeat) ~= nil
	end

	local function pendingTiles(): { Rules.PlacedTile }
		local tiles = {}
		for id, p in placed do
			local tile = rack[id]
			table.insert(tiles, { row = p.row, col = p.col, letter = p.letter, blank = tile.letter == "?" })
		end
		return tiles
	end

	local function recallAll()
		table.clear(placed)
		selected = nil
	end

	local playButton = Kit.button("Play", function()
		local tiles = pendingTiles()
		if myTurn() and #tiles > 0 then
			sendMove({ kind = "place", tiles = tiles })
		end
	end, { LayoutOrder = 1, Parent = buttons })
	local recallButton = Kit.button("Recall", function()
		recallAll()
		render()
	end, { LayoutOrder = 2, BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, Parent = buttons })
	local shuffleButton = Kit.button("Shuffle", function()
		for i = #order, 2, -1 do
			local j = math.random(1, i)
			order[i], order[j] = order[j], order[i]
		end
		render()
	end, { LayoutOrder = 3, BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, Parent = buttons })
	local swapButton: TextButton
	swapButton = Kit.button("Swap", function()
		if not swapMode then
			recallAll()
			swapMode = true
			table.clear(swapPick)
		else
			local letters = {}
			for id in swapPick do
				table.insert(letters, rack[id].letter)
			end
			if #letters > 0 and myTurn() then
				sendMove({ kind = "exchange", letters = letters })
			end
			swapMode = false
			table.clear(swapPick)
		end
		render()
	end, { LayoutOrder = 4, BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, Parent = buttons })
	local passButton: TextButton
	passButton = Kit.button("Pass", function()
		if swapMode then
			swapMode = false -- doubles as "Cancel" while swapping
			table.clear(swapPick)
			render()
			return
		end
		if passConfirm then
			passConfirm = false
			sendMove({ kind = "pass" })
		else
			-- Ask twice so a stray tap doesn't waste a turn.
			passConfirm = true
			task.delay(3, function()
				passConfirm = false
				render()
			end)
		end
		render()
	end, { LayoutOrder = 5, BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, Parent = buttons })

	-- Letter picker for blank tiles.
	local picker = Kit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.33, 0.45),
		Size = UDim2.new(0, 330, 0, 250),
		BackgroundColor3 = Theme.PanelLight,
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})
	Kit.label("Which letter is the blank?", { Font = Theme.FontBold, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 21, Parent = picker })
	local letterGrid = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 28), Size = UDim2.new(1, 0, 1, -56), ZIndex = 21, Parent = picker })
	Kit.new("UIGridLayout", { CellSize = UDim2.new(0, 38, 0, 34), CellPadding = UDim2.new(0, 4, 0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = letterGrid })
	local pickFor: { id: number, row: number, col: number }? = nil
	for i = 1, 26 do
		local letter = string.char(96 + i)
		Kit.button(string.upper(letter), function()
			if pickFor then
				placed[pickFor.id] = { row = pickFor.row, col = pickFor.col, letter = letter }
				selected = nil
			end
			pickFor = nil
			picker.Visible = false
			render()
		end, { LayoutOrder = i, TextSize = 16, ZIndex = 22, Parent = letterGrid })
	end
	Kit.button("Cancel", function()
		pickFor = nil
		picker.Visible = false
	end, { BackgroundTransparency = 1, TextColor3 = Theme.SubText, Position = UDim2.new(0, 0, 1, -24), Size = UDim2.new(1, 0, 0, 24), ZIndex = 21, Parent = picker })

	-- Unseen tiles pop-up (from the bag button).
	local unseenBox = Kit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.new(0, 360, 0, 250),
		BackgroundColor3 = Theme.PanelLight,
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})
	local unseenText = Kit.label("", { RichText = true, TextSize = 16, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, 0, 1, -30), ZIndex = 21, Parent = unseenBox })
	Kit.button("Close", function()
		unseenBox.Visible = false
	end, { BackgroundTransparency = 1, TextColor3 = Theme.SubText, Position = UDim2.new(0, 0, 1, -24), Size = UDim2.new(1, 0, 0, 24), ZIndex = 21, Parent = unseenBox })
	local function showUnseen()
		if not snapshot then
			return
		end
		local view = snapshot.view
		local left = Rules.unseen(view.board, view.rows, view.rack)
		local parts, total = {}, 0
		for i = 1, 26 do
			local letter = string.char(96 + i)
			local n = left[letter] or 0
			total += n
			if n > 0 then
				table.insert(parts, `<b>{string.upper(letter)}</b>×{n}`)
			end
		end
		if (left["?"] or 0) > 0 then
			total += left["?"]
			table.insert(parts, `<b>blank</b>×{left["?"]}`)
		end
		unseenText.Text = `<font size="18"><b>Unseen tiles: {total}</b></font>\nIn the bag ({view.bagCount}) or on other racks.\n\n{table.concat(parts, "   ")}`
		unseenBox.Visible = not unseenBox.Visible
		Juice.popIn(unseenBox)
	end
	bagLabel.Activated:Connect(showUnseen)

	local function pendingAt(row: number, col: number): number?
		for id, p in placed do
			if p.row == row and p.col == col then
				return id
			end
		end
		return nil
	end

	local function onCell(row: number, col: number)
		if not snapshot or snapshot.yourSeat == nil or swapMode or snapshot.result or snapshot.aborted then
			return
		end
		local here = pendingAt(row, col)
		if here then
			placed[here] = nil
			render()
			return
		end
		if board[row] and board[row][col] then
			return
		end
		local id = selected
		if not id then
			-- Nothing picked: use the first tile still on the rack.
			for _, candidate in order do
				if not placed[candidate] then
					id = candidate
					break
				end
			end
		end
		if not id then
			return
		end
		placeTile(id, row, col)
	end

	-- Puts rack tile `id` on a square (blanks ask which letter first).
	function placeTile(id: number, row: number, col: number)
		if board[row] and board[row][col] or pendingAt(row, col) then
			return
		end
		if rack[id].letter == "?" then
			pickFor = { id = id, row = row, col = col }
			picker.Visible = true
			return
		end
		placed[id] = { row = row, col = col, letter = rack[id].letter }
		selected = nil
		Audio.play("piece", { volume = 0.5 })
		render()
	end

	-- Drag and drop, like every word app: drag a rack tile onto the board, or along the
	-- rack to reorder it. A short press is still a tap.
	local drag: { id: number, ghost: Frame, start: Vector2, moved: boolean }? = nil
	local function cellAt(point: Vector2): (number?, number?)
		if not grid then
			return nil, nil
		end
		local size = #premium
		for r = 1, size do
			for c = 1, size do
				local cell = grid.cell(r, c)
				local p, sz = cell.AbsolutePosition, cell.AbsoluteSize
				if point.X >= p.X and point.X <= p.X + sz.X and point.Y >= p.Y and point.Y <= p.Y + sz.Y then
					return r, c
				end
			end
		end
		return nil, nil
	end
	local function startDrag(id: number, input: InputObject, slot: GuiObject)
		if drag or placed[id] or swapMode then
			return
		end
		local ghost = Kit.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(slot.AbsoluteSize.X * 1.1, slot.AbsoluteSize.Y * 1.1),
			Visible = false,
			ZIndex = 30,
			Parent = root,
		})
		local visual = tileVisual(rack[id].letter, rack[id].letter == "?", PENDING_STROKE)
		visual.ZIndex = 31
		for _, d in visual:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 32
			end
		end
		visual.Parent = ghost
		drag = { id = id, ghost = ghost, start = Vector2.new(input.Position.X, input.Position.Y), moved = false }
	end
	UserInputService.InputChanged:Connect(function(input)
		if not drag then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local point = Vector2.new(input.Position.X, input.Position.Y)
		if not drag.moved and (point - drag.start).Magnitude > 10 then
			drag.moved = true
			drag.ghost.Visible = true
			Audio.play("lift", { volume = 0.5 })
		end
		if drag.moved then
			-- input.Position is in screen space under the top bar inset; the ghost lives in root.
			local inset = root.AbsolutePosition
			local guiPoint = point + Vector2.new(0, game:GetService("GuiService"):GetGuiInset().Y)
			drag.ghost.Position = UDim2.fromOffset(guiPoint.X - inset.X, guiPoint.Y - inset.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not drag then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local d = drag
		drag = nil
		d.ghost:Destroy()
		if not d.moved then
			return -- a tap: the slot's Activated handles it
		end
		local point = Vector2.new(input.Position.X, input.Position.Y) + Vector2.new(0, game:GetService("GuiService"):GetGuiInset().Y)
		local r, c = cellAt(point)
		if r and c then
			placeTile(d.id, r :: number, c :: number)
			return
		end
		-- Dropped on the rack: move the tile to that spot.
		local rp, rs = rackFrame.AbsolutePosition, rackFrame.AbsoluteSize
		if point.Y >= rp.Y and point.Y <= rp.Y + rs.Y and point.X >= rp.X and point.X <= rp.X + rs.X then
			local slotWidth = rs.X / math.max(1, #order)
			local to = math.clamp(math.floor((point.X - rp.X) / slotWidth) + 1, 1, #order)
			local from = table.find(order, d.id)
			if from and from ~= to then
				table.remove(order, from)
				table.insert(order, to, d.id)
				render()
			end
		end
	end)

	local function buildBoard(key: string)
		if grid then
			grid.frame:Destroy()
		end
		local def = Rules.boards[key]
		premium = def.premium
		grid = BoardGrid.create(boardArea, def.size, onCell, { BackgroundColor3 = Color3.fromRGB(34, 44, 58) })
		for r = 1, def.size do
			for c = 1, def.size do
				local cell = (grid :: BoardGrid.Grid).cell(r, c)
				local info = PREMIUM[premium[r][c]]
				cell.BackgroundColor3 = if info then info.color else SQUARE
				Kit.new("UIStroke", { Color = Color3.fromRGB(34, 44, 58), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = cell })
				if info then
					Kit.new("TextLabel", {
						Name = "Premium",
						BackgroundTransparency = 1,
						Size = UDim2.fromScale(1, 1),
						Text = info.text,
						TextScaled = true,
						Font = Theme.FontBold,
						TextColor3 = Color3.new(1, 1, 1),
						TextTransparency = 0.15,
						Parent = cell,
					}, { Kit.padding(2) })
				end
			end
		end
	end

	local function nameOf(seat: number): string
		if seat == snapshot.yourSeat then
			return "You"
		end
		local s = snapshot.seats[seat]
		return if s then s.name else "?"
	end

	local function describe(play: any): string
		if play.kind == "place" then
			local words = {}
			for _, w in play.words or {} do
				table.insert(words, string.upper(w.word))
			end
			local bonus = if play.bingo then " (all 7 tiles!)" else ""
			return `{nameOf(play.seat)}: {table.concat(words, ", ")} +{play.score}{bonus}`
		elseif play.kind == "exchange" then
			return `{nameOf(play.seat)} swapped {play.count} tiles`
		end
		return `{nameOf(play.seat)} passed`
	end

	-- Keeps your rack order (and tiles you've laid out) when the rack hasn't changed.
	local function syncRack(view: any)
		local letters = view.rack or {}
		local key = table.concat(letters, ",")
		if key == rackKey then
			return
		end
		rackKey = key
		rack = {}
		order = {}
		for i, letter in letters do
			rack[i] = { id = i, letter = letter }
			order[i] = i
		end
		recallAll()
		swapMode = false
		table.clear(swapPick)
	end

	function render()
		if not snapshot or not grid then
			return
		end
		local view = snapshot.view
		local turn = myTurn()
		local over = snapshot.result ~= nil or snapshot.aborted == true
		HudKit.turnTint(side, if over then nil else snapshot.activeSeats[1], turn and not over)

		if over then
			recallAll()
			swapMode = false
		end

		-- All seven tiles in one play gets the big call-out the word apps give it.
		local play = view.lastPlay
		local firstCell = play and play.cells and play.cells[1]
		local playKey = if play then `{play.seat}|{play.score}|{if firstCell then firstCell[1] * 100 + firstCell[2] else 0}` else nil
		if play and play.kind == "place" and play.bingo and calledPlay ~= nil and playKey ~= calledPlay then
			HudKit.callout(root, `ALL 7 TILES!  +{play.score}`, Color3.fromRGB(255, 196, 64), 0.35)
		end
		calledPlay = playKey or ""

		-- Board squares.
		local last: { [number]: boolean } = {}
		if view.lastPlay and view.lastPlay.cells then
			for _, rc in view.lastPlay.cells do
				last[rc[1] * 32 + rc[2]] = true
			end
		end
		local size = #premium
		for r = 1, size do
			for c = 1, size do
				local content = grid.content(r, c)
				Kit.clear(content)
				local premiumLabel = grid.cell(r, c):FindFirstChild("Premium") :: TextLabel?
				local ch = board[r][c]
				local pendingId = pendingAt(r, c)
				if ch then
					local letter = string.lower(ch)
					tileVisual(letter, ch ~= letter, if last[r * 32 + c] then LAST_STROKE else nil).Parent = content
				elseif pendingId then
					local p = placed[pendingId]
					tileVisual(p.letter, rack[pendingId].letter == "?", PENDING_STROKE).Parent = content
				end
				if premiumLabel then
					premiumLabel.Visible = ch == nil and pendingId == nil
				end
			end
		end

		-- Score bubble on the board next to the word you're laying out: "+24", or red when
		-- the shape doesn't work yet (the apps show it before you press Play).
		local pendingNow = pendingTiles()
		if #pendingNow > 0 and not over then
			local endTile = pendingNow[1]
			for _, t in pendingNow do
				if t.row > endTile.row or (t.row == endTile.row and t.col > endTile.col) then
					endTile = t
				end
			end
			local result = Rules.evaluate(board, premium, pendingNow, nil)
			local bubble = Kit.label(if result then `+{result.score}` else "✗", {
				Font = Theme.FontBold,
				TextScaled = true,
				TextColor3 = Color3.new(1, 1, 1),
				BackgroundColor3 = if result then Color3.fromRGB(60, 170, 90) else Theme.Bad,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.fromScale(0.9, 0.55),
				ZIndex = 8,
				Parent = grid.content(endTile.row, endTile.col),
			})
			Kit.corner(8).Parent = bubble
			Kit.padding(2).Parent = bubble
		end

		-- Scores across the top of the side panel.
		Kit.clear(scoreBar)
		for seat, score in view.scores do
			local on = not over and table.find(snapshot.activeSeats, seat) ~= nil
			local chip = Kit.label(`{nameOf(seat)} {score}`, {
				Font = Theme.FontBold,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextColor3 = if on then Theme.AccentText else Theme.Text,
				BackgroundColor3 = if on then Theme.Accent else HudKit.shade(HudKit.seatColor(seat), 0.5),
				Size = UDim2.new(1 / #view.scores, -4, 1, 0),
				LayoutOrder = seat,
				Parent = scoreBar,
			})
			Kit.corner(8).Parent = chip
		end

		-- Rack.
		Kit.clear(rackFrame)
		for index, id in order do
			local tile = rack[id]
			local slot = Kit.new("TextButton", {
				Text = "",
				BackgroundTransparency = 1,
				Size = UDim2.new(1 / 7, -6, 1, 0),
				LayoutOrder = index,
				Parent = rackFrame,
			}, { Kit.new("UIAspectRatioConstraint", { AspectRatio = 1 }) })
			if placed[id] then
				-- An empty spot where the tile was; tap it to take the tile back.
				Kit.new("Frame", {
					BackgroundColor3 = Color3.new(0, 0, 0),
					BackgroundTransparency = 0.7,
					BorderSizePixel = 0,
					Size = UDim2.fromScale(0.92, 0.92),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Parent = slot,
				}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.18, 0) }) })
			else
				local stroke = if swapMode and swapPick[id] then Theme.Bad elseif selected == id then PENDING_STROKE else nil
				local visual = tileVisual(tile.letter, tile.letter == "?", stroke)
				visual.Parent = slot
				if selected == id then
					visual.Position = UDim2.fromScale(0.5, 0.4)
				end
			end
			slot.InputBegan:Connect(function(input)
				if over or not snapshot.yourSeat then
					return
				end
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					startDrag(id, input, slot)
				end
			end)
			slot.Activated:Connect(function()
				if over then
					return
				elseif swapMode then
					swapPick[id] = if swapPick[id] then nil else true
				elseif placed[id] then
					placed[id] = nil
				else
					selected = if selected == id then nil else id
				end
				render()
			end)
		end

		-- Preview of what you've laid out.
		local tiles = pendingTiles()
		if over then
			previewLabel.Text = ""
		elseif swapMode then
			local n = 0
			for _ in swapPick do
				n += 1
			end
			previewLabel.Text = `Tap the tiles to swap ({n} picked), then press Swap again. Swapping uses your turn.`
			previewLabel.TextColor3 = Theme.Text
		elseif #tiles > 0 then
			local result, err = Rules.evaluate(board, premium, tiles, nil)
			if result then
				local words = {}
				for _, w in result.words do
					table.insert(words, `{string.upper(w.word)} {w.score}`)
				end
				local bonus = if result.bingo then `  +{Rules.bingoBonus} for all 7!` else ""
				previewLabel.Text = `{table.concat(words, " · ")}\n= {result.score} points{bonus}`
				previewLabel.TextColor3 = Theme.Good
			else
				previewLabel.Text = err or ""
				previewLabel.TextColor3 = Theme.Bad
			end
		elseif turn then
			previewLabel.Text = "Your turn! Tap a tile, then a square."
			previewLabel.TextColor3 = Theme.Accent
		else
			previewLabel.Text = "You can lay out tiles while you wait. They come back if the board changes."
			previewLabel.TextColor3 = Theme.SubText
		end

		bagLabel.Text = `👜 {view.bagCount} in the bag · see unseen`
		local lines = {}
		for i = #(view.log or {}), 1, -1 do
			table.insert(lines, describe(view.log[i]))
		end
		logLabel.Text = table.concat(lines, "\n")

		local canAct = turn and not over and snapshot.yourSeat ~= nil
		playButton.Visible = not swapMode and not over
		playButton.Active = canAct and #tiles > 0
		playButton.AutoButtonColor = playButton.Active
		playButton.BackgroundTransparency = if playButton.Active then 0 else 0.5
		recallButton.Visible = not swapMode and not over
		shuffleButton.Visible = not swapMode and not over
		swapButton.Visible = view.canExchange and canAct
		swapButton.Text = if swapMode then "Swap now" else "Swap"
		passButton.Visible = canAct
		passButton.Text = if swapMode then "Cancel" elseif passConfirm then "Sure? Pass" else "Pass"
		rackFrame.Visible = snapshot.yourSeat ~= nil
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			local view = snapshot.view
			if boardKey ~= view.board then
				boardKey = view.board
				buildBoard(view.board)
			end
			board = Rules.boardFromRows(view.rows)
			-- Someone played: take back any laid-out tiles, so the preview never mixes them
			-- with new letters and no tile sits on a square that just got filled.
			local key = table.concat(view.rows, "/")
			if key ~= rowsKey then
				rowsKey = key
				recallAll()
			end
			syncRack(view)
			if not myTurn() then
				swapMode = false
				passConfirm = false
			end
			render()
		end,
		destroy = function()
			root:Destroy()
		end,
	}
end

return WordTiles
