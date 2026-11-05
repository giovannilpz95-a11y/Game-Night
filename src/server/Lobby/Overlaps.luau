-- Finds and fixes z-fighting in models built from parts: two visible surfaces in the same
-- place, facing the same way, so the renderer flickers between them. That covers
--   * flat faces (box faces and cylinder ends) on the same plane that overlap,
--   * cylinders on the same axis with the same radius whose sides overlap,
--   * balls and egg shapes with the same center and size.
-- Faces closer than EPS count as the same plane. Two overlapping faces that look the
-- same (same color, a material with no texture) don't flicker visibly and are skipped.
--
-- Overlaps.find(root) -> { Hit } lists them (tests/Overlaps.spec checks every model the
-- game builds), Overlaps.fix(root) moves faces apart (Room.build runs it on the lobby, whose
-- props are many flush boxes), Overlaps.describe(hit) -> string for reports.
-- Works on real Instances and on the test fakes (tools/test-roblox.luau).

local Overlaps = {}

Overlaps.EPS = 0.01 -- studs between two faces that still z-fight up close
Overlaps.MIN_AREA = 0.002 -- square studs of shared face worth reporting
local CIRCLE_SIDES = 24

-- Materials with no texture: the same color on two of them looks the same.
local PLAIN = { SmoothPlastic = true, Neon = true, Glass = true, ForceField = true, Plastic = true }

export type Hit = { a: any, b: any, kind: string, area: number, at: Vector3, normal: Vector3? }

local function shapeOf(p: any): string
	if p:FindFirstChildOfClass("SpecialMesh") then
		return "Egg"
	end
	local shape = p.Shape
	return if shape then shape.Name else "Block"
end

local function visible(p: any): boolean
	return p:IsA("Part") and (p.Transparency or 0) < 0.98
end

local function hasSurface(p: any): boolean
	for _, child in p:GetChildren() do
		if child:IsA("SurfaceGui") or child:IsA("Decal") or child:IsA("Texture") then
			return true
		end
	end
	return false
end

local function looksSame(a: any, b: any): boolean
	if hasSurface(a) or hasSurface(b) then
		return false
	end
	return a.Color == b.Color and a.Material == b.Material and PLAIN[a.Material.Name] == true and (a.Transparency or 0) == (b.Transparency or 0)
end

-- A face: outward normal, plane offset (normal . point) and its outline (world points).
type Face = { part: any, n: Vector3, d: number, poly: { Vector3 } }

local function boxFaces(p: any, out: { Face })
	local cf, s = p.CFrame, p.Size / 2
	local axes = { cf.XVector, cf.YVector, cf.ZVector }
	local half = { s.X, s.Y, s.Z }
	for i = 1, 3 do
		local j, k = i % 3 + 1, (i + 1) % 3 + 1
		for _, sign in { -1, 1 } do
			local n = axes[i] * sign
			local c = cf.Position + n * half[i]
			local u, v = axes[j] * half[j], axes[k] * half[k]
			table.insert(out, { part = p, n = n, d = n:Dot(c), poly = { c - u - v, c + u - v, c + u + v, c - u + v } })
		end
	end
end

local function circle(center: Vector3, u: Vector3, v: Vector3, r: number): { Vector3 }
	local pts = {}
	for i = 0, CIRCLE_SIDES - 1 do
		local a = i / CIRCLE_SIDES * math.pi * 2
		table.insert(pts, center + u * (math.cos(a) * r) + v * (math.sin(a) * r))
	end
	return pts
end

local function cylinder(p: any)
	local cf, s = p.CFrame, p.Size
	return { axis = cf.XVector, center = cf.Position, r = math.min(s.Y, s.Z) / 2, len = s.X, cf = cf }
end

local function cylFaces(p: any, out: { Face })
	local c = cylinder(p)
	for _, sign in { -1, 1 } do
		local n = c.axis * sign
		local center = c.center + n * (c.len / 2)
		table.insert(out, { part = p, n = n, d = n:Dot(center), poly = circle(center, c.cf.YVector, c.cf.ZVector, c.r) })
	end
end

-- The faces of an invisible part that carry a SurfaceGui or a decal: those draw too.
local NORMALS = { Top = Vector3.yAxis, Bottom = -Vector3.yAxis, Right = Vector3.xAxis, Left = -Vector3.xAxis, Back = Vector3.zAxis, Front = -Vector3.zAxis }
local function surfaceFaces(p: any, out: { Face })
	local all = {}
	boxFaces(p, all)
	for _, child in p:GetChildren() do
		if child:IsA("SurfaceGui") or child:IsA("Decal") or child:IsA("Texture") then
			local face = child.Face
			local n = p.CFrame:VectorToWorldSpace(NORMALS[if face then face.Name else "Front"])
			for _, f in all do
				if f.n:Dot(n) > 0.999 then
					table.insert(out, f)
				end
			end
		end
	end
end

-- 2D helpers: a plane basis, then convex polygon clipping.
local function basis(n: Vector3): (Vector3, Vector3)
	local helper = if math.abs(n.X) < 0.9 then Vector3.xAxis else Vector3.yAxis
	local u = n:Cross(helper).Unit
	return u, n:Cross(u)
end

local function to2d(poly: { Vector3 }, u: Vector3, v: Vector3): { { number } }
	local out = {}
	for _, p in poly do
		table.insert(out, { p:Dot(u), p:Dot(v) })
	end
	return out
end

local function area(poly: { { number } }): number
	local a = 0
	for i = 1, #poly do
		local p, q = poly[i], poly[i % #poly + 1]
		a += p[1] * q[2] - q[1] * p[2]
	end
	return a / 2
end

local function ccw(poly: { { number } }): { { number } }
	if area(poly) >= 0 then
		return poly
	end
	local out = {}
	for i = #poly, 1, -1 do
		table.insert(out, poly[i])
	end
	return out
end

-- Sutherland-Hodgman: the part of `subject` inside convex `clip` (both counter-clockwise).
local function clipPoly(subject: { { number } }, clip: { { number } }): { { number } }
	local out = subject
	for i = 1, #clip do
		if #out == 0 then
			break
		end
		local a, b = clip[i], clip[i % #clip + 1]
		local function inside(p)
			return (b[1] - a[1]) * (p[2] - a[2]) - (b[2] - a[2]) * (p[1] - a[1]) >= -1e-9
		end
		local function cross(p, q)
			local x1, y1, x2, y2 = p[1], p[2], q[1], q[2]
			local dx, dy = b[1] - a[1], b[2] - a[2]
			local t = (dx * (y1 - a[2]) - dy * (x1 - a[1])) / (dy * (x2 - x1) - dx * (y2 - y1))
			return { x1 + (x2 - x1) * t, y1 + (y2 - y1) * t }
		end
		local input = out
		out = {}
		for j = 1, #input do
			local p, q = input[j], input[j % #input + 1]
			if inside(q) then
				if not inside(p) then
					table.insert(out, cross(p, q))
				end
				table.insert(out, q)
			elseif inside(p) then
				table.insert(out, cross(p, q))
			end
		end
	end
	return out
end

local function sharedArea(f: Face, g: Face): (number, Vector3)
	local u, v = basis(f.n)
	local a, b = ccw(to2d(f.poly, u, v)), ccw(to2d(g.poly, u, v))
	local shared = clipPoly(a, b)
	if #shared < 3 then
		return 0, f.poly[1]
	end
	local cx, cy = 0, 0
	for _, p in shared do
		cx += p[1]
		cy += p[2]
	end
	cx /= #shared
	cy /= #shared
	return math.abs(area(shared)), u * cx + v * cy + f.n * f.d
end

-- Quick reject: faces whose bounding circles don't touch can't overlap.
local function bounds(f: any)
	if f.c then
		return
	end
	local c = Vector3.zero
	for _, p in f.poly do
		c += p
	end
	c /= #f.poly
	local r = 0
	for _, p in f.poly do
		r = math.max(r, (p - c).Magnitude)
	end
	f.c, f.r = c, r
end

local function near(f: any, g: any): boolean
	bounds(f)
	bounds(g)
	return (f.c - g.c).Magnitude < f.r + g.r
end

local function round(x: number, step: number): number
	return math.floor(x / step + 0.5)
end

function Overlaps.parts(root: any): { any }
	local list = {}
	local all = root:GetDescendants()
	if root:IsA("BasePart") then
		table.insert(all, root)
	end
	for _, d in all do
		if d:IsA("BasePart") and visible(d) then
			table.insert(list, d)
		end
	end
	return list
end

-- Invisible parts that show a SurfaceGui or a decal.
local function surfaceParts(root: any): { any }
	local list = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and not visible(d) and hasSurface(d) then
			table.insert(list, d)
		end
	end
	return list
end

-- Is `point` inside this part's shape?
local function contains(p: any, shape: string, point: Vector3): boolean
	local localPoint = p.CFrame:PointToObjectSpace(point)
	local s = p.Size / 2
	if shape == "Block" then
		return math.abs(localPoint.X) < s.X and math.abs(localPoint.Y) < s.Y and math.abs(localPoint.Z) < s.Z
	elseif shape == "Cylinder" then
		local r = math.min(s.Y, s.Z)
		return math.abs(localPoint.X) < s.X and localPoint.Y * localPoint.Y + localPoint.Z * localPoint.Z < r * r
	elseif shape == "Ball" then
		local r = math.min(s.X, s.Y, s.Z)
		return localPoint.Magnitude < r
	elseif shape == "Egg" then
		local x, y, z = localPoint.X / s.X, localPoint.Y / s.Y, localPoint.Z / s.Z
		return x * x + y * y + z * z < 1
	end
	return false
end

-- `focus` (optional): only report fights that involve one of these parts.
function Overlaps.find(root: any, focus: { [any]: boolean }?): { Hit }
	local hits: { Hit } = {}
	-- Opaque parts can hide a fight behind them: a face pair whose shared middle is
	-- inside another solid part (just in front of the faces) can't be seen.
	local solids = {}
	for _, p in Overlaps.parts(root) do
		if (p.Transparency or 0) == 0 then
			table.insert(solids, { part = p, shape = shapeOf(p), center = p.Position, radius = p.Size.Magnitude / 2 })
		end
	end
	local function hidden(a: any, b: any, point: Vector3): boolean
		for _, s in solids do
			if s.part ~= a and s.part ~= b and (s.center - point).Magnitude < s.radius and contains(s.part, s.shape, point) then
				return true
			end
		end
		return false
	end
	local faces: { Face } = {}
	local cylinders, rounds = {}, {}
	for _, p in Overlaps.parts(root) do
		local shape = shapeOf(p)
		if shape == "Block" then
			boxFaces(p, faces)
		elseif shape == "Cylinder" then
			cylFaces(p, faces)
			table.insert(cylinders, p)
		elseif shape == "Ball" or shape == "Egg" then
			table.insert(rounds, p)
		end
	end
	for _, p in surfaceParts(root) do
		surfaceFaces(p, faces)
	end

	-- Flat faces: bucket by normal, sort by plane offset, compare neighbors within EPS.
	local byNormal: { [string]: { Face } } = {}
	for _, f in faces do
		local key = `{round(f.n.X, 1e-3)},{round(f.n.Y, 1e-3)},{round(f.n.Z, 1e-3)}`
		byNormal[key] = byNormal[key] or {}
		table.insert(byNormal[key], f)
	end
	for _, list in byNormal do
		table.sort(list, function(x, y)
			return x.d < y.d
		end)
		for i = 1, #list do
			local f = list[i]
			for j = i + 1, #list do
				local g = list[j]
				if g.d - f.d > Overlaps.EPS then
					break
				end
				if f.part ~= g.part and (not focus or focus[f.part] or focus[g.part]) and near(f, g) and not looksSame(f.part, g.part) then
					local shared, at = sharedArea(f, g)
					if shared > Overlaps.MIN_AREA and not hidden(f.part, g.part, at + f.n * 0.03) then
						table.insert(hits, { a = f.part, b = g.part, kind = "face", area = shared, at = at, normal = f.n })
					end
				end
			end
		end
	end

	-- Cylinder sides on the same axis with the same radius.
	for i = 1, #cylinders do
		local a = cylinder(cylinders[i])
		for j = i + 1, #cylinders do
			local pb = cylinders[j]
			local b = cylinder(pb)
			-- Roblox draws a cylinder as a many-sided prism, so a copy turned about its own
			-- axis (Builder.smoothCylinders) crosses the original instead of lying on it.
			local sameTurn = math.abs(a.cf.YVector:Dot(b.cf.YVector)) > 0.9999
			if (not focus or focus[cylinders[i]] or focus[pb]) and sameTurn and math.abs(a.r - b.r) < Overlaps.EPS and math.abs(a.axis:Dot(b.axis)) > 0.9999 and not looksSame(cylinders[i], pb) then
				local offset = b.center - a.center
				local along = offset:Dot(a.axis)
				local apart = (offset - a.axis * along).Magnitude
				local overlap = math.min(a.len / 2, along + b.len / 2) - math.max(-a.len / 2, along - b.len / 2)
				if apart < Overlaps.EPS and overlap > 0.01 then
					table.insert(hits, { a = cylinders[i], b = pb, kind = "cylinder side", area = overlap * a.r * 2 * math.pi, at = a.center })
				end
			end
		end
	end

	-- Balls and eggs: the same surface twice.
	for i = 1, #rounds do
		for j = i + 1, #rounds do
			local a, b = rounds[i], rounds[j]
			if (a.Position - b.Position).Magnitude < Overlaps.EPS and (a.Size - b.Size).Magnitude < Overlaps.EPS and not looksSame(a, b) then
				table.insert(hits, { a = a, b = b, kind = "round", area = 0, at = a.Position })
			end
		end
	end
	return hits
end

local function path(p: any, root: any): string
	local names = {}
	local node = p
	while node and node ~= root do
		table.insert(names, 1, node.Name)
		node = node.Parent
	end
	return table.concat(names, ".")
end

local function label(p: any, root: any): string
	local s = p.Size
	return string.format("%s [%.2fx%.2fx%.2f %s]", path(p, root), s.X, s.Y, s.Z, p.Material.Name)
end

function Overlaps.describe(hit: Hit, root: any?): string
	return string.format("%s <-> %s (%s, %.3f sq studs at %.2f, %.2f, %.2f)", label(hit.a, root), label(hit.b, root), hit.kind, hit.area, hit.at.X, hit.at.Y, hit.at.Z)
end

-- Fixing ---------------------------------------------------------------------

Overlaps.GAP = 0.02 -- how far a fix moves a face: twice what still fights

-- Which of the part's local axes (1 = X, 2 = Y, 3 = Z) runs along `n`, or nil.
local function axisOf(p: any, n: Vector3): number?
	local cf = p.CFrame
	for i, axis in { cf.XVector, cf.YVector, cf.ZVector } do
		if math.abs(axis:Dot(n)) > 0.999 then
			return i
		end
	end
	return nil
end

local function sizeAlong(size: Vector3, axis: number): number
	return if axis == 1 then size.X elseif axis == 2 then size.Y else size.Z
end

local function withAxis(size: Vector3, axis: number, value: number): Vector3
	return Vector3.new(if axis == 1 then value else size.X, if axis == 2 then value else size.Y, if axis == 3 then value else size.Z)
end

-- Moves one face of `p` (the one facing `n`) by `by` studs along `n` (negative = in),
-- keeping the opposite face where it is.
local function moveFace(p: any, n: Vector3, axis: number, by: number)
	p.Size = withAxis(p.Size, axis, sizeAlong(p.Size, axis) + by)
	p.CFrame = p.CFrame + n * (by / 2)
end

-- Fixes one hit. A thick part gives way by sinking its face GAP studs; a thin one (a
-- stripe, a label, a trim) stands GAP proud instead.
local function fixHit(hit: Hit, gap: number): boolean
	if hit.kind == "face" and hit.normal then
		local n = hit.normal
		local candidates = {}
		for _, p in { hit.a, hit.b } do
			local axis = axisOf(p, n)
			if axis and shapeOf(p) ~= "Egg" then
				table.insert(candidates, { part = p, axis = axis, size = sizeAlong(p.Size, axis), area = p.Size.Magnitude })
			end
		end
		-- Prefer changing the smaller part.
		table.sort(candidates, function(x, y)
			return x.area < y.area
		end)
		for _, c in candidates do
			if c.size > 4 * gap then
				moveFace(c.part, n, c.axis, -gap)
				return true
			end
		end
		local c = candidates[1]
		if c then
			c.part.CFrame = c.part.CFrame + n * gap
			return true
		end
	elseif hit.kind == "cylinder side" or hit.kind == "round" then
		local p = if hit.a.Size.Magnitude < hit.b.Size.Magnitude then hit.a else hit.b
		local s = p.Size
		if hit.kind == "round" then
			p.Size = s - Vector3.one * (2 * gap)
		else
			p.Size = Vector3.new(s.X, s.Y - 2 * gap, s.Z - 2 * gap)
		end
		return true
	end
	return false
end

-- Moves faces apart until nothing under `root` fights, or `passes` rounds (default 12).
-- Each round moves a little further than the last, so a face pushed back in one round
-- doesn't land on a third part's face that was pushed back the same amount before.
-- Returns how many fixes it made and how many fights are left.
function Overlaps.fix(root: any, passes: number?): (number, number)
	local fixed = 0
	local hits = Overlaps.find(root)
	local focused = false
	for pass = 1, passes or 12 do
		if #hits == 0 then
			if not focused then
				break
			end
			-- A move can uncover a fight that a part in front of it hid, between two parts
			-- that never moved: check everything once more before calling it done.
			hits = Overlaps.find(root)
			focused = false
			if #hits == 0 then
				break
			end
		end
		local gap = Overlaps.GAP * (1 + (pass - 1) * 0.35)
		-- One change per face of a part per round: the next round sees where it moved.
		local touched: { [any]: { [string]: boolean } } = {}
		local function key(hit: Hit): string
			local n = hit.normal or Vector3.zero
			return `{math.round(n.X * 100)},{math.round(n.Y * 100)},{math.round(n.Z * 100)}`
		end
		for _, hit in hits do
			local k = if hit.kind == "face" then key(hit) else "all"
			local ta, tb = touched[hit.a] or {}, touched[hit.b] or {}
			if not (ta[k] or ta.all or tb[k] or tb.all) and fixHit(hit, gap) then
				ta[k], tb[k] = true, true
				fixed += 1
			end
			touched[hit.a], touched[hit.b] = ta, tb
		end
		-- New fights can only involve the parts looked at this round (moved or waiting).
		local focus = {}
		for part in touched do
			focus[part] = true
		end
		hits = Overlaps.find(root, focus)
		focused = true
	end
	if focused and #hits == 0 then
		hits = Overlaps.find(root)
	end
	return fixed, #hits
end

return Overlaps
