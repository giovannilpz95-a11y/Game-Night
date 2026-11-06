local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SeatView = require(ReplicatedStorage.Shared.SeatView)

return function(T)
	local ASPECT = 16 / 9

	-- The 8 corners of a box centered on the table's middle.
	local function box(halfX: number, halfZ: number, low: number, high: number)
		local out = {}
		for _, x in { -halfX, halfX } do
			for _, z in { -halfZ, halfZ } do
				for _, y in { low, high } do
					table.insert(out, { x = x, y = y, z = z })
				end
			end
		end
		return out
	end

	-- Heads of the others around a round table of `reach`, you at the bottom (-z).
	local function heads(count: number, reach: number)
		local out = {}
		for i = 1, count - 1 do
			local a = i / count * math.pi * 2
			table.insert(out, { x = math.sin(a) * reach, y = 2.6, z = -math.cos(a) * reach })
		end
		return out
	end

	local function inside(view, points, free, msg)
		for _, p in points do
			local x, y, depth = SeatView.project(view, p, ASPECT)
			T.ok(depth > 0, `{msg}: in front of the camera`)
			T.ok(x >= free.left - 1e-6 and x <= free.right + 1e-6, `{msg}: x {x} in {free.left}..{free.right}`)
			T.ok(y >= free.bottom - 1e-6 and y <= free.top + 1e-6, `{msg}: y {y} in {free.bottom}..{free.top}`)
		end
	end

	local FULL = { left = -1, right = 1, bottom = -1, top = 0.88 }

	T.test("a chess board and the player across both fit from your seat", function()
		local board = box(3.8, 3, 0, 1.3)
		local others = heads(2, 6)
		local view = SeatView.solve(board, others, 7.2, 7, ASPECT, FULL)
		T.eq(view.fits, "all")
		inside(view, board, FULL, "board")
		inside(view, others, FULL, "heads")
		T.ok(view.pitch > math.rad(15) and view.pitch < math.rad(75), `looks down {math.deg(view.pitch)}`)
		T.ok(math.abs(view.side) < 1e-6, "a symmetric board sits dead center")
	end)

	-- Studio (Chess): the seat list on the left made the old camera turn a little to the
	-- side. With room to spare it stays dead center and straight.
	T.test("chess with the seat list showing stays centered", function()
		local free = { left = -1 + 2 * 0.18, right = 1, bottom = -1, top = 0.88 }
		local view = SeatView.solve(box(3.8, 3, 0, 1.3), heads(2, 6), 7.2, 7, ASPECT, free)
		T.ok(view.fits ~= "none", `fits {view.fits}`)
		T.ok(math.abs(view.side) < 1e-6, `side {view.side}`)
	end)

	T.test("the eye stays at its seat when everything already fits", function()
		local view = SeatView.solve(box(1.5, 1.5, 0, 0.3), heads(2, 6), 7.2, 7, ASPECT, FULL)
		T.eq(view.back, 7.2)
		T.eq(view.height, 7)
	end)

	T.test("a right-side panel slides the view so the table sits in the free left part", function()
		local free = { left = -1, right = 0.16, bottom = -1, top = 0.88 }
		local board = box(4, 4, 0, 0.8)
		local others = heads(4, 6.5)
		local view = SeatView.solve(board, others, 7.8, 7.25, ASPECT, free)
		T.ok(view.fits ~= "none", `fits {view.fits}`)
		T.ok(view.side > 0, "slid right, so the table shows left of center")
		inside(view, board, free, "board")
		if view.fits == "all" then
			inside(view, others, free, "heads")
		end
	end)

	T.test("a big board moves the eye up and back rather than cut it off", function()
		local board = box(7, 7, 0, 0.6)
		local view = SeatView.solve(board, heads(4, 9), 10.8, 8.5, ASPECT, FULL)
		T.ok(view.fits ~= "none", `fits {view.fits}`)
		inside(view, board, FULL, "board")
	end)

	-- Studio check of the first version: at a 4-seat table Property Party's board (8 studs,
	-- nearly the whole tabletop) was cut off on the left, under the seat list.
	T.test("Property Party at a 4-seat table: whole board clear of the side panel and seat list", function()
		local reach = 6.1
		local free = { left = -1 + 2 * 0.18, right = 1 - 2 * 0.4, bottom = -1, top = 0.88 }
		local board = box(4.5, 4.5, 0, 0.8)
		local others = heads(4, reach)
		local view = SeatView.solve(board, others, reach * 1.2, 4 + reach * 0.5, ASPECT, free)
		T.eq(view.fits, "all")
		inside(view, board, free, "board")
		inside(view, others, free, "heads")
		T.ok(view.back <= reach * 1.2 * 2 + 1e-6, `back {view.back}`)
	end)

	T.test("a bottom strip (Word Tiles' rack) keeps the board above it", function()
		local free = { left = -1, right = 1, bottom = -0.7, top = 0.88 }
		local board = box(4, 4, 0, 0.4)
		local view = SeatView.solve(board, heads(4, 6.5), 7.8, 7.25, ASPECT, free)
		T.ok(view.fits ~= "none", `fits {view.fits}`)
		inside(view, board, free, "board")
	end)

	T.test("an upright frame (Four in a Row) fits, top to bottom", function()
		local board = box(3.2, 0.5, 0, 5)
		local view = SeatView.solve(board, heads(2, 6), 7.2, 7, ASPECT, FULL)
		T.ok(view.fits ~= "none", `fits {view.fits}`)
		inside(view, board, FULL, "frame")
	end)

	T.test("a phone-shaped free area still gives a usable answer", function()
		local free = { left = -1, right = -0.4, bottom = -1, top = 0.8 }
		local view = SeatView.solve(box(4, 4, 0, 0.6), heads(4, 6.5), 7.8, 7.25, 19.5 / 9, free)
		T.ok(view.back == view.back and view.pitch == view.pitch and view.side == view.side, "no NaN")
		T.ok(view.pitch > 0 and view.pitch < math.rad(89), "looks down")
	end)

	T.test("a board far behind the seat still gets a downward view", function()
		local far = box(3, 3, 0, 1)
		for _, p in far do
			p.z -= 40
		end
		local view = SeatView.solve(far, heads(2, 6), 6, 7, ASPECT, FULL)
		T.ok(view.pitch > 0.2, `looks down ({view.pitch})`)
	end)
end
