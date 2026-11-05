-- Tap one of your pieces on the 3D board, then a highlighted square. Promotions open a
-- small picker. Row/Col attributes on the cells use the 2D board's numbering (row 1 is
-- rank 8, col 1 is file a). On your turn the piece under the mouse rises off its square
-- if it can move, and the one you picked stays up until you move or let it go.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChessRules = require(ReplicatedStorage.Shared.Games.Chess)

local Chess = {}

local SELECTED = Color3.fromRGB(255, 214, 102)
local TARGET = Color3.fromRGB(80, 220, 120)

local function squareOf(row: number, col: number): string
	return ChessRules.squareName((8 - row) * 8 + (col - 1))
end

local function cellOf(square: string): (number, number)
	local sq = ChessRules.parseSquare(square) :: number
	return 8 - sq // 8, sq % 8 + 1
end

function Chess.create(ctx: any)
	local snapshot: any = nil
	local selected: string? = nil
	local picker: Frame? = nil
	local hovered: string? = nil -- the square under the mouse

	local function closePicker()
		if picker then
			picker:Destroy()
			picker = nil
		end
	end

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

	-- Lifts the picked piece high and a movable one under the mouse a little less.
	local function lift(): boolean
		local wanted = {}
		local rose = false
		if myTurn() then
			for _, square in { hovered, selected } do
				if square and #movesFrom(square) > 0 then
					local r, c = cellOf(square)
					local piece = ctx.pieceAt(r, c)
					local cell = ctx.cell(r, c)
					if piece and cell then
						wanted[piece] = cell.Size.X * (if square == selected then 0.7 else 0.45)
						rose = rose or square == hovered
					end
				end
			end
		end
		ctx.lift(wanted)
		return rose
	end

	local function render()
		ctx.clearMarks()
		lift()
		if not selected then
			return
		end
		local r, c = cellOf(selected)
		local cell = ctx.cell(r, c)
		if cell then
			ctx.mark(cell, SELECTED, "fill")
		end
		for _, m in movesFrom(selected) do
			local tr, tc = cellOf(m.to)
			local target = ctx.cell(tr, tc)
			if target then
				local occupied = snapshot.view.board[(ChessRules.parseSquare(m.to) :: number) + 1] ~= 0
				ctx.mark(target, TARGET, if occupied then "ring" else "dot")
			end
		end
	end

	local function openPicker(from: string, to: string)
		closePicker()
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromOffset(250, 70)
		frame.AnchorPoint = Vector2.new(0.5, 1)
		frame.Position = UDim2.new(0.5, 0, 1, -90)
		frame.BackgroundColor3 = Color3.fromRGB(54, 49, 84)
		Instance.new("UICorner").Parent = frame
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 8)
		layout.Parent = frame
		local white = snapshot.yourSeat == 1
		for _, choice in { { "q", "Q" }, { "r", "R" }, { "b", "B" }, { "n", "N" } } do
			local button = Instance.new("TextButton")
			button.Size = UDim2.fromOffset(52, 56)
			button.BackgroundColor3 = Color3.fromRGB(240, 222, 190)
			-- Plain letters: Roblox fonts have no chess glyphs.
			button.Text = choice[2]
			button.Font = Enum.Font.GothamBlack
			button.TextScaled = true
			button.BackgroundColor3 = if white then Color3.fromRGB(250, 246, 236) else Color3.fromRGB(40, 36, 44)
			button.TextColor3 = if white then Color3.fromRGB(40, 36, 44) else Color3.fromRGB(250, 246, 236)
			Instance.new("UICorner").Parent = button
			button.Parent = frame
			button.Activated:Connect(function()
				closePicker()
				selected = nil
				ctx.dropLift()
				ctx.sendMove({ from = from, to = to, promotion = choice[1] })
				render()
			end)
		end
		frame.Parent = ctx.gui
		picker = frame
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			if not myTurn() then
				selected = nil
				closePicker()
			end
			render()
		end,
		click = function(cell: BasePart)
			local r, c = cell:GetAttribute("Row"), cell:GetAttribute("Col")
			if not (r and c) or not myTurn() then
				return
			end
			local square = squareOf(r :: number, c :: number)
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
					selected = nil
					closePicker()
					ctx.dropLift()
					ctx.sendMove({ from = choices[1].from, to = choices[1].to })
					render()
					return
				end
			end
			closePicker()
			selected = if #movesFrom(square) > 0 and square ~= selected then square else nil
			render()
		end,
		-- Returns true when a piece rose (the controller plays a soft tick).
		hover = function(cell: BasePart?): boolean
			local r, c = cell and cell:GetAttribute("Row"), cell and cell:GetAttribute("Col")
			hovered = if r and c then squareOf(r :: number, c :: number) else nil
			return lift() and hovered ~= selected
		end,
		destroy = closePicker,
	}
end

return Chess
