-- Tap a piece on the 3D board, then each landing square in turn (multi-jumps take
-- several taps; the move is sent when the jump is complete). When a capture is forced,
-- the pieces that can jump are marked. A piece you can move rises off the board under
-- the mouse, and the one you picked stays up until the move is done.

local Checkers = {}

local SELECTED = Color3.fromRGB(255, 214, 102)
local TARGET = Color3.fromRGB(80, 220, 120)
local CAN_JUMP = Color3.fromRGB(255, 160, 60)

local function same(a: { number }, b: { number }): boolean
	return a[1] == b[1] and a[2] == b[2]
end

function Checkers.create(ctx: any)
	local snapshot: any = nil
	local selected: { number }? = nil
	local partial: { { number } } = {}
	local hovered: { number }? = nil -- the square under the mouse

	local function legal(): { any }
		return (snapshot and snapshot.view.legalMoves) or {}
	end

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

	local function markCell(r: number, c: number, color: Color3, style: string)
		local cell = ctx.cell(r, c)
		if cell then
			ctx.mark(cell, color, style)
		end
	end

	local function setHidden(piece: Instance, hidden: boolean)
		local list = piece:GetDescendants()
		table.insert(list, piece)
		for _, d in list do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = if hidden then 1 else 0
			end
		end
	end

	-- Mid-jump, show the piece where it has got to (only on your screen), like the 2D view.
	local function showJumpingPiece()
		local pieces = ctx.board:FindFirstChild("Pieces")
		if not pieces then
			return
		end
		for _, piece in pieces:GetChildren() do
			setHidden(piece, false)
		end
		if not selected or #partial == 0 then
			return
		end
		local from = ctx.cell(selected[1], selected[2])
		local to = ctx.cell(partial[#partial][1], partial[#partial][2])
		for _, piece in pieces:GetChildren() do
			if piece:GetAttribute("Row") == selected[1] and piece:GetAttribute("Col") == selected[2] and from and to then
				setHidden(piece, true)
				local ghost = piece:Clone()
				setHidden(ghost, false)
				ghost:PivotTo((ghost :: any):GetPivot() + (to.Position - from.Position))
				ctx.addLocal(ghost)
				return
			end
		end
	end

	-- Mid-jump the picked piece is already a ghost on its landing square, so it stays down.
	local function lift(): boolean
		local wanted = {}
		local rose = false
		for _, sq in { hovered, if #partial == 0 then selected else nil } do
			if sq and canMoveFrom(sq[1], sq[2]) then
				local piece = ctx.pieceAt(sq[1], sq[2])
				local cell = ctx.cell(sq[1], sq[2])
				if piece and cell then
					local picked = selected ~= nil and same(sq, selected :: { number })
					wanted[piece] = cell.Size.X * (if picked then 0.6 else 0.4)
					rose = rose or not picked
				end
			end
		end
		ctx.lift(wanted)
		return rose
	end

	local function render()
		ctx.clearMarks()
		showJumpingPiece()
		lift()
		if selected then
			markCell(selected[1], selected[2], SELECTED, "fill")
			for _, sq in partial do
				markCell(sq[1], sq[2], SELECTED, "fill")
			end
			for _, m in candidates() do
				local nextSq = m.path[#partial + 1]
				markCell(nextSq[1], nextSq[2], TARGET, "dot")
			end
		elseif snapshot and snapshot.view.mustJump then
			for _, m in legal() do
				markCell(m.from[1], m.from[2], CAN_JUMP, "ring")
			end
		end
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			selected, partial = nil, {}
			render()
		end,
		click = function(cell: BasePart)
			local r, c = cell:GetAttribute("Row") :: number?, cell:GetAttribute("Col") :: number?
			if not (r and c) or #legal() == 0 then
				return
			end
			if selected then
				for _, m in candidates() do
					local nextSq = m.path[#partial + 1]
					if nextSq[1] == r and nextSq[2] == c then
						table.insert(partial, { r, c })
						if #m.path == #partial then
							ctx.dropLift()
							ctx.sendMove({ from = m.from, path = m.path })
							selected, partial = nil, {}
						end
						render()
						return
					end
				end
				if #partial > 0 then
					return -- mid-jump: keep going with the same piece
				end
			end
			if canMoveFrom(r, c) and not (selected and same(selected, { r, c })) then
				selected, partial = { r, c }, {}
			else
				selected, partial = nil, {}
			end
			render()
		end,
		-- Returns true when a piece rose (the controller plays a soft tick).
		hover = function(cell: BasePart?): boolean
			local r, c = cell and cell:GetAttribute("Row"), cell and cell:GetAttribute("Col")
			hovered = if r and c then { r :: number, c :: number } else nil
			return lift()
		end,
	}
end

return Checkers
