-- The card-game touches first made for Color Clash, for every card game. All local to
-- this player (nothing is sent to the server):
--   * CardFx.pop: a big mark bursting up off the middle of the table toward you when
--     something big happens (SNAP!, a burn, a knock); a callout on screen without Table view
--   * CardFx.dealTo: card backs flying off the draw pile (or the middle) to a seat
--   * CardFx.arrivals: cards landing in your hand fly in from where they came from (the
--     draw pile, the middle, another player) and flip face up as they slot in
--   * CardFx.drawnPrompt: the card you just drew held up in the middle with two choices
-- The 3D ones need Table3D.Focus (Table view on).

local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayingCards = require(ReplicatedStorage.Shared.Cards.PlayingCards)
local Focus = require(script.Parent.Parent.Table3D.Focus)
local Kit = require(script.Parent.Kit)
local HudKit = require(script.Parent.HudKit)
local PlayingCard = require(script.Parent.PlayingCard)
local Theme = Kit.Theme

local CardFx = {}

local CARD_BACK = Color3.fromRGB(54, 44, 90)
local CARD_EDGE = Color3.fromRGB(245, 242, 232)

local function localPart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

-- Where these local parts live: a folder of their own, so they're easy to find and clear.
local function fxFolder(): Folder
	local folder = workspace:FindFirstChild("CardFx")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "CardFx"
		folder.Parent = workspace
	end
	return folder :: Folder
end

-- A big symbol bursting up off the middle of the table, turned toward you, then fading
-- away. Without Table view it's a callout in the middle of `fallback` (if given).
local popNow: (text: string, color: Color3, fallback: Instance?) -> ()
local nextPop = 0 -- os.clock() when the next pop may start, so two in a row don't overlap
function CardFx.pop(text: string, color: Color3, fallback: Instance?)
	local now = os.clock()
	local wait = math.max(0, nextPop - now)
	nextPop = now + wait + 0.7
	if wait > 0 then
		task.delay(wait, popNow, text, color, fallback)
	else
		popNow(text, color, fallback)
	end
end

function popNow(text: string, color: Color3, fallback: Instance?)
	local focus = Focus.get()
	if not focus then
		if fallback then
			HudKit.callout(fallback, text, color)
		end
		return
	end
	local base = focus.middle + Vector3.new(0, 0.2, 0)
	local anchor = localPart({ Name = "PopAnchor", Transparency = 1, Size = Vector3.one * 0.1, Position = base, Parent = fxFolder() })
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromScale(0.3, 0.3)
	board.LightInfluence = 0
	board.AlwaysOnTop = false
	board.Parent = anchor
	-- Long words get a wider board, so they read as big as a single symbol.
	local wide = math.clamp(#text / 3, 1, 3.2)
	-- A dark copy just behind and below, so the mark reads as a thick 3D shape.
	local function mark(name: string, tint: Color3, offset: number, z: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = tint
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.new(0.5, 0, 0.5 + offset, 0)
		label.Size = UDim2.fromScale(1, 1)
		label.ZIndex = z
		label.Parent = board
		return label
	end
	local depth = mark("Depth", color:Lerp(Color3.new(0, 0, 0), 0.45), 0.06, 1)
	local face = mark("Face", color, 0, 2)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 3
	stroke.Parent = face

	local up = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local height = if wide > 1 then 3.2 / wide * 1.4 else 3.2
	TweenService:Create(board, up, { Size = UDim2.fromScale(3.2 * math.min(wide, 2.2), math.max(height, 1.3)) }):Play()
	TweenService:Create(anchor, up, { Position = base + Vector3.new(0, 1.8, 0) + focus.toYou * 0.5 }):Play()
	task.delay(1.0, function()
		if not anchor.Parent then
			return
		end
		local out = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(board, out, { Size = UDim2.fromScale(0.6, 0.6) }):Play()
		TweenService:Create(face, out, { TextTransparency = 1 }):Play()
		TweenService:Create(depth, out, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, out, { Transparency = 1 }):Play()
		task.delay(0.32, function()
			anchor:Destroy()
		end)
	end)
end

-- The draw pile on the table: the pile the board marked DrawPile, else the first "Pile".
function CardFx.pile(): BasePart?
	local focus = Focus.get()
	local board = focus and focus.board
	if not board then
		return nil
	end
	local any: BasePart? = nil
	for _, d in board:GetDescendants() do
		if d.Name == "Pile" and d:IsA("BasePart") then
			if d:GetAttribute("DrawPile") == true then
				return d
			end
			any = any or d
		end
	end
	return any
end

-- A world point on screen, in the pixels of a ScreenGui that ignores the top-bar inset.
function CardFx.worldOnScreen(point: Vector3): Vector2?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local screen, visible = camera:WorldToViewportPoint(point)
	if not visible then
		return nil
	end
	return Vector2.new(screen.X, screen.Y)
end

function CardFx.pileOnScreen(): Vector2?
	local pile = CardFx.pile()
	if not pile then
		return nil
	end
	return CardFx.worldOnScreen(pile.Position + Vector3.new(0, pile.Size.Y / 2, 0))
end

-- The middle of the table, a little over the cloth (nil without Table view).
function CardFx.middlePoint(): Vector3?
	local focus = Focus.get()
	return if focus then focus.middle + Vector3.new(0, 0.1, 0) else nil
end

function CardFx.middleOnScreen(): Vector2?
	local focus = Focus.get()
	return if focus then CardFx.worldOnScreen(focus.middle + Vector3.new(0, 0.1, 0)) else nil
end

-- The table seat a match seat sits in (nil without a 3D table).
function CardFx.tableSeat(snapshot: any, seat: number?): number?
	local seats = seat and snapshot and snapshot.table and snapshot.table.seats
	return seats and seats[seat] or nil
end

-- A point on the table in front of a match seat: `share` of the way from the middle to the
-- seat (1 = the seat itself), a little over the tabletop.
function CardFx.seatPoint(snapshot: any, seat: number?, share: number?): Vector3?
	local focus = Focus.get()
	local tableSeat = CardFx.tableSeat(snapshot, seat)
	local part = focus and tableSeat and focus.seatOf(tableSeat)
	if not focus or not part then
		return nil
	end
	local flat = (part.Position - focus.middle) * Vector3.new(1, 0, 1)
	return focus.middle + flat * (share or 0.78) + Vector3.new(0, 0.9, 0)
end

function CardFx.seatOnScreen(snapshot: any, seat: number?): Vector2?
	local point = CardFx.seatPoint(snapshot, seat, 0.78)
	return if point then CardFx.worldOnScreen(point) else nil
end

-- `count` card backs flying, one after another, to a match seat: off the draw pile, or
-- from `from` (a world point; the middle of the table by default when there's no pile).
function CardFx.dealTo(snapshot: any, seat: number?, count: number, from: Vector3?)
	local focus = Focus.get()
	local to = CardFx.seatPoint(snapshot, seat, 0.78)
	if not focus or not to or count <= 0 then
		return
	end
	if not from then
		local pile = CardFx.pile()
		from = if pile then pile.Position + Vector3.new(0, pile.Size.Y / 2 + 0.05, 0) else focus.middle + Vector3.new(0, 0.1, 0)
	end
	local start = from :: Vector3
	local folder = fxFolder()
	local flat = (to - start) * Vector3.new(1, 0, 1)
	if flat.Magnitude < 1e-3 then
		return
	end
	local yaw = math.atan2(flat.X, flat.Z)
	for i = 1, math.min(count, 8) do
		task.delay((i - 1) * 0.14, function()
			local card = localPart({
				Name = "FlyingCard",
				Color = CARD_EDGE,
				Size = Vector3.new(0.9, 0.03, 1.26),
				CFrame = CFrame.new(start) * CFrame.Angles(0, yaw, 0),
				Parent = folder,
			})
			local back = localPart({ Name = "Back", Color = CARD_BACK, Size = Vector3.new(0.78, 0.01, 1.12), CFrame = card.CFrame * CFrame.new(0, 0.02, 0), Parent = card })
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = card, back
			weld.Parent = card
			back.Anchored = false
			local mid = start:Lerp(to, 0.5) + Vector3.new(0, 1.1, 0)
			local look = CFrame.lookAt(to, to + flat.Unit)
			local first = TweenService:Create(card, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(mid) * CFrame.Angles(0, yaw, math.rad(30)) })
			local second = TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = look * CFrame.Angles(math.rad(-70), 0, 0) })
			first.Completed:Once(function()
				second:Play()
			end)
			second.Completed:Once(function()
				card:Destroy()
			end)
			first:Play()
		end)
	end
end

-- A see-through frame over the whole screen for things that fly across it (Table view
-- docks only the bottom of a game's board, so its own frames would clip them).
local function overlayFor(anchor: Instance): Frame?
	local screen = anchor:FindFirstAncestorWhichIsA("ScreenGui")
	if not screen or Kit.inPreview(anchor) then
		return nil
	end
	local overlay = screen:FindFirstChild("CardFxOverlay")
	if not overlay then
		overlay = Kit.new("Frame", {
			Name = "CardFxOverlay",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 60,
			Parent = screen,
		})
	end
	return overlay :: Frame
end

-- A point from CardFx.*OnScreen (which ignores the top-bar inset) in `overlay`'s pixels.
local function screenToOverlay(overlay: Frame, point: Vector2): Vector2
	local screen = overlay:FindFirstAncestorWhichIsA("ScreenGui")
	if screen and not screen.IgnoreGuiInset then
		point -= GuiService:GetGuiInset()
	end
	return point - overlay.AbsolutePosition
end

-- Where a GUI object's middle is, in the same pixels as CardFx.*OnScreen (nil when it, or
-- anything it's in, is hidden: Table view hides the felt).
function CardFx.guiOnScreen(object: GuiObject?): Vector2?
	if not object or object.AbsoluteSize.X <= 0 or not object.Parent then
		return nil
	end
	local at: Instance? = object
	while at and not at:IsA("ScreenGui") do
		if at:IsA("GuiObject") and not at.Visible then
			return nil
		end
		at = at.Parent
	end
	if not at then
		return nil
	end
	local point = object.AbsolutePosition + object.AbsoluteSize / 2
	local screen = object:FindFirstAncestorWhichIsA("ScreenGui")
	if screen and not screen.IgnoreGuiInset then
		point += GuiService:GetGuiInset()
	end
	return point
end

-- One card flying from `from` (screen pixels) onto `target` face down, flipping face up
-- as it slots in. `target` hides until it lands.
-- Returns how long until it lands (0 if it can't fly).
local FLIGHT = 0.32 + 0.14
function CardFx.flyIn(id: number?, target: GuiObject, wait: number, from: Vector2): number
	local overlay = overlayFor(target)
	if not overlay then
		return 0
	end
	target.Visible = false
	task.delay(wait, function()
		if not target.Parent then
			return
		end
		local size = target.AbsoluteSize
		local start = screenToOverlay(overlay, from)
		local flyer = Kit.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(start.X, start.Y),
			Size = UDim2.fromOffset(size.X * 0.45, size.Y * 0.45),
			Rotation = -25,
			ZIndex = 60,
			Parent = overlay,
		})
		PlayingCard.face(nil).Parent = flyer
		local to = target.AbsolutePosition + size / 2 - overlay.AbsolutePosition
		local travel = TweenService:Create(flyer, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(to.X, to.Y),
			Size = UDim2.fromOffset(size.X, size.Y),
			Rotation = target.Rotation,
		})
		local function land()
			flyer:Destroy()
			if target.Parent then
				target.Visible = true
			end
		end
		travel.Completed:Once(function()
			if id == nil then
				land()
				return
			end
			-- Flip face up as it slots in.
			local shut = TweenService:Create(flyer, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.fromOffset(0, size.Y) })
			shut.Completed:Once(function()
				Kit.clear(flyer)
				PlayingCard.face(id).Parent = flyer
				local open = TweenService:Create(flyer, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(size.X, size.Y) })
				open.Completed:Once(land)
				open:Play()
			end)
			shut:Play()
		end)
		travel:Play()
	end)
	return wait + FLIGHT
end

-- Remembers which cards are in your hand, so the ones that just arrived can fly in.
-- update(faces, from): faces is what PlayingCard.renderHand returned; `from` is where new
-- cards come from on screen (CardFx.pileOnScreen(), CardFx.seatOnScreen(...), a felt slot
-- via CardFx.guiOnScreen) or nil to just let them appear. The first look never flies, and
-- a whole new hand (a deal) deals in quickly, card by card.
export type Arrivals = {
	update: (faces: { [any]: GuiObject }, from: Vector2?) -> { any },
	reset: () -> (),
}
function CardFx.arrivals(): Arrivals
	local known: { [any]: boolean }? = nil
	local landing: { [any]: number } = {} -- key -> os.clock() when its flight lands
	local self = {}
	function self.update(faces: { [any]: GuiObject }, from: Vector2?): { any }
		-- A redraw mid-flight makes new faces: keep those hidden until their card lands.
		local now = os.clock()
		for key, at in landing do
			local face = faces[key]
			if at <= now then
				landing[key] = nil
			elseif face then
				face.Visible = false
				task.delay(at - now, function()
					if face.Parent then
						face.Visible = true
					end
				end)
			end
		end
		local before = known
		known = {}
		local fresh = {}
		for key in faces do
			(known :: any)[key] = true
			if before and not before[key] then
				table.insert(fresh, key)
			end
		end
		if not before or #fresh == 0 then
			return fresh
		end
		-- Left to right, the way they sit in the hand.
		table.sort(fresh, function(a, b)
			return faces[a].Parent and faces[b].Parent and (faces[a].Parent :: any).LayoutOrder < (faces[b].Parent :: any).LayoutOrder or false
		end)
		if not from then
			return fresh
		end
		local step = if #fresh > 4 then 0.06 else 0.14
		for i, key in fresh do
			if i > 16 then
				break
			end
			local id = if type(key) == "number" then key else nil
			local lands = CardFx.flyIn(id, faces[key], (i - 1) * step, from)
			if lands > 0 then
				landing[key] = now + lands
			end
		end
		return fresh
	end
	function self.reset()
		known = nil
		table.clear(landing)
	end
	return self :: any
end

-- The card you just drew, held up in the middle of the screen with two buttons, like
-- Color Clash's Play / Keep. Returns show(id or nil, buttons) — nil hides it. Lives on the
-- whole screen (made on first show), so Table view's dock doesn't clip it.
export type DrawnButton = { text: string, color: Color3?, onClick: () -> () }
function CardFx.drawnPrompt(anchor: Instance): (id: number?, buttons: { DrawnButton }?) -> ()
	local band: Frame? = nil
	local slot: Frame? = nil
	local scale: UIScale? = nil
	local shown: number? = nil
	local row: Frame? = nil
	local pop = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local function build(): boolean
		if band and band.Parent then
			return true
		end
		local screen = anchor:FindFirstAncestorWhichIsA("ScreenGui")
		if not screen or Kit.inPreview(anchor) then
			return false
		end
		band = Kit.new("Frame", {
			Name = "DrawnCard",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.42),
			Size = UDim2.fromScale(0.5, 0.36),
			ZIndex = 55,
			Visible = false,
			Parent = screen,
		})
		Kit.new("UISizeConstraint", { MaxSize = Vector2.new(560, 320), Parent = band })
		slot = Kit.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromScale(1, 0.78),
			ZIndex = 56,
			Parent = band,
		}, { Kit.new("UIAspectRatioConstraint", { AspectRatio = PlayingCard.RATIO }) })
		scale = Kit.new("UIScale", { Scale = 1, Parent = slot })
		row = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 0, 0.8, 0),
			Size = UDim2.new(1, 0, 0.2, 0),
			ZIndex = 56,
			Parent = band,
		})
		local list = Kit.list(10, true)
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.Parent = row
		anchor.Destroying:Once(function()
			if band then
				band:Destroy()
			end
		end)
		return true
	end
	return function(id: number?, buttons: { DrawnButton }?)
		if id == shown then
			return
		end
		shown = id
		if id == nil then
			if band then
				band.Visible = false
			end
			return
		end
		if not build() then
			return
		end
		local b, s, sc, r = band :: Frame, slot :: Frame, scale :: UIScale, row :: Frame
		Kit.clear(s)
		Kit.new("UIAspectRatioConstraint", { AspectRatio = PlayingCard.RATIO, Parent = s })
		local face = PlayingCard.face(id)
		face.ZIndex = 56
		Kit.new("UIStroke", { Color = Theme.Accent, Thickness = 5, Parent = face })
		face.Parent = s
		Kit.clear(r)
		for i, info in buttons or {} do
			local button = Kit.button(info.text, function()
				info.onClick()
			end, {
				Size = UDim2.new(0, math.max(130, #info.text * 9 + 30), 1, 0),
				BackgroundColor3 = info.color or Theme.Accent,
				TextColor3 = if info.color then Theme.Text else Theme.AccentText,
				LayoutOrder = i,
				ZIndex = 57,
				Parent = r,
			})
			HudKit.pill(button)
		end
		b.Visible = true
		sc.Scale = 0.3
		s.Rotation = -12
		TweenService:Create(sc, pop, { Scale = 1 }):Play()
		TweenService:Create(s, pop, { Rotation = 0 }):Play()
	end
end

-- A key for a game's lastAction (or any small table), so effects fire once per action.
function CardFx.key(action: any, extra: any?): string?
	if type(action) ~= "table" then
		return nil
	end
	local parts = { tostring(extra) }
	for _, k in { "kind", "seat", "card", "count", "from", "to", "target", "pile", "ok", "burned", "rank", "got", "out" } do
		table.insert(parts, tostring(action[k]))
	end
	for _, id in action.cards or {} do
		table.insert(parts, tostring(id))
	end
	return table.concat(parts, "|")
end

-- changed(key): true when `key` differs from the last one seen, but never on the first
-- look (joining mid-game shouldn't replay the last move) and never for nil.
function CardFx.watch(): (key: string?) -> boolean
	local first = true
	local last: string? = nil
	return function(key: string?): boolean
		local was = last
		last = key
		if first then
			first = false
			return false
		end
		return key ~= nil and key ~= was
	end
end

-- Games where you draw from a stock or take the discard, then throw one away (Gin Rummy,
-- Thirty-One). Returns after(snapshot, faces, piles, discarding, canThrow), to call after
-- each hand redraw:
--   * your new cards fly in from the stock or the discard pile and flip face up
--   * other players' draws fly off the pile to their seat
--   * a card you draw from the stock is held up with "Throw it away" / "Keep it" (the
--     Color Clash Play / Keep), when the rules let you throw it straight back
-- piles: the 2D stock and discard slots on the felt (used when Table view is off).
export type StockPiles = { stock: GuiObject?, discard: GuiObject? }
function CardFx.stockAndDiscard(root: Instance, throw: (id: number) -> ())
	local arrivals = CardFx.arrivals()
	local showDrawn = CardFx.drawnPrompt(root)
	local changed = CardFx.watch()
	local drawnId: number? = nil
	local drewBy: number? = nil
	return function(snapshot: any, faces: { [any]: GuiObject }, piles: StockPiles, discarding: boolean, canThrow: (number) -> boolean)
		local view = snapshot.view
		local me = snapshot.yourSeat
		local a = view.lastAction
		local mine = a and a.seat == me and a.kind == "draw"
		local fromDiscard = mine and a.from == "discard"
		local from = if fromDiscard then (CardFx.middleOnScreen() or CardFx.guiOnScreen(piles.discard)) else (CardFx.pileOnScreen() or CardFx.guiOnScreen(piles.stock))
		local fresh = arrivals.update(faces, from)
		if discarding and mine and a.from == "stock" and #fresh == 1 then
			drawnId = fresh[1]
		end
		if drawnId and (not discarding or not table.find(view.hand or {}, drawnId) or not canThrow(drawnId)) then
			drawnId = nil
		end
		local id = drawnId
		showDrawn(id, if id
			then {
				{ text = "Throw it away", onClick = function()
					drawnId = nil
					showDrawn(nil)
					throw(id)
				end },
				{ text = "Keep it", color = Color3.fromRGB(70, 110, 200), onClick = function()
					drawnId = nil
					showDrawn(nil)
				end },
			}
			else nil)

		-- Other players' draws: card backs to their seat (off the pile, or from the middle
		-- when they took the discard). A bot can draw and discard between two looks, so a
		-- discard with no draw seen first counts as a draw too.
		if changed(CardFx.key(a, view.round)) and a and a.seat ~= me then
			local middle = CardFx.middlePoint()
			if a.kind == "draw" then
				drewBy = a.seat
				CardFx.dealTo(snapshot, a.seat, 1, if a.from == "discard" then middle else nil)
			elseif a.kind == "discard" then
				if drewBy ~= a.seat then
					CardFx.dealTo(snapshot, a.seat, 1, if a.from == "discard" then middle else nil)
				end
				drewBy = nil
			end
		end
	end
end

-- Off your turn, show every card dimmed and lift the ones that would fit when it comes
-- back to you (Color Clash's rule, so you can plan ahead). `fits(id)` says which.
function CardFx.offTurn(cards: { any }, fits: (number) -> boolean)
	for _, card in cards do
		card.dim = true
		card.glow = false
		card.raised = card.id ~= nil and fits(card.id)
	end
end

-- Trick games (Hearts, Spades, Oh Hell), off your turn while a trick is on: every card
-- dimmed, and the ones that would follow the suit led (or any, if you have none of it)
-- lifted, like Color Clash's would-fit cards.
function CardFx.followSuit(cards: { any }, hand: { number }, trick: { any }?)
	local lead = trick and trick[1] and PlayingCards.suit(trick[1].card)
	local has = false
	for _, id in hand do
		if lead and PlayingCards.suit(id) == lead then
			has = true
		end
	end
	CardFx.offTurn(cards, function(id: number): boolean
		return lead ~= nil and (not has or PlayingCards.suit(id) == lead)
	end)
end

-- Trick games: a new deal (or cards passed to you) flies into your hand, and a trick won
-- with a trump pops TRUMP! off the table. Returns after(snapshot, faces, from, trump) for
-- each hand redraw (`from`: where new cards come from on screen; the middle of the table
-- by default), which returns the trick just won the first time it's seen (else nil).
function CardFx.tricks(felt: GuiObject)
	local arrivals = CardFx.arrivals()
	local changed = CardFx.watch()
	return function(snapshot: any, faces: { [any]: GuiObject }, from: Vector2?, trump: number?): any
		local view = snapshot.view
		arrivals.update(faces, from or CardFx.middleOnScreen() or CardFx.guiOnScreen(felt))
		local last = view.lastTrick
		local key: string? = nil
		if last and last.plays then
			local parts = { tostring(view.round), tostring(last.winner) }
			for _, play in last.plays do
				table.insert(parts, `{play.seat}:{play.card}`)
			end
			key = table.concat(parts, ",")
		end
		if not changed(key) or not last then
			return nil
		end
		local lead = last.plays[1] and PlayingCards.suit(last.plays[1].card)
		if trump and lead ~= trump then
			for _, play in last.plays do
				if play.seat == last.winner and PlayingCards.suit(play.card) == trump then
					CardFx.pop(`{PlayingCards.suitSymbols[trump]} TRUMP!`, if PlayingCards.isRed(play.card) then Color3.fromRGB(240, 90, 100) else Color3.fromRGB(150, 160, 255))
				end
			end
		end
		return last
	end
end

return CardFx
