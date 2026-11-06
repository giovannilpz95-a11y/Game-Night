-- Camera math for the seated first-person Table view of board games: you sit at your
-- place and look down across the board to the others. Given where the board's corners
-- and the other players' heads are, it finds how far back and how high your eyes go,
-- how far to look down (pitch) and how far to slide sideways (side) so all of it sits inside
-- the part of the screen the game's panels leave free.
-- Pure numbers (no Vector3 or Instances), so tests/SeatView.spec.luau can check it.
--
-- Seat frame: origin at the middle of the tabletop, +z from your seat toward the middle
-- (away from you), +x to your right, +y up. The eye sits at (0, height, -back).
-- Screen rect: normalized device coordinates, -1..1, x right and y up.

local SeatView = {}

SeatView.FOV = 68 -- vertical field of view, degrees (the card games use the same)
SeatView.MARGIN = 0.06 -- room left at the edges of the free rect (in NDC)
-- When it doesn't fit, the eye moves up and back from its start: of every spot on this
-- grid that fits, the closest one to the start wins, so it stays as near your own chair
-- as the board allows (the controller hides your own body and stool there).
SeatView.RISE = { max = 2.5, step = 0.1 } -- shares of the starting height
SeatView.BACK = { max = 2, step = 0.1 } -- shares of the starting distance back

export type Point = { x: number, y: number, z: number }
export type Rect = { left: number, right: number, bottom: number, top: number }
export type Result = {
	back: number,
	height: number,
	pitch: number, -- radians, looking down
	side: number, -- studs slid to your right (the view always faces straight ahead)
	fits: "all" | "board" | "none",
}

-- Tries one eye position. Returns pitch, the sideways slide and whether every point lands
-- in `free`. The camera always looks straight ahead across the table (no turn: a turned
-- view read as crooked in Studio); when a panel covers one side it slides the other way
-- instead, as little as it can.
local function try(points: { Point }, back: number, height: number, t: number, aspect: number, free: Rect): (number, number, boolean)
	local m = SeatView.MARGIN
	local ta = t * aspect
	-- How far below level each point is doesn't depend on sliding sideways, so the pitch
	-- range is exact.
	local aMin, aMax = math.huge, -math.huge
	for _, p in points do
		local ahead = p.z + back
		if ahead <= 0.1 then
			return 0, 0, false
		end
		local a = math.atan2(height - p.y, ahead)
		aMin, aMax = math.min(aMin, a), math.max(aMax, a)
	end
	-- A point `a` below level shows at tan(pitch - a) / t up the screen.
	local most = aMin + math.atan((free.top - m) * t) -- the highest point stays under the top
	local least = aMax + math.atan((free.bottom + m) * t) -- the lowest stays over the bottom
	local pitch = (most + least) / 2
	-- Sideways: a point x to the right at `depth` shows at (x - side) / (depth * ta).
	-- Each point allows a range of slides; keep the one nearest zero inside all of them.
	local cp, sp = math.cos(pitch), math.sin(pitch)
	local low, high = -math.huge, math.huge
	for _, p in points do
		local depth = (p.z + back) * cp + (height - p.y) * sp
		if depth <= 0.1 then
			return pitch, 0, false
		end
		low = math.max(low, p.x - (free.right - m) * depth * ta)
		high = math.min(high, p.x - (free.left + m) * depth * ta)
	end
	local side = math.clamp(0, low, math.max(low, high))
	if low > high then
		side = (low + high) / 2
	end
	return pitch, side, least <= most and low <= high
end

-- `board`: points that must be seen (the board's corners). `heads`: points that should be
-- (the others' heads), dropped only when both can't fit. `back`/`height`: the eye's
-- starting place: it only ever gets higher, then a little further back. `aspect`:
-- screen width / height.
function SeatView.solve(board: { Point }, heads: { Point }, back: number, height: number, aspect: number, free: Rect, fov: number?): Result
	local t = math.tan(math.rad(fov or SeatView.FOV) / 2)
	local all = table.clone(board)
	for _, p in heads do
		table.insert(all, p)
	end
	for _, set in { { points = all, fits = "all" }, { points = board, fits = "board" } } do
		local best: Result? = nil
		local bestCost = math.huge
		local bs = 1
		while bs <= SeatView.BACK.max + 1e-9 do
			local hs = 1
			while hs <= SeatView.RISE.max + 1e-9 do
				local db, dh = back * (bs - 1), height * (hs - 1)
				local cost = db * db + dh * dh
				if cost < bestCost then
					local pitch, side, ok = try(set.points, back * bs, height * hs, t, aspect, free)
					-- Sliding sideways counts as moving away from your chair too.
					if ok and cost + side * side < bestCost then
						best = { back = back * bs, height = height * hs, pitch = pitch, side = side, fits = set.fits :: any }
						bestCost = cost + side * side
					end
				end
				hs += SeatView.RISE.step
			end
			bs += SeatView.BACK.step
		end
		if best then
			return best
		end
	end
	-- Nothing fits (a tiny free area): highest and furthest, splitting the difference.
	local b, h = back * SeatView.BACK.max, height * SeatView.RISE.max
	local pitch, side = try(board, b, h, t, aspect, free)
	return { back = b, height = h, pitch = pitch, side = side, fits = "none" }
end

-- Where point `p` lands on screen (NDC) for a solved view: for tests and debugging.
function SeatView.project(view: Result, p: Point, aspect: number, fov: number?): (number, number, number)
	local t = math.tan(math.rad(fov or SeatView.FOV) / 2)
	local ahead = p.z + view.back
	local up = p.y - view.height
	local cp, sp = math.cos(view.pitch), math.sin(view.pitch)
	local depth = ahead * cp - up * sp
	local y = up * cp + ahead * sp
	return (p.x - view.side) / (depth * t * aspect), y / (depth * t), depth
end

return SeatView
