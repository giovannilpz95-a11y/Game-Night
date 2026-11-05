-- Tap any column of the 3D Four in a Row frame to drop a disc there. On your turn the
-- open columns get a marker on top; the column under the mouse gets a see-through disc
-- of your color instead, hovering over its slot, ready to drop. With Pop Out, a column
-- whose bottom disc is yours asks "Drop" or "Pop out" (or pops, when it's full).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Rules = require(ReplicatedStorage.Shared.Games.FourInARow)

local FourInARow = {}

local MARK = Color3.fromRGB(255, 214, 102)

function FourInARow.create(ctx: any)
	local snapshot: any = nil
	local hovered: number? = nil
	local bob: RBXScriptConnection? = nil

	local function myTurn(): boolean
		return snapshot ~= nil and table.find(snapshot.activeSeats, snapshot.yourSeat) ~= nil
	end

	local function open(c: number): boolean
		return snapshot.view.heights[c] < Rules.rows
	end

	local function stopBob()
		if bob then
			bob:Disconnect()
			bob = nil
		end
	end

	-- Pop Out: a column that could take a drop or a pop asks which (like the chess
	-- promotion picker).
	local picker: Frame? = nil
	local function closePicker()
		if picker then
			picker:Destroy()
			picker = nil
		end
	end
	local function openPicker(c: number)
		closePicker()
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromOffset(220, 64)
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
		for _, option in { { "Drop", false }, { "Pop out", true } } do
			local button = Instance.new("TextButton")
			button.Size = UDim2.fromOffset(96, 46)
			button.Text = option[1]
			button.Font = Enum.Font.GothamBold
			button.TextSize = 18
			button.TextColor3 = Color3.fromRGB(40, 36, 44)
			button.BackgroundColor3 = if option[2] then MARK else Color3.fromRGB(240, 222, 190)
			Instance.new("UICorner").Parent = button
			button.Parent = frame
			button.Activated:Connect(function()
				closePicker()
				if myTurn() then
					ctx.sendMove(if option[2] then { column = c, pop = true } else { column = c })
				end
			end)
		end
		frame.Parent = ctx.gui
		picker = frame
	end

	-- Returns true when the ghost disc is showing over a column.
	local function render(): boolean
		stopBob()
		ctx.clearMarks()
		if not myTurn() then
			return false
		end
		local ghostShown = false
		for _, column in ctx.cells:GetChildren() do
			local c = column:GetAttribute("Col")
			if c and column:IsA("BasePart") and open(c) then
				-- Just above the frame. The click part reaches one cell above the top row,
				-- so its top minus half a cell is right there.
				local cell = column.Size.X
				local spot = column.CFrame * CFrame.new(0, column.Size.Y / 2 - cell * 0.5, 0)
				local color = ctx.board:GetAttribute(`SeatColor{snapshot.yourSeat}`)
				if c == hovered and typeof(color) == "Color3" then
					local disc = Instance.new("Part")
					disc.Name = "GhostDisc"
					disc.Shape = Enum.PartType.Cylinder
					disc.Anchored = true
					disc.CanCollide = false
					disc.CanQuery = false
					disc.CanTouch = false
					disc.CastShadow = false
					disc.Material = Enum.Material.SmoothPlastic
					disc.Color = color
					disc.Transparency = 0.35
					disc.Size = Vector3.new(cell * 0.3, cell * 0.82, cell * 0.82)
					local face = CFrame.Angles(0, math.rad(90), 0) -- face-on, like the real discs
					disc.CFrame = spot * face
					ctx.addLocal(disc)
					ghostShown = true
					local born = os.clock()
					bob = RunService.RenderStepped:Connect(function()
						if not disc.Parent then
							stopBob()
							return
						end
						local t = os.clock() - born
						local up = cell * (0.25 * (1 - math.exp(-t * 14)) + 0.06 * math.sin(t * 3.2))
						disc.CFrame = spot * CFrame.new(0, up, 0) * face
					end)
				else
					local top = Instance.new("Part")
					top.Size = Vector3.one * (cell * 0.4)
					top.CFrame = spot
					ctx.mark(top, MARK, "ball")
					top:Destroy()
				end
			end
		end
		return ghostShown
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			if not myTurn() then
				closePicker()
			end
			render()
		end,
		click = function(column: BasePart)
			local c = column:GetAttribute("Col")
			if not (c and myTurn()) then
				return
			end
			local canPop = Rules.canPop(snapshot.view, snapshot.yourSeat, c)
			if open(c) and canPop then
				openPicker(c)
			elseif canPop then
				ctx.sendMove({ column = c, pop = true })
			elseif open(c) then
				hovered = nil
				render()
				ctx.sendMove({ column = c })
			end
		end,
		hover = function(column: BasePart?): boolean
			hovered = column and column:GetAttribute("Col") :: number?
			return render()
		end,
		destroy = function()
			stopBob()
			closePicker()
		end,
	}
end

return FourInARow
