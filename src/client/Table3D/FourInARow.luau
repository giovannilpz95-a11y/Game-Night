-- Tap any column of the 3D Four in a Row frame to drop a disc there. On your turn the
-- open columns get a marker on top.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.Shared.Games.FourInARow)

local FourInARow = {}

local MARK = Color3.fromRGB(255, 214, 102)

function FourInARow.create(ctx: any)
	local snapshot: any = nil

	local function myTurn(): boolean
		return snapshot ~= nil and table.find(snapshot.activeSeats, snapshot.yourSeat) ~= nil
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			ctx.clearMarks()
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
			if c and myTurn() and snapshot.view.heights[c] < Rules.rows then
				ctx.sendMove({ column = c })
			end
		end,
	}
end

return FourInARow
