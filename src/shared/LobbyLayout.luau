-- Where everything in the lobby room goes. Pure data and math (no Instances), so
-- tests/LobbyLayout.spec.luau can check that tables, props and walkways never overlap.
--
-- Coordinates are studs. X runs west (-) to east (+), Z runs from the front door / spawn
-- (+Z, south) to the back wall with the big TV (-Z, north). `y` is the floor height a
-- thing stands on. A prop's `yaw` is in degrees, applied as CFrame.Angles(0, yaw, 0) to a
-- prop whose front faces -Z: 0 faces the back wall, 180 faces the spawn, 90 faces west,
-- -90 faces east. `w` is the prop's width (local X) and `d` its depth (local Z).
--
-- The plan follows the vault's 03 Design/Lobby.md: Quick Play nearest spawn, Strategy on
-- the quiet side, the center lounge as the crossroads, Cards and the Party Stage at the
-- back under the TV, snack bar and Dressing Room on either side of the foyer.

local LobbyLayout = {}

LobbyLayout.FLOOR_Y = 0.1 -- top of the wood floor (the Studio baseplate's top is 0)
LobbyLayout.STAGE_Y = 1.1 -- top of the Party Stage
LobbyLayout.CEILING_Y = 30
LobbyLayout.TABLE_RADIUS = 10.5 -- a table with its chairs fits in this circle
LobbyLayout.AISLE = 6 -- the narrowest gap left between two tables

-- Inside faces of the walls.
LobbyLayout.room = { minX = -100, maxX = 100, minZ = -150, maxZ = 20 }

export type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }

local function rect(minX: number, maxX: number, minZ: number, maxZ: number): Rect
	return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
end

-- Zones: the rug under each one, the banner hanging over it and its lamp color.
-- `id` matches GameCatalog categories (and Config.DefaultTables zones).
LobbyLayout.zones = {
	{ id = "Foyer", label = "Welcome!", area = rect(-24, 24, -4, 18), rug = Color3.fromRGB(150, 52, 62), border = Color3.fromRGB(232, 186, 92) },
	{ id = "Quick", label = "Quick Play", area = rect(20, 80, -34, -6), rug = Color3.fromRGB(46, 110, 150), border = Color3.fromRGB(240, 210, 140) },
	{ id = "Strategy", label = "Strategy", area = rect(-80, -20, -66, -6), rug = Color3.fromRGB(58, 66, 104), border = Color3.fromRGB(200, 180, 140) },
	{ id = "Word", label = "Word Games", area = rect(36, 64, -66, -38), rug = Color3.fromRGB(176, 120, 44), border = Color3.fromRGB(250, 236, 200) },
	{ id = "Lounge", label = "Lounge", area = rect(-16, 16, -88, -38), rug = Color3.fromRGB(122, 64, 92), border = Color3.fromRGB(236, 200, 120) },
	{ id = "Board", label = "Board Games", area = rect(-88, -24, -110, -76), rug = Color3.fromRGB(56, 112, 74), border = Color3.fromRGB(236, 214, 150) },
	{ id = "Cards", label = "Card Corner", area = rect(34, 92, -140, -76), rug = Color3.fromRGB(140, 46, 50), border = Color3.fromRGB(236, 196, 110) },
	{ id = "Party", label = "Party Stage", area = rect(-32, 32, -150, -110), rug = Color3.fromRGB(92, 52, 140), border = Color3.fromRGB(250, 214, 110) },
}

-- One spot per entry in Config.DefaultTables, in the same order (zone must match).
LobbyLayout.tables = {
	{ zone = "Quick", x = 34, z = -20 },
	{ zone = "Quick", x = 64, z = -20 },
	{ zone = "Strategy", x = -34, z = -20 },
	{ zone = "Strategy", x = -64, z = -20 },
	{ zone = "Strategy", x = -50, z = -52 },
	{ zone = "Board", x = -36, z = -93 },
	{ zone = "Board", x = -72, z = -93 },
	{ zone = "Word", x = 50, z = -52 },
	{ zone = "Cards", x = 44, z = -92 },
	{ zone = "Cards", x = 72, z = -92 },
	{ zone = "Cards", x = 56, z = -124 },
	{ zone = "Party", x = -18, z = -127 },
	{ zone = "Party", x = 18, z = -127 },
}

-- The raised Party Stage, and the step along its front edge.
LobbyLayout.stage = rect(-32, 32, -150, -110)
LobbyLayout.stageStep = rect(-32, 32, -110, -108)

LobbyLayout.spawn = { x = 0, z = 6 }
LobbyLayout.door = { x = 0, width = 12, height = 14 } -- in the front wall

-- Window openings: side walls by z, front and back walls by x. Bottom and top heights.
LobbyLayout.windows = {
	bottom = 9,
	top = 22,
	width = 14,
	side = { -20, -55, -90, -125 },
	front = { -44, 44 },
	back = { -72, 72 },
}

-- Strands of string lights hung across the room (east to west), by z.
-- Kept off the rows of tables, so they never cross a table lamp's cord.
LobbyLayout.stringLights = { -4, -36, -72, -108, -142 }

-- Props. `kind` picks the builder in server/Lobby/Props.luau.
LobbyLayout.props = {
	-- Center lounge: two couches around a coffee table, game shelves on both sides,
	-- the Party board at the back of the rug facing the spawn.
	{ kind = "Couch", x = 0, z = -46, w = 14, d = 5, yaw = 0 },
	{ kind = "Couch", x = 0, z = -70, w = 14, d = 5, yaw = 180 },
	{ kind = "CoffeeTable", x = 0, z = -58, w = 8, d = 4, yaw = 0 },
	{ kind = "FloorLamp", x = -10, z = -46, w = 2, d = 2, yaw = 0 },
	{ kind = "FloorLamp", x = 10, z = -70, w = 2, d = 2, yaw = 0 },
	{ kind = "GameShelf", x = -14, z = -58, w = 12, d = 2.4, yaw = -90 },
	{ kind = "GameShelf", x = 14, z = -58, w = 12, d = 2.4, yaw = 90 },
	{ kind = "PartyBoard", x = 0, z = -84, w = 16, d = 1.6, yaw = 180 },

	-- Back wall over the Party Stage: the big TV, trophy case and arcade cabinets.
	{ kind = "TV", x = 0, z = -148.5, w = 32, d = 2, yaw = 180 },
	{ kind = "TrophyCase", x = -50, z = -148, w = 14, d = 3, yaw = 180 },
	{ kind = "Arcade", x = 82, z = -147.5, w = 4, d = 4, yaw = 180 },
	{ kind = "Arcade", x = 88, z = -147.5, w = 4, d = 4, yaw = 180 },
	{ kind = "Arcade", x = 94, z = -147.5, w = 4, d = 4, yaw = 180 },

	-- Front-left: the snack bar. Front-right: the Dressing Room corner.
	{ kind = "SnackBar", x = -78, z = 8, w = 28, d = 14, yaw = 0 },
	{ kind = "DressingCorner", x = 80, z = 8, w = 30, d = 14, yaw = 0 },

	-- Shelves of board game boxes along the side walls, between the zones.
	{ kind = "GameShelf", x = -98.5, z = -38, w = 12, d = 2.4, yaw = -90 },
	-- West wall between Strategy and Board Games: a fireplace with two armchairs.
	{ kind = "Fireplace", x = -98, z = -72, w = 12, d = 3, yaw = -90 },
	{ kind = "Armchair", x = -89, z = -66, w = 4, d = 4, yaw = 53 },
	{ kind = "Armchair", x = -89, z = -78, w = 4, d = 4, yaw = 127 },
	{ kind = "GameShelf", x = -98.5, z = -108, w = 12, d = 2.4, yaw = -90 },
	{ kind = "GameShelf", x = 98.5, z = -38, w = 12, d = 2.4, yaw = 90 },
	{ kind = "GameShelf", x = 98.5, z = -72, w = 12, d = 2.4, yaw = 90 },
	{ kind = "GameShelf", x = 98.5, z = -108, w = 12, d = 2.4, yaw = 90 },

	-- Floor lamps lighting the walkways and corners.
	{ kind = "FloorLamp", x = -86, z = -4, w = 2, d = 2, yaw = 0 },
	{ kind = "FloorLamp", x = 88, z = -4, w = 2, d = 2, yaw = 0 },
	{ kind = "FloorLamp", x = -92, z = -142, w = 2, d = 2, yaw = 0 },
	{ kind = "FloorLamp", x = -20, z = -36, w = 2, d = 2, yaw = 0 },
	{ kind = "FloorLamp", x = 20, z = -36, w = 2, d = 2, yaw = 0 },
	{ kind = "FloorLamp", x = -54, z = -72, w = 2, d = 2, yaw = 0 },
	{ kind = "FloorLamp", x = 56, z = -72, w = 2, d = 2, yaw = 0 },
	{ kind = "FloorLamp", x = 92, z = -128, w = 2, d = 2, yaw = 0 },

	-- Plants by the door, in the corners and at the stage ends.
	{ kind = "Plant", x = -10, z = 16, w = 3, d = 3, yaw = 0 },
	{ kind = "Plant", x = 10, z = 16, w = 3, d = 3, yaw = 0 },
	{ kind = "Plant", x = -95, z = -20, w = 3, d = 3, yaw = 0 },
	{ kind = "Plant", x = 95, z = -20, w = 3, d = 3, yaw = 0 },
	{ kind = "Plant", x = -95, z = -88, w = 3, d = 3, yaw = 0 },
	{ kind = "Plant", x = 95, z = -88, w = 3, d = 3, yaw = 0 },
	{ kind = "Plant", x = -36, z = -144, w = 3, d = 3, yaw = 0 },
	{ kind = "Plant", x = 36, z = -144, w = 3, d = 3, yaw = 0 },

	-- Foyer wayfinding: a signpost pointing to every zone and shop, and a floor map.
	{ kind = "Signpost", x = -7, z = -8, w = 2, d = 2, yaw = 0 },
	{ kind = "Directory", x = -14, z = -8, w = 8, d = 1.6, yaw = 180 },

	-- A jukebox at the side of the Party Stage.
	{ kind = "Jukebox", x = 72, z = -147, w = 4, d = 3, yaw = 180 },

	-- Benches in the foyer, facing the room.
	{ kind = "Bench", x = -18, z = 2, w = 8, d = 2.4, yaw = -90 },
	{ kind = "Bench", x = 18, z = 2, w = 8, d = 2.4, yaw = 90 },
}

-- A carpet runner from the front door up the middle of the room to the lounge.
LobbyLayout.runner = rect(-4, 4, -38, 18)

-- Where the foyer signpost and the floor map send people. `zone` uses that zone's rug
-- center; otherwise `x`/`z` (the shops by the foyer).
LobbyLayout.destinations = {
	{ label = "Quick Play", zone = "Quick" },
	{ label = "Strategy", zone = "Strategy" },
	{ label = "Word Games", zone = "Word" },
	{ label = "Lounge", zone = "Lounge" },
	{ label = "Board Games", zone = "Board" },
	{ label = "Card Corner", zone = "Cards" },
	{ label = "Party Stage", zone = "Party" },
	{ label = "Snack Bar · Shop", x = -78, z = 4 },
	{ label = "Dressing Room", x = 80, z = 4 },
}

-- World x, z a destination points at.
function LobbyLayout.destinationSpot(dest: any): (number, number)
	if dest.zone then
		local zone = LobbyLayout.zone(dest.zone)
		if zone then
			local a = zone.area
			return (a.minX + a.maxX) / 2, (a.minZ + a.maxZ) / 2
		end
	end
	return dest.x or 0, dest.z or 0
end

-- Framed posters of made-up games on the side walls, between the windows (by z), with
-- a picture light over each. Skips the spot over the fireplace.
LobbyLayout.posters = {
	{ side = -1, z = -37.5, title = "Rocket Race", color = Color3.fromRGB(62, 132, 214) },
	{ side = -1, z = -107.5, title = "Dragon Dominoes", color = Color3.fromRGB(80, 160, 96) },
	{ side = 1, z = -37.5, title = "Lucky Ladders", color = Color3.fromRGB(240, 150, 52) },
	{ side = 1, z = -72.5, title = "Midnight Manor", color = Color3.fromRGB(110, 70, 190) },
	{ side = 1, z = -107.5, title = "Island Hop", color = Color3.fromRGB(40, 160, 170) },
}

-- Trees and lamp posts outside, seen through the windows.
LobbyLayout.outsideTrees = {
	{ -116, -8 }, { -124, -38 }, { -114, -66 }, { -126, -96 }, { -116, -128 },
	{ 118, -10 }, { 126, -44 }, { 114, -74 }, { 124, -104 }, { 116, -134 },
	{ -70, -166 }, { -20, -172 }, { 30, -168 }, { 80, -170 },
	{ -60, 36 }, { 60, 36 },
}
LobbyLayout.outsideLamps = { { -110, -55 }, { 110, -90 }, { -24, 30 }, { 24, 30 } }

-- Camera spots for the store thumbnails and trailer (docs/Store page.md shot list).
-- Each is a camera position and the point it looks at.
LobbyLayout.shots = {
	{ name = "Wide", from = { 70, 26, 14 }, at = { -12, 2, -84 } },
	{ name = "NightWide", from = { 0, 18, 16 }, at = { 0, 6, -110 } },
	{ name = "CardTable", from = { 84, 12, -80 }, at = { 72, 3, -92 } },
	{ name = "BoardTable", from = { -24, 13, -80 }, at = { -36, 3, -93 } },
	{ name = "StrategyTable", from = { -22, 10, -8 }, at = { -34, 3, -20 } },
	{ name = "PartyStage", from = { 0, 12, -92 }, at = { 0, 8, -140 } },
	{ name = "Lounge", from = { 22, 9, -40 }, at = { 0, 3, -62 } },
}

-- World footprint (axis-aligned) of a prop.
function LobbyLayout.propRect(prop: any): Rect
	local turned = math.abs(prop.yaw or 0) % 180 == 90
	local w = if turned then prop.d else prop.w
	local d = if turned then prop.w else prop.d
	return rect(prop.x - w / 2, prop.x + w / 2, prop.z - d / 2, prop.z + d / 2)
end

-- Distance from a point to a rectangle (0 when inside).
function LobbyLayout.distanceToRect(x: number, z: number, r: Rect): number
	local dx = math.max(r.minX - x, 0, x - r.maxX)
	local dz = math.max(r.minZ - z, 0, z - r.maxZ)
	return math.sqrt(dx * dx + dz * dz)
end

function LobbyLayout.inside(x: number, z: number, r: Rect): boolean
	return x >= r.minX and x <= r.maxX and z >= r.minZ and z <= r.maxZ
end

function LobbyLayout.overlaps(a: Rect, b: Rect): boolean
	return a.minX < b.maxX and b.minX < a.maxX and a.minZ < b.maxZ and b.minZ < a.maxZ
end

function LobbyLayout.zone(id: string): any?
	for _, zone in LobbyLayout.zones do
		if zone.id == id then
			return zone
		end
	end
	return nil
end

-- Floor height at a point: the stage is raised.
function LobbyLayout.floorAt(x: number, z: number): number
	if LobbyLayout.inside(x, z, LobbyLayout.stage) then
		return LobbyLayout.STAGE_Y
	end
	return LobbyLayout.FLOOR_Y
end

-- Spot for table `index` of Config.DefaultTables: x, y (floor), z. nil past the list.
function LobbyLayout.tableSpot(index: number): (number?, number?, number?)
	local spot = LobbyLayout.tables[index]
	if not spot then
		return nil, nil, nil
	end
	return spot.x, LobbyLayout.floorAt(spot.x, spot.z), spot.z
end

return LobbyLayout
