-- Word Tiles table: the board on the left, your rack and buttons along the bottom, and a
-- side panel with the bag, a live score preview and recent plays.
--
-- Tap a rack tile, then tap a square to put it there (blanks ask which letter). Tap a tile
-- you just placed to take it back. You can lay tiles out while others are playing; Play
-- only works on your turn, and laid-out tiles go back to the rack whenever the board changes.
-- The preview checks shape and score here and asks the server whether the words are real
-- (the WordCheck remote, like the red/green word in the apps), so "XQZ isn't a word" shows
-- before you press Play. Premium squares use our own layout and colors.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Rules = require(ReplicatedStorage.Shared.Games.WordTiles)
local Net = require(ReplicatedStorage.Shared.Net)
local Kit = require(script.Parent.Parent.UI.Kit)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local TablePrompt = require(script.Parent.Parent.UI.TablePrompt)
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
	local render: () -> ()

	-- Live word check: answers cached per word; one request per change, after a pause.
	local known: { [string]: boolean } = {}
	local askId = 0
	local asking: { [number]: { string } } = {}
	local checkRemote = Net.event(Net.Names.WordCheck)
	local checkConnection = checkRemote.OnClientEvent:Connect(function(reply: any)
		local words = type(reply) == "table" and asking[reply.id]
		if not words or type(reply.valid) ~= "table" then
			return
		end
		asking[reply.id] = nil
		for i, word in words do
			if type(reply.valid[i]) == "boolean" then
				known[word] = reply.valid[i]
			end
		end
		if snapshot then
			render()
		end
	end)
	local wanted = "" -- the words the latest preview needs checked
	local function checkWords(words: { string })
		local unknown = {}
		for _, word in words do
			if known[word] == nil and not table.find(unknown, word) then
				table.insert(unknown, word)
			end
		end
		local key = table.concat(unknown, ",")
		if #unknown == 0 or key == wanted then
			return
		end
		wanted = key
		task.delay(0.3, function()
			if wanted ~= key then
				return -- changed again while we waited
			end
			wanted = ""
			askId += 1
			asking[askId] = unknown
			checkRemote:FireServer({ id = askId, words = unknown })
		end)
	end
	-- For a shape that works: "ok", "bad" (with the first bad word) or "checking".
	local function wordStatus(result: any): (string, string?)
		local words = {}
		for _, w in result.words do
			table.insert(words, w.word)
		end
		local pending = false
		for _, word in words do
			if known[word] == false then
				return "bad", word
			elseif known[word] == nil then
				pending = true
			end
		end
		if pending then
			checkWords(words)
			return "checking"
		end
		return "ok"
	end

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
	-- Table view without the board or side panel: your rack and its buttons stay along
	-- the bottom, the scores and what your word would score are chips over it, and you
	-- lay tiles on the board on the table (UI/TablePrompt).
	local tableMode = false
	local prompt = TablePrompt.new(container)
	prompt.setVisible(false)
	local calledPlay: string? = nil -- the last play already seen (nil until the first update)
	local boardArea = Kit.new("Frame", { BackgroundTransparency = 1, ClipsDescendants = true, Size = UDim2.new(0.66, -8, 1, -96), Parent = root })

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

	local placeTile: (id: number, row: number, col: number) -> ()
	-- Table view hides the side panel; this opens it (scores, unseen tiles, hindsight and
	-- every play so far) in a window over the table.
	local logButton = Kit.button("Log", function()
		if prompt.sheetOpen() then
			prompt.sheet(nil)
		else
			prompt.sheet(side, "Plays and tiles")
		end
	end, { LayoutOrder = 6, BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, Visible = false, Parent = buttons })

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
		if prompt.sheetOpen() then
			prompt.sheet(nil) -- opened from the Table-view sheet: show the list on its own
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
	Kit.onPress(bagLabel, showUnseen)

	local function pendingAt(row: number, col: number): number?
		for id, p in placed do
			if p.row == row and p.col == col then
				return id
			end
		end
		return nil
	end

	-- "sq:<row>:<col>" (a square on the table in Table view) -> row, col.
	local function cellOfId(id: any): (number?, number?)
		if type(id) ~= "string" then
			return nil, nil
		end
		local r, c = string.match(id, "^sq:(%d+):(%d+)$")
		return tonumber(r), tonumber(c)
	end

	local panUntil = 0 -- taps right after panning the zoomed board are ignored
	local pan: { input: InputObject?, start: Vector2, focus: Vector2, moved: boolean }? = nil
	local function onCell(row: number, col: number)
		if os.clock() < panUntil or (pan and pan.moved) then
			return
		end
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

	-- Zoom for small screens (the apps' pinch zoom): pinch or the Zoom button doubles the
	-- board around where you last tapped, and dragging the zoomed board pans it.
	local zoom = 1
	local focus = Vector2.new(0.5, 0.5) -- the board point (0-1) at the centre of the view
	local zoomConnections: { RBXScriptConnection } = {}
	local zoomButton: TextButton
	local function applyZoom()
		if not grid then
			return
		end
		local frame = grid.frame
		if zoom == 1 then
			frame.Size = UDim2.fromScale(1, 1)
			frame.Position = UDim2.fromScale(0.5, 0.5)
		else
			local area = boardArea.AbsoluteSize
			local side = math.min(area.X, area.Y) * zoom
			-- Keep the board covering the view (no empty margin past its edges).
			local half = Vector2.new(math.min(0.5, area.X / side / 2), math.min(0.5, area.Y / side / 2))
			focus = Vector2.new(math.clamp(focus.X, half.X, 1 - half.X), math.clamp(focus.Y, half.Y, 1 - half.Y))
			frame.Size = UDim2.fromOffset(side, side)
			frame.Position = UDim2.fromOffset(area.X / 2 + (0.5 - focus.X) * side, area.Y / 2 + (0.5 - focus.Y) * side)
		end
		zoomButton.Text = if zoom == 1 then "Zoom +" else "Zoom -"
	end
	local function setZoom(value: number, at: Vector2?)
		if grid and at then
			local p, sz = grid.frame.AbsolutePosition, grid.frame.AbsoluteSize
			if sz.X > 0 then
				focus = Vector2.new((at.X - p.X) / sz.X, (at.Y - p.Y) / sz.Y)
			end
		end
		zoom = value
		applyZoom()
	end
	zoomButton = Kit.button("Zoom +", function()
		local at = nil
		if grid then
			-- Zoom in on your laid-out tiles, if any.
			for _, p in placed do
				local cell = grid.cell(p.row, p.col)
				at = cell.AbsolutePosition + cell.AbsoluteSize / 2
				break
			end
		end
		setZoom(if zoom == 1 then 2 else 1, at)
	end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(76, 28),
		TextSize = 14,
		BackgroundColor3 = Theme.PanelLight,
		TextColor3 = Theme.Text,
		ZIndex = 20,
		Visible = false,
		Parent = boardArea,
	})
	-- The button shows when squares get small (phones, the classic board).
	local function fitZoomButton()
		local def = boardKey and Rules.boards[boardKey]
		local area = boardArea.AbsoluteSize
		local square = if def then math.min(area.X, area.Y) / def.size else 99
		zoomButton.Visible = square < 36 or zoom > 1
		if zoom > 1 then
			applyZoom()
		end
	end
	table.insert(zoomConnections, boardArea:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitZoomButton))
	local function inBoard(pos: Vector2): boolean
		local p, sz = boardArea.AbsolutePosition, boardArea.AbsoluteSize
		return boardArea.Visible and pos.X >= p.X and pos.X <= p.X + sz.X and pos.Y >= p.Y and pos.Y <= p.Y + sz.Y
	end
	table.insert(zoomConnections, UserInputService.TouchPinch:Connect(function(positions, scale, _velocity, state)
		if state ~= Enum.UserInputState.Change or not grid or #positions < 2 then
			return
		end
		local centre = (positions[1] + positions[2]) / 2
		if not inBoard(centre) then
			return
		end
		if scale > 1.25 and zoom == 1 then
			setZoom(2, centre)
		elseif scale < 0.8 and zoom > 1 then
			setZoom(1)
		end
	end))
	table.insert(zoomConnections, UserInputService.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if zoom == 1 or pan or not (kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1) then
			return
		end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if inBoard(pos) and not drag then
			pan = { input = if kind == Enum.UserInputType.Touch then input else nil, start = pos, focus = focus, moved = false }
		end
	end))
	table.insert(zoomConnections, UserInputService.InputChanged:Connect(function(input)
		if not pan or not grid or drag then
			return
		end
		local touch = input.UserInputType == Enum.UserInputType.Touch
		if (pan.input and input ~= pan.input) or (not pan.input and input.UserInputType ~= Enum.UserInputType.MouseMovement) or (pan.input and not touch) then
			return
		end
		local delta = Vector2.new(input.Position.X, input.Position.Y) - pan.start
		if delta.Magnitude > 10 then
			pan.moved = true
		end
		if pan.moved then
			local side = grid.frame.AbsoluteSize.X
			focus = pan.focus - delta / math.max(1, side)
			applyZoom()
		end
	end))
	table.insert(zoomConnections, UserInputService.InputEnded:Connect(function(input)
		if not pan then
			return
		end
		if (pan.input and input == pan.input) or (not pan.input and input.UserInputType == Enum.UserInputType.MouseButton1) then
			if pan.moved then
				panUntil = os.clock() + 0.15
			end
			pan = nil
		end
	end))

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
		elseif play.kind == "end" then
			-- Final sums: tiles left on racks come off, and whoever went out gets them.
			local parts = {}
			for seat, delta in play.adjust or {} do
				if delta ~= 0 then
					table.insert(parts, `{nameOf(seat)} {if delta > 0 then "+" else "−"}{math.abs(delta)}`)
				end
			end
			local head = if play.reason == "out" then `{nameOf(play.seat)} went out` else "No one could score"
			return if #parts > 0 then `🏁 {head}: {table.concat(parts, ", ")} (tiles left)` else `🏁 {head}`
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
			local status = if result then wordStatus(result) else "bad"
			local bubble = Kit.label(if result and status ~= "bad" then `+{result.score}` else "X", {
				Font = Theme.FontBold,
				TextScaled = true,
				TextColor3 = Color3.new(1, 1, 1),
				BackgroundColor3 = if status == "ok" then Color3.fromRGB(60, 170, 90) elseif status == "checking" then Color3.fromRGB(120, 120, 140) else Theme.Bad,
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
			Kit.onPress(slot, function()
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
			local status, badWord = "ok", nil
			if result then
				status, badWord = wordStatus(result)
			end
			if result and status == "bad" then
				previewLabel.Text = `{string.upper(badWord or "")} isn't in the word list`
				previewLabel.TextColor3 = Theme.Bad
			elseif result then
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
		-- Hindsight (Words With Friends, Scrabble GO): the best play your last rack had.
		local hint = view.hindsight
		if over and view.biggestMiss then
			local m = view.biggestMiss
			table.insert(lines, `💡 Your biggest missed play: {m.word} for {m.score} (you scored {m.played})`)
		elseif hint and hint.best then
			table.insert(lines, `💡 Your last play was the best one on your rack!`)
		elseif hint and hint.word then
			table.insert(lines, `💡 Best on your last rack: {hint.word} for {hint.score} (you scored {hint.played})`)
		end
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
		logButton.Visible = tableMode
		passButton.Text = if swapMode then "Cancel" elseif passConfirm then "Sure? Pass" else "Pass"
		rackFrame.Visible = snapshot.yourSeat ~= nil

		if tableMode then
			local chips = {}
			for seat, score in view.scores do
				local on = not over and table.find(snapshot.activeSeats, seat) ~= nil
				table.insert(chips, TablePrompt.chip(`{nameOf(seat)} {score}`, if on then Theme.Accent else HudKit.seatColor(seat)))
			end
			table.insert(chips, TablePrompt.chip(`{view.bagCount} in the bag`))
			local text = string.gsub(previewLabel.Text, "\n", "  ")
			if text ~= "" then
				table.insert(chips, TablePrompt.chip(text, if previewLabel.TextColor3 == Theme.Bad then Theme.Bad elseif previewLabel.TextColor3 == Theme.Good then Theme.Good else nil))
			end
			prompt.chips(if over then nil else "info", chips)
		end
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			local view = snapshot.view
			if boardKey ~= view.board then
				boardKey = view.board
				buildBoard(view.board)
				zoom = 1
				fitZoomButton()
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
		-- Table view (Table3D/SceneTap): pick a tile on your rack, then tap a square on the
		-- table. Tiles you've laid out glow on their squares with their letter.
		canTap = function(id: any): boolean
			local r, c = cellOfId(id)
			if not (r and c) or not snapshot or snapshot.yourSeat == nil or swapMode or snapshot.result then
				return false
			end
			return pendingAt(r, c) ~= nil or not (board[r] and board[r][c])
		end,
		tapTable = function(id: any)
			local r, c = cellOfId(id)
			if r and c then
				onCell(r, c)
			end
		end,
		tableMarks = function(): { [any]: any }?
			local marks = {}
			for _, p in placed do
				marks[`sq:{p.row}:{p.col}`] = { kind = "picked", text = string.upper(p.letter) }
			end
			return marks
		end,
		setTableMode = function(value: boolean)
			if value == tableMode then
				return
			end
			tableMode = value
			prompt.setVisible(value) -- first: closing its sheet puts the side panel back
			boardArea.Visible = not value
			side.Visible = not value
			if snapshot then
				render()
			end
		end,
		destroy = function()
			checkConnection:Disconnect()
			for _, connection in zoomConnections do
				connection:Disconnect()
			end
			root:Destroy()
		end,
	}
end

return WordTiles
