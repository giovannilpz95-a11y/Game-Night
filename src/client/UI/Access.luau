-- Accessibility for the menus (Settings > Accessibility), all on this device:
-- * Text size: Normal, Large (x1.15) or Larger (x1.3) for every label and button in our
--   screen UI, with a floor so nothing is smaller than 12 px on a phone (11 elsewhere).
--   Code keeps setting TextSize as usual; this scales whatever it sets.
-- * Color-blind marks: a shape beside colors that carry meaning (Color Clash card colors,
--   Four in a Row discs). Renderers ask colorMarks() when they draw.
-- * Bigger tap targets on touch screens: a button shorter than 40 px gets invisible tap
--   strips above and below it (hitSlop), so a thumb that lands just off it still counts.
-- Saved with the other settings (server Core/ClientSettings: textSize, colorMarks).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Press = require(script.Parent.Press)

local Access = {}

Access.SCALES = { normal = 1, large = 1.15, larger = 1.3 }
Access.TAP_MIN = 40 -- px: the shortest a button's tap area gets on a touch screen

local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local textSize = "normal"
local scale = 1
local floor = if touch then 12 else 11
local marks = false
local listeners: { () -> () } = {}

-- TextSize the code asked for (base) and the last size we set ourselves.
local base: { [TextLabel | TextButton | TextBox]: number } = setmetatable({}, { __mode = "k" }) :: any
local mine: { [TextLabel | TextButton | TextBox]: number } = setmetatable({}, { __mode = "k" }) :: any

local function changed()
	for _, fn in listeners do
		task.spawn(fn)
	end
end

function Access.onChange(fn: () -> ())
	table.insert(listeners, fn)
end

function Access.isTouch(): boolean
	return touch
end

-- The size a label set to `size` is shown at.
function Access.size(size: number): number
	return math.max(floor, math.floor(size * scale + 0.5))
end

local function fit(text: any)
	if text.TextScaled then
		return
	end
	local now = text.TextSize
	if mine[text] ~= now then
		base[text] = now -- set by the code, not by us
	end
	local want = Access.size(base[text] or now)
	mine[text] = want
	if now ~= want then
		text.TextSize = want
	end
end

local function track(inst: Instance)
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		fit(inst)
		inst:GetPropertyChangedSignal("TextSize"):Connect(function()
			fit(inst)
		end)
	end
end

local watched: { [ScreenGui]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local function watch(gui: ScreenGui)
	if watched[gui] then
		return
	end
	watched[gui] = true
	for _, d in gui:GetDescendants() do
		track(d)
	end
	gui.DescendantAdded:Connect(track)
end

-- Starts scaling text in our screen UI (every ScreenGui in PlayerGui, now and later).
function Access.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, child in playerGui:GetChildren() do
		if child:IsA("ScreenGui") then
			watch(child)
		end
	end
	playerGui.ChildAdded:Connect(function(child)
		if child:IsA("ScreenGui") then
			watch(child)
		end
	end)
end

function Access.textSize(): string
	return textSize
end

function Access.setTextSize(value: string)
	if not Access.SCALES[value] or value == textSize then
		return
	end
	textSize = value
	scale = Access.SCALES[value]
	for text in base do
		if text.Parent then
			fit(text)
		end
	end
	changed()
end

function Access.colorMarks(): boolean
	return marks
end

local markLabels: { [TextLabel]: boolean } = setmetatable({}, { __mode = "k" }) :: any

function Access.setColorMarks(value: boolean)
	if marks == value then
		return
	end
	marks = value
	for label in markLabels do
		label.Visible = value
	end
	changed()
end

-- A small shape in the middle of `parent` (seat shapes, card color marks): dark ink on
-- light pieces, light on dark ones. Hidden until color-blind marks are on.
function Access.mark(parent: GuiObject, glyph: string, props: { [string]: any }?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "ColorMark"
	label.BackgroundTransparency = 1
	label.Text = glyph
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.35
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.5, 0.5)
	label.ZIndex = parent.ZIndex + 1
	label.Visible = marks
	for key, value in props or {} do
		(label :: any)[key] = value
	end
	label.Parent = parent
	markLabels[label] = true
	return label
end

-- Invisible tap strips above and below a short button on a touch screen, so the area
-- you can tap is at least TAP_MIN tall. A tap on them presses the button (UI/Press).
function Access.hitSlop(button: GuiButton)
	if not touch then
		return
	end
	local strips = {}
	for i, anchor in { 1, 0 } do
		local strip = Instance.new("TextButton")
		strip.Name = "TapArea"
		strip.Text = ""
		strip.AutoButtonColor = false
		strip.BackgroundTransparency = 1
		strip.Selectable = false
		strip.AnchorPoint = Vector2.new(0, anchor)
		strip.Position = UDim2.fromScale(0, if i == 1 then 0 else 1)
		strip.Visible = false
		strip.Parent = button
		strip.Activated:Connect(function()
			if button.Active and button.Visible then
				Press.fire(button)
			end
		end)
		strips[i] = strip
	end
	local function size()
		local extra = math.max(0, math.ceil((Access.TAP_MIN - button.AbsoluteSize.Y) / 2))
		for _, strip in strips do
			strip.Size = UDim2.new(1, 0, 0, extra)
			strip.ZIndex = button.ZIndex
			strip.Visible = extra > 0 and button.AbsoluteSize.Y > 0
		end
	end
	button:GetPropertyChangedSignal("AbsoluteSize"):Connect(size)
	button:GetPropertyChangedSignal("ZIndex"):Connect(size)
	size()
end

return Access
