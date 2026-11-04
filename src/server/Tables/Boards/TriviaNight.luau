-- Trivia Night at the table: a four-sided screen over the table shows the question and
-- the four answers to the whole room, then lights up the right one at the reveal.
-- Answering stays in each player's 2D view.

local Models = require(script.Parent.Parent.Models)
local Scene = require(script.Parent.Parent.Scene)

local TriviaNight = {}

local LETTERS = { "A", "B", "C", "D" }
local ANSWER_COLORS = {
	Color3.fromRGB(235, 87, 87),
	Color3.fromRGB(54, 162, 235),
	Color3.fromRGB(255, 196, 64),
	Color3.fromRGB(88, 204, 120),
}

-- A game-show buzzer in the seat's color, in front of each player.
local function buzzer(parent: Instance, cf: CFrame, color: Color3)
	Models.cyl(parent, "BuzzerBase", 0.95, 0.14, cf, Models.WALNUT, Enum.Material.Wood)
	Models.cyl(parent, "BuzzerRing", 0.74, 0.05, cf * CFrame.new(0, 0.14, 0), Models.GOLD)
	Models.egg(parent, "BuzzerDome", Vector3.new(0.6, 0.34, 0.6), cf * CFrame.new(0, 0.2, 0), color)
end

function TriviaNight.create(boardCF: CFrame, parent: Instance, layout: Scene.Layout)
	local model = Instance.new("Model")
	model.Name = "GameBoard"
	local _, faces = Scene.jumbotron(model, boardCF, 3.4)
	for seat in layout.seats do
		buzzer(model, Scene.seatSpot(boardCF, layout, seat, 0.8), Scene.SEAT_COLORS[seat] or Models.GOLD)
	end
	model.Parent = parent

	local function fill(frame: Frame, view: any)
		frame:ClearAllChildren()
		local reveal = view.phase == "reveal"
		if view.phase == "done" then
			Scene.screenText(frame, "Final scores!", UDim2.fromScale(0.05, 0.35), UDim2.fromScale(0.9, 0.3))
			return
		end
		Scene.screenText(frame, `{view.category or "Trivia"} · {view.number or 0}/{view.total or 0}`, UDim2.fromScale(0.04, 0.03), UDim2.fromScale(0.92, 0.1), { TextColor3 = Color3.fromRGB(176, 170, 204) })
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
			Scene.screenText(box, `{LETTERS[i]}  {answer}`, UDim2.fromScale(0.04, 0.08), UDim2.fromScale(0.92, 0.84), { TextColor3 = Color3.fromRGB(24, 22, 38) })
		end
	end

	return {
		model = model,
		update = function(view: any, _snapshot: any)
			for _, frame in faces do
				fill(frame, view)
			end
		end,
		destroy = function()
			model:Destroy()
		end,
	}
end

return TriviaNight
