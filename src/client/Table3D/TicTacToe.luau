-- Tap an empty square on the 3D Tic-Tac-Toe board. On your turn, the mouse over an empty
-- square floats a see-through mark of yours over it, bobbing gently, where it would go.

local RunService = game:GetService("RunService")

local TicTacToe = {}

local GHOST = 0.45 -- the ghost mark's transparency

-- A see-through X (seat 1) or O like the server's marks, standing on `surface`.
local function ghostMark(seat: number, color: Color3, cellSize: number): Model
	local model = Instance.new("Model")
	model.Name = "GhostMark"
	local function part(size: Vector3, cf: CFrame)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.Color = color
		p.Transparency = GHOST
		p.Size = size
		p.CFrame = cf
		p.Parent = model
	end
	if seat == 1 then
		for _, angle in { 45, -45 } do
			part(Vector3.new(cellSize * 0.8, cellSize * 0.18, cellSize * 0.18), CFrame.Angles(0, math.rad(angle), 0))
		end
	else
		local ring = 12
		local radius = cellSize * 0.3
		for i = 1, ring do
			local a = (i / ring) * math.pi * 2
			part(
				Vector3.new(cellSize * 0.18, cellSize * 0.18, radius * 2 * math.pi / ring + 0.05),
				CFrame.new(math.cos(a) * radius, 0, math.sin(a) * radius) * CFrame.Angles(0, -a, 0)
			)
		end
	end
	model.WorldPivot = CFrame.identity
	return model
end

function TicTacToe.create(ctx: any)
	local snapshot: any = nil
	local hovered: number? = nil
	local ghost: Model? = nil
	local ghostAt: CFrame? = nil
	local bob: RBXScriptConnection? = nil

	local function myTurn(): boolean
		return snapshot ~= nil and table.find(snapshot.activeSeats, snapshot.yourSeat) ~= nil
	end

	local function clearGhost()
		if bob then
			bob:Disconnect()
			bob = nil
		end
		if ghost then
			ghost:Destroy()
			ghost = nil
		end
	end

	-- Returns true when a ghost appeared.
	local function showGhost(): boolean
		clearGhost()
		if not (hovered and myTurn() and snapshot.view.board[hovered] == 0) then
			return false
		end
		local r, c = (hovered - 1) // 3 + 1, (hovered - 1) % 3 + 1
		local cell = ctx.cell(r, c)
		local color = ctx.board:GetAttribute(`SeatColor{snapshot.yourSeat}`)
		if not (cell and typeof(color) == "Color3") then
			return false
		end
		local size = cell.Size.X
		local model = ghostMark(snapshot.yourSeat, color, size)
		local at = cell.CFrame * CFrame.new(0, cell.Size.Y / 2 + size * 0.09, 0)
		ghost, ghostAt = model, at
		model:PivotTo(at)
		ctx.addLocal(model)
		local born = os.clock()
		bob = RunService.RenderStepped:Connect(function()
			if not model.Parent then
				clearGhost()
				return
			end
			-- Rises off the square, then hovers with a slow bob.
			local t = os.clock() - born
			local rise = 1 - math.exp(-t * 14)
			local up = size * (0.3 * rise + 0.04 * math.sin(t * 3.2))
			model:PivotTo((ghostAt :: CFrame) + Vector3.new(0, up, 0))
		end)
		return true
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			showGhost()
		end,
		click = function(cell: BasePart)
			local r, c = cell:GetAttribute("Row"), cell:GetAttribute("Col")
			if not (snapshot and r and c) or not myTurn() then
				return
			end
			local index = ((r :: number) - 1) * 3 + (c :: number)
			if snapshot.view.board[index] == 0 then
				clearGhost()
				ctx.sendMove({ cell = index })
			end
		end,
		hover = function(cell: BasePart?): boolean
			local r, c = cell and cell:GetAttribute("Row"), cell and cell:GetAttribute("Col")
			hovered = if r and c then ((r :: number) - 1) * 3 + (c :: number) else nil
			return showGhost()
		end,
		destroy = clearGhost,
	}
end

return TicTacToe
