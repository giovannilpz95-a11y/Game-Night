-- Whodunit table: the mansion map on the left (3x3 rooms with pawns and items; rooms you
-- can walk to glow, tap one to move), and on the right what to do now (suggest, show a
-- card, end turn, accuse) above your detective notes and the case log.
-- The notes fill themselves with your cards and every card shown to you; tap a row's
-- mark to note your own guesses (✗ ? ✓). Marks live only on this client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Games.Whodunit)
local Kit = require(script.Parent.Parent.UI.Kit)
local HudKit = require(script.Parent.Parent.UI.HudKit)
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
	local marks: { [number]: number } = {} -- card id -> index into MARKS
	local pickSuspect: number? = nil
	local pickItem: number? = nil
	local accuseOpen = false
	local accusePick = { suspect = nil :: number?, item = nil :: number?, room = nil :: number? }
	local bottomTab = "notes"
	local lastMatchId: string? = nil

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })

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
		accuseBox.Size = UDim2.new(0.94, 0, 0, math.min(wanted, room))
	end
	accuseList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitAccuseBox)
	accuseOverlay:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitAccuseBox)
	Kit.new("UIPadding", { PaddingRight = UDim.new(0, 12), Parent = accuseScroll }) -- room for the scrollbar

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

	local docked = false -- Table view: only the side panel shows

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

	local function renderMap(view: any)
		Kit.clear(map)
		local legal = {}
		for _, room in view.legalRooms do
			legal[room] = true
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
	end

	-- Notes and log -----------------------------------------------------------------

	local function renderNotes(view: any)
		Kit.clear(notes)
		local known = {}
		for _, note in view.notes do
			known[note.card] = note.by
		end
		local solution = {}
		if view.solution then
			solution[Rules.suspectCard(view.solution.suspect)] = true
			solution[Rules.itemCard(view.solution.item)] = true
			solution[Rules.roomCard(view.solution.room)] = true
		end
		-- Two columns per section so all 21 cards fit; tap anywhere on a row to mark it.
		local order = 0
		for _, section in { { "suspect", "Who" }, { "item", "With what" }, { "room", "Where" } } do
			order += 1
			text(notes, section[2], order, { Font = Theme.FontBold, TextColor3 = Theme.Accent, TextSize = 13 })
			order += 1
			local grid = Kit.new("Frame", {
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, -6, 0, 0),
				LayoutOrder = order,
				Parent = notes,
			})
			Kit.new("UIGridLayout", {
				CellSize = UDim2.new(0.5, -3, 0, 27),
				CellPadding = UDim2.fromOffset(6, 3),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = grid,
			})
			for index, id in Rules.categoryCards[section[1]] do
				local by = known[id]
				local mark = marks[id] or 1
				local row = Kit.new("TextButton", {
					Text = "",
					AutoButtonColor = by == nil,
					BackgroundColor3 = if solution[id] then Theme.Accent else Theme.PanelLight,
					BackgroundTransparency = if solution[id] then 0.3 else 0.35,
					BorderSizePixel = 0,
					LayoutOrder = index,
					Parent = grid,
				}, { Kit.corner(6) })
				local card = Rules.cards[id]
				local name = if card.category == "item" then `{ITEM_ICONS[card.index]} {card.name}` else card.name
				Kit.label(name, {
					TextSize = 13,
					TextTransparency = if by then 0.55 else 0,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Position = UDim2.new(0, 6, 0, 0),
					Size = UDim2.new(1, -60, 1, 0),
					Parent = row,
				})
				Kit.label(if by == snapshot.yourSeat then "Yours" elseif by then nameOf(by) else MARKS[mark], {
					TextSize = if by then 11 else 16,
					Font = Theme.FontBold,
					TextColor3 = if by then Theme.Bad else MARK_COLORS[mark],
					TextXAlignment = Enum.TextXAlignment.Right,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Position = UDim2.new(1, -56, 0, 0),
					Size = UDim2.new(0, 50, 1, 0),
					Parent = row,
				})
				row.Activated:Connect(function()
					if by == nil then
						marks[id] = mark % #MARKS + 1
						render()
					end
				end)
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
		accuseOverlay.Visible = accuseOpen and view.canAccuse
		if not accuseOverlay.Visible then
			return
		end
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

	local function accuseButton(order: number)
		button(actions, "Accuse...", order, function()
			accuseOpen = true
			render()
		end, { BackgroundColor3 = Theme.Bad, TextColor3 = Theme.Text })
	end

	local function renderActions(view: any)
		Kit.clear(actions)
		local me = snapshot.yourSeat
		-- The panel's ring shows whose move it is (gold when it's yours).
		local acting = if view.phase == "over" then nil else snapshot.activeSeats[1]
		HudKit.turnTint(actionPanel, acting, acting ~= nil and acting == me)
		local myTurn = me ~= nil and view.turn == me and view.phase ~= "show" and view.phase ~= "over"
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
			text(actions, `{theme.suspects[sol.suspect]} with the {theme.items[sol.item]} in the {theme.rooms[sol.room]}`, 4, {
				Font = Theme.FontBold,
				TextSize = 18,
				TextColor3 = Theme.Accent,
			})
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
			if #view.showOptions > 0 then
				text(actions, `Show {asker} one card in secret. Only they will see it.`, 5, { Font = Theme.FontBold, TextSize = 15, TextColor3 = Theme.Accent })
				for i, id in view.showOptions do
					button(actions, `Show {cardName(id)}`, 5 + i, function()
						sendMove({ kind = "show", card = id })
					end)
				end
			else
				text(actions, `Waiting for {nameOf(entry.shower)} to show a card...`, 5, { TextColor3 = Theme.SubText, TextSize = 15 })
			end
			return
		end

		if view.phase == "after" and entry then
			local asker = nameOf(entry.seat)
			text(actions, `{asker} suggested {suggestionText(entry)}.`, 4, { TextSize = 15 })
			if entry.shower == nil then
				text(actions, "Nobody could disprove it!", 5, { Font = Theme.FontBold, TextSize = 17, TextColor3 = Theme.Accent })
			elseif entry.card and entry.seat == me then
				text(actions, `{nameOf(entry.shower)} showed you:`, 5, { TextSize = 15 })
				text(actions, cardName(entry.card), 6, { Font = Theme.FontBold, TextSize = 22, TextColor3 = Theme.Accent })
			elseif entry.card and entry.shower == me then
				text(actions, `You showed {cardName(entry.card)}.`, 5, { TextSize = 15, TextColor3 = Theme.SubText })
			else
				text(actions, `{nameOf(entry.shower)} showed {asker == "You" and "you" or asker} a card.`, 5, { TextSize = 15, TextColor3 = Theme.SubText })
			end
			if myTurn then
				button(actions, "End turn", 10, function()
					sendMove({ kind = "end" })
				end)
				if view.canAccuse then
					accuseButton(11)
				end
			end
			return
		end

		if view.phase == "move" then
			if myTurn then
				if docked then
					-- Table view hides the map: walk with a button per room you can reach.
					text(actions, "Your turn! Pick a room to walk to.", 4, { Font = Theme.FontBold, TextSize = 16, TextColor3 = Theme.Accent })
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
					accuseButton(7)
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
			accuseButton(8)
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
	end

	return {
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
			end
			snapshot = newSnapshot
			if snapshot.view.phase == "over" and bottomTab ~= "notes" then
				selectTab("notes")
			end
			render()
		end,
		destroy = function()
			root:Destroy()
		end,
	}
end

return Whodunit
