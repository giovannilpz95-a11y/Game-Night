-- Sketch & Guess: the canvas, the drawing tools and the guesses.
--
-- Layouts (picked from the space we get, redone whenever it changes):
--   wide     canvas and tools on the left, guesses and the guess box on the right.
--   stacked  one column: word, canvas, tools (or the guesser's buttons), guesses, guess
--            box. Used on narrow or portrait screens, and in the Table view dock, where
--            only the right DOCK_SHARE of the board shows (MatchView's DOCK entry).
--
-- Drawer: pick 1 of 3 words, then draw with the pen or the line / box / oval tools,
-- 14 colors (white is the eraser), 4 sizes, Solid for filled boxes and ovals, the Fill
-- bucket (a flood fill, see shared/SketchFill), undo and clear. Keyboard: P L B O F, Ctrl+Z.
-- Pen lines are drawn locally right away and sent in small chunks (about 5 a second) so
-- everyone sees the drawing build up live. Touch follows one finger only.
-- Guessers: type guesses in the box. Near misses get a private "close!" note. Once you
-- got it, the box chats with the drawer and the others who got it (nobody else sees it).
-- Like / dislike: thumbs under the drawing, and at the reveal. After the last drawing the
-- gallery shows the most liked drawings of the game.
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
local Juice = require(script.Parent.Parent.UI.Juice)
local Audio = require(script.Parent.Parent.Audio)
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
	{ id = "bucket", label = "Fill" },
}
local SHORTCUTS = {
	[Enum.KeyCode.P] = "pen",
	[Enum.KeyCode.L] = "line",
	[Enum.KeyCode.B] = "rect",
	[Enum.KeyCode.O] = "ellipse",
	[Enum.KeyCode.F] = "bucket",
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
	local fillButton: TextButton -- "Solid": filled boxes and ovals

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
	fillButton = toolButton("Solid", 20, function()
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
	local likeButton = barButton("👍", 4, function()
		sendMove({ kind = "rate", up = true })
	end)
	local dislikeButton = barButton("👎", 5, function()
		sendMove({ kind = "rate", up = false })
	end)
	local barButtons = { hideButton, skipVoteButton, reportButton, likeButton, dislikeButton }

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
		local view = snapshot and snapshot.view
		sendMove({ kind = if view and view.youGuessed then "chat" else "guess", text = text })
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
		-- Guessers always have the box: after a right guess it's the "got it" chat.
		local canGuess = guessing and view ~= nil

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
			for _, b in barButtons do
				local share = if b == likeButton or b == dislikeButton then 0.13 else 0.24
				b.Size = UDim2.new(share, -GAP, 1, 0)
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
				for _, b in barButtons do
					local share = if b == likeButton or b == dislikeButton then 0.12 else 0.2
					b.Size = UDim2.new(share, -GAP, 1, 0)
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
	local raster = SketchCanvas.newRaster() -- where fill buckets spread

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
		raster:reset()
		local strokes = snapshot and snapshot.view.strokes or {}
		for _, s in strokes do
			SketchCanvas.draw(strokeLayer, s, canvasSize, { round = true, raster = raster })
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
			SketchCanvas.draw(strokeLayer, strokes[i], canvasSize, { round = true, raster = raster })
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
			if tool == "bucket" then
				-- One tap pours the fill. It shows when the server echoes it (the area depends
				-- on the whole drawing); the empty placeholder keeps the preview queue in step.
				local view = snapshot.view
				if (view.buckets or 0) >= (view.maxBuckets or math.huge) then
					Juice.nope(toolButtons.bucket)
					return
				end
				local x, y = toCanvas(screenPos(input))
				sendMove({ kind = "bucket", color = brushColor, points = Rules.encodePoints({ x, y }) })
				table.insert(previewChunks, newLiveFrame())
				table.insert(previewSentAt, os.clock())
				Audio.play("pop", { volume = 0.5 })
				return
			end
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

	-- Keyboard shortcuts for the drawer on a computer (not while typing in a box).
	local keys = UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.Keyboard or not isDrawer() then
			return
		end
		if UserInputService:GetFocusedTextBox() then
			return
		end
		local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		if input.KeyCode == Enum.KeyCode.Z and ctrl then
			sendMove({ kind = "undo" })
			return
		end
		local pick = SHORTCUTS[input.KeyCode]
		if pick and not ctrl and toolButtons[pick] and toolButtons[pick].Visible then
			tool = pick
			refreshTools()
			Juice.bump(toolButtons[pick])
		end
	end)

	-- A ring under the mouse showing the brush size and color (drawer, mouse only).
	local mousePos = Vector2.new(-1e4, -1e4)
	local cursor = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 5,
		Parent = canvas,
	}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), Kit.new("UIStroke", { Thickness = 1.5, Color = Color3.fromRGB(120, 120, 130) }) })
	local function updateCursor()
		local show = isDrawer() and not overlay.Visible and UserInputService.MouseEnabled and not UserInputService.TouchEnabled
		local rel = mousePos - canvas.AbsolutePosition
		local inside = rel.X >= 0 and rel.Y >= 0 and rel.X <= canvas.AbsoluteSize.X and rel.Y <= canvas.AbsoluteSize.Y
		cursor.Visible = show and inside
		if cursor.Visible then
			local d = if tool == "bucket" then 10 else math.max(4, SketchCanvas.width(brushSize, canvasSize))
			cursor.Size = UDim2.fromOffset(d, d)
			cursor.Position = UDim2.fromOffset(rel.X, rel.Y)
			local stroke = cursor:FindFirstChildOfClass("UIStroke") :: UIStroke
			stroke.Color = if brushColor == 2 then Color3.fromRGB(120, 120, 130) else SketchCanvas.color(brushColor)
		end
	end
	-- Same space as the drawing input (see screenPos), so the ring sits on the pen.
	local cursorMoved = UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			mousePos = screenPos(input)
		end
	end)
	local cursorBeat = RunService.RenderStepped:Connect(updateCursor)

	-- Rendering -------------------------------------------------------------------------

	local function nameOf(seat: number?): string
		if not seat then
			return "?"
		end
		local s = snapshot.seats[seat]
		return if seat == snapshot.yourSeat then "You" elseif s then s.name else "?"
	end

	local feedKey = ""
	local heardKey: string? = nil -- the newest feed entry we've played a sound for
	local function playFeedSounds(feed: { any })
		local last = feed[#feed]
		local key = if last then `{last.kind}:{last.seat}:{last.text}:{#feed}` else ""
		if heardKey == nil or key == heardKey then
			heardKey = key -- first look at this match: don't replay what already happened
			return
		end
		-- Walk back to the entries we haven't heard yet (at most a few per update).
		local start = #feed
		for i = #feed, math.max(1, #feed - 5), -1 do
			local e = feed[i]
			if `{e.kind}:{e.seat}:{e.text}:{i}` == heardKey then
				break
			end
			start = i
		end
		heardKey = key
		for i = start, #feed do
			local e = feed[i]
			if e.kind == "correct" then
				if e.seat == snapshot.yourSeat then
					Audio.coins(4)
				else
					Audio.play("callout")
				end
			elseif e.kind == "close" then
				Audio.play("pop")
			elseif e.kind == "like" then
				Audio.play("toggle", { volume = 0.6 })
			end
		end
	end

	local function renderFeed(view: any)
		local feed = view.feed
		local last = feed[#feed]
		local key = `{#feed}:{if last then last.text else ""}`
		if key == feedKey then
			return
		end
		feedKey = key
		playFeedSounds(feed)
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
			elseif entry.kind == "like" then
				text = `👍 {who} {entry.text}`
				color = Theme.SubText
			elseif entry.kind == "chat" then
				-- Only players who know the word get these.
				text = `✓ {who}: {entry.text}`
				color = Theme.Good
			else
				text = `{who}: {entry.text}`
			end
			Kit.label(text, {
				TextSize = 15,
				TextColor3 = color,
				Font = if entry.kind == "guess" or entry.kind == "chat" then Theme.Font else Theme.FontBold,
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

	-- After the last drawing: the most liked drawings of the game, small, two by two.
	-- Drawings by players you reported, or ones you hid, stay out of it.
	local function renderGallery(view: any)
		overlayLabel("Best drawings", 1)
		local entries = {}
		for _, e in view.gallery or {} do
			if not hiddenDrawers[e.drawer] and hiddenTurn ~= e.turn then
				table.insert(entries, e)
			end
		end
		if #entries == 0 then
			overlayLabel("Nothing to show this time.", 2, { Font = Theme.Font, TextColor3 = Theme.SubText, TextSize = math.max(13, overlayTitleSize - 6) })
			return
		end
		local area = canvas.AbsoluteSize
		local cols = if #entries == 1 then 1 else 2
		local rows = math.ceil(#entries / cols)
		local captionH = math.clamp(math.floor(area.Y / 16), 12, 18)
		local availH = area.Y - 16 - (overlayTitleSize + 4) - 6
		local cellH = math.floor((availH - (rows - 1) * GAP) / rows)
		local thumbH = math.max(20, cellH - captionH - 2)
		local thumbW = math.min(math.floor(thumbH * CANVAS_RATIO), math.floor((area.X - 16 - (cols - 1) * GAP) / cols))
		thumbH = math.floor(thumbW / CANVAS_RATIO)
		local grid = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, rows * (thumbH + captionH + 2) + (rows - 1) * GAP),
			LayoutOrder = 2,
			ZIndex = 11,
			Parent = overlay,
		})
		Kit.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(thumbW, thumbH + captionH + 2),
			CellPadding = UDim2.fromOffset(GAP, GAP),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = grid,
		})
		for i, e in entries do
			local cell = Kit.new("Frame", { BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 11, Parent = grid })
			local thumb = Kit.new("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(thumbW, thumbH),
				ClipsDescendants = true,
				ZIndex = 11,
				Parent = cell,
			}, { Kit.corner(8) })
			local thumbRaster = SketchCanvas.newRaster()
			local budget = 350
			for _, stroke in e.strokes do
				budget -= SketchCanvas.draw(thumb, stroke, Vector2.new(thumbW, thumbH), { raster = thumbRaster, budget = budget })
			end
			for _, d in thumb:GetDescendants() do
				if d:IsA("GuiObject") then
					d.ZIndex = 12
				end
			end
			local crown = if i == 1 and e.likes > 0 then "🏆 " else ""
			local likes = if e.likes > 0 then `  👍 {e.likes}` else ""
			Kit.label(`{crown}{e.word} · {nameOf(e.drawer)}{likes}`, {
				TextSize = captionH - 2,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(0, thumbH + 2),
				Size = UDim2.fromOffset(thumbW, captionH),
				ZIndex = 12,
				Parent = cell,
			})
			Juice.popIn(cell)
		end
	end

	function renderOverlay(view: any, force: boolean?)
		local key = `{view.phase}:{view.turnNumber}:{view.likes or 0}:{tostring(view.youLiked)}`
		if view.phase ~= "reveal" then
			key = `{view.phase}:{view.turnNumber}`
		end
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
				local count = #view.choices
				local h = if count > 3 then math.max(24, math.floor(overlayButtonH * 0.72)) else overlayButtonH
				for i, word in view.choices do
					local label = string.split(word, "|")[1]
					local level = view.choiceLevels and view.choiceLevels[i]
					local b = Kit.button(if level then `{label}   ({level})` else label, function()
						sendMove({ kind = "choose", index = i })
					end, {
						Size = UDim2.new(0.9, 0, 0, h),
						TextSize = math.clamp(h - 22, 13, 18),
						LayoutOrder = 1 + i,
						ZIndex = 12,
						Parent = overlay,
					})
					Juice.popIn(b)
				end
				if not force then
					Audio.play("turn")
				end
			else
				overlayLabel(`{nameOf(view.drawer)} {if view.drawer == me then "are" else "is"} picking a word...`, 1)
			end
		elseif view.phase == "gallery" then
			overlay.Visible = true
			renderGallery(view)
		elseif view.phase == "reveal" or view.phase == "done" then
			overlay.Visible = true
			overlayLabel(if view.word then `The word was "{view.word}"` else "Round over", 1)
			if view.phase == "reveal" and (view.likes or 0) > 0 then
				overlayLabel(`👍 {view.likes}`, 2, { TextSize = math.max(13, overlayTitleSize - 8), TextColor3 = Theme.SubText })
			end
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
				overlayLabel(`{nameOf(row.seat)}   +{row.points}`, 2 + i, { TextColor3 = Theme.Good, TextSize = math.max(13, overlayTitleSize - 6) })
			end
			-- Rate it before the next one starts (skribbl's thumbs at the turn's end).
			if view.phase == "reveal" and me ~= nil and me ~= view.drawer and view.youLiked == nil and #view.strokes > 0 then
				local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, overlayButtonH), LayoutOrder = 20, ZIndex = 11, Parent = overlay })
				local list = Kit.list(GAP, true)
				list.HorizontalAlignment = Enum.HorizontalAlignment.Center
				list.Parent = row
				for i, up in { true, false } do
					Kit.button(if up then "👍" else "👎", function()
						sendMove({ kind = "rate", up = up })
					end, {
						Size = UDim2.fromOffset(overlayButtonH * 1.6, overlayButtonH),
						TextSize = math.clamp(overlayButtonH - 16, 14, 26),
						BackgroundColor3 = Theme.PanelLight,
						LayoutOrder = i,
						ZIndex = 12,
						Parent = row,
					})
				end
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
		elseif view.phase == "gallery" then
			wordBar.Text = "Gallery"
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
		likeButton.BackgroundColor3 = if view.youLiked == true then Theme.Good else Theme.PanelLight
		dislikeButton.BackgroundColor3 = if view.youLiked == false then Theme.Bad else Theme.PanelLight
		guessBox.PlaceholderText = if view.youGuessed then "Chat with players who got it..." else "Type your guess..."
		reportButton.Visible = not view.youReported and not drawerIsBot
		if not amGuessing() or not reportButton.Visible then
			reportPrompt.Visible = false
		end

		local hidden = (view.phase == "draw" or view.phase == "reveal") and (hiddenTurn == view.turnNumber or hiddenDrawers[view.drawer] == true)
		strokeLayer.Visible = not hidden
		hiddenLabel.Visible = hidden
		hideButton.Text = if hidden then "Show" else "Hide"
		-- The screen over the table shows the gallery's best drawing at the end.
		local best = view.phase == "gallery" and view.gallery and view.gallery[1]
		local bestHidden = best and (hiddenDrawers[best.drawer] == true or hiddenTurn == best.turn)
		setScreenHidden(hidden or bestHidden == true)

		if not guessBox.Visible then
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
			keys:Disconnect()
			cursorBeat:Disconnect()
			cursorMoved:Disconnect()
			root:Destroy()
		end,
	}
end

return SketchGuess
