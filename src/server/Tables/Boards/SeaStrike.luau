-- Sea Strike at the table: each player has the classic folding case. Lying flat in front
-- of them is their own ocean grid, with the enemy's pegs on it (white miss, red hit) and
-- any of their ships that have sunk. Standing up in the middle of the table, facing them,
-- is their target board with the pegs of every shot they've fired. The two target boards
-- stand back to back, so the players can't see each other's oceans over them.
-- The board only gets the spectator view: ships appear only once they sink (all of them
-- when the game ends).
--
-- No faces overlap: the water plate sits on top of the case base, pegs and hulls stand on
-- the water, and the two target boards are a gap apart.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.Shared.Games.SeaStrike)
local Models = require(script.Parent.Parent.Models)
local Scene = require(script.Parent.Parent.Scene)

local SeaStrike = {}

local CASE = Color3.fromRGB(72, 84, 104)
local WATER = Color3.fromRGB(40, 110, 170)
local PANEL = Color3.fromRGB(28, 60, 98)
local HULL = Color3.fromRGB(130, 136, 146)
local HULL_SUNK = Color3.fromRGB(70, 70, 76)
local MISS = Color3.fromRGB(245, 245, 245)
local HIT = Color3.fromRGB(220, 40, 40)
local LAST = Color3.fromRGB(255, 214, 102)

local OCEAN_CELL = 0.22
local TARGET_CELL = 0.18
local OCEAN_D = 1.6 -- center of the ocean, studs from the table center toward the seat
local TARGET_D = 0.14 -- target board, studs from the center (two of them back to back)
local BASE_H = 0.06
local WATER_H = 0.02
local PANEL_T = 0.06

-- A frame at `distance` from the center toward `seat`, -Z pointing at the center and +X
-- to the seat's right (same convention as Scene.seatSpot).
local function frameFor(boardCF: CFrame, layout: Scene.Layout, seat: number, distance: number): CFrame?
	local info = layout.seats[seat]
	if not info then
		return nil
	end
	local pos = (boardCF * CFrame.new(info.dir * distance)).Position
	return CFrame.lookAt(pos, boardCF.Position, boardCF.UpVector)
end

local function oceanCell(f: CFrame, n: number, row: number, col: number): CFrame
	local half = (n + 1) / 2
	return f * CFrame.new((col - half) * OCEAN_CELL, BASE_H + WATER_H, (row - half) * OCEAN_CELL)
end

local function targetCell(f: CFrame, n: number, row: number, col: number, top: number): CFrame
	local half = (n + 1) / 2
	return f * CFrame.new((col - half) * TARGET_CELL, top - (row - 0.5) * TARGET_CELL, PANEL_T / 2)
end

function SeaStrike.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	local model = Instance.new("Model")
	model.Name = "GameBoard"
	local live = Scene.dynamic(model)
	local memo = {}
	local built = 0

	local function buildCases(n: number)
		built = n
		for _, child in model:GetChildren() do
			if child ~= live then
				child:Destroy()
			end
		end
		for seat in layout.seats do
			local ocean = frameFor(boardCF, layout, seat, OCEAN_D)
			local target = frameFor(boardCF, layout, seat, TARGET_D)
			if not ocean or not target then
				continue
			end
			local span = n * OCEAN_CELL
			Models.block(model, "CaseBase", Vector3.new(span + 0.24, BASE_H, span + 0.24), ocean * CFrame.new(0, BASE_H / 2, 0), CASE)
			local water = Models.block(model, "Water", Vector3.new(span, WATER_H, span), ocean * CFrame.new(0, BASE_H + WATER_H / 2, 0), WATER, Enum.Material.Glass)
			-- Your own ocean in Table view: place your fleet on it (renderer "ocean:<seat>";
			-- uv X runs along columns, Z along rows toward the seat).
			Scene.tappable(water, `ocean:{seat}`)
			-- Target board standing up, its grid side facing the seat (+Z).
			local tspan = n * TARGET_CELL
			local height = tspan + 0.2
			local targetBoard = Models.block(model, "TargetBoard", Vector3.new(tspan + 0.2, height, PANEL_T), target * CFrame.new(0, height / 2, 0), PANEL)
			-- Tap it in Table view to fire (renderer tapTable "target:<seat>"). The grid sits
			-- TapMargin (a share of the board's width and height) in from each edge.
			Scene.tappable(targetBoard, `target:{seat}`)
			targetBoard:SetAttribute("TapMargin", 0.1 / height)
			Models.block(model, "TargetFoot", Vector3.new(tspan + 0.3, 0.05, 0.16), target * CFrame.new(0, 0.025, 0.13), CASE)
			-- Faint grid lines on the target board: thin strips just in front of its face.
			for i = 0, n do
				local x = (i - n / 2) * TARGET_CELL
				Models.block(model, "GridV", Vector3.new(0.012, tspan, 0.004), target * CFrame.new(x, 0.1 + tspan / 2, PANEL_T / 2 + 0.026), WATER)
				local y = 0.1 + i * TARGET_CELL
				Models.block(model, "GridH", Vector3.new(tspan, 0.012, 0.004), target * CFrame.new(0, y, PANEL_T / 2 + 0.012), WATER)
			end
		end
	end

	model.Parent = parent
	return {
		model = model,
		update = function(view: any, _snapshot: any)
			if type(view) ~= "table" or type(view.boards) ~= "table" then
				return
			end
			local n = view.size or 10
			if built ~= n then
				buildCases(n)
			end
			if not Scene.changed(memo, view) then
				return
			end
			local last = view.lastShot
			Scene.redraw(live, function(folder)
				for seat, board in view.boards do
					local ocean = frameFor(boardCF, layout, seat, OCEAN_D)
					local target = frameFor(boardCF, layout, seat, TARGET_D)
					if not ocean or not target then
						continue
					end
					-- Ships on this seat's ocean (sunk ones, or all at the end).
					local hullTop: { [number]: number } = {}
					for _, ship in board.ships or {} do
						for _, c in Rules.cellsOf(ship) do
							hullTop[(c[1] - 1) * n + c[2]] = 0.12
						end
						local first = oceanCell(ocean, n, ship.row, ship.col)
						local lastCell = Rules.cellsOf(ship)[ship.len]
						local finish = oceanCell(ocean, n, lastCell[1], lastCell[2])
						local mid = first:Lerp(finish, 0.5)
						local long = ship.len * OCEAN_CELL - 0.05
						local size = if ship.dir == "h" then Vector3.new(long, 0.12, OCEAN_CELL * 0.7) else Vector3.new(OCEAN_CELL * 0.7, 0.12, long)
						Models.block(folder, "Hull", size, mid * CFrame.new(0, 0.06, 0), if ship.sunk then HULL_SUNK else HULL)
					end
					-- Pegs the enemy put on this ocean.
					for i, code in board.shotsAt do
						if code ~= 0 then
							local row, col = (i - 1) // n + 1, (i - 1) % n + 1
							local cf = oceanCell(ocean, n, row, col) * CFrame.new(0, hullTop[i] or 0, 0)
							Models.cyl(folder, "Peg", 0.1, 0.12, cf, if code == Rules.MISS then MISS else HIT)
							if last and last.seat ~= seat and last.row == row and last.col == col then
								Models.cyl(folder, "LastShot", 0.2, 0.02, cf, LAST, Enum.Material.Neon)
							end
						end
					end
					-- This seat's own shots, on its target board.
					local mine = view.boards[3 - seat]
					local top = 0.1 + n * TARGET_CELL
					for i, code in (mine and mine.shotsAt) or {} do
						if code ~= 0 then
							local row, col = (i - 1) // n + 1, (i - 1) % n + 1
							Models.ball(folder, "Peg", if code == Rules.MISS then 0.08 else 0.11, targetCell(target, n, row, col, top) * CFrame.new(0, 0, 0.05), if code == Rules.MISS then MISS else HIT)
						end
					end
				end
			end)
		end,
		destroy = function()
			model:Destroy()
		end,
	}
end

return SeaStrike
