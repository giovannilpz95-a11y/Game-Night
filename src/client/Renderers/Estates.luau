-- Property Party table: the 40-space board on the left (11x11 ring of tiles, tokens on
-- them, owner outlines, houses and hotels), dice and the latest news in the middle.
-- On the right: what you can do right now (roll, buy, bid, pay, answer a trade), and
-- the deed you tapped (rents, owner, and Build / Sell / Mortgage when it's yours).
-- A Trade window lets you swap deeds, cash and Get Out of Jail cards with anyone.
--
-- Board data and the build/mortgage checks come from the shared rules module, so the
-- buttons match what the server will accept. The server still checks everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Rules = require(ReplicatedStorage.Shared.Games.Estates)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local Kit = require(script.Parent.Parent.UI.Kit)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local Theme = Kit.Theme

local Estates = {}

local spaces = Rules.spaces
local TILE = 1 / 11
local BOARD_COLOR = Color3.fromRGB(214, 232, 214)
local TILE_COLOR = Color3.fromRGB(246, 243, 232)
local TILE_TEXT = Color3.fromRGB(40, 36, 50)
local CORNER_KINDS = { start = true, jail = true, rest = true, gotojail = true }
local KIND_ICONS = {
	start = "START\n→ $200",
	jail = "JAIL",
	rest = "REST\nSTOP",
	gotojail = "GO TO\nJAIL",
	lucky = "?",
	mail = "✉",
	station = "🚉",
	utility = "⚡",
	tax = "$",
}

-- Grid cell (column, row; 0-based) of each board position. Start is bottom-right and
-- play goes clockwise: along the bottom, up the left, across the top, down the right.
local function cellOf(pos: number): (number, number)
	local i = pos - 1
	if i <= 10 then
		return 10 - i, 10
	elseif i <= 20 then
		return 0, 10 - (i - 10)
	elseif i <= 30 then
		return i - 20, 0
	end
	return 10, i - 30
end

local function money(n: number): string
	return `${n}`
end

-- The rules' checks (canBuild etc.) want a state; this rebuilds enough of one from a view.
local function stateFromView(view: any): any
	local owner = {}
	for pos, seat in view.owner do
		owner[pos] = if seat ~= 0 then seat else nil
	end
	local players = {}
	for seat, p in view.players do
		players[seat] = { cash = p.cash, cards = table.create(p.cards, "card"), bankrupt = p.bankrupt }
	end
	return {
		owner = owner,
		houses = view.houses,
		mortgaged = view.mortgaged,
		housesLeft = view.housesLeft,
		hotelsLeft = view.hotelsLeft,
		players = players,
	}
end

local function groupHasBuildings(view: any, group: number): boolean
	for _, pos in Rules.groupMembers[group] do
		if view.houses[pos] > 0 then
			return true
		end
	end
	return false
end

local function tradable(view: any, pos: number): boolean
	local space = spaces[pos]
	return space.kind ~= "street" or not groupHasBuildings(view, space.group)
end

function Estates.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local selected: number? = nil
	local tradeOpen = false
	local bankruptConfirm = false

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
	local rerender: () -> () = function() end

	-- Board -------------------------------------------------------------------
	local boardArea = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(0.6, 1), Parent = root })
	local board = Kit.new("Frame", {
		BackgroundColor3 = BOARD_COLOR,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = boardArea,
	}, { Kit.corner(12), Kit.new("UIAspectRatioConstraint", { AspectRatio = 1 }) })

	local function nameOf(seat: number?): string
		if seat == nil then
			return ""
		end
		if snapshot and seat == snapshot.yourSeat then
			return "You"
		end
		local s = snapshot and snapshot.seats[seat]
		return if s then s.name else `Seat {seat}`
	end

	local tiles = {}
	for pos, space in spaces do
		local col, row = cellOf(pos)
		local tile = Kit.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = TILE_COLOR,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(col * TILE, row * TILE),
			Size = UDim2.fromScale(TILE, TILE),
			Parent = board,
		})
		local stroke = Kit.new("UIStroke", { Color = Color3.fromRGB(150, 150, 140), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = tile })
		local bar = nil
		if space.kind == "street" then
			bar = Kit.new("Frame", {
				BackgroundColor3 = Rules.groups[space.group].color,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 0.24),
				Parent = tile,
			})
		end
		local houses = Kit.label("", {
			Font = Theme.FontBold,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.4,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 0.24),
			ZIndex = 3,
			Parent = tile,
		})
		local icon = KIND_ICONS[space.kind]
		local name = Kit.label(if CORNER_KINDS[space.kind] then icon else space.name, {
			Font = if CORNER_KINDS[space.kind] then Theme.FontBold else Theme.Font,
			TextScaled = true,
			TextColor3 = TILE_TEXT,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			Position = UDim2.fromScale(0.04, if CORNER_KINDS[space.kind] then 0.05 else 0.25),
			Size = UDim2.fromScale(0.92, if CORNER_KINDS[space.kind] then 0.6 else 0.3),
			Parent = tile,
		})
		Kit.new("UITextSizeConstraint", { MaxTextSize = if CORNER_KINDS[space.kind] then 18 else 12, Parent = name })
		if icon and not CORNER_KINDS[space.kind] and space.kind ~= "street" then
			name.Text = `{icon} {space.name}`
		end
		local price = Kit.label(if space.price then money(space.price) elseif space.amount then `Pay {money(space.amount)}` else "", {
			TextScaled = true,
			TextColor3 = Color3.fromRGB(90, 86, 100),
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromScale(0, 0.53),
			Size = UDim2.fromScale(1, 0.13),
			Parent = tile,
		})
		Kit.new("UITextSizeConstraint", { MaxTextSize = 11, Parent = price })
		-- Tokens get the bottom third of the tile, below the price, so they never cover it.
		local tokens = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.04, if CORNER_KINDS[space.kind] then 0.62 else 0.66),
			Size = UDim2.fromScale(0.92, if CORNER_KINDS[space.kind] then 0.34 else 0.32),
			ZIndex = 4,
			Parent = tile,
		})
		Kit.new("UIGridLayout", {
			CellSize = UDim2.fromScale(0.23, 0.45),
			CellPadding = UDim2.fromScale(0.02, 0.05),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = tokens,
		})
		tile.Activated:Connect(function()
			if Rules.isDeed(pos) then
				selected = pos
				rerender()
			end
		end)
		tiles[pos] = { frame = tile, stroke = stroke, bar = bar, houses = houses, tokens = tokens, price = price }
	end

	-- Middle of the board: title, dice, news.
	local middle = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(TILE + 0.02, TILE + 0.02),
		Size = UDim2.fromScale(1 - 2 * TILE - 0.04, 1 - 2 * TILE - 0.04),
		Parent = board,
	})
	local catalogEntry = GameCatalog.get(Rules.id)
	local title = Kit.label(string.upper(if catalogEntry then catalogEntry.name else "Property Party"), {
		Font = Theme.FontBold,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(60, 120, 80),
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 0.12),
		Parent = middle,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 40, Parent = title })
	local roundLabel = Kit.label("", {
		TextScaled = true,
		TextColor3 = Color3.fromRGB(70, 90, 80),
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromScale(0, 0.12),
		Size = UDim2.fromScale(1, 0.05),
		Parent = middle,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 16, Parent = roundLabel })

	local diceRow = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromScale(0.3, 0.2), Size = UDim2.fromScale(0.4, 0.17), Parent = middle })
	local dice = {}
	for i = 1, 2 do
		local die = Kit.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(if i == 1 then 0.27 else 0.73, 0.5),
			Size = UDim2.fromScale(0.42, 1),
			Parent = diceRow,
		}, { Kit.corner(10), Kit.new("UIAspectRatioConstraint", { AspectRatio = 1 }), Kit.new("UIStroke", { Thickness = 2, Color = Color3.fromRGB(60, 60, 70) }) })
		dice[i] = Kit.label("", {
			Font = Theme.FontBold,
			TextScaled = true,
			TextColor3 = TILE_TEXT,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			Parent = die,
		})
		dice[i .. "frame"] = die
	end

	local cardBox = Kit.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 250, 220),
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.1, 0.4),
		Size = UDim2.fromScale(0.8, 0.17),
		Visible = false,
		Parent = middle,
	}, { Kit.corner(10), Kit.padding(6), Kit.new("UIStroke", { Thickness = 2, Color = Theme.Accent }) })
	local cardText = Kit.label("", {
		TextScaled = true,
		TextColor3 = TILE_TEXT,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = cardBox,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 18, Parent = cardText })

	local logFrame = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromScale(0, 0.6), Size = UDim2.fromScale(1, 0.4), Parent = middle })
	local logList = Kit.list(2)
	logList.VerticalAlignment = Enum.VerticalAlignment.Bottom
	logList.Parent = logFrame

	-- Side panel ----------------------------------------------------------------
	local side = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0.6, 12, 0, 0), Size = UDim2.new(0.4, -12, 1, 0), Parent = root })

	local actionPanel = Kit.panel({ Size = UDim2.new(1, 0, 0.42, -6), Parent = side })
	local actionText = Kit.label("", {
		TextSize = 17,
		Font = Theme.FontBold,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 1, -92),
		Parent = actionPanel,
	})
	-- Two rows of buttons pinned to the bottom of the panel, so they never float.
	local actionButtons = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 84),
		Parent = actionPanel,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -4, 0, 38),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = actionButtons,
	})

	local detailPanel = Kit.panel({ Position = UDim2.fromScale(0, 0.42), Size = UDim2.new(1, 0, 0.58, 0), Parent = side })
	local detailBar = Kit.new("Frame", { BorderSizePixel = 0, Visible = false, Size = UDim2.new(1, 0, 0, 8), Parent = detailPanel }, { Kit.corner(4) })
	local detailTitle = Kit.label("", { TextSize = 21, Font = Theme.FontTitle, Position = UDim2.new(0, 0, 0, 12), Parent = detailPanel })
	local detailBody = Kit.label("", {
		TextSize = 14,
		TextColor3 = Theme.SubText,
		TextYAlignment = Enum.TextYAlignment.Top,
		RichText = true,
		Position = UDim2.new(0, 0, 0, 38),
		Size = UDim2.new(1, 0, 1, -38 - 84),
		Parent = detailPanel,
	})
	local detailButtons = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 1, -80), Size = UDim2.new(1, 0, 0, 80), Parent = detailPanel })
	Kit.new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -4, 0, 36),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = detailButtons,
	})

	-- Trade window ----------------------------------------------------------------
	local trade = Kit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.98, 0.98),
		BackgroundColor3 = Theme.PanelLight,
		Visible = false,
		ZIndex = 20,
		Parent = boardArea, -- over the board, so the action panel stays visible
	})
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(640, 520), Parent = trade })
	Kit.label("Trade", { TextSize = 22, Font = Theme.FontTitle, ZIndex = 21, Parent = trade })
	local partnerRow = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 30), Size = UDim2.new(1, 0, 0, 34), ZIndex = 21, Parent = trade })
	Kit.list(6, true).Parent = partnerRow

	local tradeDraft = { partner = nil :: number?, give = {} :: { [number]: boolean }, get = {} :: { [number]: boolean }, giveCards = 0, getCards = 0 }

	local function tradeColumn(x: number, heading: string)
		local col = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(x, if x > 0 then 6 else 0, 0, 72), Size = UDim2.new(0.5, -6, 1, -72 - 50), ZIndex = 21, Parent = trade })
		local headingLabel = Kit.label(heading, { TextSize = 16, Font = Theme.FontBold, ZIndex = 21, Parent = col })
		local list = Kit.new("ScrollingFrame", {
			BackgroundColor3 = Theme.Panel,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 0, 24),
			Size = UDim2.new(1, 0, 1, -24 - 76),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 6,
			ZIndex = 21,
			Parent = col,
		}, { Kit.corner(8), Kit.padding(6) })
		Kit.list(4).Parent = list
		local cash = Kit.new("TextBox", {
			PlaceholderText = "Cash $0",
			Text = "",
			ClearTextOnFocus = false,
			BackgroundColor3 = Theme.Panel,
			TextColor3 = Theme.Text,
			PlaceholderColor3 = Theme.SubText,
			Font = Theme.Font,
			TextSize = 16,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 1, -70),
			Size = UDim2.new(1, 0, 0, 32),
			ZIndex = 21,
			Parent = col,
		}, { Kit.corner(8) })
		local cards = Kit.button("", function() end, {
			BackgroundColor3 = Theme.Panel,
			TextColor3 = Theme.Text,
			TextSize = 14,
			Position = UDim2.new(0, 0, 1, -32),
			Size = UDim2.new(1, 0, 0, 30),
			ZIndex = 21,
			Parent = col,
		})
		return { heading = headingLabel, list = list, cash = cash, cards = cards }
	end
	local giveCol = tradeColumn(0, "You give")
	local getCol = tradeColumn(0.5, "You get")

	local function parseCash(box: TextBox): number
		local digits = string.gsub(box.Text, "[^%d]", "")
		return math.min(tonumber(digits) or 0, 10000000)
	end

	local renderTrade: () -> ()

	local function sideOf(picks: { [number]: boolean }, cash: number, cards: number)
		local props = {}
		for pos, on in picks do
			if on then
				table.insert(props, pos)
			end
		end
		table.sort(props)
		return { props = props, cash = cash, cards = cards }
	end

	local sendButton = Kit.button("Send offer", function()
		if not tradeDraft.partner then
			return
		end
		sendMove({
			kind = "offer",
			to = tradeDraft.partner,
			give = sideOf(tradeDraft.give, parseCash(giveCol.cash), tradeDraft.giveCards),
			get = sideOf(tradeDraft.get, parseCash(getCol.cash), tradeDraft.getCards),
		})
		tradeOpen = false
		trade.Visible = false
	end, { Position = UDim2.new(0.5, 6, 1, -40), Size = UDim2.new(0.5, -6, 0, 40), ZIndex = 21, Parent = trade })
	Kit.button("Cancel", function()
		tradeOpen = false
		trade.Visible = false
	end, { BackgroundColor3 = Theme.Panel, TextColor3 = Theme.Text, Position = UDim2.new(0, 0, 1, -40), Size = UDim2.new(0.5, -6, 0, 40), ZIndex = 21, Parent = trade })

	giveCol.cards.Activated:Connect(function()
		local have = snapshot and snapshot.view.players[snapshot.yourSeat].cards or 0
		tradeDraft.giveCards = (tradeDraft.giveCards + 1) % (have + 1)
		renderTrade()
	end)
	getCol.cards.Activated:Connect(function()
		local have = if snapshot and tradeDraft.partner then snapshot.view.players[tradeDraft.partner].cards else 0
		tradeDraft.getCards = (tradeDraft.getCards + 1) % (have + 1)
		renderTrade()
	end)

	local function deedRow(list: ScrollingFrame, pos: number, picked: boolean, mortgaged: boolean, onClick: () -> ())
		local space = spaces[pos]
		local row = Kit.new("TextButton", {
			Text = "",
			AutoButtonColor = true,
			BackgroundColor3 = if picked then Theme.Accent else Theme.PanelLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 30),
			LayoutOrder = pos,
			ZIndex = 22,
			Parent = list,
		}, { Kit.corner(6) })
		Kit.new("Frame", {
			BackgroundColor3 = if space.group then Rules.groups[space.group].color else Theme.SubText,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 4, 0, 4),
			Size = UDim2.new(0, 8, 1, -8),
			ZIndex = 23,
			Parent = row,
		}, { Kit.corner(3) })
		Kit.label(`{space.name}{if mortgaged then " (mortgaged)" else ""}  {money(space.price)}`, {
			TextSize = 14,
			TextColor3 = if picked then Theme.AccentText else Theme.Text,
			Position = UDim2.new(0, 18, 0, 0),
			Size = UDim2.new(1, -22, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 23,
			Parent = row,
		})
		row.Activated:Connect(onClick)
	end

	function renderTrade()
		if not snapshot then
			return
		end
		local view = snapshot.view
		local me = snapshot.yourSeat
		Kit.clear(partnerRow)
		for seat, p in view.players do
			if seat ~= me and not p.bankrupt then
				Kit.button(nameOf(seat), function()
					if tradeDraft.partner ~= seat then
						tradeDraft.partner = seat
						table.clear(tradeDraft.get)
						tradeDraft.getCards = 0
						getCol.cash.Text = ""
					end
					renderTrade()
				end, {
					BackgroundColor3 = if tradeDraft.partner == seat then Theme.Seat[seat] or Theme.Accent else Theme.Panel,
					TextColor3 = if tradeDraft.partner == seat then Theme.AccentText else Theme.Text,
					Size = UDim2.new(0, 120, 1, 0),
					TextTruncate = Enum.TextTruncate.AtEnd,
					ZIndex = 22,
					Parent = partnerRow,
				})
			end
		end
		local function fill(col, seat: number?, picks: { [number]: boolean }, cards: number)
			Kit.clear(col.list)
			if not seat then
				col.cards.Visible = false
				return
			end
			for pos in picks do
				-- Drop picks that changed hands or got buildings since they were picked.
				if view.owner[pos] ~= seat or not tradable(view, pos) then
					picks[pos] = nil
				end
			end
			for pos = 1, #spaces do
				if view.owner[pos] == seat and Rules.isDeed(pos) and tradable(view, pos) then
					deedRow(col.list, pos, picks[pos] == true, view.mortgaged[pos], function()
						picks[pos] = not picks[pos]
						renderTrade()
					end)
				end
			end
			local have = view.players[seat].cards
			col.cards.Visible = have > 0
			col.cards.Text = `Get Out of Jail cards: {cards} of {have} (tap)`
			col.cash.PlaceholderText = `Cash (has {money(view.players[seat].cash)})`
		end
		fill(giveCol, me, tradeDraft.give, tradeDraft.giveCards)
		fill(getCol, tradeDraft.partner, tradeDraft.get, tradeDraft.getCards)
		getCol.heading.Text = if tradeDraft.partner then `You get from {nameOf(tradeDraft.partner)}` else "Pick a player above"
		-- Send offer stays grey until there's someone to send it to.
		local ready = tradeDraft.partner ~= nil
		sendButton.AutoButtonColor = ready
		sendButton.BackgroundColor3 = if ready then Theme.Accent else Theme.Panel
		sendButton.TextColor3 = if ready then Theme.AccentText else Theme.SubText
	end

	local function openTrade()
		tradeOpen = true
		table.clear(tradeDraft.give)
		table.clear(tradeDraft.get)
		tradeDraft.giveCards, tradeDraft.getCards = 0, 0
		giveCol.cash.Text = ""
		getCol.cash.Text = ""
		trade.Visible = true
		renderTrade()
	end

	-- Rendering -------------------------------------------------------------------
	local function describeSide(side: any): string
		local parts = {}
		for _, pos in side.props do
			table.insert(parts, spaces[pos].name)
		end
		if side.cash > 0 then
			table.insert(parts, money(side.cash))
		end
		if side.cards > 0 then
			table.insert(parts, `{side.cards} Jail card{if side.cards > 1 then "s" else ""}`)
		end
		return if #parts > 0 then table.concat(parts, ", ") else "nothing"
	end

	-- `enabled = false` draws a greyed button that does nothing, so a slot keeps its place.
	local function addButton(text: string, onClick: () -> (), color: Color3?, order: number?, enabled: boolean?)
		local on = enabled ~= false
		Kit.button(text, function()
			if on then
				onClick()
			end
		end, {
			-- Disabled buttons keep a faint fill so they still read as buttons.
			BackgroundColor3 = if not on then Theme.PanelLight elseif color then color else Theme.Accent,
			BackgroundTransparency = if on then 0 else 0.35,
			TextColor3 = if not on then Theme.SubText elseif color then Theme.Text else Theme.AccentText,
			AutoButtonColor = on,
			TextSize = 15,
			TextWrapped = true,
			LayoutOrder = order or 0,
			Parent = actionButtons,
		})
	end

	local lastCardN = 0
	local lastDice = ""

	local function renderActions(view: any, me: number?)
		Kit.clear(actionButtons)
		local active = snapshot.activeSeats[1]
		-- The panel's ring shows whose move it is (gold when it's yours).
		HudKit.turnTint(actionPanel, if view.phase == "over" then nil else active, active ~= nil and active == me and view.phase ~= "over")
		local mine = me ~= nil and active == me
		local myPlayer = if me then view.players[me] else nil
		if view.phase == "over" then
			actionText.Text = "Game over"
			return
		end
		if me and myPlayer and myPlayer.bankrupt then
			actionText.Text = "You're bankrupt. Stick around to see who wins!"
			return
		end

		if view.phase == "auction" then
			local a = view.auction
			local leader = if a.leader then `{nameOf(a.leader)} lead{if a.leader == me then "" else "s"} with {money(a.high)}` else "No bids yet"
			actionText.Text = `Auction: {spaces[a.pos].name} (worth {money(spaces[a.pos].price)})\n{leader}`
			if mine then
				for i, step in { 10, 50, 100 } do
					local amount = a.high + step
					if amount <= myPlayer.cash then
						addButton(`Bid {money(amount)}`, function()
							sendMove({ kind = "bid", amount = amount })
						end, nil, i)
					end
				end
				addButton("Pass", function()
					sendMove({ kind = "pass" })
				end, Theme.PanelLight, 9)
			else
				actionText.Text ..= `\nWaiting for {nameOf(active)} to bid...`
			end
			return
		end

		if view.phase == "trade" then
			local t = view.trade
			actionText.Text = `{nameOf(t.from)} offer{if t.from == me then "" else "s"} {if t.to == me then "you" else nameOf(t.to)}:\nGives {describeSide(t.give)}\nWants {describeSide(t.get)}`
			if mine then
				addButton("Accept", function()
					sendMove({ kind = "accept" })
				end, Theme.Good, 1)
				addButton("Decline", function()
					sendMove({ kind = "reject" })
				end, Theme.Bad, 2)
			end
			return
		end

		if not mine then
			local doing = if view.phase == "buy" then `is deciding on {spaces[view.players[active].pos].name}`
				elseif view.phase == "debt" then "is raising cash"
				else "is taking their turn"
			actionText.Text = `{nameOf(active)} {doing}...`
			return
		end

		local canTrade = view.tradesLeft > 0
		if view.phase == "buy" then
			local space = spaces[myPlayer.pos]
			local auctions = view.auctions ~= false
			actionText.Text = if auctions then `Buy {space.name} for {money(space.price)}?\nIf you don't, it goes to auction.` else `Buy {space.name} for {money(space.price)}?\nIf you don't, it stays with the bank.`
			if myPlayer.cash >= space.price then
				addButton(`Buy {money(space.price)}`, function()
					sendMove({ kind = "buy" })
				end, nil, 1)
			else
				actionText.Text ..= if auctions then "\nNot enough cash: mortgage a deed (tap it) or auction it." else "\nNot enough cash: mortgage a deed (tap it) or pass."
			end
			addButton(if auctions then "Auction it" else "Pass", function()
				sendMove({ kind = "decline" })
			end, Theme.PanelLight, 2)
		elseif view.phase == "debt" then
			local d = view.debt
			actionText.Text = `You owe {money(d.amount)} ({d.why}). Tap your deeds to sell houses or mortgage, then pay.`
			-- Fixed slots: Pay, Trade, Go bankrupt never change places under a tap.
			addButton(`Pay {money(d.amount)}`, function()
				sendMove({ kind = "payDebt" })
			end, Theme.Good, 1, myPlayer.cash >= d.amount)
			addButton("Trade", openTrade, Theme.PanelLight, 2, canTrade)
			addButton(if bankruptConfirm then "Sure? Tap again" else "Go bankrupt", function()
				if bankruptConfirm then
					bankruptConfirm = false
					sendMove({ kind = "bankrupt" })
				else
					bankruptConfirm = true
					rerender()
					task.delay(3, function()
						bankruptConfirm = false
					end)
				end
			end, Theme.Bad, 3)
		else
			if view.canRoll then
				if myPlayer.inJail then
					actionText.Text = "You're in Jail. Roll doubles to get out, or pay."
					addButton("Roll for doubles", function()
						sendMove({ kind = "roll" })
					end, nil, 1)
					if myPlayer.cash >= Rules.JAIL_FEE then
						addButton(`Pay {money(Rules.JAIL_FEE)}`, function()
							sendMove({ kind = "payJail" })
						end, Theme.PanelLight, 2)
					end
					if myPlayer.cards > 0 then
						addButton("Use Jail card", function()
							sendMove({ kind = "useCard" })
						end, Theme.PanelLight, 3)
					end
				else
					actionText.Text = "Your turn! Roll the dice.\nTap your deeds to build or mortgage."
					addButton("Roll dice", function()
						sendMove({ kind = "roll" })
					end, nil, 1)
				end
			else
				actionText.Text = "Build, trade, or end your turn."
				addButton("End turn", function()
					sendMove({ kind = "endTurn" })
				end, nil, 1)
			end
			if canTrade then
				addButton("Trade", openTrade, Theme.PanelLight, 5)
			end
		end
	end

	local function renderDetail(view: any, me: number?)
		Kit.clear(detailButtons)
		if not selected then
			detailBar.Visible = false
			detailTitle.Text = "Deeds"
			detailBody.Text = "Tap any street, station or utility on the board to see its rents. Tap your own to build, sell or mortgage."
			return
		end
		local pos = selected
		local space = spaces[pos]
		detailBar.Visible = true
		detailBar.BackgroundColor3 = if space.group then Rules.groups[space.group].color else Theme.SubText
		detailTitle.Text = space.name
		local lines = {}
		local owner = view.owner[pos]
		table.insert(lines, `Price {money(space.price)} · Mortgage {money(space.price // 2)}`)
		if space.kind == "street" then
			local r = space.rents
			table.insert(lines, `Rent {money(r[1])} · Full set {money(r[1] * 2)}`)
			table.insert(lines, `1 house {money(r[2])} · 2 houses {money(r[3])}`)
			table.insert(lines, `3 houses {money(r[4])} · 4 houses {money(r[5])}`)
			table.insert(lines, `Hotel {money(r[6])} · Each house/hotel costs {money(space.houseCost)}`)
		elseif space.kind == "station" then
			table.insert(lines, "Rent $25 / $50 / $100 / $200 for 1-4 stations owned")
		else
			table.insert(lines, "Rent: 4x the dice, or 10x if you own both utilities")
		end
		local ownerText = if owner == 0 then "For sale" else `Owner: {nameOf(owner)}`
		if view.mortgaged[pos] then
			ownerText ..= " (mortgaged)"
		end
		local h = view.houses[pos]
		if h == 5 then
			ownerText ..= " · Hotel"
		elseif h > 0 then
			ownerText ..= ` · {h} house{if h > 1 then "s" else ""}`
		end
		table.insert(lines, `<b>{ownerText}</b>`)
		detailBody.Text = table.concat(lines, "\n")

		local manage = me ~= nil
			and owner == me
			and view.turn == me
			and (view.phase == "turn" or view.phase == "buy" or view.phase == "debt")
		if not manage then
			return
		end
		local fake = stateFromView(view)
		local function action(kind: string, label: string, check: (any, number, number) -> (boolean, string?), order: number)
			local ok = check(fake, me :: number, pos)
			if ok and (kind == "build" or kind == "unmortgage") and view.phase == "debt" then
				ok = false
			end
			if ok then
				Kit.button(label, function()
					sendMove({ kind = kind, pos = pos })
				end, { TextSize = 14, TextWrapped = true, LayoutOrder = order, Parent = detailButtons })
			end
		end
		if space.kind == "street" then
			action("build", if h == 4 then `Build hotel ({money(space.houseCost)})` else `Build house ({money(space.houseCost)})`, Rules.canBuild, 1)
			action("sell", `Sell {if h == 5 then "hotel" else "house"} (+{money(space.houseCost // 2)})`, Rules.canSell, 2)
		end
		action("mortgage", `Mortgage (+{money(space.price // 2)})`, Rules.canMortgage, 3)
		action("unmortgage", `Pay off ({money(Rules.unmortgageCost(pos))})`, Rules.canUnmortgage, 4)
	end

	local function render()
		local view = snapshot.view
		local me = snapshot.yourSeat

		roundLabel.Text = `Round {math.min(view.round, view.maxRounds)} of {view.maxRounds} · richest player wins at the end`
		if view.pot then
			roundLabel.Text ..= ` · Rest Stop jackpot {money(view.pot)}`
		end

		-- Tiles: owner outline, houses, mortgages, tokens.
		for pos, t in tiles do
			local owner = view.owner[pos]
			if owner ~= 0 and owner ~= nil then
				t.stroke.Color = Theme.Seat[owner] or Theme.Text
				t.stroke.Thickness = 3
			else
				t.stroke.Color = Color3.fromRGB(150, 150, 140)
				t.stroke.Thickness = 1
			end
			t.frame.BackgroundColor3 = if view.mortgaged[pos] then Color3.fromRGB(190, 186, 176)
				elseif pos == selected then Color3.fromRGB(255, 245, 200)
				else TILE_COLOR
			local h = view.houses[pos]
			t.houses.Text = if view.mortgaged[pos] then "MORTGAGED" elseif h == 5 then "HOTEL" elseif h > 0 then string.rep("■", h) else ""
			Kit.clear(t.tokens)
		end
		for seat, p in view.players do
			if not p.bankrupt then
				local token = Kit.new("Frame", {
					BackgroundColor3 = Theme.Seat[seat] or Theme.Text,
					BorderSizePixel = 0,
					LayoutOrder = seat,
					ZIndex = 5,
					Parent = tiles[p.pos].tokens,
				}, {
					Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
					Kit.new("UIStroke", { Thickness = if seat == me then 2 else 1, Color = if seat == me then Color3.new(1, 1, 1) else Color3.fromRGB(40, 40, 40) }),
					Kit.new("UIAspectRatioConstraint", { AspectRatio = 1 }),
				})
				if p.inJail then
					Kit.label("▥", { TextScaled = true, TextColor3 = Color3.new(0, 0, 0), TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = token })
				end
			end
		end

		-- Dice: a little bounce when a new roll comes in.
		local d = view.dice
		local diceKey = if d then `{d[1]},{d[2]},{snapshot.moveNumber}` else ""
		for i = 1, 2 do
			dice[i].Text = if d then tostring(d[i]) else "-"
		end
		if d and diceKey ~= lastDice and view.log[#view.log] and string.find(view.log[#view.log].text, "rolled", 1, true) then
			for i = 1, 2 do
				local frame = dice[i .. "frame"]
				frame.Rotation = if i == 1 then -25 else 25
				TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
			end
		end
		lastDice = diceKey

		-- The last card drawn stays up until the next one.
		local card = view.lastCard
		if card then
			local deck = Rules.decks[card.deck]
			cardBox.Visible = true
			cardText.Text = `{deck.name} ({nameOf(card.seat)}): {deck.cards[card.index].text}`
			if card.n ~= lastCardN then
				lastCardN = card.n
				cardBox.Size = UDim2.fromScale(0.6, 0.12)
				TweenService:Create(cardBox, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromScale(0.8, 0.17) }):Play()
			end
		else
			cardBox.Visible = false
		end

		-- News feed.
		Kit.clear(logFrame)
		for i, entry in view.log do
			local who = if entry.seat then nameOf(entry.seat) .. " " else ""
			local text = entry.text
			if entry.seat ~= nil and entry.seat == me then
				text = string.gsub(text, "^owes ", "owe ") -- "You owe", not "You owes"
			end
			local line = Kit.label(`{who}{text}`, {
				TextScaled = true,
				-- Seat colors darkened a lot so they read on the pale board.
				TextColor3 = if entry.seat then (Theme.Seat[entry.seat] or TILE_TEXT):Lerp(Color3.new(0, 0, 0), 0.65) else TILE_TEXT,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 1 / 8, -2),
				LayoutOrder = i,
				Parent = logFrame,
			})
			Kit.new("UITextSizeConstraint", { MaxTextSize = 15, Parent = line })
		end

		renderActions(view, me)
		renderDetail(view, me)
		if tradeOpen then
			-- Close the window if the turn moved on.
			if view.turn ~= me or not (view.phase == "turn" or view.phase == "debt") or view.tradesLeft <= 0 then
				tradeOpen = false
				trade.Visible = false
			else
				renderTrade()
			end
		end
	end
	rerender = function()
		if snapshot then
			render()
		end
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			render()
		end,
		destroy = function()
			root:Destroy()
		end,
	}
end

return Estates
