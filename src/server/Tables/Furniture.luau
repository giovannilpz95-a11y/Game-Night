-- Detailed game tables and stools, built from parts in code (Config.Tables.furniture =
-- "Detailed"). Round tables are a poker-style top: walnut top with a brass band, a padded
-- leather rail around the felt and a turned pedestal on four feet. Square tables have
-- rounded corners, the same rail and four turned legs. Each seat is a stool with a buttoned
-- cushion and a footrest.
--
-- If ReplicatedStorage.Assets.Meshes has the meshes from /mnt/project-files/meshes (see
-- docs/Meshes.md), the smooth mesh is used for the parts that look faceted as Roblox
-- cylinders: the round top, the rail and the stool cushion. Everything works without them.
--
-- Part budget (phones): about 70 parts for a round table and 9 per stool.

local Models = require(script.Parent.Models)
local Pieces = require(script.Parent.Pieces)

local Furniture = {}

Furniture.WOOD = Color3.fromRGB(122, 80, 52)
Furniture.WALNUT = Color3.fromRGB(78, 48, 32)
Furniture.FELT = Color3.fromRGB(40, 100, 72)
Furniture.LEATHER = Color3.fromRGB(58, 34, 30)
Furniture.BRASS = Color3.fromRGB(214, 170, 82)
Furniture.CUSHION = Color3.fromRGB(196, 72, 66)

Furniture.TOP_HEIGHT = 3.4 -- felt surface, above the floor
Furniture.SEAT_TOP = 2.0 -- stool cushion top, above the floor
Furniture.ROUND_DIAMETER = 13
Furniture.ROUND_SEAT_RADIUS = 8.2
Furniture.SQUARE_SIZE = 9
Furniture.SQUARE_SEAT_RADIUS = 6.2

local RAIL_SEGMENTS = 28

local function solid(part: BasePart): BasePart
	part.CanCollide = true
	return part
end

-- A flat, horizontal ring made of short lying cylinders (a padded rail or a brass hoop).
-- `cf` is the center of the ring on the surface it sits on.
local function ring(parent: Instance, name: string, cf: CFrame, radius: number, thickness: number, color: Color3, material: Enum.Material, segments: number)
	local chord = 2 * radius * math.sin(math.pi / segments) * 1.08 -- a little overlap hides the joins
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * math.pi * 2
		local at = cf * CFrame.new(math.sin(a) * radius, thickness / 2, math.cos(a) * radius) * CFrame.Angles(0, a, 0)
		-- A cylinder's axis is its X: turn it to run along the tangent.
		local part = Models.block(parent, name, Vector3.new(chord, thickness, thickness), at, color, material)
		part.Shape = Enum.PartType.Cylinder
	end
end

-- A smooth mesh from Assets.Meshes when it's there, else `fallback()`.
local function meshOr(parent: Instance, meshName: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, fallback: () -> ()): BasePart?
	local part = Models.mesh(parent, meshName, size, cf, color, material)
	if part then
		return part
	end
	fallback()
	return nil
end

-- A thin printed line on the felt (a gold circle or rounded square), drawn with a
-- SurfaceGui stroke so it costs one invisible part.
local function feltLine(parent: Instance, cf: CFrame, width: number, round: boolean)
	local plate = Pieces.part({
		Name = "FeltLine",
		Size = Vector3.new(width, 0.01, width),
		CFrame = cf * CFrame.new(0, 0.03, 0),
		Transparency = 1,
		CanQuery = false,
		Parent = parent,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 1
	gui.MaxDistance = 90
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = if round then UDim.new(0.5, 0) else UDim.new(0.08, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Furniture.BRASS
	stroke.Thickness = 3
	stroke.Transparency = 0.35
	stroke.Parent = frame
	frame.Parent = gui
	gui.Parent = plate
end

-- A turned leg or column from the floor at `cf` up `height` studs: foot, taper, bead,
-- shaft and a collar under the top.
local function turnedLeg(parent: Instance, cf: CFrame, height: number, width: number, color: Color3)
	Models.cyl(parent, "LegFoot", width * 1.25, height * 0.06, cf, Furniture.WALNUT, Enum.Material.Wood)
	Models.egg(parent, "LegBulb", Vector3.new(width * 1.15, height * 0.22, width * 1.15), cf * CFrame.new(0, height * 0.2, 0), color, Enum.Material.Wood)
	Models.cyl(parent, "LegBead", width * 1.05, height * 0.04, cf * CFrame.new(0, height * 0.33, 0), Furniture.BRASS, Enum.Material.Metal)
	solid(Models.cyl(parent, "Leg", width * 0.72, height * 0.62, cf * CFrame.new(0, height * 0.33, 0), color, Enum.Material.Wood))
	Models.cyl(parent, "LegCollar", width * 1.1, height * 0.07, cf * CFrame.new(0, height * 0.93, 0), Furniture.WALNUT, Enum.Material.Wood)
end

-- A stool standing on `floor` (its -Z faces the table). The Seat part that does the
-- sitting is added by `stools`, invisible, with its top at Furniture.SEAT_TOP.
local function stool(parent: Instance, floor: CFrame)
	local h = Furniture.SEAT_TOP
	Models.cyl(parent, "StoolBase", 1.7, 0.12, floor, Furniture.WALNUT, Enum.Material.Wood)
	Models.cyl(parent, "StoolBaseTrim", 1.78, 0.03, floor * CFrame.new(0, 0.1, 0), Furniture.BRASS, Enum.Material.Metal)
	solid(Models.cyl(parent, "StoolColumn", 0.42, h - 0.5, floor * CFrame.new(0, 0.12, 0), Furniture.WOOD, Enum.Material.Wood))
	Models.cyl(parent, "Footrest", 1.3, 0.07, floor * CFrame.new(0, 0.7, 0), Furniture.BRASS, Enum.Material.Metal)
	Models.cyl(parent, "FootrestHub", 0.6, 0.18, floor * CFrame.new(0, 0.64, 0), Furniture.WALNUT, Enum.Material.Wood)
	Models.cyl(parent, "SeatPan", 1.9, 0.14, floor * CFrame.new(0, h - 0.5, 0), Furniture.WALNUT, Enum.Material.Wood)
	local cushionAt = floor * CFrame.new(0, h - 0.36, 0)
	meshOr(parent, "StoolCushion", Vector3.new(1.95, 0.36, 1.95), cushionAt * CFrame.new(0, 0.18, 0), Furniture.CUSHION, Enum.Material.Fabric, function()
		Models.cyl(parent, "Cushion", 1.86, 0.26, cushionAt, Furniture.CUSHION, Enum.Material.Fabric)
		Models.egg(parent, "CushionDome", Vector3.new(1.8, 0.22, 1.8), cushionAt * CFrame.new(0, 0.25, 0), Furniture.CUSHION, Enum.Material.Fabric)
		Models.cyl(parent, "Piping", 1.96, 0.05, cushionAt * CFrame.new(0, 0.2, 0), Furniture.CUSHION:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Fabric)
	end)
	Models.cyl(parent, "Button", 0.16, 0.04, floor * CFrame.new(0, h - 0.02, 0), Furniture.CUSHION:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.Fabric)
end

local function newSeat(name: string, cf: CFrame, parent: Instance): Seat
	local seat = Instance.new("Seat")
	seat.Name = name
	seat.Size = Vector3.new(2, 1, 2)
	seat.CFrame = cf
	seat.Anchored = true
	seat.Transparency = 1
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.Parent = parent
	return seat
end

-- `count` stools around `center` at `radius`, seat 1 on +Z, each Seat facing the middle.
local function stools(model: Model, center: Vector3, floorY: number, radius: number, count: number)
	local folder = Instance.new("Model")
	folder.Name = "Stools"
	folder.Parent = model
	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2
		local pos = Vector3.new(center.X + math.sin(angle) * radius, floorY, center.Z + math.cos(angle) * radius)
		local floor = CFrame.lookAt(pos, Vector3.new(center.X, floorY, center.Z))
		stool(folder, floor)
		newSeat(`Seat{i}`, floor * CFrame.new(0, Furniture.SEAT_TOP - 0.5, 0), model)
	end
end

local function anchor(model: Model, cf: CFrame)
	Pieces.part({
		Name = "BoardAnchor",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = cf,
		Transparency = 1,
		CanQuery = false,
		Parent = model,
	})
end

function Furniture.round(at: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Table_Round8"
	local d = Furniture.ROUND_DIAMETER
	local surfaceY = at.Y + Furniture.TOP_HEIGHT
	local base = CFrame.new(at)
	local top = CFrame.new(at.X, surfaceY, at.Z)
	local feltD = d - 1.5

	-- Top: walnut slab with a brass band around its edge and a darker apron under it.
	local slabAt = top * CFrame.new(0, -0.4, 0)
	meshOr(model, "TableTopRound", Vector3.new(d, 0.4, d), slabAt * CFrame.new(0, 0.2, 0), Furniture.WOOD, Enum.Material.Wood, function()
		solid(Models.cyl(model, "Top", d, 0.4, slabAt, Furniture.WOOD, Enum.Material.Wood))
	end)
	Models.cyl(model, "Band", d + 0.08, 0.07, slabAt * CFrame.new(0, 0.16, 0), Furniture.BRASS, Enum.Material.Metal)
	Models.cyl(model, "Apron", d - 1.2, 0.45, slabAt * CFrame.new(0, -0.45, 0), Furniture.WALNUT, Enum.Material.Wood)
	Models.cyl(model, "ApronLip", d - 0.9, 0.08, slabAt * CFrame.new(0, -0.08, 0), Furniture.WALNUT, Enum.Material.Wood)

	-- Felt, a printed line on it, and the padded rail around it.
	Models.cyl(model, "Felt", feltD, 0.02, top, Furniture.FELT, Enum.Material.Fabric)
	feltLine(model, top, feltD - 2.2, true)
	local railR = feltD / 2 + 0.2
	meshOr(model, "TableRailRound", Vector3.new(railR * 2 + 0.42, 0.42, railR * 2 + 0.42), top * CFrame.new(0, 0.21, 0), Furniture.LEATHER, Enum.Material.Leather, function()
		ring(model, "Rail", top * CFrame.new(0, -0.04, 0), railR, 0.42, Furniture.LEATHER, Enum.Material.Leather, RAIL_SEGMENTS)
	end)

	-- Pedestal: column with turned rings, on four feet with brass caps.
	local footY = 0.3
	Models.cyl(model, "PedestalBase", 2.8, footY, base, Furniture.WALNUT, Enum.Material.Wood)
	solid(Models.cyl(model, "Pedestal", 1.3, Furniture.TOP_HEIGHT - 0.85 - footY, base * CFrame.new(0, footY, 0), Furniture.WOOD, Enum.Material.Wood))
	Models.egg(model, "PedestalBulb", Vector3.new(2, 1.1, 2), base * CFrame.new(0, 1.05, 0), Furniture.WOOD, Enum.Material.Wood)
	Models.cyl(model, "PedestalRing", 2.05, 0.1, base * CFrame.new(0, 1.0, 0), Furniture.BRASS, Enum.Material.Metal)
	Models.cyl(model, "PedestalCollar", 2.2, 0.22, base * CFrame.new(0, Furniture.TOP_HEIGHT - 1.1, 0), Furniture.WALNUT, Enum.Material.Wood)
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		local dir = CFrame.Angles(0, a, 0)
		Models.block(model, "Foot", Vector3.new(0.7, 0.34, 3.4), base * dir * CFrame.new(0, 0.17, 1.6), Furniture.WALNUT, Enum.Material.Wood)
		Models.block(model, "FootTop", Vector3.new(0.5, 0.16, 2.6), base * dir * CFrame.new(0, 0.38, 1.3) * CFrame.Angles(math.rad(-6), 0, 0), Furniture.WOOD, Enum.Material.Wood)
		Models.ball(model, "FootCap", 0.5, base * dir * CFrame.new(0, 0.22, 3.25), Furniture.BRASS, Enum.Material.Metal)
	end

	stools(model, at, at.Y, Furniture.ROUND_SEAT_RADIUS, 8)
	anchor(model, CFrame.new(at.X, surfaceY + 0.05, at.Z))
	return model
end

-- A rounded rectangle slab `w` x `w` with corner radius `r`, `h` tall, base on `cf`.
local function roundedSlab(parent: Instance, name: string, w: number, r: number, h: number, cf: CFrame, color: Color3, material: Enum.Material): { BasePart }
	local parts = {}
	table.insert(parts, Models.block(parent, name, Vector3.new(w - 2 * r, h, w), cf * CFrame.new(0, h / 2, 0), color, material))
	table.insert(parts, Models.block(parent, name, Vector3.new(w, h, w - 2 * r), cf * CFrame.new(0, h / 2, 0), color, material))
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			table.insert(parts, Models.cyl(parent, name, r * 2, h, cf * CFrame.new(sx * (w / 2 - r), 0, sz * (w / 2 - r)), color, material))
		end
	end
	return parts
end

function Furniture.square(at: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Table_Square4"
	local w = Furniture.SQUARE_SIZE
	local surfaceY = at.Y + Furniture.TOP_HEIGHT
	local top = CFrame.new(at.X, surfaceY, at.Z)
	local slabAt = top * CFrame.new(0, -0.4, 0)
	local r = 0.7

	for _, part in roundedSlab(model, "Top", w, r, 0.4, slabAt, Furniture.WOOD, Enum.Material.Wood) do
		solid(part)
	end
	roundedSlab(model, "Band", w + 0.08, r + 0.04, 0.07, slabAt * CFrame.new(0, 0.16, 0), Furniture.BRASS, Enum.Material.Metal)
	-- Apron: four boards under the top, set in from the edge.
	local apron = w - 1.4
	for i = 0, 3 do
		local side = CFrame.Angles(0, math.rad(i * 90), 0)
		Models.block(model, "Apron", Vector3.new(apron, 0.5, 0.18), slabAt * side * CFrame.new(0, -0.25, apron / 2), Furniture.WALNUT, Enum.Material.Wood)
	end

	local feltW = w - 1.4
	roundedSlab(model, "Felt", feltW, 0.4, 0.02, top, Furniture.FELT, Enum.Material.Fabric)
	feltLine(model, top, feltW - 1.6, false)
	-- Rail: a padded tube along each side and a ball at each corner.
	local railR = feltW / 2 + 0.15
	local tube = 0.4
	for i = 0, 3 do
		local side = CFrame.Angles(0, math.rad(i * 90), 0)
		local part = Models.block(model, "Rail", Vector3.new(railR * 2, tube, tube), top * side * CFrame.new(0, tube / 2 - 0.04, railR), Furniture.LEATHER, Enum.Material.Leather)
		part.Shape = Enum.PartType.Cylinder
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Models.ball(model, "RailCorner", tube, top * CFrame.new(sx * railR, tube / 2 - 0.04, sz * railR), Furniture.LEATHER, Enum.Material.Leather)
		end
	end

	-- Legs at the corners, under the apron.
	local legAt = w / 2 - 1.0
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			turnedLeg(model, CFrame.new(at.X + sx * legAt, at.Y, at.Z + sz * legAt), Furniture.TOP_HEIGHT - 0.4, 0.62, Furniture.WOOD)
		end
	end

	stools(model, at, at.Y, Furniture.SQUARE_SEAT_RADIUS, 4)
	anchor(model, CFrame.new(at.X, surfaceY + 0.05, at.Z))
	return model
end

function Furniture.build(shape: string, at: Vector3): Model
	return if shape == "Round8" then Furniture.round(at) else Furniture.square(at)
end

return Furniture
