-- The Game Café lobby HUD (used when Kit.Style is "Cafe"; LobbyHud is the Classic one).
-- Same API as LobbyHud (target, setPlay, setBadge, setVoice) plus setProfile, setParty,
-- setQuests and setUpNext. Mockup: project files ui-mockups/a-cafe-hub.jpg.
--
--   top-left      your plate (headshot, level ring, XP) and the party strip: everyone at
--                 your table plus an empty "+" seat that opens the Party window;
--   left          a rail of wood buttons: Shop, Pass, Avatar, Stats, and More (Tables, Host
--                 tools, Voice, Help, Settings) in a small pop-over;
--   bottom-left   today's quests on a paper card (tap for the Pass's quest tab);
--   bottom-right  "Up next" on felt: the game you last played (or today's pick), live,
--                 with the big gold PLAY.
--
-- Touch screens keep the bottom corners free for the thumbstick and jump button: the
-- quest card hides and PLAY moves to the bottom center with the game's name above it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local GameArt = require(ReplicatedStorage.Shared.GameArt)
local Flair = require(script.Parent.Flair)
local GamePreview = require(script.Parent.GamePreview)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)
local Perf = require(script.Parent.Parent.Perf)
local Theme = Kit.Theme

local CafeHud = {}

local VOICE_COLOR = Color3.fromRGB(96, 116, 230)
local STAR = Color3.fromRGB(255, 200, 61)
local MAX_FACES = 6

export type Actions = {
	play: () -> (),
	party: () -> (),
	tables: () -> (),
	stats: () -> (),
	shop: () -> (),
	pass: () -> (),
	avatar: () -> (),
	host: () -> (),
	voice: () -> (),
	help: () -> (),
	sound: () -> (),
	-- Optional extras (fall back to the ones above when missing).
	settings: (() -> ())?,
	quests: (() -> ())?,
	playGame: ((gameId: string) -> ())?,
	addGems: (() -> ())?,
}

-- A wood-framed panel: dark walnut with a chunky rim and a thin gold line inside.
local function woodPanel(props: { [string]: any }, radius: number?): Frame
	local frame = Kit.new("Frame", {
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
	}, {
		Kit.corner(radius or 16),
		Kit.new("UIStroke", { Name = "Outline", Color = Theme.WoodDark, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		Kit.shade(0.2),
	})
	for key, value in props do
		(frame :: any)[key] = value
	end
	return frame
end

local function round(object: GuiObject)
	local corner = object:FindFirstChildOfClass("UICorner") or Kit.new("UICorner", { Parent = object })
	corner.CornerRadius = UDim.new(0.5, 0)
end

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

function CafeHud.create(parent: Instance, actions: Actions)
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local userId = Players.LocalPlayer.UserId
	local buttons: { [string]: GuiObject } = {}
	local badges: { [string]: TextLabel } = {}

	local function badge(holder: GuiObject, key: string)
		local b = Kit.label("", {
			Name = "Badge",
			BackgroundColor3 = Theme.Bad,
			BackgroundTransparency = 0,
			TextColor3 = Color3.new(1, 1, 1),
			Font = Theme.FontBold,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 4, 0, -4),
			Size = UDim2.fromOffset(22, 22),
			Visible = false,
			ZIndex = holder.ZIndex + 3,
			Parent = holder,
		}, { Kit.new("UIStroke", { Color = Theme.WoodDark, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) })
		round(b)
		Flair.nudge(b, 4)
		badges[key] = b
	end

	----------------------------------------------------------------------------------
	-- Your plate: headshot with a level ring, name and XP bar. Tap for your stats.
	----------------------------------------------------------------------------------
	local plate = Kit.new("TextButton", {
		Name = "Plate",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(250, 64),
		ZIndex = 5,
		Parent = parent,
	}, {
		Kit.corner(32),
		Kit.new("UIStroke", { Name = "Outline", Color = Theme.WoodDark, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		Kit.shade(0.2),
	})
	plate.Activated:Connect(actions.stats)
	Kit.pressable(plate)
	local face = Kit.avatar(userId, 52, { Position = UDim2.fromOffset(6, 6), ZIndex = 6, BackgroundColor3 = Theme.PanelLight, Parent = plate })
	local faceRing = face:FindFirstChildOfClass("UIStroke")
	if faceRing then
		faceRing.Color = Theme.Accent
		faceRing.Transparency = 0
		faceRing.Thickness = 3
	end
	local level = Kit.label("1", {
		Name = "Level",
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 0,
		TextColor3 = Theme.AccentText,
		Font = Theme.FontTitle,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(52, 52),
		Size = UDim2.fromOffset(24, 24),
		ZIndex = 8,
		Parent = plate,
	}, { Kit.new("UIStroke", { Color = Theme.WoodDark, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) })
	round(level)
	local nameLabel = Kit.label(Players.LocalPlayer.DisplayName, {
		Name = "PlayerName",
		Font = Theme.FontTitle,
		TextSize = 18,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(70, 9),
		Size = UDim2.new(1, -84, 0, 22),
		ZIndex = 6,
		Parent = plate,
	})
	local xpBar, setXp = Kit.progress(Theme.Accent, { Position = UDim2.fromOffset(70, 36), Size = UDim2.new(1, -150, 0, 10), ZIndex = 6, Parent = plate })
	local xpFill = xpBar:FindFirstChild("Fill") :: Frame?
	if xpFill then
		xpFill.ZIndex = 7
	end
	local xpText = Kit.label("", {
		Name = "XP",
		TextSize = 12,
		Font = Theme.FontBold,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 32),
		Size = UDim2.fromOffset(72, 18),
		TextWrapped = false,
		ZIndex = 6,
		Parent = plate,
	})

	----------------------------------------------------------------------------------
	-- Party strip: everyone at your table, then an empty seat to invite more.
	----------------------------------------------------------------------------------
	local strip = woodPanel({
		Name = "PartyStrip",
		Size = UDim2.fromOffset(0, 64),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 5,
		Parent = parent,
	}, 32)
	local stripList = Kit.list(6, true)
	stripList.VerticalAlignment = Enum.VerticalAlignment.Center
	stripList.Parent = strip
	Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = strip })
	local faces = Kit.new("Frame", {
		Name = "Faces",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 48),
		LayoutOrder = 1,
		ZIndex = 6,
		Parent = strip,
	}, { Kit.list(4, true) })
	local invite = Kit.new("TextButton", {
		Name = "Invite",
		Text = "+",
		Font = Theme.FontTitle,
		TextSize = 26,
		TextColor3 = Theme.Accent,
		AutoButtonColor = true,
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(44, 44),
		LayoutOrder = 2,
		ZIndex = 6,
		Parent = strip,
	}, { Kit.new("UIStroke", { Color = Theme.Accent, Transparency = 0.2, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) })
	round(invite)
	invite.Activated:Connect(actions.party)
	Kit.pressable(invite)
	badge(invite, "Party")
	local inviteHint = Kit.label("Invite", {
		Name = "InviteHint",
		Font = Theme.FontBold,
		TextSize = 13,
		TextColor3 = Theme.SubText,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		TextWrapped = false,
		LayoutOrder = 3,
		ZIndex = 6,
		Parent = strip,
	})
	buttons.Party = strip
	local faceSize = 44

	local function renderFaces(party: any)
		Kit.clear(faces)
		local members = if party and type(party.members) == "table" then party.members else { { userId = userId, name = Players.LocalPlayer.DisplayName } }
		for i, member in members do
			if i > MAX_FACES then
				Kit.label(`+{#members - MAX_FACES}`, { Font = Theme.FontTitle, TextSize = 16, Size = UDim2.fromOffset(34, 44), TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = i, ZIndex = 7, Parent = faces })
				break
			end
			local holder = Kit.new("TextButton", {
				Name = "Member",
				Text = "",
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(faceSize, faceSize + 4),
				LayoutOrder = i,
				ZIndex = 7,
				Parent = faces,
			})
			holder.Activated:Connect(actions.party)
			local img = Kit.avatar(member.userId, faceSize, { Position = UDim2.fromOffset(0, 2), ZIndex = 7, BackgroundColor3 = Theme.PanelLight, Parent = holder })
			local ring = img:FindFirstChildOfClass("UIStroke")
			if ring then
				ring.Color = if party and member.userId == party.leaderId then Theme.Accent else Theme.Text
				ring.Transparency = if party and member.userId == party.leaderId then 0 else 0.6
				ring.Thickness = 2
			end
			if party and member.userId == party.leaderId and #members > 1 then
				-- The leader picks the game: a little gold crown on their face.
				Kit.label("👑", { TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(18, 18), ZIndex = 9, Parent = holder })
			end
		end
		inviteHint.Visible = #members < 2
	end
	renderFaces(nil)

	----------------------------------------------------------------------------------
	-- Rail: four wood buttons and More.
	----------------------------------------------------------------------------------
	local rail = Kit.new("Frame", {
		Name = "SideRail",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(68, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 5,
		Parent = parent,
	}, { Kit.list(10) })
	local railSize = 68

	local function railButton(key: string, order: number, icon: string, label: string, onClick: () -> ()): TextButton
		local button = Kit.new("TextButton", {
			Name = key,
			Text = "",
			AutoButtonColor = true,
			BackgroundColor3 = Theme.Panel,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(railSize, railSize),
			LayoutOrder = order,
			ZIndex = 5,
			Parent = rail,
		}, {
			Kit.corner(16),
			Kit.new("UIStroke", { Name = "Outline", Color = Theme.WoodDark, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
			Kit.shade(0.25),
		})
		Kit.innerRim(button, 0, 12)
		local rim = button:FindFirstChild("Rim") :: Frame?
		if rim then
			rim.Position = UDim2.fromOffset(3, 3)
			rim.Size = UDim2.new(1, -6, 1, -6)
		end
		Kit.label(icon, {
			Name = "Icon",
			TextSize = 26,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 0, 0, 6),
			Size = UDim2.new(1, 0, 0.55, 0),
			ZIndex = 6,
			Parent = button,
		})
		Kit.label(label, {
			Name = "Caption",
			TextSize = 12,
			Font = Theme.FontBold,
			TextColor3 = Theme.Text,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 0, 0.62, 0),
			Size = UDim2.new(1, 0, 0.28, 0),
			TextWrapped = false,
			ZIndex = 6,
			Parent = button,
		})
		badge(button, key)
		button.Activated:Connect(onClick)
		Kit.pressable(button)
		buttons[key] = button
		return button
	end

	railButton("Shop", 1, "🛒", "Shop", actions.shop)
	railButton("Pass", 2, "🎟️", "Pass", actions.pass)
	railButton("Avatar", 3, "👕", "Avatar", actions.avatar)
	railButton("Stats", 4, "📊", "Stats", actions.stats)
	local more: TextButton

	-- The More pop-over: a wood card beside the rail, closed by any tap outside it.
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
	local pop = woodPanel({
		Name = "MoreMenu",
		Size = UDim2.fromOffset(220, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		ZIndex = 15,
		Parent = parent,
	}, 16)
	Kit.padding(8).Parent = pop
	Kit.list(4).Parent = pop
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
			AutoButtonColor = true,
			BackgroundColor3 = Theme.PanelLight,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 42),
			LayoutOrder = order,
			ZIndex = 16,
			Parent = pop,
		}, { Kit.corner(10) })
		Kit.label(icon, { Name = "Icon", TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(4, 0), Size = UDim2.new(0, 36, 1, 0), ZIndex = 17, Parent = row })
		Kit.label(label, { Name = "Text", Font = Theme.FontBold, TextSize = 15, Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -48, 1, 0), TextWrapped = false, ZIndex = 17, Parent = row })
		row.Activated:Connect(function()
			closeMore()
			onClick()
		end)
		Kit.pressable(row)
		moreRows[key] = row
	end
	moreRow("Tables", 1, "🎲", "Tables in this server", actions.tables)
	moreRow("Host", 2, "👑", "Host tools", actions.host)
	moreRow("Voice", 3, "🎙", "Voice chat", actions.voice)
	moreRow("Help", 4, "❔", "Help and rules", actions.help)
	moreRow("Settings", 5, "⚙️", "Settings", actions.settings or actions.sound)
	moreRows.Voice.Visible = false

	more = railButton("More", 5, "•••", "More", function()
		local show = not pop.Visible
		catcher.Visible = show
		pop.Visible = show
		if show then
			local abs = more.AbsolutePosition
			local inset = (parent :: any).AbsolutePosition :: Vector2
			pop.Position = UDim2.fromOffset(abs.X - inset.X + more.AbsoluteSize.X + 10, abs.Y - inset.Y)
			-- Keep it on screen: grow upward when it would run off the bottom.
			task.defer(function()
				local over = (pop.AbsolutePosition.Y + pop.AbsoluteSize.Y) - ((parent :: any).AbsoluteSize.Y - 12)
				if over > 0 then
					pop.Position -= UDim2.fromOffset(0, over)
				end
			end)
			Kit.popIn(pop)
		end
	end)
	-- Settings has its own gear too, top-right under the wallet.
	local gear = Kit.button("⚙️", actions.settings or actions.sound, {
		Name = "SettingsButton",
		BackgroundColor3 = Theme.Panel,
		TextColor3 = Theme.Text,
		TextSize = 20,
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(40, 40),
		ZIndex = 5,
		Parent = parent,
	})
	round(gear)

	----------------------------------------------------------------------------------
	-- Quests: today's three on a paper card.
	----------------------------------------------------------------------------------
	local questCard = Kit.paper({
		Name = "QuestCard",
		Size = UDim2.fromOffset(290, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 5,
		Parent = parent,
	})
	Kit.new("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = questCard,
	})
	Kit.list(6).Parent = questCard
	local questHead = Kit.new("TextButton", {
		Name = "Head",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 0,
		ZIndex = 6,
		Parent = questCard,
	})
	Kit.label("📅  Daily quests", { Font = Theme.FontTitle, TextSize = 17, TextColor3 = Theme.Ink, Size = UDim2.new(1, -80, 1, 0), TextWrapped = false, ZIndex = 6, Parent = questHead })
	local questTimer = Kit.label("", {
		Font = Theme.FontBold,
		TextSize = 12,
		TextColor3 = Theme.Ink2,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 90, 1, 0),
		TextWrapped = false,
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
	}, { Kit.list(8) })
	questRows.Activated:Connect(openQuests)
	buttons.Quests = questCard

	local function renderQuests(quests: { any }?)
		Kit.clear(questRows)
		local list = quests or {}
		if #list == 0 then
			Kit.label("Play any game to get today's quests.", { TextSize = 13, TextColor3 = Theme.Ink2, Size = UDim2.new(1, 0, 0, 18), ZIndex = 6, Parent = questRows })
		end
		for i, quest in list do
			if i > 3 then
				break
			end
			local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = i, ZIndex = 6, Parent = questRows })
			local done = quest.done == true
			Kit.label(`{if done then "✅ " else ""}{quest.text or "Quest"}`, {
				TextSize = 13,
				Font = Theme.FontBold,
				TextColor3 = if done then Theme.Good else Theme.Ink,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Size = UDim2.new(1, -64, 0, 16),
				ZIndex = 6,
				Parent = row,
			})
			Kit.label(`+{commas(quest.stars or 0)} ⭐`, {
				TextSize = 12,
				Font = Theme.FontBold,
				TextColor3 = Theme.Ink2,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Size = UDim2.fromOffset(62, 16),
				TextWrapped = false,
				ZIndex = 6,
				Parent = row,
			})
			local bar, set = Kit.progress(if done then Theme.Good else STAR, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, -44, 0, 8), BackgroundColor3 = Theme.Ink, BackgroundTransparency = 0.82, ZIndex = 6, Parent = row })
			local fill = bar:FindFirstChild("Fill") :: Frame?
			if fill then
				fill.ZIndex = 7
			end
			local target = tonumber(quest.target) or 0
			local progress = tonumber(quest.progress) or 0
			set(if done then 1 elseif target > 0 then progress / target else 0)
			Kit.label(if done then "Done" else `{progress}/{target}`, {
				TextSize = 11,
				Font = Theme.FontBold,
				TextColor3 = Theme.Ink2,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 17),
				Size = UDim2.fromOffset(40, 16),
				TextWrapped = false,
				ZIndex = 6,
				Parent = row,
			})
		end
	end
	renderQuests(nil)
	task.spawn(function()
		while questCard.Parent do
			local now = os.time()
			local left = (now // 86400 + 1) * 86400 - now
			questTimer.Text = if left >= 3600 then `{left // 3600}h {left % 3600 // 60}m left` else `{left // 60}m left`
			task.wait(30)
		end
	end)

	----------------------------------------------------------------------------------
	-- Up next: felt card with the game, live, and the big PLAY.
	----------------------------------------------------------------------------------
	local upNext = Kit.new("Frame", {
		Name = "UpNext",
		BackgroundColor3 = Theme.Felt,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(300, 250),
		ZIndex = 5,
		Parent = parent,
	}, {
		Kit.corner(18),
		Kit.new("UIStroke", { Name = "Outline", Color = Theme.WoodDark, Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		Kit.new("UIGradient", { Name = "Shade", Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)) }),
	})
	Kit.innerRim(upNext, 0, 14)
	local upRim = upNext:FindFirstChild("Rim") :: Frame?
	if upRim then
		upRim.Position = UDim2.fromOffset(4, 4)
		upRim.Size = UDim2.new(1, -8, 1, -8)
	end
	local upLabel = Kit.label("UP NEXT", {
		Name = "Kicker",
		Font = Theme.FontBold,
		TextSize = 12,
		TextColor3 = Theme.Accent,
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -32, 0, 14),
		ZIndex = 6,
		Parent = upNext,
	})
	local upName = Kit.label("Pick a game", {
		Name = "GameName",
		Font = Theme.FontTitle,
		TextSize = 22,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(16, 26),
		Size = UDim2.new(1, -32, 0, 26),
		ZIndex = 6,
		Parent = upNext,
	})
	local upMeta = Kit.label("", {
		Name = "Meta",
		Font = Theme.FontBold,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(200, 232, 214),
		Position = UDim2.fromOffset(16, 52),
		Size = UDim2.new(1, -32, 0, 14),
		TextWrapped = false,
		ZIndex = 6,
		Parent = upNext,
	})
	local art = Kit.new("Frame", {
		Name = "Art",
		BackgroundColor3 = Theme.FeltDark,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(14, 72),
		Size = UDim2.new(1, -28, 0, 92),
		ClipsDescendants = true,
		ZIndex = 6,
		Parent = upNext,
	}, { Kit.corner(10), Kit.new("UIStroke", { Color = Theme.WoodDark, Thickness = 2, Transparency = 0.3 }) })
	local artIcon = Kit.label("🎲", { Name = "Icon", TextSize = 48, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 7, Parent = art })
	local artImage = Kit.new("ImageLabel", { Name = "Image", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Crop, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 8, Parent = art }, { Kit.corner(10) })
	local hint = Kit.label("", {
		Name = "PlayHint",
		Font = Theme.FontBold,
		TextSize = 13,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(300, 18),
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
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -32),
		Size = UDim2.new(1, -28, 0, 54),
		TextSize = 30,
		Font = Theme.FontTitle,
		ZIndex = 7,
		Parent = upNext,
	})
	Flair.idleShine(play, 5)
	local change = Kit.new("TextButton", {
		Name = "AllGames",
		Text = "All games  ›",
		Font = Theme.FontBold,
		TextSize = 13,
		TextColor3 = Theme.Text,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -28, 0, 20),
		ZIndex = 7,
		Parent = upNext,
	})
	change.Activated:Connect(actions.play)

	local preview: any = nil
	local function dropPreview()
		if preview then
			pcall(preview.destroy)
			preview = nil
		end
	end
	local function lobbyShown(): boolean
		local node: Instance? = upNext
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
		if lobbyShown() and art.Visible and not Perf.isLow() then
			preview.play()
		else
			preview.pause()
		end
	end
	if parent:IsA("GuiObject") then
		parent:GetPropertyChangedSignal("Visible"):Connect(syncPreview)
	end
	Perf.onChange(syncPreview)

	local function setUpNext(entry: any?, why: string?)
		dropPreview()
		upNextId = entry and entry.id or nil
		upName.Text = if entry then entry.name else "Pick a game"
		upLabel.Text = why or "UP NEXT"
		if entry then
			local seats = if entry.minSeats == entry.maxSeats then `{entry.minSeats} players` else `{entry.minSeats}-{entry.maxSeats} players`
			local minutes = if entry.typicalMinutes then `  ·  about {math.max(1, math.floor(entry.typicalMinutes + 0.5))} min` else ""
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
		local margin = if compact then 8 else 14
		local left = info.left + margin
		local top = info.top + (if compact then 6 else 10)

		-- Plate and party strip.
		plate.Position = UDim2.fromOffset(left, top)
		local plateH = if compact then 48 else 64
		plate.Size = UDim2.fromOffset(if compact then 48 else 250, plateH)
		face.Size = UDim2.fromOffset(plateH - 12, plateH - 12)
		level.Position = UDim2.fromOffset(plateH - 12, plateH - 12)
		level.Size = UDim2.fromOffset(if compact then 20 else 24, if compact then 20 else 24)
		nameLabel.Visible = not compact
		xpBar.Visible = not compact
		xpText.Visible = not compact
		strip.Position = UDim2.fromOffset(left + plate.Size.X.Offset + 10, top)
		strip.Size = UDim2.fromOffset(0, plateH)
		faceSize = plateH - 20
		invite.Size = UDim2.fromOffset(faceSize, faceSize)
		faces.Size = UDim2.fromOffset(0, plateH - 16)
		for _, holder in faces:GetChildren() do
			if holder:IsA("TextButton") then
				holder.Size = UDim2.fromOffset(faceSize, faceSize + 4)
				local img = holder:FindFirstChild("Avatar") :: ImageLabel?
				if img then
					img.Size = UDim2.fromOffset(faceSize, faceSize)
				end
			end
		end

		-- Gear: top right, under the wallet.
		gear.Position = UDim2.new(1, -(margin + 22), 0, top + (if compact then 0 else 4))
		gear.Visible = not compact

		-- Rail: under the plate, sized to fit the height left.
		railSize = if compact then 48 else 68
		local gap = if compact then 6 else 10
		local railTop = top + plateH + (if compact then 10 else 18)
		local reserved = if small then (info.bottom + 90) else (info.bottom + 16)
		local room = info.height - railTop - reserved
		local count = 5
		if room > 0 then
			railSize = math.max(38, math.min(railSize, math.floor((room - gap * (count - 1)) / count)))
		end
		local list = rail:FindFirstChildOfClass("UIListLayout")
		if list then
			list.Padding = UDim.new(0, gap)
		end
		for _, key in { "Shop", "Pass", "Avatar", "Stats", "More" } do
			local button = buttons[key] :: GuiObject
			button.Size = UDim2.fromOffset(railSize, railSize)
			local icon = button:FindFirstChild("Icon") :: TextLabel?
			local caption = button:FindFirstChild("Caption") :: TextLabel?
			if icon then
				icon.TextSize = if railSize < 56 then 22 else 30
				icon.Position = UDim2.new(0, 0, 0, if railSize < 56 then 3 else 6)
			end
			if caption then
				caption.TextSize = if railSize < 56 then 10 else 12
			end
		end
		rail.Size = UDim2.fromOffset(railSize, 0)
		rail.Position = UDim2.fromOffset(left, railTop)

		-- Quests: bottom left, right of the rail, when there's room and no thumbstick.
		local questRoom = info.height - info.bottom - 14
		questCard.Position = UDim2.new(0, left + railSize + 16, 1, -(info.bottom + 14))
		questCard.AnchorPoint = Vector2.new(0, 1)
		questCard.Visible = not small and info.width >= 900 and questRoom > railTop + 200

		-- Up next: bottom right on a big screen; PLAY alone at the bottom center on touch.
		if small then
			local playW = if compact then 190 else 230
			local playH = if compact then 52 else 62
			upNext.BackgroundTransparency = 1
			upNext.AnchorPoint = Vector2.new(0.5, 1)
			upNext.Position = UDim2.new(0.5, 0, 1, -(info.bottom + (if compact then 10 else 18)))
			upNext.Size = UDim2.fromOffset(playW, playH)
			for _, child in { upLabel, upName, upMeta, art, change } do
				child.Visible = false
			end
			local outline = upNext:FindFirstChild("Outline") :: UIStroke?
			if outline then
				outline.Enabled = false
			end
			if upRim then
				upRim.Visible = false
			end
			play.AnchorPoint = Vector2.new(0, 0)
			play.Position = UDim2.fromScale(0, 0)
			play.Size = UDim2.fromScale(1, 1)
			play.TextSize = if compact then 24 else 28
			hint.Position = UDim2.new(0.5, 0, 1, -(info.bottom + (if compact then 10 else 18) + playH + 4))
			hint.Size = UDim2.fromOffset(math.min(420, info.width - 2 * (left + railSize + 16)), 18)
		else
			local cardW = if info.width >= 1300 then 320 else 290
			local cardH = if info.height >= 760 then 260 else 210
			upNext.BackgroundTransparency = 0
			upNext.AnchorPoint = Vector2.new(1, 1)
			upNext.Position = UDim2.new(1, -(margin + 4), 1, -(info.bottom + 14))
			upNext.Size = UDim2.fromOffset(cardW, cardH)
			for _, child in { upLabel, upName, upMeta, change } do
				child.Visible = true
			end
			art.Visible = cardH >= 240
			local outline = upNext:FindFirstChild("Outline") :: UIStroke?
			if outline then
				outline.Enabled = true
			end
			if upRim then
				upRim.Visible = true
			end
			play.AnchorPoint = Vector2.new(0.5, 1)
			play.Position = UDim2.new(0.5, 0, 1, -32)
			play.Size = UDim2.new(1, -28, 0, 54)
			play.TextSize = 30
			art.Size = UDim2.new(1, -28, 0, cardH - 72 - 98)
			hint.Position = UDim2.new(1, -(margin + 4 + cardW / 2), 1, -(info.bottom + 14 + cardH + 4))
			hint.Size = UDim2.fromOffset(cardW + 40, 18)
		end
		syncPreview()
	end)

	return {
		-- The button for a lobby tour step: "Play", a rail key, or one inside More (points
		-- at More).
		target = function(key: string): GuiObject?
			if key == "Play" then
				return play
			elseif key == "Help" or key == "Sound" or key == "Tables" or key == "Host" or key == "Voice" or key == "Settings" then
				return more
			end
			return buttons[key]
		end,
		setPlay = function(text: string, hintText: string?)
			-- The Café's button just says PLAY; "Games" (someone else picks) keeps its word.
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
			moreRows.Voice.BackgroundColor3 = if onVoiceServer then VOICE_COLOR else Theme.PanelLight
		end,
		-- Wallet state: level and XP for the plate.
		setProfile = function(state: any)
			if type(state) ~= "table" then
				return
			end
			local lv = tonumber(state.level) or 1
			level.Text = tostring(lv)
			local xp, need = tonumber(state.xp) or 0, tonumber(state.xpNeeded) or 0
			setXp(if need > 0 then xp / need else 0)
			xpText.Text = if need > 0 then `{commas(xp)}/{commas(need)}` else ""
		end,
		setParty = renderFaces,
		setQuests = renderQuests,
		setUpNext = setUpNext,
		upNextId = function(): string?
			return upNextId
		end,
	}
end

return CafeHud
