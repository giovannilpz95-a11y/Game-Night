-- The table is the stage: for a Showtime move, a stand-in copy of the player (Puppet)
-- hops from their chair up onto the table, performs the move standing (full body, with
-- its sounds and particle bursts on the beat) and hops back. The real body stays seated
-- and is hidden on this screen meanwhile. Every client does this locally.
--
-- Effects that sell it: a soft spotlight over the stand-in, motion trails off the hands
-- and feet, a dust puff and a glowing ring where it lands, and every beat reported to
-- Stage.onHit so Showtime can kick its camera. Low-detail mode (client/Perf) keeps only
-- the ring and the dust.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Dance = require(script.Parent.Dance)
local FxMath = require(script.Parent.FxMath)
local Perf = require(script.Parent.Parent.Perf)
local Puppet = require(script.Parent.Puppet)
local Audio = require(script.Parent.Parent.Audio)

local Stage = {}

local HOP = 0.42 -- seconds to hop up (and back down)
local HOP_HEIGHT = 2.4
local LAND = 0.22 -- the landing squash, easing into the move

local AIR: Dance.Move = {
	length = 1,
	keys = {
		{
			t = 0,
			RH = { 55, 0, 0 }, LH = { 55, 0, 0 }, RK = { -85, 0, 0 }, LK = { -85, 0, 0 },
			RS = { 20, 0, 70 }, LS = { 20, 0, -70 }, RE = { 30, 0, 0 }, LE = { 30, 0, 0 }, N = { 10, 0, 0 },
		},
	},
}

export type Handle = {
	root: () -> BasePart?,
	alive: () -> boolean,
	stop: () -> (),
}

type Show = {
	body: Model,
	puppet: Puppet.Puppet,
	move: Dance.Move,
	start: number,
	seconds: number,
	from: CFrame, -- the puppet root at the chair
	to: CFrame, -- the puppet root on the table
	hidden: { [Instance]: boolean },
	lastT: number,
	colors: ColorSequence?,
	emitter: ParticleEmitter?,
	ambient: ParticleEmitter?,
	light: BasePart?, -- the spotlight rig above the stand-in
	landed: boolean,
	done: boolean,
}

local shows: { [Model]: Show } = {}
local folder: Folder? = nil
local hitListeners: { (BasePart, number) -> () } = {}

local function stageFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "GameNightStage"
	f.Parent = workspace
	folder = f
	return f
end

local function hide(show: Show)
	for _, d in show.body:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = 1
			show.hidden[d] = true
		end
	end
end

-- Shows the real body again. Your own body in Table view is hidden again by the table
-- camera the next frame.
local function unhide(show: Show)
	for inst in show.hidden do
		if inst.Parent then
			(inst :: any).LocalTransparencyModifier = 0
		end
	end
	table.clear(show.hidden)
end

local function emitter(parent: Instance, colors: ColorSequence, rate: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Color = colors
	e.Rate = rate
	e.Lifetime = NumberRange.new(1.0, 1.7)
	e.Speed = NumberRange.new(7, 12)
	e.SpreadAngle = Vector2.new(60, 60)
	e.Acceleration = Vector3.new(0, -16, 0)
	e.Drag = 1.5
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-200, 200)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	e.LightEmission = 0.45
	e.Parent = parent
	return e
end

local function hit(show: Show, power: number)
	for _, fn in hitListeners do
		task.spawn(fn, show.puppet.root, power)
	end
end

local function firstColor(colors: ColorSequence?): Color3
	return if colors then colors.Keypoints[1].Value else Color3.fromRGB(255, 236, 140)
end

-- A glowing ring that spreads over the tabletop and a puff of dust, where feet land.
local function landingFx(at: CFrame, colors: ColorSequence?, big: boolean)
	local ring = Instance.new("Part")
	ring.Name = "LandingRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = firstColor(colors)
	ring.Transparency = 0.35
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Size = Vector3.new(0.05, 0.6, 0.6)
	-- A cylinder's axis is X: stand it up so the disc lies flat on the table.
	ring.CFrame = CFrame.new(at.Position + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = stageFolder()
	local spread = if big then 7 else 5
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.05, spread, spread),
		Transparency = 1,
	}):Play()
	local dust = Instance.new("ParticleEmitter")
	dust.Color = ColorSequence.new(Color3.fromRGB(235, 225, 210))
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(0.45, 0.8)
	dust.Speed = NumberRange.new(4, 7)
	dust.SpreadAngle = Vector2.new(85, 85)
	dust.EmissionDirection = Enum.NormalId.Top
	dust.Acceleration = Vector3.new(0, 2, 0)
	dust.Drag = 6
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.4) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	dust.Parent = ring
	dust:Emit(if Perf.isLow() then 6 else 14)
	task.delay(1, function()
		ring:Destroy()
	end)
end

-- Ribbons off the hands and feet that trail every swing.
local function trails(puppet: Puppet.Puppet, colors: ColorSequence?)
	local color = firstColor(colors)
	for _, name in { "RightHand", "LeftHand", "RightFoot", "LeftFoot" } do
		local part = puppet:part(name)
		if not part then
			continue
		end
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.22, 0)
		a0.Parent = part
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.22, 0)
		a1.Parent = part
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
		trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
		trail.Lifetime = 0.22
		trail.MinLength = 0.05
		trail.LightEmission = 0.6
		trail.FaceCamera = true
		trail.Parent = part
	end
end

-- A soft spotlight from above that follows the stand-in onto the table.
local function spotlight(over: CFrame): BasePart
	local rig = Instance.new("Part")
	rig.Name = "Spotlight"
	rig.Transparency = 1
	rig.Anchored = true
	rig.CanCollide = false
	rig.CanQuery = false
	rig.CanTouch = false
	rig.Size = Vector3.new(0.2, 0.2, 0.2)
	rig.CFrame = CFrame.new(over.Position + Vector3.new(0, 9, 0))
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = 55
	light.Range = 16
	light.Brightness = 0
	light.Color = Color3.fromRGB(255, 240, 220)
	light.Shadows = true
	light.Parent = rig
	rig.Parent = stageFolder()
	TweenService:Create(light, TweenInfo.new(0.4), { Brightness = 3 }):Play()
	return rig
end

local function finish(show: Show)
	if show.done then
		return
	end
	show.done = true
	shows[show.body] = nil
	show.puppet:destroy()
	unhide(show)
	local light = show.light
	if light then
		show.light = nil
		local spot = light:FindFirstChildOfClass("SpotLight")
		if spot then
			TweenService:Create(spot, TweenInfo.new(0.3), { Brightness = 0 }):Play()
		end
		task.delay(0.35, function()
			light:Destroy()
		end)
	end
end

local function arc(from: CFrame, to: CFrame, k: number): CFrame
	local e = Dance.ease("io", k)
	local cf = from:Lerp(to, e)
	return cf + Vector3.new(0, math.sin(math.pi * k) * HOP_HEIGHT, 0)
end

local function step()
	local now = os.clock()
	for _, show in shows do
		local t = now - show.start
		if t >= show.seconds or not show.body.Parent then
			finish(show)
			continue
		end
		hide(show)
		local puppet = show.puppet
		local outAt = show.seconds - HOP
		if t < HOP then
			-- Up onto the table.
			puppet.root.CFrame = arc(show.from, show.to, t / HOP)
			puppet:pose(AIR, 0, 1)
		elseif t >= outAt then
			-- Back to the chair.
			puppet.root.CFrame = arc(show.to, show.from, (t - outAt) / HOP)
			puppet:pose(AIR, 0, 1)
		else
			local mt = t - HOP
			local landing = math.clamp(mt / LAND, 0, 1)
			-- Ease out of the move just before hopping back.
			local fade = math.clamp((outAt - t) / 0.2, 0, 1)
			local transforms = Dance.cframes(Dance.sample(show.move, mt), fade)
			if not show.landed then
				show.landed = true
				landingFx(show.to - Vector3.new(0, show.puppet.standHeight, 0), show.colors, show.ambient ~= nil)
				Audio.playAt("tick", show.to.Position)
				hit(show, 0.35)
			end
			if landing < 1 then
				-- Squash on landing, then into the move.
				local dip = -0.45 * math.sin(math.pi * landing)
				transforms.Root = CFrame.new(0, dip, 0) * (transforms.Root or CFrame.identity)
			end
			puppet.root.CFrame = show.to
			puppet:apply(transforms)
			for _, cue in Dance.cuesBetween(show.move, show.lastT, mt) do
				if cue.sound then
					Audio.playAt(cue.sound, puppet.root.Position)
				end
				if cue.burst and show.emitter then
					show.emitter:Emit(cue.burst)
				end
				hit(show, FxMath.cuePower(cue))
			end
			show.lastT = mt
		end
	end
end

local started = false
local function ensureStarted()
	if started then
		return
	end
	started = true
	RunService.PreSimulation:Connect(step)
end

-- Performs `move` with `body`: hops onto the table to `feet` (a CFrame on the tabletop,
-- facing where they should face), plays for `seconds` in all (hops included), hops back.
-- `colors` = particle colors for bursts; `ambient` keeps particles flowing (celebrations).
function Stage.perform(body: Model, feet: CFrame, move: Dance.Move, seconds: number, colors: ColorSequence?, ambient: boolean?): Handle?
	ensureStarted()
	local old = shows[body]
	if old then
		finish(old)
	end
	local puppet = Puppet.new(body, stageFolder())
	if not puppet then
		return nil
	end
	local bodyRoot = body:FindFirstChild("HumanoidRootPart")
	local to = feet * CFrame.new(0, puppet.standHeight, 0)
	local from = if bodyRoot and bodyRoot:IsA("BasePart") then CFrame.new(bodyRoot.Position) * (to - to.Position) else to
	local show: Show = {
		body = body,
		puppet = puppet,
		move = move,
		start = os.clock(),
		seconds = math.max(seconds, HOP * 2 + 0.3),
		from = from,
		to = to,
		hidden = {},
		lastT = 0,
		colors = colors,
		emitter = nil,
		ambient = nil,
		light = nil,
		landed = false,
		done = false,
	}
	puppet.root.CFrame = from
	local torso = puppet:part("UpperTorso") or puppet.root
	local burstColors = colors or ColorSequence.new(Color3.fromRGB(255, 236, 140), Color3.new(1, 1, 1))
	show.emitter = emitter(torso, burstColors, 0)
	if ambient then
		local head = puppet:part("Head") or torso
		show.ambient = emitter(head, burstColors, 18)
	end
	if not Perf.isLow() then
		trails(puppet, colors)
		show.light = spotlight(to)
	end
	hide(show)
	shows[body] = show
	Audio.playAt("pop", from.Position)
	return {
		root = function()
			return if show.done then nil else puppet.root
		end,
		alive = function()
			return not show.done
		end,
		stop = function()
			finish(show)
		end,
	}
end

-- Calls `fn(standInRoot, power)` on every beat of every show (landing, bursts, the big
-- hits), `power` 0..1 (Table3D/FxMath.cuePower).
function Stage.onHit(fn: (BasePart, number) -> ())
	table.insert(hitListeners, fn)
end

-- Ends every show now (a new match took the table).
function Stage.stopAll()
	for _, show in shows do
		finish(show)
	end
end

return Stage
