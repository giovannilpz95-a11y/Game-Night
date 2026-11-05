-- The Showtime moves (shared/Showtime): the poses players strike in the game-start intro
-- and the celebrations winners do at the end. Like the other gestures in Avatars, they're
-- procedural: joint angles on the seated R15 body (upper body, plus a little leg bounce),
-- added on top of the sitting animation. No animation assets.
--
-- Each move is build(t, w, rel) -> pose, where t is seconds since it started, w the fade
-- in/out weight, and rel(x, y, z, w) a joint rotation (radians) scaled by w. Rough sign
-- guide, from the existing gestures: Shoulder x = arm forward/up, z = arm out to the side
-- and up (right +, left -); Elbow x = bend; Neck x = look up, y = turn, z = tilt;
-- Waist x = lean back, y = twist, z = side lean; Wrist z = wiggle.
--
-- Avatars turns every entry into a gesture named by its id (Showtime.PoseSeconds or
-- Showtime.VictorySeconds long). tests/Showtime.spec.luau checks every Showtime id has one.

type Rel = (number, number, number, number) -> any
type Build = (t: number, w: number, rel: Rel) -> { [string]: any }

local Moves = {}

local sin, abs, floor, pi = math.sin, math.abs, math.floor, math.pi

-- 0 or 1, switching every `period` seconds (for snappy two-beat moves).
local function beat(t: number, period: number): number
	return floor(t / period) % 2
end

-- A soft bounce in the knees, for celebrations.
local function knees(pose: { [string]: any }, t: number, w: number, rel: Rel, speed: number, amount: number)
	pose.RightKnee = rel(sin(t * speed) * amount, 0, 0, w)
	pose.LeftKnee = rel(-sin(t * speed) * amount, 0, 0, w)
	return pose
end

---------------------------------------------------------------- intro poses

local poses: { [string]: Build } = {}

poses.pose_wave = function(t, w, rel)
	return {
		RightShoulder = rel(0, 0, 2.5 + sin(t * 12) * 0.3, w),
		RightElbow = rel(0.4, 0, 0, w),
		RightWrist = rel(0, 0, sin(t * 12) * 0.25, w),
		Neck = rel(0.1, 0, -0.14, w),
		Waist = rel(0.04, 0, -0.06, w),
	}
end

poses.pose_thumbs = function(t, w, rel)
	local pump = sin(t * 7) * 0.1
	return {
		RightShoulder = rel(0.95 + pump, 0.2, 0.15, w),
		LeftShoulder = rel(0.95 + pump, -0.2, -0.15, w),
		RightElbow = rel(1.45, 0, 0, w),
		LeftElbow = rel(1.45, 0, 0, w),
		Neck = rel(0.12, 0, sin(t * 3.5) * 0.08, w),
		Waist = rel(0.08, 0, 0, w),
	}
end

poses.pose_flex = function(t, w, rel)
	local squeeze = 0.12 * sin(t * 9)
	return {
		RightShoulder = rel(0.25, 0.9, 1.45 + squeeze, w),
		LeftShoulder = rel(0.25, -0.9, -(1.45 + squeeze), w),
		RightElbow = rel(1.9, 0, 0, w),
		LeftElbow = rel(1.9, 0, 0, w),
		Neck = rel(0.12, sin(t * 2.5) * 0.25, 0, w),
		Waist = rel(0.12, 0, 0, w),
	}
end

poses.pose_peace = function(t, w, rel)
	return {
		RightShoulder = rel(1.05, 0.15, 0.55, w),
		RightElbow = rel(1.55, 0, 0, w),
		RightWrist = rel(0, 0, sin(t * 6) * 0.15, w),
		LeftShoulder = rel(0.1, 0, -0.35, w),
		Neck = rel(0.08, 0.1, 0.22, w),
		Waist = rel(0.04, 0, 0.08, w),
	}
end

poses.pose_superstar = function(t, w, rel)
	local reach = math.min(1, t / 0.5)
	return {
		RightShoulder = rel(0.25, 0, 2.95 * reach, w),
		RightElbow = rel(0.05, 0, 0, w),
		LeftShoulder = rel(-0.1, 0.3, -0.45, w),
		LeftElbow = rel(1.25, 0, 0, w),
		Neck = rel(0.4, 0, -0.1, w),
		Waist = rel(0.16, 0, -0.06, w),
	}
end

poses.pose_cool = function(t, w, rel)
	return {
		RightShoulder = rel(0.85, 0.75, 0, w),
		LeftShoulder = rel(0.8, -0.75, 0, w),
		RightElbow = rel(1.9, 0, 0, w),
		LeftElbow = rel(1.95, 0, 0, w),
		Neck = rel(0.12 + sin(t * 4) * 0.06, 0.15, 0.1, w),
		Waist = rel(0.22, 0, 0, w),
	}
end

poses.pose_heart = function(t, w, rel)
	return {
		RightShoulder = rel(1.6, 0.4, 0, w),
		LeftShoulder = rel(1.6, -0.4, 0, w),
		RightElbow = rel(1.25, 0, 0, w),
		LeftElbow = rel(1.25, 0, 0, w),
		Neck = rel(0.05, 0, sin(t * 3) * 0.15, w),
		Waist = rel(0.02, 0, sin(t * 3) * 0.06, w),
	}
end

poses.pose_tada = function(t, w, rel)
	local jazz = sin(t * 22) * 0.45
	return {
		RightShoulder = rel(0.35, 0, 1.9, w),
		LeftShoulder = rel(0.35, 0, -1.9, w),
		RightElbow = rel(0.5, 0, 0, w),
		LeftElbow = rel(0.5, 0, 0, w),
		RightWrist = rel(0, 0, jazz, w),
		LeftWrist = rel(0, 0, -jazz, w),
		Neck = rel(0.2, 0, 0, w),
		Waist = rel(0.12, 0, 0, w),
	}
end

poses.pose_bow = function(t, w, rel)
	-- Flourish out, bow down, come back up proud.
	local down = math.clamp((t - 0.35) / 0.4, 0, 1) * (1 - math.clamp((t - 1.5) / 0.4, 0, 1))
	return {
		Waist = rel(-0.55 * down + 0.06 * (1 - down), 0, 0, w),
		Neck = rel(-0.3 * down + 0.15 * (1 - down), 0, 0, w),
		RightShoulder = rel(0.9, 0.55, 0.1, w),
		RightElbow = rel(1.7, 0, 0, w),
		LeftShoulder = rel(0.3, 0, -1.5 + down * 0.3, w),
		LeftElbow = rel(0.25, 0, 0, w),
		LeftWrist = rel(0, 0, sin(t * 8) * 0.3, w),
	}
end

poses.pose_challenge = function(t, w, rel)
	-- Point at the table, then beckon: "come on".
	local beckon = if t > 1 then 0.6 + sin((t - 1) * 12) * 0.55 else 0.08
	return {
		RightShoulder = rel(1.5, 0, 0.1, w),
		RightElbow = rel(beckon, 0, 0, w),
		Neck = rel(-0.06, 0, 0.1, w),
		Waist = rel(-0.08, 0, 0, w),
		LeftShoulder = rel(0.1, 0.3, -0.4, w),
		LeftElbow = rel(1.3, 0, 0, w),
	}
end

poses.pose_thinker = function(t, w, rel)
	return {
		RightShoulder = rel(0.95, 0.4, 0, w),
		RightElbow = rel(2.15, 0, 0, w),
		LeftShoulder = rel(0.7, -0.6, 0, w),
		LeftElbow = rel(1.6, 0, 0, w),
		Neck = rel(0.15 + sin(t * 2) * 0.04, 0.2, 0.12, w),
		Waist = rel(-0.04, 0, 0, w),
	}
end

poses.pose_boxer = function(t, w, rel)
	-- Guard up, bob and weave, a quick jab.
	local jab = math.max(0, sin(t * 5)) ^ 6
	return {
		RightShoulder = rel(1.0 + jab * 0.5, 0.3, 0, w),
		LeftShoulder = rel(1.0, -0.3, 0, w),
		RightElbow = rel(2.0 - jab * 1.8, 0, 0, w),
		LeftElbow = rel(2.0, 0, 0, w),
		Waist = rel(-0.06, sin(t * 7) * 0.12, sin(t * 3.5) * 0.08, w),
		Neck = rel(-0.1, 0, 0, w),
	}
end

---------------------------------------------------------------- celebrations

local dances: { [string]: Build } = {}

dances.win_pump = function(t, w, rel)
	local r, l = sin(t * 10), sin(t * 10 + pi)
	return knees({
		RightShoulder = rel(0.2, 0, 2.55 + r * 0.3, w),
		LeftShoulder = rel(0.2, 0, -(2.55 + l * 0.3), w),
		RightElbow = rel(0.5 + abs(r) * 0.5, 0, 0, w),
		LeftElbow = rel(0.5 + abs(l) * 0.5, 0, 0, w),
		Neck = rel(0.3, 0, sin(t * 5) * 0.1, w),
		Waist = rel(0.1 + abs(sin(t * 10)) * 0.06, 0, 0, w),
	}, t, w, rel, 10, 0.15)
end

dances.win_clap = function(t, w, rel)
	local open = 0.5 + 0.5 * sin(t * 15)
	return knees({
		RightShoulder = rel(1.35, 0.45 - open * 0.3, 0, w),
		LeftShoulder = rel(1.35, -(0.45 - open * 0.3), 0, w),
		RightElbow = rel(0.55, 0, 0, w),
		LeftElbow = rel(0.55, 0, 0, w),
		Neck = rel(0.2, sin(t * 4) * 0.2, 0, w),
		Waist = rel(0.06 + abs(sin(t * 7.5)) * 0.06, 0, sin(t * 3.75) * 0.06, w),
	}, t, w, rel, 7.5, 0.12)
end

dances.win_roof = function(t, w, rel)
	local push = math.max(0, sin(t * 8))
	return knees({
		RightShoulder = rel(0.2, 0, 2.3 + push * 0.35, w),
		LeftShoulder = rel(0.2, 0, -(2.3 + push * 0.35), w),
		RightElbow = rel(1.3 - push * 1.0, 0, 0, w),
		LeftElbow = rel(1.3 - push * 1.0, 0, 0, w),
		Neck = rel(0.2 + sin(t * 8) * 0.12, 0, 0, w),
		Waist = rel(0.08, 0, 0, w),
	}, t, w, rel, 8, 0.15)
end

dances.win_sprinkler = function(t, w, rel)
	-- Hand behind the head, the other arm out front ticking across, then whipping back.
	local cycle = (t % 1.6) / 1.6
	local sweep = if cycle < 0.8 then -0.5 + floor(cycle / 0.1) * 0.125 else 0.5 - (cycle - 0.8) / 0.2 * 1.0
	return {
		LeftShoulder = rel(0.3, 0, -2.3, w),
		LeftElbow = rel(2.0, 0, 0, w),
		RightShoulder = rel(1.5, 0, 0.05, w),
		RightElbow = rel(0.1, 0, 0, w),
		Waist = rel(0.05, sweep, 0, w),
		Neck = rel(0.05, sweep * 0.5, 0, w),
	}
end

dances.win_robot = function(t, w, rel)
	local step = floor(t * 4) % 4
	local rx = ({ 0.3, 1.5, 1.5, 0.3 })[step + 1]
	local lx = ({ 1.5, 0.3, 0.3, 1.5 })[step + 1]
	local head = ({ -0.35, 0, 0.35, 0 })[step + 1]
	return {
		RightShoulder = rel(rx, 0, 0.1, w),
		LeftShoulder = rel(lx, 0, -0.1, w),
		RightElbow = rel(1.57, 0, 0, w),
		LeftElbow = rel(1.57, 0, 0, w),
		Neck = rel(0, head, 0, w),
		Waist = rel(0, -head * 0.4, 0, w),
	}
end

dances.win_disco = function(t, w, rel)
	local up = beat(t, 0.45) == 0
	return knees({
		RightShoulder = if up then rel(0.3, 0, 2.6, w) else rel(0.7, -0.6, 0.3, w),
		RightElbow = rel(0.08, 0, 0, w),
		LeftShoulder = rel(-0.1, 0.3, -0.45, w),
		LeftElbow = rel(1.25, 0, 0, w),
		Neck = if up then rel(0.3, 0, -0.1, w) else rel(-0.2, -0.2, 0.1, w),
		Waist = rel(0.05, 0, if up then -0.1 else 0.1, w),
	}, t, w, rel, pi / 0.45, 0.2)
end

dances.win_groove = function(t, w, rel)
	local s = sin(t * 6)
	return knees({
		Waist = rel(0.04, s * 0.25, sin(t * 3) * 0.1, w),
		RightShoulder = rel(0.5 + s * 0.35, 0, 0.2, w),
		LeftShoulder = rel(0.5 - s * 0.35, 0, -0.2, w),
		RightElbow = rel(1.4, 0, 0, w),
		LeftElbow = rel(1.4, 0, 0, w),
		Neck = rel(sin(t * 12) * 0.12, -s * 0.15, 0, w),
	}, t, w, rel, 6, 0.25)
end

dances.win_champion = function(t, w, rel)
	-- Trophy overhead (both hands up together), pumping; then a big double flex.
	if t < 3 then
		local pump = sin(t * 7) * 0.15
		return {
			RightShoulder = rel(0.3, 0.25, 2.75 + pump, w),
			LeftShoulder = rel(0.3, -0.25, -(2.75 + pump), w),
			RightElbow = rel(0.55, 0, 0, w),
			LeftElbow = rel(0.55, 0, 0, w),
			Neck = rel(0.4, 0, 0, w),
			Waist = rel(0.14, 0, 0, w),
		}
	end
	local squeeze = 0.12 * sin(t * 9)
	return knees({
		RightShoulder = rel(0.25, 0.9, 1.45 + squeeze, w),
		LeftShoulder = rel(0.25, -0.9, -(1.45 + squeeze), w),
		RightElbow = rel(1.9, 0, 0, w),
		LeftElbow = rel(1.9, 0, 0, w),
		Neck = rel(0.2, sin(t * 3) * 0.3, 0, w),
		Waist = rel(0.14, 0, 0, w),
	}, t, w, rel, 9, 0.1)
end

dances.win_wave = function(t, w, rel)
	local s = sin(t * 3)
	return {
		RightShoulder = rel(0.1, 0, 2.55 + s * 0.25, w),
		LeftShoulder = rel(0.1, 0, -(2.55 - s * 0.25), w),
		RightElbow = rel(0.3, 0, 0, w),
		LeftElbow = rel(0.3, 0, 0, w),
		RightWrist = rel(0, 0, s * 0.4, w),
		LeftWrist = rel(0, 0, s * 0.4, w),
		Waist = rel(0.06, 0, s * 0.25, w),
		Neck = rel(0.2, 0, s * 0.15, w),
	}
end

dances.win_heart = function(t, w, rel)
	-- Kiss the hand, throw it out; left, then right.
	local cycle = (t % 1.1) / 1.1
	local out = math.clamp((cycle - 0.45) / 0.25, 0, 1)
	local right = beat(t, 1.1) == 0
	local kiss = { x = 1.3 + out * 0.3, y = 0.3 - out * 0.3, z = out * 0.6, e = 2.2 - out * 1.9 }
	local pose = {
		Neck = rel(0.15 + out * 0.15, if right then 0.15 else -0.15, 0, w),
		Waist = rel(0.06, 0, if right then -0.05 else 0.05, w),
	}
	if right then
		pose.RightShoulder = rel(kiss.x, kiss.y, kiss.z, w)
		pose.RightElbow = rel(kiss.e, 0, 0, w)
	else
		pose.LeftShoulder = rel(kiss.x, -kiss.y, -kiss.z, w)
		pose.LeftElbow = rel(kiss.e, 0, 0, w)
	end
	return pose
end

dances.win_fire = function(t, w, rel)
	local flap = sin(t * 16)
	return knees({
		RightShoulder = rel(0.9, 0.2, 0.2, w),
		LeftShoulder = rel(0.9, -0.2, -0.2, w),
		RightElbow = rel(1.8 + flap * 0.3, 0, 0, w),
		LeftElbow = rel(1.8 - flap * 0.3, 0, 0, w),
		RightWrist = rel(0, 0, flap * 0.5, w),
		LeftWrist = rel(0, 0, -flap * 0.5, w),
		Neck = rel(0.25, sin(t * 4) * 0.2, 0, w),
		Waist = rel(0.08 + abs(sin(t * 8)) * 0.05, 0, 0, w),
	}, t, w, rel, 8, 0.15)
end

dances.win_money = function(t, w, rel)
	local flick = math.max(0, sin(t * 14)) ^ 2
	return knees({
		LeftShoulder = rel(0.9, -0.3, 0, w),
		LeftElbow = rel(1.6, 0, 0, w),
		RightShoulder = rel(1.2, 0, 0.6, w),
		RightElbow = rel(0.9 - flick * 0.5, 0, 0, w),
		RightWrist = rel(0, 0, flick * 0.7, w),
		Neck = rel(0.18, sin(t * 2.5) * 0.3, 0, w),
		Waist = rel(0.1, sin(t * 2.5) * 0.12, 0, w),
	}, t, w, rel, 7, 0.12)
end

Moves.poses = poses
Moves.dances = dances

return Moves
