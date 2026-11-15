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

-- Grid coordinates like the paper game: rows A-J down the side, columns 1-10 along the top.
local LABEL = Color3.fromRGB(235, 240, 255)
local function rowLetter(r: number): string
	return string.sub("ABCDEFGHIJ", r, r)
end

local function textLabel(parent: Instance, text: string, position: UDim2, size: UDim2)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = position
	t.Size = size
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.Text = text
	t.TextColor3 = LABEL
	t.Parent = parent
end

-- Letters and numbers on the margin of a standing target board (its +Z face).
local function labelTarget(board: BasePart, n: number)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Coordinates"
	gui.Face = Enum.NormalId.Back -- +Z, the side facing the seat
	gui.LightInfluence = 0.2
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 400
	gui.Parent = board
	local w, h = board.Size.X, board.Size.Y
	local margin = (w - n * TARGET_CELL) / 2
	local cell = UDim2.fromScale(margin * 0.9 / w, margin * 0.9 / h)
	for i = 1, n do
		textLabel(gui, tostring(i), UDim2.fromScale((margin + (i - 0.5) * TARGET_CELL) / w, margin / 2 / h), cell)
		textLabel(gui, rowLetter(i), UDim2.fromScale(margin / 2 / w, (margin + (i - 0.5) * TARGET_CELL) / h), cell)
	end
end

-- The same on the flat case around your own ocean, reading upright from your seat.
local function labelOcean(model: Instance, ocean: CFrame, n: number)
	local half = (n + 1) / 2
	local edge = n * OCEAN_CELL / 2 + 0.06
	local function label(text: string, x: number, z: number)
		local part = Instance.new("Part")
		part.Name = "Coord_" .. text
		part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
		part.Transparency = 1
		part.Size = Vector3.new(0.11, 0.01, 0.11)
		part.CFrame = ocean * CFrame.new(x, BASE_H + 0.006, z) -- -Z away from the seat: upright for them
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.LightInfluence = 0.2
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 400
		gui.Parent = part
		textLabel(gui, text, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1))
		part.Parent = model
	end
	for i = 1, n do
		label(tostring(i), (i - half) * OCEAN_CELL, -edge)
		label(rowLetter(i), -edge, (i - half) * OCEAN_CELL)
	end
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
			labelOcean(model, ocean, n)
			-- Target board standing up, its grid side facing the seat (+Z).
			local tspan = n * TARGET_CELL
			local height = tspan + 0.2
			local targetBoard = Models.block(model, "TargetBoard", Vector3.new(tspan + 0.2, height, PANEL_T), target * CFrame.new(0, height / 2, 0), PANEL)
			-- Tap it in Table view to fire (renderer tapTable "target:<seat>"). The grid sits
			-- TapMargin (a share of the board's width and height) in from each edge.
			Scene.tappable(targetBoard, `target:{seat}`)
			targetBoard:SetAttribute("TapMargin", 0.1 / height)
			labelTarget(targetBoard, n)
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
			-- The latest shots get a glowing ring: the last one, or the whole last salvo.
			local recent: { [string]: boolean } = {}
			for _, shot in (view.lastSalvo or { view.lastShot }) do
				if type(shot) == "table" then
					recent[`{shot.seat}:{shot.row}:{shot.col}`] = true
				end
			end
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
					-- WATER (squares known empty next to a sunk ship) was never fired at: no peg.
					for i, code in board.shotsAt do
						if code ~= 0 and code ~= Rules.WATER then
							local row, col = (i - 1) // n + 1, (i - 1) % n + 1
							local cf = oceanCell(ocean, n, row, col) * CFrame.new(0, hullTop[i] or 0, 0)
							Models.cyl(folder, "Peg", 0.1, 0.12, cf, if code == Rules.MISS then MISS else HIT)
							if recent[`{3 - seat}:{row}:{col}`] then
								Models.cyl(folder, "LastShot", 0.2, 0.02, cf, LAST, Enum.Material.Neon)
							end
						end
					end
					-- This seat's own shots, on its target board.
					local mine = view.boards[3 - seat]
					local top = 0.1 + n * TARGET_CELL
					-- Ships you've sunk get a dark strip under their pegs, like the apps'
					-- greyed-out wrecks.
					for _, ship in (mine and mine.ships) or {} do
						if ship.sunk then
							local cells = Rules.cellsOf(ship)
							local a = targetCell(target, n, cells[1][1], cells[1][2], top)
							local b = targetCell(target, n, cells[#cells][1], cells[#cells][2], top)
							local long = ship.len * TARGET_CELL - 0.03
							local size = if ship.dir == "h" then Vector3.new(long, TARGET_CELL * 0.7, 0.004) else Vector3.new(TARGET_CELL * 0.7, long, 0.004)
							Models.block(folder, "SunkStrip", size, a:Lerp(b, 0.5) * CFrame.new(0, 0, 0.037), HULL_SUNK) -- in front of the grid lines, clear of every face
						end
					end
					for i, code in (mine and mine.shotsAt) or {} do
						if code ~= 0 then
							local row, col = (i - 1) // n + 1, (i - 1) % n + 1
							local size = if code == Rules.WATER then 0.035 elseif code == Rules.MISS then 0.08 else 0.11
							Models.ball(folder, "Peg", size, targetCell(target, n, row, col, top) * CFrame.new(0, 0, 0.05), if code == Rules.MISS or code == Rules.WATER then MISS else HIT)
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
