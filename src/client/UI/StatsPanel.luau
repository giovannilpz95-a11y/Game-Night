-- The stats window (📊 Stats on the side rail): a player's level, totals, per-game
-- records, badges and this week's leaderboards. Opens on your own profile; the Party
-- window's 📊 buttons and the leaderboard rows open other players in this server.
-- The server sends everything (ProgressionService); this only draws it and asks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local StatsCatalog = require(ReplicatedStorage.Shared.StatsCatalog)
local Badges = require(ReplicatedStorage.Shared.Badges)
local Economy = require(ReplicatedStorage.Shared.Economy)
local GameArt = require(ReplicatedStorage.Shared.GameArt)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)
local Theme = Kit.Theme

local StatsPanel = {}

local localPlayer = Players.LocalPlayer
local OVERALL = "_all"

local TABS = {
	{ key = "overview", name = "Overview" },
	{ key = "games", name = "Games" },
	{ key = "badges", name = "Badges" },
	{ key = "weekly", name = "Weekly" },
}

local function duration(minutes: number): string
	minutes = math.floor(minutes + 0.5)
	if minutes < 60 then
		return `{minutes}m`
	end
	local hours = minutes // 60
	if hours < 48 then
		return `{hours}h {minutes % 60}m`
	end
	return `{hours // 24}d {hours % 24}h`
end

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function winRate(row: any): string
	if row.played == 0 then
		return "-"
	end
	return `{math.floor(100 * row.wins / row.played + 0.5)}%`
end

local function date(unix: number, format: string): string
	local ok, text = pcall(function()
		return DateTime.fromUnixTimestamp(unix):FormatUniversalTime(format, "en-us")
	end)
	return if ok then text else ""
end

local function gameName(gameId: string): string
	local entry = GameCatalog.get(gameId)
	return if entry then entry.name else gameId
end

function StatsPanel.create(parent: Instance, send: (any) -> ())
	local window = Kit.modal(parent, { name = "StatsWindow", maxSize = Vector2.new(860, 640) })
	local body = window.body

	local title = Kit.label("Stats", { TextSize = 22, Font = Theme.FontTitle, Size = UDim2.new(1, -48, 0, 28), Parent = body })
	local tabRow = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 34),
		Size = UDim2.new(1, 0, 0, 34),
		Parent = body,
	}, { Kit.list(6, true) })
	local content = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 76),
		Size = UDim2.new(1, 0, 1, -76),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		Parent = body,
	}, { Kit.list(8), Kit.new("UIPadding", { PaddingRight = UDim.new(0, 8) }) })

	local profile: any = nil
	local viewing = localPlayer.UserId -- whose profile the window shows
	local function askProfile(userId: number?)
		viewing = userId or localPlayer.UserId
		send({ action = "profile", userId = userId })
	end
	local boards: { [string]: any } = {}
	local tab = "overview"
	local board = OVERALL
	local compact = false
	local render: () -> ()

	local tabButtons: { [string]: TextButton } = {}
	for i, t in TABS do
		tabButtons[t.key] = Kit.button(t.name, function()
			tab = t.key
			if tab == "weekly" then
				send({ action = "board", board = board })
			end
			render()
		end, { Size = UDim2.new(0, 110, 1, 0), TextSize = 15, LayoutOrder = i, Parent = tabRow })
		local corner = tabButtons[t.key]:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(0.5, 0)
		end
	end

	-- Building blocks -----------------------------------------------------------------

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local function section(text: string)
		Kit.label(text, { Font = Theme.FontBold, TextSize = 18, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = nextOrder(), Parent = content })
	end

	local function note(text: string, color: Color3?)
		Kit.label(text, {
			TextColor3 = color or Theme.SubText,
			TextSize = 14,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = nextOrder(),
			Parent = content,
		})
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
			CellPadding = UDim2.fromOffset(8, 8),
			CellSize = UDim2.new(1 / columns, -8, 0, cellHeight),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = frame,
		})
		return frame
	end

	local function tile(container: Instance, value: string, label: string, index: number)
		local frame = Kit.new("Frame", { BackgroundColor3 = Theme.PanelLight, BorderSizePixel = 0, LayoutOrder = index, Parent = container }, { Kit.corner(10), Kit.shade(0.14) })
		Kit.label(value, {
			Font = Theme.FontTitle,
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 4, 0, 6),
			Size = UDim2.new(1, -8, 0, 28),
			TextScaled = true,
			Parent = frame,
		})
		Kit.label(label, {
			TextColor3 = Theme.SubText,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 4, 0, 36),
			Size = UDim2.new(1, -8, 0, 18),
			Parent = frame,
		})
	end

	local function bar(parentFrame: Instance, fraction: number, color: Color3, position: UDim2, size: UDim2)
		local _, set = Kit.progress(color, { Position = position, Size = size, Parent = parentFrame })
		set(fraction)
	end

	local function card(height: number): Frame
		return Kit.new("Frame", {
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, height),
			LayoutOrder = nextOrder(),
			Parent = content,
		}, { Kit.corner(10), Kit.shade(0.12) })
	end

	-- Tabs ----------------------------------------------------------------------------

	local function renderOverview(p: any)
		local t = p.totals
		local head = card(64)
		Kit.label(`Level {p.level}`, { Font = Theme.FontTitle, TextSize = 24, Position = UDim2.new(0, 12, 0, 6), Size = UDim2.new(0.5, 0, 0, 28), Parent = head })
		Kit.label(`{p.xp} / {p.xpNeeded} XP to level {p.level + 1}`, {
			TextColor3 = Theme.SubText,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.new(0.5, 0, 0, 10),
			Size = UDim2.new(0.5, -12, 0, 20),
			Parent = head,
		})
		bar(head, p.xp / math.max(1, p.xpNeeded), Theme.Accent, UDim2.new(0, 12, 0, 40), UDim2.new(1, -24, 0, 12))

		local columns = if compact then 3 else 4
		local tiles = grid(58, columns)
		local owned = 0
		for _ in p.badges do
			owned += 1
		end
		local cells = {
			{ commas(t.matches), "Games played" },
			{ commas(t.wins), "Wins" },
			{ if t.matches > 0 then `{math.floor(100 * t.wins / t.matches + 0.5)}%` else "-", "Win rate" },
			{ `{t.bestStreak}`, "Best win streak" },
			{ `{t.streak}`, "Current streak" },
			{ duration(t.minutes), "Time played" },
			{ `{t.gamesTried}/{Badges.AllGames}`, "Games tried" },
			{ `{owned}/{#Badges.list}`, "Badges" },
			{ commas(t.humanMatches), "Games with people" },
			{ commas(t.humanWins), "Wins vs people" },
			{ `{t.daysPlayed}`, "Days played" },
			{ `{t.bestLoginStreak}`, "Best login streak" },
		}
		for i, cell in cells do
			tile(tiles, cell[1], cell[2], i)
		end
		note(`{commas(t.losses)} losses · {commas(t.draws)} draws · {commas(t.botMatches)} games with only bots`)

		section("Friends")
		local social = grid(58, columns)
		tile(social, commas(p.social.friendsJoined or 0), "Joined from your invites", 1)
		tile(social, commas(p.social.invitesSent or 0), "Invites sent", 2)
		tile(social, commas(p.social.partiesJoined or 0), "Parties joined", 3)

		section("Gems and Coins")
		local c = p.currency
		local wallet = grid(58, columns)
		tile(wallet, commas(c.gemsEarned), "Gems earned", 1)
		if p.mine then
			tile(wallet, commas(c.gemsBought or 0), "Gems bought", 2)
		end
		tile(wallet, commas(c.gemsSpent), "Gems spent", 3)
		tile(wallet, commas(c.coinsEarned), "Coins earned", 4)
		tile(wallet, commas(c.coinsSpent), "Coins spent", 5)
		if p.mine and c.coins then
			local keys = {}
			for key in c.coins do
				table.insert(keys, key)
			end
			table.sort(keys, function(a, b)
				local ca, cb = Economy.Coins[a], Economy.Coins[b]
				return (if ca then ca.order else 99) < (if cb then cb.order else 99)
			end)
			for _, key in keys do
				local row = c.coins[key]
				note(`{Economy.coinName(key)}: {commas(row.earned)} earned, {commas(row.spent)} spent`, Theme.Text)
			end
		end
		if p.joined and p.joined > 0 then
			note(`Playing since {date(p.joined, "LL")}`)
		end
	end

	local function renderGames(p: any)
		local played, unplayed = {}, {}
		for _, entry in GameCatalog.entries do
			local row = p.games[entry.id]
			if row and row.played > 0 then
				table.insert(played, entry.id)
			elseif entry.status == "ready" then
				table.insert(unplayed, entry.id)
			end
		end
		table.sort(played, function(a, b)
			return p.games[a].played > p.games[b].played
		end)
		if #played == 0 then
			note("No games finished yet. Press Play and pick one!")
		end
		for _, gameId in played do
			local row = p.games[gameId]
			local catalog = StatsCatalog.get(gameId)
			local lines = {
				`{row.played} played · {row.wins} W  {row.losses} L  {row.draws} D · {winRate(row)} wins`,
				`Streak {row.streak} (best {row.bestStreak}) · {duration(row.minutes)} played{if row.fastestWin > 0 then ` · fastest win {duration(math.max(1, row.fastestWin))}` else ""}`,
			}
			if row.humanWins > 0 then
				table.insert(lines, `{row.humanWins} wins against people`)
			end
			if catalog.score and row.bestScore ~= nil then
				table.insert(lines, `{catalog.score.label}: {commas(row.bestScore)}`)
			end
			local extras = {}
			for _, def in catalog.extra or {} do
				local value = row.extra and row.extra[def.key]
				if value and value > 0 then
					table.insert(extras, `{def.label}: {commas(value)}`)
				end
			end
			if #extras > 0 then
				table.insert(lines, table.concat(extras, " · "))
			end
			local frame = card(34 + 20 * #lines)
			Kit.label(`{GameArt.icon(gameId)}  {gameName(gameId)}`, { Font = Theme.FontBold, TextSize = 17, Position = UDim2.new(0, 12, 0, 6), Size = UDim2.new(1, -24, 0, 22), Parent = frame })
			for i, text in lines do
				Kit.label(text, {
					TextColor3 = if i == 1 then Theme.Text else Theme.SubText,
					TextSize = 14,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextWrapped = false,
					Position = UDim2.new(0, 12, 0, 10 + 20 * i),
					Size = UDim2.new(1, -24, 0, 18),
					Parent = frame,
				})
			end
		end
		if #unplayed > 0 then
			local names = {}
			for _, gameId in unplayed do
				table.insert(names, gameName(gameId))
			end
			section("Not played yet")
			note(table.concat(names, ", "))
		end
	end

	local function renderBadges(p: any)
		local owned = 0
		for _ in p.badges do
			owned += 1
		end
		note(`{owned} of {#Badges.list} earned. Badges pay {Economy.BadgeGems[1]} / {Economy.BadgeGems[2]} / {Economy.BadgeGems[3]} Gems (bronze / silver / gold), once.`)
		local columns = if compact then 2 else 3
		local container = grid(92, columns)
		-- Earned first (newest first), then closest to done.
		local list = table.clone(Badges.list)
		local function progress(badge: any): number
			local current, goal = Badges.progress(p, badge)
			return current / goal
		end
		table.sort(list, function(a, b)
			local ea, eb = p.badges[a.id], p.badges[b.id]
			if (ea ~= nil) ~= (eb ~= nil) then
				return ea ~= nil
			end
			if ea and eb then
				return ea > eb
			end
			return progress(a) > progress(b)
		end)
		for i, badge in list do
			local earned = p.badges[badge.id] ~= nil
			local color = Badges.TierColors[badge.tier] or Theme.SubText
			local frame = Kit.new("Frame", {
				BackgroundColor3 = Theme.PanelLight,
				BackgroundTransparency = if earned then 0 else 0.35,
				BorderSizePixel = 0,
				LayoutOrder = i,
				Parent = container,
			}, {
				Kit.corner(10),
				Kit.new("UIStroke", { Color = color, Thickness = if earned then 2 else 1, Transparency = if earned then 0 else 0.6 }),
			})
			Kit.label(badge.icon, {
				TextSize = 30,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTransparency = if earned then 0 else 0.5,
				Position = UDim2.new(0, 6, 0, 8),
				Size = UDim2.new(0, 44, 0, 44),
				Parent = frame,
			})
			Kit.label(badge.name, {
				Font = Theme.FontBold,
				TextSize = 15,
				TextColor3 = if earned then color else Theme.Text,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Position = UDim2.new(0, 56, 0, 8),
				Size = UDim2.new(1, -62, 0, 20),
				Parent = frame,
			})
			Kit.label(badge.desc, {
				TextSize = 12,
				TextColor3 = Theme.SubText,
				TextYAlignment = Enum.TextYAlignment.Top,
				Position = UDim2.new(0, 56, 0, 28),
				Size = UDim2.new(1, -62, 0, 32),
				Parent = frame,
			})
			local current, goal = Badges.progress(p, badge)
			if earned then
				Kit.label(`✓ {Badges.TierNames[badge.tier]} · {date(p.badges[badge.id], "ll")}`, {
					TextSize = 12,
					TextColor3 = color,
					Position = UDim2.new(0, 10, 1, -24),
					Size = UDim2.new(1, -20, 0, 18),
					Parent = frame,
				})
			else
				bar(frame, current / goal, color, UDim2.new(0, 10, 1, -18), UDim2.new(1, -80, 0, 8))
				Kit.label(`{commas(current)}/{commas(goal)}`, {
					TextSize = 12,
					TextColor3 = Theme.SubText,
					TextXAlignment = Enum.TextXAlignment.Right,
					Position = UDim2.new(1, -68, 1, -24),
					Size = UDim2.new(0, 60, 0, 18),
					Parent = frame,
				})
			end
		end
	end

	local function renderWeekly()
		-- Board picker: Overall, then every ready game.
		local chips = Kit.new("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 40),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			CanvasSize = UDim2.new(),
			ScrollingDirection = Enum.ScrollingDirection.X,
			ScrollBarThickness = 3,
			LayoutOrder = nextOrder(),
			Parent = content,
		}, { Kit.list(6, true) })
		local choices = { OVERALL }
		for _, entry in GameCatalog.entries do
			if entry.status == "ready" and StatsCatalog.games[entry.id] then
				table.insert(choices, entry.id)
			end
		end
		for i, key in choices do
			local selected = key == board
			local chip = Kit.button(if key == OVERALL then "All games" else gameName(key), function()
				board = key
				send({ action = "board", board = key })
				render()
			end, {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 0, 32),
				TextSize = 14,
				BackgroundColor3 = if selected then Theme.Accent else Theme.PanelLight,
				TextColor3 = if selected then Theme.AccentText else Theme.Text,
				LayoutOrder = i,
				Parent = chips,
			})
			Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = chip })
		end

		local data = boards[board]
		if not data then
			note("Loading...")
			return
		end
		local left = math.max(0, data.endsAt - os.time())
		note(`You: {commas(data.you)} points this week · resets in {duration(left / 60)} (Monday 00:00 UTC)`, Theme.Text)
		if #data.rows == 0 then
			note("Nobody has points on this board yet. Be the first!")
		end
		for _, row in data.rows do
			local me = row.userId == localPlayer.UserId
			local frame = card(36)
			if me then
				Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 2, Parent = frame })
			end
			local medal = ({ "🥇", "🥈", "🥉" })[row.rank] or `#{row.rank}`
			Kit.label(medal, { TextSize = 18, Font = Theme.FontBold, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 6, 0, 0), Size = UDim2.new(0, 40, 1, 0), Parent = frame })
			local name = Kit.label(`{row.name}{if me then " (you)" else ""}`, {
				Position = UDim2.new(0, 50, 0, 0),
				Size = UDim2.new(1, -150, 1, 0),
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Parent = frame,
			})
			Kit.label(`{commas(row.points)} pts`, {
				Font = Theme.FontBold,
				TextXAlignment = Enum.TextXAlignment.Right,
				Position = UDim2.new(1, -100, 0, 0),
				Size = UDim2.new(0, 90, 1, 0),
				Parent = frame,
			})
			if Players:GetPlayerByUserId(row.userId) and not me then
				-- In this server: tap to see their profile.
				local open = Kit.new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = frame })
				open.Activated:Connect(function()
					tab = "overview"
					askProfile(row.userId)
				end)
				name.TextColor3 = Theme.Accent
			end
		end
		if data.source == "server" then
			note("Showing players in this server: the global boards need a published game (or Studio API access).")
		end
		note("Points: 3 for a win with other people, 1 for a draw with other people, 1 for a win against bots. Resigned, very short and over-the-limit games don't count.")
	end

	function render()
		Kit.clear(content)
		order = 0
		for key, button in tabButtons do
			local selected = key == tab
			button.BackgroundColor3 = if selected then Theme.Accent else Theme.PanelLight
			button.TextColor3 = if selected then Theme.AccentText else Theme.Text
			button.Size = UDim2.new(0, if compact then 84 else 110, 1, 0)
			button.TextSize = if compact then 13 else 15
		end
		local p = profile
		if not p then
			title.Text = "Stats"
			note("Loading...")
			return
		end
		local mine = p.userId == localPlayer.UserId
		title.Text = if mine then "Your stats" else `{p.name}'s stats`
		if not mine then
			Kit.button("◂ Back to mine", function()
				askProfile(nil)
			end, { Size = UDim2.new(0, 150, 0, 30), TextSize = 14, BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, LayoutOrder = nextOrder(), Parent = content })
		end
		if tab == "overview" then
			renderOverview(p)
		elseif tab == "games" then
			renderGames(p)
		elseif tab == "badges" then
			renderBadges(p)
		else
			renderWeekly()
		end
	end

	Layout.onChange(function(info)
		window.fit(info.top, info.bottom)
		local wasCompact = compact
		compact = info.compact
		if wasCompact ~= compact and window.isOpen() then
			render()
		end
	end)

	local api = {}

	-- Opens on your own profile, or someone else's (in this server) when userId is given.
	function api.open(userId: number?)
		window.open()
		if userId and userId ~= localPlayer.UserId then
			tab = "overview"
			askProfile(userId)
		else
			askProfile(nil)
		end
		if tab == "weekly" then
			send({ action = "board", board = board })
		end
		render()
	end

	function api.close()
		window.close()
	end

	function api.isOpen(): boolean
		return window.isOpen()
	end

	-- StatsState from the server.
	function api.setState(message: any)
		if type(message) ~= "table" then
			return
		end
		if message.kind == "profile" then
			if type(message.profile) ~= "table" or message.profile.userId ~= viewing then
				return -- an update for a profile we're not showing
			end
			profile = message.profile
		elseif message.kind == "board" then
			boards[message.board] = message
		elseif message.kind == "error" then
			viewing = if profile then profile.userId else localPlayer.UserId
			return
		end
		if window.isOpen() then
			render()
		end
	end

	return api
end

return StatsPanel
