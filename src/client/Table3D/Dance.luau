-- Keyframe engine for the Showtime moves (Table3D/Moves): full-body R15 poses with eased
-- in-betweens, a looping section and cues (sounds, particle bursts) on the beat.
--
-- A move:
--   { length = seconds, loop = { from, to }?, keys = { Key }, cues = { { t, sound?, burst? } }? }
-- A key: { t = seconds, e = ease into this key, and joint angles in degrees:
--   N (Neck), W (Waist), R (Root: LowerTorso under the HumanoidRootPart, also takes
--   px/py/pz in studs to bounce, sway and hop), RS RE RW / LS LE LW (shoulder, elbow, wrist),
--   RH RK RA / LH LK LA (hip, knee, ankle) }. Each joint value is { x, y, z, tw? }:
--   x = forward (arms, legs) / lean back (waist) / look up (neck), z = out to the side
--   (right +, left -), y = turn, tw = twist around the limb itself (applied first).
-- Joints a key leaves out are at rest (standing straight, arms down).
-- Eases: "lin", "io" (smooth, default), "out" (snappy), "in", "back" (overshoot then
-- settle), "hold" (jumps at the end).
--
-- Sampling is plain numbers (tested in tests/Showtime.spec.luau); Dance.cframes turns a
-- sample into joint Transforms.

local Dance = {}

export type Joint = { number }
export type Key = { [string]: any }
export type Move = { length: number, loop: { number }?, keys: { Key }, cues: { any }? }

Dance.Joints = {
	N = "Neck", W = "Waist", R = "Root",
	RS = "RightShoulder", RE = "RightElbow", RW = "RightWrist",
	LS = "LeftShoulder", LE = "LeftElbow", LW = "LeftWrist",
	RH = "RightHip", RK = "RightKnee", RA = "RightAnkle",
	LH = "LeftHip", LK = "LeftKnee", LA = "LeftAnkle",
}

local MIRROR = { RS = "LS", RE = "LE", RW = "LW", RH = "LH", RK = "LK", RA = "LA" }
for a, b in table.clone(MIRROR) do
	MIRROR[b] = a
end

local function ease(kind: string?, x: number): number
	x = math.clamp(x, 0, 1)
	if kind == "lin" then
		return x
	elseif kind == "out" then
		return 1 - (1 - x) * (1 - x)
	elseif kind == "in" then
		return x * x
	elseif kind == "back" then
		local c1 = 1.70158
		local c3 = c1 + 1
		return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
	elseif kind == "hold" then
		return if x >= 1 then 1 else 0
	end
	return x * x * (3 - 2 * x)
end
Dance.ease = ease

local ZERO = { 0, 0, 0, 0, 0, 0, 0 }

-- The same key for the other side: left and right swap, turns and sideways moves flip.
function Dance.mirror(key: Key): Key
	local out: Key = {}
	for name, value in key do
		if type(value) == "table" then
			local v = table.clone(value)
			v[2] = -(v[2] or 0)
			v[3] = -(v[3] or 0)
			if v[4] then
				v[4] = -v[4]
			end
			if name == "R" and v[5] then
				v[5] = -v[5]
			end
			out[MIRROR[name] or name] = v
		else
			out[name] = value
		end
	end
	return out
end

-- Time inside the move: past the loop's end it wraps back into the loop.
function Dance.localTime(move: Move, t: number): number
	local loop = move.loop
	if loop and t > loop[2] and loop[2] > loop[1] then
		return loop[1] + (t - loop[1]) % (loop[2] - loop[1])
	end
	return math.min(t, move.length)
end

-- Joint values at time t: { [short name] = { x, y, z, tw, px, py, pz } } (degrees, studs).
function Dance.sample(move: Move, t: number): { [string]: { number } }
	local keys = move.keys
	local lt = Dance.localTime(move, t)
	local a, b = keys[1], keys[1]
	for i = 1, #keys do
		if keys[i].t <= lt then
			a = keys[i]
			b = keys[i + 1] or keys[i]
		end
	end
	if lt < keys[1].t then
		a, b = keys[1], keys[1]
	end
	local span = b.t - a.t
	local k = if span > 0 then ease(b.e, (lt - a.t) / span) else 1
	if b == a then
		k = 1
	end
	local out = {}
	for short in Dance.Joints do
		local va = a[short] or ZERO
		local vb = b[short] or ZERO
		if va ~= ZERO or vb ~= ZERO then
			local v = {}
			for i = 1, 7 do
				local x0, x1 = va[i] or 0, vb[i] or 0
				v[i] = x0 + (x1 - x0) * k
			end
			out[short] = v
		end
	end
	return out
end

-- Cues that fire between two moments (seconds since the move started); loops repeat them.
function Dance.cuesBetween(move: Move, from: number, to: number): { any }
	local hits = {}
	local cues = move.cues
	if not cues or to <= from then
		return hits
	end
	local a, b = Dance.localTime(move, from), Dance.localTime(move, to)
	local loop = move.loop
	for _, cue in cues do
		local c = cue.t
		local hit
		if b >= a then
			hit = a < c and c <= b
		else -- wrapped around the loop
			hit = (a < c and c <= (loop :: { number })[2]) or ((loop :: { number })[1] <= c and c <= b)
		end
		if hit then
			table.insert(hits, cue)
		end
	end
	return hits
end

local rad = math.rad

-- A sample as joint Transforms (full motor names), weighted toward rest by w (0..1).
function Dance.cframes(sample: { [string]: { number } }, w: number): { [string]: CFrame }
	local out = {}
	for short, v in sample do
		local cf = CFrame.new((v[5] or 0) * w, (v[6] or 0) * w, (v[7] or 0) * w)
			* CFrame.fromEulerAnglesYXZ(rad(v[1]) * w, rad(v[2]) * w, rad(v[3]) * w)
			* CFrame.Angles(0, rad(v[4] or 0) * w, 0)
		out[Dance.Joints[short]] = cf
	end
	return out
end

return Dance
