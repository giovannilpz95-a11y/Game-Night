local ServerScriptService = game:GetService("ServerScriptService")
local VoicePool = require(ServerScriptService.Server.Core.VoicePool)

return function(T)
	local NOW = 1000

	local function entry(players, updated, holds)
		return { players = players, updated = updated or NOW, holds = holds or {} }
	end

	T.test("picks the fullest server that still fits the party", function()
		local entries = {
			{ key = "a", value = entry(4) },
			{ key = "b", value = entry(15) },
			{ key = "c", value = entry(19) },
		}
		T.eq(VoicePool.choose(entries, 3, 20, NOW, 45), "b", "c has only 1 seat left")
		T.eq(VoicePool.choose(entries, 1, 20, NOW, 45), "c")
	end)

	T.test("returns nil when every server is full or stale", function()
		local entries = {
			{ key = "full", value = entry(20) },
			{ key = "dead", value = entry(2, NOW - 100) },
		}
		T.eq(VoicePool.choose(entries, 2, 20, NOW, 45), nil)
		T.eq(VoicePool.choose({}, 1, 20, NOW, 45), nil)
	end)

	T.test("held seats count until they expire", function()
		local value = entry(10, NOW, { t1 = { count = 8, expires = NOW + 30 } })
		T.eq(VoicePool.seatsUsed(value, NOW), 18)
		T.eq(VoicePool.seatsUsed(value, NOW + 31), 10, "expired hold no longer counts")
		T.eq(VoicePool.choose({ { key = "x", value = value } }, 4, 20, NOW, 45), nil)
	end)

	T.test("addHold refuses when the server filled up meanwhile", function()
		local value = entry(17)
		T.eq(VoicePool.addHold(value, "t", 4, 20, NOW, 60), nil)
		local ok = VoicePool.addHold(value, "t", 3, 20, NOW, 60)
		T.ok(ok ~= nil)
		T.eq(VoicePool.seatsUsed(ok, NOW), 20)
	end)

	T.test("addHold on a missing entry only works for a brand-new server", function()
		T.eq(VoicePool.addHold(nil, "t", 2, 20, NOW, 60), nil, "shut-down server")
		local fresh = VoicePool.addHold(nil, "t", 2, 20, NOW, 60, true)
		T.ok(fresh ~= nil)
		T.eq(fresh.updated, NOW, "new server counts as live")
		T.eq(VoicePool.choose({ { key = "n", value = fresh } }, 2, 20, NOW + 5, 45), "n")
	end)

	T.test("heartbeat shrinks holds as members arrive and drops expired ones", function()
		local value = entry(0, NOW - 10, {
			party = { count = 4, expires = NOW + 50 },
			old = { count = 3, expires = NOW - 1 },
			done = { count = 2, expires = NOW + 50 },
		})
		local beat = VoicePool.heartbeat(value, 5, { party = 3, done = 2 }, NOW)
		T.eq(beat.players, 5)
		T.eq(beat.updated, NOW)
		T.eq(beat.holds.party.count, 1)
		T.eq(beat.holds.old, nil)
		T.eq(beat.holds.done, nil)
		T.eq(VoicePool.seatsUsed(beat, NOW), 6)
	end)

	T.test("releaseHold frees a failed party's seats", function()
		local value = entry(2, NOW, { t = { count = 5, expires = NOW + 60 } })
		T.eq(VoicePool.seatsUsed(VoicePool.releaseHold(value, "t"), NOW), 2)
		T.eq(VoicePool.releaseHold(nil, "t"), nil)
	end)

	T.test("junk values never error", function()
		T.eq(VoicePool.seatsUsed("junk", NOW), 0)
		T.eq(VoicePool.choose({ { key = "j", value = 5 } }, 1, 20, NOW, 45), nil, "updated=0 is stale")
	end)
end
