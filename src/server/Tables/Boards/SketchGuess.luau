-- Sketch & Guess at the table: the drawing appears live on a four-sided screen over the
-- table, with the hint (or the word at the reveal) underneath. Drawing and guessing stay
-- in each player's 2D view. Only new strokes are added each update; a clear or undo
-- redraws the canvas.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.Shared.Games.SketchGuess)
local Scene = require(script.Parent.Parent.Scene)

local SketchGuess = {}

local MAX_SEGMENTS = 900 -- per side; very busy drawings stop adding detail past this
local CANVAS = Vector2.new(360, 228) -- pixels on each 400x300 side

local function toColor(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

function SketchGuess.create(boardCF: CFrame, parent: Instance, _layout: Scene.Layout)
	local model = Instance.new("Model")
	model.Name = "GameBoard"
	local _, faces = Scene.jumbotron(model, boardCF, 3.4)
	model.Parent = parent

	type Side = { canvas: Frame, caption: TextLabel, segments: number }
	local sides: { Side } = {}
	for _, frame in faces do
		local canvas = Instance.new("Frame")
		canvas.Position = UDim2.fromOffset(20, 10)
		canvas.Size = UDim2.fromOffset(CANVAS.X, CANVAS.Y)
		canvas.BackgroundColor3 = Color3.new(1, 1, 1)
		canvas.BorderSizePixel = 0
		canvas.ClipsDescendants = true
		canvas.Parent = frame
		local caption = Scene.screenText(frame, "", UDim2.fromOffset(20, 244), UDim2.fromOffset(360, 48))
		table.insert(sides, { canvas = canvas, caption = caption, segments = 0 })
	end

	local rendered = 0
	local renderedLast: string? = nil

	local function segment(side: Side, x1: number, y1: number, x2: number, y2: number, color: Color3, width: number)
		if side.segments >= MAX_SEGMENTS then
			return
		end
		side.segments += 1
		local res = Rules.resolution
		local a = Vector2.new(x1 / res * CANVAS.X, y1 / res * CANVAS.Y)
		local b = Vector2.new(x2 / res * CANVAS.X, y2 / res * CANVAS.Y)
		local d = b - a
		local w = math.max(1, width * CANVAS.X / 600)
		local mid = (a + b) / 2
		local line = Instance.new("Frame")
		line.BackgroundColor3 = color
		line.BorderSizePixel = 0
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.fromOffset(mid.X, mid.Y)
		line.Size = UDim2.fromOffset(d.Magnitude + w, w)
		line.Rotation = math.deg(math.atan2(d.Y, d.X))
		line.Parent = side.canvas
	end

	local function drawStroke(s: any)
		local points = Rules.decodePoints(s.points)
		if not points then
			return
		end
		local color = toColor(Rules.palette[s.color] or Rules.palette[1])
		local width = Rules.sizes[s.size] or Rules.sizes[1]
		for _, side in sides do
			if #points == 2 then
				segment(side, points[1], points[2], points[1], points[2], color, width)
			else
				for i = 1, #points - 3, 2 do
					segment(side, points[i], points[i + 1], points[i + 2], points[i + 3], color, width)
				end
			end
		end
	end

	return {
		model = model,
		update = function(view: any, _snapshot: any)
			local strokes = view.strokes or {}
			local consistent = #strokes >= rendered and (rendered == 0 or (strokes[rendered] and strokes[rendered].points == renderedLast))
			if not consistent then
				for _, side in sides do
					side.canvas:ClearAllChildren()
					side.segments = 0
				end
				rendered = 0
			end
			for i = rendered + 1, #strokes do
				drawStroke(strokes[i])
			end
			rendered = #strokes
			renderedLast = if rendered > 0 then strokes[rendered].points else nil

			-- The spectator view never has the word until the reveal.
			local caption = if view.word then string.upper(view.word) elseif view.hint then view.hint else (view.status or "")
			for _, side in sides do
				side.caption.Text = caption
			end
		end,
		destroy = function()
			model:Destroy()
		end,
	}
end

return SketchGuess
