-- Tap a piece on the 3D board, then each landing square in turn. A multi-jump finishes by
-- itself as soon as only one route is left (like the 2D board), and the rest of each route
-- shows as numbered hops. Tap the piece's starting square to cancel a half-entered jump.
-- When a capture is forced, the pieces that can jump are ringed in orange and a "You must
-- jump!" note shows; otherwise your movable pieces get a faint ring. A piece you can move
-- rises off the board under the mouse, and the one you picked stays up until the move is done.

local ClockPills = require(script.Parent.Parent.UI.ClockPills)

local Checkers = {}

local SELECTED = Color3.fromRGB(255, 214, 102)
local TARGET = Color3.fromRGB(80, 220, 120)
local CAN_JUMP = Color3.fromRGB(255, 160, 60)
local CAN_MOVE = Color3.fromRGB(200, 230, 255)

local function same(a: { number }, b: { number }): boolean
	return a[1] == b[1] and a[2] == b[2]
end

function Checkers.create(ctx: any)
	local snapshot: any = nil
	-- Game clocks (house rule): both times over the table, under the header.
	local clocks = if ctx.gui
		then ClockPills.create({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 62),
			Size = UDim2.fromOffset(260, 28),
			Parent = ctx.gui,
		})
		else nil
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

	-- A small number over a square: which hop of the jump lands there.
	local function hopLabel(r: number, c: number, n: number)
		local cell = ctx.cell(r, c)
		if not cell then
			return
		end
		local holder = Instance.new("Part")
		holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch = true, false, false, false
		holder.Transparency = 1
		holder.Size = Vector3.one * 0.05
		holder.CFrame = cell.CFrame * CFrame.new(0, cell.Size.X * 0.45, 0)
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromScale(cell.Size.X * 0.5, cell.Size.X * 0.5)
		gui.LightInfluence = 0
		gui.AlwaysOnTop = true
		gui.Parent = holder
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = SELECTED
		label.BackgroundTransparency = 0.15
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(60, 40, 20)
		label.Text = tostring(n)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = label
		label.Parent = gui
		ctx.addLocal(holder)
	end

	-- "You must jump!" over the table while a capture is forced on your turn.
	local note: TextLabel? = nil
	local function setNote(text: string?)
		if text and not note and ctx.gui then
			local label = Instance.new("TextLabel")
			label.Name = "CheckersNote"
			label.AnchorPoint = Vector2.new(0.5, 0)
			label.Position = UDim2.new(0.5, 0, 0, 96)
			label.Size = UDim2.fromOffset(240, 30)
			label.BackgroundColor3 = Color3.fromRGB(54, 49, 84)
			label.BackgroundTransparency = 0.15
			label.Font = Enum.Font.GothamBold
			label.TextSize = 18
			label.TextColor3 = Color3.fromRGB(255, 214, 102)
			local corner = Instance.new("UICorner")
			corner.Parent = label
			label.Parent = ctx.gui
			note = label
		end
		if note then
			note.Visible = text ~= nil
			note.Text = text or ""
		end
	end

	local function render()
		ctx.clearMarks()
		showJumpingPiece()
		lift()
		local jumping = snapshot ~= nil and snapshot.view.mustJump == true and #legal() > 0
		setNote(if jumping then (if #partial > 0 then "Keep jumping! (tap the start to undo)" else "You must jump!") else nil)
		if selected then
			markCell(selected[1], selected[2], SELECTED, "fill")
			for _, sq in partial do
				markCell(sq[1], sq[2], SELECTED, "fill")
			end
			local hops: { [number]: number } = {}
			for _, m in candidates() do
				local nextSq = m.path[#partial + 1]
				markCell(nextSq[1], nextSq[2], TARGET, "dot")
				for i, sq in m.path do
					if i > #partial then
						local key = sq[1] * 10 + sq[2]
						hops[key] = math.min(hops[key] or i, i)
					end
				end
			end
			if jumping then
				for key, n in hops do
					hopLabel(key // 10, key % 10, n)
				end
			end
		elseif jumping then
			for _, m in legal() do
				markCell(m.from[1], m.from[2], CAN_JUMP, "ring")
			end
		else
			local seen = {}
			for _, m in legal() do
				local key = m.from[1] * 10 + m.from[2]
				if not seen[key] then
					seen[key] = true
					markCell(m.from[1], m.from[2], CAN_MOVE, "ring")
				end
			end
		end
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			if clocks then
				clocks.set(snapshot)
			end
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
						-- Only one way to finish from here: play the whole jump.
						local left = candidates()
						local chosen = if #m.path == #partial then m elseif #left == 1 then left[1] else nil
						if chosen then
							ctx.dropLift()
							ctx.sendMove({ from = chosen.from, path = chosen.path })
							selected, partial = nil, {}
						end
						render()
						return
					end
				end
				if #partial > 0 then
					if same(selected :: { number }, { r, c }) then
						partial = {} -- tapped the start: take the half-entered jump back
						render()
					end
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
		destroy = function()
			if clocks then
				clocks.destroy()
			end
			if note then
				note:Destroy()
				note = nil
			end
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
