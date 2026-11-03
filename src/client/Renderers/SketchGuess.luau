-- Sketch & Guess: canvas on the left, guesses on the right.
--
-- Drawer: pick 1 of 3 words, then draw with the palette, brush sizes, undo and clear.
-- Lines are drawn locally right away and sent in small chunks (about 5 a second) so
-- everyone sees the drawing build up live.
-- Guessers: type guesses in the box. Near misses get a private "close!" note. Anyone can
-- hide the drawing on their own screen, or vote to skip it (moderation).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Rules = require(ReplicatedStorage.Shared.Games.SketchGuess)
local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = Kit.Theme

local SketchGuess = {}

local CANVAS_RATIO = 4 / 3
local SEND_EVERY = 0.2 -- seconds between chunks while drawing (keeps under the rate limit)
local MIN_STEP = 0.008 -- of the canvas width; finer movements are skipped
local RES = Rules.resolution
local BASE_WIDTH = 600 -- brush sizes are in pixels on a canvas this wide

local function toColor(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

function SketchGuess.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local brushColor = 1
	local brushSize = 2
	local hidden = false

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })

	-- Left column: word bar, canvas, toolbar.
	local left = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.68, -10, 1, 0), Parent = root })
	local wordBar = Kit.label("", {
		Font = Theme.FontBold,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 36),
		Parent = left,
	})
	local canvasHolder = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 42),
		Size = UDim2.new(1, 0, 1, -42 - 96),
		Parent = left,
	})
	local canvas = Kit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		Active = true,
		Parent = canvasHolder,
	}, { Kit.new("UIAspectRatioConstraint", { AspectRatio = CANVAS_RATIO }), Kit.corner(12) })
	local strokeLayer = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = canvas })
	local previewLayer = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = canvas })
	local hiddenLabel = Kit.label("Drawing hidden on your screen", {
		TextColor3 = Color3.fromRGB(120, 120, 130),
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = canvas,
	})

	-- Overlay on the canvas for picking a word / the reveal.
	local overlay = Kit.new("Frame", {
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Visible = false,
		Parent = canvas,
	})
	local overlayTitle = Kit.label("", {
		Font = Theme.FontBold,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0.18, 0),
		Size = UDim2.new(1, 0, 0, 34),
		ZIndex = 11,
		Parent = overlay,
	})
	local overlayBody = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0.1, 0, 0.18, 44),
		Size = UDim2.new(0.8, 0, 0.6, 0),
		ZIndex = 11,
		Parent = overlay,
	})
	Kit.list(8).Parent = overlayBody

	-- Toolbar (drawer) / guesser buttons.
	local toolbar = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 1, -88),
		Size = UDim2.new(1, 0, 0, 88),
		Parent = left,
	})
	local swatches = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 38), Parent = toolbar })
	Kit.list(4, true).Parent = swatches
	local tools = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 46), Size = UDim2.new(1, 0, 0, 38), Parent = toolbar })
	Kit.list(6, true).Parent = tools

	local swatchButtons: { TextButton } = {}
	local sizeButtons: { TextButton } = {}
	local function refreshTools()
		for i, b in swatchButtons do
			(b:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = if i == brushColor then 3 else 0
		end
		for i, b in sizeButtons do
			b.BackgroundColor3 = if i == brushSize then Theme.Accent else Theme.PanelLight
		end
	end
	for i, rgb in Rules.palette do
		local b = Kit.new("TextButton", {
			Text = if i == 2 then "ERASE" else "",
			TextColor3 = Color3.fromRGB(110, 110, 120),
			TextSize = 8,
			Font = Theme.FontBold,
			BackgroundColor3 = toColor(rgb),
			BorderSizePixel = 0,
			Size = UDim2.new(0, 32, 0, 32),
			LayoutOrder = i,
			Parent = swatches,
		}, { Kit.corner(16), Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) })
		b.Activated:Connect(function()
			brushColor = i
			refreshTools()
		end)
		swatchButtons[i] = b
	end
	for i, width in Rules.sizes do
		local b = Kit.new("TextButton", {
			Text = "",
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 38, 0, 38),
			LayoutOrder = i,
			Parent = tools,
		}, { Kit.corner(10) })
		local dot = math.clamp(width, 3, 26)
		Kit.new("Frame", {
			BackgroundColor3 = Theme.Text,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(dot, dot),
			Parent = b,
		}, { Kit.corner(dot) })
		b.Activated:Connect(function()
			brushSize = i
			refreshTools()
		end)
		sizeButtons[i] = b
	end
	local function toolButton(text: string, order: number, onClick: () -> (), color: Color3?): TextButton
		return Kit.button(text, onClick, {
			BackgroundColor3 = color or Theme.PanelLight,
			TextColor3 = Theme.Text,
			Size = UDim2.new(0, 96, 0, 38),
			LayoutOrder = order,
			Parent = tools,
		})
	end
	toolButton("Undo", 10, function()
		sendMove({ kind = "undo" })
	end)
	toolButton("Clear", 11, function()
		sendMove({ kind = "clear" })
	end)
	toolButton("Skip turn", 12, function()
		sendMove({ kind = "giveUp" })
	end, Theme.Bad)
	refreshTools()

	local guesserBar = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 1, -44), Size = UDim2.new(1, 0, 0, 40), Parent = left })
	Kit.list(8, true).Parent = guesserBar
	local hideButton: TextButton
	hideButton = Kit.button("Hide drawing", function()
		hidden = not hidden
		hideButton.Text = if hidden then "Show drawing" else "Hide drawing"
		strokeLayer.Visible = not hidden
		hiddenLabel.Visible = hidden
	end, { BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, Size = UDim2.new(0, 150, 1, 0), Parent = guesserBar })
	local skipVoteButton = Kit.button("Vote to skip", function()
		sendMove({ kind = "voteSkip" })
	end, { BackgroundColor3 = Theme.Bad, TextColor3 = Theme.Text, Size = UDim2.new(0, 150, 1, 0), LayoutOrder = 2, Parent = guesserBar })

	-- Right column: guesses feed and the guess box.
	local right = Kit.panel({ Position = UDim2.new(0.68, 0, 0, 0), Size = UDim2.new(0.32, 0, 1, 0), Parent = root })
	local feedFrame = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -52),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		Parent = right,
	})
	Kit.list(2).Parent = feedFrame
	local guessBox = Kit.new("TextBox", {
		PlaceholderText = "Type your guess...",
		Text = "",
		ClearTextOnFocus = false,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.SubText,
		BackgroundColor3 = Theme.PanelLight,
		Font = Theme.Font,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -44),
		Size = UDim2.new(1, 0, 0, 44),
		Parent = right,
	}, { Kit.corner(10), Kit.padding(8) })

	local lastGuessAt = 0
	guessBox.FocusLost:Connect(function(enterPressed)
		if not enterPressed then
			return
		end
		local text = guessBox.Text
		guessBox.Text = ""
		if #text == 0 or #text > 40 or os.clock() - lastGuessAt < 0.6 then
			return
		end
		lastGuessAt = os.clock()
		sendMove({ kind = "guess", text = text })
	end)

	-- Drawing ----------------------------------------------------------------------

	local canvasSize = Vector2.new(BASE_WIDTH, BASE_WIDTH / CANVAS_RATIO)

	local function segment(parent: Instance, x1: number, y1: number, x2: number, y2: number, color: Color3, width: number)
		local a = Vector2.new(x1 / RES * canvasSize.X, y1 / RES * canvasSize.Y)
		local b = Vector2.new(x2 / RES * canvasSize.X, y2 / RES * canvasSize.Y)
		local d = b - a
		local w = math.max(1, width * canvasSize.X / BASE_WIDTH)
		local mid = (a + b) / 2
		Kit.new("Frame", {
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(mid.X, mid.Y),
			Size = UDim2.fromOffset(d.Magnitude + w, w),
			Rotation = math.deg(math.atan2(d.Y, d.X)),
			Parent = parent,
		}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	end

	local function drawPoints(parent: Instance, points: { number }, colorIndex: number, sizeIndex: number)
		local color = toColor(Rules.palette[colorIndex] or Rules.palette[1])
		local width = Rules.sizes[sizeIndex] or Rules.sizes[1]
		if #points == 2 then
			segment(parent, points[1], points[2], points[1], points[2], color, width)
			return
		end
		for i = 1, #points - 3, 2 do
			segment(parent, points[i], points[i + 1], points[i + 2], points[i + 3], color, width)
		end
	end

	local rendered = 0 -- how many of the server's strokes are on the canvas
	local renderedLast: string? = nil

	-- Drawer's own lines that the server hasn't echoed yet.
	local previewChunks: { Frame } = {}
	local previewSentAt: { number } = {}
	local livePoints: { number } = {} -- the chunk being drawn now (not sent yet)
	local liveFrame: Frame? = nil
	local liveCont = false
	local drawing = false
	local sinceSend = 0

	local function clearPreview()
		previewLayer:ClearAllChildren()
		table.clear(previewChunks)
		table.clear(previewSentAt)
		liveFrame = nil
	end

	local function redrawAll()
		strokeLayer:ClearAllChildren()
		rendered = 0
		renderedLast = nil
		local strokes = snapshot and snapshot.view.strokes or {}
		for _, s in strokes do
			local pts = Rules.decodePoints(s.points)
			if pts then
				drawPoints(strokeLayer, pts, s.color, s.size)
			end
		end
		rendered = #strokes
		renderedLast = if rendered > 0 then strokes[rendered].points else nil
	end

	local function syncStrokes()
		local strokes = snapshot.view.strokes
		local consistent = #strokes >= rendered and (rendered == 0 or strokes[rendered].points == renderedLast)
		if not consistent then
			redrawAll()
			clearPreview()
			return
		end
		for i = rendered + 1, #strokes do
			local s = strokes[i]
			local pts = Rules.decodePoints(s.points)
			if pts then
				drawPoints(strokeLayer, pts, s.color, s.size)
			end
			-- The server now has one of our chunks: drop its preview copy.
			local oldest = table.remove(previewChunks, 1)
			table.remove(previewSentAt, 1)
			if oldest then
				oldest:Destroy()
			end
		end
		-- A chunk the server never took (rate limited or rejected) shouldn't linger.
		while previewSentAt[1] and os.clock() - previewSentAt[1] > 3 do
			table.remove(previewSentAt, 1)
			local stale = table.remove(previewChunks, 1)
			if stale then
				stale:Destroy()
			end
		end
		rendered = #strokes
		renderedLast = if rendered > 0 then strokes[rendered].points else nil
	end

	canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		canvasSize = canvas.AbsoluteSize
		if snapshot then
			redrawAll()
			clearPreview()
		end
	end)
	canvasSize = if canvas.AbsoluteSize.X > 0 then canvas.AbsoluteSize else canvasSize

	local function isDrawer(): boolean
		return snapshot ~= nil
			and snapshot.view.phase == "draw"
			and snapshot.yourSeat == snapshot.view.drawer
			and table.find(snapshot.activeSeats, snapshot.yourSeat) ~= nil
	end

	local function toCanvas(screen: Vector2): (number, number)
		local rel = (screen - canvas.AbsolutePosition) / canvas.AbsoluteSize
		return math.clamp(rel.X, 0, 1) * RES, math.clamp(rel.Y, 0, 1) * RES
	end

	local function sendLive()
		if #livePoints < 4 or not liveFrame then -- need at least two points
			return
		end
		local pts = livePoints
		sendMove({
			kind = "stroke",
			color = brushColor,
			size = brushSize,
			points = Rules.encodePoints(pts),
			cont = liveCont,
		})
		table.insert(previewChunks, liveFrame)
		table.insert(previewSentAt, os.clock())
		-- The next chunk of the same line starts where this one ended.
		liveCont = true
		livePoints = { pts[#pts - 1], pts[#pts] }
		liveFrame = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = previewLayer })
		sinceSend = 0
	end

	local function addPoint(screen: Vector2)
		local x, y = toCanvas(screen)
		local n = #livePoints
		if n >= 2 then
			local dx, dy = (x - livePoints[n - 1]) / RES, (y - livePoints[n]) / RES
			if math.sqrt(dx * dx + dy * dy) < MIN_STEP then
				return
			end
		end
		table.insert(livePoints, x)
		table.insert(livePoints, y)
		n = #livePoints
		if liveFrame then
			if n >= 4 then
				drawPoints(liveFrame, { livePoints[n - 3], livePoints[n - 2], x, y }, brushColor, brushSize)
			else
				drawPoints(liveFrame, { x, y }, brushColor, brushSize)
			end
		end
		if n // 2 >= Rules.maxPointsPerStroke then
			sendLive()
		end
	end

	-- The ScreenGui ignores the GUI inset, so input positions and AbsolutePosition
	-- already share one space.
	local function screenPos(input: InputObject): Vector2
		return Vector2.new(input.Position.X, input.Position.Y)
	end

	local drawOpenedAt = 0 -- when this client last saw the drawing phase start

	canvas.InputBegan:Connect(function(input)
		-- Ignore a click that picked the word, or arrives just as the canvas opens.
		if not isDrawer() or overlay.Visible or os.clock() - drawOpenedAt < 0.4 then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			drawing = true
			liveCont = false
			livePoints = {}
			liveFrame = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = previewLayer })
			sinceSend = 0
			addPoint(screenPos(input))
		end
	end)
	local moved = UserInputService.InputChanged:Connect(function(input)
		if drawing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			if not isDrawer() then
				drawing = false
				return
			end
			addPoint(screenPos(input))
		end
	end)
	local ended = UserInputService.InputEnded:Connect(function(input)
		if drawing and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			drawing = false
			if #livePoints == 2 then
				-- A single tap: send it as a dot.
				table.insert(livePoints, livePoints[1])
				table.insert(livePoints, livePoints[2])
			end
			sendLive()
			if liveFrame and #livePoints <= 2 then
				liveFrame:Destroy()
			end
			liveFrame = nil
			livePoints = {}
		end
	end)
	local heartbeat = RunService.Heartbeat:Connect(function(dt)
		if drawing then
			sinceSend += dt
			if sinceSend >= SEND_EVERY then
				sendLive()
			end
		end
	end)

	-- Rendering --------------------------------------------------------------------

	local feedKey = ""
	local function renderFeed(view: any)
		local feed = view.feed
		local last = feed[#feed]
		local key = `{#feed}:{if last then last.text else ""}`
		if key == feedKey then
			return
		end
		feedKey = key
		Kit.clear(feedFrame)
		for i, entry in feed do
			local who = ""
			local color = Theme.Text
			if entry.seat then
				local s = snapshot.seats[entry.seat]
				who = if entry.seat == snapshot.yourSeat then "You" elseif s then s.name else "?"
			end
			local text
			if entry.kind == "system" then
				text = entry.text
				color = Theme.SubText
			elseif entry.kind == "correct" then
				text = `{who} {entry.text}`
				color = Theme.Good
			elseif entry.kind == "close" then
				text = entry.text
				color = Theme.Accent
			else
				text = `{who}: {entry.text}`
			end
			Kit.label(text, {
				TextSize = 15,
				TextColor3 = color,
				Font = if entry.kind == "guess" then Theme.Font else Theme.FontBold,
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, -6, 0, 18),
				LayoutOrder = i,
				Parent = feedFrame,
			})
		end
		feedFrame.CanvasPosition = Vector2.new(0, 1e6)
	end

	local overlayKey = ""
	local function renderOverlay(view: any)
		local key = `{view.phase}:{view.turnNumber}`
		if key == overlayKey then
			return
		end
		overlayKey = key
		if view.phase == "draw" then
			drawOpenedAt = os.clock()
		end
		Kit.clear(overlayBody)
		local me = snapshot.yourSeat
		if view.phase == "choose" then
			overlay.Visible = true
			if view.choices then
				overlayTitle.Text = "Pick a word to draw"
				for i, word in view.choices do
					local label = string.split(word, "|")[1]
					Kit.button(`{label}   ({({ "easy", "medium", "hard" })[i]})`, function()
						sendMove({ kind = "choose", index = i })
					end, { Size = UDim2.new(1, 0, 0, 44), LayoutOrder = i, Parent = overlayBody, ZIndex = 12 })
				end
			else
				local s = snapshot.seats[view.drawer]
				overlayTitle.Text = `{if s then s.name else "Someone"} is picking a word...`
			end
		elseif view.phase == "reveal" or view.phase == "done" then
			overlay.Visible = true
			overlayTitle.Text = if view.word then `The word was "{view.word}"` else "Round over"
			local order = {}
			for seat, points in view.lastPoints or {} do
				table.insert(order, { seat = seat, points = points })
			end
			table.sort(order, function(a, b)
				return a.points > b.points
			end)
			if #order == 0 then
				Kit.label("Nobody scored this time.", { TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Theme.SubText, ZIndex = 12, Parent = overlayBody })
			end
			for i, row in order do
				local s = snapshot.seats[row.seat]
				local name = if row.seat == me then "You" elseif s then s.name else "?"
				Kit.label(`{name}   +{row.points}`, {
					TextXAlignment = Enum.TextXAlignment.Center,
					Font = Theme.FontBold,
					TextColor3 = Theme.Good,
					LayoutOrder = i,
					ZIndex = 12,
					Parent = overlayBody,
				})
			end
		else
			overlay.Visible = false
		end
	end

	local function render()
		local view = snapshot.view
		local me = snapshot.yourSeat
		local amDrawer = me ~= nil and me == view.drawer and view.phase ~= "done"

		if view.phase == "draw" then
			if view.word then
				wordBar.Text = if amDrawer then `Draw: {view.word}` else `✓ {view.word}`
			else
				wordBar.Text = view.hint or ""
			end
		elseif view.phase == "choose" then
			wordBar.Text = `Drawing {view.turnNumber} of {view.totalTurns}`
		else
			wordBar.Text = ""
		end

		toolbar.Visible = amDrawer and view.phase == "draw"
		guesserBar.Visible = not amDrawer and view.phase == "draw"
		skipVoteButton.Visible = not view.youVotedSkip
		guessBox.Visible = not amDrawer and view.phase == "draw" and not view.youGuessed
		if not guessBox.Visible then
			guessBox:ReleaseFocus()
		end
		if not isDrawer() then
			drawing = false
		end

		syncStrokes()
		renderFeed(view)
		renderOverlay(view)
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			render()
		end,
		destroy = function()
			moved:Disconnect()
			ended:Disconnect()
			heartbeat:Disconnect()
			root:Destroy()
		end,
	}
end

return SketchGuess
