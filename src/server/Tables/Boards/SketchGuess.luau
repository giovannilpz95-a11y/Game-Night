-- Sketch & Guess at the table: the drawing appears live on a four-sided screen over the
-- table, with the hint (or the word at the reveal) underneath. Drawing and guessing stay
-- in each player's 2D view (docked beside the table in Table view). A player who hides or
-- reports a drawing has this screen hidden on their own client too. Only new strokes are
-- added each update; a clear or undo redraws the canvas.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SketchCanvas = require(ReplicatedStorage.Shared.SketchCanvas)
local Scene = require(script.Parent.Parent.Scene)

local SketchGuess = {}

local MAX_SEGMENTS = 900 -- per side; very busy drawings stop adding detail past this
local CANVAS = Vector2.new(360, 228) -- pixels on each 400x300 side

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
	local raster = SketchCanvas.newRaster() -- one for all four sides: fill buckets

	local function drawStroke(s: any)
		local rects = raster:add(s)
		for _, side in sides do
			side.segments += SketchCanvas.draw(side.canvas, s, CANVAS, { budget = MAX_SEGMENTS - side.segments, rects = rects })
		end
	end

	return {
		model = model,
		update = function(view: any, snapshot: any)
			local strokes = view.strokes or {}
			-- The gallery at the end: the most liked drawing goes back up.
			local best = view.gallery and view.gallery[1]
			if best then
				strokes = best.strokes
			end
			local consistent = #strokes >= rendered and (rendered == 0 or (strokes[rendered] and strokes[rendered].points == renderedLast))
			if not consistent then
				for _, side in sides do
					side.canvas:ClearAllChildren()
					side.segments = 0
				end
				raster:reset()
				rendered = 0
			end
			for i = rendered + 1, #strokes do
				drawStroke(strokes[i])
			end
			rendered = #strokes
			renderedLast = if rendered > 0 then strokes[rendered].points else nil

			-- The spectator view never has the word until the reveal.
			local caption = if view.word then string.upper(view.word) elseif view.hint then view.hint else (view.status or "")
			if best then
				local seat = snapshot and snapshot.seats and snapshot.seats[best.drawer]
				caption = `BEST DRAWING: {string.upper(best.word)}{if seat and seat.name then ` BY {string.upper(seat.name)}` else ""}`
			end
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
