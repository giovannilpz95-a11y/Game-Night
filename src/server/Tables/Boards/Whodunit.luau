-- Whodunit at the table: the mansion's nine rooms as a 3x3 board with low walls and
-- furniture, each suspect's pawn with its own hat (seat N plays suspect N, in that seat's
-- color) and the six silly items as minis. The case file sits beside the board, sealed.
-- Play stays in the 2D view.
--
-- Rooms and items are matched by position in Rules.theme, so a re-themed mansion keeps
-- working: the scenery just stops matching the new names until it's redrawn.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.Shared.Games.Whodunit)
local Models = require(script.Parent.Parent.Models)
local Scene = require(script.Parent.Parent.Scene)

local Whodunit = {}

local SIZE = 6.6
local CELL = SIZE / 3
local FLOOR_Y = 0.25
local WALL = Color3.fromRGB(120, 88, 66)
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

local function roomCF(boardCF: CFrame, room: number, height: number): CFrame
	local r, c = (room - 1) // 3, (room - 1) % 3
	return boardCF * CFrame.new((c - 1) * CELL, height, (r - 1) * CELL)
end

-- Furniture for each room, in Rules.theme.rooms order. `cf` is the room's far-left corner
-- area on the floor, kept clear of the pawns in the middle.
local FURNITURE: { (m: Instance, cf: CFrame) -> () } = {
	function(m, cf) -- Kitchen: stove and counter
		Models.block(m, "Counter", Vector3.new(1, 0.26, 0.3), cf * CFrame.new(0.2, 0.13, 0), Color3.fromRGB(240, 240, 235))
		Models.block(m, "Stove", Vector3.new(0.34, 0.3, 0.32), cf * CFrame.new(-0.2, 0.15, 0), Models.INK)
		Models.cyl(m, "Pot", 0.2, 0.12, cf * CFrame.new(-0.2, 0.3, 0), Color3.fromRGB(210, 80, 70))
	end,
	function(m, cf) -- Music Room: piano
		Models.block(m, "Piano", Vector3.new(0.8, 0.4, 0.3), cf * CFrame.new(0, 0.2, 0), Models.INK)
		Models.block(m, "Keys", Vector3.new(0.72, 0.03, 0.12), cf * CFrame.new(0, 0.3, 0.2), Models.IVORY)
		Models.block(m, "Bench", Vector3.new(0.4, 0.14, 0.14), cf * CFrame.new(0, 0.07, 0.4), Models.WALNUT)
	end,
	function(m, cf) -- Observatory: telescope
		Models.cyl(m, "Mount", 0.34, 0.12, cf, Models.STEEL)
		Models.block(m, "Tube", Vector3.new(0.16, 0.16, 0.8), cf * CFrame.new(0, 0.34, 0) * CFrame.Angles(math.rad(40), 0, 0), Models.GOLD)
		Models.block(m, "Leg", Vector3.new(0.05, 0.28, 0.05), cf * CFrame.new(0, 0.2, 0), Models.WALNUT)
	end,
	function(m, cf) -- Greenhouse: planters
		for i = -1, 1 do
			local pot = cf * CFrame.new(i * 0.36, 0, 0)
			Models.cyl(m, "Pot", 0.24, 0.16, pot, Color3.fromRGB(190, 110, 70))
			Models.egg(m, "Plant", Vector3.new(0.3, 0.42, 0.3), pot * CFrame.new(0, 0.32, 0), Color3.fromRGB(60, 150, 80), Enum.Material.Grass)
		end
	end,
	function(m, cf) -- Grand Hall: rug and pillars
		Models.block(m, "Rug", Vector3.new(1.3, 0.03, 0.6), cf * CFrame.new(0, 0.005, 0.5), Color3.fromRGB(170, 50, 60), Enum.Material.Fabric)
		for _, x in { -0.6, 0.6 } do
			Models.cyl(m, "Pillar", 0.2, 0.6, cf * CFrame.new(x, 0, 0), Models.IVORY)
			Models.cyl(m, "PillarCap", 0.28, 0.06, cf * CFrame.new(x, 0.6, 0), Models.GOLD)
		end
	end,
	function(m, cf) -- Arcade: cabinet
		Models.block(m, "Cabinet", Vector3.new(0.42, 0.64, 0.32), cf * CFrame.new(-0.26, 0.32, 0), Color3.fromRGB(90, 60, 160))
		Models.block(m, "Screen", Vector3.new(0.32, 0.22, 0.02), cf * CFrame.new(-0.26, 0.46, 0.17), Color3.fromRGB(80, 230, 200), Enum.Material.Neon)
		Models.block(m, "Cabinet2", Vector3.new(0.42, 0.64, 0.32), cf * CFrame.new(0.26, 0.32, 0), Color3.fromRGB(210, 70, 90))
		Models.block(m, "Screen2", Vector3.new(0.32, 0.22, 0.02), cf * CFrame.new(0.26, 0.46, 0.17), Color3.fromRGB(255, 220, 110), Enum.Material.Neon)
	end,
	function(m, cf) -- Pool: water with a float ring
		Models.block(m, "PoolEdge", Vector3.new(1.3, 0.05, 0.66), cf * CFrame.new(0, 0.025, 0.1), Models.IVORY)
		Models.block(m, "Water", Vector3.new(1.16, 0.06, 0.52), cf * CFrame.new(0, 0, 0.1), Color3.fromRGB(70, 180, 220), Enum.Material.Glass)
		Models.cyl(m, "Float", 0.3, 0.04, cf * CFrame.new(0.28, 0.06, 0.1), Color3.fromRGB(245, 120, 90))
	end,
	function(m, cf) -- Garage: a little car
		local red = Color3.fromRGB(210, 60, 60)
		Models.block(m, "CarBody", Vector3.new(0.8, 0.16, 0.36), cf * CFrame.new(0, 0.16, 0), red)
		Models.block(m, "CarTop", Vector3.new(0.4, 0.14, 0.32), cf * CFrame.new(0, 0.3, 0), Color3.fromRGB(170, 220, 240))
		for _, x in { -0.26, 0.26 } do
			for _, z in { -0.2, 0.2 } do
				Models.ball(m, "Wheel", 0.17, cf * CFrame.new(x, 0.09, z), Models.INK)
			end
		end
	end,
	function(m, cf) -- Library: shelves of books
		Models.block(m, "Shelf", Vector3.new(1.2, 0.56, 0.2), cf * CFrame.new(0, 0.28, 0), Models.WALNUT, Enum.Material.Wood)
		local colors = { Color3.fromRGB(200, 70, 70), Color3.fromRGB(70, 120, 200), Color3.fromRGB(230, 180, 70), Color3.fromRGB(80, 160, 110) }
		for row = 0, 1 do
			for i = 1, 8 do
				Models.block(m, "Book", Vector3.new(0.1, 0.18, 0.03), cf * CFrame.new((i - 4.5) * 0.13, 0.15 + row * 0.25, 0.1), colors[(i + row) % 4 + 1])
			end
		end
	end,
}

-- Hats, one per suspect in Rules.theme.suspects order, sitting on a pawn `height` tall.
local HATS: { (m: Instance, cf: CFrame, s: number) -> () } = {
	function(m, cf, s) -- Madame Rosette: wide brim and a flower
		Models.cyl(m, "Brim", s * 0.52, s * 0.03, cf, Color3.fromRGB(240, 140, 170))
		Models.cyl(m, "Crown", s * 0.26, s * 0.1, cf, Color3.fromRGB(240, 140, 170))
		Models.ball(m, "Flower", s * 0.11, cf * CFrame.new(s * 0.14, s * 0.08, -s * 0.06), Color3.fromRGB(220, 50, 80))
	end,
	function(m, cf, s) -- Captain Cobalt: sailor's cap
		Models.cyl(m, "Cap", s * 0.34, s * 0.1, cf, Models.IVORY)
		Models.block(m, "Peak", Vector3.new(s * 0.26, s * 0.02, s * 0.14), cf * CFrame.new(0, s * 0.01, -s * 0.18), Models.INK)
		Models.block(m, "Badge", Vector3.new(s * 0.09, s * 0.05, s * 0.01), cf * CFrame.new(0, s * 0.06, -s * 0.17), Models.GOLD)
	end,
	function(m, cf, s) -- Chef Butterscotch: tall chef's hat
		Models.cyl(m, "Band", s * 0.3, s * 0.08, cf, Color3.new(1, 1, 1))
		Models.egg(m, "Puff", Vector3.new(s * 0.4, s * 0.26, s * 0.4), cf * CFrame.new(0, s * 0.18, 0), Color3.new(1, 1, 1))
	end,
	function(m, cf, s) -- Dr. Minty: head mirror on a strap
		Models.block(m, "Strap", Vector3.new(s * 0.38, s * 0.04, s * 0.38), cf * CFrame.new(0, -s * 0.05, 0), Color3.fromRGB(70, 190, 150))
		Models.cyl(m, "Mirror", s * 0.16, s * 0.02, cf * CFrame.new(0, 0, -s * 0.2) * CFrame.Angles(math.rad(80), 0, 0), Models.STEEL)
	end,
	function(m, cf, s) -- Duke Lavender: a crown
		Models.cyl(m, "CrownBand", s * 0.32, s * 0.06, cf, Models.GOLD)
		for i = 0, 4 do
			local a = i / 5 * math.pi * 2
			Models.block(m, "CrownPoint", Vector3.new(s * 0.05, s * 0.1, s * 0.05), cf * CFrame.new(math.sin(a) * s * 0.13, s * 0.1, math.cos(a) * s * 0.13), Models.GOLD)
		end
	end,
	function(m, cf, s) -- Coach Tangerine: a visor and a whistle
		Models.cyl(m, "Visor", s * 0.34, s * 0.04, cf, Color3.fromRGB(245, 150, 60))
		Models.block(m, "Peak", Vector3.new(s * 0.28, s * 0.02, s * 0.18), cf * CFrame.new(0, 0, -s * 0.2), Color3.fromRGB(245, 150, 60))
	end,
}

-- The items as minis, in Rules.theme.items order.
local ITEMS: { (m: Instance, cf: CFrame) -> () } = {
	function(m, cf) -- Rubber Chicken
		local yellow = Color3.fromRGB(250, 214, 80)
		Models.egg(m, "Body", Vector3.new(0.12, 0.26, 0.12), cf * CFrame.new(0, 0.13, 0), yellow)
		Models.ball(m, "Head", 0.1, cf * CFrame.new(0, 0.3, 0), yellow)
		Models.block(m, "Beak", Vector3.new(0.05, 0.03, 0.07), cf * CFrame.new(0, 0.3, -0.07), Color3.fromRGB(240, 130, 50))
		Models.block(m, "Comb", Vector3.new(0.03, 0.06, 0.08), cf * CFrame.new(0, 0.37, 0), Color3.fromRGB(220, 60, 60))
	end,
	function(m, cf) -- Grappling Hook
		Models.block(m, "Shaft", Vector3.new(0.04, 0.3, 0.04), cf * CFrame.new(0, 0.15, 0), Models.STEEL, Enum.Material.Metal)
		for i = 0, 2 do
			Models.block(m, "Hook", Vector3.new(0.03, 0.03, 0.14), cf * CFrame.Angles(0, math.rad(i * 120), 0) * CFrame.new(0, 0.3, 0.07), Models.STEEL, Enum.Material.Metal)
		end
		Models.cyl(m, "Rope", 0.18, 0.05, cf, Color3.fromRGB(190, 160, 110))
	end,
	function(m, cf) -- Butterfly Net
		Models.block(m, "Handle", Vector3.new(0.03, 0.38, 0.03), cf * CFrame.new(0, 0.19, 0), Models.WOOD)
		Models.egg(m, "Net", Vector3.new(0.2, 0.2, 0.06), cf * CFrame.new(0, 0.44, 0), Color3.fromRGB(240, 240, 240))
	end,
	function(m, cf) -- Giant Magnet
		local red = Color3.fromRGB(220, 60, 60)
		for _, x in { -0.08, 0.08 } do
			Models.block(m, "Leg", Vector3.new(0.07, 0.2, 0.07), cf * CFrame.new(x, 0.16, 0), red)
			Models.block(m, "Tip", Vector3.new(0.07, 0.06, 0.07), cf * CFrame.new(x, 0.03, 0), Models.STEEL)
		end
		Models.block(m, "Bend", Vector3.new(0.23, 0.07, 0.07), cf * CFrame.new(0, 0.29, 0), red)
	end,
	function(m, cf) -- Umbrella
		Models.block(m, "Pole", Vector3.new(0.03, 0.36, 0.03), cf * CFrame.new(0, 0.18, 0), Models.INK)
		Models.egg(m, "Canopy", Vector3.new(0.34, 0.16, 0.34), cf * CFrame.new(0, 0.38, 0), Color3.fromRGB(90, 130, 220))
	end,
	function(m, cf) -- Fishing Rod
		Models.block(m, "Rod", Vector3.new(0.03, 0.46, 0.03), cf * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(-18)), Models.WALNUT)
		Models.cyl(m, "Reel", 0.09, 0.04, cf * CFrame.new(-0.02, 0.12, 0.03), Models.STEEL)
		Models.ball(m, "Bobber", 0.08, cf * CFrame.new(0.16, 0.14, 0), Color3.fromRGB(230, 60, 60))
	end,
}

function Whodunit.create(boardCF: CFrame, parent: Instance, _layout: Scene.Layout)
	local model = Instance.new("Model")
	model.Name = "GameBoard"
	Models.block(model, "Base", Vector3.new(SIZE + 0.4, 0.2, SIZE + 0.4), boardCF * CFrame.new(0, 0.1, 0), Color3.fromRGB(90, 64, 48), Enum.Material.Wood)
	for room, name in Rules.theme.rooms do
		local floor = roomCF(boardCF, room, FLOOR_Y)
		Models.block(model, name, Vector3.new(CELL * 0.94, 0.05, CELL * 0.94), roomCF(boardCF, room, 0.225), FLOORS[room] or Color3.new(1, 1, 1))
		-- Low walls on three sides, open toward seat 1 so the room can be seen into.
		local wall = CELL * 0.94
		Models.block(model, "Wall", Vector3.new(wall, 0.3, 0.06), floor * CFrame.new(0, 0.15, -wall / 2), WALL)
		for _, s in { -1, 1 } do
			Models.block(model, "Wall", Vector3.new(0.06, 0.3, wall), floor * CFrame.new(s * wall / 2, 0.15, 0), WALL)
		end
		local furnish = FURNITURE[room]
		if furnish then
			furnish(model, floor * CFrame.new(0, 0, -CELL * 0.3))
		end
		-- Room name floating over the room, facing each viewer, so walls and furniture
		-- never hide it.
		Scene.floatText(model, floor * CFrame.new(0, 0.9, -CELL * 0.3), CELL * 0.9, CELL * 0.22, name, { TextColor3 = Color3.fromRGB(60, 44, 34) })
	end
	local dynamic = Scene.dynamic(model)
	model.Parent = parent
	local memo = {}

	return {
		model = model,
		update = function(view: any, snapshot: any)
			if not Scene.changed(memo, view) then
				return
			end
			Scene.redraw(dynamic, function(dynamic)
				-- Group by room so pawns stand side by side.
				local seatCount = view.seatCount or (snapshot and #snapshot.seats) or #Rules.theme.suspects
				local inRoom: { [number]: number } = {}
				local height = 0.72
				for suspect, room in view.suspectRoom or {} do
					local k = inRoom[room] or 0
					inRoom[room] = k + 1
					local cf = roomCF(boardCF, room, FLOOR_Y) * CFrame.new(((k % 3) - 1) * CELL * 0.26, 0, (k // 3) * CELL * 0.2)
					local color = if suspect <= seatCount then (Scene.SEAT_COLORS[suspect] or Color3.new(1, 1, 1)) else Color3.fromRGB(150, 150, 150)
					local pawn = Models.pawn(dynamic, cf, color, height)
					local hat = HATS[suspect]
					if hat then
						hat(pawn, cf * CFrame.new(0, height * 0.96, 0), height)
					end
				end
				local itemsIn: { [number]: number } = {}
				for item, room in view.itemRoom or {} do
					local k = itemsIn[room] or 0
					itemsIn[room] = k + 1
					local mini = ITEMS[item]
					local cf = roomCF(boardCF, room, FLOOR_Y) * CFrame.new((k - 2.5) * 0.3, 0, CELL * 0.17)
					if mini then
						mini(dynamic, cf)
					end
				end
				-- The sealed case file (opens at the end).
				local solved = view.solution ~= nil
				local file = boardCF * CFrame.new(SIZE / 2 + 0.75, 0, 0)
				Models.block(dynamic, "CaseFile", Vector3.new(0.95, 0.07, 0.7), file * CFrame.new(0, 0.035, 0), if solved then Color3.fromRGB(240, 230, 200) else Color3.fromRGB(200, 170, 120))
				Models.block(dynamic, "CaseFlap", Vector3.new(0.6, 0.01, 0.6), file * CFrame.new(0, 0.075, 0) * CFrame.Angles(0, math.rad(45), 0), Color3.fromRGB(180, 150, 100))
				if solved then
					Scene.flatText(dynamic, file * CFrame.new(0, 0.085, 0), 0.8, 0.4, "Solved!", { TextColor3 = Color3.fromRGB(40, 30, 24) })
				else
					Models.cyl(dynamic, "WaxSeal", 0.26, 0.03, file * CFrame.new(0, 0.08, 0), Color3.fromRGB(170, 30, 40))
				end
			end)
		end,
		destroy = function()
			model:Destroy()
		end,
	}
end

return Whodunit
