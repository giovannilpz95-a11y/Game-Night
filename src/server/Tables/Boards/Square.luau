-- A square board of clickable cells on the table, shared by Chess, Checkers and
-- Tic-Tac-Toe. Each cell is a part in the board's "Cells" folder with Row and Col
-- attributes; the client raycasts against that folder to know which cell was tapped.

local Models = require(script.Parent.Parent.Models)
local Pieces = require(script.Parent.Parent.Pieces)

local Square = {}

export type Board = {
	model: Model,
	cellSize: number,
	-- World CFrame of the top surface center of a cell (Y up), for standing pieces on it.
	surface: (row: number, col: number) -> CFrame,
	cell: (row: number, col: number) -> Part,
	pieces: Folder,
}

-- `position(row, col)` returns the cell's x, z in board space (see Shared/TableLayout).
-- `color(row, col)` returns its base color.
function Square.create(boardCF: CFrame, parent: Instance, size: number, boardSize: number, position: (number, number) -> (number, number), color: (number, number) -> Color3, frameColor: Color3): Board
	local cellSize = boardSize / size
	local model = Instance.new("Model")
	model.Name = "GameBoard"

	Pieces.part({
		Name = "Frame",
		Size = Vector3.new(boardSize + 0.6, 0.3, boardSize + 0.6),
		CFrame = boardCF * CFrame.new(0, 0.15, 0),
		Color = frameColor,
		Material = Enum.Material.Wood,
		CanQuery = false,
		Parent = model,
	})
	-- A darker plinth under the frame and a lip on top read as a beveled edge.
	Models.block(model, "Plinth", Vector3.new(boardSize + 0.78, 0.08, boardSize + 0.78), boardCF * CFrame.new(0, 0.04, 0), frameColor:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.Wood)
	Models.block(model, "Lip", Vector3.new(boardSize + 0.46, 0.02, boardSize + 0.46), boardCF * CFrame.new(0, 0.3, 0), frameColor:Lerp(Color3.new(1, 1, 1), 0.08), Enum.Material.Wood)
	-- A gold inlay around the squares and brass studs on the corners.
	-- Each stands at least 0.016 over the face under it, so no two faces fight (flicker).
	local inlay = boardSize + 0.14
	local inlayTop, studTop = 0.326, 0.342
	for _, s in { -1, 1 } do
		Models.block(model, "Inlay", Vector3.new(inlay, inlayTop - 0.3, 0.05), boardCF * CFrame.new(0, (inlayTop + 0.3) / 2, s * inlay / 2), Models.GOLD)
		Models.block(model, "Inlay", Vector3.new(0.05, inlayTop - 0.3, inlay), boardCF * CFrame.new(s * inlay / 2, (inlayTop + 0.3) / 2, 0), Models.GOLD)
		for _, t in { -1, 1 } do
			Models.cyl(model, "Stud", 0.2, studTop - 0.3, boardCF * CFrame.new(s * (boardSize / 2 + 0.17), 0.3, t * (boardSize / 2 + 0.17)), Models.GOLD)
		end
	end

	local cellsFolder = Instance.new("Folder")
	cellsFolder.Name = "Cells"
	cellsFolder.Parent = model
	local pieces = Instance.new("Folder")
	pieces.Name = "Pieces"
	pieces.Parent = model

	local cells: { [number]: Part } = {}
	local tops: { [number]: CFrame } = {}
	for r = 1, size do
		for c = 1, size do
			local x, z = position(r, c)
			local cf = boardCF * CFrame.new(x, 0.35, z)
			local cell = Pieces.part({
				Name = `Cell_{r}_{c}`,
				Size = Vector3.new(cellSize, 0.1, cellSize),
				CFrame = cf,
				Color = color(r, c),
				Material = Enum.Material.Wood,
				CanQuery = true,
				Parent = cellsFolder,
			})
			cell:SetAttribute("Row", r)
			cell:SetAttribute("Col", c)
			cell:SetAttribute("BaseColor", cell.Color)
			cells[r * 100 + c] = cell
			tops[r * 100 + c] = cf * CFrame.new(0, 0.05, 0)
		end
	end
	model.Parent = parent

	return {
		model = model,
		cellSize = cellSize,
		surface = function(r, c)
			return tops[r * 100 + c]
		end,
		cell = function(r, c)
			return cells[r * 100 + c]
		end,
		pieces = pieces,
	}
end

-- Resets every cell to its base color, then tints the ones in `tints` ({ [key] = Color3 },
-- key = row * 100 + col).
function Square.tint(board: Board, size: number, tints: { [number]: Color3 })
	for r = 1, size do
		for c = 1, size do
			local cell = board.cell(r, c)
			local base = cell:GetAttribute("BaseColor") :: Color3
			local tint = tints[r * 100 + c]
			cell.Color = if tint then base:Lerp(tint, 0.6) else base
		end
	end
end

return Square
