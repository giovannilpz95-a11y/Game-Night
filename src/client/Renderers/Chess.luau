-- Chess board: tap one of your pieces, then a highlighted square, or drag it there. Pawns
-- reaching the last rank open a promotion picker. Shows the last move, check, captured
-- pieces, board coordinates and the moves, like chess.com and Lichess:
--   * dots for quiet moves, rings for captures
--   * premoves: pick a move while the other side thinks; it plays the moment your turn
--     comes if it's still legal (tap anywhere else to cancel)
--   * tap a move in the list (or < >) to look back at that position; Live returns
--   * the opening's name while you play (from shared/ChessReview's book)
--   * Game Review after the game, like chess.com: every move labelled Best ... Blunder,
--     accuracy for both sides, an eval bar, and a green arrow for the better move

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local ChessRules = require(ReplicatedStorage.Shared.Games.Chess)
local ChessReview = require(ReplicatedStorage.Shared.ChessReview)
local Kit = require(script.Parent.Parent.UI.Kit)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local BoardGrid = require(script.Parent.Parent.UI.BoardGrid)
local PieceView = require(script.Parent.Parent.UI.PieceView)
local Audio = require(script.Parent.Parent.Audio)
local Theme = Kit.Theme

local Chess = {}

local NAMES = { "Pawn", "Knight", "Bishop", "Rook", "Queen", "King" }
local LETTERS = { "", "N", "B", "R", "Q", "K" }
local LIGHT = Color3.fromRGB(240, 222, 190)
local DARK = Color3.fromRGB(176, 128, 92)
local SELECTED = Color3.fromRGB(255, 214, 102)
local LAST_MOVE = Color3.fromRGB(214, 196, 110)
local CHECK = Color3.fromRGB(235, 87, 87)
local PREMOVE = Color3.fromRGB(110, 150, 230)
local REVIEW = Color3.fromRGB(120, 170, 255)
local FILE_LETTERS = "abcdefgh"

-- Game row 1 is rank 8 (the top as White sees it).
local function squareOf(row: number, col: number): string
	return ChessRules.squareName((8 - row) * 8 + (col - 1))
end

local function cellOf(square: string): (number, number)
	local sq = ChessRules.parseSquare(square) :: number
	return 8 - sq // 8, sq % 8 + 1
end

-- White models face -Z (away from the 2D camera) and Black face +Z. Turn knights so both
-- show the same three-quarter profile; other pieces look the same from any side.
local KNIGHT_YAW = { White = -120, Black = 60 }

local function pieceVisual(code: number): GuiObject
	local kind = math.abs(code)
	local white = code > 0
	local color = if white then "White" else "Black"
	local name = `{NAMES[kind]}_{color}`
	local yaw = if kind == 2 then KNIGHT_YAW[color] else nil
	return PieceView.create("Chess", name, function()
		local fill = if white then Color3.fromRGB(250, 248, 240) else Color3.fromRGB(40, 36, 44)
		local stroke = if white then Color3.fromRGB(60, 50, 40) else Color3.fromRGB(230, 220, 200)
		local token = BoardGrid.token(fill, stroke, if kind == 1 then "" else LETTERS[kind], stroke)
		if kind == 1 then
			token.Size = UDim2.fromScale(0.5, 0.5)
		end
		return token
	end, { yaw = yaw })
end

function Chess.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local selected: string? = nil
	local shownCodes: { [string]: number } = {}
	local viewing: number? = nil -- a past move being looked at (nil = the live board)
	local premove: { from: string, to: string }? = nil
	local premoveFrom: string? = nil -- picked a piece to premove with
	local connections: { RBXScriptConnection } = {}
	local drag: any = nil
	local review: any = nil -- a ChessReview once the player asks for one
	local reviewing = false -- the review is running
	local reviewFor: string? = nil -- the game (start fen + moves) it reviews

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
	local boardArea = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -230, 1, 0), Parent = root })

	local side = Kit.panel({ Size = UDim2.new(0, 210, 1, 0), Position = UDim2.new(1, -210, 0, 0), Parent = root })
	-- On phones the move list narrows so the board keeps most of the width.
	local function fitSide()
		local width = root.AbsoluteSize.X
		local sideW = if width < 560 then 140 elseif width < 760 then 170 else 210
		side.Size = UDim2.new(0, sideW, 1, 0)
		side.Position = UDim2.new(1, -sideW, 0, 0)
		boardArea.Size = UDim2.new(1, -(sideW + 20), 1, 0)
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitSide)
	fitSide()
	local capturedLabel = Kit.label("", { TextSize = 14, TextColor3 = Theme.SubText, Size = UDim2.new(1, 0, 0, 44), TextYAlignment = Enum.TextYAlignment.Top, Parent = side })
	-- Step through the game: back, forward, and back to the live board.
	local nav = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 1, -34), Size = UDim2.new(1, 0, 0, 30), Parent = side }, { Kit.list(4, true) })
	local navButtons: { [string]: TextButton } = {}
	local stepTo: (number?) -> ()
	for i, spec in { { "back", "<" }, { "forward", ">" }, { "live", "Live" } } do
		navButtons[spec[1]] = Kit.button(spec[2], function()
			local total = snapshot and #snapshot.view.past or 0
			if spec[1] == "back" then
				stepTo(math.max(0, (viewing or total) - 1))
			elseif spec[1] == "forward" then
				stepTo(if viewing then viewing + 1 else nil)
			else
				stepTo(nil)
			end
		end, {
			BackgroundColor3 = Theme.Panel,
			TextColor3 = Theme.Text,
			TextSize = 14,
			Size = if spec[1] == "live" then UDim2.new(0.4, -4, 1, 0) else UDim2.new(0.3, -3, 1, 0),
			LayoutOrder = i,
			Parent = nav,
		})
	end
	-- Game Review: shows once the game is over.
	local reviewButton: TextButton
	local startReview: () -> ()
	reviewButton = Kit.button("Game Review", function()
		startReview()
	end, {
		BackgroundColor3 = Color3.fromRGB(129, 182, 76),
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 14,
		Position = UDim2.new(0, 0, 1, -68),
		Size = UDim2.new(1, 0, 0, 30),
		Visible = false,
		Parent = side,
	})
	local moves = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 50),
		Size = UDim2.new(1, 0, 1, -88),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		Parent = side,
	}, { Kit.list(2) })

	local promotionPicker: Frame? = nil

	local function closePicker()
		if promotionPicker then
			promotionPicker:Destroy()
			promotionPicker = nil
		end
	end

	local render: () -> ()
	local grid: BoardGrid.Grid

	local function myTurn(): boolean
		return snapshot ~= nil and snapshot.view.legalMoves ~= nil and table.find(snapshot.activeSeats, snapshot.yourSeat) ~= nil
	end

	local function movesFrom(square: string): { any }
		local out = {}
		for _, m in (snapshot and snapshot.view.legalMoves) or {} do
			if m.from == square then
				table.insert(out, m)
			end
		end
		return out
	end

	local function openPicker(from: string, to: string)
		closePicker()
		local white = snapshot.yourSeat == 1
		local picker = Kit.panel({
			Size = UDim2.new(0, 260, 0, 90),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundColor3 = Theme.PanelLight,
			ZIndex = 5,
			Parent = boardArea,
		})
		Kit.list(8, true).Parent = picker
		for _, choice in { { "q", 5 }, { "r", 4 }, { "b", 3 }, { "n", 2 } } do
			local button = Kit.new("TextButton", {
				Text = "",
				BackgroundColor3 = LIGHT,
				Size = UDim2.new(0, 52, 0, 64),
				ZIndex = 6,
				Parent = picker,
			}, { Kit.corner(8) })
			local visual = pieceVisual(choice[2] * (if white then 1 else -1))
			visual.ZIndex = 7
			visual.Parent = button
			button.Activated:Connect(function()
				closePicker()
				selected = nil
				sendMove({ from = from, to = to, promotion = choice[1] })
				render()
			end)
		end
		promotionPicker = picker
	end

	local function myColor(code: number): boolean
		return code ~= 0 and (code > 0) == (snapshot.yourSeat == 1)
	end

	local function premoveTargets(from: string): { [string]: boolean }
		local out = {}
		for _, m in ChessRules.premoves(snapshot.view.fen, snapshot.yourSeat) do
			if m.from == from then
				out[m.to] = true
			end
		end
		return out
	end

	-- Premoves: while the other side thinks, pick a piece and a square for it.
	local function canPremove(): boolean
		local over = snapshot.result ~= nil or snapshot.aborted == true
		return not over and snapshot.yourSeat ~= nil and snapshot.view.ask == nil and snapshot.view.turn ~= snapshot.yourSeat
	end

	local function onPremoveClick(square: string)
		local sq = ChessRules.parseSquare(square) :: number
		local code = snapshot.view.board[sq + 1]
		if premoveFrom and premoveTargets(premoveFrom)[square] then
			premove = { from = premoveFrom, to = square }
			premoveFrom = nil
			Audio.play("click", { volume = 0.6 })
		elseif myColor(code) and square ~= premoveFrom then
			premoveFrom = square
			premove = nil
		else
			premoveFrom = nil
			premove = nil
		end
		render()
	end

	local function onClick(row: number, col: number)
		if viewing then
			stepTo(nil) -- back to the live board first
			return
		end
		if snapshot and canPremove() then
			onPremoveClick(squareOf(row, col))
			return
		end
		if not myTurn() then
			return
		end
		local square = squareOf(row, col)
		if selected then
			local choices = {}
			for _, m in movesFrom(selected) do
				if m.to == square then
					table.insert(choices, m)
				end
			end
			if #choices > 1 then
				openPicker(selected, square)
				return
			elseif #choices == 1 then
				local m = choices[1]
				selected = nil
				closePicker()
				sendMove({ from = m.from, to = m.to })
				render()
				return
			end
		end
		closePicker()
		selected = if #movesFrom(square) > 0 and square ~= selected then square else nil
		render()
	end

	-- Drag a piece to its square (tap-tap still works). A press on a piece that can move
	-- (or premove) picks it; letting go over another square plays it there.
	local function cellAt(point: Vector2): (number?, number?)
		for r = 1, 8 do
			for c = 1, 8 do
				local cell = grid.cell(r, c)
				local p, sz = cell.AbsolutePosition, cell.AbsoluteSize
				if point.X >= p.X and point.X <= p.X + sz.X and point.Y >= p.Y and point.Y <= p.Y + sz.Y then
					return r, c
				end
			end
		end
		return nil, nil
	end

	local function startDrag(row: number, col: number, input: InputObject)
		if drag or viewing or not snapshot then
			return
		end
		local square = squareOf(row, col)
		local sq = ChessRules.parseSquare(square) :: number
		local code = snapshot.view.board[sq + 1]
		local live = myTurn() and #movesFrom(square) > 0
		if not live and not (canPremove() and myColor(code)) then
			return
		end
		local cell = grid.cell(row, col)
		local ghost = Kit.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(cell.AbsoluteSize.X * 1.15, cell.AbsoluteSize.Y * 1.15),
			Visible = false,
			ZIndex = 30,
			Parent = root,
		})
		local visual = pieceVisual(code)
		visual.ZIndex = 31
		visual.Parent = ghost
		drag = { row = row, col = col, square = square, ghost = ghost, start = Vector2.new(input.Position.X, input.Position.Y), moved = false }
	end

	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if not drag or (input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch) then
			return
		end
		local point = Vector2.new(input.Position.X, input.Position.Y)
		if not drag.moved and (point - drag.start).Magnitude > 10 then
			drag.moved = true
			drag.ghost.Visible = true
			grid.content(drag.row, drag.col).Visible = false
			Audio.play("lift", { volume = 0.5 })
			-- Show where it can go while it's in the air.
			if myTurn() then
				selected = drag.square
			else
				premoveFrom = drag.square
				premove = nil
			end
			render()
		end
		if drag.moved then
			local guiPoint = point + Vector2.new(0, GuiService:GetGuiInset().Y)
			local inset = root.AbsolutePosition
			drag.ghost.Position = UDim2.fromOffset(guiPoint.X - inset.X, guiPoint.Y - inset.Y)
		end
	end))

	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if not drag or (input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch) then
			return
		end
		local d = drag
		drag = nil
		d.ghost:Destroy()
		grid.content(d.row, d.col).Visible = true
		if not d.moved then
			return -- a tap: the cell's Activated handles it
		end
		local point = Vector2.new(input.Position.X, input.Position.Y) + Vector2.new(0, GuiService:GetGuiInset().Y)
		local r, c = cellAt(point)
		if r and c and (r ~= d.row or c ~= d.col) then
			onClick(r :: number, c :: number)
		else
			render()
		end
	end))

	local clearMarks: () -> ()
	local shownFlipped: boolean? = nil
	grid = BoardGrid.create(boardArea, 8, function(row, col)
		clearMarks()
		onClick(row, col)
	end)
	for r = 1, 8 do
		for c = 1, 8 do
			local cell = grid.cell(r, c)
			cell.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					startDrag(r, c, input)
				end
			end)
			-- Coordinates in the corners of the edge squares, like the big chess sites.
			Kit.new("TextLabel", {
				Name = "Rank",
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.04, 0.02),
				Size = UDim2.fromScale(0.3, 0.26),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "",
				ZIndex = 2,
				Parent = cell,
			})
			Kit.new("TextLabel", {
				Name = "File",
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.66, 0.72),
				Size = UDim2.fromScale(0.3, 0.26),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = "",
				ZIndex = 2,
				Parent = cell,
			})
		end
	end

	-- Right-click marks, like the big chess sites: right-click a square to ring it, or
	-- right-drag from one square to another for an arrow. Any left click clears them.
	-- Only you see them.
	local MARK = Color3.fromRGB(255, 160, 40)
	local inner = grid.cell(1, 1).Parent :: Frame
	local markLayer = Kit.new("Frame", { Name = "Marks", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = inner })
	local marks: { [string]: boolean } = {} -- "a1" (ring) or "a1>c3" (arrow)
	local BEST_ARROW = Color3.fromRGB(129, 182, 76)
	local reviewArrow: string? = nil -- "e2>e4": the better move while looking at a reviewed move
	-- Eval bar beside the board during a review: white fills from White's side.
	local evalBar = Kit.new("Frame", {
		Name = "EvalBar",
		BackgroundColor3 = Color3.fromRGB(40, 36, 44),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0, -6, 0, 0),
		Size = UDim2.new(0.03, 0, 1, 0),
		Visible = false,
		Parent = inner,
	}, { Kit.corner(4) })
	local evalFill = Kit.new("Frame", { BackgroundColor3 = Color3.fromRGB(250, 248, 240), BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.5), Parent = evalBar }, { Kit.corner(4) })
	local function center(row: number, col: number): Vector2
		local p = grid.cell(row, col).Position
		return Vector2.new(p.X.Scale + 1 / 16, p.Y.Scale + 1 / 16)
	end
	local function drawMarks()
		Kit.clear(markLayer)
		local keys = {}
		for key in marks do
			keys[key] = MARK
		end
		if reviewArrow then
			keys[reviewArrow] = BEST_ARROW
		end
		for key, color in keys do
			local from, to = string.match(key, "^(%w+)>(%w+)$")
			if from and to then
				local a = center(cellOf(from))
				local b = center(cellOf(to))
				local d = b - a
				local angle = math.deg(math.atan2(d.Y, d.X))
				local tip = b - d.Unit * 0.03
				Kit.new("Frame", {
					BackgroundColor3 = color,
					BackgroundTransparency = 0.2,
					BorderSizePixel = 0,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale((a.X + tip.X) / 2, (a.Y + tip.Y) / 2),
					Size = UDim2.fromScale((tip - a).Magnitude, 0.022),
					Rotation = angle,
					ZIndex = 8,
					Parent = markLayer,
				}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
				Kit.label("▶", {
					TextScaled = true,
					TextColor3 = color,
					TextTransparency = 0.1,
					TextXAlignment = Enum.TextXAlignment.Center,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(tip.X, tip.Y),
					Size = UDim2.fromScale(0.07, 0.07),
					Rotation = angle,
					ZIndex = 9,
					Parent = markLayer,
				})
			else
				local c = center(cellOf(key))
				Kit.new("Frame", {
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(c.X, c.Y),
					Size = UDim2.fromScale(0.115, 0.115),
					ZIndex = 8,
					Parent = markLayer,
				}, {
					Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
					Kit.new("UIStroke", { Color = color, Thickness = 4, Transparency = 0.15 }),
				})
			end
		end
	end
	function clearMarks()
		if next(marks) then
			table.clear(marks)
			drawMarks()
		end
	end
	local dragFrom: string? = nil
	for row = 1, 8 do
		for col = 1, 8 do
			local cell = grid.cell(row, col)
			cell.MouseButton2Down:Connect(function()
				dragFrom = squareOf(row, col)
			end)
			cell.MouseButton2Up:Connect(function()
				local from, to = dragFrom, squareOf(row, col)
				dragFrom = nil
				if not from then
					return
				end
				local key = if from == to then to else `{from}>{to}`
				marks[key] = if marks[key] then nil else true
				drawMarks()
			end)
		end
	end

	function stepTo(index: number?)
		local total = snapshot and #snapshot.view.past or 0
		if index ~= nil and index >= total then
			index = nil
		end
		if index ~= viewing then
			viewing = index
			selected = nil
			closePicker()
			Audio.play("piece", { volume = 0.5 })
			render()
		end
	end

	function render()
		if not snapshot then
			return
		end
		local view = snapshot.view
		local flipped = snapshot.yourSeat == 2
		if flipped ~= shownFlipped then
			shownFlipped = flipped
			clearMarks()
		end
		grid.setFlipped(flipped)
		local over = snapshot.result ~= nil or snapshot.aborted == true
		local acting = if over then nil else snapshot.activeSeats[1]
		HudKit.turnTint(side, acting, acting ~= nil and acting == snapshot.yourSeat)

		-- The board to draw: live, or a past position from the move list.
		local boardAt: (number) -> number
		local last = view.lastMove
		local past = view.past or {}
		if viewing == 0 or (viewing and past[viewing]) then
			local fen = if viewing == 0 then view.startFen else past[viewing :: number].fen
			local pos = ChessRules.fromFen(fen)
			boardAt = function(sq)
				return pos.board[sq]
			end
			last = if viewing == 0 then nil else past[viewing :: number]
		else
			viewing = nil
			boardAt = function(sq)
				return view.board[sq + 1]
			end
		end

		local targets, targetColor = {}, Color3.fromRGB(30, 30, 30)
		if viewing then
			-- looking back: no move hints
		elseif selected then
			for _, m in movesFrom(selected) do
				targets[m.to] = true
			end
		elseif premoveFrom and canPremove() then
			targets = premoveTargets(premoveFrom)
			targetColor = PREMOVE
		end
		if not canPremove() then
			premoveFrom = nil
		end

		for row = 1, 8 do
			for col = 1, 8 do
				local square = squareOf(row, col)
				local sq = ChessRules.parseSquare(square) :: number
				local code = boardAt(sq)
				local cell = grid.cell(row, col)
				local light = (row + col) % 2 == 0
				local base = if light then LIGHT else DARK
				if square == selected or square == premoveFrom then
					base = SELECTED
				elseif premove and (square == premove.from or square == premove.to) then
					base = base:Lerp(PREMOVE, 0.6)
				elseif last and (square == last.from or square == last.to) then
					base = base:Lerp(if viewing then REVIEW else LAST_MOVE, 0.55)
				end
				if not viewing and view.inCheck and square == view.kingSquare then
					base = base:Lerp(CHECK, 0.7)
				end
				cell.BackgroundColor3 = base

				-- Coordinates on the edges as you see the board.
				local bottomRow = if flipped then 1 else 8
				local leftCol = if flipped then 8 else 1
				local rankLabel = cell:FindFirstChild("Rank") :: TextLabel
				local fileLabel = cell:FindFirstChild("File") :: TextLabel
				rankLabel.Text = if col == leftCol then tostring(9 - row) else ""
				fileLabel.Text = if row == bottomRow then string.sub(FILE_LETTERS, col, col) else ""
				rankLabel.TextColor3 = if light then DARK else LIGHT
				fileLabel.TextColor3 = rankLabel.TextColor3

				local content = grid.content(row, col)
				if shownCodes[square] ~= code then
					shownCodes[square] = code
					content:ClearAllChildren()
					if code ~= 0 then
						pieceVisual(code).Parent = content
					end
				end

				-- A dot for a quiet move, a ring around a piece you can take.
				local dot = cell:FindFirstChild("Target")
				local capture = code ~= 0
				if dot and (not targets[square] or dot:GetAttribute("Capture") ~= capture or dot:GetAttribute("Pre") ~= (targetColor == PREMOVE)) then
					dot:Destroy()
					dot = nil
				end
				if targets[square] and not dot then
					local marker = Kit.new("Frame", {
						Name = "Target",
						BackgroundColor3 = targetColor,
						BackgroundTransparency = if capture then 1 else 0.55,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = if capture then UDim2.fromScale(0.9, 0.9) else UDim2.fromScale(0.3, 0.3),
						ZIndex = 3,
						Parent = cell,
					}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
					marker:SetAttribute("Capture", capture)
					marker:SetAttribute("Pre", targetColor == PREMOVE)
					if capture then
						Kit.new("UIStroke", { Color = targetColor, Thickness = 4, Transparency = 0.35, Parent = marker })
					end
				end
			end
		end

		-- Captured pieces and move list
		-- Taken pieces as piece symbols, smallest first, with the material lead like
		-- the big chess sites show it ("PPN +3").
		local VALUE = { 1, 3, 3, 5, 9, 0 }
		local SYMBOL = { "P", "N", "B", "R", "Q", "K" }
		local worth = { 0, 0 }
		local function capturedText(seat: number): string
			local list = table.clone(view.captured[seat] or {})
			table.sort(list)
			local symbols = {}
			for _, kind in list do
				worth[seat] += VALUE[kind] or 0
				table.insert(symbols, SYMBOL[kind] or LETTERS[kind] or "?")
			end
			return table.concat(symbols, "")
		end
		local white, black = capturedText(1), capturedText(2)
		local function lead(seat: number): string
			local d = worth[seat] - worth[3 - seat]
			return if d > 0 then `  +{d}` else ""
		end
		capturedLabel.Text = `White took: {white}{lead(1)}\nBlack took: {black}{lead(2)}`
		local openingName = ChessReview.opening(view.moveList)
		if openingName then
			capturedLabel.Text ..= `\n{openingName}`
		end
		-- Game Review results: accuracy, and a coach line for the move you're looking at.
		local reviewed = review and review.done and reviewFor == view.startFen .. #view.past
		local shown = if reviewed then review.moves[viewing or #view.past] else nil
		if reviewed then
			capturedLabel.Text = `Accuracy  White {review.accuracy[1]}  ·  Black {review.accuracy[2]}\n` .. capturedLabel.Text
			if shown then
				capturedLabel.Text ..= `\n{shown.symbol} {ChessReview.describe(shown)}`
			end
		end
		local labelHeight = if reviewed then 100 else 58
		capturedLabel.Size = UDim2.new(1, 0, 0, labelHeight)
		capturedLabel.TextWrapped = true
		moves.Position = UDim2.new(0, 0, 0, labelHeight + 6)
		reviewButton.Visible = over and #view.past >= 2 and not reviewed
		local buttonRoom = if reviewButton.Visible then 34 else 0
		moves.Size = UDim2.new(1, 0, 1, -(labelHeight + 44 + buttonRoom))
		if reviewing and review then
			reviewButton.Text = `Reviewing... {review.progress}/{#review.plies}`
		elseif not reviewed then
			reviewButton.Text = "Game Review"
		end
		local arrow = if shown and shown.bestFrom and viewing then `{shown.bestFrom}>{shown.bestTo}` else nil
		if arrow ~= reviewArrow then
			reviewArrow = arrow
			drawMarks()
		end
		evalBar.Visible = reviewed == true
		if reviewed then
			local cp = if shown then shown.evalAfter else 0
			local whiteShare = ChessReview.winPercent(cp) / 100
			-- The bar's White end is the side nearest you.
			evalFill.AnchorPoint = if flipped then Vector2.new(0, 0) else Vector2.new(0, 1)
			evalFill.Position = if flipped then UDim2.fromScale(0, 0) else UDim2.fromScale(0, 1)
			evalFill.Size = UDim2.fromScale(1, whiteShare)
		end
		if view.checks then
			capturedLabel.Text ..= `\nChecks: White {view.checks[1]}/3 · Black {view.checks[2]}/3`
		end

		-- Each move is a button: tap it to see the board after it.
		local plies = #view.moveList
		do
			Kit.clear(moves)
			for i = 1, plies, 2 do
				local number = (i + 1) // 2
				local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = number, Parent = moves }, { Kit.list(2, true) })
				Kit.label(`{number}.`, { TextSize = 13, TextColor3 = Theme.SubText, Size = UDim2.new(0, 28, 1, 0), LayoutOrder = 0, Parent = row })
				for k = 0, 1 do
					local ply = i + k
					local san = view.moveList[ply]
					if san then
						local current = if viewing then ply == viewing else ply == plies
						local graded = if reviewed then review.moves[ply] else nil
						Kit.new("TextButton", {
							Text = if graded then `{san} {graded.symbol}` else san,
							TextColor3 = if graded and graded.label ~= "Book" and graded.label ~= "Forced" and graded.label ~= "Best" and graded.label ~= "Excellent" and graded.label ~= "Good" then ChessReview.COLORS[graded.label] else Theme.Text,
							Font = if current then Theme.FontBold else Theme.Font,
							TextSize = 14,
							BackgroundColor3 = if current then Theme.Accent else Theme.Panel,
							BackgroundTransparency = if current then 0.3 else 1,
							AutoButtonColor = true,
							Size = UDim2.new(0.5, -16, 1, 0),
							LayoutOrder = ply,
							Parent = row,
						}, { Kit.corner(6) }).Activated:Connect(function()
							stepTo(ply)
						end)
					end
				end
			end
			if not viewing then
				moves.CanvasPosition = Vector2.new(0, 1e6)
			end
		end
		navButtons.back.Visible = plies > 0
		navButtons.forward.Visible = plies > 0
		navButtons.live.Visible = plies > 0
		navButtons.live.BackgroundColor3 = if viewing then Theme.Accent else Theme.Panel
		if premove then
			capturedLabel.Text ..= `\nPremove: {premove.from}-{premove.to}`
		end
	end

	-- Runs the review one move per frame so the game never hitches, then opens it at move 1.
	local destroyed = false
	function startReview()
		if reviewing or not snapshot then
			return
		end
		local view = snapshot.view
		local key = view.startFen .. #view.past
		if review and reviewFor == key then
			return
		end
		review = ChessReview.new(view.startFen, view.past, { depth = 4, seconds = 0.2 })
		reviewFor = key
		reviewing = true
		Audio.play("click")
		render()
		task.spawn(function()
			local current = review
			while not destroyed and current == review and not current:step() do
				render()
				task.wait()
			end
			if destroyed or current ~= review then
				return
			end
			reviewing = false
			Audio.play("win", { volume = 0.4 })
			stepTo(1)
			render()
		end)
	end

	return {
		update = function(newSnapshot: any)
			local hadMoves = snapshot and #snapshot.view.moveList or 0
			snapshot = newSnapshot
			if review and reviewFor ~= snapshot.view.startFen .. #snapshot.view.past and snapshot.result == nil then
				review, reviewFor, reviewing = nil, nil, false -- a rematch started
			end
			if not myTurn() then
				selected = nil
				closePicker()
			end
			if #snapshot.view.moveList ~= hadMoves and viewing then
				viewing = nil -- a new move brings you back to the live board
			end
			-- The turn came: play the queued premove if it's still legal.
			if premove and myTurn() then
				local queued = premove
				premove = nil
				for _, m in snapshot.view.legalMoves do
					if m.from == queued.from and m.to == queued.to then
						sendMove({ from = m.from, to = m.to, promotion = if m.promotion then "q" else nil })
						break
					end
				end
			elseif premove and (snapshot.result ~= nil or snapshot.aborted) then
				premove = nil
			end
			render()
		end,
		-- The end card's extra button (UI/MatchView).
		endAction = function(): any?
			if not snapshot or #snapshot.view.past < 2 then
				return nil
			end
			return { label = "Game Review", run = startReview }
		end,
		destroy = function()
			destroyed = true
			for _, connection in connections do
				connection:Disconnect()
			end
			if drag then
				drag.ghost:Destroy()
			end
			root:Destroy()
		end,
	}
end

return Chess
