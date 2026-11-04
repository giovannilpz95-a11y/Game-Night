-- Hexlands at the table: the 19-hex island with number tokens, the Bandit, and every
-- camp, town and road in its owner's color. Play stays in the 2D view.
-- Uses the same hex layout as the rules (Hexlands.hexes / vertices / edges).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.Shared.Games.Hexlands)
local Pieces = require(script.Parent.Parent.Pieces)
local Scene = require(script.Parent.Parent.Scene)

local Hexlands = {}

local S = 0.82 -- studs per hex radius: the island is about 8 studs across
local SEA = Color3.fromRGB(70, 140, 200)
local TILE_Y = 0.3

local function landColor(land: string): Color3
	local info = Rules.resourceInfo[land]
	return if info then info.color else Rules.DUNES.color
end

local function at(boardCF: CFrame, x: number, y: number, height: number): CFrame
	return boardCF * CFrame.new(x * S, height, y * S)
end

function Hexlands.create(boardCF: CFrame, parent: Instance, _layout: Scene.Layout)
	local model = Instance.new("Model")
	model.Name = "GameBoard"
	Pieces.part({
		Name = "Sea",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 9 * S * 1.2, 9 * S * 1.2),
		CFrame = boardCF * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = SEA,
		CanQuery = false,
		Parent = model,
	})
	local tiles = Instance.new("Folder")
	tiles.Name = "Tiles"
	tiles.Parent = model
	local dynamic = Scene.dynamic(model)
	model.Parent = parent
	local built = false

	-- A pointy-top hex: three overlapping bars turned 0, 60 and 120 degrees.
	local function hex(h: number, color: Color3)
		local center = Rules.hexes[h]
		local cf = at(boardCF, center.x, center.y, TILE_Y)
		for i = 0, 2 do
			Pieces.part({
				Name = `Hex_{h}`,
				Size = Vector3.new(math.sqrt(3) * S * 0.96, 0.2, S * 0.96),
				CFrame = cf * CFrame.Angles(0, math.rad(60 * i), 0),
				Color = color,
				Material = Enum.Material.Grass,
				CanQuery = false,
				Parent = tiles,
			})
		end
	end

	local function buildTiles(view: any)
		tiles:ClearAllChildren()
		for h, tile in view.tiles or {} do
			hex(h, landColor(tile.land))
			if tile.number and tile.number > 0 then
				local center = Rules.hexes[h]
				local token = Pieces.part({
					Name = "Number",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.06, S * 0.62, S * 0.62),
					CFrame = at(boardCF, center.x, center.y, TILE_Y + 0.13) * CFrame.Angles(0, 0, math.rad(90)),
					Color = Color3.fromRGB(245, 236, 214),
					CanQuery = false,
					Parent = tiles,
				})
				local red = tile.number == 6 or tile.number == 8
				-- Text on a flat square on top of the round token.
				local face = Pieces.part({
					Name = "NumberFace",
					Size = Vector3.new(S * 0.42, 0.01, S * 0.42),
					CFrame = at(boardCF, center.x, center.y, TILE_Y + 0.165),
					Transparency = 1,
					CanQuery = false,
					Parent = tiles,
				})
				Scene.text(face, Enum.NormalId.Top, tostring(tile.number), { TextColor3 = if red then Color3.fromRGB(200, 40, 40) else Color3.fromRGB(40, 30, 24) })
				token.Name = "Number"
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
			dynamic:ClearAllChildren()
			-- Roads
			for e, seat in view.road or {} do
				if seat ~= 0 then
					local edge = Rules.edges[e]
					local a, b = Rules.vertices[edge.a], Rules.vertices[edge.b]
					local pa = at(boardCF, a.x, a.y, TILE_Y + 0.18).Position
					local pb = at(boardCF, b.x, b.y, TILE_Y + 0.18).Position
					local mid = (pa + pb) / 2
					Pieces.part({
						Name = "Road",
						Size = Vector3.new(0.14, 0.12, (pb - pa).Magnitude * 0.72),
						CFrame = CFrame.lookAt(mid, pb, boardCF.UpVector),
						Color = Scene.SEAT_COLORS[seat] or Color3.new(1, 1, 1),
						CanQuery = false,
						Parent = dynamic,
					})
				end
			end
			-- Camps and towns
			for v, seat in view.owner or {} do
				if seat ~= 0 then
					local vertex = Rules.vertices[v]
					local town = (view.town or {})[v] == true
					local size = if town then Vector3.new(0.36, 0.36, 0.36) else Vector3.new(0.26, 0.24, 0.26)
					local cf = at(boardCF, vertex.x, vertex.y, TILE_Y + 0.12 + size.Y / 2)
					Pieces.part({ Name = if town then "Town" else "Camp", Size = size, CFrame = cf, Color = Scene.SEAT_COLORS[seat] or Color3.new(1, 1, 1), CanQuery = false, Parent = dynamic })
					if town then
						Pieces.part({ Name = "Roof", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = cf * CFrame.new(0, 0.26, 0), Color = (Scene.SEAT_COLORS[seat] or Color3.new(1, 1, 1)):Lerp(Color3.new(0, 0, 0), 0.3), CanQuery = false, Parent = dynamic })
					end
				end
			end
			-- The Bandit
			if view.bandit and Rules.hexes[view.bandit] then
				local center = Rules.hexes[view.bandit]
				Scene.pawn(dynamic, at(boardCF, center.x + 0.38, center.y, TILE_Y + 0.1), Color3.fromRGB(40, 36, 44), 0.55)
			end
			-- Dice
			for i, value in view.dice or {} do
				local die = Pieces.part({ Name = "Die", Size = Vector3.one * 0.45, CFrame = boardCF * CFrame.new(4.4 + (i - 1.5) * 0.6, 0.23, 3.4), Color = Color3.new(1, 1, 1), CanQuery = false, Parent = dynamic })
				Scene.text(die, Enum.NormalId.Top, tostring(value))
			end
		end,
		destroy = function()
			model:Destroy()
		end,
	}
end

return Hexlands
