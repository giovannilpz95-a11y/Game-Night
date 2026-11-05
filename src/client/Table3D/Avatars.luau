-- Avatars at the tables act out the game: they reach for the square they play, carry a
-- chess piece from one square to the next, toss cards on the pile, shake and roll the
-- dice, slap, point at the player they ask, cheer when they win and groan when they lose.
-- Players can also pick an emote from the wheel (UI/EmoteWheel).
--
-- The server says who did what (server/Services/TableActionService, gestures from
-- Shared/TableActions); every client animates it locally. There are no animation assets:
-- gestures are poses on the R15 upper-body joints, written every frame after the
-- Animator, so the seated pose underneath keeps playing. A joint is either a Motor6D or,
-- on rigs with the newer avatar joints, an AnimationConstraint (Transform on both). Arms that reach
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
local Perf = require(script.Parent.Parent.Perf)

local Avatars = {}

local actionListeners: { (any, Vector3, string) -> () } = {}

local MAX_DISTANCE = 140 -- studs from the camera; further tables don't animate
-- In low-detail mode (client/Perf) only nearby tables keep their idle breathing; gestures
-- still play out to MAX_DISTANCE.
local LOW_IDLE_DISTANCE = 60
local DOWN = Vector3.new(0, -1, 0)
local UP = Vector3.new(0, 1, 0)

---------------------------------------------------------------- rigs and joints

-- Per joint (keyed by the Motor6D / AnimationConstraint): the pose under our offset, what
-- we last wrote, and a bot's fixed rest pose. Plain tables: Instance keys can drop out of
-- weak tables in Roblox.
local baseOf: { [any]: CFrame } = {}
local wroteOf: { [any]: CFrame } = {}
local restOf: { [any]: CFrame } = {}

-- One body joint. `inst` has a writable Transform (Motor6D or AnimationConstraint);
-- `frame()` is the joint's world frame before Transform (Part0.CFrame * C0 for a motor,
-- Attachment0.WorldCFrame for a constraint); `part1` is the limb it moves.
type Joint = { inst: any, part1: BasePart, frame: () -> CFrame }

type Rig = {
	model: Model,
	motors: { [string]: Joint },
	rightHand: BasePart?,
	head: BasePart?,
}

local JOINTS = { "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist" }

local function jointOf(model: Model, name: string): Joint?
	-- Prefer a Motor6D; fall back to an AnimationConstraint of the same name.
	local constraint: AnimationConstraint? = nil
	for _, d in model:GetDescendants() do
		if d.Name == name then
			if d:IsA("Motor6D") and d.Part0 and d.Part1 then
				local motor = d
				return {
					inst = motor,
					part1 = motor.Part1 :: BasePart,
					frame = function()
						return (motor.Part0 :: BasePart).CFrame * motor.C0
					end,
				}
			elseif d:IsA("AnimationConstraint") and not constraint then
				constraint = d
			end
		end
	end
	local c = constraint
	-- Only kinematic constraints: a physics-driven one (IsKinematic false) would let the
	-- body fold under a written pose. Your own character is the exception, since this
	-- client simulates it.
	local mine = model == Players.LocalPlayer.Character
	if c and not (c.IsKinematic or mine) then
		return nil
	end
	if c and c.Attachment0 and c.Attachment1 then
		local a0, a1 = c.Attachment0 :: Attachment, c.Attachment1 :: Attachment
		local part1 = a1.Parent
		if part1 and part1:IsA("BasePart") then
			return {
				inst = c,
				part1 = part1,
				frame = function()
					return a0.WorldCFrame
				end,
			}
		end
	end
	return nil
end

local function rigOf(model: Model): Rig?
	local motors = {}
	for _, name in JOINTS do
		motors[name] = jointOf(model, name)
	end
	-- A bot (no player owns it): remember each joint's rest pose the first time.
	if not Players:GetPlayerFromCharacter(model) then
		for _, joint in motors do
			if restOf[joint.inst] == nil and wroteOf[joint.inst] == nil then
				restOf[joint.inst] = joint.inst.Transform
			end
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
-- Plain tables (not weak-keyed): Roblox can drop an Instance key from a weak table while
-- the Instance still exists. restore() clears the entries when a gesture ends.

-- AnimationConstraint.Transform doesn't read back bit-for-bit what was written, so "is
-- it still what we wrote" has to allow a little rounding. Without this, every frame took
-- our own last pose as the new base and the gesture never fully went back.
local function same(a: CFrame, b: CFrame): boolean
	if (a.Position - b.Position).Magnitude > 1e-3 then
		return false
	end
	return a.LookVector:Dot(b.LookVector) > 0.99999 and a.UpVector:Dot(b.UpVector) > 0.99999
end

-- Bots have no Animator, so their rest pose never changes: it's captured once, the
-- first time we see each joint, and every gesture starts from and returns to it. Even
-- if a read-back check ever misses, poses can't pile up across gestures.

local function currentBase(motor: any): CFrame
	local rest = restOf[motor]
	if rest then
		return rest
	end
	local now = motor.Transform
	local wrote = wroteOf[motor]
	if wrote and same(now, wrote) then
		return baseOf[motor] or CFrame.identity
	end
	baseOf[motor] = now
	return now
end

local function write(motor: any, value: CFrame)
	motor.Transform = value
	wroteOf[motor] = value
end

-- Puts the joint back as it was before the gesture (unless an Animator has already
-- written over it this frame, in which case its value stands).
local function restore(motor: any)
	local rest = restOf[motor]
	if rest then
		motor.Transform = rest
		wroteOf[motor] = nil
		return
	end
	local wrote = wroteOf[motor]
	if wrote and same(motor.Transform, wrote) then
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

local function jointFrame(joint: Joint): CFrame
	return joint.frame()
end

-- Shoulder Transform that points the (straight) arm at `point`.
local function aimShoulder(motor: Joint, point: Vector3): CFrame
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
local function aimNeck(motor: Joint, point: Vector3): CFrame
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
-- body leans in if it's out of reach and the head looks. `look` (default w) lets the
-- eyes get there first: people look at a thing before their hand moves.
local function reach(rig: Rig, pose: Pose, point: Vector3, w: number, look: number?)
	local lookW = math.max(look or w, w)
	if lookW > 0.001 and rig.motors.Neck then
		pose.Neck = { abs = aimNeck(rig.motors.Neck, point), w = lookW }
	end
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
end

-- A reach with anticipation and follow-through, for gestures that go out to a spot and
-- come back: the head turns first, the body draws back a touch, the arm goes out a hair
-- past the spot and settles, then comes home with the body easing forward after it.
-- Returns the arm weight and the point to aim at (with the overshoot).
local function anticipate(t: number, lead: number, out: number, hold: number, back: number): (number, number, number)
	local look = ramp(t, 0, lead + out * 0.5) * (1 - ramp(t, lead + out + hold + back * 0.3, lead + out + hold + back))
	local arm = ramp(t, lead * 0.6, lead + out) * (1 - ramp(t, lead + out + hold, lead + out + hold + back))
	-- 0 → 1 → 0 bump at the end of the reach (overshoot), and a small pull-back first.
	local over = math.sin(clamp01((t - lead - out * 0.6) / (out * 0.4 + hold * 0.6)) * math.pi)
	return arm, look, over
end

local function withLean(pose: Pose, t: number, lead: number, settleAt: number, settleFor: number)
	-- Draws back before the reach, eases forward after coming home.
	local draw = math.sin(clamp01(t / math.max(lead, 0.01)) * math.pi) * 0.07
	local settle = math.sin(clamp01((t - settleAt) / settleFor) * math.pi) * -0.04
	local extra = draw + settle
	if math.abs(extra) > 0.001 then
		local waist = pose.Waist
		if waist and waist.rel then
			waist.rel = waist.rel * CFrame.Angles(extra, 0, 0)
		elseif not waist then
			pose.Waist = { rel = CFrame.Angles(extra, 0, 0) }
		end
	end
end

---------------------------------------------------------------- props (client-only parts)

local pickUp: (Model?, Vector3, Vector3) -> any
local placeCarried: (any, Vector3, number) -> ()
local putDown: (any) -> ()

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

---------------------------------------------------------------- carrying real pieces

-- A move picks the real piece up: client-side copies of its parts ride in the hand
-- while the originals (wherever the server has the piece: still on `from`, or already
-- on `to`) are hidden on this screen, then the copies go and the originals come back.
type Carried = { copies: { { part: BasePart, offset: CFrame } }, board: Model, from: Vector3, to: Vector3, fromSource: boolean, hidden: { [BasePart]: boolean } }

local function piecePartsAt(board: Model, point: Vector3): { BasePart }
	local found = {}
	for _, d in board:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 and not d:IsA("Seat") then
			local size = d.Size
			if math.max(size.X, size.Y, size.Z) < 1.6 and d.Position.Y > point.Y + 0.02 and d.Position.Y < point.Y + 1.8 then
				local flat = (d.Position - point) * Vector3.new(1, 0, 1)
				if flat.Magnitude < 0.42 then
					local skip = false
					local parent = d.Parent
					while parent and parent ~= board do
						if parent.Name == "Cells" or parent.Name == "Bots" or parent.Name == "TableSign" or parent:FindFirstChildOfClass("Humanoid") then
							skip = true
							break
						end
						parent = parent.Parent
					end
					if not skip then
						table.insert(found, d)
					end
				end
			end
		end
	end
	return found
end

local function hideAt(c: Carried, point: Vector3)
	for _, part in piecePartsAt(c.board, point) do
		if not c.hidden[part] then
			c.hidden[part] = true
			part.LocalTransparencyModifier = 1
		end
	end
end

pickUp = function(board: Model?, from: Vector3, to: Vector3): Carried?
	if not board then
		return nil
	end
	local fromSource = true
	local source = piecePartsAt(board, from)
	local base = from
	if #source == 0 then
		fromSource = false
		source = piecePartsAt(board, to)
		base = to
	end
	if #source == 0 then
		return nil
	end
	local carried: Carried = { copies = {}, board = board, from = from, to = to, fromSource = fromSource, hidden = {} }
	local origin = CFrame.new(base)
	for _, part in source do
		local copy = part:Clone()
		for _, child in copy:GetChildren() do
			if not (child:IsA("DataModelMesh") or child:IsA("Decal") or child:IsA("SurfaceGui") or child:IsA("SurfaceAppearance")) then
				child:Destroy()
			end
		end
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanQuery = false
		copy.CanTouch = false
		copy.Parent = fxFolder()
		table.insert(carried.copies, { part = copy, offset = origin:ToObjectSpace(part.CFrame) })
	end
	hideAt(carried, base)
	return carried
end

placeCarried = function(c: Carried, at: Vector3, tilt: number)
	local frame = CFrame.new(at) * CFrame.Angles(tilt, 0, 0)
	for _, copy in c.copies do
		copy.part.CFrame = frame * copy.offset
	end
	-- Keep the real piece hidden wherever it is now: the server's update may land mid-carry.
	hideAt(c, c.from)
	if not c.fromSource or #piecePartsAt(c.board, c.from) == 0 then
		hideAt(c, c.to)
	end
end

putDown = function(c: Carried)
	for _, copy in c.copies do
		copy.part:Destroy()
	end
	table.clear(c.copies)
	for part in c.hidden do
		part.LocalTransparencyModifier = 0
	end
	table.clear(c.hidden)
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
	board: Model?, -- the table, for gestures that pick up its pieces
	carry: any, -- move: the piece in the hand (nil until picked up, false if none found)
}

-- `finish` runs however the gesture ends (done, interrupted, body gone): clean up props.
type Gesture = { duration: number, pose: (t: number, ctx: Ctx) -> Pose, finish: ((ctx: Ctx) -> ())? }

-- Chest height in front of the body, for hands that come back with something.
local function chest(ctx: Ctx): Vector3
	local torso = ctx.rig.motors.Waist.part1
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

-- Reach out, touch, come back (with a look first, a draw-back and a settle).
local LEAD = 0.16
local function reachGesture(out: number, hold: number, back: number, lift: number?): Gesture
	local total = LEAD + out + hold + back
	return {
		duration = total + 0.25,
		pose = function(t, ctx)
			local arm, look, over = anticipate(t, LEAD, out, hold, back)
			local shoulder = ctx.rig.motors.RightShoulder.frame().Position
			local spot = ctx.target + Vector3.new(0, lift or 0.25, 0)
			local past = (spot - shoulder) * Vector3.new(1, 0, 1)
			local aim = spot + (if past.Magnitude > 0.1 then past.Unit * 0.25 * over else Vector3.zero) - Vector3.new(0, 0.12 * over, 0)
			local pose = {}
			reach(ctx.rig, pose, aim, arm, look)
			withLean(pose, t, LEAD, LEAD + out + hold + back * 0.6, 0.4)
			return pose
		end,
	}
end

G.place = reachGesture(0.34, 0.16, 0.42)

-- Look, reach the piece, pick it up (the real piece leaves the board and rides in the
-- hand), carry it over in an arc, set it down with a little press, come back.
local PICK, PUT = 0.48, 0.98 -- when the piece leaves the board and when it lands
G.move = {
	duration = 1.6,
	pose = function(t, ctx)
		local from = ctx.from or ctx.target
		local to = ctx.to or ctx.target
		if ctx.carry == nil and t >= PICK - 0.02 then
			ctx.carry = pickUp(ctx.board, from, to) or false
		end
		local arm = ramp(t, 0.1, 0.42) * (1 - ramp(t, 1.15, 1.5))
		local look = ramp(t, 0, 0.25) * (1 - ramp(t, 1.2, 1.55))
		local along = ramp(t, PICK, PUT)
		local lift = math.sin(along * math.pi) * 0.95
		-- Dip to grab and press to set down.
		local dip = math.sin(clamp01((t - 0.36) / 0.18) * math.pi) * 0.12 + math.sin(clamp01((t - PUT + 0.04) / 0.16) * math.pi) * 0.1
		local spot = from:Lerp(to, along) + Vector3.new(0, lift, 0)
		local carried = ctx.carry
		if carried then
			if t < PUT then
				placeCarried(carried, spot + Vector3.new(0, ramp(t, PICK, PICK + 0.1) * 0.12, 0), (along - 0.5) * 0.25)
			elseif not ctx.fired.landed then
				ctx.fired.landed = true
				putDown(carried)
			end
		end
		local pose = {}
		reach(ctx.rig, pose, spot + Vector3.new(0, 0.32 - dip, 0), arm, look)
		withLean(pose, t, 0.12, 1.2, 0.35)
		return pose
	end,
	finish = function(ctx)
		if ctx.carry then
			putDown(ctx.carry)
		end
	end,
}

-- Glance at the pile, wind the card in toward the chest, flick it out (the card leaves
-- at the end of the flick), follow through and settle.
G.card = {
	duration = 1.05,
	pose = function(t, ctx)
		if once(ctx, "card", t, 0.34) then
			flyCard(handPos(ctx), ctx.target)
		end
		local w = ramp(t, 0.04, 0.2) * (1 - ramp(t, 0.6, 0.98))
		local look = ramp(t, 0, 0.16) * (1 - ramp(t, 0.7, 1.0))
		local wind = ramp(t, 0.04, 0.2) * (1 - ramp(t, 0.2, 0.34))
		local high = ctx.target + Vector3.new(0, 0.6, 0)
		local aim = high:Lerp(chest(ctx) + Vector3.new(0, 0.3, 0), wind * 0.55)
		-- Follow-through: the hand drops a little past the release.
		aim -= Vector3.new(0, math.sin(clamp01((t - 0.34) / 0.3) * math.pi) * 0.3, 0)
		local pose = {}
		reach(ctx.rig, pose, aim, w, look)
		withLean(pose, t, 0.12, 0.6, 0.35)
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
		local w = ramp(t, 0.06, 0.3) * (1 - ramp(t, 0.6, 0.95))
		local look = ramp(t, 0, 0.18) * (1 - ramp(t, 0.5, 0.8))
		local back = ramp(t, 0.38, 0.75)
		local pose = {}
		reach(ctx.rig, pose, ctx.target:Lerp(chest(ctx), back) + Vector3.new(0, 0.3, 0), w, look)
		-- Glance down at the new card once it's in hand.
		if pose.Neck and back > 0.3 then
			pose.Neck = { abs = (pose.Neck.abs :: CFrame) * CFrame.Angles(-0.35 * back, 0, 0), w = math.max(look, back * (1 - ramp(t, 0.75, 0.95))) }
		end
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
		reach(ctx.rig, pose, ctx.target + Vector3.new(0, 1.2, 0), throw, shake + throw)
		if shake > 0.001 then
			-- Hunch over the dice while shaking, then throw the whole body into it.
			pose.Waist = rel(-0.1 - math.sin(t * 19) * 0.02, 0, 0, shake)
		end
		withLean(pose, t, 0.2, 0.9, 0.5)
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
		local torso = ctx.rig.motors.Waist.part1
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
	if p.gesture.finish then
		pcall(p.gesture.finish, p.ctx)
	end
	if not model.Parent then
		-- The bot left (match over): forget its joints.
		for _, joint in p.ctx.rig.motors do
			restOf[joint.inst] = nil
		end
	end
	for name in p.written do
		local joint = p.ctx.rig.motors[name]
		if joint then
			restore(joint.inst)
		end
	end
end

-- Writes a pose onto a rig's joints (on top of each joint's base), noting what it wrote.
local function applyPose(rig: Rig, pose: Pose, written: { [string]: boolean }, scale: number?)
	local k = scale or 1
	for name, jp in pose do
		local joint = rig.motors[name]
		if joint then
			local motor = joint.inst
			local base = currentBase(motor)
			local value = base
			if jp.abs then
				value = base:Lerp(jp.abs, clamp01((jp.w or 1) * k))
			elseif jp.rel then
				value = if k >= 1 then base * jp.rel else base:Lerp(base * jp.rel, clamp01(k))
			end
			write(motor, value)
			written[name] = true
		end
	end
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

---------------------------------------------------------------- idle life

-- Between gestures, everyone at a table near you stays alive: slow breathing, a little
-- sway, the head following whoever's turn it is (the seat with the turn tag up),
-- glancing at the others now and then, and turning to look when someone at the table
-- does something. Your own avatar is left to Roblox (your camera is in its head).
type Idle = {
	body: Model,
	table: Model,
	rig: Rig,
	phase: number,
	look: Vector3?,
	glance: Vector3?,
	glanceUntil: number,
	nextGlance: number,
	blend: number,
	written: { [string]: boolean },
}
local idles: { [Model]: Idle } = {}
local lastScan = 0
local IDLE_SCAN = 0.5

local function headOf(body: Model): Vector3?
	local head = body:FindFirstChild("Head")
	return if head and head:IsA("BasePart") then head.Position else nil
end

-- The seats whose turn it is at each table (the server shows their TurnTag), refreshed
-- with every scan rather than searched every frame.
local turnSeats: { [Model]: { Seat } } = {}

local function findTurnSeats(tableModel: Model): { Seat }
	local list = {}
	for _, d in tableModel:GetDescendants() do
		if d:IsA("BillboardGui") and d.Name == "TurnTag" and d.Enabled and d.Parent and d.Parent:IsA("Seat") then
			table.insert(list, d.Parent :: Seat)
		end
	end
	return list
end

local function turnPoint(tableModel: Model, except: Model): Vector3?
	for _, seat in turnSeats[tableModel] or {} do
		local sitter = seat.Occupant and seat.Occupant.Parent
		if sitter ~= except then
			return seat.Position + Vector3.new(0, 3, 0)
		end
	end
	return nil
end

local function bodiesAt(tableModel: Model): { Model }
	local list = {}
	local bots = tableModel:FindFirstChild("Bots")
	if bots then
		for _, body in bots:GetChildren() do
			if body:IsA("Model") then
				table.insert(list, body)
			end
		end
	end
	for _, d in tableModel:GetDescendants() do
		if d:IsA("Seat") and d.Occupant then
			local body = d.Occupant.Parent
			if body and body:IsA("Model") and body ~= Players.LocalPlayer.Character and not table.find(list, body) then
				table.insert(list, body)
			end
		end
	end
	return list
end

local function endIdle(body: Model)
	local idle = idles[body]
	if not idle then
		return
	end
	idles[body] = nil
	for name in idle.written do
		local joint = idle.rig.motors[name]
		if joint and body.Parent then
			restore(joint.inst)
		end
	end
end

local function scanIdles(now: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local seen: { [Model]: boolean } = {}
	table.clear(turnSeats)
	for _, inst in CollectionService:GetTagged(Config.TableTag) do
		if inst:IsA("Model") and inst:GetAttribute("State") ~= "Free" then
			local anchor = anchorPosition(inst)
			if (camera.CFrame.Position - anchor).Magnitude <= (if Perf.isLow() then LOW_IDLE_DISTANCE else MAX_DISTANCE) then
				turnSeats[inst] = findTurnSeats(inst)
				for _, body in bodiesAt(inst) do
					seen[body] = true
					if not idles[body] then
						local rig = rigOf(body)
						if rig then
							idles[body] = {
								body = body,
								table = inst,
								rig = rig,
								phase = math.random() * 10,
								look = nil,
								glance = nil,
								glanceUntil = 0,
								nextGlance = now + 2 + math.random() * 5,
								blend = 0,
								written = {},
							}
						end
					end
				end
			end
		end
	end
	for body in idles do
		if not seen[body] or not body.Parent then
			endIdle(body)
		end
	end
end

local function stepIdle(idle: Idle, now: number, dt: number)
	if playing[idle.body] then
		-- A gesture owns the joints; ease back in once it's done.
		idle.blend = 0
		table.clear(idle.written)
		return
	end
	idle.blend = math.min(1, idle.blend + dt / 0.6)
	local w = smooth(idle.blend)
	local t = now + idle.phase
	-- Where to look: a glance, whoever's turn it is, or down at the table.
	if now >= idle.nextGlance then
		local others = bodiesAt(idle.table)
		local pick = others[math.random(1, math.max(1, #others))]
		local point = pick and pick ~= idle.body and headOf(pick)
		if point then
			idle.glance = point
			idle.glanceUntil = now + 0.9 + math.random() * 0.8
		end
		idle.nextGlance = now + 4 + math.random() * 6
	end
	local target = if now < idle.glanceUntil then idle.glance else nil
	target = target or turnPoint(idle.table, idle.body) or (anchorPosition(idle.table) + Vector3.new(0, 0.3, 0))
	local look = idle.look or (target :: Vector3)
	look = look:Lerp(target :: Vector3, 1 - math.exp(-dt * 4))
	idle.look = look
	local pose: Pose = {
		Waist = rel(math.sin(t * 1.5) * 0.02 - 0.02, math.sin(t * 0.37) * 0.03, 0, 1),
	}
	if idle.rig.motors.Neck then
		pose.Neck = { abs = aimNeck(idle.rig.motors.Neck, look), w = 0.8 }
	end
	-- Slow shoulder breathing.
	pose.RightShoulder = rel(0, 0, math.sin(t * 1.5) * 0.015, 1)
	pose.LeftShoulder = rel(0, 0, -math.sin(t * 1.5) * 0.015, 1)
	applyPose(idle.rig, pose, idle.written, w)
end

-- Someone at `tableModel` did something: everyone else there turns to look.
local function lookAtActor(tableModel: Model, actor: Model, kind: string)
	if kind == "think" then
		return
	end
	local point = headOf(actor)
	if not point then
		return
	end
	local now = os.clock()
	for body, idle in idles do
		if idle.table == tableModel and body ~= actor then
			-- A beat later, like real people noticing.
			idle.glance = point
			idle.glanceUntil = now + 1.1 + math.random() * 0.5
			idle.nextGlance = math.max(idle.nextGlance, idle.glanceUntil + 2)
		end
	end
end

local lastStep = os.clock()
local function step()
	local now = os.clock()
	local dt = math.clamp(now - lastStep, 0, 0.1)
	lastStep = now
	if now - lastScan > IDLE_SCAN then
		lastScan = now
		scanIdles(now)
	end
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
				local joint = p.ctx.rig.motors[name]
				if joint then
					write(joint.inst, currentBase(joint.inst))
				end
			end
		end
		applyPose(p.ctx.rig, pose, p.written)
	end
	for _, idle in idles do
		stepIdle(idle, now, dt)
	end
	stepFlights(now)
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
		-- Tell the table camera where the action is: the hand's target, or the face for
		-- reactions and emotes.
		local focusPoint = if icon and rig.head then rig.head.Position else target :: Vector3
		endIdle(body)
		lookAtActor(model, body, payload.kind)
		for _, listener in actionListeners do
			task.spawn(listener, payload.table, focusPoint, payload.kind)
		end
		playing[body] = {
			gesture = gesture,
			ctx = { rig = rig, center = center, front = front, target = target :: Vector3, from = from, to = to, fired = {}, board = model },
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

-- The body sitting at a table seat, for Showtime: `who` = { seat = table seat, userId?, bot? }.
function Avatars.bodyAt(tableId: any, who: any): Model?
	local model = findTable(tableId)
	if not model or type(who) ~= "table" then
		return nil
	end
	return bodyOf(model, who)
end

-- Calls `listener(tableId, point, kind)` whenever a gesture starts at any table.
function Avatars.onAction(listener: (any, Vector3, string) -> ())
	table.insert(actionListeners, listener)
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
