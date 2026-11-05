-- Chess board: tap one of your pieces, then a highlighted square. Pawns reaching the last
-- rank open a promotion picker. Shows the last move, check, captured pieces and the moves.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChessRules = require(ReplicatedStorage.Shared.Games.Chess)
local Kit = require(script.Parent.Parent.UI.Kit)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local DrawOffer = require(script.Parent.Parent.UI.DrawOffer)
local BoardGrid = require(script.Parent.Parent.UI.BoardGrid)
local PieceView = require(script.Parent.Parent.UI.PieceView)
local Theme = Kit.Theme

local Chess = {}

local NAMES = { "Pawn", "Knight", "Bishop", "Rook", "Queen", "King" }
local LETTERS = { "", "N", "B", "R", "Q", "K" }
local LIGHT = Color3.fromRGB(240, 222, 190)
local DARK = Color3.fromRGB(176, 128, 92)
local SELECTED = Color3.fromRGB(255, 214, 102)
local LAST_MOVE = Color3.fromRGB(214, 196, 110)
local CHECK = Color3.fromRGB(235, 87, 87)
local PREMOVE = Color3.fromRGB(222, 110, 90)

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
	-- Premoves: off your turn, pick a piece and a square; it plays the moment your turn
	-- comes, if it's legal then.
	local preSel: string? = nil
	local premove: { from: string, to: string }? = nil
	local shownCodes: { [string]: number } = {}
	local shownFlipped: boolean? = nil

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
	local moves = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 50),
		Size = UDim2.new(1, 0, 1, -134),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		Parent = side,
	}, { Kit.list(2) })

	-- Offer / accept a draw, under the move list.
	local draw = DrawOffer.new(side, sendMove, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, 0, 0, 76) })
	local promotionPicker: Frame? = nil

	local function closePicker()
		if promotionPicker then
			promotionPicker:Destroy()
			promotionPicker = nil
		end
	end

	local render: () -> ()
	local clearMarks: () -> ()
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
				sendMove(draw.withOffer({ from = from, to = to, promotion = choice[1] }))
				render()
			end)
		end
		promotionPicker = picker
	end

	local function onClick(row: number, col: number)
		local square = squareOf(row, col)
		if not myTurn() then
			if snapshot and snapshot.yourSeat and snapshot.result == nil and not snapshot.aborted then
				local code = snapshot.view.board[(ChessRules.parseSquare(square) :: number) + 1]
				local mine = code ~= 0 and ((code > 0) == (snapshot.yourSeat == 1))
				if preSel and square ~= preSel and not mine then
					premove = { from = preSel, to = square }
					preSel = nil
				elseif mine and square ~= preSel then
					preSel, premove = square, nil
				else
					preSel, premove = nil, nil
				end
				render()
			end
			return
		end
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
				sendMove(draw.withOffer({ from = m.from, to = m.to }))
				render()
				return
			end
		end
		closePicker()
		selected = if #movesFrom(square) > 0 and square ~= selected then square else nil
		render()
	end

	grid = BoardGrid.create(boardArea, 8, function(row, col)
		clearMarks()
		onClick(row, col)
	end)

	-- Right-click marks, like the big chess sites: right-click a square to ring it, or
	-- right-drag from one square to another for an arrow. Any left click clears them.
	-- Only you see them.
	local MARK = Color3.fromRGB(255, 160, 40)
	local inner = grid.cell(1, 1).Parent :: Frame
	local markLayer = Kit.new("Frame", { Name = "Marks", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = inner })
	local marks: { [string]: boolean } = {} -- "a1" (ring) or "a1>c3" (arrow)
	local function center(row: number, col: number): Vector2
		local p = grid.cell(row, col).Position
		return Vector2.new(p.X.Scale + 1 / 16, p.Y.Scale + 1 / 16)
	end
	local function drawMarks()
		Kit.clear(markLayer)
		for key in marks do
			local from, to = string.match(key, "^(%w+)>(%w+)$")
			if from and to then
				local a = center(cellOf(from))
				local b = center(cellOf(to))
				local d = b - a
				local angle = math.deg(math.atan2(d.Y, d.X))
				local tip = b - d.Unit * 0.03
				Kit.new("Frame", {
					BackgroundColor3 = MARK,
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
					TextColor3 = MARK,
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
					Kit.new("UIStroke", { Color = MARK, Thickness = 4, Transparency = 0.15 }),
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

	function render()
		if not snapshot then
			return
		end
		local view = snapshot.view
		local flipped = snapshot.yourSeat == 2
		if flipped ~= shownFlipped then
			shownFlipped = flipped
			grid.setFlipped(flipped)
			clearMarks()
		end
		local over = snapshot.result ~= nil or snapshot.aborted == true
		local acting = if over then nil else snapshot.activeSeats[1]
		HudKit.turnTint(side, acting, acting ~= nil and acting == snapshot.yourSeat)

		local targets = {}
		if selected then
			for _, m in movesFrom(selected) do
				targets[m.to] = true
			end
		end
		local last = view.lastMove

		for row = 1, 8 do
			for col = 1, 8 do
				local square = squareOf(row, col)
				local sq = ChessRules.parseSquare(square) :: number
				local code = view.board[sq + 1]
				local cell = grid.cell(row, col)
				local base = if (row + col) % 2 == 0 then LIGHT else DARK
				if square == selected then
					base = SELECTED
				elseif square == preSel or (premove and (square == premove.from or square == premove.to)) then
					base = base:Lerp(PREMOVE, 0.75)
				elseif last and (square == last.from or square == last.to) then
					base = base:Lerp(LAST_MOVE, 0.55)
				end
				if view.inCheck and square == view.kingSquare then
					base = base:Lerp(CHECK, 0.7)
				end
				cell.BackgroundColor3 = base

				local content = grid.content(row, col)
				if shownCodes[square] ~= code then
					shownCodes[square] = code
					content:ClearAllChildren()
					if code ~= 0 then
						pieceVisual(code).Parent = content
					end
				end

				local dot = cell:FindFirstChild("Target")
				if targets[square] and not dot then
					Kit.new("Frame", {
						Name = "Target",
						BackgroundColor3 = Color3.fromRGB(30, 30, 30),
						BackgroundTransparency = 0.6,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = if code ~= 0 then UDim2.fromScale(0.95, 0.95) else UDim2.fromScale(0.3, 0.3),
						ZIndex = 3,
						Parent = cell,
					}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
				elseif not targets[square] and dot then
					dot:Destroy()
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
		if view.checks then
			capturedLabel.Text ..= `\nChecks: White {view.checks[1]}/3 · Black {view.checks[2]}/3`
		end

		Kit.clear(moves)
		for i = 1, #view.moveList, 2 do
			local number = (i + 1) // 2
			local text = `{number}. {view.moveList[i]}`
			if view.moveList[i + 1] then
				text ..= `   {view.moveList[i + 1]}`
			end
			Kit.label(text, { TextSize = 14, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = number, Parent = moves })
		end
		moves.CanvasPosition = Vector2.new(0, 1e6)
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			draw.update(newSnapshot)
			if not myTurn() then
				selected = nil
				closePicker()
			elseif premove then
				-- Your turn: play the premove if it's still legal.
				local pre = premove
				premove, preSel = nil, nil
				for _, m in snapshot.view.legalMoves or {} do
					if m.from == pre.from and m.to == pre.to then
						sendMove({ from = m.from, to = m.to, promotion = if m.promotion then "q" else nil })
						break
					end
				end
			end
			if snapshot.result ~= nil or snapshot.aborted then
				premove, preSel = nil, nil
			end
			render()
		end,
		destroy = function()
			root:Destroy()
		end,
	}
end

return Chess
