-- Picking with the keyboard at the table, side by side with the mouse: A / D or the
-- Left / Right arrows move between the things you can pick (the cards in your hand, the
-- squares of a board, the spots on a table scene), W / S or Up / Down move across a board,
-- and Enter plays the one picked. Hovering with the mouse (or the crosshair, mouse
-- locked) picks too: whichever moved last wins. (Giovanni, 2026-11-15: "either or".)
--
-- Things you can pick register a source. The one with the highest priority that has any
-- choices right now gets the keys; when none does, the keys pass through untouched.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SeatLook = require(ReplicatedStorage.Shared.SeatLook)

local KeyPick = {}

-- Higher wins. Cards in your hand beat the board and the table scene.
KeyPick.HAND = 3
KeyPick.BOARD = 2
KeyPick.SCENE = 1

export type Choice = { key: any, x: number, y: number } -- x, y: where it is on screen
export type Source = {
	priority: number,
	ordered: boolean?, -- a row in order (a hand): left and right cycle, up and down pass
	choices: () -> { Choice },
	current: () -> any, -- the key picked now (by keys or the mouse), or nil
	select: (key: any) -> (),
	confirm: (key: any) -> (),
}

local ACTION = "GameNightKeyPick"
local DIRECTIONS: { [Enum.KeyCode]: Vector2 } = {
	[Enum.KeyCode.A] = Vector2.new(-1, 0),
	[Enum.KeyCode.Left] = Vector2.new(-1, 0),
	[Enum.KeyCode.D] = Vector2.new(1, 0),
	[Enum.KeyCode.Right] = Vector2.new(1, 0),
	[Enum.KeyCode.W] = Vector2.new(0, -1),
	[Enum.KeyCode.Up] = Vector2.new(0, -1),
	[Enum.KeyCode.S] = Vector2.new(0, 1),
	[Enum.KeyCode.Down] = Vector2.new(0, 1),
}
local CONFIRM = { [Enum.KeyCode.Return] = true, [Enum.KeyCode.KeypadEnter] = true }

local sources: { Source } = {}
local enabled = false

-- Adds a source; returns the function that removes it again.
function KeyPick.add(source: Source): () -> ()
	table.insert(sources, source)
	return function()
		local i = table.find(sources, source)
		if i then
			table.remove(sources, i)
		end
	end
end

-- The source that gets the keys now and its choices.
local function activeSource(): (Source?, { Choice })
	local best: Source? = nil
	local bestChoices: { Choice } = {}
	for _, source in sources do
		if not best or source.priority >= (best :: Source).priority then
			local ok, choices = pcall(source.choices)
			if ok and type(choices) == "table" and #choices > 0 then
				best, bestChoices = source, choices
			end
		end
	end
	return best, bestChoices
end

local function indexOf(choices: { Choice }, key: any): number?
	if key == nil then
		return nil
	end
	for i, c in choices do
		if c.key == key then
			return i
		end
	end
	return nil
end

local function onInput(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local source, choices = activeSource()
	if not source then
		return Enum.ContextActionResult.Pass
	end
	local s = source :: Source
	if CONFIRM[input.KeyCode] then
		local key = s.current()
		if indexOf(choices, key) then
			s.confirm(key)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end
	local dir = DIRECTIONS[input.KeyCode]
	if not dir then
		return Enum.ContextActionResult.Pass
	end
	local from = indexOf(choices, s.current())
	local nextIndex: number?
	if s.ordered then
		if dir.X == 0 then
			return Enum.ContextActionResult.Pass
		end
		nextIndex = SeatLook.cycle(#choices, from, dir.X)
	else
		local camera = workspace.CurrentCamera
		local view = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		local spots = {}
		for i, c in choices do
			spots[i] = { x = c.x, y = c.y }
		end
		nextIndex = SeatLook.step(spots, from, dir.X, dir.Y, { x = view.X / 2, y = view.Y / 2 })
	end
	if nextIndex and choices[nextIndex] then
		s.select(choices[nextIndex].key)
	end
	return Enum.ContextActionResult.Sink
end

-- On while you're at a table (Table view). Bound under Color Clash's wild wheel, which
-- takes the arrows itself while it's open.
function KeyPick.setEnabled(value: boolean)
	if value == enabled then
		return
	end
	enabled = value
	if value then
		local keys = {}
		for key in DIRECTIONS do
			table.insert(keys, key)
		end
		for key in CONFIRM do
			table.insert(keys, key)
		end
		ContextActionService:BindActionAtPriority(ACTION, onInput, false, Enum.ContextActionPriority.High.Value, table.unpack(keys))
	else
		ContextActionService:UnbindAction(ACTION)
	end
end

return KeyPick
