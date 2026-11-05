-- Tap any column of the 3D Four in a Row frame to drop a disc there. On your turn the
-- open columns get a marker on top, and a see-through ghost of your disc shows where it
-- would land in the column under the mouse.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.Shared.Games.FourInARow)

local FourInARow = {}

local MARK = Color3.fromRGB(255, 214, 102)
local SEAT_COLORS = { Color3.fromRGB(255, 99, 132), Color3.fromRGB(255, 206, 86) } -- as Boards/FourInARow

function FourInARow.create(ctx: any)
	local snapshot: any = nil
	local ghost: Part? = nil
	local over: BasePart? = nil

	local function myTurn(): boolean
		return snapshot ~= nil and table.find(snapshot.activeSeats, snapshot.yourSeat) ~= nil
	end

	local function showGhost()
		local column = over
		local c = column and column:GetAttribute("Col")
		if not (column and c and myTurn() and snapshot.view.heights[c] < Rules.rows) then
			if ghost then
				ghost:Destroy()
				ghost = nil
			end
			return
		end
		if not ghost or not ghost.Parent then
			local part = Instance.new("Part")
			part.Name = "GhostDisc"
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Shape = Enum.PartType.Cylinder
			part.Material = Enum.Material.SmoothPlastic
			part.Transparency = 0.55
			ctx.addLocal(part)
			ghost = part
		end
		local g = ghost :: Part
		local cell = column.Size.X
		g.Color = SEAT_COLORS[snapshot.yourSeat] or MARK
		g.Size = Vector3.new(column.Size.Z * 0.7, cell * 0.84, cell * 0.84)
		-- The click part runs from the bottom row to one cell above the top one.
		local y = -column.Size.Y / 2 + (snapshot.view.heights[c] + 0.5) * cell
		g.CFrame = column.CFrame * CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(90), 0)
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			ctx.clearMarks()
			ghost = nil
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
			showGhost()
		end,
		hover = function(part: Instance?)
			over = if part and part:IsA("BasePart") and part:GetAttribute("Col") then part else nil
			showGhost()
		end,
		click = function(column: BasePart)
			local c = column:GetAttribute("Col")
			if c and myTurn() and snapshot.view.heights[c] < Rules.rows then
				ctx.sendMove({ column = c })
			end
		end,
	}
end

return FourInARow
