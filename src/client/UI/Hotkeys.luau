-- Number keys for the buttons on screen, so a game plays all the way through with Table
-- view's mouse locked (Giovanni, 2026-11-15: "make sure the game is fully playable with
-- the mouse locked and unlocked"). While the mouse is locked, each button you could
-- press (Roll, Draw, Pass, a question's choices, Rematch...) wears a small number, and
-- that number key presses it. M opens and closes the match menu.
--
-- Which buttons: the ones a key can press (UI/Press: every Kit.button, and buttons
-- connected with Press.connect) that are showing inside the match screen or a game's
-- pop-up layer (Kit.hotkeyArea), or inside the top window open over them (rules, a
-- modal, the menu: Kit.needsMouse windows).
-- Rows top to bottom, left to right, numbered 1-9 then 0. Things marked NoHotkey (the
-- header, the seat list, the cards in your hand: A / D and Enter pick those) and buttons
-- marked HotkeyOff (greyed out) are left out.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local Juice = require(script.Parent.Juice)
local Press = require(script.Parent.Press)

local Hotkeys = {}

local ACTION = "GameNightHotkeys"
local NEEDS_MOUSE = "GameNightNeedsMouse" -- Kit.NEEDS_MOUSE
local HOTKEY_AREA = "GameNightHotkeyArea" -- Kit.HOTKEY_AREA
local SCAN_EVERY = 0.12
local ROW_SLOP = 18 -- pixels: buttons this close in height share a row

local NUMBER_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
	[Enum.KeyCode.Zero] = 10,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.KeypadThree] = 3,
	[Enum.KeyCode.KeypadFour] = 4,
	[Enum.KeyCode.KeypadFive] = 5,
	[Enum.KeyCode.KeypadSix] = 6,
	[Enum.KeyCode.KeypadSeven] = 7,
	[Enum.KeyCode.KeypadEight] = 8,
	[Enum.KeyCode.KeypadNine] = 9,
	[Enum.KeyCode.KeypadZero] = 10,
}
local MENU_KEY = Enum.KeyCode.M

local scope: GuiObject? = nil
local menuToggle: (() -> ())? = nil
local enabled = false
local showing = false -- numbers on (the mouse is locked)
local assigned: { GuiButton } = {}
local nextScan = 0

---------------------------------------------------------------- finding the buttons

type Rect = { x0: number, y0: number, x1: number, y1: number }

local function rectOf(gui: GuiObject): Rect
	local at, size = gui.AbsolutePosition, gui.AbsoluteSize
	return { x0 = at.X, y0 = at.Y, x1 = at.X + size.X, y1 = at.Y + size.Y }
end

local function inside(x: number, y: number, r: Rect?): boolean
	return r == nil or (x >= r.x0 and x <= r.x1 and y >= r.y0 and y <= r.y1)
end

local function clipTo(a: Rect?, b: Rect): Rect
	if not a then
		return b
	end
	return { x0 = math.max(a.x0, b.x0), y0 = math.max(a.y0, b.y0), x1 = math.min(a.x1, b.x1), y1 = math.min(a.y1, b.y1) }
end

local function usable(button: GuiButton, clip: Rect?, view: Vector2): boolean
	if button:GetAttribute("HotkeyOff") then
		return false
	end
	local size = button.AbsoluteSize
	if size.X < 16 or size.Y < 16 or size.X * size.Y > view.X * view.Y * 0.4 then
		return false -- a speck, or a dim layer that closes a window when clicked
	end
	local c = button.AbsolutePosition + size / 2
	return c.X >= 0 and c.Y >= 0 and c.X <= view.X and c.Y <= view.Y and inside(c.X, c.Y, clip)
end

local function collect(at: Instance, out: { GuiButton }, clip: Rect?, view: Vector2)
	for _, child in at:GetChildren() do
		if child:IsA("GuiObject") then
			if child.Visible and not child:GetAttribute("NoHotkey") then
				if child:IsA("GuiButton") and Press.has(child) and usable(child, clip, view) then
					table.insert(out, child)
				end
				collect(child, out, if child.ClipsDescendants then clipTo(clip, rectOf(child)) else clip, view)
			end
		elseif child:IsA("Folder") then
			collect(child, out, clip, view)
		end
	end
end

-- Whether `gui` is on screen: it and everything above it showing, in an enabled screen.
local function shownOnScreen(gui: GuiObject): (boolean, LayerCollector?)
	local at: Instance? = gui
	while at and at:IsA("GuiObject") do
		if not at.Visible then
			return false, nil
		end
		at = at.Parent
	end
	local screen = gui:FindFirstAncestorWhichIsA("LayerCollector")
	if not (screen and screen.Enabled and screen:IsDescendantOf(Players.LocalPlayer)) then
		return false, nil
	end
	return true, screen
end

-- The window open on top, if any (its buttons are the only ones then).
local function topWindow(): GuiObject?
	local best: GuiObject? = nil
	local bestRank = -math.huge
	for _, gui in CollectionService:GetTagged(NEEDS_MOUSE) do
		if gui:IsA("GuiObject") then
			local shown, screen = shownOnScreen(gui)
			if shown then
				local order = if screen and screen:IsA("ScreenGui") then screen.DisplayOrder else 0
				local rank = order * 100000 + gui.ZIndex
				if rank > bestRank then
					best, bestRank = gui, rank
				end
			end
		end
	end
	return best
end

local function scan(): { GuiButton }
	local out: { GuiButton } = {}
	local camera = workspace.CurrentCamera
	local view = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local window = topWindow()
	if window then
		collect(window, out, nil, view)
	else
		if scope and shownOnScreen(scope) then
			collect(scope :: GuiObject, out, nil, view)
		end
		-- Pop-up layers games put on the whole screen, outside the match screen.
		for _, area in CollectionService:GetTagged(HOTKEY_AREA) do
			if area:IsA("GuiObject") and not (scope and area:IsDescendantOf(scope)) and shownOnScreen(area) then
				collect(area, out, nil, view)
			end
		end
	end
	-- Rows top to bottom, then left to right along each row.
	local function center(b: GuiButton): Vector2
		return b.AbsolutePosition + b.AbsoluteSize / 2
	end
	table.sort(out, function(a, b)
		return center(a).Y < center(b).Y
	end)
	local rows: { { GuiButton } } = {}
	local rowY = -math.huge
	for _, button in out do
		local y = center(button).Y
		if y - rowY > ROW_SLOP then
			table.insert(rows, {})
			rowY = y
		end
		table.insert(rows[#rows], button)
	end
	local ordered: { GuiButton } = {}
	for _, row in rows do
		table.sort(row, function(a, b)
			return center(a).X < center(b).X
		end)
		for _, button in row do
			if #ordered < 10 then
				table.insert(ordered, button)
			end
		end
	end
	return ordered
end

---------------------------------------------------------------- the numbers on screen

local gui: ScreenGui? = nil
local badges: { TextLabel } = {}

local function badge(i: number): TextLabel
	if badges[i] then
		return badges[i]
	end
	if not (gui and gui.Parent) then
		local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		local screen = Instance.new("ScreenGui")
		screen.Name = "GameNightHotkeys"
		screen.IgnoreGuiInset = true
		screen.ResetOnSpawn = false
		screen.DisplayOrder = 45
		screen.Parent = playerGui
		gui = screen
	end
	local label = Instance.new("TextLabel")
	label.Name = `Key{i}`
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = UDim2.fromOffset(22, 22)
	label.BackgroundColor3 = Color3.fromRGB(24, 20, 40)
	label.BackgroundTransparency = 0.05
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 14
	label.Text = tostring(i % 10)
	label.ZIndex = 10
	label.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.15
	stroke.Parent = label
	label.Parent = gui
	badges[i] = label
	return label
end

local function hideBadges()
	for _, label in badges do
		label.Visible = false
	end
end

-- Pins each number to its button's top-left corner (buttons slide and pop in).
local function placeBadges()
	local inset = GuiService:GetGuiInset()
	for i, button in assigned do
		local label = badge(i)
		-- AbsolutePosition is measured from under Roblox's top bar even in an IgnoreGuiInset
		-- screen like this one (a Studio check found every number a top bar too high).
		local at = button.AbsolutePosition + inset
		label.Position = UDim2.fromOffset(at.X + 4, at.Y + 4)
		label.Visible = button.Parent ~= nil
	end
	for i = #assigned + 1, #badges do
		badges[i].Visible = false
	end
end

---------------------------------------------------------------- keys

local function onInput(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if input.KeyCode == MENU_KEY then
		if menuToggle then
			(menuToggle :: () -> ())()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end
	local n = NUMBER_KEYS[input.KeyCode]
	if not (n and showing) then
		return Enum.ContextActionResult.Pass
	end
	local button = assigned[n]
	if not (button and button.Parent) then
		return Enum.ContextActionResult.Pass
	end
	Juice.bump(button)
	local label = badges[n]
	if label then
		Juice.bump(label, 0.4)
	end
	Press.fire(button)
	nextScan = 0 -- the screen probably changed
	return Enum.ContextActionResult.Sink
end

---------------------------------------------------------------- set up by the table

-- The match screen: buttons inside it can get numbers.
function Hotkeys.setScope(root: GuiObject)
	scope = root
end

-- What M does (open or close the match menu).
function Hotkeys.setMenu(toggle: () -> ())
	menuToggle = toggle
end

-- On while you're at a table (Table view), with KeyPick.
function Hotkeys.setEnabled(value: boolean)
	if value == enabled then
		return
	end
	enabled = value
	if value then
		local keys = { MENU_KEY }
		for key in NUMBER_KEYS do
			table.insert(keys, key)
		end
		ContextActionService:BindActionAtPriority(ACTION, onInput, false, Enum.ContextActionPriority.High.Value, table.unpack(keys))
	else
		ContextActionService:UnbindAction(ACTION)
		showing = false
		table.clear(assigned)
		hideBadges()
	end
end

-- Every frame at the table: numbers show while the mouse is locked.
function Hotkeys.step(locked: boolean)
	if not enabled then
		return
	end
	if not locked then
		if showing then
			showing = false
			table.clear(assigned)
			hideBadges()
		end
		return
	end
	showing = true
	if os.clock() >= nextScan then
		nextScan = os.clock() + SCAN_EVERY
		assigned = scan()
	end
	placeBadges()
end

return Hotkeys
