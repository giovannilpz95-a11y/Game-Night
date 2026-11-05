-- Property Party table, played the way the big online property-trading games play:
--
-- * The 40-space board on the left (11x11 ring of tiles), with owner outlines, houses
--   and hotels. Tokens hop space by space after a roll. Dice, the round, the jackpot and
--   the latest news sit in the middle.
-- * On the right: everyone's money (counting up and down, with +$ / -$ pop-ups and rent
--   flying from payer to owner) and their deeds as little color chips; under it, what you
--   can do now (Roll, End turn, Pay) plus Manage and Trade.
-- * One decision at a time pops up over the board (or over the table in Table view):
--   the deed card when you land on a free deed (Buy / Auction), the live auction with its
--   countdown and quick bids, your Jail choices, a trade offer to answer (Accept /
--   Counter / Decline), the trade screen and the Manage screen (build, sell, mortgage
--   every set at once).
-- * Every roll tumbles big in the middle, and drawn cards flip over.
--
-- Tapping any deed (on this board, or on the 3D board in Table view: tapTable) opens its
-- card. Board data and the build/mortgage checks come from the shared rules module, so
-- the buttons match what the server will accept. The server still checks everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Rules = require(ReplicatedStorage.Shared.Games.Estates)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local Kit = require(script.Parent.Parent.UI.Kit)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local Flair = require(script.Parent.Parent.UI.Flair)
local Audio = require(script.Parent.Parent.Audio)
local Theme = Kit.Theme
local Juice = Kit.Juice

local Estates = {}

local spaces = Rules.spaces
local TILE = 1 / 11
local BOARD_COLOR = Color3.fromRGB(214, 232, 214)
local TILE_COLOR = Color3.fromRGB(246, 243, 232)
local TILE_TEXT = Color3.fromRGB(40, 36, 50)
local DEED_PAPER = Color3.fromRGB(252, 249, 238)
local STATION_COLOR = Color3.fromRGB(70, 70, 80)
local UTILITY_COLOR = Color3.fromRGB(120, 190, 220)
local CORNER_KINDS = { start = true, jail = true, rest = true, gotojail = true }
local KIND_ICONS = {
	start = "START\n→ $200",
	jail = "JAIL",
	rest = "REST\nSTOP",
	gotojail = "GO TO\nJAIL",
	lucky = "?",
	mail = "✉",
	station = "🚉",
	utility = "⚡",
	tax = "$",
}
local HOP = 0.12 -- seconds per space when a token walks
local DICE_TIME = 0.6 -- the dice tumble before they land
local DIE_PIPS = { "⚀", "⚁", "⚂", "⚃", "⚄", "⚅" }

-- Grid cell (column, row; 0-based) of each board position. Start is bottom-right and
-- play goes clockwise: along the bottom, up the left, across the top, down the right.
local function cellOf(pos: number): (number, number)
	local i = pos - 1
	if i <= 10 then
		return 10 - i, 10
	elseif i <= 20 then
		return 0, 10 - (i - 10)
	elseif i <= 30 then
		return i - 20, 0
	end
	return 10, i - 30
end

local function money(n: number): string
	return `${n}`
end

local function deedColor(pos: number): Color3
	local space = spaces[pos]
	if space.kind == "street" then
		return Rules.groups[space.group].color
	elseif space.kind == "station" then
		return STATION_COLOR
	end
	return UTILITY_COLOR
end

-- A light color gets dark text on it.
local function textOn(color: Color3): Color3
	local lum = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
	return if lum > 0.6 then TILE_TEXT else Color3.new(1, 1, 1)
end

-- The pure rules' build/mortgage checks run on this stand-in state built from the view.
local function stateFromView(view: any): any
	local owner = {}
	for pos, seat in view.owner do
		owner[pos] = if seat ~= 0 then seat else nil
	end
	local players = {}
	for seat, p in view.players do
		players[seat] = { cash = p.cash, cards = table.create(p.cards, "card"), bankrupt = p.bankrupt }
	end
	return {
		owner = owner,
		houses = view.houses,
		mortgaged = view.mortgaged,
		housesLeft = view.housesLeft,
		hotelsLeft = view.hotelsLeft,
		players = players,
	}
end

local function groupHasBuildings(view: any, group: number): boolean
	for _, pos in Rules.groupMembers[group] do
		if view.houses[pos] > 0 then
			return true
		end
	end
	return false
end

local function tradable(view: any, pos: number): boolean
	local space = spaces[pos]
	return space.kind ~= "street" or not groupHasBuildings(view, space.group)
end

-- Rent lines for a deed card: { label, amount }.
local function rentLines(pos: number): { { string } }
	local space = spaces[pos]
	if space.kind == "street" then
		local r = space.rents
		return {
			{ "Rent", money(r[1]) },
			{ "Full color set", money(r[1] * 2) },
			{ "With 1 house", money(r[2]) },
			{ "With 2 houses", money(r[3]) },
			{ "With 3 houses", money(r[4]) },
			{ "With 4 houses", money(r[5]) },
			{ "With a hotel", money(r[6]) },
		}
	elseif space.kind == "station" then
		return { { "1 station", "$25" }, { "2 stations", "$50" }, { "3 stations", "$100" }, { "4 stations", "$200" } }
	end
	return { { "1 utility", "4x the dice" }, { "Both utilities", "10x the dice" } }
end

function Estates.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local docked = false
	local quiet = Kit.inPreview(container) -- picker previews: no pop-ups, no sound
	local alive = true

	-- What you opened yourself: a deed card, the trade screen or the Manage screen.
	local userPopup: { kind: string, pos: number? }? = nil
	local bankruptConfirm = false

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
	local rerender: () -> () = function() end

	local function play(sound: string, opts: any?)
		if not quiet then
			Audio.play(sound, opts)
		end
	end

	local function nameOf(seat: number?): string
		if seat == nil then
			return ""
		end
		if snapshot and seat == snapshot.yourSeat then
			return "You"
		end
		local s = snapshot and snapshot.seats[seat]
		return if s then s.name else `Seat {seat}`
	end

	-- Animation clock: the dice tumble, then the token walks, then the next choice pops
	-- up. Anything that should wait for the board to settle waits for busyUntil.
	local busyUntil = 0
	local function at(time: number, fn: () -> ())
		local wait = time - os.clock()
		if wait <= 0 then
			fn()
		else
			task.delay(wait, function()
				if alive then
					fn()
				end
			end)
		end
	end

	-- Board -------------------------------------------------------------------
	local boardArea = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(0.6, 1), Parent = root })
	local board = Kit.new("Frame", {
		BackgroundColor3 = BOARD_COLOR,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = boardArea,
	}, { Kit.corner(12), Kit.new("UIAspectRatioConstraint", { AspectRatio = 1 }) })

	local tapDeed: (pos: number) -> ()

	local tiles = {}
	for pos, space in spaces do
		local col, row = cellOf(pos)
		local tile = Kit.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = TILE_COLOR,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(col * TILE, row * TILE),
			Size = UDim2.fromScale(TILE, TILE),
			Parent = board,
		})
		local stroke = Kit.new("UIStroke", { Color = Color3.fromRGB(150, 150, 140), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = tile })
		local bar = nil
		if space.kind == "street" then
			bar = Kit.new("Frame", {
				BackgroundColor3 = Rules.groups[space.group].color,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 0.24),
				Parent = tile,
			})
		end
		local houses = Kit.label("", {
			Font = Theme.FontBold,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.4,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 0.24),
			ZIndex = 3,
			Parent = tile,
		})
		local icon = KIND_ICONS[space.kind]
		local name = Kit.label(if CORNER_KINDS[space.kind] then icon else space.name, {
			Font = if CORNER_KINDS[space.kind] then Theme.FontBold else Theme.Font,
			TextScaled = true,
			TextColor3 = TILE_TEXT,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			Position = UDim2.fromScale(0.04, if CORNER_KINDS[space.kind] then 0.05 else 0.25),
			Size = UDim2.fromScale(0.92, if CORNER_KINDS[space.kind] then 0.6 else 0.3),
			Parent = tile,
		})
		Kit.new("UITextSizeConstraint", { MaxTextSize = if CORNER_KINDS[space.kind] then 18 else 12, Parent = name })
		if icon and not CORNER_KINDS[space.kind] and space.kind ~= "street" then
			name.Text = `{icon} {space.name}`
		end
		local price = Kit.label(if space.price then money(space.price) elseif space.amount then `Pay {money(space.amount)}` else "", {
			TextScaled = true,
			TextColor3 = Color3.fromRGB(90, 86, 100),
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromScale(0, 0.53),
			Size = UDim2.fromScale(1, 0.13),
			Parent = tile,
		})
		Kit.new("UITextSizeConstraint", { MaxTextSize = 11, Parent = price })
		tile.Activated:Connect(function()
			if Rules.isDeed(pos) then
				tapDeed(pos)
			end
		end)
		tiles[pos] = { frame = tile, stroke = stroke, bar = bar, houses = houses, price = price }
	end

	-- Middle of the board: title, round, jackpot, dice, the last card, news.
	local middle = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(TILE + 0.02, TILE + 0.02),
		Size = UDim2.fromScale(1 - 2 * TILE - 0.04, 1 - 2 * TILE - 0.04),
		Parent = board,
	})
	local catalogEntry = GameCatalog.get(Rules.id)
	local title = Kit.label(string.upper(if catalogEntry then catalogEntry.name else "Property Party"), {
		Font = Theme.FontTitle,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(60, 120, 80),
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 0.12),
		Parent = middle,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 40, Parent = title })
	local roundLabel = Kit.label("", {
		TextScaled = true,
		TextColor3 = Color3.fromRGB(70, 90, 80),
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromScale(0, 0.12),
		Size = UDim2.fromScale(1, 0.05),
		Parent = middle,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 16, Parent = roundLabel })

	local diceRow = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromScale(0.3, 0.2), Size = UDim2.fromScale(0.4, 0.17), Parent = middle })
	local dice = {}
	for i = 1, 2 do
		local die = Kit.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(if i == 1 then 0.27 else 0.73, 0.5),
			Size = UDim2.fromScale(0.42, 1),
			Parent = diceRow,
		}, { Kit.corner(10), Kit.new("UIAspectRatioConstraint", { AspectRatio = 1 }), Kit.new("UIStroke", { Thickness = 2, Color = Color3.fromRGB(60, 60, 70) }) })
		dice[i] = Kit.label("", {
			Font = Theme.FontBold,
			TextScaled = true,
			TextColor3 = TILE_TEXT,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			Parent = die,
		})
	end
	local potLabel = Kit.label("", {
		Font = Theme.FontBold,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(160, 110, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromScale(0, 0.38),
		Size = UDim2.fromScale(1, 0.05),
		Visible = false,
		Parent = middle,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 16, Parent = potLabel })

	local cardBox = Kit.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 250, 220),
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.1, 0.44),
		Size = UDim2.fromScale(0.8, 0.15),
		Visible = false,
		Parent = middle,
	}, { Kit.corner(10), Kit.padding(6), Kit.new("UIStroke", { Thickness = 2, Color = Theme.Accent }) })
	local cardText = Kit.label("", {
		TextScaled = true,
		TextColor3 = TILE_TEXT,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = cardBox,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 16, Parent = cardText })

	local logFrame = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromScale(0, 0.62), Size = UDim2.fromScale(1, 0.38), Parent = middle })
	local logList = Kit.list(2)
	logList.VerticalAlignment = Enum.VerticalAlignment.Bottom
	logList.Parent = logFrame

	-- Tokens ride on their own layer so they can walk from space to space.
	local tokenLayer = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = board })
	type Token = { frame: Frame, lock: TextLabel, pos: number, jail: boolean, walk: thread? }
	local tokens: { [number]: Token } = {}

	local function tokenSpot(seat: number, pos: number, jail: boolean): UDim2
		local col, row = cellOf(pos)
		local angle = (seat - 1) / 8 * math.pi * 2
		local x = (col + 0.5) * TILE + math.cos(angle) * TILE * 0.22
		local y = (row + 0.7) * TILE + math.sin(angle) * TILE * 0.14
		if jail then
			x += TILE * 0.12
			y -= TILE * 0.3
		end
		return UDim2.fromScale(x, y)
	end

	local function moveToken(seat: number, p: any, startAt: number): number
		local t = tokens[seat]
		if p.bankrupt then
			if t then
				if t.walk then
					task.cancel(t.walk)
				end
				t.frame:Destroy()
				tokens[seat] = nil
			end
			return 0
		end
		local jail = p.inJail == true
		if not t then
			local frame = Kit.new("Frame", {
				BackgroundColor3 = HudKit.seatColor(seat),
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = tokenSpot(seat, p.pos, jail),
				Size = UDim2.fromScale(TILE * 0.32, TILE * 0.32),
				ZIndex = 7,
				Parent = tokenLayer,
			}, {
				Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
				Kit.new("UIStroke", { Thickness = 2, Color = Color3.fromRGB(30, 30, 40) }),
			})
			local lock = Kit.label("▥", { TextScaled = true, TextColor3 = Color3.new(0, 0, 0), TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 8, Visible = jail, Parent = frame })
			tokens[seat] = { frame = frame, lock = lock, pos = p.pos, jail = jail }
			return 0
		end
		if snapshot and seat == snapshot.yourSeat then
			(t.frame:FindFirstChildOfClass("UIStroke") :: UIStroke).Color = Color3.new(1, 1, 1)
		end
		if t.pos == p.pos and t.jail == jail then
			return 0
		end
		if t.walk then
			task.cancel(t.walk)
			t.walk = nil
		end
		local from, to = t.pos, p.pos
		t.pos, t.jail = to, jail
		local steps = (to - from) % #spaces
		local walking = not jail and steps >= 1 and steps <= 12
		local duration = if walking then steps * HOP else 0.6
		t.walk = task.spawn(function()
			local wait = startAt - os.clock()
			if wait > 0 then
				task.wait(wait)
			end
			t.frame.ZIndex = 9
			if walking then
				-- A dice move: hop along every space on the way.
				local scale = Juice.scale(t.frame, "Hop")
				for k = 1, steps do
					local nextPos = (from + k - 1) % #spaces + 1
					TweenService:Create(t.frame, TweenInfo.new(HOP * 0.9, Enum.EasingStyle.Quad), { Position = tokenSpot(seat, nextPos, false) }):Play()
					scale.Scale = 1.35
					TweenService:Create(scale, TweenInfo.new(HOP * 0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 1 }):Play()
					play("piece", { volume = 0.35, pitch = (k % 2) * 2 })
					task.wait(HOP)
				end
			else
				-- A card or Jail: one long glide over the board.
				TweenService:Create(t.frame, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Position = tokenSpot(seat, to, jail) }):Play()
				task.wait(0.6)
			end
			t.lock.Visible = jail
			t.frame.ZIndex = 7
			t.walk = nil
		end)
		return duration
	end

	-- Side panel: everyone's money and deeds, then what you can do -------------------------
	local side = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0.6, 12, 0, 0), Size = UDim2.new(0.4, -12, 1, 0), Parent = root })

	local playersPanel = Kit.panel({ Size = UDim2.new(1, 0, 0.56, -6), Parent = side })
	HudKit.sidePanel(playersPanel)
	local playersList = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		Parent = playersPanel,
	})
	Kit.list(6).Parent = playersList

	type Row = { frame: TextButton, stroke: UIStroke, name: TextLabel, cash: TextLabel, sub: TextLabel, chips: Frame, chipKey: string }
	local rows: { [number]: Row } = {}
	local shownCash: { [number]: number } = {}

	local openTrade: (partner: number?, wantPos: number?) -> ()

	local function makeRow(seat: number): Row
		local frame = Kit.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.PanelLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -6, 0, 60),
			LayoutOrder = seat,
			Parent = playersList,
		}, { Kit.corner(10) })
		local stroke = Kit.new("UIStroke", { Thickness = 2, Color = HudKit.seatColor(seat), Transparency = 1, Parent = frame })
		Kit.new("Frame", {
			BackgroundColor3 = HudKit.seatColor(seat),
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(22, 22),
		}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), Kit.new("UIStroke", { Thickness = 2, Color = Color3.fromRGB(30, 30, 40) }) }).Parent = frame
		local name = Kit.label("", { Font = Theme.FontBold, TextSize = 15, TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false, Position = UDim2.fromOffset(38, 4), Size = UDim2.new(1, -130, 0, 18), Parent = frame })
		local sub = Kit.label("", { TextSize = 12, TextColor3 = Theme.SubText, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(38, 21), Size = UDim2.new(1, -130, 0, 14), Parent = frame })
		local cash = Kit.label("", {
			Font = Theme.FontTitle,
			TextSize = 22,
			TextColor3 = Color3.fromRGB(140, 230, 150),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextWrapped = false,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 4),
			Size = UDim2.fromOffset(90, 28),
			Parent = frame,
		})
		local chips = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 38), Size = UDim2.new(1, -16, 0, 16), Parent = frame })
		Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(8, 14), CellPadding = UDim2.fromOffset(2, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = chips })
		frame.Activated:Connect(function()
			-- Tap someone to start a trade with them (on your turn).
			local view = snapshot and snapshot.view
			local me = snapshot and snapshot.yourSeat
			if view and me and seat ~= me and view.turn == me and (view.phase == "turn" or view.phase == "debt") and view.tradesLeft > 0 and not view.players[seat].bankrupt then
				openTrade(seat, nil)
			end
		end)
		return { frame = frame, stroke = stroke, name = name, cash = cash, sub = sub, chips = chips, chipKey = "" }
	end

	local actionPanel = Kit.panel({ Position = UDim2.fromScale(0, 0.56), Size = UDim2.new(1, 0, 0.44, 0), Parent = side })
	local actionText = Kit.label("", {
		TextSize = 16,
		Font = Theme.FontBold,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 1, -98),
		Parent = actionPanel,
	})
	-- A big main button over a row of smaller ones, pinned to the bottom of the panel.
	local primaryRow = Kit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -44), Size = UDim2.new(1, 0, 0, 48), Parent = actionPanel })
	local secondaryRow = Kit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 38), Parent = actionPanel })
	local secondaryList = Kit.list(6, true)
	secondaryList.HorizontalFlex = Enum.UIFlexAlignment.Fill
	secondaryList.Parent = secondaryRow

	-- Pop-ups -----------------------------------------------------------------------
	-- They sit on the whole screen, not in this board: Table view docks only the side
	-- panel, and the rest of the screen is the table. They center on the board (2D) or
	-- the table (Table view), left of the side panel.
	local overlay = Kit.new("Frame", { Name = "EstatesOverlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 40, Parent = root })
	local function attachOverlay()
		local screen = if quiet then nil else container:FindFirstAncestorWhichIsA("ScreenGui")
		local parent = screen or root
		if overlay.Parent ~= parent then
			overlay.Parent = parent
		end
	end

	-- Center and size (pixels, in the overlay's space) of the area pop-ups go over.
	local function stage(): (Vector2, Vector2)
		local o = overlay.AbsolutePosition
		local right = side.AbsolutePosition.X - o.X - 10
		local top = side.AbsolutePosition.Y - o.Y
		local height = side.AbsoluteSize.Y
		local left = if docked then 0 else math.max(0, boardArea.AbsolutePosition.X - o.X)
		if right - left < 240 then
			-- Not enough room beside the panel (a narrow phone): go over everything.
			left, right = 0, overlay.AbsoluteSize.X
		end
		return Vector2.new((left + right) / 2, top + height / 2), Vector2.new(right - left, height)
	end

	local popup = Kit.new("TextButton", {
		Name = "Popup",
		Text = "",
		AutoButtonColor = false,
		Active = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 41,
		Parent = overlay,
	}, { Kit.corner(16), Kit.padding(12), Kit.shade(0.12), Kit.new("UIStroke", { Name = "Outline", Thickness = 2, Color = Theme.Stroke, Transparency = 0.2 }) })
	local popupKind: string? = nil
	local popupWant = Vector2.new(320, 420)
	local timerBar: Frame? = nil
	local timerText: TextLabel? = nil

	local function placePopup()
		local center, size = stage()
		local w = math.min(popupWant.X, size.X - 16)
		local h = math.min(popupWant.Y, size.Y - 16)
		popup.Position = UDim2.fromOffset(center.X, center.Y)
		popup.Size = UDim2.fromOffset(math.max(200, w), math.max(160, h))
	end
	side:GetPropertyChangedSignal("AbsolutePosition"):Connect(placePopup)
	side:GetPropertyChangedSignal("AbsoluteSize"):Connect(placePopup)

	-- Shows the pop-up `kind`, built by `build` (rebuilt on every update; it only pops
	-- in when the kind changes).
	local function openPopup(kind: string, want: Vector2, build: (Frame) -> ())
		local fresh = popupKind ~= kind or not popup.Visible
		Kit.clear(popup)
		timerBar, timerText = nil, nil
		popup.BackgroundColor3 = Theme.Panel
		popupWant = want
		placePopup()
		popupKind = kind
		build(popup)
		popup.Visible = true
		if fresh then
			Juice.popIn(popup)
			play("pop")
		end
	end

	local function closePopup()
		popupKind = nil
		popup.Visible = false
		timerBar, timerText = nil, nil
	end

	-- Small builders for pop-up content ------------------------------------------------
	local function z(props: { [string]: any }): { [string]: any }
		props.ZIndex = 42
		return props
	end

	local function popButton(parent: Instance, text: string, color: Color3?, onClick: () -> (), enabled: boolean?, order: number?): TextButton
		local on = enabled ~= false
		local button = Kit.button(text, function()
			if on then
				onClick()
			else
				Juice.nope(popup)
			end
		end, z({
			BackgroundColor3 = if not on then Theme.PanelLight elseif color then color else Theme.Accent,
			BackgroundTransparency = if on then 0 else 0.4,
			TextColor3 = if not on then Theme.SubText elseif color then textOn(color) else Theme.AccentText,
			AutoButtonColor = on,
			TextSize = 15,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 40),
			LayoutOrder = order or 0,
			Parent = parent,
		}))
		return button
	end

	-- A row of buttons along the bottom of a pop-up.
	local function buttonBar(parent: Instance, height: number?): Frame
		local bar = Kit.new("Frame", z({ BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, height or 40), Parent = parent }))
		local list = Kit.list(8, true)
		list.HorizontalFlex = Enum.UIFlexAlignment.Fill
		list.Parent = bar
		return bar
	end

	-- The deed card itself: color band with the name, the rent table, costs, owner.
	local function deedCard(parent: Instance, pos: number, height: UDim): Frame
		local space = spaces[pos]
		local view = snapshot.view
		local color = deedColor(pos)
		local card = Kit.new("Frame", z({ BackgroundColor3 = DEED_PAPER, BorderSizePixel = 0, Size = UDim2.new(1, 0, height.Scale, height.Offset), Parent = parent }), {
			Kit.corner(10),
			Kit.new("UIStroke", { Thickness = 2, Color = Color3.fromRGB(60, 56, 70) }),
		})
		local band = Kit.new("Frame", z({ BackgroundColor3 = color, BorderSizePixel = 0, Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 0, 50), Parent = card }), {
			Kit.corner(6),
			Kit.new("UIStroke", { Thickness = 1.5, Color = Color3.fromRGB(40, 36, 50) }),
		})
		local kindText = if space.kind == "street" then "TITLE DEED" elseif space.kind == "station" then "🚉 STATION" else "⚡ UTILITY"
		Kit.label(kindText, z({ TextSize = 11, Font = Theme.FontBold, TextColor3 = textOn(color), TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 3), Parent = band }))
		Kit.label(string.upper(space.name), z({ TextSize = 18, Font = Theme.FontTitle, TextColor3 = textOn(color), TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, Size = UDim2.new(1, -8, 0, 26), Position = UDim2.fromOffset(4, 19), Parent = band }), {
			Kit.new("UITextSizeConstraint", { MaxTextSize = 20 }),
		})
		local lines = rentLines(pos)
		local listFrame = Kit.new("Frame", z({ BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 62), Size = UDim2.new(1, -28, 1, -62 - 52), Parent = card }))
		local layout = Kit.list(0)
		layout.VerticalFlex = Enum.UIFlexAlignment.Fill
		layout.Parent = listFrame
		local owner = view.owner[pos]
		local h = view.houses[pos]
		local liveRent = nil
		if owner ~= 0 and not view.mortgaged[pos] and space.kind == "street" then
			-- Which line of the table is charged right now.
			liveRent = if h > 0 then h + 2 elseif Rules.ownsGroup(stateFromView(view), owner, space.group) then 2 else 1
		end
		for i, line in lines do
			local row = Kit.new("Frame", z({ BackgroundTransparency = if i == liveRent then 0.2 else 1, BackgroundColor3 = Color3.fromRGB(255, 226, 120), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = i, Parent = listFrame }), { Kit.corner(4) })
			Kit.label(line[1], z({ TextSize = 13, TextColor3 = TILE_TEXT, TextWrapped = false, Position = UDim2.fromOffset(4, 0), Size = UDim2.new(0.7, -4, 1, 0), Parent = row }))
			Kit.label(line[2], z({ TextSize = 13, Font = Theme.FontBold, TextColor3 = TILE_TEXT, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0.5, -4, 1, 0), Parent = row }))
		end
		local costs = `Price {money(space.price)} · Mortgage {money(space.price // 2)}`
		if space.kind == "street" then
			costs ..= `\nHouses {money(space.houseCost)} each · Hotel {money(space.houseCost)} + 4 houses`
		end
		Kit.label(costs, z({ TextSize = 11, TextColor3 = Color3.fromRGB(90, 86, 100), TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -24), Size = UDim2.new(1, -16, 0, 28), Parent = card }))
		local ownerText = if owner == 0 then "For sale" else `Owner: {nameOf(owner)}`
		if view.mortgaged[pos] then
			ownerText ..= " · MORTGAGED"
		elseif h == 5 then
			ownerText ..= " · Hotel"
		elseif h > 0 then
			ownerText ..= ` · {h} house{if h > 1 then "s" else ""}`
		end
		local ownerLabel = Kit.label(ownerText, z({ TextSize = 13, Font = Theme.FontBold, TextColor3 = if owner ~= 0 then HudKit.shade(HudKit.seatColor(owner), 0.45) else Color3.fromRGB(40, 120, 70), TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 6, 1, -4), Size = UDim2.new(1, -12, 0, 18), Parent = card }))
		ownerLabel.TextWrapped = false
		return card
	end

	-- One line in a trade list: color chip, name, price.
	local function deedLine(parent: Instance, pos: number, picked: boolean?, onClick: (() -> ())?, order: number?)
		local space = spaces[pos]
		local view = snapshot.view
		local row = Kit.new(if onClick then "TextButton" else "Frame", z({
			BackgroundColor3 = if picked then Theme.Accent else Theme.PanelLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = order or pos,
			Parent = parent,
		}), { Kit.corner(6) })
		if onClick then
			row.Text = ""
			row.AutoButtonColor = true;
			(row :: TextButton).Activated:Connect(onClick)
		end
		Kit.new("Frame", z({ BackgroundColor3 = deedColor(pos), BorderSizePixel = 0, Position = UDim2.fromOffset(4, 4), Size = UDim2.new(0, 8, 1, -8), Parent = row }), { Kit.corner(3) })
		Kit.label(`{space.name}{if view.mortgaged[pos] then " (M)" else ""}`, z({
			TextSize = 13,
			TextColor3 = if picked then Theme.AccentText else Theme.Text,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(16, 0),
			Size = UDim2.new(1, -60, 1, 0),
			Parent = row,
		}))
		Kit.label(money(space.price), z({ TextSize = 12, TextColor3 = if picked then Theme.AccentText else Theme.SubText, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false, Position = UDim2.new(1, -48, 0, 0), Size = UDim2.new(0, 44, 1, 0), Parent = row }))
	end

	local function describeSide(sideData: any): string
		local parts = {}
		for _, pos in sideData.props do
			table.insert(parts, spaces[pos].name)
		end
		if sideData.cash > 0 then
			table.insert(parts, money(sideData.cash))
		end
		if sideData.cards > 0 then
			table.insert(parts, `{sideData.cards} Jail card{if sideData.cards > 1 then "s" else ""}`)
		end
		return if #parts > 0 then table.concat(parts, ", ") else "nothing"
	end

	local function sideValue(sideData: any): number
		local total = sideData.cash + 50 * sideData.cards
		for _, pos in sideData.props do
			total += if snapshot.view.mortgaged[pos] then spaces[pos].price // 2 else spaces[pos].price
		end
		return total
	end

	-- A column listing one side of a trade (for answering an offer).
	local function offerColumn(parent: Instance, x: number, heading: string, sideData: any)
		local col = Kit.new("Frame", z({ BackgroundTransparency = 1, Position = UDim2.new(x, if x > 0 then 5 else 0, 0, 0), Size = UDim2.new(0.5, -5, 1, 0), Parent = parent }))
		Kit.label(heading, z({ TextSize = 14, Font = Theme.FontBold, Size = UDim2.new(1, 0, 0, 18), Parent = col }))
		local list = Kit.new("ScrollingFrame", z({
			BackgroundColor3 = Theme.Background,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 20),
			Size = UDim2.new(1, 0, 1, -20),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 4,
			Parent = col,
		}), { Kit.corner(8), Kit.padding(5) })
		Kit.list(4).Parent = list
		for i, pos in sideData.props do
			deedLine(list, pos, false, nil, i)
		end
		if sideData.cash > 0 then
			Kit.label(`💵 {money(sideData.cash)}`, z({ TextSize = 15, Font = Theme.FontBold, TextColor3 = Color3.fromRGB(140, 230, 150), LayoutOrder = 100, Parent = list }))
		end
		if sideData.cards > 0 then
			Kit.label(`🎟 {sideData.cards} Get Out of Jail card{if sideData.cards > 1 then "s" else ""}`, z({ TextSize = 13, LayoutOrder = 101, Parent = list }))
		end
		if #sideData.props == 0 and sideData.cash == 0 and sideData.cards == 0 then
			Kit.label("Nothing", z({ TextSize = 13, TextColor3 = Theme.SubText, Parent = list }))
		end
	end

	-- Trade screen ------------------------------------------------------------------------
	-- counter: answering an offer with your own terms (partner fixed, sent as "counter").
	local tradeDraft = {
		partner = nil :: number?,
		give = {} :: { [number]: boolean },
		get = {} :: { [number]: boolean },
		giveCash = 0,
		getCash = 0,
		giveCards = 0,
		getCards = 0,
		counter = false,
	}

	local function picks(set: { [number]: boolean }): { number }
		local out = {}
		for pos, on in set do
			if on then
				table.insert(out, pos)
			end
		end
		table.sort(out)
		return out
	end

	function openTrade(partner: number?, wantPos: number?)
		tradeDraft.partner = partner
		table.clear(tradeDraft.give)
		table.clear(tradeDraft.get)
		tradeDraft.giveCash, tradeDraft.getCash, tradeDraft.giveCards, tradeDraft.getCards = 0, 0, 0, 0
		tradeDraft.counter = false
		if wantPos then
			tradeDraft.get[wantPos] = true
		end
		userPopup = { kind = "trade" }
		rerender()
	end

	local function openCounter()
		local t = snapshot.view.trade
		tradeDraft.partner = t.from
		table.clear(tradeDraft.give)
		table.clear(tradeDraft.get)
		-- Start from their offer, seen from your side.
		for _, pos in t.get.props do
			tradeDraft.give[pos] = true
		end
		for _, pos in t.give.props do
			tradeDraft.get[pos] = true
		end
		tradeDraft.giveCash, tradeDraft.getCash = t.get.cash, t.give.cash
		tradeDraft.giveCards, tradeDraft.getCards = t.get.cards, t.give.cards
		tradeDraft.counter = true
		userPopup = { kind = "trade" }
		rerender()
	end

	-- Tapping a deed on the board while trading puts it on (or takes it off) the table.
	local function toggleTradeDeed(pos: number): boolean
		local view = snapshot.view
		local me = snapshot.yourSeat
		local owner = view.owner[pos]
		if not tradable(view, pos) or owner == 0 then
			return false
		end
		if owner == me then
			tradeDraft.give[pos] = not tradeDraft.give[pos]
		elseif not tradeDraft.counter and (tradeDraft.partner == nil or tradeDraft.partner == owner) then
			tradeDraft.partner = owner
			tradeDraft.get[pos] = not tradeDraft.get[pos]
		elseif tradeDraft.partner == owner then
			tradeDraft.get[pos] = not tradeDraft.get[pos]
		else
			return false
		end
		rerender()
		return true
	end

	local function buildTrade(frame: Frame)
		local view = snapshot.view
		local me = snapshot.yourSeat
		local partner = tradeDraft.partner
		Kit.label(if tradeDraft.counter then `Counter-offer to {nameOf(partner)}` else "Trade", z({ TextSize = 22, Font = Theme.FontTitle, Size = UDim2.new(1, -40, 0, 26), Parent = frame }))
		Kit.closeButton(function()
			if tradeDraft.counter then
				userPopup = nil
			else
				userPopup = nil
			end
			rerender()
		end, { ZIndex = 45, Parent = frame })
		local y = 30
		if not tradeDraft.counter then
			local partnerRow = Kit.new("ScrollingFrame", z({ BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 34), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollBarThickness = 0, Parent = frame }))
			Kit.list(6, true).Parent = partnerRow
			for seat, p in view.players do
				if seat ~= me and not p.bankrupt then
					local chosen = partner == seat
					Kit.button(nameOf(seat), function()
						if tradeDraft.partner ~= seat then
							tradeDraft.partner = seat
							table.clear(tradeDraft.get)
							tradeDraft.getCash, tradeDraft.getCards = 0, 0
						end
						rerender()
					end, z({
						BackgroundColor3 = if chosen then HudKit.seatColor(seat) else Theme.PanelLight,
						TextColor3 = if chosen then textOn(HudKit.seatColor(seat)) else Theme.Text,
						TextSize = 14,
						Size = UDim2.fromOffset(110, 32),
						TextTruncate = Enum.TextTruncate.AtEnd,
						Parent = partnerRow,
					}))
				end
			end
			y += 40
		end

		local function column(x: number, seat: number?, set: { [number]: boolean }, cashKey: string, cardsKey: string, heading: string)
			local col = Kit.new("Frame", z({ BackgroundTransparency = 1, Position = UDim2.new(x, if x > 0 then 5 else 0, 0, y), Size = UDim2.new(0.5, -5, 1, -y - 70), Parent = frame }))
			Kit.label(heading, z({ TextSize = 14, Font = Theme.FontBold, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, 0, 0, 18), Parent = col }))
			local list = Kit.new("ScrollingFrame", z({
				BackgroundColor3 = Theme.Background,
				BackgroundTransparency = 0.3,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, 20),
				Size = UDim2.new(1, 0, 1, -20 - 72),
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollBarThickness = 4,
				Parent = col,
			}), { Kit.corner(8), Kit.padding(5) })
			Kit.list(4).Parent = list
			if not seat then
				Kit.label("Pick a player above, or tap one of their deeds on the board.", z({ TextSize = 13, TextColor3 = Theme.SubText, Size = UDim2.new(1, 0, 0, 52), Parent = list }))
				return
			end
			for pos in set do
				if view.owner[pos] ~= seat or not tradable(view, pos) then
					set[pos] = nil -- changed hands or got buildings since it was picked
				end
			end
			local any = false
			for pos = 1, #spaces do
				if view.owner[pos] == seat and Rules.isDeed(pos) and tradable(view, pos) then
					any = true
					deedLine(list, pos, set[pos] == true, function()
						set[pos] = not set[pos]
						rerender()
					end)
				end
			end
			if not any then
				Kit.label("No deeds to trade", z({ TextSize = 13, TextColor3 = Theme.SubText, Parent = list }))
			end
			-- Cash: steppers instead of typing (quick on phones).
			local have = view.players[seat].cash
			local draft = tradeDraft :: any
			draft[cashKey] = math.clamp(draft[cashKey], 0, have)
			local cashRow = Kit.new("Frame", z({ BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -36), Size = UDim2.new(1, 0, 0, 32), Parent = col }))
			local cashList = Kit.list(3, true)
			cashList.HorizontalFlex = Enum.UIFlexAlignment.Fill
			cashList.VerticalAlignment = Enum.VerticalAlignment.Center
			cashList.Parent = cashRow
			local function step(delta: number, order: number)
				Kit.button(if delta > 0 then `+{delta}` else `{delta}`, function()
					draft[cashKey] = math.clamp(draft[cashKey] + delta, 0, have)
					rerender()
				end, z({ BackgroundColor3 = Theme.PanelLight, TextColor3 = Theme.Text, TextSize = 12, Size = UDim2.fromOffset(30, 30), LayoutOrder = order, Parent = cashRow }))
			end
			step(-100, 1)
			step(-10, 2)
			Kit.label(money(draft[cashKey]), z({ TextSize = 15, Font = Theme.FontBold, TextColor3 = Color3.fromRGB(140, 230, 150), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, Size = UDim2.fromOffset(56, 30), LayoutOrder = 3, Parent = cashRow }))
			step(10, 4)
			step(100, 5)
			local cards = view.players[seat].cards
			draft[cardsKey] = math.clamp(draft[cardsKey], 0, cards)
			local cardButton = Kit.button(if cards > 0 then `🎟 Jail cards: {draft[cardsKey]} of {cards}` else `Cash: has {money(have)}`, function()
				if cards > 0 then
					draft[cardsKey] = (draft[cardsKey] + 1) % (cards + 1)
					rerender()
				end
			end, z({ BackgroundColor3 = Theme.Panel, TextColor3 = Theme.SubText, AutoButtonColor = cards > 0, TextSize = 12, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 30), Parent = col }))
			cardButton.TextWrapped = true
		end
		column(0, me, tradeDraft.give, "giveCash", "giveCards", "You give")
		column(0.5, partner, tradeDraft.get, "getCash", "getCards", if partner then `You get from {nameOf(partner)}` else "You get")

		local give = { props = picks(tradeDraft.give), cash = tradeDraft.giveCash, cards = tradeDraft.giveCards }
		local get = { props = picks(tradeDraft.get), cash = tradeDraft.getCash, cards = tradeDraft.getCards }
		local empty = #give.props + #get.props + give.cash + get.cash + give.cards + get.cards == 0
		Kit.label(`Worth: you give {money(sideValue(give))} · you get {money(sideValue(get))}`, z({ TextSize = 12, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -46), Size = UDim2.new(1, 0, 0, 18), Parent = frame }))
		local bar = buttonBar(frame)
		popButton(bar, "Cancel", Theme.PanelLight, function()
			userPopup = nil
			rerender()
		end, true, 1)
		popButton(bar, if tradeDraft.counter then "Send counter" else "Send offer", nil, function()
			if not partner or empty then
				return
			end
			if tradeDraft.counter then
				sendMove({ kind = "counter", give = give, get = get })
			else
				sendMove({ kind = "offer", to = partner, give = give, get = get })
			end
			userPopup = nil
			closePopup()
		end, partner ~= nil and not empty, 2)
	end

	-- Manage screen: every set you own, with build / sell / mortgage on each deed -------------
	local function buildManage(frame: Frame)
		local view = snapshot.view
		local me = snapshot.yourSeat :: number
		local fake = stateFromView(view)
		local debt = view.phase == "debt"
		Kit.label("Manage your deeds", z({ TextSize = 22, Font = Theme.FontTitle, Size = UDim2.new(1, -40, 0, 26), Parent = frame }))
		Kit.closeButton(function()
			userPopup = nil
			rerender()
		end, { ZIndex = 45, Parent = frame })
		Kit.label(`Cash {money(view.players[me].cash)} · Bank has {view.housesLeft} houses and {view.hotelsLeft} hotels{if debt then " · Raise cash: sell or mortgage" else ""}`, z({ TextSize = 13, TextColor3 = Theme.SubText, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 16), Parent = frame }))
		local scroll = Kit.new("ScrollingFrame", z({
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 50),
			Size = UDim2.new(1, 0, 1, -50),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 5,
			Parent = frame,
		}))
		Kit.new("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 0, 150), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })

		local function setCard(order: number, titleText: string, color: Color3, members: { number }, full: boolean)
			local card = Kit.new("Frame", z({ BackgroundColor3 = Theme.PanelLight, BorderSizePixel = 0, LayoutOrder = order, Parent = scroll }), { Kit.corner(10) })
			local band = Kit.new("Frame", z({ BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 24), Parent = card }), { Kit.corner(10) })
			Kit.label(titleText .. (if full then "  ★ Full set" else ""), z({ TextSize = 14, Font = Theme.FontBold, TextColor3 = textOn(color), TextWrapped = false, Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, 0), Parent = band }))
			local list = Kit.new("Frame", z({ BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 28), Size = UDim2.new(1, -12, 1, -32), Parent = card }))
			Kit.list(4).Parent = list
			for i, pos in members do
				local space = spaces[pos]
				local mine = view.owner[pos] == me
				local row = Kit.new("Frame", z({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = i, Parent = list }))
				local h = view.houses[pos]
				local status = if not mine then (if view.owner[pos] == 0 then "for sale" else nameOf(view.owner[pos]))
					elseif view.mortgaged[pos] then "mortgaged"
					elseif h == 5 then "🏨 hotel"
					elseif h > 0 then string.rep("🏠", h)
					else "no houses"
				Kit.label(space.name, z({ TextSize = 13, Font = Theme.FontBold, TextColor3 = if mine then Theme.Text else Theme.SubText, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, -96, 0, 16), Parent = row }))
				Kit.label(status, z({ TextSize = 11, TextColor3 = Theme.SubText, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, -96, 0, 16), Parent = row }))
				if mine then
					local buttons = Kit.new("Frame", z({ BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), Size = UDim2.fromOffset(94, 30), Parent = row }))
					Kit.list(3, true).Parent = buttons
					local function small(text: string, kind: string, ok: boolean, color: Color3?, width: number)
						Kit.button(text, function()
							if ok then
								sendMove({ kind = kind, pos = pos })
							else
								Juice.nope(row)
							end
						end, z({
							BackgroundColor3 = if ok then (color or Theme.Accent) else Theme.Panel,
							BackgroundTransparency = if ok then 0 else 0.3,
							TextColor3 = if ok then (if color then textOn(color) else Theme.AccentText) else Theme.SubText,
							AutoButtonColor = ok,
							TextSize = 12,
							Size = UDim2.fromOffset(width, 30),
							Parent = buttons,
						}))
					end
					if space.kind == "street" then
						small("−", "sell", (Rules.canSell(fake, me, pos)), Theme.Warn, 26)
						small("+", "build", (Rules.canBuild(fake, me, pos)) and not debt, Theme.Good, 26)
					end
					if view.mortgaged[pos] then
						small("Pay off", "unmortgage", (Rules.canUnmortgage(fake, me, pos)) and not debt, Theme.Accent, 36)
					else
						small("Mort.", "mortgage", (Rules.canMortgage(fake, me, pos)), Theme.PanelLight, 36)
					end
				end
			end
		end

		local order = 0
		for g, group in Rules.groups do
			local members = Rules.groupMembers[g]
			local owned = 0
			for _, pos in members do
				if view.owner[pos] == me then
					owned += 1
				end
			end
			if owned > 0 then
				order += 1
				setCard(order, group.name, group.color, members, owned == #members)
			end
		end
		for _, list in { { "Stations", STATION_COLOR, Rules.stations }, { "Utilities", UTILITY_COLOR, Rules.utilities } } do
			local mine = {}
			for _, pos in list[3] :: { number } do
				if view.owner[pos] == me then
					table.insert(mine, pos)
				end
			end
			if #mine > 0 then
				order += 1
				setCard(order, list[1] :: string, list[2] :: Color3, mine, false)
			end
		end
		if order == 0 then
			Kit.label("You don't own any deeds yet. Land on one and buy it!", z({ TextSize = 15, TextColor3 = Theme.SubText, Parent = scroll }))
		end
	end

	-- The pop-ups ---------------------------------------------------------------------------
	local function deedPopup(pos: number, landing: boolean)
		local view = snapshot.view
		local me = snapshot.yourSeat
		local space = spaces[pos]
		openPopup(if landing then `land{pos}` else `deed{pos}`, Vector2.new(290, 430), function(frame)
			popup.BackgroundColor3 = Theme.Panel
			if not landing then
				Kit.closeButton(function()
					userPopup = nil
					rerender()
				end, { ZIndex = 45, Parent = frame })
			end
			local buttonRows = 1
			local mine = me ~= nil and view.owner[pos] == me
			local manage = mine and view.turn == me and (view.phase == "turn" or view.phase == "buy" or view.phase == "debt")
			if manage and space.kind == "street" then
				buttonRows = 2
			end
			deedCard(frame, pos, UDim.new(1, -(buttonRows * 46)))
			local bar = buttonBar(frame, buttonRows * 46 - 6)
			if landing then
				local active = snapshot.activeSeats[1]
				if active == me then
					local cash = view.players[me].cash
					popButton(bar, if view.auctions then "Auction" else "Pass", Theme.PanelLight, function()
						sendMove({ kind = "decline" })
					end, true, 2)
					popButton(bar, `Buy {money(space.price)}`, Theme.Good, function()
						sendMove({ kind = "buy" })
					end, cash >= space.price, 1)
				else
					Kit.label(`{nameOf(active)} is deciding...`, z({ TextSize = 15, Font = Theme.FontBold, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = bar }))
				end
				return
			end
			if manage then
				bar:FindFirstChildOfClass("UIListLayout"):Destroy()
				local grid = Kit.new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 40), CellPadding = UDim2.fromOffset(8, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = bar })
				grid.Parent = bar
				local fake = stateFromView(view)
				local h = view.houses[pos]
				local debt = view.phase == "debt"
				if space.kind == "street" then
					popButton(bar, if h == 4 then `Hotel {money(space.houseCost)}` else `House {money(space.houseCost)}`, Theme.Good, function()
						sendMove({ kind = "build", pos = pos })
					end, (Rules.canBuild(fake, me, pos)) and not debt, 1)
					popButton(bar, `Sell +{money(space.houseCost // 2)}`, Theme.Warn, function()
						sendMove({ kind = "sell", pos = pos })
					end, (Rules.canSell(fake, me, pos)), 2)
				end
				if view.mortgaged[pos] then
					popButton(bar, `Pay off {money(Rules.unmortgageCost(pos))}`, nil, function()
						sendMove({ kind = "unmortgage", pos = pos })
					end, (Rules.canUnmortgage(fake, me, pos)) and not debt, 3)
				else
					popButton(bar, `Mortgage +{money(space.price // 2)}`, Theme.PanelLight, function()
						sendMove({ kind = "mortgage", pos = pos })
					end, (Rules.canMortgage(fake, me, pos)), 3)
				end
				popButton(bar, "Close", Theme.PanelLight, function()
					userPopup = nil
					rerender()
				end, true, 4)
				return
			end
			local owner = view.owner[pos]
			local canAsk = me ~= nil and owner ~= 0 and owner ~= me and view.turn == me and (view.phase == "turn" or view.phase == "debt") and view.tradesLeft > 0 and tradable(view, pos)
			if canAsk then
				popButton(bar, "Ask to trade", nil, function()
					openTrade(owner, pos)
				end, true, 1)
			end
			popButton(bar, "Close", Theme.PanelLight, function()
				userPopup = nil
				rerender()
			end, true, 2)
		end)
	end

	local function auctionPopup()
		local view = snapshot.view
		local me = snapshot.yourSeat
		local a = view.auction
		local space = spaces[a.pos]
		openPopup("auction", Vector2.new(330, 330), function(frame)
			local color = deedColor(a.pos)
			local band = Kit.new("Frame", z({ BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 44), Parent = frame }), { Kit.corner(10) })
			Kit.label("AUCTION", z({ TextSize = 11, Font = Theme.FontBold, TextColor3 = textOn(color), TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 3), Parent = band }))
			Kit.label(`{string.upper(space.name)} · worth {money(space.price)}`, z({ TextSize = 17, Font = Theme.FontTitle, TextColor3 = textOn(color), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, TextScaled = true, Position = UDim2.fromOffset(6, 17), Size = UDim2.new(1, -12, 0, 22), Parent = band }), {
				Kit.new("UITextSizeConstraint", { MaxTextSize = 18 }),
			})
			Kit.label("Top bid", z({ TextSize = 13, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 16), Parent = frame }))
			local high = Kit.label(if a.leader then money(a.high) else "No bids yet", z({ TextSize = 34, Font = Theme.FontTitle, TextColor3 = Color3.fromRGB(140, 230, 150), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 38), Parent = frame }))
			if a.leader then
				Kit.label(if a.leader == me then "That's you!" else nameOf(a.leader), z({ TextSize = 15, Font = Theme.FontBold, TextColor3 = HudKit.seatColor(a.leader), TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 102), Size = UDim2.new(1, 0, 0, 18), Parent = frame }))
				if a.bids > 0 and popupKind == "auction" then
					Juice.bump(high, 0.2)
				end
			end
			-- The countdown: restarts on every bid.
			local track = Kit.new("Frame", z({ BackgroundColor3 = Theme.Background, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 126), Size = UDim2.new(1, 0, 0, 10), Parent = frame }), { Kit.corner(5) })
			timerBar = Kit.new("Frame", z({ BackgroundColor3 = Theme.Good, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = track }), { Kit.corner(5) })
			timerText = Kit.label("", z({ TextSize = 13, Font = Theme.FontBold, TextColor3 = Theme.Warn, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 138), Size = UDim2.new(1, 0, 0, 16), Parent = frame }))
			-- Who's still in.
			local chips = Kit.new("Frame", z({ BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 158), Size = UDim2.new(1, 0, 0, 22), Parent = frame }))
			local chipList = Kit.list(4, true)
			chipList.HorizontalAlignment = Enum.HorizontalAlignment.Center
			chipList.Parent = chips
			for _, seat in a.bidders do
				Kit.tag(nameOf(seat), HudKit.seatColor(seat), z({ Parent = chips }))
			end
			local inIt = me ~= nil and table.find(a.bidders, me) ~= nil
			local bar = buttonBar(frame, 86)
			bar:FindFirstChildOfClass("UIListLayout"):Destroy()
			Kit.new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -6, 0, 40), CellPadding = UDim2.fromOffset(8, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = bar })
			if not inIt or a.leader == me then
				Kit.label(if a.leader == me and inIt then "You're on top! Hold on..." elseif me == nil then "" else "You're out of this one.", z({ TextSize = 15, Font = Theme.FontBold, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1, Parent = bar }))
				return
			end
			local cash = view.players[me].cash
			for i, step in { 1, 10, 100 } do
				local amount = a.high + step
				popButton(bar, `+{step}\n{money(amount)}`, Theme.Good, function()
					sendMove({ kind = "bid", amount = amount })
				end, amount <= cash, i)
			end
			popButton(bar, "Pass", Theme.PanelLight, function()
				sendMove({ kind = "pass" })
			end, true, 4)
		end)
	end

	local function jailPopup()
		local view = snapshot.view
		local me = snapshot.yourSeat
		local p = view.players[me]
		openPopup("jail", Vector2.new(300, 270), function(frame)
			Kit.label("🔒 In Jail", z({ TextSize = 26, Font = Theme.FontTitle, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 32), Parent = frame }))
			local tries = (p.jailTries or 0) + 1
			Kit.label(`Try {tries} of 3: roll doubles to walk out free, or pay {money(Rules.JAIL_FEE)} and roll as normal. You still collect rent in Jail.`, z({ TextSize = 14, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 60), Parent = frame }))
			local bar = buttonBar(frame, 136)
			bar:FindFirstChildOfClass("UIListLayout"):Destroy()
			local list = Kit.list(6)
			list.Parent = bar
			popButton(bar, "🎲 Roll for doubles", nil, function()
				sendMove({ kind = "roll" })
			end, true, 1)
			popButton(bar, `Pay {money(Rules.JAIL_FEE)}`, Theme.PanelLight, function()
				sendMove({ kind = "payJail" })
			end, p.cash >= Rules.JAIL_FEE, 2)
			popButton(bar, if p.cards > 0 then "🎟 Use Get Out of Jail card" else "No Get Out of Jail card", Theme.PanelLight, function()
				sendMove({ kind = "useCard" })
			end, p.cards > 0, 3)
		end)
	end

	local function offerPopup()
		local view = snapshot.view
		local me = snapshot.yourSeat
		local t = view.trade
		local incoming = t.to == me
		openPopup(if incoming then "offerIn" else "offerOut", Vector2.new(440, 360), function(frame)
			local heading = if incoming then `{nameOf(t.from)} {if (t.counters or 0) > 0 then "counters" else "offers you a deal"}` else `Waiting for {nameOf(t.to)} to answer...`
			Kit.label(heading, z({ TextSize = 20, Font = Theme.FontTitle, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, 0, 0, 26), Parent = frame }))
			local body = Kit.new("Frame", z({ BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -30 - 70), Parent = frame }))
			if incoming then
				offerColumn(body, 0, "You get", t.give)
				offerColumn(body, 0.5, "You give", t.get)
			else
				offerColumn(body, 0, "You give", t.give)
				offerColumn(body, 0.5, "You get", t.get)
			end
			Kit.label(`Worth: {money(sideValue(if incoming then t.give else t.get))} for {money(sideValue(if incoming then t.get else t.give))}`, z({ TextSize = 12, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -46), Size = UDim2.new(1, 0, 0, 18), Parent = frame }))
			local bar = buttonBar(frame)
			if not incoming then
				Kit.label("They can accept, decline or counter.", z({ TextSize = 14, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center, Parent = bar }))
				return
			end
			popButton(bar, "Decline", Theme.Bad, function()
				sendMove({ kind = "reject" })
			end, true, 1)
			popButton(bar, "Counter", Theme.PanelLight, openCounter, (t.counters or 0) < Rules.COUNTERS_PER_TRADE, 2)
			popButton(bar, "Accept", Theme.Good, function()
				sendMove({ kind = "accept" })
			end, true, 3)
		end)
	end

	-- Big moments over the board: the dice roll and the card you drew --------------------------
	local fx = Kit.new("Frame", { Name = "Fx", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 60, Parent = overlay })

	local function showDice(a: number, b: number)
		if quiet then
			return
		end
		local center, size = stage()
		local dieSize = math.clamp(size.X * 0.16, 54, 86)
		local holder = Kit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(center.X, center.Y - size.Y * 0.12), Size = UDim2.fromOffset(dieSize * 2.5, dieSize), ZIndex = 61, Parent = fx })
		play("dice")
		local labels = {}
		for i, value in { a, b } do
			local die = Kit.new("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(if i == 1 then 0.2 else 0.8, 0, 0.5, 0),
				Size = UDim2.fromOffset(dieSize, dieSize),
				Rotation = if i == 1 then -160 else 160,
				ZIndex = 62,
				Parent = holder,
			}, { Kit.corner(math.floor(dieSize * 0.18)), Kit.new("UIStroke", { Thickness = 3, Color = Color3.fromRGB(40, 36, 50) }) })
			labels[i] = Kit.label(DIE_PIPS[math.random(1, 6)], { Font = Theme.FontBold, TextScaled = true, TextColor3 = TILE_TEXT, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 63, Parent = die })
			TweenService:Create(die, TweenInfo.new(DICE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = if i == 1 then -8 else 8 }):Play()
			Juice.popIn(die, 0.3)
			task.spawn(function()
				local start = os.clock()
				while os.clock() - start < DICE_TIME * 0.8 do
					labels[i].Text = DIE_PIPS[math.random(1, 6)]
					task.wait(0.06)
				end
				labels[i].Text = DIE_PIPS[value]
				Juice.bump(die, 0.2)
			end)
		end
		task.delay(DICE_TIME, function()
			if a == b and holder.Parent then
				Kit.label("DOUBLES!", { Font = Theme.FontTitle, TextSize = 26, TextColor3 = Theme.Accent, TextStrokeTransparency = 0.3, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 6), Size = UDim2.fromOffset(200, 30), ZIndex = 63, Parent = holder })
				play("callout")
			end
		end)
		task.delay(DICE_TIME + 0.9, function()
			if holder.Parent then
				Juice.popOut(holder, function()
					holder:Destroy()
				end)
			end
		end)
	end

	local function showCard(deckKey: string, index: number, seat: number)
		if quiet then
			return
		end
		local deck = Rules.decks[deckKey]
		local center, size = stage()
		local w = math.min(280, size.X - 30)
		local color = if deckKey == "lucky" then Color3.fromRGB(240, 150, 60) else Color3.fromRGB(70, 140, 210)
		local card = Kit.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = DEED_PAPER,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center.X, center.Y),
			Size = UDim2.fromOffset(0, 170),
			ZIndex = 61,
			Parent = fx,
		}, { Kit.corner(12), Kit.new("UIStroke", { Thickness = 4, Color = color }) })
		Kit.label(`{if deckKey == "lucky" then "?" else "✉"} {string.upper(deck.name)}`, { Font = Theme.FontTitle, TextSize = 20, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 24), ZIndex = 62, Parent = card })
		Kit.label(deck.cards[index].text, { TextSize = 16, Font = Theme.FontBold, TextColor3 = TILE_TEXT, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(12, 38), Size = UDim2.new(1, -24, 1, -66), ZIndex = 62, Parent = card })
		Kit.label(nameOf(seat), { TextSize = 13, TextColor3 = HudKit.shade(HudKit.seatColor(seat), 0.4), TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -6), Size = UDim2.new(1, 0, 0, 18), ZIndex = 62, Parent = card })
		-- Flips over: grows out of its edge.
		play("flip")
		TweenService:Create(card, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(w, 170) }):Play()
		local function gone()
			if card.Parent then
				Juice.popOut(card, function()
					card:Destroy()
				end)
			end
		end
		card.Activated:Connect(gone)
		task.delay(2.8, gone)
	end

	-- Countdown on the auction pop-up.
	local heartbeat = RunService.Heartbeat:Connect(function()
		if not (timerBar and snapshot and snapshot.turnEndsAt and snapshot.view.phase == "auction") then
			return
		end
		local total = snapshot.view.auctionSeconds or Rules.AUCTION_SECONDS
		local left = math.max(0, snapshot.turnEndsAt - workspace:GetServerTimeNow())
		local share = math.clamp(left / total, 0, 1)
		timerBar.Size = UDim2.fromScale(share, 1)
		timerBar.BackgroundColor3 = if left < 2 then Theme.Bad elseif left < 4 then Theme.Warn else Theme.Good
		if timerText then
			timerText.Text = if left < 1.5 then "Going twice..." elseif left < 3 then "Going once..." else `{math.ceil(left)} s`
		end
	end)

	-- Action panel -----------------------------------------------------------------------
	local endTurnButton: TextButton? = nil
	local function primary(text: string, onClick: () -> (), color: Color3?, enabled: boolean?): TextButton
		local on = enabled ~= false
		return Kit.button(text, function()
			if on then
				onClick()
			end
		end, {
			BackgroundColor3 = if not on then Theme.PanelLight elseif color then color else Theme.Accent,
			TextColor3 = if not on then Theme.SubText elseif color then textOn(color) else Theme.AccentText,
			AutoButtonColor = on,
			Font = Theme.FontTitle,
			TextSize = 22,
			Size = UDim2.fromScale(1, 1),
			Parent = primaryRow,
		})
	end
	local function secondary(text: string, onClick: () -> (), color: Color3?, order: number, enabled: boolean?)
		local on = enabled ~= false
		Kit.button(text, function()
			if on then
				onClick()
			end
		end, {
			BackgroundColor3 = if not on then Theme.Panel elseif color then color else Theme.PanelLight,
			BackgroundTransparency = if on then 0 else 0.4,
			TextColor3 = if not on then Theme.SubText elseif color then textOn(color) else Theme.Text,
			AutoButtonColor = on,
			TextSize = 14,
			Size = UDim2.new(0, 60, 1, 0),
			LayoutOrder = order,
			Parent = secondaryRow,
		})
	end

	local function ownsAny(view: any, me: number): boolean
		for _, seat in view.owner do
			if seat == me then
				return true
			end
		end
		return false
	end

	local function renderActions(view: any, me: number?)
		Kit.clear(primaryRow)
		Kit.clear(secondaryRow)
		endTurnButton = nil
		local active = snapshot.activeSeats[1]
		local myTurn = me ~= nil and view.turn == me
		HudKit.turnTint(actionPanel, if view.phase == "over" then nil else view.turn, myTurn and view.phase ~= "over")
		local myPlayer = if me then view.players[me] else nil
		primaryRow.Visible, secondaryRow.Visible = true, true
		if view.phase == "over" then
			actionText.Text = "Game over"
			return
		end
		if me and myPlayer and myPlayer.bankrupt then
			actionText.Text = "You're bankrupt. Stick around to see who wins!"
			return
		end
		if view.phase == "auction" then
			local a = view.auction
			actionText.Text = `Auction: {spaces[a.pos].name}\n{if a.leader then `{nameOf(a.leader)} lead{if a.leader == me then "" else "s"} with {money(a.high)}` else "No bids yet"}`
			return
		end
		if view.phase == "trade" then
			local t = view.trade
			actionText.Text = `{nameOf(t.from)} offer{if t.from == me then "" else "s"} {if t.to == me then "you" else nameOf(t.to)} a trade:\nGives {describeSide(t.give)}\nWants {describeSide(t.get)}`
			return
		end
		if not myTurn then
			local doing = if view.phase == "buy" then `is deciding on {spaces[view.players[active].pos].name}`
				elseif view.phase == "debt" then "is raising cash"
				else "is taking their turn"
			actionText.Text = `{nameOf(view.turn)} {doing}...`
			return
		end

		local canTrade = view.tradesLeft > 0 and (view.phase == "turn" or view.phase == "debt")
		local canManage = ownsAny(view, me :: number) and (view.phase == "turn" or view.phase == "buy" or view.phase == "debt")
		if view.phase == "buy" then
			local space = spaces[myPlayer.pos]
			actionText.Text = `You landed on {space.name}. Buy it for {money(space.price)}{if view.auctions then " or put it up for auction" else ""}.`
			primary("Show deed", function()
				userPopup = nil
				rerender()
			end, Theme.PanelLight)
		elseif view.phase == "debt" then
			local d = view.debt
			actionText.Text = `You owe {money(d.amount)} ({d.why}). Sell houses or mortgage deeds in Manage, then pay.`
			primary(`Pay {money(d.amount)}`, function()
				sendMove({ kind = "payDebt" })
			end, Theme.Good, myPlayer.cash >= d.amount)
			secondary(if bankruptConfirm then "Sure?" else "Bankrupt", function()
				if bankruptConfirm then
					bankruptConfirm = false
					sendMove({ kind = "bankrupt" })
				else
					bankruptConfirm = true
					rerender()
					task.delay(3, function()
						bankruptConfirm = false
						rerender()
					end)
				end
			end, Theme.Bad, 3)
		elseif view.canRoll then
			if myPlayer.inJail then
				actionText.Text = "You're in Jail. Roll doubles, pay, or use a card."
				primary("🔒 Jail options", function()
					userPopup = nil
					rerender()
				end)
			else
				actionText.Text = if view.dice and view.dice[1] == view.dice[2] then "Doubles! Roll again." else "Your turn! Roll the dice."
				primary("🎲 Roll", function()
					sendMove({ kind = "roll" })
				end)
			end
		else
			actionText.Text = "Build, trade, or end your turn."
			endTurnButton = primary("End turn", function()
				sendMove({ kind = "endTurn" })
			end)
		end
		secondary("Manage", function()
			userPopup = { kind = "manage" }
			rerender()
		end, nil, 1, canManage)
		secondary("Trade", function()
			openTrade(nil, nil)
		end, nil, 2, canTrade)
	end

	-- Players panel ------------------------------------------------------------------------
	local function renderPlayers(view: any, me: number?, fxAt: number)
		-- Money changes: count up or down, with a +$ / -$ pop-up. A single matching payment
		-- (rent) flies from the payer to the owner.
		local losers, gainers = {}, {}
		for seat, p in view.players do
			local row = rows[seat]
			if not row then
				row = makeRow(seat)
				rows[seat] = row
			end
			row.name.Text = nameOf(seat) .. (if p.inJail then "  🔒" else "") .. (if p.cards > 0 then `  🎟{if p.cards > 1 then p.cards else ""}` else "")
			local deeds = 0
			local chipKey = {}
			for pos = 1, #spaces do
				if view.owner[pos] == seat then
					deeds += 1
					table.insert(chipKey, `{pos}{if view.mortgaged[pos] then "m" else ""}`)
				end
			end
			row.sub.Text = if p.bankrupt then "Bankrupt" else `{deeds} deed{if deeds == 1 then "" else "s"} · worth {money(p.worth)}`
			row.frame.BackgroundTransparency = if p.bankrupt then 0.6 else 0
			local key = table.concat(chipKey, ",")
			if key ~= row.chipKey then
				row.chipKey = key
				Kit.clear(row.chips)
				for pos = 1, #spaces do
					if view.owner[pos] == seat then
						local chip = Kit.new("TextButton", {
							Text = "",
							AutoButtonColor = false,
							BackgroundColor3 = deedColor(pos),
							BackgroundTransparency = if view.mortgaged[pos] then 0.65 else 0,
							BorderSizePixel = 0,
							LayoutOrder = pos,
							Parent = row.chips,
						}, { Kit.corner(2) })
						chip.Activated:Connect(function()
							tapDeed(pos)
						end)
					end
				end
			end
			-- Whose turn: a glowing ring.
			row.stroke.Transparency = if view.turn == seat and view.phase ~= "over" then 0 else 1
			local before = shownCash[seat]
			if before == nil or quiet then
				shownCash[seat] = p.cash
				row.cash.Text = money(p.cash)
			elseif before ~= p.cash then
				shownCash[seat] = p.cash
				local delta = p.cash - before
				if delta < 0 then
					table.insert(losers, { seat = seat, delta = delta })
				else
					table.insert(gainers, { seat = seat, delta = delta })
				end
				at(fxAt, function()
					Juice.countUp(row.cash, before, p.cash, money, 0.6)
					local pos = row.cash.AbsolutePosition + row.cash.AbsoluteSize / 2
					Flair.floatText(row.cash, if delta > 0 then `+{money(delta)}` else `-{money(-delta)}`, pos, if delta > 0 then Color3.fromRGB(140, 240, 150) else Color3.fromRGB(255, 120, 120))
				end)
			end
		end
		if #losers == 1 and #gainers == 1 and losers[1].delta == -gainers[1].delta and not quiet then
			local payer, payee = rows[losers[1].seat], rows[gainers[1].seat]
			at(fxAt, function()
				if payer.frame.AbsoluteSize.X > 0 then
					Flair.flyTo(payee.cash, {
						count = math.clamp(math.ceil(gainers[1].delta / 50), 2, 8),
						from = payer.cash.AbsolutePosition + payer.cash.AbsoluteSize / 2,
						make = function()
							return Kit.label("💵", { TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(28, 28) })
						end,
					})
				end
			end)
		end
	end

	-- Rendering ------------------------------------------------------------------------------
	local lastLogN = 0
	local lastCardN = 0
	local firstRender = true

	-- Which pop-up to show: a choice the game is waiting on comes first, then whatever you
	-- opened yourself.
	local function renderPopup(view: any, me: number?)
		if quiet or view.phase == "over" or (me and view.players[me].bankrupt and view.phase ~= "auction") then
			closePopup()
			return
		end
		local myTurn = me ~= nil and view.turn == me
		-- What you opened yourself is dropped once it no longer makes sense.
		if userPopup then
			local kind = userPopup.kind
			if (kind == "trade" or kind == "manage") and not (myTurn and (view.phase == "turn" or view.phase == "debt" or (kind == "manage" and view.phase == "buy"))) then
				if not (kind == "trade" and tradeDraft.counter and view.phase == "trade" and view.trade.to == me) then
					userPopup = nil
				end
			end
			if kind == "trade" and not tradeDraft.counter and view.tradesLeft <= 0 then
				userPopup = nil
			end
		end
		local settling = os.clock() < busyUntil
		if settling then
			task.delay(busyUntil - os.clock() + 0.05, rerender)
		end
		if view.phase == "auction" then
			auctionPopup()
		elseif view.phase == "trade" and (view.trade.to == me or view.trade.from == me) then
			if userPopup and userPopup.kind == "trade" and tradeDraft.counter and view.trade.to == me then
				openPopup("trade", Vector2.new(640, 500), buildTrade)
			else
				offerPopup()
			end
		elseif userPopup and userPopup.kind == "trade" then
			openPopup("trade", Vector2.new(640, 500), buildTrade)
		elseif userPopup and userPopup.kind == "manage" then
			openPopup("manage", Vector2.new(620, 520), buildManage)
		elseif view.phase == "buy" and myTurn and not settling then
			-- Your own landing comes before a deed card you had open.
			if userPopup and userPopup.kind == "deed" then
				userPopup = nil
			end
			deedPopup(view.players[view.turn].pos, true)
		elseif userPopup and userPopup.kind == "deed" then
			deedPopup(userPopup.pos :: number, false)
		elseif view.phase == "buy" and not settling then
			deedPopup(view.players[view.turn].pos, true)
		elseif myTurn and view.phase == "turn" and view.canRoll and view.players[me].inJail and not settling then
			jailPopup()
		else
			closePopup()
		end
	end

	function tapDeed(pos: number)
		if not snapshot then
			return
		end
		if userPopup and userPopup.kind == "trade" then
			if toggleTradeDeed(pos) then
				return
			end
		end
		if userPopup and userPopup.kind == "deed" and userPopup.pos == pos then
			userPopup = nil
		else
			userPopup = { kind = "deed", pos = pos }
		end
		play("click")
		rerender()
	end

	local function render()
		local view = snapshot.view
		local me = snapshot.yourSeat
		attachOverlay()

		roundLabel.Text = `Round {math.min(view.round, view.maxRounds)} of {view.maxRounds}{if view.fast then " · Fast mode" else ""} · richest wins at the end`
		potLabel.Visible = view.jackpot == true
		potLabel.Text = `Rest Stop jackpot: {money(view.pot or 0)}`

		-- Tiles: owner outline, houses, mortgages, selection.
		local selected = if userPopup and userPopup.kind == "deed" then userPopup.pos else nil
		local inTrade = userPopup and userPopup.kind == "trade"
		for pos, t in tiles do
			local owner = view.owner[pos]
			if owner ~= 0 and owner ~= nil then
				t.stroke.Color = HudKit.seatColor(owner)
				t.stroke.Thickness = 3
			else
				t.stroke.Color = Color3.fromRGB(150, 150, 140)
				t.stroke.Thickness = 1
			end
			local picked = inTrade and (tradeDraft.give[pos] or tradeDraft.get[pos])
			t.frame.BackgroundColor3 = if picked then Theme.Accent
				elseif view.mortgaged[pos] then Color3.fromRGB(190, 186, 176)
				elseif pos == selected then Color3.fromRGB(255, 245, 200)
				else TILE_COLOR
			local h = view.houses[pos]
			t.houses.Text = if view.mortgaged[pos] then "MORTGAGED" elseif h == 5 then "HOTEL" elseif h > 0 then string.rep("■", h) else ""
		end

		-- New events since last time: a roll tumbles, then tokens walk, then the money moves.
		local now = os.clock()
		local start = math.max(now, busyUntil)
		local rolled = false
		for _, entry in view.log do
			if entry.n > lastLogN then
				if not firstRender and string.find(entry.text, "^rolled ") then
					rolled = true
				end
			end
		end
		if #view.log > 0 then
			lastLogN = view.log[#view.log].n
		end
		local d = view.dice
		for i = 1, 2 do
			dice[i].Text = if d then DIE_PIPS[d[i]] else "-"
		end
		local walkAt = start
		if rolled and d then
			at(start, function()
				showDice(d[1], d[2])
			end)
			walkAt = start + (if quiet then 0 else DICE_TIME + 0.15)
		end
		local walk = 0
		for seat, p in view.players do
			walk = math.max(walk, moveToken(seat, p, walkAt))
		end
		local settled = walkAt + walk
		-- A card drawn on landing flips over once the token is there.
		local card = view.lastCard
		if card then
			local deck = Rules.decks[card.deck]
			cardBox.Visible = true
			cardText.Text = `{deck.name} ({nameOf(card.seat)}): {deck.cards[card.index].text}`
			if card.n ~= lastCardN then
				local fresh = lastCardN ~= 0 or not firstRender
				lastCardN = card.n
				if fresh then
					at(settled, function()
						showCard(card.deck, card.index, card.seat)
					end)
					settled += 1.2
				end
			end
		else
			cardBox.Visible = false
		end
		if not quiet and (rolled or walk > 0) then
			busyUntil = math.max(busyUntil, settled)
		end

		-- News feed.
		Kit.clear(logFrame)
		for i, entry in view.log do
			local who = if entry.seat then nameOf(entry.seat) .. " " else ""
			local text = entry.text
			if entry.seat ~= nil and entry.seat == me then
				text = string.gsub(text, "^owes ", "owe ") -- "You owe", not "You owes"
			end
			local line = Kit.label(`{who}{text}`, {
				TextScaled = true,
				-- Seat colors darkened a lot so they read on the pale board.
				TextColor3 = if entry.seat then HudKit.seatColor(entry.seat):Lerp(Color3.new(0, 0, 0), 0.65) else TILE_TEXT,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 1 / 8, -2),
				LayoutOrder = i,
				Parent = logFrame,
			})
			Kit.new("UITextSizeConstraint", { MaxTextSize = 15, Parent = line })
		end

		renderPlayers(view, me, if rolled or walk > 0 then settled else now)
		renderActions(view, me)
		renderPopup(view, me)
		if endTurnButton and not quiet then
			Flair.nudge(endTurnButton, 5)
		end
		firstRender = false
	end
	rerender = function()
		if snapshot and alive then
			render()
		end
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			render()
		end,
		-- Table view docks just the side panel: pop-ups move over the table.
		setDocked = function(value: boolean)
			docked = value
			placePopup()
		end,
		-- A space tapped on the 3D board (Table view).
		tapTable = function(id: any)
			if type(id) == "number" and Rules.isDeed(id) then
				tapDeed(id)
			end
		end,
		destroy = function()
			alive = false
			heartbeat:Disconnect()
			for _, t in tokens do
				if t.walk then
					task.cancel(t.walk)
				end
			end
			overlay:Destroy()
			root:Destroy()
		end,
	}
end

return Estates
