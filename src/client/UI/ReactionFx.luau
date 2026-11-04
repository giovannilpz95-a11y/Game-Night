-- Plays one animated reaction (shared/Reactions) inside an empty, see-through holder
-- frame: over a head in 3D (Table3D/HeadReactions), next to a seat chip in 2D
-- (UI/MatchView) and as a preview in the shop. Everything is laid out in scale, so the
-- holder can be any size; keep it square for emoji and about 5:2 for text.
--
-- Only TweenService and plain GUI objects: no uploaded images or animations. Emoji keep
-- their own colors, so effects (steam, tears, embers, confetti) are separate pieces.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Reactions = require(ReplicatedStorage.Shared.Reactions)

local ReactionFx = {}

local Sine, Quad, Back = Enum.EasingStyle.Sine, Enum.EasingStyle.Quad, Enum.EasingStyle.Back
local In, Out, InOut = Enum.EasingDirection.In, Enum.EasingDirection.Out, Enum.EasingDirection.InOut

local FACE_Y = 0.56 -- where the emoji sits in the holder
local CONFETTI = {
	Color3.fromRGB(255, 99, 132),
	Color3.fromRGB(255, 196, 64),
	Color3.fromRGB(75, 192, 192),
	Color3.fromRGB(54, 162, 235),
	Color3.fromRGB(153, 102, 255),
}

local function tween(obj: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?, repeats: number?, reverses: boolean?): Tween
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Quad, dir or Out, repeats or 0, reverses or false), props)
	tw:Play()
	return tw
end

-- Tweens a throwaway piece and destroys it when it's done.
local function fly(obj: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	tween(obj, t, props, style, dir).Completed:Once(function()
		obj:Destroy()
	end)
end

local function label(parent: Instance, text: string, size: number, pos: UDim2, z: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Size = UDim2.fromScale(size, size)
	l.Position = pos
	l.Text = text
	l.TextScaled = true
	l.Font = Enum.Font.GothamBlack
	l.TextColor3 = Color3.new(1, 1, 1)
	l.ZIndex = z or 2
	l.Parent = parent
	return l
end

local function dot(parent: Instance, color: Color3, size: number, pos: UDim2, transparency: number?, z: number?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(size, size)
	f.Position = pos
	f.ZIndex = z or 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = f
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.Parent = f
	f.Parent = parent
	return f
end

-- Calls fn(i) every `gap` seconds until `untilT` (os.clock) or the holder is gone.
local function every(holder: Instance, gap: number, untilT: number, fn: (number) -> ())
	task.spawn(function()
		local i = 0
		while holder.Parent and os.clock() < untilT do
			i += 1
			fn(i)
			task.wait(gap)
		end
	end)
end

local function at(x: number, y: number): UDim2
	return UDim2.fromScale(x, y)
end

local rng = Random.new()

-- Each style gets (holder, face, faceScale, endsAt). The face has already sprung in.
type Ctx = { holder: Frame, face: TextLabel, scale: UIScale, endsAt: number }
local styles: { [string]: (Ctx) -> () } = {}

function styles.steam(c: Ctx)
	-- A red glow, a furious tremble and steam out of both sides of the head.
	local glow = dot(c.holder, Color3.fromRGB(255, 60, 40), 0.7, at(0.5, FACE_Y), 0.75, 1)
	tween(glow, 0.25, { BackgroundTransparency = 0.45, Size = UDim2.fromScale(0.8, 0.8) }, Sine, InOut, -1, true)
	tween(c.scale, 0.16, { Scale = 1.1 }, Sine, InOut, -1, true)
	every(c.holder, 0.05, c.endsAt, function()
		c.face.Position = at(0.5 + rng:NextNumber(-0.025, 0.025), FACE_Y + rng:NextNumber(-0.015, 0.015))
	end)
	every(c.holder, 0.14, c.endsAt, function(i)
		local side = if i % 2 == 0 then -1 else 1
		local puff = dot(c.holder, Color3.fromRGB(240, 240, 245), 0.1, at(0.5 + side * 0.2, 0.36), 0.1, 4)
		fly(puff, 0.75, {
			Position = at(0.5 + side * rng:NextNumber(0.36, 0.48), rng:NextNumber(0.02, 0.14)),
			Size = UDim2.fromScale(0.26, 0.26),
			BackgroundTransparency = 1,
		})
	end)
end

function styles.laughCry(c: Ctx)
	-- Rocks with laughter while tears fly off both sides.
	c.face.Rotation = -14
	tween(c.face, 0.17, { Rotation = 14 }, Sine, InOut, -1, true)
	tween(c.face, 0.17, { Position = at(0.5, FACE_Y - 0.05) }, Quad, Out, -1, true)
	every(c.holder, 0.12, c.endsAt, function(i)
		local side = if i % 2 == 0 then -1 else 1
		local drop = label(c.holder, "💧", 0.15, at(0.5 + side * 0.2, FACE_Y - 0.06), 4)
		drop.Rotation = side * 40
		fly(drop, 0.55, { Position = at(0.5 + side * rng:NextNumber(0.45, 0.55), FACE_Y + 0.3), TextTransparency = 1 }, Quad, In)
	end)
end

local function drip(c: Ctx, x: number, y: number, gap: number, size: number, t: number)
	every(c.holder, gap, c.endsAt, function()
		local drop = label(c.holder, "💧", size, at(x, y), 4)
		local grow = Instance.new("UIScale")
		grow.Scale = 0.3
		grow.Parent = drop
		tween(grow, 0.2, { Scale = 1 })
		fly(drop, t, { Position = at(x, y + 0.42), TextTransparency = 0.6 }, Quad, In)
	end)
end

function styles.tear(c: Ctx)
	-- Droops a little and a single tear runs down.
	tween(c.face, 0.6, { Position = at(0.5, FACE_Y + 0.04), Rotation = -6 }, Sine, InOut)
	tween(c.scale, 0.9, { Scale = 0.94 }, Sine, InOut, -1, true)
	drip(c, 0.62, FACE_Y - 0.02, 0.7, 0.14, 0.75)
end

function styles.sob(c: Ctx)
	every(c.holder, 0.06, c.endsAt, function()
		c.face.Position = at(0.5 + rng:NextNumber(-0.012, 0.012), FACE_Y + rng:NextNumber(-0.01, 0.01))
	end)
	drip(c, 0.38, FACE_Y - 0.03, 0.16, 0.1, 0.45)
	drip(c, 0.62, FACE_Y - 0.03, 0.16, 0.1, 0.45)
end

function styles.sweat(c: Ctx)
	tween(c.face, 0.3, { Rotation = 6 }, Sine, InOut, -1, true)
	every(c.holder, 0.9, c.endsAt, function()
		local drop = label(c.holder, "💧", 0.13, at(0.76, FACE_Y - 0.2), 4)
		fly(drop, 0.85, { Position = at(0.8, FACE_Y + 0.1), TextTransparency = 1 }, Sine, In)
	end)
end

function styles.pop(c: Ctx)
	c.scale.Scale = 0.2
	tween(c.scale, 0.45, { Scale = 1.15 }, Back, Out)
	task.delay(0.45, function()
		tween(c.face, 0.12, { Rotation = 12 }, Sine, InOut, 3, true)
	end)
end

function styles.bounce(c: Ctx)
	tween(c.face, 0.22, { Position = at(0.5, FACE_Y - 0.14) }, Quad, Out, -1, true)
end

function styles.pulse(c: Ctx)
	tween(c.scale, 0.22, { Scale = 1.22 }, Sine, InOut, -1, true)
end

function styles.shake(c: Ctx)
	tween(c.scale, 0.2, { Scale = 1.12 }, Back, Out)
	every(c.holder, 0.035, c.endsAt, function()
		c.face.Position = at(0.5 + rng:NextNumber(-0.05, 0.05), FACE_Y + rng:NextNumber(-0.02, 0.02))
		c.face.Rotation = rng:NextNumber(-8, 8)
	end)
end

function styles.shiver(c: Ctx)
	every(c.holder, 0.03, c.endsAt, function()
		c.face.Position = at(0.5 + rng:NextNumber(-0.018, 0.018), FACE_Y)
	end)
	every(c.holder, 0.22, c.endsAt, function()
		local flake = label(c.holder, "❄️", 0.12, at(rng:NextNumber(0.12, 0.88), 0.04), 4)
		fly(flake, 1.1, { Position = at(flake.Position.X.Scale + rng:NextNumber(-0.1, 0.1), 1), Rotation = 180, TextTransparency = 1 }, Sine, In)
	end)
end

function styles.spin(c: Ctx)
	tween(c.face, 0.8, { Rotation = 360 }, Quad, InOut, 1)
end

function styles.wobble(c: Ctx)
	c.face.Rotation = -18
	tween(c.face, 0.32, { Rotation = 18 }, Sine, InOut, -1, true)
end

function styles.look(c: Ctx)
	c.face.Position = at(0.42, FACE_Y)
	tween(c.face, 0.4, { Position = at(0.58, FACE_Y) }, Sine, InOut, -1, true)
end

local function confettiBurst(c: Ctx, count: number)
	for _ = 1, count do
		local piece = Instance.new("Frame")
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.BorderSizePixel = 0
		piece.BackgroundColor3 = CONFETTI[rng:NextInteger(1, #CONFETTI)]
		piece.Size = UDim2.fromScale(0.05, 0.09)
		piece.Position = at(0.5, FACE_Y - 0.1)
		piece.Rotation = rng:NextNumber(0, 180)
		piece.ZIndex = 4
		piece.Parent = c.holder
		local angle = rng:NextNumber(-math.pi * 0.95, -math.pi * 0.05)
		local reach = rng:NextNumber(0.3, 0.5)
		local x, y = 0.5 + math.cos(angle) * reach, FACE_Y - 0.1 + math.sin(angle) * reach
		tween(piece, 0.35, { Position = at(x, y), Rotation = piece.Rotation + 180 }, Quad, Out).Completed:Once(function()
			fly(piece, 0.9, { Position = at(x + rng:NextNumber(-0.08, 0.08), 1.05), Rotation = piece.Rotation + 360, BackgroundTransparency = 1 }, Sine, In)
		end)
	end
end

function styles.confetti(c: Ctx)
	tween(c.face, 0.2, { Rotation = 10 }, Sine, InOut, -1, true)
	confettiBurst(c, 16)
	task.delay(0.9, function()
		if c.holder.Parent then
			confettiBurst(c, 10)
		end
	end)
end

function styles.fire(c: Ctx)
	tween(c.face, 0.09, { Size = UDim2.fromScale(0.54, 0.62) }, Sine, InOut, -1, true)
	every(c.holder, 0.08, c.endsAt, function()
		local color = if rng:NextNumber() < 0.5 then Color3.fromRGB(255, 140, 30) else Color3.fromRGB(255, 214, 64)
		local ember = dot(c.holder, color, rng:NextNumber(0.04, 0.08), at(0.5 + rng:NextNumber(-0.22, 0.22), FACE_Y + 0.12), 0, 4)
		fly(ember, 0.7, { Position = at(ember.Position.X.Scale + rng:NextNumber(-0.08, 0.08), 0.02), BackgroundTransparency = 1 }, Quad, Out)
	end)
end

function styles.hearts(c: Ctx)
	tween(c.scale, 0.3, { Scale = 1.12 }, Sine, InOut, -1, true)
	every(c.holder, 0.22, c.endsAt, function()
		local heart = label(c.holder, "❤️", rng:NextNumber(0.12, 0.18), at(0.5 + rng:NextNumber(-0.3, 0.3), FACE_Y + 0.1), 4)
		fly(heart, 1, { Position = at(heart.Position.X.Scale + rng:NextNumber(-0.1, 0.1), 0.0), TextTransparency = 1 }, Sine, Out)
	end)
end

local function sparkleRing(c: Ctx, count: number, reach: number)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		local spark = label(c.holder, "✨", 0.14, at(0.5, FACE_Y), 4)
		fly(spark, 0.6, { Position = at(0.5 + math.cos(angle) * reach, FACE_Y + math.sin(angle) * reach), TextTransparency = 1 }, Quad, Out)
	end
end

function styles.burst(c: Ctx)
	tween(c.scale, 0.5, { Scale = 1.35 }, Quad, In).Completed:Once(function()
		if c.holder.Parent then
			sparkleRing(c, 10, 0.48)
			tween(c.scale, 0.3, { Scale = 1 }, Back, Out)
			tween(c.face, 0.1, { Rotation = 8 }, Sine, InOut, 5, true)
		end
	end)
end

function styles.sparkle(c: Ctx)
	tween(c.scale, 0.5, { Scale = 1.08 }, Sine, InOut, -1, true)
	every(c.holder, 0.2, c.endsAt, function()
		local angle = rng:NextNumber(0, math.pi * 2)
		local spark = label(c.holder, "✨", 0.02, at(0.5 + math.cos(angle) * 0.38, FACE_Y + math.sin(angle) * 0.36), 4)
		tween(spark, 0.25, { Size = UDim2.fromScale(0.17, 0.17) }, Back, Out).Completed:Once(function()
			fly(spark, 0.3, { Size = UDim2.fromScale(0.02, 0.02), TextTransparency = 1 })
		end)
	end)
end

function styles.zzz(c: Ctx)
	tween(c.face, 0.8, { Position = at(0.5, FACE_Y + 0.04), Rotation = 8 }, Sine, InOut, -1, true)
	every(c.holder, 0.45, c.endsAt, function()
		local z = label(c.holder, "z", 0.1, at(0.66, FACE_Y - 0.2), 4)
		z.TextColor3 = Color3.fromRGB(160, 200, 255)
		fly(z, 1.2, { Position = at(0.92, 0.02), Size = UDim2.fromScale(0.22, 0.22), TextTransparency = 1, Rotation = 20 }, Sine, Out)
	end)
end

-- Text reactions: a speech bubble that springs in and wiggles.
local function playText(holder: Frame, reaction: Reactions.Reaction)
	local color = reaction.color or Color3.fromRGB(54, 140, 235)
	local bubble = Instance.new("Frame")
	bubble.AnchorPoint = Vector2.new(0.5, 0.5)
	bubble.Position = at(0.5, 0.45)
	bubble.Size = UDim2.fromScale(0.96, 0.78)
	bubble.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	bubble.BorderSizePixel = 0
	bubble.ZIndex = 2
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.4, 0)
	corner.Parent = bubble
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 3
	stroke.Parent = bubble
	-- The tail under the bubble.
	local tail = Instance.new("Frame")
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = at(0.5, 1)
	tail.Size = UDim2.fromScale(0.09, 0.22)
	tail.Rotation = 45
	tail.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	tail.BorderSizePixel = 0
	tail.ZIndex = 1
	local tailAspect = Instance.new("UIAspectRatioConstraint")
	tailAspect.Parent = tail
	tail.Parent = bubble
	local text = label(bubble, reaction.text or reaction.label, 1, at(0.5, 0.5), 3)
	text.Size = UDim2.fromScale(0.86, 0.7)
	text.TextColor3 = color
	bubble.Parent = holder

	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = bubble
	tween(scale, 0.35, { Scale = 1 }, Back, Out)
	bubble.Rotation = -5
	tween(bubble, 0.3, { Rotation = 5 }, Sine, InOut, -1, true)
end

-- Plays `reaction` in `holder` for `seconds`, then fades out and destroys `cleanup`
-- (the holder itself if not given).
function ReactionFx.play(holder: Frame, reaction: Reactions.Reaction, seconds: number?, cleanup: Instance?)
	local duration = seconds or Reactions.Duration
	holder.ClipsDescendants = false
	if reaction.style == "text" or not reaction.icon then
		playText(holder, reaction)
	else
		local face = label(holder, reaction.icon, 0.58, at(0.5, FACE_Y), 3)
		local scale = Instance.new("UIScale")
		scale.Scale = 0.2
		scale.Parent = face
		local ctx: Ctx = { holder = holder, face = face, scale = scale, endsAt = os.clock() + duration - 0.2 }
		tween(scale, 0.28, { Scale = 1 }, Back, Out).Completed:Once(function()
			local style = styles[reaction.style]
			if style and holder.Parent then
				style(ctx)
			end
		end)
	end

	task.delay(duration, function()
		if not holder.Parent then
			return
		end
		-- Fade everything and drift up a little.
		local fade = TweenInfo.new(0.3)
		for _, obj in holder:GetDescendants() do
			if obj:IsA("TextLabel") then
				TweenService:Create(obj, fade, { TextTransparency = 1 }):Play()
			elseif obj:IsA("Frame") then
				TweenService:Create(obj, fade, { BackgroundTransparency = 1 }):Play()
			elseif obj:IsA("UIStroke") then
				TweenService:Create(obj, fade, { Transparency = 1 }):Play()
			end
		end
		TweenService:Create(holder, fade, { Position = holder.Position - UDim2.fromOffset(0, math.floor(holder.AbsoluteSize.Y * 0.15)) }):Play()
		task.wait(0.32)
		local target = cleanup or holder
		target:Destroy()
	end)
end

-- Size (pixels) to give a holder for `reaction` when `base` is the emoji size.
function ReactionFx.size(reaction: Reactions.Reaction, base: number): Vector2
	if reaction.style == "text" or not reaction.icon then
		return Vector2.new(math.floor(base * 2.3), math.floor(base * 0.9))
	end
	return Vector2.new(base, base)
end

return ReactionFx
