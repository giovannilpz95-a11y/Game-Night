-- Trivia Night: the question, a draining timer bar and four big answer buttons (2x2, so
-- they work on phones). After the reveal: the right answer glows, yours shows if it was
-- wrong, and your points pop up.
--
-- Table view (setTableMode): no panel. The screen over the table shows the question,
-- the answers and the clock to the room. You lock in by tapping one of your four answer
-- pads on the table (legal pads glow) or a colored button in the bar along the bottom;
-- the line above it repeats the question, then says how you did at the reveal.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Parent.UI.Kit)
local TablePrompt = require(script.Parent.Parent.UI.TablePrompt)
local Audio = require(script.Parent.Parent.Audio)
local HudKit = require(script.Parent.Parent.UI.HudKit)
local Rules = require(ReplicatedStorage.Shared.Games.TriviaNight)
local Theme = Kit.Theme

local TriviaNight = {}

-- Same letters and colors as the screen over the table.
local ANSWER_COLORS = Rules.ANSWER_COLORS
local LETTERS = Rules.ANSWER_LETTERS

function TriviaNight.create(container: Frame, sendMove: (any) -> ())
	local snapshot: any = nil
	local timerStart: number? = nil

	local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
	local tableMode = false
	local prompt = TablePrompt.new(container)
	prompt.setVisible(false)
	local pending: number? = nil -- the answer you just tapped, until the server confirms

	-- Can you lock in answer i right now?
	local function canAnswer(i: number): boolean
		local view = snapshot and snapshot.view
		return view ~= nil
			and (view.phase == "question" or view.phase == "pick")
			and view.yourAnswer == nil
			and pending == nil
			and view.answers ~= nil
			and view.answers[i] ~= nil
			and snapshot.yourSeat ~= nil
			and table.find(snapshot.activeSeats, snapshot.yourSeat) ~= nil
	end

	local function answer(i: number)
		if not canAnswer(i) then
			return
		end
		local view = snapshot.view
		pending = i
		sendMove({ kind = if view.phase == "pick" then "pick" else "answer", choice = i })
	end

	local top = Kit.panel({ Size = UDim2.new(1, 0, 0.36, 0), Parent = root })
	local category = Kit.label("", {
		TextSize = 15,
		Font = Theme.FontBold,
		TextColor3 = Theme.Accent,
		Size = UDim2.new(0.6, 0, 0, 20),
		Parent = top,
	})
	local counter = Kit.label("", {
		TextSize = 15,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(0.4, 0, 0, 20),
		Position = UDim2.new(0.6, 0, 0, 0),
		Parent = top,
	})
	local question = Kit.label("", {
		TextSize = 28,
		Font = Theme.FontTitle,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextScaled = true,
		Size = UDim2.new(1, 0, 1, -56),
		Position = UDim2.new(0, 0, 0, 24),
		Parent = top,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 34, MinTextSize = 14, Parent = question })

	local track = Kit.new("Frame", {
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 10),
		Position = UDim2.new(0, 0, 1, -14),
		Parent = top,
	}, { Kit.corner(5) })
	local fill = Kit.new("Frame", {
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = track,
	}, { Kit.corner(5) })

	local grid = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0.5, 0),
		Position = UDim2.new(0, 0, 0.39, 0),
		Parent = root,
	})
	local gridLayout = Kit.new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -6, 0.5, -6),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})

	local buttons: { TextButton } = {}
	local answerLabels: { TextLabel } = {}
	local pointsLabels: { TextLabel } = {}
	for i = 1, 4 do
		local button = Kit.new("TextButton", {
			Text = "",
			AutoButtonColor = true,
			BackgroundColor3 = ANSWER_COLORS[i],
			BorderSizePixel = 0,
			LayoutOrder = i,
			Parent = grid,
		}, { Kit.corner(14) })
		Kit.label(LETTERS[i], {
			TextSize = 26,
			Font = Theme.FontBold,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(0, 48, 1, 0),
			Parent = button,
		})
		local text = Kit.label("", {
			TextSize = 22,
			Font = Theme.FontBold,
			TextColor3 = Color3.new(1, 1, 1),
			TextScaled = true,
			Size = UDim2.new(1, -64, 1, -16),
			Position = UDim2.new(0, 48, 0, 8),
			Parent = button,
		})
		Kit.new("UITextSizeConstraint", { MaxTextSize = 24, MinTextSize = 12, Parent = text })
		local points = Kit.label("", {
			TextSize = 18,
			Font = Theme.FontBold,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.new(0, 120, 0, 24),
			Position = UDim2.new(1, -128, 0, 6),
			Parent = button,
		})
		Kit.new("UIStroke", { Name = "Ring", Color = Color3.new(1, 1, 1), Thickness = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = button })
		Kit.onPress(button, function()
			if canAnswer(i) then
				answer(i)
				-- Show the pick right away; the server confirms with the next snapshot.
				for j, b in buttons do
					b.BackgroundTransparency = if j == i then 0 else 0.6
				end
			end
		end)
		buttons[i] = button
		answerLabels[i] = text
		pointsLabels[i] = points
	end

	local footer = Kit.label("", {
		TextSize = 16,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.new(0, 0, 0.92, 0),
		Parent = root,
	})

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

	local lastPhaseKey = ""
	local wasPick = false
	local isDocked = false

	local function placeText(view: any): string?
		if not view.place then
			return nil
		end
		local ahead = view.ahead and snapshot.seats[view.ahead]
		if view.place == 1 then
			return "You're 1st!"
		elseif ahead then
			return `You're {Rules.ordinal(view.place)}, {view.gap} behind {ahead.name}`
		end
		return `You're {Rules.ordinal(view.place)}`
	end

	-- How many seats picked answer i (votes in a category vote, picks at the reveal).
	local function countFor(view: any, i: number): number
		local tally = if view.phase == "pick" then view.votesBySeat elseif view.phase == "reveal" then view.answersBySeat else nil
		local n = 0
		for _, choice in tally or {} do
			if choice == i then
				n += 1
			end
		end
		return n
	end

	local function renderTable(view: any)
		if not tableMode then
			return
		end
		local chips = {}
		if view.phase ~= "done" then
			local cat = if view.category then string.upper(view.category) else "TRIVIA"
			table.insert(chips, TablePrompt.chip(`{cat} · {view.number}/{view.total}`))
			if view.streak and view.streak >= 2 then
				table.insert(chips, TablePrompt.chip(`🔥 {view.streak} in a row`, Theme.Bad))
			end
			local me = snapshot.yourSeat
			if me and view.scores and view.scores[me] then
				table.insert(chips, TablePrompt.chip(`⭐ {view.scores[me]} pts`, Theme.Accent))
			end
			local place = placeText(view)
			if place and view.phase ~= "pick" then
				table.insert(chips, TablePrompt.chip(place))
			end
		end
		prompt.chips(`chips:{view.phase}:{view.number}`, chips)
		prompt.ask(nil)

		if snapshot.result or view.phase == "done" then
			prompt.bar(nil)
			return
		end
		local me = snapshot.yourSeat
		local count = if view.answers then #view.answers else 0
		local mine = view.yourAnswer or pending
		if view.phase == "question" or view.phase == "pick" then
			local voting = view.phase == "pick"
			local buttons = {}
			if me and mine == nil and table.find(snapshot.activeSeats, me) then
				for i = 1, count do
					local votes = if voting then countFor(view, i) else 0
					table.insert(buttons, {
						text = `{LETTERS[i]}  {view.answers[i]}{if votes > 0 then `  🗳{votes}` else ""}`,
						color = ANSWER_COLORS[i],
						onClick = function()
							answer(i)
						end,
					})
				end
			end
			local line
			if me == nil then
				line = view.question or ""
			elseif mine ~= nil then
				line = `🔒 {LETTERS[mine]}  {view.answers and view.answers[mine] or ""} · {view.answeredCount} of {#snapshot.seats} {if voting then "voted" else "answered"}`
			else
				line = if voting then `🎯 {view.question}` else view.question or ""
			end
			prompt.bar(`{view.phase}:{view.number}:{mine or ""}`, line, buttons)
		elseif view.phase == "reveal" then
			local line
			local right = view.correct and view.answers and view.answers[view.correct] or ""
			if me == nil then
				line = `✓ {LETTERS[view.correct or 1] or ""}  {right}`
			elseif view.yourAnswer == nil then
				line = `⏰ Out of time · it was {LETTERS[view.correct or 1] or ""}  {right}`
			else
				local gained = view.lastPoints and view.lastPoints[me] or 0
				if view.yourAnswer == view.correct then
					line = `✅ Right! +{gained}`
				else
					line = `❌ It was {LETTERS[view.correct or 1] or ""}  {right}{if gained < 0 then `  ({gained})` else ""}`
				end
			end
			prompt.bar(`reveal:{view.number}`, line, {})
		else
			prompt.bar(nil)
		end
	end

	local function render()
		local view = snapshot.view
		local phaseKey = `{view.phase}:{view.number}`
		if phaseKey ~= lastPhaseKey then
			lastPhaseKey = phaseKey
			pending = nil
			if tableMode and view.phase == "reveal" and snapshot.yourSeat and view.yourAnswer ~= nil then
				Audio.play(if view.yourAnswer == view.correct then "win" else "lose")
			end
			timerStart = workspace:GetServerTimeNow()
			if view.phase == "question" or view.phase == "pick" then
				-- Pop the new question in.
				question.TextTransparency = 1
				TweenService:Create(question, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
			end
			-- A vote just picked the category: say so.
			if view.phase == "question" and wasPick and view.pickedCategory then
				HudKit.callout((if Kit.inPreview(container) then nil else container:FindFirstAncestorWhichIsA("ScreenGui")) or root, `🎯 {string.upper(view.pickedCategory)}!`, Theme.Accent)
			end
			wasPick = view.phase == "pick"
			-- Table view hides the footer, so the place pops up once per reveal instead.
			local place = placeText(view)
			if view.phase == "reveal" and (isDocked or tableMode) and place then
				HudKit.callout((if Kit.inPreview(container) then nil else container:FindFirstAncestorWhichIsA("ScreenGui")) or root, place, Theme.Accent)
			end
		end

		counter.Text = if view.phase == "done" then "" else `Question {view.number} of {view.total}`
		category.Text = if view.category then string.upper(view.category) else ""
		if view.streak and view.streak >= 2 then
			category.Text ..= `   🔥 {view.streak} in a row`
		end

		if view.yourAnswer ~= nil then
			pending = nil
		end
		renderTable(view)

		if view.phase == "done" then
			question.Text = "That's the game!"
			grid.Visible = false
			track.Visible = false
			footer.Text = ""
			return
		end
		grid.Visible = true
		track.Visible = view.phase == "question" or view.phase == "pick"
		question.Text = view.question or ""

		local reveal = view.phase == "reveal"
		for i, button in buttons do
			answerLabels[i].Text = view.answers and view.answers[i] or ""
			button.Visible = view.answers ~= nil and view.answers[i] ~= nil
			local ring = button:FindFirstChild("Ring") :: UIStroke
			local isCorrect = reveal and view.correct == i
			local isMine = view.yourAnswer == i
			if reveal then
				button.BackgroundTransparency = if isCorrect then 0 else 0.7
				ring.Thickness = if isCorrect then 5 elseif isMine then 3 else 0
				ring.Color = if isCorrect then Theme.Good else Theme.Bad
			elseif view.yourAnswer ~= nil then
				button.BackgroundTransparency = if isMine then 0 else 0.6
				ring.Thickness = if isMine then 4 else 0
				ring.Color = Color3.new(1, 1, 1)
			else
				button.BackgroundTransparency = 0
				ring.Thickness = 0
			end
			pointsLabels[i].Text = ""
			if view.phase == "pick" then
				local votes = 0
				for _, choice in view.votesBySeat or {} do
					if choice == i then
						votes += 1
					end
				end
				pointsLabels[i].Text = if votes > 0 then `🗳 {votes}` else ""
			end
			if reveal then
				-- How many picked each answer (the classic quiz-show reveal), plus your points.
				local picked = 0
				for _, choice in view.answersBySeat or {} do
					if choice == i then
						picked += 1
					end
				end
				local mine = ""
				if isMine and snapshot.yourSeat then
					local gained = view.lastPoints and view.lastPoints[snapshot.yourSeat] or 0
					mine = (if gained > 0 then `+{gained}` elseif gained < 0 then `Wrong {gained}` else "Wrong") .. "   "
				end
				pointsLabels[i].Text = `{mine}👤 {picked}`
			end
		end

		if reveal then
			local right = 0
			for _, choice in view.answersBySeat or {} do
				if choice == view.correct then
					right += 1
				end
			end
			footer.Text = `{right} of {#snapshot.seats} got it right`
			if snapshot.yourSeat and view.yourAnswer == nil then
				footer.Text ..= "  (you ran out of time)"
			end
			local place = placeText(view)
			if place then
				footer.Text ..= `   ·   {place}`
			end
		elseif view.phase == "pick" then
			footer.Text = `{view.answeredCount} of {#snapshot.seats} voted`
		else
			footer.Text = `{view.answeredCount} of {#snapshot.seats} answered`
		end
	end

	return {
		update = function(newSnapshot: any)
			snapshot = newSnapshot
			render()
		end,
		-- Table view: the screen over the table shows the question, so the dock gets just
		-- the four answers in one row.
		setDocked = function(docked: boolean)
			isDocked = docked
			top.Visible = not docked
			footer.Visible = not docked
			if docked then
				grid.Position = UDim2.new(0, 6, 1, -6)
				grid.AnchorPoint = Vector2.new(0, 1)
				grid.Size = UDim2.new(1, -12, 0.24, -12)
				gridLayout.CellSize = UDim2.new(0.25, -9, 1, 0)
			else
				grid.Position = UDim2.new(0, 0, 0.39, 0)
				grid.AnchorPoint = Vector2.new(0, 0)
				grid.Size = UDim2.new(1, 0, 0.5, 0)
				gridLayout.CellSize = UDim2.new(0.5, -6, 0.5, -6)
			end
		end,
		setTableMode = function(value: boolean)
			if value == tableMode then
				return
			end
			tableMode = value
			root.Visible = not value
			prompt.setVisible(value)
			if snapshot then
				render()
			end
		end,
		-- Table view (Table3D/SceneTap): your answer pads are "ans:<seat>:<n>".
		canTap = function(id: any): boolean
			local seat, i = nil, nil
			if type(id) == "string" then
				local a, b = string.match(id, "^ans:(%d+):(%d+)$")
				seat, i = tonumber(a), tonumber(b)
			end
			return snapshot ~= nil and seat ~= nil and i ~= nil and seat == snapshot.yourSeat and canAnswer(i)
		end,
		tapTable = function(id: any)
			local a, b = string.match(if type(id) == "string" then id else "", "^ans:(%d+):(%d+)$")
			local seat, i = tonumber(a), tonumber(b)
			if snapshot and seat == snapshot.yourSeat and i and canAnswer(i) then
				answer(i)
				Audio.play("cardHover")
				render()
			end
		end,
		tableMarks = function(): { [any]: any }?
			if not (tableMode and snapshot) then
				return nil
			end
			local me = snapshot.yourSeat
			local view = snapshot.view
			local marks = {}
			if me and view.answers then
				local mine = view.yourAnswer or pending
				for i = 1, #view.answers do
					local id = `ans:{me}:{i}`
					if mine == i then
						marks[id] = "picked"
					elseif canAnswer(i) then
						marks[id] = "target"
					end
				end
			end
			return marks
		end,
		destroy = function()
			heartbeat:Disconnect()
			prompt.layer:Destroy()
			root:Destroy()
		end,
	}
end

return TriviaNight
