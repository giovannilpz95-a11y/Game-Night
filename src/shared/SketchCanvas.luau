-- Draws Sketch & Guess strokes as GUI Frames. Shared by the player's canvas
-- (client/Renderers/SketchGuess) and the screen over the table (server/Tables/Boards).
--
--   SketchCanvas.draw(parent, stroke, canvasSize, opts?) -> frames made
--   SketchCanvas.drawPoints(parent, decodedPoints, stroke, canvasSize, opts?) -> frames made
--
-- stroke is one entry of the game's strokes: { color, size, points, shape?, fill? }.
-- Freehand lines and "line" shapes are rotated Frames; a filled box is one Frame; an
-- oval is a ring of short lines, or stacked bars when filled. opts.round gives line ends
-- round caps (nicer, but one more instance each); opts.budget caps how many Frames one
-- call may make (busy drawings stop adding detail instead of piling up instances).
-- Fill bucket strokes need opts.raster (SketchCanvas.newRaster(), fed every stroke in
-- order and reset when the canvas is redrawn); without it a bucket draws nothing.

local Rules = require(script.Parent.Games.SketchGuess)
local SketchFill = require(script.Parent.SketchFill)

local SketchCanvas = {}

local BASE_WIDTH = 600 -- brush sizes are in pixels on a canvas this wide
local OVAL_SIDES = 28

export type Options = { round: boolean?, budget: number?, raster: any?, rects: { { number } }? }

-- Tracks the drawing so fill buckets know their area (see shared/SketchFill).
function SketchCanvas.newRaster()
	return SketchFill.new()
end

-- A bucket's area as Frames: one per rect, a touch bigger so no seams show at the edges.
local function drawFill(parent: Instance, rects: { { number } }, stroke: any, canvasSize: Vector2, budget: number): number
	local color = SketchCanvas.color(stroke.color)
	local sx, sy = canvasSize.X / SketchFill.W, canvasSize.Y / SketchFill.H
	local grow = 0.4
	local made = 0
	for _, r in rects do
		if made >= budget then
			break
		end
		made += 1
		local f = Instance.new("Frame")
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.Position = UDim2.fromOffset((r[1] - grow) * sx, (r[2] - grow) * sy)
		f.Size = UDim2.fromOffset((r[3] + 2 * grow) * sx, (r[4] + 2 * grow) * sy)
		f.Parent = parent
	end
	return made
end

local function toColor(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

function SketchCanvas.color(index: number): Color3
	return toColor(Rules.palette[index] or Rules.palette[1])
end

function SketchCanvas.width(sizeIndex: number, canvasSize: Vector2): number
	return math.max(1, (Rules.sizes[sizeIndex] or Rules.sizes[1]) * canvasSize.X / BASE_WIDTH)
end

function SketchCanvas.draw(parent: Instance, stroke: any, canvasSize: Vector2, opts: Options?): number
	-- opts.rects: a bucket's area already worked out (one raster shared by several canvases).
	local raster = opts and opts.raster
	local rects = if opts and opts.rects then opts.rects elseif raster then raster:add(stroke) else nil
	if stroke.shape == "bucket" then
		local budget = if opts and opts.budget then opts.budget else math.huge
		return if rects and budget > 0 then drawFill(parent, rects, stroke, canvasSize, budget) else 0
	end
	local points = Rules.decodePoints(stroke.points or "")
	if not points then
		return 0
	end
	return SketchCanvas.drawPoints(parent, points, stroke, canvasSize, opts)
end

-- Same as draw, with the points already decoded ({ x1, y1, x2, y2, ... } in 0..resolution).
-- stroke supplies color, size, shape and fill.
function SketchCanvas.drawPoints(parent: Instance, points: { number }, stroke: any, canvasSize: Vector2, opts: Options?): number
	if #points < 2 then
		return 0
	end
	local round = opts ~= nil and opts.round == true
	local budget = if opts and opts.budget then opts.budget else math.huge
	if budget <= 0 then
		return 0
	end
	local res = Rules.resolution
	local color = SketchCanvas.color(stroke.color)
	local width = SketchCanvas.width(stroke.size, canvasSize)
	local made = 0

	local function px(x: number, y: number): Vector2
		return Vector2.new(x / res * canvasSize.X, y / res * canvasSize.Y)
	end

	local function frame(position: Vector2, size: Vector2, rotation: number, corner: boolean)
		if made >= budget then
			return
		end
		made += 1
		local f = Instance.new("Frame")
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromOffset(position.X, position.Y)
		f.Size = UDim2.fromOffset(size.X, size.Y)
		f.Rotation = rotation
		if corner then
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = f
		end
		f.Parent = parent
	end

	local function segment(a: Vector2, b: Vector2)
		local d = b - a
		frame((a + b) / 2, Vector2.new(d.Magnitude + width, width), math.deg(math.atan2(d.Y, d.X)), round)
	end

	local shape = stroke.shape
	if shape == "bucket" then
		return made -- drawn by draw(), which has the raster
	elseif shape == nil then
		if #points == 2 then
			local p = px(points[1], points[2])
			segment(p, p)
			return made
		end
		for i = 1, #points - 3, 2 do
			segment(px(points[i], points[i + 1]), px(points[i + 2], points[i + 3]))
		end
		return made
	end

	if #points < 4 then
		return 0
	end
	local a, b = px(points[1], points[2]), px(points[3], points[4])
	if shape == "line" then
		segment(a, b)
		return made
	end
	local minP = Vector2.new(math.min(a.X, b.X), math.min(a.Y, b.Y))
	local maxP = Vector2.new(math.max(a.X, b.X), math.max(a.Y, b.Y))
	local size = maxP - minP
	local center = (minP + maxP) / 2
	if shape == "rect" then
		if stroke.fill then
			frame(center, Vector2.new(math.max(size.X, 1), math.max(size.Y, 1)), 0, false)
		else
			local tl, tr = minP, Vector2.new(maxP.X, minP.Y)
			local br, bl = maxP, Vector2.new(minP.X, maxP.Y)
			segment(tl, tr)
			segment(tr, br)
			segment(br, bl)
			segment(bl, tl)
		end
	elseif shape == "ellipse" then
		local rx, ry = size.X / 2, size.Y / 2
		if stroke.fill then
			-- Horizontal bars, each as wide as the oval at its height.
			local rows = math.clamp(math.floor(size.Y / 5), 4, 32)
			local h = size.Y / rows
			for i = 0, rows - 1 do
				local t = ((i + 0.5) * h - ry) / math.max(ry, 0.001)
				local half = rx * math.sqrt(math.max(0, 1 - t * t))
				frame(Vector2.new(center.X, minP.Y + (i + 0.5) * h), Vector2.new(math.max(1, half * 2), h + 1), 0, false)
			end
		else
			local prev = Vector2.new(center.X + rx, center.Y)
			for i = 1, OVAL_SIDES do
				local angle = i / OVAL_SIDES * math.pi * 2
				local p = Vector2.new(center.X + rx * math.cos(angle), center.Y + ry * math.sin(angle))
				segment(prev, p)
				prev = p
			end
		end
	end
	return made
end

return SketchCanvas
