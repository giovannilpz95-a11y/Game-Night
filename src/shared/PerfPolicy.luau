-- Performance rules shared by the server (which sets physics and shadow flags on the
-- lobby decor and tables) and the client (which turns on a low-detail mode on slow
-- devices). Pure: plain numbers in, plain tables out, so tests can run it.
--
-- Normal quality looks the same as before: only parts too small to throw a visible shadow
-- lose CastShadow. Low-detail mode is client-only and fully reversible.

local PerfPolicy = {}

-- A part whose longest side is under this many studs throws a shadow too small to see
-- from a seat, and is too small to block anyone walking.
PerfPolicy.SMALL = 1
-- In low-detail mode, decor parts this small are hidden (knick-knacks, bulbs, buttons).
PerfPolicy.TINY = 0.6
-- In low-detail mode, decor text further away than this is not drawn.
PerfPolicy.LOW_TEXT_DISTANCE = 90

export type PartInfo = {
	className: string,
	sx: number,
	sy: number,
	sz: number,
	transparency: number,
	canCollide: boolean,
	-- Has a ProximityPrompt, ClickDetector, SurfaceGui, Decal or Texture: something a
	-- player reads or uses, so it's never hidden or made unqueryable.
	interactive: boolean?,
	hasSurface: boolean?,
	-- Enum.Material name. Neon bulbs stay in low-detail mode: they're what makes the
	-- room read as lit.
	material: string?,
}

export type Flags = {
	anchored: boolean?,
	castShadow: boolean?,
	canCollide: boolean?,
	canQuery: boolean?,
	canTouch: boolean?,
	-- Hide this part in low-detail mode.
	detail: boolean?,
}

-- Parts the policy must never touch: Roblox gives these behavior through touch.
local KEEP = {
	Seat = true,
	VehicleSeat = true,
	SpawnLocation = true,
	Terrain = true,
}

-- The flags to set on one static decor part (lobby furniture, table furniture). Fields
-- left nil keep the part's current value.
function PerfPolicy.decor(info: PartInfo): Flags
	if KEEP[info.className] then
		return {}
	end
	local flags: Flags = {
		anchored = true,
		-- Nothing in the game listens for Touched on decor, and touch tests cost every
		-- physics step a character is near them.
		canTouch = false,
	}
	local longest = math.max(info.sx, info.sy, info.sz)
	local invisible = info.transparency >= 1
	if longest < PerfPolicy.SMALL then
		flags.castShadow = false
		if not info.interactive then
			flags.canCollide = false
			-- Roblox only allows CanQuery off on parts that don't collide. Off, the camera
			-- no longer pops in front of a candle or a book.
			flags.canQuery = false
		end
	end
	if invisible then
		flags.castShadow = false
		if not info.canCollide and not info.interactive then
			flags.canQuery = false
		end
	end
	if longest < PerfPolicy.TINY and not invisible and not info.interactive and not info.hasSurface and info.material ~= "Neon" then
		flags.detail = true
	end
	return flags
end

-- What the player's own graphics slider says: true = low detail, false = normal, nil =
-- Automatic (decide from the frame rate). `level` is Enum.SavedQualitySetting's Value:
-- 0 is Automatic, 1-10 the slider.
function PerfPolicy.lowFromSetting(level: number): boolean?
	if level <= 0 then
		return nil
	end
	return level <= 3
end

-- Watches the frame rate while the graphics slider is on Automatic. Feed it every
-- frame's delta time; `add` returns true once the device has been slow for `strikes`
-- windows in a row (after a warm-up, so loading hitches don't count). Once it says
-- low it stays low: flipping back and forth would cost more than it saves.
export type Monitor = {
	add: (self: Monitor, dt: number) -> boolean,
	isLow: (self: Monitor) -> boolean,
	reset: (self: Monitor) -> (),
}

local MonitorClass = {}
MonitorClass.__index = MonitorClass

function PerfPolicy.monitor(opts: { lowFps: number?, window: number?, strikes: number?, warmup: number? }?): Monitor
	local o = opts or {}
	local self = setmetatable({
		lowFps = o.lowFps or 30,
		window = o.window or 5,
		strikes = o.strikes or 2,
		warmup = o.warmup or 10,
		elapsed = 0,
		windowTime = 0,
		frames = 0,
		slow = 0,
		low = false,
	}, MonitorClass)
	return self :: any
end

function MonitorClass.add(self: any, dt: number): boolean
	if self.low then
		return true
	end
	if type(dt) ~= "number" or dt ~= dt or dt <= 0 or dt == math.huge then
		return false
	end
	self.elapsed += dt
	if self.elapsed < self.warmup then
		return false
	end
	-- One very long frame (a tab switch, a breakpoint) shouldn't sink a whole window.
	self.windowTime += math.min(dt, 0.5)
	self.frames += 1
	if self.windowTime >= self.window then
		local fps = self.frames / self.windowTime
		self.slow = if fps < self.lowFps then self.slow + 1 else 0
		self.windowTime = 0
		self.frames = 0
		if self.slow >= self.strikes then
			self.low = true
		end
	end
	return self.low
end

function MonitorClass.isLow(self: any): boolean
	return self.low
end

function MonitorClass.reset(self: any)
	self.elapsed = 0
	self.windowTime = 0
	self.frames = 0
	self.slow = 0
	self.low = false
end

return PerfPolicy
