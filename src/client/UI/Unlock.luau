-- The "it's yours!" moment the top Roblox games make of every purchase, unlock and level
-- up: the screen dims, a burst of light turns behind a big tier-colored badge, the item
-- name pops in, confetti falls. Tap anywhere (or wait) to carry on.
-- Several in a row queue up; at a table it's a compact banner that doesn't cover the game.
-- Research: vault "05 Research/Top Roblox Games UI". The server has already given the item;
-- this only shows it (client/Main diffs the wallet state to find what's new).

local TweenService = game:GetService("TweenService")

local Audio = require(script.Parent.Parent.Audio)
local Flair = require(script.Parent.Flair)
local HudKit = require(script.Parent.HudKit)
local Kit = require(script.Parent.Kit)
local Juice = Kit.Juice

local Unlock = {}

export type Entry = {
	heading: string, -- "NEW!", "UNLOCKED", "LEVEL UP!"
	title: string, -- the item's name
	icon: string, -- an emoji for the badge
	color: Color3, -- tier color
	tier: string?, -- Common | Rare | Epic | Legendary (moving border, tag)
	subtitle: string?,
	compact: boolean?, -- at a table: a banner across the top instead of the full screen
}

local queue: { Entry } = {}
local showing = false
local screen: Instance? = nil

local showNext: () -> ()

local function full(parent: Instance, entry: Entry, done: () -> ())
	local overlay = Kit.new("TextButton", {
		Name = "Unlock",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(12, 8, 24),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 80,
		Parent = parent,
	})
	Juice.tween(overlay, Juice.Info.Fade, { BackgroundTransparency = 0.35 })
	Flair.blur("unlock", true)
	local short = math.min(overlay.AbsoluteSize.X, overlay.AbsoluteSize.Y)
	local burst = math.clamp(short * 0.95, 260, 620)
	Flair.rays(overlay, entry.color, { size = burst, zIndex = 81, position = UDim2.fromScale(0.5, 0.42), beams = 16, speed = 14 })

	local stack = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromOffset(320, 330),
		ZIndex = 82,
		Parent = overlay,
	})
	local scale = Kit.new("UIScale", { Scale = 0.3, Parent = stack })

	local heading = Kit.label(entry.heading, {
		Font = Kit.Theme.FontTitle,
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		Size = UDim2.new(1, 0, 0, 40),
		ZIndex = 84,
		Parent = stack,
	})
	Flair.titleStyle(heading, entry.color)

	local badge = Kit.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(46, 32, 72),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 52),
		Size = UDim2.fromOffset(132, 132),
		ZIndex = 83,
		Parent = stack,
	}, { Kit.corner(28) })
	Kit.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(entry.color:Lerp(Color3.new(1, 1, 1), 0.25), entry.color:Lerp(Color3.new(0, 0, 0), 0.45)),
		Parent = badge,
	})
	local ring = Kit.new("UIStroke", { Color = entry.color, Thickness = 4, Parent = badge })
	Flair.spinGradient(ring, Flair.Rarity[entry.tier or ""] or Flair.Gold, 160)
	Kit.label(entry.icon, {
		TextSize = 70,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 84,
		Parent = badge,
	})

	local title = Kit.label(entry.title, {
		Font = Kit.Theme.FontTitle,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, 196),
		Size = UDim2.new(1, 0, 0, 34),
		ZIndex = 84,
		Parent = stack,
	})
	Kit.new("UIStroke", { Color = Color3.fromRGB(30, 20, 40), Thickness = 2, Parent = title })
	local y = 234
	if entry.tier then
		Kit.tag(string.upper(entry.tier), entry.color, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, y),
			ZIndex = 84,
			Parent = stack,
		})
		y += 26
	end
	if entry.subtitle then
		Kit.label(entry.subtitle, {
			TextSize = 15,
			TextColor3 = Color3.fromRGB(230, 222, 250),
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 0, 0, y),
			Size = UDim2.new(1, 0, 0, 40),
			ZIndex = 84,
			Parent = stack,
		})
	end
	local hint = Kit.label("Tap to continue", {
		TextSize = 14,
		TextColor3 = Color3.fromRGB(200, 190, 230),
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(240, 20),
		TextTransparency = 1,
		ZIndex = 84,
		Parent = overlay,
	})

	TweenService:Create(scale, Juice.Info.Bounce, { Scale = 1 }):Play()
	Audio.play("callout")
	Audio.coins(3)
	task.delay(0.25, function()
		if badge.Parent then
			Flair.sweep(badge, 85)
			HudKit.confetti(overlay, 60, 86)
		end
	end)
	task.delay(0.9, function()
		if hint.Parent then
			Juice.tween(hint, Juice.Info.Fade, { TextTransparency = 0 })
		end
	end)

	local closed = false
	local opened = os.clock()
	local function close()
		if closed then
			return
		end
		closed = true
		Flair.blur("unlock", false)
		Juice.tween(overlay, Juice.Info.Close, { BackgroundTransparency = 1 })
		TweenService:Create(scale, Juice.Info.Close, { Scale = 0 }):Play()
		for _, d in overlay:GetDescendants() do
			if d:IsA("TextLabel") then
				Juice.tween(d, Juice.Info.Close, { TextTransparency = 1 })
			end
		end
		task.delay(0.16, function()
			overlay:Destroy()
			done()
		end)
	end
	overlay.Activated:Connect(function()
		-- A tap that was already on its way (buying, then tapping again) shouldn't skip it.
		if os.clock() - opened > 0.6 then
			close()
		end
	end)
	task.delay(5, close)
end

local function compact(parent: Instance, entry: Entry, done: () -> ())
	local card = Kit.new("Frame", {
		Name = "UnlockBanner",
		BackgroundColor3 = Color3.fromRGB(46, 32, 72),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(300, 64),
		ClipsDescendants = false,
		ZIndex = 80,
		Parent = parent,
	}, { Kit.corner(16) })
	local ring = Kit.new("UIStroke", { Color = entry.color, Thickness = 3, Parent = card })
	Flair.spinGradient(ring, Flair.Rarity[entry.tier or ""] or Flair.Gold, 160)
	Kit.label(entry.icon, { TextSize = 34, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(56, 52), ZIndex = 82, Parent = card })
	local heading = Kit.label(entry.heading, { Font = Kit.Theme.FontTitle, TextSize = 16, TextWrapped = false, Position = UDim2.fromOffset(68, 8), Size = UDim2.new(1, -76, 0, 22), ZIndex = 82, Parent = card })
	Flair.titleStyle(heading, entry.color)
	Kit.label(entry.title, { Font = Kit.Theme.FontBold, TextSize = 15, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(68, 32), Size = UDim2.new(1, -76, 0, 22), ZIndex = 82, Parent = card })
	Juice.popIn(card)
	Audio.play("callout")
	task.delay(0.2, function()
		if card.Parent then
			Flair.sweep(card, 83)
		end
	end)
	task.delay(3, function()
		Juice.popOut(card, function()
			card:Destroy()
			done()
		end)
	end)
end

function showNext()
	local entry = table.remove(queue, 1)
	if not entry or not screen then
		showing = false
		return
	end
	showing = true
	local show = if entry.compact then compact else full
	show(screen, entry, function()
		task.delay(0.15, showNext)
	end)
end

-- Where the moments are drawn (the main ScreenGui). Call once.
function Unlock.init(parent: Instance)
	screen = parent
end

-- Queues one moment. They play one after another.
function Unlock.show(entry: Entry)
	-- Never let a pile build up (say, a bundle of nine packs): Main sums those into one.
	if #queue >= 4 then
		return
	end
	table.insert(queue, entry)
	if not showing then
		showNext()
	end
end

return Unlock
