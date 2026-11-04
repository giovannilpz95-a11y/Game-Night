-- Lobby furniture and decor, built from parts so it ships with the scripts. Every
-- builder takes the prop's floor-center CFrame (front facing -Z, like a Roblox
-- LookVector), its width `w` and depth `d`, and returns a Model. Style rules are in the
-- vault's 05 Research/Art Direction.md: chunky, warm, wood and felt, readable from far.
--
-- No casino props here (slot machines, roulette, chips): the maturity questionnaire
-- answer for gambling is No.

local Props = {}

Props.Colors = {
	wood = Color3.fromRGB(122, 84, 56),
	darkWood = Color3.fromRGB(82, 54, 36),
	lightWood = Color3.fromRGB(176, 128, 86),
	cream = Color3.fromRGB(246, 232, 204),
	brass = Color3.fromRGB(214, 168, 82),
	lampWarm = Color3.fromRGB(255, 214, 168),
	tableLight = Color3.fromRGB(255, 242, 226), -- near white over play areas
	ink = Color3.fromRGB(38, 34, 60),
	purple = Color3.fromRGB(110, 70, 190),
	leaf = Color3.fromRGB(70, 140, 72),
	leafDark = Color3.fromRGB(46, 104, 56),
}
local C = Props.Colors

-- Bright box colors for the game shelves (made-up games, no real box art).
local BOX_COLORS = {
	Color3.fromRGB(226, 76, 76),
	Color3.fromRGB(62, 132, 214),
	Color3.fromRGB(246, 190, 60),
	Color3.fromRGB(80, 176, 104),
	Color3.fromRGB(150, 92, 204),
	Color3.fromRGB(240, 128, 52),
	Color3.fromRGB(236, 236, 230),
	Color3.fromRGB(40, 44, 60),
	Color3.fromRGB(232, 104, 160),
	Color3.fromRGB(70, 190, 196),
}

-- A part relative to `origin`. `at` is the part's center in the prop's local space.
local function part(model: Model, origin: CFrame, at: CFrame, props: { [string]: any }): BasePart
	local p: BasePart = Instance.new(props.Class or "Part") :: any
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CastShadow = true
	for key, value in props do
		if key ~= "Class" then
			(p :: any)[key] = value
		end
	end
	p.CFrame = origin * at
	p.Parent = model
	return p
end
Props.part = part

local function box(model, origin, x, y, z, sx, sy, sz, props)
	props = props or {}
	props.Size = Vector3.new(sx, sy, sz)
	return part(model, origin, CFrame.new(x, y, z), props)
end

-- A cylinder standing up (Roblox cylinders lie along X, so turn it).
local function cylinder(model, origin, x, y, z, height, diameter, props)
	props = props or {}
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, diameter, diameter)
	return part(model, origin, CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(90)), props)
end

local function ball(model, origin, x, y, z, diameter, props)
	props = props or {}
	props.Shape = Enum.PartType.Ball
	props.Size = Vector3.new(diameter, diameter, diameter)
	return part(model, origin, CFrame.new(x, y, z), props)
end

local function newModel(name: string, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

-- Text on one face of a part. Returns the label so callers can change it.
function Props.text(target: BasePart, face: Enum.NormalId, text: string, opts: { [string]: any }?): TextLabel
	local o = opts or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = o.name or "Text"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = o.pixelsPerStud or 40
	gui.LightInfluence = o.lightInfluence or 0.3
	gui.CanvasSize = Vector2.new(400, 100) -- ignored in PixelsPerStud mode
	gui.ZOffset = 1
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = if o.background then 0 else 1
	label.BackgroundColor3 = o.background or Color3.new(0, 0, 0)
	label.Size = UDim2.fromScale(1, 1)
	label.Font = o.font or Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = o.color or C.cream
	label.TextScaled = true
	label.TextWrapped = true
	label.RichText = o.rich or false
	label.TextXAlignment = o.align or Enum.TextXAlignment.Center
	local pad = Instance.new("UIPadding")
	local p = UDim.new(o.padding or 0.08, 0)
	pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = p, p, p, p
	pad.Parent = label
	if o.stroke then
		local stroke = Instance.new("UIStroke")
		stroke.Color = o.stroke
		stroke.Thickness = 3
		stroke.Parent = label
	end
	label.Parent = gui
	gui.Parent = target
	return label
end

-- A warm lamp light inside a part.
local function lamp(target: BasePart, range: number, brightness: number, color: Color3?): PointLight
	local light = Instance.new("PointLight")
	light.Range = range
	light.Brightness = brightness
	light.Color = color or C.lampWarm
	light.Shadows = true
	light.Parent = target
	return light
end
Props.lamp = lamp

local function seat(model, origin, x, y, z, sx, sz)
	-- An invisible Seat on top of the cushion, so avatars can sit on the furniture
	-- (good for filming the lounge, and somewhere to wait between games).
	return part(model, origin, CFrame.new(x, y, z), {
		Class = "Seat",
		Size = Vector3.new(sx, 0.4, sz),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
end

---------------------------------------------------------------------------------------
-- Furniture

function Props.Couch(origin: CFrame, w: number, d: number, parent: Instance): Model
	local m = newModel("Couch", parent)
	local fabric = Color3.fromRGB(62, 118, 128)
	local cushion = Color3.fromRGB(80, 142, 150)
	local props = { Color = fabric, Material = Enum.Material.Fabric }
	-- Feet, base, back, arms. The front is -Z.
	for _, fx in { -w / 2 + 0.8, w / 2 - 0.8 } do
		for _, fz in { -d / 2 + 0.6, d / 2 - 0.6 } do
			box(m, origin, fx, 0.25, fz, 0.6, 0.5, 0.6, { Color = C.darkWood, Material = Enum.Material.Wood })
		end
	end
	box(m, origin, 0, 1.1, 0.2, w, 1.2, d - 0.4, props)
	box(m, origin, 0, 2.6, d / 2 - 0.6, w, 3, 1.2, props)
	for _, ax in { -w / 2 + 0.6, w / 2 - 0.6 } do
		box(m, origin, ax, 2.1, 0, 1.2, 2.2, d, props)
	end
	local seats = math.max(2, math.floor((w - 2.4) / 3.6))
	local cw = (w - 2.4) / seats
	for i = 1, seats do
		local cx = -w / 2 + 1.2 + cw * (i - 0.5)
		box(m, origin, cx, 1.95, -0.2, cw - 0.15, 0.5, d - 1.8, { Color = cushion, Material = Enum.Material.Fabric })
		box(m, origin, cx, 3.0, d / 2 - 1.35, cw - 0.3, 1.8, 0.5, { Color = cushion, Material = Enum.Material.Fabric })
		seat(m, origin, cx, 2.25, -0.2, cw - 0.4, d - 2.2)
	end
	-- Throw pillows at the ends.
	box(m, origin, -w / 2 + 1.9, 2.7, d / 2 - 1.8, 1.4, 1.4, 0.5, { Color = Color3.fromRGB(240, 186, 70), Material = Enum.Material.Fabric }).CFrame *= CFrame.Angles(0, 0, math.rad(12))
	box(m, origin, w / 2 - 1.9, 2.7, d / 2 - 1.8, 1.4, 1.4, 0.5, { Color = Color3.fromRGB(226, 96, 86), Material = Enum.Material.Fabric }).CFrame *= CFrame.Angles(0, 0, math.rad(-12))
	return m
end

function Props.CoffeeTable(origin: CFrame, w: number, d: number, parent: Instance): Model
	local m = newModel("CoffeeTable", parent)
	box(m, origin, 0, 1.75, 0, w, 0.3, d, { Color = C.wood, Material = Enum.Material.Wood })
	box(m, origin, 0, 0.7, 0, w - 0.8, 0.15, d - 0.8, { Color = C.darkWood, Material = Enum.Material.Wood })
	for _, lx in { -w / 2 + 0.4, w / 2 - 0.4 } do
		for _, lz in { -d / 2 + 0.4, d / 2 - 0.4 } do
			box(m, origin, lx, 0.8, lz, 0.4, 1.6, 0.4, { Color = C.darkWood, Material = Enum.Material.Wood })
		end
	end
	-- A game left out mid-play: a box, its lid, a few pawns and two dice.
	box(m, origin, -w / 4, 2.1, 0, 2.6, 0.4, 2.6, { Color = BOX_COLORS[2] })
	box(m, origin, -w / 4 + 0.3, 2.4, 0.2, 2.6, 0.2, 2.6, { Color = BOX_COLORS[3] }).CFrame *= CFrame.Angles(0, math.rad(20), 0)
	for i, color in { BOX_COLORS[1], BOX_COLORS[4], BOX_COLORS[5] } do
		cylinder(m, origin, w / 8 + i * 0.6, 2.15, -0.6 + (i % 2) * 0.8, 0.5, 0.4, { Color = color })
		ball(m, origin, w / 8 + i * 0.6, 2.55, -0.6 + (i % 2) * 0.8, 0.35, { Color = color })
	end
	for i = 1, 2 do
		local die = box(m, origin, w / 4 + 0.5 * i, 2.15, 0.8, 0.45, 0.45, 0.45, { Color = Color3.new(1, 1, 1) })
		die.CFrame *= CFrame.Angles(0, math.rad(25 * i), 0)
	end
	return m
end

function Props.FloorLamp(origin: CFrame, _w: number, _d: number, parent: Instance): Model
	local m = newModel("FloorLamp", parent)
	cylinder(m, origin, 0, 0.15, 0, 0.3, 1.8, { Color = C.brass, Material = Enum.Material.Metal })
	cylinder(m, origin, 0, 3.5, 0, 6.6, 0.25, { Color = C.brass, Material = Enum.Material.Metal })
	local bulb = ball(m, origin, 0, 7.0, 0, 0.8, { Color = C.lampWarm, Material = Enum.Material.Neon, CastShadow = false, CanCollide = false })
	-- A drum shade, open at the bottom: the bulb lights the floor around it.
	cylinder(m, origin, 0, 7.4, 0, 1.6, 2.6, { Color = C.cream, Material = Enum.Material.Fabric, Transparency = 0.15, CastShadow = false, CanCollide = false })
	lamp(bulb, 20, 1.3)
	return m
end

function Props.Bench(origin: CFrame, w: number, d: number, parent: Instance): Model
	local m = newModel("Bench", parent)
	box(m, origin, 0, 1.6, 0, w, 0.4, d, { Color = C.lightWood, Material = Enum.Material.Wood })
	box(m, origin, 0, 1.95, 0, w - 0.4, 0.3, d - 0.4, { Color = Color3.fromRGB(150, 52, 62), Material = Enum.Material.Fabric })
	for _, lx in { -w / 2 + 0.6, w / 2 - 0.6 } do
		box(m, origin, lx, 0.7, 0, 0.5, 1.4, d - 0.4, { Color = C.darkWood, Material = Enum.Material.Wood })
	end
	seat(m, origin, 0, 2.2, 0, w - 1, d - 0.6)
	return m
end

function Props.Plant(origin: CFrame, w: number, _d: number, parent: Instance): Model
	local m = newModel("Plant", parent)
	cylinder(m, origin, 0, 1.1, 0, 2.2, w * 0.7, { Color = Color3.fromRGB(196, 110, 72), Material = Enum.Material.Slate })
	cylinder(m, origin, 0, 2.25, 0, 0.1, w * 0.62, { Color = Color3.fromRGB(70, 48, 34), Material = Enum.Material.Ground })
	local rng = Random.new(math.floor(origin.X * 7 + origin.Z * 13))
	for i = 1, 6 do
		local angle = i / 6 * math.pi * 2
		local leaf = box(m, origin, math.sin(angle) * 0.6, 3.6, math.cos(angle) * 0.6, 0.9, 3.4, 0.2, {
			Color = if i % 2 == 0 then C.leaf else C.leafDark,
			Material = Enum.Material.Grass,
			CastShadow = false,
		})
		leaf.CFrame = origin * CFrame.new(math.sin(angle) * 0.7, 3.8, math.cos(angle) * 0.7) * CFrame.Angles(0, angle, 0) * CFrame.Angles(math.rad(-25 - rng:NextNumber() * 15), 0, 0)
	end
	ball(m, origin, 0, 4.4, 0, 2.4, { Color = C.leaf, Material = Enum.Material.Grass })
	return m
end

---------------------------------------------------------------------------------------
-- Shelves, screens and showpieces

-- A tall wooden shelf full of board game boxes standing like books, with a few lying flat.
function Props.GameShelf(origin: CFrame, w: number, d: number, parent: Instance): Model
	local m = newModel("GameShelf", parent)
	local h = 8
	local wood = { Color = C.wood, Material = Enum.Material.Wood }
	box(m, origin, 0, h / 2, d / 2 - 0.15, w, h, 0.3, { Color = C.darkWood, Material = Enum.Material.Wood })
	for _, sx in { -w / 2 + 0.2, w / 2 - 0.2 } do
		box(m, origin, sx, h / 2, 0, 0.4, h, d, wood)
	end
	box(m, origin, 0, h + 0.2, 0, w + 0.4, 0.4, d + 0.2, wood)
	local rows = 4
	local rng = Random.new(math.floor(origin.X * 3 + origin.Z * 17))
	for r = 0, rows - 1 do
		local y = 0.3 + r * (h / rows)
		box(m, origin, 0, y, 0, w - 0.4, 0.25, d, wood)
		-- Boxes along the shelf.
		local x = -w / 2 + 0.6
		while x < w / 2 - 1.2 do
			local thick = 0.5 + rng:NextNumber() * 0.6
			local tall = 1.2 + rng:NextNumber() * 0.5
			if rng:NextNumber() < 0.18 and x + 2.2 < w / 2 - 0.4 then
				-- A small stack lying flat.
				for s = 0, 1 + rng:NextInteger(0, 1) do
					box(m, origin, x + 1, y + 0.33 + s * 0.42, -0.1, 2, 0.4, d - 0.7, { Color = BOX_COLORS[rng:NextInteger(1, #BOX_COLORS)] })
				end
				x += 2.3
			else
				local color = BOX_COLORS[rng:NextInteger(1, #BOX_COLORS)]
				box(m, origin, x + thick / 2, y + 0.125 + tall / 2, -0.1, thick, tall, d - 0.7, { Color = color })
				-- A light stripe on the spine, like a title band.
				if rng:NextNumber() < 0.6 then
					box(m, origin, x + thick / 2, y + 0.125 + tall * 0.7, -0.1 - (d - 0.7) / 2 - 0.01, thick + 0.02, 0.22, 0.02, { Color = C.cream, CastShadow = false })
				end
				x += thick + 0.05
			end
		end
	end
	return m
end

-- The big TV over the Party Stage. Its screen has a SurfaceGui named "Screen" with
-- `Title` and `Line` labels that LobbyService fills in.
function Props.TV(origin: CFrame, w: number, d: number, parent: Instance): Model
	local m = newModel("TV", parent)
	local h = w * 9 / 16
	local bottom = 8 -- screen from 8 to 26 studs over the stage for a 32-wide TV
	-- Low media console under it.
	box(m, origin, 0, 1.4, -0.5, w * 0.6, 2.8, d + 1, { Color = C.darkWood, Material = Enum.Material.Wood })
	box(m, origin, 0, 2.9, -0.5, w * 0.6 + 0.4, 0.2, d + 1.2, { Color = C.wood, Material = Enum.Material.Wood })
	-- Frame and screen.
	box(m, origin, 0, bottom + h / 2, 0.2, w + 1, h + 1, d * 0.5, { Color = Color3.fromRGB(24, 22, 30) })
	local screen = box(m, origin, 0, bottom + h / 2, -0.06, w, h, 0.1, { Color = Color3.fromRGB(20, 16, 40), Material = Enum.Material.Neon, CastShadow = false })
	screen.Name = "Screen"
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Screen"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(34, 24, 66)
	bg.BorderSizePixel = 0
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(70, 40, 140), Color3.fromRGB(26, 20, 52))
	gradient.Rotation = 90
	gradient.Parent = bg
	bg.Parent = gui
	local function label(name, y, height, font, color, text)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.06, y)
		l.Size = UDim2.fromScale(0.88, height)
		l.Font = font
		l.TextScaled = true
		l.TextColor3 = color
		l.Text = text
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(70, 30, 120)
		stroke.Thickness = 4
		stroke.Parent = l
		l.Parent = bg
		return l
	end
	label("Title", 0.14, 0.42, Enum.Font.FredokaOne, Color3.fromRGB(255, 240, 200), "GAME NIGHT")
	label("Line", 0.6, 0.16, Enum.Font.GothamBold, Color3.fromRGB(255, 255, 255), "Pull up a chair")
	label("Sub", 0.78, 0.1, Enum.Font.GothamMedium, Color3.fromRGB(210, 196, 255), "")
	gui.Parent = screen
	lamp(screen, 26, 0.6, Color3.fromRGB(170, 140, 255)).Shadows = false
	-- Speakers on either side.
	for _, sx in { -w / 2 - 2.6, w / 2 + 2.6 } do
		box(m, origin, sx, bottom - 1.2 + h * 0.4, 0, 3, h * 0.8, d, { Color = Color3.fromRGB(30, 28, 36) })
		for i = 0, 1 do
			cylinder(m, origin, sx, bottom + h * (0.15 + i * 0.4), -d / 2 - 0.05, 2, 2, { Color = Color3.fromRGB(60, 56, 70) }).CFrame = origin
				* CFrame.new(sx, bottom + h * (0.15 + i * 0.4), -d / 2 - 0.05)
				* CFrame.Angles(0, math.rad(90), 0)
		end
	end
	return m
end

local function trophy(m, origin, x, y, z, color, scale)
	local metal = { Color = color, Material = Enum.Material.Metal, Reflectance = 0.15 }
	box(m, origin, x, y + 0.2 * scale, z, 0.9 * scale, 0.4 * scale, 0.9 * scale, { Color = C.darkWood, Material = Enum.Material.Wood })
	cylinder(m, origin, x, y + 0.75 * scale, z, 0.7 * scale, 0.25 * scale, metal)
	cylinder(m, origin, x, y + 1.45 * scale, z, 0.9 * scale, 0.9 * scale, metal)
	ball(m, origin, x, y + 1.05 * scale, z, 0.6 * scale, metal)
	for _, side in { -1, 1 } do
		box(m, origin, x + side * 0.55 * scale, y + 1.5 * scale, z, 0.15 * scale, 0.5 * scale, 0.15 * scale, metal)
	end
end

-- A glass-front cabinet of trophies with a "Hall of Champions" plaque. Later it can
-- show the weekly winners (vault: Monetization Playbook, leaderboards).
function Props.TrophyCase(origin: CFrame, w: number, d: number, parent: Instance): Model
	local m = newModel("TrophyCase", parent)
	local h = 8
	local wood = { Color = C.darkWood, Material = Enum.Material.Wood }
	box(m, origin, 0, 0.75, 0, w, 1.5, d, wood)
	box(m, origin, 0, h - 0.2, 0, w, 0.4, d, wood)
	box(m, origin, 0, h / 2, d / 2 - 0.1, w, h, 0.2, { Color = Color3.fromRGB(60, 30, 40), Material = Enum.Material.Fabric })
	for _, sx in { -w / 2 + 0.2, w / 2 - 0.2 } do
		box(m, origin, sx, h / 2, 0, 0.4, h, d, wood)
	end
	box(m, origin, 0, 4.4, 0, w - 0.4, 0.15, d - 0.4, { Color = C.cream, Material = Enum.Material.Glass, Transparency = 0.5 })
	box(m, origin, 0, h / 2 + 0.4, -d / 2 + 0.05, w - 0.4, h - 2.2, 0.1, { Color = Color3.fromRGB(200, 220, 230), Material = Enum.Material.Glass, Transparency = 0.75, CastShadow = false })
	local gold, silver, bronze = Color3.fromRGB(240, 196, 70), Color3.fromRGB(200, 204, 214), Color3.fromRGB(196, 128, 76)
	for i, color in { silver, gold, bronze } do
		trophy(m, origin, -w / 3 + (i - 1) * w / 3, 1.5, 0, color, if color == gold then 1.5 else 1.1)
	end
	for i = 1, 4 do
		trophy(m, origin, -w / 2 + i * w / 5, 4.5, 0, if i % 2 == 0 then gold else silver, 0.9)
	end
	local light = box(m, origin, 0, h - 0.5, 0, w - 1, 0.1, 0.4, { Color = C.lampWarm, Material = Enum.Material.Neon, CastShadow = false })
	lamp(light, 10, 0.8)
	local plaque = box(m, origin, 0, h + 1.1, 0, w * 0.8, 1.8, 0.3, { Color = C.brass, Material = Enum.Material.Metal })
	Props.text(plaque, Enum.NormalId.Front, "Hall of Champions", { color = C.ink, padding = 0.12 })
	return m
end

-- An arcade cabinet. The screen just shows a title and "Coming soon": in the design it
-- becomes the portal frame for future big games. No coin slot or payout tray.
function Props.Arcade(origin: CFrame, w: number, d: number, parent: Instance): Model
	local m = newModel("Arcade", parent)
	local hue = (math.floor(origin.X) % 3)
	local body = ({ Color3.fromRGB(70, 60, 170), Color3.fromRGB(196, 56, 86), Color3.fromRGB(40, 140, 150) })[hue + 1]
	local props = { Color = body }
	box(m, origin, 0, 2, 0.3, w - 0.6, 4, d - 0.6, props)
	box(m, origin, 0, 5.4, 0.8, w - 0.6, 3, d - 1.6, props)
	box(m, origin, 0, 7.5, 0.4, w - 0.6, 1.4, d - 0.8, { Color = Color3.fromRGB(30, 26, 40) })
	for _, sx in { -w / 2 + 0.3, w / 2 - 0.3 } do
		box(m, origin, sx, 4, 0, 0.3, 8, d, { Color = Color3.fromRGB(26, 22, 34) })
	end
	local marquee = box(m, origin, 0, 7.5, -0.36, w - 0.8, 1.1, 0.1, { Color = Color3.fromRGB(255, 220, 120), Material = Enum.Material.Neon, CastShadow = false })
	local titles = { "Block Party", "Star Hop", "Mega Maze" }
	Props.text(marquee, Enum.NormalId.Front, titles[hue + 1], { color = C.ink, lightInfluence = 0 })
	local screen = box(m, origin, 0, 5.4, -0.71, w - 1.2, 2.4, 0.1, { Color = Color3.fromRGB(20, 30, 50), Material = Enum.Material.Neon, CastShadow = false })
	screen.CFrame *= CFrame.Angles(math.rad(-12), 0, 0)
	Props.text(screen, Enum.NormalId.Front, "COMING SOON", { color = Color3.fromRGB(120, 255, 200), lightInfluence = 0, font = Enum.Font.Arcade, background = Color3.fromRGB(14, 18, 34) })
	-- Control panel: a joystick and two buttons.
	local panel = box(m, origin, 0, 4.1, -0.9, w - 0.6, 0.3, 1.4, { Color = Color3.fromRGB(30, 26, 40) })
	panel.CFrame *= CFrame.Angles(math.rad(10), 0, 0)
	cylinder(m, origin, -0.7, 4.6, -1, 0.7, 0.18, { Color = Color3.fromRGB(30, 30, 30) })
	ball(m, origin, -0.7, 5.0, -1, 0.45, { Color = Color3.fromRGB(230, 60, 60) })
	ball(m, origin, 0.4, 4.35, -1.05, 0.35, { Color = Color3.fromRGB(80, 180, 255), Material = Enum.Material.Neon })
	ball(m, origin, 0.9, 4.35, -0.8, 0.35, { Color = Color3.fromRGB(255, 220, 80), Material = Enum.Material.Neon })
	lamp(screen, 8, 0.6, Color3.fromRGB(120, 255, 200)).Shadows = false
	return m
end

-- The lounge's Party board: who's playing what, at which table. LobbyService fills the
-- SurfaceGui named "PartyBoard" (a `Rows` frame of TextLabels).
function Props.PartyBoard(origin: CFrame, w: number, d: number, parent: Instance): Model
	local m = newModel("PartyBoard", parent)
	local h = 9
	local bottom = 2.4
	for _, px in { -w / 2 + 0.5, w / 2 - 0.5 } do
		box(m, origin, px, (bottom + h) / 2 + 0.3, 0, 0.8, bottom + h + 0.6, d, { Color = C.darkWood, Material = Enum.Material.Wood })
	end
	local board = box(m, origin, 0, bottom + h / 2, 0, w - 1.6, h, d * 0.6, { Color = Color3.fromRGB(40, 64, 52), Material = Enum.Material.Slate })
	board.Name = "Board"
	box(m, origin, 0, bottom + h + 0.6, 0, w + 0.4, 1.2, d + 0.2, { Color = C.wood, Material = Enum.Material.Wood })
	local header = box(m, origin, 0, bottom + h + 0.6, -d / 2 - 0.06, w - 2, 1, 0.05, { Transparency = 1, CanCollide = false })
	Props.text(header, Enum.NormalId.Front, "Who's playing", { color = C.cream, padding = 0.02 })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PartyBoard"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0.4
	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.fromScale(0.04, 0.05)
	rows.Size = UDim2.fromScale(0.92, 0.9)
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0.01, 0)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = rows
	rows.Parent = gui
	gui.Parent = board
	-- A lamp over the board so it reads at night.
	local bar = box(m, origin, 0, bottom + h + 0.05, -d / 2 - 0.5, w - 3, 0.25, 0.4, { Color = C.lampWarm, Material = Enum.Material.Neon, CastShadow = false })
	lamp(bar, 12, 0.9)
	return m
end

---------------------------------------------------------------------------------------
-- Corners

local function stool(m, origin, x, z, top)
	cylinder(m, origin, x, 0.1, z, 0.2, 1.4, { Color = Color3.fromRGB(60, 60, 66), Material = Enum.Material.Metal })
	cylinder(m, origin, x, top / 2, z, top, 0.3, { Color = Color3.fromRGB(60, 60, 66), Material = Enum.Material.Metal })
	cylinder(m, origin, x, top + 0.2, z, 0.4, 1.8, { Color = Color3.fromRGB(196, 60, 64), Material = Enum.Material.Leather })
	seat(m, origin, x, top + 0.45, z, 1.4, 1.4)
end

-- The snack bar (front-left of the room). The counter runs along the prop's width with
-- its customer side to the front (-Z); a back bar of treats stands against the wall.
function Props.SnackBar(origin: CFrame, w: number, d: number, parent: Instance): Model
	local m = newModel("SnackBar", parent)
	local counterZ = -d / 2 + 4
	box(m, origin, 0, 1.8, counterZ, w, 3.6, 2.4, { Color = C.wood, Material = Enum.Material.WoodPlanks })
	box(m, origin, 0, 3.75, counterZ, w + 0.4, 0.3, 3, { Color = C.cream, Material = Enum.Material.Marble })
	-- A warm strip under the counter lip.
	box(m, origin, 0, 3.45, counterZ - 1.25, w - 0.4, 0.15, 0.1, { Color = C.lampWarm, Material = Enum.Material.Neon, CastShadow = false })
	for i = 0, 4 do
		stool(m, origin, -w / 2 + 3 + i * (w - 6) / 4, counterZ - 2.6, 2.6)
	end
	-- On the counter: a popcorn machine, a lemonade dispenser, a jar of pretzels.
	local px = -w / 2 + 3
	box(m, origin, px, 4.1, counterZ, 2.2, 0.4, 2, { Color = Color3.fromRGB(200, 40, 46) })
	box(m, origin, px, 5.4, counterZ, 2.2, 2.2, 2, { Color = Color3.fromRGB(240, 230, 200), Material = Enum.Material.Glass, Transparency = 0.5 })
	box(m, origin, px, 4.8, counterZ, 1.9, 0.9, 1.7, { Color = Color3.fromRGB(255, 236, 160) })
	box(m, origin, px, 6.7, counterZ, 2.4, 0.4, 2.2, { Color = Color3.fromRGB(200, 40, 46) })
	local dx = w / 2 - 3
	cylinder(m, origin, dx, 5.2, counterZ, 2.6, 1.6, { Color = Color3.fromRGB(255, 230, 90), Material = Enum.Material.Glass, Transparency = 0.35 })
	box(m, origin, dx, 4.0, counterZ, 2, 0.3, 2, { Color = Color3.fromRGB(80, 80, 90), Material = Enum.Material.Metal })
	cylinder(m, origin, 0, 4.7, counterZ, 1.6, 1.4, { Color = Color3.fromRGB(220, 230, 235), Material = Enum.Material.Glass, Transparency = 0.5 })
	cylinder(m, origin, 0, 4.4, counterZ, 0.9, 1.2, { Color = Color3.fromRGB(176, 110, 52) })
	-- Back bar shelves with jars and boxes of snacks.
	local backZ = d / 2 - 1
	box(m, origin, 0, 4, backZ, w, 8, 2, { Color = C.darkWood, Material = Enum.Material.Wood })
	local rng = Random.new(7)
	for r = 0, 1 do
		box(m, origin, 0, 3.4 + r * 2.4, backZ - 1.3, w - 1, 0.2, 0.8, { Color = C.wood, Material = Enum.Material.Wood })
		for i = 0, 9 do
			local jx = -w / 2 + 1.6 + i * (w - 3.2) / 9
			cylinder(m, origin, jx, 4.05 + r * 2.4, backZ - 1.3, 1.1, 0.7, { Color = BOX_COLORS[rng:NextInteger(1, #BOX_COLORS)], Material = Enum.Material.Glass, Transparency = 0.2 })
		end
	end
	-- Menu sign above the back bar.
	local sign = box(m, origin, 0, 10.2, backZ - 0.2, w * 0.7, 3, 0.3, { Color = C.ink })
	Props.text(sign, Enum.NormalId.Front, "Snack Bar", { color = Color3.fromRGB(255, 214, 120), stroke = Color3.fromRGB(150, 60, 30), lightInfluence = 0, padding = 0.1 })
	lamp(sign, 16, 0.8)
	-- Pendant lights over the counter.
	for i = 0, 2 do
		local lx = -w / 2 + w * (i + 0.5) / 3
		box(m, origin, lx, 12.5, counterZ, 0.1, 5, 0.1, { Color = Color3.fromRGB(30, 30, 30), CanCollide = false })
		local shade = cylinder(m, origin, lx, 9.8, counterZ, 0.9, 1.8, { Color = Color3.fromRGB(30, 70, 60), Material = Enum.Material.Metal, CanCollide = false })
		local bulb = ball(m, origin, lx, 9.3, counterZ, 0.6, { Color = C.lampWarm, Material = Enum.Material.Neon, CastShadow = false, CanCollide = false })
		lamp(bulb, 14, 1)
		local _ = shade
	end
	return m
end

local function rack(m, origin, x, z, rng)
	box(m, origin, x, 0.15, z, 7, 0.3, 1.6, { Color = Color3.fromRGB(60, 60, 66), Material = Enum.Material.Metal })
	for _, sx in { -3.2, 3.2 } do
		box(m, origin, x + sx, 3, z, 0.25, 6, 0.25, { Color = C.brass, Material = Enum.Material.Metal })
	end
	box(m, origin, x, 6, z, 6.8, 0.2, 0.2, { Color = C.brass, Material = Enum.Material.Metal })
	for i = 0, 7 do
		local hx = x - 2.8 + i * 0.8
		local color = BOX_COLORS[rng:NextInteger(1, #BOX_COLORS)]
		box(m, origin, hx, 4.6, z, 0.25, 2.6, 1.6, { Color = color, Material = Enum.Material.Fabric })
	end
end

-- The Dressing Room corner (front-right, off the foyer): a lit mirror, clothing racks
-- and a little photo stage. The Dressing Room button on the HUD opens the try-on UI.
function Props.DressingCorner(origin: CFrame, w: number, d: number, parent: Instance): Model
	local m = newModel("DressingCorner", parent)
	local rng = Random.new(11)
	-- Photo stage with a backdrop against the front wall.
	local stageX = w / 2 - 6
	cylinder(m, origin, stageX, 0.3, d / 2 - 5.5, 0.6, 9, { Color = Color3.fromRGB(236, 200, 120), Material = Enum.Material.Wood })
	cylinder(m, origin, stageX, 0.62, d / 2 - 5.5, 0.05, 8.2, { Color = Color3.fromRGB(150, 52, 62), Material = Enum.Material.Carpet })
	box(m, origin, stageX, 6, d / 2 - 0.4, 10, 12, 0.4, { Color = Color3.fromRGB(110, 70, 190), Material = Enum.Material.Fabric })
	for i = 0, 9 do
		local bulb = ball(m, origin, stageX - 4.5 + i, 11.6, d / 2 - 0.7, 0.4, { Color = C.lampWarm, Material = Enum.Material.Neon, CastShadow = false })
		local _ = bulb
	end
	-- Mirror with bulbs around it.
	local mx = -w / 2 + 6
	box(m, origin, mx, 4.5, d / 2 - 0.5, 7, 8, 0.4, { Color = C.cream, Material = Enum.Material.Wood })
	box(m, origin, mx, 4.5, d / 2 - 0.75, 6, 7, 0.1, { Color = Color3.fromRGB(200, 214, 224), Material = Enum.Material.Glass, Reflectance = 0.5, CastShadow = false })
	for i = 0, 5 do
		ball(m, origin, mx - 3.2, 1.6 + i * 1.2, d / 2 - 0.8, 0.45, { Color = C.lampWarm, Material = Enum.Material.Neon, CastShadow = false })
		ball(m, origin, mx + 3.2, 1.6 + i * 1.2, d / 2 - 0.8, 0.45, { Color = C.lampWarm, Material = Enum.Material.Neon, CastShadow = false })
	end
	local top = ball(m, origin, mx, 8.6, d / 2 - 0.8, 0.45, { Color = C.lampWarm, Material = Enum.Material.Neon, CastShadow = false })
	lamp(top, 14, 1)
	-- Two racks of clothes.
	rack(m, origin, -w / 2 + 6, -d / 2 + 3, rng)
	rack(m, origin, 1, -d / 2 + 3, rng)
	-- A sign over it.
	local sign = box(m, origin, 0, 14, d / 2 - 0.5, 14, 2.4, 0.3, { Color = C.ink })
	Props.text(sign, Enum.NormalId.Front, "Dressing Room", { color = Color3.fromRGB(255, 200, 236), stroke = Color3.fromRGB(120, 40, 110), lightInfluence = 0, padding = 0.1 })
	lamp(sign, 16, 0.8, Color3.fromRGB(255, 190, 220))
	return m
end

---------------------------------------------------------------------------------------
-- Room pieces used by Room.luau

-- A hanging sign with text on both sides. `cf` is the sign's center.
function Props.hangingSign(cf: CFrame, w: number, h: number, text: string, color: Color3, ceilingY: number, parent: Instance): Model
	local m = newModel("Banner", parent)
	local origin = cf
	local board = box(m, origin, 0, 0, 0, w, h, 0.4, { Color = color, Material = Enum.Material.Wood, CanCollide = false })
	box(m, origin, 0, -h / 2 - 0.15, 0, w + 0.3, 0.3, 0.5, { Color = C.darkWood, Material = Enum.Material.Wood, CanCollide = false })
	box(m, origin, 0, h / 2 + 0.15, 0, w + 0.3, 0.3, 0.5, { Color = C.darkWood, Material = Enum.Material.Wood, CanCollide = false })
	local up = ceilingY - cf.Y - h / 2
	for _, sx in { -w / 2 + 0.6, w / 2 - 0.6 } do
		box(m, origin, sx, h / 2 + up / 2, 0, 0.1, up, 0.1, { Color = Color3.fromRGB(40, 40, 40), CanCollide = false, CastShadow = false })
	end
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		Props.text(board, face, text, { color = C.cream, stroke = Color3.fromRGB(40, 24, 20), lightInfluence = 0.2, padding = 0.12 })
	end
	return m
end

-- A pendant lamp hanging over a table. Returns the model and its light.
function Props.pendant(at: Vector3, ceilingY: number, parent: Instance): (Model, PointLight, BasePart)
	local m = newModel("TableLamp", parent)
	local origin = CFrame.new(at)
	local cord = ceilingY - at.Y
	box(m, origin, 0, cord / 2, 0, 0.12, cord, 0.12, { Color = Color3.fromRGB(30, 30, 30), CanCollide = false, CastShadow = false, CanQuery = false })
	local shade = cylinder(m, origin, 0, 0.3, 0, 1.2, 4, { Color = Color3.fromRGB(40, 70, 60), Material = Enum.Material.Metal, CanCollide = false, CanQuery = false })
	box(m, origin, 0, 0.95, 0, 1.2, 0.2, 1.2, { Color = C.brass, Material = Enum.Material.Metal, CanCollide = false, CanQuery = false })
	local bulb = ball(m, origin, 0, -0.35, 0, 1.2, { Color = C.lampWarm, Material = Enum.Material.Neon, CastShadow = false, CanCollide = false, CanQuery = false })
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = 100
	light.Range = 22
	light.Brightness = 1.1
	light.Color = C.tableLight
	light.Shadows = true
	light.Parent = bulb
	local glow = lamp(bulb, 12, 0.3, C.tableLight)
	glow.Shadows = false
	local _ = shade
	return m, glow, bulb
end

return Props
