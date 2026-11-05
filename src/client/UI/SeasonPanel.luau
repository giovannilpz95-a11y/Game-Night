-- The 🎟️ Pass window (side rail): the Game Night Pass season, your tier and Stars, the
-- reward track (free on top, premium below) with Claim buttons, and the daily and weekly
-- quests that earn Stars. The track and numbers come from shared/Season; your progress
-- comes with the wallet (EconomyService.push -> state.season). The server checks every
-- claim and purchase, this only asks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Economy)
local Season = require(ReplicatedStorage.Shared.Season)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local Showtime = require(ReplicatedStorage.Shared.Showtime)
local Reactions = require(ReplicatedStorage.Shared.Reactions)
local Kit = require(script.Parent.Kit)
local Theme = Kit.Theme

local SeasonPanel = {}

local PREMIUM = Color3.fromRGB(255, 196, 64)
local STAR = Color3.fromRGB(255, 220, 90)
local TIER_COLORS = {
	Common = Color3.fromRGB(176, 170, 204),
	Rare = Color3.fromRGB(54, 162, 235),
	Epic = Color3.fromRGB(153, 102, 255),
	Legendary = Color3.fromRGB(255, 196, 64),
}
local SLOT_ICONS = {
	chair = "🪑",
	nameplate = "🏷️",
	theme = "🎨",
	title = "📜",
	trail = "💫",
	reactions = "😀",
}
local SLOT_NAMES = {
	chair = "Chair",
	nameplate = "Nameplate",
	theme = "Table theme",
	title = "Title",
	trail = "Trail",
	reactions = "Reaction pack",
	pose = "Intro pose",
	victory = "Win celebration",
}

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function timeLeft(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local days = seconds // 86400
	local hours = (seconds % 86400) // 3600
	if days > 0 then
		return `{days}d {hours}h`
	end
	return `{hours}h {(seconds % 3600) // 60}m`
end

-- Icon (emoji text or nil when a Kit icon is drawn) and a short caption for a reward.
local function rewardLook(reward: Season.Reward): (string?, string, Color3?)
	if reward.gems then
		return nil, `{reward.gems}`, Theme.Gem
	elseif reward.universal then
		return nil, `{reward.universal}`, Economy.UniversalCoin.color
	end
	local item = reward.item and ShopCatalog.get(reward.item)
	if not item then
		return "🎁", "?", nil
	end
	local icon = SLOT_ICONS[item.slot] or "🎁"
	local move = Showtime.get(item.id)
	if move then
		icon = move.icon
	end
	local pack = Reactions.pack(item.id)
	if pack then
		icon = pack.icon
	end
	local name = string.gsub(item.name, "^Title: ", "")
	return icon, name, TIER_COLORS[item.tier]
end

function SeasonPanel.create(parent: Instance, sendEconomy: (any) -> (), sendPurchase: (any) -> ())
	local window = Kit.modal(parent, { name = "PassWindow", maxSize = Vector2.new(900, 640) })
	local body = window.body

	local title = Kit.label("🎟️ Game Night Pass", { TextSize = 22, Font = Theme.FontTitle, Size = UDim2.new(1, -48, 0, 28), Parent = body })
	local subtitle = Kit.label("", { TextSize = 13, TextColor3 = Theme.SubText, Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, -48, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false, Parent = body })

	local content = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 1, -52),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		Parent = body,
	})

	local wallet: any = nil
	local tab = "rewards"
	local trackScroll: ScrollingFrame? = nil
	local savedScroll: number? = nil

	local render: () -> ()

	local function card(order: number): Frame
		return Kit.card({ Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, Parent = content })
	end

	-- Header: tier, Stars bar, premium and claim buttons.
	local function renderHeader(view: any, track: Season.Track)
		local c = card(1)
		Kit.new("UIStroke", { Color = if view.premium then PREMIUM else Theme.Stroke, Thickness = 2, Parent = c })
		local tier = Season.tierFor(view.stars)
		local into, need = Season.progress(view.stars)
		Kit.label(track.icon, { TextSize = 40, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(56, 56), Parent = c })
		Kit.label(`Tier {tier}{if tier >= Season.Tiers then " · MAX" else ""}`, { Font = Theme.FontTitle, TextSize = 26, Position = UDim2.fromOffset(64, 0), Size = UDim2.new(0.5, -64, 0, 30), Parent = c })
		Kit.label(
			if tier >= Season.Tiers then `⭐ {commas(view.stars)} Stars, track complete!` else `⭐ {commas(into)} / {commas(need)} to tier {tier + 1}`,
			{ TextSize = 13, TextColor3 = Theme.SubText, Position = UDim2.fromOffset(64, 30), Size = UDim2.new(0.5, -64, 0, 18), Parent = c }
		)
		local _, setBar = Kit.progress(STAR, { Position = UDim2.fromOffset(64, 52), Size = UDim2.new(0.5, -64, 0, 10), Parent = c })
		setBar(into / need)

		local right = Kit.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.new(0.5, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = c,
		}, { Kit.list(6) })
		if view.premium then
			Kit.tag("⭐ PREMIUM PASS", PREMIUM, { LayoutOrder = 1, Parent = right })
		else
			Kit.label("Premium: a reward on every tier, a bonus daily quest, and every tier you've reached unlocks right away.", { TextSize = 12, TextColor3 = Theme.SubText, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = right })
			local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 2, Parent = right })
			local ready = wallet.seasonProductReady == true
			Kit.button(if ready then `R$ {Season.Premium.robux}` else "R$ soon", function()
				if ready then
					sendPurchase({ action = "buySeasonPass" })
				end
			end, {
				BackgroundColor3 = if ready then Theme.Good else Theme.Panel,
				TextColor3 = if ready then Theme.AccentText else Theme.SubText,
				TextSize = 14,
				Size = UDim2.new(0.5, -3, 1, 0),
				Parent = row,
			})
			local gemButton: TextButton
			gemButton = Kit.button(`{Season.Premium.gems} Gems`, function()
				if wallet.gems < Season.Premium.gems then
					Kit.nope(gemButton)
				end
				sendEconomy({ action = "seasonPremium" })
			end, { BackgroundColor3 = Theme.Gem, TextColor3 = Theme.AccentText, TextSize = 14, Position = UDim2.new(0.5, 3, 0, 0), Size = UDim2.new(0.5, -3, 1, 0), Parent = row })
		end
		local row2 = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 3, Parent = right })
		if view.unclaimed > 0 then
			local claim = Kit.button(`🎁 Claim all ({view.unclaimed})`, function()
				sendEconomy({ action = "seasonClaim", all = true })
			end, { BackgroundColor3 = Theme.Accent, TextColor3 = Theme.AccentText, TextSize = 14, Size = UDim2.new(0.5, -3, 1, 0), Parent = row2 })
			Kit.bump(claim)
		end
		if tier < Season.Tiers then
			local skip: TextButton
			skip = Kit.secondary(`Skip a tier · {Season.TierSkipGems} 💎`, function()
				if wallet.gems < Season.TierSkipGems then
					Kit.nope(skip)
				end
				sendEconomy({ action = "seasonTiers", count = 1 })
			end, { TextSize = 13, Position = UDim2.new(0.5, 3, 0, 0), Size = UDim2.new(0.5, -3, 1, 0), Parent = row2 })
		end
		Kit.new("UIPadding", { PaddingBottom = UDim.new(0, 4), Parent = c })
		-- Keep the header tall enough for the left side.
		Kit.new("UISizeConstraint", { MinSize = Vector2.new(0, 70), Parent = c })
	end

	local function tabs(order: number)
		local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 34), LayoutOrder = order, Parent = content }, { Kit.list(8, true) })
		for i, t in { { key = "rewards", name = "🎁 Rewards" }, { key = "quests", name = "🎯 Quests" } } do
			local chip = Kit.chip(t.name, function()
				tab = t.key
				render()
			end, { LayoutOrder = i, Parent = row })
			Kit.setChip(chip, tab == t.key)
		end
	end

	-- One reward cell on the track.
	local function cell(parentFrame: Instance, reward: Season.Reward?, state: string, premiumCell: boolean, onClaim: () -> ())
		local frame = Kit.new("Frame", {
			BackgroundColor3 = if premiumCell then Color3.fromRGB(70, 56, 30) else Theme.PanelLight,
			BackgroundTransparency = if reward then 0 else 0.6,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 104),
			Parent = parentFrame,
		}, { Kit.corner(10) })
		if not reward then
			return
		end
		local icon, caption, color = rewardLook(reward)
		Kit.new("UIStroke", { Color = if state == "ready" then Theme.Accent else (color or Theme.Stroke), Thickness = if state == "ready" then 3 else 1.5, Transparency = if state == "locked" then 0.6 else 0, Parent = frame })
		if icon then
			Kit.label(icon, { TextSize = 30, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 36), Parent = frame })
		elseif reward.gems then
			Kit.gemIcon(30, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Parent = frame })
		else
			Kit.coinIcon(Economy.UniversalCoin.color, 28, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Parent = frame })
		end
		Kit.label(caption, { TextSize = 11, Font = Theme.FontBold, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(2, 44), Size = UDim2.new(1, -4, 0, 28), TextYAlignment = Enum.TextYAlignment.Top, Parent = frame })
		if state == "claimed" then
			Kit.label("✅", { TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -4), Size = UDim2.new(1, 0, 0, 22), Parent = frame })
		elseif state == "ready" then
			local b = Kit.button("Claim", onClaim, { BackgroundColor3 = Theme.Accent, TextColor3 = Theme.AccentText, TextSize = 12, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.new(1, -8, 0, 24), Parent = frame })
			Kit.bump(b)
		else
			Kit.label(if state == "premium" then "🔒" else "", { TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -4), Size = UDim2.new(1, 0, 0, 22), Parent = frame })
			for _, child in frame:GetDescendants() do
				if child:IsA("TextLabel") and child.Text ~= "🔒" then
					child.TextTransparency = 0.45
				end
			end
		end
	end

	local function renderTrack(view: any, track: Season.Track)
		local tier = Season.tierFor(view.stars)
		local holder = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 262), LayoutOrder = 3, Parent = content })
		Kit.label("FREE", { Font = Theme.FontBold, TextSize = 12, TextColor3 = Theme.SubText, Position = UDim2.fromOffset(0, 30), Size = UDim2.fromOffset(60, 104), TextXAlignment = Enum.TextXAlignment.Center, Parent = holder })
		Kit.label("⭐\nPREMIUM", { Font = Theme.FontBold, TextSize = 12, TextColor3 = PREMIUM, Position = UDim2.fromOffset(0, 142), Size = UDim2.fromOffset(60, 104), TextXAlignment = Enum.TextXAlignment.Center, Parent = holder })
		local scroll = Kit.new("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(64, 0),
			Size = UDim2.new(1, -64, 1, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			CanvasSize = UDim2.new(),
			ScrollingDirection = Enum.ScrollingDirection.X,
			ScrollBarThickness = 6,
			Parent = holder,
		}, { Kit.list(8, true) })
		trackScroll = scroll
		local COLUMN = 92
		for t = 1, Season.Tiers do
			local column = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(COLUMN, 250), LayoutOrder = t, Parent = scroll }, { Kit.list(6) })
			local reached = t <= tier
			Kit.label(`{t}`, {
				Font = Theme.FontBold,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Center,
				BackgroundColor3 = if reached then STAR else Theme.Background,
				BackgroundTransparency = if reached then 0 else 0.3,
				TextColor3 = if reached then Theme.AccentText else Theme.SubText,
				Size = UDim2.new(1, 0, 0, 22),
				LayoutOrder = 0,
				Parent = column,
			})
			local key = tostring(t)
			local free = track.free[t]
			local freeState = if not reached then "locked" elseif view.free[key] then "claimed" else "ready"
			local freeHolder = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 104), LayoutOrder = 1, Parent = column })
			cell(freeHolder, free, freeState, false, function()
				sendEconomy({ action = "seasonClaim", track = "free", tier = t })
			end)
			local premium = track.premium[t]
			local premiumState = if not view.premium then "premium" elseif not reached then "locked" elseif view.paid[key] then "claimed" else "ready"
			local premiumHolder = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 104), LayoutOrder = 2, Parent = column })
			cell(premiumHolder, premium, premiumState, true, function()
				sendEconomy({ action = "seasonClaim", track = "premium", tier = t })
			end)
		end
		-- Open on the current tier (or where the player had scrolled to).
		task.defer(function()
			if scroll.Parent then
				scroll.CanvasPosition = Vector2.new(savedScroll or math.max(0, (tier - 2) * (COLUMN + 8)), 0)
			end
		end)
		local note = `Every reward is shown here: nothing is random. Rewards you leave unclaimed are given to you when the season ends.`
		Kit.label(note, { TextSize = 12, TextColor3 = Theme.SubText, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4, Parent = content })
	end

	local function questRow(parentFrame: Instance, order: number, quest: any, canReroll: boolean)
		local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = order, Parent = parentFrame })
		local done = quest.done
		local rightWidth = if canReroll and not done then 150 else 110
		Kit.label(`{if done then "✅" elseif quest.bonus then "⭐" else "🎯"} {quest.text}{if quest.bonus then "  (pass bonus)" else ""}`, {
			TextSize = 14,
			TextColor3 = if done then Theme.Good else Theme.Text,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Size = UDim2.new(1, -rightWidth, 0, 20),
			Parent = row,
		})
		local reward = `+{commas(quest.stars or 0)} ⭐`
		if quest.gems and quest.gems > 0 then
			reward = `+{quest.gems} 💎  {reward}`
		end
		Kit.label(reward, { Font = Theme.FontBold, TextSize = 13, TextColor3 = STAR, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, if canReroll and not done then -40 else 0, 0, 0), Size = UDim2.fromOffset(110, 20), Parent = row })
		if canReroll and not done then
			Kit.button("🔄", function()
				sendEconomy({ action = "questReroll", questId = quest.id })
			end, { BackgroundColor3 = Theme.PanelLight, TextSize = 14, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(34, 26), Parent = row })
		end
		local _, set = Kit.progress(if done then Theme.Good else STAR, { Position = UDim2.new(0, 0, 0, 28), Size = UDim2.new(1, -rightWidth, 0, 8), Parent = row })
		set(if done then 1 elseif quest.target and quest.target > 0 then quest.progress / quest.target else 0)
		Kit.label(if done then "Done" else `{quest.progress}/{quest.target}`, { TextSize = 12, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(1, -rightWidth + 6, 0, 23), Size = UDim2.fromOffset(60, 16), Parent = row })
	end

	local function renderQuests(view: any)
		local now = os.time()
		local daily = card(3)
		Kit.list(6).Parent = daily
		local tomorrow = (now // 86400 + 1) * 86400
		Kit.label(`📅 Daily quests · new ones in {timeLeft(tomorrow - now)}`, { Font = Theme.FontBold, TextSize = 15, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 0, Parent = daily })
		local canReroll = not view.rerollUsed
		for i, quest in wallet.challenges or {} do
			questRow(daily, i, quest, canReroll)
		end
		Kit.label(if canReroll then "🔄 Swap one quest you don't like, once a day." else "🔄 Swap used today.", { TextSize = 12, TextColor3 = Theme.SubText, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 50, Parent = daily })
		if not view.premium then
			Kit.label("⭐ The premium pass adds a bonus daily quest.", { TextSize = 12, TextColor3 = PREMIUM, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 51, Parent = daily })
		end

		local weekly = card(4)
		Kit.list(6).Parent = weekly
		Kit.label(`🗓️ Weekly quests · new ones in {timeLeft(view.weekEndsAt - now)}`, { Font = Theme.FontBold, TextSize = 15, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 0, Parent = weekly })
		for i, quest in view.weekly or {} do
			questRow(weekly, i, quest, false)
		end
		if #(view.weekly or {}) == 0 then
			Kit.label("Play a game to get this week's quests.", { TextSize = 13, TextColor3 = Theme.SubText, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1, Parent = weekly })
		end
		Kit.label(`Stars also come from every rewarded game: {Season.StarsPerMinute} a minute, +{Season.WinStars} for a win (half with only bots).`, { TextSize = 12, TextColor3 = Theme.SubText, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5, Parent = content })
	end

	function render()
		if trackScroll and trackScroll.Parent then
			savedScroll = trackScroll.CanvasPosition.X
		end
		trackScroll = nil
		Kit.clear(content)
		Kit.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8) }).Parent = content
		Kit.list(10).Parent = content
		local view = wallet and wallet.season
		if not view then
			Kit.label("Loading...", { Size = UDim2.new(1, 0, 0, 24), Parent = content })
			return
		end
		if view.number < 1 then
			title.Text = "🎟️ Game Night Pass"
			subtitle.Text = "The first season starts soon."
			Kit.label(`Season 1 starts in {timeLeft(Season.Epoch - os.time())}.`, { Size = UDim2.new(1, 0, 0, 24), Parent = content })
			return
		end
		local track, rerun = Season.track(view.number)
		title.Text = `🎟️ Season {view.number}: {track.name}{if rerun then " (encore)" else ""}`
		subtitle.Text = `{track.blurb}  Ends in {timeLeft(Season.endsAt(view.number) - os.time())}.{if view.finalWeek then "  ⭐ Final week: double Stars!" else ""}`
		renderHeader(view, track)
		tabs(2)
		if tab == "rewards" then
			renderTrack(view, track)
		else
			renderQuests(view)
		end
		if wallet.studio then
			local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 32), LayoutOrder = 90, Parent = content }, { Kit.list(8, true) })
			Kit.secondary("Studio test: +5 tiers", function()
				sendEconomy({ action = "studioSeason" })
			end, { Size = UDim2.fromOffset(200, 30), LayoutOrder = 1, Parent = row })
			Kit.secondary(`Studio test: premium {if view.premium then "ON" else "off"}`, function()
				sendEconomy({ action = "studioSeason", premium = true })
			end, { Size = UDim2.fromOffset(220, 30), LayoutOrder = 2, Parent = row })
		end
	end

	return {
		window = window,
		open = function(which: string?)
			if which == "quests" or which == "rewards" then
				tab = which
			end
			savedScroll = nil
			window.open()
			render()
		end,
		close = window.close,
		isOpen = window.isOpen,
		setWallet = function(state: any)
			wallet = state
			if window.isOpen() then
				render()
			end
		end,
		fit = window.fit,
	}
end

-- Rewards waiting to be claimed (the 🎟️ badge on the side rail).
function SeasonPanel.unclaimed(state: any): number
	local view = state and state.season
	return if view and view.unclaimed then view.unclaimed else 0
end

return SeasonPanel
