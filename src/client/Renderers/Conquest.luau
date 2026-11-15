-- Conquest Isles table: the map on the left (territories as round markers in their owner's
-- seat color with the army count, ringed in their region's color, borders as lines), and
-- on the right what you can do now (place, attack, blitz, move armies, end turn), your
-- cards, the last battle's dice, who holds each region, and the news feed.
--
-- Map data and the connection check come from the shared rules module, so highlights
-- match what the server accepts. The server still checks everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Rules = require(ReplicatedStorage.Shared.Games.Conquest)
local Kit = require(script.Parent.Parent.UI.Kit)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local Juice = require(script.Parent.Parent.UI.Juice)
local Flair = require(script.Parent.Parent.UI.Flair)
local Audio = require(script.Parent.Parent.Audio)
local TablePrompt = require(script.Parent.Parent.UI.TablePrompt)
local Theme = Kit.Theme

local Conquest = {}

local territories = Rules.territories -- the match's map, set by buildMap
local SEA = Color3.fromRGB(46, 92, 140)
local SEA_LIGHT = Color3.fromRGB(70, 122, 170)
local LAND_LINE = Color3.fromRGB(226, 220, 200)
local NODE_SIZE = 0.058 -- of the map's width
local LAND_SIZE = 0.10 -- land patch under each territory, of the map's width
local MAP_ASPECT = 1.5
local FOG = Color3.fromRGB(96, 104, 122) -- a territory hidden by fog of war
local CARD_COLORS = {
	sword = Color3.fromRGB(235, 87, 87),
	shield = Color3.fromRGB(54, 162, 235),
	crown = Color3.fromRGB(255, 196, 64),
	wild = Color3.fromRGB(153, 102, 255),
}
local CARD_ICONS = { sword = "⚔", shield = "🛡", crown = "👑", wild = "★" }

function Conquest.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local selected: number? = nil -- your territory to attack or move from
	local target: number? = nil -- where to attack or move to
	local placeAmount: number | string = 1
	local moveCount = 1
	local pickedCards: { number } = {}
	local lastTurnId = -1
	local occupyFor: number? = nil -- the conquest the occupy counter was set up for
	local lastBattleId: number? = nil -- the battle whose losses already popped on the map
	local diceCount: number? = nil -- dice for a single Roll (nil: as many as you can)
	local stopAt = 1 -- a blitz stops when the attacking territory is down to this many
	local tumbledBattle: number? = nil -- the battle whose dice already tumbled
	local zoom = 1 -- map zoom (pinch, wheel or the +/- buttons)

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
	local rerender: () -> () = function() end
	-- Table view without the map or side panel: tap islands on the table; what to do
	-- now is a bar along the bottom, attacks and moves pop up (UI/TablePrompt).
	local tableMode = false
	local prompt = TablePrompt.new(container)
	prompt.setVisible(false)

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

	-- Map ----------------------------------------------------------------------
	local mapArea = Kit.new("Frame", { BackgroundTransparency = 1, ClipsDescendants = true, Size = UDim2.new(0.68, -8, 1, 0), Parent = root })
	local mapScale = Kit.new("UIScale", { Scale = 1 })
	local map = Kit.new("Frame", {
		BackgroundColor3 = SEA,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		Parent = mapArea,
	}, { Kit.corner(14), Kit.new("UIAspectRatioConstraint", { AspectRatio = MAP_ASPECT }), mapScale })

	-- The map's lands, borders and dots are built for the match's map (view.mapId) on the
	-- first update, and again if it changes.
	local lines = {}
	local nodes = {}
	local built: { Instance } = {}
	local builtMap: string? = nil
	local mapLinks: { any } = {}
	local onNode: (number) -> () = function() end
	local function track<T>(instance: T): T
		table.insert(built, instance :: any)
		return instance
	end
	local function layoutLines()
		local size = map.AbsoluteSize
		for i, line in lines do
			local link = mapLinks[i]
			local a, b = territories[link[1]], territories[link[2]]
			local ax, ay = a.x * size.X, a.y * size.Y
			local bx, by = b.x * size.X, b.y * size.Y
			local dx, dy = bx - ax, by - ay
			line.Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2)
			line.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), if link.sea then 2 else 4)
			line.Rotation = math.deg(math.atan2(dy, dx))
		end
	end
	map:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutLines)

	local function buildMap()
		for _, instance in built do
			instance:Destroy()
		end
		table.clear(built)
		builtMap = Rules.mapId
		territories = Rules.territories
		mapLinks = Rules.links
		-- Same-row neighbours on the bigger map sit closer, so their names get less room.
		local nameWidth = if #territories > 24 then 0.125 else 0.15
		-- A round patch of land in the region's color under each territory. On the Isles
		-- patches of the same region overlap into islands and different regions never touch
		-- (the closest neighbours across a border are further apart than LAND_SIZE); on the
		-- Crown every land is its own islet. The border lines join them. Each region's name and bonus sits in
		-- open sea next to it (labelX/labelY in the map data).
		for _, territory in territories do
			track(Kit.new("Frame", {
				BackgroundColor3 = Rules.regions[territory.region].color,
				BackgroundTransparency = 0.45,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(territory.x, territory.y),
				Size = UDim2.fromScale(LAND_SIZE, LAND_SIZE * MAP_ASPECT),
				ZIndex = 1,
				Parent = map,
			}, { Kit.corner(1000) }))
		end
		for _, region in Rules.regions do
			local label = track(Kit.label(`{region.name} +{region.bonus}`, {
				Font = Theme.FontBold,
				TextScaled = true,
				TextColor3 = region.color:Lerp(Color3.new(1, 1, 1), 0.35),
				TextStrokeTransparency = 0.6,
				TextXAlignment = Enum.TextXAlignment.Center,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(region.labelX, region.labelY),
				Size = UDim2.fromScale(0.17, 0.034),
				ZIndex = 2,
				Parent = map,
			}))
			Kit.new("UITextSizeConstraint", { MaxTextSize = 15, Parent = label })
		end

		table.clear(lines)
		for i, link in Rules.links do
			lines[i] = track(Kit.new("Frame", {
				BackgroundColor3 = if link.sea then SEA_LIGHT else LAND_LINE,
				BackgroundTransparency = if link.sea then 0.1 else 0.35,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				ZIndex = 2,
				Parent = map,
			}))
		end
		layoutLines()

		table.clear(nodes)
		for t, territory in territories do
			local node = track(Kit.new("TextButton", {
				Text = "",
				AutoButtonColor = false, -- a darker press tint looked like a change of owner
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(territory.x, territory.y),
				Size = UDim2.fromScale(NODE_SIZE, NODE_SIZE * MAP_ASPECT),
				BackgroundColor3 = Theme.PanelLight,
				Font = Theme.FontBold,
				TextColor3 = Color3.new(1, 1, 1),
				TextStrokeTransparency = 0.3,
				TextScaled = true,
				BorderSizePixel = 0,
				ZIndex = 4,
				Parent = map,
			}, { Kit.corner(100), Kit.new("UIAspectRatioConstraint", { AspectRatio = 1 }), Kit.padding(4) }))
			Kit.new("UITextSizeConstraint", { MaxTextSize = 22, Parent = node })
			local stroke = Kit.new("UIStroke", {
				Color = Rules.regions[territory.region].color,
				Thickness = 3,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Parent = node,
			})
			local name = track(Kit.label(territory.name, {
				Font = Theme.FontBold,
				TextScaled = true,
				TextStrokeTransparency = 0.35,
				TextXAlignment = Enum.TextXAlignment.Center,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(territory.x, territory.y + NODE_SIZE * MAP_ASPECT * 0.55),
				Size = UDim2.fromScale(nameWidth, 0.033),
				ZIndex = 5,
				Parent = map,
			}))
			Kit.new("UITextSizeConstraint", { MaxTextSize = 13, Parent = name })
			Kit.onPress(node, function()
				onNode(t)
			end)
			-- Capital conquest: a star on the capital's corner in its founder's color.
			local star = track(Kit.label("★", {
				Font = Theme.FontBold,
				TextScaled = true,
				TextColor3 = Color3.new(1, 1, 1),
				TextStrokeTransparency = 0.2,
				TextXAlignment = Enum.TextXAlignment.Center,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(territory.x + NODE_SIZE * 0.45, territory.y - NODE_SIZE * MAP_ASPECT * 0.45),
				Size = UDim2.fromScale(NODE_SIZE * 0.6, NODE_SIZE * 0.6 * MAP_ASPECT),
				Visible = false,
				ZIndex = 6,
				Parent = map,
			}))
			nodes[t] = { button = node, stroke = stroke, star = star }
		end
	end

	-- Phase bar across the top of the map, like the official app: Place · Attack · Move,
	-- the current step lit.
	local phaseBar = Kit.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(24, 30, 48),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0.5, 0, 0, 30),
		ZIndex = 10,
		Parent = map,
	}, { Kit.corner(15), Kit.padding(3) })
	local phaseList = Kit.list(4, true)
	phaseList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	phaseList.Parent = phaseBar
	local phasePills = {}
	for i, label in { "1 Place", "2 Attack", "3 Move" } do
		phasePills[i] = Kit.label(label, {
			Font = Theme.FontBold,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundColor3 = Theme.Accent,
			BackgroundTransparency = 1,
			Size = UDim2.new(1 / 3, -4, 1, 0),
			LayoutOrder = i,
			ZIndex = 11,
			Parent = phaseBar,
		})
		Kit.corner(12).Parent = phasePills[i]
	end
	-- The blitz win chance, over the territory you're about to attack.
	local chanceTag = Kit.label("", {
		Font = Theme.FontBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = Theme.Bad,
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(58, 22),
		Visible = false,
		ZIndex = 12,
		Parent = map,
	})
	Kit.corner(11).Parent = chanceTag
	-- Roll / Blitz right next to the target, like the official app (the panel has them too).
	local attackCard = Kit.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(24, 30, 48),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(150, 40),
		Visible = false,
		ZIndex = 12,
		Parent = map,
	}, { Kit.corner(10), Kit.padding(4), Kit.list(4, true) })
	local attackRoll = Kit.button("Roll", function() end, { Size = UDim2.new(0.5, -2, 1, 0), TextSize = 14, BackgroundColor3 = Theme.Bad, ZIndex = 13, Parent = attackCard })
	local attackBlitz = Kit.button("Blitz", function() end, { Size = UDim2.new(0.5, -2, 1, 0), TextSize = 14, ZIndex = 13, Parent = attackCard })
	local function sendAttack(blitz: boolean)
		if not (selected and target) then
			return
		end
		local move: any = { kind = "attack", from = selected, to = target, blitz = blitz }
		local most = math.min(3, (snapshot.view.armies[selected] or 2) - 1)
		if not blitz and diceCount and diceCount < most then
			move.dice = diceCount
		end
		if blitz and stopAt > 1 and stopAt < (snapshot.view.armies[selected] or 0) then
			move.stopAt = stopAt
		end
		sendMove(move)
	end
	Kit.onPress(attackRoll, function()
		sendAttack(false)
	end)
	Kit.onPress(attackBlitz, function()
		sendAttack(true)
	end)

	-- Side panel ---------------------------------------------------------------
	local side = Kit.new("ScrollingFrame", {
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Position = UDim2.new(0.68, 8, 0, 0),
		Size = UDim2.new(0.32, -8, 1, 0),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = root,
	}, { Kit.corner(14), Kit.padding(12), Kit.list(8) })
	HudKit.sidePanel(side)

	-- Phones and small boards: the map takes the full width on top (territories about
	-- twice as big) and the panel sits below it like a bottom sheet. Pinch, the mouse
	-- wheel or the +/- buttons zoom the map; drag pans it while zoomed.
	local compact = false
	local pan = Vector2.zero
	local function applyZoom()
		zoom = math.clamp(zoom, 1, 2.4)
		mapScale.Scale = zoom
		local area = mapArea.AbsoluteSize
		local limit = area * (zoom - 1) / 2
		pan = Vector2.new(math.clamp(pan.X, -limit.X, limit.X), math.clamp(pan.Y, -limit.Y, limit.Y))
		map.Position = UDim2.new(0.5, pan.X, 0.5, pan.Y)
	end
	local function layout()
		local size = root.AbsoluteSize
		compact = size.X < 760 or size.X / math.max(1, size.Y) < 1.25
		if compact then
			mapArea.Size = UDim2.new(1, 0, 0.6, -4)
			mapArea.Position = UDim2.new()
			side.Position = UDim2.new(0, 0, 0.6, 4)
			side.Size = UDim2.new(1, 0, 0.4, -4)
		else
			mapArea.Size = UDim2.new(0.68, -8, 1, 0)
			mapArea.Position = UDim2.new()
			side.Position = UDim2.new(0.68, 8, 0, 0)
			side.Size = UDim2.new(0.32, -8, 1, 0)
		end
		applyZoom()
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()
	local zoomBar = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -6, 1, -6),
		Size = UDim2.fromOffset(40, 128),
		ZIndex = 20,
		Parent = mapArea,
	}, { Kit.list(4) })
	for i, spec in { { "+", 0.4 }, { "−", -0.4 }, { "⤢", 0 } } do
		Kit.button(spec[1], function()
			if spec[2] == 0 then
				zoom, pan = 1, Vector2.zero
			else
				zoom += spec[2]
			end
			applyZoom()
		end, {
			Size = UDim2.fromOffset(40, 40),
			TextSize = 20,
			BackgroundColor3 = Theme.PanelLight,
			TextColor3 = Theme.Text,
			LayoutOrder = i,
			ZIndex = 21,
			Parent = zoomBar,
		})
	end
	local function overMap(position: Vector3 | Vector2): boolean
		local p, a, s = Vector2.new(position.X, position.Y), mapArea.AbsolutePosition, mapArea.AbsoluteSize
		return p.X >= a.X and p.Y >= a.Y and p.X <= a.X + s.X and p.Y <= a.Y + s.Y
	end
	local connections = {}
	local pinchStart = 1
	table.insert(connections, UserInputService.TouchPinch:Connect(function(points, scale, _velocity, state)
		if not root.Visible or not points[1] or not overMap(points[1]) then
			return
		end
		if state == Enum.UserInputState.Begin then
			pinchStart = zoom
		end
		zoom = pinchStart * scale
		applyZoom()
	end))
	table.insert(connections, UserInputService.TouchPan:Connect(function(points, translation, _velocity, state)
		if not root.Visible or zoom <= 1 or not points[1] or not overMap(points[1]) or #points > 1 then
			return
		end
		if state == Enum.UserInputState.Change then
			pan += translation * 0.05
			applyZoom()
		end
	end))
	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if root.Visible and input.UserInputType == Enum.UserInputType.MouseWheel and overMap(input.Position) then
			zoom += input.Position.Z * 0.2
			applyZoom()
		end
	end))

	local function section(order: number): Frame
		return Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			Parent = side,
		}, { Kit.list(6) })
	end

	local actions = section(1)
	local modesSection = section(2) -- secret mission, capitals, fog of war
	local cardsSection = section(3)
	local battleSection = section(4)
	local regionsSection = section(5)
	local logSection = section(6)

	local function heading(text: string, parent: Instance, order: number)
		return HudKit.heading(text, { LayoutOrder = order, Parent = parent })
	end
	local function hint(text: string, parent: Instance, order: number, color: Color3?)
		return Kit.label(text, {
			TextSize = 15,
			TextColor3 = color or Theme.SubText,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			LayoutOrder = order,
			Parent = parent,
		})
	end
	local function row(parent: Instance, order: number): Frame
		return Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 36),
			LayoutOrder = order,
			Parent = parent,
		}, { Kit.list(6, true) })
	end
	local function smallButton(text: string, parent: Instance, width: number, onClick: () -> (), color: Color3?, order: number?)
		return Kit.button(text, onClick, {
			Size = UDim2.new(width, if width < 1 then -4 else 0, 0, 36),
			BackgroundColor3 = color or Theme.Accent,
			TextColor3 = if color then Theme.Text else Theme.AccentText,
			TextSize = 15,
			LayoutOrder = order or 0,
			Parent = parent,
		})
	end

	local function myTurn(): boolean
		local view = snapshot and snapshot.view
		return view ~= nil and not snapshot.result and snapshot.yourSeat ~= nil and view.turn == snapshot.yourSeat
	end

	-- "Round 3 of 14", or near the end "Round 13 · cease-fire any turn now".
	local function roundText(view: any): string
		if view.ceaseFire then
			return `Round {view.round} · cease-fire any turn now`
		end
		return `Round {view.round} of {view.maxRounds}`
	end

	-- Highlights for the current selection: "attack" (enemy neighbours) and "move" (your
	-- land you can reach).
	local function targetsOf(view: any, me: number?): { [number]: string }
		local out = {}
		if not selected or not me or view.phase ~= "attack" then
			return out
		end
		for _, n in Rules.neighbors[selected] do
			if view.owner[n] ~= me and view.conquestsLeft > 0 then
				out[n] = "attack"
			end
		end
		for t = 1, #territories do
			if t ~= selected and view.owner[t] == me and Rules.connected(view.owner, me, selected, t) then
				out[t] = "move"
			end
		end
		return out
	end

	onNode = function(t: number)
		if not snapshot or not myTurn() then
			return
		end
		local view = snapshot.view
		local me = snapshot.yourSeat
		if view.phase == "reinforce" then
			if view.owner[t] ~= me or view.mustTrade then
				return
			end
			local count = if placeAmount == "all" then view.reinforcements else math.min(placeAmount :: number, view.reinforcements)
			if count > 0 then
				sendMove({ kind = "place", territory = t, count = count })
			end
		elseif view.phase == "attack" then
			local targets = targetsOf(view, me)
			if t == selected then
				selected, target = nil, nil
			elseif targets[t] then
				target = t
				moveCount = view.armies[selected :: number] - 1
			elseif view.owner[t] == me then
				selected = if view.armies[t] >= 2 then t else nil
				target = nil
			end
			rerender()
		end
	end

	-- End of the game: places by territories then armies, land share round by round
	-- (a stacked bar per round), and the biggest battle.
	local function renderFinal(view: any)
		heading("Final standings", actions, 2)
		local seats = {}
		for seat = 1, #view.eliminated do
			table.insert(seats, seat)
		end
		local totals = view.totals or {}
		local function lands(seat: number): number
			return Rules.countOwned(view.owner, seat)
		end
		table.sort(seats, function(a, b)
			if lands(a) ~= lands(b) then
				return lands(a) > lands(b)
			end
			return (totals[a] or 0) > (totals[b] or 0)
		end)
		for place, seat in seats do
			local text = if view.eliminated[seat] then "knocked out" else `{lands(seat)} lands · {totals[seat] or 0} armies`
			hint(`{place}. {nameOf(seat)}  {text}`, actions, 2 + place, Theme.Seat[seat])
		end
		local history = view.history
		if history and #history > 1 then
			hint("Territories round by round", actions, 20)
			local chart = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 70), LayoutOrder = 21, Parent = actions })
			local width = 1 / #history
			for i, rowCounts in history do
				local total = 0
				for _, n in rowCounts do
					total += n
				end
				local y = 0
				for seat, n in rowCounts do
					if n > 0 and total > 0 then
						Kit.new("Frame", {
							BackgroundColor3 = Theme.Seat[seat] or Theme.Text,
							BorderSizePixel = 0,
							Position = UDim2.new((i - 1) * width, 0, y / total, 0),
							Size = UDim2.new(width, -1, n / total, 0),
							Parent = chart,
						})
						y += n
					end
				end
			end
		end
		local b = view.biggestBattle
		if b then
			hint(`Biggest battle: {nameOf(b.attacker)} vs {nameOf(b.defender)} at {territories[b.to].name}, {b.lost} armies lost{if b.conquered then ", and it fell" else ""}.`, actions, 22)
		end
	end

	local function renderActions(view: any, me: number?)
		Kit.clear(actions)
		if snapshot.result then
			HudKit.turnTint(side, nil, false)
			HudKit.statusCard("Game over", nil, false, { LayoutOrder = 1, Parent = actions })
			renderFinal(view)
			return
		end
		HudKit.turnTint(side, view.turn, myTurn())
		if not myTurn() then
			HudKit.statusCard(`{nameOf(view.turn)}'s turn`, view.turn, false, { LayoutOrder = 1, Parent = actions })
			local doing = if view.phase == "reinforce" then "placing armies" else "on the attack"
			hint(`{roundText(view)}. They're {doing}.`, actions, 2)
			if view.nextUp and #view.nextUp > 0 then
				local names = {}
				for _, seat in view.nextUp do
					table.insert(names, nameOf(seat))
				end
				hint(`Next up: {table.concat(names, ", then ")}`, actions, 3)
			end
			return
		end
		HudKit.statusCard(`{roundText(view)}: your turn`, view.turn, true, { LayoutOrder = 1, Parent = actions })
		if view.phase == "reinforce" then
			if view.mustTrade then
				hint(`You have {#view.hand} cards. Trade a set below first.`, actions, 2, Theme.Accent)
				return
			end
			if view.holdForTrade then
				hint("All placed. You still hold a set: trade it now (more armies to place), or start attacking.", actions, 2, Theme.Accent)
				smallButton("Start attacking", actions, 1, function()
					sendMove({ kind = "startAttack" })
				end, nil, 3)
				return
			end
			hint(`Place {view.reinforcements} armies: tap your territories.`, actions, 2, Theme.Text)
			if view.income then
				local parts = {}
				for _, part in view.income do
					table.insert(parts, `{part.armies} {part.label}`)
				end
				hint(`From {table.concat(parts, " + ")}{if view.reinforcements > 0 then "" else ""}`, actions, 2)
			end
			if view.rallying then
				hint(`Includes +{Rules.RALLY_ARMIES} rally armies for holding fewer lands than average.`, actions, 2, Theme.Good)
			end
			local amounts = row(actions, 3)
			for i, amount in { 1, 3, 5, "all" } do
				local chosen = placeAmount == amount
				smallButton(if amount == "all" then "All" else `+{amount}`, amounts, 1 / 4, function()
					placeAmount = amount
					rerender()
				end, if chosen then nil else Theme.PanelLight, i)
			end
		elseif view.phase == "occupy" then
			local occupy = view.occupy
			if occupyFor ~= occupy.to then
				occupyFor = occupy.to
				moveCount = occupy.max
			end
			moveCount = math.clamp(moveCount, occupy.min, occupy.max)
			hint(`You took {territories[occupy.to].name}! How many armies move in?`, actions, 2, Theme.Good)
			local counter = row(actions, 3)
			smallButton("−", counter, 0.2, function()
				moveCount = math.max(occupy.min, moveCount - 1)
				rerender()
			end, Theme.PanelLight, 1)
			Kit.label(`{moveCount}`, { Size = UDim2.new(0.2, -4, 1, 0), Font = Theme.FontBold, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2, Parent = counter })
			smallButton("+", counter, 0.2, function()
				moveCount = math.min(occupy.max, moveCount + 1)
				rerender()
			end, Theme.PanelLight, 3)
			smallButton("Half", counter, 0.2, function()
				moveCount = math.clamp(math.ceil(occupy.max / 2), occupy.min, occupy.max)
				rerender()
			end, Theme.PanelLight, 4)
			smallButton("All", counter, 0.2, function()
				moveCount = occupy.max
				rerender()
			end, Theme.PanelLight, 5)
			smallButton(`Move {moveCount} in`, actions, 1, function()
				sendMove({ kind = "occupy", count = moveCount })
			end, nil, 4)
		elseif view.phase == "attack" then
			local targets = targetsOf(view, me)
			if selected and target and targets[target] == "attack" then
				local from, to = territories[selected].name, territories[target].name
				hint(`Attack {to} ({view.armies[target]}) from {from} ({view.armies[selected]})`, actions, 2, Theme.Text)
				local chance = Rules.winChance(view.armies[selected], view.armies[target])
				hint(`Blitz win chance: {math.floor(chance * 100 + 0.5)}%`, actions, 2, if chance >= 0.6 then Theme.Good elseif chance >= 0.35 then Theme.Accent else Theme.Bad)
				local most = math.min(3, view.armies[selected] - 1)
				local dice = math.min(diceCount or most, most)
				local diceRowFrame = row(actions, 3)
				Kit.label("Dice", { Size = UDim2.new(0.25, -4, 1, 0), TextSize = 15, LayoutOrder = 0, Parent = diceRowFrame })
				for n = 1, 3 do
					smallButton(tostring(n), diceRowFrame, 0.25, function()
						if n <= most then
							diceCount = n
							rerender()
						end
					end, if n == dice then nil else Theme.PanelLight, n)
				end
				local buttons = row(actions, 4)
				smallButton(`Roll {dice}`, buttons, 0.5, function()
					sendAttack(false)
				end, Theme.Bad, 1)
				smallButton(if stopAt > 1 then `Blitz (stop at {stopAt})` else "Blitz", buttons, 0.5, function()
					sendAttack(true)
				end, nil, 2)
				local stopRow = row(actions, 5)
				Kit.label("Blitz stops at", { Size = UDim2.new(0.4, -4, 1, 0), TextSize = 14, LayoutOrder = 0, Parent = stopRow })
				smallButton("−", stopRow, 0.2, function()
					stopAt = math.max(1, stopAt - 1)
					rerender()
				end, Theme.PanelLight, 1)
				Kit.label(`{stopAt}`, { Size = UDim2.new(0.2, -4, 1, 0), Font = Theme.FontBold, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2, Parent = stopRow })
				smallButton("+", stopRow, 0.2, function()
					stopAt = math.min(math.max(1, view.armies[selected] - 1), stopAt + 1)
					rerender()
				end, Theme.PanelLight, 3)
			elseif selected and target and targets[target] == "move" then
				local max = view.armies[selected] - 1
				moveCount = math.clamp(moveCount, 1, math.max(1, max))
				hint(`Move armies from {territories[selected].name} to {territories[target].name}. This ends your turn.`, actions, 2, Theme.Text)
				local counter = row(actions, 3)
				smallButton("−", counter, 0.2, function()
					moveCount = math.max(1, moveCount - 1)
					rerender()
				end, Theme.PanelLight, 1)
				Kit.label(`{moveCount}`, { Size = UDim2.new(0.2, -4, 1, 0), Font = Theme.FontBold, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2, Parent = counter })
				smallButton("+", counter, 0.2, function()
					moveCount = math.min(max, moveCount + 1)
					rerender()
				end, Theme.PanelLight, 3)
				smallButton("Half", counter, 0.2, function()
					moveCount = math.max(1, math.ceil(max / 2))
					rerender()
				end, Theme.PanelLight, 4)
				smallButton("All", counter, 0.2, function()
					moveCount = max
					rerender()
				end, Theme.PanelLight, 5)
				smallButton(`Move {moveCount} and end turn`, actions, 1, function()
					sendMove({ kind = "fortify", from = selected, to = target, count = moveCount })
				end, Theme.Good, 4)
			elseif view.peaceRound then
				hint("Round 1 is for placing armies: attacks start in round 2. Move armies once, or end your turn.", actions, 2, Theme.Accent)
			elseif view.conquestsLeft == 0 then
				hint("That's all the territories you can take this turn. More open up in later rounds.", actions, 2, Theme.Accent)
				if selected then
					hint(`{territories[selected].name} selected. Tap a green territory to move armies there, or end your turn.`, actions, 3)
				else
					hint("Tap one of your territories with 2+ armies to move armies from it, or end your turn.", actions, 3)
				end
			elseif selected then
				hint(`{territories[selected].name} selected. Tap a red neighbour to attack, or a green territory to move armies there.`, actions, 2)
			else
				hint("Tap one of your territories with 2+ armies to attack from it.", actions, 2)
			end
			if view.conquestsLeft > 0 and view.round <= 5 and view.earlyLimit ~= false and not view.peaceRound then
				local n = view.conquestsLeft
				hint(`You can take {n} more {if n == 1 then "territory" else "territories"} this turn.`, actions, 2)
			end
			if selected then
				smallButton("Cancel", actions, 1, function()
					selected, target = nil, nil
					rerender()
				end, Theme.PanelLight, 5)
			end
			smallButton("End turn", actions, 1, function()
				selected, target = nil, nil
				sendMove({ kind = "endTurn" })
			end, Theme.PanelLight, 6)
		end
	end

	-- Secret mission (yours, or everyone's at the end), capitals and fog of war.
	local function renderModes(view: any, me: number?)
		Kit.clear(modesSection)
		local order = 1
		local function line(text: string, color: Color3?)
			order += 1
			hint(text, modesSection, order, color)
		end
		if view.mission then
			heading("Your secret mission", modesSection, 1)
			line(Rules.missionText(view.mission, nameOf), Theme.Accent)
			if view.mission.needed and view.mission.needed > 1 then
				line(`Progress: {view.mission.done} of {view.mission.needed}`)
			end
			line("Finish it on your turn to win at once. Nobody else can see it.")
		elseif view.missions then
			heading("Secret missions", modesSection, 1)
			for seat, mission in view.missions do
				line(`{nameOf(seat)}: {Rules.missionText(mission, nameOf)}`, Theme.Seat[seat])
			end
		end
		if view.capitals then
			if order == 1 then
				heading("Capitals", modesSection, 1)
			end
			local mine = 0
			for _, t in view.capitals do
				if me and view.owner[t] == me then
					mine += 1
				end
			end
			if me then
				line(`Capitals (★): you hold {mine}. Hold {view.capitalsToWin} to win.`)
			else
				line(`Capitals (★): hold {view.capitalsToWin} to win.`)
			end
		end
		if view.fog then
			line("Fog of war: grey lands are hidden. You see lands that are yours or touch yours.", Theme.SubText)
		end
	end

	local function renderCards(view: any)
		local me = snapshot.yourSeat
		Kit.clear(cardsSection)
		if not view.hand then
			return
		end
		heading(`Your cards ({#view.hand})`, cardsSection, 1)
		if #view.hand == 0 then
			hint("Take a territory this turn to earn a card.", cardsSection, 2)
			return
		end
		local grid = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			Parent = cardsSection,
		})
		Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(64, 72), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
		for i, kind in view.hand do
			local picked = table.find(pickedCards, i) ~= nil
			local land = view.handLands and view.handLands[i] or 0
			local landName = if land > 0 and territories[land] then territories[land].name else nil
			local yours = land > 0 and me ~= nil and view.owner[land] == me
			local card = Kit.new("TextButton", {
				Text = if landName then `{CARD_ICONS[kind] or "?"}\n{landName}{if yours then "\n+2" else ""}` else `{CARD_ICONS[kind] or "?"}\n{Rules.cardNames[kind] or kind}`,
				TextWrapped = true,
				Font = Theme.FontBold,
				TextSize = 13,
				TextColor3 = Color3.new(1, 1, 1),
				TextStrokeTransparency = 0.5,
				BackgroundColor3 = CARD_COLORS[kind] or Theme.PanelLight,
				BorderSizePixel = 0,
				LayoutOrder = i,
				Parent = grid,
			}, { Kit.corner(8) })
			if picked then
				Kit.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 3, Parent = card })
			end
			Kit.onPress(card, function()
				local at = table.find(pickedCards, i)
				if at then
					table.remove(pickedCards, at)
				elseif #pickedCards < 3 then
					table.insert(pickedCards, i)
				end
				rerender()
			end)
		end
		local canTrade = myTurn() and view.phase == "reinforce" and not (view.knockoutTrade and #view.hand < Rules.HAND_LIMIT)
		local cards: { number }? = nil
		local value: number? = nil
		if #pickedCards == 3 then
			local kinds = {}
			for j, index in pickedCards do
				kinds[j] = view.hand[index]
			end
			value = Rules.setValue(kinds)
			cards = if value then table.clone(pickedCards) else nil
		else
			cards, value = Rules.bestSet(view.hand)
		end
		if value and view.nextRising then
			value = view.nextRising -- rising card values: every set is worth the same
		end
		if cards and value then
			local label = if #pickedCards == 3 then `Trade for {value} armies` else `Trade best set for {value}`
			local tradeButton = smallButton(label, cardsSection, 1, function()
				if canTrade then
					pickedCards = {}
					sendMove({ kind = "trade", cards = cards })
				end
			end, if canTrade then nil else Theme.PanelLight, 3)
			if canTrade then
				Flair.nudge(tradeButton, 3) -- a set is ready: the button nudges, like the card tray
			end
			if not canTrade then
				hint("Trade at the start of your turn.", cardsSection, 4)
			end
		elseif #pickedCards == 3 then
			hint("Those 3 aren't a set.", cardsSection, 3, Theme.Bad)
		end
		local values = Rules.setValues
		if view.nextRising then
			hint(`Sets: 3 of a kind or one of each. Rising values: the next trade at the table is worth {view.nextRising}. Wilds match anything.`, cardsSection, 5)
		else
			hint(`Sets: 3 Swords {values.sword} · 3 Shields {values.shield} · 3 Crowns {values.crown} · one of each {values.mixed}. Wilds match anything.`, cardsSection, 5)
		end
		hint(`A traded card showing a territory you hold puts +{Rules.CARD_LAND_BONUS} armies there.`, cardsSection, 6)
	end

	local function diceRow(parent: Instance, dice: { number }, color: Color3, order: number, tumble: boolean?)
		local frame = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = order, Parent = parent }, { Kit.list(6, true) })
		for i, value in dice do
			local die = Kit.new("TextLabel", {
				Text = `{value}`,
				Font = Theme.FontBold,
				TextSize = 18,
				TextColor3 = if color == Theme.Bad then Color3.new(1, 1, 1) else Color3.fromRGB(30, 30, 40),
				BackgroundColor3 = color,
				Size = UDim2.fromOffset(30, 30),
				LayoutOrder = i,
				Parent = frame,
			}, { Kit.corner(6) })
			-- A new battle: the dice tumble for a moment before they land.
			if tumble then
				task.spawn(function()
					for step = 1, 6 do
						if not die.Parent then
							return
						end
						die.Text = tostring(math.random(1, 6))
						die.Rotation = if step % 2 == 0 then 12 else -12
						task.wait(0.06)
					end
					if die.Parent then
						die.Text = `{value}`
						die.Rotation = 0
					end
				end)
			end
		end
	end

	local function renderBattle(view: any)
		Kit.clear(battleSection)
		local b = view.lastBattle
		if not b then
			return
		end
		heading("Last battle", battleSection, 1)
		local outcome = if b.conquered then " and took it!" elseif b.blitz then " and was held off." else "."
		local rolls = if b.rolls > 1 then ` ({b.rolls} rolls)` else ""
		hint(
			`{nameOf(b.attacker)} attacked {territories[b.to].name} from {territories[b.from].name}{rolls}: lost {b.attackerLost}, defeated {b.defenderLost}{outcome}`,
			battleSection,
			2,
			Theme.Text
		)
		local tumble = b.id ~= nil and b.id ~= tumbledBattle and tumbledBattle ~= nil
		if b.id ~= tumbledBattle then
			tumbledBattle = b.id or tumbledBattle or 0
		end
		diceRow(battleSection, b.attackDice, Theme.Bad, 3, tumble)
		diceRow(battleSection, b.defendDice, Color3.fromRGB(240, 240, 240), 4, tumble)
	end

	local function renderRegions(view: any)
		Kit.clear(regionsSection)
		heading("Regions", regionsSection, 1)
		for r, region in Rules.regions do
			local holder = Rules.regionOwner(view.owner, r)
			if holder == 0 then
				holder = nil -- all of it is in the fog
			end
			local line = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = r + 1, Parent = regionsSection })
			Kit.new("Frame", { BackgroundColor3 = region.color, BorderSizePixel = 0, Size = UDim2.fromOffset(12, 12), Position = UDim2.fromOffset(0, 4), Parent = line }, { Kit.corner(3) })
			Kit.label(`{region.name}  +{region.bonus}`, { TextSize = 14, Position = UDim2.fromOffset(18, 0), Size = UDim2.new(0.6, -18, 1, 0), Parent = line })
			Kit.label(if holder then nameOf(holder) else "—", {
				TextSize = 14,
				Font = Theme.FontBold,
				TextColor3 = if holder then Theme.Seat[holder] or Theme.Text else Theme.SubText,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.fromScale(0.6, 0),
				Size = UDim2.fromScale(0.4, 1),
				Parent = line,
			})
		end
	end

	local function renderLog(view: any)
		Kit.clear(logSection)
		heading("News", logSection, 1)
		local count = #view.log
		for i = count, 1, -1 do
			local entry = view.log[i]
			local text = entry.text
			if entry.target then
				text = string.gsub(text, "{target}", function()
					return nameOf(entry.target)
				end)
			end
			if entry.seat then
				local who = nameOf(entry.seat)
				if who == "You" then
					-- "is knocked out" -> "are knocked out", "was held off" -> "were held off"
					if string.sub(text, 1, 3) == "is " then
						text = "are " .. string.sub(text, 4)
					elseif string.sub(text, 1, 4) == "was " then
						text = "were " .. string.sub(text, 5)
					end
				end
				text = `{who} {text}`
			end
			hint(text, logSection, count - i + 2, if entry.seat then Theme.Seat[entry.seat] else nil)
		end
	end

	local function renderMap(view: any, me: number?)
		local targets = targetsOf(view, me)
		local placing = myTurn() and view.phase == "reinforce" and not view.mustTrade
		-- Phase bar: the step you're on (anyone's turn), Move lit once you pick a move.
		local step = if view.phase == "reinforce" then 1 elseif target and targets[target] == "move" then 3 else 2
		phaseBar.Visible = not snapshot.result
		for i, pill in phasePills do
			local on = i == step
			pill.BackgroundTransparency = if on then 0 else 1
			pill.TextColor3 = if on then Theme.AccentText else Theme.SubText
		end
		-- Everything you can't act on right now dims, so the choices stand out.
		local focus = myTurn() and (placing or (view.phase == "attack" and selected ~= nil))
		for t, node in nodes do
			local owner = view.owner[t]
			local fogged = owner == 0 -- fog of war: not yours and not next to yours
			node.button.BackgroundColor3 = if fogged then FOG else Theme.Seat[owner] or Theme.PanelLight
			node.button.Text = if fogged then "?" else `{view.armies[t]}`
			local founder = nil
			for seat, capital in view.capitals or {} do
				if capital == t then
					founder = seat
				end
			end
			node.star.Visible = founder ~= nil
			if founder then
				node.star.TextColor3 = Theme.Seat[founder] or Color3.new(1, 1, 1)
			end
			local live = not focus or (placing and owner == me) or t == selected or targets[t] ~= nil
			node.button.BackgroundTransparency = if live then 0 else 0.55
			node.button.TextTransparency = if live then 0 else 0.4
			local stroke = node.stroke
			local mark = targets[t]
			if t == selected then
				stroke.Color, stroke.Thickness = Theme.Accent, 5
			elseif t == target then
				stroke.Color, stroke.Thickness = Color3.new(1, 1, 1), 5
			elseif mark == "attack" then
				stroke.Color, stroke.Thickness = Theme.Bad, 4
			elseif mark == "move" then
				stroke.Color, stroke.Thickness = Theme.Good, 4
			elseif placing and owner == me then
				stroke.Color, stroke.Thickness = Theme.Accent, 3
			else
				stroke.Color, stroke.Thickness = Rules.regions[territories[t].region].color, 3
			end
		end
		-- Win chance over the territory you're aiming at.
		if myTurn() and selected and target and targets[target] == "attack" then
			local chance = Rules.winChance(view.armies[selected], view.armies[target])
			local spot = territories[target]
			chanceTag.Visible = true
			chanceTag.Text = `{math.floor(chance * 100 + 0.5)}%`
			chanceTag.BackgroundColor3 = if chance >= 0.6 then Color3.fromRGB(60, 160, 90) elseif chance >= 0.35 then Color3.fromRGB(200, 150, 40) else Theme.Bad
			chanceTag.Position = UDim2.fromScale(spot.x, spot.y - NODE_SIZE * MAP_ASPECT * 0.55)
			attackCard.Visible = not tableMode
			attackCard.Position = UDim2.fromScale(math.clamp(spot.x, 0.1, 0.9), math.min(spot.y + NODE_SIZE * MAP_ASPECT * 0.9, 0.9))
			local most = math.min(3, view.armies[selected] - 1)
			attackRoll.Text = `Roll {math.min(diceCount or most, most)}`
			attackBlitz.Text = if stopAt > 1 then `Blitz ≥{stopAt}` else "Blitz"
		else
			chanceTag.Visible = false
			attackCard.Visible = false
		end
		-- A new battle: losses pop over both territories, a conquest flips with a bounce.
		local b = view.lastBattle
		if b and b.id and b.id ~= lastBattleId then
			local first = lastBattleId == nil
			lastBattleId = b.id
			if not first then
				for _, side in { { b.from, b.attackerLost }, { b.to, b.defenderLost } } do
					local node = nodes[side[1]]
					if node and side[2] > 0 then
						local button = node.button
						Flair.floatText(button, `-{side[2]}`, button.AbsolutePosition + button.AbsoluteSize / 2, Color3.fromRGB(255, 110, 110))
						Juice.bump(button, 0.25)
					end
				end
				if b.conquered and nodes[b.to] then
					Juice.popIn(nodes[b.to].button, 0.4)
					Audio.play("callout", { volume = 0.5 })
				else
					Audio.play("dice", { volume = 0.5 })
				end
			end
		end
	end

	local function renderTable(view: any, me: number?)
		if not tableMode then
			return
		end
		local cardsN = if view.hand then #view.hand else 0
		local info = { text = if cardsN > 0 then `Cards ({cardsN})` else "Info", color = Theme.PanelLight, onClick = function()
			prompt.sheet(side, if cardsN > 0 then "Cards and battle" else "Battle")
		end }
		if snapshot.result then
			prompt.ask(nil)
			prompt.chips(nil)
			prompt.bar("over", "Game over", { { text = "Final standings", onClick = function()
				prompt.sheet(side, "Final standings")
			end } })
			return
		end
		local chips = { TablePrompt.chip(roundText(view)) }
		if me and view.owner then
			local lands, armies = 0, 0
			for t, owner in view.owner do
				if owner == me then
					lands += 1
					armies += view.armies[t]
				end
			end
			table.insert(chips, TablePrompt.chip(`Your islands {lands} · armies {armies}`, HudKit.seatColor(me)))
		end
		if view.mission then
			local progress = if view.mission.needed and view.mission.needed > 1 then ` ({view.mission.done}/{view.mission.needed})` else ""
			table.insert(chips, TablePrompt.chip(`Mission: {Rules.missionText(view.mission, nameOf)}{progress}`))
		end
		if view.capitals and me then
			local held = 0
			for _, t in view.capitals do
				if view.owner[t] == me then
					held += 1
				end
			end
			table.insert(chips, TablePrompt.chip(`Capitals ★ {held}/{view.capitalsToWin}`))
		end
		if view.fog then
			table.insert(chips, TablePrompt.chip("Fog of war"))
		end
		prompt.chips("info", chips)
		if not myTurn() then
			local doing = if view.phase == "reinforce" then "placing armies" else "on the attack"
			local nextText = ""
			if view.nextUp and view.nextUp[1] then
				nextText = ` · next: {nameOf(view.nextUp[1])}`
			end
			prompt.bar("wait", `{nameOf(view.turn)}'s turn: {doing}{nextText}`, { info })
			prompt.ask(nil)
			return
		end
		if view.phase == "reinforce" then
			prompt.ask(nil)
			if view.mustTrade then
				local cards, value = Rules.bestSet(view.hand)
				if view.nextRising and value then
					value = view.nextRising
				end
				prompt.ask("trade", `You have {cardsN} cards`, "Trade a set before placing armies.", {
					{ text = if value then `Trade for {value}` else "Pick cards", color = Theme.Good, onClick = function()
						if cards and value then
							pickedCards = {}
							sendMove({ kind = "trade", cards = cards })
						else
							prompt.sheet(side, "Cards")
						end
					end },
					{ text = "See cards", color = Theme.PanelLight, onClick = function()
						prompt.sheet(side, "Cards")
					end },
				})
				prompt.bar("trade", nil, {})
				return
			end
			if view.holdForTrade then
				local cards, value = Rules.bestSet(view.hand)
				if view.nextRising and value then
					value = view.nextRising
				end
				prompt.ask("hold", "You still hold a set", "Trade it for more armies, or start attacking.", {
					{ text = if value then `Trade for {value}` else "Cards", color = Theme.Good, onClick = function()
						if cards and value then
							pickedCards = {}
							sendMove({ kind = "trade", cards = cards })
						end
					end },
					{ text = "Start attacking", onClick = function()
						sendMove({ kind = "startAttack" })
					end },
				})
				prompt.bar("hold", nil, {})
				return
			end
			local buttons = {}
			for _, amount in { 1, 3, 5, "all" } do
				table.insert(buttons, {
					text = if amount == "all" then "All" else `+{amount}`,
					color = if placeAmount == amount then Theme.Accent else Theme.PanelLight,
					onClick = function()
						placeAmount = amount
						rerender()
					end,
				})
			end
			table.insert(buttons, info)
			prompt.bar("place", `Place {view.reinforcements} armies: tap your islands`, buttons)
		elseif view.phase == "occupy" then
			local occupy = view.occupy
			if occupyFor ~= occupy.to then
				occupyFor = occupy.to
				moveCount = occupy.max
			end
			moveCount = math.clamp(moveCount, occupy.min, occupy.max)
			prompt.bar("occupy", nil, {})
			prompt.ask(`occupy:{occupy.to}`, `You took {territories[occupy.to].name}!`, "How many armies move in?", {
				{ text = "-", color = Theme.PanelLight, enabled = moveCount > occupy.min, onClick = function()
					moveCount = math.max(occupy.min, moveCount - 1)
					rerender()
				end },
				{ text = `Move {moveCount} in`, color = Theme.Good, onClick = function()
					sendMove({ kind = "occupy", count = moveCount })
				end },
				{ text = "+", color = Theme.PanelLight, enabled = moveCount < occupy.max, onClick = function()
					moveCount = math.min(occupy.max, moveCount + 1)
					rerender()
				end },
				{ text = "Half", color = Theme.PanelLight, onClick = function()
					moveCount = math.clamp(math.ceil(occupy.max / 2), occupy.min, occupy.max)
					rerender()
				end },
				{ text = "All", color = Theme.PanelLight, onClick = function()
					moveCount = occupy.max
					rerender()
				end },
			})
		elseif view.phase == "attack" then
			local targets = targetsOf(view, me)
			local cancel = function()
				selected, target = nil, nil
				rerender()
			end
			if selected and target and targets[target] == "attack" then
				local from, to = territories[selected].name, territories[target].name
				local chance = Rules.winChance(view.armies[selected], view.armies[target])
				local most = math.min(3, view.armies[selected] - 1)
				local dice = math.min(diceCount or most, most)
				prompt.ask(`attack:{selected}:{target}:{dice}`, `Attack {to}?`, `From {from} ({view.armies[selected]}) against {view.armies[target]}. Blitz win chance {math.floor(chance * 100 + 0.5)}%`, {
					{ text = `Roll {dice}`, color = Theme.Bad, onClick = function()
						sendAttack(false)
					end },
					{ text = `Dice: {dice}`, color = Theme.PanelLight, onClick = function()
						diceCount = if dice <= 1 then most else dice - 1
						rerender()
					end },
					{ text = "Blitz", onClick = function()
						sendAttack(true)
					end },
					{ text = "Cancel", color = Theme.PanelLight, onClick = cancel },
				})
			elseif selected and target and targets[target] == "move" then
				local max = view.armies[selected] - 1
				moveCount = math.clamp(moveCount, 1, math.max(1, max))
				prompt.ask(`move:{selected}:{target}`, `Move to {territories[target].name}?`, "Moving armies ends your turn.", {
					{ text = "-", color = Theme.PanelLight, enabled = moveCount > 1, onClick = function()
						moveCount = math.max(1, moveCount - 1)
						rerender()
					end },
					{ text = `Move {moveCount}`, color = Theme.Good, onClick = function()
						sendMove({ kind = "fortify", from = selected, to = target, count = moveCount })
					end },
					{ text = "+", color = Theme.PanelLight, enabled = moveCount < max, onClick = function()
						moveCount = math.min(max, moveCount + 1)
						rerender()
					end },
					{ text = "Half", color = Theme.PanelLight, onClick = function()
						moveCount = math.max(1, math.ceil(max / 2))
						rerender()
					end },
					{ text = "Cancel", color = Theme.PanelLight, onClick = cancel },
				})
			else
				prompt.ask(nil)
			end
			local line
			if view.peaceRound then
				line = "Round 1 is for placing: move armies once or end your turn"
			elseif view.conquestsLeft == 0 then
				line = if selected then "Tap a green island to move armies there, or end your turn" else "No more conquests this turn: move armies or end your turn"
			elseif selected then
				line = "Tap a red neighbour to attack, or a green island to move armies"
			else
				line = "Tap one of your islands with 2+ armies to attack from it"
			end
			local buttons = {}
			if selected then
				table.insert(buttons, { text = "Cancel", color = Theme.PanelLight, onClick = cancel })
			end
			table.insert(buttons, info)
			table.insert(buttons, { text = "End turn", color = Theme.PanelLight, onClick = function()
				selected, target = nil, nil
				sendMove({ kind = "endTurn" })
			end })
			prompt.bar("attack", line, buttons)
		end
	end

	local function render()
		local view = snapshot.view
		local me = snapshot.yourSeat
		Rules.useMap(view.mapId)
		if builtMap ~= Rules.mapId then
			selected, target = nil, nil
			buildMap()
		end
		if view.turnId ~= lastTurnId then
			lastTurnId = view.turnId
			selected, target, pickedCards, occupyFor = nil, nil, {}, nil
			diceCount, stopAt = nil, 1
		end
		-- Drop a selection the board no longer allows (lost the territory, down to 1 army).
		if selected and (view.owner[selected] ~= me or view.armies[selected] < 2 or view.phase ~= "attack") then
			selected, target = nil, nil
		end
		if target and selected and not targetsOf(view, me)[target] then
			target = nil
		end
		if view.hand then
			for i = #pickedCards, 1, -1 do
				if pickedCards[i] > #view.hand then
					table.remove(pickedCards, i)
				end
			end
		end
		renderMap(view, me)
		renderActions(view, me)
		renderModes(view, me)
		renderCards(view)
		renderBattle(view)
		renderRegions(view)
		renderLog(view)
		renderTable(view, me)
	end
	rerender = function()
		if snapshot then
			render()
		end
	end

	-- Table view (Table3D/SceneTap): the islands on the table work like the map's dots.
	local function islandOf(id: any): number?
		local t = type(id) == "string" and tonumber(string.match(id, "^terr:(%d+)$"))
		return if t and snapshot and snapshot.view.owner[t] ~= nil then t else nil
	end

	-- Your picked island and where it can go (outlines on the table).
	local function selectionMarks(): { [any]: any }?
		if not (snapshot and myTurn() and snapshot.view.phase == "attack") then
			-- Table mode: where the armies you're placing can go.
			if tableMode and snapshot and myTurn() and snapshot.view.phase == "reinforce" and not snapshot.view.mustTrade then
				local marks = {}
				for t, owner in snapshot.view.owner do
					if owner == snapshot.yourSeat then
						marks[`terr:{t}`] = "target"
					end
				end
				return marks
			end
			return nil
		end
		local marks = {}
		if selected then
			marks[`terr:{selected}`] = "picked"
			for t in targetsOf(snapshot.view, snapshot.yourSeat) do
				marks[`terr:{t}`] = "target"
			end
		end
		if target then
			marks[`terr:{target}`] = "picked"
		end
		return marks
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			render()
		end,
		canTap = function(id: any): boolean
			local t = islandOf(id)
			if not (t and myTurn()) then
				return false
			end
			local view, me = snapshot.view, snapshot.yourSeat
			if view.phase == "reinforce" then
				return view.owner[t] == me and not view.mustTrade
			elseif view.phase == "attack" then
				return t == selected or (selected ~= nil and targetsOf(view, me)[t] ~= nil) or (view.owner[t] == me and view.armies[t] >= 2)
			end
			return false
		end,
		tapTable = function(id: any)
			local t = islandOf(id)
			if t then
				onNode(t)
			end
		end,
		tableMarks = function(): { [any]: any }?
			local marks = selectionMarks()
			-- Fog of war: the table board shows no armies (everyone sees it), so the ones
			-- you can see float over the islands on your screen only.
			if snapshot and snapshot.view.fog then
				marks = marks or {}
				for t, owner in snapshot.view.owner do
					if owner ~= 0 then
						local id = `terr:{t}`
						local mark = marks[id]
						marks[id] = {
							kind = if type(mark) == "string" then mark else "label",
							text = tostring(snapshot.view.armies[t]),
							color = HudKit.seatColor(owner),
						}
					end
				end
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
			for _, connection in connections do
				connection:Disconnect()
			end
			root:Destroy()
		end,
	}
end

return Conquest
