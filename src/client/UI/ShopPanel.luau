-- The shop window: your wallet and daily challenges, Gems & passes (Robux), the hub shop
-- (Gems), reaction packs (Gems, Coins or the Robux bundle) and one shop per kind of Coin.
-- Wide screens get a tab column on the left; phones get a row of tabs across the top.
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

-- A picture for each kind of item, shown big on its tile.
local SLOT_ICONS = {
	board = "🟫",
	brush = "🖌️",
	cards = "🃏",
	celebration = "🎉",
	chair = "🪑",
	dice = "🎲",
	effect = "✨",
	nameplate = "🏷️",
	pieces = "♟️",
	reactions = "😀",
	sound = "🔊",
	theme = "🎨",
	title = "📜",
	trail = "💫",
}

local PASS_ICONS = { vip = "👑", partyHost = "🎉" }

local NARROW = 600 -- window width under which the tabs move to a row on top
local TAB_W = 170

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

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

function ShopPanel.create(parent: Instance, sendEconomy: (any) -> (), sendPurchase: (any) -> ())
	local root = Kit.panel({
		Name = "Shop",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.92, 0.86),
		BackgroundColor3 = Theme.Panel,
		Visible = false,
		ZIndex = 30,
		Parent = parent,
	})
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(860, 580) }).Parent = root
	Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 2, Transparency = 0.2 }).Parent = root

	local title = Kit.title("🛒 Shop", { Size = UDim2.new(1, -190, 0, 30), Parent = root })
	Kit.closeButton(function()
		root.Visible = false
	end, { Parent = root })

	-- Your Gems, always in view at the top right.
	local gemChip = Kit.new("Frame", {
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -44, 0, 0),
		Size = UDim2.fromOffset(0, 32),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = root,
	}, {
		Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 12) }),
	})
	local gemList = Kit.list(6, true)
	gemList.VerticalAlignment = Enum.VerticalAlignment.Center
	gemList.Parent = gemChip
	Kit.gemIcon(20, { LayoutOrder = 1, Parent = gemChip })
	local gemText = Kit.label("...", {
		Font = Theme.FontBold,
		TextSize = 16,
		TextWrapped = false,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 2,
		Parent = gemChip,
	})

	local tabsFrame = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 3,
		Parent = root,
	}, { Kit.list(6), Kit.new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 4) }) })

	local content = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		Parent = root,
	})

	local narrow = false
	local function place()
		local width = root.AbsoluteSize.X
		local nowNarrow = width > 0 and width < NARROW
		narrow = nowNarrow
		local list = tabsFrame:FindFirstChildOfClass("UIListLayout")
		if narrow then
			tabsFrame.Position = UDim2.new(0, 0, 0, 40)
			tabsFrame.Size = UDim2.new(1, 0, 0, 38)
			tabsFrame.AutomaticCanvasSize = Enum.AutomaticSize.X
			tabsFrame.ScrollingDirection = Enum.ScrollingDirection.X
			tabsFrame.ScrollBarThickness = 0
			if list then
				list.FillDirection = Enum.FillDirection.Horizontal
			end
			content.Position = UDim2.new(0, 0, 0, 84)
			content.Size = UDim2.new(1, 0, 1, -84)
		else
			tabsFrame.Position = UDim2.new(0, 0, 0, 44)
			tabsFrame.Size = UDim2.new(0, TAB_W, 1, -44)
			tabsFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
			tabsFrame.ScrollingDirection = Enum.ScrollingDirection.Y
			tabsFrame.ScrollBarThickness = 3
			if list then
				list.FillDirection = Enum.FillDirection.Vertical
			end
			content.Position = UDim2.new(0, TAB_W + 14, 0, 44)
			content.Size = UDim2.new(1, -(TAB_W + 14), 1, -44)
		end
		for _, b in tabsFrame:GetChildren() do
			if b:IsA("TextButton") then
				b.Size = if narrow then UDim2.new(0, 0, 1, -4) else UDim2.new(1, 0, 0, 40)
				b.AutomaticSize = if narrow then Enum.AutomaticSize.X else Enum.AutomaticSize.None
			end
		end
	end
	place()

	local wallet: any = nil
	local tab = "wallet"
	local converter = CoinConvertPanel.create(parent, sendEconomy)

	local tabs = {
		{ key = "wallet", name = "👛 Wallet & daily", short = "👛 Wallet" },
		{ key = "robux", name = "💎 Gems & passes", short = "💎 Gems" },
		{ key = "hub", name = "🏪 Hub shop", short = "🏪 Hub" },
		{ key = "reactions", name = "😀 Reactions", short = "😀 Reactions" },
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
		local short = (string.gsub(Economy.coinName(key), " Coins$", ""))
		table.insert(tabs, { key = key, name = `{short} shop`, short = short, coin = key })
	end

	local render: () -> ()

	local function section(text: string, order: number)
		Kit.label(text, { Font = Theme.FontBold, TextSize = 17, TextColor3 = Theme.SubText, LayoutOrder = order, Size = UDim2.new(1, -8, 0, 24), Parent = content })
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

	local function card(order: number, height: number?): Frame
		return Kit.card({
			Size = UDim2.new(1, -8, 0, height or 0),
			AutomaticSize = if height then Enum.AutomaticSize.None else Enum.AutomaticSize.Y,
			LayoutOrder = order,
			Parent = content,
		})
	end

	-- A grid of tiles inside the content list.
	local function grid(order: number, cell: UDim2): Frame
		local frame = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			Parent = content,
		})
		Kit.new("UIGridLayout", { CellSize = cell, CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = frame })
		return frame
	end

	-- A price button with the currency's icon on its left.
	local function priceButton(parentFrame: Instance, amount: string, icon: string, color: Color3, onClick: () -> (), props: { [string]: any }?): TextButton
		local button = Kit.button(amount, onClick, {
			BackgroundColor3 = color,
			TextColor3 = Theme.AccentText,
			TextSize = 15,
			Size = UDim2.new(1, 0, 0, 32),
			Parent = parentFrame,
		})
		Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 20), Parent = button })
		if icon == "gem" then
			Kit.gemIcon(18, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -14, 0.5, 0), Parent = button })
		elseif icon == "robux" then
			Kit.label("R$", { Font = Theme.FontBold, TextSize = 13, TextColor3 = Theme.AccentText, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -16, 0.5, 0), Size = UDim2.fromOffset(22, 18), Parent = button })
		else
			local coinColor = Economy.Coins[icon] and Economy.Coins[icon].color or (if icon == "universal" then Economy.UniversalCoin.color else Theme.Accent)
			Kit.coinIcon(coinColor, 16, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -12, 0.5, 0), Parent = button })
		end
		for key, value in props or {} do
			(button :: any)[key] = value
		end
		return button
	end

	local function balanceTile(parentFrame: Instance, order: number, amount: number, name: string, icon: Frame)
		local tile = Kit.card({ LayoutOrder = order, Parent = parentFrame })
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 0, 0.5, 0)
		icon.Parent = tile
		Kit.label(commas(amount), { Font = Theme.FontBold, TextSize = 18, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.new(0, 34, 0, 0), Size = UDim2.new(1, -34, 0, 20), Parent = tile })
		Kit.label(name, { TextSize = 12, TextColor3 = Theme.SubText, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.new(0, 34, 0, 20), Size = UDim2.new(1, -34, 0, 16), Parent = tile })
		return tile
	end

	local function renderWallet()
		Kit.list(10).Parent = content

		-- Level and XP.
		local level = card(1, 70)
		Kit.label(`Level {wallet.level}`, { Font = Theme.FontTitle, TextSize = 24, Size = UDim2.new(0.5, 0, 0, 28), Parent = level })
		Kit.label(`{commas(wallet.xp)} / {commas(wallet.xpNeeded)} XP`, { TextSize = 13, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 6), Size = UDim2.new(0.5, 0, 0, 18), Parent = level })
		local _, setXp = Kit.progress(Theme.Accent, { Position = UDim2.new(0, 0, 0, 36), Size = UDim2.new(1, 0, 0, 12), Parent = level })
		setXp(if wallet.xpNeeded and wallet.xpNeeded > 0 then wallet.xp / wallet.xpNeeded else 0)

		-- Balances: Gems, Universal Coins (convertible), then every game's Coins.
		section("Balances", 2)
		local top = grid(3, UDim2.new(0.5, -4, 0, 56))
		balanceTile(top, 1, wallet.gems, Economy.GemsName, Kit.gemIcon(26))
		local universal = wallet.coins[Economy.UniversalCoin.key] or 0
		local uniTile = balanceTile(top, 2, universal, Economy.UniversalCoin.name, Kit.coinIcon(Economy.UniversalCoin.color, 24))
		if universal > 0 then
			for _, child in uniTile:GetChildren() do
				if child:IsA("TextLabel") then
					child.Size = UDim2.new(1, -34 - 92, 0, child.Size.Y.Offset)
				end
			end
			Kit.button("Convert", function()
				converter.open(universal, nil)
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 86, 0, 30), TextSize = 14, Parent = uniTile })
		end
		local coins = grid(4, UDim2.new(if narrow then 0.5 else 1 / 3, -6, 0, 50))
		for i, key in coinKeys do
			balanceTile(coins, i, wallet.coins[key] or 0, Economy.coinName(key), Kit.coinIcon(Economy.Coins[key].color, 22))
		end

		-- Today: streak, first win, challenges with progress bars.
		section("Today", 20)
		local today = card(21)
		Kit.list(8).Parent = today
		Kit.label(`🔥 Login streak: day {wallet.loginStreak}`, { Font = Theme.FontBold, LayoutOrder = 1, Parent = today })
		Kit.label(
			if wallet.firstWinDone then "🏆 First win of the day: done" else `🏆 First win of the day: +{Economy.FirstWinGems} {Economy.GemsName}`,
			{ TextColor3 = if wallet.firstWinDone then Theme.Good else Theme.Text, LayoutOrder = 2, Parent = today }
		)
		for i, challenge in wallet.challenges or {} do
			local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 2 + i, Parent = today })
			local done = challenge.done
			Kit.label(`{if done then "✅" else "🎯"} {challenge.text}`, {
				TextSize = 14,
				TextColor3 = if done then Theme.Good else Theme.Text,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Size = UDim2.new(1, -110, 0, 20),
				Parent = row,
			})
			Kit.label(`+{Economy.ChallengeGems}`, { Font = Theme.FontBold, TextSize = 14, TextColor3 = Theme.Gem, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -22, 0, 0), Size = UDim2.fromOffset(80, 20), Parent = row })
			Kit.gemIcon(16, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), Parent = row })
			local _, setDone = Kit.progress(if done then Theme.Good else Theme.Accent, { Position = UDim2.new(0, 0, 0, 26), Size = UDim2.new(1, -60, 0, 8), Parent = row })
			setDone(if done then 1 elseif challenge.target and challenge.target > 0 then challenge.progress / challenge.target else 0)
			Kit.label(if done then "Done" else `{challenge.progress}/{challenge.target}`, { TextSize = 12, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 21), Size = UDim2.fromOffset(54, 16), Parent = row })
		end
		if not wallet.saving then
			line("⚠ Progress isn't saving this session.", 40, Theme.Bad)
		end
		if wallet.studio then
			Kit.secondary("Studio test: free Gems and Coins", function()
				sendEconomy({ action = "studioGrant" })
			end, { LayoutOrder = 50, Size = UDim2.new(0, 280, 0, 34), Parent = content })
			-- Passes can't be bought before they exist in the Creator Hub, so test their perks here.
			for i, key in { "vip", "partyHost" } do
				local on = wallet.passes and wallet.passes[key]
				Kit.secondary(`Studio test: {Economy.Passes[key].name} {if on then "ON" else "off"}`, function()
					sendEconomy({ action = "studioPass", key = key })
				end, { LayoutOrder = 50 + i, Size = UDim2.new(0, 280, 0, 34), Parent = content })
			end
		end
	end

	local function robuxButton(parentFrame: Instance, robux: number, ready: boolean, onClick: () -> (), props: { [string]: any }?)
		if ready then
			priceButton(parentFrame, tostring(robux), "robux", Theme.Good, onClick, props)
		else
			local button = Kit.button("Coming soon", function() end, { BackgroundColor3 = Theme.Panel, TextColor3 = Theme.SubText, TextSize = 13, AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 32), Parent = parentFrame })
			for key, value in props or {} do
				(button :: any)[key] = value
			end
		end
	end

	local function renderRobux()
		Kit.list(10).Parent = content
		local order = 1
		if wallet.starterAvailable then
			local pack = Economy.StarterPack
			local c = card(order, 78)
			Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 2, Parent = c })
			Kit.label("🎁 Starter Pack", { Font = Theme.FontTitle, TextSize = 20, Size = UDim2.new(1, -150, 0, 24), Parent = c })
			Kit.tag("FIRST 3 DAYS", Theme.Accent, { Position = UDim2.new(0, 0, 0, 28), Parent = c })
			Kit.label(`{pack.gems} Gems + Cozy Cabin table + nameplate`, { TextColor3 = Theme.SubText, TextSize = 13, Position = UDim2.new(0, 0, 0, 48), Size = UDim2.new(1, -150, 0, 18), Parent = c })
			robuxButton(c, pack.robux, pack.productId ~= 0, function()
				sendPurchase({ action = "buyStarter" })
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 130, 0, 36) })
			order += 1
		end

		section("Gems", order)
		order += 1
		local packs = grid(order, UDim2.new(if narrow then 0.5 else 0.25, -6, 0, 140))
		order += 1
		local best = #Economy.GemPacks
		for i, pack in Economy.GemPacks do
			local tile = Kit.card({ LayoutOrder = i, Parent = packs })
			if i == best then
				Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 2, Parent = tile })
			end
			-- Bigger packs get a bigger gem.
			local size = 26 + math.min(i, 4) * 5
			Kit.gemIcon(size, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Parent = tile })
			Kit.label(commas(pack.gems), { Font = Theme.FontTitle, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 0, 0, 52), Size = UDim2.new(1, 0, 0, 24), Parent = tile })
			if pack.bonus then
				Kit.tag(if i == best then `BEST {pack.bonus}` else pack.bonus, if i == best then Theme.Accent else Theme.Good, {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 4, 0, -4),
					Parent = tile,
				})
			end
			robuxButton(tile, pack.robux, pack.productId ~= 0, function()
				sendPurchase({ action = "buyGems", key = pack.key })
			end, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0) })
		end

		section("Passes", order)
		order += 1
		for _, key in { "vip", "partyHost" } do
			local pass = Economy.Passes[key]
			local owned = wallet.passes and wallet.passes[key]
			local c = card(order)
			local info = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -146, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = c }, { Kit.list(4) })
			Kit.label(`{PASS_ICONS[key] or "⭐"} {pass.name}`, { Font = Theme.FontTitle, TextSize = 20, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1, Parent = info })
			for i, perk in pass.perks do
				Kit.label(`✓  {perk}`, { TextSize = 14, TextColor3 = Theme.SubText, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 + i, Parent = info })
			end
			local side = Kit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(130, 36), Parent = c })
			if owned then
				Kit.tag("OWNED", Theme.Good, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 8), Parent = side })
			else
				robuxButton(side, pass.robux, pass.gamePassId ~= 0, function()
					sendPurchase({ action = "buyPass", key = key })
				end, { Size = UDim2.new(1, 0, 1, 0) })
			end
			order += 1
		end
	end

	local function renderItems(shop: string)
		Kit.new("UIGridLayout", {
			CellSize = UDim2.new(if narrow then 0.5 else 1 / 3, -8, 0, 176),
			CellPadding = UDim2.new(0, 8, 0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}).Parent = content
		local vip = wallet.vip == true
		local equipped = wallet.equipped and wallet.equipped[shop] or {}
		for index, item in ShopCatalog.forShop(shop) do
			if item.slot == "reactions" then
				continue -- on the Reactions tab
			end
			local tier = TIER_COLORS[item.tier] or Theme.SubText
			local owned = wallet.owned and wallet.owned[item.id]
			local isOn = owned and equipped[item.slot] == item.id
			local c = Kit.card({ LayoutOrder = index, Parent = content })
			Kit.new("UIStroke", { Color = if isOn then Theme.Good else tier, Thickness = 2, Transparency = if isOn then 0 else 0.25, Parent = c })
			-- Picture: the slot's icon on a tier-colored badge.
			local badge = Kit.label(SLOT_ICONS[item.slot] or "🎁", {
				BackgroundColor3 = tier,
				BackgroundTransparency = 0.7,
				TextSize = 26,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.fromOffset(46, 46),
				Parent = c,
			})
			Kit.corner(12).Parent = badge
			Kit.tag(string.upper(item.tier), tier, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Parent = c })
			if isOn then
				Kit.tag("EQUIPPED", Theme.Good, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 22), Parent = c })
			end
			Kit.label(item.name, { Font = Theme.FontBold, TextSize = 15, Position = UDim2.new(0, 0, 0, 52), Size = UDim2.new(1, 0, 0, 36), TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.AtEnd, Parent = c })
			Kit.label(`{item.slot}{if item.earnedOnly then " · earned only" else ""}`, { TextSize = 12, TextColor3 = Theme.SubText, Position = UDim2.new(0, 0, 0, 88), Size = UDim2.new(1, 0, 0, 16), Parent = c })

			if owned then
				Kit.button(if isOn then "Unequip" else "Equip", function()
					sendEconomy({ action = "equip", itemId = item.id })
				end, { BackgroundColor3 = if isOn then Theme.Panel else Theme.Good, TextColor3 = if isOn then Theme.Text else Theme.AccentText, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 32), Parent = c })
			else
				local buttons = {}
				if item.coins and shop ~= "hub" then
					table.insert(buttons, { text = commas(item.coins), icon = shop, currency = "coins", color = Economy.Coins[shop] and Economy.Coins[shop].color or Theme.Accent })
				end
				local gems = gemPrice(item, vip)
				if gems then
					table.insert(buttons, { text = commas(gems), icon = "gem", currency = "gems", color = Theme.Gem })
				end
				-- Side by side when there are two, so the tile stays short.
				for i, b in buttons do
					local half = #buttons == 2
					priceButton(c, b.text, b.icon, b.color, function()
						sendEconomy({ action = "buy", itemId = item.id, currency = b.currency })
					end, {
						AnchorPoint = Vector2.new(0, 1),
						Position = if half then UDim2.new((i - 1) * 0.5, if i == 2 then 3 else 0, 1, 0) else UDim2.new(0, 0, 1, 0),
						Size = if half then UDim2.new(0.5, -3, 0, 32) else UDim2.new(1, 0, 0, 32),
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
			local b = Kit.button(if narrow then t.short else t.name, function()
				tab = t.key
				Analytics.shop("ViewedTab", tab)
				render()
			end, {
				BackgroundColor3 = if selected then Theme.Accent else Theme.PanelLight,
				TextColor3 = if selected then Theme.AccentText else Theme.Text,
				TextSize = 15,
				TextXAlignment = if narrow then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left,
				Size = if narrow then UDim2.new(0, 0, 1, -4) else UDim2.new(1, 0, 0, 40),
				AutomaticSize = if narrow then Enum.AutomaticSize.X else Enum.AutomaticSize.None,
				LayoutOrder = index,
				Parent = tabsFrame,
			})
			Kit.new("UIPadding", { PaddingLeft = UDim.new(0, if t.coin then 30 else 12), PaddingRight = UDim.new(0, 12), Parent = b })
			if t.coin then
				Kit.coinIcon(Economy.Coins[t.coin].color, 14, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -20, 0.5, 0), Parent = b })
			end
		end

		for _, child in content:GetChildren() do
			child:Destroy()
		end
		-- Inset so the first row's borders (UIStroke) aren't clipped by the scroll area.
		Kit.new("UIPadding", {
			PaddingTop = UDim.new(0, 4),
			PaddingLeft = UDim.new(0, 4),
			PaddingRight = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 8),
		}).Parent = content
		gemText.Text = if wallet then commas(wallet.gems) else "..."
		if not wallet then
			line("Loading your wallet...", 1)
			return
		end
		if tab == "wallet" then
			title.Text = "👛 Wallet"
			renderWallet()
		elseif tab == "robux" then
			title.Text = "💎 Gems & passes"
			renderRobux()
		elseif tab == "reactions" then
			title.Text = "😀 Reactions"
			renderReactions()
		else
			if tab == "hub" then
				title.Text = "🏪 Hub shop"
			else
				title.Text = `{Economy.coinName(tab)}: {commas(wallet.coins[tab] or 0)}`
			end
			renderItems(tab)
		end
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		-- Tabs switch between column and row at NARROW; redraw so tiles re-flow.
		local wasNarrow = narrow
		place()
		if root.Visible and narrow ~= wasNarrow then
			render()
		end
	end)

	return {
		root = root,
		-- Opens on a coin's shop (from a game table), "reactions" (the 😀 wheel) or the wallet.
		open = function(coinKey: string?)
			if coinKey == "reactions" then
				tab = "reactions"
			else
				tab = if coinKey and #ShopCatalog.forShop(coinKey) > 0 then coinKey else "wallet"
			end
			local wasOpen = root.Visible
			root.Visible = true
			if not wasOpen then
				Kit.popIn(root)
			end
			place()
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
