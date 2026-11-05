-- In-match look, on top of Kit's theme: avatar badges for seats, glassy gradient panels,
-- a pulsing ring for whoever's turn it is, "thinking" dots, confetti and a shine sweep.
-- Used by MatchView and the shared game layouts (CardTable, BoardGrid). Menus and windows
-- keep using Kit directly.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Kit = require(script.Parent.Kit)
local Audio = require(script.Parent.Parent.Audio)
local Theme = Kit.Theme

local HudKit = {}

-- Seat shapes, so color is never the only way to tell seats apart.
HudKit.SeatShapes = { "●", "■", "▲", "◆", "★", "✖", "♥", "♣" }

function HudKit.seatColor(seat: number): Color3
	return Theme.Seat[seat] or Theme.Text
end

function HudKit.seatShape(seat: number): string
	return HudKit.SeatShapes[seat] or "●"
end

-- Darker (amount > 0) or lighter (amount < 0) copy of a color.
function HudKit.shade(color: Color3, amount: number): Color3
	if amount >= 0 then
		return color:Lerp(Color3.new(0, 0, 0), amount)
	end
	return color:Lerp(Color3.new(1, 1, 1), -amount)
end

-- A two-stop gradient; rotation 90 runs top to bottom.
function HudKit.gradient(from: Color3, to: Color3, rotation: number?, transparency: NumberSequence?): UIGradient
	return Kit.new("UIGradient", {
		Name = "HudGradient",
		Color = ColorSequence.new(from, to),
		Rotation = rotation or 90,
		Transparency = transparency or NumberSequence.new(0),
	})
end

-- Dark see-through panel with a soft top light and a thin rim, for HUD pieces that float
-- over the 3D room (header, seat list, dock).
function HudKit.glass(frame: GuiObject, transparency: number?)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = transparency or 0.12
	local old = frame:FindFirstChild("HudGradient")
	if old then
		old:Destroy()
	end
	HudKit.gradient(HudKit.shade(Theme.PanelLight, -0.05), HudKit.shade(Theme.Background, 0.15)).Parent = frame
	if not frame:FindFirstChild("Rim") then
		Kit.new("UIStroke", {
			Name = "Rim",
			Color = Theme.Stroke,
			Transparency = 0.45,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = frame,
		})
	end
end

-- Makes a frame or button a pill (fully round ends).
function HudKit.pill(object: GuiObject)
	local corner = object:FindFirstChildOfClass("UICorner")
	if not corner then
		corner = Kit.new("UICorner", { Parent = object })
	end
	(corner :: UICorner).CornerRadius = UDim.new(0.5, 0)
end

---------------------------------------------------------------- side panels
-- The big games' side panels (Property Party, Hexlands, Conquest Isles, Whodunit).
-- Uses Kit's own Shade gradient and Outline stroke, so Kit.clear keeps them.
function HudKit.sidePanel(frame: GuiObject)
	frame.BackgroundColor3 = Theme.Panel
	if not frame:FindFirstChild("Shade") then
		Kit.shade(0.22).Parent = frame
	end
	if not frame:FindFirstChild("Outline") then
		Kit.stroke().Parent = frame
	end
	if frame:IsA("ScrollingFrame") then
		frame.ScrollBarImageColor3 = Theme.Accent
		frame.ScrollBarImageTransparency = 0.4
	end
end

-- Rings a panel in the color of whoever's turn it is (gold when it's yours), so the
-- side panel says whose move it is even when you aren't reading it.
function HudKit.turnTint(frame: GuiObject, seat: number?, yours: boolean)
	local outline = frame:FindFirstChild("Outline") :: UIStroke?
	if not outline then
		return
	end
	if yours then
		outline.Color = Theme.Accent
		outline.Thickness = 2
		outline.Transparency = 0.1
	elseif seat then
		outline.Color = HudKit.seatColor(seat)
		outline.Thickness = 2
		outline.Transparency = 0.35
	else
		outline.Color = Theme.Stroke
		outline.Thickness = 1
		outline.Transparency = 0.55
	end
end

-- A section heading: title font, with a short gold underline that fades out.
-- props: LayoutOrder, Parent, TextColor3, Text size via `size`.
function HudKit.heading(text: string, props: { [string]: any }): Frame
	local size = props.size or 17
	local frame = Kit.new("Frame", {
		Name = "Heading",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, size + 10),
		LayoutOrder = props.LayoutOrder or 0,
	})
	Kit.label(text, {
		Name = "Text",
		Font = Theme.FontTitle,
		TextSize = size + 1,
		TextColor3 = props.TextColor3 or Theme.Text,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, size + 5),
		ZIndex = props.ZIndex or 1,
		Parent = frame,
	})
	Kit.new("Frame", {
		Name = "Underline",
		BackgroundColor3 = props.TextColor3 or Theme.Accent,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -1),
		Size = UDim2.new(0.6, 0, 0, 2),
		ZIndex = props.ZIndex or 1,
		Parent = frame,
	}, {
		Kit.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	frame.Parent = props.Parent
	return frame
end

-- A status card: the "what now" line on a seat-tinted glass strip with a pulsing ring
-- when it's your move.
function HudKit.statusCard(text: string, seat: number?, yours: boolean, props: { [string]: any }): Frame
	local card = Kit.new("Frame", {
		Name = "Status",
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = props.LayoutOrder or 0,
	}, {
		Kit.corner(10),
		Kit.new("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 10),
		}),
	})
	HudKit.glass(card, 0)
	local tint = if yours then Theme.Accent elseif seat then HudKit.seatColor(seat) else Theme.PanelLight
	card.HudGradient.Color = ColorSequence.new(HudKit.shade(tint, if yours then 0.55 else 0.6), HudKit.shade(Theme.Panel, 0.1))
	card.HudGradient.Rotation = 0
	card.Rim.Color = tint
	card.Rim.Transparency = 0.2
	if yours then
		card.Rim.Thickness = 2
		HudKit.pulse(card.Rim, 0, 0.55)
	end
	Kit.new("Frame", {
		Name = "Stripe",
		BackgroundColor3 = tint,
		BorderSizePixel = 0,
		Position = UDim2.new(0, -8, 0, 0),
		Size = UDim2.new(0, 3, 1, 0),
		Parent = card,
	}, { Kit.corner(2) })
	Kit.label(text, {
		Name = "Text",
		Font = Theme.FontBold,
		TextSize = props.size or 16,
		TextColor3 = if yours then Color3.fromRGB(255, 230, 150) else Theme.Text,
		RichText = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		Parent = card,
	})
	card.Parent = props.Parent
	return card
end

---------------------------------------------------------------- avatars
local headshots: { [number]: string } = {}
local waiting: { [number]: { ImageLabel } } = {}

local function fetchHeadshot(userId: number)
	local ok, content, ready = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
	end)
	local list = waiting[userId] or {}
	waiting[userId] = nil
	if ok and ready and type(content) == "string" then
		headshots[userId] = content
		for _, image in list do
			if image.Parent then
				image.Image = content
				image.Visible = true
			end
		end
	elseif ok and type(content) == "string" then
		-- Not ready yet: try again in a moment.
		waiting[userId] = list
		task.delay(2, fetchHeadshot, userId)
	end
end

-- A round avatar badge with a ring in the seat's color and the seat's shape in a little
-- tag on its corner. Players show their headshot (loaded in the background, with their
-- initial meanwhile); bots show 🤖. props: Size, Position, AnchorPoint, ZIndex, Parent.
function HudKit.avatar(seat: number, seatInfo: any, props: { [string]: any }): Frame
	local color = HudKit.seatColor(seat)
	local z = props.ZIndex or 4
	local frame = Kit.new("Frame", {
		Name = "Avatar",
		BackgroundColor3 = HudKit.shade(color, 0.55),
		BorderSizePixel = 0,
		ZIndex = z,
	}, {
		Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Kit.new("UIAspectRatioConstraint", { AspectRatio = 1 }),
		Kit.new("UIStroke", { Name = "Ring", Color = color, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	})
	for key, value in props do
		if key ~= "Parent" then
			(frame :: any)[key] = value
		end
	end
	local isBot = seatInfo and seatInfo.kind == "bot"
	local name = (seatInfo and seatInfo.name) or "?"
	local fallback = Kit.label(if isBot then "🤖" else string.upper(string.sub(name, 1, 1)), {
		Font = Theme.FontBold,
		TextScaled = true,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		ZIndex = z + 1,
		Parent = frame,
	})
	local userId = seatInfo and seatInfo.userId
	if not isBot and type(userId) == "number" and userId > 0 then
		local image = Kit.new("ImageLabel", {
			Name = "Headshot",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = headshots[userId] or "",
			Visible = headshots[userId] ~= nil,
			ZIndex = z + 2,
			Parent = frame,
		}, { Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		if not headshots[userId] then
			local list = waiting[userId]
			if list then
				table.insert(list, image)
			else
				waiting[userId] = { image }
				task.spawn(fetchHeadshot, userId)
			end
		end
		image:GetPropertyChangedSignal("Visible"):Connect(function()
			fallback.Visible = not image.Visible
		end)
		fallback.Visible = not image.Visible
	end
	-- Seat shape tag, bottom-right.
	local tag = Kit.label(HudKit.seatShape(seat), {
		Name = "Shape",
		Font = Theme.FontBold,
		TextScaled = true,
		TextColor3 = HudKit.shade(color, 0.7),
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.86, 0.86),
		Size = UDim2.fromScale(0.42, 0.42),
		ZIndex = z + 3,
		Parent = frame,
	})
	Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = tag })
	Kit.new("UIPadding", {
		PaddingTop = UDim.new(0.18, 0),
		PaddingBottom = UDim.new(0.18, 0),
		PaddingLeft = UDim.new(0.18, 0),
		PaddingRight = UDim.new(0.18, 0),
		Parent = tag,
	})
	frame.Parent = props.Parent
	return frame
end

---------------------------------------------------------------- motion
local PULSE_INFO = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

-- A ring that breathes (whose turn it is). Stops by itself when the stroke is destroyed.
function HudKit.pulse(stroke: UIStroke, low: number?, high: number?)
	stroke.Transparency = low or 0
	local tween = TweenService:Create(stroke, PULSE_INFO, { Transparency = high or 0.65 })
	tween:Play()
	-- A forever tween holds on to its stroke; let both go when the stroke does.
	stroke.Destroying:Once(function()
		tween:Cancel()
		tween:Destroy()
	end)
end

-- "Sam is thinking" dots: cycles . .. ... on a label until it's destroyed or hidden.
function HudKit.dots(label: TextLabel, base: string)
	task.spawn(function()
		local n = 0
		while label.Parent do
			n = n % 3 + 1
			label.Text = base .. string.rep(".", n)
			task.wait(0.4)
		end
	end)
end

-- A big moment called out over the game for a second or two ("Hearts are broken!",
-- "BINGO! +50", "Gin!"): a pill that pops in, shines and fades away. `color` tints it.
function HudKit.callout(parent: Instance, text: string, color: Color3?, y: number?)
	local pill = Kit.new("Frame", {
		Name = "Callout",
		BackgroundColor3 = color or Kit.Theme.Accent,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, y or 0.4),
		Size = UDim2.fromOffset(math.clamp(#text * 17 + 60, 180, 520), 58),
		ZIndex = 40,
		Parent = parent,
	}, { Kit.new("UICorner", { CornerRadius = UDim.new(0, 14) }), Kit.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Transparency = 0.3 }) })
	local scale = Kit.new("UIScale", { Scale = 0.4, Parent = pill })
	local label = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = text,
		TextScaled = true,
		Font = Kit.Theme.FontBold,
		TextColor3 = Kit.Theme.AccentText,
		ZIndex = 41,
		Parent = pill,
	}, { Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }) })
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	HudKit.shine(pill, 42)
	Audio.play("callout")
	task.delay(1.6, function()
		if not pill.Parent then
			return
		end
		local info = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(pill, info, { BackgroundTransparency = 1, Position = UDim2.fromScale(0.5, (y or 0.4) - 0.05) }):Play()
		TweenService:Create(label, info, { TextTransparency = 1 }):Play()
		local stroke = pill:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, info, { Transparency = 1 }):Play()
		end
		task.delay(0.45, function()
			pill:Destroy()
		end)
	end)
end

-- A secret card shown just to you, flipped over in the middle of the screen like it's
-- slid across the table face down and turned up (Whodunit's "showed you" moment).
-- Tap it or wait a few seconds and it tucks away.
function HudKit.revealCard(parent: Instance, heading: string, title: string, subtitle: string?, color: Color3?)
	local old = parent:FindFirstChild("RevealCard")
	if old then
		old:Destroy()
	end
	local card = Kit.new("TextButton", {
		Name = "RevealCard",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(70, 48, 96),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(170, 240),
		ZIndex = 45,
		Parent = parent,
	}, { Kit.new("UICorner", { CornerRadius = UDim.new(0, 14) }), Kit.new("UIStroke", { Color = Color3.fromRGB(255, 214, 120), Thickness = 3 }) })
	local scale = Kit.new("UIScale", { Scale = 0.6, Parent = card })
	local back = Kit.label("?", { TextSize = 72, Font = Kit.Theme.FontBold, TextColor3 = Color3.fromRGB(255, 214, 120), TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 46, Parent = card })
	local face = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 46, Parent = card })
	Kit.label(heading, { TextSize = 13, TextColor3 = Color3.fromRGB(110, 96, 80), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, Position = UDim2.new(0, 8, 0, 10), Size = UDim2.new(1, -16, 0, 34), ZIndex = 47, Parent = face })
	Kit.label(title, { TextSize = 26, Font = Kit.Theme.FontBold, TextColor3 = color or Color3.fromRGB(40, 30, 24), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, Position = UDim2.new(0, 8, 0.3, 0), Size = UDim2.new(1, -16, 0.4, 0), ZIndex = 47, Parent = face })
	if subtitle then
		Kit.label(subtitle, { TextSize = 14, TextColor3 = Color3.fromRGB(110, 96, 80), TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 8, 1, -40), Size = UDim2.new(1, -16, 0, 28), ZIndex = 47, Parent = face })
	end
	-- Pop in face down, then squash to nothing on X and come back face up.
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.45, function()
		if not card.Parent then
			return
		end
		local half = TweenService:Create(card, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.fromOffset(0, 240) })
		Audio.play("flip")
		half.Completed:Once(function()
			if not card.Parent then
				return
			end
			back.Visible = false
			face.Visible = true
			card.BackgroundColor3 = Color3.fromRGB(252, 246, 230)
			TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(170, 240) }):Play()
			HudKit.shine(card, 48)
		end)
		half:Play()
	end)
	local function tuck()
		if card.Parent then
			local t = TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 })
			t.Completed:Once(function()
				card:Destroy()
			end)
			t:Play()
		end
	end
	card.Activated:Connect(tuck)
	task.delay(4.5, tuck)
end

-- A light band that sweeps across once (banners, the win title).
function HudKit.shine(object: GuiObject, z: number?)
	local band = Kit.new("Frame", {
		Name = "Shine",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z or (object.ZIndex + 1),
		Parent = object,
	}, { Kit.new("UICorner", { CornerRadius = UDim.new(0, 14) }) })
	local gradient = Kit.new("UIGradient", {
		Rotation = 20,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.55),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Offset = Vector2.new(-1, 0),
		Parent = band,
	})
	local tween = TweenService:Create(gradient, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Offset = Vector2.new(1, 0) })
	tween.Completed:Once(function()
		band:Destroy()
	end)
	tween:Play()
end

local CONFETTI = {
	Color3.fromRGB(255, 196, 64),
	Color3.fromRGB(255, 99, 132),
	Color3.fromRGB(54, 162, 235),
	Color3.fromRGB(88, 204, 120),
	Color3.fromRGB(153, 102, 255),
}

-- A burst of confetti falling over `parent` (the win screen). Cleans itself up.
function HudKit.confetti(parent: GuiObject, count: number?, z: number?)
	local size = parent.AbsoluteSize
	if size.X <= 0 then
		return
	end
	local rng = Random.new()
	for i = 1, count or 40 do
		local w = rng:NextInteger(6, 11)
		local bit = Kit.new("Frame", {
			Name = "Confetti",
			BackgroundColor3 = CONFETTI[(i % #CONFETTI) + 1],
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(rng:NextNumber(0.1, 0.9) * size.X, -rng:NextNumber(0, 0.3) * size.Y),
			Size = UDim2.fromOffset(w, math.floor(w * 1.6)),
			Rotation = rng:NextNumber(0, 360),
			ZIndex = z or 60,
			Parent = parent,
		})
		local duration = rng:NextNumber(1.4, 2.4)
		local drift = rng:NextNumber(-0.18, 0.18) * size.X
		local tween = TweenService:Create(bit, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromOffset(bit.Position.X.Offset + drift, size.Y * rng:NextNumber(0.9, 1.1)),
			Rotation = bit.Rotation + rng:NextNumber(-540, 540),
			BackgroundTransparency = 0.6,
		})
		tween.Completed:Once(function()
			bit:Destroy()
		end)
		task.delay(rng:NextNumber(0, 0.35), function()
			if bit.Parent then
				tween:Play()
			end
		end)
	end
end

-- Slides a row in from the left with a small delay (end-screen standings).
function HudKit.slideIn(object: GuiObject, delay: number)
	local scale = object:FindFirstChild("SlideScale") :: UIScale?
	if not scale then
		scale = Kit.new("UIScale", { Name = "SlideScale", Parent = object })
	end
	local s = scale :: UIScale
	s.Scale = 0.6
	if object:IsA("Frame") then
		local target = object.BackgroundTransparency
		object.BackgroundTransparency = 1
		task.delay(delay, function()
			if object.Parent then
				TweenService:Create(object, TweenInfo.new(0.25), { BackgroundTransparency = target }):Play()
			end
		end)
	end
	task.delay(delay, function()
		if s.Parent then
			TweenService:Create(s, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end)
end

return HudKit
