-- Tiny UI toolkit: theme colors and helpers to build GUI objects in code.
-- Everything is built in code so it lives in Git. Use the shared sizes below (TextSize,
-- Radius) so every window reads the same, and the helpers (title, closeButton, chip)
-- instead of hand-made copies.


local Audio = require(script.Parent.Parent.Audio)
local Flair = require(script.Parent.Flair)
local Juice = require(script.Parent.Juice)
local Press = require(script.Parent.Press)

local Kit = {}

-- Windows over the game (rules, modals, the shop, the match menu): while one is open
-- with Table view's mouse locked, only its buttons get number keys (UI/Hotkeys).
Kit.NEEDS_MOUSE = "GameNightNeedsMouse"
function Kit.needsMouse(gui: GuiObject): GuiObject
	game:GetService("CollectionService"):AddTag(gui, Kit.NEEDS_MOUSE)
	return gui
end

-- A game's pop-up layer that sits on the whole screen, outside the match screen (Color
-- Clash's overlay, the card you just drew): its buttons get number keys too.
Kit.HOTKEY_AREA = "GameNightHotkeyArea"
function Kit.hotkeyArea(gui: GuiObject): GuiObject
	game:GetService("CollectionService"):AddTag(gui, Kit.HOTKEY_AREA)
	return gui
end

-- The look comes from shared/UIStyle (Config.UIStyle, or a "UIStyle" attribute on
-- Workspace in Studio). Kit.Style is its name ("Lounge", "Cafe" or "Classic").
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIStyle = require(ReplicatedStorage.Shared.UIStyle)
local Config = require(ReplicatedStorage.Shared.Config)

Kit.Style = UIStyle.pick(workspace:GetAttribute("UIStyle") or Config.UIStyle)
local style = UIStyle.Styles[Kit.Style]
Kit.StyleInfo = style
-- True for the Game Café look (wood, paper, felt): screens that have a Café layout check it.
Kit.cafe = Kit.Style == "Cafe"
-- True for the Midnight Lounge look (dark glass, neon accent, tab bar on top).
Kit.lounge = Kit.Style == "Lounge"
-- True for the redesigned looks (Café and Lounge): screens with a new layout (the picker's
-- game panel, the shop's Featured page, paper cards) check this; Classic keeps the old one.
Kit.rich = Kit.Style ~= "Classic"

local function font(name: string, fallback: Enum.Font): Enum.Font
	local ok, value = pcall(function()
		return (Enum.Font :: any)[name]
	end)
	return if ok and value then value else fallback
end

local theme: any = {
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
	Font = font(style.fonts.body, Enum.Font.GothamMedium),
	FontBold = font(style.fonts.bold, Enum.Font.GothamBold),
	-- Rounded, playful face for window titles and big calls to action.
	FontTitle = font(style.fonts.title, Enum.Font.FredokaOne),
	-- Type scale: window title, section heading, body text, small notes, tiny captions.
	TextSize = { Title = 22, Heading = 18, Body = 16, Small = 14, Tiny = 12 },
	Radius = { Small = 8, Medium = 10, Large = 14 },
	-- Window outline thickness and the dark edge under buttons (chunkier in the Café).
	Frame = style.frame,
	Edge = style.edge,
}
-- Colors: Background, Panel, PanelLight, Accent, AccentText, Good, Bad, Warn, Text,
-- SubText, Gem, Stroke (thin outline between windows and the 3D room), and the Café's
-- Paper/Paper2/Ink/Ink2 (light cards and their text), Wood/WoodDark, Felt/FeltDark.
for token, rgb in style.colors do
	theme[token] = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end
Kit.Theme = theme

Kit.Juice = Juice

-- Use instead of button.Activated:Connect(fn): the same, and a number key can press the
-- button while Table view has the mouse locked (UI/Hotkeys).
Kit.onPress = Press.connect

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

-- A window's outline: the thin line in Classic, a dark wood rim in the Café.
function Kit.frameStroke(): UIStroke
	if Kit.cafe then
		return Kit.stroke(Kit.Theme.WoodDark, 0, Kit.Theme.Frame)
	elseif Kit.lounge then
		-- Glass: a hairline of light around the edge.
		return Kit.stroke(Color3.new(1, 1, 1), 0.84, 1)
	end
	return Kit.stroke()
end

-- The Lounge's tall headline face (Oswald Bold); nil in the other looks. Kit.headline
-- puts it on a label.
Kit.HeadlineFace = if Kit.lounge then Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold) else nil
function Kit.headline(label: TextLabel | TextButton, upper: boolean?)
	if Kit.HeadlineFace then
		label.FontFace = Kit.HeadlineFace
		if upper ~= false then
			label.Text = label.Text:upper()
		end
	end
end

-- A dark glass panel (the Lounge's cards and bars): see-through dark plum with a hairline
-- edge. In the other looks it's a plain panel.
function Kit.glass(props: { [string]: any }?, radius: number?): Frame
	local frame = Kit.new("Frame", {
		BackgroundColor3 = Kit.Theme.Panel,
		BackgroundTransparency = if Kit.lounge then 0.18 else 0,
		BorderSizePixel = 0,
	}, {
		Kit.corner(radius or 14),
		Kit.frameStroke(),
	})
	for key, value in props or {} do
		(frame :: any)[key] = value
	end
	return frame
end

-- The Café's thin gold line just inside a window's rim (nothing in Classic). `inset` is
-- the parent's UIPadding, so the line sits 4 px in from the real edge.
function Kit.innerRim(parent: GuiObject, inset: number?, radius: number?)
	if not Kit.cafe then
		return
	end
	local pad = (inset or 0) - 4
	Kit.new("Frame", {
		Name = "Rim",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(-pad, -pad),
		Size = UDim2.new(1, pad * 2, 1, pad * 2),
		ZIndex = parent.ZIndex,
		Parent = parent,
	}, {
		Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or 10) }),
		Kit.new("UIStroke", { Color = Kit.Theme.Accent, Transparency = 0.55, Thickness = 1.5 }),
	})
end

-- A light "paper" card (game tiles, shop items, settings groups) with a wood frame in the
-- Café; a lighter panel card in Classic. Text on it uses Theme.Ink / Theme.Ink2.
function Kit.paper(props: { [string]: any }?): Frame
	local frame = Kit.new("Frame", {
		BackgroundColor3 = Kit.Theme.Paper,
		BorderSizePixel = 0,
	}, {
		Kit.corner(12),
		Kit.new("UIStroke", {
			Name = "Outline",
			Color = Kit.Theme.Wood,
			Transparency = if Kit.cafe then 0 else 0.55,
			Thickness = if Kit.cafe then 2.5 else 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Kit.new("UIGradient", {
			Name = "Shade",
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(238, 232, 222)),
		}),
	})
	for key, value in props or {} do
		(frame :: any)[key] = value
	end
	return frame
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
	}, { Kit.corner(14), Kit.padding(12), Kit.frameStroke(), Kit.shade() })
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
	Press.connect(button, onClick)
	Kit.pressable(button)
	Kit.edge(button)
	return button
end

-- A darker rim in the button's own color, so buttons read as chunky, tappable toys.
-- Follows the button's color; steps aside when the caller adds its own UIStroke.
function Kit.edge(button: GuiObject)
	local edge = Kit.new("UIStroke", {
		Name = "Edge",
		Thickness = Kit.Theme.Edge,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = button,
	})
	local function sync()
		edge.Color = button.BackgroundColor3:Lerp(Color3.new(0, 0, 0), if Kit.cafe then 0.5 else 0.35)
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

-- Buttons squash when pressed, spring past full size on release, and lift with a tick
-- under the mouse or gamepad (client/UI/Juice; the tick is Audio.hover), so a tap feels like it landed. The
-- sound is the button's "Sfx" attribute (a shared/Sounds.Effects name), "click" if unset,
-- "none" for silent.
function Kit.pressable(button: GuiButton)
	Press.connect(button, function()
		local sfx = button:GetAttribute("Sfx")
		if sfx ~= "none" then
			Audio.play(if type(sfx) == "string" then sfx else "click")
		end
	end)
	Juice.press(button)
end

-- The "no" for a tap that can't happen: a wobble and a bonk instead of a popup.
Kit.nope = Juice.nope
-- A happy bump for something that just changed or got picked.
Kit.bump = Juice.bump

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

-- The round X in a window's top-right corner.
function Kit.closeButton(onClick: () -> (), props: { [string]: any }?): TextButton
	local button = Kit.button("X", onClick, {
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

-- A window title: same size and weight everywhere. Leaves room for the X on the right.
function Kit.title(text: string, props: { [string]: any }?): TextLabel
	local label = Kit.label(text, {
		Name = "Title",
		Font = Kit.Theme.FontTitle,
		-- Oswald is narrow, so the Lounge's titles go a little bigger.
		TextSize = Kit.Theme.TextSize.Title + (if Kit.lounge then 4 else 0),
		Size = UDim2.new(1, -48, 0, 28),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
	})
	for key, value in props or {} do
		(label :: any)[key] = value
	end
	Kit.headline(label)
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
	-- Bounce when it becomes the picked one (not on every redraw).
	local was = chip:GetAttribute("Selected")
	chip:SetAttribute("Selected", selected)
	if selected and was == false then
		Juice.bump(chip, 0.1)
	end
	chip.BackgroundColor3 = if selected then Kit.Theme.Accent else Kit.Theme.PanelLight
	chip.TextColor3 = if selected then Kit.Theme.AccentText else Kit.Theme.Text
end

-- Grows a window in from small with a springy overshoot, so it doesn't just blink on.
function Kit.popIn(object: GuiObject)
	Juice.popIn(object)
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
	Kit.needsMouse(overlay)
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
		Kit.corner(if Kit.cafe then 18 elseif Kit.lounge then 16 else 14),
		Kit.padding(12),
		Kit.frameStroke(),
		Kit.shade(),
		Kit.new("UISizeConstraint", { MaxSize = opts.maxSize or Vector2.new(900, 640) }),
	})
	Kit.innerRim(panel, 12, 14)
	if Kit.lounge then
		-- Dark glass: the dimmed room shows faintly through.
		panel.BackgroundTransparency = 0.06
	end
	local body = Kit.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = panel,
	})

	local modal: any = { overlay = overlay, panel = panel, body = body }
	-- The world behind softly blurs while the window is up (client/UI/Flair).
	local blurKey = "modal:" .. overlay:GetFullName() .. tostring(math.random(1, 1e9))
	local DIM = overlay.BackgroundTransparency
	-- True while the close animation plays: the window counts as closed already.
	local closing = false
	overlay:GetPropertyChangedSignal("Visible"):Connect(function()
		Flair.blur(blurKey, overlay.Visible and not closing, overlay)
	end)
	overlay.Destroying:Connect(function()
		Flair.blur(blurKey, false)
	end)
	function modal.close()
		if overlay.Visible and not closing then
			closing = true
			if opts.onClose then
				opts.onClose()
			end
			Juice.tween(overlay, Juice.Info.Close, { BackgroundTransparency = 1 })
			Flair.blur(blurKey, false)
			Juice.popOut(panel, function()
				closing = false
				overlay.Visible = false
				overlay.BackgroundTransparency = DIM
			end)
		end
	end
	function modal.open()
		if not overlay.Visible or closing then
			closing = false
			overlay.Visible = true
			overlay.BackgroundTransparency = 1
			Juice.tween(overlay, Juice.Info.Fade, { BackgroundTransparency = DIM })
			Flair.blur(blurKey, true, overlay)
			Kit.popIn(panel)
		end
	end
	function modal.toggle()
		if modal.isOpen() then
			modal.close()
		else
			modal.open()
		end
	end
	function modal.isOpen(): boolean
		return overlay.Visible and not closing
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
	-- The fill glides to its new length (snaps the first time, so a window opens filled).
	local first = true
	local function set(fraction: number)
		fraction = math.clamp(fraction, 0, 1)
		fill.Visible = fraction > 0
		if first or not bar.Parent then
			first = false
			fill.Size = UDim2.fromScale(fraction, 1)
		else
			Juice.tween(fill, Juice.Info.Fill, { Size = UDim2.fromScale(fraction, 1) })
		end
	end
	return bar, set
end

-- A round avatar headshot (Roblox thumbnail URL, no yielding). Blank for bots/0.
function Kit.avatar(userId: number?, size: number, props: { [string]: any }?): ImageLabel
	local image = Kit.new("ImageLabel", {
		Name = "Avatar",
		BackgroundColor3 = Kit.Theme.Panel,
		BorderSizePixel = 0,
		Image = if userId and userId > 0 then `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150` else "",
		Size = UDim2.fromOffset(size, size),
	}, {
		Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Kit.new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.6, Thickness = 1.5 }),
	})
	for key, value in props or {} do
		(image :: any)[key] = value
	end
	return image
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

-- True inside a game picker preview (client/UI/GamePreview): boards drawn there must
-- keep everything inside the tile, take no input and make no sound.
function Kit.inPreview(object: Instance?): boolean
	local at = object
	while at do
		if at:GetAttribute("GamePreview") then
			return true
		end
		at = at.Parent
	end
	return false
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
