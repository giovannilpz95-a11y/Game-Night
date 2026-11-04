-- Builds the lobby room from parts: floor, walls with night windows, ceiling beams and
-- string lights, zone rugs and banners, the Party Stage, the front door, and every prop
-- in shared/LobbyLayout. The tables themselves come from server/Tables/Builder.
--
-- Returns the Room model plus the pieces LobbyService animates (TV, Party board).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local L = require(ReplicatedStorage.Shared.LobbyLayout)
local Props = require(script.Parent.Props)

local Room = {}

local C = Props.Colors
local WALL = Color3.fromRGB(226, 196, 160)
local WAINSCOT = Color3.fromRGB(110, 70, 48)
local FLOOR = Color3.fromRGB(150, 102, 66)
local CEILING = Color3.fromRGB(70, 48, 36)
local NIGHT = Color3.fromRGB(26, 34, 70)
local THICK = 2

local function part(parent: Instance, props: { [string]: any }): BasePart
	local p: BasePart = Instance.new(props.Class or "Part") :: any
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		if key ~= "Class" then
			(p :: any)[key] = value
		end
	end
	p.Parent = parent
	return p
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- A straight wall from `a` to `b` along one axis, with window openings.
-- `along` is "X" or "Z"; `fixed` is the wall's other coordinate (its center line);
-- `openings` are { center, width, bottom, top }.
local function wall(parent: Instance, along: string, fixed: number, from: number, to: number, openings: { any }, inward: number)
	local height = L.CEILING_Y
	local function place(a: number, b: number, y0: number, y1: number, color: Color3, material: Enum.Material, depth: number?, offset: number?)
		if b - a < 0.05 or y1 - y0 < 0.05 then
			return
		end
		local mid, len = (a + b) / 2, b - a
		local dep = depth or THICK
		local c = fixed + (offset or 0) * inward
		local size = if along == "X" then Vector3.new(len, y1 - y0, dep) else Vector3.new(dep, y1 - y0, len)
		local pos = if along == "X" then Vector3.new(mid, (y0 + y1) / 2, c) else Vector3.new(c, (y0 + y1) / 2, mid)
		part(parent, { Size = size, Position = pos, Color = color, Material = material })
	end
	table.sort(openings, function(x, y)
		return x.center < y.center
	end)
	-- Solid bands below the lowest opening and above the highest, piers between.
	local low, high = math.huge, 0
	for _, o in openings do
		low = math.min(low, o.bottom)
		high = math.max(high, o.top)
	end
	if #openings == 0 then
		low, high = height, height
	end
	place(from, to, 0, low, WALL, Enum.Material.Plaster)
	place(from, to, high, height, WALL, Enum.Material.Plaster)
	local cursor = from
	for _, o in openings do
		local a, b = o.center - o.width / 2, o.center + o.width / 2
		place(cursor, a, low, high, WALL, Enum.Material.Plaster)
		place(a, b, low, o.bottom, WALL, Enum.Material.Plaster)
		place(a, b, o.top, high, WALL, Enum.Material.Plaster)
		cursor = b
	end
	place(cursor, to, low, high, WALL, Enum.Material.Plaster)
	-- Wood wainscot along the bottom (on the room side), with a trim rail.
	-- (skipping doorways).
	local trimFrom = from
	for _, o in openings do
		if o.bottom < 4.4 then
			place(trimFrom, o.center - o.width / 2, 0, 4, WAINSCOT, Enum.Material.Wood, 0.3, THICK / 2 + 0.15)
			place(trimFrom, o.center - o.width / 2, 4, 4.4, C.darkWood, Enum.Material.Wood, 0.5, THICK / 2 + 0.25)
			trimFrom = o.center + o.width / 2
		end
	end
	place(trimFrom, to, 0, 4, WAINSCOT, Enum.Material.Wood, 0.3, THICK / 2 + 0.15)
	place(trimFrom, to, 4, 4.4, C.darkWood, Enum.Material.Wood, 0.5, THICK / 2 + 0.25)
	-- Crown molding under the ceiling.
	place(from, to, height - 0.8, height, C.darkWood, Enum.Material.Wood, 0.6, THICK / 2 + 0.3)

	-- Glass, frame and a cross mullion in each opening.
	for _, o in openings do
		if o.glass ~= false then
			local h = o.top - o.bottom
			local function at(u: number, y: number, off: number): Vector3
				local c = fixed + off * inward
				return if along == "X" then Vector3.new(u, y, c) else Vector3.new(c, y, u)
			end
			local function size(u: number, y: number, dep: number): Vector3
				return if along == "X" then Vector3.new(u, y, dep) else Vector3.new(dep, y, u)
			end
			part(parent, { Size = size(o.width, h, 0.2), Position = at(o.center, o.bottom + h / 2, -0.4), Color = NIGHT, Material = Enum.Material.Glass, Transparency = 0.55, CastShadow = false })
			for _, y in { o.bottom, o.top } do
				part(parent, { Size = size(o.width + 0.8, 0.5, 0.8), Position = at(o.center, y, THICK / 2), Color = C.cream, Material = Enum.Material.Wood })
			end
			for _, u in { o.center - o.width / 2, o.center + o.width / 2 } do
				part(parent, { Size = size(0.5, h, 0.8), Position = at(u, o.bottom + h / 2, THICK / 2), Color = C.cream, Material = Enum.Material.Wood })
			end
			part(parent, { Size = size(0.3, h, 0.4), Position = at(o.center, o.bottom + h / 2, 0), Color = C.cream, Material = Enum.Material.Wood })
			part(parent, { Size = size(o.width, 0.3, 0.4), Position = at(o.center, o.bottom + h * 0.6, 0), Color = C.cream, Material = Enum.Material.Wood })
			-- A sill on the room side.
			part(parent, { Size = size(o.width + 1.2, 0.3, 1.4), Position = at(o.center, o.bottom - 0.1, THICK / 2 + 0.5), Color = C.wood, Material = Enum.Material.Wood })
		end
	end
end

local function shell(room: Model)
	local f = folder("Shell", room)
	local r = L.room
	local cx, cz = (r.minX + r.maxX) / 2, (r.minZ + r.maxZ) / 2
	local w, d = r.maxX - r.minX, r.maxZ - r.minZ
	part(f, { Name = "Floor", Size = Vector3.new(w + THICK * 2, 1, d + THICK * 2), Position = Vector3.new(cx, L.FLOOR_Y - 0.5, cz), Color = FLOOR, Material = Enum.Material.WoodPlanks })
	part(f, { Name = "Ceiling", Size = Vector3.new(w + THICK * 2, 1, d + THICK * 2), Position = Vector3.new(cx, L.CEILING_Y + 0.5, cz), Color = CEILING, Material = Enum.Material.Wood })
	-- Beams across the ceiling.
	local beam = r.maxZ - 10
	while beam > r.minZ + 4 do
		part(f, { Name = "Beam", Size = Vector3.new(w, 1.4, 1.6), Position = Vector3.new(cx, L.CEILING_Y - 0.7, beam), Color = C.darkWood, Material = Enum.Material.Wood })
		beam -= 26
	end

	local win = L.windows
	local function openings(list: { number }): { any }
		local out = {}
		for _, c in list do
			table.insert(out, { center = c, width = win.width, bottom = win.bottom, top = win.top })
		end
		return out
	end
	wall(f, "Z", r.minX - THICK / 2, r.minZ - THICK, r.maxZ + THICK, openings(win.side), 1)
	wall(f, "Z", r.maxX + THICK / 2, r.minZ - THICK, r.maxZ + THICK, openings(win.side), -1)
	wall(f, "X", r.minZ - THICK / 2, r.minX, r.maxX, openings(win.back), 1)
	local front = openings(win.front)
	table.insert(front, { center = L.door.x, width = L.door.width, bottom = 0, top = L.door.height, glass = false })
	wall(f, "X", r.maxZ + THICK / 2, r.minX, r.maxX, front, -1)

	-- The front door: two closed doors with little windows, a frame and a neon sign.
	local dz = r.maxZ - 0.2
	local dw, dh = L.door.width, L.door.height
	for _, side in { -1, 1 } do
		local x = L.door.x + side * dw / 4
		part(f, { Name = "Door", Size = Vector3.new(dw / 2 - 0.1, dh - 0.4, 0.6), Position = Vector3.new(x, dh / 2, dz + 0.4), Color = Color3.fromRGB(120, 40, 46), Material = Enum.Material.Wood })
		part(f, { Size = Vector3.new(dw / 2 - 2, 4, 0.2), Position = Vector3.new(x, dh * 0.62, dz + 0.05), Color = NIGHT, Material = Enum.Material.Glass, Transparency = 0.4 })
		part(f, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6), Position = Vector3.new(L.door.x + side * 0.9, dh * 0.42, dz - 0.05), Color = C.brass, Material = Enum.Material.Metal })
	end
	part(f, { Size = Vector3.new(dw + 1.6, 0.8, 1), Position = Vector3.new(L.door.x, dh + 0.4, dz), Color = C.cream, Material = Enum.Material.Wood })
	for _, side in { -1, 1 } do
		part(f, { Size = Vector3.new(0.8, dh, 1), Position = Vector3.new(L.door.x + side * (dw / 2 + 0.4), dh / 2, dz), Color = C.cream, Material = Enum.Material.Wood })
	end
	local sign = part(f, { Name = "DoorSign", Size = Vector3.new(22, 4.4, 0.3), Position = Vector3.new(L.door.x, dh + 3.6, dz - 0.3), Color = Color3.fromRGB(34, 24, 66), CanCollide = false })
	Props.text(sign, Enum.NormalId.Front, "GAME NIGHT", { color = Color3.fromRGB(255, 226, 150), stroke = Color3.fromRGB(150, 70, 200), lightInfluence = 0, padding = 0.06 })
	Props.lamp(sign, 18, 1, Color3.fromRGB(220, 170, 255)).Shadows = false
end

-- Zone rugs: a border and an inner field, flat on the floor.
local function rugs(room: Model)
	local f = folder("Rugs", room)
	for _, zone in L.zones do
		if zone.id ~= "Party" then -- the stage has its own carpet
			local a = zone.area
			local cx, cz = (a.minX + a.maxX) / 2, (a.minZ + a.maxZ) / 2
			local w, d = a.maxX - a.minX, a.maxZ - a.minZ
			part(f, { Name = `{zone.id}Rug`, Size = Vector3.new(w, 0.06, d), Position = Vector3.new(cx, L.FLOOR_Y + 0.03, cz), Color = zone.border, Material = Enum.Material.Carpet, CanCollide = false, CastShadow = false })
			part(f, { Size = Vector3.new(w - 1.6, 0.06, d - 1.6), Position = Vector3.new(cx, L.FLOOR_Y + 0.05, cz), Color = zone.rug, Material = Enum.Material.Carpet, CanCollide = false, CastShadow = false })
		end
	end
end

local function stage(room: Model)
	local f = folder("Stage", room)
	local s, step = L.stage, L.stageStep
	local cx, cz = (s.minX + s.maxX) / 2, (s.minZ + s.maxZ) / 2
	local w, d = s.maxX - s.minX, s.maxZ - s.minZ
	local height = L.STAGE_Y - L.FLOOR_Y
	part(f, { Name = "Stage", Size = Vector3.new(w, height, d), Position = Vector3.new(cx, L.FLOOR_Y + height / 2, cz), Color = Color3.fromRGB(96, 60, 40), Material = Enum.Material.WoodPlanks })
	local zone = L.zone("Party")
	part(f, { Size = Vector3.new(w - 3, 0.06, d - 3), Position = Vector3.new(cx, L.STAGE_Y + 0.03, cz - 1.5), Color = zone and zone.rug or C.purple, Material = Enum.Material.Carpet, CanCollide = false, CastShadow = false })
	part(f, { Name = "Step", Size = Vector3.new(step.maxX - step.minX, height / 2, step.maxZ - step.minZ), Position = Vector3.new(cx, L.FLOOR_Y + height / 4, (step.minZ + step.maxZ) / 2), Color = Color3.fromRGB(120, 78, 52), Material = Enum.Material.WoodPlanks })
	-- Warm light strip along the stage's front edge.
	part(f, { Size = Vector3.new(w, 0.15, 0.15), Position = Vector3.new(cx, L.STAGE_Y - 0.15, s.maxZ + 0.05), Color = Color3.fromRGB(255, 200, 110), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
	-- Curtains framing the back wall on both sides of the TV.
	for _, side in { -1, 1 } do
		for i = 0, 3 do
			part(f, { Size = Vector3.new(1.6, L.CEILING_Y - L.STAGE_Y, 1), Position = Vector3.new(side * (25 + i * 1.5), (L.CEILING_Y + L.STAGE_Y) / 2, s.minZ + 1 + (i % 2) * 0.5), Color = Color3.fromRGB(140, 30, 50), Material = Enum.Material.Fabric, CastShadow = false })
		end
	end
end

local function banners(room: Model)
	local f = folder("Banners", room)
	for _, zone in L.zones do
		if zone.id ~= "Foyer" and zone.id ~= "Lounge" then
			local a = zone.area
			-- Over the zone's front edge (the side facing the spawn), clear of the table
			-- lamps and, on the stage, of the TV.
			local cx, cz = (a.minX + a.maxX) / 2, a.maxZ - 4
			local w = math.clamp(#zone.label * 1.3 + 3, 10, 18)
			-- Face the spawn (both sides have text).
			local cf = CFrame.new(cx, 21, cz) * CFrame.Angles(0, math.pi, 0)
			Props.hangingSign(cf, w, 3, zone.label, zone.rug, L.CEILING_Y - 1.4, f)
		end
	end
end

-- Strands of warm bulbs hung across the room, sagging a little in the middle.
local function stringLights(room: Model)
	local f = folder("StringLights", room)
	local r = L.room
	local span = r.maxX - r.minX
	for _, z in L.stringLights do
		local count = 34
		local prev: Vector3? = nil
		for i = 0, count do
			local t = i / count
			local x = r.minX + t * span
			local sag = 4 * t * (1 - t) -- 0 at the walls, 1 in the middle
			local y = L.CEILING_Y - 2.4 - sag * 3.2
			local pos = Vector3.new(x, y, z)
			if prev then
				local mid = (prev + pos) / 2
				part(f, { Size = Vector3.new(0.08, 0.08, (pos - prev).Magnitude), CFrame = CFrame.lookAt(mid, pos), Color = Color3.fromRGB(30, 30, 30), CanCollide = false, CastShadow = false, CanQuery = false })
			end
			if i > 0 and i < count then
				local warm = if i % 3 == 0 then Color3.fromRGB(255, 170, 110) else Color3.fromRGB(255, 214, 150)
				part(f, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.55, 0.55, 0.55), Position = pos - Vector3.new(0, 0.3, 0), Color = warm, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, CanQuery = false })
			end
			prev = pos
		end
	end
end

local function props(room: Model): { [string]: Model }
	local f = folder("Props", room)
	local found = {}
	for _, prop in L.props do
		local builder = (Props :: any)[prop.kind]
		if builder then
			local y = prop.y or L.floorAt(prop.x, prop.z)
			local cf = CFrame.new(prop.x, y, prop.z) * CFrame.Angles(0, math.rad(prop.yaw or 0), 0)
			local model = builder(cf, prop.w, prop.d, f)
			found[prop.kind] = found[prop.kind] or model
		else
			warn(`[GameNight] no lobby prop builder for {prop.kind}`)
		end
	end
	return found
end

-- Invisible camera markers for the store thumbnails and trailer: each Part looks from
-- the shot's camera spot toward its subject. In Studio, select one and use
-- View > "Camera to part" (or set workspace.CurrentCamera.CFrame to its CFrame).
local function shots(room: Model)
	local f = folder("ShotCameras", room)
	for _, shot in L.shots do
		local from = Vector3.new(shot.from[1], shot.from[2], shot.from[3])
		local at = Vector3.new(shot.at[1], shot.at[2], shot.at[3])
		part(f, { Name = `Shot_{shot.name}`, Size = Vector3.new(1, 1, 1), CFrame = CFrame.lookAt(from, at), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	end
end

function Room.build(parent: Instance): (Model, { [string]: Model })
	local room = Instance.new("Model")
	room.Name = "Room"
	shell(room)
	rugs(room)
	stage(room)
	banners(room)
	stringLights(room)
	local found = props(room)
	shots(room)
	room.Parent = parent
	return room, found
end

return Room
