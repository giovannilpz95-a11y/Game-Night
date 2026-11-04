-- Werewolf: a header with the phase (🌙 night / ☀️ day / 🗳 vote), a draining timer and
-- your secret role; the village as a grid of player cards (tap one to pick them); and
-- the "what now" strip with the buttons for this phase.
--
-- Cards show what each seat said today, the open votes, who is out, and what only you
-- know (your packmates as a wolf, your checks as the Seer, your last shield as the
-- Guardian). In Table view the screen over the table shows the phase, so the dock keeps
-- one row of cards and the buttons.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Games.Werewolf)
local Kit = require(script.Parent.Parent.UI.Kit)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local Layout = require(script.Parent.Parent.UI.Layout)
local Audio = require(script.Parent.Parent.Audio)
local Theme = Kit.Theme

local Werewolf = {}

local ROLES = Rules.ROLES
local NIGHT_TINT = Color3.fromRGB(36, 40, 86)
local DAY_TINT = Color3.fromRGB(120, 84, 40)

local ACTION_WORD = { wolf = "Catch", seer = "Check", guardian = "Shield", villager = "Hunch:" }
local NIGHT_PROMPT = {
	wolf = "Pick a villager for the pack to catch.",
	seer = "Pick a player to check. You'll learn if they're a werewolf.",
	guardian = "Pick a player to shield tonight.",
	villager = "Everyone taps someone at night. Pick who you suspect.",
}

function Werewolf.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local selected: number? = nil
	local docked = false
	local compact = Layout.get().compact
	local lastPhaseKey = ""
	local timerStart: number? = nil
	local lastMatchId: string? = nil

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })

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
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.new(0.36, -12, 0, 36),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = header,
	})
	HudKit.pill(roleChip)
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

	local function canPick(seat: number): boolean
		local view = snapshot.view
		return myTurn() and view.targets ~= nil and table.find(view.targets, seat) ~= nil
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
		if docked then
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
		card.Activated:Connect(function()
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
		elseif phase == "dawn" then
			local ln = view.lastNight
			if ln and ln.caught then
				return `☀️ Day {view.day}`, `The wolves caught {nameOf(ln.caught)} in the night!`
			elseif ln and ln.saved then
				return `☀️ Day {view.day}`, "The Guardian saved someone. Nobody was caught!"
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
		elseif not view.youAlive then
			text = `You're out ({roleText(role)}). Watch quietly: no spoilers on voice!`
			yours = false
		elseif view.phase == "roles" then
			local info = ROLES[role]
			text = `You are the <b>{roleText(role)}</b>. {if info.team == "wolves" then "Catch villagers without being found." else "Find the werewolves!"}`
		elseif view.phase == "night" then
			text = if mine then NIGHT_PROMPT[role] or "" else "Done. Waiting for the night to pass..."
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

		if not mine then
			return
		end
		local who = if selected then nameOf(selected) else nil
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
		end
	end

	local heartbeat = RunService.Heartbeat:Connect(function()
		if not snapshot or not snapshot.turnEndsAt or not timerStart then
			fill.Size = UDim2.fromScale(0, 1)
			return
		end
		local left = snapshot.turnEndsAt - workspace:GetServerTimeNow()
		local total = math.max(0.1, snapshot.turnEndsAt - timerStart)
		fill.Size = UDim2.fromScale(math.clamp(left / total, 0, 1), 1)
		fill.BackgroundColor3 = if left < 5 then Theme.Bad else Theme.Accent
	end)

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
		applyLayout()

		local title, sub = headline(view)
		phaseLabel.Text = title
		subLabel.Text = sub
		local night = view.phase == "night" or view.phase == "roles"
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

		reveal.Visible = view.phase == "roles" and role ~= nil and not docked
		if reveal.Visible and role then
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
			else
				revealText.Text = "No power at night. Listen, talk, and vote out the werewolves."
			end
		end
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
		destroy = function()
			destroyed = true
			heartbeat:Disconnect()
			root:Destroy()
		end,
	}
end

return Werewolf
