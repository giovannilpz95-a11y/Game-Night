-- Checkers board. Tap a piece, then tap each landing square in turn (multi-jumps take
-- several taps; the move is sent when the jump sequence is complete). When a capture is
-- forced, only the pieces that can jump glow.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Games.Checkers)
local Kit = require(script.Parent.Parent.UI.Kit)
local BoardGrid = require(script.Parent.Parent.UI.BoardGrid)
local PieceView = require(script.Parent.Parent.UI.PieceView)
local Theme = Kit.Theme

local Checkers = {}

local LIGHT_SQUARE = Color3.fromRGB(236, 220, 192)
local DARK_SQUARE = Color3.fromRGB(96, 70, 56)
local GLOW = Color3.fromRGB(255, 214, 102)
local LAST_MOVE = Color3.fromRGB(150, 120, 70)
local HINT = Color3.fromRGB(120, 200, 255)

local DARK_PIECE = Color3.fromRGB(200, 62, 72)
local LIGHT_PIECE = Color3.fromRGB(245, 236, 214)

local function pieceVisual(v: number): GuiObject
	local dark = (v - 1) % 2 == 0
	local king = v > 2
	local name = `{if king then "King" else "Man"}_{if dark then "Dark" else "Light"}`
	return PieceView.create("Checkers", name, function()
		local fill = if dark then DARK_PIECE else LIGHT_PIECE
		local stroke = if dark then Color3.fromRGB(110, 28, 36) else Color3.fromRGB(150, 130, 100)
		return BoardGrid.token(fill, stroke, if king then "K" else "", if dark then LIGHT_PIECE else DARK_PIECE)
	end)
end

local function same(a: { number }, b: { number }): boolean
	return a[1] == b[1] and a[2] == b[2]
end

function Checkers.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local selected: { number }? = nil
	local partial: { { number } } = {}
	local shown: { [number]: number } = {}

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
	local hint = Kit.label("", {
		TextColor3 = Theme.Accent,
		Font = Theme.FontBold,
		Size = UDim2.new(1, 0, 0, 24),
		Parent = root,
	})
	local boardArea = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 30), Size = UDim2.new(1, 0, 1, -30), Parent = root })

	-- 💡 Hint, like the casual apps: a few per game, worked out here with the medium bot.
	local HINTS = 3
	local hintsLeft = HINTS
	local hinted: any = nil -- the suggested move, until you move
	local hintButton: TextButton
	hintButton = Kit.button(`💡 Hint ({HINTS})`, function()
		if not snapshot or hintsLeft <= 0 or not snapshot.view.legalMoves then
			return
		end
		local view = snapshot.view
		local move = Rules.chooseBotMove({ board = view.board, optionalCaptures = view.optionalCaptures, botLevel = "medium" }, snapshot.yourSeat, Random.new())
		if move then
			hintsLeft -= 1
			hinted = move
			hintButton.Text = `💡 Hint ({hintsLeft})`
			render()
		end
	end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(110, 26),
		TextSize = 14,
		BackgroundColor3 = Theme.PanelLight,
		TextColor3 = Theme.Text,
		Visible = false,
		Parent = root,
	})

	local render: () -> ()

	local function legal(): { any }
		return (snapshot and snapshot.view.legalMoves) or {}
	end

	-- Moves from the selected piece whose path starts with what's been tapped so far.
	local function candidates(): { any }
		local out = {}
		if not selected then
			return out
		end
		for _, m in legal() do
			if same(m.from, selected) and #m.path > #partial then
				local ok = true
				for i, sq in partial do
					if not same(m.path[i], sq) then
						ok = false
						break
					end
				end
				if ok then
					table.insert(out, m)
				end
			end
		end
		return out
	end

	local function canMoveFrom(r: number, c: number): boolean
		for _, m in legal() do
			if m.from[1] == r and m.from[2] == c then
				return true
			end
		end
		return false
	end

	local function onClick(r: number, c: number)
		if #legal() == 0 then
			return
		end
		if selected then
			for _, m in candidates() do
				local nextSq = m.path[#partial + 1]
				if nextSq[1] == r and nextSq[2] == c then
					table.insert(partial, { r, c })
					if #m.path == #partial then
						sendMove({ from = m.from, path = m.path })
						selected, partial = nil, {}
					end
					render()
					return
				end
			end
			if #partial > 0 then
				return -- mid-jump: must keep going with the same piece
			end
		end
		if canMoveFrom(r, c) and not (selected and same(selected, { r, c })) then
			selected, partial = { r, c }, {}
		else
			selected, partial = nil, {}
		end
		render()
	end

	local grid = BoardGrid.create(boardArea, 8, onClick)

	function render()
		if not snapshot then
			return
		end
		local view = snapshot.view
		grid.setFlipped(snapshot.yourSeat == 2)
		hint.Text = if view.mustJump then "You must jump!" elseif hinted then "💡 Try the glowing move" else ""
		hintButton.Visible = view.legalMoves ~= nil and snapshot.result == nil and hintsLeft > 0
		local hintSquares: { [number]: boolean } = {}
		if hinted then
			hintSquares[hinted.from[1] * 10 + hinted.from[2]] = true
			for _, sq in hinted.path do
				hintSquares[sq[1] * 10 + sq[2]] = true
			end
		end

		local nextSquares: { [number]: boolean } = {}
		for _, m in candidates() do
			local sq = m.path[#partial + 1]
			nextSquares[sq[1] * 10 + sq[2]] = true
		end
		local lastSquares: { [number]: boolean } = {}
		if view.lastMove then
			lastSquares[view.lastMove.from[1] * 10 + view.lastMove.from[2]] = true
			for _, sq in view.lastMove.path do
				lastSquares[sq[1] * 10 + sq[2]] = true
			end
		end
		local trail: { [number]: boolean } = {}
		for _, sq in partial do
			trail[sq[1] * 10 + sq[2]] = true
		end

		for r = 1, 8 do
			for c = 1, 8 do
				local key = r * 10 + c
				local cell = grid.cell(r, c)
				local dark = (r + c) % 2 == 1
				local color = if dark then DARK_SQUARE else LIGHT_SQUARE
				if dark and lastSquares[key] then
					color = LAST_MOVE
				end
				if selected and same(selected, { r, c }) or trail[key] then
					color = GLOW
				elseif nextSquares[key] then
					color = color:Lerp(GLOW, 0.6)
				elseif view.mustJump and not selected and canMoveFrom(r, c) then
					color = color:Lerp(GLOW, 0.4)
				elseif hintSquares[key] then
					color = color:Lerp(HINT, 0.65)
				end
				cell.BackgroundColor3 = color

				local v = view.board[r][c]
				-- While mid-jump, show the piece where it has got to.
				if selected and #partial > 0 then
					if same(selected, { r, c }) then
						v = 0
					elseif same(partial[#partial], { r, c }) then
						v = view.board[selected[1]][selected[2]]
					end
				end
				if shown[key] ~= v then
					shown[key] = v
					local content = grid.content(r, c)
					content:ClearAllChildren()
					if v ~= 0 then
						pieceVisual(v).Parent = content
					end
				end
			end
		end
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			selected, partial = nil, {}
			if not snapshot.view.legalMoves then
				hinted = nil
			end
			if (snapshot.moveNumber or 0) <= 1 then
				hintsLeft = HINTS -- a new game
			end
			render()
		end,
		destroy = function()
			root:Destroy()
		end,
	}
end

return Checkers
