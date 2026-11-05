-- Flair: the "top Roblox game" polish layer, on top of Juice (motion) and Audio.
-- Research: vault "05 Research/Top Roblox Games UI". What the biggest earners all do and
-- what lives here:
--   * rewards are physical: icons burst out and fly into the wallet, which bumps as each
--     one lands, and a "+120" floats up (Flair.flyTo, Flair.floatText);
--   * rarity is a moving color, not a word: Epic and Legendary borders spin their gradient
--     (Flair.rarityBorder, Flair.spin);
--   * big moments sit on a slowly turning burst of light (Flair.rays);
--   * the button that matters glints every few seconds, and a badge with something waiting
--     gives a little nudge now and then (Flair.idleShine, Flair.nudge);
--   * a menu over the 3D world softly blurs it (Flair.blur);
--   * headings are chunky: light-to-tint gradient fill with a dark outline (Flair.titleStyle);
--   * "MOST POPULAR" / "BEST VALUE" banners ride on top of shop tiles (Flair.banner).
-- No Kit dependency (Kit uses this), so everything is built with Instance.new.
-- Low-detail mode (client/Perf) freezes the looping motion; one-shot effects still play.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Audio = require(script.Parent.Parent.Audio)
local Perf = require(script.Parent.Parent.Perf)
local Juice = require(script.Parent.Juice)

local Flair = {}

local OUT = Enum.EasingDirection.Out

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local object = Instance.new(className)
	for key, value in props do
		(object :: any)[key] = value
	end
	if parent then
		object.Parent = parent
	end
	return object
end

local function tween(object: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local t = TweenService:Create(object, info, goal)
	t:Play()
	return t
end

-- Rarity colors as moving gradients (shop tiles, unlock cards). Rare and up spin.
Flair.Rarity = {
	Common = ColorSequence.new(Color3.fromRGB(176, 170, 204), Color3.fromRGB(214, 210, 232)),
	Rare = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(54, 162, 235)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(140, 228, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(54, 162, 235)),
	}),
	Epic = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(153, 102, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 128, 220)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(153, 102, 255)),
	}),
	Legendary = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 186, 48)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 248, 196)),
		ColorSequenceKeypoint.new(0.65, Color3.fromRGB(255, 140, 30)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 186, 48)),
	}),
}
-- How fast each tier's border turns (degrees a second); 0 = still.
Flair.RaritySpeed = { Common = 0, Rare = 40, Epic = 90, Legendary = 140 }

Flair.Gold = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 196, 64)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 250, 210)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 196, 64)),
})

--------------------------------------------------------------------------------
-- One shared loop turns every spinning thing (gradients, ray bursts), so a full shop
-- grid costs one connection. Entries drop out when their instance leaves the game.
--------------------------------------------------------------------------------

type Spinner = { object: Instance, speed: number }
local spinners: { Spinner } = {}
local loop: RBXScriptConnection? = nil

local function step(dt: number)
	if Perf.isLow() then
		return
	end
	local i = 1
	while i <= #spinners do
		local s = spinners[i]
		if s.object.Parent == nil then
			spinners[i] = spinners[#spinners]
			spinners[#spinners] = nil
		else
			local o: any = s.object
			o.Rotation = (o.Rotation + s.speed * dt) % 360
			i += 1
		end
	end
	if #spinners == 0 and loop then
		loop:Disconnect()
		loop = nil
	end
end

-- Keeps turning `object` (a UIGradient or a GuiObject) by `speed` degrees a second.
function Flair.spin(object: Instance, speed: number)
	if speed == 0 then
		return
	end
	table.insert(spinners, { object = object, speed = speed })
	if not loop then
		loop = RunService.Heartbeat:Connect(step)
	end
end

-- A gradient on a UIStroke (or any GuiObject) that turns forever: the "it's rare" shimmer.
function Flair.spinGradient(target: Instance, colors: ColorSequence, speed: number?): UIGradient
	local old = target:FindFirstChild("FlairGradient")
	if old then
		old:Destroy()
	end
	local gradient = make("UIGradient", { Name = "FlairGradient", Color = colors, Rotation = math.random(0, 359) }, target)
	Flair.spin(gradient, speed or 90)
	return gradient
end

-- Turns a tile's UIStroke into its tier's moving border. Commons stay as they are.
function Flair.rarityBorder(stroke: UIStroke, tier: string)
	local colors = Flair.Rarity[tier]
	if not colors or tier == "Common" then
		return
	end
	stroke.Color = Color3.new(1, 1, 1) -- the gradient tints white
	Flair.spinGradient(stroke, colors, Flair.RaritySpeed[tier])
end

--------------------------------------------------------------------------------
-- Ray burst: beams of light turning slowly behind a reward, a win or a featured item.
--------------------------------------------------------------------------------

-- A burst of `beams` light rays centered at `position` in `parent`, `size` pixels across.
-- Returns the holder (destroy it, or let its parent go). Fades in.
function Flair.rays(parent: Instance, color: Color3, opts: { [string]: any }?): Frame
	local o = opts or {}
	local size = o.size or 360
	local z = o.zIndex or 1
	local beams = o.beams or 12
	local holder = make("Frame", {
		Name = "Rays",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = o.position or UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		ZIndex = z,
	})
	-- Each bar crosses the whole burst (a GuiObject turns around its middle), so half as
	-- many bars as beams. Bright in the middle, gone at the tips.
	local fade = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, o.strength or 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	local bars = math.max(2, math.floor(beams / 2))
	local width = math.max(6, math.floor(size * (o.width or 0.1)))
	for i = 1, bars do
		local bar = make("Frame", {
			Name = "Beam",
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, width, 1, 0),
			Rotation = (i - 1) * 180 / bars,
			ZIndex = z,
		}, holder)
		make("UIGradient", { Rotation = 90, Transparency = fade }, bar)
	end
	-- A soft glow in the middle.
	local glow = make("Frame", {
		Name = "Glow",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 0.55,
		ZIndex = z,
	}, holder)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, glow)
	make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, glow)
	local scale = make("UIScale", { Scale = 0.4 }, holder)
	holder.Parent = parent
	tween(scale, Juice.Info.Bounce, { Scale = 1 })
	Flair.spin(holder, o.speed or 18)
	return holder
end

--------------------------------------------------------------------------------
-- Glints and nudges: the idle motion that says "this one".
--------------------------------------------------------------------------------

-- A light band that sweeps once across `object`, clipped to its rounded corners.
function Flair.sweep(object: GuiObject, z: number?)
	local corner = object:FindFirstChildOfClass("UICorner")
	local band = make("Frame", {
		Name = "Glint",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z or (object.ZIndex + 1),
	})
	make("UICorner", { CornerRadius = if corner then corner.CornerRadius else UDim.new(0, 8) }, band)
	local gradient = make("UIGradient", {
		Rotation = 25,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 1),
			NumberSequenceKeypoint.new(0.5, 0.5),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Offset = Vector2.new(-1, 0),
	}, band)
	band.Parent = object
	tween(gradient, TweenInfo.new(0.6, Enum.EasingStyle.Quad, OUT), { Offset = Vector2.new(1, 0) }).Completed:Once(function()
		band:Destroy()
	end)
end

-- Repeats a glint across `object` every `every` seconds while it's on screen (the Buy
-- button on the best pack, the Play button).
function Flair.idleShine(object: GuiObject, every: number?)
	if object:GetAttribute("FlairShine") then
		return
	end
	object:SetAttribute("FlairShine", true)
	local gap = every or 4
	task.spawn(function()
		task.wait(math.random() * gap)
		while object.Parent do
			if object.Visible and not Perf.isLow() and object.AbsoluteSize.X > 0 then
				Flair.sweep(object)
			end
			task.wait(gap)
		end
	end)
end

-- Every `every` seconds, while `object` is showing, a little wiggle and bump: a badge with
-- something to claim.
function Flair.nudge(object: GuiObject, every: number?)
	if object:GetAttribute("FlairNudge") then
		return
	end
	object:SetAttribute("FlairNudge", true)
	local gap = every or 5
	task.spawn(function()
		while object.Parent do
			task.wait(gap)
			if object.Visible and not Perf.isLow() then
				Juice.bump(object, 0.25)
				Juice.wiggle(object)
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Rewards you can see arriving.
--------------------------------------------------------------------------------

local function overlayFor(target: GuiObject): Frame?
	local screen = target:FindFirstAncestorOfClass("ScreenGui")
	if not screen then
		return nil
	end
	local overlay = screen:FindFirstChild("FlairOverlay")
	if not overlay then
		overlay = make("Frame", {
			Name = "FlairOverlay",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 95,
			Active = false,
		}, screen)
	end
	return overlay :: Frame
end

local function center(object: GuiObject): Vector2
	return object.AbsolutePosition + object.AbsoluteSize / 2
end

export type FlyOptions = {
	make: () -> GuiObject, -- builds one flying icon
	count: number?, -- icons (1-12)
	from: Vector2?, -- screen pixels; default: the middle of the screen
	onArrive: ((index: number, last: boolean) -> ())?,
}

-- Icons burst out of `from`, hang for a beat, then swoop into `target` one after another.
-- Each landing bumps the target and dings a little higher. Returns the seconds until the
-- first one lands (0 if nothing flew: no screen, or the target is hidden).
function Flair.flyTo(target: GuiObject, opts: FlyOptions): number
	local overlay = overlayFor(target)
	if not overlay or target.AbsoluteSize.X <= 0 or not target.Visible then
		return 0
	end
	local count = math.clamp(math.floor(opts.count or 6), 1, 12)
	local from = opts.from or (overlay.AbsoluteSize / 2)
	local rng = Random.new()
	local BURST, HANG, FLY, GAP = 0.32, 0.12, 0.45, 0.06
	local landed = 0
	for i = 1, count do
		local icon = opts.make()
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromOffset(from.X, from.Y)
		icon.ZIndex = 96
		for _, d in icon:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 97
			end
		end
		local scale = make("UIScale", { Scale = 0.2 }, icon)
		icon.Parent = overlay
		local angle = rng:NextNumber(0, math.pi * 2)
		local reach = rng:NextNumber(40, 110)
		local burst = from + Vector2.new(math.cos(angle), math.sin(angle)) * reach
		tween(scale, TweenInfo.new(BURST, Enum.EasingStyle.Back, OUT), { Scale = 1.15 })
		tween(icon, TweenInfo.new(BURST, Enum.EasingStyle.Quart, OUT), {
			Position = UDim2.fromOffset(burst.X, burst.Y),
			Rotation = rng:NextNumber(-25, 25),
		})
		task.delay(BURST + HANG + (i - 1) * GAP, function()
			if not icon.Parent then
				return
			end
			local goal = if target.Parent then center(target) else from
			tween(scale, TweenInfo.new(FLY, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.55 })
			tween(icon, TweenInfo.new(FLY, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(goal.X, goal.Y),
				Rotation = 0,
			}).Completed:Once(function()
				icon:Destroy()
				landed += 1
				if target.Parent then
					Juice.bump(target, 0.14)
				end
				Audio.play("coin")
				if opts.onArrive then
					opts.onArrive(landed, landed == count)
				end
			end)
		end)
	end
	return BURST + HANG + FLY
end

-- "+120" rising and fading at `position` (screen pixels) over `target`'s screen.
function Flair.floatText(target: GuiObject, text: string, position: Vector2, color: Color3?)
	local overlay = overlayFor(target)
	if not overlay then
		return
	end
	local label = make("TextLabel", {
		Name = "FloatText",
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.FredokaOne,
		TextSize = 24,
		TextColor3 = color or Color3.fromRGB(255, 226, 120),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(position.X, position.Y),
		Size = UDim2.fromOffset(160, 32),
		ZIndex = 98,
	})
	make("UIStroke", { Color = Color3.fromRGB(30, 20, 40), Thickness = 2.5 }, label)
	local scale = make("UIScale", { Scale = 0.3 }, label)
	label.Parent = overlay
	tween(scale, Juice.Info.Bounce, { Scale = 1 })
	tween(label, TweenInfo.new(1.1, Enum.EasingStyle.Quad, OUT), { Position = UDim2.fromOffset(position.X, position.Y + 34) })
	task.delay(0.7, function()
		if label.Parent then
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				tween(stroke, TweenInfo.new(0.4), { Transparency = 1 })
			end
			tween(label, TweenInfo.new(0.4), { TextTransparency = 1 }).Completed:Once(function()
				label:Destroy()
			end)
		end
	end)
end

--------------------------------------------------------------------------------
-- Menus over the world.
--------------------------------------------------------------------------------

local blurKeys: { [string]: GuiObject | boolean } = {}
local BLUR_SIZE = 10
local blurOn = false
local watching = false

-- True when `object` and everything above it is shown (a window inside a hidden lobby
-- frame doesn't count).
local function onScreen(object: GuiObject): boolean
	local node: Instance? = object
	while node do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		elseif node:IsA("ScreenGui") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

local function updateBlur()
	local any = false
	for key, object in blurKeys do
		if typeof(object) == "Instance" then
			if object.Parent == nil then
				blurKeys[key] = nil
			elseif onScreen(object :: GuiObject) then
				any = true
			end
		else
			any = true
		end
	end
	any = any and not Perf.isLow()
	local blur = Lighting:FindFirstChild("GameNightMenuBlur") :: BlurEffect?
	if not blur then
		blur = make("BlurEffect", { Name = "GameNightMenuBlur", Size = 0 }, Lighting)
	end
	if any ~= blurOn then
		blurOn = any
		tween(blur :: BlurEffect, if any then Juice.Info.Fade else Juice.Info.Close, { Size = if any then BLUR_SIZE else 0 })
	end
	-- While a window is registered, look again now and then: its frame might be hidden
	-- from above (the lobby goes away when a match starts).
	if next(blurKeys) ~= nil and not watching then
		watching = true
		task.delay(0.5, function()
			watching = false
			updateBlur()
		end)
	end
end

-- Soft-blurs the 3D world while any menu that asked for it (`key`) is open. Pass the
-- window as `object` so the blur also lifts if the window gets hidden some other way.
function Flair.blur(key: string, on: boolean, object: GuiObject?)
	blurKeys[key] = if on then (object or true) else nil
	updateBlur()
end

--------------------------------------------------------------------------------
-- Look.
--------------------------------------------------------------------------------

-- A chunky heading: white at the top fading to `tint` at the bottom, with a dark outline.
function Flair.titleStyle(label: TextLabel, tint: Color3?, outline: Color3?)
	local old = label:FindFirstChild("TitleGradient")
	if old then
		old:Destroy()
	end
	label.TextColor3 = Color3.new(1, 1, 1)
	make("UIGradient", {
		Name = "TitleGradient",
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), tint or Color3.fromRGB(255, 214, 120)),
	}, label)
	if not label:FindFirstChild("TitleStroke") then
		make("UIStroke", {
			Name = "TitleStroke",
			Color = outline or Color3.fromRGB(40, 24, 56),
			Thickness = 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		}, label)
	end
end

-- A pill banner sitting on the top edge of a tile ("MOST POPULAR", "BEST VALUE"), with a
-- gradient fill and a glint every few seconds.
function Flair.banner(parent: GuiObject, text: string, from: Color3, to: Color3): Frame
	local z = parent.ZIndex + 3
	local pill = make("Frame", {
		Name = "Banner",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0.86, 0, 0, 20),
		ZIndex = z,
	})
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pill)
	make("UIGradient", { Color = ColorSequence.new(from, to) }, pill) -- tints the fill only
	make("UIStroke", { Color = Color3.fromRGB(40, 24, 56), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pill)
	local label = make("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.FredokaOne,
		TextSize = 12,
		TextColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 1,
	}, pill)
	make("UIStroke", { Color = Color3.fromRGB(40, 24, 56), Thickness = 1.5 }, label)
	pill.Parent = parent
	Flair.idleShine(pill, 3.5)
	return pill
end

return Flair
