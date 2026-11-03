-- The Dressing Room window: browse the Roblox catalog, try items on, buy them with Robux,
-- save looks, and save a fully owned look to your real Roblox avatar.
--
-- The client searches the catalog (AvatarEditorService) and shows results. Everything that
-- changes your avatar or spends anything goes to the server as a request with an asset ID.
-- Basic on purpose; the polish step restyles it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local AvatarEditorService = game:GetService("AvatarEditorService")

local DressingRoom = require(ReplicatedStorage.Shared.DressingRoom)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Kit = require(script.Parent.Kit)
local Theme = Kit.Theme

local DressingRoomPanel = {}

local GEM_COLOR = Color3.fromRGB(110, 220, 255)
local ROBUX_COLOR = Theme.Good

local SORTS = {
	{ key = "Relevance", name = "Top" },
	{ key = "Bestselling", name = "Best selling" },
	{ key = "PriceLowToHigh", name = "Cheapest" },
	{ key = "RecentlyCreated", name = "Newest" },
}

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

-- Runs a catalog search. Returns the CatalogPages object, or nil and an error.
local function searchCatalog(category: any, keyword: string, sortKey: string): (any, string?)
	local params = CatalogSearchParams.new()
	params.SearchKeyword = keyword
	local types = {}
	for _, typeId in category.types do
		local info = DressingRoom.Types[typeId]
		local item = info and enumItem(Enum.AvatarAssetType, info.search)
		if item then
			table.insert(types, item)
		end
	end
	params.AssetTypes = types
	params.IncludeOffSale = false
	local sort = enumItem(Enum.CatalogSortType, sortKey)
	if sort then
		params.SortType = sort :: any
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
		return nil, tostring(pages)
	end
	return pages
end

-- Live 3D preview of your own character, slowly turning.
local function createPreview(parent: Instance, isVisible: () -> boolean)
	local viewport = Kit.new("ViewportFrame", {
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -150),
		Ambient = Color3.fromRGB(200, 200, 210),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-0.4, -1, -0.6),
		Parent = parent,
	}, { Kit.corner(12) })
	local world = Kit.new("WorldModel", { Parent = viewport })
	local camera = Kit.new("Camera", { FieldOfView = 40, Parent = viewport })
	viewport.CurrentCamera = camera
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.6, -9.5), Vector3.new(0, 0.2, 0))

	local model: Model? = nil
	local angle = 0
	local pending = false

	local function rebuild()
		pending = false
		local character = Players.LocalPlayer.Character
		if model then
			model:Destroy()
			model = nil
		end
		if not character then
			return
		end
		local wasArchivable = character.Archivable
		character.Archivable = true
		local ok, clone = pcall(function()
			return character:Clone()
		end)
		character.Archivable = wasArchivable
		if not ok or not clone then
			return
		end
		for _, d in clone:GetDescendants() do
			if d:IsA("BaseScript") or d:IsA("ForceField") or d:IsA("Sound") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		local humanoid = clone:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
		clone:PivotTo(CFrame.Angles(0, angle, 0))
		clone.Parent = world
		model = clone
	end

	-- Accessories arrive one by one after ApplyDescription, so wait for them to settle.
	local function refresh()
		if pending then
			return
		end
		pending = true
		task.delay(0.6, rebuild)
	end

	local connections: { RBXScriptConnection } = {}
	local function watchCharacter(character: Model)
		for _, c in connections do
			c:Disconnect()
		end
		connections = {
			character.DescendantAdded:Connect(refresh),
			character.DescendantRemoving:Connect(refresh),
		}
		refresh()
	end
	Players.LocalPlayer.CharacterAdded:Connect(watchCharacter)
	if Players.LocalPlayer.Character then
		watchCharacter(Players.LocalPlayer.Character)
	end

	RunService.RenderStepped:Connect(function(dt)
		if model and isVisible() then
			angle = (angle + dt * 0.5) % (math.pi * 2)
			model:PivotTo(CFrame.Angles(0, angle, 0))
		end
	end)

	return { viewport = viewport, refresh = refresh }
end

function DressingRoomPanel.create(parent: Instance, send: (any) -> ())
	local root = Kit.panel({
		Name = "DressingRoom",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.96, 0.9),
		Visible = false,
		ZIndex = 30,
		Parent = parent,
	})
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(1120, 660) }).Parent = root
	Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 2 }).Parent = root

	Kit.label("Dressing Room", { TextSize = 24, Font = Theme.FontBold, Size = UDim2.new(0, 220, 0, 30), Parent = root })
	local hint = Kit.label("Try on anything. Buy what you love with Robux, it's yours on Roblox forever.", {
		TextColor3 = Theme.SubText,
		TextSize = 14,
		Position = UDim2.new(0, 220, 0, 6),
		Size = UDim2.new(1, -280, 0, 20),
		Parent = root,
	})
	Kit.button("X", function()
		root.Visible = false
	end, { BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, Size = UDim2.new(0, 36, 0, 32), Position = UDim2.new(1, -36, 0, 0), Parent = root })

	local BODY_TOP = 42
	local LEFT_W, RIGHT_W, GAP = 240, 290, 12

	-- Left column: preview and avatar actions -------------------------------------------
	local left = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, BODY_TOP),
		Size = UDim2.new(0, LEFT_W, 1, -BODY_TOP),
		Parent = root,
	})
	local preview = createPreview(left, function()
		return root.Visible
	end)

	local leftButtons = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 1, -140),
		Size = UDim2.new(1, 0, 0, 140),
		Parent = left,
	}, { Kit.list(6) })

	-- Middle column: catalog ----------------------------------------------------------
	local middle = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, LEFT_W + GAP, 0, BODY_TOP),
		Size = UDim2.new(1, -(LEFT_W + RIGHT_W + GAP * 2), 1, -BODY_TOP),
		Parent = root,
	})
	local tabs = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 38),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 3,
		Parent = middle,
	}, { Kit.list(6, true) })

	local searchRow = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(1, 0, 0, 34),
		Parent = middle,
	})
	local searchBox = Kit.new("TextBox", {
		PlaceholderText = "Search the catalog",
		Text = "",
		ClearTextOnFocus = false,
		BackgroundColor3 = Theme.PanelLight,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.SubText,
		Font = Theme.Font,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -230, 1, 0),
		Parent = searchRow,
	}, { Kit.corner(8), Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 10) }) })

	local grid = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 86),
		Size = UDim2.new(1, 0, 1, -86),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		Parent = middle,
	})

	-- Right column: your look and saved looks -------------------------------------------
	local right = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -RIGHT_W, 0, BODY_TOP),
		Size = UDim2.new(0, RIGHT_W, 1, -BODY_TOP),
		Parent = root,
	})
	local lookTitle = Kit.label("Your look", { Font = Theme.FontBold, TextSize = 18, Parent = right })
	local lookList = Kit.new("ScrollingFrame", {
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 26),
		Size = UDim2.new(1, 0, 0.5, -70),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		Parent = right,
	}, { Kit.corner(10), Kit.list(6), Kit.padding(6) })
	local buyAllHolder = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0.5, -38),
		Size = UDim2.new(1, 0, 0, 34),
		Parent = right,
	})
	local savedTitle = Kit.label("Saved looks", { Font = Theme.FontBold, TextSize = 18, Position = UDim2.new(0, 0, 0.5, 4), Parent = right })
	local savedList = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0.5, 30),
		Size = UDim2.new(1, 0, 0.5, -30),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		Parent = right,
	}, { Kit.list(6) })

	-- State -----------------------------------------------------------------------------
	local state: any = nil
	local categoryIndex = 1
	local sortIndex = 1
	local results: { any } = {}
	local pages: any = nil
	local searchToken = 0
	local loadingMore = false
	local statusText = ""

	local renderGrid: () -> ()

	local function wearingIds(): { [number]: boolean }
		local ids = {}
		if state then
			for _, item in state.look.items do
				ids[item.id] = true
			end
		end
		return ids
	end

	local function readPage(token: number)
		local ok, page = pcall(function()
			return pages:GetCurrentPage()
		end)
		if token ~= searchToken then
			return
		end
		if not ok then
			statusText = "The catalog didn't answer. Try again."
			return
		end
		for _, entry in page do
			if entry.ItemType == nil or entry.ItemType == "Asset" then
				table.insert(results, entry)
			end
		end
		statusText = if #results == 0 then "Nothing found. Try another search." else ""
	end

	local function runSearch()
		searchToken += 1
		local token = searchToken
		results = {}
		pages = nil
		statusText = "Searching..."
		renderGrid()
		task.spawn(function()
			local found, err = searchCatalog(DressingRoom.Categories[categoryIndex], searchBox.Text, SORTS[sortIndex].key)
			if token ~= searchToken then
				return
			end
			if not found then
				warn(`[GameNight] catalog search failed: {err}`)
				statusText = "The catalog didn't answer. Try again."
			else
				pages = found
				readPage(token)
			end
			renderGrid()
		end)
	end

	local function loadMore()
		if not pages or loadingMore or pages.IsFinished then
			return
		end
		loadingMore = true
		local token = searchToken
		task.spawn(function()
			local ok = pcall(function()
				pages:AdvanceToNextPageAsync()
			end)
			loadingMore = false
			if ok and token == searchToken then
				readPage(token)
				renderGrid()
			end
		end)
	end

	local sortButton = Kit.button(`Sort: {SORTS[sortIndex].name}`, function() end, {
		BackgroundColor3 = Theme.PanelLight,
		TextColor3 = Theme.Text,
		TextSize = 14,
		Position = UDim2.new(1, -130, 0, 0),
		Size = UDim2.new(0, 130, 1, 0),
		Parent = searchRow,
	})
	sortButton.Activated:Connect(function()
		sortIndex = sortIndex % #SORTS + 1
		sortButton.Text = `Sort: {SORTS[sortIndex].name}`
		runSearch()
	end)
	Kit.button("Search", runSearch, {
		TextSize = 14,
		Position = UDim2.new(1, -222, 0, 0),
		Size = UDim2.new(0, 86, 1, 0),
		Parent = searchRow,
	})
	searchBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			runSearch()
		end
	end)

	local function renderTabs()
		Kit.clear(tabs)
		for index, category in DressingRoom.Categories do
			local selected = index == categoryIndex
			Kit.button(category.name, function()
				categoryIndex = index
				renderTabs()
				runSearch()
			end, {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 0, 32),
				TextSize = 14,
				BackgroundColor3 = if selected then Theme.Accent else Theme.PanelLight,
				TextColor3 = if selected then Theme.AccentText else Theme.Text,
				LayoutOrder = index,
				Parent = tabs,
			})
		end
		for _, b in tabs:GetChildren() do
			if b:IsA("TextButton") then
				Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }).Parent = b
			end
		end
	end

	function renderGrid()
		for _, child in grid:GetChildren() do
			child:Destroy()
		end
		Kit.new("UIGridLayout", {
			CellSize = UDim2.new(0, 132, 0, 186),
			CellPadding = UDim2.new(0, 8, 0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}).Parent = grid
		local wearing = wearingIds()
		for index, entry in results do
			local id = entry.Id
			local isOn = wearing[id] == true
			local card = Kit.new("ImageButton", {
				BackgroundColor3 = Theme.PanelLight,
				BorderSizePixel = 0,
				AutoButtonColor = true,
				LayoutOrder = index,
				Parent = grid,
			}, { Kit.corner(10), Kit.padding(6) })
			Kit.new("UIStroke", { Color = if isOn then Theme.Accent else Theme.PanelLight, Thickness = if isOn then 3 else 1 }).Parent = card
			Kit.new("ImageLabel", {
				BackgroundColor3 = Color3.fromRGB(230, 230, 236),
				BorderSizePixel = 0,
				Image = DressingRoom.thumbnail(id, 150),
				Size = UDim2.new(1, 0, 0, 110),
				Parent = card,
			}, { Kit.corner(8) })
			Kit.label(tostring(entry.Name or "Item"), {
				TextSize = 13,
				Font = Theme.FontBold,
				TextWrapped = true,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextYAlignment = Enum.TextYAlignment.Top,
				Position = UDim2.new(0, 0, 0, 114),
				Size = UDim2.new(1, 0, 0, 32),
				Parent = card,
			})
			local price = entry.Price
			if price == nil then
				price = entry.LowestPrice
			end
			Kit.label(if isOn then "Wearing" else priceText(price, price ~= nil), {
				TextSize = 13,
				TextColor3 = if isOn then Theme.Accent else Theme.SubText,
				Position = UDim2.new(0, 0, 1, -18),
				Size = UDim2.new(1, 0, 0, 18),
				Parent = card,
			})
			card.Activated:Connect(function()
				send({ action = if isOn then "takeOff" else "tryOn", assetId = id })
			end)
		end
		if statusText ~= "" then
			Kit.label(statusText, { TextColor3 = Theme.SubText, LayoutOrder = 0, Parent = grid })
		elseif pages and not pages.IsFinished then
			Kit.button(if loadingMore then "Loading..." else "Load more", loadMore, {
				BackgroundColor3 = Theme.PanelLight,
				TextColor3 = Theme.Text,
				LayoutOrder = #results + 1,
				Parent = grid,
			})
		end
	end

	local function smallButton(text: string, color: Color3, onClick: () -> (), props: { [string]: any })
		local merged = {
			BackgroundColor3 = color,
			TextColor3 = if color == Theme.PanelLight or color == Theme.Panel then Theme.Text else Theme.AccentText,
			TextSize = 13,
			Size = UDim2.new(0, 60, 0, 26),
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
			hint.Text = "Roblox couldn't open the save prompt. Try again in a moment."
		end
	end

	local function renderLeft()
		Kit.clear(leftButtons)
		local base = if state then state.look.base else "mine"
		local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 1, Parent = leftButtons })
		for i, option in { { key = "mine", name = "My avatar" }, { key = "blank", name = "Blank" } } do
			local selected = base == option.key
			smallButton(option.name, if selected then Theme.Accent else Theme.PanelLight, function()
				send({ action = "setBase", base = option.key })
			end, { Position = UDim2.new((i - 1) * 0.5, if i == 2 then 3 else 0, 0, 0), Size = UDim2.new(0.5, -3, 1, 0), Parent = row })
		end
		Kit.label("Start your look from", { TextSize = 12, TextColor3 = Theme.SubText, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 0, Parent = leftButtons })
		Kit.button("Back to my own avatar", function()
			send({ action = "reset" })
		end, { BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, TextSize = 14, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 2, Parent = leftButtons })
		local canSave = state and state.allOwned
		Kit.button(if canSave then "Save to my Roblox avatar" else "Own every item to save it to Roblox", function()
			if canSave then
				saveToRoblox()
			end
		end, {
			BackgroundColor3 = if canSave then Theme.Good else Theme.Panel,
			TextColor3 = if canSave then Theme.AccentText else Theme.SubText,
			TextSize = 13,
			Size = UDim2.new(1, 0, 0, 32),
			LayoutOrder = 3,
			Parent = leftButtons,
		})
	end

	local function renderLook()
		Kit.clear(lookList)
		Kit.clear(buyAllHolder)
		local items = if state then state.look.items else {}
		lookTitle.Text = if #items > 0 then `Your look ({#items} items)` else "Your look"
		if #items == 0 then
			Kit.label("Tap an item to try it on. Looks show everywhere in Game Night.", {
				TextColor3 = Theme.SubText,
				TextSize = 14,
				Size = UDim2.new(1, -4, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Parent = lookList,
			})
		end
		for index, item in items do
			local row = Kit.new("Frame", {
				BackgroundColor3 = Theme.PanelLight,
				BorderSizePixel = 0,
				Size = UDim2.new(1, -4, 0, 52),
				LayoutOrder = index,
				Parent = lookList,
			}, { Kit.corner(8) })
			Kit.new("ImageLabel", {
				BackgroundColor3 = Color3.fromRGB(230, 230, 236),
				BorderSizePixel = 0,
				Image = DressingRoom.thumbnail(item.id, 150),
				Position = UDim2.new(0, 4, 0, 4),
				Size = UDim2.new(0, 44, 0, 44),
				Parent = row,
			}, { Kit.corner(6) })
			Kit.label(item.name, {
				TextSize = 13,
				Font = Theme.FontBold,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.new(0, 54, 0, 4),
				Size = UDim2.new(1, -150, 0, 20),
				Parent = row,
			})
			Kit.label(if item.owned then `{item.kind} · Owned` else `{item.kind} · {priceText(item.price, item.forSale)}`, {
				TextSize = 12,
				TextColor3 = if item.owned then Theme.Good else Theme.SubText,
				Position = UDim2.new(0, 54, 0, 26),
				Size = UDim2.new(1, -150, 0, 18),
				Parent = row,
			})
			if not item.owned and item.forSale then
				smallButton(if item.price == 0 then "Get" else `R$ {item.price}`, ROBUX_COLOR, function()
					send({ action = "buy", assetId = item.id })
				end, { Position = UDim2.new(1, -96, 0.5, -13), Size = UDim2.new(0, 62, 0, 26), Parent = row })
			end
			smallButton("X", Theme.Panel, function()
				send({ action = "takeOff", assetId = item.id })
			end, { Position = UDim2.new(1, -30, 0.5, -13), Size = UDim2.new(0, 26, 0, 26), Parent = row })
		end

		local count = if state then state.unownedCount else 0
		if count > 0 then
			Kit.button(`Buy the whole look · R$ {state.unownedRobux} ({count} items)`, function()
				send({ action = "buyAll" })
			end, { BackgroundColor3 = ROBUX_COLOR, TextSize = 14, Size = UDim2.new(1, 0, 1, 0), Parent = buyAllHolder })
		elseif #items > 0 then
			Kit.label("You own everything for sale in this look", { TextColor3 = Theme.Good, TextSize = 14, Size = UDim2.new(1, 0, 1, 0), Parent = buyAllHolder })
		end
	end

	local function renderSaved()
		Kit.clear(savedList)
		if not state then
			return
		end
		savedTitle.Text = `Saved looks ({#state.saved}/{state.slots})`
		local order = 1
		if #state.saved < state.slots then
			Kit.button("Save this look", function()
				send({ action = "save", slot = "new" })
			end, { TextSize = 14, Size = UDim2.new(1, -6, 0, 32), LayoutOrder = order, Parent = savedList })
			order += 1
		end
		for slot, saved in state.saved do
			local row = Kit.new("Frame", {
				BackgroundColor3 = Theme.PanelLight,
				BorderSizePixel = 0,
				Size = UDim2.new(1, -6, 0, 40),
				LayoutOrder = order,
				Parent = savedList,
			}, { Kit.corner(8) })
			order += 1
			Kit.label(`{saved.name} · {saved.count} items`, {
				TextSize = 13,
				Position = UDim2.new(0, 8, 0, 0),
				Size = UDim2.new(1, -170, 1, 0),
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = row,
			})
			smallButton("Wear", Theme.Accent, function()
				send({ action = "load", slot = slot })
			end, { Position = UDim2.new(1, -164, 0.5, -13), Size = UDim2.new(0, 52, 0, 26), Parent = row })
			smallButton("Save", Theme.Panel, function()
				send({ action = "save", slot = slot })
			end, { Position = UDim2.new(1, -108, 0.5, -13), Size = UDim2.new(0, 52, 0, 26), Parent = row })
			smallButton("Delete", Theme.Bad, function()
				send({ action = "delete", slot = slot })
			end, { Position = UDim2.new(1, -52, 0.5, -13), Size = UDim2.new(0, 48, 0, 26), Parent = row })
		end
		if state.slots < state.maxSlots then
			local affordable = state.gems >= state.slotPrice
			Kit.button(`+1 look slot · {state.slotPrice} {Economy.GemsName}`, function()
				send({ action = "buySlot" })
			end, {
				BackgroundColor3 = if affordable then GEM_COLOR else Theme.Panel,
				TextColor3 = if affordable then Theme.AccentText else Theme.SubText,
				TextSize = 14,
				Size = UDim2.new(1, -6, 0, 32),
				LayoutOrder = order,
				Parent = savedList,
			})
		end
	end

	local function renderAll()
		renderLeft()
		renderLook()
		renderSaved()
		renderGrid()
	end

	renderTabs()
	renderAll()
	local searchedOnce = false

	return {
		root = root,
		open = function()
			root.Visible = true
			preview.refresh()
			if not searchedOnce then
				searchedOnce = true
				runSearch()
			end
			send({ action = "sync" })
		end,
		close = function()
			root.Visible = false
		end,
		isOpen = function(): boolean
			return root.Visible
		end,
		setState = function(newState: any)
			state = newState
			if root.Visible then
				renderAll()
			end
		end,
	}
end

return DressingRoomPanel
