local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SeatLook = require(ReplicatedStorage.Shared.SeatLook)

return function(T)
	local function near(a: number, b: number, msg: string)
		T.ok(math.abs(a - b) < 1e-6, `{msg}: {a} vs {b}`)
	end

	T.test("look stays inside the neck's range", function()
		local base = math.rad(-30) -- resting view looks down at the table
		local look = SeatLook.clamp({ yaw = 10, pitch = 10 }, base)
		near(look.yaw, SeatLook.YAW_LIMIT, "yaw capped right")
		near(base + look.pitch, SeatLook.PITCH_UP, "can't look past straight up's limit")
		look = SeatLook.clamp({ yaw = -10, pitch = -10 }, base)
		near(look.yaw, -SeatLook.YAW_LIMIT, "yaw capped left")
		near(base + look.pitch, SeatLook.PITCH_DOWN, "can't look further down than the lap")
		look = SeatLook.clamp({ yaw = 0.2, pitch = 0.1 }, base)
		near(look.yaw, 0.2, "small yaw untouched")
		near(look.pitch, 0.1, "small pitch untouched")
	end)

	T.test("mouse right turns right, mouse down looks down", function()
		local look = SeatLook.turn({ yaw = 0, pitch = 0 }, 100, 0, SeatLook.MOUSE, 0)
		T.ok(look.yaw < 0, "moving right lowers yaw (turns right)")
		look = SeatLook.turn({ yaw = 0, pitch = 0 }, 0, 50, SeatLook.MOUSE, 0)
		T.ok(look.pitch < 0, "moving down looks down")
		-- A huge flick still lands inside the range.
		look = SeatLook.turn({ yaw = 0, pitch = 0 }, 1e6, -1e6, SeatLook.MOUSE, math.rad(-40))
		near(look.yaw, -SeatLook.YAW_LIMIT, "flick capped")
		near(math.rad(-40) + look.pitch, SeatLook.PITCH_UP, "flick up capped")
	end)

	T.test("easing heads to the target and arrives", function()
		local from = { yaw = 1, pitch = -0.5 }
		local to = { yaw = 0, pitch = 0 }
		local half = SeatLook.ease(from, to, 0.05, 10)
		T.ok(half.yaw < 1 and half.yaw > 0, "partway")
		local look = from
		for _ = 1, 120 do
			look = SeatLook.ease(look, to, 1 / 60, 10)
		end
		T.ok(math.abs(look.yaw) < 1e-3 and math.abs(look.pitch) < 1e-3, "arrives")
	end)

	T.test("base angles from a look direction", function()
		local yaw, pitch = SeatLook.base(0, 0, -1)
		near(yaw, 0, "facing -z is yaw 0")
		near(pitch, 0, "level")
		yaw, pitch = SeatLook.base(-1, 0, 0)
		near(yaw, math.pi / 2, "facing -x is a quarter turn left")
		local s = math.sqrt(0.5)
		_, pitch = SeatLook.base(0, -s, -s)
		near(pitch, math.rad(-45), "looking 45 degrees down")
	end)

	T.test("taps versus drags", function()
		T.ok(SeatLook.isTap(3, 0.2), "a short still touch is a tap")
		T.ok(not SeatLook.isTap(40, 0.2), "a swipe looks around")
		T.ok(not SeatLook.isTap(0, 2), "a long press isn't a tap")
	end)

	T.test("arrow keys step across a grid on screen", function()
		-- A 3x3 grid, 100 px apart, slightly in perspective (top row narrower).
		local spots = {}
		for row = 0, 2 do
			for col = -1, 1 do
				local squeeze = 0.8 + row * 0.1
				table.insert(spots, { x = 500 + col * 100 * squeeze, y = 200 + row * 100 })
			end
		end
		local center = { x = 500, y = 300 }
		local first = SeatLook.step(spots, nil, 1, 0, center)
		T.eq(first, 5, "first press picks what's nearest the middle")
		T.eq(SeatLook.step(spots, 5, 1, 0, center), 6, "right")
		T.eq(SeatLook.step(spots, 5, -1, 0, center), 4, "left")
		T.eq(SeatLook.step(spots, 5, 0, -1, center), 2, "up")
		T.eq(SeatLook.step(spots, 5, 0, 1, center), 8, "down")
		T.eq(SeatLook.step(spots, 6, 1, 0, center), 6, "nothing further right: stays")
		T.eq(SeatLook.step({}, nil, 1, 0, center), nil, "nothing to pick")
	end)

	T.test("cards cycle in order and wrap", function()
		T.eq(SeatLook.cycle(5, nil, 1), 3, "starts in the middle")
		T.eq(SeatLook.cycle(5, 3, 1), 4, "next")
		T.eq(SeatLook.cycle(5, 5, 1), 1, "wraps right")
		T.eq(SeatLook.cycle(5, 1, -1), 5, "wraps left")
		T.eq(SeatLook.cycle(0, nil, 1), nil, "empty hand")
		T.eq(SeatLook.cycle(4, 9, 1), 2, "stale pick restarts in the middle")
	end)
end
