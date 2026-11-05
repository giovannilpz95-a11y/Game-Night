-- Trivia Night at the table: a four-sided screen over the table shows the question and
-- the four answers to the whole room, then lights up the right one at the reveal.
-- Answers are tapped in each player's own view (docked under the table in Table view).
-- Each seat's buzzer lights up when that player locks in an answer, and turns green or
-- red at the reveal.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage.Shared.Games.TriviaNight)
local Models = require(script.Parent.Parent.Models)
local Scene = require(script.Parent.Parent.Scene)

local TriviaNight = {}

local LETTERS = Rules.ANSWER_LETTERS
local ANSWER_COLORS = Rules.ANSWER_COLORS
local RIGHT = Color3.fromRGB(88, 204, 120)
local WRONG = Color3.fromRGB(220, 60, 60)

-- A game-show buzzer in the seat's color, in front of each player. Returns the dome.
local function buzzer(parent: Instance, cf: CFrame, color: Color3): BasePart
	Models.cyl(parent, "BuzzerBase", 0.95, 0.14, cf, Models.WALNUT, Enum.Material.Wood)
	Models.cyl(parent, "BuzzerRing", 0.74, 0.05, cf * CFrame.new(0, 0.14, 0), Models.GOLD)
	return Models.egg(parent, "BuzzerDome", Vector3.new(0.6, 0.34, 0.6), cf * CFrame.new(0, 0.2, 0), color)
end

function TriviaNight.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	local model = Instance.new("Model")
	model.Name = "GameBoard"
	local _, faces = Scene.jumbotron(model, boardCF, 3.4)
	local domes: { [number]: { part: BasePart, color: Color3, cf: CFrame } } = {}
	for seat in layout.seats do
		local color = Scene.SEAT_COLORS[seat] or Models.GOLD
		local dome = buzzer(model, Scene.seatSpot(boardCF, layout, seat, 0.8), color)
		domes[seat] = { part = dome, color = color, cf = dome.CFrame }
	end

	-- Up and glowing once that seat has answered; green or red at the reveal.
	local function lightBuzzers(view: any)
		local answered = {}
		for _, seat in view.answeredSeats or {} do
			answered[seat] = true
		end
		for seat, dome in domes do
			local part = dome.part
			local choice = view.answersBySeat and view.answersBySeat[seat]
			if view.phase == "reveal" and choice ~= nil then
				part.Color = if choice == view.correct then RIGHT else WRONG
				part.Material = Enum.Material.Neon
				part.CFrame = dome.cf
			elseif view.phase == "question" and answered[seat] then
				part.Color = dome.color
				part.Material = Enum.Material.Neon
				part.CFrame = dome.cf * CFrame.new(0, -0.08, 0) -- pressed in
			else
				part.Color = dome.color
				part.Material = Enum.Material.SmoothPlastic
				part.CFrame = dome.cf
			end
		end
	end
	model.Parent = parent

	-- Seats by score, best first, with names from the snapshot.
	local function standings(view: any, snapshot: any): { { name: string, score: number, seat: number } }
		local list = {}
		for seat, score in view.scores or {} do
			local info = snapshot and snapshot.seats and snapshot.seats[seat]
			table.insert(list, { seat = seat, score = score, name = if info and info.name then info.name else `Seat {seat}` })
		end
		table.sort(list, function(a, b)
			if a.score ~= b.score then
				return a.score > b.score
			end
			return a.seat < b.seat
		end)
		return list
	end
	local MEDALS = { "🥇", "🥈", "🥉" }

	local function fill(frame: Frame, view: any, snapshot: any)
		frame:ClearAllChildren()
		local reveal = view.phase == "reveal"
		if view.phase == "done" then
			-- The podium: the game-show finish, top three big, everyone else under them.
			Scene.screenText(frame, "Final scores!", UDim2.fromScale(0.05, 0.03), UDim2.fromScale(0.9, 0.14), { TextColor3 = Color3.fromRGB(255, 214, 90) })
			local list = standings(view, snapshot)
			local heights = { 0.5, 0.36, 0.26 }
			local xs = { 0.36, 0.06, 0.66 }
			for place = 1, math.min(3, #list) do
				local entry = list[place]
				local step = Instance.new("Frame")
				step.AnchorPoint = Vector2.new(0, 1)
				step.Position = UDim2.fromScale(xs[place], 0.98)
				step.Size = UDim2.fromScale(0.28, heights[place])
				step.BorderSizePixel = 0
				step.BackgroundColor3 = Scene.SEAT_COLORS[entry.seat] or Models.GOLD
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0, 8)
				corner.Parent = step
				step.Parent = frame
				Scene.screenText(step, `{MEDALS[place]}\n{entry.score}`, UDim2.fromScale(0.05, 0.05), UDim2.fromScale(0.9, 0.9), { TextColor3 = Color3.fromRGB(24, 22, 38) })
				Scene.screenText(frame, entry.name, UDim2.fromScale(xs[place], 0.98 - heights[place] - 0.12), UDim2.fromScale(0.28, 0.1))
			end
			return
		end
		local top = `{view.category or "Trivia"} · {view.number or 0}/{view.total or 0}`
		if reveal then
			-- Between questions the top line becomes the leaderboard.
			local parts = {}
			for place, entry in standings(view, snapshot) do
				if place > 3 then
					break
				end
				table.insert(parts, `{MEDALS[place]} {entry.name} {entry.score}`)
			end
			top = table.concat(parts, "   ")
		end
		Scene.screenText(frame, top, UDim2.fromScale(0.04, 0.03), UDim2.fromScale(0.92, 0.1), { TextColor3 = if reveal then Color3.fromRGB(255, 214, 90) else Color3.fromRGB(176, 170, 204) })
		Scene.screenText(frame, view.question or "", UDim2.fromScale(0.04, 0.14), UDim2.fromScale(0.92, 0.34))
		for i, answer in view.answers or {} do
			local col, row = (i - 1) % 2, (i - 1) // 2
			local box = Instance.new("Frame")
			box.Position = UDim2.fromScale(0.04 + col * 0.47, 0.52 + row * 0.23)
			box.Size = UDim2.fromScale(0.45, 0.2)
			box.BorderSizePixel = 0
			local right = reveal and view.correct == i
			box.BackgroundColor3 = if reveal and not right then ANSWER_COLORS[i]:Lerp(Color3.new(0, 0, 0), 0.6) else ANSWER_COLORS[i]
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 10)
			corner.Parent = box
			if right then
				local stroke = Instance.new("UIStroke")
				stroke.Color = Color3.new(1, 1, 1)
				stroke.Thickness = 4
				stroke.Parent = box
			end
			box.Parent = frame
			-- At the reveal every answer shows how many picked it.
			local picked = 0
			if reveal then
				for _, choice in view.answersBySeat or {} do
					if choice == i then
						picked += 1
					end
				end
			end
			Scene.screenText(box, `{LETTERS[i]}  {answer}`, UDim2.fromScale(0.04, 0.08), UDim2.fromScale(if reveal then 0.72 else 0.92, 0.84), { TextColor3 = Color3.fromRGB(24, 22, 38) })
			if reveal then
				Scene.screenText(box, `👤{picked}`, UDim2.fromScale(0.76, 0.12), UDim2.fromScale(0.22, 0.76), { TextColor3 = Color3.fromRGB(24, 22, 38) })
			end
		end
	end

	return {
		model = model,
		update = function(view: any, snapshot: any)
			for _, frame in faces do
				fill(frame, view, snapshot)
			end
			lightBuzzers(view)
		end,
		destroy = function()
			model:Destroy()
		end,
	}
end

return TriviaNight
