-- Avatars at the tables act out the game: they reach for the square they play, carry a
-- chess piece from one square to the next, toss cards on the pile, shake and roll the
-- dice, slap, point at the player they ask, cheer when they win and groan when they lose.
-- Players can also pick an emote from the wheel (UI/EmoteWheel).
--
-- The server says who did what (server/Services/TableActionService, gestures from
-- Shared/TableActions); every client animates it locally. There are no animation assets:
-- gestures are poses on the R15 upper-body joints (Motor6D.Transform), written every
-- frame after the Animator, so the seated pose underneath keeps playing. Arms that reach
-- for something are aimed at its real position on the table. Small props (a card, two
-- dice, a spoon) are client-only parts.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local TableActions = require(ReplicatedStorage.Shared.TableActions)

local Avatars = {}

local MAX_DISTANCE = 140 -- studs from the camera; further tables don't animate
local DOWN = Vector3.new(0, -1, 0)
local UP = Vector3.new(0, 1, 0)

---------------------------------------------------------------- rigs and joints

type Rig = {
	model: Model,
	motors: { [string]: Motor6D },
	rightHand: BasePart?,
	head: BasePart?,
}

local JOINTS = { "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist" }

local function rigOf(model: Model): Rig?
	local motors = {}
	for _, name in JOINTS do
		local motor = model:FindFirstChild(name, true)
		if motor and motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
			motors[name] = motor
		end
	end
	if not (motors.RightShoulder and motors.RightElbow and motors.Waist) then
		return nil -- not an R15 body (the block stand-in bots use without a network)
	end
	return {
		model = model,
		motors = motors,
		rightHand = model:FindFirstChild("RightHand") :: BasePart?,
		head = model:FindFirstChild("Head") :: BasePart?,
	}
end

-- What each joint looks like under our offset. The Animator rewrites Transform every
-- frame for players; bot bodies have no Animator tracks, so their Transform stays put.
-- If the value is still what we wrote last frame, nothing rewrote it and the base is the
-- one we saved; otherwise the new value is the base.
local baseOf: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local wroteOf: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

local function currentBase(motor: Motor6D): CFrame
	local now = motor.Transform
	local wrote = wroteOf[motor]
	if wrote and now == wrote then
		return baseOf[motor] or CFrame.identity
	end
	baseOf[motor] = now
	return now
end

local function write(motor: Motor6D, value: CFrame)
	motor.Transform = value
	wroteOf[motor] = value
end

local function restore(motor: Motor6D)
	if wroteOf[motor] and motor.Transform == wroteOf[motor] then
		motor.Transform = baseOf[motor] or CFrame.identity
	end
	wroteOf[motor] = nil
	baseOf[motor] = nil
end

-- A joint target from a pose: `rel` is added on top of the seated pose; `abs` replaces
-- it (blended in by `w`). Arms that aim at things use abs.
type JointPose = { rel: CFrame?, abs: CFrame?, w: number? }
type Pose = { [string]: JointPose }

local function rel(x: number, y: number, z: number, amount: number): JointPose
	return { rel = CFrame.fromEulerAnglesYXZ(x * amount, y * amount, z * amount) }
end

---------------------------------------------------------------- easing

local function clamp01(x: number): number
	return if x < 0 then 0 elseif x > 1 then 1 else x
end

local function smooth(x: number): number
	x = clamp01(x)
	return x * x * (3 - 2 * x)
end

-- 0 before a, eases to 1 at b.
local function ramp(t: number, a: number, b: number): number
	return smooth((t - a) / (b - a))
end

-- Fades in over `fadeIn`, holds, fades out over the last `fadeOut` seconds.
local function envelope(t: number, duration: number, fadeIn: number, fadeOut: number): number
	return ramp(t, 0, fadeIn) * (1 - ramp(t, duration - fadeOut, duration))
end

---------------------------------------------------------------- aiming

local function jointFrame(motor: Motor6D): CFrame
	return (motor.Part0 :: BasePart).CFrame * motor.C0
end

-- Shoulder Transform that points the (straight) arm at `point`.
local function aimShoulder(motor: Motor6D, point: Vector3): CFrame
	local frame = jointFrame(motor)
	local offset = point - frame.Position
	if offset.Magnitude < 0.05 then
		return CFrame.identity
	end
	local dir = frame:VectorToObjectSpace(offset.Unit)
	local axis = DOWN:Cross(dir)
	local angle = math.acos(math.clamp(DOWN:Dot(dir), -1, 1))
	if axis.Magnitude < 1e-4 then
		return if angle > 1 then CFrame.Angles(math.pi, 0, 0) else CFrame.identity
	end
	return CFrame.fromAxisAngle(axis.Unit, angle)
end

-- Neck Transform that turns the head toward `point` (limited, like a real neck).
local function aimNeck(motor: Motor6D, point: Vector3): CFrame
	local frame = jointFrame(motor)
	local offset = point - frame.Position
	if offset.Magnitude < 0.05 then
		return CFrame.identity
	end
	local dir = frame:VectorToObjectSpace(offset.Unit)
	local yaw = math.clamp(math.atan2(-dir.X, -dir.Z), -1.1, 1.1)
	local pitch = math.clamp(math.asin(math.clamp(dir.Y, -1, 1)), -0.7, 0.5)
	return CFrame.fromEulerAnglesYXZ(pitch * 0.8, yaw * 0.8, 0)
end

-- Arm reaching for `point` with weight w: the shoulder aims, the elbow straightens, the
-- body leans in if it's out of reach and the head looks.
local function reach(rig: Rig, pose: Pose, point: Vector3, w: number)
	if w <= 0.001 then
		return
	end
	local shoulder = rig.motors.RightShoulder
	pose.RightShoulder = { abs = aimShoulder(shoulder, point), w = w }
	pose.RightElbow = { abs = CFrame.Angles(math.rad(12), 0, 0), w = w }
	if rig.motors.RightWrist then
		pose.RightWrist = { abs = CFrame.Angles(math.rad(-10), 0, 0), w = w }
	end
	local distance = (point - jointFrame(shoulder).Position).Magnitude
	local scale = rig.model:GetScale()
	local lean = clamp01((distance - 2.2 * scale) / (3 * scale)) * 0.5
	pose.Waist = rel(-lean, 0, 0, w)
	if rig.motors.Neck then
		pose.Neck = { abs = aimNeck(rig.motors.Neck, point), w = w }
	end
end

---------------------------------------------------------------- props (client-only parts)

local fx: Folder? = nil
local function fxFolder(): Folder
	if not fx or not fx.Parent then
		local folder = Instance.new("Folder")
		folder.Name = "GameNightAvatarFX"
		folder.Parent = workspace
		fx = folder
	end
	return fx :: Folder
end

local function prop(size: Vector3, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Parent = fxFolder()
	return part
end

type Flight = { part: BasePart, start: number, duration: number, from: Vector3, to: Vector3, arc: number, spin: Vector3, linger: number, follow: BasePart? }
local flights: { Flight } = {}

-- Throws `part` from `from` to `to` in an arc, tumbling by `spin`; it rests there for
-- `linger` seconds, then fades away. With `follow`, it rides along with that part instead.
local function fly(part: BasePart, from: Vector3, to: Vector3, duration: number, arc: number, spin: Vector3?, linger: number?)
	part.CFrame = CFrame.new(from)
	table.insert(flights, { part = part, start = os.clock(), duration = duration, from = from, to = to, arc = arc, spin = spin or Vector3.zero, linger = linger or 0.4 })
end

local function carry(part: BasePart, follow: BasePart, duration: number)
	table.insert(flights, { part = part, start = os.clock(), duration = duration, from = follow.Position, to = follow.Position, arc = 0, spin = Vector3.zero, linger = 0, follow = follow })
end

local function stepFlights(now: number)
	for i = #flights, 1, -1 do
		local f = flights[i]
		local t = now - f.start
		if f.follow then
			if t >= f.duration or not f.follow.Parent then
				f.part:Destroy()
				table.remove(flights, i)
			else
				f.part.CFrame = f.follow.CFrame * CFrame.new(0, -0.35, -0.2)
			end
		elseif t >= f.duration + f.linger + 0.3 then
			f.part:Destroy()
			table.remove(flights, i)
		else
			local k = clamp01(t / f.duration)
			local eased = 1 - (1 - k) * (1 - k)
			local pos = f.from:Lerp(f.to, eased) + Vector3.new(0, math.sin(k * math.pi) * f.arc, 0)
			local turn = f.spin * (1 - (1 - k) ^ 3)
			f.part.CFrame = CFrame.new(pos) * CFrame.Angles(turn.X, turn.Y, turn.Z)
			if t > f.duration + f.linger then
				f.part.Transparency = clamp01((t - f.duration - f.linger) / 0.3)
			end
		end
	end
end

local CARD_BACK = Color3.fromRGB(200, 60, 70)

local function flyCard(from: Vector3, to: Vector3)
	local card = prop(Vector3.new(0.9, 0.04, 1.25), CARD_BACK)
	fly(card, from, to + Vector3.new(0, 0.1, 0), 0.32, 0.6, Vector3.new(0, math.rad(math.random(-60, 60)), 0), 0.25)
end

---------------------------------------------------------------- gestures

-- Everything a gesture needs to know, resolved once when it starts.
type Ctx = {
	rig: Rig,
	center: Vector3, -- where cards and dice land: the middle of the table
	front: Vector3, -- the table just in front of this seat
	target: Vector3, -- what this gesture reaches for
	from: Vector3?,
	to: Vector3?,
	fired: { [string]: boolean },
}

type Gesture = { duration: number, pose: (t: number, ctx: Ctx) -> Pose }

-- Chest height in front of the body, for hands that come back with something.
local function chest(ctx: Ctx): Vector3
	local torso = ctx.rig.motors.Waist.Part1 :: BasePart
	return torso.Position + torso.CFrame.LookVector * 1.4 - Vector3.new(0, 0.4, 0)
end

local function once(ctx: Ctx, key: string, t: number, at: number): boolean
	if t >= at and not ctx.fired[key] then
		ctx.fired[key] = true
		return true
	end
	return false
end

local function handPos(ctx: Ctx): Vector3
	local hand = ctx.rig.rightHand
	return if hand then hand.Position else chest(ctx)
end

local G: { [string]: Gesture } = {}

-- Reach out, touch, come back.
local function reachGesture(out: number, hold: number, back: number, lift: number?): Gesture
	return {
		duration = out + hold + back,
		pose = function(t, ctx)
			local w = ramp(t, 0, out) * (1 - ramp(t, out + hold, out + hold + back))
			local pose = {}
			reach(ctx.rig, pose, ctx.target + Vector3.new(0, lift or 0.25, 0), w)
			return pose
		end,
	}
end

G.place = reachGesture(0.35, 0.18, 0.4)

G.move = {
	duration = 1.25,
	pose = function(t, ctx)
		local from = ctx.from or ctx.target
		local to = ctx.to or ctx.target
		local w = ramp(t, 0, 0.3) * (1 - ramp(t, 0.9, 1.25))
		-- Pick it up (dip), carry it over (lifted), set it down.
		local along = ramp(t, 0.4, 0.78)
		local lift = 0.25 + math.sin(along * math.pi) * 0.9
		local pose = {}
		reach(ctx.rig, pose, from:Lerp(to, along) + Vector3.new(0, lift, 0), w)
		return pose
	end,
}

G.card = {
	duration = 0.8,
	pose = function(t, ctx)
		if once(ctx, "card", t, 0.2) then
			flyCard(handPos(ctx), ctx.target)
		end
		local w = ramp(t, 0, 0.22) * (1 - ramp(t, 0.42, 0.8))
		local pose = {}
		reach(ctx.rig, pose, ctx.target + Vector3.new(0, 0.6, 0), w)
		return pose
	end,
}

G.draw = {
	duration = 0.95,
	pose = function(t, ctx)
		if once(ctx, "draw", t, 0.32) and ctx.rig.rightHand then
			local card = prop(Vector3.new(0.9, 0.04, 1.25), CARD_BACK)
			carry(card, ctx.rig.rightHand, 0.5)
		end
		local w = ramp(t, 0, 0.3) * (1 - ramp(t, 0.6, 0.95))
		local back = ramp(t, 0.38, 0.75)
		local pose = {}
		reach(ctx.rig, pose, ctx.target:Lerp(chest(ctx), back) + Vector3.new(0, 0.3, 0), w)
		return pose
	end,
}

G.dice = {
	duration = 1.5,
	pose = function(t, ctx)
		local pose: Pose = {}
		local shake = ramp(t, 0, 0.2) * (1 - ramp(t, 0.6, 0.75))
		if shake > 0.001 then
			-- Both hands cupped in front, shaking.
			local jiggle = math.sin(t * 38) * 0.22
			pose.RightShoulder = rel(1.05, 0.35, 0, shake)
			pose.RightElbow = rel(1.0 + jiggle, 0, 0, shake)
			pose.LeftShoulder = rel(1.05, -0.35, 0, shake)
			pose.LeftElbow = rel(1.0 - jiggle, 0, 0, shake)
			pose.Neck = rel(-0.2, 0, 0, shake)
		end
		if once(ctx, "roll", t, 0.82) then
			local start = handPos(ctx)
			for i = 1, 2 do
				local die = prop(Vector3.new(0.5, 0.5, 0.5), Color3.fromRGB(250, 248, 240))
				local side = (i - 1.5) * 0.9
				local to = ctx.target + Vector3.new(side, 0.3, side * 0.5)
				fly(die, start, to, 0.5, 1.2, Vector3.new(math.pi * (3 + i), math.pi * 2, math.pi * (2 + i)), 0.6)
			end
		end
		local throw = ramp(t, 0.62, 0.85) * (1 - ramp(t, 1.05, 1.45))
		reach(ctx.rig, pose, ctx.target + Vector3.new(0, 1.2, 0), throw)
		return pose
	end,
}

G.slap = {
	duration = 0.85,
	pose = function(t, ctx)
		local pose = {}
		local up = ramp(t, 0, 0.16) * (1 - ramp(t, 0.16, 0.26))
		local down = ramp(t, 0.16, 0.26) * (1 - ramp(t, 0.5, 0.85))
		local high = ctx.target:Lerp(chest(ctx), 0.6) + Vector3.new(0, 4, 0)
		if up > 0.001 then
			reach(ctx.rig, pose, high, up)
		else
			reach(ctx.rig, pose, ctx.target + Vector3.new(0, 0.1, 0), down)
		end
		return pose
	end,
}

G.grab = {
	duration = 1.5,
	pose = function(t, ctx)
		if once(ctx, "grab", t, 0.22) and ctx.rig.rightHand then
			local spoon = prop(Vector3.new(0.18, 0.08, 1.3), Color3.fromRGB(205, 210, 220), Enum.Material.Metal)
			carry(spoon, ctx.rig.rightHand, 1.05)
		end
		local w = ramp(t, 0, 0.2) * (1 - ramp(t, 1.15, 1.5))
		local raise = ramp(t, 0.28, 0.6)
		local head = if ctx.rig.head then ctx.rig.head.Position else chest(ctx)
		local overhead = head + Vector3.new(0, 5, 0) + (head - ctx.center) * Vector3.new(1, 0, 1) * 0.05
		local pose = {}
		reach(ctx.rig, pose, ctx.target:Lerp(overhead, raise) + Vector3.new(0, 0.2, 0), w)
		if raise > 0 and ctx.rig.motors.Neck then
			pose.Neck = rel(0.25, 0, 0, raise * (1 - ramp(t, 1.15, 1.5)))
		end
		return pose
	end,
}

G.point = {
	duration = 1.3,
	pose = function(t, ctx)
		local w = ramp(t, 0, 0.3) * (1 - ramp(t, 0.95, 1.3))
		local bob = math.sin(t * 9) * 0.25 * ramp(t, 0.3, 0.45)
		local pose = {}
		reach(ctx.rig, pose, ctx.target + Vector3.new(0, bob, 0), w)
		-- Don't lean across the table to point.
		pose.Waist = rel(-0.08, 0, 0, w)
		return pose
	end,
}

G.knock = {
	duration = 1.05,
	pose = function(t, ctx)
		local w = ramp(t, 0, 0.25) * (1 - ramp(t, 0.75, 1.05))
		local tap = math.abs(math.sin((t - 0.25) * math.pi * 4)) * ramp(t, 0.25, 0.3) * (1 - ramp(t, 0.7, 0.75))
		local pose = {}
		reach(ctx.rig, pose, ctx.front + Vector3.new(0, 0.2 + tap * 0.7, 0), w)
		pose.Waist = rel(-0.06, 0, 0, w)
		return pose
	end,
}

G.pass = {
	duration = 0.9,
	pose = function(t, ctx)
		local w = ramp(t, 0, 0.22) * (1 - ramp(t, 0.6, 0.9))
		local torso = ctx.rig.motors.Waist.Part1 :: BasePart
		local sweep = ramp(t, 0.22, 0.55)
		local point = ctx.front + Vector3.new(0, 1.2, 0) + torso.CFrame.RightVector * (sweep * 2.2 - 0.4)
		local pose = {}
		reach(ctx.rig, pose, point, w)
		pose.Waist = rel(0, 0, 0, w)
		if ctx.rig.motors.Neck then
			pose.Neck = rel(0, 0, 0.12, w)
		end
		return pose
	end,
}

G.buzz = {
	duration = 0.75,
	pose = function(t, ctx)
		local pose = {}
		local up = ramp(t, 0, 0.14) * (1 - ramp(t, 0.14, 0.24))
		local down = ramp(t, 0.14, 0.24) * (1 - ramp(t, 0.45, 0.75))
		if up > 0.001 then
			reach(ctx.rig, pose, ctx.front + Vector3.new(0, 3, 0), up)
		else
			reach(ctx.rig, pose, ctx.front + Vector3.new(0, 0.3, 0), down)
		end
		return pose
	end,
}

-- Poses that don't reach for anything: fixed joint angles, faded in and out.
local function posed(duration: number, fadeIn: number, fadeOut: number, build: (t: number, w: number) -> Pose): Gesture
	return {
		duration = duration,
		pose = function(t, _ctx)
			return build(t, envelope(t, duration, fadeIn, fadeOut))
		end,
	}
end

G.think = posed(1.9, 0.35, 0.35, function(t, w)
	return {
		RightShoulder = rel(0.95, 0.4, 0, w),
		RightElbow = rel(2.15, 0, 0, w),
		Neck = rel(-0.12, 0, 0.14 + math.sin(t * 2) * 0.04, w),
		Waist = rel(-0.06, 0, 0, w),
	}
end)

G.cheer = posed(1.9, 0.2, 0.35, function(t, w)
	local pump = math.sin(t * 11) * 0.22
	return {
		RightShoulder = rel(0.2, 0, 2.7 + pump, w),
		LeftShoulder = rel(0.2, 0, -(2.7 + pump), w),
		RightElbow = rel(0.25, 0, 0, w),
		LeftElbow = rel(0.25, 0, 0, w),
		Neck = rel(0.3, 0, 0, w),
		Waist = rel(0.08 + math.abs(math.sin(t * 11)) * 0.06, 0, 0, w),
	}
end)

G.groan = posed(2.1, 0.4, 0.45, function(t, w)
	return {
		Neck = rel(-0.55, math.sin(t * 5) * 0.3, 0, w),
		Waist = rel(-0.3, 0, 0, w),
		RightShoulder = rel(0.35, 0.2, 0, w),
		LeftShoulder = rel(0.35, -0.2, 0, w),
		RightElbow = rel(0.6, 0, 0, w),
		LeftElbow = rel(0.6, 0, 0, w),
	}
end)

G.shrug = posed(1.4, 0.25, 0.35, function(_t, w)
	return {
		RightShoulder = rel(0.1, 0, 0.5, w),
		LeftShoulder = rel(0.1, 0, -0.5, w),
		RightElbow = rel(1.45, 0, 0, w),
		LeftElbow = rel(1.45, 0, 0, w),
		Neck = rel(0, 0, 0.25, w),
	}
end)

G.wave = posed(1.7, 0.25, 0.35, function(t, w)
	return {
		RightShoulder = rel(0, 0, 2.55 + math.sin(t * 12) * 0.28, w),
		RightElbow = rel(0.35, 0, 0, w),
		Neck = rel(0.05, 0, -0.1, w),
	}
end)

G.clap = posed(1.6, 0.25, 0.3, function(t, w)
	local open = 0.5 + 0.5 * math.sin(t * 15)
	return {
		RightShoulder = rel(1.25, 0.45 - open * 0.3, 0, w),
		LeftShoulder = rel(1.25, -(0.45 - open * 0.3), 0, w),
		RightElbow = rel(0.5, 0, 0, w),
		LeftElbow = rel(0.5, 0, 0, w),
		Neck = rel(0.1, 0, 0, w),
	}
end)

G.laugh = posed(1.6, 0.2, 0.35, function(t, w)
	local shake = math.sin(t * 17) * 0.07
	return {
		Neck = rel(0.35 + shake, 0, 0, w),
		Waist = rel(0.12 + shake, 0, 0, w),
		RightShoulder = rel(0.5, 0.45, 0, w),
		LeftShoulder = rel(0.5, -0.45, 0, w),
		RightElbow = rel(1.2, 0, 0, w),
		LeftElbow = rel(1.2, 0, 0, w),
	}
end)

G.thumbsUp = posed(1.4, 0.2, 0.3, function(t, w)
	local pump = math.sin(t * 8) * 0.12
	return {
		RightShoulder = rel(0.65 + pump, 0.2, 0, w),
		RightElbow = rel(1.55, 0, 0, w),
		Neck = rel(-0.08 + math.sin(t * 8) * 0.08, 0, 0, w),
	}
end)

G.facepalm = posed(1.7, 0.3, 0.4, function(t, w)
	return {
		RightShoulder = rel(1.45, 0.5, 0, w),
		RightElbow = rel(2.05, 0, 0, w),
		Neck = rel(-0.38, math.sin(t * 4) * 0.12, 0, w),
		Waist = rel(-0.12, 0, 0, w),
	}
end)

---------------------------------------------------------------- playing

type Playing = { gesture: Gesture, ctx: Ctx, start: number, written: { [string]: boolean } }
local playing: { [Model]: Playing } = {}

local function stop(model: Model)
	local p = playing[model]
	if not p then
		return
	end
	playing[model] = nil
	for name in p.written do
		local motor = p.ctx.rig.motors[name]
		if motor then
			restore(motor)
		end
	end
end

local function step()
	local now = os.clock()
	for model, p in playing do
		local t = now - p.start
		if t >= p.gesture.duration or not model.Parent then
			stop(model)
			continue
		end
		local ok, pose = pcall(p.gesture.pose, t, p.ctx)
		if not ok then
			stop(model)
			continue
		end
		-- Joints this gesture touched before but not this frame go back to their base.
		for name in p.written do
			if not pose[name] then
				local motor = p.ctx.rig.motors[name]
				if motor then
					write(motor, currentBase(motor))
				end
			end
		end
		for name, jp in pose do
			local motor = p.ctx.rig.motors[name]
			if motor then
				local base = currentBase(motor)
				local value = base
				if jp.abs then
					value = base:Lerp(jp.abs, clamp01(jp.w or 1))
				elseif jp.rel then
					value = base * jp.rel
				end
				write(motor, value)
				p.written[name] = true
			end
		end
	end
	stepFlights(now)
end

---------------------------------------------------------------- finding things

local function findTable(id: any): Model?
	if type(id) ~= "string" then
		return nil
	end
	for _, inst in CollectionService:GetTagged(Config.TableTag) do
		if inst:IsA("Model") and inst:GetAttribute("TableId") == id then
			return inst
		end
	end
	return nil
end

local function anchorPosition(model: Model): Vector3
	local anchor = model:FindFirstChild("BoardAnchor", true)
	if anchor and anchor:IsA("Attachment") then
		return anchor.WorldPosition
	elseif anchor and anchor:IsA("BasePart") then
		return anchor.Position
	end
	local cf, size = model:GetBoundingBox()
	return cf.Position + Vector3.new(0, size.Y / 2, 0)
end

local function seatPart(model: Model, index: any): BasePart?
	if type(index) ~= "number" then
		return nil
	end
	local seat = model:FindFirstChild(`Seat{index}`, true)
	return if seat and seat:IsA("BasePart") then seat else nil
end

local function cellPart(model: Model, row: number?, col: number?): BasePart?
	local board = model:FindFirstChild("GameBoard", true)
	local cells = board and board:FindFirstChild("Cells", true)
	if not cells then
		return nil
	end
	for _, cell in cells:GetChildren() do
		if cell:IsA("BasePart") and cell:GetAttribute("Col") == col and cell:GetAttribute("Row") == row then
			return cell
		end
	end
	return nil
end

local function cellPoint(model: Model, rc: any): Vector3?
	if type(rc) ~= "table" or type(rc[1]) ~= "number" or type(rc[2]) ~= "number" then
		return nil
	end
	local cell = cellPart(model, rc[1], rc[2])
	return if cell then cell.Position + Vector3.new(0, cell.Size.Y / 2, 0) else nil
end

local function bodyOf(model: Model, payload: any): Model?
	if type(payload.userId) == "number" then
		local player = Players:GetPlayerByUserId(payload.userId)
		return player and player.Character
	end
	if type(payload.bot) == "string" then
		local bots = model:FindFirstChild("Bots")
		local body = bots and bots:FindFirstChild(payload.bot)
		return if body and body:IsA("Model") then body else nil
	end
	return nil
end

---------------------------------------------------------------- emoji over the head

local function bubble(body: Model, icon: string, seconds: number)
	local head = body:FindFirstChild("Head") or body.PrimaryPart
	if not (head and head:IsA("BasePart")) then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "GameNightEmote"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(56, 56)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 90
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.3, 0.3)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Text = icon
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = gui
	gui.Parent = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	TweenService:Create(label, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 1) }):Play()
	task.delay(seconds, function()
		local fade = TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1, Position = UDim2.fromScale(0.5, 0.1) })
		fade:Play()
		fade.Completed:Wait()
		gui:Destroy()
	end)
end

---------------------------------------------------------------- incoming actions

local function play(payload: any)
	if type(payload) ~= "table" or type(payload.kind) ~= "string" then
		return
	end
	local gesture = G[payload.kind]
	local model = findTable(payload.table)
	if not gesture or not model then
		return
	end
	local anchor = anchorPosition(model)
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - anchor).Magnitude > MAX_DISTANCE then
		return
	end
	local body = bodyOf(model, payload)
	if not body then
		return
	end

	local emote = TableActions.emote(payload.kind)
	local icon = if emote then emote.icon else TableActions.ReactionIcons[payload.kind]
	if icon then
		bubble(body, icon, gesture.duration)
	end

	local rig = rigOf(body)
	if not rig then
		return
	end
	-- The table in front of this seat, and its middle (a little toward the seat).
	local seat = seatPart(model, payload.seat)
	local toSeat = if seat then (seat.Position - anchor) * Vector3.new(1, 0, 1) else Vector3.zero
	local front, center = anchor, anchor
	if toSeat.Magnitude > 0.1 then
		local d = toSeat.Magnitude
		front = anchor + toSeat.Unit * math.max(1.2, math.min(d - 2.6, d * 0.6))
		center = anchor + toSeat.Unit * math.min(1.2, d * 0.2)
	end

	local from = cellPoint(model, payload.from)
	local to = cellPoint(model, payload.to)
	local target = cellPoint(model, payload.cell)
	if not target and type(payload.column) == "number" then
		-- Four in a Row: drop into the top of the column.
		local column = cellPart(model, nil, payload.column)
		if column then
			target = column.Position + Vector3.new(0, column.Size.Y / 2, 0)
		end
	end
	if not target and payload.kind == "point" then
		local other = seatPart(model, payload.at)
		target = if other then other.Position + Vector3.new(0, 3.4, 0) else center + Vector3.new(0, 1.5, 0)
	end
	if not target then
		-- Big boards with no cells (Conquest, Hexlands, Property Party...): somewhere
		-- between you and the middle.
		target = if payload.kind == "place" then front:Lerp(center, 0.55) else center
	end

	local function start()
		if not body.Parent then
			return
		end
		stop(body)
		playing[body] = {
			gesture = gesture,
			ctx = { rig = rig, center = center, front = front, target = target :: Vector3, from = from, to = to, fired = {} },
			start = os.clock(),
			written = {},
		}
	end
	if type(payload.wait) == "number" and payload.wait > 0 then
		task.delay(math.min(payload.wait, 3), start)
	else
		start()
	end
end

local started = false
function Avatars.start()
	if started then
		return
	end
	started = true
	Net.event(Net.Names.TableAction).OnClientEvent:Connect(play)
	RunService.PreSimulation:Connect(step)
end

-- Asks the server to play an emote on your avatar (only while you're seated in a game).
function Avatars.emote(id: string)
	Net.event(Net.Names.TableAction):FireServer({ emote = id })
end

return Avatars
