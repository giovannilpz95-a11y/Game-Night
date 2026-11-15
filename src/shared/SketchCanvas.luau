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
-- Stamps (stamps tables, shape = "stamp") are one rotated box each, built from Frames,
-- UIGradient cuts and a few font glyphs (SketchCanvas.stampFrame).
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

-- Stamps --------------------------------------------------------------------------------

local CUT = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.502, 1),
	NumberSequenceKeypoint.new(1, 1),
})
local GLYPHS = { star = "★", flower = "✿", sun = "☀" } -- glyphs Roblox fonts draw (checked in Studio)
-- Cloud puffs: { x, y, w, h } as shares of the box (top-left corners).
local CLOUD = { { 0, 0.45, 1, 0.55 }, { 0.06, 0.2, 0.42, 0.66 }, { 0.28, 0, 0.46, 0.74 }, { 0.56, 0.24, 0.38, 0.6 } }

local function piece(parent: Instance, color: Color3?, round: boolean): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	if color then
		f.BackgroundColor3 = color
	else
		f.BackgroundTransparency = 1
	end
	if round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = f
	end
	f.Parent = parent
	return f
end

local function cut(parent: Instance, rotation: number)
	local g = Instance.new("UIGradient")
	g.Transparency = CUT
	g.Rotation = rotation
	g.Parent = parent
end

-- One stamp: a box w x h pixels centered at (x, y), turned rot degrees. Returns the box
-- (a Frame; everything else is inside it) and how many GUI objects it took.
function SketchCanvas.stampFrame(parent: Instance, stamp: string, color: Color3, x: number, y: number, w: number, h: number, rot: number): (Frame, number)
	local box = piece(parent, nil, false)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromOffset(x, y)
	box.Size = UDim2.fromOffset(math.max(1, w), math.max(1, h))
	box.Rotation = rot
	local made = 1
	local thick = math.max(1.5, math.min(w, h) * 0.12)
	if stamp == "circle" or stamp == "stick" or stamp == "square" then
		box.BackgroundColor3 = color
		box.BackgroundTransparency = 0
		if stamp ~= "square" then
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = box
		end
	elseif stamp == "ring" or stamp == "frame" then
		local inner = piece(box, nil, stamp == "ring")
		inner.AnchorPoint = Vector2.new(0.5, 0.5)
		inner.Position = UDim2.fromScale(0.5, 0.5)
		inner.Size = UDim2.new(1, -2 * thick, 1, -2 * thick)
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = thick
		stroke.LineJoinMode = if stamp == "frame" then Enum.LineJoinMode.Miter else Enum.LineJoinMode.Round
		stroke.Parent = inner
		made += 1
	elseif stamp == "triangle" then
		-- Two halves, each cut along its diagonal (UIGradient turns in pixels, not shares).
		local a = math.deg(math.atan2(w / 2, h))
		for side = 0, 1 do
			local half = piece(box, color, false)
			half.Size = UDim2.new(0.5, 1, 1, 0)
			half.Position = UDim2.fromScale(side * 0.5, 0)
			cut(half, if side == 0 then 180 + a else -a)
			made += 1
		end
	elseif stamp == "dome" then
		-- The top half of a w x 2h oval.
		local oval = piece(box, color, true)
		oval.Size = UDim2.fromScale(1, 2)
		cut(oval, 90)
		made += 1
	elseif stamp == "arc" then
		-- The top half of a w x 2h ring (turn it over for a smile).
		local ring = piece(box, nil, true)
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 1)
		ring.Size = UDim2.new(1, -2 * thick, 2, -2 * thick)
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = thick
		stroke.Parent = ring
		cut(stroke, 90)
		made += 1
	elseif stamp == "cloud" then
		for _, r in CLOUD do
			local puff = piece(box, color, true)
			puff.Position = UDim2.fromScale(r[1], r[2])
			puff.Size = UDim2.fromScale(r[3], r[4])
			made += 1
		end
	elseif stamp == "heart" then
		local tip = piece(box, color, false)
		tip.AnchorPoint = Vector2.new(0.5, 0.5)
		tip.Position = UDim2.fromScale(0.5, 0.56)
		tip.Size = UDim2.fromScale(0.52, 0.52)
		tip.Rotation = 45
		for i = 0, 1 do
			local lobe = piece(box, color, true)
			lobe.AnchorPoint = Vector2.new(0.5, 0.5)
			lobe.Position = UDim2.fromScale(0.32 + 0.36 * i, 0.38)
			lobe.Size = UDim2.fromScale(0.52, 0.52)
		end
		made += 3
	elseif GLYPHS[stamp] then
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.fromScale(1.35, 1.35)
		label.Font = Enum.Font.GothamBold
		label.Text = GLYPHS[stamp]
		label.TextScaled = true
		label.TextColor3 = color
		label.Parent = box
		made += 1
	end
	return box, made
end

-- A stamp stroke in pixels on a canvas this size: x, y, w, h (or nil if it isn't one).
function SketchCanvas.stampPixels(stroke: any, canvasSize: Vector2): (number?, number?, number?, number?)
	local x, y, w, h = Rules.stampBox(stroke)
	if not x then
		return nil
	end
	local res = Rules.resolution
	return x / res * canvasSize.X, (y :: number) / res * canvasSize.Y, (w :: number) / res * canvasSize.X, (h :: number) / res * canvasSize.X
end

function SketchCanvas.draw(parent: Instance, stroke: any, canvasSize: Vector2, opts: Options?): number
	if stroke.shape == "stamp" then
		local budget = if opts and opts.budget then opts.budget else math.huge
		local x, y, w, h = SketchCanvas.stampPixels(stroke, canvasSize)
		if not x or budget <= 0 then
			return 0
		end
		local _, made = SketchCanvas.stampFrame(parent, stroke.stamp, SketchCanvas.color(stroke.color), x, y :: number, w :: number, h :: number, stroke.rot or 0)
		return made
	end
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
