-- Juice: the shared motion kit that makes the UI feel springy and toy-like.
-- Research and rules: vault "05 Research/Nintendo UI Feel". In short:
--   * answer a touch in the same frame (press squashes at once);
--   * overshoot, then settle (pop-ins and releases spring past their size);
--   * short and snappy (0.06 to 0.4 s), closing faster than opening;
--   * a "no" is a wobble with a dull bonk, never an error popup;
--   * rewards are performed (count up with a rising tick, then a bump).
-- Kit and HudKit call into this, so every menu gets the feel without its own code.
-- Low-detail mode (client/Perf) keeps the one-shot motions but stops looping ones.

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Audio = require(script.Parent.Parent.Audio)
local Perf = require(script.Parent.Parent.Perf)

local Juice = {}

local OUT = Enum.EasingDirection.Out
local IN = Enum.EasingDirection.In

-- The springs everything shares, so the whole game moves with one rhythm.
Juice.Info = {
	Snap = TweenInfo.new(0.06, Enum.EasingStyle.Quad, OUT), -- press: lands the same frame
	Stretch = TweenInfo.new(0.08, Enum.EasingStyle.Quad, OUT), -- release: shoot past full size
	Spring = TweenInfo.new(0.3, Enum.EasingStyle.Back, OUT), -- settle with a little overshoot
	Pop = TweenInfo.new(0.32, Enum.EasingStyle.Back, OUT), -- windows and cards appearing
	Bounce = TweenInfo.new(0.5, Enum.EasingStyle.Elastic, OUT), -- rewards, big moments
	Close = TweenInfo.new(0.13, Enum.EasingStyle.Quad, IN), -- leaving is quicker than arriving
	Fill = TweenInfo.new(0.45, Enum.EasingStyle.Quart, OUT), -- bars and meters
	Fade = TweenInfo.new(0.18, Enum.EasingStyle.Quad, OUT),
}

Juice.PRESS = 0.9 -- scale while held down
Juice.STRETCH = 1.07 -- scale the release shoots to before settling
Juice.HOVER = 1.05 -- scale under the mouse or gamepad selection

local function tween(object: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local t = TweenService:Create(object, info, goal)
	t:Play()
	return t
end
Juice.tween = tween

-- The UIScale Juice animates on `object` (made if missing, named `name`). An object gets
-- only one: Roblox applies a single UIScale per object, so a pressable tile that also
-- pops in shares it. Kit.clear keeps PressScale/PopScale.
function Juice.scale(object: GuiObject, name: string?): UIScale
	local key = name or "PressScale"
	for _, candidate in { key, "PressScale", "PopScale" } do
		local existing = object:FindFirstChild(candidate)
		if existing and existing:IsA("UIScale") then
			return existing
		end
	end
	local s = Instance.new("UIScale")
	s.Name = key
	s.Parent = object
	return s
end

-- True when the last input was a mouse or gamepad (touch has no hover, and phones fire
-- MouseEnter on a tap, which would double the feedback).
local function canHover(): boolean
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return false
	end
	return UserInputService.MouseEnabled or UserInputService.GamepadEnabled
end


-- A quick tilt left-right-centre. Rotation works inside UIListLayouts, where Position
-- can't be moved, so every wobble here is a rotation.
local function wobble(object: GuiObject, degrees: number, swings: number, period: number)
	if object:GetAttribute("JuiceWobbling") then
		return
	end
	object:SetAttribute("JuiceWobbling", true)
	local base = object.Rotation
	task.spawn(function()
		local info = TweenInfo.new(period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		for i = 1, swings do
			if not object.Parent then
				break
			end
			local amount = degrees * (1 - (i - 1) / swings)
			local sign = if i % 2 == 1 then 1 else -1
			tween(object, info, { Rotation = base + amount * sign }).Completed:Wait()
		end
		if object.Parent then
			tween(object, info, { Rotation = base }).Completed:Wait()
		end
		object:SetAttribute("JuiceWobbling", nil)
	end)
end

-- The friendly "hi": a small wiggle when hovered (tiles, round buttons).
function Juice.wiggle(object: GuiObject)
	wobble(object, 3, 2, 0.06)
end

-- The "no": a firm side-to-side shake with a dull bonk, for a tap that can't happen
-- (a locked tile, a game that's coming soon, not enough Gems). No popup.
function Juice.nope(object: GuiObject)
	Audio.play("bonk")
	wobble(object, 7, 4, 0.045)
end

-- A quick happy bump: grow a little, spring back. For a pick, a total that changed, a
-- chip that just got selected.
function Juice.bump(object: GuiObject, amount: number?)
	local s = Juice.scale(object)
	local token = (s:GetAttribute("Token") or 0) + 1
	s:SetAttribute("Token", token)
	tween(s, Juice.Info.Stretch, { Scale = 1 + (amount or 0.12) }).Completed:Once(function()
		if s:GetAttribute("Token") == token then
			tween(s, Juice.Info.Spring, { Scale = 1 })
		end
	end)
end

-- Press feel for any button: squash at once on press, shoot past full size on release
-- and spring back, lift and tick under the mouse/gamepad. Small buttons also wiggle on
-- hover. Set the attribute "NoWiggle" to keep a button still.
function Juice.press(button: GuiButton)
	local s = Juice.scale(button)
	local hovered = false
	local held = false
	local function rest(): number
		return if hovered then Juice.HOVER else 1
	end
	local function go(info: TweenInfo, value: number, after: (() -> ())?)
		local token = (s:GetAttribute("Token") or 0) + 1
		s:SetAttribute("Token", token)
		if not s.Parent then
			return
		end
		local t = tween(s, info, { Scale = value })
		if after then
			t.Completed:Once(function()
				if s:GetAttribute("Token") == token then
					after()
				end
			end)
		end
	end
	local function isPress(input: InputObject): boolean
		local kind = input.UserInputType
		return kind == Enum.UserInputType.MouseButton1
			or kind == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA
	end
	button.InputBegan:Connect(function(input)
		if isPress(input) then
			held = true
			go(Juice.Info.Snap, Juice.PRESS)
		end
	end)
	button.InputEnded:Connect(function(input)
		if isPress(input) and held then
			held = false
			go(Juice.Info.Stretch, Juice.STRETCH, function()
				go(Juice.Info.Spring, rest())
			end)
		end
	end)
	local function enter()
		if hovered or not canHover() then
			return
		end
		hovered = true
		if not held then
			go(Juice.Info.Spring, Juice.HOVER)
		end
		if button.Active and button:GetAttribute("Sfx") ~= "none" then
			Audio.hover(button)
		end
		local size = button.AbsoluteSize
		if not button:GetAttribute("NoWiggle") and size.X <= 140 and size.Y <= 140 then
			Juice.wiggle(button)
		end
	end
	local function leave()
		if not hovered and not held then
			return
		end
		hovered = false
		held = false
		Audio.unhover(button)
		go(Juice.Info.Spring, 1)
	end
	button.MouseEnter:Connect(enter)
	button.MouseLeave:Connect(leave)
	button.SelectionGained:Connect(enter)
	button.SelectionLost:Connect(leave)
end

-- Window or card appearing: grows in from small and overshoots. Also fades in the
-- object's own background if `fade` is given (its target transparency).
function Juice.popIn(object: GuiObject, from: number?)
	local s = Juice.scale(object, "PopScale")
	local token = (s:GetAttribute("Token") or 0) + 1
	s:SetAttribute("Token", token)
	s.Scale = from or 0.7
	tween(s, Juice.Info.Pop, { Scale = 1 })
end

-- Window leaving: shrinks a little and is gone. Calls `done` after (unless popIn ran again).
function Juice.popOut(object: GuiObject, done: () -> ())
	local s = Juice.scale(object, "PopScale")
	local token = (s:GetAttribute("Token") or 0) + 1
	s:SetAttribute("Token", token)
	tween(s, Juice.Info.Close, { Scale = 0.82 }).Completed:Once(function()
		if s:GetAttribute("Token") == token then
			s.Scale = 1
			done()
		end
	end)
end

-- Children of `container` pop in one after another, Mario Party results style.
-- `gap` seconds between each (default 0.035), at most `limit` animated (rest just show).
function Juice.stagger(container: Instance, gap: number?, limit: number?)
	local items = {}
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") and child.Visible then
			table.insert(items, child)
		end
	end
	table.sort(items, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i, child in items do
		if i > (limit or 24) then
			break
		end
		local s = Juice.scale(child, "PopScale")
		s.Scale = 0
		task.delay((i - 1) * (gap or 0.035), function()
			if s.Parent then
				tween(s, Juice.Info.Pop, { Scale = 1 })
			end
		end)
	end
end

-- Counts a number label up (or down) like a coin tally: ticks rise in pitch, then the
-- label bumps. `format` turns the number into text. Returns at once.
function Juice.countUp(label: TextLabel, from: number, to: number, format: (number) -> string, duration: number?)
	local token = (label:GetAttribute("CountToken") or 0) + 1
	label:SetAttribute("CountToken", token)
	if from == to then
		label.Text = format(to)
		return
	end
	local time = duration or math.clamp(0.25 + math.abs(to - from) * 0.02, 0.3, 1.2)
	task.spawn(function()
		local start = os.clock()
		local shown = from
		local lastTick = 0
		while true do
			if label:GetAttribute("CountToken") ~= token or not label.Parent then
				return
			end
			local t = math.min((os.clock() - start) / time, 1)
			-- Ease out: fast at first, slows down as it lands.
			local eased = 1 - (1 - t) ^ 3
			local value = math.floor(from + (to - from) * eased + 0.5)
			if value ~= shown then
				shown = value
				label.Text = format(value)
				local now = os.clock()
				if now - lastTick > 0.05 then
					lastTick = now
					-- Up to a fifth higher by the end of the tally.
					Audio.play("count", { pitch = 7 * t })
				end
			end
			if t >= 1 then
				break
			end
			task.wait()
		end
		label.Text = format(to)
		Juice.bump(label, 0.18)
	end)
end

-- A slow breathing glow on a stroke (selected tile, your turn). Stops by itself when
-- the stroke goes away; skipped in low-detail mode (a still ring instead).
function Juice.breathe(stroke: UIStroke, low: number?, high: number?)
	stroke.Transparency = low or 0
	if Perf.isLow() then
		return
	end
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local t = tween(stroke, info, { Transparency = high or 0.6 })
	stroke.AncestryChanged:Connect(function(_, parent)
		if not parent then
			t:Cancel()
		end
	end)
end

-- Gamepad/keyboard selection: a thick, breathing gold ring around the selected button
-- (Game Night's accent, rounded to match our corners), with a tick and a pop each move.
local installed = false
function Juice.installSelection(playerGui: PlayerGui, color: Color3)
	if installed then
		return
	end
	installed = true
	local ring = Instance.new("Frame")
	ring.Name = "SelectionRing"
	ring.BackgroundTransparency = 1
	ring.Size = UDim2.fromScale(1, 1)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = ring
	Juice.breathe(stroke, 0, 0.45)
	playerGui.SelectionImageObject = ring
	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		local selected = GuiService.SelectedObject
		if selected then
			Audio.play("hover")
		end
	end)
end

return Juice
