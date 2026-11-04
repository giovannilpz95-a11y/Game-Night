-- Tiny UI toolkit: theme colors and helpers to build GUI objects in code.
-- Everything is built in code so it lives in Git. Use the shared sizes below (TextSize,
-- Radius) so every window reads the same, and the helpers (title, closeButton, chip)
-- instead of hand-made copies.

local TweenService = game:GetService("TweenService")

local Audio = require(script.Parent.Parent.Audio)

local Kit = {}

Kit.Theme = {
	Background = Color3.fromRGB(24, 22, 38),
	Panel = Color3.fromRGB(38, 34, 60),
	PanelLight = Color3.fromRGB(54, 49, 84),
	Accent = Color3.fromRGB(255, 196, 64),
	AccentText = Color3.fromRGB(40, 28, 0),
	Good = Color3.fromRGB(88, 204, 120),
	Bad = Color3.fromRGB(235, 87, 87),
	Warn = Color3.fromRGB(255, 150, 60),
	Text = Color3.fromRGB(245, 243, 255),
	SubText = Color3.fromRGB(176, 170, 204),
	Seat = {
		Color3.fromRGB(255, 99, 132),
		Color3.fromRGB(54, 162, 235),
		Color3.fromRGB(255, 206, 86),
		Color3.fromRGB(75, 192, 192),
		Color3.fromRGB(153, 102, 255),
		Color3.fromRGB(255, 159, 64),
		Color3.fromRGB(102, 255, 153),
		Color3.fromRGB(255, 102, 204),
	},
	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
	-- Rounded, playful face for window titles and big calls to action.
	FontTitle = Enum.Font.FredokaOne,
	Gem = Color3.fromRGB(110, 220, 255),
	-- Thin outline on windows and cards, so they separate from the 3D room behind them.
	Stroke = Color3.fromRGB(120, 110, 170),
	-- Type scale: window title, section heading, body text, small notes, tiny captions.
	TextSize = { Title = 22, Heading = 18, Body = 16, Small = 14, Tiny = 12 },
	Radius = { Small = 8, Medium = 10, Large = 14 },
}

local PRESS_SCALE = 0.95
local PRESS_INFO = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- Kit.new("Frame", { Size = ..., Parent = ... }, { children })
function Kit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		else
			(instance :: any)[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	instance.Parent = parent
	return instance
end

function Kit.corner(radius: number?): UICorner
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
end

function Kit.padding(px: number): UIPadding
	return Kit.new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

function Kit.list(gap: number?, horizontal: boolean?): UIListLayout
	return Kit.new("UIListLayout", {
		Padding = UDim.new(0, gap or 6),
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

-- A thin outline. Border mode, so it rings a button's box rather than its text.
function Kit.stroke(color: Color3?, transparency: number?, thickness: number?): UIStroke
	return Kit.new("UIStroke", {
		Name = "Outline",
		Color = color or Kit.Theme.Stroke,
		Transparency = transparency or 0.55,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

-- A soft top-to-bottom shade on a window or card background (it only tints the
-- object's own background, never its children or text-free buttons' labels).
function Kit.shade(amount: number?): UIGradient
	local bottom = 1 - (amount or 0.16)
	return Kit.new("UIGradient", {
		Name = "Shade",
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(bottom, bottom, bottom)),
	})
end

-- A card inside a window: lighter panel, rounded, padded, shaded.
function Kit.card(props: { [string]: any }?): Frame
	local frame = Kit.new("Frame", {
		BackgroundColor3 = Kit.Theme.PanelLight,
		BorderSizePixel = 0,
	}, { Kit.corner(12), Kit.padding(10), Kit.shade(0.12) })
	for key, value in props or {} do
		(frame :: any)[key] = value
	end
	return frame
end

function Kit.panel(props: { [string]: any }): Frame
	local frame = Kit.new("Frame", {
		BackgroundColor3 = Kit.Theme.Panel,
		BorderSizePixel = 0,
	}, { Kit.corner(14), Kit.padding(12), Kit.stroke(), Kit.shade() })
	-- A panel that brings its own outline (an accent ring) drops the default one.
	frame.ChildAdded:Connect(function(child)
		if child:IsA("UIStroke") and child.Name ~= "Outline" then
			local outline = frame:FindFirstChild("Outline")
			if outline then
				outline:Destroy()
			end
		end
	end)
	for key, value in props do
		(frame :: any)[key] = value
	end
	return frame
end

function Kit.label(text: string, props: { [string]: any }?): TextLabel
	local label = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Kit.Theme.Text,
		Font = Kit.Theme.Font,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 22),
		TextWrapped = true,
	})
	for key, value in props or {} do
		(label :: any)[key] = value
	end
	return label
end

function Kit.button(text: string, onClick: () -> (), props: { [string]: any }?): TextButton
	local button = Kit.new("TextButton", {
		Text = text,
		AutoButtonColor = true,
		BackgroundColor3 = Kit.Theme.Accent,
		TextColor3 = Kit.Theme.AccentText,
		Font = Kit.Theme.FontBold,
		TextSize = 16,
		Size = UDim2.new(1, 0, 0, 36),
		BorderSizePixel = 0,
	}, { Kit.corner(10) })
	for key, value in props or {} do
		(button :: any)[key] = value
	end
	button.Activated:Connect(onClick)
	Kit.pressable(button)
	Kit.edge(button)
	return button
end

-- A darker rim in the button's own color, so buttons read as chunky, tappable toys.
-- Follows the button's color; steps aside when the caller adds its own UIStroke.
function Kit.edge(button: GuiObject)
	local edge = Kit.new("UIStroke", {
		Name = "Edge",
		Thickness = 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = button,
	})
	local function sync()
		edge.Color = button.BackgroundColor3:Lerp(Color3.new(0, 0, 0), 0.35)
		edge.Transparency = math.max(button.BackgroundTransparency, 0.15)
	end
	sync()
	button:GetPropertyChangedSignal("BackgroundColor3"):Connect(sync)
	button:GetPropertyChangedSignal("BackgroundTransparency"):Connect(sync)
	button.ChildAdded:Connect(function(child)
		if child:IsA("UIStroke") and child ~= edge then
			edge:Destroy()
		end
	end)
end

-- Buttons sink a little while pressed and click, so a tap feels like it landed. The
-- sound is the button's "Sfx" attribute (a shared/Sounds.Effects name), "click" if unset.
function Kit.pressable(button: GuiButton)
	local scale = Kit.new("UIScale", { Name = "PressScale", Parent = button })
	button.Activated:Connect(function()
		local sfx = button:GetAttribute("Sfx")
		Audio.play(if type(sfx) == "string" then sfx else "click")
	end)
	local function to(value: number)
		if scale.Parent then
			TweenService:Create(scale, PRESS_INFO, { Scale = value }):Play()
		end
	end
	button.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			to(PRESS_SCALE)
		end
	end)
	button.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			to(1)
		end
	end)
	button.MouseLeave:Connect(function()
		to(1)
	end)
end

-- A secondary button: panel colored, light text. Same props as Kit.button.
function Kit.secondary(text: string, onClick: () -> (), props: { [string]: any }?): TextButton
	local button = Kit.button(text, onClick, {
		BackgroundColor3 = Kit.Theme.PanelLight,
		TextColor3 = Kit.Theme.Text,
	})
	for key, value in props or {} do
		(button :: any)[key] = value
	end
	return button
end

-- The round ✕ in a window's top-right corner.
function Kit.closeButton(onClick: () -> (), props: { [string]: any }?): TextButton
	local button = Kit.button("✕", onClick, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 4, 0, -4),
		Size = UDim2.new(0, 36, 0, 36),
		BackgroundColor3 = Kit.Theme.PanelLight,
		TextColor3 = Kit.Theme.Text,
		TextSize = 18,
	})
	button:SetAttribute("Sfx", "close")
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0.5, 0)
	end
	for key, value in props or {} do
		(button :: any)[key] = value
	end
	return button
end

-- A window title: same size and weight everywhere. Leaves room for the ✕ on the right.
function Kit.title(text: string, props: { [string]: any }?): TextLabel
	local label = Kit.label(text, {
		Name = "Title",
		Font = Kit.Theme.FontTitle,
		TextSize = Kit.Theme.TextSize.Title,
		Size = UDim2.new(1, -48, 0, 28),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
	})
	for key, value in props or {} do
		(label :: any)[key] = value
	end
	return label
end

-- A pill-shaped toggle (tabs, filters). Kit.setChip(chip, selected) recolors it.
function Kit.chip(text: string, onClick: () -> (), props: { [string]: any }?): TextButton
	local chip = Kit.button(text, onClick, {
		Size = UDim2.new(0, 0, 0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = Kit.Theme.TextSize.Small,
		BackgroundColor3 = Kit.Theme.PanelLight,
		TextColor3 = Kit.Theme.Text,
	})
	chip:SetAttribute("Sfx", "toggle")
	local corner = chip:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0.5, 0)
	end
	Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = chip })
	for key, value in props or {} do
		(chip :: any)[key] = value
	end
	return chip
end

function Kit.setChip(chip: TextButton, selected: boolean)
	chip.BackgroundColor3 = if selected then Kit.Theme.Accent else Kit.Theme.PanelLight
	chip.TextColor3 = if selected then Kit.Theme.AccentText else Kit.Theme.Text
end

-- Grows a window in from slightly smaller, so it doesn't just blink on.
function Kit.popIn(object: GuiObject)
	local scale = object:FindFirstChild("PopScale") :: UIScale?
	if not scale then
		scale = Kit.new("UIScale", { Name = "PopScale", Parent = object })
	end
	local s = scale :: UIScale
	s.Scale = 0.92
	TweenService:Create(s, POP_INFO, { Scale = 1 }):Play()
end

-- A centered window over a dimmed screen. Tapping the dim area or the X closes it.
-- Put content in `body`. opts: name, maxSize (Vector2), zIndex, onClose.
function Kit.modal(parent: Instance, opts: { [string]: any }): any
	local z = opts.zIndex or 25
	local overlay = Kit.new("TextButton", {
		Name = opts.name or "Modal",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = z,
		Parent = parent,
	})
	-- A button that does nothing, so taps on the window don't reach the dim area behind it.
	local panel = Kit.new("TextButton", {
		Name = "Window",
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -24, 1, -24),
		BackgroundColor3 = Kit.Theme.Panel,
		BorderSizePixel = 0,
		ZIndex = z,
		Parent = overlay,
	}, {
		Kit.corner(14),
		Kit.padding(12),
		Kit.stroke(),
		Kit.shade(),
		Kit.new("UISizeConstraint", { MaxSize = opts.maxSize or Vector2.new(900, 640) }),
	})
	local body = Kit.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = panel,
	})

	local modal: any = { overlay = overlay, panel = panel, body = body }
	function modal.close()
		if overlay.Visible then
			overlay.Visible = false
			if opts.onClose then
				opts.onClose()
			end
		end
	end
	function modal.open()
		if not overlay.Visible then
			overlay.Visible = true
			Kit.popIn(panel)
		end
	end
	function modal.toggle()
		if overlay.Visible then
			modal.close()
		else
			modal.open()
		end
	end
	function modal.isOpen(): boolean
		return overlay.Visible
	end
	-- Fit inside the free screen area (below Roblox's top bar).
	function modal.fit(top: number, bottom: number)
		panel.Position = UDim2.new(0.5, 0, 0.5, (top - bottom) / 2)
		panel.Size = UDim2.new(1, -24, 1, -(top + bottom + 12))
	end
	overlay.Activated:Connect(modal.close)
	Kit.closeButton(modal.close, { ZIndex = z + 20, Parent = panel })
	return modal
end

-- The Gem: a small cyan diamond. Same shape as the wallet's.
function Kit.gemIcon(size: number, props: { [string]: any }?): Frame
	local holder = Kit.new("Frame", { Name = "Gem", BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size) })
	Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.7),
		Rotation = 45,
		BackgroundColor3 = Kit.Theme.Gem,
		BorderSizePixel = 0,
		Parent = holder,
	}, {
		Kit.new("UICorner", { CornerRadius = UDim.new(0.2, 0) }),
		Kit.new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.4, Thickness = 1 }),
	})
	for key, value in props or {} do
		(holder :: any)[key] = value
	end
	return holder
end

-- A coin: a disc in the coin's color with a darker rim.
function Kit.coinIcon(color: Color3, size: number, props: { [string]: any }?): Frame
	local coin = Kit.new("Frame", {
		Name = "Coin",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
	}, {
		Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Kit.new("UIStroke", { Color = color:Lerp(Color3.new(0, 0, 0), 0.4), Thickness = math.max(1, size / 8) }),
	})
	for key, value in props or {} do
		(coin :: any)[key] = value
	end
	return coin
end

-- A progress bar. Returns the bar and a setter taking 0..1.
function Kit.progress(color: Color3?, props: { [string]: any }?): (Frame, (number) -> ())
	local bar = Kit.new("Frame", {
		Name = "Progress",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 8),
	}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local fill = Kit.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = color or Kit.Theme.Good,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = bar,
	}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), Kit.shade(0.25) })
	for key, value in props or {} do
		(bar :: any)[key] = value
	end
	local function set(fraction: number)
		fraction = math.clamp(fraction, 0, 1)
		fill.Size = UDim2.fromScale(fraction, 1)
		fill.Visible = fraction > 0
	end
	return bar, set
end

-- A small rounded tag ("BEST VALUE", "OWNED") in the corner of a card.
function Kit.tag(text: string, color: Color3, props: { [string]: any }?): TextLabel
	local tag = Kit.label(text, {
		Name = "Tag",
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
		TextColor3 = Kit.Theme.AccentText,
		Font = Kit.Theme.FontBold,
		TextSize = 11,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
	})
	Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = tag })
	Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = tag })
	for key, value in props or {} do
		(tag :: any)[key] = value
	end
	return tag
end

function Kit.clear(container: Instance)
	for _, child in container:GetChildren() do
		if
			not child:IsA("UIListLayout")
			and not child:IsA("UIGridLayout")
			and not child:IsA("UIPadding")
			and not child:IsA("UICorner")
			-- Kit's own decorations on the container itself.
			and not (child:IsA("UIStroke") and (child.Name == "Outline" or child.Name == "Edge"))
			and not (child:IsA("UIGradient") and child.Name == "Shade")
			and not (child:IsA("UIScale") and (child.Name == "PressScale" or child.Name == "PopScale"))
		then
			child:Destroy()
		end
	end
end

return Kit
