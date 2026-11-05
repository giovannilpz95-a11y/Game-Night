-- Camera math for the seated first-person Table view of board games: you sit at your
-- place and look down across the board to the others. Given where the board's corners
-- and the other players' heads are, it finds how far back and how high your eyes go,
-- how far to look down (pitch) and how far to turn (yaw) so that all of it sits inside
-- the part of the screen the game's panels leave free.
-- Pure numbers (no Vector3 or Instances), so tests/SeatView.spec.luau can check it.
--
-- Seat frame: origin at the middle of the tabletop, +z from your seat toward the middle
-- (away from you), +x to your right, +y up. The eye sits at (0, height, -back).
-- Screen rect: normalized device coordinates, -1..1, x right and y up.

local SeatView = {}

SeatView.FOV = 68 -- vertical field of view, degrees (the card games use the same)
SeatView.MARGIN = 0.06 -- room left at the edges of the free rect (in NDC)
SeatView.STEP = 0.08 -- each try moves the eye this share further back and up
SeatView.MAX_STEPS = 14

export type Point = { x: number, y: number, z: number }
export type Rect = { left: number, right: number, bottom: number, top: number }
export type Result = {
	back: number,
	height: number,
	pitch: number, -- radians, looking down
	yaw: number, -- radians, turned right
	fits: "all" | "board" | "none",
}

-- Tries one eye position. Returns pitch, yaw and whether every point lands in `free`.
local function try(points: { Point }, back: number, height: number, t: number, aspect: number, free: Rect): (number, number, boolean)
	local m = SeatView.MARGIN
	local ta = t * aspect
	-- Turn so the points' left-right spread is centered in the free columns.
	local hMin, hMax = math.huge, -math.huge
	for _, p in points do
		local ahead = p.z + back
		if ahead <= 0.1 then
			return 0, 0, false
		end
		local h = math.atan2(p.x, ahead)
		hMin, hMax = math.min(hMin, h), math.max(hMax, h)
	end
	local center = (free.left + free.right) / 2
	local yaw = (hMin + hMax) / 2 - math.atan(center * ta)
	local cy, sy = math.cos(yaw), math.sin(yaw)
	-- In the turned frame each point is `side` to the right and `ahead` in front. How far
	-- below level it is doesn't depend on `side`, so the pitch range is exact.
	local sides, aheads = table.create(#points), table.create(#points)
	local below = table.create(#points)
	local aMin, aMax = math.huge, -math.huge
	for i, p in points do
		local z = p.z + back
		local side = p.x * cy - z * sy
		local ahead = p.x * sy + z * cy
		if ahead <= 0.1 then
			return 0, yaw, false
		end
		sides[i], aheads[i] = side, ahead
		local a = math.atan2(height - p.y, ahead)
		below[i] = a
		aMin, aMax = math.min(aMin, a), math.max(aMax, a)
	end
	-- A point `a` below level shows at tan(pitch - a) / t up the screen.
	local most = aMin + math.atan((free.top - m) * t) -- the highest point stays under the top
	local least = aMax + math.atan((free.bottom + m) * t) -- the lowest stays over the bottom
	local pitch = (most + least) / 2
	local fits = least <= most
	if fits then
		local cp, sp = math.cos(pitch), math.sin(pitch)
		for i, p in points do
			local depth = aheads[i] * cp + (height - p.y) * sp
			if depth <= 0.1 then
				fits = false
				break
			end
			local x = sides[i] / (depth * ta)
			if x < free.left + m or x > free.right - m then
				fits = false
				break
			end
		end
	end
	return pitch, yaw, fits
end

-- `board`: points that must be seen (the board's corners). `heads`: points that should be
-- (the others' heads), dropped only when both can't fit. `back`/`height`: the eye's
-- starting place, the closest it gets. `aspect`: screen width / height.
function SeatView.solve(board: { Point }, heads: { Point }, back: number, height: number, aspect: number, free: Rect, fov: number?): Result
	local t = math.tan(math.rad(fov or SeatView.FOV) / 2)
	local all = table.clone(board)
	for _, p in heads do
		table.insert(all, p)
	end
	for _, set in { { points = all, fits = "all" }, { points = board, fits = "board" } } do
		for step = 0, SeatView.MAX_STEPS do
			local s = 1 + step * SeatView.STEP
			local pitch, yaw, ok = try(set.points, back * s, height * s, t, aspect, free)
			if ok then
				return { back = back * s, height = height * s, pitch = pitch, yaw = yaw, fits = set.fits :: any }
			end
		end
	end
	-- Nothing fits (a tiny free area): sit furthest back and split the difference.
	local s = 1 + SeatView.MAX_STEPS * SeatView.STEP
	local pitch, yaw = try(board, back * s, height * s, t, aspect, free)
	return { back = back * s, height = height * s, pitch = pitch, yaw = yaw, fits = "none" }
end

-- Where point `p` lands on screen (NDC) for a solved view: for tests and debugging.
function SeatView.project(view: Result, p: Point, aspect: number, fov: number?): (number, number, number)
	local t = math.tan(math.rad(fov or SeatView.FOV) / 2)
	local z = p.z + view.back
	local cy, sy = math.cos(view.yaw), math.sin(view.yaw)
	local side = p.x * cy - z * sy
	local ahead = p.x * sy + z * cy
	local up = p.y - view.height
	local cp, sp = math.cos(view.pitch), math.sin(view.pitch)
	local depth = ahead * cp - up * sp
	local y = up * cp + ahead * sp
	return side / (depth * t * aspect), y / (depth * t), depth
end

return SeatView
