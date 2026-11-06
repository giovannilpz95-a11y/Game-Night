-- Hexlands at the table: the 19-hex island as little dioramas (trees, clay, sheep, wheat,
-- rocks, sand), number tokens, harbors, the Bandit, and every camp, town and road in its
-- owner's color. Play stays in the 2D view.
-- Uses the same hex layout as the rules (Hexlands.hexes / vertices / edges).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.Shared.Games.Hexlands)
local Models = require(script.Parent.Parent.Models)
local Scene = require(script.Parent.Parent.Scene)

local Hexlands = {}

local S = 0.82 -- studs per hex radius: the island is about 8 studs across
local SEA = Color3.fromRGB(70, 140, 200)
local TILE_Y = 0.3
local TOP_Y = TILE_Y + 0.1 -- top surface of a land tile

local function landColor(land: string): Color3
	local info = Rules.resourceInfo[land]
	return if info then info.color else Rules.DUNES.color
end

local function at(boardCF: CFrame, x: number, y: number, height: number): CFrame
	return boardCF * CFrame.new(x * S, height, y * S)
end

-- Little scenery for each land, placed around the edge so the number token stays clear.
local TRUNK = Color3.fromRGB(110, 76, 50)
local DECOR = {
	lumber = function(m: Instance, cf: CFrame)
		local leaf = Color3.fromRGB(36, 100, 56)
		Models.cyl(m, "Trunk", 0.08, 0.16, cf, TRUNK)
		Models.egg(m, "Leaves", Vector3.new(0.3, 0.28, 0.3), cf * CFrame.new(0, 0.24, 0), leaf)
		Models.egg(m, "LeavesTop", Vector3.new(0.2, 0.24, 0.2), cf * CFrame.new(0, 0.4, 0), leaf:Lerp(Color3.new(1, 1, 1), 0.1))
	end,
	clay = function(m: Instance, cf: CFrame)
		local brick = Color3.fromRGB(176, 92, 62)
		Models.block(m, "Brick", Vector3.new(0.3, 0.09, 0.14), cf * CFrame.new(0, 0.045, 0.08), brick)
		Models.block(m, "Brick", Vector3.new(0.3, 0.09, 0.14), cf * CFrame.new(0, 0.045, -0.08), brick:Lerp(Color3.new(0, 0, 0), 0.15))
		Models.block(m, "Brick", Vector3.new(0.3, 0.09, 0.14), cf * CFrame.new(0, 0.14, 0) * CFrame.Angles(0, math.rad(90), 0), brick)
	end,
	wool = function(m: Instance, cf: CFrame)
		local wool = Color3.fromRGB(246, 244, 236)
		Models.egg(m, "Sheep", Vector3.new(0.3, 0.2, 0.2), cf * CFrame.new(0, 0.15, 0), wool)
		Models.egg(m, "SheepHead", Vector3.new(0.12, 0.12, 0.11), cf * CFrame.new(-0.17, 0.2, 0), Color3.fromRGB(50, 44, 48))
		for _, x in { -0.08, 0.08 } do
			Models.block(m, "Leg", Vector3.new(0.035, 0.08, 0.1), cf * CFrame.new(x, 0.04, 0), Color3.fromRGB(50, 44, 48))
		end
	end,
	grain = function(m: Instance, cf: CFrame)
		local wheat = Color3.fromRGB(214, 164, 52)
		for i = 0, 2 do
			local stalk = cf * CFrame.Angles(0, math.rad(i * 120), 0) * CFrame.new(0, 0, 0.07) * CFrame.Angles(math.rad(10), 0, 0)
			Models.block(m, "Stalk", Vector3.new(0.03, 0.26, 0.03), stalk * CFrame.new(0, 0.13, 0), Color3.fromRGB(180, 150, 70))
			Models.egg(m, "Ear", Vector3.new(0.07, 0.16, 0.07), stalk * CFrame.new(0, 0.3, 0), wheat)
		end
	end,
	stone = function(m: Instance, cf: CFrame)
		local rock = Color3.fromRGB(128, 128, 136)
		Models.block(m, "Rock", Vector3.new(0.24, 0.24, 0.24), cf * CFrame.new(0, 0.12, 0) * CFrame.Angles(math.rad(30), math.rad(40), math.rad(20)), rock, Enum.Material.Slate)
		Models.block(m, "Rock", Vector3.new(0.14, 0.14, 0.14), cf * CFrame.new(0.17, 0.07, 0.08) * CFrame.Angles(math.rad(10), math.rad(25), math.rad(40)), rock:Lerp(Color3.new(1, 1, 1), 0.15), Enum.Material.Slate)
	end,
	dunes = function(m: Instance, cf: CFrame)
		local green = Color3.fromRGB(80, 150, 90)
		Models.egg(m, "Cactus", Vector3.new(0.1, 0.36, 0.1), cf * CFrame.new(0, 0.18, 0), green)
		Models.egg(m, "CactusArm", Vector3.new(0.06, 0.16, 0.06), cf * CFrame.new(0.09, 0.2, 0), green)
	end,
}

-- A camp: a hut in the owner's color with a pointed roof.
local function camp(parent: Instance, cf: CFrame, color: Color3)
	Models.house(parent, cf, color, 0.3, color:Lerp(Color3.new(0, 0, 0), 0.35))
end

-- A town: a bigger hall with a tower and a flag.
local function town(parent: Instance, cf: CFrame, color: Color3)
	Models.house(parent, cf, color, 0.42, color:Lerp(Color3.new(0, 0, 0), 0.35))
	local tower = cf * CFrame.new(0.17, 0, 0.13)
	Models.block(parent, "Tower", Vector3.new(0.17, 0.52, 0.17), tower * CFrame.new(0, 0.24, 0), color:Lerp(Color3.new(1, 1, 1), 0.2))
	Models.flag(parent, tower * CFrame.new(0, 0.5, 0), Models.GOLD, 0.24)
end

-- The Bandit: a hooded figure in a dark cloak with a lantern.
local function bandit(parent: Instance, cf: CFrame)
	local cloak = Color3.fromRGB(40, 36, 44)
	Models.cyl(parent, "Base", 0.34, 0.08, cf, Color3.fromRGB(20, 18, 24))
	Models.egg(parent, "Cloak", Vector3.new(0.34, 0.56, 0.32), cf * CFrame.new(0, 0.3, 0), cloak)
	Models.egg(parent, "Hood", Vector3.new(0.26, 0.28, 0.26), cf * CFrame.new(0, 0.6, 0), cloak:Lerp(Color3.new(1, 1, 1), 0.08))
	Models.block(parent, "Mask", Vector3.new(0.16, 0.05, 0.02), cf * CFrame.new(0, 0.6, -0.125), Color3.fromRGB(230, 60, 60))
	Models.ball(parent, "Lantern", 0.1, cf * CFrame.new(0.2, 0.26, -0.06), Color3.fromRGB(255, 210, 110), Enum.Material.Neon)
end

function Hexlands.create(boardCF: CFrame, parent: Instance, _layout: Scene.Layout)
	local model = Instance.new("Model")
	model.Name = "GameBoard"
	local seaSize = 9 * S * 1.2
	Models.cyl(model, "Rim", seaSize + 0.5, 0.16, boardCF, Models.WALNUT, Enum.Material.Wood)
	Models.cyl(model, "Sea", seaSize, 0.2, boardCF, SEA)
	-- Harbors: a wooden pier on each harbor edge, pointing out to sea.
	for _, e in Rules.harborEdges or {} do
		local edge = Rules.edges[e]
		local a, b = Rules.vertices[edge.a], Rules.vertices[edge.b]
		local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
		local length = math.sqrt(mx * mx + my * my)
		local pier = at(boardCF, mx * (1 + 0.3 / length), my * (1 + 0.3 / length), 0.22)
		local facing = CFrame.lookAt(pier.Position, (boardCF * CFrame.new(mx * 2 * S, 0.22, my * 2 * S)).Position, boardCF.UpVector)
		Models.block(model, "Pier", Vector3.new(0.24, 0.05, 0.62), facing, Models.WOOD, Enum.Material.Wood)
		Models.block(model, "PierEnd", Vector3.new(0.34, 0.09, 0.1), facing * CFrame.new(0, 0, -0.3), Models.WALNUT, Enum.Material.Wood)
	end
	local tiles = Instance.new("Folder")
	tiles.Name = "Tiles"
	tiles.Parent = model
	-- Invisible spots on every corner and road edge: tap them in Table view to build
	-- (renderer tapTable "v:<vertex>" / "e:<edge>"; the client glows the ones you can use).
	local spots = Instance.new("Folder")
	spots.Name = "Spots"
	spots.Parent = model
	local function spot(name: string, id: string, size: Vector3, cf: CFrame, shape: Enum.PartType)
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = shape
		part.Size = size
		part.CFrame = cf
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Parent = spots
		Scene.tappable(part, id)
	end
	for e, edge in Rules.edges do
		local a, b = Rules.vertices[edge.a], Rules.vertices[edge.b]
		local pa = at(boardCF, a.x, a.y, TOP_Y + 0.08).Position
		local pb = at(boardCF, b.x, b.y, TOP_Y + 0.08).Position
		spot("EdgeSpot", `e:{e}`, Vector3.new(0.2, 0.12, (pb - pa).Magnitude * 0.5), CFrame.lookAt((pa + pb) / 2, pb, boardCF.UpVector), Enum.PartType.Block)
	end
	for v, vertex in Rules.vertices do
		spot("CornerSpot", `v:{v}`, Vector3.one * 0.36, at(boardCF, vertex.x, vertex.y, TOP_Y + 0.12), Enum.PartType.Ball)
	end
	local dynamic = Scene.dynamic(model)
	model.Parent = parent
	local built = false
	local memo = {}

	-- A pointy-top hex: three overlapping bars turned 0, 60 and 120 degrees.
	-- Each tile's parts sit in their own model, so Table view outlines the whole tile.
	local function hex(h: number, color: Color3): Model
		local center = Rules.hexes[h]
		local cf = at(boardCF, center.x, center.y, TILE_Y)
		local tile = Instance.new("Model")
		tile.Name = `Tile_{h}`
		tile.Parent = tiles
		-- One beveled hex mesh when it's imported (docs/Meshes.md), else three bars.
		if Models.mesh(tile, `Hex_{h}`, Vector3.new(math.sqrt(3) * S * 0.96, 0.2, 2 * S * 0.96), cf, color, Enum.Material.Grass) then
			return tile
		end
		-- Each bar's top and bottom sit 0.025 inside the last one's, so where they overlap
		-- no two faces share a plane and fight (flicker).
		for i = 0, 2 do
			Models.block(tile, `Hex_{h}`, Vector3.new(math.sqrt(3) * S * 0.96, 0.2 - 0.05 * i, S * 0.96), cf * CFrame.Angles(0, math.rad(60 * i), 0), color, Enum.Material.Grass)
		end
		return tile
	end

	local function buildTiles(view: any)
		tiles:ClearAllChildren()
		for h, tile in view.tiles or {} do
			-- Tap a land in Table view to move the bandit there (renderer tapTable "h:<hex>").
			Scene.tappable(hex(h, landColor(tile.land)), `h:{h}`)
			local center = Rules.hexes[h]
			local top = at(boardCF, center.x, center.y, TOP_Y)
			local decor = DECOR[tile.land]
			if decor then
				for i = 0, 2 do
					local a = math.rad(i * 120 + h * 37)
					decor(tiles, top * CFrame.new(math.cos(a) * S * 0.52, 0, math.sin(a) * S * 0.52) * CFrame.Angles(0, a, 0))
				end
			end
			if tile.number and tile.number > 0 then
				local red = tile.number == 6 or tile.number == 8
				Models.cyl(tiles, "Number", S * 0.5, 0.05, top, Color3.fromRGB(245, 236, 214))
				Scene.flatText(tiles, top * CFrame.new(0, 0.055, 0), S * 0.34, S * 0.34, tostring(tile.number), { TextColor3 = if red then Color3.fromRGB(200, 40, 40) else Color3.fromRGB(40, 30, 24) })
			end
		end
	end

	return {
		model = model,
		update = function(view: any, _snapshot: any)
			if not built and view.tiles then
				buildTiles(view)
				built = true
			end
			if not Scene.changed(memo, view) then
				return
			end
			Scene.redraw(dynamic, function(dynamic)
				-- Roads
				for e, seat in view.road or {} do
					if seat ~= 0 then
						local edge = Rules.edges[e]
						local a, b = Rules.vertices[edge.a], Rules.vertices[edge.b]
						local pa = at(boardCF, a.x, a.y, TOP_Y + 0.06).Position
						local pb = at(boardCF, b.x, b.y, TOP_Y + 0.06).Position
						local color = Scene.SEAT_COLORS[seat] or Color3.new(1, 1, 1)
						local cf = CFrame.lookAt((pa + pb) / 2, pb, boardCF.UpVector)
						local length = (pb - pa).Magnitude * 0.7
						Models.block(dynamic, "Road", Vector3.new(0.14, 0.12, length), cf, color)
						Models.block(dynamic, "RoadTop", Vector3.new(0.07, 0.02, length * 0.8), cf * CFrame.new(0, 0.07, 0), color:Lerp(Color3.new(1, 1, 1), 0.4))
					end
				end
				-- Camps and towns
				for v, seat in view.owner or {} do
					if seat ~= 0 then
						local vertex = Rules.vertices[v]
						local cf = at(boardCF, vertex.x, vertex.y, TOP_Y)
						local color = Scene.SEAT_COLORS[seat] or Color3.new(1, 1, 1)
						if (view.town or {})[v] == true then
							town(dynamic, cf, color)
						else
							camp(dynamic, cf, color)
						end
					end
				end
				if view.bandit and Rules.hexes[view.bandit] then
					local center = Rules.hexes[view.bandit]
					bandit(dynamic, at(boardCF, center.x + 0.38, center.y, TOP_Y))
				end
				-- The roll that just paid: a glowing halo under the number on every hex that
				-- paid, with what it paid floating over it.
				local gain = view.lastGain
				local dice = view.dice
				if gain and dice and #dice == 2 and gain.roll == dice[1] + dice[2] and gain.roll ~= 7 then
					for _, h in gain.hexes or {} do
						local center = Rules.hexes[h]
						if center then
							local ring = Models.cyl(dynamic, "PaidRing", S * 0.72, 0.02, at(boardCF, center.x, center.y, TOP_Y + 0.002), Color3.fromRGB(255, 230, 120), Enum.Material.Neon)
							ring.Transparency = 0.25
							local land = view.tiles and view.tiles[h] and view.tiles[h].land
							local info = land and Rules.resourceInfo[land]
							local label = info and `{info.icon} {info.name}`
							if label then
								Scene.floatText(dynamic, at(boardCF, center.x, center.y, TOP_Y + 0.9), 1.6, 0.42, `+{label}`, { TextColor3 = Color3.fromRGB(255, 236, 150), TextStrokeColor3 = Color3.fromRGB(30, 24, 20), TextStrokeTransparency = 0.1 })
							end
						end
					end
				end
				for i, value in view.dice or {} do
					Models.die(dynamic, boardCF * CFrame.new(4.4 + (i - 1.5) * 0.6, 0, 3.4) * CFrame.Angles(0, math.rad(i * 23), 0), value, 0.45)
				end
			end)
		end,
		destroy = function()
			model:Destroy()
		end,
	}
end

return Hexlands
