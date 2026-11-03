-- 3D Tic-Tac-Toe: a 3x3 board with chunky X and O marks in each seat's color.
-- Cells are numbered 1..9 left to right, top (far side for seat 1) to bottom.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local TableLayout = require(ReplicatedStorage.Shared.TableLayout)
local Pieces = require(script.Parent.Parent.Pieces)
local Square = require(script.Parent.Square)

local TicTacToe = {}

local SEAT_COLORS = { Color3.fromRGB(255, 99, 132), Color3.fromRGB(54, 162, 235) }
local WIN = Color3.fromRGB(255, 196, 64)

local function mark(seat: number, surface: CFrame, cellSize: number): Instance
	local model = Instance.new("Model")
	model.Name = if seat == 1 then "X" else "O"
	local color = SEAT_COLORS[seat]
	if seat == 1 then
		for _, angle in { 45, -45 } do
			Pieces.part({
				Size = Vector3.new(cellSize * 0.8, cellSize * 0.18, cellSize * 0.18),
				CFrame = surface * CFrame.new(0, cellSize * 0.09, 0) * CFrame.Angles(0, math.rad(angle), 0),
				Color = color,
				CanQuery = false,
				Parent = model,
			})
		end
	else
		local ring = 12
		for i = 1, ring do
			local a = (i / ring) * math.pi * 2
			local radius = cellSize * 0.3
			Pieces.part({
				Size = Vector3.new(cellSize * 0.18, cellSize * 0.18, radius * 2 * math.pi / ring + 0.05),
				CFrame = surface * CFrame.new(math.cos(a) * radius, cellSize * 0.09, math.sin(a) * radius) * CFrame.Angles(0, -a, 0),
				Color = color,
				CanQuery = false,
				Parent = model,
			})
		end
	end
	return model
end

local function rowCol(cell: number): (number, number)
	return (cell - 1) // 3 + 1, (cell - 1) % 3 + 1
end

function TicTacToe.create(boardCF: CFrame, parent: Instance)
	local size = Config.BoardSize * 0.75
	local board = Square.create(boardCF, parent, 3, size, function(r, c)
		return TableLayout.gridCell(r, c, 3, size / 3)
	end, function(r, c)
		return if (r + c) % 2 == 0 then Color3.fromRGB(240, 232, 214) else Color3.fromRGB(222, 210, 186)
	end, Color3.fromRGB(70, 46, 32))
	local shown: { [number]: Instance } = {}
	local shownSeat: { [number]: number } = {}

	return {
		model = board.model,
		update = function(view: any)
			for i = 1, 9 do
				local seat = view.board[i]
				if shownSeat[i] ~= seat then
					shownSeat[i] = seat
					if shown[i] then
						shown[i]:Destroy()
						shown[i] = nil
					end
					if seat ~= 0 then
						local r, c = rowCol(i)
						local m = mark(seat, board.surface(r, c), board.cellSize)
						m.Parent = board.pieces
						shown[i] = m
					end
				end
			end
			local tints = {}
			for _, i in view.winningLine or {} do
				local r, c = rowCol(i)
				tints[r * 100 + c] = WIN
			end
			Square.tint(board, 3, tints)
		end,
		destroy = function()
			board.model:Destroy()
		end,
	}
end

return TicTacToe
