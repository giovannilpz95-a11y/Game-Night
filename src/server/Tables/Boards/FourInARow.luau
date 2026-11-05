-- 3D Four in a Row: an upright frame standing across the table, so the two players see
-- it from opposite sides. Discs are Assets.FourInARow.Disc_<seat>, turned face-on.
-- Each column is one invisible clickable part with a Col attribute.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local TableLayout = require(ReplicatedStorage.Shared.TableLayout)
local Rules = require(ReplicatedStorage.Shared.Games.FourInARow)
local Pieces = require(script.Parent.Parent.Pieces)

local FourInARow = {}

local COLS, ROWS = Rules.columns, Rules.rows
local FRAME_COLOR = Color3.fromRGB(150, 102, 62)
local SEAT_COLORS = { Color3.fromRGB(255, 99, 132), Color3.fromRGB(255, 206, 86) }
local WIN = Color3.fromRGB(255, 255, 255)
local BASE_HEIGHT = 0.6

function FourInARow.create(boardCF: CFrame, parent: Instance)
	local cellSize = Config.BoardSize * 0.85 / COLS
	local width = COLS * cellSize
	local height = ROWS * cellSize
	local depth = cellSize * 0.5
	local model = Instance.new("Model")
	model.Name = "GameBoard"

	-- Feet and base
	Pieces.part({
		Name = "Base",
		Size = Vector3.new(width + 1.2, BASE_HEIGHT, depth * 3),
		CFrame = boardCF * CFrame.new(0, BASE_HEIGHT / 2, 0),
		Color = FRAME_COLOR:Lerp(Color3.new(0, 0, 0), 0.25),
		CanQuery = false,
		Parent = model,
	})
	-- Lattice: posts between columns, bars between rows (leaves the holes open).
	for c = 0, COLS do
		local x = (c - COLS / 2) * cellSize
		Pieces.part({
			Name = "Post",
			Size = Vector3.new(cellSize * 0.14, height + 0.1, depth),
			CFrame = boardCF * CFrame.new(x, BASE_HEIGHT + height / 2, 0),
			Color = FRAME_COLOR,
			CanQuery = false,
			Parent = model,
		})
	end
	for r = 0, ROWS - 1 do
		Pieces.part({
			Name = "Bar",
			Size = Vector3.new(width, cellSize * 0.12, depth),
			CFrame = boardCF * CFrame.new(0, BASE_HEIGHT + r * cellSize + cellSize * 0.06, 0),
			Color = FRAME_COLOR,
			CanQuery = false,
			Parent = model,
		})
	end

	local cells = Instance.new("Folder")
	cells.Name = "Cells"
	cells.Parent = model
	for c = 1, COLS do
		local x = TableLayout.fourCell(c, 1, COLS, cellSize)
		local column = Pieces.part({
			Name = `Column_{c}`,
			Size = Vector3.new(cellSize, height + cellSize, depth * 2),
			CFrame = boardCF * CFrame.new(x, BASE_HEIGHT + (height + cellSize) / 2, 0),
			Transparency = 1,
			CanQuery = true,
			Parent = cells,
		})
		column:SetAttribute("Col", c)
	end

	local pieces = Instance.new("Folder")
	pieces.Name = "Pieces"
	pieces.Parent = model
	-- Each seat's disc color, for the ghost disc the client floats over a hovered column.
	for seat, color in SEAT_COLORS do
		model:SetAttribute(`SeatColor{seat}`, color)
	end
	model.Parent = parent

	local discSize = cellSize * 0.82
	local function holeCF(c: number, r: number): CFrame
		local x, y = TableLayout.fourCell(c, r, COLS, cellSize)
		return boardCF * CFrame.new(x, BASE_HEIGHT + y, 0)
	end

	local function makeDisc(seat: number, at: CFrame): Instance
		local template = Pieces.find("FourInARow", `Disc_{seat}`)
		if template then
			local _, size = template:GetBoundingBox()
			local factor = discSize / math.max(size.X, size.Y, size.Z)
			return Pieces.place(template, factor, at, Pieces.faceOnRotation(size))
		end
		return Pieces.part({
			Name = `Disc_{seat}`,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(depth * 0.8, discSize, discSize),
			CFrame = at * CFrame.Angles(0, math.rad(90), 0),
			Color = SEAT_COLORS[seat],
			CanQuery = false,
		})
	end

	local shown: { [number]: Instance } = {}
	local shownValue: { [number]: number } = {}
	local glow: { Instance } = {}

	return {
		model = model,
		update = function(view: any)
			for c = 1, COLS do
				for r = 1, ROWS do
					local key = c * 100 + r
					local v = view.grid[c][r]
					if shownValue[key] ~= v then
						shownValue[key] = v
						if shown[key] then
							shown[key]:Destroy()
							shown[key] = nil
						end
						if v ~= 0 then
							local final = holeCF(c, r)
							local disc = makeDisc(v, final)
							disc.Parent = pieces
							shown[key] = disc
							local last = view.lastMove
							if last and last.column == c and last.row == r then
								-- Drop in from above the frame.
								local start = holeCF(c, ROWS + 1)
								local offset = (disc :: any):GetPivot()
								local relative = final:ToObjectSpace(offset)
								;(disc :: any):PivotTo(start * relative)
								task.spawn(function()
									local steps = 8
									for i = 1, steps do
										if not disc.Parent then
											return
										end
										local t = (i / steps) ^ 2
										;(disc :: any):PivotTo(start:Lerp(final, t) * relative)
										task.wait(1 / 30)
									end
								end)
							end
						end
					end
				end
			end
			for _, g in glow do
				g:Destroy()
			end
			glow = {}
			for _, cell in view.winningCells or {} do
				local ring = Pieces.part({
					Name = "Win",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(depth * 1.1, discSize * 1.12, discSize * 1.12),
					CFrame = holeCF(cell[1], cell[2]) * CFrame.Angles(0, math.rad(90), 0),
					Color = WIN,
					Material = Enum.Material.Neon,
					Transparency = 0.55,
					CanQuery = false,
					Parent = pieces,
				})
				table.insert(glow, ring)
			end
		end,
		destroy = function()
			model:Destroy()
		end,
	}
end

return FourInARow
