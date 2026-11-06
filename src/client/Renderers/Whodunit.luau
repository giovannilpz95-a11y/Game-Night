-- Whodunit table: the mansion map on the left (3x3 rooms with pawns and items; rooms you
-- can walk to glow, tap one to move), and on the right what to do now (suggest, show a
-- card, end turn, accuse) above your detective notes and the case log.
-- The notes fill themselves with your cards and every card shown to you; tap a row's
-- mark to note your own guesses (✗ ? ✓). Marks live only on this client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Rules = require(ReplicatedStorage.Shared.Games.Whodunit)
local Kit = require(script.Parent.Parent.UI.Kit)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local Juice = require(script.Parent.Parent.UI.Juice)
local Audio = require(script.Parent.Parent.Audio)
local TablePrompt = require(script.Parent.Parent.UI.TablePrompt)
local Theme = Kit.Theme

local Whodunit = {}

local theme = Rules.theme
local ROOM_COLORS = {
	Color3.fromRGB(92, 70, 58), -- Kitchen
	Color3.fromRGB(78, 62, 104), -- Music Room
	Color3.fromRGB(40, 56, 98), -- Observatory
	Color3.fromRGB(52, 92, 64), -- Greenhouse
	Color3.fromRGB(110, 84, 48), -- Grand Hall
	Color3.fromRGB(96, 50, 96), -- Arcade
	Color3.fromRGB(40, 92, 112), -- Pool
	Color3.fromRGB(70, 74, 82), -- Garage
	Color3.fromRGB(88, 60, 44), -- Library
}
local ITEM_ICONS = { "🐔", "🧗", "🦋", "🧲", "☂️", "🎣" }
local MARKS = { "·", "✗", "?", "✓" }
local MARK_COLORS = { Theme.SubText, Theme.Bad, Theme.Accent, Theme.Good }

local function suspectColor(i: number): Color3
	return Theme.Seat[i] or Theme.Text
end

function Whodunit.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	-- Your own marks in the notes grid: marks[card][seat] -> index into MARKS.
	local marks: { [number]: { [number]: number } } = {}
	local lastRooms: { [number]: number } = {} -- suspect -> room on the last render (pawn pops)
	local roundKey: number? = nil -- the suggestion whose go-round is playing
	local roundStart = 0
	local endShownFor: string? = nil -- the match whose case file already flipped open
	local pickSuspect: number? = nil
	local pickItem: number? = nil
	local accuseOpen = false
	local accusePick = { suspect = nil :: number?, item = nil :: number?, room = nil :: number? }
	local bottomTab = "notes"
	local lastMatchId: string? = nil

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
	local shownAccusations: number? = nil -- accusations already opened on screen
	local revealed: any = nil -- the suggestion whose shown card already flipped up
	local revealedKeys: { [string]: boolean } = {}

	-- Mansion map -----------------------------------------------------------------
	local map = Kit.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(30, 26, 44),
		BorderSizePixel = 0,
		Size = UDim2.new(0.56, 0, 1, 0),
		Parent = root,
	}, { Kit.corner(18), Kit.padding(8) })

	-- Right column ------------------------------------------------------------------
	local side = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0.56, 12, 0, 0),
		Size = UDim2.new(0.44, -12, 1, 0),
		Parent = root,
	})
	local actionPanel = Kit.panel({ Size = UDim2.new(1, 0, 0.5, -6), Parent = side })
	-- Accusing is kept apart from the everyday buttons: a red bar pinned at the bottom.
	local accuseBar = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 38),
		Visible = false,
		Parent = actionPanel,
	})
	local actions = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		Parent = actionPanel,
	})
	Kit.list(8).Parent = actions

	local bottom = Kit.panel({ Position = UDim2.new(0, 0, 0.5, 6), Size = UDim2.new(1, 0, 0.5, -6), Parent = side })
	local tabs = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), Parent = bottom })
	local notesTab, logTab
	local notes = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 34),
		Size = UDim2.new(1, 0, 1, -34),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		Parent = bottom,
	})
	Kit.list(3).Parent = notes
	local logList = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 34),
		Size = UDim2.new(1, 0, 1, -34),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		Visible = false,
		Parent = bottom,
	})
	Kit.list(6).Parent = logList

	local render: () -> ()
	local docked = false -- Table view: only the side panel shows
	-- Table mode (Table view without the map): walk by tapping the glowing rooms on the
	-- table; what to do now is a panel along the bottom, the notes open in a window, and
	-- suggest / show / accuse pop up as before.
	local tableMode = false
	local prompt = TablePrompt.new(container)
	prompt.setVisible(false)
	local sideSize = Kit.new("UISizeConstraint", { MaxSize = Vector2.new(560, math.huge) })
	local notesButton = Kit.button("Notes", function()
		prompt.sheet(bottom, "Detective notes")
	end, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 0, -6),
		Size = UDim2.fromOffset(110, 34),
		BackgroundColor3 = Theme.PanelLight,
		TextColor3 = Theme.Text,
		Visible = false,
		Parent = side,
	})
	local function selectTab(tab: string)
		bottomTab = tab
		notes.Visible = tab == "notes"
		logList.Visible = tab == "log"
		notesTab.BackgroundColor3 = if tab == "notes" then Theme.Accent else Theme.PanelLight
		notesTab.TextColor3 = if tab == "notes" then Theme.AccentText else Theme.Text
		logTab.BackgroundColor3 = if tab == "log" then Theme.Accent else Theme.PanelLight
		logTab.TextColor3 = if tab == "log" then Theme.AccentText else Theme.Text
	end
	notesTab = Kit.button("Detective notes", function()
		selectTab("notes")
	end, { Size = UDim2.new(0.5, -4, 1, 0), TextSize = 14, Parent = tabs })
	logTab = Kit.button("Case log", function()
		selectTab("log")
	end, { Size = UDim2.new(0.5, -4, 1, 0), Position = UDim2.new(0.5, 4, 0, 0), TextSize = 14, Parent = tabs })
	HudKit.pill(notesTab)
	HudKit.pill(logTab)
	selectTab("notes")

	-- Accusation picker (an overlay over the whole table).
	local accuseOverlay = Kit.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})
	local accuseBox = Kit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.94, 0, 0.98, 0),
		BackgroundColor3 = Theme.PanelLight,
		ZIndex = 21,
		Parent = accuseOverlay,
	})
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(720, 900), Parent = accuseBox })
	-- Accuse / Cancel stay pinned at the bottom; the choices scroll above them.
	local accuseFooter = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 1, -40),
		Size = UDim2.new(1, 0, 0, 40),
		ZIndex = 21,
		Parent = accuseBox,
	})
	local accuseScroll = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -48),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ZIndex = 21,
		Parent = accuseBox,
	})
	local accuseList = Kit.list(6)
	accuseList.Parent = accuseScroll
	-- Fit the box to its content (choices + pinned buttons), but never past the screen.
	local function fitAccuseBox()
		local wanted = accuseList.AbsoluteContentSize.Y + 48 + 24 -- footer + panel padding
		local room = math.max(200, accuseOverlay.AbsoluteSize.Y * 0.98)
		-- Table view shows only the side column (the right 44%), so center on that.
		accuseBox.Position = UDim2.fromScale(if docked then 0.78 else 0.5, 0.5)
		accuseBox.Size = UDim2.new(if docked then 0.42 else 0.94, 0, 0, math.min(wanted, room))
	end
	accuseList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitAccuseBox)
	accuseOverlay:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitAccuseBox)
	Kit.new("UIPadding", { PaddingRight = UDim.new(0, 12), Parent = accuseScroll }) -- room for the scrollbar

	-- Show-a-card pop-up: when your cards can disprove someone, the matching ones come up
	-- big and you pick the one to slide across, face down to everyone but them.
	local showOverlay = Kit.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 30,
		Parent = root,
	})
	local showKey: string? = nil

	-- Helpers -----------------------------------------------------------------------

	local function nameOf(seat: number?): string
		if not seat then
			return "?"
		end
		if seat == snapshot.yourSeat then
			return "You"
		end
		local s = snapshot.seats[seat]
		return if s then s.name else "?"
	end

	local function cardName(id: number): string
		return Rules.cards[id].name
	end

	local function suggestionText(entry: any): string
		return `{theme.suspects[entry.suspect]} with the {theme.items[entry.item]} in the {theme.rooms[entry.room]}`
	end

	local function text(parent: Instance, value: string, order: number, props: { [string]: any }?): TextLabel
		local label = Kit.label(value, {
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			LayoutOrder = order,
			Parent = parent,
		})
		for key, v in props or {} do
			(label :: any)[key] = v
		end
		return label
	end

	-- A titled grid of choice buttons. colors[i] adds a color stripe.
	local function chips(parent: Instance, order: number, names: { string }, selected: number?, onPick: (number) -> (), colors: { Color3 }?, zIndex: number?, columns: number?)
		local perRow = columns or 2
		local grid = Kit.new("Frame", {
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			LayoutOrder = order,
			Parent = parent,
		})
		Kit.new("UIGridLayout", {
			CellSize = UDim2.new(1 / perRow, -6, 0, 30),
			CellPadding = UDim2.fromOffset(8, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = grid,
		})
		for i, name in names do
			local isOn = selected == i
			local button = Kit.button(name, function()
				onPick(i)
			end, {
				TextSize = 13,
				TextTruncate = Enum.TextTruncate.AtEnd,
				BackgroundColor3 = if isOn then Theme.Accent else Color3.fromRGB(72, 66, 110),
				TextColor3 = if isOn then Theme.AccentText else Theme.Text,
				LayoutOrder = i,
				ZIndex = zIndex or 1,
				Parent = grid,
			})
			if colors then
				Kit.new("Frame", {
					BackgroundColor3 = colors[i],
					BorderSizePixel = 0,
					Size = UDim2.new(0, 5, 1, -10),
					Position = UDim2.new(0, 5, 0, 5),
					ZIndex = (zIndex or 1) + 1,
					Parent = button,
				}, { Kit.corner(3) })
			end
		end
	end


	local function button(parent: Instance, label: string, order: number, onClick: () -> (), props: { [string]: any }?)
		local b = Kit.button(label, onClick, { LayoutOrder = order, Parent = parent })
		for key, v in props or {} do
			(b :: any)[key] = v
		end
		return b
	end

	local itemNames = {}
	for i, name in theme.items do
		itemNames[i] = `{ITEM_ICONS[i]} {name}`
	end

	local suspectColors = {}
	for i = 1, #theme.suspects do
		suspectColors[i] = suspectColor(i)
	end

	-- Map ---------------------------------------------------------------------------

	local function ended(): boolean
		return snapshot.view.phase == "over" or snapshot.result ~= nil or snapshot.aborted == true
	end

	local function renderMap(view: any)
		Kit.clear(map)
		local legal = {}
		if not ended() then
			for _, room in view.legalRooms do
				legal[room] = true
			end
		end
		local myRoom = if snapshot.yourSeat then view.suspectRoom[snapshot.yourSeat] else nil
		for room = 1, 9 do
			local row, col = (room - 1) // 3, (room - 1) % 3
			local isLegal = legal[room] == true
			local tile = Kit.new("TextButton", {
				Text = "",
				AutoButtonColor = isLegal,
				BackgroundColor3 = ROOM_COLORS[room],
				BorderSizePixel = 0,
				Position = UDim2.new(col / 3, 4, row / 3, 4),
				Size = UDim2.new(1 / 3, -8, 1 / 3, -8),
				Parent = map,
			}, { Kit.corner(12) })
			if view.solution and view.solution.room == room then
				Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 4, Parent = tile })
			elseif isLegal then
				Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 3, Parent = tile })
			elseif room == myRoom then
				Kit.new("UIStroke", { Color = suspectColor(snapshot.yourSeat), Thickness = 2, Transparency = 0.3, Parent = tile })
			end
			Kit.label(theme.rooms[room], {
				Font = Theme.FontBold,
				TextSize = 14,
				TextColor3 = Color3.new(1, 1, 1),
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.new(0, 8, 0, 4),
				Size = UDim2.new(1, -16, 0, 18),
				Parent = tile,
			})
			if isLegal then
				Kit.label(if room == myRoom then "Stay here" else "Walk here", {
					TextSize = 12,
					TextColor3 = Theme.Accent,
					TextXAlignment = Enum.TextXAlignment.Right,
					Position = UDim2.new(0, 8, 0, 4),
					Size = UDim2.new(1, -16, 0, 18),
					Parent = tile,
				})
			end
			local passage = Rules.passages[room]
			if passage then
				Kit.new("Frame", {
					BackgroundColor3 = Color3.fromRGB(20, 16, 28),
					BorderSizePixel = 0,
					Position = UDim2.new(0, 8, 1, -19),
					Size = UDim2.fromOffset(10, 14),
					Parent = tile,
				}, {
					Kit.new("UICorner", { CornerRadius = UDim.new(0, 3) }),
					Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 1 }),
				})
				Kit.label(`Secret passage: {theme.rooms[passage]}`, {
					TextSize = 12,
					TextColor3 = Color3.new(1, 1, 1),
					TextTransparency = 0.25,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Position = UDim2.new(0, 24, 1, -20),
					Size = UDim2.new(1, -32, 0, 16),
					Parent = tile,
				})
			end
			-- Pawns in this room.
			local pawns = Kit.new("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 8, 0, 26),
				Size = UDim2.new(1, -16, 0, 26),
				Parent = tile,
			})
			Kit.list(4, true).Parent = pawns
			for suspect, where in view.suspectRoom do
				if where == room then
					local playing = suspect <= view.seatCount
					local pawn = Kit.new("TextLabel", {
						Text = string.match(theme.suspects[suspect], "(%a)%a*$") or "?", -- "Dr. Minty" -> M
						Font = Theme.FontBold,
						TextSize = 14,
						TextColor3 = Color3.fromRGB(30, 26, 44),
						BackgroundColor3 = suspectColor(suspect),
						BackgroundTransparency = if playing then 0 else 0.5,
						Size = UDim2.fromOffset(24, 24),
						LayoutOrder = suspect,
						Parent = pawns,
					}, { Kit.corner(12) })
					if suspect == snapshot.yourSeat then
						Kit.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Parent = pawn })
					end
					-- Walked or pulled in by a suggestion since the last look: it pops in.
					if lastRooms[suspect] ~= nil and lastRooms[suspect] ~= room then
						Juice.popIn(pawn, 0.2)
					end
					if playing and view.eliminated[suspect] then
						pawn.TextTransparency = 0.6
					end
				end
			end
			-- Items in this room, each on a light chip so dark icons still read.
			local itemRow = Kit.new("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 8, 0, 56),
				Size = UDim2.new(1, -16, 0, 30),
				Parent = tile,
			})
			Kit.list(4, true).Parent = itemRow
			for item, where in view.itemRoom do
				if where == room then
					Kit.new("TextLabel", {
						Text = ITEM_ICONS[item],
						TextSize = 20,
						Font = Theme.Font,
						BackgroundColor3 = Color3.fromRGB(240, 236, 250),
						BackgroundTransparency = 0.1,
						Size = UDim2.fromOffset(30, 30),
						LayoutOrder = item,
						Parent = itemRow,
					}, { Kit.corner(8) })
				end
			end
			tile.Activated:Connect(function()
				if isLegal then
					sendMove({ kind = "move", room = room })
				end
			end)
		end
		lastRooms = table.clone(view.suspectRoom)
	end

	-- Notes and log -----------------------------------------------------------------

	local function renderNotes(view: any)
		Kit.clear(notes)
		local me = snapshot.yourSeat
		-- Who's who: cards in your hand and cards shown to you, by holder.
		local known: { [number]: number } = {}
		for _, note in view.notes do
			known[note.card] = note.by
		end
		-- Public: seats that couldn't disprove a suggestion hold none of its cards.
		local lacks: { [number]: { [number]: boolean } } = {}
		for _, pair in view.lacks or {} do
			lacks[pair.card] = lacks[pair.card] or {}
			lacks[pair.card][pair.seat] = true
		end
		local solution = {}
		if view.solution then
			solution[Rules.suspectCard(view.solution.suspect)] = true
			solution[Rules.itemCard(view.solution.item)] = true
			solution[Rules.roomCard(view.solution.room)] = true
		end
		-- Columns: every other player at the table, like the paper sheet's player columns.
		local columns = {}
		for seat = 1, view.seatCount do
			if seat ~= me then
				table.insert(columns, seat)
			end
		end
		local NAME = 0.42
		local colWidth = (1 - NAME) / math.max(1, #columns)
		local order = 0
		local function row(height: number): Frame
			order += 1
			return Kit.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -6, 0, height),
				LayoutOrder = order,
				Parent = notes,
			})
		end
		-- Header: each player's initial in their color.
		local head = row(24)
		Kit.label("Tap a box to mark it", { TextSize = 11, TextColor3 = Theme.SubText, Size = UDim2.new(NAME, -4, 1, 0), Parent = head })
		for i, seat in columns do
			local chip = Kit.new("Frame", {
				BackgroundColor3 = suspectColor(seat),
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(NAME + colWidth * (i - 0.5), 0, 0.5, 0),
				Size = UDim2.fromOffset(22, 22),
				Parent = head,
			}, { Kit.corner(11) })
			local name = nameOf(seat)
			Kit.label(string.upper(string.sub(name, 1, 1)), {
				Font = Theme.FontBold,
				TextSize = 13,
				TextColor3 = Color3.fromRGB(30, 26, 44),
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.fromScale(1, 1),
				Parent = chip,
			})
			if view.eliminated[seat] then
				chip.BackgroundTransparency = 0.6
			end
		end
		for _, section in { { "suspect", "Who" }, { "item", "With what" }, { "room", "Where" } } do
			order += 1
			text(notes, section[2], order, { Font = Theme.FontBold, TextColor3 = Theme.Accent, TextSize = 13 })
			for _, id in Rules.categoryCards[section[1]] do
				local by = known[id]
				local cleared = by ~= nil
				local cardMarks = marks[id] or {}
				for _, seat in columns do
					if cardMarks[seat] == 4 then
						cleared = true -- you ticked someone as holding it
					end
				end
				local line = row(24)
				local back = Kit.new("Frame", {
					BackgroundColor3 = if solution[id] then Theme.Accent else Theme.PanelLight,
					BackgroundTransparency = if solution[id] then 0.3 else 0.5,
					BorderSizePixel = 0,
					Size = UDim2.fromScale(1, 1),
					Parent = line,
				}, { Kit.corner(6) })
				local card = Rules.cards[id]
				local name = if card.category == "item" then `{ITEM_ICONS[card.index]} {card.name}` else card.name
				local shown = if by == me and me ~= nil then `{name} (yours)` else name
				-- Crossed off like the paper notepad once you know someone holds it.
				Kit.label(if cleared then `<s>{shown}</s>` else shown, {
					RichText = true,
					TextSize = 12,
					TextTransparency = if cleared then 0.5 else 0,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Position = UDim2.new(0, 6, 0, 0),
					Size = UDim2.new(NAME, -8, 1, 0),
					Parent = back,
				})
				for i, seat in columns do
					-- What the game knows beats your own marks: ✓ for the one who showed it
					-- to you, ✗ for everyone else then, and ✗ for anyone who passed on it.
					local auto: number? = nil
					if by ~= nil then
						auto = if by == seat then 4 else 2
					elseif lacks[id] and lacks[id][seat] then
						auto = 2
					end
					local mark = auto or cardMarks[seat] or 1
					local cell = Kit.new("TextButton", {
						Text = MARKS[mark],
						Font = Theme.FontBold,
						TextSize = if mark == 1 then 16 else 14,
						TextColor3 = MARK_COLORS[mark],
						TextTransparency = if auto then 0.35 else 0,
						AutoButtonColor = auto == nil,
						BackgroundColor3 = Theme.Panel,
						BackgroundTransparency = if auto then 0.8 else 0.4,
						BorderSizePixel = 0,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(NAME + colWidth * (i - 0.5), 0, 0.5, 0),
						Size = UDim2.new(colWidth, -4, 1, -4),
						Parent = back,
					}, { Kit.corner(4) })
					cell.Activated:Connect(function()
						if auto == nil then
							marks[id] = marks[id] or {}
							marks[id][seat] = mark % #MARKS + 1
							Audio.play("click", { volume = 0.4 })
							render()
						end
					end)
				end
			end
		end
	end

	local function renderLog(view: any)
		Kit.clear(logList)
		if #view.log == 0 and #view.accusations == 0 then
			text(logList, "No suggestions yet. Walk into a room and make one!", 1, { TextColor3 = Theme.SubText, TextSize = 14 })
			return
		end
		local count = #view.log
		for index, entry in view.log do
			local line = `{nameOf(entry.seat)}: {suggestionText(entry)}.`
			if view.phase == "show" and view.suggestion ~= nil and index == count then
				line ..= ` Waiting for {nameOf(entry.shower)} to show a card...`
			elseif entry.shower then
				if entry.card then
					line ..= if entry.shower == snapshot.yourSeat then ` You showed {cardName(entry.card)}.` else ` {nameOf(entry.shower)} showed {cardName(entry.card)}.`
				else
					line ..= ` {nameOf(entry.shower)} showed a card.`
				end
			else
				line ..= " Nobody could disprove it!"
			end
			if #entry.passed > 0 then
				local names = {}
				for _, seat in entry.passed do
					table.insert(names, nameOf(seat))
				end
				line ..= ` (No card: {table.concat(names, ", ")})`
			end
			-- Newest first.
			text(logList, line, count - index + 1, { TextSize = 13, TextColor3 = if index == count then Theme.Text else Theme.SubText })
		end
		for index, a in view.accusations do
			local isMe = a.seat == snapshot.yourSeat
			local verdict = if a.correct then "and solved it!" elseif isMe then "and were wrong. You're out." else "and was wrong. They're out."
			text(logList, `⚖ {nameOf(a.seat)} accused {theme.suspects[a.suspect]} with the {theme.items[a.item]} in the {theme.rooms[a.room]} {verdict}`, -index, {
				TextSize = 13,
				TextColor3 = if a.correct then Theme.Good else Theme.Bad,
			})
		end
	end

	-- Accusation picker ---------------------------------------------------------------

	local function renderAccuse(view: any)
		accuseOverlay.Visible = accuseOpen and view.canAccuse and not ended()
		if not accuseOverlay.Visible then
			return
		end
		fitAccuseBox()
		Kit.clear(accuseScroll)
		Kit.clear(accuseFooter)
		local z = 22
		text(accuseScroll, "Make an accusation", 1, { Font = Theme.FontBold, TextSize = 20, ZIndex = z })
		text(accuseScroll, "Right, and you win. Wrong, and you're out of the game (you still show cards).", 2, { TextSize = 13, TextColor3 = Theme.SubText, ZIndex = z })
		text(accuseScroll, "Who?", 3, { Font = Theme.FontBold, TextSize = 14, TextColor3 = Theme.Accent, ZIndex = z })
		chips(accuseScroll, 4, theme.suspects, accusePick.suspect, function(i)
			accusePick.suspect = i
			render()
		end, suspectColors, z, 3)
		text(accuseScroll, "With what?", 5, { Font = Theme.FontBold, TextSize = 14, TextColor3 = Theme.Accent, ZIndex = z })
		chips(accuseScroll, 6, itemNames, accusePick.item, function(i)
			accusePick.item = i
			render()
		end, nil, z, 3)
		text(accuseScroll, "Where?", 7, { Font = Theme.FontBold, TextSize = 14, TextColor3 = Theme.Accent, ZIndex = z })
		chips(accuseScroll, 8, theme.rooms, accusePick.room, function(i)
			accusePick.room = i
			render()
		end, nil, z, 3)
		local ready = accusePick.suspect ~= nil and accusePick.item ~= nil and accusePick.room ~= nil
		button(accuseFooter, if ready then "Accuse!" else "Pick one of each", 1, function()
			if accusePick.suspect and accusePick.item and accusePick.room then
				sendMove({ kind = "accuse", suspect = accusePick.suspect, item = accusePick.item, room = accusePick.room })
				accuseOpen = false
				render()
			end
		end, { BackgroundColor3 = if ready then Theme.Bad else Theme.Panel, TextColor3 = Theme.Text, ZIndex = z, Size = UDim2.new(0.62, -4, 1, 0) })
		button(accuseFooter, "Cancel", 2, function()
			accuseOpen = false
			render()
		end, { BackgroundColor3 = Theme.Panel, TextColor3 = Theme.SubText, ZIndex = z, Size = UDim2.new(0.38, -4, 1, 0), Position = UDim2.new(0.62, 4, 0, 0) })
	end

	-- What to do now ------------------------------------------------------------------

	local function accuseButton()
		-- Separate and red, pinned under everything else: a wrong accusation knocks you out.
		accuseBar.Visible = true
		actions.Size = UDim2.new(1, 0, 1, -46)
		button(accuseBar, "⚖ Accuse...", 1, function()
			accuseOpen = true
			render()
		end, { BackgroundColor3 = Theme.Bad, TextColor3 = Theme.Text, Size = UDim2.fromScale(1, 1) })
	end

	local function categoryOf(id: number): string
		local card = Rules.cards[id]
		return if card.category == "item" then "Item" elseif card.category == "room" then "Room" else "Suspect"
	end

	-- A playing-card sized tile: category on top, name in the middle.
	local function bigCard(parent: Instance, id: number, order: number, width: number, z: number?): TextButton
		local card = Rules.cards[id]
		local tile = Kit.new("TextButton", {
			Text = "",
			AutoButtonColor = true,
			BackgroundColor3 = Color3.fromRGB(252, 246, 230),
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(width, math.floor(width * 1.4)),
			LayoutOrder = order,
			ZIndex = z or 1,
			Parent = parent,
		}, { Kit.corner(10), Kit.new("UIStroke", { Color = Color3.fromRGB(255, 214, 120), Thickness = 3 }) })
		Kit.label(categoryOf(id), {
			TextSize = 12,
			TextColor3 = Color3.fromRGB(110, 96, 80),
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 4, 0, 6),
			Size = UDim2.new(1, -8, 0, 16),
			ZIndex = (z or 1) + 1,
			Parent = tile,
		})
		local icon = if card.category == "item" then ITEM_ICONS[card.index] elseif card.category == "suspect" then "🕵" else "🚪"
		Kit.label(icon, {
			TextSize = math.floor(width * 0.3),
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 0, 0.18, 0),
			Size = UDim2.new(1, 0, 0.32, 0),
			ZIndex = (z or 1) + 1,
			Parent = tile,
		})
		Kit.label(card.name, {
			Font = Theme.FontBold,
			TextSize = math.clamp(math.floor(width * 0.14), 12, 20),
			TextColor3 = if card.category == "suspect" then HudKit.shade(suspectColor(card.index), 0.45) else Color3.fromRGB(40, 30, 24),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = true,
			Position = UDim2.new(0, 6, 0.54, 0),
			Size = UDim2.new(1, -12, 0.4, 0),
			ZIndex = (z or 1) + 1,
			Parent = tile,
		})
		return tile
	end

	-- The show-a-card pop-up (built once per suggestion so it doesn't flicker).
	local function renderShow(view: any)
		local want = view.phase == "show" and #view.showOptions > 0 and not ended()
		if not want then
			showOverlay.Visible = false
			showKey = nil
			return
		end
		local key = `{view.logCount}`
		showOverlay.Visible = true
		if showKey == key then
			return
		end
		showKey = key
		Kit.clear(showOverlay)
		local entry = view.suggestion
		local box = Kit.panel({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(if docked then 0.78 else 0.5, 0.5),
			Size = UDim2.fromOffset(math.max(320, #view.showOptions * 150 + 40), 330),
			BackgroundColor3 = Theme.PanelLight,
			ZIndex = 31,
			Parent = showOverlay,
		})
		Kit.label(`Show {nameOf(entry.seat)} a card`, { Font = Theme.FontTitle, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 28), ZIndex = 32, Parent = box })
		Kit.label(`They suggested {suggestionText(entry)}. Only they will see the card you pick.`, {
			TextSize = 13,
			TextColor3 = Theme.SubText,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 30),
			Size = UDim2.new(1, 0, 0, 34),
			ZIndex = 32,
			Parent = box,
		})
		local row = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 74), Size = UDim2.new(1, 0, 1, -74), ZIndex = 32, Parent = box })
		local list = Kit.list(14, true)
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.Parent = row
		for i, id in view.showOptions do
			local tile = bigCard(row, id, i, 130, 33)
			tile.Activated:Connect(function()
				Audio.play("card")
				showOverlay.Visible = false
				sendMove({ kind = "show", card = id })
			end)
		end
		Juice.popIn(box)
		Juice.stagger(row, 0.08)
		Audio.play("pop")
	end

	-- The go-round after a suggestion: each seat clockwise lights up in turn with "no
	-- card", until someone shows one (face down, unless it's to you).
	local STEP = 0.55
	local roundShown = 0
	local function goRound(view: any, entry: any, order: number): number
		local me = snapshot.yourSeat
		local key = view.logCount
		if roundKey ~= key then
			roundKey = key
			roundStart = os.clock()
			roundShown = 0
		end
		local seq = {}
		for _, seat in entry.passed do
			table.insert(seq, { seat = seat, text = "No card", color = Theme.Bad, sound = "knock" })
		end
		if entry.shower then
			local says = if view.phase == "show" then "Choosing..."
				elseif entry.card and entry.seat == me then `Shows you {cardName(entry.card)}`
				elseif entry.card and entry.shower == me then `You showed {cardName(entry.card)}`
				else "🂠 Shows a card"
			table.insert(seq, { seat = entry.shower, text = says, color = Theme.Good, sound = if view.phase == "show" then nil else "card" })
		end
		local strip = Kit.new("Frame", {
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			LayoutOrder = order,
			Parent = actions,
		})
		Kit.list(4).Parent = strip
		local visible = math.min(#seq, math.floor((os.clock() - roundStart) / STEP) + 1)
		for i = 1, visible do
			local step = seq[i]
			local chip = Kit.new("Frame", {
				BackgroundColor3 = Theme.PanelLight,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 26),
				LayoutOrder = i,
				Parent = strip,
			}, { Kit.corner(8) })
			Kit.new("Frame", { BackgroundColor3 = suspectColor(step.seat), BorderSizePixel = 0, Size = UDim2.new(0, 6, 1, 0), Parent = chip }, { Kit.corner(3) })
			Kit.label(nameOf(step.seat), { Font = Theme.FontBold, TextSize = 13, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.45, -12, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = chip })
			Kit.label(step.text, { TextSize = 13, TextColor3 = step.color, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.new(0.45, 0, 0, 0), Size = UDim2.new(0.55, -8, 1, 0), Parent = chip })
			if i > roundShown then
				Juice.popIn(chip, 0.5)
				if step.sound then
					Audio.play(step.sound, { volume = 0.6 })
				end
			end
		end
		roundShown = math.max(roundShown, visible)
		if visible < #seq then
			task.delay(roundStart + visible * STEP - os.clock() + 0.02, function()
				if roundKey == key then
					render()
				end
			end)
		end
		-- Seconds until the go-round has finished.
		return math.max(0, roundStart + #seq * STEP - os.clock())
	end

	local function renderActions(view: any)
		Kit.clear(actions)
		Kit.clear(accuseBar)
		accuseBar.Visible = false
		actions.Size = UDim2.fromScale(1, 1)
		local me = snapshot.yourSeat
		-- The panel's ring shows whose move it is (gold when it's yours).
		local acting = if ended() then nil else snapshot.activeSeats[1]
		HudKit.turnTint(actionPanel, acting, acting ~= nil and acting == me)
		local myTurn = me ~= nil and view.turn == me and view.phase ~= "show" and not ended()
		local entry = view.suggestion
		local turnName = nameOf(view.turn)

		text(actions, view.mystery, 1, { Font = Theme.FontBold, TextSize = 13, TextColor3 = Theme.SubText })
		if me and view.seatCount >= me then
			text(actions, `You are {theme.suspects[me]}{if view.eliminated[me] then " (out: you still show cards)" else ""}`, 2, {
				TextSize = 13,
				TextColor3 = suspectColor(me),
			})
		end

		if view.phase == "over" then
			local sol = view.solution
			text(actions, "The case file:", 3, { Font = Theme.FontBold, TextSize = 16 })
			-- The three cards come out of the envelope one at a time.
			local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 120), LayoutOrder = 4, Parent = actions })
			local list = Kit.list(8, true)
			list.HorizontalAlignment = Enum.HorizontalAlignment.Center
			list.Parent = row
			for i, id in { Rules.suspectCard(sol.suspect), Rules.itemCard(sol.item), Rules.roomCard(sol.room) } do
				bigCard(row, id, i, 84).AutoButtonColor = false
			end
			if endShownFor ~= snapshot.matchId then
				endShownFor = snapshot.matchId
				Juice.stagger(row, 0.6)
				for i = 0, 2 do
					task.delay(i * 0.6, function()
						Audio.play("flip")
					end)
				end
			end
			text(actions, `{theme.suspects[sol.suspect]} with the {theme.items[sol.item]} in the {theme.rooms[sol.room]}`, 5, {
				Font = Theme.FontBold,
				TextSize = 16,
				TextColor3 = Theme.Accent,
			})
			return
		end
		if ended() then
			-- Ended early (everyone left, or the host ended it): nothing left to do here.
			text(actions, "This game has ended.", 3, { Font = Theme.FontBold, TextSize = 16, TextColor3 = Theme.SubText })
			return
		end

		-- What just happened.
		local last = view.lastAction
		if last and last.kind == "accuse" and not last.correct then
			text(actions, `{nameOf(last.seat)} accused wrongly and is out!`, 3, { TextColor3 = Theme.Bad, TextSize = 15 })
		end

		if view.phase == "show" then
			local asker = nameOf(entry.seat)
			text(actions, `{asker} suggested {suggestionText(entry)}.`, 4, { TextSize = 15 })
			goRound(view, entry, 5)
			if #view.showOptions > 0 then
				text(actions, `Pick a card to show {asker}. Only they will see it.`, 6, { Font = Theme.FontBold, TextSize = 15, TextColor3 = Theme.Accent })
				for i, id in view.showOptions do
					button(actions, `Show {cardName(id)}`, 6 + i, function()
						sendMove({ kind = "show", card = id })
					end)
				end
			end
			return
		end

		if view.phase == "after" and entry then
			local asker = nameOf(entry.seat)
			text(actions, `{asker} suggested {suggestionText(entry)}.`, 4, { TextSize = 15 })
			local wait = goRound(view, entry, 5)
			-- The card slid across to you, turned face up in the middle of the screen once
			-- the go-round reaches the one who showed it.
			if entry.card and entry.seat == me then
				local key = `{entry.suspect}|{entry.item}|{entry.room}|{entry.shower}|{entry.card}|{view.logCount}`
				if revealed ~= entry and not revealedKeys[key] then
					revealedKeys[key] = true
					local id, shower = entry.card, entry.shower
					task.delay(math.max(0, wait - STEP * 0.5), function()
						if root.Parent then
							HudKit.revealCard(root, `{nameOf(shower)} showed you`, cardName(id), `{categoryOf(id)} · not in the case file`)
						end
					end)
				end
				revealed = entry
			end
			if entry.shower == nil then
				text(actions, "Nobody could disprove it!", 6, { Font = Theme.FontBold, TextSize = 17, TextColor3 = Theme.Accent })
				if roundShown >= #entry.passed and not revealedKeys[`none|{view.logCount}`] then
					revealedKeys[`none|{view.logCount}`] = true
					task.delay(wait, function()
						if root.Parent then
							HudKit.callout(root, "Nobody could disprove it!", Theme.Accent)
						end
					end)
				end
			end
			if myTurn then
				button(actions, "End turn", 10, function()
					sendMove({ kind = "end" })
				end)
				if view.canAccuse then
					accuseButton()
				end
			end
			return
		end

		if view.phase == "move" then
			if myTurn then
				if docked then
					-- Table view: tap a room on the table, or use a button per room you can reach.
					text(actions, "Your turn! Tap a room on the table, or pick one here.", 4, { Font = Theme.FontBold, TextSize = 16, TextColor3 = Theme.Accent })
					for i, room in view.legalRooms do
						button(actions, theme.rooms[room], 20 + i, function()
							sendMove({ kind = "move", room = room })
						end, { Size = UDim2.new(1, 0, 0, 34), TextSize = 15 })
					end
				else
					text(actions, "Your turn! Tap a glowing room to walk there.", 4, { Font = Theme.FontBold, TextSize = 16, TextColor3 = Theme.Accent })
				end
				if view.canStay then
					text(actions, "You were brought here, so you may stay.", 5, { TextSize = 13, TextColor3 = Theme.SubText })
				end
				if view.canAccuse then
					text(actions, "Sure you know? You can accuse now instead.", 6, { TextSize = 13, TextColor3 = Theme.SubText })
					accuseButton()
				end
			else
				text(actions, `{turnName} {if turnName == "You" then "are" else "is"} walking the halls...`, 4, { TextSize = 15, TextColor3 = Theme.SubText })
			end
			return
		end

		-- Suggest.
		local here = theme.rooms[view.suspectRoom[view.turn]]
		if not myTurn then
			text(actions, `{turnName} is in the {here}, thinking about a suggestion...`, 4, { TextSize = 15, TextColor3 = Theme.SubText })
			return
		end
		text(actions, `You're in the {here}. Who did it, and with what?`, 4, { Font = Theme.FontBold, TextSize = 16, TextColor3 = Theme.Accent })
		chips(actions, 5, theme.suspects, pickSuspect, function(i)
			pickSuspect = i
			render()
		end, suspectColors)
		chips(actions, 6, itemNames, pickItem, function(i)
			pickItem = i
			render()
		end)
		local ready = pickSuspect ~= nil and pickItem ~= nil
		button(actions, if ready then "Suggest" else "Pick a suspect and an item", 7, function()
			if pickSuspect and pickItem then
				sendMove({ kind = "suggest", suspect = pickSuspect, item = pickItem })
				pickSuspect, pickItem = nil, nil
			end
		end, { BackgroundColor3 = if ready then Theme.Accent else Theme.Panel, TextColor3 = if ready then Theme.AccentText else Theme.SubText })
		if view.canAccuse then
			accuseButton()
		end
	end

	render = function()
		if not snapshot then
			return
		end
		local view = snapshot.view
		renderMap(view)
		renderActions(view)
		renderNotes(view)
		renderLog(view)
		renderAccuse(view)
		renderShow(view)
	end

	-- An accusation: the case file envelope in the middle of the screen. Its flap opens,
	-- the three accused cards slide out and turn over one by one, then the verdict is
	-- stamped across them. Everyone at the table watches it. Tap to close.
	local function openCaseFile(accusation: any)
		local old = root:FindFirstChild("CaseFile")
		if old then
			old:Destroy()
		end
		local MANILA = Color3.fromRGB(214, 180, 120)
		local holder = Kit.new("TextButton", {
			Name = "CaseFile",
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 60,
			Parent = root,
		})
		holder.Activated:Connect(function()
			holder:Destroy()
		end)
		local stage = Kit.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(420, 320),
			ZIndex = 61,
			Parent = holder,
		})
		Kit.new("UIScale", { Scale = math.clamp((root.AbsoluteSize.X - 20) / 420, 0.5, 1), Parent = stage })
		Kit.label(`{nameOf(accusation.seat)} opens the case file...`, {
			TextSize = 18,
			Font = Theme.FontBold,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 24),
			ZIndex = 62,
			Parent = stage,
		})
		local envelope = Kit.new("Frame", {
			BackgroundColor3 = MANILA,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.fromOffset(340, 140),
			ZIndex = 66,
			Parent = stage,
		}, { Kit.corner(8), Kit.new("UIStroke", { Color = Color3.fromRGB(120, 90, 50), Thickness = 2 }) })
		Kit.label("CASE FILE · CONFIDENTIAL", {
			TextSize = 18,
			Font = Theme.FontBold,
			TextColor3 = Color3.fromRGB(150, 40, 40),
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromScale(0, 0.45),
			Size = UDim2.new(1, 0, 0, 30),
			Rotation = -5,
			ZIndex = 67,
			Parent = envelope,
		})
		-- The flap: a darker strip along the top that folds up and away.
		local flap = Kit.new("Frame", {
			BackgroundColor3 = MANILA:Lerp(Color3.new(0, 0, 0), 0.18),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 0),
			Size = UDim2.new(1, 0, 0, 46),
			ZIndex = 68,
			Parent = envelope,
		}, { Kit.corner(8) })
		local names = {
			cardName(Rules.suspectCard(accusation.suspect)),
			cardName(Rules.itemCard(accusation.item)),
			cardName(Rules.roomCard(accusation.room)),
		}
		local cards = {}
		for i, name in names do
			local card = Kit.new("Frame", {
				BackgroundColor3 = Color3.fromRGB(70, 48, 96),
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5 + (i - 2) * 0.29, 0, 1, -30),
				Size = UDim2.fromOffset(112, 150),
				ZIndex = 64,
				Parent = stage,
			}, { Kit.corner(10), Kit.new("UIStroke", { Color = Color3.fromRGB(255, 214, 120), Thickness = 2 }) })
			local label = Kit.label("?", {
				TextSize = 40,
				Font = Theme.FontBold,
				TextColor3 = Color3.fromRGB(255, 214, 120),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextWrapped = true,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 65,
				Parent = card,
			})
			cards[i] = { frame = card, label = label, name = name }
		end
		local quick = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.spawn(function()
			task.wait(0.4)
			TweenService:Create(flap, quick, { Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1 }):Play()
			Audio.play("flip")
			task.wait(0.35)
			for _, c in cards do
				if not holder.Parent then
					return
				end
				-- Up out of the envelope...
				TweenService:Create(c.frame, quick, { Position = c.frame.Position - UDim2.fromOffset(0, 120) }):Play()
				task.wait(0.25)
			end
			task.wait(0.3)
			for _, c in cards do
				if not holder.Parent then
					return
				end
				-- ...and over, one at a time.
				local half = TweenService:Create(c.frame, TweenInfo.new(0.12), { Size = UDim2.fromOffset(0, 150) })
				half:Play()
				half.Completed:Wait()
				c.frame.BackgroundColor3 = Color3.fromRGB(252, 246, 230)
				c.label.Text = c.name
				c.label.TextSize = 17
				c.label.TextColor3 = Color3.fromRGB(40, 30, 24)
				Audio.play("flip")
				TweenService:Create(c.frame, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(112, 150) }):Play()
				task.wait(0.45)
			end
			if not holder.Parent then
				return
			end
			local stamp = Kit.label(if accusation.correct then "SOLVED!" else "WRONG!", {
				TextSize = 54,
				Font = Theme.FontBold,
				TextColor3 = if accusation.correct then Theme.Good else Theme.Bad,
				TextStrokeTransparency = 0.2,
				TextXAlignment = Enum.TextXAlignment.Center,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.42),
				Size = UDim2.new(1, 0, 0, 70),
				Rotation = -12,
				ZIndex = 70,
				Parent = stage,
			})
			local pop = Kit.new("UIScale", { Scale = 2.2, Parent = stamp })
			TweenService:Create(pop, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			Audio.play(if accusation.correct then "win" else "caught")
			task.wait(2.6)
			if holder.Parent then
				holder:Destroy()
			end
		end)
	end

	return {
		tableHeight = function(): number
			return 230
		end,
		setTableMode = function(value: boolean)
			if value == tableMode then
				return
			end
			tableMode = value
			map.Visible = not value
			bottom.Visible = not value
			notesButton.Visible = value
			prompt.setVisible(value)
			if value then
				side.AnchorPoint = Vector2.new(0.5, 1)
				side.Position = UDim2.new(0.5, 0, 1, -4)
				side.Size = UDim2.new(0.9, 0, 0, 180)
				actionPanel.Size = UDim2.fromScale(1, 1)
				sideSize.Parent = side
			else
				side.AnchorPoint = Vector2.zero
				side.Position = UDim2.new(0.56, 12, 0, 0)
				side.Size = UDim2.new(0.44, -12, 1, 0)
				actionPanel.Size = UDim2.new(1, 0, 0.5, -6)
				sideSize.Parent = nil
			end
			if snapshot then
				render()
			end
		end,
		-- Rooms you can walk to glow on the table.
		canTap = function(id: any): boolean
			return snapshot ~= nil and not ended() and type(id) == "number" and table.find(snapshot.view.legalRooms or {}, id) ~= nil
		end,
		tableMarks = function(): { [any]: any }?
			if not (tableMode and snapshot) or ended() then
				return nil
			end
			local marks = {}
			for _, room in snapshot.view.legalRooms or {} do
				marks[room] = "target"
			end
			return marks
		end,
		setDocked = function(value: boolean)
			if docked ~= value then
				docked = value
				if snapshot then
					render()
				end
			end
		end,
		update = function(newSnapshot: any)
			if newSnapshot.matchId ~= lastMatchId then
				lastMatchId = newSnapshot.matchId
				marks = {}
				pickSuspect, pickItem = nil, nil
				accuseOpen = false
				accusePick = { suspect = nil, item = nil, room = nil }
				lastRooms = {}
				roundKey = nil
				showKey = nil
			end
			snapshot = newSnapshot
			local accusations = snapshot.view.accusations or {}
			if shownAccusations ~= nil and #accusations > shownAccusations then
				openCaseFile(accusations[#accusations])
			end
			shownAccusations = #accusations
			if snapshot.view.phase == "over" and bottomTab ~= "notes" then
				selectTab("notes")
			end
			render()
		end,
		-- A room tapped on the 3D table (Table view): walk there if you can.
		tapTable = function(id: any)
			if not snapshot or ended() or type(id) ~= "number" then
				return
			end
			if table.find(snapshot.view.legalRooms, id) then
				Audio.play("click")
				sendMove({ kind = "move", room = id })
			end
		end,
		destroy = function()
			root:Destroy()
		end,
	}
end

return Whodunit
