-- Five Dice table. Left: the felt dice tray with the five dice of whoever is rolling
-- (yours on your turn), Roll and Score. Tap a die to keep it: it drops down onto a gold
-- line and stays put on the next roll. Right: the score card, one column per player.
-- On your turn, after a roll, every box you may use shows what it would score (faded);
-- tap a box to pick it, then Score (or tap the same box again).
--
-- In Table view the right side is docked: the dice and buttons move to the top of the
-- score card panel (setDocked), and the 3D tray on the table shows everyone's dice.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Games.FiveDice)
local Kit = require(script.Parent.Parent.UI.Kit)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local Juice = require(script.Parent.Parent.UI.Juice)
local Audio = require(script.Parent.Parent.Audio)
local Theme = Kit.Theme

local FiveDice = {}

local FELT = Color3.fromRGB(30, 104, 70)
local FELT_DARK = Color3.fromRGB(20, 72, 48)
local DIE_FACE = Color3.fromRGB(250, 246, 236)
local PIP = Color3.fromRGB(38, 32, 42)
local HELD = Color3.fromRGB(255, 206, 86)
local PREVIEW = Color3.fromRGB(255, 220, 140)

-- Where the pips go on a face, in thirds (x, y).
local PIPS = {
	{ { 0.5, 0.5 } },
	{ { 0.25, 0.25 }, { 0.75, 0.75 } },
	{ { 0.25, 0.25 }, { 0.5, 0.5 }, { 0.75, 0.75 } },
	{ { 0.25, 0.25 }, { 0.75, 0.25 }, { 0.25, 0.75 }, { 0.75, 0.75 } },
	{ { 0.25, 0.25 }, { 0.75, 0.25 }, { 0.5, 0.5 }, { 0.25, 0.75 }, { 0.75, 0.75 } },
	{ { 0.25, 0.22 }, { 0.75, 0.22 }, { 0.25, 0.5 }, { 0.75, 0.5 }, { 0.25, 0.78 }, { 0.75, 0.78 } },
}

local CALLS = {
	house = "Full house!",
	small = "Small straight!",
	large = "Large straight!",
	four = "4 of a kind!",
}

local function drawFace(face: Frame, value: number)
	for _, child in face:GetChildren() do
		if child.Name == "Pip" then
			child:Destroy()
		end
	end
	local spots = PIPS[value]
	if not spots then
		return
	end
	for _, spot in spots do
		Kit.new("Frame", {
			Name = "Pip",
			BackgroundColor3 = if value == 1 then Color3.fromRGB(210, 50, 60) else PIP,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spot[1], spot[2]),
			Size = UDim2.fromScale(if value == 1 then 0.26 else 0.19, if value == 1 then 0.26 else 0.19),
			ZIndex = face.ZIndex + 1,
			Parent = face,
		}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	end
end

local function fiveKind(dice: { number }): boolean
	for i = 2, #dice do
		if dice[i] ~= dice[1] or dice[i] == 0 then
			return false
		end
	end
	return dice[1] ~= 0
end

function FiveDice.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local docked = false
	local localHeld = { false, false, false, false, false }
	local heldFor = "" -- "<seat>:<rollId>" the local holds belong to
	local selected: string? = nil
	local shownRoll: { [number]: number } = {} -- [seat] = rollId already animated
	local shownScore = -1
	local shownBonus: { [number]: boolean } = {}
	local first = true

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })

	---------------------------------------------------------------- the tray (left)
	local tray = Kit.new("Frame", {
		BackgroundColor3 = FELT,
		BorderSizePixel = 0,
		Size = UDim2.new(0.57, 0, 1, 0),
		ClipsDescendants = false,
		Parent = root,
	}, {
		Kit.corner(18),
		Kit.new("UIStroke", { Color = Color3.fromRGB(92, 58, 38), Thickness = 6 }),
		HudKit.gradient(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 170, 170), 90),
	})
	local header = Kit.label("", {
		Font = Theme.FontTitle,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromScale(0.05, 0.04),
		Size = UDim2.fromScale(0.9, 0.09),
		Parent = tray,
	}, nil)
	Kit.new("UITextSizeConstraint", { MaxTextSize = 30, Parent = header })
	local subheader = Kit.label("", {
		TextScaled = true,
		TextColor3 = Color3.fromRGB(210, 236, 220),
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromScale(0.05, 0.13),
		Size = UDim2.fromScale(0.9, 0.06),
		Parent = tray,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 18, Parent = subheader })

	---------------------------------------------------------------- dice + buttons
	local controls = Kit.new("Frame", {
		Name = "Controls",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.58),
		Size = UDim2.fromScale(0.92, 0.6),
		Parent = tray,
	})
	local diceRow = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0.58),
		Parent = controls,
	})
	local dieViews = {}

	local function canHold(): boolean
		if not snapshot or snapshot.result or not snapshot.yourSeat then
			return false
		end
		local view = snapshot.view
		local me = view.players[snapshot.yourSeat]
		return view.preview ~= nil and me ~= nil and me.rolls >= 1 and me.rolls < view.maxRolls
	end

	local render: () -> () = function() end

	for i = 1, Rules.DICE do
		local slot = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromScale((i - 1) / Rules.DICE, 0),
			Size = UDim2.fromScale(1 / Rules.DICE, 1),
			Parent = diceRow,
		})
		local button = Kit.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = DIE_FACE,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.4),
			Size = UDim2.fromScale(0.82, 0.82),
			ZIndex = 3,
			Parent = slot,
		}, {
			Kit.new("UICorner", { CornerRadius = UDim.new(0.2, 0) }),
			Kit.new("UIAspectRatioConstraint", { AspectRatio = 1 }),
			Kit.shade(0.14),
		})
		local stroke = Kit.new("UIStroke", { Color = Color3.fromRGB(180, 170, 150), Thickness = 2, Parent = button })
		local keep = Kit.label("KEEP", {
			Font = Theme.FontBold,
			TextScaled = true,
			TextColor3 = HELD,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.86),
			Size = UDim2.fromScale(0.8, 0.14),
			Visible = false,
			Parent = slot,
		})
		local blank = Kit.label("?", {
			Font = Theme.FontTitle,
			TextScaled = true,
			TextColor3 = Color3.fromRGB(200, 190, 170),
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
			Parent = button,
		})
		local view = { button = button, stroke = stroke, keep = keep, blank = blank, value = -1 }
		dieViews[i] = view
		button.Activated:Connect(function()
			if not canHold() then
				if snapshot and snapshot.view.preview then
					Juice.nope(button)
				end
				return
			end
			localHeld[i] = not localHeld[i]
			Audio.play(if localHeld[i] then "lift" else "piece")
			Juice.bump(button, 0.08)
			sendMove({ kind = "hold", held = table.clone(localHeld) })
			render()
		end)
		Juice.press(button)
	end

	local buttons = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, 0.64),
		Size = UDim2.fromScale(1, 0.36),
		Parent = controls,
	})
	local rollButton = Kit.button("Roll", function()
		if not snapshot or not snapshot.view.players[snapshot.yourSeat or 0] then
			return
		end
		local me = snapshot.view.players[snapshot.yourSeat]
		if me.rolls == 0 then
			sendMove({ kind = "roll" })
		else
			sendMove({ kind = "roll", held = table.clone(localHeld) })
		end
		selected = nil
	end, {
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(0.48, 1),
		TextScaled = true,
		Font = Theme.FontTitle,
		Parent = buttons,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 26, Parent = rollButton })
	-- Shake the cup: holding Roll rattles the loose dice, letting go rolls them.
	local shaking = 0
	local function stopShake()
		shaking += 1
		for _, dv in dieViews do
			dv.button.Rotation = 0
		end
	end
	rollButton.MouseButton1Down:Connect(function()
		if not rollButton.Active then
			return
		end
		shaking += 1
		local token = shaking
		task.spawn(function()
			local tick = 0
			while shaking == token and rollButton.Parent do
				tick += 1
				for i, dv in dieViews do
					if not localHeld[i] then
						dv.button.Rotation = math.random(-14, 14)
					end
				end
				if tick % 4 == 1 then
					Audio.play("piece")
				end
				task.wait(0.05)
			end
		end)
	end)
	rollButton.MouseButton1Up:Connect(stopShake)
	rollButton.MouseLeave:Connect(stopShake)
	rollButton.Activated:Connect(stopShake)
	Kit.padding(6).Parent = rollButton
	local scoreButton = Kit.button("Score", function()
		if selected then
			sendMove({ kind = "score", box = selected })
			selected = nil
		end
	end, {
		Position = UDim2.fromScale(0.52, 0),
		Size = UDim2.fromScale(0.48, 1),
		TextScaled = true,
		BackgroundColor3 = Theme.Good,
		TextColor3 = Color3.fromRGB(10, 40, 20),
		Font = Theme.FontTitle,
		Parent = buttons,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 22, Parent = scoreButton })
	Kit.padding(6).Parent = scoreButton
	local waitLabel = Kit.label("", {
		TextScaled = true,
		TextColor3 = Color3.fromRGB(210, 236, 220),
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 0.6),
		Position = UDim2.fromScale(0, 0.2),
		Visible = false,
		Parent = buttons,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 20, Parent = waitLabel })

	---------------------------------------------------------------- score card (right)
	local panel = Kit.new("Frame", {
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.59, 0),
		Size = UDim2.fromScale(0.41, 1),
		Parent = root,
	}, { Kit.corner(14) })
	HudKit.sidePanel(panel)
	local controlsSlot = Kit.new("Frame", {
		BackgroundColor3 = FELT_DARK,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 6, 0, 6),
		Size = UDim2.new(1, -12, 0.3, -6),
		Visible = false,
		Parent = panel,
	}, { Kit.corner(10) })
	local sheet = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 6, 0, 6),
		Size = UDim2.new(1, -12, 1, -12),
		Parent = panel,
	})
	local sheetRows: { any } = {}
	local sheetKey = ""

	local function nameOf(seat: number): string
		if snapshot and seat == snapshot.yourSeat then
			return "You"
		end
		local s = snapshot and snapshot.seats[seat]
		return if s then s.name else `Seat {seat}`
	end

	local function cellLabel(parent: Instance, text: string, x: number, w: number, props: { [string]: any }?): TextLabel
		local label = Kit.label(text, {
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(x, 0, 0.12, 0),
			Size = UDim2.new(w, 0, 0.76, 0),
			ZIndex = 3,
			Parent = parent,
		})
		Kit.new("UITextSizeConstraint", { MaxTextSize = 16, Parent = label })
		for k, v in props or {} do
			(label :: any)[k] = v
		end
		return label
	end

	-- Rebuilds the card's rows when the seats or boxes change (once a match).
	local function buildSheet(view: any)
		local seats = #view.players
		local key = `{seats}:{table.concat(view.boxes, ",")}:{view.bigBonusRule}`
		if key == sheetKey then
			return
		end
		sheetKey = key
		Kit.clear(sheet)
		sheetRows = {}
		local rows: { any } = { { kind = "head" } }
		for _, id in view.boxes do
			table.insert(rows, { kind = "box", id = id })
			if id == "sixes" and not view.quick then
				table.insert(rows, { kind = "upperBonus" })
			end
		end
		if view.bigBonusRule then
			table.insert(rows, { kind = "bigBonus" })
		end
		table.insert(rows, { kind = "total" })
		local nameW = 0.4
		local colW = (1 - nameW) / seats
		for r, row in rows do
			local isBox = row.kind == "box"
			local frame = Kit.new(if isBox then "TextButton" else "Frame", {
				BackgroundColor3 = if r % 2 == 0 then Theme.PanelLight else Theme.Panel,
				BackgroundTransparency = if row.kind == "head" then 1 else 0.2,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0, (r - 1) / #rows),
				Size = UDim2.new(1, 0, 1 / #rows, -1),
				Parent = sheet,
			}, { Kit.corner(4) })
			if isBox then
				(frame :: TextButton).Text = "";
				(frame :: TextButton).AutoButtonColor = false
			end
			local title = if row.kind == "head" then ""
				elseif row.kind == "box" then Rules.BOX[row.id].name
				elseif row.kind == "upperBonus" then "Bonus (63+)"
				elseif row.kind == "bigBonus" then "Big Five bonus"
				else "TOTAL"
			local nameLabel = cellLabel(frame, title, 0.03, nameW - 0.03, {
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = if row.kind == "total" or row.id == "big" then Theme.FontBold else Theme.Font,
				TextColor3 = if row.id == "big" then Theme.Accent else Theme.Text,
			})
			local cells = {}
			for seat = 1, seats do
				cells[seat] = cellLabel(frame, "", nameW + (seat - 1) * colW, colW, {
					Font = if row.kind == "total" or row.kind == "head" then Theme.FontBold else Theme.Font,
				})
			end
			row.frame = frame
			row.name = nameLabel
			row.cells = cells
			if isBox then
				local id = row.id
				frame.Activated:Connect(function()
					local v = snapshot and snapshot.view
					if not v or not v.preview or snapshot.result then
						return
					end
					if v.preview[id] == nil then
						Juice.nope(frame)
						return
					end
					if selected == id then
						sendMove({ kind = "score", box = id })
						selected = nil
					else
						selected = id
						Audio.play("toggle")
					end
					render()
				end)
			end
			table.insert(sheetRows, row)
		end
	end

	local function setDocked(value: boolean)
		docked = value
		if docked then
			controls.Parent = controlsSlot
			controls.AnchorPoint = Vector2.new(0.5, 0.5)
			controls.Position = UDim2.fromScale(0.5, 0.5)
			controls.Size = UDim2.fromScale(0.94, 0.9)
			controlsSlot.Visible = true
			sheet.Position = UDim2.new(0, 6, 0.3, 6)
			sheet.Size = UDim2.new(1, -12, 0.7, -12)
		else
			controls.Parent = tray
			controls.Position = UDim2.fromScale(0.5, 0.58)
			controls.Size = UDim2.fromScale(0.92, 0.6)
			controlsSlot.Visible = false
			sheet.Position = UDim2.new(0, 6, 0, 6)
			sheet.Size = UDim2.new(1, -12, 1, -12)
		end
	end

	-- The seat whose dice the tray shows: you on your turn (or in together mode), else
	-- whoever is rolling.
	local function shownSeat(view: any, me: number?): number?
		if view.together then
			return me or 1
		end
		return view.turn or me
	end

	local function animateRoll(dice: { number }, held: { boolean })
		for i, dv in dieViews do
			if not held[i] then
				local token = (dv.button:GetAttribute("Roll") or 0) + 1
				dv.button:SetAttribute("Roll", token)
				task.spawn(function()
					for step = 1, 7 do
						if dv.button:GetAttribute("Roll") ~= token then
							return
						end
						drawFace(dv.button, math.random(1, 6))
						dv.button.Rotation = math.random(-25, 25)
						task.wait(0.04 + step * 0.012)
					end
					if dv.button:GetAttribute("Roll") ~= token then
						return
					end
					dv.value = dice[i]
					drawFace(dv.button, dice[i])
					TweenService:Create(dv.button, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
					Juice.bump(dv.button, 0.1)
				end)
			end
		end
	end

	function render()
		if not snapshot then
			return
		end
		local view = snapshot.view
		local me = snapshot.yourSeat
		buildSheet(view)
		local seat = shownSeat(view, me)
		local p = seat and view.players[seat]
		local mine = seat ~= nil and seat == me
		local active = view.preview ~= nil and not snapshot.result

		-- Your holds are kept locally (instant taps); others' come from the server.
		local holdKey = if p then `{seat}:{p.rollId}` else ""
		if mine and p and holdKey ~= heldFor then
			heldFor = holdKey
			localHeld = table.clone(p.held)
			if p.rolls == 0 then
				localHeld = { false, false, false, false, false }
			end
		end
		local held = if mine then localHeld else (p and p.held or { false, false, false, false, false })

		-- Header
		if snapshot.result then
			header.Text = "Game over"
			subheader.Text = ""
		elseif view.together then
			header.Text = if active then "Your roll!" else "Waiting for the others"
			subheader.Text = `Round {math.min(view.round, view.rounds)} of {view.rounds} · everyone rolls at once`
		else
			header.Text = if mine then "Your roll!" else `{nameOf(view.turn)} is rolling`
			subheader.Text = `Round {math.min(view.round, view.rounds)} of {view.rounds}`
		end
		HudKit.turnTint(panel, if view.together then nil else view.turn, active)

		-- Dice
		local fresh = p ~= nil and seat ~= nil and p.rollId ~= (shownRoll[seat] or 0) and p.rolls > 0
		for i, dv in dieViews do
			local value = if p and p.rolls > 0 then p.dice[i] else 0
			dv.blank.Visible = value == 0
			local isHeld = value ~= 0 and held[i] == true
			dv.keep.Visible = isHeld
			dv.stroke.Color = if isHeld then HELD else Color3.fromRGB(180, 170, 150)
			dv.stroke.Thickness = if isHeld then 4 else 2
			TweenService:Create(dv.button, TweenInfo.new(0.15), { Position = UDim2.fromScale(0.5, if isHeld then 0.5 else 0.4) }):Play()
			if not fresh and dv.value ~= value then
				dv.value = value
				drawFace(dv.button, value)
			end
		end
		if fresh and seat then
			local firstSeen = shownRoll[seat] == nil and first
			shownRoll[seat] = p.rollId
			if firstSeen then
				for i, dv in dieViews do
					dv.value = p.dice[i]
					drawFace(dv.button, p.dice[i])
				end
			else
				animateRoll(p.dice, p.held)
				if not docked then
					Audio.play("dice")
				end
				if fiveKind(p.dice) then
					task.delay(0.45, function()
						HudKit.callout(root, if mine then "BIG FIVE!" else `{nameOf(seat)}: BIG FIVE!`, Theme.Accent, 0.3)
						HudKit.confetti(root, 50, 50)
					end)
				end
			end
		end

		-- Buttons
		local meP = me and view.players[me]
		if active and meP then
			local left = view.maxRolls - meP.rolls
			rollButton.Visible = true
			scoreButton.Visible = meP.rolls > 0
			waitLabel.Visible = false
			if meP.rolls == 0 then
				rollButton.Text = "Roll!"
				rollButton.Size = UDim2.fromScale(1, 1)
			else
				rollButton.Size = UDim2.fromScale(0.48, 1)
				rollButton.Text = if left > 0 then `Roll ({left} left)` else "No rolls left"
			end
			rollButton.Active = left > 0
			rollButton.AutoButtonColor = left > 0
			rollButton.BackgroundColor3 = if left > 0 then Theme.Accent else Theme.PanelLight
			if selected and (view.preview[selected] == nil) then
				selected = nil
			end
			if selected then
				scoreButton.Text = `Score {view.preview[selected]} in {Rules.BOX[selected].name}`
				scoreButton.BackgroundColor3 = Theme.Good
			else
				scoreButton.Text = if view.joker then "Joker! Pick a box" else "Pick a box"
				scoreButton.BackgroundColor3 = Theme.PanelLight
			end
		else
			selected = nil
			rollButton.Visible = false
			scoreButton.Visible = false
			waitLabel.Visible = not snapshot.result
			waitLabel.Text = if not me then "Watching"
				elseif view.together then "You've scored this round. Waiting for the others…"
				else `Waiting for {nameOf(view.turn)}…`
		end

		-- Score card
		for _, row in sheetRows do
			for s, cell in row.cells do
				local sp = view.players[s]
				local isRoller = if view.together then sp.done < view.round else view.turn == s
				if row.kind == "head" then
					cell.Text = string.sub(nameOf(s), 1, 8)
					cell.TextColor3 = HudKit.seatColor(s)
					cell.Font = if isRoller and not view.finished then Theme.FontTitle else Theme.FontBold
				elseif row.kind == "box" then
					local v = sp.card[row.id]
					if v ~= nil then
						cell.Text = if v == 0 then "–" else tostring(v)
						cell.TextColor3 = if s == me then Theme.Text else Theme.SubText
						cell.TextTransparency = 0
					elseif s == me and view.preview and view.preview[row.id] ~= nil then
						cell.Text = tostring(view.preview[row.id])
						cell.TextColor3 = PREVIEW
						cell.TextTransparency = if selected == row.id then 0 else 0.35
					else
						cell.Text = ""
					end
				elseif row.kind == "upperBonus" then
					local t = sp.totals
					cell.Text = if t.upperBonus > 0 then "+35" else `{t.upper}/63`
					cell.TextColor3 = if t.upperBonus > 0 then Theme.Good else Theme.SubText
				elseif row.kind == "bigBonus" then
					cell.Text = if sp.totals.bigBonus > 0 then `+{sp.totals.bigBonus}` else ""
					cell.TextColor3 = Theme.Accent
				elseif row.kind == "total" then
					cell.Text = tostring(sp.totals.total)
					cell.TextColor3 = HudKit.seatColor(s)
				end
			end
			if row.kind == "box" then
				local can = view.preview ~= nil and view.preview[row.id] ~= nil and not snapshot.result
				row.frame.BackgroundColor3 = if selected == row.id then Color3.fromRGB(70, 120, 80)
					elseif can then Theme.PanelLight
					else Theme.Panel
				row.frame.BackgroundTransparency = if can then 0 else 0.35
				row.name.TextTransparency = if view.preview and not can then 0.45 else 0
			end
		end

		-- Score call-outs (anyone's), and the upper bonus when it lands.
		local last = view.lastScore
		if last and last.n ~= shownScore then
			local wasFirst = shownScore == -1 and first
			shownScore = last.n
			if not wasFirst then
				local who = if last.seat == me then "" else `{nameOf(last.seat)}: `
				if last.bonus then
					HudKit.callout(root, `{who}Big Five bonus +100!`, Theme.Accent, 0.3)
					HudKit.confetti(root, 60, 50)
				elseif last.bigFive then
					HudKit.callout(root, `{who}Big Five +50!`, Theme.Accent, 0.3)
				elseif CALLS[last.box] and last.points > 0 then
					HudKit.callout(root, `{who}{CALLS[last.box]} +{last.points}`, Theme.Good, 0.3)
				end
			end
		end
		for s, sp in view.players do
			local got = sp.totals.upperBonus > 0
			if got and not shownBonus[s] and not first then
				task.delay(0.8, function()
					HudKit.callout(root, if s == me then "Upper bonus +35!" else `{nameOf(s)}: upper bonus +35`, Theme.Good, 0.42)
				end)
			end
			shownBonus[s] = got
		end
		first = false
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			render()
		end,
		setDocked = function(value: boolean)
			if value ~= docked then
				setDocked(value)
			end
		end,
		destroy = function()
			root:Destroy()
		end,
	}
end

return FiveDice
