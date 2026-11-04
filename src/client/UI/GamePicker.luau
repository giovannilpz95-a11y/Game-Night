-- Center panel: the shelf of games. The party leader picks a game and a table size,
-- empty seats get bots. Everyone else sees what's available while they wait.
-- Party Hosts can also change house rules and pick their own word list or quiz deck.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local Config = require(ReplicatedStorage.Shared.Config)
local HouseRules = require(ReplicatedStorage.Shared.HouseRules)
local CustomContent = require(ReplicatedStorage.Shared.CustomContent)
local GameArt = require(ReplicatedStorage.Shared.GameArt)
local Kit = require(script.Parent.Kit)
local Analytics = require(script.Parent.Parent.Analytics)
local Theme = Kit.Theme

local GamePicker = {}

local localPlayer = Players.LocalPlayer

local ALL = "All"
local GRID_TOP = 94 -- title, status line, filter chips

local function rgb(list: { number }): Color3
	return Color3.fromRGB(list[1], list[2], list[3])
end

-- hooks: needHost(reason), showRules(gameId)
function GamePicker.create(parent: Instance, sendMatch: (any) -> (), hooks: any)
	-- Fills `parent` (the Play window). Phones get a 2-column grid; wide screens get more.
	local root = Kit.new("Frame", {
		Name = "GamePicker",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	})

	Kit.title("Pick a game", { Parent = root })
	local status = Kit.label("", { TextColor3 = Theme.SubText, TextSize = 14, Position = UDim2.new(0, 0, 0, 30), Size = UDim2.new(1, -48, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd, Parent = root })

	-- Filter chips: All, then each category. Scrolls sideways on a narrow phone.
	local filter = ALL
	local render: () -> ()
	local chipRow = Kit.new("ScrollingFrame", {
		Name = "Filters",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 56),
		Size = UDim2.new(1, 0, 0, 32),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		Parent = root,
	}, { Kit.list(6, true) })
	local chips: { [string]: TextButton } = {}
	local function addChip(key: string, text: string, order: number)
		chips[key] = Kit.chip(text, function()
			filter = key
			render()
		end, { Size = UDim2.new(0, 0, 1, 0), LayoutOrder = order, Parent = chipRow })
	end
	addChip(ALL, "All games", 0)
	for i, category in GameArt.categories do
		addChip(category.key, `{category.icon} {category.name}`, i)
	end

	local BAR_H = 44
	local gridLayout = Kit.new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -6, 0, 112),
		CellPadding = UDim2.new(0, 8, 0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	local grid = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, GRID_TOP),
		Size = UDim2.new(1, 0, 1, -GRID_TOP - BAR_H - 8),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		Parent = root,
	}, { gridLayout, Kit.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 2) }) })
	local function fitGrid()
		local width = grid.AbsoluteSize.X - 8
		if width <= 0 then
			return
		end
		local columns = math.clamp(math.floor(width / 190), 2, 5)
		local cellHeight = if width / columns < 170 then 104 else 124
		gridLayout.CellSize = UDim2.new(1 / columns, -8, 0, cellHeight)
	end
	grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitGrid)
	fitGrid()

	-- Bottom bar (leader only): the controls sit right-aligned in one row; the chosen
	-- game's name is in the status line above, so nothing overlaps on a phone.
	local bar = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 1, -BAR_H), Size = UDim2.new(1, 0, 0, BAR_H), Parent = root })
	local barList = Kit.list(8, true)
	barList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	barList.VerticalAlignment = Enum.VerticalAlignment.Center
	barList.Parent = bar
	local seatsLabel = Kit.label("", { TextXAlignment = Enum.TextXAlignment.Center, TextSize = 15, Size = UDim2.new(0, 72, 1, 0), LayoutOrder = 3, Parent = bar })

	-- House rules (leader, once a game is chosen) and the rules sheet it opens.
	local rulesRow = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, 112, 0, 40), LayoutOrder = 1, Visible = false, Parent = bar })
	local sheet = Kit.new("Frame", { BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, Position = UDim2.new(0, 0, 0, GRID_TOP), Size = UDim2.new(1, 0, 1, -GRID_TOP - BAR_H - 8), Visible = false, ZIndex = 5, Parent = root })
	local sheetList = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ZIndex = 5,
		Parent = sheet,
	}, { Kit.list(6) })

	local isHost = false
	local hostSaved: any = { words = {}, quiz = {} }
	local picks: { [string]: number } = {} -- rule key -> choice index
	local customSlot: number? = nil -- the host's word list / quiz deck for this game

	local party: any = nil
	local chosen: GameCatalog.Entry? = nil
	local seats = 2
	local botLevel = Config.DefaultBotLevel
	local BOT_LEVEL_NAMES = { easy = "Easy bots", medium = "Medium bots", hard = "Hard bots" }

	local function clampSeats()
		if not chosen then
			return
		end
		local members = if party then #party.members else 1
		local maxSeats = math.min(chosen.maxSeats, Config.MaxSeats)
		seats = math.clamp(seats, math.max(chosen.minSeats, members), maxSeats)
	end

	local renderBar: () -> ()
	-- The seat stepper counts every press (not every completed click), and only redraws
	-- the bar, so fast taps on + all land.
	local function stepper(text: string, delta: number, order: number): TextButton
		local button = Kit.button(text, function() end, { Size = UDim2.new(0, 40, 0, 40), LayoutOrder = order, Parent = bar })
		button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonA then
				seats += delta
				clampSeats()
				renderBar()
			end
		end)
		return button
	end
	local minus = stepper("-", -1, 2)
	local plus = stepper("+", 1, 4)
	local startButton = Kit.button("Start", function()
		if chosen then
			sendMatch({ action = "start", gameId = chosen.id, seats = seats, botLevel = botLevel, rules = picks, custom = customSlot })
		end
	end, { BackgroundColor3 = Theme.Good, Size = UDim2.new(0, 110, 0, 40), TextSize = 18, LayoutOrder = 6, Parent = bar })
	-- Tapping cycles Easy -> Medium -> Hard. Only shown when bots will play.
	local levelButton: TextButton
	levelButton = Kit.button("", function()
		local index = table.find(Config.BotLevels, botLevel) or 1
		botLevel = Config.BotLevels[index % #Config.BotLevels + 1]
		render()
	end, { BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, Size = UDim2.new(0, 112, 0, 40), TextSize = 14, LayoutOrder = 5, Parent = bar })

	local function savedLists(kind: string): { any }
		local out = {}
		for _, entry in hostSaved[kind] or {} do
			table.insert(out, entry)
		end
		table.sort(out, function(a, b)
			return a.slot < b.slot
		end)
		return out
	end

	local function rulesText(entry: GameCatalog.Entry): string
		local values = HouseRules.resolve(entry, picks)
		local lines = HouseRules.describe(entry, values)
		if customSlot and entry.custom then
			for _, saved in hostSaved[entry.custom] or {} do
				if saved.slot == customSlot then
					table.insert(lines, 1, `"{saved.name}"`)
				end
			end
		end
		return if #lines > 0 then table.concat(lines, ", ") else "Normal rules"
	end

	local function sheetRow(order: number, title: string, hint: string?, value: string, onClick: () -> ())
		local frame = Kit.new("Frame", { BackgroundColor3 = Theme.PanelLight, BorderSizePixel = 0, Size = UDim2.new(1, -8, 0, if hint then 56 else 40), LayoutOrder = order, ZIndex = 6, Parent = sheetList }, { Kit.corner(8) })
		Kit.label(title, { Font = Theme.FontBold, Position = UDim2.new(0, 10, 0, 6), Size = UDim2.new(1, -220, 0, 22), ZIndex = 7, Parent = frame })
		if hint then
			Kit.label(hint, { TextSize = 12, TextColor3 = Theme.SubText, Position = UDim2.new(0, 10, 0, 28), Size = UDim2.new(1, -220, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 7, Parent = frame })
		end
		Kit.button(`{value}  ▸`, onClick, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.new(0, 190, 0, 32),
			TextSize = 14,
			BackgroundColor3 = if isHost then Theme.Accent else Theme.Panel,
			TextColor3 = if isHost then Theme.AccentText else Theme.SubText,
			ZIndex = 7,
			Parent = frame,
		})
	end

	local function renderSheet()
		Kit.clear(sheetList)
		local entry = chosen
		if not entry then
			return
		end
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end
		Kit.label(`{entry.name} house rules`, { Font = Theme.FontBold, TextSize = 18, Size = UDim2.new(1, -110, 0, 28), LayoutOrder = nextOrder(), ZIndex = 6, Parent = sheetList })
		if not isHost then
			Kit.button("House rules come with Party Host. Get it", function()
				hooks.needHost(nil)
			end, { Size = UDim2.new(1, -8, 0, 34), TextSize = 14, LayoutOrder = nextOrder(), ZIndex = 6, Parent = sheetList })
		end
		for _, rule in HouseRules.list(entry) do
			local index = picks[rule.key] or rule.default
			sheetRow(nextOrder(), rule.name, rule.hint, rule.choices[index].label, function()
				if not isHost then
					return hooks.needHost("House rules come with the Party Host pass")
				end
				picks[rule.key] = index % #rule.choices + 1
				render()
			end)
		end
		if entry.custom then
			local kind = entry.custom
			local lists = savedLists(kind)
			local label = if kind == "words" then "Our words" else "Our questions"
			for _, saved in lists do
				if saved.slot == customSlot then
					label = saved.name
				end
			end
			local hint = if #lists == 0 then `Make your own in Host tools ({CustomContent.Kinds[kind].plural}).` else `Play with one of your {CustomContent.Kinds[kind].plural}.`
			sheetRow(nextOrder(), CustomContent.Kinds[kind].name, hint, label, function()
				if not isHost then
					return hooks.needHost("Custom word lists and quiz decks come with the Party Host pass")
				end
				-- Cycle: ours -> each saved list -> ours.
				local position = 0
				for i, saved in lists do
					if saved.slot == customSlot then
						position = i
					end
				end
				local nextList = lists[position + 1]
				customSlot = if nextList then nextList.slot else nil
				render()
			end)
		end
		Kit.button("Reset to normal", function()
			table.clear(picks)
			customSlot = nil
			render()
		end, { Size = UDim2.new(0, 180, 0, 34), TextSize = 14, BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, LayoutOrder = nextOrder(), ZIndex = 6, Parent = sheetList })
	end

	local rulesButton = Kit.button("House rules", function()
		sheet.Visible = not sheet.Visible
		render()
	end, { Size = UDim2.fromScale(1, 1), TextSize = 14, BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, Parent = rulesRow })

	function render()
		local isLeader = party ~= nil and party.leaderId == localPlayer.UserId
		if not party then
			status.Text = "Connecting..."
		elseif isLeader and chosen then
			local hasRules = #HouseRules.list(chosen) > 0 or chosen.custom ~= nil
			status.Text = if hasRules then `{chosen.name} · {rulesText(chosen)}` else `{chosen.name} · empty seats get bots`
		elseif isLeader then
			status.Text = "Tap a game, then Start. Empty seats are filled with bots."
		else
			local leaderName = "the leader"
			for _, member in party.members do
				if member.userId == party.leaderId then
					leaderName = member.name
				end
			end
			status.Text = `Waiting for {leaderName} to pick a game...`
		end

		for key, chip in chips do
			Kit.setChip(chip, key == filter)
		end
		Kit.clear(grid)
		for index, entry in GameCatalog.entries do
			if filter ~= ALL and entry.category ~= filter then
				continue
			end
			local ready = entry.status == "ready"
			local selected = chosen ~= nil and chosen.id == entry.id
			local tint = rgb(GameArt.rgb(entry.category))
			local card = Kit.new("TextButton", {
				Name = entry.id,
				Text = "",
				AutoButtonColor = ready and isLeader,
				BackgroundColor3 = if selected then Theme.Accent else Theme.PanelLight,
				BackgroundTransparency = if ready then 0 else 0.35,
				BorderSizePixel = 0,
				LayoutOrder = if ready then index else 100 + index,
				Parent = grid,
			}, {
				Kit.corner(12),
				Kit.padding(10),
				Kit.stroke(if selected then Color3.new(1, 1, 1) else tint, if selected then 0.2 else 0.6, if selected then 2 else 1),
			})
			if ready and isLeader then
				Kit.pressable(card)
			end
			-- Icon badge in the category's color.
			local icon = Kit.label(GameArt.icon(entry.id), {
				Name = "Icon",
				BackgroundColor3 = tint,
				BackgroundTransparency = if selected then 0.1 else 0.55,
				TextSize = 20,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.fromOffset(36, 36),
				Parent = card,
			})
			Kit.corner(10).Parent = icon
			local textColor = if selected then Theme.AccentText else Theme.Text
			Kit.label(entry.name, {
				Font = Theme.FontBold,
				TextSize = 17,
				TextColor3 = textColor,
				Position = UDim2.new(0, 44, 0, 0),
				Size = UDim2.new(1, -44 - 26, 0, 36),
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = true,
				Parent = card,
			})
			Kit.label(entry.description, {
				TextSize = 13,
				TextColor3 = if selected then Theme.AccentText else Theme.SubText,
				Position = UDim2.new(0, 0, 0, 40),
				Size = UDim2.new(1, 0, 1, -60),
				TextYAlignment = Enum.TextYAlignment.Top,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = card,
			})
			local players = if entry.minSeats == entry.maxSeats then `👤 {entry.maxSeats}` else `👤 {entry.minSeats}-{entry.maxSeats}`
			local minutes = if entry.typicalMinutes then `  ·  ⏱ {entry.typicalMinutes} min` else ""
			Kit.label(if ready then players .. minutes else "Coming soon", {
				Font = Theme.FontBold,
				TextSize = 12,
				TextColor3 = if ready then (if selected then Theme.AccentText else Theme.SubText) else Theme.Accent,
				Position = UDim2.new(0, 0, 1, -18),
				Size = UDim2.new(1, 0, 0, 18),
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = card,
			})
			if ready and hooks.showRules then
				-- How to play, for everyone (not just the leader).
				local rules = Kit.button("?", function()
					hooks.showRules(entry.id)
				end, {
					Name = "Rules",
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 4, 0, -4),
					Size = UDim2.fromOffset(28, 28),
					TextSize = 15,
					BackgroundColor3 = if selected then Theme.AccentText else Theme.Panel,
					TextColor3 = if selected then Theme.Accent else Theme.Text,
					ZIndex = 2,
					Parent = card,
				})
				local rulesCorner = rules:FindFirstChildOfClass("UICorner")
				if rulesCorner then
					rulesCorner.CornerRadius = UDim.new(0.5, 0)
				end
			end
			if ready and isLeader then
				card.Activated:Connect(function()
					if not chosen or chosen.id ~= entry.id then
						table.clear(picks)
						customSlot = nil
					end
					chosen = entry
					Analytics.step("PickedGame")
					seats = math.max(entry.minSeats, if party then #party.members else 1)
					clampSeats()
					render()
				end)
			end
		end

		bar.Visible = isLeader
		-- Non-leaders don't get the bar, so the grid can use its space.
		grid.Size = if isLeader then UDim2.new(1, 0, 1, -GRID_TOP - BAR_H - 8) else UDim2.new(1, 0, 1, -GRID_TOP)
		local hasRules = chosen ~= nil and (#HouseRules.list(chosen) > 0 or chosen.custom ~= nil)
		rulesRow.Visible = isLeader and hasRules
		if not rulesRow.Visible then
			sheet.Visible = false
		end
		rulesButton.Text = if sheet.Visible then "Done" else "House rules"
		if sheet.Visible then
			renderSheet()
		end
		renderBar()
	end

	function renderBar()
		if chosen then
			seatsLabel.Text = `{seats} seats`
			minus.Visible = chosen.minSeats ~= chosen.maxSeats
			plus.Visible = minus.Visible
			startButton.Visible = true
			local members = if party then #party.members else 1
			levelButton.Visible = seats > members
			levelButton.Text = BOT_LEVEL_NAMES[botLevel] or botLevel
		else
			levelButton.Visible = false
			seatsLabel.Text = ""
			minus.Visible = false
			plus.Visible = false
			startButton.Visible = false
		end
	end

	render()

	return {
		root = root,
		setParty = function(newParty: any)
			party = newParty
			Analytics.step("SawLobby") -- the picker is up and showing games
			clampSeats()
			render()
		end,
		setHost = function(value: boolean)
			isHost = value
			if not isHost then
				table.clear(picks)
				customSlot = nil
			end
			render()
		end,
		setHostSaved = function(state: any)
			hostSaved = if type(state) == "table" then state else { words = {}, quiz = {} }
			if customSlot and chosen and chosen.custom then
				local still = false
				for _, saved in hostSaved[chosen.custom] or {} do
					if saved.slot == customSlot then
						still = true
					end
				end
				if not still then
					customSlot = nil
				end
			end
			render()
		end,
	}
end

return GamePicker
