local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local L = require(ReplicatedStorage.Shared.LobbyLayout)

return function(T)
	local R = L.TABLE_RADIUS

	T.test("there's a table spot for every default table, in its zone", function()
		T.eq(#L.tables, #Config.DefaultTables)
		for i, spec in Config.DefaultTables do
			local spot = L.tables[i]
			T.eq(spot.zone, spec.zone, `table {i}`)
			local zone = L.zone(spot.zone)
			T.ok(zone ~= nil, `zone {spot.zone} has a rug`)
			T.ok(L.inside(spot.x, spot.z, zone.area), `table {i} sits on its zone's rug`)
		end
	end)

	T.test("tables fit in the room with an aisle between them", function()
		local room = L.room
		for i, a in L.tables do
			T.ok(a.x - R >= room.minX and a.x + R <= room.maxX and a.z - R >= room.minZ and a.z + R <= room.maxZ, `table {i} inside the walls`)
			for j = i + 1, #L.tables do
				local b = L.tables[j]
				local dist = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
				T.ok(dist >= 2 * R + L.AISLE, `tables {i} and {j} are {dist} apart`)
			end
		end
	end)

	T.test("a table is all on the stage or all off it", function()
		for i, t in L.tables do
			local onStage = L.inside(t.x, t.z, L.stage)
			local box = { minX = t.x - R, maxX = t.x + R, minZ = t.z - R, maxZ = t.z + R }
			if onStage then
				T.ok(box.minX >= L.stage.minX and box.maxX <= L.stage.maxX and box.minZ >= L.stage.minZ and box.maxZ <= L.stage.maxZ, `table {i} hangs off the stage`)
			else
				T.ok(not L.overlaps(box, L.stage) and not L.overlaps(box, L.stageStep), `table {i} runs into the stage`)
			end
			local _, y = L.tableSpot(i)
			T.eq(y, if onStage then L.STAGE_Y else L.FLOOR_Y)
		end
		T.ok(L.tableSpot(#L.tables + 1) == nil)
	end)

	T.test("props stay clear of tables, the spawn and each other", function()
		for i, prop in L.props do
			local r = L.propRect(prop)
			local room = L.room
			T.ok(r.minX >= room.minX and r.maxX <= room.maxX and r.minZ >= room.minZ and r.maxZ <= room.maxZ, `{prop.kind} {i} inside the walls`)
			for j, t in L.tables do
				local gap = L.distanceToRect(t.x, t.z, r) - R
				T.ok(gap >= 3, `{prop.kind} {i} is {gap} from table {j}`)
			end
			T.ok(L.distanceToRect(L.spawn.x, L.spawn.z, r) >= 6, `{prop.kind} {i} crowds the spawn`)
			for j = i + 1, #L.props do
				T.ok(not L.overlaps(r, L.propRect(L.props[j])), `{prop.kind} {i} overlaps {L.props[j].kind} {j}`)
			end
			-- Nothing straddles the stage edge (it would float or sink).
			local onStage = L.overlaps(r, L.stage)
			local inStage = r.minX >= L.stage.minX and r.maxX <= L.stage.maxX and r.minZ >= L.stage.minZ and r.maxZ <= L.stage.maxZ
			T.ok(not onStage or inStage, `{prop.kind} {i} straddles the stage edge`)
			T.ok(not L.overlaps(r, L.stageStep), `{prop.kind} {i} blocks the stage step`)
		end
	end)

	T.test("the walk from the spawn to the first Quick Play table is clear", function()
		local first = L.tables[1]
		for step = 0, 20 do
			local f = step / 20
			local x = L.spawn.x + (first.x - L.spawn.x) * f
			local z = L.spawn.z + (first.z - L.spawn.z) * f
			for i, prop in L.props do
				T.ok(L.distanceToRect(x, z, L.propRect(prop)) >= 1.5, `{prop.kind} {i} is in the way`)
			end
		end
	end)

	T.test("zone rugs don't overlap", function()
		for i, a in L.zones do
			for j = i + 1, #L.zones do
				T.ok(not L.overlaps(a.area, L.zones[j].area), `{a.id} and {L.zones[j].id}`)
			end
		end
	end)

	T.test("windows fit between the corners and miss the door", function()
		local w = L.windows
		for _, z in w.side do
			T.ok(z - w.width / 2 > L.room.minZ and z + w.width / 2 < L.room.maxZ)
		end
		for _, x in w.front do
			T.ok(math.abs(x - L.door.x) > (w.width + L.door.width) / 2)
		end
		T.ok(w.top < L.CEILING_Y and w.bottom > 0)
	end)
end
