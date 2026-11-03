-- 3D checkers board. board[row][col] as in Shared/Games/Checkers; seat 1 (Dark) sits on
-- the +Z side, nearest row 8. Pieces are Assets.Checkers.<Man|King>_<Dark|Light>.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local TableLayout = require(ReplicatedStorage.Shared.TableLayout)
local Pieces = require(script.Parent.Parent.Pieces)
local Square = require(script.Parent.Square)

local Checkers = {}

local LIGHT_SQUARE = Color3.fromRGB(236, 220, 192)
local DARK_SQUARE = Color3.fromRGB(96, 70, 56)
local LAST_MOVE = Color3.fromRGB(230, 190, 90)
local NAMES = { "Man_Dark", "Man_Light", "King_Dark", "King_Light" }

local function fallbackPiece(v: number, surface: CFrame, cellSize: number): Instance
	local dark = (v - 1) % 2 == 0
	local height = cellSize * (if v > 2 then 0.3 else 0.15)
	local width = cellSize * 0.75
	return Pieces.part({
		Name = NAMES[v],
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, width, width),
		CFrame = surface * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = if dark then Color3.fromRGB(200, 62, 72) else Color3.fromRGB(245, 236, 214),
		CanQuery = false,
	})
end

function Checkers.create(boardCF: CFrame, parent: Instance)
	local size = Config.BoardSize
	local board = Square.create(boardCF, parent, 8, size, function(r, c)
		return TableLayout.checkersCell(r, c, size / 8)
	end, function(r, c)
		return if (r + c) % 2 == 1 then DARK_SQUARE else LIGHT_SQUARE
	end, Color3.fromRGB(70, 46, 32))

	local factor = Pieces.setScale("Checkers", NAMES, board.cellSize * 0.8)
	local shown: { [number]: Instance } = {}
	local shownValue: { [number]: number } = {}

	return {
		model = board.model,
		update = function(view: any)
			for r = 1, 8 do
				for c = 1, 8 do
					local key = r * 100 + c
					local v = view.board[r][c]
					if shownValue[key] ~= v then
						shownValue[key] = v
						if shown[key] then
							shown[key]:Destroy()
							shown[key] = nil
						end
						if v ~= 0 then
							local template = Pieces.find("Checkers", NAMES[v])
							local piece = if template
								then Pieces.stand(template, factor, board.surface(r, c))
								else fallbackPiece(v, board.surface(r, c), board.cellSize)
							piece.Parent = board.pieces
							shown[key] = piece
						end
					end
				end
			end
			local tints = {}
			if view.lastMove then
				tints[view.lastMove.from[1] * 100 + view.lastMove.from[2]] = LAST_MOVE
				for _, sq in view.lastMove.path do
					tints[sq[1] * 100 + sq[2]] = LAST_MOVE
				end
			end
			Square.tint(board, 8, tints)
		end,
		destroy = function()
			board.model:Destroy()
		end,
	}
end

return Checkers
