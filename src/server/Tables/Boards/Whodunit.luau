-- Whodunit at the table: the mansion's nine rooms as a 3x3 board, each suspect's pawn
-- in its room (seat N plays suspect N, in that seat's color) and the items as small
-- tokens. The case file sits in the middle, sealed. Play stays in the 2D view.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.Shared.Games.Whodunit)
local Pieces = require(script.Parent.Parent.Pieces)
local Scene = require(script.Parent.Parent.Scene)

local Whodunit = {}

local SIZE = 6.6
local CELL = SIZE / 3
local FLOORS = {
	Color3.fromRGB(230, 214, 186),
	Color3.fromRGB(206, 188, 220),
	Color3.fromRGB(190, 210, 232),
	Color3.fromRGB(196, 226, 190),
	Color3.fromRGB(236, 206, 170),
	Color3.fromRGB(240, 196, 206),
	Color3.fromRGB(180, 222, 226),
	Color3.fromRGB(210, 206, 196),
	Color3.fromRGB(224, 204, 176),
}
local ITEM_COLOR = Color3.fromRGB(240, 200, 70)

local function roomCF(boardCF: CFrame, room: number, height: number): CFrame
	local r, c = (room - 1) // 3, (room - 1) % 3
	return boardCF * CFrame.new((c - 1) * CELL, height, (r - 1) * CELL)
end

function Whodunit.create(boardCF: CFrame, parent: Instance, _layout: Scene.Layout)
	local model = Instance.new("Model")
	model.Name = "GameBoard"
	Pieces.part({ Name = "Base", Size = Vector3.new(SIZE + 0.3, 0.2, SIZE + 0.3), CFrame = boardCF * CFrame.new(0, 0.1, 0), Color = Color3.fromRGB(90, 64, 48), Material = Enum.Material.Wood, CanQuery = false, Parent = model })
	for room, name in Rules.theme.rooms do
		local floor = Pieces.part({
			Name = name,
			Size = Vector3.new(CELL * 0.94, 0.05, CELL * 0.94),
			CFrame = roomCF(boardCF, room, 0.225),
			Color = FLOORS[room] or Color3.new(1, 1, 1),
			CanQuery = false,
			Parent = model,
		})
		-- Room name along the far edge, so pawns don't cover it.
		local strip = Pieces.part({ Name = "Name", Size = Vector3.new(CELL * 0.9, 0.01, CELL * 0.22), CFrame = roomCF(boardCF, room, 0.26) * CFrame.new(0, 0, -CELL * 0.33), Transparency = 1, CanQuery = false, Parent = model })
		Scene.text(strip, Enum.NormalId.Top, name, { TextColor3 = Color3.fromRGB(60, 44, 34) })
		floor.Name = name
	end
	local dynamic = Scene.dynamic(model)
	model.Parent = parent

	return {
		model = model,
		update = function(view: any, snapshot: any)
			dynamic:ClearAllChildren()
			-- Group by room so pawns stand side by side.
			local seatCount = view.seatCount or (snapshot and #snapshot.seats) or #Rules.theme.suspects
			local inRoom: { [number]: number } = {}
			for suspect, room in view.suspectRoom or {} do
				local k = inRoom[room] or 0
				inRoom[room] = k + 1
				local cf = roomCF(boardCF, room, 0.25) * CFrame.new(((k % 3) - 1) * CELL * 0.26, 0, (k // 3) * CELL * 0.26)
				local color = if suspect <= seatCount then (Scene.SEAT_COLORS[suspect] or Color3.new(1, 1, 1)) else Color3.fromRGB(150, 150, 150)
				Scene.pawn(dynamic, cf, color, 0.65)
			end
			local itemsIn: { [number]: number } = {}
			for _, room in view.itemRoom or {} do
				local k = itemsIn[room] or 0
				itemsIn[room] = k + 1
				Pieces.part({
					Name = "Item",
					Size = Vector3.new(0.2, 0.2, 0.2),
					CFrame = roomCF(boardCF, room, 0.35) * CFrame.new((k - 2.5) * 0.25, 0, CELL * 0.36) * CFrame.Angles(0, math.rad(45), 0),
					Color = ITEM_COLOR,
					Material = Enum.Material.Neon,
					CanQuery = false,
					Parent = dynamic,
				})
			end
			-- The sealed case file (opens at the end).
			local solved = view.solution ~= nil
			local file = Pieces.part({ Name = "CaseFile", Size = Vector3.new(0.9, 0.06, 0.65), CFrame = boardCF * CFrame.new(SIZE / 2 + 0.6, 0.06, 0), Color = if solved then Color3.fromRGB(240, 230, 200) else Color3.fromRGB(150, 40, 40), CanQuery = false, Parent = dynamic })
			Scene.text(file, Enum.NormalId.Top, if solved then "Solved!" else "CASE", { TextColor3 = if solved then Color3.fromRGB(40, 30, 24) else Color3.new(1, 1, 1) })
		end,
		destroy = function()
			model:Destroy()
		end,
	}
end

return Whodunit
