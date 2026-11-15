-- Werewolf: a header with the phase (🌙 night / ☀️ day / 🗳 vote), a draining timer and
-- your secret role; the village as a grid of player cards (tap one to pick them); and
-- the "what now" strip with the buttons for this phase.
--
-- Cards show what each seat said today, the open votes, who is out, and what only you
-- know (your packmates as a wolf, your checks as the Seer, your last shield as the
-- Guardian).
--
-- Table view (setTableMode): no panel. You play on the table: tap a player's lantern to
-- pick them (legal picks glow), and the buttons for this phase sit in a bar along the
-- bottom (UI/TablePrompt). Your role pops up as a card at the start, what only you know
-- floats over the lanterns (your pack, your checks), and "Village" opens the full grid
-- of player cards in a window.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Games.Werewolf)
local Kit = require(script.Parent.Parent.UI.Kit)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local Layout = require(script.Parent.Parent.UI.Layout)
local Audio = require(script.Parent.Parent.Audio)
local TablePrompt = require(script.Parent.Parent.UI.TablePrompt)
local Theme = Kit.Theme

local Werewolf = {}

local ROLES = Rules.ROLES
local NIGHT_TINT = Color3.fromRGB(36, 40, 86)
local DAY_TINT = Color3.fromRGB(120, 84, 40)

local ACTION_WORD = { wolf = "Catch", seer = "Check", guardian = "Shield", villager = "Hunch:", hunter = "Hunch:", witch = "Hunch:" }
local NIGHT_PROMPT = {
	wolf = "Pick a villager for the pack to catch.",
	seer = "Pick a player to check. You'll learn if they're a werewolf.",
	guardian = "Pick a player to shield tonight.",
	villager = "Everyone taps someone at night. Pick who you suspect.",
	hunter = "Pick who you suspect. If you go out, you take someone with you.",
	witch = "Pick who you suspect. Your potions come after everyone has picked.",
}

function Werewolf.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local selected: number? = nil
	local docked = false
	local compact = Layout.get().compact
	local lastPhaseKey = ""
	local wordsDraft = "" -- your last words, kept while the strip redraws
	local timerStart: number? = nil
	local lastMatchId: string? = nil

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
	local tableMode = false
	local villageOpen = false -- the village grid is in the Table view window
	local revealSeen: string? = nil -- the match whose role card you closed
	local prompt = TablePrompt.new(container)
	prompt.setVisible(false)

	-- Header ------------------------------------------------------------------------
	local header = Kit.new("Frame", { BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 70), Parent = root }, { Kit.corner(14) })
	HudKit.glass(header, 0.1)
	local phaseLabel = Kit.label("", {
		Font = Theme.FontTitle,
		TextSize = 26,
		Position = UDim2.new(0, 14, 0, 6),
		Size = UDim2.new(0.6, -14, 0, 32),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = header,
	})
	local subLabel = Kit.label("", {
		TextSize = 14,
		TextColor3 = Theme.SubText,
		Position = UDim2.new(0, 14, 0, 38),
		Size = UDim2.new(0.62, -14, 0, 18),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = header,
	})
	local roleChip = Kit.label("", {
		Font = Theme.FontBold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.PanelLight,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -90, 0, 12),
		Size = UDim2.new(0.36, -90, 0, 36),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = header,
	})
	HudKit.pill(roleChip)
	-- The roles in this game and the day cap (they change with table size and house rules).
	local setupLabel = Kit.label("", {
		TextSize = 12,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 50),
		Size = UDim2.new(0.4, 0, 0, 14),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = header,
	})
	local openLog: () -> () = function() end
	Kit.button("📜 Log", function()
		openLog()
	end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(72, 36),
		TextSize = 15,
		BackgroundColor3 = Theme.PanelLight,
		Parent = header,
	})
	local track = Kit.new("Frame", {
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 14, 1, -10),
		Size = UDim2.new(1, -28, 0, 5),
		Parent = header,
	}, { Kit.corner(3) })
	local fill = Kit.new("Frame", { BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = track }, { Kit.corner(3) })

	-- Village -----------------------------------------------------------------------
	local village = Kit.new("Frame", { BackgroundTransparency = 1, Parent = root })
	local grid = Kit.new("UIGridLayout", {
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = village,
	})

	-- What now ----------------------------------------------------------------------
	local actionArea = Kit.new("Frame", { BackgroundTransparency = 1, Parent = root })
	Kit.list(6).Parent = actionArea

	-- The big role reveal at the start (full view only; the dock shows it in the strip).
	local reveal = Kit.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})
	local revealCard = Kit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.7, 0, 0.62, 0),
		ZIndex = 21,
		Parent = reveal,
	})
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(460, 360), Parent = revealCard })
	local revealIcon = Kit.label("", { TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0.42, 0), ZIndex = 22, Parent = revealCard })
	local revealName = Kit.label("", {
		Font = Theme.FontTitle,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0.44, 0),
		Size = UDim2.new(1, 0, 0.18, 0),
		ZIndex = 22,
		Parent = revealCard,
	})
	local revealText = Kit.label("", {
		TextSize = 16,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0, 0, 0.66, 0),
		Size = UDim2.new(1, 0, 0.34, 0),
		ZIndex = 22,
		Parent = revealCard,
	})

	-- Helpers -----------------------------------------------------------------------

	local function nameOf(seat: number?): string
		if not seat or not snapshot then
			return "?"
		end
		if seat == snapshot.yourSeat then
			return "You"
		end
		local s = snapshot.seats[seat]
		return if s then s.name else "?"
	end

	local function roleText(role: string?): string
		local info = role and ROLES[role]
		return if info then `{info.icon} {info.name}` else "?"
	end

	-- "🐺x2 · 🔮 🛡️ 🏹 🧪 · Day 3 of 8"
	local function setupText(view: any): string
		local icons = {}
		for _, pair in { { view.withSeer, "seer" }, { view.withGuardian, "guardian" }, { view.withHunter, "hunter" }, { view.withWitch, "witch" } } do
			if pair[1] then
				table.insert(icons, ROLES[pair[2]].icon)
			end
		end
		local wolves = `🐺x{view.wolfCount or 1}{if view.wolvesLeft then ` ({view.wolvesLeft} left)` else ""}`
		return `{wolves} · {table.concat(icons, " ")} · Day {view.day or 1} of {view.maxDays or 8}`
	end

	local function statementText(st: any): string
		if not st then
			return ""
		elseif st.kind == "pass" then
			return "💬 Nothing to say"
		elseif st.kind == "accuse" then
			return `💬 Suspects {nameOf(st.target)}`
		elseif st.kind == "claim" then
			return if st.wolf then `🔮 "Seer: {nameOf(st.target)} is a WOLF"` else `🔮 "Seer: {nameOf(st.target)} is clear"`
		end
		return ""
	end

	local function myTurn(): boolean
		return snapshot ~= nil and snapshot.yourSeat ~= nil and snapshot.result == nil and table.find(snapshot.activeSeats, snapshot.yourSeat) ~= nil
	end

	-- The Witch's step: she moves out of turn, so it isn't in activeSeats.
	local function witchTurn(): boolean
		return snapshot ~= nil and snapshot.result == nil and snapshot.view.phase == "witch" and snapshot.view.witchCanAct == true
	end

	local function canPick(seat: number): boolean
		local view = snapshot.view
		return (myTurn() or witchTurn()) and view.targets ~= nil and table.find(view.targets, seat) ~= nil
	end

	-- The Witch's buttons: save tonight's victim, poison the picked player, or done.
	local function witchButtons(view: any): { any }
		local buttons = {}
		local who = if selected then nameOf(selected) else nil
		local victim = view.witchSees
		if view.potions and view.potions.heal and victim and not view.witchHeal then
			table.insert(buttons, { text = `🧪 Save {nameOf(victim)}`, color = Theme.Good, textColor = Theme.Text, onClick = function()
				send({ kind = "potion", potion = "heal", target = victim })
			end })
		end
		if view.potions and view.potions.poison and view.witchPoison == nil then
			table.insert(buttons, { text = if who then `☠️ Poison {who}` else "☠️ Poison: tap a player", color = if who then Color3.fromRGB(120, 60, 150) else Theme.Panel, textColor = Theme.Text, enabled = who ~= nil, onClick = function()
				if selected then
					send({ kind = "potion", potion = "poison", target = selected })
				end
			end })
		end
		table.insert(buttons, { text = "Done", color = Theme.Panel, textColor = Theme.SubText, onClick = function()
			send({ kind = "potion", potion = "none" })
		end })
		return buttons
	end

	-- What the Witch reads in her step.
	local function witchLine(view: any): string
		local parts = {}
		if view.witchSees then
			table.insert(parts, if view.witchHeal then `🧪 You're saving {nameOf(view.witchSees)}.` else `🐺 The wolves picked {nameOf(view.witchSees)}.`)
		elseif view.potions and view.potions.heal then
			table.insert(parts, "Nobody is in danger tonight.")
		end
		if view.witchPoison then
			table.insert(parts, `☠️ {nameOf(view.witchPoison)} is poisoned.`)
		end
		if view.witchCanAct then
			table.insert(parts, "Use a potion, or let the night pass.")
		end
		return table.concat(parts, " ")
	end

	local render: () -> ()

	local function send(move: any)
		sendMove(move)
		selected = nil
	end

	local function button(text: string, order: number, onClick: () -> (), props: { [string]: any }?): TextButton
		local b = Kit.button(text, onClick, {
			Size = UDim2.new(1, 0, 0, if compact then 32 else 36),
			TextSize = if compact then 14 else 16,
			LayoutOrder = order,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		for key, value in props or {} do
			(b :: any)[key] = value
		end
		return b
	end

	-- A row of buttons sharing the width.
	local function buttonRow(order: number, items: { { text: string, onClick: () -> (), color: Color3?, textColor: Color3? } })
		local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, if compact then 32 else 36), LayoutOrder = order, Parent = actionArea })
		local n = #items
		for i, item in items do
			local b = button(item.text, i, item.onClick, {
				Size = UDim2.new(1 / n, -6 * (n - 1) / n, 1, 0),
				Position = UDim2.new((i - 1) / n, 6 * (i - 1) / n, 0, 0),
			})
			if item.color then
				b.BackgroundColor3 = item.color
			end
			if item.textColor then
				b.TextColor3 = item.textColor
			end
			b.Parent = row
		end
	end

	-- Layout: full view (header, village, strip) or docked (one row of cards + strip).
	local function applyLayout()
		local view = snapshot and snapshot.view
		local n = if view then view.seatCount else 8
		header.Visible = not docked
		if villageOpen then
			-- In the Table view window: the full grid, sized by the window.
			local cols = if n <= 6 then 3 else 4
			local rows = math.ceil(n / cols)
			grid.CellSize = UDim2.new(1 / cols, -8, 1 / rows, -8)
		elseif docked then
			-- The dock shows the bottom 44% of the board (MatchView DOCK).
			village.Position = UDim2.new(0, 4, 0.57, 0)
			village.Size = UDim2.new(1, -8, 0.17, 0)
			grid.CellSize = UDim2.new(1 / n, -8, 1, 0)
			actionArea.Position = UDim2.new(0, 6, 0.75, 0)
			actionArea.Size = UDim2.new(1, -12, 0.25, -4)
		else
			local cols = if n <= 6 then 3 else 4
			local rows = math.ceil(n / cols)
			village.Position = UDim2.new(0, 0, 0, 78)
			village.Size = UDim2.new(1, 0, 0.66, -84)
			grid.CellSize = UDim2.new(1 / cols, -8, 1 / rows, -8)
			actionArea.Position = UDim2.new(0, 0, 0.66, 0)
			actionArea.Size = UDim2.new(1, 0, 0.34, 0)
		end
	end

	-- Cards ---------------------------------------------------------------------------

	local function seatCard(seat: number, order: number)
		local view = snapshot.view
		local me = snapshot.yourSeat
		local out = not view.alive[seat]
		local pickable = canPick(seat)
		local isSelected = selected == seat
		local card = Kit.new("TextButton", {
			Text = "",
			AutoButtonColor = pickable,
			BackgroundColor3 = if out then Color3.fromRGB(30, 28, 40) else Theme.PanelLight,
			BackgroundTransparency = if out then 0.4 else 0,
			BorderSizePixel = 0,
			LayoutOrder = order,
			Parent = village,
		}, { Kit.corner(12) })
		local ring = Kit.new("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = if isSelected then Theme.Accent else HudKit.seatColor(seat),
			Thickness = if isSelected then 3 elseif pickable then 1.5 else 0,
			Transparency = if pickable or isSelected then 0 else 1,
			Parent = card,
		})
		if isSelected then
			HudKit.pulse(ring, 0, 0.4)
		end
		Kit.onPress(card, function()
			if canPick(seat) then
				selected = if selected == seat then nil else seat
				render()
			end
		end)

		-- Avatar on the left in a row card (dock), on top in a tall card.
		local avatarSize = if docked then UDim2.new(0, 0, 0.8, 0) else UDim2.new(0, 0, 0.42, 0)
		local avatar = HudKit.avatar(seat, snapshot.seats[seat], {
			Size = avatarSize,
			AnchorPoint = if docked then Vector2.new(0, 0.5) else Vector2.new(0.5, 0),
			Position = if docked then UDim2.new(0, 4, 0.5, 0) else UDim2.new(0.5, 0, 0.06, 0),
			ZIndex = 4,
			Parent = card,
		})
		local aspect = avatar:FindFirstChildOfClass("UIAspectRatioConstraint")
		if aspect then
			aspect.DominantAxis = Enum.DominantAxis.Height
		end
		if out then
			avatar.BackgroundTransparency = 0.5
		end

		-- Lines under the name: what only you know first, then the public line.
		local lines = {}
		local role = view.roles[seat]
		if view.allRoles then
			role = view.allRoles[seat]
		end
		if out then
			table.insert(lines, if role then `Out · {roleText(role)}` else "Out")
		elseif role and view.phase == "done" then
			table.insert(lines, roleText(role))
		end
		if seat == me and view.yourRole and not out and view.phase ~= "done" then
			table.insert(lines, roleText(view.yourRole))
		end
		if view.pack and table.find(view.pack, seat) and view.phase ~= "done" then
			table.insert(lines, "🐺 Your pack")
		end
		if view.peeks and view.peeks[seat] ~= nil and view.phase ~= "done" then
			table.insert(lines, if view.peeks[seat] then "🔮 WEREWOLF!" else "🔮 Not a wolf")
		end
		if view.lastShield == seat and view.phase == "night" then
			table.insert(lines, "🛡️ Shielded last night")
		end
		if view.packPicks then
			local by = {}
			for s, t in view.packPicks do
				if t == seat then
					table.insert(by, nameOf(s))
				end
			end
			if #by > 0 then
				table.insert(lines, `🐺 {table.concat(by, ", ")} picked`)
			end
		end
		if view.yourPick == seat then
			table.insert(lines, `✓ Your pick`)
		end
		if view.witchSees == seat then
			table.insert(lines, if view.witchHeal then "🧪 Saving them" else "🐺 The wolves' victim")
		end
		if view.witchPoison == seat then
			table.insert(lines, "☠️ Poisoned")
		end
		if view.lastWords and view.lastWords.seat == seat and view.lastWords.text and view.lastWords.text ~= "" then
			table.insert(lines, `🕯️ "{view.lastWords.text}"`)
		elseif view.lastWords and view.lastWords.seat == seat and view.lastWords.hidden then
			table.insert(lines, "🕯️ (hidden by chat settings)")
		end
		if view.lastShot and view.lastShot.target == seat then
			table.insert(lines, `🏹 Taken down by {nameOf(view.lastShot.hunter)}`)
		end
		if view.statements and view.statements[seat] then
			table.insert(lines, statementText(view.statements[seat]))
		end
		if view.votes then
			local got = 0
			for _, t in view.votes do
				if t == seat then
					got += 1
				end
			end
			local cast = view.votes[seat]
			if cast ~= nil then
				table.insert(lines, if cast == 0 then "🗳 Skipped" else `🗳 → {nameOf(cast)}`)
			end
			if got > 0 then
				local badge = Kit.label(`{got}`, {
					Font = Theme.FontBold,
					TextSize = 16,
					TextColor3 = Theme.Text,
					TextXAlignment = Enum.TextXAlignment.Center,
					BackgroundTransparency = 0,
					BackgroundColor3 = Theme.Bad,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -4, 0, 4),
					Size = UDim2.fromOffset(26, 26),
					ZIndex = 6,
					Parent = card,
				})
				HudKit.pill(badge)
			end
		end

		local textX = if docked then UDim2.new(0, 0, 0, 0) else UDim2.new(0, 6, 0.5, 0)
		local nameLabel = Kit.label(nameOf(seat), {
			Font = Theme.FontBold,
			TextScaled = true,
			TextXAlignment = if docked then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
			TextColor3 = if out then Theme.SubText else Theme.Text,
			Position = textX,
			Size = if docked then UDim2.new(1, 0, 0.42, 0) else UDim2.new(1, -12, 0.17, 0),
			ZIndex = 5,
			Parent = card,
		})
		Kit.new("UITextSizeConstraint", { MaxTextSize = if compact then 14 else 18, Parent = nameLabel })
		local info = Kit.label(table.concat(lines, "\n"), {
			TextScaled = true,
			TextXAlignment = if docked then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = Theme.SubText,
			Position = if docked then UDim2.new(0, 0, 0.44, 0) else UDim2.new(0, 6, 0.68, 0),
			Size = if docked then UDim2.new(1, 0, 0.54, 0) else UDim2.new(1, -12, 0.3, 0),
			ZIndex = 5,
			Parent = card,
		})
		Kit.new("UITextSizeConstraint", { MaxTextSize = if compact then 12 else 14, Parent = info })
		if docked then
			-- Text sits right of the avatar.
			local holder = Kit.new("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 0, 0.08, 0),
				Size = UDim2.new(1, 0, 0.84, 0),
				ZIndex = 5,
				Parent = card,
			})
			Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 0), Parent = holder })
			nameLabel.Parent = holder
			info.Parent = holder
			-- Avatar width is its height (aspect 1); push the text past it.
			local function place()
				local w = avatar.AbsoluteSize.X
				holder.Position = UDim2.new(0, w + 8, 0.08, 0)
				holder.Size = UDim2.new(1, -(w + 12), 0.84, 0)
			end
			avatar:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
			place()
		end
	end

	-- Header and strip text --------------------------------------------------------------

	local function headline(view: any): (string, string)
		local phase = view.phase
		if phase == "roles" then
			return "🎭 Roles are dealt", "Read your role. Keep it secret!"
		elseif phase == "night" then
			return `🌙 Night {view.day}`, `{view.acted} of {view.aliveCount} have picked`
		elseif phase == "witch" then
			return `🌙 Night {view.day}`, "The night goes on..."
		elseif phase == "dawn" then
			local ln = view.lastNight
			if ln and ln.poisoned then
				local caught = if ln.caught then `The wolves caught {nameOf(ln.caught)}, and ` else ""
				return `☀️ Day {view.day}`, `{caught}{nameOf(ln.poisoned)} was poisoned in the night!`
			elseif ln and ln.caught then
				return `☀️ Day {view.day}`, `The wolves caught {nameOf(ln.caught)} in the night!`
			elseif ln and ln.saved then
				return `☀️ Day {view.day}`, "Someone was saved. Nobody was caught!"
			end
			return `☀️ Day {view.day}`, "Nobody was caught last night."
		elseif phase == "day" then
			return `☀️ Day {view.day}`, `Talk it over · {view.acted} of {view.aliveCount} have spoken`
		elseif phase == "vote" then
			return `🗳 Vote · Day {view.day}`, `{view.acted} of {view.aliveCount} have voted`
		elseif phase == "verdict" then
			local v = view.lastVerdict
			if v and v.out then
				local role = view.roles[v.out]
				return `🗳 Verdict · Day {view.day}`, `{nameOf(v.out)} was voted out{if role then ` · {roleText(role)}` else ""}`
			end
			return `🗳 Verdict · Day {view.day}`, "Nobody was voted out."
		elseif phase == "lastWords" then
			local seat = view.lastWords and view.lastWords.seat
			return `🕯️ Last words`, `{nameOf(seat)} gets a few last words...`
		elseif phase == "hunter" then
			return `🏹 The Hunter`, `{nameOf(view.hunterUp)} was the Hunter, and takes someone down with them!`
		end
		return if view.winner == "village" then "🎉 The village wins!" else "🐺 The werewolves win!", view.reason or ""
	end

	local function renderActions(view: any)
		Kit.clear(actionArea)
		local me = snapshot.yourSeat
		local mine = myTurn()
		local title, sub = headline(view)
		local yours = mine
		local text
		local role = view.yourRole

		if view.phase == "done" then
			text = `<b>{title}</b>  {sub}`
		elseif me == nil then
			text = `{title} · {sub}`
		elseif view.phase == "lastWords" and mine then
			text = "You were voted out. Any last words? (Everyone sees them.)"
		elseif view.phase == "hunter" and mine then
			text = "🏹 You were the Hunter! Tap a player to take down with you, or holster."
		elseif not view.youAlive then
			text = `You're out ({roleText(role)}). Watch quietly: no spoilers on voice!`
			yours = false
		elseif view.phase == "roles" then
			local info = ROLES[role]
			text = `You are the <b>{roleText(role)}</b>. {if info.team == "wolves" then "Catch villagers without being found." else "Find the werewolves!"}`
		elseif view.phase == "witch" and role == "witch" then
			text = witchLine(view)
			yours = view.witchCanAct == true
		elseif view.phase == "witch" then
			text = "The night goes on..."
		elseif view.phase == "night" then
			text = if mine then NIGHT_PROMPT[role] or "" else "Done. Waiting for the night to pass..."
			local packAlive = false
			for _, s in view.pack or {} do
				packAlive = packAlive or view.alive[s] == true
			end
			if role == "wolf" and packAlive then
				text ..= " Pack chat: only your pack sees your chat tonight."
			end
		elseif view.phase == "day" then
			text = if mine then "Make one statement. Tap a player first to name them." else "Said! Waiting for the others to speak..."
		elseif view.phase == "vote" then
			text = if mine then "Tap who to vote out, or skip." else "Voted. Waiting for the others..."
		else
			text = sub
		end
		if docked and view.phase ~= "done" then
			text = `{title} · {text}`
		end
		HudKit.statusCard(text, nil, yours, { Parent = actionArea, LayoutOrder = 1, size = if compact then 13 else 15 })

		if witchTurn() then
			buttonRow(2, witchButtons(view))
			return
		end
		if not mine then
			return
		end
		local who = if selected then nameOf(selected) else nil
		if view.phase == "lastWords" then
			local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, if compact then 32 else 36), LayoutOrder = 2, Parent = actionArea })
			local box = Kit.new("TextBox", {
				PlaceholderText = "Your last words...",
				Text = wordsDraft,
				ClearTextOnFocus = false,
				TextColor3 = Theme.Text,
				PlaceholderColor3 = Theme.SubText,
				BackgroundColor3 = Theme.PanelLight,
				Font = Theme.Font,
				TextSize = if compact then 14 else 16,
				TextXAlignment = Enum.TextXAlignment.Left,
				BorderSizePixel = 0,
				Size = UDim2.new(0.72, -6, 1, 0),
				Parent = row,
			}, { Kit.corner(10), Kit.padding(6) })
			box:GetPropertyChangedSignal("Text"):Connect(function()
				if #box.Text > 120 then
					box.Text = string.sub(box.Text, 1, 120)
				end
				wordsDraft = box.Text
			end)
			local function say()
				local text = wordsDraft
				wordsDraft = ""
				send({ kind = "lastWords", text = if text ~= "" then text else nil })
			end
			box.FocusLost:Connect(function(enter)
				if enter then
					say()
				end
			end)
			button("Say it", 1, say, { Size = UDim2.new(0.28, 0, 1, 0), Position = UDim2.new(0.72, 0, 0, 0), Parent = row })
			buttonRow(3, {
				{ text = "Stay silent", color = Theme.Panel, textColor = Theme.SubText, onClick = function()
					wordsDraft = ""
					send({ kind = "lastWords" })
				end },
			})
			return
		elseif view.phase == "hunter" then
			buttonRow(2, {
				{
					text = if who then `🏹 Take down {who}` else "Tap a player",
					color = if who then Theme.Bad else Theme.Panel,
					textColor = Theme.Text,
					onClick = function()
						if selected then
							send({ kind = "shoot", target = selected })
						end
					end,
				},
				{ text = "Holster", color = Theme.Panel, textColor = Theme.SubText, onClick = function()
					send({ kind = "shoot", target = 0 })
				end },
			})
			return
		end
		if view.phase == "night" then
			local word = ACTION_WORD[role] or "Pick"
			local isWolf = role == "wolf"
			buttonRow(2, {
				{
					text = if who then `{word} {who}` else "Tap a player",
					color = if who then (if isWolf then Theme.Bad else Theme.Accent) else Theme.Panel,
					textColor = if who and not isWolf then Theme.AccentText else Theme.Text,
					onClick = function()
						if selected then
							send({ kind = "night", target = selected })
						end
					end,
				},
			})
		elseif view.phase == "day" then
			if who then
				buttonRow(2, {
					{ text = `Suspect {who}`, onClick = function()
						if selected then
							send({ kind = "accuse", target = selected })
						end
					end },
				})
				buttonRow(3, {
					{ text = `🔮 {who} is a wolf`, color = Theme.Bad, textColor = Theme.Text, onClick = function()
						if selected then
							send({ kind = "claim", target = selected, wolf = true })
						end
					end },
					{ text = `🔮 {who} is clear`, color = Theme.Good, textColor = Theme.Text, onClick = function()
						if selected then
							send({ kind = "claim", target = selected, wolf = false })
						end
					end },
				})
			end
			buttonRow(4, {
				{ text = "Nothing to say", color = Theme.Panel, textColor = Theme.SubText, onClick = function()
					send({ kind = "pass" })
				end },
			})
		elseif view.phase == "vote" then
			buttonRow(2, {
				{
					text = if who then `Vote out {who}` else "Tap a player",
					color = if who then Theme.Bad else Theme.Panel,
					textColor = Theme.Text,
					onClick = function()
						if selected then
							send({ kind = "vote", target = selected })
						end
					end,
				},
				{ text = "Skip", color = Theme.Panel, textColor = Theme.SubText, onClick = function()
					send({ kind = "vote", target = 0 })
				end },
			})
		end
	end

	-- Sounds and the reveal pop on phase changes.
	local function onPhase(view: any)
		local phase = view.phase
		if phase == "night" then
			Audio.play("night")
		elseif phase == "dawn" then
			Audio.play("dawn")
			if view.lastNight and view.lastNight.caught then
				task.delay(0.6, Audio.play, "caught")
			end
		elseif phase == "verdict" and view.lastVerdict and view.lastVerdict.out then
			Audio.play("caught")
		elseif phase == "hunter" then
			Audio.play("caught")
		end
	end

	local autoSend: (number) -> () = function() end
	local heartbeat = RunService.Heartbeat:Connect(function()
		if not snapshot or not snapshot.turnEndsAt or not timerStart then
			fill.Size = UDim2.fromScale(0, 1)
			return
		end
		local left = snapshot.turnEndsAt - workspace:GetServerTimeNow()
		local total = math.max(0.1, snapshot.turnEndsAt - timerStart)
		fill.Size = UDim2.fromScale(math.clamp(left / total, 0, 1), 1)
		fill.BackgroundColor3 = if left < 5 then Theme.Bad else Theme.Accent
		autoSend(left)
	end)

	-- Village log --------------------------------------------------------------------
	-- Day by day: what each dawn told the village, every statement, every vote and who
	-- went out (with their role when roles are shown). A window in both views.

	local logList = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	})
	Kit.list(4).Parent = logList
	local logKey = ""

	local HOW = { night = "caught by the wolves", poison = "poisoned", vote = "voted out", hunter = "taken down by the Hunter" }

	local function buildLog(view: any)
		local key = `{#(view.nights or {})}:{#(view.history or {})}:{#(view.voteHistory or {})}:{#(view.outOrder or {})}:{view.phase == "done"}`
		if key == logKey then
			return
		end
		logKey = key
		for _, child in logList:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local order = 0
		local function line(text: string, props: { [string]: any }?)
			order += 1
			local label = Kit.label(text, {
				TextSize = 15,
				TextWrapped = true,
				RichText = true,
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, -10, 0, 18),
				LayoutOrder = order,
				Parent = logList,
			})
			for k, v in props or {} do
				(label :: any)[k] = v
			end
			return label
		end
		local function outLine(o: any)
			local role = view.roles and view.roles[o.seat]
			line(`☠️ {nameOf(o.seat)} was {HOW[o.how] or "out"}{if role then ` · {roleText(role)}` else ""}`, { TextColor3 = Theme.Bad })
		end
		local any = false
		for day = 1, view.day or 1 do
			local night
			for _, n in view.nights or {} do
				if n.day == day then
					night = n
				end
			end
			local said, votes, outs = {}, {}, {}
			for _, h in view.history or {} do
				if h.day == day then
					table.insert(said, h)
				end
			end
			for _, v in view.voteHistory or {} do
				if v.day == day then
					table.insert(votes, v)
				end
			end
			for _, o in view.outOrder or {} do
				if o.day == day then
					table.insert(outs, o)
				end
			end
			if night or #said > 0 or #votes > 0 or #outs > 0 then
				any = true
				line(`🌙 Night {day}`, { Font = Theme.FontTitle, TextSize = 18, TextColor3 = Color3.fromRGB(170, 184, 255) })
				if night and not night.caught and not night.poisoned then
					line(if night.saved then "Someone was saved. Nobody was caught." else "Nobody was caught.", { TextColor3 = Theme.SubText })
				end
				for _, o in outs do
					if o.how == "night" or o.how == "poison" then
						outLine(o)
					end
				end
				if #said > 0 or #votes > 0 then
					line(`☀️ Day {day}`, { Font = Theme.FontTitle, TextSize = 18, TextColor3 = Color3.fromRGB(255, 200, 120) })
				end
				for _, h in said do
					line(`<b>{nameOf(h.seat)}</b>  {statementText(h)}`)
				end
				if #votes > 0 then
					local byTarget, skips = {}, {}
					for _, v in votes do
						if v.target == 0 or v.target == nil then
							table.insert(skips, nameOf(v.seat))
						else
							byTarget[v.target] = byTarget[v.target] or {}
							table.insert(byTarget[v.target], nameOf(v.seat))
						end
					end
					for target = 1, view.seatCount do
						local list = byTarget[target]
						if list then
							line(`🗳 <b>{nameOf(target)}</b> ({#list}): {table.concat(list, ", ")}`)
						end
					end
					if #skips > 0 then
						line(`🗳 Skipped ({#skips}): {table.concat(skips, ", ")}`, { TextColor3 = Theme.SubText })
					end
				end
				for _, o in outs do
					if o.how ~= "night" and o.how ~= "poison" then
						outLine(o)
					end
				end
			end
		end
		if not any then
			line("Nothing yet. The log fills in as the nights and days go by.", { TextColor3 = Theme.SubText })
		end
	end

	-- The 2D view's log window.
	local logOverlay = Kit.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 25,
		Parent = root,
	})
	local logPanel = Kit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0.86, 0),
		ZIndex = 26,
		Parent = logOverlay,
	})
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(560, 640), Parent = logPanel })
	Kit.label("📜 Village log", { Font = Theme.FontTitle, TextSize = 22, Size = UDim2.new(1, -60, 0, 30), ZIndex = 27, Parent = logPanel })
	Kit.button("X", function()
		logOverlay.Visible = false
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(36, 30), ZIndex = 27, Parent = logPanel })
	local logHolder = Kit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 1, -38), ZIndex = 27, Parent = logPanel })
	logList.Parent = logHolder

	-- If the clock runs out while you have a player selected at night or in the vote,
	-- that pick goes in (you tapped, then time ran out before the button).
	local autoSent: string? = nil
	autoSend = function(left: number)
		if left > 0.6 or not selected or not snapshot then
			return
		end
		local view = snapshot.view
		local key = `{view.phase}:{view.day}`
		if autoSent == key or not myTurn() or not canPick(selected) then
			return
		end
		if view.phase == "night" then
			autoSent = key
			send({ kind = "night", target = selected })
		elseif view.phase == "vote" then
			autoSent = key
			send({ kind = "vote", target = selected })
		end
	end

	-- Table view ------------------------------------------------------------------------

	-- Your last words in Table view: a box over the bar.
	local wordsPanel = Kit.new("Frame", {
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -140),
		Size = UDim2.fromOffset(460, 56),
		Visible = false,
		ZIndex = 40,
		Parent = prompt.layer,
	}, { Kit.corner(14), Kit.stroke(Theme.Accent, 0.2, 2) })
	local wordsBox = Kit.new("TextBox", {
		PlaceholderText = "Your last words... (Enter to say them)",
		Text = "",
		ClearTextOnFocus = false,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.SubText,
		BackgroundColor3 = Theme.PanelLight,
		Font = Theme.Font,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 1, -16),
		ZIndex = 41,
		Parent = wordsPanel,
	}, { Kit.corner(10), Kit.padding(6) })
	local function sayWords()
		local text = wordsDraft
		wordsDraft = ""
		wordsBox.Text = ""
		send({ kind = "lastWords", text = if text ~= "" then text else nil })
	end
	wordsBox:GetPropertyChangedSignal("Text"):Connect(function()
		if #wordsBox.Text > 120 then
			wordsBox.Text = string.sub(wordsBox.Text, 1, 120)
		end
		wordsDraft = wordsBox.Text
	end)
	wordsBox.FocusLost:Connect(function(enter)
		if enter then
			sayWords()
		end
	end)

	openLog = function()
		if not snapshot then
			return
		end
		buildLog(snapshot.view)
		if tableMode then
			prompt.sheet(logList, "📜 Village log", function() end)
		else
			logOverlay.Visible = true
		end
	end

	local function openVillage()
		villageOpen = true
		prompt.sheet(village, "The village", function()
			villageOpen = false
			task.defer(render)
		end)
		render()
	end

	-- What floats over each lantern for you: legal picks glow, your pick is gold, and a
	-- short label says what you know or what they said today.
	local function seatLabel(view: any, seat: number): string?
		if view.witchPoison == seat then
			return "☠️"
		end
		if view.witchSees == seat then
			return if view.witchHeal then "🧪 saved" else "🐺 victim"
		end
		if view.yourPick == seat then
			return "✓"
		end
		if view.peeks and view.peeks[seat] ~= nil and view.phase ~= "done" then
			return if view.peeks[seat] then "🔮 WOLF" else "🔮 clear"
		end
		if view.pack and table.find(view.pack, seat) and view.phase ~= "done" then
			return "🐺"
		end
		if view.votes then
			local got = 0
			for _, t in view.votes do
				if t == seat then
					got += 1
				end
			end
			if got > 0 then
				return `🗳 {got}`
			end
		end
		local st = view.statements and view.statements[seat]
		if st and st.kind == "accuse" then
			return `💬 {nameOf(st.target)}?`
		elseif st and st.kind == "claim" then
			return `🔮 {nameOf(st.target)} {if st.wolf then "🐺" else "✓"}`
		end
		return nil
	end

	local function renderTable(view: any)
		if not tableMode then
			return
		end
		local me = snapshot.yourSeat
		local mine = myTurn()
		local role = view.yourRole
		local info = role and ROLES[role]
		local title, sub = headline(view)
		local villageButton = { text = "Village", color = Theme.PanelLight, onClick = openVillage }
		local logButton = { text = "📜 Log", color = Theme.PanelLight, onClick = openLog }
		wordsPanel.Visible = false

		-- Chips: your role, the phase, your pack.
		local chips = {}
		if info and view.phase ~= "done" then
			table.insert(chips, TablePrompt.chip(`You: {info.icon} {info.name}`, info.color))
		end
		table.insert(chips, TablePrompt.chip(title))
		if view.phase ~= "done" then
			table.insert(chips, TablePrompt.chip(setupText(view)))
		end
		if view.pack and #view.pack > 0 and view.phase ~= "done" then
			local names = {}
			for _, s in view.pack do
				table.insert(names, nameOf(s))
			end
			table.insert(chips, TablePrompt.chip(`🐺 Pack: {table.concat(names, ", ")}`, ROLES.wolf.color))
		end
		if view.withWitch and view.potions and role == "witch" then
			table.insert(chips, TablePrompt.chip(`{if view.potions.heal then "🧪" else ""}{if view.potions.poison then "☠️" else ""} potions`, ROLES.witch.color))
		end
		prompt.chips(`chips:{view.phase}`, chips)

		if snapshot.result or view.phase == "done" then
			prompt.bar(nil)
			prompt.ask(nil)
			return
		end

		-- The role card pops up once at the start (the Town of Salem moment).
		if view.phase == "roles" and info and revealSeen ~= snapshot.matchId then
			local line = revealText.Text
			prompt.ask(`reveal:{snapshot.matchId}`, `{info.icon} You are the {info.name}`, line, {
				{ text = "Got it", onClick = function()
					revealSeen = snapshot.matchId
					prompt.ask(nil)
					render()
				end },
			})
		else
			prompt.ask(nil)
		end

		local who = if selected then nameOf(selected) else nil
		local tapHint = "Tap a player's lantern"
		if me == nil then
			prompt.bar("watch", `{title} · {sub}`, { villageButton, logButton })
		elseif view.phase == "lastWords" and mine then
			wordsPanel.Visible = true
			wordsBox.Text = wordsDraft
			prompt.bar("words", "You were voted out. Any last words? Everyone sees them.", {
				{ text = "Say it", color = Theme.Accent, onClick = sayWords },
				{ text = "Stay silent", color = Theme.PanelLight, onClick = function()
					wordsDraft = ""
					send({ kind = "lastWords" })
				end },
			})
		elseif view.phase == "hunter" and mine then
			prompt.bar("hunter", "🏹 You were the Hunter! Tap a lantern to take someone down with you.", {
				{ text = if who then `🏹 Take down {who}` else tapHint, color = Theme.Bad, enabled = who ~= nil, onClick = function()
					if selected then
						send({ kind = "shoot", target = selected })
					end
				end },
				{ text = "Holster", color = Theme.PanelLight, onClick = function()
					send({ kind = "shoot", target = 0 })
				end },
			})
		elseif not view.youAlive then
			prompt.bar("out", `You're out ({roleText(role)}). Watch quietly: no spoilers on voice!`, { villageButton, logButton })
		elseif view.phase == "witch" and role == "witch" then
			local buttons = if witchTurn() then witchButtons(view) else {}
			table.insert(buttons, villageButton)
			prompt.bar(`witch:{if view.witchHeal then "h" else ""}{view.witchPoison or ""}{if view.witchCanAct then "a" else ""}`, witchLine(view), buttons)
		elseif view.phase == "night" and mine then
			local word = ACTION_WORD[role] or "Pick"
			local buttons = {
				{ text = if who then `{word} {who}` else tapHint, color = if role == "wolf" then Theme.Bad else Theme.Accent, enabled = who ~= nil, onClick = function()
					if selected then
						send({ kind = "night", target = selected })
					end
				end },
			}
			table.insert(buttons, villageButton)
			local line = NIGHT_PROMPT[role] or ""
			local packAlive = false
			for _, s in view.pack or {} do
				packAlive = packAlive or view.alive[s] == true
			end
			if role == "wolf" and packAlive then
				line ..= " Pack chat is on."
			end
			prompt.bar(`night:{role}`, line, buttons)
		elseif view.phase == "day" and mine then
			if who then
				prompt.bar("say", `What do you say about {who}?`, {
					{ text = `Suspect {who}`, onClick = function()
						if selected then
							send({ kind = "accuse", target = selected })
						end
					end },
					{ text = `🔮 {who} is a wolf`, color = Theme.Bad, onClick = function()
						if selected then
							send({ kind = "claim", target = selected, wolf = true })
						end
					end },
					{ text = `🔮 {who} is clear`, color = Theme.Good, onClick = function()
						if selected then
							send({ kind = "claim", target = selected, wolf = false })
						end
					end },
					{ text = "Never mind", color = Theme.PanelLight, onClick = function()
						selected = nil
						render()
					end },
				})
			else
				prompt.bar("day", "Talk it over. Tap a lantern to name someone, or pass.", {
					{ text = "Nothing to say", color = Theme.PanelLight, onClick = function()
						send({ kind = "pass" })
					end },
					villageButton,
					logButton,
				})
			end
		elseif view.phase == "vote" and mine then
			prompt.bar("vote", "Tap who to vote out, or skip. Votes are public.", {
				{ text = if who then `Vote out {who}` else tapHint, color = Theme.Bad, enabled = who ~= nil, onClick = function()
					if selected then
						send({ kind = "vote", target = selected })
					end
				end },
				{ text = "Skip", color = Theme.PanelLight, onClick = function()
					send({ kind = "vote", target = 0 })
				end },
				villageButton,
				logButton,
			})
		else
			-- Waiting, or a phase with nothing to do (dawn, verdict, someone's last words).
			local line = sub
			if view.phase == "night" or view.phase == "witch" then
				line = if view.phase == "witch" then "The night goes on..." else "Done. Waiting for the night to pass..."
			elseif view.phase == "day" then
				line = "Said! Waiting for the others to speak..."
			elseif view.phase == "vote" then
				line = "Voted. Waiting for the others..."
			elseif view.phase == "lastWords" and view.lastWords and view.lastWords.text then
				line = `🕯️ {nameOf(view.lastWords.seat)}: "{view.lastWords.text}"`
			end
			prompt.bar(`wait:{view.phase}`, line, { villageButton, logButton })
		end
	end

	render = function()
		if not snapshot then
			return
		end
		local view = snapshot.view
		local key = `{view.phase}:{view.day}`
		if key ~= lastPhaseKey then
			lastPhaseKey = key
			timerStart = workspace:GetServerTimeNow()
			selected = nil
			onPhase(view)
		end
		if selected and not canPick(selected) then
			selected = nil
		end
		buildLog(view)
		applyLayout()

		local title, sub = headline(view)
		phaseLabel.Text = title
		subLabel.Text = sub
		setupLabel.Text = if view.phase == "done" then "" else setupText(view)
		local night = view.phase == "night" or view.phase == "witch" or view.phase == "roles"
		local gradient = header:FindFirstChild("HudGradient")
		if gradient and gradient:IsA("UIGradient") then
			local tint = if night then NIGHT_TINT elseif view.phase == "done" then Theme.Panel else DAY_TINT
			gradient.Color = ColorSequence.new(tint, HudKit.shade(Theme.Panel, 0.1))
		end
		track.Visible = view.phase ~= "done"
		local role = view.yourRole and ROLES[view.yourRole]
		roleChip.Visible = role ~= nil
		if role then
			roleChip.Text = `You: {role.icon} {role.name}`
			roleChip.BackgroundColor3 = HudKit.shade(role.color, 0.45)
		end

		Kit.clear(village)
		for seat = 1, view.seatCount do
			seatCard(seat, seat)
		end
		renderActions(view)

		reveal.Visible = view.phase == "roles" and role ~= nil and not docked and not tableMode
		if view.phase == "roles" and role then -- the text also goes on the Table view card
			revealIcon.Text = role.icon
			revealName.Text = `You are the {role.name}`
			revealName.TextColor3 = role.color
			if view.yourRole == "wolf" then
				local pack = {}
				for _, s in view.pack or {} do
					table.insert(pack, nameOf(s))
				end
				revealText.Text = if #pack > 0 then `Your pack: {table.concat(pack, ", ")}. Catch villagers each night; don't get voted out.` else "You hunt alone. Catch villagers each night; don't get voted out."
			elseif view.yourRole == "seer" then
				revealText.Text = "Each night, check one player. Share what you learn, but the wolves will come for you."
			elseif view.yourRole == "guardian" then
				revealText.Text = "Each night, shield one player from the wolves."
			elseif view.yourRole == "hunter" then
				revealText.Text = "No power at night, but if you go out, you take someone down with you. Choose well."
			elseif view.yourRole == "witch" then
				revealText.Text = "Two potions, once each: after the night picks you see who the wolves went for. Save them, poison someone, or both."
			else
				revealText.Text = "No power at night. Listen, talk, and vote out the werewolves."
			end
		end
		renderTable(view)
	end

	local destroyed = false
	Layout.onChange(function(info)
		if not destroyed and info.compact ~= compact then
			compact = info.compact
			render()
		end
	end)

	return {
		update = function(newSnapshot: any)
			if newSnapshot.matchId ~= lastMatchId then
				lastMatchId = newSnapshot.matchId
				selected = nil
				lastPhaseKey = ""
			end
			snapshot = newSnapshot
			render()
		end,
		setDocked = function(value: boolean)
			if docked ~= value then
				docked = value
				render()
			end
		end,
		setTableMode = function(value: boolean)
			if value == tableMode then
				return
			end
			tableMode = value
			root.Visible = not value
			prompt.setVisible(value)
			wordsPanel.Visible = false
			villageOpen = false
			render()
		end,
		-- Table view (Table3D/SceneTap): each player's lantern is "seat:N".
		canTap = function(id: any): boolean
			local seat = type(id) == "string" and tonumber(string.match(id, "^seat:(%d+)$"))
			return snapshot ~= nil and seat ~= nil and canPick(seat)
		end,
		tapTable = function(id: any)
			local seat = type(id) == "string" and tonumber(string.match(id, "^seat:(%d+)$"))
			if snapshot and seat and canPick(seat) then
				selected = if selected == seat then nil else seat
				Audio.play("cardHover")
				render()
			end
		end,
		tableMarks = function(): { [any]: any }?
			if not (tableMode and snapshot) then
				return nil
			end
			local view = snapshot.view
			local marks = {}
			for seat = 1, view.seatCount do
				local text = seatLabel(view, seat)
				local id = `seat:{seat}`
				if selected == seat then
					marks[id] = { kind = "picked", text = text or "" }
				elseif canPick(seat) then
					marks[id] = { kind = "target", text = text or "" }
				elseif text then
					marks[id] = { kind = "label", text = text }
				end
			end
			return marks
		end,
		destroy = function()
			destroyed = true
			heartbeat:Disconnect()
			root:Destroy()
		end,
	}
end

return Werewolf
