-- Conquest Isles table: the map on the left (territories as round markers in their owner's
-- seat color with the army count, ringed in their region's color, borders as lines), and
-- on the right what you can do now (place, attack, blitz, move armies, end turn), your
-- cards, the last battle's dice, who holds each region, and the news feed.
--
-- Map data and the connection check come from the shared rules module, so highlights
-- match what the server accepts. The server still checks everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Games.Conquest)
local Kit = require(script.Parent.Parent.UI.Kit)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local Juice = require(script.Parent.Parent.UI.Juice)
local Flair = require(script.Parent.Parent.UI.Flair)
local Audio = require(script.Parent.Parent.Audio)
local Theme = Kit.Theme

local Conquest = {}

local territories = Rules.territories
local SEA = Color3.fromRGB(46, 92, 140)
local SEA_LIGHT = Color3.fromRGB(70, 122, 170)
local LAND_LINE = Color3.fromRGB(226, 220, 200)
local NODE_SIZE = 0.058 -- of the map's width
local LAND_SIZE = 0.10 -- land patch under each territory, of the map's width
local MAP_ASPECT = 1.5
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

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
	local rerender: () -> () = function() end

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
	local mapArea = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.68, -8, 1, 0), Parent = root })
	local map = Kit.new("Frame", {
		BackgroundColor3 = SEA,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		Parent = mapArea,
	}, { Kit.corner(14), Kit.new("UIAspectRatioConstraint", { AspectRatio = MAP_ASPECT }) })

	-- A round patch of land in the region's color under each territory. Patches of the
	-- same region overlap into islands; different regions never touch (the closest
	-- neighbours across a border are further apart than LAND_SIZE), so the regions read
	-- as separate lands joined by the border lines. Each region's name and bonus sits in
	-- open sea next to it (labelX/labelY in the map data).
	for _, territory in territories do
		Kit.new("Frame", {
			BackgroundColor3 = Rules.regions[territory.region].color,
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(territory.x, territory.y),
			Size = UDim2.fromScale(LAND_SIZE, LAND_SIZE * MAP_ASPECT),
			ZIndex = 1,
			Parent = map,
		}, { Kit.corner(1000) })
	end
	for _, region in Rules.regions do
		local label = Kit.label(`{region.name} +{region.bonus}`, {
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
		})
		Kit.new("UITextSizeConstraint", { MaxTextSize = 15, Parent = label })
	end

	local lines = {}
	for i, link in Rules.links do
		lines[i] = Kit.new("Frame", {
			BackgroundColor3 = if link.sea then SEA_LIGHT else LAND_LINE,
			BackgroundTransparency = if link.sea then 0.1 else 0.35,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 2,
			Parent = map,
		})
	end
	local function layoutLines()
		local size = map.AbsoluteSize
		for i, link in Rules.links do
			local a, b = territories[link[1]], territories[link[2]]
			local ax, ay = a.x * size.X, a.y * size.Y
			local bx, by = b.x * size.X, b.y * size.Y
			local dx, dy = bx - ax, by - ay
			local line = lines[i]
			line.Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2)
			line.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), if link.sea then 2 else 4)
			line.Rotation = math.deg(math.atan2(dy, dx))
		end
	end
	map:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutLines)
	layoutLines()

	local onNode: (number) -> () = function() end
	local nodes = {}
	for t, territory in territories do
		local node = Kit.new("TextButton", {
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
		}, { Kit.corner(100), Kit.new("UIAspectRatioConstraint", { AspectRatio = 1 }), Kit.padding(4) })
		Kit.new("UITextSizeConstraint", { MaxTextSize = 22, Parent = node })
		local stroke = Kit.new("UIStroke", {
			Color = Rules.regions[territory.region].color,
			Thickness = 3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = node,
		})
		local name = Kit.label(territory.name, {
			Font = Theme.FontBold,
			TextScaled = true,
			TextStrokeTransparency = 0.35,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(territory.x, territory.y + NODE_SIZE * MAP_ASPECT * 0.55),
			Size = UDim2.fromScale(0.15, 0.033),
			ZIndex = 5,
			Parent = map,
		})
		Kit.new("UITextSizeConstraint", { MaxTextSize = 13, Parent = name })
		node.Activated:Connect(function()
			onNode(t)
		end)
		nodes[t] = { button = node, stroke = stroke }
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
	local cardsSection = section(2)
	local battleSection = section(3)
	local regionsSection = section(4)
	local logSection = section(5)

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

	local function renderActions(view: any, me: number?)
		Kit.clear(actions)
		if snapshot.result then
			HudKit.turnTint(side, nil, false)
			HudKit.statusCard("Game over", nil, false, { LayoutOrder = 1, Parent = actions })
			return
		end
		HudKit.turnTint(side, view.turn, myTurn())
		if not myTurn() then
			HudKit.statusCard(`{nameOf(view.turn)}'s turn`, view.turn, false, { LayoutOrder = 1, Parent = actions })
			local doing = if view.phase == "reinforce" then "placing armies" else "on the attack"
			hint(`Round {view.round} of {view.maxRounds}. They're {doing}.`, actions, 2)
			return
		end
		HudKit.statusCard(`Round {view.round} of {view.maxRounds}: your turn`, view.turn, true, { LayoutOrder = 1, Parent = actions })
		if view.phase == "reinforce" then
			if view.mustTrade then
				hint(`You have {#view.hand} cards. Trade a set below first.`, actions, 2, Theme.Accent)
				return
			end
			hint(`Place {view.reinforcements} armies: tap your territories.`, actions, 2, Theme.Text)
			if view.rallying then
				hint(`Includes +{Rules.RALLY_ARMIES} rally armies for holding fewer lands than average.`, actions, 2, Theme.Good)
			end
			local amounts = row(actions, 3)
			for i, amount in { 1, 3, "all" } do
				local chosen = placeAmount == amount
				smallButton(if amount == "all" then "All" else `+{amount}`, amounts, 1 / 3, function()
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
				local buttons = row(actions, 3)
				smallButton("Roll", buttons, 0.5, function()
					sendMove({ kind = "attack", from = selected, to = target, blitz = false })
				end, Theme.Bad, 1)
				smallButton("Blitz", buttons, 0.5, function()
					sendMove({ kind = "attack", from = selected, to = target, blitz = true })
				end, nil, 2)
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
			if view.conquestsLeft > 0 and view.round <= 5 and view.earlyLimit ~= false then
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

	local function renderCards(view: any)
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
		Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(52, 64), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
		for i, kind in view.hand do
			local picked = table.find(pickedCards, i) ~= nil
			local card = Kit.new("TextButton", {
				Text = `{CARD_ICONS[kind] or "?"}\n{Rules.cardNames[kind] or kind}`,
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
			card.Activated:Connect(function()
				local at = table.find(pickedCards, i)
				if at then
					table.remove(pickedCards, at)
				elseif #pickedCards < 3 then
					table.insert(pickedCards, i)
				end
				rerender()
			end)
		end
		local canTrade = myTurn() and view.phase == "reinforce"
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
	end

	local function diceRow(parent: Instance, dice: { number }, color: Color3, order: number)
		local frame = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = order, Parent = parent }, { Kit.list(6, true) })
		for i, value in dice do
			Kit.new("TextLabel", {
				Text = `{value}`,
				Font = Theme.FontBold,
				TextSize = 18,
				TextColor3 = if color == Theme.Bad then Color3.new(1, 1, 1) else Color3.fromRGB(30, 30, 40),
				BackgroundColor3 = color,
				Size = UDim2.fromOffset(30, 30),
				LayoutOrder = i,
				Parent = frame,
			}, { Kit.corner(6) })
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
		diceRow(battleSection, b.attackDice, Theme.Bad, 3)
		diceRow(battleSection, b.defendDice, Color3.fromRGB(240, 240, 240), 4)
	end

	local function renderRegions(view: any)
		Kit.clear(regionsSection)
		heading("Regions", regionsSection, 1)
		for r, region in Rules.regions do
			local holder = Rules.regionOwner(view.owner, r)
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
			node.button.BackgroundColor3 = Theme.Seat[owner] or Theme.PanelLight
			node.button.Text = `{view.armies[t]}`
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
		else
			chanceTag.Visible = false
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

	local function render()
		local view = snapshot.view
		local me = snapshot.yourSeat
		if view.turnId ~= lastTurnId then
			lastTurnId = view.turnId
			selected, target, pickedCards, occupyFor = nil, nil, {}, nil
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
		renderCards(view)
		renderBattle(view)
		renderRegions(view)
		renderLog(view)
	end
	rerender = function()
		if snapshot then
			render()
		end
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			render()
		end,
		destroy = function()
			root:Destroy()
		end,
	}
end

return Conquest
