-- The shop window: your wallet and daily challenges, Gems & passes (Robux), the hub shop
-- (Gems), reaction packs (Gems, Coins or the Robux bundle) and one shop per kind of Coin. Basic on purpose; the polish step restyles it.
-- The server checks every purchase, this only asks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Economy)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local Reactions = require(ReplicatedStorage.Shared.Reactions)
local ReactionFx = require(script.Parent.ReactionFx)
local Kit = require(script.Parent.Kit)
local CoinConvertPanel = require(script.Parent.CoinConvertPanel)
local Analytics = require(script.Parent.Parent.Analytics)
local Theme = Kit.Theme

local ShopPanel = {}

local TIER_COLORS = {
	Common = Color3.fromRGB(176, 170, 204),
	Rare = Color3.fromRGB(54, 162, 235),
	Epic = Color3.fromRGB(153, 102, 255),
	Legendary = Color3.fromRGB(255, 196, 64),
}

local function gemPrice(item: ShopCatalog.Item, vip: boolean): number?
	-- Mirrors server/Core/Shop.gemPrice so the buttons show the real price.
	if item.notForSale or item.earnedOnly then
		return nil
	end
	local gems = item.gems
	if gems == nil and item.coins then
		gems = math.ceil(item.coins / Economy.CoinsPerGem)
	end
	if gems and vip then
		gems = math.ceil(gems * (1 - Economy.VipGemDiscount))
	end
	return gems
end

function ShopPanel.create(parent: Instance, sendEconomy: (any) -> (), sendPurchase: (any) -> ())
	local root = Kit.panel({
		Name = "Shop",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.85),
		BackgroundColor3 = Theme.Panel,
		Visible = false,
		ZIndex = 30,
		Parent = parent,
	})
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(820, 560) }).Parent = root
	Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 2 }).Parent = root

	local title = Kit.label("Shop", { TextSize = 24, Font = Theme.FontBold, Size = UDim2.new(1, -60, 0, 30), Parent = root })
	Kit.button("X", function()
		root.Visible = false
	end, { BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, Size = UDim2.new(0, 36, 0, 32), Position = UDim2.new(1, -36, 0, 0), Parent = root })

	local tabsFrame = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(0, 170, 1, -44),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 3,
		Parent = root,
	}, { Kit.list(6) })

	local content = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 184, 0, 44),
		Size = UDim2.new(1, -184, 1, -44),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		Parent = root,
	})

	local wallet: any = nil
	local tab = "wallet"
	local converter = CoinConvertPanel.create(parent, sendEconomy)

	local tabs = {
		{ key = "wallet", name = "Wallet & daily" },
		{ key = "robux", name = "Gems & passes" },
		{ key = "hub", name = "Hub shop" },
		{ key = "reactions", name = "😀 Reactions" },
	}
	-- Every coin kind, for the wallet list; only kinds with items get a shop tab.
	local coinKeys = {}
	for key in Economy.Coins do
		table.insert(coinKeys, key)
	end
	table.sort(coinKeys, function(a, b)
		return Economy.Coins[a].order < Economy.Coins[b].order
	end)
	local shopKeys = {}
	for _, key in coinKeys do
		if #ShopCatalog.forShop(key) > 0 then
			table.insert(shopKeys, key)
		end
	end
	for _, key in shopKeys do
		table.insert(tabs, { key = key, name = `{(string.gsub(Economy.coinName(key), " Coins$", ""))} shop` })
	end

	local render: () -> ()

	local function section(text: string, order: number)
		Kit.label(text, { Font = Theme.FontBold, TextSize = 18, LayoutOrder = order, Size = UDim2.new(1, -8, 0, 26), Parent = content })
	end

	local function line(text: string, order: number, color: Color3?)
		Kit.label(text, {
			TextColor3 = color or Theme.Text,
			LayoutOrder = order,
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = content,
		})
	end

	local function card(order: number, height: number): Frame
		return Kit.new("Frame", {
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -8, 0, height),
			LayoutOrder = order,
			Parent = content,
		}, { Kit.corner(10), Kit.padding(10) })
	end

	local function renderWallet()
		Kit.list(6).Parent = content
		section(`Level {wallet.level}  ({wallet.xp}/{wallet.xpNeeded} XP)`, 1)
		section("Balances", 2)
		line(`{wallet.gems} {Economy.GemsName}`, 3, Color3.fromRGB(110, 220, 255))
		-- Universal Coins (daily calendar) turn into any game's Coins.
		local universal = wallet.coins[Economy.UniversalCoin.key] or 0
		local universalRow = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 30), LayoutOrder = 3, Parent = content })
		Kit.label(`{universal} {Economy.UniversalCoin.name}`, { TextColor3 = Economy.UniversalCoin.color, Size = UDim2.new(1, -110, 1, 0), Parent = universalRow })
		if universal > 0 then
			Kit.button("Convert", function()
				converter.open(universal, nil)
			end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 100, 1, 0), TextSize = 14, Parent = universalRow })
		end
		local order = 4
		for _, key in coinKeys do
			line(`{wallet.coins[key] or 0} {Economy.coinName(key)}`, order, Economy.Coins[key].color)
			order += 1
		end
		section("Today", 20)
		line(`Login streak: day {wallet.loginStreak}`, 21)
		line(if wallet.firstWinDone then "First win of the day: done" else `First win of the day: +{Economy.FirstWinGems} {Economy.GemsName}`, 22)
		for i, challenge in wallet.challenges or {} do
			local status = if challenge.done then "Done" else `{challenge.progress}/{challenge.target}`
			line(`{challenge.text}  ({status})  +{Economy.ChallengeGems} {Economy.GemsName}`, 22 + i, if challenge.done then Theme.Good else Theme.Text)
		end
		if not wallet.saving then
			line("Progress isn't saving this session.", 40, Theme.Bad)
		end
		if wallet.studio then
			Kit.button("Studio test: free Gems and Coins", function()
				sendEconomy({ action = "studioGrant" })
			end, { LayoutOrder = 50, Size = UDim2.new(0, 280, 0, 34), BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, Parent = content })
			-- Passes can't be bought before they exist in the Creator Hub, so test their perks here.
			for i, key in { "vip", "partyHost" } do
				local on = wallet.passes and wallet.passes[key]
				Kit.button(`Studio test: {Economy.Passes[key].name} {if on then "ON" else "off"}`, function()
					sendEconomy({ action = "studioPass", key = key })
				end, { LayoutOrder = 50 + i, Size = UDim2.new(0, 280, 0, 34), BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, Parent = content })
			end
		end
	end

	local function robuxButton(parent: Instance, text: string, ready: boolean, onClick: () -> ())
		Kit.button(if ready then text else "Coming soon", function()
			if ready then
				onClick()
			end
		end, {
			BackgroundColor3 = if ready then Theme.Good else Theme.Panel,
			TextColor3 = if ready then Theme.AccentText else Theme.SubText,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.new(0, 130, 0, 34),
			Parent = parent,
		})
	end

	local function renderRobux()
		Kit.list(8).Parent = content
		local order = 1
		if wallet.starterAvailable then
			local pack = Economy.StarterPack
			local c = card(order, 70)
			Kit.label("Starter Pack (first 3 days only)", { Font = Theme.FontBold, Parent = c })
			Kit.label(`{pack.gems} Gems + Cozy Cabin table + nameplate`, { TextColor3 = Theme.SubText, TextSize = 14, Position = UDim2.new(0, 0, 0, 24), Size = UDim2.new(1, -140, 0, 20), Parent = c })
			robuxButton(c, `R$ {pack.robux}`, pack.productId ~= 0, function()
				sendPurchase({ action = "buyStarter" })
			end)
			order += 1
		end
		for _, pack in Economy.GemPacks do
			local c = card(order, 56)
			Kit.label(`{pack.gems} {Economy.GemsName}{if pack.bonus then `  ({pack.bonus})` else ""}`, { Font = Theme.FontBold, Size = UDim2.new(1, -140, 1, 0), Parent = c })
			robuxButton(c, `R$ {pack.robux}`, pack.productId ~= 0, function()
				sendPurchase({ action = "buyGems", key = pack.key })
			end)
			order += 1
		end
		for _, key in { "vip", "partyHost" } do
			local pass = Economy.Passes[key]
			local owned = wallet.passes and wallet.passes[key]
			local c = card(order, 40 + 18 * #pass.perks)
			Kit.label(pass.name, { Font = Theme.FontBold, Parent = c })
			Kit.label("• " .. table.concat(pass.perks, "\n• "), {
				TextColor3 = Theme.SubText,
				TextSize = 14,
				Position = UDim2.new(0, 0, 0, 24),
				Size = UDim2.new(1, -140, 0, 18 * #pass.perks),
				TextYAlignment = Enum.TextYAlignment.Top,
				Parent = c,
			})
			if owned then
				Kit.label("Owned", { TextColor3 = Theme.Good, Font = Theme.FontBold, TextXAlignment = Enum.TextXAlignment.Right, Parent = c })
			else
				robuxButton(c, `R$ {pass.robux}`, pass.gamePassId ~= 0, function()
					sendPurchase({ action = "buyPass", key = key })
				end)
			end
			order += 1
		end
	end

	local function renderItems(shop: string)
		Kit.new("UIGridLayout", {
			CellSize = UDim2.new(0, 190, 0, 150),
			CellPadding = UDim2.new(0, 8, 0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}).Parent = content
		local vip = wallet.vip == true
		local equipped = wallet.equipped and wallet.equipped[shop] or {}
		for index, item in ShopCatalog.forShop(shop) do
			if item.slot == "reactions" then
				continue -- on the Reactions tab
			end
			local c = Kit.new("Frame", { BackgroundColor3 = Theme.PanelLight, BorderSizePixel = 0, LayoutOrder = index, Parent = content }, { Kit.corner(10), Kit.padding(8) })
			Kit.new("UIStroke", { Color = TIER_COLORS[item.tier] or Theme.SubText, Thickness = 2 }).Parent = c
			Kit.label(item.name, { Font = Theme.FontBold, TextSize = 15, Size = UDim2.new(1, 0, 0, 36), TextYAlignment = Enum.TextYAlignment.Top, Parent = c })
			Kit.label(`{item.tier} {item.slot}{if item.earnedOnly then " · earned only" else ""}`, { TextSize = 12, TextColor3 = TIER_COLORS[item.tier] or Theme.SubText, Position = UDim2.new(0, 0, 0, 38), Size = UDim2.new(1, 0, 0, 16), Parent = c })

			if wallet.owned and wallet.owned[item.id] then
				local isOn = equipped[item.slot] == item.id
				Kit.button(if isOn then "Unequip" else "Equip", function()
					sendEconomy({ action = "equip", itemId = item.id })
				end, { BackgroundColor3 = if isOn then Theme.Panel else Theme.Good, TextColor3 = if isOn then Theme.Text else Theme.AccentText, Position = UDim2.new(0, 0, 1, -32), Size = UDim2.new(1, 0, 0, 32), Parent = c })
			else
				local buttons = {}
				if item.coins and shop ~= "hub" then
					table.insert(buttons, { text = `{item.coins} Coins`, currency = "coins", color = Economy.Coins[shop] and Economy.Coins[shop].color or Theme.Accent })
				end
				local gems = gemPrice(item, vip)
				if gems then
					table.insert(buttons, { text = `{gems} Gems`, currency = "gems", color = Color3.fromRGB(110, 220, 255) })
				end
				for i, b in buttons do
					Kit.button(b.text, function()
						sendEconomy({ action = "buy", itemId = item.id, currency = b.currency })
					end, {
						BackgroundColor3 = b.color,
						TextColor3 = Theme.AccentText,
						TextSize = 14,
						Position = UDim2.new(0, 0, 1, -32 - (#buttons - i) * 36),
						Size = UDim2.new(1, 0, 0, 32),
						Parent = c,
					})
				end
			end
		end
	end

	-- Reaction packs: tap any reaction to see it play in the preview on the left.
	local function renderReactions()
		Kit.list(8).Parent = content
		local vip = wallet.vip == true
		local ownedSet = wallet.owned or {}

		local function packCard(order: number, name: string, sub: string, ids: { string }, tierColor: Color3?): (Frame, Frame)
			local c = Kit.new("Frame", {
				BackgroundColor3 = Theme.PanelLight,
				BorderSizePixel = 0,
				Size = UDim2.new(1, -8, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = order,
				Parent = content,
			}, { Kit.corner(10), Kit.padding(10) })
			if tierColor then
				Kit.new("UIStroke", { Color = tierColor, Thickness = 2, Parent = c })
			end
			local preview = Kit.new("Frame", {
				Name = "Preview",
				BackgroundColor3 = Theme.Panel,
				BorderSizePixel = 0,
				ClipsDescendants = true,
				Size = UDim2.fromOffset(72, 72),
				Parent = c,
			}, { Kit.corner(12) })
			local middle = Kit.new("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(82, 0),
				Size = UDim2.new(1, -82 - 136, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Parent = c,
			}, { Kit.list(4) })
			Kit.label(name, { Font = Theme.FontBold, LayoutOrder = 1, Parent = middle })
			Kit.label(sub, { TextSize = 13, TextColor3 = tierColor or Theme.SubText, LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 16), Parent = middle })
			local icons = Kit.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 3,
				Parent = middle,
			})
			Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(34, 34), CellPadding = UDim2.fromOffset(4, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = icons })
			-- A still picture of the last reaction shown, so the thumbnail is never blank
			-- (before an animation starts, after it ends, or while the shop redraws).
			local still = Kit.label("", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.8, 0.8),
				Font = Theme.FontBold,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = preview,
			})
			local function setStill(reaction: Reactions.Reaction)
				still.Text = reaction.icon or reaction.text or reaction.label
				still.TextColor3 = if reaction.icon then Theme.Text else (reaction.color or Theme.Text)
				still.Size = if reaction.icon then UDim2.fromScale(0.62, 0.62) else UDim2.fromScale(0.9, 0.5)
			end
			local current: Frame? = nil
			local function show(reaction: Reactions.Reaction)
				if current then
					current:Destroy()
				end
				setStill(reaction)
				still.Visible = false
				local size = ReactionFx.size(reaction, 64)
				local scaleDown = math.min(1, 68 / size.X)
				local holder = Kit.new("Frame", {
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(size.X * scaleDown, size.Y * scaleDown),
					Parent = preview,
				})
				current = holder
				holder.Destroying:Once(function()
					if current == holder then
						current = nil
						still.Visible = true
					end
				end)
				ReactionFx.play(holder, reaction)
			end
			for i, id in ids do
				local reaction = Reactions.get(id)
				if reaction then
					local b = Kit.button(reaction.icon or "", function()
						show(reaction)
					end, {
						BackgroundColor3 = Theme.Panel,
						TextColor3 = reaction.color or Theme.Text,
						TextSize = 20,
						LayoutOrder = i,
						Parent = icons,
					})
					if not reaction.icon then
						-- Text reactions: the words, small.
						b.Text = reaction.text or reaction.label
						b.TextScaled = true
						b.Font = Theme.FontBold
						b.TextColor3 = Theme.Text
						Kit.new("UIStroke", { Color = reaction.color or Theme.Accent, Thickness = 1, Parent = b })
						Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 2), Parent = b })
					end
				end
			end
			local first = Reactions.get(ids[1])
			if first then
				setStill(first)
			end
			local buttons = Kit.new("Frame", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Size = UDim2.fromOffset(130, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Parent = c,
			}, { Kit.list(6) })
			return c, buttons
		end

		local function buyButton(parent: Instance, text: string, color: Color3, order: number, onClick: () -> ())
			Kit.button(text, onClick, {
				BackgroundColor3 = color,
				TextColor3 = Theme.AccentText,
				TextSize = 14,
				LayoutOrder = order,
				Size = UDim2.new(1, 0, 0, 32),
				Parent = parent,
			})
		end

		line("Tap 😀 in any game to pop a reaction over your head (or next to your seat in the 2D view).", 1, Theme.SubText)
		if wallet.studio then
			-- Same as the Wallet tab's button, here so buying packs can be tested in place.
			Kit.button("Studio test: free Gems and Coins", function()
				sendEconomy({ action = "studioGrant" })
			end, { LayoutOrder = 1, Size = UDim2.new(0, 280, 0, 34), BackgroundColor3 = Theme.Accent, TextColor3 = Theme.AccentText, Parent = content })
		end

		-- Every Gem pack for Robux.
		local bundle = Economy.ReactionBundle
		local missing = 0
		for _, id in bundle.items do
			if not ownedSet[id] then
				missing += 1
			end
		end
		local bundleIds = {}
		for _, id in bundle.items do
			local pack = Reactions.pack(id)
			if pack then
				table.insert(bundleIds, pack.reactions[1])
			end
		end
		local _, bundleButtons = packCard(2, "Every reaction pack", `{#bundle.items} packs, {#bundle.items * Reactions.PerPage} reactions`, bundleIds, TIER_COLORS.Legendary)
		if missing == 0 then
			Kit.label("Owned", { TextColor3 = Theme.Good, Font = Theme.FontBold, TextXAlignment = Enum.TextXAlignment.Right, Parent = bundleButtons })
		else
			local ready = bundle.productId ~= 0
			Kit.button(if ready then `R$ {bundle.robux}` else "Coming soon", function()
				if ready then
					sendPurchase({ action = "buyReactionBundle" })
				end
			end, {
				BackgroundColor3 = if ready then Theme.Good else Theme.Panel,
				TextColor3 = if ready then Theme.AccentText else Theme.SubText,
				TextSize = 14,
				Size = UDim2.new(1, 0, 0, 32),
				Parent = bundleButtons,
			})
		end

		-- The free ones, so players can preview them too.
		local _, freeButtons = packCard(3, "Free reactions", "Everyone has these", Reactions.free, nil)
		Kit.label("Free", { TextColor3 = Theme.Good, Font = Theme.FontBold, TextXAlignment = Enum.TextXAlignment.Right, Parent = freeButtons })

		for index, pack in Reactions.packs do
			local item = ShopCatalog.get(pack.id)
			if item then
				local coinShop = item.shop ~= "hub"
				local sub = `{item.tier} · {#pack.reactions} reactions{if coinShop then ` · {Economy.coinName(item.shop)}` else ""}`
				local _, buttons = packCard(10 + index, `{pack.icon} {pack.name}`, sub, pack.reactions, TIER_COLORS[item.tier])
				if ownedSet[item.id] then
					Kit.label("On your wheel", { TextColor3 = Theme.Good, Font = Theme.FontBold, TextXAlignment = Enum.TextXAlignment.Right, Parent = buttons })
				else
					if item.coins and coinShop then
						local coinColor = Economy.Coins[item.shop] and Economy.Coins[item.shop].color or Theme.Accent
						buyButton(buttons, `{item.coins} Coins`, coinColor, 1, function()
							sendEconomy({ action = "buy", itemId = item.id, currency = "coins" })
						end)
					end
					local gems = gemPrice(item, vip)
					if gems then
						buyButton(buttons, `{gems} Gems`, Color3.fromRGB(110, 220, 255), 2, function()
							sendEconomy({ action = "buy", itemId = item.id, currency = "gems" })
						end)
					end
					if item.universal and not item.notForSale then
						buyButton(buttons, `{item.universal} Universal`, Economy.UniversalCoin.color, 3, function()
							sendEconomy({ action = "buy", itemId = item.id, currency = "universal" })
						end)
					end
				end
			end
		end
	end

	function render()
		Kit.clear(tabsFrame)
		for index, t in tabs do
			local selected = t.key == tab
			Kit.button(t.name, function()
				tab = t.key
				Analytics.shop("ViewedTab", tab)
				render()
			end, {
				BackgroundColor3 = if selected then Theme.Accent else Theme.PanelLight,
				TextColor3 = if selected then Theme.AccentText else Theme.Text,
				TextSize = 15,
				LayoutOrder = index,
				Parent = tabsFrame,
			})
		end

		for _, child in content:GetChildren() do
			child:Destroy()
		end
		-- Inset so the first row's borders (UIStroke) aren't clipped by the scroll area.
		Kit.new("UIPadding", {
			PaddingTop = UDim.new(0, 4),
			PaddingLeft = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 4),
		}).Parent = content
		if not wallet then
			line("Loading your wallet...", 1)
			return
		end
		if tab == "wallet" then
			title.Text = "Wallet"
			renderWallet()
		elseif tab == "robux" then
			title.Text = "Gems & passes"
			renderRobux()
		elseif tab == "reactions" then
			title.Text = `Reactions  ·  {wallet.gems} {Economy.GemsName}`
			renderReactions()
		else
			if tab == "hub" then
				title.Text = `Hub shop  ·  {wallet.gems} {Economy.GemsName}`
			else
				title.Text = `{Economy.coinName(tab)}: {wallet.coins[tab] or 0}  ·  {wallet.gems} {Economy.GemsName}`
			end
			renderItems(tab)
		end
	end

	return {
		root = root,
		-- Opens on a coin's shop (from a game table), "reactions" (the 😀 wheel) or the wallet.
		open = function(coinKey: string?)
			if coinKey == "reactions" then
				tab = "reactions"
			else
				tab = if coinKey and #ShopCatalog.forShop(coinKey) > 0 then coinKey else "wallet"
			end
			root.Visible = true
			Analytics.shop("Opened", tab)
			render()
		end,
		setWallet = function(state: any)
			wallet = state
			converter.setBalance(state.coins and state.coins[Economy.UniversalCoin.key] or 0)
			if root.Visible then
				render()
			end
		end,
	}
end

return ShopPanel
