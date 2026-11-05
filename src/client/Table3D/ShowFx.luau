-- Camera effects for Showtime (Table3D/Showtime), so the intro and the celebrations feel
-- like a broadcast replay instead of a plain camera move:
--   * motion blur: Roblox has no motion blur, so a BlurEffect follows how fast the camera
--     turns and travels (whip pans between players blur, holds are sharp);
--   * depth of field on whoever is on stage, so the room behind melts away;
--   * a punchier, slightly warm color grade;
--   * a vignette around the screen edges;
--   * impact: a quick zoom punch (field of view) plus a short shake on big hits, and a
--     white flash on the biggest ones.
-- Everything is local to this screen (effects parented to the camera) and goes away when
-- the show ends. Low-detail mode (client/Perf) skips the blur and depth of field.
-- The numbers live in Table3D/FxMath.

local TweenService = game:GetService("TweenService")

local Lighting = game:GetService("Lighting")

local FxMath = require(script.Parent.FxMath)
local Perf = require(script.Parent.Parent.Perf)

local ShowFx = {}

type State = {
	camera: Camera,
	blur: BlurEffect?,
	dof: DepthOfFieldEffect?,
	grade: ColorCorrectionEffect,
	vignette: Frame?,
	flash: Frame?,
	last: CFrame?,
	blurNow: number,
	kickAt: number,
	kickPower: number,
}

local state: State? = nil

local function make(className: string, props: { [string]: any }, parent: Instance): any
	local inst = Instance.new(className)
	for key, value in props do
		(inst :: any)[key] = value
	end
	inst.Parent = parent
	return inst
end

-- Dark gradient strips on the four screen edges.
local function vignette(gui: ScreenGui): Frame
	local holder = make("Frame", {
		Name = "Vignette",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
	}, gui)
	local sides = {
		{ pos = UDim2.fromScale(0, 0), size = UDim2.fromScale(1, 0.22), rot = 90 },
		{ pos = UDim2.fromScale(0, 0.78), size = UDim2.fromScale(1, 0.22), rot = -90 },
		{ pos = UDim2.fromScale(0, 0), size = UDim2.fromScale(0.16, 1), rot = 0 },
		{ pos = UDim2.fromScale(0.84, 0), size = UDim2.fromScale(0.16, 1), rot = 180 },
	}
	for _, side in sides do
		local f = make("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			Position = side.pos,
			Size = side.size,
			ZIndex = 0,
		}, holder)
		make("UIGradient", {
			Rotation = side.rot,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }),
		}, f)
	end
	return holder
end

-- Starts the effects. `gui` is the Showtime overlay (for the vignette and flash).
function ShowFx.begin(camera: Camera, gui: ScreenGui)
	ShowFx.finish(true)
	local low = Perf.isLow()
	-- Only one depth of field applies at a time: leave a scene's own one alone.
	local ownFocus = false
	for _, d in Lighting:GetChildren() do
		ownFocus = ownFocus or (d:IsA("DepthOfFieldEffect") and d.Enabled)
	end
	local s: State = {
		camera = camera,
		blur = if low then nil else make("BlurEffect", { Name = "ShowtimeMotionBlur", Size = 0, Enabled = false }, camera),
		dof = if low or ownFocus then nil else make("DepthOfFieldEffect", {
			Name = "ShowtimeFocus",
			FarIntensity = 0,
			NearIntensity = 0,
			FocusDistance = 10,
			InFocusRadius = 6,
		}, camera),
		grade = make("ColorCorrectionEffect", { Name = "ShowtimeGrade", Saturation = 0, Contrast = 0, Brightness = 0 }, camera),
		vignette = vignette(gui),
		flash = make("Frame", {
			Name = "Flash",
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 30,
		}, gui),
		last = nil,
		blurNow = 0,
		kickAt = -1,
		kickPower = 0,
	}
	state = s
	-- Ease the look in.
	local info = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(s.grade, info, { Saturation = 0.18, Contrast = 0.1, Brightness = 0.02, TintColor = Color3.fromRGB(255, 246, 236) }):Play()
	if s.dof then
		TweenService:Create(s.dof, info, { FarIntensity = 0.45, NearIntensity = 0.25 }):Play()
	end
end

-- A hit: zoom punch and shake, `power` 0..1. Big hits (power >= 0.8) also flash white.
function ShowFx.kick(power: number)
	local s = state
	if not s then
		return
	end
	s.kickAt = os.clock()
	s.kickPower = math.clamp(power, 0, 1)
	if power >= FxMath.FlashAt and s.flash then
		s.flash.BackgroundTransparency = 0.55
		TweenService:Create(s.flash, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	end
end

-- Called every frame with where the camera wants to be. Returns the frame and field-of-
-- view change to actually use (shake and zoom punch added), and updates blur and focus.
function ShowFx.frame(dt: number, cf: CFrame, focus: Vector3?): (CFrame, number)
	local s = state
	if not s then
		return cf, 0
	end
	-- Motion blur from how fast the view turns and moves.
	if s.blur and s.last and dt > 0 then
		local last = s.last :: CFrame
		local turn = math.acos(math.clamp(last.LookVector:Dot(cf.LookVector), -1, 1)) / dt
		local travel = (cf.Position - last.Position).Magnitude / dt
		s.blurNow = FxMath.chase(s.blurNow, FxMath.blurFor(turn, travel), dt)
		s.blur.Size = s.blurNow
		s.blur.Enabled = s.blurNow > FxMath.BlurFloor
	end
	s.last = cf
	if s.dof and focus then
		local distance = (focus - cf.Position).Magnitude
		s.dof.FocusDistance = distance
		s.dof.InFocusRadius = math.max(4, distance * 0.35)
	end
	-- Zoom punch and shake after a kick, dying out.
	local since = os.clock() - s.kickAt
	local power = if s.kickAt < 0 then 0 else FxMath.kickLeft(s.kickPower, since)
	if power <= 0 then
		return cf, 0
	end
	local t = since * 38
	local shake = CFrame.Angles(math.sin(t) * 0.012 * power, math.cos(t * 1.3) * 0.012 * power, math.sin(t * 0.7) * 0.02 * power)
	return cf * shake, -FxMath.KickFov * power
end

-- Ends the effects (eased out unless `now`).
function ShowFx.finish(now: boolean?)
	local s = state
	if not s then
		return
	end
	state = nil
	local function clear()
		for _, inst in { s.blur, s.dof, s.grade } do
			if inst then
				inst:Destroy()
			end
		end
	end
	if now then
		clear()
		return
	end
	local info = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if s.blur then
		s.blur.Enabled = false
	end
	TweenService:Create(s.grade, info, { Saturation = 0, Contrast = 0, Brightness = 0, TintColor = Color3.new(1, 1, 1) }):Play()
	if s.dof then
		TweenService:Create(s.dof, info, { FarIntensity = 0, NearIntensity = 0 }):Play()
	end
	task.delay(0.32, clear)
end

return ShowFx
