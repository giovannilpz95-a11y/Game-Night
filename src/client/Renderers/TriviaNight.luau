-- Trivia Night: the question, a draining timer bar and four big answer buttons (2x2, so
-- they work on phones). After the reveal: the right answer glows, yours shows if it was
-- wrong, and your points pop up.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Parent.UI.Kit)
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
		button.Activated:Connect(function()
			local view = snapshot and snapshot.view
			local voting = view and view.phase == "pick"
			if view and (view.phase == "question" or voting) and view.yourAnswer == nil and view.answers and view.answers[i] and table.find(snapshot.activeSeats, snapshot.yourSeat) then
				sendMove({ kind = if voting then "pick" else "answer", choice = i })
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

	local function render()
		local view = snapshot.view
		local phaseKey = `{view.phase}:{view.number}`
		if phaseKey ~= lastPhaseKey then
			lastPhaseKey = phaseKey
			timerStart = workspace:GetServerTimeNow()
			if view.phase == "question" or view.phase == "pick" then
				-- Pop the new question in.
				question.TextTransparency = 1
				TweenService:Create(question, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
			end
			-- A vote just picked the category: say so.
			if view.phase == "question" and wasPick and view.pickedCategory then
				HudKit.callout(container:FindFirstAncestorWhichIsA("ScreenGui") or root, `🎯 {string.upper(view.pickedCategory)}!`, Theme.Accent)
			end
			wasPick = view.phase == "pick"
		end

		counter.Text = if view.phase == "done" then "" else `Question {view.number} of {view.total}`
		category.Text = if view.category then string.upper(view.category) else ""
		if view.streak and view.streak >= 2 then
			category.Text ..= `   🔥 {view.streak} in a row`
		end

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
					mine = (if gained > 0 then `+{gained}` else "Wrong") .. "   "
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
		destroy = function()
			heartbeat:Disconnect()
			root:Destroy()
		end,
	}
end

return TriviaNight
