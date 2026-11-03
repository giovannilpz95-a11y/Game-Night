local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TableLayout = require(ReplicatedStorage.Shared.TableLayout)

return function(T)
	local function list(t)
		return table.concat(t, ",")
	end

	T.test("two players at a 4-seat table face each other", function()
		T.eq(list(TableLayout.seatMap(4, 2)), "1,3")
		T.eq(list(TableLayout.seatMap(8, 2)), "1,5")
		T.eq(list(TableLayout.seatMap(4, 4)), "1,2,3,4")
		T.eq(list(TableLayout.seatMap(8, 3)), "1,3,6")
	end)

	T.test("seat map never repeats a seat", function()
		for total = 2, 8 do
			for used = 1, total do
				local seen = {}
				for _, s in TableLayout.seatMap(total, used) do
					T.ok(not seen[s] and s >= 1 and s <= total, `{used} of {total}`)
					seen[s] = true
				end
			end
		end
	end)

	T.test("chess: white's rank 1 is nearest seat 1, files run left to right", function()
		local ax, az = TableLayout.chessCell(0, 1) -- a1
		local hx, hz = TableLayout.chessCell(63, 1) -- h8
		T.eq(ax, -3.5)
		T.eq(az, 3.5)
		T.eq(hx, 3.5)
		T.eq(hz, -3.5)
	end)

	T.test("checkers: seat 1's home row 8 is nearest seat 1", function()
		local _, near = TableLayout.checkersCell(8, 1, 1)
		local _, far = TableLayout.checkersCell(1, 1, 1)
		T.ok(near > 0 and far < 0)
		-- Both games agree on which corner is a1, so the boards look the same.
		local cx, cz = TableLayout.checkersCell(8, 1, 1)
		local ax, az = TableLayout.chessCell(0, 1)
		T.eq(cx, ax)
		T.eq(cz, az)
	end)

	T.test("four in a row: middle column is centered, row 1 at the bottom", function()
		local x, y = TableLayout.fourCell(4, 1, 7, 1)
		T.eq(x, 0)
		T.eq(y, 0.5)
	end)

	T.test("picks the zone's table, then the smallest that fits", function()
		local tables = {
			{ id = "Cards-1", zone = "Cards", seats = 8 },
			{ id = "Quick-1", zone = "Quick", seats = 4 },
			{ id = "Strategy-1", zone = "Strategy", seats = 4 },
		}
		T.eq(TableLayout.pickTable(tables, "Strategy", 2).id, "Strategy-1")
		T.eq(TableLayout.pickTable(tables, "Cards", 6).id, "Cards-1")
		tables[3].busy = true
		T.eq(TableLayout.pickTable(tables, "Strategy", 2).id, "Quick-1", "falls back to another zone")
		T.eq(TableLayout.pickTable(tables, "Party", 6).id, "Cards-1", "only the big table fits")
		T.eq(TableLayout.pickTable(tables, "Strategy", 2, "Cards-1").id, "Cards-1", "keeps the party's last table")
		tables[1].busy = true
		tables[2].busy = true
		T.eq(TableLayout.pickTable(tables, "Quick", 2), nil, "everything busy: 2D overflow")
	end)
end
