-- Word Tiles at the table: the board with its premium squares, every tile laid so far,
-- and each player's rack of tiles (backs only) in front of them. Play stays in the 2D view.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.Shared.Games.WordTiles)
local Pieces = require(script.Parent.Parent.Pieces)
local Scene = require(script.Parent.Parent.Scene)

local WordTiles = {}

local SIZE = 5.8
local PREMIUM = {
	W = Color3.fromRGB(230, 96, 96), -- triple word
	w = Color3.fromRGB(240, 170, 170), -- double word
	L = Color3.fromRGB(70, 130, 210), -- triple letter
	l = Color3.fromRGB(160, 200, 240), -- double letter
	["*"] = Color3.fromRGB(240, 170, 170),
}
local SQUARE = Color3.fromRGB(214, 206, 180)
local TILE = Color3.fromRGB(244, 224, 176)

function WordTiles.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	local model = Instance.new("Model")
	model.Name = "GameBoard"
	Pieces.part({ Name = "Base", Size = Vector3.new(SIZE + 0.3, 0.2, SIZE + 0.3), CFrame = boardCF * CFrame.new(0, 0.1, 0), Color = Color3.fromRGB(60, 90, 70), CanQuery = false, Parent = model })
	local squares = Instance.new("Folder")
	squares.Name = "Squares"
	squares.Parent = model
	local dynamic = Scene.dynamic(model)
	model.Parent = parent
	local builtFor: string? = nil
	local size = 11

	local function cellCF(r: number, c: number, height: number): CFrame
		local cell = SIZE / size
		local mid = (size + 1) / 2
		return boardCF * CFrame.new((c - mid) * cell, height, (r - mid) * cell)
	end

	local function buildSquares(key: string)
		squares:ClearAllChildren()
		local def = Rules.boards[key] or Rules.boards.quick
		size = def.size
		local cell = SIZE / size
		for r = 1, size do
			for c = 1, size do
				local kind = def.premium[r] and def.premium[r][c] or "."
				Pieces.part({
					Name = "Square",
					Size = Vector3.new(cell * 0.92, 0.04, cell * 0.92),
					CFrame = cellCF(r, c, 0.22),
					Color = PREMIUM[kind] or SQUARE,
					CanQuery = false,
					Parent = squares,
				})
			end
		end
		builtFor = key
	end

	return {
		model = model,
		update = function(view: any, _snapshot: any)
			local key = view.board or "quick"
			if builtFor ~= key then
				buildSquares(key)
			end
			dynamic:ClearAllChildren()
			local cell = SIZE / size
			for r, row in view.rows or {} do
				for c = 1, #row do
					local ch = string.sub(row, c, c)
					if ch ~= "." then
						local tile = Pieces.part({
							Name = "Tile",
							Size = Vector3.new(cell * 0.86, 0.1, cell * 0.86),
							CFrame = cellCF(r, c, 0.29),
							Color = TILE,
							CanQuery = false,
							Parent = dynamic,
						})
						-- Blanks are stored in upper case: show them a little paler.
						local blank = ch == string.upper(ch) and ch ~= string.lower(ch)
						Scene.text(tile, Enum.NormalId.Top, string.upper(ch), { TextColor3 = if blank then Color3.fromRGB(150, 120, 90) else Color3.fromRGB(40, 30, 24) })
					end
				end
			end
			-- Racks: a wooden stand with the right number of tiles on it.
			for seat, count in view.rackCounts or {} do
				local spot = Scene.seatSpot(boardCF, layout, seat, 0.45)
				Pieces.part({ Name = "Rack", Size = Vector3.new(3.2, 0.25, 0.4), CFrame = spot * CFrame.new(0, 0.125, 0), Color = Color3.fromRGB(150, 104, 64), Material = Enum.Material.Wood, CanQuery = false, Parent = dynamic })
				for i = 1, count do
					Pieces.part({
						Name = "RackTile",
						Size = Vector3.new(0.38, 0.38, 0.08),
						CFrame = spot * CFrame.new((i - (count + 1) / 2) * 0.43, 0.44, 0.05) * CFrame.Angles(math.rad(-15), 0, 0),
						Color = TILE,
						CanQuery = false,
						Parent = dynamic,
					})
				end
			end
		end,
		destroy = function()
			model:Destroy()
		end,
	}
end

return WordTiles
