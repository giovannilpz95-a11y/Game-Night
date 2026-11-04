-- 3D chess board. Rows and cols follow the 2D renderer: row 1 is rank 8, col 1 is file a.
-- Pieces are Assets.Chess.<Piece>_<White|Black>, which already face the right way
-- (White faces -Z, toward Black).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local TableLayout = require(ReplicatedStorage.Shared.TableLayout)
local Pieces = require(script.Parent.Parent.Pieces)
local Square = require(script.Parent.Square)

local Chess = {}

local NAMES = { "Pawn", "Knight", "Bishop", "Rook", "Queen", "King" }
local LIGHT = Color3.fromRGB(240, 222, 190)
local DARK = Color3.fromRGB(150, 104, 72)
local LAST_MOVE = Color3.fromRGB(230, 200, 90)
local CHECK = Color3.fromRGB(235, 70, 70)

local ALL_NAMES = {}
for _, name in NAMES do
	table.insert(ALL_NAMES, `{name}_White`)
	table.insert(ALL_NAMES, `{name}_Black`)
end

-- row/col <-> square index (0 = a1), same as the 2D renderer.
local function squareOf(row: number, col: number): number
	return (8 - row) * 8 + (col - 1)
end

local function cellOfName(name: string): (number, number)
	local file = string.byte(name, 1) - string.byte("a")
	local rank = tonumber(string.sub(name, 2, 2)) :: number
	return 9 - rank, file + 1
end

local function fallbackPiece(kind: number, white: boolean, surface: CFrame, cellSize: number): Instance
	local height = ({ 0.55, 0.75, 0.8, 0.7, 0.95, 1.05 })[kind] * cellSize
	local width = cellSize * (if kind == 1 then 0.45 else 0.6)
	local part = Pieces.part({
		Name = NAMES[kind],
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, width, width),
		CFrame = surface * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = if white then Color3.fromRGB(250, 246, 236) else Color3.fromRGB(40, 36, 44),
		CanQuery = false,
	})
	return part
end

function Chess.create(boardCF: CFrame, parent: Instance)
	local size = Config.BoardSize
	local board = Square.create(boardCF, parent, 8, size, function(r, c)
		return TableLayout.chessCell(squareOf(r, c), size / 8)
	end, function(r, c)
		return if (r + c) % 2 == 0 then LIGHT else DARK
	end, Color3.fromRGB(70, 46, 32))

	local factor = Pieces.setScale("Chess", ALL_NAMES, board.cellSize * 0.8)
	local shown: { [number]: Instance } = {}
	local shownCode: { [number]: number } = {}

	return {
		model = board.model,
		update = function(view: any)
			for r = 1, 8 do
				for c = 1, 8 do
					local sq = squareOf(r, c)
					local code = view.board[sq + 1]
					if shownCode[sq] ~= code then
						shownCode[sq] = code
						if shown[sq] then
							shown[sq]:Destroy()
							shown[sq] = nil
						end
						if code ~= 0 then
							local kind, white = math.abs(code), code > 0
							local template = Pieces.find("Chess", `{NAMES[kind]}_{if white then "White" else "Black"}`)
							local piece = if template
								then Pieces.stand(template, factor, board.surface(r, c))
								else fallbackPiece(kind, white, board.surface(r, c), board.cellSize)
							piece.Parent = board.pieces
							shown[sq] = piece
						end
					end
				end
			end
			local tints = {}
			local last = view.lastMove
			if last then
				for _, name in { last.from, last.to } do
					local r, c = cellOfName(name)
					tints[r * 100 + c] = LAST_MOVE
				end
			end
			if view.inCheck and view.kingSquare then
				local r, c = cellOfName(view.kingSquare)
				tints[r * 100 + c] = CHECK
			end
			Square.tint(board, 8, tints)
		end,
		destroy = function()
			board.model:Destroy()
		end,
	}
end

return Chess
