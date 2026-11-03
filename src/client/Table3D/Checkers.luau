-- Tap a piece on the 3D board, then each landing square in turn (multi-jumps take
-- several taps; the move is sent when the jump is complete). When a capture is forced,
-- the pieces that can jump are marked.

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

	local function render()
		ctx.clearMarks()
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
	}
end

return Checkers
