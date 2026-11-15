-- Math for the free-look seat camera (client/Table3D/FreeLook) and for picking things
-- with the keyboard (client/UI/KeyPick). Pure numbers, so tests/SeatLook.spec.luau can
-- check it.
--
-- Look: you sit at your seat and turn your head. The seat camera gives a resting view
-- (its yaw and pitch); the look is an offset from it, kept inside a range like a real
-- neck: so far left and right of the table, not straight up, not into your lap.
-- Angles in radians; pitch is positive looking up (Roblox's convention).

local SeatLook = {}

SeatLook.YAW_LIMIT = math.rad(100) -- each way from facing the table
SeatLook.PITCH_UP = math.rad(50) -- highest you can look, above level
SeatLook.PITCH_DOWN = math.rad(-80) -- lowest, below level
SeatLook.MOUSE = math.rad(0.22) -- per pixel of mouse movement
SeatLook.TOUCH = math.rad(0.32) -- per pixel of finger drag
SeatLook.STICK = math.rad(150) -- per second at full right stick
SeatLook.TAP_SLOP = 12 -- pixels a finger can wander and still count as a tap
SeatLook.TAP_TIME = 0.6 -- seconds a tap can last

export type Look = { yaw: number, pitch: number }

-- Keeps an offset inside the range for a resting view looking `basePitch` above level.
function SeatLook.clamp(look: Look, basePitch: number): Look
	local yaw = math.clamp(look.yaw, -SeatLook.YAW_LIMIT, SeatLook.YAW_LIMIT)
	local low = SeatLook.PITCH_DOWN - basePitch
	local high = SeatLook.PITCH_UP - basePitch
	local pitch = if low <= high then math.clamp(look.pitch, low, high) else 0
	return { yaw = yaw, pitch = pitch }
end

-- Turns by a mouse or finger movement of (dx, dy) pixels at `perPixel`: right turns
-- right (yaw goes down), down looks down.
function SeatLook.turn(look: Look, dx: number, dy: number, perPixel: number, basePitch: number): Look
	return SeatLook.clamp({ yaw = look.yaw - dx * perPixel, pitch = look.pitch - dy * perPixel }, basePitch)
end

-- Eases `from` toward `to` over dt at `rate` (higher = snappier), frame-rate independent.
function SeatLook.ease(from: Look, to: Look, dt: number, rate: number): Look
	local a = 1 - math.exp(-dt * rate)
	return { yaw = from.yaw + (to.yaw - from.yaw) * a, pitch = from.pitch + (to.pitch - from.pitch) * a }
end

-- The resting view's yaw and pitch from its look direction (x, y, z), Roblox axes: yaw 0
-- faces -z.
function SeatLook.base(x: number, y: number, z: number): (number, number)
	local yaw = math.atan2(-x, -z)
	local pitch = math.asin(math.clamp(y, -1, 1))
	return yaw, pitch
end

-- Whether a finger that moved `moved` pixels in all over `held` seconds was a tap (and
-- not a drag to look around).
function SeatLook.isTap(moved: number, held: number): boolean
	return moved <= SeatLook.TAP_SLOP and held <= SeatLook.TAP_TIME
end

---------------------------------------------------------------- keyboard picking

export type Spot = { x: number, y: number } -- a choice's place on screen, pixels, y down

-- The choice to go to from `from` (an index into `spots`, or nil for none yet) when
-- pressing toward (dx, dy) (one of the four arrows: (1, 0) is right, (0, 1) is down).
-- Picks the nearest choice that lies that way, favoring ones straight along the arrow
-- over ones off to the side. With nothing picked yet, the one nearest `center`.
function SeatLook.step(spots: { Spot }, from: number?, dx: number, dy: number, center: Spot): number?
	if #spots == 0 then
		return nil
	end
	local origin = from and spots[from]
	if not origin then
		local best, bestD = nil, math.huge
		for i, s in spots do
			local d = (s.x - center.x) ^ 2 + (s.y - center.y) ^ 2
			if d < bestD then
				best, bestD = i, d
			end
		end
		return best
	end
	local best, bestCost = nil, math.huge
	for i, s in spots do
		if i ~= from then
			local ox, oy = s.x - origin.x, s.y - origin.y
			local along = ox * dx + oy * dy
			local across = math.abs(ox * dy - oy * dx)
			-- Must be ahead (a little), and not further off to the side than ahead.
			if along > 2 and across <= along * 2 then
				local cost = along + across * 2.5
				if cost < bestCost then
					best, bestCost = i, cost
				end
			end
		end
	end
	return best or from
end

-- A row of choices in order (cards in a hand): the next one each way, wrapping around.
-- With nothing picked yet, the middle one.
function SeatLook.cycle(count: number, from: number?, delta: number): number?
	if count <= 0 then
		return nil
	end
	if not from or from < 1 or from > count then
		return math.ceil(count / 2)
	end
	return (from - 1 + delta) % count + 1
end

return SeatLook
