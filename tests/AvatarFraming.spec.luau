local ReplicatedStorage = game:GetService("ReplicatedStorage")
local F = require(ReplicatedStorage.Shared.AvatarFraming)

return function(T)
	local function near(a, b, msg)
		T.ok(math.abs(a - b) < 1e-6, `{msg}: {a} vs {b}`)
	end

	T.test("wide screens dock the panel right and leave the stage on the left", function()
		local s = F.split(1280, 720, 58, 0, 0, 0)
		T.eq(s.portrait, false)
		T.ok(s.stage.x < s.panel.x, "stage left of panel")
		T.ok(s.stage.x + s.stage.w <= s.panel.x, "no overlap")
		T.ok(s.panel.x + s.panel.w <= 1280, "panel on screen")
		T.ok(s.stage.w >= 140, "stage wide enough for an avatar")
	end)

	T.test("a landscape phone still gets a usable stage and panel", function()
		local s = F.split(844, 390, 50, 44, 44, 20)
		T.ok(s.stage.w >= 140, `stage {s.stage.w}`)
		T.ok(s.panel.w >= 300, `panel {s.panel.w}`)
		T.ok(s.stage.x >= 44 and s.panel.x + s.panel.w <= 844 - 44, "inside the safe area")
		T.ok(s.panel.y + s.panel.h <= 390 - 20, "above the home bar")
	end)

	T.test("tall screens put the panel along the bottom", function()
		local s = F.split(390, 844, 50, 0, 0, 30)
		T.eq(s.portrait, true)
		T.ok(s.stage.y + s.stage.h <= s.panel.y, "stage above panel")
		T.ok(s.panel.y + s.panel.h <= 844 - 30, "panel on screen")
	end)

	T.test("fit distance shows the whole avatar in its part of the screen", function()
		local h, w = 6, 3
		local fov, aspect = F.FOV, 16 / 9
		local d = F.fitDistance(h, w, 0, fov, aspect, 0.4, 0.9)
		local t = math.tan(math.rad(fov) / 2)
		T.ok(2 * d * t * 0.9 >= h, "height fits")
		T.ok(2 * d * t * aspect * 0.4 >= w, "width fits")
		-- A bigger avatar (huge hat) needs the camera further away.
		T.ok(F.fitDistance(9, w, 0, fov, aspect, 0.4, 0.9) > d, "taller avatar, further camera")
		T.ok(F.fitDistance(h, 8, 0, fov, aspect, 0.4, 0.9) > d, "wide wings, further camera")
	end)

	T.test("shift puts the avatar in the middle of the stage", function()
		local s = F.split(1280, 720, 58, 0, 0, 0)
		local nx, ny = F.center(s.stage, 1280, 720)
		T.ok(nx < 0, "stage center is left of screen center")
		local d, aspect = 10, 1280 / 720
		local sx, sy = F.shift(nx, ny, d, F.FOV, aspect)
		-- Camera moved by (sx, sy): the avatar at the origin projects to -sx / halfWidth.
		local t = math.tan(math.rad(F.FOV) / 2)
		near(-sx / (d * t * aspect), nx, "x")
		near(-sy / (d * t), ny, "y")
	end)

	T.test("zoom steps clamp and the focus moves toward the head when close", function()
		T.ok(F.stepZoom(1, 1) < 1, "+ zooms in")
		T.ok(F.stepZoom(1, -1) > 1, "- zooms out")
		local z = 1
		for _ = 1, 30 do
			z = F.stepZoom(z, 1)
		end
		T.eq(z, F.ZOOM_MIN)
		for _ = 1, 30 do
			z = F.stepZoom(z, -1)
		end
		T.eq(z, F.ZOOM_MAX)
		T.eq(F.headBias(1), 0)
		T.eq(F.headBias(1.5), 0)
		T.ok(F.headBias(F.ZOOM_MIN) > F.headBias(0.7), "closer = more head")
		T.eq(F.clampPitch(5), F.PITCH_MAX)
	end)

	T.test("drag spins the avatar and the shown turn eases the short way round", function()
		T.ok(F.spin(0, 100) > 0, "drag right turns")
		T.ok(math.abs(F.spin(0, -1) - (math.pi * 2 - F.SPIN_PER_PIXEL)) < 1e-9, "wraps into 0..2pi")
		-- From 350 degrees to 10 degrees goes forward through 0, not back through 180.
		local shown = math.rad(350)
		local nextYaw = F.easeYaw(shown, math.rad(10), 1 / 60)
		T.ok(nextYaw > shown or nextYaw < math.rad(10), "short way round")
		local y = shown
		for _ = 1, 300 do
			y = F.easeYaw(y, math.rad(10), 1 / 60)
		end
		T.eq(y, math.rad(10))
	end)

	T.test("closing returns you to your spot unless something else moved you", function()
		T.ok(F.shouldReturn(0, false), "still on stage")
		T.ok(not F.shouldReturn(0, true), "seated at a table")
		T.ok(not F.shouldReturn(F.RETURN_RADIUS + 1, false), "moved away")
	end)
end
