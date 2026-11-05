-- The numbers behind Showtime's camera effects (Table3D/ShowFx), kept pure so tests
-- can check them.

local FxMath = {}

FxMath.MaxBlur = 14 -- BlurEffect.Size at full speed
FxMath.BlurPerRadian = 5 -- blur per radian/second of turning
FxMath.BlurPerStud = 0.28 -- blur per stud/second of travel
FxMath.BlurFloor = 1.2 -- below this the blur is off, so holds stay sharp
FxMath.KickSeconds = 0.45 -- how long a hit's zoom punch and shake last
FxMath.KickFov = 7 -- degrees the view punches in on a full-power hit
FxMath.KickMin = 0.3 -- weaker cues don't move the camera
FxMath.FlashAt = 0.8 -- hits this strong also flash the screen

-- How much motion blur a camera moving this fast wants (turn in radians/second,
-- travel in studs/second).
function FxMath.blurFor(turn: number, travel: number): number
	return math.clamp(turn * FxMath.BlurPerRadian + travel * FxMath.BlurPerStud, 0, FxMath.MaxBlur)
end

-- Moves the shown blur toward `want` over `dt` seconds: rises fast and settles slower,
-- like a shutter catching a whip pan.
function FxMath.chase(now: number, want: number, dt: number): number
	local rate = if want > now then 18 else 8
	return now + (want - now) * (1 - math.exp(-rate * dt))
end

-- How hard a move's cue hits the camera, 0..1 (a particle burst's size, or the big
-- landing sound).
function FxMath.cuePower(cue: { burst: number?, sound: string? }): number
	local power = (cue.burst or 0) / 28
	if cue.sound == "caught" then
		power = 1
	elseif cue.sound == "callout" then
		power = math.max(power, 0.5)
	end
	return math.clamp(power, 0, 1)
end

-- What's left of a kick `since` seconds after it (eases out to 0).
function FxMath.kickLeft(power: number, since: number): number
	if since < 0 or since >= FxMath.KickSeconds then
		return 0
	end
	local fade = 1 - since / FxMath.KickSeconds
	return power * fade * fade
end

return FxMath
