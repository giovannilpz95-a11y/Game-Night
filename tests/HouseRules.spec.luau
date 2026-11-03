local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HouseRules = require(ReplicatedStorage.Shared.HouseRules)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local Games = ReplicatedStorage.Shared.Games

return function(T)
	local colorClash = GameCatalog.get("ColorClash") :: any
	local trivia = GameCatalog.get("TriviaNight") :: any

	T.test("every ready game has at least one house rule", function()
		for _, entry in GameCatalog.entries do
			if entry.status == "ready" then
				T.ok(#HouseRules.list(entry) > 0, `{entry.id} has no house rules`)
			end
		end
	end)

	T.test("every rule has a valid default and unique key", function()
		for _, entry in GameCatalog.entries do
			local seen = {}
			for _, rule in HouseRules.list(entry) do
				T.ok(not seen[rule.key], `{entry.id}: duplicate rule {rule.key}`)
				seen[rule.key] = true
				T.ok(rule.choices[rule.default] ~= nil, `{entry.id}.{rule.key}: bad default`)
			end
		end
	end)

	T.test("no picks means normal rules", function()
		local values, custom = HouseRules.resolve(colorClash, nil)
		T.eq(custom, false)
		T.eq(values.stacking, true)
		T.eq(values.handSize, 7)
		T.eq(values.drawUntilPlayable, false)
		T.eq(values.turnTimer, 1)
	end)

	T.test("picks change values and count as custom", function()
		local values, custom = HouseRules.resolve(colorClash, { stacking = 1, handSize = 3 })
		T.eq(custom, true)
		T.eq(values.stacking, false)
		T.eq(values.handSize, 10)
	end)

	T.test("picking the default is not custom", function()
		local _, custom = HouseRules.resolve(colorClash, { stacking = 2, handSize = 2 })
		T.eq(custom, false)
	end)

	T.test("bad picks fall back to the defaults", function()
		local values, custom = HouseRules.resolve(colorClash, { stacking = 9, handSize = 1.5, nope = 1, turnTimer = "x" })
		T.eq(custom, false)
		T.eq(values.stacking, true)
		T.eq(values.handSize, 7)
		T.eq(values.nope, nil)
		local values2 = HouseRules.resolve(colorClash, "not a table")
		T.eq(values2.handSize, 7)
	end)

	T.test("turn timer scales a game's turn seconds; party games have none", function()
		local quick = HouseRules.resolve(colorClash, { turnTimer = 1 })
		T.eq(HouseRules.turnSeconds(colorClash, quick), 10)
		local relaxed = HouseRules.resolve(colorClash, { turnTimer = 3 })
		T.eq(HouseRules.turnSeconds(colorClash, relaxed), 40)
		T.eq(HouseRules.turnSeconds(trivia, HouseRules.resolve(trivia, nil)), nil)
		for _, rule in HouseRules.list(trivia) do
			T.ok(rule.key ~= "turnTimer", "phase-clock games don't get a turn timer")
		end
	end)

	T.test("describe lists only the changed rules", function()
		local values = HouseRules.resolve(colorClash, { stacking = 1 })
		local lines = HouseRules.describe(colorClash, values)
		T.eq(#lines, 1)
		T.eq(lines[1], "Stack draw cards: Off")
		T.eq(#HouseRules.describe(colorClash, HouseRules.resolve(colorClash, nil)), 0)
	end)

	T.test("every game starts with each choice of each of its rules", function()
		for _, entry in GameCatalog.entries do
			if entry.status == "ready" and entry.module then
				local rules = require(Games[entry.module])
				for _, rule in HouseRules.list(entry) do
					for index in rule.choices do
						local values = HouseRules.resolve(entry, { [rule.key] = index })
						local options = { botLevel = "easy", bots = {}, rules = values }
						local state = rules.new(rules.minSeats, options, T.Random.new(index))
						T.ok(state ~= nil, `{entry.id} {rule.key}={index}`)
					end
				end
			end
		end
	end)
end
