-- Small models shared by the table scenes: pawns, player tokens, dice, houses, soldiers.
-- Everything is built from parts in code, so it ships with the scripts and needs nothing
-- from ReplicatedStorage.Assets. Art rules are in the vault's Art Direction note: chunky,
-- toy-like, readable from a seat.
--
-- Every model stands on `cf` (a CFrame on the surface, Y up, -Z is "forward"), takes one
-- size number, and is returned parented to `parent`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Pieces = require(script.Parent.Pieces)

local Models = {}

Models.WOOD = Color3.fromRGB(150, 102, 62)
Models.WALNUT = Color3.fromRGB(92, 58, 38)
Models.GOLD = Color3.fromRGB(226, 178, 72)
Models.IVORY = Color3.fromRGB(242, 230, 206)
Models.INK = Color3.fromRGB(38, 32, 42)
Models.STEEL = Color3.fromRGB(190, 195, 205)

local UP = CFrame.Angles(0, 0, math.rad(90))

-- How far a detail (a door, a window, a stripe) stands out of the face it's on, in studs
-- whatever the model's size: closer than about 0.01 the two faces fight (flicker).
Models.PROUD = 0.02

function Models.block(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	return Pieces.part({ Name = name, Size = size, CFrame = cf, Color = color, Material = material or Enum.Material.SmoothPlastic, CanQuery = false, Parent = parent })
end

-- A vertical cylinder with its base on `cf`.
function Models.cyl(parent: Instance, name: string, diameter: number, height: number, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local part = Models.block(parent, name, Vector3.new(height, diameter, diameter), cf * CFrame.new(0, height / 2, 0) * UP, color, material)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- A ball centered on `cf`.
function Models.ball(parent: Instance, name: string, diameter: number, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local part = Models.block(parent, name, Vector3.one * diameter, cf, color, material)
	part.Shape = Enum.PartType.Ball
	return part
end

-- A soft ellipsoid centered on `cf`.
function Models.egg(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local part = Models.block(parent, name, size, cf, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- A smooth mesh from ReplicatedStorage.Assets.Meshes (see docs/Meshes.md), sized to
-- `size` and centered on `cf`, or nil when that mesh hasn't been imported. Callers build
-- the same shape from parts when this returns nil.
function Models.mesh(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3?, material: Enum.Material?): MeshPart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Meshes")
	local found = folder and folder:FindFirstChild(name)
	if found and found:IsA("Model") then
		found = found:FindFirstChildWhichIsA("MeshPart", true)
	end
	if not (found and found:IsA("MeshPart")) then
		return nil
	end
	local part = found:Clone()
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	if color and part.TextureID == "" then
		part.Color = color
	end
	if material then
		part.Material = material
	end
	part.Parent = parent
	return part
end

local function newModel(name: string, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

local function darker(color: Color3, amount: number?): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount or 0.3)
end

-- A plain playing piece: stepped base, soft body, collar and round head.
function Models.pawn(parent: Instance, cf: CFrame, color: Color3, height: number): Model
	local m = newModel("Pawn", parent)
	local h = height
	if Models.mesh(m, "Pawn", Vector3.new(h * 0.62, h, h * 0.62), cf * CFrame.new(0, h / 2, 0), color, Enum.Material.SmoothPlastic) then
		return m
	end
	Models.cyl(m, "Base", h * 0.62, h * 0.1, cf, darker(color, 0.25))
	Models.cyl(m, "BaseBead", h * 0.56, h * 0.03, cf * CFrame.new(0, h * 0.1, 0), Models.GOLD)
	Models.cyl(m, "Step", h * 0.5, h * 0.08, cf * CFrame.new(0, h * 0.1, 0), color)
	Models.egg(m, "Body", Vector3.new(h * 0.42, h * 0.6, h * 0.42), cf * CFrame.new(0, h * 0.42, 0), color)
	Models.cyl(m, "Collar", h * 0.36, h * 0.05, cf * CFrame.new(0, h * 0.64, 0), darker(color, 0.25))
	Models.ball(m, "Head", h * 0.36, cf * CFrame.new(0, h * 0.82, 0), color)
	-- A small highlight dot so the head reads as glossy from a seat.
	Models.ball(m, "Shine", h * 0.08, cf * CFrame.new(-h * 0.08, h * 0.92, -h * 0.1), color:Lerp(Color3.new(1, 1, 1), 0.55))
	return m
end

-- Player tokens for Property Party: original designs, one per seat, main color = seat color.
local function at(cf: CFrame, h: number, x: number, y: number, z: number): CFrame
	return cf * CFrame.new(x * h, y * h, z * h)
end

local TOKENS: { (m: Model, cf: CFrame, c: Color3, h: number) -> () } = {
	function(m, cf, c, h) -- Rocket
		Models.egg(m, "Body", Vector3.new(0.36, 0.84, 0.36) * h, at(cf, h, 0, 0.56, 0), Models.IVORY)
		Models.egg(m, "Nose", Vector3.new(0.24, 0.3, 0.24) * h, at(cf, h, 0, 0.88, 0), c)
		Models.ball(m, "Window", 0.15 * h, at(cf, h, 0, 0.6, -0.15), Color3.fromRGB(90, 190, 230))
		for i = 0, 2 do
			Models.block(m, "Fin", Vector3.new(0.06, 0.28, 0.2) * h, cf * CFrame.Angles(0, math.rad(i * 120), 0) * CFrame.new(0, 0.28 * h, 0.2 * h), c)
		end
	end,
	function(m, cf, c, h) -- Sneaker
		Models.block(m, "Sole", Vector3.new(0.36, 0.1, 0.78) * h, at(cf, h, 0, 0.18, 0), Models.IVORY)
		Models.egg(m, "Toe", Vector3.new(0.36, 0.3, 0.46) * h, at(cf, h, 0, 0.3, -0.16), c)
		Models.block(m, "Ankle", Vector3.new(0.34, 0.5, 0.36) * h, at(cf, h, 0, 0.46, 0.18), c)
		Models.block(m, "Cuff", Vector3.new(0.34 * h + 2 * Models.PROUD, 0.08 * h + 2 * Models.PROUD, 0.36 * h + 2 * Models.PROUD), at(cf, h, 0, 0.72, 0.18), Models.IVORY)
		for i = 0, 1 do
			Models.block(m, "Lace", Vector3.new(0.34 * h - 2 * Models.PROUD, 0.04 * h, 0.06 * h), at(cf, h, 0, 0.42 + i * 0.06, -0.1 + i * 0.07), Models.IVORY)
		end
	end,
	function(m, cf, c, h) -- Cat
		Models.egg(m, "Body", Vector3.new(0.46, 0.62, 0.46) * h, at(cf, h, 0, 0.4, 0.02), c)
		Models.ball(m, "Head", 0.4 * h, at(cf, h, 0, 0.8, -0.04), c)
		for _, s in { -1, 1 } do
			Models.block(m, "Ear", Vector3.new(0.1, 0.16, 0.08) * h, at(cf, h, s * 0.12, 1, -0.04) * CFrame.Angles(0, 0, math.rad(-s * 12)), c)
			Models.ball(m, "Eye", 0.07 * h, at(cf, h, s * 0.08, 0.84, -0.22), Models.INK)
		end
		Models.block(m, "Tail", Vector3.new(0.08, 0.5, 0.08) * h, at(cf, h, 0.14, 0.42, 0.3) * CFrame.Angles(math.rad(-16), 0, 0), darker(c, 0.2))
	end,
	function(m, cf, c, h) -- Guitar
		local tilt = at(cf, h, 0, 0.14, 0) * CFrame.Angles(0, 0, math.rad(-10))
		Models.egg(m, "Lower", Vector3.new(0.48, 0.42, 0.14) * h, tilt * CFrame.new(0, 0.2 * h, 0), c)
		Models.egg(m, "Upper", Vector3.new(0.34, 0.3, 0.14) * h, tilt * CFrame.new(0, 0.48 * h, 0), c)
		Models.cyl(m, "Hole", 0.13 * h, 0.02 * h, tilt * CFrame.new(0, 0.3 * h, -0.075 * h) * CFrame.Angles(math.rad(90), 0, 0), Models.INK)
		Models.block(m, "Neck", Vector3.new(0.07, 0.44, 0.05) * h, tilt * CFrame.new(0, 0.74 * h, 0), Models.WOOD)
		Models.block(m, "Headstock", Vector3.new(0.13, 0.13, 0.09) * h, tilt * CFrame.new(0, 1 * h, 0), Models.WALNUT)
	end,
	function(m, cf, c, h) -- Robot
		Models.block(m, "Body", Vector3.new(0.46, 0.42, 0.34) * h, at(cf, h, 0, 0.4, 0), c)
		Models.block(m, "Head", Vector3.new(0.36, 0.26, 0.3) * h, at(cf, h, 0, 0.76, 0), Models.STEEL)
		Models.block(m, "Chest", Vector3.new(0.2 * h, 0.1 * h, 2 * Models.PROUD), at(cf, h, 0, 0.44, -0.17), Models.GOLD)
		for _, s in { -1, 1 } do
			Models.ball(m, "Eye", 0.08 * h, at(cf, h, s * 0.08, 0.78, -0.15), Models.INK)
			Models.block(m, "Arm", Vector3.new(0.08, 0.34, 0.1) * h, at(cf, h, s * 0.28, 0.42, 0), Models.STEEL)
		end
		Models.block(m, "Antenna", Vector3.new(0.03, 0.16, 0.03) * h, at(cf, h, 0, 0.96, 0), Models.STEEL)
		Models.ball(m, "Tip", 0.08 * h, at(cf, h, 0, 1.04, 0), c)
	end,
	function(m, cf, c, h) -- Duck
		Models.egg(m, "Body", Vector3.new(0.5, 0.42, 0.68) * h, at(cf, h, 0, 0.34, 0.06), c)
		Models.ball(m, "Head", 0.34 * h, at(cf, h, 0, 0.72, -0.16), c)
		Models.egg(m, "Bill", Vector3.new(0.22, 0.08, 0.2) * h, at(cf, h, 0, 0.7, -0.36), Color3.fromRGB(240, 150, 50))
		Models.block(m, "Tail", Vector3.new(0.14, 0.2, 0.1) * h, at(cf, h, 0, 0.5, 0.4) * CFrame.Angles(math.rad(-30), 0, 0), c)
		for _, s in { -1, 1 } do
			Models.ball(m, "Eye", 0.06 * h, at(cf, h, s * 0.12, 0.76, -0.27), Models.INK)
		end
	end,
	function(m, cf, c, h) -- Cactus
		Models.cyl(m, "Pot", 0.44 * h, 0.2 * h, at(cf, h, 0, 0.12, 0), c)
		Models.egg(m, "Trunk", Vector3.new(0.28, 0.82, 0.28) * h, at(cf, h, 0, 0.66, 0), Color3.fromRGB(70, 150, 90))
		for _, s in { -1, 1 } do
			Models.block(m, "ArmOut", Vector3.new(0.22, 0.09, 0.09) * h, at(cf, h, s * 0.2, 0.6 + s * 0.04, 0), Color3.fromRGB(70, 150, 90))
			Models.egg(m, "ArmUp", Vector3.new(0.11, 0.32, 0.11) * h, at(cf, h, s * 0.3, 0.74 + s * 0.04, 0), Color3.fromRGB(70, 150, 90))
		end
	end,
	function(m, cf, c, h) -- Flying saucer
		Models.cyl(m, "Stem", 0.06 * h, 0.5 * h, at(cf, h, 0, 0.12, 0), Models.STEEL)
		Models.egg(m, "Saucer", Vector3.new(0.86, 0.2, 0.86) * h, at(cf, h, 0, 0.66, 0), c)
		Models.egg(m, "Dome", Vector3.new(0.38, 0.38, 0.38) * h, at(cf, h, 0, 0.8, 0), Color3.fromRGB(150, 225, 240))
		for i = 0, 5 do
			local a = i / 6 * math.pi * 2
			Models.ball(m, "Light", 0.08 * h, at(cf, h, math.sin(a) * 0.32, 0.64, math.cos(a) * 0.32), Models.GOLD)
		end
	end,
}

function Models.token(parent: Instance, cf: CFrame, seat: number, color: Color3, height: number): Model
	local m = newModel("Token", parent)
	Models.cyl(m, "Base", height * 0.72, height * 0.12, cf, darker(color, 0.25))
	-- Tokens are drawn facing -Z; turn them to look out at seat 1's side of the board.
	TOKENS[(seat - 1) % #TOKENS + 1](m, cf * CFrame.Angles(0, math.rad(180), 0), color, height)
	return m
end

local PIPS = {
	{ { 0, 0 } },
	{ { -1, -1 }, { 1, 1 } },
	{ { -1, -1 }, { 0, 0 }, { 1, 1 } },
	{ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } },
	{ { -1, -1 }, { 1, -1 }, { 0, 0 }, { -1, 1 }, { 1, 1 } },
	{ { -1, -1 }, { 1, -1 }, { -1, 0 }, { 1, 0 }, { -1, 1 }, { 1, 1 } },
}

-- Which values face front and right for each top value (opposite faces add up to 7).
local SIDES = { { 2, 3 }, { 1, 3 }, { 1, 2 }, { 1, 5 }, { 1, 4 }, { 2, 4 } }

-- The pips of `value` on one face of a die. `face` is a CFrame at the face center whose
-- Y axis points out of the die.
local function pips(m: Model, face: CFrame, value: number, size: number, color: Color3)
	for _, pip in PIPS[value] or {} do
		-- Mostly sunk into the face; the 0.016 that stands out keeps the dot's face from
		-- fighting (flickering) with the die's face around it.
		Models.cyl(m, "Pip", size * 0.19, size * 0.03 + 0.016, face * CFrame.new(pip[1] * size * 0.25, -size * 0.03, pip[2] * size * 0.25), color)
	end
end

-- A die with rounded edges and corners showing `value` on top, with the right pips on the
-- four sides too (anyone at the table sees a real die, not a stamped cube).
function Models.die(parent: Instance, cf: CFrame, value: number, size: number, color: Color3?, pipColor: Color3?): Model
	local m = newModel("Die", parent)
	local c = color or Models.IVORY
	local ink = pipColor or Models.INK
	local mid = cf * CFrame.new(0, size / 2, 0)
	local mesh = Models.mesh(m, "Die", Vector3.one * size, mid, c, Enum.Material.SmoothPlastic)
	if not mesh then
		local r = size * 0.12
		local inner = size - 2 * r
		Models.block(m, "Body", Vector3.new(size, inner, inner), mid, c)
		Models.block(m, "BodyY", Vector3.new(inner, size, inner), mid, c)
		Models.block(m, "BodyZ", Vector3.new(inner, inner, size), mid, c)
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					Models.ball(m, "Corner", r * 2, mid * CFrame.new(sx * inner / 2, sy * inner / 2, sz * inner / 2), c)
				end
			end
		end
	end
	local v = math.clamp(math.floor(value), 1, 6)
	local front, right = SIDES[v][1], SIDES[v][2]
	local half = size / 2
	pips(m, mid * CFrame.new(0, half, 0), v, size, ink)
	pips(m, mid * CFrame.new(0, 0, -half) * CFrame.Angles(math.rad(-90), 0, 0), front, size, ink)
	pips(m, mid * CFrame.new(0, 0, half) * CFrame.Angles(math.rad(90), 0, 0), 7 - front, size, ink)
	pips(m, mid * CFrame.new(half, 0, 0) * CFrame.Angles(0, 0, math.rad(-90)), right, size, ink)
	pips(m, mid * CFrame.new(-half, 0, 0) * CFrame.Angles(0, 0, math.rad(90)), 7 - right, size, ink)
	return m
end

-- A little house: walls, door and a pitched roof (a block turned 45 degrees, half sunk in).
function Models.house(parent: Instance, cf: CFrame, color: Color3, size: number, roofColor: Color3?): Model
	local m = newModel("House", parent)
	Models.block(m, "Walls", Vector3.new(size, size * 0.62, size * 0.86), cf * CFrame.new(0, size * 0.31, 0), color)
	Models.block(m, "Roof", Vector3.new(size + 2 * Models.PROUD, size * 0.68, size * 0.68), cf * CFrame.new(0, size * 0.62, 0) * CFrame.Angles(math.rad(45), 0, 0), roofColor or darker(color, 0.35))
	Models.block(m, "Door", Vector3.new(size * 0.24, size * 0.36 - Models.PROUD, 2 * Models.PROUD), cf * CFrame.new(0, (size * 0.36 + Models.PROUD) / 2, -size * 0.43), Models.WALNUT)
	return m
end

-- A hotel: long, tall, with rows of windows and a gold roof trim.
function Models.hotel(parent: Instance, cf: CFrame, color: Color3, size: number): Model
	local m = newModel("Hotel", parent)
	Models.block(m, "Walls", Vector3.new(size * 1.5, size * 0.85, size * 0.7), cf * CFrame.new(0, size * 0.425, 0), color)
	Models.block(m, "Roof", Vector3.new(size * 1.6, size * 0.12, size * 0.8), cf * CFrame.new(0, size * 0.91, 0), Models.GOLD)
	for row = 0, 1 do
		for col = -1, 1 do
			Models.block(m, "Window", Vector3.new(size * 0.22, size * 0.2, 2 * Models.PROUD), cf * CFrame.new(col * size * 0.42, size * (0.28 + row * 0.32), -size * 0.35), Color3.fromRGB(255, 232, 170))
		end
	end
	return m
end

-- A toy soldier in `color`: body, head and a helmet.
function Models.soldier(parent: Instance, cf: CFrame, color: Color3, height: number): Model
	local m = newModel("Soldier", parent)
	local h = height
	Models.cyl(m, "Stand", h * 0.46, h * 0.08, cf, darker(color, 0.3))
	Models.egg(m, "Body", Vector3.new(h * 0.36, h * 0.62, h * 0.3), cf * CFrame.new(0, h * 0.38, 0), color)
	Models.ball(m, "Head", h * 0.26, cf * CFrame.new(0, h * 0.78, 0), Color3.fromRGB(240, 206, 170))
	Models.egg(m, "Helmet", Vector3.new(h * 0.32, h * 0.18, h * 0.32), cf * CFrame.new(0, h * 0.88, 0), darker(color, 0.2))
	Models.block(m, "Rifle", Vector3.new(h * 0.05, h * 0.62, h * 0.05), cf * CFrame.new(h * 0.21, h * 0.46, 0), Models.WALNUT)
	return m
end

-- A small flag on a pole, for marking who owns something.
function Models.flag(parent: Instance, cf: CFrame, color: Color3, height: number): Model
	local m = newModel("Flag", parent)
	Models.cyl(m, "Pole", height * 0.07, height, cf, Models.STEEL)
	Models.block(m, "Cloth", Vector3.new(height * 0.5, height * 0.32, height * 0.03), cf * CFrame.new(height * 0.27, height * 0.82, 0), color)
	return m
end

return Models
