-- The Midnight Lounge lobby HUD (used when Kit.Style is "Lounge"; CafeHud and LobbyHud are
-- the other looks). Same API as CafeHud. Mockup: project files ui-mockups/c-lounge/01-hub.jpg.
--
--   top center    a tab bar inside Roblox's top bar, like Fortnite's: Play (this hub),
--                 Games, Shop, Pass, Avatar, Friends. The open window's tab is lit with a
--                 neon underline;
--   top right     the wallet (client/UI/WalletBar), and under it the gear and "•••" (Stats,
--                 Tables, Host tools, Voice, Help) and today's quests on dark glass;
--   left          your party: one row per player (you first, with your level and XP), then
--                 a dashed "Invite friends" row;
--   bottom left   the season card (tap for the Pass);
--   bottom right  the selected game (live preview, "Change game") and the big yellow PLAY.
--
-- Touch screens keep the bottom corners free for the thumbstick and jump button: the
-- season, quests and game cards hide, the party shrinks to faces and PLAY moves to the
-- bottom center with the game's name above it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Economy = require(ReplicatedStorage.Shared.Economy)
local GameArt = require(ReplicatedStorage.Shared.GameArt)
local Season = require(ReplicatedStorage.Shared.Season)
local Flair = require(script.Parent.Flair)
local GamePreview = require(script.Parent.GamePreview)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)
local Perf = require(script.Parent.Parent.Perf)
local Theme = Kit.Theme

local LoungeHud = {}

local NEON = Color3.fromRGB(124, 92, 255)
local PINK = Color3.fromRGB(255, 79, 163)
local CYAN = Color3.fromRGB(56, 225, 255)
local STAR = Color3.fromRGB(255, 216, 74)
local VOICE_COLOR = Color3.fromRGB(96, 116, 230)
local MAX_ROWS = 5

export type Actions = {
	play: () -> (),
	party: () -> (),
	tables: () -> (),
	stats: () -> (),
	achievements: (() -> ())?,
	shop: () -> (),
	pass: () -> (),
	avatar: () -> (),
	host: () -> (),
	voice: () -> (),
	help: () -> (),
	sound: () -> (),
	settings: (() -> ())?,
	quests: (() -> ())?,
	playGame: ((gameId: string) -> ())?,
	-- Lounge extras: back to this hub (closes every window), the Friends window, which
	-- tab's window is open now, and how wide the wallet is.
	home: (() -> ())?,
	friends: (() -> ())?,
	current: (() -> string?)?,
	walletWidth: (() -> number)?,
}

local function round(object: GuiObject)
	local corner = object:FindFirstChildOfClass("UICorner") or Kit.new("UICorner", { Parent = object })
	corner.CornerRadius = UDim.new(0.5, 0)
end

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- A small uppercase section label ("PARTY · 3/8", "QUESTS").
local function kicker(text: string, props: { [string]: any }): TextLabel
	local label = Kit.label(text, {
		Font = Theme.FontBold,
		TextSize = 13,
		TextColor3 = Theme.SubText,
		TextWrapped = false,
		Size = UDim2.new(1, 0, 0, 18),
	})
	for key, value in props do
		(label :: any)[key] = value
	end
	return label
end

function LoungeHud.create(parent: Instance, actions: Actions)
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local userId = Players.LocalPlayer.UserId
	local buttons: { [string]: GuiObject } = {}
	local badges: { [string]: TextLabel } = {}

	local function badge(holder: GuiObject, key: string, offset: Vector2?)
		local at = offset or Vector2.new(4, -4)
		local b = Kit.label("", {
			Name = "Badge",
			BackgroundColor3 = PINK,
			BackgroundTransparency = 0,
			TextColor3 = Color3.new(1, 1, 1),
			Font = Theme.FontBold,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, at.X, 0, at.Y),
			Size = UDim2.fromOffset(18, 18),
			Visible = false,
			ZIndex = holder.ZIndex + 3,
			Parent = holder,
		})
		Kit.new("UIStroke", { Color = PINK, Transparency = 0.5, Thickness = 2, Parent = b })
		round(b)
		Flair.nudge(b, 4)
		badges[key] = b
	end

	----------------------------------------------------------------------------------
	-- Tab bar
	----------------------------------------------------------------------------------
	local nav = Kit.glass({
		Name = "TabBar",
		AnchorPoint = Vector2.new(0.5, 0.5),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 44),
		-- Above the lobby's windows and their dimmed backdrop, so the tabs switch pages
		-- while one is open.
		ZIndex = 40,
		Parent = parent,
	}, 14)
	Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), Parent = nav })
	local navList = Kit.list(2, true)
	navList.VerticalAlignment = Enum.VerticalAlignment.Center
	navList.Parent = nav
	local navScale = Kit.new("UIScale", { Name = "FitScale", Parent = nav })
	local tabs: { [string]: TextButton } = {}
	local activeTab = "Play"

	local function paintTab(key: string)
		for name, tab in tabs do
			local on = name == key
			tab.BackgroundTransparency = if on then 0.62 else 1
			tab.TextColor3 = if on then Color3.new(1, 1, 1) else Theme.SubText
			local line = tab:FindFirstChild("Underline") :: Frame?
			if line then
				line.Visible = on
			end
		end
	end

	local function tab(key: string, order: number, onClick: () -> ())
		local button = Kit.new("TextButton", {
			Name = key,
			Text = key:upper(),
			Font = Theme.FontTitle,
			TextSize = 19,
			TextColor3 = Theme.SubText,
			AutoButtonColor = false,
			BackgroundColor3 = NEON,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 36),
			LayoutOrder = order,
			ZIndex = 6,
			Parent = nav,
		}, {
			Kit.corner(10),
			Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }),
		})
		Kit.headline(button)
		-- The lit tab's neon underline (a soft glow from its own stroke).
		Kit.new("Frame", {
			Name = "Underline",
			BackgroundColor3 = Theme.Accent,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 1),
			Size = UDim2.new(1, -12, 0, 3),
			Visible = false,
			ZIndex = 7,
			Parent = button,
		}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), Kit.new("UIStroke", { Color = Theme.Accent, Transparency = 0.6, Thickness = 2 }) })
		badge(button, key, Vector2.new(8, -6))
		Kit.onPress(button, function()
			activeTab = key
			paintTab(key)
			onClick()
		end)
		Kit.pressable(button)
		button.MouseEnter:Connect(function()
			if activeTab ~= key then
				button.TextColor3 = Theme.Text
			end
		end)
		button.MouseLeave:Connect(function()
			if activeTab ~= key then
				button.TextColor3 = Theme.SubText
			end
		end)
		tabs[key] = button
		buttons[key] = button
	end
	tab("Play", 1, actions.home or function() end)
	tab("Games", 2, actions.play)
	tab("Shop", 3, actions.shop)
	tab("Pass", 4, actions.pass)
	tab("Avatar", 5, actions.avatar)
	tab("Friends", 6, actions.friends or actions.party)
	paintTab("Play")
	-- Follow the windows: closing one (X, tapping outside) lights Play again.
	if actions.current then
		task.spawn(function()
			while nav.Parent do
				local now = actions.current() or "Play"
				if now ~= activeTab then
					activeTab = now
					paintTab(now)
				end
				task.wait(0.2)
			end
		end)
	end

	----------------------------------------------------------------------------------
	-- Gear and More, under the wallet
	----------------------------------------------------------------------------------
	local corner = Kit.new("Frame", {
		Name = "TopRight",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 40),
		ZIndex = 5,
		Parent = parent,
	})
	local cornerList = Kit.list(8, true)
	cornerList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	cornerList.Parent = corner
	local function squareButton(name: string, text: string, order: number, onClick: () -> ()): TextButton
		local button = Kit.new("TextButton", {
			Name = name,
			Text = text,
			Font = Theme.FontBold,
			TextSize = 18,
			TextColor3 = Theme.Text,
			AutoButtonColor = true,
			BackgroundColor3 = Theme.PanelLight,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(40, 40),
			LayoutOrder = order,
			ZIndex = 6,
			Parent = corner,
		}, { Kit.corner(10), Kit.frameStroke() })
		Kit.onPress(button, onClick)
		Kit.pressable(button)
		buttons[name] = button
		return button
	end

	local catcher = Kit.new("TextButton", {
		Name = "MoreCatcher",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 14,
		Parent = parent,
	})
	local pop = Kit.glass({
		Name = "MoreMenu",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(230, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.06,
		Visible = false,
		ZIndex = 15,
		Parent = parent,
	}, 14)
	Kit.padding(6).Parent = pop
	Kit.list(2).Parent = pop
	local function closeMore()
		catcher.Visible = false
		pop.Visible = false
	end
	catcher.Activated:Connect(closeMore)
	local moreRows: { [string]: TextButton } = {}
	local function moreRow(key: string, order: number, icon: string, label: string, onClick: () -> ())
		local row = Kit.new("TextButton", {
			Name = key,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = NEON,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 40),
			LayoutOrder = order,
			ZIndex = 16,
			Parent = pop,
		}, { Kit.corner(10) })
		row.MouseEnter:Connect(function()
			row.BackgroundTransparency = 0.7
		end)
		row.MouseLeave:Connect(function()
			row.BackgroundTransparency = 1
		end)
		Kit.label(icon, { Name = "Icon", TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(4, 0), Size = UDim2.new(0, 34, 1, 0), ZIndex = 17, Parent = row })
		Kit.label(label, { Name = "Text", Font = Theme.FontBold, TextSize = 15, Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -46, 1, 0), TextWrapped = false, ZIndex = 17, Parent = row })
		Kit.onPress(row, function()
			closeMore()
			onClick()
		end)
		Kit.pressable(row)
		moreRows[key] = row
	end
	moreRow("Stats", 1, "📊", "Your stats", actions.stats)
	if actions.achievements then
		moreRow("Achievements", 2, "🏆", "Achievements", actions.achievements)
	end
	moreRow("Tables", 3, "🎲", "Tables in this server", actions.tables)
	moreRow("Host", 4, "👑", "Host tools", actions.host)
	moreRow("Voice", 5, "🎙", "Voice chat", actions.voice)
	moreRow("Help", 6, "❔", "Help and rules", actions.help)
	moreRows.Voice.Visible = false

	local more: TextButton
	more = squareButton("More", "•••", 1, function()
		local show = not pop.Visible
		catcher.Visible = show
		pop.Visible = show
		if show then
			local abs = more.AbsolutePosition
			local inset = (parent :: any).AbsolutePosition :: Vector2
			pop.Position = UDim2.fromOffset(abs.X - inset.X + more.AbsoluteSize.X, abs.Y - inset.Y + more.AbsoluteSize.Y + 8)
			Kit.popIn(pop)
		end
	end)
	badge(more, "More")
	local gear = squareButton("SettingsButton", "⚙️", 2, actions.settings or actions.sound)

	----------------------------------------------------------------------------------
	-- Quests: today's three on dark glass.
	----------------------------------------------------------------------------------
	local questCard = Kit.glass({
		Name = "QuestCard",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(330, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 5,
		Parent = parent,
	}, 14)
	Kit.new("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		Parent = questCard,
	})
	Kit.list(8).Parent = questCard
	local questHead = Kit.new("TextButton", {
		Name = "Head",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 0,
		ZIndex = 6,
		Parent = questCard,
	})
	kicker("QUESTS", { ZIndex = 6, Size = UDim2.new(1, -90, 1, 0), Parent = questHead })
	local questTimer = kicker("", {
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 90, 1, 0),
		ZIndex = 6,
		Parent = questHead,
	})
	local openQuests = actions.quests or actions.pass
	questHead.Activated:Connect(openQuests)
	local questRows = Kit.new("TextButton", {
		Name = "Rows",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		ZIndex = 6,
		Parent = questCard,
	}, { Kit.list(10) })
	questRows.Activated:Connect(openQuests)
	buttons.Quests = questCard

	local function renderQuests(quests: { any }?)
		Kit.clear(questRows)
		local list = quests or {}
		if #list == 0 then
			Kit.label("Play any game to get today's quests.", { TextSize = 14, TextColor3 = Theme.SubText, Size = UDim2.new(1, 0, 0, 18), ZIndex = 6, Parent = questRows })
		end
		for i, quest in list do
			if i > 3 then
				break
			end
			local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = i, ZIndex = 6, Parent = questRows })
			local done = quest.done == true
			Kit.label(`{if done then "✓ " else ""}{quest.text or "Quest"}`, {
				TextSize = 15,
				Font = Theme.FontBold,
				TextColor3 = if done then Theme.Good else Theme.Text,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Size = UDim2.new(1, -70, 0, 18),
				ZIndex = 6,
				Parent = row,
			})
			Kit.label(`{commas(quest.stars or 0)} ⭐`, {
				TextSize = 14,
				Font = Theme.FontBold,
				TextColor3 = STAR,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Size = UDim2.fromOffset(68, 18),
				TextWrapped = false,
				ZIndex = 6,
				Parent = row,
			})
			local bar, set = Kit.progress(if done then Theme.Good else NEON, {
				Position = UDim2.fromOffset(0, 23),
				Size = UDim2.new(1, 0, 0, 5),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.88,
				ZIndex = 6,
				Parent = row,
			})
			local fill = bar:FindFirstChild("Fill") :: Frame?
			if fill then
				fill.ZIndex = 7
			end
			local target = tonumber(quest.target) or 0
			local progress = tonumber(quest.progress) or 0
			set(if done then 1 elseif target > 0 then progress / target else 0)
		end
	end
	renderQuests(nil)
	task.spawn(function()
		while questCard.Parent do
			local now = os.time()
			local left = (now // 86400 + 1) * 86400 - now
			questTimer.Text = if left >= 3600 then `{left // 3600}H {left % 3600 // 60}M` else `{left // 60}M`
			task.wait(30)
		end
	end)

	----------------------------------------------------------------------------------
	-- Party: a row per player, you first, then "Invite friends".
	----------------------------------------------------------------------------------
	local partyBox = Kit.new("Frame", {
		Name = "Party",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(250, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 5,
		Parent = parent,
	}, { Kit.list(8) })
	local partyHead = kicker("PARTY", { Name = "Head", LayoutOrder = 0, ZIndex = 5, TextSize = 14, Parent = partyBox })
	local partyRows = Kit.new("Frame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		ZIndex = 5,
		Parent = partyBox,
	}, { Kit.list(8) })
	buttons.Party = partyBox
	local slim = false -- phone: faces only
	local myLevel, myXp, myNeed = 1, 0, 0

	local function memberRow(member: any, order: number, party: any?)
		local isMe = member.userId == userId
		local isLeader = party ~= nil and member.userId == party.leaderId
		local rowH = if slim then 48 else 58
		local row = Kit.new("TextButton", {
			Name = if isMe then "You" else "Member",
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Panel,
			BackgroundTransparency = 0.18,
			BorderSizePixel = 0,
			Size = if slim then UDim2.fromOffset(rowH, rowH) else UDim2.new(1, 0, 0, rowH),
			LayoutOrder = order,
			ZIndex = 6,
			Parent = partyRows,
		}, { Kit.corner(12), Kit.frameStroke() })
		Kit.onPress(row, if isMe then actions.stats else actions.party)
		Kit.pressable(row)
		local face = Kit.avatar(member.userId, rowH - 14, {
			Position = UDim2.fromOffset(7, 7),
			BackgroundColor3 = Theme.PanelLight,
			ZIndex = 7,
			Parent = row,
		})
		local ring = face:FindFirstChildOfClass("UIStroke")
		if ring then
			ring.Color = if isLeader then Theme.Accent else Color3.new(1, 1, 1)
			ring.Transparency = if isLeader then 0 else 0.7
			ring.Thickness = 2
		end
		if slim then
			return
		end
		Kit.label(member.name or "Player", {
			Name = "PlayerName",
			Font = Theme.FontBold,
			TextSize = 17,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(rowH + 2, 9),
			Size = UDim2.new(1, -(rowH + 64), 0, 20),
			ZIndex = 7,
			Parent = row,
		})
		local status = if isLeader and #(party and party.members or {}) > 1 then "Picks the game" elseif isMe then "That's you" else "Ready"
		Kit.label(status, {
			Name = "Status",
			Font = Theme.FontBold,
			TextSize = 13,
			TextColor3 = if isLeader then Theme.Accent else Theme.Good,
			TextWrapped = false,
			Position = UDim2.fromOffset(rowH + 2, 30),
			Size = UDim2.new(1, -(rowH + 64), 0, 16),
			ZIndex = 7,
			Parent = row,
		})
		if isMe then
			Kit.label(`LV {myLevel}`, {
				Name = "Level",
				Font = Theme.FontBold,
				TextSize = 13,
				TextColor3 = Theme.SubText,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 11),
				Size = UDim2.fromOffset(56, 16),
				TextWrapped = false,
				ZIndex = 7,
				Parent = row,
			})
			local bar, set = Kit.progress(Theme.Accent, {
				Name = "XP",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 33),
				Size = UDim2.fromOffset(52, 5),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.85,
				ZIndex = 7,
				Parent = row,
			})
			local fill = bar:FindFirstChild("Fill") :: Frame?
			if fill then
				fill.ZIndex = 8
			end
			set(if myNeed > 0 then myXp / myNeed else 0)
		end
	end

	local lastParty: any = nil
	local function renderParty(party: any)
		lastParty = party
		Kit.clear(partyRows)
		local members = if party and type(party.members) == "table" then party.members else { { userId = userId, name = Players.LocalPlayer.DisplayName } }
		-- You first, then everyone else in join order.
		local ordered = {}
		for _, member in members do
			if member.userId == userId then
				table.insert(ordered, 1, member)
			else
				table.insert(ordered, member)
			end
		end
		local maxSize = if party and tonumber(party.maxSize) then party.maxSize else nil
		partyHead.Text = if maxSize then `PARTY  ·  {#members}/{maxSize}` else "PARTY"
		partyHead.Visible = not slim
		for i, member in ordered do
			if i > MAX_ROWS then
				Kit.label(`+{#ordered - MAX_ROWS} more`, { Font = Theme.FontBold, TextSize = 13, TextColor3 = Theme.SubText, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = i, ZIndex = 6, Parent = partyRows })
				break
			end
			memberRow(member, i, party)
		end
		-- The empty seat: invite more.
		local rowH = if slim then 48 else 58
		local invite = Kit.new("TextButton", {
			Name = "Invite",
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Background,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			Size = if slim then UDim2.fromOffset(rowH, rowH) else UDim2.new(1, 0, 0, rowH),
			LayoutOrder = 99,
			ZIndex = 6,
			Parent = partyRows,
		}, { Kit.corner(12), Kit.new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.72, Thickness = 1.5 }) })
		Kit.onPress(invite, actions.party)
		Kit.pressable(invite)
		local plus = Kit.label("+", {
			Font = Theme.FontBold,
			TextSize = 22,
			TextColor3 = Theme.Text,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(7, 7),
			Size = UDim2.fromOffset(rowH - 14, rowH - 14),
			ZIndex = 7,
			Parent = invite,
		})
		Kit.new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.6, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = plus })
		round(plus)
		badge(invite, "Party")
		if not slim then
			Kit.label("Invite friends", { Font = Theme.FontBold, TextSize = 17, Position = UDim2.fromOffset(rowH + 2, 9), Size = UDim2.new(1, -(rowH + 8), 0, 20), TextWrapped = false, ZIndex = 7, Parent = invite })
			Kit.label(`+{Economy.FriendInviteGems} Gems each`, { Font = Theme.FontBold, TextSize = 13, TextColor3 = Theme.Good, Position = UDim2.fromOffset(rowH + 2, 30), Size = UDim2.new(1, -(rowH + 8), 0, 16), TextWrapped = false, ZIndex = 7, Parent = invite })
		end
	end
	renderParty(nil)

	----------------------------------------------------------------------------------
	-- Season card: the Pass's current season, tap to open it.
	----------------------------------------------------------------------------------
	local news = Kit.new("TextButton", {
		Name = "SeasonCard",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromOffset(340, 168),
		ZIndex = 5,
		Parent = parent,
	}, {
		Kit.corner(14),
		Kit.frameStroke(),
		Kit.new("UIGradient", {
			Name = "Sky",
			Rotation = 25,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 24, 110)),
				ColorSequenceKeypoint.new(0.6, NEON),
				ColorSequenceKeypoint.new(1, CYAN),
			}),
		}),
	})
	Kit.onPress(news, actions.pass)
	Kit.pressable(news)
	local newsIcon = Kit.label("", {
		Name = "Icon",
		TextSize = 64,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(90, 80),
		Rotation = 8,
		TextTransparency = 0.1,
		ZIndex = 6,
		Parent = news,
	})
	local newsTitle = Kit.label("", {
		Name = "Title",
		Font = Theme.FontTitle,
		TextSize = 36,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextStrokeTransparency = 0.7,
		Position = UDim2.fromOffset(16, 46),
		Size = UDim2.new(1, -32, 0, 40),
		ZIndex = 6,
		Parent = news,
	})
	local newsSub = Kit.label("", {
		Name = "Sub",
		Font = Theme.FontBold,
		TextSize = 14,
		TextWrapped = false,
		TextStrokeTransparency = 0.7,
		Position = UDim2.fromOffset(16, 88),
		Size = UDim2.new(1, -32, 0, 18),
		ZIndex = 6,
		Parent = news,
	})
	local newsFoot = Kit.new("Frame", {
		Name = "Foot",
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 44),
		ZIndex = 6,
		Parent = news,
	})
	local newsLine = Kit.label("", {
		Name = "Line",
		Font = Theme.FontBold,
		TextSize = 14,
		TextColor3 = Theme.SubText,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -32, 1, 0),
		ZIndex = 7,
		Parent = newsFoot,
	})
	local function renderSeason()
		local now = os.time()
		local n = Season.number(now)
		if n < 1 then
			newsTitle.Text = "GAME NIGHT PASS"
			newsSub.Text = "The first season starts soon"
			newsLine.Text = "Play to earn Stars"
			newsIcon.Text = "🎟️"
		else
			local track = Season.track(n)
			local daysLeft = math.max(0, math.ceil((Season.endsAt(n) - now) / 86400))
			newsTitle.Text = string.upper(track.name)
			newsSub.Text = `Season {n} is live  ·  {daysLeft} {if daysLeft == 1 then "day" else "days"} left`
			newsLine.Text = if Season.isFinalWeek(now) then "Last week: double Stars from every game" else track.blurb
			newsIcon.Text = track.icon
		end
		Kit.headline(newsTitle, false)
	end
	renderSeason()
	task.spawn(function()
		while news.Parent do
			task.wait(600)
			renderSeason()
		end
	end)

	----------------------------------------------------------------------------------
	-- Selected game and PLAY
	----------------------------------------------------------------------------------
	local selected = Kit.glass({
		Name = "UpNext",
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(380, 120),
		ZIndex = 5,
		Parent = parent,
	}, 14)
	local art = Kit.new("Frame", {
		Name = "Art",
		BackgroundColor3 = Theme.Felt,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(0, 150, 1, -20),
		ClipsDescendants = true,
		ZIndex = 6,
		Parent = selected,
	}, { Kit.corner(10) })
	local artIcon = Kit.label("🎲", { Name = "Icon", TextSize = 44, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 7, Parent = art })
	local artImage = Kit.new("ImageLabel", { Name = "Image", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Crop, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 8, Parent = art }, { Kit.corner(10) })
	local upLabel = kicker("SELECTED GAME", {
		Name = "Kicker",
		TextColor3 = Theme.SubText,
		Position = UDim2.fromOffset(172, 10),
		Size = UDim2.new(1, -184, 0, 16),
		ZIndex = 6,
		Parent = selected,
	})
	local upName = Kit.label("Pick a game", {
		Name = "GameName",
		Font = Theme.FontTitle,
		TextSize = 30,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(172, 26),
		Size = UDim2.new(1, -184, 0, 34),
		ZIndex = 6,
		Parent = selected,
	})
	local upMeta = Kit.label("", {
		Name = "Meta",
		Font = Theme.FontBold,
		TextSize = 13,
		TextColor3 = Theme.SubText,
		Position = UDim2.fromOffset(172, 62),
		Size = UDim2.new(1, -184, 0, 16),
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 6,
		Parent = selected,
	})
	local change = Kit.new("TextButton", {
		Name = "AllGames",
		Text = "▦  Change game",
		Font = Theme.FontBold,
		TextSize = 14,
		TextColor3 = CYAN,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(172, 84),
		Size = UDim2.new(1, -184, 0, 22),
		ZIndex = 7,
		Parent = selected,
	})
	Kit.onPress(change, actions.play)
	Kit.pressable(change)

	local hint = Kit.label("", {
		Name = "PlayHint",
		Font = Theme.FontBold,
		TextSize = 13,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(380, 18),
		ZIndex = 6,
		Parent = parent,
	})

	local upNextId: string? = nil
	local play = Kit.button("PLAY", function()
		if upNextId and actions.playGame then
			actions.playGame(upNextId)
		else
			actions.play()
		end
	end, {
		Name = "PlayButton",
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(380, 76),
		TextSize = 44,
		Font = Theme.FontTitle,
		ZIndex = 6,
		Parent = parent,
	})
	Kit.headline(play)
	local playCorner = play:FindFirstChildOfClass("UICorner")
	if playCorner then
		playCorner.CornerRadius = UDim.new(0, 14)
	end
	Kit.new("UIGradient", {
		Name = "Shade",
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(235, 220, 200)),
		Parent = play,
	})
	-- The neon glow around it.
	Kit.new("UIStroke", { Name = "Glow", Color = Theme.Accent, Transparency = 0.55, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = play })
	Flair.idleShine(play, 5)

	local preview: any = nil
	local function dropPreview()
		if preview then
			pcall(preview.destroy)
			preview = nil
		end
	end
	local function lobbyShown(): boolean
		local node: Instance? = selected
		while node and node:IsA("GuiObject") do
			if not node.Visible then
				return false
			end
			node = node.Parent
		end
		return true
	end
	local function syncPreview()
		if not preview then
			return
		end
		if lobbyShown() and not Perf.isLow() then
			preview.play()
		else
			preview.pause()
		end
	end
	if parent:IsA("GuiObject") then
		parent:GetPropertyChangedSignal("Visible"):Connect(syncPreview)
	end
	Perf.onChange(syncPreview)

	local currentEntry: any = nil
	local function setUpNext(entry: any?, why: string?)
		dropPreview()
		currentEntry = entry
		upNextId = entry and entry.id or nil
		upName.Text = if entry then entry.name else "Pick a game"
		Kit.headline(upName)
		upLabel.Text = why or "SELECTED GAME"
		if entry then
			local seats = if entry.minSeats == entry.maxSeats then `{entry.minSeats} players` else `{entry.minSeats}-{entry.maxSeats} players`
			local minutes = if entry.typicalMinutes then `  ·  {math.max(1, math.floor(entry.typicalMinutes + 0.5))} min` else ""
			local category = GameArt.category(entry.category)
			upMeta.Text = `{if category then category.name .. "  ·  " else ""}{seats}{minutes}`
			artIcon.Text = GameArt.icon(entry.id)
			local image = GameArt.thumbnail(entry.id)
			artImage.Image = image or ""
			artImage.Visible = image ~= nil
			if not image and not Perf.isLow() then
				local ok, made = pcall(GamePreview.new, entry, art)
				if ok and made then
					preview = made
					made.root.ZIndex = 8
					syncPreview()
				end
			end
		else
			upMeta.Text = "Board, card and party games"
			artIcon.Text = "🎲"
			artImage.Visible = false
		end
	end

	----------------------------------------------------------------------------------
	-- Layout
	----------------------------------------------------------------------------------
	Layout.onChange(function(info)
		local compact = info.compact
		local small = compact or touch
		local margin = if compact then 8 else 16
		local left = info.left + margin
		local right = info.right + margin
		local top = info.top + (if compact then 4 else 10)

		-- Tab bar: centered on the screen inside Roblox's top bar, shrunk to fit beside the
		-- wallet (and left of center if the screen is too narrow to center it).
		local walletW = if actions.walletWidth then actions.walletWidth() else 160
		local stripRight = info.barX + info.barW - walletW - 16
		local barH = math.clamp(info.barH, 32, 48)
		nav.Size = UDim2.fromOffset(0, barH)
		for _, button in tabs do
			button.Size = UDim2.fromOffset(0, barH - 8)
			button.TextSize = if compact then 16 else 19
			local pad = button:FindFirstChildOfClass("UIPadding")
			if pad then
				pad.PaddingLeft = UDim.new(0, if compact then 10 else 16)
				pad.PaddingRight = pad.PaddingLeft
			end
		end
		task.defer(function()
			local natural = nav.AbsoluteSize.X / math.max(navScale.Scale, 0.01)
			local centered = 2 * math.min(info.width / 2 - info.barX, stripRight - info.width / 2)
			local cx = info.width / 2
			local room = centered
			if centered < natural * 0.8 then
				-- Not enough room to center: use the whole free strip.
				room = stripRight - info.barX
				cx = info.barX + room / 2
			end
			navScale.Scale = math.clamp(room / math.max(natural, 1), 0.55, 1)
			nav.Position = UDim2.fromOffset(cx, info.barY + info.barH / 2)
		end)

		-- Gear and More under the wallet; quests under them.
		corner.Position = UDim2.new(1, -right, 0, top)
		questCard.Position = UDim2.new(1, -right, 0, top + 52)
		questCard.Size = UDim2.fromOffset(if info.width >= 1300 then 340 else 300, 0)

		-- Party: left column (faces only on a phone).
		local wasSlim = slim
		slim = small
		partyBox.Position = UDim2.fromOffset(left, top + (if compact then 0 else 4))
		partyBox.Size = UDim2.fromOffset(if slim then 48 else (if info.width >= 1300 then 270 else 240), 0)
		if wasSlim ~= slim then
			renderParty(lastParty)
		end

		-- Bottom corners: the season card and the selected game, with PLAY under it.
		local bottom = info.bottom + (if compact then 10 else 18)
		local cardW = if info.width >= 1300 then 380 else 330
		local playH = if info.height >= 760 then 76 else 62
		news.Position = UDim2.new(0, left, 1, -bottom)
		news.AnchorPoint = Vector2.new(0, 1)
		news.Size = UDim2.fromOffset(if info.width >= 1300 then 340 else 300, if info.height >= 760 then 168 else 140)
		newsSub.Visible = info.height >= 640
		local roomLeft = info.height - bottom - news.Size.Y.Offset - (top + 4 + 66 * 3)
		news.Visible = not small and roomLeft > 0
		questCard.Visible = not small and info.width >= 900

		if small then
			local playW = if compact then 200 else 240
			local playHs = if compact then 52 else 62
			selected.Visible = false
			play.AnchorPoint = Vector2.new(0.5, 1)
			play.Position = UDim2.new(0.5, 0, 1, -bottom)
			play.Size = UDim2.fromOffset(playW, playHs)
			play.TextSize = if compact then 30 else 36
			hint.Position = UDim2.new(0.5, 0, 1, -(bottom + playHs + 4))
			hint.Size = UDim2.fromOffset(math.min(420, info.width - 2 * (left + 64)), 18)
		else
			local showCard = info.height >= 560
			selected.Visible = showCard
			play.AnchorPoint = Vector2.new(1, 1)
			play.Position = UDim2.new(1, -right, 1, -bottom)
			play.Size = UDim2.fromOffset(cardW, playH)
			play.TextSize = if playH >= 70 then 44 else 36
			selected.Position = UDim2.new(1, -right, 1, -(bottom + playH + 10))
			selected.Size = UDim2.fromOffset(cardW, if info.height >= 760 then 120 else 104)
			art.Size = UDim2.new(0, if cardW >= 380 then 150 else 120, 1, -20)
			local textX = art.Size.X.Offset + 22
			for _, label in { upLabel, upName, upMeta, change } do
				label.Position = UDim2.fromOffset(textX, label.Position.Y.Offset)
				label.Size = UDim2.new(1, -(textX + 12), 0, label.Size.Y.Offset)
			end
			local above = if showCard then bottom + playH + 10 + selected.Size.Y.Offset else bottom + playH
			hint.Position = UDim2.new(1, -(right + cardW / 2), 1, -(above + 4))
			hint.Size = UDim2.fromOffset(cardW + 40, 18)
		end
		syncPreview()
	end)

	return {
		-- The button for a lobby tour step: "Play", a tab, the party, or one inside "•••"
		-- (points at "•••").
		target = function(key: string): GuiObject?
			if key == "Play" then
				return play
			elseif key == "Stats" or key == "Achievements" or key == "Help" or key == "Tables" or key == "Host" or key == "Voice" then
				return more
			elseif key == "Sound" or key == "Settings" then
				return gear
			end
			return buttons[key]
		end,
		setPlay = function(text: string, hintText: string?)
			-- PLAY, or "GAMES" when someone else picks.
			play.Text = if text:find("Play") then "PLAY" else text:gsub("^▶%s*", ""):upper()
			hint.Text = hintText or ""
		end,
		setBadge = function(key: string, text: string?)
			local b = badges[key]
			if b then
				b.Text = text or ""
				b.Visible = text ~= nil and text ~= ""
			end
		end,
		setVoice = function(enabled: boolean, onVoiceServer: boolean)
			moreRows.Voice.Visible = enabled
			local text = moreRows.Voice:FindFirstChild("Text") :: TextLabel?
			if text then
				text.Text = if onVoiceServer then "Voice chat: on" else "Voice chat"
			end
			moreRows.Voice.BackgroundColor3 = if onVoiceServer then VOICE_COLOR else NEON
			moreRows.Voice.BackgroundTransparency = if onVoiceServer then 0.4 else 1
		end,
		-- Wallet state: your level and XP on your party row.
		setProfile = function(state: any)
			if type(state) ~= "table" then
				return
			end
			local lv = tonumber(state.level) or 1
			local xp, need = tonumber(state.xp) or 0, tonumber(state.xpNeeded) or 0
			if lv ~= myLevel or xp ~= myXp or need ~= myNeed then
				myLevel, myXp, myNeed = lv, xp, need
				renderParty(lastParty)
			end
		end,
		setParty = renderParty,
		setQuests = renderQuests,
		setUpNext = setUpNext,
		upNextId = function(): string?
			return upNextId
		end,
		-- The game on the card, for the picker to open on.
		upNext = function(): any
			return currentEntry
		end,
	}
end

return LoungeHud
