-- The Dressing Room: browse the Roblox catalog, try items on, buy them with Robux, save
-- looks, and save a fully owned look to your real Roblox avatar.
--
-- Opening it walks you onto the stage in the lobby's Dressing Room corner and the camera
-- frames your real avatar (UI/DressingCamera). The catalog panel docks on the right (or
-- along the bottom on a tall screen) and the rest of the screen is the stage, with + / -
-- / Fit zoom buttons, pinch and mouse-wheel zoom and drag to spin the avatar.
--
-- The panel has three views: Shop (catalog tabs with "For you" first, search, a grid that
-- loads more as you scroll), My look (what you have on, buy, reset, save to Roblox) and
-- Saved (saved looks and slots). The client only searches and shows; everything that
-- changes your avatar or spends anything goes to the server as a request with an asset ID.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local AvatarEditorService = game:GetService("AvatarEditorService")

local AvatarFraming = require(ReplicatedStorage.Shared.AvatarFraming)
local DressingRoom = require(ReplicatedStorage.Shared.DressingRoom)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Recommendations = require(ReplicatedStorage.Shared.Recommendations)
local Trending = require(ReplicatedStorage.Shared.Trending)
local DressingCamera = require(script.Parent.DressingCamera)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)
local Theme = Kit.Theme

local DressingRoomPanel = {}

local GEM_COLOR = Color3.fromRGB(110, 220, 255)
local ROBUX_COLOR = Theme.Good
local THUMB_BG = Color3.fromRGB(232, 230, 240)
local MAX_RESULTS = 600 -- cards kept in one list before it stops loading more
local RETRY_SECONDS = 3

local SORTS = {
	{ key = "Relevance", name = "Top" },
	{ key = "Bestselling", name = "Best selling" },
	{ key = "PriceLowToHigh", name = "Cheapest" },
	{ key = "RecentlyCreated", name = "Newest" },
}

-- "For you" sits in front of the shared browse categories and "Trending" right after
-- Popular. Both have their own order, so sorting or searching switches to Popular.
local FOR_YOU = { key = "foryou", name = "✨ For you", types = {}, special = true }
local TRENDING = { key = "trending", name = "🔥 Trending", types = {}, special = true }
local POPULAR_INDEX = 2
local TABS: { any } = { FOR_YOU }
for i, category in DressingRoom.Categories do
	table.insert(TABS, category)
	if i == 1 then
		table.insert(TABS, TRENDING)
	end
end

local function enumItem(enum: any, name: string): EnumItem?
	local ok, item = pcall(function()
		return enum[name]
	end)
	return if ok then item else nil
end

local function priceText(price: number?, forSale: boolean?): string
	if not forSale or price == nil then
		return "Try on only"
	elseif price == 0 then
		return "Free"
	end
	return `R$ {price}`
end

local function assetTypesFor(typeIds: { number }): { EnumItem }
	local types = {}
	for _, typeId in typeIds do
		local info = DressingRoom.Types[typeId]
		local item = info and enumItem(Enum.AvatarAssetType, info.search)
		if item then
			table.insert(types, item)
		end
	end
	return types
end

local ALL_TYPES = {}
for typeId, info in DressingRoom.Types do
	if not info.tryOnly then
		table.insert(ALL_TYPES, typeId)
	end
end

-- One catalog search. Returns CatalogPages, or raises.
local function searchCatalog(opts: { types: { number }, keyword: string?, sort: string, creator: string? }): any
	local params = CatalogSearchParams.new()
	params.SearchKeyword = opts.keyword or ""
	params.AssetTypes = assetTypesFor(opts.types)
	params.IncludeOffSale = false
	local sort = enumItem(Enum.CatalogSortType, opts.sort)
	if sort then
		params.SortType = sort :: any
	end
	if opts.creator then
		pcall(function()
			(params :: any).CreatorName = opts.creator
		end)
	end
	pcall(function()
		(params :: any).Limit = DressingRoom.SearchPageSize
	end)
	local ok, pages = pcall(function()
		return (AvatarEditorService :: any):SearchCatalogAsync(params)
	end)
	if not ok then
		ok, pages = pcall(function()
			return AvatarEditorService:SearchCatalog(params)
		end)
	end
	if not ok then
		error(pages)
	end
	return pages
end

-- The catalog's "similar items" for one worn asset.
local function similarTo(seed: Recommendations.Seed): { Recommendations.Pick }
	local info = DressingRoom.Types[seed.t]
	local assetType = info and enumItem(Enum.AvatarAssetType, info.search)
	if not assetType then
		return {}
	end
	local ok, result = pcall(function()
		return (AvatarEditorService :: any):GetRecommendedAssetsAsync(assetType, seed.id)
	end)
	if not ok then
		ok, result = pcall(function()
			return (AvatarEditorService :: any):GetRecommendedAssets(assetType, seed.id)
		end)
	end
	if not ok or type(result) ~= "table" then
		return {}
	end
	local picks = {}
	for _, entry in result do
		local pick = Recommendations.fromRoblox(entry)
		if pick then
			table.insert(picks, pick)
		end
	end
	return picks
end

-- "Similar items" for several seeds at once, asked in parallel. Lists come back in seed order.
local function similarLists(batch: { Recommendations.Seed }): { { Recommendations.Pick } }
	local lists: { { any } } = {}
	local left = #batch
	local thread = coroutine.running()
	for i, seed in batch do
		task.spawn(function()
			lists[i] = similarTo(seed)
			left -= 1
			if left == 0 and coroutine.status(thread) == "suspended" then
				task.spawn(thread)
			end
		end)
	end
	if left > 0 then
		coroutine.yield()
	end
	local ordered = {}
	for i = 1, #batch do
		table.insert(ordered, lists[i] or {})
	end
	return ordered
end

-- Names and prices for a list of asset ids, as catalog cards (id -> card).
local function itemDetails(ids: { number }): { [number]: any }
	local out = {}
	if #ids == 0 then
		return out
	end
	local ok, result = pcall(function()
		return (AvatarEditorService :: any):GetBatchItemDetails(ids, Enum.AvatarItemType.Asset)
	end)
	if ok and type(result) == "table" then
		for _, entry in result do
			local card = Trending.fromDetails(entry)
			if card then
				out[card.Id] = card
			end
		end
	end
	return out
end

-- The items on your own avatar (and whatever you have on right now), as seeds.
local function ownSeeds(): { Recommendations.Seed }
	local seeds = {}
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return seeds
	end
	local ok, description = pcall(function()
		return humanoid:GetAppliedDescription()
	end)
	if not ok or not description then
		return seeds
	end
	pcall(function()
		for _, acc in description:GetAccessories(true) do
			local t = DressingRoom.TypeByAccessory[acc.AccessoryType.Name]
			if t and acc.AssetId then
				table.insert(seeds, { id = acc.AssetId, t = t })
			end
		end
	end)
	for property, t in { Shirt = 11, Pants = 12, GraphicTShirt = 2 } do
		local id = (description :: any)[property]
		if type(id) == "number" and id > 0 then
			table.insert(seeds, { id = id, t = t })
		end
	end
	return seeds
end

local function pageEntries(pages: any, exclude: { [number]: boolean }?): { any }
	local out = {}
	for _, entry in pages:GetCurrentPage() do
		if (entry.ItemType == nil or entry.ItemType == "Asset") and type(entry.Id) == "number" and not (exclude and exclude[entry.Id]) then
			local price = entry.Price
			if price == nil then
				price = entry.LowestPrice
			end
			table.insert(out, { Id = entry.Id, Name = entry.Name, Price = price, creator = entry.CreatorName })
		end
	end
	return out
end

function DressingRoomPanel.create(parent: Instance, send: (any) -> ())
	local cam = DressingCamera.new()
	local compact = false

	local root = Kit.new("Frame", {
		Name = "DressingRoom",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 30,
		Parent = parent,
	})

	-- Stage: the free part of the screen where your avatar shows. Drag, pinch, scroll.
	local stage = Kit.new("TextButton", {
		Name = "Stage",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		ZIndex = 30,
		Parent = root,
	})
	local zoomPill = Kit.new("Frame", {
		Name = "Zoom",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -4, 1, -4),
		Size = UDim2.new(0, 48, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.15,
		ZIndex = 31,
		Parent = stage,
	}, { Kit.corner(24), Kit.list(4), Kit.padding(4) })
	local function pillButton(text: string, order: number, onClick: () -> ())
		return Kit.button(text, onClick, {
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundColor3 = Theme.PanelLight,
			TextColor3 = Theme.Text,
			TextSize = 22,
			LayoutOrder = order,
			ZIndex = 32,
			Parent = zoomPill,
		})
	end
	pillButton("+", 1, function()
		cam.zoomBy(1)
	end)
	pillButton("−", 2, function()
		cam.zoomBy(-1)
	end)
	local fitButton = pillButton("Fit", 3, function()
		cam.fit()
	end)
	fitButton.TextSize = 14
	for _, b in zoomPill:GetChildren() do
		if b:IsA("TextButton") then
			Kit.corner(20).Parent = b
		end
	end
	local stageHint = Kit.label("Drag to spin your avatar · pinch or scroll to zoom", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -120, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Text,
		TextStrokeTransparency = 0.5,
		TextSize = 13,
		ZIndex = 31,
		Parent = stage,
	})

	-- The catalog panel.
	local sheet = Kit.panel({ Name = "Panel", ZIndex = 30, Parent = root })
	Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 2, Transparency = 0.3 }).Parent = sheet

	local title = Kit.label("Dressing Room", { TextSize = 22, Font = Theme.FontBold, Size = UDim2.new(0, 190, 0, 30), ZIndex = 31, Parent = sheet })
	local DEFAULT_HINT = "Try anything on. Buy what you love with Robux."
	local hint = Kit.label(DEFAULT_HINT, {
		TextColor3 = Theme.SubText,
		TextSize = 13,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Position = UDim2.new(0, 196, 0, 6),
		Size = UDim2.new(1, -240, 0, 20),
		ZIndex = 31,
		Parent = sheet,
	})
	local hintToken = 0
	local hintFits = true
	local function flash(text: string)
		hintToken += 1
		local token = hintToken
		hint.Text = text
		hint.TextColor3 = Theme.Warn
		hint.Visible = true
		task.delay(5, function()
			if token == hintToken then
				hint.Text = DEFAULT_HINT
				hint.TextColor3 = Theme.SubText
				hint.Visible = hintFits
			end
		end)
	end

	local close: () -> ()
	Kit.button("X", function()
		close()
	end, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, -2),
		Size = UDim2.new(0, 36, 0, 34),
		BackgroundColor3 = Theme.PanelLight,
		TextColor3 = Theme.Text,
		ZIndex = 32,
		Parent = sheet,
	})

	-- Shop / My look / Saved
	local segments = Kit.new("Frame", {
		BackgroundColor3 = Theme.Background,
		Position = UDim2.new(0, 0, 0, 38),
		Size = UDim2.new(1, 0, 0, 34),
		ZIndex = 31,
		Parent = sheet,
	}, { Kit.corner(10), Kit.padding(3) })
	local BODY_TOP = 80
	local function view(name: string): Frame
		return Kit.new("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 0, 0, BODY_TOP),
			Size = UDim2.new(1, 0, 1, -BODY_TOP),
			Visible = false,
			ZIndex = 31,
			Parent = sheet,
		})
	end
	local shopView = view("Shop")
	local lookView = view("MyLook")
	local savedView = view("Saved")
	local currentView = "shop"
	local segmentButtons: { [string]: TextButton } = {}

	-- Shop view ---------------------------------------------------------------------------
	local tabs = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 34),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		ZIndex = 31,
		Parent = shopView,
	}, { Kit.list(6, true) })

	local searchRow = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 40),
		Size = UDim2.new(1, 0, 0, 34),
		ZIndex = 31,
		Parent = shopView,
	})
	local searchBox = Kit.new("TextBox", {
		PlaceholderText = "🔍  Search the catalog",
		Text = "",
		ClearTextOnFocus = false,
		BackgroundColor3 = Theme.PanelLight,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.SubText,
		Font = Theme.Font,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -128, 1, 0),
		ZIndex = 31,
		Parent = searchRow,
	}, { Kit.corner(8), Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }) })
	local sortButton = Kit.button(`↕ {SORTS[1].name}`, function() end, {
		BackgroundColor3 = Theme.PanelLight,
		TextColor3 = Theme.Text,
		TextSize = 13,
		Position = UDim2.new(1, -120, 0, 0),
		Size = UDim2.new(0, 120, 1, 0),
		ZIndex = 31,
		Parent = searchRow,
	})

	local GRID_TOP = 82
	local grid = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, GRID_TOP),
		Size = UDim2.new(1, 0, 1, -(GRID_TOP + 22)),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 31,
		Parent = shopView,
	})
	local gridLayout = Kit.new("UIGridLayout", {
		CellSize = UDim2.new(0, 128, 0, 178),
		CellPadding = UDim2.new(0, 8, 0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local statusLabel = Kit.label("", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = 13,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 31,
		Parent = shopView,
	})

	-- My look view ------------------------------------------------------------------------
	local baseRow = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), ZIndex = 31, Parent = lookView })
	local lookList = Kit.new("ScrollingFrame", {
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 36),
		Size = UDim2.new(1, 0, 1, -(36 + 84)),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ZIndex = 31,
		Parent = lookView,
	}, { Kit.corner(10), Kit.list(6), Kit.padding(6) })
	local lookActions = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 78),
		ZIndex = 31,
		Parent = lookView,
	})

	-- Saved view --------------------------------------------------------------------------
	local savedList = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ZIndex = 31,
		Parent = savedView,
	}, { Kit.list(6) })

	-- State -------------------------------------------------------------------------------
	local state: any = nil
	local tabIndex = 1
	local sortIndex = 1
	local lookKey = "" -- the worn ids, to notice when "For you" is out of date
	local picksKey: string? = nil -- lookKey the "For you" list was built for

	type Card = { button: ImageButton, stroke: UIStroke, badge: TextLabel, price: TextLabel, priceText: string }
	type Feed = {
		next: () -> ({ any }, boolean),
		entries: { any },
		ids: { [number]: boolean },
		done: boolean,
		loading: boolean,
		failedAt: number?,
		note: string?,
		empty: string,
	}
	local feed: Feed? = nil
	local cards: { [number]: Card } = {}

	local function wearingIds(): { [number]: boolean }
		local ids = {}
		if state then
			for _, item in state.look.items do
				ids[item.id] = true
			end
		end
		return ids
	end

	local function updateStatus()
		local f = feed
		if not f then
			statusLabel.Text = ""
		elseif f.loading then
			statusLabel.Text = if #f.entries == 0 then "Looking..." else "Loading more..."
		elseif f.failedAt then
			statusLabel.Text = "The catalog didn't answer. Scroll down to try again."
		elseif f.done and #f.entries == 0 then
			statusLabel.Text = f.empty
		else
			statusLabel.Text = f.note or ""
		end
	end

	local function styleCard(card: Card, isOn: boolean)
		card.stroke.Color = if isOn then Theme.Accent else Theme.PanelLight
		card.stroke.Thickness = if isOn then 3 else 1
		card.badge.Visible = isOn
		card.price.Text = if isOn then "Wearing · tap to take off" else card.priceText
		card.price.TextColor3 = if isOn then Theme.Accent else Theme.SubText
	end

	local function refreshWearing()
		local wearing = wearingIds()
		for id, card in cards do
			styleCard(card, wearing[id] == true)
		end
	end

	local function addCard(entry: any, order: number)
		local id = entry.Id
		local button = Kit.new("ImageButton", {
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			LayoutOrder = order,
			ZIndex = 31,
			Parent = grid,
		}, { Kit.corner(10) })
		local stroke = Kit.new("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = button })
		local thumb = Kit.new("ImageLabel", {
			BackgroundColor3 = THUMB_BG,
			BorderSizePixel = 0,
			Image = DressingRoom.thumbnail(id, 150),
			ScaleType = Enum.ScaleType.Fit,
			Position = UDim2.new(0, 5, 0, 5),
			Size = UDim2.new(1, -10, 1, -52),
			ZIndex = 32,
			Parent = button,
		}, { Kit.corner(8) })
		local badge = Kit.label("✓ On", {
			BackgroundColor3 = Theme.Accent,
			BackgroundTransparency = 0,
			TextColor3 = Theme.AccentText,
			Font = Theme.FontBold,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 4, 0, 4),
			Size = UDim2.new(0, 44, 0, 18),
			Visible = false,
			ZIndex = 33,
			Parent = thumb,
		})
		Kit.corner(9).Parent = badge
		Kit.label(tostring(entry.Name or "Item"), {
			TextSize = 12,
			Font = Theme.FontBold,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.new(0, 6, 1, -45),
			Size = UDim2.new(1, -12, 0, 26),
			ZIndex = 32,
			Parent = button,
		})
		local text = priceText(entry.Price, entry.Price ~= nil)
		local price = Kit.label(text, {
			TextSize = 12,
			Font = Theme.FontBold,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Position = UDim2.new(0, 6, 1, -19),
			Size = UDim2.new(1, -12, 0, 16),
			ZIndex = 32,
			Parent = button,
		})
		local card: Card = { button = button, stroke = stroke, badge = badge, price = price, priceText = text }
		cards[id] = card
		styleCard(card, wearingIds()[id] == true)
		button.Activated:Connect(function()
			local isOn = wearingIds()[id] == true
			send({ action = if isOn then "takeOff" else "tryOn", assetId = id })
		end)
	end

	local loadMore: () -> ()

	-- Infinite scroll: fetch the next page when you're within two rows of the end, and keep
	-- going until the window is full.
	local function nearEnd(): boolean
		local cell = gridLayout.AbsoluteCellSize.Y + 8
		local remaining = grid.AbsoluteCanvasSize.Y - (grid.CanvasPosition.Y + grid.AbsoluteWindowSize.Y)
		return remaining < cell * 2
	end
	local checkQueued = false
	local function checkScroll()
		if checkQueued then
			return
		end
		checkQueued = true
		task.defer(function()
			checkQueued = false
			if root.Visible and currentView == "shop" and nearEnd() then
				loadMore()
			end
		end)
	end
	grid:GetPropertyChangedSignal("CanvasPosition"):Connect(checkScroll)
	grid:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(checkScroll)

	function loadMore()
		local f = feed
		if not f or f.loading or f.done or #f.entries >= MAX_RESULTS then
			return
		end
		if f.failedAt and os.clock() - f.failedAt < RETRY_SECONDS then
			return
		end
		f.loading = true
		updateStatus()
		task.spawn(function()
			local ok, entries, done = pcall(f.next)
			if feed ~= f then
				return
			end
			f.loading = false
			if not ok then
				warn(`[GameNight] catalog failed: {entries}`)
				f.failedAt = os.clock()
			else
				f.failedAt = nil
				for _, entry in entries :: { any } do
					if type(entry.Id) == "number" and not f.ids[entry.Id] and #f.entries < MAX_RESULTS then
						f.ids[entry.Id] = true
						table.insert(f.entries, entry)
						addCard(entry, #f.entries)
					end
				end
				f.done = done == true
			end
			updateStatus()
			checkScroll()
		end)
	end

	local function startFeed(next: () -> ({ any }, boolean), empty: string, note: string?)
		Kit.clear(grid)
		cards = {}
		grid.CanvasPosition = Vector2.zero
		feed = { next = next, entries = {}, ids = {}, done = false, loading = false, empty = empty, note = note }
		loadMore()
	end

	local function searchFeed(category: any, keyword: string, sortKey: string): () -> ({ any }, boolean)
		local pages: any = nil
		return function()
			if not pages then
				pages = searchCatalog({ types = category.types, keyword = keyword, sort = sortKey })
			else
				pages:AdvanceToNextPageAsync()
			end
			return pageEntries(pages), pages.IsFinished
		end
	end

	-- "For you": similar items for a few worn things at a time, then the best sellers from
	-- the creators you wear most. See shared/Recommendations.
	local function picksFeed(): (() -> ({ any }, boolean), boolean)
		local tried = {}
		local lookItems = if state then state.look.items else {}
		for _, item in lookItems do
			table.insert(tried, { id = item.id, t = item.t })
		end
		local seeds = Recommendations.seeds(tried, ownSeeds(), DressingRoom.Types)
		local exclude = wearingIds()
		local creators = Recommendations.topCreators(lookItems, 3)
		local cursor = 1
		local creatorIndex = 1
		local creatorPages: any = nil
		local creatorPagesRead = 0
		local function next(): ({ any }, boolean)
			if cursor <= #seeds then
				local batch = {}
				for i = cursor, math.min(#seeds, cursor + Recommendations.SEEDS_PER_BATCH - 1) do
					table.insert(batch, seeds[i])
				end
				cursor += #batch
				local merged = Recommendations.merge(similarLists(batch), exclude, creators, 60)
				for _, pick in merged do
					exclude[pick.Id] = true
				end
				return merged, cursor > #seeds and #creators == 0
			end
			if creatorIndex <= #creators then
				if not creatorPages then
					creatorPages = searchCatalog({ types = ALL_TYPES, sort = "Bestselling", creator = creators[creatorIndex] })
				else
					creatorPages:AdvanceToNextPageAsync()
				end
				creatorPagesRead += 1
				local entries = pageEntries(creatorPages, exclude)
				for _, e in entries do
					exclude[e.Id] = true
				end
				if creatorPages.IsFinished or creatorPagesRead >= 3 then
					creatorIndex += 1
					creatorPages, creatorPagesRead = nil, 0
				end
				return entries, creatorIndex > #creators
			end
			return {}, true
		end
		return next, #seeds > 0
	end

	-- Asks the server for the Trending list and waits (up to 5 seconds) for the answer.
	-- If it doesn't come, the last list we got is used.
	local trendingPayload: any = nil
	local trendingWaiters: { (any) -> () } = {}
	local function fetchTrending(): any
		local thread = coroutine.running()
		local done = false
		local function finish(payload: any)
			if not done then
				done = true
				task.spawn(thread, payload)
			end
		end
		table.insert(trendingWaiters, finish)
		send({ action = "trending" })
		task.delay(5, function()
			finish(trendingPayload)
		end)
		return coroutine.yield()
	end

	-- "Trending": what Game Night players wear the most (the server keeps count), then items
	-- similar to the top ones, then Popular's best sellers.
	local function trendingFeed(): () -> ({ any }, boolean)
		local items: { any }? = nil
		local listIndex = 1
		local seeds: { Recommendations.Seed } = {}
		local seedCursor = 1
		local exclude: { [number]: boolean } = {}
		local popular: any = nil
		local function next(): ({ any }, boolean)
			if not items then
				local list = Trending.fromServer(fetchTrending())
				items = list
				for i = 1, math.min(Trending.SIMILAR_SEEDS, #list) do
					table.insert(seeds, { id = list[i].id, t = list[i].t })
				end
			end
			local list = items :: { any }
			if listIndex <= #list then
				local ids = {}
				for i = listIndex, math.min(#list, listIndex + DressingRoom.SearchPageSize - 1) do
					table.insert(ids, list[i].id)
				end
				local details = itemDetails(ids)
				local out = {}
				for i, id in ids do
					local item = list[listIndex + i - 1]
					exclude[id] = true
					table.insert(out, details[id] or { Id = id, Name = item.name or "Item" })
				end
				listIndex += #ids
				return out, false
			end
			if seedCursor <= #seeds then
				local batch = {}
				for i = seedCursor, math.min(#seeds, seedCursor + Recommendations.SEEDS_PER_BATCH - 1) do
					table.insert(batch, seeds[i])
				end
				seedCursor += #batch
				local merged = Recommendations.merge(similarLists(batch), exclude, {}, 60)
				for _, pick in merged do
					exclude[pick.Id] = true
				end
				return merged, false
			end
			if not popular then
				popular = searchCatalog({ types = DressingRoom.Categories[1].types, sort = "Bestselling" })
			else
				popular:AdvanceToNextPageAsync()
			end
			return pageEntries(popular, exclude), popular.IsFinished
		end
		return next
	end

	local function runSearch()
		local tab = TABS[tabIndex]
		if tab == TRENDING then
			startFeed(trendingFeed(), "Nothing trending yet.", "Most worn in Game Night, then similar items")
		elseif tab == FOR_YOU then
			picksKey = lookKey
			local next, hasSeeds = picksFeed()
			if hasSeeds then
				startFeed(next, "Nothing to suggest yet. Try a few things on.", "Picked from what you're wearing")
			else
				startFeed(searchFeed(DressingRoom.Categories[1], searchBox.Text, SORTS[sortIndex].key), "Nothing found.", "Try a few things on and this tab learns your style")
			end
		else
			startFeed(searchFeed(tab, searchBox.Text, SORTS[sortIndex].key), "Nothing found. Try another search.")
		end
	end

	local renderTabs: () -> ()
	sortButton.Activated:Connect(function()
		sortIndex = sortIndex % #SORTS + 1
		sortButton.Text = `↕ {SORTS[sortIndex].name}`
		if TABS[tabIndex].special then
			tabIndex = POPULAR_INDEX -- sorting is for browsing; For you and Trending have their own order
			renderTabs()
		end
		runSearch()
	end)
	searchBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			if TABS[tabIndex].special and searchBox.Text ~= "" then
				tabIndex = POPULAR_INDEX
				renderTabs()
			end
			runSearch()
		end
	end)

	function renderTabs()
		Kit.clear(tabs)
		for index, tab in TABS do
			local selected = index == tabIndex
			local b = Kit.button(tab.name, function()
				-- Tapping For you (after a change) or Trending again refreshes it.
				if tabIndex == index and not (tab == FOR_YOU and picksKey ~= lookKey) and tab ~= TRENDING then
					return
				end
				tabIndex = index
				if tab.special then
					searchBox.Text = ""
				end
				renderTabs()
				runSearch()
			end, {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 1, -4),
				TextSize = 13,
				BackgroundColor3 = if selected then Theme.Accent else Theme.PanelLight,
				TextColor3 = if selected then Theme.AccentText else Theme.Text,
				LayoutOrder = index,
				ZIndex = 32,
				Parent = tabs,
			})
			Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }).Parent = b
			Kit.corner(15).Parent = b
		end
	end

	-- Grid cells: as many columns as fit, square thumbnails.
	local function fitGrid()
		local w = grid.AbsoluteSize.X - 6
		if w <= 0 then
			return
		end
		local gap = 8
		local minCell = if compact then 100 else 124
		local cols = math.max(2, math.floor((w + gap) / (minCell + gap)))
		local cellW = math.floor((w - gap * (cols - 1)) / cols)
		gridLayout.CellSize = UDim2.new(0, cellW, 0, cellW + 42)
	end
	grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitGrid)

	local function smallButton(text: string, color: Color3, onClick: () -> (), props: { [string]: any })
		local merged = {
			BackgroundColor3 = color,
			TextColor3 = if color == Theme.PanelLight or color == Theme.Panel then Theme.Text else Theme.AccentText,
			TextSize = 13,
			Size = UDim2.new(0, 60, 0, 28),
			ZIndex = 32,
		}
		for k, v in props do
			merged[k] = v
		end
		return Kit.button(text, onClick, merged)
	end

	local function saveToRoblox()
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local ok, err = pcall(function()
			AvatarEditorService:PromptSaveAvatar(humanoid:GetAppliedDescription(), humanoid.RigType)
		end)
		if not ok then
			warn(`[GameNight] PromptSaveAvatar failed: {err}`)
			flash("Roblox couldn't open the save prompt. Try again in a moment.")
		end
	end

	local function renderLook()
		Kit.clear(baseRow)
		Kit.clear(lookList)
		Kit.clear(lookActions)
		local base = if state then state.look.base else "mine"
		Kit.label("Start from", { TextSize = 13, TextColor3 = Theme.SubText, Size = UDim2.new(0, 80, 1, 0), ZIndex = 32, Parent = baseRow })
		for i, option in { { key = "mine", name = "My avatar" }, { key = "blank", name = "Blank" } } do
			local selected = base == option.key
			smallButton(option.name, if selected then Theme.Accent else Theme.PanelLight, function()
				send({ action = "setBase", base = option.key })
			end, {
				Position = UDim2.new((i - 1) * 0.5, 80 - (i - 1) * 40 + (if i == 2 then 4 else 0), 0, 0),
				Size = UDim2.new(0.5, -44, 1, 0),
				Parent = baseRow,
			})
		end

		local items = if state then state.look.items else {}
		if #items == 0 then
			Kit.label("Nothing on yet. Tap items in the Shop to try them on. Your look shows everywhere in Game Night.", {
				TextColor3 = Theme.SubText,
				TextSize = 14,
				Size = UDim2.new(1, -4, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				ZIndex = 32,
				Parent = lookList,
			})
		end
		for index, item in items do
			local row = Kit.new("Frame", {
				BackgroundColor3 = Theme.PanelLight,
				BorderSizePixel = 0,
				Size = UDim2.new(1, -4, 0, 52),
				LayoutOrder = index,
				ZIndex = 32,
				Parent = lookList,
			}, { Kit.corner(8) })
			Kit.new("ImageLabel", {
				BackgroundColor3 = THUMB_BG,
				BorderSizePixel = 0,
				Image = DressingRoom.thumbnail(item.id, 150),
				Position = UDim2.new(0, 4, 0, 4),
				Size = UDim2.new(0, 44, 0, 44),
				ZIndex = 33,
				Parent = row,
			}, { Kit.corner(6) })
			local buyable = not item.owned and item.forSale
			local rightSpace = if buyable then 108 else 40
			Kit.label(item.name, {
				TextSize = 13,
				Font = Theme.FontBold,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.new(0, 54, 0, 5),
				Size = UDim2.new(1, -(54 + rightSpace), 0, 20),
				ZIndex = 33,
				Parent = row,
			})
			Kit.label(if item.owned then `{item.kind} · Owned` else `{item.kind} · {priceText(item.price, item.forSale)}`, {
				TextSize = 12,
				TextColor3 = if item.owned then Theme.Good else Theme.SubText,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.new(0, 54, 0, 27),
				Size = UDim2.new(1, -(54 + rightSpace), 0, 18),
				ZIndex = 33,
				Parent = row,
			})
			if buyable then
				smallButton(if item.price == 0 then "Get" else `R$ {item.price}`, ROBUX_COLOR, function()
					send({ action = "buy", assetId = item.id })
				end, { Position = UDim2.new(1, -104, 0.5, -14), Size = UDim2.new(0, 64, 0, 28), Parent = row })
			end
			smallButton("✕", Theme.Panel, function()
				send({ action = "takeOff", assetId = item.id })
			end, { Position = UDim2.new(1, -34, 0.5, -14), Size = UDim2.new(0, 30, 0, 28), Parent = row })
		end

		local count = if state then state.unownedCount else 0
		if count > 0 then
			Kit.button(`Buy the whole look · R$ {state.unownedRobux} ({count})`, function()
				send({ action = "buyAll" })
			end, { BackgroundColor3 = ROBUX_COLOR, TextSize = 14, Size = UDim2.new(1, 0, 0, 36), ZIndex = 32, Parent = lookActions })
		elseif #items > 0 then
			Kit.label("You own everything for sale in this look", {
				TextColor3 = Theme.Good,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 36),
				ZIndex = 32,
				Parent = lookActions,
			})
		end
		Kit.button("↺ My own avatar", function()
			send({ action = "reset" })
		end, {
			BackgroundColor3 = Theme.PanelLight,
			TextColor3 = Theme.Text,
			TextSize = 13,
			Position = UDim2.new(0, 0, 0, 42),
			Size = UDim2.new(0.5, -4, 0, 36),
			ZIndex = 32,
			Parent = lookActions,
		})
		local canSave = state and state.allOwned
		Kit.button(if canSave then "Save to Roblox avatar" else "Own all to save to Roblox", function()
			if canSave then
				saveToRoblox()
			else
				flash("Buy or own every item in the look first, then you can save it to your Roblox avatar.")
			end
		end, {
			BackgroundColor3 = if canSave then Theme.Good else Theme.Panel,
			TextColor3 = if canSave then Theme.AccentText else Theme.SubText,
			TextSize = 13,
			Position = UDim2.new(0.5, 4, 0, 42),
			Size = UDim2.new(0.5, -4, 0, 36),
			ZIndex = 32,
			Parent = lookActions,
		})
	end

	local function renderSaved()
		Kit.clear(savedList)
		if not state then
			return
		end
		local order = 1
		Kit.label(`{#state.saved} of {state.slots} looks saved`, { TextSize = 13, TextColor3 = Theme.SubText, LayoutOrder = order, ZIndex = 32, Parent = savedList })
		order += 1
		if #state.saved < state.slots then
			Kit.button("＋ Save this look", function()
				send({ action = "save", slot = "new" })
			end, { TextSize = 14, Size = UDim2.new(1, -6, 0, 36), LayoutOrder = order, ZIndex = 32, Parent = savedList })
			order += 1
		end
		for slot, saved in state.saved do
			local row = Kit.new("Frame", {
				BackgroundColor3 = Theme.PanelLight,
				BorderSizePixel = 0,
				Size = UDim2.new(1, -6, 0, 52),
				LayoutOrder = order,
				ZIndex = 32,
				Parent = savedList,
			}, { Kit.corner(8) })
			order += 1
			-- Up to three thumbnails of what's in it.
			local thumbs = 0
			for i, id in saved.preview or {} do
				if i > 3 then
					break
				end
				thumbs = i
				Kit.new("ImageLabel", {
					BackgroundColor3 = THUMB_BG,
					BorderSizePixel = 0,
					Image = DressingRoom.thumbnail(id, 150),
					Position = UDim2.new(0, 4 + (i - 1) * 30, 0, 9),
					Size = UDim2.new(0, 34, 0, 34),
					ZIndex = 33 + i,
					Parent = row,
				}, { Kit.corner(17) })
			end
			local textLeft = 8 + math.max(thumbs, 0) * 30 + (if thumbs > 0 then 10 else 0)
			Kit.label(`{saved.name}\n{saved.count} items`, {
				TextSize = 12,
				Position = UDim2.new(0, textLeft, 0, 0),
				Size = UDim2.new(1, -(textLeft + 166), 1, 0),
				TextWrapped = true,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 33,
				Parent = row,
			})
			smallButton("Wear", Theme.Accent, function()
				send({ action = "load", slot = slot })
			end, { Position = UDim2.new(1, -162, 0.5, -14), Size = UDim2.new(0, 52, 0, 28), Parent = row })
			smallButton("Save", Theme.Panel, function()
				send({ action = "save", slot = slot })
			end, { Position = UDim2.new(1, -106, 0.5, -14), Size = UDim2.new(0, 50, 0, 28), Parent = row })
			smallButton("Delete", Theme.Bad, function()
				send({ action = "delete", slot = slot })
			end, { Position = UDim2.new(1, -52, 0.5, -14), Size = UDim2.new(0, 48, 0, 28), Parent = row })
		end
		if state.slots < state.maxSlots then
			local affordable = state.gems >= state.slotPrice
			Kit.button(`+1 look slot · {state.slotPrice} {Economy.GemsName}`, function()
				send({ action = "buySlot" })
			end, {
				BackgroundColor3 = if affordable then GEM_COLOR else Theme.Panel,
				TextColor3 = if affordable then Theme.AccentText else Theme.SubText,
				TextSize = 14,
				Size = UDim2.new(1, -6, 0, 36),
				LayoutOrder = order,
				ZIndex = 32,
				Parent = savedList,
			})
		end
	end

	local function renderSegments()
		Kit.clear(segments)
		local count = if state then #state.look.items else 0
		local options = {
			{ key = "shop", name = "Shop" },
			{ key = "look", name = if count > 0 then `My look · {count}` else "My look" },
			{ key = "saved", name = if state then `Saved · {#state.saved}/{state.slots}` else "Saved" },
		}
		for i, option in options do
			local selected = option.key == currentView
			segmentButtons[option.key] = Kit.button(option.name, function()
				currentView = option.key
				shopView.Visible = currentView == "shop"
				lookView.Visible = currentView == "look"
				savedView.Visible = currentView == "saved"
				renderSegments()
				if currentView == "shop" then
					checkScroll()
				end
			end, {
				Position = UDim2.new((i - 1) / 3, if i > 1 then 2 else 0, 0, 0),
				Size = UDim2.new(1 / 3, -2, 1, 0),
				BackgroundColor3 = if selected then Theme.PanelLight else Theme.Background,
				BackgroundTransparency = if selected then 0 else 1,
				TextColor3 = if selected then Theme.Text else Theme.SubText,
				TextSize = if compact then 13 else 14,
				ZIndex = 32,
				Parent = segments,
			})
		end
		shopView.Visible = currentView == "shop"
		lookView.Visible = currentView == "look"
		savedView.Visible = currentView == "saved"
	end

	local function renderState()
		renderSegments()
		renderLook()
		renderSaved()
		refreshWearing()
	end

	-- Screen layout: panel and stage, and phone sizes.
	local function relayout(info: Layout.Info)
		compact = info.compact
		local split = AvatarFraming.split(info.width, info.height, info.top, info.left, info.right, info.bottom)
		sheet.Position = UDim2.fromOffset(split.panel.x, split.panel.y)
		sheet.Size = UDim2.fromOffset(split.panel.w, split.panel.h)
		stage.Position = UDim2.fromOffset(split.stage.x, split.stage.y)
		stage.Size = UDim2.fromOffset(split.stage.w, split.stage.h)
		cam.setStage(split.stage)
		title.TextSize = if compact then 18 else 22
		hintFits = split.panel.w >= 470
		hint.Visible = hintFits or hint.TextColor3 == Theme.Warn
		stageHint.Visible = split.stage.w >= 240
		if split.portrait then
			-- Zoom buttons go across the stage's right edge, middle height.
			zoomPill.AnchorPoint = Vector2.new(1, 0.5)
			zoomPill.Position = UDim2.new(1, -4, 0.5, 0)
		else
			zoomPill.AnchorPoint = Vector2.new(1, 1)
			zoomPill.Position = UDim2.new(1, -4, 1, -4)
		end
		renderSegments()
		fitGrid()
	end

	-- Stage input: drag to spin the avatar, two fingers to pinch, mouse wheel to zoom.
	local mouseDown = false
	local lastMouse = Vector2.zero
	local touches: { [InputObject]: Vector2 } = {}
	local function touchList(): { Vector2 }
		local list = {}
		for _, pos in touches do
			table.insert(list, pos)
		end
		return list
	end
	stage.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseDown = true
			lastMouse = Vector2.new(input.Position.X, input.Position.Y)
		elseif input.UserInputType == Enum.UserInputType.Touch then
			touches[input] = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	stage.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			cam.zoomBy(input.Position.Z * 0.5)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not cam.isActive() then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement and mouseDown then
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			local delta = pos - lastMouse
			lastMouse = pos
			cam.turn(delta.X, delta.Y)
		elseif input.UserInputType == Enum.UserInputType.Touch and touches[input] then
			local before = touchList()
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			local old = touches[input]
			touches[input] = pos
			if #before == 1 then
				local delta = pos - old
				cam.turn(delta.X, delta.Y)
			elseif #before >= 2 then
				local after = touchList()
				local d0 = (before[1] - before[2]).Magnitude
				local d1 = (after[1] - after[2]).Magnitude
				if d0 > 10 and d1 > 10 then
					cam.setZoom(cam.getZoom() * d0 / d1)
				end
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseDown = false
		elseif input.UserInputType == Enum.UserInputType.Touch then
			touches[input] = nil
		end
	end)

	-- The walk-up prompts in the corner hide while you're in the window.
	local function setPrompts(enabled: boolean)
		local lobby = workspace:FindFirstChild("Lobby")
		local corner = lobby and lobby:FindFirstChild("DressingCorner", true)
		if corner then
			for _, d in corner:GetDescendants() do
				if d:IsA("ProximityPrompt") and d.Name == "DressingRoomPrompt" then
					d.Enabled = enabled
				end
			end
		end
	end

	renderTabs()
	renderState()
	Layout.onChange(relayout)
	local searchedOnce = false

	close = function()
		if not root.Visible then
			return
		end
		root.Visible = false
		mouseDown = false
		touches = {}
		cam.exit()
		setPrompts(true)
	end

	local function open()
		if root.Visible then
			return
		end
		root.Visible = true
		cam.enter()
		setPrompts(false)
		stageHint.TextTransparency = 0
		task.delay(5, function()
			stageHint.TextTransparency = 0.6
		end)
		send({ action = "sync" })
		if not searchedOnce then
			searchedOnce = true
			-- Wait a moment for the look to arrive, so "For you" knows what you're wearing.
			task.delay(0.5, function()
				if feed == nil then
					runSearch()
				end
			end)
		elseif TABS[tabIndex] == FOR_YOU and picksKey ~= lookKey then
			runSearch()
		else
			checkScroll()
		end
	end

	return {
		root = root,
		open = open,
		close = close,
		isOpen = function(): boolean
			return root.Visible
		end,
		setTrending = function(payload: any)
			trendingPayload = payload
			local waiters = trendingWaiters
			trendingWaiters = {}
			for _, finish in waiters do
				finish(payload)
			end
		end,
		setState = function(newState: any)
			state = newState
			local ids = {}
			for _, item in newState.look.items do
				table.insert(ids, tostring(item.id))
			end
			lookKey = table.concat(ids, ",")
			renderState()
			if feed and TABS[tabIndex] == FOR_YOU and picksKey ~= nil and picksKey ~= lookKey then
				feed.note = "Tap ✨ For you again to update your picks"
				updateStatus()
			end
			if root.Visible and searchedOnce and feed == nil then
				runSearch()
			end
		end,
	}
end

return DressingRoomPanel
