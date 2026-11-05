-- Center panel: the shelf of games. The party leader picks a game and a table size,
-- empty seats get bots. Everyone else sees what's available while they wait.
-- Party Hosts can also change house rules and pick their own word list or quiz deck.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local Config = require(ReplicatedStorage.Shared.Config)
local HouseRules = require(ReplicatedStorage.Shared.HouseRules)
local CustomContent = require(ReplicatedStorage.Shared.CustomContent)
local GameArt = require(ReplicatedStorage.Shared.GameArt)
local Kit = require(script.Parent.Kit)
local Analytics = require(script.Parent.Parent.Analytics)
local Perf = require(script.Parent.Parent.Perf)
local GamePreview = require(script.Parent.GamePreview)
local Theme = Kit.Theme

local GamePicker = {}

local localPlayer = Players.LocalPlayer

local ALL = "All"
local GRID_TOP = 94 -- title, status line, filter chips

local HOVER_DELAY = 1 -- seconds resting on a tile before its hover card plays the game
local NAME_H = 42 -- the name and player count under each tile's picture

local function rgb(list: { number }): Color3
	return Color3.fromRGB(list[1], list[2], list[3])
end

-- Actually on screen: every frame up the chain visible, its ScreenGui on.
local function shown(object: GuiObject): boolean
	if object.AbsoluteSize.X <= 0 then
		return false
	end
	local at: Instance? = object
	while at do
		if at:IsA("GuiObject") and not at.Visible then
			return false
		elseif at:IsA("LayerCollector") then
			return at.Enabled
		end
		at = at.Parent
	end
	return false
end

-- The mouse in `object`'s pixels (ScreenGuis that keep the top-bar inset are offset).
local function mouseIn(object: GuiObject): boolean
	local point = UserInputService:GetMouseLocation()
	local screen = object:FindFirstAncestorWhichIsA("ScreenGui")
	if screen and not screen.IgnoreGuiInset then
		point -= GuiService:GetGuiInset()
	end
	local at, size = object.AbsolutePosition, object.AbsoluteSize
	return point.X >= at.X and point.X <= at.X + size.X and point.Y >= at.Y and point.Y <= at.Y + size.Y
end

-- A tile's picture before (or instead of) its bot preview: the category color with the
-- game's icon, big. Coming-soon games keep it.
local function poster(entry: any, parent: Instance): Frame
	local tint = rgb(GameArt.rgb(entry.category))
	local frame = Kit.new("Frame", {
		Name = "Poster",
		BackgroundColor3 = tint,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	}, {
		Kit.corner(Theme.Radius.Medium),
		Kit.new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(120, 110, 150)),
		}),
	})
	Kit.label(GameArt.icon(entry.id), {
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.6),
		Parent = frame,
	})
	return frame
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
		-- A 16:9 picture on top, the name and player count under it.
		local cellWidth = width / columns - 8
		gridLayout.CellSize = UDim2.new(1 / columns, -8, 0, math.floor(cellWidth * 9 / 16) + NAME_H + 12)
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
	local staggeredFilter: string? = nil
	local bumpedId: string? = nil
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

	local thumbFor: (any) -> Frame
	local hideHover: () -> ()
	local hoverable: (GuiButton, any) -> ()
	local onPick: ((any, GuiObject) -> ())? = nil

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

	-- Tile pictures, kept across redraws. Bot previews are drawn one per frame while the
	-- picker is on screen (not in low-detail mode); until then a tile shows its poster.
	type Thumb = { holder: Frame, preview: GamePreview.Preview? }
	local thumbs: { [string]: Thumb } = {}
	local buildQueue: { any } = {}
	function thumbFor(entry: any): Frame
		local thumb = thumbs[entry.id]
		if not thumb then
			local holder = Kit.new("Frame", { Name = "Picture", BackgroundTransparency = 1, ClipsDescendants = true })
			local image = GameArt.thumbnail(entry.id)
			if image then
				Kit.new("ImageLabel", {
					Name = "Thumbnail",
					BackgroundColor3 = Theme.Background,
					BorderSizePixel = 0,
					Image = image,
					ScaleType = Enum.ScaleType.Crop,
					Size = UDim2.fromScale(1, 1),
					Parent = holder,
				}, { Kit.corner(Theme.Radius.Medium) })
			else
				poster(entry, holder)
				if entry.status == "ready" then
					table.insert(buildQueue, entry)
				end
			end
			thumb = { holder = holder, preview = nil }
			thumbs[entry.id] = thumb
		end
		return thumb.holder
	end

	-- The hover card: rest the mouse (or a gamepad's selection) on a tile and a bigger card
	-- opens over it, playing the game with bots, with the full description.
	local hover = Kit.new("TextButton", {
		Name = "HoverCard",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 20,
		Parent = root,
	}, { Kit.corner(Theme.Radius.Large), Kit.padding(8), Kit.stroke(Color3.new(1, 1, 1), 0.3, 2) })
	local hoverScale = Kit.Juice.scale(hover, "HoverPop")
	local hoverPicture = Kit.new("Frame", { Name = "Picture", BackgroundTransparency = 1, ClipsDescendants = true, Parent = hover })
	local hoverName = Kit.label("", { Font = Theme.FontBold, TextSize = 18, Size = UDim2.new(1, 0, 0, 24), TextTruncate = Enum.TextTruncate.AtEnd, Parent = hover })
	local hoverText = Kit.label("", { TextSize = 13, TextColor3 = Theme.SubText, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, 0, 0, 34), Parent = hover })
	local hoverPreview: GamePreview.Preview? = nil
	local hoverCard: GuiObject? = nil -- the tile under the mouse / selection
	local hoverEntry: any = nil
	local hoverSince = 0
	local hoverOpen = false
	local hoverPad = false

	function hideHover()
		hoverOpen = false
		hover.Visible = false
		if hoverPreview then
			hoverPreview.destroy()
			hoverPreview = nil
		end
		for _, child in hoverPicture:GetChildren() do
			child:Destroy()
		end
	end

	local function openHover()
		local card, entry = hoverCard, hoverEntry
		if not card or not entry or not card.Parent then
			return
		end
		hoverOpen = true
		local cardSize, cardAt = card.AbsoluteSize, card.AbsolutePosition - root.AbsolutePosition
		local width = math.clamp(math.floor(cardSize.X * 1.7), 300, 440)
		width = math.min(width, root.AbsoluteSize.X - 8)
		local pictureH = math.floor((width - 16) * 9 / 16)
		local height = pictureH + 16 + 24 + 38
		hoverPicture.Size = UDim2.new(1, 0, 0, pictureH)
		hoverName.Position = UDim2.new(0, 2, 0, pictureH + 4)
		hoverText.Position = UDim2.new(0, 2, 0, pictureH + 28)
		hoverName.Text = entry.name
		local players = if entry.minSeats == entry.maxSeats then `{entry.maxSeats} players` else `{entry.minSeats}-{entry.maxSeats} players`
		hoverText.Text = `{entry.description}  ·  {players}`
		-- Centered on the tile, kept inside the picker.
		local x = math.clamp(cardAt.X + cardSize.X / 2 - width / 2, 4, root.AbsoluteSize.X - width - 4)
		local y = math.clamp(cardAt.Y + cardSize.Y / 2 - height / 2, 4, root.AbsoluteSize.Y - height - 4)
		hover.Position = UDim2.fromOffset(x, y)
		hover.Size = UDim2.fromOffset(width, height)
		local image = GameArt.thumbnail(entry.id)
		if image then
			Kit.new("ImageLabel", { BackgroundTransparency = 1, Image = image, ScaleType = Enum.ScaleType.Crop, Size = UDim2.fromScale(1, 1), Parent = hoverPicture }, { Kit.corner(Theme.Radius.Medium) })
		else
			poster(entry, hoverPicture)
		end
		if entry.status == "ready" then
			hoverPreview = GamePreview.new(entry, hoverPicture)
			if hoverPreview then
				hoverPreview.play()
				-- Fade the live game in over the picture, like a video starting.
				hoverPreview.root.GroupTransparency = 1
				TweenService:Create(hoverPreview.root, TweenInfo.new(0.35), { GroupTransparency = 0 }):Play()
			end
		end
		hover.Visible = true
		hoverScale.Scale = 0.85
		TweenService:Create(hoverScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end

	-- Clicking the hover card is clicking its tile.
	hover.Activated:Connect(function()
		local card = hoverCard
		hideHover()
		if card and card:IsA("GuiButton") and hoverEntry and onPick then
			onPick(hoverEntry, card)
		end
	end)

	local tiles: { [GuiObject]: any } = {} -- tile -> its game, for this redraw
	function hoverable(card: GuiButton, entry: any)
		tiles[card] = entry
		card.SelectionGained:Connect(function()
			hideHover()
			hoverCard, hoverEntry, hoverSince, hoverPad = card, entry, os.clock(), true
		end)
	end

	grid:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		hideHover()
		hoverCard = nil
	end)

	RunService.Heartbeat:Connect(function()
		local onScreen = shown(grid)
		-- Draw one more tile preview.
		if onScreen and #buildQueue > 0 and not Perf.isLow() then
			local entry = table.remove(buildQueue, 1)
			local thumb = thumbs[entry.id]
			if thumb then
				thumb.preview = GamePreview.new(entry, thumb.holder)
				if thumb.preview and chosen and chosen.id == entry.id then
					thumb.preview.play()
				end
			end
		end
		-- The hover card: open after a rest, close when the mouse or selection moves off.
		local last = UserInputService:GetLastInputType()
		local usingMouse = last == Enum.UserInputType.MouseMovement or last == Enum.UserInputType.MouseButton1 or last == Enum.UserInputType.MouseWheel
		if not hoverCard and usingMouse and onScreen and not sheet.Visible then
			for tile, entry in tiles do
				if tile.Parent and mouseIn(tile) then
					hoverCard, hoverEntry, hoverSince, hoverPad = tile, entry, os.clock(), false
					break
				end
			end
		end
		local card = hoverCard
		if not card then
			return
		end
		local still = onScreen and card.Parent ~= nil and not sheet.Visible
		if still then
			if hoverPad then
				still = GuiService.SelectedObject == card or (hoverOpen and GuiService.SelectedObject == hover)
			else
				still = mouseIn(card) or (hoverOpen and mouseIn(hover))
			end
		end
		if not still then
			hideHover()
			hoverCard = nil
		elseif not hoverOpen and os.clock() - hoverSince >= HOVER_DELAY then
			openHover()
		end
	end)

	local function pick(entry: any)
		if not chosen or chosen.id ~= entry.id then
			table.clear(picks)
			customSlot = nil
		end
		chosen = entry
		Analytics.step("PickedGame")
		seats = math.max(entry.minSeats, if party then #party.members else 1)
		clampSeats()
		render()
	end
	onPick = function(entry: any, card: GuiObject)
		local isLeader = party ~= nil and party.leaderId == localPlayer.UserId
		if isLeader and entry.status == "ready" then
			pick(entry)
		else
			Kit.nope(card)
		end
	end

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
		for _, thumb in thumbs do
			thumb.holder.Parent = nil -- kept: a drawn preview survives the redraw
		end
		hideHover()
		hoverCard = nil
		table.clear(tiles)
		Kit.clear(grid)
		-- Tiles pop in one by one when the list changes (first open, a new filter), not
		-- on every redraw; a fresh pick bumps just that tile.
		local restagger = filter ~= staggeredFilter
		staggeredFilter = filter
		local picked: GuiObject? = nil
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
				Kit.padding(6),
				Kit.stroke(if selected then Color3.new(1, 1, 1) else tint, if selected then 0.2 else 0.6, if selected then 2 else 1),
			})
			if ready and isLeader then
				Kit.pressable(card)
			else
				-- Coming soon, or not the leader: a wobble says "not now".
				card.Activated:Connect(function()
					Kit.nope(card)
				end)
			end
			if selected then
				picked = card
				local ring = card:FindFirstChild("Outline")
				if ring and ring:IsA("UIStroke") then
					Kit.Juice.breathe(ring, 0.05, 0.55)
				end
			end
			-- The picture: the uploaded thumbnail, or a still from a bot game on the real
			-- board (a poster with the icon until that's drawn).
			local picture = thumbFor(entry)
			picture.Size = UDim2.new(1, 0, 1, -NAME_H)
			picture.Parent = card
			if not ready then
				local soon = Kit.label("Coming soon", {
					Font = Theme.FontBold,
					TextSize = 13,
					TextColor3 = Theme.AccentText,
					BackgroundColor3 = Theme.Accent,
					TextXAlignment = Enum.TextXAlignment.Center,
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -6),
					Size = UDim2.fromOffset(104, 22),
					ZIndex = 2,
					Parent = picture,
				})
				Kit.corner(11).Parent = soon
			end
			-- Small icon badge in the category's color, on the picture's corner.
			local icon = Kit.label(GameArt.icon(entry.id), {
				Name = "Icon",
				BackgroundColor3 = tint,
				BackgroundTransparency = if selected then 0 else 0.15,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(4, 4),
				Size = UDim2.fromOffset(26, 26),
				ZIndex = 2,
				Parent = card,
			})
			Kit.corner(8).Parent = icon
			local textColor = if selected then Theme.AccentText else Theme.Text
			Kit.label(entry.name, {
				Font = Theme.FontBold,
				TextSize = 16,
				TextColor3 = textColor,
				Position = UDim2.new(0, 2, 1, -NAME_H + 2),
				Size = UDim2.new(1, -4, 0, 22),
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = card,
			})
			local players = if entry.minSeats == entry.maxSeats then `👤 {entry.maxSeats}` else `👤 {entry.minSeats}-{entry.maxSeats}`
			local minutes = if entry.typicalMinutes then `  ·  ⏱ {entry.typicalMinutes} min` else ""
			Kit.label(players .. minutes, {
				Font = Theme.FontBold,
				TextSize = 12,
				TextColor3 = if selected then Theme.AccentText else Theme.SubText,
				Position = UDim2.new(0, 2, 1, -18),
				Size = UDim2.new(1, -4, 0, 18),
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = card,
			})
			hoverable(card, entry)
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
					pick(entry)
				end)
			end
		end

		-- The picked game plays on its own tile (how phones, with no hover, see it move).
		for id, thumb in thumbs do
			if thumb.preview then
				if chosen and chosen.id == id then
					thumb.preview.play()
				else
					thumb.preview.pause()
				end
			end
		end

		if restagger then
			Kit.Juice.stagger(grid, 0.03)
		elseif picked and picked.Name ~= bumpedId then
			Kit.bump(picked, 0.08)
		end
		bumpedId = if picked then picked.Name else nil

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
