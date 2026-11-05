-- Tap any column of the 3D Four in a Row frame to drop a disc there. On your turn the
-- open columns get a marker on top. With Pop Out, a column whose bottom disc is yours
-- asks "Drop" or "Pop out".

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.Shared.Games.FourInARow)

local FourInARow = {}

local MARK = Color3.fromRGB(255, 214, 102)

function FourInARow.create(ctx: any)
	local snapshot: any = nil

	local function myTurn(): boolean
		return snapshot ~= nil and table.find(snapshot.activeSeats, snapshot.yourSeat) ~= nil
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

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			ctx.clearMarks()
			if not myTurn() then
				closePicker()
			end
			if myTurn() then
				for _, column in ctx.cells:GetChildren() do
					local c = column:GetAttribute("Col")
					if c and snapshot.view.heights[c] < Rules.rows and column:IsA("BasePart") then
						-- A small ball just above the frame. The click part reaches one cell
						-- above the top row, so its top minus half a cell is right there.
						local cell = column.Size.X
						local top = Instance.new("Part")
						top.Size = Vector3.one * (cell * 0.4)
						top.CFrame = column.CFrame * CFrame.new(0, column.Size.Y / 2 - cell * 0.5, 0)
						ctx.mark(top, MARK, "ball")
						top:Destroy()
					end
				end
			end
		end,
		click = function(column: BasePart)
			local c = column:GetAttribute("Col")
			if not (c and myTurn()) then
				return
			end
			local canDrop = snapshot.view.heights[c] < Rules.rows
			local canPop = Rules.canPop(snapshot.view, snapshot.yourSeat, c)
			if canDrop and canPop then
				openPicker(c)
			elseif canPop then
				ctx.sendMove({ column = c, pop = true })
			elseif canDrop then
				ctx.sendMove({ column = c })
			end
		end,
	}
end

return FourInARow
