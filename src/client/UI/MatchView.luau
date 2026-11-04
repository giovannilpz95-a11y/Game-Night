-- Full-screen table view while a match is on.
--
-- Phone-first layout:
-- * The header lives inside Roblox's top bar (game name, one "what now" line, the view
--   toggle and a ⋯ menu with Resign / End for everyone / Leave), so it costs no height.
--   A thin timer bar under it drains and turns orange, then red.
-- * Seats are a narrow column of chips on the left; the active seat glows and has its own
--   timer bar.
-- * The board gets everything else. It is drawn by the game's renderer in
--   client/Renderers/<module>.
-- * "Your turn!" slides in with a sound when your turn starts.
-- * The end screen shows the result, standings, rewards and a big Rematch button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HapticService = game:GetService("HapticService")

local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)
local Table3D = require(script.Parent.Parent.Table3D.Controller)
local Avatars = require(script.Parent.Parent.Table3D.Avatars)
local EmoteWheel = require(script.Parent.EmoteWheel)
local ReactionFx = require(script.Parent.ReactionFx)
local Net = require(ReplicatedStorage.Shared.Net)
local Reactions = require(ReplicatedStorage.Shared.Reactions)
local Theme = Kit.Theme

local Renderers = script.Parent.Parent.Renderers

local MatchView = {}

-- Table view of a watch-only scene keeps part of the 2D board on screen: the edge where
-- that game keeps your hand, buttons and prompts. Bottom docks: size < 1 is a fraction of
-- the board, above 1 it's pixels. Right docks: size is the share of the board the game's
-- side panel takes (the dock is sized to show all of it). Unlisted games dock their
-- bottom 40%.
local DOCK_DEFAULT = { side = "bottom", size = 0.4 }
local DOCK: { [string]: { side: string, size: number } } = {
	Hexlands = { side = "right", size = 0.42 },
	Conquest = { side = "right", size = 0.32 },
	Estates = { side = "right", size = 0.4 },
	Whodunit = { side = "right", size = 0.44 },
	SketchGuess = { side = "right", size = 0.32 },
	WordTiles = { side = "bottom", size = 96 },
	ColorClash = { side = "bottom", size = 0.45 }, -- the "+2 waiting" line, buttons and hand
	TriviaNight = { side = "bottom", size = 0.26 }, -- answers only (the screen shows the question)
	Spoons = { side = "bottom", size = 0.41 },
	War = { side = "bottom", size = 0.2 },
	GoFish = { side = "bottom", size = 0.36 },
	Speed = { side = "bottom", size = 0.36 },
	Cheat = { side = "bottom", size = 0.39 },
	President = { side = "bottom", size = 0.39 },
	SlapStack = { side = "bottom", size = 0.39 },
	Hearts = { side = "bottom", size = 0.39 },
	Spades = { side = "bottom", size = 0.39 },
	ThirtyOne = { side = "bottom", size = 0.39 },
	Palace = { side = "bottom", size = 0.39 },
	OldMaid = { side = "bottom", size = 0.39 },
	Snap = { side = "bottom", size = 0.39 },
	GinRummy = { side = "bottom", size = 0.39 },
	OhHell = { side = "bottom", size = 0.39 },
}

local localPlayer = Players.LocalPlayer

local TURN_SOUND = "rbxasset://sounds/electronicpingshort.wav"
local TICK_SOUND = "rbxasset://sounds/clickfast.wav"

local function hex(color: Color3): string
	return string.format("#%02X%02X%02X", math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255))
end

-- Text that goes inside a RichText label.
local function esc(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- Green while there's time, orange under 10 s, red under 5 s.
local function timerColor(left: number): Color3
	if left <= 5 then
		return Theme.Bad
	elseif left <= 10 then
		return Theme.Warn
	end
	return Theme.Good
end

-- openRules(gameId): shows that game's rules over the table (the ? in the header).
-- openReactionShop(): the reaction packs in the shop (the wheel's 🛍️ button).
function MatchView.create(parent: Instance, sendMatch: (any) -> (), isLeader: () -> boolean, walletWidth: (() -> number)?, openRules: ((string) -> ())?, openReactionShop: (() -> ())?)
	local root = Kit.new("Frame", {
		Name = "MatchView",
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = parent,
	})

	local function sound(id: string, volume: number): Sound
		return Kit.new("Sound", { SoundId = id, Volume = volume, Parent = root })
	end
	local turnSound = sound(TURN_SOUND, 0.6)
	local tickSound = sound(TICK_SOUND, 0.35)

	---------------------------------------------------------------- header (in the top bar)
	local header = Kit.new("Frame", {
		Name = "Header",
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ZIndex = 20,
		Parent = root,
	}, { Kit.corner(10) })
	local turnLabel = Kit.label("", {
		RichText = true,
		Font = Theme.FontBold,
		TextSize = 18,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.new(0, 12, 0, 0),
		ZIndex = 21,
		Parent = header,
	})
	-- Drains while the clock runs (your turn, or a party game's phase).
	local timerTrack = Kit.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 8, 1, -2),
		Size = UDim2.new(1, -16, 0, 4),
		Visible = false,
		ZIndex = 21,
		Parent = header,
	}, { Kit.corner(2) })
	local timerFill = Kit.new("Frame", {
		BackgroundColor3 = Theme.Good,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 22,
		Parent = timerTrack,
	}, { Kit.corner(2) })

	local menuButton = Kit.button("⋯", function() end, {
		Name = "Menu",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = Theme.PanelLight,
		TextColor3 = Theme.Text,
		TextSize = 22,
		ZIndex = 21,
		Parent = header,
	})

	-- Table view: the game on the real table, seen from your seat, with your hand and
	-- prompts docked along the edge for watch-only tables. It's the default everywhere
	-- except on phones (there the flat view is easier to tap and read). Your toggle is
	-- remembered per game for the session, so turning Table view off for one game doesn't
	-- turn it off for the rest.
	local function defaultView(): boolean
		return not (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	end
	local viewChoice: { [string]: boolean } = {}
	local snapshot: any = nil
	local function wanted(): boolean
		local gameId = snapshot and snapshot.gameId
		local choice = gameId and viewChoice[gameId]
		if choice == nil then
			return defaultView()
		end
		return choice
	end
	-- Rules for this game, any time. A window over the table: the match keeps going.
	local rulesButton = Kit.button("?", function()
		if snapshot and openRules then
			openRules(snapshot.gameId)
		end
	end, {
		Name = "Rules",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = Theme.PanelLight,
		TextColor3 = Theme.Text,
		TextSize = 20,
		Visible = openRules ~= nil,
		ZIndex = 21,
		Parent = header,
	})

	local viewButton: TextButton
	local applyMode: () -> ()
	local relayout: () -> ()
	local dockSpec: () -> { side: string, size: number }
	local table3D = Table3D.create(parent :: ScreenGui, function(move: any)
		sendMatch({ action = "move", move = move })
	end, function()
		applyMode()
	end)

	---------------------------------------------------------------- ⋯ menu
	local menu = Kit.panel({
		Name = "MatchMenu",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.new(0, 200, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.PanelLight,
		Visible = false,
		ZIndex = 40,
		Parent = root,
	})
	Kit.list(6).Parent = menu
	local function closeMenu()
		menu.Visible = false
	end
	local resignConfirm = false
	local resignButton: TextButton
	resignButton = Kit.button("Resign", function()
		if resignConfirm then
			resignConfirm = false
			resignButton.Text = "Resign"
			closeMenu()
			sendMatch({ action = "resign" })
		else
			-- Ask twice so a stray tap doesn't throw the game.
			resignConfirm = true
			resignButton.Text = "Tap again to resign"
			task.delay(3, function()
				resignConfirm = false
				resignButton.Text = "Resign"
			end)
		end
	end, { BackgroundColor3 = Theme.Panel, TextColor3 = Theme.Text, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 1, ZIndex = 41, Parent = menu })
	local endButton = Kit.button("End for everyone", function()
		closeMenu()
		sendMatch({ action = "endForAll" })
	end, { BackgroundColor3 = Theme.Bad, TextColor3 = Theme.Text, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 2, ZIndex = 41, Parent = menu })
	local leaveButton = Kit.button("Leave game", function()
		closeMenu()
		sendMatch({ action = "leave" })
	end, { BackgroundColor3 = Theme.Panel, TextColor3 = Theme.Text, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 3, ZIndex = 41, Parent = menu })
	-- Calm camera: Table view without the lean, push-ins and drift.
	local calmButton: TextButton
	local function calmText(): string
		return if Table3D.isCalm() then "Camera motion: Calm" else "Camera motion: Full"
	end
	calmButton = Kit.button(calmText(), function()
		Table3D.setCalm(not Table3D.isCalm())
		calmButton.Text = calmText()
	end, { BackgroundColor3 = Theme.Panel, TextColor3 = Theme.Text, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 4, ZIndex = 41, Parent = menu })
	menuButton.Activated:Connect(function()
		menu.Visible = not menu.Visible
	end)
	Avatars.onAction(function(tableId, point, kind)
		table3D.focus(tableId, point, kind)
	end)

	---------------------------------------------------------------- seats and board
	local seatsPanel = Kit.new("ScrollingFrame", {
		Name = "Seats",
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 3,
		ZIndex = 2,
		Parent = root,
	}, { Kit.corner(12), Kit.padding(6), Kit.list(6) })

	do
		local listLayout = seatsPanel:FindFirstChildOfClass("UIListLayout")
		if listLayout then
			listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
				if relayout and table3D.isActive() then
					relayout()
				end
			end)
		end
	end

	local board = Kit.new("Frame", {
		Name = "Board",
		BackgroundTransparency = 1,
		Parent = root,
	})

	-- Table view of a watch-only scene: the 2D board stays live, but only the strip with
	-- your hand, buttons and prompts shows, docked on the edge where that game keeps them.
	local dock = Kit.new("Frame", {
		Name = "Dock",
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Visible = false,
		ZIndex = 2,
		Parent = root,
	}, { Kit.corner(12) })

	---------------------------------------------------------------- "Your turn!" banner
	local banner = Kit.new("Frame", {
		Name = "TurnBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(260, 56),
		Visible = false,
		ZIndex = 30,
		Parent = root,
	}, { Kit.corner(14), Kit.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Transparency = 0.3 }) })
	local bannerText = Kit.label("Your turn!", {
		Font = Theme.FontBold,
		TextSize = 28,
		TextColor3 = Theme.AccentText,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 31,
		Parent = banner,
	})
	local bannerToken = 0
	local bannerY = 0

	local function hideBanner()
		bannerToken += 1
		banner.Visible = false
	end

	local function showBanner(text: string)
		bannerToken += 1
		local token = bannerToken
		bannerText.Text = text
		banner.Visible = true
		banner.BackgroundTransparency = 0
		bannerText.TextTransparency = 0
		banner.Position = UDim2.new(0.5, 0, 0, bannerY - 70)
		TweenService:Create(banner, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 0, bannerY),
		}):Play()
		turnSound:Play()
		-- A short buzz on gamepads (phones without haptics just skip it).
		pcall(function()
			HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0.6)
			task.delay(0.15, function()
				pcall(HapticService.SetMotor, HapticService, Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0)
			end)
		end)
		task.delay(1.1, function()
			if bannerToken ~= token then
				return
			end
			local fade = TweenInfo.new(0.35)
			TweenService:Create(banner, fade, { BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 0, bannerY - 20) }):Play()
			TweenService:Create(bannerText, fade, { TextTransparency = 1 }):Play()
			task.delay(0.36, function()
				if bannerToken == token then
					banner.Visible = false
				end
			end)
		end)
	end

	---------------------------------------------------------------- end screen
	local resultOverlay = Kit.panel({
		Name = "Result",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.PanelLight,
		Visible = false,
		ZIndex = 50,
		Parent = root,
	})
	Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 2, Transparency = 0.4, Parent = resultOverlay })
	local resultLabel = Kit.label("", { TextSize = 26, Font = Theme.FontBold, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 36), ZIndex = 51, Parent = resultOverlay })
	-- Two lines, so longer reasons (a Whodunit solution) wrap instead of being cut off.
	local reasonLabel = Kit.label("", { TextSize = 15, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.new(0, 0, 0, 38), Size = UDim2.new(1, 0, 0, 38), ZIndex = 51, Parent = resultOverlay })
	local standings = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 80),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 3,
		ZIndex = 51,
		Parent = resultOverlay,
	}, { Kit.list(4) })
	-- What you earned, filled in by showReward a moment after the result arrives.
	local REWARD_H = 46
	local rewardLabel = Kit.label("", {
		TextSize = 14,
		TextColor3 = Theme.Accent,
		Font = Theme.FontBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -52),
		Size = UDim2.new(1, 0, 0, REWARD_H),
		ZIndex = 51,
		Parent = resultOverlay,
	})
	local shownMatchId: string? = nil
	local rematchAsked = false
	local rematchButton: TextButton
	rematchButton = Kit.button("Rematch", function()
		if rematchAsked or not snapshot then
			return
		end
		rematchAsked = true
		sendMatch({ action = "rematch" })
		rematchButton.Text = if isLeader() then "Starting..." else "Asked the leader"
		rematchButton.AutoButtonColor = false
		rematchButton.BackgroundColor3 = Theme.Panel
		rematchButton.TextColor3 = Theme.SubText
		-- If the server said no (it explains in a toast), let them try again.
		local askedFor = shownMatchId
		task.delay(if isLeader() then 5 else 10, function()
			if rematchAsked and shownMatchId == askedFor and resultOverlay.Visible then
				rematchAsked = false
				rematchButton.Text = if isLeader() then "Rematch" else "Ask for rematch"
				rematchButton.AutoButtonColor = true
				rematchButton.BackgroundColor3 = Theme.Accent
				rematchButton.TextColor3 = Theme.AccentText
			end
		end)
	end, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(0.6, -4, 0, 46),
		TextSize = 20,
		ZIndex = 51,
		Parent = resultOverlay,
	})
	local closeButton: TextButton

	---------------------------------------------------------------- state
	local renderer: any = nil
	local rendererGameId: string? = nil
	local wasMyTurn = false
	local timerFor: number? = nil -- turnEndsAt the timer bars are measuring
	local timerTotal = 1
	local lastTick = -1

	viewButton = Kit.button("2D view", function()
		if snapshot then
			-- From what's on screen: if Table view was wanted but the table never
			-- streamed in, the button reads "Table view" and should try again.
			viewChoice[snapshot.gameId] = not table3D.isActive()
			table3D.setSnapshot(snapshot, wanted())
		end
		applyMode()
	end, {
		Name = "View",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = Theme.PanelLight,
		TextColor3 = Theme.Text,
		TextSize = 14,
		Visible = false,
		ZIndex = 21,
		Parent = header,
	})

	-- The 😀 wheel: animated reactions while you have a seat, plus emotes for your avatar
	-- when you're seated at a 3D table.
	local reactionRemote = Net.event(Net.Names.Reaction)
	local emotes = EmoteWheel.create(root, header, {
		emote = Avatars.emote,
		react = function(id: string)
			reactionRemote:FireServer({ id = id })
		end,
		openShop = openReactionShop,
	})

	local function nameOf(seat: number): string
		local s = snapshot.seats[seat]
		if not s then
			return "?"
		end
		return if seat == snapshot.yourSeat then "You" else s.name
	end

	local function isOver(): boolean
		return snapshot ~= nil and (snapshot.result ~= nil or snapshot.aborted == true)
	end

	local function isMyTurn(): boolean
		return snapshot ~= nil and snapshot.yourSeat ~= nil and not isOver() and table.find(snapshot.activeSeats, snapshot.yourSeat) ~= nil
	end

	-- Seconds left on the clock we show, or nil when there's no clock to show.
	local function secondsLeft(): number?
		if not snapshot or isOver() or not snapshot.turnEndsAt then
			return nil
		end
		if not (snapshot.timed or isMyTurn()) then
			return nil
		end
		return math.max(0, snapshot.turnEndsAt - workspace:GetServerTimeNow())
	end

	---------------------------------------------------------------- layout
	function dockSpec(): { side: string, size: number }
		return (snapshot and DOCK[snapshot.gameId]) or DOCK_DEFAULT
	end

	function relayout()
		local info = Layout.get()
		local compact = info.compact
		local in3D = table3D.isActive()

		-- Header: inside Roblox's top bar, stopping before the wallet at its right end.
		local wallet = if walletWidth then walletWidth() else 0
		local barW = math.max(160, info.barW - (if wallet > 0 then wallet + 8 else 0))
		local barH = math.max(36, info.barH - 4)
		header.Position = UDim2.fromOffset(info.barX, info.barY + 2)
		header.Size = UDim2.fromOffset(barW, barH)
		local buttonH = math.min(36, barH - 8)
		menuButton.Size = UDim2.fromOffset(40, buttonH)
		menuButton.Position = UDim2.new(1, -4, 0.5, -1)
		local rulesW = if rulesButton.Visible then 40 else 0
		rulesButton.Size = UDim2.fromOffset(36, buttonH)
		rulesButton.Position = UDim2.new(1, -48, 0.5, -1)
		local viewW = if compact then 84 else 110
		viewButton.Size = UDim2.fromOffset(viewW, buttonH)
		viewButton.Position = UDim2.new(1, -48 - rulesW, 0.5, -1)
		local textRight = 52 + rulesW + (if viewButton.Visible then viewW + 4 else 0)
		emotes.button.Size = UDim2.fromOffset(40, buttonH)
		emotes.button.Position = UDim2.new(1, -textRight, 0.5, -1)
		if emotes.button.Visible then
			textRight += 44
		end
		turnLabel.Size = UDim2.new(1, -(12 + textRight), 1, -4)
		turnLabel.TextSize = if compact then 16 else 19
		menu.Position = UDim2.fromOffset(info.barX + barW, info.barY + 2 + barH + 4)

		-- Seats column and the board fill everything under the top bar.
		local top = info.top
		local left = info.left + 8
		local right = info.right + 8
		local bottom = info.bottom + 8
		local seatsW = if compact then 140 else 210
		local available = info.height - top - bottom
		seatsPanel.Position = UDim2.fromOffset(left, top)
		if in3D then
			-- Watching the room: a short seat list, sized to its chips.
			-- Sized to the chips actually drawn (their height depends on what each shows),
			-- so the last seat isn't cut off.
			local listLayout = seatsPanel:FindFirstChildOfClass("UIListLayout")
			local listH = if listLayout then listLayout.AbsoluteContentSize.Y + 14 else 0
			if listH < 20 then
				local count = if snapshot then #snapshot.seats else 2
				listH = count * ((if compact then 38 else 52) + 6) + 14
			end
			seatsPanel.Size = UDim2.fromOffset(seatsW, math.min(listH, available))
		else
			seatsPanel.Size = UDim2.fromOffset(seatsW, available)
		end
		local boardX = left + seatsW + 8
		local boardW, boardH = math.max(100, info.width - boardX - right), math.max(100, available)
		board.Size = UDim2.fromOffset(boardW, boardH)
		if board.Parent == dock then
			local spec = dockSpec()
			if spec.side == "right" then
				-- spec.size is the share of the board the game's side panel takes. The dock
				-- gets a sensible width (280 px at least, half the board at most) and the
				-- board is drawn just wide enough that its side panel exactly fills it, so
				-- the panel is never cut off on small screens.
				local w = math.floor(math.clamp(boardW * 0.3, math.min(280, boardW * 0.5), boardW * 0.5))
				local virtualW = math.floor(w / spec.size)
				board.Size = UDim2.fromOffset(virtualW, boardH)
				dock.Position = UDim2.fromOffset(boardX + boardW - w, top)
				dock.Size = UDim2.fromOffset(w, boardH)
				board.Position = UDim2.fromOffset(w - virtualW, 0)
				table3D.setInsets((w + right) / info.width, 0)
			else
				local h = if spec.size > 1 then spec.size else math.floor(boardH * spec.size)
				dock.Position = UDim2.fromOffset(boardX, top + boardH - h)
				dock.Size = UDim2.fromOffset(boardW, h)
				board.Position = UDim2.fromOffset(0, h - boardH)
				table3D.setInsets(0, (h + bottom) / info.height)
			end
		else
			board.Position = UDim2.fromOffset(boardX, top)
			table3D.setInsets(0, 0)
		end

		-- Over the middle of the board, clear of the opponents' row along its top.
		bannerY = top + math.floor(available * 0.4)
		banner.Size = UDim2.fromOffset(if compact then 220 else 280, if compact then 48 else 60)
		bannerText.TextSize = if compact then 24 else 30

		-- End card: as big as it can be, up to 420 x 420.
		local cardW = math.min(420, info.width - 24)
		local cardH = math.min(420, available)
		resultOverlay.Size = UDim2.fromOffset(cardW, cardH)
		resultOverlay.Position = UDim2.fromOffset(info.width / 2, top + available / 2)
		resultLabel.TextSize = if compact then 22 else 26
		-- 12 px padding on each side of the card.
		standings.Size = UDim2.new(1, 0, 0, math.max(0, cardH - 24 - 80 - REWARD_H - 52 - 4))
	end
	Layout.onChange(function()
		if applyMode then
			applyMode()
		end
	end)

	function applyMode()
		local in3D = table3D.isActive()
		-- In 3D the screen stays see-through: header, seats and results float over the room.
		root.BackgroundTransparency = if in3D then 1 else 0
		-- Scenes keep your hand docked on screen; games played on the table don't need it.
		local docked = in3D and not table3D.playable()
		board.Parent = if docked then dock else root
		if renderer and renderer.setDocked then
			-- Some games lay out a compact strip for the dock (Trivia: just the answers).
			renderer.setDocked(docked)
		end
		board.Visible = not in3D or docked
		dock.Visible = docked
		viewButton.Visible = table3D.available() and snapshot ~= nil and not isOver()
		emotes.setEnabled(snapshot ~= nil and snapshot.yourSeat ~= nil and not isOver(), snapshot ~= nil and snapshot.table ~= nil)
		local compact = Layout.get().compact
		if table3D.playable() then
			viewButton.Text = if in3D then "2D view" else "3D view"
		elseif compact then
			viewButton.Text = if in3D then "Game" else "Table"
		else
			viewButton.Text = if in3D then "Back to game" else "Table view"
		end
		relayout()
	end

	---------------------------------------------------------------- per-frame: turn text and clocks
	local function updateTurnText()
		if not snapshot then
			return
		end
		local entry = GameCatalog.get(snapshot.gameId)
		local title = if entry then entry.name else snapshot.gameId
		local prefix = `<font color="{hex(Theme.SubText)}">{esc(title)}</font>   `
		if isOver() then
			turnLabel.Text = prefix .. "Game over"
			timerTrack.Visible = false
			return
		end
		local active = snapshot.activeSeats
		local text
		local status = snapshot.view and snapshot.view.status
		if type(status) == "string" then
			-- Party games describe their own phase ("Sam is drawing", "Question 3 of 10").
			text = esc(status)
		elseif isMyTurn() then
			text = `<font color="{hex(Theme.Accent)}">Your turn!</font>`
		elseif snapshot.yourSeat == nil and #active == 1 then
			text = `Watching · {esc(nameOf(active[1]))}'s turn`
		elseif #active == 1 then
			local s = snapshot.seats[active[1]]
			local name = esc(s.name)
			text = if s.kind == "bot" then `{name} is thinking...` else `Waiting for {name}...`
		else
			text = "Waiting for other players..."
		end

		local left = secondsLeft()
		if left then
			if timerFor ~= snapshot.turnEndsAt then
				timerFor = snapshot.turnEndsAt
				timerTotal = math.max(1, left)
			end
			local whole = math.ceil(left)
			local color = timerColor(left)
			text ..= `  <font color="{hex(color)}">{whole}s</font>`
			timerTrack.Visible = true
			timerFill.Size = UDim2.fromScale(math.clamp(left / timerTotal, 0, 1), 1)
			timerFill.BackgroundColor3 = color
			-- Tick for the last five seconds of your own turn.
			if isMyTurn() and whole <= 5 and whole >= 1 and whole ~= lastTick then
				lastTick = whole
				tickSound:Play()
			end
		else
			timerTrack.Visible = false
		end
		turnLabel.Text = prefix .. text

		-- The active seats' own timer bars.
		for _, chip in seatsPanel:GetChildren() do
			local bar = chip:FindFirstChild("Timer")
			if bar and bar:IsA("Frame") then
				local fill = bar:FindFirstChild("Fill") :: Frame?
				bar.Visible = left ~= nil
				if fill and left then
					fill.Size = UDim2.fromScale(math.clamp(left / timerTotal, 0, 1), 1)
					fill.BackgroundColor3 = timerColor(left)
				end
			end
		end
	end

	local function renderSeats()
		Kit.clear(seatsPanel)
		local compact = Layout.get().compact
		for index, s in snapshot.seats do
			local active = not isOver() and table.find(snapshot.activeSeats, index) ~= nil
			local info = snapshot.seatInfo and snapshot.seatInfo[index]
			local chipH = if compact then (if info then 38 else 32) else (if info then 52 else 40)
			local seatColor = Theme.Seat[index] or Theme.Text
			local frame = Kit.new("Frame", {
				Name = `Seat{index}`,
				BackgroundColor3 = if active then Theme.PanelLight else Theme.Background,
				BackgroundTransparency = if active then 0 else 0.3,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, chipH),
				LayoutOrder = index,
				ZIndex = 3,
				Parent = seatsPanel,
			}, { Kit.corner(8) })
			if active then
				Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 2, Parent = frame })
			end
			-- Seat color with a shape, so colors aren't the only way to tell seats apart.
			Kit.label(({ "●", "■", "▲", "◆", "★", "✖", "♥", "♣" })[index] or "●", {
				TextColor3 = seatColor,
				TextSize = if compact then 14 else 16,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.new(0, 2, 0, 0),
				Size = UDim2.new(0, 18, 0, if info then chipH - (if compact then 14 else 22) else chipH),
				ZIndex = 4,
				Parent = frame,
			})
			local icon = if s.kind == "bot" then "🤖 " else ""
			local nameH = if info then chipH - (if compact then 14 else 22) else chipH
			Kit.label(`{icon}{nameOf(index)}`, {
				Position = UDim2.new(0, 20, 0, if info then 2 else 0),
				Size = UDim2.new(1, -24, 0, nameH - (if info then 2 else 0)),
				Font = if active then Theme.FontBold else Theme.Font,
				TextSize = if compact then 13 else 16,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 4,
				Parent = frame,
			})
			if info then
				Kit.label(info, {
					Position = UDim2.new(0, 20, 0, nameH),
					Size = UDim2.new(1, -24, 0, if compact then 12 else 18),
					TextSize = if compact then 11 else 13,
					TextColor3 = Theme.SubText,
					TextWrapped = false,
					TextTruncate = Enum.TextTruncate.AtEnd,
					ZIndex = 4,
					Parent = frame,
				})
			end
			if active then
				local bar = Kit.new("Frame", {
					Name = "Timer",
					BackgroundColor3 = Color3.new(0, 0, 0),
					BackgroundTransparency = 0.5,
					BorderSizePixel = 0,
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 6, 1, -2),
					Size = UDim2.new(1, -12, 0, 3),
					Visible = false,
					ZIndex = 5,
					Parent = frame,
				})
				Kit.new("Frame", { Name = "Fill", BackgroundColor3 = Theme.Good, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = bar })
			end
		end
	end

	-- Reactions next to the seat chip. At a 3D table they pop over the player's head
	-- instead (Table3D/HeadReactions), unless you're looking at the 2D board.
	local chipReaction: { [number]: Frame } = {}
	reactionRemote.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" or not snapshot or payload.match ~= snapshot.matchId or type(payload.seat) ~= "number" then
			return
		end
		local reaction = Reactions.get(payload.id)
		local chip = seatsPanel:FindFirstChild(`Seat{payload.seat}`)
		if not reaction or not (chip and chip:IsA("GuiObject")) then
			return
		end
		local origin = root.AbsolutePosition
		local anchor, x, y
		if table3D.isActive() and payload.table ~= nil then
			-- Others see it over the head. Your own head is hidden behind the camera in
			-- the Table view, so yours shows bottom-center, above your docked hand.
			if payload.userId ~= localPlayer.UserId then
				return
			end
			anchor = Vector2.new(0.5, 1)
			x = root.AbsoluteSize.X / 2
			if dock.Visible then
				y = dock.AbsolutePosition.Y - origin.Y - 8
			else
				y = root.AbsoluteSize.Y - Layout.get().bottom - 24
			end
		else
			anchor = Vector2.new(0, 0.5)
			x = chip.AbsolutePosition.X + chip.AbsoluteSize.X + 4 - origin.X
			y = chip.AbsolutePosition.Y + chip.AbsoluteSize.Y / 2 - origin.Y
		end
		local old = chipReaction[payload.seat]
		if old then
			old:Destroy()
		end
		local base = if Layout.get().compact then 56 else 72
		if anchor.Y == 1 then
			base = math.floor(base * 1.3) -- the only one on screen: a bit bigger
		end
		local size = ReactionFx.size(reaction, base)
		local holder = Kit.new("Frame", {
			Name = "Reaction",
			BackgroundTransparency = 1,
			AnchorPoint = anchor,
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(size.X, size.Y),
			ZIndex = 40,
			Parent = root,
		})
		chipReaction[payload.seat] = holder
		holder.Destroying:Once(function()
			if chipReaction[payload.seat] == holder then
				chipReaction[payload.seat] = nil
			end
		end)
		ReactionFx.play(holder, reaction)
	end)

	local function renderResult()
		local result = snapshot.result
		local over = isOver()
		local wasShown = resultOverlay.Visible
		resultOverlay.Visible = over
		if not over then
			return
		end
		if not wasShown then
			Kit.popIn(resultOverlay)
		end
		local winners: { [number]: boolean } = {}
		for _, seat in (result and result.winners) or {} do
			winners[seat] = true
		end
		-- Gold when you won, light for a draw or a game you watched, muted when you lost.
		resultLabel.TextColor3 = Theme.Text
		if snapshot.aborted then
			resultLabel.Text = "Game ended"
		elseif result and result.isDraw then
			resultLabel.Text = "It's a draw!"
		elseif result and snapshot.yourSeat and winners[snapshot.yourSeat] then
			resultLabel.Text = "You win! 🎉"
			resultLabel.TextColor3 = Theme.Accent
		elseif result then
			if snapshot.yourSeat then
				resultLabel.TextColor3 = Theme.SubText
			end
			local names = {}
			for _, seat in result.winners do
				table.insert(names, nameOf(seat))
			end
			resultLabel.Text = `{table.concat(names, ", ")} won`
		end
		reasonLabel.Text = if result and result.reason then result.reason else ""

		-- Standings: winners first, then everyone else in seat order, with their last
		-- seat line (points, cards left...).
		Kit.clear(standings)
		local order = {}
		for index in snapshot.seats do
			table.insert(order, index)
		end
		table.sort(order, function(a, b)
			local wa, wb = winners[a] == true, winners[b] == true
			if wa ~= wb then
				return wa
			end
			return a < b
		end)
		for place, index in order do
			local s = snapshot.seats[index]
			local info = snapshot.seatInfo and snapshot.seatInfo[index]
			local row = Kit.new("Frame", {
				BackgroundColor3 = if index == snapshot.yourSeat then Theme.Panel else Theme.Background,
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				Size = UDim2.new(1, -4, 0, 30),
				LayoutOrder = place,
				ZIndex = 52,
				Parent = standings,
			}, { Kit.corner(6) })
			local medal = if winners[index] then "🏆" elseif result and result.isDraw then "🤝" else ""
			Kit.label(`{medal} {if s.kind == "bot" then "🤖 " else ""}{nameOf(index)}`, {
				Position = UDim2.new(0, 8, 0, 0),
				Size = UDim2.new(0.55, -8, 1, 0),
				Font = if winners[index] then Theme.FontBold else Theme.Font,
				TextSize = 15,
				TextColor3 = Theme.Seat[index] or Theme.Text,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 53,
				Parent = row,
			})
			Kit.label(info or "", {
				Position = UDim2.new(0.55, 0, 0, 0),
				Size = UDim2.new(0.45, -8, 1, 0),
				TextSize = 13,
				TextColor3 = Theme.SubText,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 53,
				Parent = row,
			})
		end

		if not rematchAsked then
			rematchButton.Text = if isLeader() then "Rematch" else "Ask for rematch"
			rematchButton.AutoButtonColor = true
			rematchButton.BackgroundColor3 = Theme.Accent
			rematchButton.TextColor3 = Theme.AccentText
		end
		-- Only people who were playing can ask (not spectators).
		rematchButton.Visible = snapshot.yourSeat ~= nil
		closeButton.Size = if rematchButton.Visible then UDim2.new(0.4, -4, 0, 46) else UDim2.new(1, 0, 0, 46)
	end

	closeButton = Kit.button("Lobby", function()
		snapshot = nil
		root.Visible = false
		resultOverlay.Visible = false
		closeMenu()
		table3D.setSnapshot(nil, false)
	end, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.new(0.4, -4, 0, 46),
		BackgroundColor3 = Theme.Panel,
		TextColor3 = Theme.Text,
		TextSize = 18,
		ZIndex = 51,
		Parent = resultOverlay,
	})

	RunService.Heartbeat:Connect(function()
		if root.Visible then
			updateTurnText()
		end
	end)

	return {
		root = root,
		-- What the player owns (wallet state), so the wheel shows their reaction packs.
		setOwned = emotes.setOwned,
		setSnapshot = function(newSnapshot: any)
			if newSnapshot == nil then
				-- We left the match; drop the view unless a result is still on screen.
				if snapshot and not isOver() then
					snapshot = nil
					root.Visible = false
					closeMenu()
					table3D.setSnapshot(nil, false)
				end
				return
			end
			if newSnapshot.matchId ~= shownMatchId or (snapshot ~= nil and newSnapshot.gameId ~= snapshot.gameId) then
				-- A new match (or a rematch): fresh end card and turn tracking.
				shownMatchId = newSnapshot.matchId
				rewardLabel.Text = ""
				rematchAsked = false
				wasMyTurn = false
				timerFor = nil
				closeMenu()
			end
			snapshot = newSnapshot
			root.Visible = true

			if rendererGameId ~= snapshot.gameId then
				if renderer and renderer.destroy then
					renderer.destroy()
				end
				Kit.clear(board)
				renderer = nil
				rendererGameId = snapshot.gameId
				local entry = GameCatalog.get(snapshot.gameId)
				local moduleScript = entry and entry.module and Renderers:FindFirstChild(entry.module)
				if moduleScript then
					renderer = (require(moduleScript) :: any).create(board, function(move: any)
						sendMatch({ action = "move", move = move })
					end)
				end
			end

			local over = isOver()
			leaveButton.Visible = not over
			endButton.Visible = not over and isLeader()
			resignButton.Visible = not over and #snapshot.seats == 2 and snapshot.yourSeat ~= nil
			menuButton.Visible = not over
			rulesButton.Visible = openRules ~= nil and not over
			if over then
				closeMenu()
			end
			renderSeats()

			-- Your turn just started: say so, loudly. Party games (everyone moves at once,
			-- with their own status line) skip the banner.
			local mine = isMyTurn()
			local status = snapshot.view and snapshot.view.status
			if mine and not wasMyTurn and type(status) ~= "string" then
				showBanner("Your turn!")
			end
			if mine ~= wasMyTurn then
				lastTick = -1
			end
			if not mine and wasMyTurn then
				hideBanner()
			end
			wasMyTurn = mine

			updateTurnText()
			if renderer then
				renderer.update(snapshot)
			end
			renderResult()
			table3D.setSnapshot(snapshot, wanted())
			applyMode()
		end,
		isOpen = function(): boolean
			return root.Visible
		end,
		-- The game being shown, so the wallet bar can show its Coins.
		gameId = function(): string?
			return if root.Visible and snapshot then snapshot.gameId else nil
		end,
		-- Shows match rewards on the results card. Returns false if no result is showing.
		showReward = function(lines: { string }): boolean
			if not (root.Visible and resultOverlay.Visible) then
				return false
			end
			rewardLabel.Text = table.concat(lines, "\n")
			return true
		end,
		relayout = function()
			relayout()
		end,
	}
end

return MatchView
