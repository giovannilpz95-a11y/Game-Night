local ReplicatedStorage = game:GetService("ReplicatedStorage")
local R = require(ReplicatedStorage.Shared.Recommendations)

return function(T)
	local allowed = { [8] = true, [41] = true, [65] = true }

	T.test("seeds: newest try-on first, one of each kind before repeats", function()
		local tried = { { id = 1, t = 8 }, { id = 2, t = 41 }, { id = 3, t = 8 } }
		local own = { { id = 10, t = 65 }, { id = 2, t = 41 }, { id = 11, t = 999 } }
		local s = R.seeds(tried, own, allowed)
		local ids = {}
		for i, seed in s do
			ids[i] = seed.id
		end
		T.eq(table.concat(ids, ","), "3,2,10,1")
	end)

	T.test("seeds respect the limit and skip bad ids", function()
		local s = R.seeds({ { id = 0, t = 8 }, { id = 5, t = 8 }, { id = 6, t = 41 } }, {}, allowed, 1)
		T.eq(#s, 1)
		T.eq(s[1].id, 6)
	end)

	T.test("merge: items several seeds agree on rank first, worn items are left out", function()
		local a = { { Id = 100 }, { Id = 101 }, { Id = 102 } }
		local b = { { Id = 103 }, { Id = 102 }, { Id = 104 } }
		local out = R.merge({ a, b }, { [100] = true }, {}, 10)
		T.eq(out[1].Id, 102)
		local seen = {}
		for _, p in out do
			T.ok(not seen[p.Id], "no duplicates")
			seen[p.Id] = true
		end
		T.ok(not seen[100], "worn item left out")
		T.eq(#out, 4)
	end)

	T.test("merge: a favorite creator breaks ties and limit caps", function()
		local a = { { Id = 1, creator = "x" }, { Id = 2, creator = "y" } }
		local b = { { Id = 3, creator = "y" }, { Id = 4, creator = "x" } }
		local out = R.merge({ a, b }, {}, { "y" }, 3)
		T.eq(#out, 3)
		T.eq(out[1].Id, 3) -- top of a list and the favorite creator
	end)

	T.test("topCreators counts and keeps first-seen order on ties", function()
		local names = R.topCreators({ { creator = "a" }, { creator = "b" }, { creator = "b" }, { creator = "" }, { creator = "c" }, { creator = "a" } }, 2)
		T.eq(table.concat(names, ","), "a,b")
	end)

	T.test("fromRoblox reads the API shape and drops resale limiteds", function()
		local p = R.fromRoblox({ Item = { AssetId = 9, Name = "Cap", Price = 50 }, Creator = { Name = "Maker" }, Product = { PriceInRobux = 45, IsForSale = true } })
		T.ok(p ~= nil, "read")
		T.eq(p.Id, 9)
		T.eq(p.Price, 45)
		T.eq(p.creator, "Maker")
		T.eq(R.fromRoblox({ Item = { AssetId = 9 }, Product = { IsLimitedUnique = true } }), nil)
		T.eq(R.fromRoblox({ Item = {} }), nil)
		local off = R.fromRoblox({ Item = { AssetId = 3, Name = "Old" }, Product = { IsForSale = false } })
		T.eq(off.Price, nil)
	end)
end
