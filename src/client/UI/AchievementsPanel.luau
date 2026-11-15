-- The 🏆 Achievements window: every achievement with its five tiers (Bronze to Diamond),
-- your trophy score, level and the next level reward, what you're closest to, what you
-- earned last, and every game's own achievements with its mastery bar. Built from Kit's
-- tokens, so it works in every look; in the Midnight Lounge it's dark glass with the neon
-- yellow accent, Oswald headings and tabs along the top.
-- Data: your own stats profile (ProgressionService, StatsState), which carries
-- `achievements`. Rules and rewards come from shared/Achievements and shared/Economy.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Achievements = require(ReplicatedStorage.Shared.Achievements)
local Economy = require(ReplicatedStorage.Shared.Economy)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local GameArt = require(ReplicatedStorage.Shared.GameArt)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)
local Theme = Kit.Theme

local AchievementsPanel = {}

local localPlayer = Players.LocalPlayer
local commas = Achievements.commas

local TABS = {
	{ key = "overview", name = "Overview" },
	{ key = "general", name = "General" },
	{ key = "games", name = "Games" },
}

local function glass(props: { [string]: any }, radius: number?): Frame
	local k: any = Kit
	if k.glass then
		return k.glass(props, radius)
	end
	local frame = Kit.new("Frame", { BackgroundColor3 = Theme.PanelLight, BorderSizePixel = 0 }, { Kit.corner(radius or 12) })
	for key, value in props do
		(frame :: any)[key] = value
	end
	return frame
end

local function headline(label: TextLabel, upper: boolean?)
	local k: any = Kit
	if k.headline then
		k.headline(label, upper)
	end
end

-- What the next tier pays, as text.
local function nextReward(a: Achievements.Achievement, tier: number): string
	local r = Economy.AchievementRewards
	local parts = {}
	if a.gameId then
		local entry = GameCatalog.get(a.gameId)
		local coins = r.game.coins[tier] or 0
		if coins > 0 then
			table.insert(parts, `{commas(coins)} {Economy.coinName(entry and entry.coin or Economy.DefaultCoin)}`)
		end
		if (r.game.gems[tier] or 0) > 0 then
			table.insert(parts, `{r.game.gems[tier]} {Economy.GemsName}`)
		end
		table.insert(parts, `{r.game.xp[tier]} XP`)
	else
		table.insert(parts, `{r.general.gems[tier]} {Economy.GemsName}`)
		table.insert(parts, `{r.general.xp[tier]} XP`)
	end
	if tier == #a.goals and a.title then
		local item = ShopCatalog.get(a.title)
		if item then
			table.insert(parts, item.name)
		end
	end
	return "+" .. table.concat(parts, " · +")
end

local function levelRewardText(level: number): string?
	local at, reward = Economy.nextLevelMilestone(level)
	if not at then
		return nil
	end
	local parts = {}
	if reward.item then
		local item = ShopCatalog.get(reward.item)
		if item then
			table.insert(parts, item.name)
		end
	end
	if reward.gems then
		table.insert(parts, `{reward.gems} {Economy.GemsName}`)
	end
	if reward.universal then
		table.insert(parts, `{commas(reward.universal)} {Economy.UniversalCoin.name}`)
	end
	return `Level {at} reward: {table.concat(parts, " · ")}`
end

function AchievementsPanel.create(parent: Instance, send: (any) -> ())
	local window = Kit.modal(parent, { name = "AchievementsWindow", maxSize = Vector2.new(960, 680) })
	local body = window.body

	local title = Kit.title("Achievements", { Size = UDim2.new(0.5, 0, 0, 30), Parent = body })
	-- Trophy score and badge count, top right (left of the X).
	local scoreLabel = Kit.label("", {
		Font = Theme.FontBold,
		TextSize = 15,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -52, 0, 4),
		Size = UDim2.new(0.5, -52, 0, 24),
		Parent = body,
	})

	-- Tabs along the top, with a neon underline under the open one.
	local tabRow = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 38),
		Size = UDim2.new(1, 0, 0, 34),
		Parent = body,
	}, { Kit.list(18, true) })
	local content = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 82),
		Size = UDim2.new(1, 0, 1, -82),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Accent,
		Parent = body,
	}, { Kit.list(10), Kit.new("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }) })

	local profile: any = nil
	local tab = "overview"
	local gameOpen: string? = nil -- a game's own list on the Games tab
	local compact = false
	local render: () -> ()

	local tabButtons: { [string]: { button: TextButton, line: Frame } } = {}
	for i, t in TABS do
		local button = Kit.new("TextButton", {
			Name = t.key,
			Text = t.name,
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Font = Theme.FontBold,
			TextSize = 17,
			TextColor3 = Theme.SubText,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			LayoutOrder = i,
			Parent = tabRow,
		})
		headline(button :: any)
		local line = Kit.new("Frame", {
			Name = "Underline",
			BackgroundColor3 = Theme.Accent,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 3),
			Visible = false,
			Parent = button,
		}, { Kit.corner(2) })
		button:SetAttribute("Sfx", "toggle")
		Kit.onPress(button, function()
			tab = t.key
			gameOpen = nil
			content.CanvasPosition = Vector2.zero
			render()
		end)
		tabButtons[t.key] = { button = button, line = line }
	end

	-- Building blocks ---------------------------------------------------------------------

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local function section(text: string, sub: string?)
		local label = Kit.label(text, { Font = Theme.FontBold, TextSize = 18, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = nextOrder(), Parent = content })
		headline(label)
		if sub then
			Kit.label(sub, { TextSize = 13, TextColor3 = Theme.SubText, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder(), Parent = content })
		end
	end

	local function grid(cellHeight: number, columns: number): Frame
		local frame = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = nextOrder(),
			Parent = content,
		})
		Kit.new("UIGridLayout", {
			CellPadding = UDim2.fromOffset(10, 10),
			CellSize = UDim2.new(1 / columns, -10, 0, cellHeight),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = frame,
		})
		return frame
	end

	-- Five little gems, one per tier, lit in the tier's color when earned.
	local function pips(parentFrame: Instance, a: Achievements.Achievement, tier: number, position: UDim2)
		local row = Kit.new("Frame", { BackgroundTransparency = 1, Position = position, Size = UDim2.fromOffset(5 * 16, 12), Parent = parentFrame }, { Kit.list(4, true) })
		for t = 1, #a.goals do
			local lit = t <= tier
			Kit.new("Frame", {
				BackgroundColor3 = if lit then Achievements.TierColors[t] else Theme.Background,
				BackgroundTransparency = if lit then 0 else 0.3,
				BorderSizePixel = 0,
				Rotation = 45,
				Size = UDim2.fromOffset(9, 9),
				LayoutOrder = t,
				Parent = row,
			}, { Kit.corner(2), Kit.new("UIStroke", { Color = Achievements.TierColors[t], Transparency = if lit then 0.2 else 0.55, Thickness = 1 }) })
		end
	end

	-- One achievement: icon in a tier ring, name, what the next tier asks, the five pips,
	-- a progress bar and what the next tier pays.
	local function achievementCard(container: Instance, a: Achievements.Achievement, index: number, showGame: boolean?)
		local p = profile
		local tier = Achievements.earnedTier(p.achievements, a.id)
		local secret = a.hidden and tier == 0
		local value, goal, nextTier = Achievements.progress(p, a, tier)
		local color = if tier > 0 then Achievements.TierColors[tier] else Theme.SubText
		local card = glass({ LayoutOrder = index, Parent = container }, 12)
		if tier >= #a.goals then
			Kit.new("UIStroke", { Color = color, Thickness = 1.5, Transparency = 0.15, Parent = card })
		end
		local iconBox = Kit.new("Frame", {
			BackgroundColor3 = Theme.Background,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.fromOffset(56, 56),
			Parent = card,
		}, { Kit.corner(14), Kit.new("UIStroke", { Color = color, Thickness = if tier > 0 then 2 else 1, Transparency = if tier > 0 then 0 else 0.5 }) })
		Kit.label(if secret then "❔" else a.icon, {
			TextSize = 30,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTransparency = if tier > 0 then 0 else 0.35,
			Size = UDim2.fromScale(1, 1),
			Parent = iconBox,
		})
		if tier > 0 then
			local chip = Kit.label(Achievements.TierShort[tier], {
				Font = Theme.FontBold,
				TextSize = 11,
				TextColor3 = Theme.AccentText,
				BackgroundColor3 = color,
				BackgroundTransparency = 0,
				TextXAlignment = Enum.TextXAlignment.Center,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 1, 0),
				Size = UDim2.fromOffset(26, 16),
				TextWrapped = false,
				Parent = iconBox,
			})
			Kit.corner(8).Parent = chip
		end
		local name = if secret then "Secret achievement" else (if showGame then Achievements.fullName(a) else a.name)
		Kit.label(name, {
			Font = Theme.FontBold,
			TextSize = 16,
			TextColor3 = if tier > 0 then color else Theme.Text,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Position = UDim2.fromOffset(76, 8),
			Size = UDim2.new(1, -170, 0, 20),
			Parent = card,
		})
		pips(card, a, tier, UDim2.new(1, -88, 0, 13))
		local desc = if secret
			then "Keep playing to find this one."
			elseif nextTier then Achievements.describe(a, nextTier)
			else `{Achievements.describe(a, #a.goals)} · complete`
		Kit.label(desc, {
			TextSize = 13,
			TextColor3 = Theme.SubText,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Position = UDim2.fromOffset(76, 30),
			Size = UDim2.new(1, -86, 0, 18),
			Parent = card,
		})
		if not secret then
			local barColor = if nextTier then Achievements.TierColors[nextTier] else color
			local _, set = Kit.progress(barColor, { Position = UDim2.fromOffset(76, 54), Size = UDim2.new(1, -170, 0, 8), Parent = card })
			set(if goal > 0 then value / goal else 0)
			Kit.label(`{commas(math.min(value, goal))} / {commas(goal)}`, {
				TextSize = 12,
				TextColor3 = Theme.SubText,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextWrapped = false,
				Position = UDim2.new(1, -90, 0, 49),
				Size = UDim2.fromOffset(80, 18),
				Parent = card,
			})
		end
		local foot = if secret then "" elseif nextTier then `Next: {nextReward(a, nextTier)}` else `{Achievements.TierNames[#a.goals]} · every tier earned`
		Kit.label(foot, {
			TextSize = 12,
			TextColor3 = if nextTier then Theme.Text else color,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Position = UDim2.new(0, 10, 1, -24),
			Size = UDim2.new(1, -20, 0, 18),
			Parent = card,
		})
	end

	local CARD_HEIGHT = 100
	local function cards(list: { Achievements.Achievement }, showGame: boolean?)
		local container = grid(CARD_HEIGHT, if compact then 1 else 2)
		for i, a in list do
			achievementCard(container, a, i, showGame)
		end
	end

	-- Tabs --------------------------------------------------------------------------------

	local function renderOverview(p: any)
		-- Level card: level, XP bar, next level reward.
		local head = glass({ Size = UDim2.new(1, 0, 0, 96), LayoutOrder = nextOrder(), Parent = content }, 14)
		local levelLabel = Kit.label(`Level {p.level}`, { Font = Theme.FontTitle, TextSize = 28, TextWrapped = false, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(0.5, 0, 0, 34), Parent = head })
		headline(levelLabel)
		Kit.label(`{commas(p.xp)} / {commas(p.xpNeeded or 1)} XP`, {
			TextSize = 13,
			TextColor3 = Theme.SubText,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextWrapped = false,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 16),
			Size = UDim2.new(0.5, -14, 0, 18),
			Parent = head,
		})
		local _, set = Kit.progress(Theme.Accent, { Position = UDim2.fromOffset(14, 48), Size = UDim2.new(1, -28, 0, 10), Parent = head })
		set((p.xp or 0) / math.max(1, p.xpNeeded or 1))
		Kit.label(levelRewardText(p.level) or "Every level reward earned. Legend!", {
			TextSize = 13,
			TextColor3 = Theme.Text,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Position = UDim2.fromOffset(14, 66),
			Size = UDim2.new(1, -28, 0, 18),
			Parent = head,
		})

		-- Badges by tier.
		local counts = { 0, 0, 0, 0, 0 }
		for _, a in Achievements.list do
			for t = 1, Achievements.earnedTier(p.achievements, a.id) do
				counts[t] += 1
			end
		end
		local tiers = grid(58, if compact then 3 else 5)
		for t = 1, Achievements.MaxTier do
			local cell = glass({ LayoutOrder = t, Parent = tiers }, 12)
			Kit.new("Frame", {
				BackgroundColor3 = Achievements.TierColors[t],
				BorderSizePixel = 0,
				Rotation = 45,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 14, 0.5, 0),
				Size = UDim2.fromOffset(14, 14),
				Parent = cell,
			}, { Kit.corner(3) })
			Kit.label(tostring(counts[t]), { Font = Theme.FontTitle, TextSize = 22, TextWrapped = false, Position = UDim2.fromOffset(38, 6), Size = UDim2.new(1, -44, 0, 26), Parent = cell })
			Kit.label(Achievements.TierNames[t], { TextSize = 12, TextColor3 = Achievements.TierColors[t], TextWrapped = false, Position = UDim2.fromOffset(38, 32), Size = UDim2.new(1, -44, 0, 16), Parent = cell })
		end

		-- Closest to their next tier (secrets stay secret).
		local close = {}
		for _, a in Achievements.list do
			local tier = Achievements.earnedTier(p.achievements, a.id)
			if not (a.hidden and tier == 0) then
				local value, goal, nextTier = Achievements.progress(p, a, tier)
				if nextTier and value > 0 then
					table.insert(close, { a = a, f = value / goal })
				end
			end
		end
		table.sort(close, function(x, y)
			return x.f > y.f
		end)
		if #close > 0 then
			section("Almost there")
			local list = {}
			for i = 1, math.min(if compact then 3 else 4, #close) do
				table.insert(list, close[i].a)
			end
			cards(list, true)
		end

		-- Earned most recently.
		local recent = {}
		for id, entry in p.achievements do
			local a = Achievements.get(id)
			if a and type(entry) == "table" then
				table.insert(recent, { a = a, at = entry.at or 0 })
			end
		end
		table.sort(recent, function(x, y)
			return x.at > y.at
		end)
		if #recent > 0 then
			section("Earned lately")
			local list = {}
			for i = 1, math.min(if compact then 4 else 6, #recent) do
				table.insert(list, recent[i].a)
			end
			cards(list, true)
		else
			section("Your first badge", "Finish a game to earn Regular I. Every achievement has five tiers, Bronze to Diamond, and each one pays more than the last.")
		end
	end

	local function renderGeneral(p: any)
		for _, group in Achievements.Groups do
			local list = {}
			for _, a in Achievements.general() do
				if a.group == group.key then
					table.insert(list, a)
				end
			end
			if #list > 0 then
				section(group.name)
				cards(list)
			end
		end
		local _ = p
	end

	local function renderGame(p: any, gameId: string)
		local entry = GameCatalog.get(gameId)
		local back = Kit.button("< All games", function()
			gameOpen = nil
			render()
		end, { Size = UDim2.new(0, 140, 0, 30), TextSize = 14, BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, LayoutOrder = nextOrder(), Parent = content })
		local _ = back
		local have, total = Achievements.gameProgress(p.achievements, gameId)
		local mastered = Achievements.mastered(p.achievements, gameId)
		local masteryItem = ShopCatalog.get(Achievements.masteryTitle(gameId))
		section(
			`{GameArt.icon(gameId)} {if entry then entry.name else gameId}`,
			if mastered
				then `Mastered! {have} of {total} badges.`
				else `{have} of {total} badges. Get every one of them to Gold to master it: +{Economy.AchievementRewards.mastery.gems} {Economy.GemsName} and {if masteryItem then masteryItem.name else "a title"}.`
		)
		cards(Achievements.forGame(gameId))
	end

	local function renderGames(p: any)
		if gameOpen then
			renderGame(p, gameOpen)
			return
		end
		section("Every game", `Master a game by getting all its achievements to Gold. You've mastered {p.totals and p.totals.mastered or 0}.`)
		local container = grid(86, if compact then 2 else 4)
		local entries = {}
		for _, entry in GameCatalog.entries do
			if entry.status == "ready" then
				table.insert(entries, entry)
			end
		end
		-- Most progress first, then by name.
		table.sort(entries, function(x, y)
			local hx, tx = Achievements.gameProgress(p.achievements, x.id)
			local hy, ty = Achievements.gameProgress(p.achievements, y.id)
			local fx, fy = hx / math.max(1, tx), hy / math.max(1, ty)
			if fx ~= fy then
				return fx > fy
			end
			return x.name < y.name
		end)
		for i, entry in entries do
			local have, total = Achievements.gameProgress(p.achievements, entry.id)
			local mastered = Achievements.mastered(p.achievements, entry.id)
			local tile = Kit.new("TextButton", {
				Name = entry.id,
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = Theme.Panel,
				BackgroundTransparency = if Kit.lounge then 0.18 else 0,
				BorderSizePixel = 0,
				LayoutOrder = i,
				Parent = container,
			}, { Kit.corner(12), Kit.frameStroke() })
			if mastered then
				Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 1.5, Parent = tile })
			end
			Kit.label(GameArt.icon(entry.id), { TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(36, 36), Parent = tile })
			Kit.label(entry.name, {
				Font = Theme.FontBold,
				TextSize = 14,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Position = UDim2.fromOffset(50, 10),
				Size = UDim2.new(1, -56, 0, 18),
				Parent = tile,
			})
			Kit.label(if mastered then "MASTERED" else `{have}/{total} badges`, {
				TextSize = 12,
				Font = if mastered then Theme.FontBold else Theme.Font,
				TextColor3 = if mastered then Theme.Accent else Theme.SubText,
				TextWrapped = false,
				Position = UDim2.fromOffset(50, 28),
				Size = UDim2.new(1, -56, 0, 16),
				Parent = tile,
			})
			local _, set = Kit.progress(if mastered then Theme.Accent else Achievements.TierColors[3], { Position = UDim2.new(0, 10, 1, -20), Size = UDim2.new(1, -20, 0, 8), Parent = tile })
			set(have / math.max(1, total))
			Kit.pressable(tile)
			Kit.onPress(tile, function()
				gameOpen = entry.id
				content.CanvasPosition = Vector2.zero
				render()
			end)
		end
	end

	function render()
		Kit.clear(content)
		order = 0
		for key, t in tabButtons do
			local selected = key == tab
			t.button.TextColor3 = if selected then Theme.Text else Theme.SubText
			t.line.Visible = selected
			t.button.TextSize = if compact then 15 else 17
		end
		local p = profile
		if not p or type(p.achievements) ~= "table" then
			scoreLabel.Text = ""
			Kit.label("Loading...", { TextColor3 = Theme.SubText, TextSize = 14, Size = UDim2.new(1, 0, 0, 20), Parent = content })
			return
		end
		local points, badges, total = Achievements.score(p.achievements)
		scoreLabel.Text = `🏆 {commas(points)}   ·   {badges}/{total} badges`
		if tab == "overview" then
			renderOverview(p)
		elseif tab == "general" then
			renderGeneral(p)
		else
			renderGames(p)
		end
	end
	local _ = title

	Layout.onChange(function(info)
		window.fit(info.top, info.bottom)
		local wasCompact = compact
		compact = info.compact
		if wasCompact ~= compact and window.isOpen() then
			render()
		end
	end)

	local api = {}

	-- Opens on a tab ("overview" | "general" | "games"), or a game's list (a game id).
	function api.open(what: string?)
		window.open()
		if what and GameCatalog.get(what) then
			tab, gameOpen = "games", what
		elseif what then
			tab, gameOpen = what, nil
		end
		send({ action = "profile" })
		render()
	end

	function api.close()
		window.close()
	end

	function api.isOpen(): boolean
		return window.isOpen()
	end

	-- StatsState from the server (only your own profile is drawn here).
	function api.setState(message: any)
		if type(message) ~= "table" or message.kind ~= "profile" or type(message.profile) ~= "table" then
			return
		end
		if message.profile.userId ~= localPlayer.UserId then
			return
		end
		profile = message.profile
		if window.isOpen() then
			render()
		end
	end

	return api
end

return AchievementsPanel
