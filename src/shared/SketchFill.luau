-- The Sketch & Guess fill bucket: a flood fill over a low-resolution copy of the drawing.
-- Pure Luau (no Instances), so tests can run it and every screen gets the same result.
--
--   local raster = SketchFill.new()
--   raster:add(stroke) -> rects?   -- feed every stroke in order; a bucket stroke returns
--                                     the area it fills as { {x, y, w, h}, ... } in cells
--   raster:reset()                 -- after an undo or clear
--
-- Strokes only queue up until a bucket arrives, so drawings without a bucket cost nothing.
-- Lines are traced at least one cell thick (no diagonal gaps) and the fill spreads
-- up, down, left and right, so it never leaks through a closed outline. Eraser (white)
-- lines count as their own color: a fill stops at them, the way they look on screen.

local Rules = require(script.Parent.Games.SketchGuess)

local SketchFill = {}
SketchFill.__index = SketchFill

SketchFill.W = 240
SketchFill.H = 180
SketchFill.maxRects = 600 -- a fill that would need more Frames than this stops adding detail

local W, H = SketchFill.W, SketchFill.H
local BACKGROUND = 2 -- palette index of white: an untouched canvas
local ERASED = -1 -- white painted by the eraser
local BASE_WIDTH = 600 -- brush sizes are pixels on a canvas this wide (as in SketchCanvas)
local OVAL_SIDES = 28 -- the same outline the renderer draws
local THIN = 0.71 -- cells: any cell a line passes through is within this of it

export type Rect = { number } -- { x, y, w, h } in cells

function SketchFill.new()
	local self = setmetatable({}, SketchFill)
	self:reset()
	return self
end

function SketchFill.reset(self)
	self.cells = nil -- made on the first bucket
	self.pending = {}
end

local function cellsOf(points: { number }, i: number): (number, number)
	local res = Rules.resolution + 1
	return points[i] / res * W, points[i + 1] / res * H
end

local function brushRadius(sizeIndex: number): number
	local px = Rules.sizes[sizeIndex] or Rules.sizes[1]
	local cells = px / BASE_WIDTH * W
	return math.max(THIN, cells / 2 - 0.4)
end

local function paintValue(color: number): number
	return if color == BACKGROUND then ERASED else color
end

-- Every cell whose center is within r of the segment a-b (a capsule). The capsule is
-- convex, so each row it touches is one run of cells: worked out per row, not per cell.
local function paintSegment(cells: { number }, ax: number, ay: number, bx: number, by: number, r: number, value: number)
	local dx, dy = bx - ax, by - ay
	local len2 = dx * dx + dy * dy
	local len = math.sqrt(len2)
	local nx, ny = 0, 0
	if len > 0 then
		nx, ny = -dy / len, dx / len
	end
	local y0 = math.max(0, math.floor(math.min(ay, by) - r - 0.5))
	local y1 = math.min(H - 1, math.ceil(math.max(ay, by) + r - 0.5))
	for y = y0, y1 do
		local cy = y + 0.5
		local lo, hi = math.huge, -math.huge
		-- The round ends.
		for _, e in { { ax, ay }, { bx, by } } do
			local oy = cy - e[2]
			if oy * oy <= r * r then
				local h = math.sqrt(r * r - oy * oy)
				lo, hi = math.min(lo, e[1] - h), math.max(hi, e[1] + h)
			end
		end
		-- The band between them: close enough to the line, and alongside the segment.
		if len > 0 then
			local oy = cy - ay
			local bLo, bHi = -math.huge, math.huge
			if math.abs(nx) > 1e-9 then
				local p1, p2 = ax + (-r - oy * ny) / nx, ax + (r - oy * ny) / nx
				bLo, bHi = math.min(p1, p2), math.max(p1, p2)
			elseif math.abs(oy * ny) > r then
				bLo, bHi = math.huge, -math.huge
			end
			if math.abs(dx) > 1e-9 then
				local q1, q2 = ax + (0 - oy * dy) / dx, ax + (len2 - oy * dy) / dx
				bLo, bHi = math.max(bLo, math.min(q1, q2)), math.min(bHi, math.max(q1, q2))
			else
				local t = oy * dy / len2
				if t < 0 or t > 1 then
					bLo, bHi = math.huge, -math.huge
				end
			end
			if bLo <= bHi then
				lo, hi = math.min(lo, bLo), math.max(hi, bHi)
			end
		end
		if lo <= hi then
			local row = y * W
			for x = math.max(0, math.ceil(lo - 0.5)), math.min(W - 1, math.floor(hi - 0.5)) do
				cells[row + x + 1] = value
			end
		end
	end
end

local function paintBox(cells: { number }, ax: number, ay: number, bx: number, by: number, value: number)
	local x0 = math.max(0, math.floor(math.min(ax, bx)))
	local x1 = math.min(W - 1, math.ceil(math.max(ax, bx)) - 1)
	local y0 = math.max(0, math.floor(math.min(ay, by)))
	local y1 = math.min(H - 1, math.ceil(math.max(ay, by)) - 1)
	for y = y0, y1 do
		local row = y * W
		for x = x0, x1 do
			cells[row + x + 1] = value
		end
	end
end

local function paintOval(cells: { number }, ax: number, ay: number, bx: number, by: number, value: number)
	local cx, cy = (ax + bx) / 2, (ay + by) / 2
	local rx, ry = math.max(math.abs(bx - ax) / 2, 0.001), math.max(math.abs(by - ay) / 2, 0.001)
	local y0 = math.max(0, math.floor(cy - ry))
	local y1 = math.min(H - 1, math.ceil(cy + ry))
	local x0 = math.max(0, math.floor(cx - rx))
	local x1 = math.min(W - 1, math.ceil(cx + rx))
	for y = y0, y1 do
		local ty = (y + 0.5 - cy) / ry
		local row = y * W
		for x = x0, x1 do
			local tx = (x + 0.5 - cx) / rx
			if tx * tx + ty * ty <= 1 then
				cells[row + x + 1] = value
			end
		end
	end
end

local function flood(cells: { number }, sx: number, sy: number, value: number): { Rect }
	sx = math.clamp(math.floor(sx), 0, W - 1)
	sy = math.clamp(math.floor(sy), 0, H - 1)
	local start = sy * W + sx + 1
	local target = cells[start]
	if target == value then
		return {}
	end
	-- Mark the area first (so the rows can be read off), then paint it.
	local mark: { [number]: boolean } = {}
	local stack = { start }
	mark[start] = true
	while #stack > 0 do
		local i = table.remove(stack) :: number
		local x = (i - 1) % W
		if x > 0 and not mark[i - 1] and cells[i - 1] == target then
			mark[i - 1] = true
			table.insert(stack, i - 1)
		end
		if x < W - 1 and not mark[i + 1] and cells[i + 1] == target then
			mark[i + 1] = true
			table.insert(stack, i + 1)
		end
		if i > W and not mark[i - W] and cells[i - W] == target then
			mark[i - W] = true
			table.insert(stack, i - W)
		end
		if i + W <= W * H and not mark[i + W] and cells[i + W] == target then
			mark[i + W] = true
			table.insert(stack, i + W)
		end
	end
	-- Runs per row; a run with the same ends as one in the row above grows that rect.
	local rects: { Rect } = {}
	local open: { [number]: Rect } = {} -- [x0 * W + x1] = rect still growing down
	for y = 0, H - 1 do
		local row = y * W
		local nextOpen: { [number]: Rect } = {}
		local x = 0
		while x < W do
			if mark[row + x + 1] then
				local x0 = x
				while x < W and mark[row + x + 1] do
					cells[row + x + 1] = value
					x += 1
				end
				local key = x0 * W + x
				local rect = open[key]
				if rect then
					rect[4] += 1
				else
					rect = { x0, y, x - x0, 1 }
					table.insert(rects, rect)
				end
				nextOpen[key] = rect
			else
				x += 1
			end
		end
		open = nextOpen
	end
	return rects
end

function SketchFill._paint(self, stroke: any)
	local cells = self.cells
	local points = Rules.decodePoints(stroke.points or "")
	if not points or #points < 2 then
		return nil
	end
	local color = stroke.color
	if stroke.shape == "bucket" then
		local x, y = cellsOf(points, 1)
		return flood(cells, x, y, color)
	end
	local value = paintValue(color)
	local r = brushRadius(stroke.size)
	if stroke.shape == nil then
		if #points == 2 then
			local x, y = cellsOf(points, 1)
			paintSegment(cells, x, y, x, y, r, value)
		end
		for i = 1, #points - 3, 2 do
			local ax, ay = cellsOf(points, i)
			local bx, by = cellsOf(points, i + 2)
			paintSegment(cells, ax, ay, bx, by, r, value)
		end
		return nil
	end
	if #points < 4 then
		return nil
	end
	local ax, ay = cellsOf(points, 1)
	local bx, by = cellsOf(points, 3)
	if stroke.shape == "line" then
		paintSegment(cells, ax, ay, bx, by, r, value)
	elseif stroke.shape == "rect" then
		if stroke.fill then
			paintBox(cells, ax, ay, bx, by, value)
		else
			paintSegment(cells, ax, ay, bx, ay, r, value)
			paintSegment(cells, bx, ay, bx, by, r, value)
			paintSegment(cells, bx, by, ax, by, r, value)
			paintSegment(cells, ax, by, ax, ay, r, value)
		end
	elseif stroke.shape == "ellipse" then
		if stroke.fill then
			paintOval(cells, ax, ay, bx, by, value)
		else
			local cx, cy = (ax + bx) / 2, (ay + by) / 2
			local rx, ry = math.abs(bx - ax) / 2, math.abs(by - ay) / 2
			local px, py = cx + rx, cy
			for i = 1, OVAL_SIDES do
				local angle = i / OVAL_SIDES * math.pi * 2
				local qx, qy = cx + rx * math.cos(angle), cy + ry * math.sin(angle)
				paintSegment(cells, px, py, qx, qy, r, value)
				px, py = qx, qy
			end
		end
	end
	return nil
end

-- Feed the next stroke of the drawing. Returns the rects a bucket fills (nil otherwise).
function SketchFill.add(self, stroke: any): { Rect }?
	if stroke.shape ~= "bucket" then
		if self.cells then
			self:_paint(stroke)
		else
			table.insert(self.pending, stroke)
		end
		return nil
	end
	if not self.cells then
		self.cells = table.create(W * H, BACKGROUND)
		for _, s in self.pending do
			self:_paint(s)
		end
		self.pending = {}
	end
	local rects = self:_paint(stroke) or {}
	if #rects > SketchFill.maxRects then
		-- Keep the biggest pieces (the whole area is still painted in the copy).
		table.sort(rects, function(a, b)
			return a[3] * a[4] > b[3] * b[4]
		end)
		local kept = table.move(rects, 1, SketchFill.maxRects, 1, {})
		return kept
	end
	return rects
end

-- The color index at a point (0..resolution), for tests: white is the canvas.
function SketchFill.colorAt(self, x: number, y: number): number
	if not self.cells then
		self.cells = table.create(W * H, BACKGROUND)
		for _, s in self.pending do
			self:_paint(s)
		end
		self.pending = {}
	end
	local cx, cy = cellsOf({ x, y }, 1)
	local v = self.cells[math.floor(cy) * W + math.floor(cx) + 1]
	return if v == ERASED then BACKGROUND else v
end

return SketchFill
