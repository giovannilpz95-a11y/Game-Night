local ReplicatedStorage = game:GetService("ReplicatedStorage")
local P = require(ReplicatedStorage.Shared.PerfPolicy)

local function info(sx: number, sy: number, sz: number, extra: { [string]: any }?): any
	local t: { [string]: any } = { className = "Part", sx = sx, sy = sy, sz = sz, transparency = 0, canCollide = true }
	for k, v in extra or {} do
		t[k] = v
	end
	return t
end

return function(T)
	T.test("big decor keeps its shadow and stays solid", function()
		local f = P.decor(info(6, 3, 2))
		T.eq(f.anchored, true)
		T.eq(f.canTouch, false)
		T.eq(f.castShadow, nil, "shadow left as built")
		T.eq(f.canCollide, nil, "collision left as built")
		T.eq(f.canQuery, nil)
		T.eq(f.detail, nil)
	end)

	T.test("small decor loses shadow, collision and queries", function()
		local f = P.decor(info(0.8, 0.5, 0.3))
		T.eq(f.castShadow, false)
		T.eq(f.canCollide, false)
		T.eq(f.canQuery, false)
		T.eq(f.detail, nil, "0.8 studs is shown in low detail")
	end)

	T.test("tiny decor is hidden in low detail, unless it's a bulb or has text", function()
		T.eq(P.decor(info(0.3, 0.3, 0.3)).detail, true)
		T.eq(P.decor(info(0.3, 0.3, 0.3, { material = "Neon" })).detail, nil)
		T.eq(P.decor(info(0.3, 0.3, 0.3, { hasSurface = true })).detail, nil)
		T.eq(P.decor(info(0.3, 0.3, 0.3, { transparency = 1 })).detail, nil)
	end)

	T.test("parts with prompts stay solid and queryable", function()
		local f = P.decor(info(0.5, 0.5, 0.5, { interactive = true }))
		T.eq(f.castShadow, false)
		T.eq(f.canCollide, nil)
		T.eq(f.canQuery, nil)
		T.eq(f.detail, nil)
	end)

	T.test("invisible walls keep colliding; invisible markers stop being queried", function()
		local wall = P.decor(info(10, 12, 1, { transparency = 1, canCollide = true }))
		T.eq(wall.castShadow, false)
		T.eq(wall.canCollide, nil)
		T.eq(wall.canQuery, nil)
		local marker = P.decor(info(4, 0.2, 4, { transparency = 1, canCollide = false }))
		T.eq(marker.canQuery, false)
	end)

	T.test("seats and spawns are left alone", function()
		for _, class in { "Seat", "VehicleSeat", "SpawnLocation" } do
			local f = P.decor(info(0.5, 0.5, 0.5, { className = class }))
			T.eq(next(f), nil, class)
		end
	end)

	T.test("graphics slider 1-3 is low, 4+ normal, Automatic undecided", function()
		T.eq(P.lowFromSetting(0), nil)
		T.eq(P.lowFromSetting(1), true)
		T.eq(P.lowFromSetting(3), true)
		T.eq(P.lowFromSetting(4), false)
		T.eq(P.lowFromSetting(10), false)
	end)

	T.test("frame-rate monitor: needs two slow windows after warm-up", function()
		local m = P.monitor({ lowFps = 30, window = 5, strikes = 2, warmup = 10 })
		local function run(seconds: number, fps: number): boolean
			local result = false
			for _ = 1, math.floor(seconds * fps) do
				result = m:add(1 / fps)
			end
			return result
		end
		T.eq(run(10, 10), false, "slow loading doesn't count")
		T.eq(run(5, 20), false, "one slow window")
		T.eq(run(5, 60), false, "a fast window resets the count")
		T.eq(run(5, 20), false)
		T.eq(run(5.2, 20), true, "second slow window in a row")
		T.eq(run(5, 60), true, "stays low")
		m:reset()
		T.eq(m:isLow(), false)
	end)

	T.test("frame-rate monitor ignores bad deltas and fast devices", function()
		local m = P.monitor()
		T.eq(m:add(0 / 0), false)
		T.eq(m:add(-1), false)
		T.eq(m:add(math.huge), false)
		for _ = 1, 60 * 60 do
			m:add(1 / 60)
		end
		T.eq(m:isLow(), false)
	end)
end
