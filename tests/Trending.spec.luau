local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trending = require(ReplicatedStorage.Shared.Trending)

return function(T)
	local NOW = Trending.EPOCH + 10 * 86400

	T.test("only Dressing Room items count, and kinds weigh differently", function()
		local pending = {}
		T.ok(Trending.add(pending, 100, 8, "tryOn", NOW, "Cap"), "hat counts")
		T.ok(not Trending.add(pending, 101, 70, "tryOn", NOW), "shoes are try-only")
		T.ok(not Trending.add(pending, 102, 999, "tryOn", NOW), "unknown type")
		T.ok(not Trending.add(pending, -5, 8, "tryOn", NOW), "bad id")
		T.ok(not Trending.add(pending, 103, 8, "hack", NOW), "unknown kind")
		Trending.add(pending, 104, 41, "buy", NOW)
		T.ok(pending[104].score > pending[100].score, "a purchase counts more than a try-on")
		T.eq(pending[100].name, "Cap")
	end)

	T.test("newer wears count more: one half-life later a wear is worth double", function()
		local w0 = Trending.weight(NOW)
		local w1 = Trending.weight(NOW + Trending.HALF_LIFE_DAYS * 86400)
		T.ok(math.abs(w1 / w0 - 2) < 1e-9, "doubles")
		-- Two wears a half-life ago tie one today, so one today plus an hour wins.
		local old, new = {}, {}
		Trending.add(old, 1, 8, "tryOn", NOW)
		Trending.add(old, 1, 8, "avatar", NOW)
		Trending.add(new, 2, 8, "tryOn", NOW + Trending.HALF_LIFE_DAYS * 86400 + 3600)
		local ranked = Trending.rank({}, old, new, 10)
		T.eq(ranked[1].id, 2)
	end)

	T.test("takeBatch sends the biggest first and leaves the rest", function()
		local pending = {}
		for id = 1, 5 do
			for _ = 1, id do
				Trending.add(pending, id, 8, "tryOn", NOW)
			end
		end
		local batch = Trending.takeBatch(pending, 2)
		T.eq(#batch, 2)
		T.eq(batch[1].id, 5)
		T.eq(batch[2].id, 4)
		T.ok(pending[5] == nil and pending[3] ~= nil, "taken out, rest kept")
	end)

	T.test("combine adds to the map's score and keeps the old name", function()
		local value, score = Trending.combine({ t = 8, n = "Old name" }, 10, { id = 7, t = 8, score = 2.5 })
		T.eq(score, 12.5)
		T.eq(value.n, "Old name")
		local fresh, s2 = Trending.combine(nil, nil, { id = 7, t = 8, score = 1, name = "New" })
		T.eq(s2, 1)
		T.eq(fresh.n, "New")
	end)

	T.test("rank sums the global list with this server's counts", function()
		local global = {
			Trending.decode({ key = "10", value = { t = 8, n = "A" }, sortKey = 5 }),
			Trending.decode({ key = "11", value = { t = 41 }, sortKey = 4 }),
		}
		T.eq(#global, 2)
		T.eq(Trending.decode({ key = "x", value = { t = 8 }, sortKey = 1 }), nil)
		T.eq(Trending.decode({ key = "12", value = { t = 70 }, sortKey = 1 }), nil)
		local pending = { [11] = { id = 11, t = 41, score = 2 } }
		local sent = { [12] = { id = 12, t = 8, score = 0.5 } }
		local ranked = Trending.rank(global :: any, pending, sent, 10)
		T.eq(ranked[1].id, 11) -- 4 + 2 beats 5
		T.eq(ranked[2].id, 10)
		T.eq(ranked[3].id, 12)
		T.eq(#Trending.rank(global :: any, pending, sent, 2), 2)
		T.eq(global[1].score, 5) -- ranking doesn't change the stored list
	end)

	T.test("the client keeps only well-formed, unique items", function()
		local out = Trending.fromServer({
			items = {
				{ id = 1, t = 8, name = "Hat" },
				{ id = 1, t = 8 },
				{ id = "2", t = 8 },
				{ id = 3, t = 70 },
				"junk",
				{ id = 4, t = 65, name = 5 },
			},
		})
		T.eq(#out, 2)
		T.eq(out[1].name, "Hat")
		T.eq(out[2].id, 4)
		T.eq(out[2].name, nil)
		T.eq(#Trending.fromServer(nil), 0)
		local client = Trending.toClient({ { id = 9, t = 8, score = 99, name = "N" } })
		T.eq(client[1].score, nil)
		T.eq(client[1].id, 9)
	end)

	T.test("catalog details become cards; off-sale items show no price", function()
		local card = Trending.fromDetails({ Id = 5, Name = "Wings", Price = 50, CreatorName = "Maker" })
		T.eq(card and card.Price, 50)
		T.eq(card and card.creator, "Maker")
		local off = Trending.fromDetails({ Id = 6, Name = "Old", Price = 10, IsOffSale = true })
		T.eq(off and off.Price, nil)
		T.eq(Trending.fromDetails({ Name = "No id" }), nil)
	end)
end
