-- Camera math for the Dressing Room: where the try-on window sits on screen, how far the
-- camera has to be to fit the whole avatar in the free part of the screen, the zoom steps
-- and how far to shift the camera so the avatar sits in the middle of that free part.
-- Pure numbers (no Vector3 or Instances), so tests/AvatarFraming.spec.luau can check it.

local AvatarFraming = {}

AvatarFraming.FOV = 40 -- vertical field of view while dressing, degrees
AvatarFraming.MARGIN = 1.15 -- room left around the avatar when it's fitted
AvatarFraming.ZOOM_MIN = 0.3 -- 1 = whole avatar fits; smaller = closer
AvatarFraming.ZOOM_MAX = 1.8
AvatarFraming.ZOOM_STEP = 1.25 -- one + or - press
AvatarFraming.PITCH_MIN = -0.35 -- radians the camera can tilt down / up from level
AvatarFraming.PITCH_MAX = 0.6

export type Rect = { x: number, y: number, w: number, h: number }
export type Split = { portrait: boolean, panel: Rect, stage: Rect }

local function clamp(v: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, v))
end

-- Splits the screen into the catalog panel and the stage (where the avatar shows).
-- Wide screens dock the panel on the right; tall screens put it along the bottom.
-- `top` is the first free y below Roblox's top bar; left/right/bottom are safe insets.
function AvatarFraming.split(width: number, height: number, top: number, left: number, right: number, bottom: number): Split
	local gap = 8
	local x0, y0 = left + gap, top
	local usableW = width - left - right - gap * 2
	local usableH = height - top - bottom - gap
	if height > width * 1.1 then
		local panelH = math.floor(clamp(usableH * 0.56, 260, usableH - 160))
		local stageH = usableH - panelH - gap
		return {
			portrait = true,
			stage = { x = x0, y = y0, w = usableW, h = stageH },
			panel = { x = x0, y = y0 + stageH + gap, w = usableW, h = panelH },
		}
	end
	local panelW = math.floor(clamp(usableW * 0.58, math.min(340, usableW - 140), 720))
	local stageW = usableW - panelW - gap
	return {
		portrait = false,
		stage = { x = x0, y = y0, w = stageW, h = usableH },
		panel = { x = x0 + stageW + gap, y = y0, w = panelW, h = usableH },
	}
end

-- Distance from the avatar's center that fits a box of height h, width w and depth d into
-- a part of the screen that's fracW of its width and fracH of its height.
function AvatarFraming.fitDistance(h: number, w: number, d: number, fovDeg: number, aspect: number, fracW: number, fracH: number): number
	local t = math.tan(math.rad(fovDeg) / 2)
	local m = AvatarFraming.MARGIN
	local byHeight = (h * m) / (2 * t * math.max(fracH, 0.05))
	local byWidth = (w * m) / (2 * t * aspect * math.max(fracW, 0.05))
	return math.max(byHeight, byWidth) + d / 2
end

-- Sideways and upward camera shift (studs, along the camera's right and up vectors) that
-- makes a point `distance` ahead show up at normalized screen spot (nx, ny), where -1..1
-- runs left to right and bottom to top.
function AvatarFraming.shift(nx: number, ny: number, distance: number, fovDeg: number, aspect: number): (number, number)
	local t = math.tan(math.rad(fovDeg) / 2)
	return -nx * distance * t * aspect, -ny * distance * t
end

-- The middle of a screen rect as normalized screen coordinates (see `shift`).
function AvatarFraming.center(rect: Rect, width: number, height: number): (number, number)
	local cx = rect.x + rect.w / 2
	local cy = rect.y + rect.h / 2
	return cx / width * 2 - 1, 1 - cy / height * 2
end

function AvatarFraming.clampZoom(zoom: number): number
	return clamp(zoom, AvatarFraming.ZOOM_MIN, AvatarFraming.ZOOM_MAX)
end

-- `steps` > 0 zooms in (closer), < 0 zooms out. Fractions work for the mouse wheel.
function AvatarFraming.stepZoom(zoom: number, steps: number): number
	return AvatarFraming.clampZoom(zoom / (AvatarFraming.ZOOM_STEP ^ steps))
end

-- How far the focus moves from the avatar's middle toward its head as you zoom in:
-- 0 when fitted or zoomed out, up to 0.85 at the closest zoom (hats and faces).
function AvatarFraming.headBias(zoom: number): number
	if zoom >= 1 then
		return 0
	end
	return 0.85 * (1 - zoom) / (1 - AvatarFraming.ZOOM_MIN)
end

function AvatarFraming.clampPitch(pitch: number): number
	return clamp(pitch, AvatarFraming.PITCH_MIN, AvatarFraming.PITCH_MAX)
end

return AvatarFraming
