-- Hexlands table: the hex island on the left (land hexes, number tokens, harbors, roads,
-- camps, towns and the Bandit). On the right: what you can do right now (roll, build,
-- trade, play action cards, discard, answer a trade), your cards, and the scoreboard.
--
-- Highlights come from view.options (the rules work out legal spots), so taps match what
-- the server will accept. The server still checks everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Rules = require(ReplicatedStorage.Shared.Games.Hexlands)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local Kit = require(script.Parent.Parent.UI.Kit)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local Flair = require(script.Parent.Parent.UI.Flair)
local Juice = require(script.Parent.Parent.UI.Juice)
local TablePrompt = require(script.Parent.Parent.UI.TablePrompt)
local Theme = Kit.Theme

local Hexlands = {}

local RES = Rules.RES
local info = Rules.resourceInfo
local SQRT3 = math.sqrt(3)
local EXTENT = 5.6 -- board units from the center to the frame edge (harbors sit outside the land)
local UNIT = 1 / (2 * EXTENT) -- one hex radius as a fraction of the board
local SEA = Color3.fromRGB(70, 150, 200)
local HIGHLIGHT = Color3.fromRGB(255, 255, 255)
local TOKEN = Color3.fromRGB(250, 240, 210)
local DARK = Color3.fromRGB(40, 36, 50)

local function at(x: number, y: number): UDim2
	return UDim2.fromScale((x + EXTENT) * UNIT, (y + EXTENT) * UNIT)
end

local function landColor(land: string): Color3
	return if land == "dunes" then Rules.DUNES.color else info[land].color
end

local function landIcon(land: string): string
	return if land == "dunes" then Rules.DUNES.icon else info[land].icon
end

local function cardsText(cards: { [string]: number }): string
	local parts = {}
	for _, r in RES do
		local n = cards[r] or 0
		if n > 0 then
			table.insert(parts, `{n} {info[r].icon}`)
		end
	end
	return if #parts > 0 then table.concat(parts, "  ") else "nothing"
end

local function costText(cost: { [string]: number }): string
	local parts = {}
	for _, r in RES do
		for _ = 1, cost[r] or 0 do
			table.insert(parts, info[r].icon)
		end
	end
	return table.concat(parts, "")
end

local function circle(props: { [string]: any }): Frame
	local frame = Kit.new(props.ClassName or "Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0,
	}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), Kit.new("UIAspectRatioConstraint", { AspectRatio = 1 }) })
	for k, v in props do
		if k ~= "ClassName" then
			(frame :: any)[k] = v
		end
	end
	return frame
end

function Hexlands.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local mode: string? = nil -- "road" | "camp" | "town" while choosing where to build
	local banditHex: number? = nil -- picked a hex that has several people to rob
	local picker: any = nil -- { card = "harvest" | "hoard", picks = { res } }
	local discard: { [string]: number } = {}
	-- to = 0 offers it to everyone (the default, like the online versions).
	local offer = { to = 0 :: number, give = {} :: { [string]: number }, get = {} :: { [string]: number } }
	local counter: any = nil -- { id, give, get } from your side while writing a counter-offer
	local lastGainKey = ""
	local bankGive: string? = nil
	local lastDice = ""

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
	local rerender: () -> () = function() end
	-- Table view without the map or side panel: build on the table's glowing spots; your
	-- cards are chips over a build bar, trades and the Bandit pop up (UI/TablePrompt).
	-- Bank trades, offers, discards and action cards open the side panel in a window.
	local tableMode = false
	local prompt = TablePrompt.new(container)
	prompt.setVisible(false)
	local renderTable: (view: any, me: number?) -> ()
	local renderTrade: (view: any, me: number?) -> ()

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

	-- Seats with a camp or town on hex h and at least one card (the Bandit can rob them).
	local function victimsAt(view: any, me: number?, h: number): { number }
		local victims = {}
		for _, v in Rules.hexVertices[h] do
			local owner = view.owner[v]
			if owner ~= 0 and owner ~= me and not table.find(victims, owner) and view.players[owner].cards > 0
				and not (view.friendly and (view.players[owner].points or 0) <= 2) then
				table.insert(victims, owner)
			end
		end
		table.sort(victims)
		return victims
	end

	-- Board ---------------------------------------------------------------------
	local boardArea = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(0.58, 1), Parent = root })
	local board = Kit.new("Frame", {
		BackgroundColor3 = SEA,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = boardArea,
	}, { Kit.corner(16), Kit.new("UIAspectRatioConstraint", { AspectRatio = 1 }) })

	-- Hexes: three rotated rectangles make a pointy-top hexagon.
	local hexViews = {}
	-- What tapping each land, road edge and corner does (the map's buttons and Table view).
	local hexActs: { [number]: () -> () } = {}
	local edgeActs: { [number]: () -> () } = {}
	local vertexActs: { [number]: () -> () } = {}
	for h, hex in Rules.hexes do
		local holder = Kit.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = at(hex.x, hex.y),
			Size = UDim2.fromScale(SQRT3 * UNIT * 0.97, 2 * UNIT * 0.97),
			ZIndex = 1,
			Parent = board,
		})
		local parts = {}
		for i, rotation in { 0, 60, -60 } do
			parts[i] = Kit.new("Frame", {
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 0.5),
				Rotation = rotation,
				ZIndex = 1,
				Parent = holder,
			})
		end
		local icon = Kit.label("", {
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.2),
			Size = UDim2.fromScale(0.5, 0.2),
			ZIndex = 2,
			Parent = holder,
		})
		local token = circle({
			BackgroundColor3 = TOKEN,
			Position = UDim2.fromScale(0.5, 0.53),
			Size = UDim2.fromScale(0.38, 0.33),
			ZIndex = 3,
			Parent = holder,
		})
		local tokenStroke = Kit.new("UIStroke", { Thickness = 1, Color = DARK, Parent = token })
		local number = Kit.label("", {
			Font = Theme.FontBold,
			TextScaled = true,
			TextColor3 = DARK,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromScale(0.1, 0.08),
			Size = UDim2.fromScale(0.8, 0.6),
			ZIndex = 4,
			Parent = token,
		})
		local pips = Kit.label("", {
			Font = Theme.FontBold,
			TextScaled = true,
			TextColor3 = DARK,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromScale(0.15, 0.62),
			Size = UDim2.fromScale(0.7, 0.26),
			ZIndex = 4,
			Parent = token,
		})
		local bandit = circle({
			BackgroundColor3 = Color3.fromRGB(25, 22, 30),
			Position = UDim2.fromScale(0.5, 0.53),
			Size = UDim2.fromScale(0.42, 0.37),
			ZIndex = 6,
			Visible = false,
			Parent = holder,
		})
		Kit.new("UIStroke", { Thickness = 2, Color = Color3.fromRGB(200, 60, 60), Parent = bandit })
		-- Drawn, not an emoji, so it shows on every device: a dark token with a mask band.
		Kit.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(200, 60, 60),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.36),
			Size = UDim2.fromScale(0.8, 0.16),
			ZIndex = 7,
			Parent = bandit,
		}, { Kit.corner(3) })
		Kit.label("B", {
			Font = Theme.FontBold,
			TextScaled = true,
			TextColor3 = Color3.fromRGB(240, 230, 230),
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromScale(0.2, 0.46),
			Size = UDim2.fromScale(0.6, 0.46),
			ZIndex = 8,
			Parent = bandit,
		})
		local button = circle({
			ClassName = "TextButton",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.8, 0.7),
			ZIndex = 8,
			Parent = holder,
		})
		hexActs[h] = function()
			if not snapshot then
				return
			end
			local view = snapshot.view
			if view.phase == "bandit" and table.find(view.options.hexes, h) then
				local victims = victimsAt(view, snapshot.yourSeat, h)
				if #victims <= 1 then
					banditHex = nil
					sendMove({ kind = "bandit", hex = h, victim = victims[1] })
				else
					banditHex = h
					rerender()
				end
			end
		end
		button.Activated:Connect(hexActs[h])
		hexViews[h] = { parts = parts, icon = icon, token = token, tokenStroke = tokenStroke, number = number, pips = pips, bandit = bandit }
	end

	-- Harbors, just off the coast.
	local harborLabels = {}
	for i, e in Rules.harborEdges do
		local edge = Rules.edges[e]
		local a, b = Rules.vertices[edge.a], Rules.vertices[edge.b]
		local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
		local len = math.sqrt(mx * mx + my * my)
		local ox, oy = mx / len * 0.62, my / len * 0.62
		for _, v in { a, b } do
			local dx, dy = (mx + ox) - v.x, (my + oy) - v.y
			Kit.new("Frame", {
				BackgroundColor3 = Color3.fromRGB(150, 110, 70),
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = at(v.x + dx / 2, v.y + dy / 2),
				Size = UDim2.fromScale(math.sqrt(dx * dx + dy * dy) * UNIT, 0.008),
				Rotation = math.deg(math.atan2(dy, dx)),
				ZIndex = 1,
				Parent = board,
			})
		end
		local label = circle({
			BackgroundColor3 = Color3.fromRGB(245, 235, 210),
			Position = at(mx + ox, my + oy),
			Size = UDim2.fromScale(0.085, 0.085),
			ZIndex = 2,
			Parent = board,
		})
		Kit.new("UIStroke", { Thickness = 1, Color = Color3.fromRGB(150, 110, 70), Parent = label })
		harborLabels[i] = Kit.label("", {
			Font = Theme.FontBold,
			TextScaled = false,
			TextSize = 17,
			RichText = true,
			LineHeight = 0.9,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextColor3 = DARK,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromScale(0, 0),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
			Parent = label,
		})
	end

	-- Roads: a bar along each edge, plus a dot to tap when you can build there.
	local edgeViews = {}
	for e, edge in Rules.edges do
		local a, b = Rules.vertices[edge.a], Rules.vertices[edge.b]
		local bar = Kit.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = at((a.x + b.x) / 2, (a.y + b.y) / 2),
			Size = UDim2.fromScale(0.72 * UNIT, 0.014),
			Rotation = math.deg(math.atan2(b.y - a.y, b.x - a.x)),
			Visible = false,
			ZIndex = 9,
			Parent = board,
		}, { Kit.new("UIStroke", { Thickness = 1, Color = DARK }) })
		local dot = circle({
			ClassName = "TextButton",
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = HIGHLIGHT,
			BackgroundTransparency = 0.2,
			Position = at((a.x + b.x) / 2, (a.y + b.y) / 2),
			Size = UDim2.fromScale(0.03, 0.03),
			Visible = false,
			ZIndex = 12,
			Parent = board,
		})
		Kit.new("UIStroke", { Thickness = 2, Color = Theme.Accent, Parent = dot })
		edgeActs[e] = function()
			sendMove({ kind = "road", edge = e })
			mode = nil
		end
		dot.Activated:Connect(edgeActs[e])
		edgeViews[e] = { bar = bar, dot = dot }
	end

	-- Corners: camps, towns, and a dot to tap when you can build there.
	local vertexViews = {}
	for v, vertex in Rules.vertices do
		local piece = Kit.new("Frame", {
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = at(vertex.x, vertex.y),
			Size = UDim2.fromScale(0.04, 0.04),
			Visible = false,
			ZIndex = 13,
			Parent = board,
		}, { Kit.corner(4), Kit.new("UIStroke", { Thickness = 2, Color = DARK }) })
		local star = Kit.label("★", {
			Font = Theme.FontBold,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.3,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 14,
			Visible = false,
			Parent = piece,
		})
		local dot = circle({
			ClassName = "TextButton",
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = HIGHLIGHT,
			BackgroundTransparency = 0.2,
			Position = at(vertex.x, vertex.y),
			Size = UDim2.fromScale(0.036, 0.036),
			Visible = false,
			ZIndex = 15,
			Parent = board,
		})
		Kit.new("UIStroke", { Thickness = 2, Color = Theme.Accent, Parent = dot })
		vertexActs[v] = function()
			if not snapshot then
				return
			end
			local view = snapshot.view
			if view.phase == "setup" then
				sendMove({ kind = "place", vertex = v })
			elseif mode == "town" then
				sendMove({ kind = "town", vertex = v })
			else
				sendMove({ kind = "camp", vertex = v })
			end
			mode = nil
		end
		dot.Activated:Connect(vertexActs[v])
		vertexViews[v] = { piece = piece, star = star, dot = dot }
	end

	-- Dice in the corner of the sea.
	local diceRow = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.03, 0.03),
		Size = UDim2.fromScale(0.2, 0.09),
		ZIndex = 20,
		Parent = board,
	})
	local dice = {}
	for i = 1, 2 do
		local die = Kit.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Position = UDim2.fromScale((i - 1) * 0.52, 0),
			Size = UDim2.fromScale(0.46, 1),
			ZIndex = 20,
			Parent = diceRow,
		}, { Kit.corner(8), Kit.new("UIAspectRatioConstraint", { AspectRatio = 1 }), Kit.new("UIStroke", { Thickness = 2, Color = DARK }) })
		local label = Kit.label("-", {
			Font = Theme.FontBold,
			TextScaled = true,
			TextColor3 = DARK,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 21,
			Parent = die,
		})
		dice[i] = { frame = die, label = label }
	end
	local catalogEntry = GameCatalog.get(Rules.id)
	local title = Kit.label(string.upper(if catalogEntry then catalogEntry.name else "Hexlands"), {
		Font = Theme.FontBold,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(235, 245, 255),
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.97, 0.03),
		Size = UDim2.fromScale(0.4, 0.05),
		ZIndex = 20,
		Parent = board,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 28, Parent = title })

	-- Side panel ------------------------------------------------------------------
	local side = Kit.new("ScrollingFrame", {
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Position = UDim2.new(0.58, 8, 0, 0),
		Size = UDim2.new(0.42, -8, 1, 0),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = root,
	}, { Kit.corner(14), Kit.padding(10), Kit.list(8) })
	HudKit.sidePanel(side)
	-- Where your resource cards fly to after a roll (the side panel is rebuilt each update,
	-- so this sits over it and stays put).
	local handTarget = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.79, 4, 0, 90),
		Size = UDim2.fromOffset(40, 40),
		Parent = root,
	})

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local function heading(text: string, color: Color3?)
		HudKit.heading(text, { TextColor3 = color, LayoutOrder = nextOrder(), Parent = side })
	end

	local function note(text: string, color: Color3?)
		Kit.label(text, {
			TextSize = 14,
			TextColor3 = color or Theme.SubText,
			RichText = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = nextOrder(),
			Parent = side,
		})
	end

	local function row(height: number?): Frame
		return Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, height or 34),
			LayoutOrder = nextOrder(),
			Parent = side,
		}, { Kit.list(6, true) })
	end

	local function button(parent: Instance, text: string, onClick: () -> (), width: number, enabled: boolean?, color: Color3?)
		local on = enabled ~= false
		return Kit.button(text, function()
			if on then
				onClick()
			end
		end, {
			TextSize = 14,
			TextWrapped = true,
			AutoButtonColor = on,
			BackgroundColor3 = if not on then Theme.PanelLight elseif color then color else Theme.Accent,
			TextColor3 = if on then Theme.AccentText else Theme.SubText,
			Size = UDim2.new(width, -6, 1, 0),
			Parent = parent,
		})
	end

	-- A row of five resource buttons.
	local function resourceRow(label: (string) -> string, onPick: (string) -> (), enabled: ((string) -> boolean)?, selected: string?)
		local r = row(40)
		for _, res in RES do
			local on = if enabled then enabled(res) else true
			local b = button(r, label(res), function()
				onPick(res)
			end, 0.2, on, if res == selected then Theme.Good else info[res].color:Lerp(Color3.new(1, 1, 1), 0.35))
			b.TextColor3 = if on then DARK else Theme.SubText
		end
	end

	-- A +/- counter per resource (discards, trade offers).
	local function counterRows(counts: { [string]: number }, limit: (string) -> number)
		local r = row(48)
		for _, res in RES do
			local cell = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.2, -6, 1, 0), Parent = r }, { Kit.list(2) })
			local n = counts[res] or 0
			Kit.label(`{info[res].icon} {n}`, { TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 18), Parent = cell })
			local buttons = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), Parent = cell }, { Kit.list(2, true) })
			button(buttons, "−", function()
				counts[res] = math.max(0, n - 1)
				rerender()
			end, 0.5, n > 0)
			button(buttons, "+", function()
				counts[res] = n + 1
				rerender()
			end, 0.5, n < limit(res))
		end
	end

	local function total(counts: { [string]: number }): number
		local n = 0
		for _, res in RES do
			n += counts[res] or 0
		end
		return n
	end

	local function clean(counts: { [string]: number }): { [string]: number }
		local out = {}
		for _, res in RES do
			if (counts[res] or 0) > 0 then
				out[res] = counts[res]
			end
		end
		return out
	end

	local function canAfford(hand: any, cost: { [string]: number }): boolean
		for res, n in cost do
			if hand[res] < n then
				return false
			end
		end
		return true
	end

	-- Status line -------------------------------------------------------------------
	local function statusText(view: any, me: number?): string
		local turnName = nameOf(view.turn)
		local mine = me ~= nil and view.turn == me
		local phase = view.phase
		if phase == "over" then
			return "Game over"
		elseif phase == "setup" then
			if mine then
				return if view.setupStep == "place" then "Place a camp on a glowing corner" else "Place a road next to it"
			end
			return `{turnName} is placing a {if view.setupStep == "place" then "camp" else "road"}`
		elseif phase == "roll" then
			return if mine then "Your turn: roll the dice" else `{turnName} is about to roll`
		elseif phase == "discard" then
			if me and view.discards[me] > 0 then
				return `A 7! Discard {view.discards[me]} cards`
			end
			return "A 7! Waiting for big hands to discard"
		elseif phase == "bandit" then
			return if mine then "Tap a hex to move the Bandit" else `{turnName} is moving the Bandit`
		elseif phase == "trade" then
			local t = view.trade
			if me and t.from == me then
				return "Your trade offer: pick who to trade with"
			elseif me and (t.answers[me] or -1) == 0 then
				return `{nameOf(t.from)} offers you a trade`
			end
			return if t.to == 0 then `{nameOf(t.from)} offered everyone a trade` else `{nameOf(t.from)} offered {nameOf(t.to)} a trade`
		elseif phase == "roads" then
			return if mine then `Road Crew: place {view.freeRoads} free road{if view.freeRoads == 1 then "" else "s"}` else `{turnName} is building roads`
		end
		return if mine then "Build, trade, then end your turn" else `{turnName}'s turn`
	end

	-- A trade in progress -------------------------------------------------------------
	-- Everyone asked gets a chip: thinking, in, no, or a counter-offer. The offerer taps
	-- Trade on the one they want; the people asked answer Accept / Decline / Counter.
	local ANSWER = {
		[0] = { "thinking...", Theme.SubText },
		[1] = { "✓ In", Theme.Good },
		[2] = { "✗ No", Theme.Bad },
		[3] = { "↔ Counter", Theme.Accent },
	}

	function renderTrade(view: any, me: number?)
		local t = view.trade
		local you = view.you
		local mineOffer = me ~= nil and t.from == me
		if mineOffer then
			note(`<b>You give →</b> {cardsText(t.give)}\n<b>← You get</b> {cardsText(t.get)}`, Theme.Text)
		else
			note(`<b>{nameOf(t.from)} gives →</b> {cardsText(t.give)}\n<b>← wants</b> {cardsText(t.get)}`, Theme.Text)
		end
		local countersBy = {}
		for _, c in t.counters do
			countersBy[c.seat] = c
		end
		for seat = 1, #t.answers do
			local answer = t.answers[seat]
			if answer >= 0 then
				local line = Kit.new("Frame", {
					BackgroundColor3 = Theme.PanelLight,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 34),
					LayoutOrder = nextOrder(),
					Parent = side,
				}, { Kit.corner(8), Kit.padding(4) })
				Kit.new("Frame", { BackgroundColor3 = Theme.Seat[seat] or Theme.Text, BorderSizePixel = 0, Size = UDim2.new(0, 6, 1, 0), Parent = line }, { Kit.corner(3) })
				local c = countersBy[seat]
				local says = ANSWER[answer] or ANSWER[0]
				local text = says[1]
				if c then
					-- Counter terms, read from the offerer's side.
					text = if mineOffer then `↔ you give {cardsText(c.give)}, get {cardsText(c.get)}` else `↔ asks {cardsText(c.give)} for {cardsText(c.get)}`
				end
				Kit.label(`<b>{nameOf(seat)}</b>  <font color="#{says[2]:ToHex()}">{text}</font>`, {
					TextSize = 13,
					RichText = true,
					TextWrapped = false,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Position = UDim2.fromOffset(12, 0),
					Size = UDim2.new(if mineOffer then 0.72 else 1, -12, 1, 0),
					Parent = line,
				})
				if mineOffer and (answer == 1 or answer == 3) then
					local give = if c then c.give else t.give
					local ok = you ~= nil and canAfford(you.hand, give)
					local b = button(line, "Trade", function()
						sendMove({ kind = "confirm", with = seat })
					end, 0.28, ok, Theme.Good)
					b.AnchorPoint = Vector2.new(1, 0)
					b.Position = UDim2.fromScale(1, 0)
					Flair.nudge(b, 3)
				end
			end
		end
		if mineOffer then
			local r = row(36)
			button(r, "Call it off", function()
				sendMove({ kind = "cancel" })
			end, 1, true, Theme.PanelLight)
			return
		end
		if not (me and (t.answers[me] or -1) == 0 and you) then
			return
		end
		-- Your answer: big, well apart, like the online versions after players mis-tapped.
		if counter and counter.id == t.id then
			note("<b>Your counter-offer</b>")
			note("<b>You give →</b>")
			counterRows(counter.give, function(res)
				return you.hand[res]
			end)
			note("<b>← You get</b>")
			counterRows(counter.get, function(_)
				return 9
			end)
			local r = row(40)
			local ready = total(counter.give) > 0 and total(counter.get) > 0
			button(r, "Send counter", function()
				-- Written from the offerer's side, like the offer.
				sendMove({ kind = "counter", give = clean(counter.get), get = clean(counter.give) })
				counter = nil
			end, 0.6, ready, Theme.Good)
			button(r, "Back", function()
				counter = nil
				rerender()
			end, 0.4, true, Theme.PanelLight)
			return
		end
		local r = row(44)
		r:FindFirstChildOfClass("UIListLayout").Padding = UDim.new(0, 14)
		button(r, "Accept", function()
			sendMove({ kind = "accept" })
		end, 0.34, canAfford(you.hand, t.get), Theme.Good)
		button(r, "Counter", function()
			counter = { id = t.id, give = table.clone(t.get), get = table.clone(t.give) }
			rerender()
		end, 0.32, true, Theme.Accent)
		button(r, "Decline", function()
			sendMove({ kind = "reject" })
		end, 0.34, true, Theme.Bad)
	end

	-- Sections ----------------------------------------------------------------------
	local function renderActions(view: any, me: number?)
		local you = view.you
		local mine = me ~= nil and view.turn == me
		local phase = view.phase

		if phase == "roll" and mine then
			local r = row(40)
			button(r, "🎲 Roll", function()
				sendMove({ kind = "roll" })
			end, if view.canPlay.guard then 0.5 else 1)
			if view.canPlay.guard then
				button(r, "Play Guard first", function()
					sendMove({ kind = "play", card = "guard" })
				end, 0.5, true, Theme.Good)
			end
		end

		if phase == "bandit" and mine and banditHex then
			note("Take a card from:")
			local r = row(36)
			local victims = victimsAt(view, me, banditHex)
			for _, victim in victims do
				local hex = banditHex
				button(r, nameOf(victim), function()
					banditHex = nil
					sendMove({ kind = "bandit", hex = hex, victim = victim })
				end, 1 / #victims, true, Theme.Seat[victim])
			end
		end

		if phase == "discard" and me and view.discards[me] > 0 and you then
			local need = view.discards[me]
			counterRows(discard, function(res)
				return you.hand[res]
			end)
			local r = row(36)
			button(r, `Discard {total(discard)} of {need}`, function()
				sendMove({ kind = "discard", cards = clean(discard) })
				discard = {}
			end, 1, total(discard) == need)
		end

		if phase == "trade" and you then
			renderTrade(view, me)
		end

		if phase == "roads" and mine then
			local r = row(34)
			button(r, "Stop building roads", function()
				sendMove({ kind = "doneRoads" })
			end, 1, true, Theme.PanelLight)
		end

		if phase == "main" and mine and you then
			local p = view.players[me]
			heading("Build")
			local r = row(44)
			local opt = view.options
			local function buildButton(kind: string, label: string, cost: { [string]: number }, spots: number)
				local on = spots > 0
				button(r, `{if mode == kind then "✓ " else ""}{label}\n{costText(cost)}`, function()
					mode = if mode == kind then nil else kind
					rerender()
				end, 0.25, on, if mode == kind then Theme.Good else nil)
			end
			buildButton("road", `Road ({p.roads})`, Rules.costs.road, #opt.edges)
			buildButton("camp", `Camp ({p.camps})`, Rules.costs.camp, #opt.vertices)
			buildButton("town", `Town ({p.towns})`, Rules.costs.town, #opt.towns)
			button(r, `Card ({view.deckLeft})\n{costText(Rules.costs.card)}`, function()
				sendMove({ kind = "buyCard" })
			end, 0.25, view.deckLeft > 0 and canAfford(you.hand, Rules.costs.card))
			if mode then
				note("Tap a glowing spot on the island.")
			end

			-- Bank / harbor trades: pick what to give, then what to get.
			heading("Trade with the bank")
			resourceRow(function(res)
				return `{info[res].icon} {you.rates[res]}:1`
			end, function(res)
				bankGive = if bankGive == res then nil else res
				rerender()
			end, function(res)
				return you.hand[res] >= you.rates[res]
			end, bankGive)
			if bankGive then
				note(`Give {you.rates[bankGive]} {info[bankGive].name} for 1 of:`)
				resourceRow(function(res)
					return info[res].icon
				end, function(res)
					sendMove({ kind = "bank", give = bankGive, get = res })
					bankGive = nil
				end, function(res)
					return res ~= bankGive and view.bank[res] > 0
				end)
			end

			-- Player trades: "you give" and "you get", then everyone or one player.
			if view.tradesLeft > 0 then
				heading(`Offer a trade ({view.tradesLeft} left)`)
				note("<b>You give →</b>")
				counterRows(offer.give, function(res)
					return you.hand[res]
				end)
				note("<b>← You get</b>")
				counterRows(offer.get, function(_)
					return 9
				end)
				local who = row(34)
				local others = { 0 }
				for seat in view.players do
					if seat ~= me then
						table.insert(others, seat)
					end
				end
				for _, seat in others do
					local label = if seat == 0 then "Everyone" else nameOf(seat)
					button(who, `{if offer.to == seat then "✓ " else ""}{label}`, function()
						offer.to = seat
						rerender()
					end, 1 / #others, true, if seat == 0 then Theme.Accent else Theme.Seat[seat])
				end
				local ready = total(offer.give) > 0 and total(offer.get) > 0
				if not ready then
					note("Add cards on both sides to send an offer.")
				end
				local sendRow = row(38)
				button(sendRow, if offer.to == 0 then "Offer to everyone" else `Offer to {nameOf(offer.to)}`, function()
					sendMove({ kind = "offer", to = offer.to, give = clean(offer.give), get = clean(offer.get) })
					offer.give, offer.get = {}, {}
				end, 1, ready)
			end

			local endRow = row(40)
			button(endRow, "End turn", function()
				mode = nil
				sendMove({ kind = "endTurn" })
			end, 1, true, Theme.Bad)
		end
	end

	local function renderCards(view: any, me: number?)
		local you = view.you
		if not you then
			return
		end
		heading("Your cards")
		local r = row(44)
		for _, res in RES do
			local cell = Kit.new("Frame", {
				BackgroundColor3 = info[res].color,
				BorderSizePixel = 0,
				Size = UDim2.new(0.2, -6, 1, 0),
				Parent = r,
			}, { Kit.corner(8) })
			Kit.label(`{info[res].icon}\n{you.hand[res]}`, {
				Font = Theme.FontBold,
				TextSize = 15,
				TextColor3 = DARK,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.fromScale(1, 1),
				Parent = cell,
			})
		end

		if #you.cards > 0 then
			heading("Action cards")
			local counts, ready = {}, {}
			for _, card in you.cards do
				counts[card.kind] = (counts[card.kind] or 0) + 1
				ready[card.kind] = ready[card.kind] or card.ready
			end
			for _, kind in Rules.CARD_ORDER do
				if counts[kind] then
					local def = Rules.cards[kind]
					local line = row(38)
					Kit.label(`<b>{def.name} x{counts[kind]}</b>  {def.text}`, {
						TextSize = 13,
						RichText = true,
						Size = UDim2.new(0.7, -6, 1, 0),
						Parent = line,
					})
					if kind ~= "monument" and view.phase ~= "over" then
						button(line, if ready[kind] then "Play" else "Next turn", function()
							if kind == "harvest" or kind == "hoard" then
								picker = { card = kind, picks = {} }
								rerender()
							else
								sendMove({ kind = "play", card = kind })
							end
						end, 0.3, view.canPlay[kind] == true, Theme.Good)
					end
				end
			end
			if picker and view.canPlay[picker.card] then
				local need = if picker.card == "harvest" then 2 else 1
				note(if need == 2 then `Pick 2 to take from the bank ({#picker.picks}/2):` else "Pick a resource to collect from everyone:")
				resourceRow(function(res)
					return info[res].icon
				end, function(res)
					table.insert(picker.picks, res)
					if #picker.picks >= need then
						local move = { kind = "play", card = picker.card, res = if need == 2 then picker.picks else picker.picks[1] }
						picker = nil
						sendMove(move)
					else
						rerender()
					end
				end)
			else
				picker = nil
			end
		end
	end

	local function renderPlayers(view: any, me: number?)
		heading("Players")
		for seat, p in view.players do
			local turn = seat == view.turn and view.phase ~= "over"
			local line = Kit.new("Frame", {
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 42),
				LayoutOrder = nextOrder(),
				Parent = side,
			}, { Kit.corner(8), Kit.padding(6) })
			HudKit.glass(line, if turn then 0 else 0.25)
			if turn then
				line.HudGradient.Color = ColorSequence.new(HudKit.shade(HudKit.seatColor(seat), 0.5), HudKit.shade(Theme.Panel, 0.1))
				line.HudGradient.Rotation = 0
				line.Rim.Color = Theme.Accent
				line.Rim.Thickness = 2
				HudKit.pulse(line.Rim, 0, 0.6)
			end
			HudKit.avatar(seat, snapshot.seats[seat], {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, -2, 0.5, 0),
				Size = UDim2.fromOffset(28, 28),
				Parent = line,
			})
			local badges = {}
			if view.longestRoad == seat then
				table.insert(badges, "🛣 Longest Road")
			end
			if view.biggestGuard == seat then
				table.insert(badges, "🛡 Biggest Guard")
			end
			-- Cards in hand turn red over the hand limit (a 7 would cost them half).
			local over = p.cards > (view.handLimit or 7)
			Kit.label(`<b>{nameOf(seat)}</b>  ·  <font color="#{if over then "ff7a7a" else "c8c4dc"}">{p.cards} cards{if over then " !" else ""}</font>  ·  {p.actionCards} action`, {
				TextSize = 14,
				RichText = true,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.fromOffset(32, 0),
				Size = UDim2.new(1, -96, 0, 16),
				Parent = line,
			})
			-- Points as a big number with the goal, like the online player cards.
			Kit.label(`{p.points}{if seat == me and view.you and view.you.secret > 0 then `+{view.you.secret}` else ""}<font size="12">/{view.target}★</font>`, {
				Font = Theme.FontBold,
				TextSize = 22,
				RichText = true,
				TextColor3 = if p.points >= view.target - 2 then Theme.Accent else Theme.Text,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				Size = UDim2.fromOffset(70, 28),
				Parent = line,
			})
			Kit.label(`Road {p.roadLength} · Guards {p.guards}  {table.concat(badges, "  ")}`, {
				TextSize = 12,
				TextColor3 = Theme.SubText,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.fromOffset(32, 16),
				Size = UDim2.new(1, -96, 0, 14),
				Parent = line,
			})
		end
	end

	-- How often each total has come up, as bars (the "dice stats" of the big online
	-- versions), with the odds-expected count as a faint line so streaks stand out.
	local function renderDiceStats(view: any)
		local counts = view.rollCounts
		if not counts then
			return
		end
		local rolls, most = 0, 1
		for t = 2, 12 do
			rolls += counts[t] or 0
			most = math.max(most, counts[t] or 0)
		end
		if rolls == 0 then
			return
		end
		heading(`Dice stats · {rolls} rolls`)
		local chart = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 74), LayoutOrder = nextOrder(), Parent = side })
		local last = view.dice and (view.dice[1] + view.dice[2])
		for t = 2, 12 do
			local x = (t - 2) / 11
			local n = counts[t] or 0
			local expected = rolls * (6 - math.abs(7 - t)) / 36
			local scale = math.max(most, expected)
			local barH = n / scale
			local col = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(x, 1, 0, 0), Size = UDim2.new(1 / 11, -2, 1, 0), Parent = chart })
			Kit.new("Frame", {
				BackgroundColor3 = if t == last then Theme.Accent elseif t == 6 or t == 8 then Color3.fromRGB(220, 90, 80) else Theme.PanelLight,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 0, 1, -16),
				Size = UDim2.new(1, 0, barH, -16 * barH),
				Parent = col,
			}, { Kit.new("UICorner", { CornerRadius = UDim.new(0, 3) }) })
			Kit.new("Frame", {
				BackgroundColor3 = Theme.Text,
				BackgroundTransparency = 0.6,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 1 - expected / scale, -16 * (1 - expected / scale)),
				Size = UDim2.new(1, 0, 0, 2),
				Parent = col,
			})
			Kit.label(tostring(t), { TextSize = 11, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 0, 1, -14), Size = UDim2.new(1, 0, 0, 14), Parent = col })
		end
	end

	local function renderLog(view: any)
		heading("News")
		for i = #view.log, 1, -1 do
			local entry = view.log[i]
			local who = if entry.seat then nameOf(entry.seat) .. " " else ""
			local target = if entry.target then " " .. nameOf(entry.target) else ""
			note(`{who}{entry.text}{target}`, if entry.seat then Theme.Seat[entry.seat] else Theme.SubText)
		end
	end

	-- Render ------------------------------------------------------------------------
	function renderTable(view: any, me: number?)
		if not tableMode then
			return
		end
		local you = view.you
		local mine = me ~= nil and view.turn == me and view.phase ~= "over"
		local phase = view.phase
		local function panel(title: string)
			return function()
				prompt.sheet(side, title)
			end
		end
		if phase == "over" or snapshot.result then
			prompt.bar(nil)
			prompt.ask(nil)
			prompt.chips(nil)
			return
		end
		-- Your hand, as chips over the bar.
		if you then
			local chips = {}
			for _, res in RES do
				table.insert(chips, TablePrompt.chip(`{info[res].icon} {you.hand[res]}`, info[res].color))
			end
			local p = view.players[me]
			if p and p.points then
				table.insert(chips, TablePrompt.chip(`{p.points} / {view.target} pts`))
			end
			if #you.cards > 0 then
				table.insert(chips, TablePrompt.chip(`{#you.cards} action card{if #you.cards == 1 then "" else "s"}`, Theme.Accent))
			end
			prompt.chips("hand", chips)
		else
			prompt.chips(nil)
		end
		local cardsButton = { text = "Cards", color = Theme.PanelLight, onClick = panel("Your cards") }
		local status = statusText(view, me)

		-- Pop-ups: who to rob, a trade you're asked about.
		local asked = phase == "trade" and me ~= nil and you ~= nil and view.trade.from ~= me and (view.trade.answers[me] or -1) == 0 and not (counter and counter.id == view.trade.id)
		if phase == "bandit" and mine and banditHex then
			local hex = banditHex
			local buttons = {}
			for _, victim in victimsAt(view, me, hex) do
				table.insert(buttons, { text = nameOf(victim), color = Theme.Seat[victim], onClick = function()
					banditHex = nil
					sendMove({ kind = "bandit", hex = hex, victim = victim })
				end })
			end
			prompt.ask(`rob:{hex}`, "Take a card from", nil, buttons)
		elseif asked then
			local t = view.trade
			prompt.ask(`trade:{t.id}`, `{nameOf(t.from)} offers a trade`, `They give {cardsText(t.give)}, they want {cardsText(t.get)}`, {
				{ text = "Accept", color = Theme.Good, enabled = canAfford(you.hand, t.get), onClick = function()
					sendMove({ kind = "accept" })
				end },
				{ text = "Counter", onClick = function()
					counter = { id = t.id, give = table.clone(t.get), get = table.clone(t.give) }
					rerender()
					prompt.sheet(side, "Counter-offer")
				end },
				{ text = "Decline", color = Theme.Bad, onClick = function()
					sendMove({ kind = "reject" })
				end },
			})
		else
			prompt.ask(nil)
		end

		-- The bar.
		if phase == "roll" and mine then
			local buttons = { { text = "Roll", onClick = function()
				sendMove({ kind = "roll" })
			end } }
			if view.canPlay.guard then
				table.insert(buttons, { text = "Play Guard", color = Theme.Good, onClick = function()
					sendMove({ kind = "play", card = "guard" })
				end })
			end
			table.insert(buttons, cardsButton)
			prompt.bar("roll", status, buttons)
		elseif phase == "discard" and me and view.discards[me] > 0 and you then
			prompt.bar("discard", status, { { text = "Pick cards to discard", color = Theme.Bad, onClick = panel("Discard") } })
		elseif phase == "trade" and me and view.trade.from == me then
			prompt.bar("myTrade", "Your trade offer: waiting for answers", {
				{ text = "See answers", onClick = panel("Your trade") },
				{ text = "Call it off", color = Theme.PanelLight, onClick = function()
					sendMove({ kind = "cancel" })
				end },
			})
		elseif phase == "roads" and mine then
			prompt.bar("roads", status, { { text = "Stop building roads", color = Theme.PanelLight, onClick = function()
				sendMove({ kind = "doneRoads" })
			end } })
		elseif phase == "main" and mine and you then
			local p = view.players[me]
			local opt = view.options
			local buttons = {}
			local function build(kind: string, label: string, spots: number)
				table.insert(buttons, {
					text = label,
					color = if mode == kind then Theme.Good else Theme.Accent,
					enabled = spots > 0,
					onClick = function()
						mode = if mode == kind then nil else kind
						rerender()
					end,
				})
			end
			build("road", `Road ({p.roads})`, #opt.edges)
			build("camp", `Camp ({p.camps})`, #opt.vertices)
			build("town", `Town ({p.towns})`, #opt.towns)
			table.insert(buttons, { text = "Buy card", enabled = view.deckLeft > 0 and canAfford(you.hand, Rules.costs.card), onClick = function()
				sendMove({ kind = "buyCard" })
			end })
			table.insert(buttons, { text = "Trade / cards", color = Theme.PanelLight, onClick = panel("Trade and cards") })
			table.insert(buttons, { text = "End turn", color = Theme.Bad, onClick = function()
				mode = nil
				sendMove({ kind = "endTurn" })
			end })
			local line = if mode then `Tap a glowing spot to build a {mode} ({costText(Rules.costs[mode])})` else status
			prompt.bar("main", line, buttons)
		else
			prompt.bar("wait", status, { { text = "Info", color = Theme.PanelLight, onClick = panel("Island") } })
		end
	end

	local function render()
		local view = snapshot.view
		local me = snapshot.yourSeat
		local mine = me ~= nil and view.turn == me
		if view.phase ~= "main" or not mine then
			mode = nil
			bankGive = nil
		end
		if view.phase ~= "bandit" then
			banditHex = nil
		end
		if view.phase ~= "discard" then
			discard = {}
		end
		if counter and not (view.trade and view.trade.id == counter.id) then
			counter = nil
		end

		-- Hexes.
		for h, hv in hexViews do
			local tile = view.tiles[h]
			local color = landColor(tile.land)
			local pickable = view.phase == "bandit" and mine and table.find(view.options.hexes, h) ~= nil
			for _, part in hv.parts do
				-- The Bandit's hex goes dark: it pays nobody while he's there.
				part.BackgroundColor3 = if banditHex == h then color:Lerp(Color3.new(1, 1, 1), 0.5)
					elseif view.bandit == h then color:Lerp(Color3.fromRGB(20, 18, 26), 0.55)
					else color
			end
			hv.icon.Text = landIcon(tile.land)
			hv.token.Visible = tile.number > 0
			hv.number.Text = if tile.number > 0 then tostring(tile.number) else ""
			local red = tile.number == 6 or tile.number == 8
			hv.number.TextColor3 = if red then Color3.fromRGB(200, 40, 40) else DARK
			hv.pips.Text = string.rep("•", Rules.PIPS[tile.number] or 0)
			hv.pips.TextColor3 = hv.number.TextColor3
			hv.tokenStroke.Thickness = if pickable then 3 else 1
			hv.tokenStroke.Color = if pickable then Theme.Accent else DARK
			hv.bandit.Visible = view.bandit == h
			-- A rolled number lights up its hexes for a moment.
			if view.dice and tile.number == view.dice[1] + view.dice[2] then
				hv.token.BackgroundColor3 = Color3.fromRGB(255, 230, 120)
			else
				hv.token.BackgroundColor3 = TOKEN
			end
		end

		for i, harbor in view.harbors do
			harborLabels[i].Text = if harbor.kind == "any" then "3:1" else `2:1\n<font size="22">{info[harbor.kind].icon}</font>`
		end

		-- Roads and highlights.
		local opt = view.options
		local showEdges = mine and (view.phase == "setup" or view.phase == "roads" or (view.phase == "main" and mode == "road"))
		local edgeSet = {}
		if showEdges then
			for _, e in opt.edges do
				edgeSet[e] = true
			end
		end
		for e, ev in edgeViews do
			local owner = view.road[e]
			ev.bar.Visible = owner ~= 0
			if owner ~= 0 then
				ev.bar.BackgroundColor3 = Theme.Seat[owner] or Theme.Text
			end
			ev.dot.Visible = edgeSet[e] == true
		end

		local vertexSet = {}
		if mine and (view.phase == "setup" or (view.phase == "main" and mode == "camp")) then
			for _, v in opt.vertices do
				vertexSet[v] = true
			end
		elseif mine and view.phase == "main" and mode == "town" then
			for _, v in opt.towns do
				vertexSet[v] = true
			end
		end
		for v, vv in vertexViews do
			local owner = view.owner[v]
			vv.piece.Visible = owner ~= 0
			if owner ~= 0 then
				vv.piece.BackgroundColor3 = Theme.Seat[owner] or Theme.Text
				local town = view.town[v] == true
				vv.piece.Size = UDim2.fromScale(if town then 0.056 else 0.04, if town then 0.056 else 0.04)
				vv.star.Visible = town
			end
			vv.dot.Visible = vertexSet[v] == true
		end

		-- Dice, with a little shake when a new roll comes in.
		local d = view.dice
		for i = 1, 2 do
			dice[i].label.Text = if d then tostring(d[i]) else "-"
		end
		local key = if d then `{d[1]},{d[2]},{snapshot.moveNumber}` else ""
		if d and key ~= lastDice and view.log[#view.log] and string.find(view.log[#view.log].text, "rolled", 1, true) then
			-- What the roll paid you, called out (the resource cards flying in).
			local gain = view.lastGain
			if me and gain and gain.roll == d[1] + d[2] and gain.roll ~= 7 then
				local mine = (gain.gains or {})[tostring(me)]
				if mine then
					local parts = {}
					for _, r in Rules.resources do
						local n = mine[r.key]
						if n and n > 0 then
							table.insert(parts, `+{n} {r.icon}`)
						end
					end
					if #parts > 0 then
						HudKit.callout(if tableMode then prompt.layer else root, table.concat(parts, "  "), Color3.fromRGB(150, 220, 120), 0.3)
					end
					-- The cards fly off the hexes that paid into your hand.
					local gainKey = `{gain.turn}|{gain.roll}|{snapshot.moveNumber}`
					if gainKey ~= lastGainKey then
						lastGainKey = gainKey
						for _, h in gain.hexes or {} do
							local tile = view.tiles[h]
							local hv = hexViews[h]
							local n = tile and mine[tile.land]
							if hv and n and n > 0 then
								local icon = info[tile.land].icon
								Flair.flyTo(handTarget, {
									count = n,
									from = hv.token.AbsolutePosition + hv.token.AbsoluteSize / 2,
									make = function()
										local card = Kit.label(icon, { TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center, BackgroundColor3 = info[tile.land].color, BackgroundTransparency = 0, Size = UDim2.fromOffset(30, 40) })
										Kit.corner(6).Parent = card
										return card
									end,
								})
							end
						end
					end
				end
			end
			for i = 1, 2 do
				dice[i].frame.Rotation = if i == 1 then -25 else 25
				TweenService:Create(dice[i].frame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
			end
		end
		lastDice = key

		-- Side panel.
		for _, child in side:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		order = 0
		local mine = me ~= nil and view.turn == me and view.phase ~= "over"
		local turnSeat = if view.phase == "over" then nil else view.turn
		HudKit.turnTint(side, turnSeat, mine)
		HudKit.statusCard(statusText(view, me), turnSeat, mine, { LayoutOrder = nextOrder(), Parent = side })
		note(`First to {view.target} points wins · round {math.min(view.round, view.maxRounds)} of {view.maxRounds}`)
		if view.steal and view.steal.res then
			local s = view.steal
			if s.to == me then
				note(`You took 1 {info[s.res].icon} {info[s.res].name} from {nameOf(s.from)}`)
			elseif s.from == me then
				note(`{nameOf(s.to)} took your {info[s.res].icon} {info[s.res].name}`)
			end
		end
		renderCards(view, me)
		renderActions(view, me)
		renderPlayers(view, me)
		renderDiceStats(view)
		renderLog(view)
		renderTable(view, me)
	end
	rerender = function()
		if snapshot then
			render()
		end
	end

	-- Table view (Table3D/SceneTap): the corners, road edges and lands on the table work
	-- like the map's dots and tiles. Spots you can use glow.
	local function banditHexes(): { [number]: boolean }
		local out = {}
		local view = snapshot and snapshot.view
		if view and view.phase == "bandit" and view.turn == snapshot.yourSeat and view.options and view.options.hexes then
			for _, h in view.options.hexes do
				out[h] = true
			end
		end
		return out
	end
	local function usable(id: any): (() -> ())?
		if type(id) ~= "string" or not snapshot then
			return nil
		end
		local kind, n = string.match(id, "^(%a):(%d+)$")
		local i = tonumber(n)
		if not i then
			return nil
		end
		if kind == "v" and vertexViews[i] and vertexViews[i].dot.Visible then
			return vertexActs[i]
		elseif kind == "e" and edgeViews[i] and edgeViews[i].dot.Visible then
			return edgeActs[i]
		elseif kind == "h" and banditHexes()[i] then
			return hexActs[i]
		end
		return nil
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			render()
		end,
		canTap = function(id: any): boolean
			return usable(id) ~= nil
		end,
		tapTable = function(id: any)
			local act = usable(id)
			if act then
				act()
			end
		end,
		tableMarks = function(): { [any]: string }?
			if not snapshot then
				return nil
			end
			local marks = {}
			for v, view in vertexViews do
				if view.dot.Visible then
					marks[`v:{v}`] = "target"
				end
			end
			for e, view in edgeViews do
				if view.dot.Visible then
					marks[`e:{e}`] = "target"
				end
			end
			for h in banditHexes() do
				marks[`h:{h}`] = "target"
			end
			if banditHex then
				marks[`h:{banditHex}`] = "picked"
			end
			return marks
		end,
		setTableMode = function(value: boolean)
			if value == tableMode then
				return
			end
			tableMode = value
			root.Visible = not value
			prompt.setVisible(value)
			rerender()
		end,
		destroy = function()
			root:Destroy()
		end,
	}
end

return Hexlands
