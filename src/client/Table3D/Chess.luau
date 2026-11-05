-- Tap one of your pieces on the 3D board, then a highlighted square. Promotions open a
-- small picker. Row/Col attributes on the cells use the 2D board's numbering (row 1 is
-- rank 8, col 1 is file a).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChessRules = require(ReplicatedStorage.Shared.Games.Chess)
local DrawOffer = require(script.Parent.Parent.UI.DrawOffer)

local Chess = {}

local SELECTED = Color3.fromRGB(255, 214, 102)
local TARGET = Color3.fromRGB(80, 220, 120)
local PREMOVE = Color3.fromRGB(222, 110, 90)

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
	-- Premoves (see the 2D board): played as soon as your turn comes, if still legal.
	local preSel: string? = nil
	local premove: { from: string, to: string }? = nil
	local picker: Frame? = nil
	-- Offer / accept a draw, bottom right over the room.
	local draw = DrawOffer.new(ctx.gui, ctx.sendMove, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16) })

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

	local function render()
		ctx.clearMarks()
		local pre = {}
		if preSel then
			table.insert(pre, preSel)
		end
		if premove then
			table.insert(pre, premove.from)
			table.insert(pre, premove.to)
		end
		for _, square in pre do
			local r, c = cellOf(square)
			local cell = ctx.cell(r, c)
			if cell then
				ctx.mark(cell, PREMOVE, "fill")
			end
		end
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
				ctx.sendMove(draw.withOffer({ from = from, to = to, promotion = choice[1] }))
				render()
			end)
		end
		frame.Parent = ctx.gui
		picker = frame
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			draw.update(newSnapshot)
			if not myTurn() then
				selected = nil
				closePicker()
			elseif premove then
				local pre = premove
				premove, preSel = nil, nil
				for _, m in snapshot.view.legalMoves or {} do
					if m.from == pre.from and m.to == pre.to then
						ctx.sendMove({ from = m.from, to = m.to, promotion = if m.promotion then "q" else nil })
						break
					end
				end
			end
			if snapshot.result ~= nil or snapshot.aborted then
				premove, preSel = nil, nil
			end
			render()
		end,
		click = function(cell: BasePart)
			local r, c = cell:GetAttribute("Row"), cell:GetAttribute("Col")
			if not (r and c) or not snapshot then
				return
			end
			local square = squareOf(r :: number, c :: number)
			if not myTurn() then
				if snapshot.yourSeat and snapshot.result == nil and not snapshot.aborted then
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
					selected = nil
					closePicker()
					ctx.sendMove(draw.withOffer({ from = choices[1].from, to = choices[1].to }))
					render()
					return
				end
			end
			closePicker()
			selected = if #movesFrom(square) > 0 and square ~= selected then square else nil
			render()
		end,
		setShown = function(shown: boolean)
			draw.frame.Parent = if shown then ctx.gui else nil
		end,
		destroy = function()
			closePicker()
			draw.destroy()
		end,
	}
end

return Chess
