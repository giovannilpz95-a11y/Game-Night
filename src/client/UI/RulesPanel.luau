-- The rules page for any game (shared/GameRules), and the how-to-play card shown when a
-- match starts.
--
-- * open(gameId): the full rules for one game. Used by the ? in the match header and the
--   ? on each game in the picker. It's a window over the table, so the match keeps going
--   behind it.
-- * openHelp(): every game in a list, each opening its rules, plus "Replay the lobby tour".
-- * showCard(gameId, hidden, onHide): the short card for a new match: the goal and 2-4
--   lines, Full rules, Got it, and a "Don't show again for this game" toggle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local GameRules = require(ReplicatedStorage.Shared.GameRules)
local HouseRules = require(ReplicatedStorage.Shared.HouseRules)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)
local Theme = Kit.Theme

local RulesPanel = {}

local Z = 70 -- above the match screen and its end card

local function players(entry: GameCatalog.Entry): string
	return if entry.minSeats == entry.maxSeats then `{entry.maxSeats} players` else `{entry.minSeats}-{entry.maxSeats} players`
end

-- hooks: replayTour()
function RulesPanel.create(screen: Instance, hooks: { replayTour: () -> () })
	---------------------------------------------------------------- rules window
	local window = Kit.modal(screen, { name = "RulesWindow", maxSize = Vector2.new(560, 640), zIndex = Z })
	window.overlay.BackgroundTransparency = 0.7 -- lighter: the game is still on behind it
	local body = window.body

	local title = Kit.label("", { Font = Theme.FontBold, TextSize = 22, Size = UDim2.new(1, -96, 0, 28), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = Z + 1, Parent = body })
	local subtitle = Kit.label("", { TextSize = 13, TextColor3 = Theme.SubText, Position = UDim2.new(0, 0, 0, 28), Size = UDim2.new(1, -48, 0, 18), ZIndex = Z + 1, Parent = body })
	local backButton: TextButton
	local list = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 52),
		Size = UDim2.new(1, 0, 1, -52),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ZIndex = Z + 1,
		Parent = body,
	}, { Kit.list(8), Kit.new("UIPadding", { PaddingRight = UDim.new(0, 8) }) })

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local function text(value: string, props: { [string]: any }?): TextLabel
		local label = Kit.label(value, {
			TextSize = 15,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			TextYAlignment = Enum.TextYAlignment.Top,
			LayoutOrder = nextOrder(),
			ZIndex = Z + 2,
			Parent = list,
		})
		for key, v in props or {} do
			(label :: any)[key] = v
		end
		return label
	end

	local showHelp: () -> ()
	local fromHelp = false

	local function showRules(gameId: string)
		Kit.clear(list)
		list.CanvasPosition = Vector2.zero
		order = 0
		local entry = GameCatalog.get(gameId)
		local info = GameRules.get(gameId)
		title.Text = if entry then `How to play {entry.name}` else "How to play"
		subtitle.Text = if entry then `{players(entry)} · {entry.category}` else ""
		backButton.Visible = fromHelp
		title.Position = UDim2.new(0, if fromHelp then 44 else 0, 0, 0)
		if not info then
			text("Rules for this game are on the way.")
			return
		end
		local goal = Kit.new("Frame", {
			BackgroundColor3 = Theme.Accent,
			BorderSizePixel = 0,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			LayoutOrder = nextOrder(),
			ZIndex = Z + 2,
			Parent = list,
		}, { Kit.corner(10), Kit.padding(10) })
		Kit.label(`Goal: {info.goal}`, {
			Font = Theme.FontBold,
			TextSize = 16,
			TextColor3 = Theme.AccentText,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			ZIndex = Z + 3,
			Parent = goal,
		})
		for _, section in info.sections do
			text(section.title, { Font = Theme.FontBold, TextSize = 17, TextColor3 = Theme.Accent })
			for _, line in section.lines do
				text(`•  {line}`, { TextColor3 = Theme.Text })
			end
		end
		local houseRules = if entry then HouseRules.list(entry) else {}
		if #houseRules > 0 then
			text("House rules (Party Host)", { Font = Theme.FontBold, TextSize = 17, TextColor3 = Theme.Accent })
			for _, rule in houseRules do
				local hint = if rule.hint then `: {rule.hint}` else ""
				text(`•  {rule.name}{hint}`, { TextColor3 = Theme.SubText, TextSize = 14 })
			end
		end
	end

	backButton = Kit.button("◂", function()
		showHelp()
	end, {
		Size = UDim2.fromOffset(36, 28),
		BackgroundColor3 = Theme.PanelLight,
		TextColor3 = Theme.Text,
		Visible = false,
		ZIndex = Z + 2,
		Parent = body,
	})

	function showHelp()
		fromHelp = true
		Kit.clear(list)
		list.CanvasPosition = Vector2.zero
		order = 0
		backButton.Visible = false
		title.Position = UDim2.new(0, 0, 0, 0)
		title.Text = "Help"
		subtitle.Text = "Tap a game to see how it's played."
		Kit.button("Replay the lobby tour", function()
			window.close()
			hooks.replayTour()
		end, { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = nextOrder(), ZIndex = Z + 2, Parent = list })
		text("In a match, tap ? at the top to see that game's rules any time. The game keeps going while you read.", { TextColor3 = Theme.SubText, TextSize = 13 })
		for _, entry in GameCatalog.entries do
			if entry.status == "ready" then
				local row = Kit.button("", function()
					showRules(entry.id)
				end, {
					BackgroundColor3 = Theme.PanelLight,
					Size = UDim2.new(1, 0, 0, 48),
					LayoutOrder = nextOrder(),
					ZIndex = Z + 2,
					Parent = list,
				})
				Kit.label(entry.name, { Font = Theme.FontBold, TextSize = 16, Position = UDim2.new(0, 12, 0, 4), Size = UDim2.new(1, -40, 0, 22), ZIndex = Z + 3, Parent = row })
				local info = GameRules.get(entry.id)
				Kit.label(if info then info.goal else entry.description, {
					TextSize = 12,
					TextColor3 = Theme.SubText,
					Position = UDim2.new(0, 12, 0, 24),
					Size = UDim2.new(1, -40, 0, 18),
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextWrapped = false,
					ZIndex = Z + 3,
					Parent = row,
				})
				Kit.label("▸", { TextSize = 18, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(20, 22), ZIndex = Z + 3, Parent = row })
			end
		end
	end

	---------------------------------------------------------------- how-to-play card
	local card = Kit.panel({
		Name = "HowToPlay",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Panel,
		Visible = false,
		ZIndex = Z - 10,
		Parent = screen,
	})
	Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 2, Parent = card })
	Kit.list(6).Parent = card
	local cardTitle = Kit.label("", { Font = Theme.FontBold, TextSize = 20, LayoutOrder = 1, ZIndex = Z - 9, Parent = card })
	local cardGoal = Kit.label("", { Font = Theme.FontBold, TextSize = 15, TextColor3 = Theme.Accent, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2, ZIndex = Z - 9, Parent = card })
	local cardLines = Kit.new("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 3, ZIndex = Z - 9, Parent = card }, { Kit.list(4) })
	local hideRow = Kit.new("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 4,
		ZIndex = Z - 9,
		Parent = card,
	})
	local hideBox = Kit.label("", {
		BackgroundColor3 = Theme.PanelLight,
		BackgroundTransparency = 0,
		Font = Theme.FontBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.fromOffset(22, 22),
		ZIndex = Z - 8,
		Parent = hideRow,
	}, nil)
	Kit.corner(6).Parent = hideBox
	Kit.label("Don't show this card for this game", { TextSize = 13, TextColor3 = Theme.SubText, Position = UDim2.fromOffset(30, 4), Size = UDim2.new(1, -30, 0, 22), ZIndex = Z - 8, Parent = hideRow })
	local cardButtons = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 5, ZIndex = Z - 9, Parent = card })
	local cardGameId: string? = nil
	local cardHidden = false
	local onHide: ((boolean) -> ())? = nil

	local function closeCard()
		card.Visible = false
		cardGameId = nil
	end
	Kit.button("Full rules", function()
		local id = cardGameId
		closeCard()
		if id then
			fromHelp = false
			showRules(id)
			window.open()
		end
	end, { BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, Size = UDim2.new(0.45, -4, 1, 0), ZIndex = Z - 8, Parent = cardButtons })
	Kit.button("Got it", closeCard, { BackgroundColor3 = Theme.Good, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.55, -4, 1, 0), TextSize = 18, ZIndex = Z - 8, Parent = cardButtons })
	local function renderHide()
		hideBox.Text = if cardHidden then "✓" else ""
	end
	hideRow.Activated:Connect(function()
		cardHidden = not cardHidden
		renderHide()
		if onHide then
			onHide(cardHidden)
		end
	end)

	Layout.onChange(function(info)
		window.fit(info.top, info.bottom)
		local w = math.min(400, info.width - 32)
		card.Size = UDim2.fromOffset(w, 0)
		-- Centered under the top bar.
		card.Position = UDim2.fromOffset(info.width / 2, info.top + (info.height - info.top - info.bottom) / 2)
		cardTitle.TextSize = if info.compact then 18 else 20
	end)

	return {
		open = function(gameId: string)
			fromHelp = false
			showRules(gameId)
			window.open()
		end,
		openHelp = function()
			showHelp()
			window.open()
		end,
		close = function()
			window.close()
			closeCard()
		end,
		isOpen = function(): boolean
			return window.isOpen()
		end,
		showCard = function(gameId: string, hidden: boolean, hideChanged: (boolean) -> ())
			local info = GameRules.get(gameId)
			local entry = GameCatalog.get(gameId)
			if not info or not entry then
				return
			end
			cardGameId = gameId
			cardHidden = hidden
			onHide = hideChanged
			cardTitle.Text = `How to play {entry.name}`
			cardGoal.Text = info.goal
			Kit.clear(cardLines)
			for i, line in info.card do
				Kit.label(`{i}.  {line}`, {
					TextSize = 14,
					AutomaticSize = Enum.AutomaticSize.Y,
					Size = UDim2.new(1, 0, 0, 0),
					LayoutOrder = i,
					ZIndex = Z - 9,
					Parent = cardLines,
				})
			end
			renderHide()
			card.Visible = true
		end,
		closeCard = closeCard,
		cardOpen = function(): boolean
			return card.Visible
		end,
	}
end

return RulesPanel
