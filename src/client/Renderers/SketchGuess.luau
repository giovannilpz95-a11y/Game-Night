-- Sketch & Guess: the canvas, the drawing tools and the guesses.
--
-- Layouts (picked from the space we get, redone whenever it changes):
--   wide     canvas and tools on the left, guesses and the guess box on the right.
--   stacked  one column: word, canvas, tools (or the guesser's buttons), guesses, guess
--            box. Used on narrow or portrait screens, and in the Table view dock, where
--            only the right DOCK_SHARE of the board shows (MatchView's DOCK entry).
--
-- Drawer: pick 1 of 3 words, then draw with the pen or the line / box / oval tools,
-- 14 colors (white is the eraser), 4 sizes, fill for boxes and ovals, undo and clear.
-- Pen lines are drawn locally right away and sent in small chunks (about 5 a second) so
-- everyone sees the drawing build up live. Touch follows one finger only.
-- Guessers: type guesses in the box. Near misses get a private "close!" note.
-- Moderation: anyone can hide a drawing on their own screen (and the screen over the
-- table), vote to skip it, or report it. Reporting hides that player's drawings for you
-- for the rest of the match, counts as a skip vote, and can block them through Roblox.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Rules = require(ReplicatedStorage.Shared.Games.SketchGuess)
local SketchCanvas = require(ReplicatedStorage.Shared.SketchCanvas)
local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = Kit.Theme

local SketchGuess = {}

local CANVAS_RATIO = 4 / 3
local DOCK_SHARE = 0.32 -- keep in step with MatchView's DOCK.SketchGuess.size
local SEND_EVERY = 0.2 -- seconds between chunks while drawing (keeps under the rate limit)
local MIN_STEP = 0.008 -- of the canvas width; finer movements are skipped
local MIN_SHAPE = 0.01 -- of the canvas; smaller boxes and ovals are ignored
local RES = Rules.resolution
local GAP = 6

local TOOLS = {
	{ id = "pen", label = "Pen" },
	{ id = "line", label = "Line" },
	{ id = "rect", label = "Box" },
	{ id = "ellipse", label = "Oval" },
}

function SketchGuess.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local brushColor = 1
	local brushSize = 2
	local tool = "pen"
	local fill = false
	local docked = false
	local hiddenTurn: number? = nil -- turn the player hid by hand
	local hiddenDrawers: { [number]: boolean } = {} -- seats the player reported
	local rerender: () -> ()

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })

	local wordBar = Kit.label("", {
		Font = Theme.FontBold,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = false,
		Parent = root,
	})

	-- Canvas -------------------------------------------------------------------------

	local canvasHolder = Kit.new("Frame", { BackgroundTransparency = 1, Parent = root })
	local canvas = Kit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		Active = true, -- touches on the canvas don't turn the camera
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

	-- Over the canvas: picking a word, the reveal, the report prompt.
	local overlay = Kit.new("Frame", {
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Visible = false,
		Parent = canvas,
	}, { Kit.padding(8) })
	local overlayList = Kit.list(6)
	overlayList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	overlayList.VerticalAlignment = Enum.VerticalAlignment.Center
	overlayList.Parent = overlay

	local reportPrompt = Kit.new("Frame", {
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Visible = false,
		Parent = canvas,
	}, { Kit.padding(10) })
	local reportList = Kit.list(6)
	reportList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	reportList.VerticalAlignment = Enum.VerticalAlignment.Center
	reportList.Parent = reportPrompt

	-- Drawer's tools --------------------------------------------------------------------

	local toolbar = Kit.new("Frame", { BackgroundTransparency = 1, Parent = root })
	local swatches = Kit.new("Frame", { BackgroundTransparency = 1, Parent = toolbar })
	local swatchGrid = Kit.new("UIGridLayout", { CellPadding = UDim2.fromOffset(4, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = swatches })
	local tools = Kit.new("Frame", { BackgroundTransparency = 1, Parent = toolbar })
	local toolGrid = Kit.new("UIGridLayout", { CellPadding = UDim2.fromOffset(4, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tools })

	local swatchButtons: { TextButton } = {}
	local sizeButtons: { TextButton } = {}
	local toolButtons: { [string]: TextButton } = {}
	local fillButton: TextButton

	local function refreshTools()
		for i, b in swatchButtons do
			local stroke = b:FindFirstChildOfClass("UIStroke") :: UIStroke
			stroke.Thickness = if i == brushColor then 3 elseif i == 2 then 1 else 0
			stroke.Color = if i == brushColor then Theme.Accent else Color3.fromRGB(150, 150, 160)
		end
		for i, b in sizeButtons do
			b.BackgroundColor3 = if i == brushSize then Theme.Accent else Theme.PanelLight
		end
		for id, b in toolButtons do
			b.BackgroundColor3 = if id == tool then Theme.Accent else Theme.PanelLight
			b.TextColor3 = if id == tool then Theme.AccentText else Theme.Text
		end
		local shapeTool = tool == "rect" or tool == "ellipse"
		fillButton.BackgroundColor3 = if fill and shapeTool then Theme.Accent else Theme.PanelLight
		fillButton.TextColor3 = if fill and shapeTool then Theme.AccentText else (if shapeTool then Theme.Text else Theme.SubText)
	end

	for i, rgb in Rules.palette do
		local b = Kit.new("TextButton", {
			Text = if i == 2 then "E" else "",
			TextColor3 = Color3.fromRGB(150, 150, 160),
			TextSize = 12,
			Font = Theme.FontBold,
			BackgroundColor3 = Color3.fromRGB(rgb[1], rgb[2], rgb[3]),
			BorderSizePixel = 0,
			LayoutOrder = i,
			Parent = swatches,
		}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), Kit.new("UIStroke", { Thickness = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) })
		b.Activated:Connect(function()
			brushColor = i
			refreshTools()
		end)
		swatchButtons[i] = b
	end
	for i, width in Rules.sizes do
		local b = Kit.new("TextButton", { Text = "", BackgroundColor3 = Theme.PanelLight, BorderSizePixel = 0, LayoutOrder = i, Parent = tools }, { Kit.corner(8) })
		local dot = math.clamp(width * 0.6, 3, 22)
		Kit.new("Frame", {
			BackgroundColor3 = Theme.Text,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(dot, dot),
			Parent = b,
		}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
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
			TextSize = 14,
			LayoutOrder = order,
			Parent = tools,
		})
	end
	for i, t in TOOLS do
		toolButtons[t.id] = toolButton(t.label, 10 + i, function()
			tool = t.id
			refreshTools()
		end)
	end
	fillButton = toolButton("Fill", 20, function()
		fill = not fill
		if tool ~= "rect" and tool ~= "ellipse" then
			tool = "rect"
		end
		refreshTools()
	end)
	toolButton("Undo", 30, function()
		sendMove({ kind = "undo" })
	end)
	toolButton("Clear", 31, function()
		sendMove({ kind = "clear" })
	end)
	toolButton("Skip", 32, function()
		sendMove({ kind = "giveUp" })
	end, Theme.Bad)
	refreshTools()
	local TOOL_COUNT = #Rules.sizes + #TOOLS + 4

	-- Guessers' buttons -------------------------------------------------------------------

	local guesserBar = Kit.new("Frame", { BackgroundTransparency = 1, Parent = root })
	local guesserList = Kit.list(GAP, true)
	guesserList.Parent = guesserBar
	local function barButton(text: string, order: number, onClick: () -> (), color: Color3?): TextButton
		return Kit.button(text, onClick, {
			BackgroundColor3 = color or Theme.PanelLight,
			TextColor3 = Theme.Text,
			TextSize = 14,
			LayoutOrder = order,
			Parent = guesserBar,
		})
	end
	local hideButton = barButton("Hide", 1, function()
		if not snapshot then
			return
		end
		local turn = snapshot.view.turnNumber
		hiddenTurn = if hiddenTurn == turn then nil else turn
		rerender()
	end)
	local skipVoteButton = barButton("Vote skip", 2, function()
		sendMove({ kind = "voteSkip" })
	end, Theme.Warn)
	local reportButton = barButton("Report", 3, function()
		reportPrompt.Visible = true
	end, Theme.Bad)

	-- Guesses -------------------------------------------------------------------------

	local feedPanel = Kit.new("Frame", { BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, Parent = root }, { Kit.corner(12), Kit.padding(8) })
	local feedFrame = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		Parent = feedPanel,
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
		Parent = root,
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

	-- Report prompt ---------------------------------------------------------------------

	local function promptLabel(text: string, order: number, size: number, bold: boolean?)
		return Kit.label(text, {
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = size,
			Font = if bold then Theme.FontBold else Theme.Font,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, size + 2),
			LayoutOrder = order,
			ZIndex = 21,
			Parent = reportPrompt,
		})
	end
	local reportTitle = promptLabel("Report this drawing?", 1, 18, true)
	local reportBody = promptLabel(
		"It's hidden for you, their drawings stay hidden for you this game, and it counts as a vote to skip. To report the player to Roblox, open the Roblox menu and pick Report.",
		2,
		13
	)
	local reportButtons = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 3, ZIndex = 21, Parent = reportPrompt })
	local reportButtonList = Kit.list(GAP, true)
	reportButtonList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	reportButtonList.Parent = reportButtons

	local function drawerPlayer(): Player?
		local s = snapshot and snapshot.seats[snapshot.view.drawer]
		return if s and s.userId then Players:GetPlayerByUserId(s.userId) else nil
	end
	local function report(block: boolean)
		reportPrompt.Visible = false
		if not snapshot then
			return
		end
		hiddenDrawers[snapshot.view.drawer] = true
		sendMove({ kind = "report" })
		local target = drawerPlayer()
		if block and target then
			pcall(function()
				StarterGui:SetCore("PromptBlockPlayer", target)
			end)
		end
		rerender()
	end
	local function promptButton(text: string, order: number, color: Color3, onClick: () -> ())
		Kit.button(text, onClick, {
			BackgroundColor3 = color,
			TextColor3 = Theme.Text,
			TextSize = 14,
			Size = UDim2.new(0.31, 0, 1, 0),
			LayoutOrder = order,
			ZIndex = 22,
			Parent = reportButtons,
		})
	end
	promptButton("Report", 1, Theme.Bad, function()
		report(false)
	end)
	promptButton("Report + block", 2, Theme.Bad, function()
		report(true)
	end)
	promptButton("Cancel", 3, Theme.PanelLight, function()
		reportPrompt.Visible = false
	end)

	-- Layout ----------------------------------------------------------------------------

	local canvasSize = Vector2.new(600, 450)
	local overlayButtonH = 44
	local overlayTitleSize = 26
	local overlaySizeKey = ""
	local renderOverlay: (any, boolean?) -> ()

	local function amDrawing(): boolean
		local view = snapshot and snapshot.view
		return view ~= nil and snapshot.yourSeat ~= nil and snapshot.yourSeat == view.drawer and view.phase == "draw"
	end
	local function amGuessing(): boolean
		local view = snapshot and snapshot.view
		return view ~= nil and view.phase == "draw" and snapshot.yourSeat ~= nil and snapshot.yourSeat ~= view.drawer
	end

	-- Places a grid of `count` square-ish cells in `width`; returns the height it takes.
	local function gridHeight(grid: UIGridLayout, count: number, width: number, cellW: number, cellH: number): number
		local cols = math.max(1, math.floor((width + 4) / (cellW + 4)))
		cols = math.min(cols, count)
		-- Stretch the cells so a row fills the width.
		local w = math.floor((width - 4 * (cols - 1)) / cols)
		grid.CellSize = UDim2.fromOffset(math.min(w, cellW * 1.6), cellH)
		local rows = math.ceil(count / cols)
		return rows * cellH + (rows - 1) * 4
	end

	local function place(obj: GuiObject, x: number, y: number, w: number, h: number)
		obj.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
		obj.Size = UDim2.fromOffset(math.max(0, math.floor(w)), math.max(0, math.floor(h)))
	end

	local function layout()
		local size = root.AbsoluteSize
		local W, H = size.X, size.Y
		if W <= 0 or H <= 0 then
			return
		end
		local drawing = amDrawing()
		local guessing = amGuessing()
		local view = snapshot and snapshot.view
		local canGuess = guessing and view and not view.youGuessed

		local stacked = docked or W < 560 or W < H * 1.15
		local x0, colW = 0, W
		if docked then
			x0 = W * (1 - DOCK_SHARE)
			colW = W * DOCK_SHARE
		end
		local small = stacked or H < 420
		local swatchCell = if small then 26 else 32
		local toolCell = if small then 32 else 36

		toolbar.Visible = drawing
		guesserBar.Visible = guessing
		guessBox.Visible = canGuess == true

		if stacked then
			local y = 0
			local wordH = if small then 28 else 36
			wordBar.TextSize = if small then 20 else 28
			place(wordBar, x0, y, colW, wordH)
			y += wordH + 4
			local toolsH = 0
			if drawing then
				local swatchH = gridHeight(swatchGrid, #Rules.palette, colW, swatchCell, swatchCell)
				local toolH = gridHeight(toolGrid, TOOL_COUNT, colW, 52, toolCell)
				place(swatches, 0, 0, colW, swatchH)
				place(tools, 0, swatchH + GAP, colW, toolH)
				toolsH = swatchH + GAP + toolH
			end
			local barH = if guessing then 32 else 0
			local boxH = if canGuess then 40 else 0
			local below = (if drawing then toolsH + GAP else 0) + (if guessing then barH + GAP else 0) + (if canGuess then boxH + GAP else 0)
			local feedMin = if drawing then 60 else 90
			local canvasH = math.max(80, math.min(colW / CANVAS_RATIO, H - y - below - feedMin))
			place(canvasHolder, x0, y, colW, canvasH)
			y += canvasH + GAP
			if drawing then
				place(toolbar, x0, y, colW, toolsH)
				y += toolsH + GAP
			end
			if guessing then
				place(guesserBar, x0, y, colW, barH)
				y += barH + GAP
			end
			local feedH = H - y - (if canGuess then boxH + GAP else 0)
			place(feedPanel, x0, y, colW, math.max(0, feedH))
			if canGuess then
				place(guessBox, x0, H - boxH, colW, boxH)
			end
			for _, b in { hideButton, skipVoteButton, reportButton } do
				b.Size = UDim2.new(1 / 3, -GAP, 1, 0)
			end
		else
			local leftW = W * 0.68 - 10
			local rightX = W * 0.68
			local rightW = W * 0.32
			wordBar.TextSize = 28
			place(wordBar, 0, 0, leftW, 36)
			local y = 42
			local toolsH = 0
			if drawing then
				local swatchH = gridHeight(swatchGrid, #Rules.palette, leftW, swatchCell, swatchCell)
				local toolH = gridHeight(toolGrid, TOOL_COUNT, leftW, 56, toolCell)
				place(swatches, 0, 0, leftW, swatchH)
				place(tools, 0, swatchH + GAP, leftW, toolH)
				toolsH = swatchH + GAP + toolH
			end
			local bottomH = if drawing then toolsH elseif guessing then 38 else 0
			local canvasH = H - y - (if bottomH > 0 then bottomH + GAP else 0)
			place(canvasHolder, 0, y, leftW, canvasH)
			if drawing then
				place(toolbar, 0, H - toolsH, leftW, toolsH)
			end
			if guessing then
				place(guesserBar, 0, H - 38, leftW, 38)
				for _, b in { hideButton, skipVoteButton, reportButton } do
					b.Size = UDim2.fromOffset(130, 38)
				end
			end
			local boxH = if canGuess then 44 else 0
			place(feedPanel, rightX, 0, rightW, H - (if canGuess then boxH + GAP else 0))
			if canGuess then
				place(guessBox, rightX, H - boxH, rightW, boxH)
			end
		end

		-- Overlay text and buttons scale with the canvas.
		local ch = canvasHolder.AbsoluteSize.Y
		overlayTitleSize = math.clamp(math.floor(ch / 11), 15, 26)
		overlayButtonH = math.clamp(math.floor(ch / 7), 28, 44)
		reportTitle.TextSize = math.clamp(math.floor(ch / 14), 14, 20)
		reportBody.TextSize = math.clamp(math.floor(ch / 20), 11, 15)
		local sizeKey = `{overlayTitleSize}:{overlayButtonH}`
		if snapshot and sizeKey ~= overlaySizeKey then
			overlaySizeKey = sizeKey
			renderOverlay(snapshot.view, true)
		end
	end

	-- Drawing ---------------------------------------------------------------------------

	local rendered = 0 -- how many of the server's strokes are on the canvas
	local renderedLast: string? = nil

	-- Drawer's own lines and shapes that the server hasn't echoed yet.
	local previewChunks: { Frame } = {}
	local previewSentAt: { number } = {}
	local livePoints: { number } = {} -- pen: the chunk being drawn now; shapes: start, end
	local liveFrame: Frame? = nil
	local liveCont = false
	local drawing = false
	local activeInput: InputObject? = nil
	local liveTool = "pen"
	local sinceSend = 0

	local function clearPreview()
		previewLayer:ClearAllChildren()
		table.clear(previewChunks)
		table.clear(previewSentAt)
		liveFrame = nil
	end

	local function redrawAll()
		strokeLayer:ClearAllChildren()
		local strokes = snapshot and snapshot.view.strokes or {}
		for _, s in strokes do
			SketchCanvas.draw(strokeLayer, s, canvasSize, { round = true })
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
			SketchCanvas.draw(strokeLayer, strokes[i], canvasSize, { round = true })
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
		if canvas.AbsoluteSize.X <= 0 then
			return
		end
		canvasSize = canvas.AbsoluteSize
		if snapshot then
			redrawAll()
			clearPreview()
		end
	end)
	canvasSize = if canvas.AbsoluteSize.X > 0 then canvas.AbsoluteSize else canvasSize

	local function isDrawer(): boolean
		return amDrawing() and table.find(snapshot.activeSeats, snapshot.yourSeat) ~= nil
	end

	local function toCanvas(screen: Vector2): (number, number)
		local rel = (screen - canvas.AbsolutePosition) / canvas.AbsoluteSize
		return math.clamp(rel.X, 0, 1) * RES, math.clamp(rel.Y, 0, 1) * RES
	end

	local function newLiveFrame(): Frame
		return Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = previewLayer })
	end

	local function brush(): any
		return { color = brushColor, size = brushSize }
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
		liveFrame = newLiveFrame()
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
			local seg = if n >= 4 then { livePoints[n - 3], livePoints[n - 2], x, y } else { x, y }
			SketchCanvas.drawPoints(liveFrame, seg, brush(), canvasSize, { round = true })
		end
		if n // 2 >= Rules.maxPointsPerStroke then
			sendLive()
		end
	end

	local function shapeStroke(): any
		local s = brush()
		s.shape = liveTool
		s.fill = fill and liveTool ~= "line"
		return s
	end

	local function updateShape(screen: Vector2)
		local x, y = toCanvas(screen)
		livePoints[3], livePoints[4] = x, y
		if liveFrame then
			liveFrame:ClearAllChildren()
			SketchCanvas.drawPoints(liveFrame, livePoints, shapeStroke(), canvasSize, { round = true })
		end
	end

	local function finishShape()
		if #livePoints < 4 or not liveFrame then
			return
		end
		local dx, dy = math.abs(livePoints[3] - livePoints[1]) / RES, math.abs(livePoints[4] - livePoints[2]) / RES
		local tooSmall = if liveTool == "line" then math.max(dx, dy) < MIN_SHAPE else (dx < MIN_SHAPE or dy < MIN_SHAPE)
		if tooSmall then
			liveFrame:Destroy()
			return
		end
		local s = shapeStroke()
		sendMove({ kind = "shape", shape = s.shape, color = s.color, size = s.size, fill = s.fill, points = Rules.encodePoints(livePoints) })
		table.insert(previewChunks, liveFrame)
		table.insert(previewSentAt, os.clock())
	end

	-- The ScreenGui ignores the GUI inset, so input positions and AbsolutePosition
	-- already share one space.
	local function screenPos(input: InputObject): Vector2
		return Vector2.new(input.Position.X, input.Position.Y)
	end

	local drawOpenedAt = 0 -- when this client last saw the drawing phase start

	local function stopDrawing()
		drawing = false
		activeInput = nil
		if liveFrame and liveTool == "pen" and #livePoints <= 2 then
			liveFrame:Destroy()
		end
		liveFrame = nil
		livePoints = {}
	end

	canvas.InputBegan:Connect(function(input)
		-- Ignore a click that picked the word, or arrives just as the canvas opens.
		if drawing or not isDrawer() or overlay.Visible or os.clock() - drawOpenedAt < 0.4 then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			drawing = true
			activeInput = input
			liveTool = if snapshot.view.tools == "shapes" and tool == "pen" then "line" else tool
			liveCont = false
			livePoints = {}
			liveFrame = newLiveFrame()
			sinceSend = 0
			if liveTool == "pen" then
				addPoint(screenPos(input))
			else
				local x, y = toCanvas(screenPos(input))
				livePoints = { x, y, x, y }
			end
		end
	end)
	local moved = UserInputService.InputChanged:Connect(function(input)
		if not drawing then
			return
		end
		local isMouse = input.UserInputType == Enum.UserInputType.MouseMovement and activeInput ~= nil and activeInput.UserInputType == Enum.UserInputType.MouseButton1
		local isTouch = input.UserInputType == Enum.UserInputType.Touch and input == activeInput
		if not (isMouse or isTouch) then
			return
		end
		if not isDrawer() then
			stopDrawing()
			return
		end
		if liveTool == "pen" then
			addPoint(screenPos(input))
		else
			updateShape(screenPos(input))
		end
	end)
	local ended = UserInputService.InputEnded:Connect(function(input)
		if not drawing then
			return
		end
		local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
		local isTouch = input.UserInputType == Enum.UserInputType.Touch and input == activeInput
		if not (isMouse or isTouch) then
			return
		end
		if liveTool == "pen" then
			if #livePoints == 2 then
				-- A single tap: send it as a dot.
				table.insert(livePoints, livePoints[1])
				table.insert(livePoints, livePoints[2])
			end
			sendLive()
		else
			finishShape()
			liveFrame = nil
		end
		stopDrawing()
	end)
	local heartbeat = RunService.Heartbeat:Connect(function(dt)
		if drawing and liveTool == "pen" then
			sinceSend += dt
			if sinceSend >= SEND_EVERY then
				sendLive()
			end
		end
	end)

	-- Rendering -------------------------------------------------------------------------

	local function nameOf(seat: number?): string
		if not seat then
			return "?"
		end
		local s = snapshot.seats[seat]
		return if seat == snapshot.yourSeat then "You" elseif s then s.name else "?"
	end

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
			local who = if entry.seat then nameOf(entry.seat) else ""
			local color = Theme.Text
			local text
			if entry.kind == "system" then
				text = if entry.seat then `{who} {entry.text}` else entry.text
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
	local function overlayLabel(text: string, order: number, props: { [string]: any }?)
		local label = Kit.label(text, {
			Font = Theme.FontBold,
			TextSize = overlayTitleSize,
			TextXAlignment = Enum.TextXAlignment.Center,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, overlayTitleSize + 4),
			LayoutOrder = order,
			ZIndex = 11,
			Parent = overlay,
		})
		for k, v in props or {} do
			(label :: any)[k] = v
		end
		return label
	end

	function renderOverlay(view: any, force: boolean?)
		local key = `{view.phase}:{view.turnNumber}`
		if key == overlayKey and not force then
			return
		end
		if key ~= overlayKey and view.phase == "draw" then
			drawOpenedAt = os.clock()
		end
		overlayKey = key
		Kit.clear(overlay)
		local me = snapshot.yourSeat
		if view.phase == "choose" then
			overlay.Visible = true
			if view.choices then
				overlayLabel("Pick a word to draw", 1)
				for i, word in view.choices do
					local label = string.split(word, "|")[1]
					Kit.button(`{label}   ({({ "easy", "medium", "hard" })[i] or "?"})`, function()
						sendMove({ kind = "choose", index = i })
					end, {
						Size = UDim2.new(0.9, 0, 0, overlayButtonH),
						TextSize = math.clamp(overlayButtonH - 22, 13, 18),
						LayoutOrder = 1 + i,
						ZIndex = 12,
						Parent = overlay,
					})
				end
			else
				overlayLabel(`{nameOf(view.drawer)} {if view.drawer == me then "are" else "is"} picking a word...`, 1)
			end
		elseif view.phase == "reveal" or view.phase == "done" then
			overlay.Visible = true
			overlayLabel(if view.word then `The word was "{view.word}"` else "Round over", 1)
			local order = {}
			for seat, points in view.lastPoints or {} do
				table.insert(order, { seat = seat, points = points })
			end
			table.sort(order, function(a, b)
				return a.points > b.points
			end)
			if #order == 0 then
				overlayLabel("Nobody scored this time.", 2, { Font = Theme.Font, TextColor3 = Theme.SubText, TextSize = math.max(13, overlayTitleSize - 6) })
			end
			for i, row in order do
				if i > 6 then
					break
				end
				overlayLabel(`{nameOf(row.seat)}   +{row.points}`, 1 + i, { TextColor3 = Theme.Good, TextSize = math.max(13, overlayTitleSize - 6) })
			end
		else
			overlay.Visible = false
		end
	end

	-- Hides the drawing on the screen over our table too (only on this client).
	local screenHidden = false
	local function setScreenHidden(hide: boolean)
		if hide == screenHidden and not hide then
			return
		end
		screenHidden = hide
		local tableInfo = snapshot and snapshot.table
		if not tableInfo then
			return
		end
		for _, model in CollectionService:GetTagged(Config.TableTag) do
			if model:GetAttribute("TableId") == tableInfo.id then
				local board = model:FindFirstChild("GameBoard")
				if board then
					for _, d in board:GetDescendants() do
						if d:IsA("SurfaceGui") then
							d.Enabled = not hide
						end
					end
				end
			end
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
				local hint = view.hint or ""
				local letters = select(2, string.gsub(hint, "[%a_]", ""))
				wordBar.Text = `{hint}   ({letters})`
			end
		elseif view.phase == "choose" then
			wordBar.Text = `Drawing {view.turnNumber} of {view.totalTurns}`
		else
			wordBar.Text = ""
		end

		if view.tools == "shapes" and tool == "pen" then
			tool = "line"
			refreshTools()
		end
		toolButtons.pen.Visible = view.tools ~= "shapes"

		local drawerSeat = snapshot.seats[view.drawer]
		local drawerIsBot = view.drawerIsBot or (drawerSeat ~= nil and drawerSeat.kind == "bot")
		skipVoteButton.Visible = not view.youVotedSkip
		reportButton.Visible = not view.youReported and not drawerIsBot
		if not amGuessing() or not reportButton.Visible then
			reportPrompt.Visible = false
		end

		local hidden = (view.phase == "draw" or view.phase == "reveal") and (hiddenTurn == view.turnNumber or hiddenDrawers[view.drawer] == true)
		strokeLayer.Visible = not hidden
		hiddenLabel.Visible = hidden
		hideButton.Text = if hidden then "Show" else "Hide"
		setScreenHidden(hidden)

		if not guessBox.Visible or view.youGuessed then
			guessBox:ReleaseFocus()
		end
		if not isDrawer() and drawing then
			stopDrawing()
		end

		layout()
		syncStrokes()
		renderFeed(view)
		renderOverlay(view)
	end
	function rerender()
		if snapshot then
			render()
		end
	end

	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if snapshot then
			layout()
		end
	end)

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			render()
		end,
		setDocked = function(isDocked: boolean)
			docked = isDocked
			if snapshot then
				render()
			end
		end,
		destroy = function()
			setScreenHidden(false)
			moved:Disconnect()
			ended:Disconnect()
			heartbeat:Disconnect()
			root:Destroy()
		end,
	}
end

return SketchGuess
