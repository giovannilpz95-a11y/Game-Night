-- Screen layout facts shared by the HUD and the match screen: the screen size, whether
-- we're on a small (phone) screen, the free strip inside Roblox's top bar, and the
-- device safe area (notches, rounded corners).
--
-- Everything is in the offset space of an IgnoreGuiInset ScreenGui (0,0 = top-left of
-- the whole screen), which is what our main ScreenGui uses.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local Layout = {}

export type Info = {
	width: number,
	height: number,
	compact: boolean, -- phone-sized: tighter spacing, smaller labels
	-- The free part of Roblox's top bar, between its own buttons. Our match header and
	-- wallet sit in it so they don't cost any height.
	barX: number,
	barY: number,
	barW: number,
	barH: number,
	top: number, -- first free y below the top bar
	left: number, -- device safe insets
	right: number,
	bottom: number,
}

local COMPACT_HEIGHT = 540
local COMPACT_WIDTH = 800

local current: Info = {
	width = 1280,
	height = 720,
	compact = false,
	barX = 120,
	barY = 6,
	barW = 1040,
	barH = 44,
	top = 58,
	left = 0,
	right = 0,
	bottom = 0,
}
local listeners: { (Info) -> () } = {}
local started = false

-- Rough check used before init (and by tests): is this a phone-sized screen?
function Layout.isCompact(width: number, height: number): boolean
	return height < COMPACT_HEIGHT or width < COMPACT_WIDTH
end

local function compute(screen: ScreenGui, probe: Frame?, full: Frame?)
	local size = screen.AbsoluteSize
	local width, height = size.X, size.Y
	if width <= 0 or height <= 0 then
		return
	end

	local left, right, bottom = 0, 0, 0
	if probe and full then
		-- Difference between a full-screen frame and one inside the device safe area.
		local fp, fs = full.AbsolutePosition, full.AbsoluteSize
		local pp, ps = probe.AbsolutePosition, probe.AbsoluteSize
		if ps.X > 0 and ps.Y > 0 then
			left = math.max(0, pp.X - fp.X)
			right = math.max(0, (fp.X + fs.X) - (pp.X + ps.X))
			bottom = math.max(0, (fp.Y + fs.Y) - (pp.Y + ps.Y))
		end
	end

	local barX, barY, barW, barH = 0, 0, 0, 0
	local ok, inset = pcall(function()
		return GuiService.TopbarInset
	end)
	if ok and typeof(inset) == "Rect" and inset.Width > 80 and inset.Height > 20 then
		barX, barY, barW, barH = inset.Min.X, inset.Min.Y, inset.Width, inset.Height
	else
		-- No top bar info (old client or top bar hidden): leave room for Roblox's buttons.
		barX, barY, barW, barH = math.max(left, 12) + 100, 4, width - math.max(left, 12) - 112 - right, 44
	end
	-- Keep the strip within the screen and a little inset from Roblox's buttons.
	barX += 4
	barW = math.max(120, barW - 8)

	current = {
		width = width,
		height = height,
		compact = Layout.isCompact(width, height),
		barX = barX,
		barY = barY,
		barW = barW,
		barH = barH,
		top = barY + barH + 6,
		left = left,
		right = right,
		bottom = bottom,
	}
	for _, listener in listeners do
		task.spawn(listener, current)
	end
end

-- Call once with the main (IgnoreGuiInset) ScreenGui.
function Layout.init(screen: ScreenGui)
	if started then
		return
	end
	started = true

	-- A hidden full-screen frame and a frame inside the device safe area, to measure notches.
	local full = Instance.new("Frame")
	full.Name = "LayoutProbe"
	full.BackgroundTransparency = 1
	full.Size = UDim2.fromScale(1, 1)
	full.Active = false
	full.Parent = screen

	local probeGui = Instance.new("ScreenGui")
	probeGui.Name = "GameNightSafeArea"
	probeGui.ResetOnSpawn = false
	probeGui.IgnoreGuiInset = true
	pcall(function()
		probeGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)
	local probe = Instance.new("Frame")
	probe.BackgroundTransparency = 1
	probe.Size = UDim2.fromScale(1, 1)
	probe.Active = false
	probe.Parent = probeGui
	probeGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local queued = false
	local function update()
		if queued then
			return
		end
		queued = true
		task.defer(function()
			queued = false
			compute(screen, probe, full)
		end)
	end
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	probe:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	probe:GetPropertyChangedSignal("AbsolutePosition"):Connect(update)
	pcall(function()
		GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(update)
	end)
	compute(screen, probe, full)
end

function Layout.get(): Info
	return current
end

-- Calls `listener(info)` now and whenever the screen changes (rotation, window resize).
function Layout.onChange(listener: (Info) -> ())
	table.insert(listeners, listener)
	task.spawn(listener, current)
end

return Layout
