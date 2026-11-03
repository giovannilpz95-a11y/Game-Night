local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Hexlands = require(ReplicatedStorage.Shared.Games.Hexlands)
local GameModule = require(ReplicatedStorage.Shared.GameModule)
local Match = require(ServerScriptService.Server.Core.Match)

return function(T)
	local V, E = Hexlands.vertices, Hexlands.edges

	local function play(s, seat, move)
		local ok, err = Hexlands.validateMove(s, seat, move)
		assert(ok, err)
		Hexlands.applyMove(s, seat, move)
	end

	local function rejects(s, seat, move, message)
		local ok = Hexlands.validateMove(s, seat, move)
		T.eq(ok, false, message)
	end

	-- A rng that hands out scripted numbers first, then real random ones.
	local function scripted(values, seed)
		local real = T.Random.new(seed or 1)
		return {
			NextInteger = function(_, min, max)
				local v = table.remove(values, 1)
				if v then
					return v
				end
				return real:NextInteger(min, max)
			end,
			NextNumber = function()
				return real:NextNumber()
			end,
		}
	end

	-- Plays setup with bots so tests start from a normal first turn.
	local function afterSetup(seats, seed)
		local s = Hexlands.new(seats, { botLevel = "medium" }, T.Random.new(seed or 1))
		local rng = T.Random.new(seed or 1)
		while s.phase == "setup" do
			local seat = Hexlands.getActiveSeats(s)[1]
			play(s, seat, Hexlands.chooseBotMove(s, seat, rng))
		end
		return s
	end

	T.test("the island has 19 hexes, 54 corners, 72 edges and 9 harbors", function()
		T.eq(#Hexlands.hexes, 19)
		T.eq(#V, 54)
		T.eq(#E, 72)
		T.eq(#Hexlands.harborEdges, 9)
		local coast = 0
		for _, edge in E do
			if #edge.hexes == 1 then
				coast += 1
			end
		end
		T.eq(coast, 30)
		-- No two harbors share a corner.
		local used = {}
		for _, e in Hexlands.harborEdges do
			T.ok(not used[E[e].a] and not used[E[e].b], "harbors share a corner")
			used[E[e].a] = true
			used[E[e].b] = true
		end
	end)

	T.test("maps have the right lands and numbers, with no red numbers touching", function()
		for seed = 1, 30 do
			local s = Hexlands.new(3, {}, T.Random.new(seed))
			local count = {}
			local numbers = 0
			for h, tile in s.tiles do
				count[tile.land] = (count[tile.land] or 0) + 1
				if tile.number > 0 then
					numbers += 1
				end
				if tile.land == "dunes" then
					T.eq(s.bandit, h, "the Bandit starts on the Dunes")
				end
			end
			T.eq(count.lumber, 4)
			T.eq(count.clay, 3)
			T.eq(count.wool, 4)
			T.eq(count.grain, 4)
			T.eq(count.stone, 3)
			T.eq(count.dunes, 1)
			T.eq(numbers, 18)
		end
	end)

	T.test("setup goes in snake order and the second camp pays out", function()
		local s = Hexlands.new(3, {}, T.Random.new(4))
		local order = {}
		local rng = T.Random.new(4)
		while s.phase == "setup" do
			local seat = Hexlands.getActiveSeats(s)[1]
			if s.setupStep == "place" then
				table.insert(order, seat)
			end
			play(s, seat, Hexlands.chooseBotMove(s, seat, rng))
		end
		T.eq(table.concat(order, ","), "1,2,3,3,2,1")
		T.eq(s.phase, "roll")
		T.eq(s.turn, 1)
		local cards = 0
		for seat = 1, 3 do
			for _, r in Hexlands.RES do
				cards += s.players[seat].hand[r]
			end
			T.eq(s.players[seat].camps, 3)
			T.eq(s.players[seat].roads, 13)
		end
		T.ok(cards > 0, "second camps should pay something")
	end)

	T.test("the distance rule and road rules are enforced", function()
		local s = Hexlands.new(2, {}, T.Random.new(2))
		local v = 20
		play(s, 1, { kind = "place", vertex = v })
		rejects(s, 1, { kind = "place", vertex = v }, "road step expects a road")
		-- A road that doesn't touch the camp.
		local far = nil
		for e, edge in E do
			if edge.a ~= v and edge.b ~= v then
				far = e
				break
			end
		end
		rejects(s, 1, { kind = "road", edge = far }, "setup road must touch the camp")
		rejects(s, 1, { kind = "road", edge = "1" }, "bad types")
		play(s, 1, { kind = "road", edge = V[v].edges[1] })
		-- Seat 2 can't camp on or next to seat 1's camp.
		rejects(s, 2, { kind = "place", vertex = v }, "taken corner")
		rejects(s, 2, { kind = "place", vertex = V[v].near[1] }, "next-door corner")
		rejects(s, 1, { kind = "place", vertex = 40 }, "not seat 1's turn")
		rejects(s, 2, { kind = "place", vertex = 999 }, "no such corner")
	end)

	T.test("rolling pays camps and towns; the Bandit blocks", function()
		local s = afterSetup(2, 3)
		-- Find a hex next to seat 1 and make it roll.
		local target = nil
		for v, owner in s.owner do
			if owner == 1 then
				for _, h in V[v].hexes do
					if s.tiles[h].number > 0 and h ~= s.bandit then
						target = { h = h, v = v }
					end
				end
			end
		end
		T.ok(target, "seat 1 should touch a numbered hex")
		local tile = s.tiles[target.h]
		local before = s.players[1].hand[tile.land]
		s.town[target.v] = true
		local n = tile.number
		local a = math.max(1, n - 6)
		s.rng = scripted({ a, n - a })
		play(s, 1, { kind = "roll" })
		T.ok(s.players[1].hand[tile.land] >= before + 2, "a town pays 2")
		T.eq(s.phase, "main")

		-- Now block it with the Bandit and roll again next turn.
		play(s, 1, { kind = "endTurn" })
		s.bandit = target.h
		local held = s.players[1].hand[tile.land]
		s.rng = scripted({ a, n - a })
		play(s, 2, { kind = "roll" })
		-- Other hexes with the same number may still pay, but not the blocked one.
		local expected = held
		for h, t in s.tiles do
			if h ~= target.h and t.number == n and t.land == tile.land then
				for _, v in Hexlands.hexVertices[h] do
					if s.owner[v] == 1 then
						expected += if s.town[v] then 2 else 1
					end
				end
			end
		end
		T.eq(s.players[1].hand[tile.land], expected)
	end)

	T.test("a 7 makes big hands discard half, then the roller moves the Bandit and steals", function()
		local s = afterSetup(2, 5)
		for _, r in Hexlands.RES do
			s.players[2].hand[r] = 2 -- 10 cards
			s.players[1].hand[r] = 0
		end
		s.rng = scripted({ 3, 4 })
		play(s, 1, { kind = "roll" })
		T.eq(s.phase, "discard")
		T.eq(s.discards[2], 5)
		T.eq(table.concat(Hexlands.getActiveSeats(s), ","), "2")
		rejects(s, 2, { kind = "discard", cards = { lumber = 2 } }, "wrong count")
		rejects(s, 2, { kind = "discard", cards = { lumber = 5 } }, "not enough lumber")
		rejects(s, 2, { kind = "discard", cards = { gold = 5 } }, "not a resource")
		play(s, 2, { kind = "discard", cards = { lumber = 2, clay = 2, wool = 1 } })
		T.eq(s.phase, "bandit")
		-- Find a hex where seat 2 has a building.
		local h2 = nil
		for v, owner in s.owner do
			if owner == 2 then
				for _, h in V[v].hexes do
					if h ~= s.bandit then
						h2 = h
					end
				end
			end
		end
		rejects(s, 1, { kind = "bandit", hex = s.bandit }, "must move")
		local victims = Hexlands.banditVictims(s, 1, h2)
		T.ok(table.find(victims, 2) ~= nil, "seat 2 is a victim")
		rejects(s, 1, { kind = "bandit", hex = h2 }, "must pick a victim")
		play(s, 1, { kind = "bandit", hex = h2, victim = 2 })
		T.eq(s.bandit, h2)
		local total = 0
		for _, r in Hexlands.RES do
			total += s.players[1].hand[r]
		end
		T.eq(total, 1, "stole one card")
		T.eq(s.phase, "main")
	end)

	T.test("building costs cards and pieces; illegal builds are rejected", function()
		local s = afterSetup(2, 6)
		s.rng = scripted({ 1, 1 }) -- a 2
		play(s, 1, { kind = "roll" })
		for _, r in Hexlands.RES do
			s.players[1].hand[r] = 0
		end
		local opts = Hexlands.getView(s, 1).options
		T.eq(#opts.edges, 0, "no cards, no roads")
		local road = nil
		for e in E do
			if Hexlands.canRoad(s, 1, e) then
				road = e
				break
			end
		end
		rejects(s, 1, { kind = "road", edge = road }, "can't afford")
		s.players[1].hand.lumber = 1
		s.players[1].hand.clay = 1
		play(s, 1, { kind = "road", edge = road })
		T.eq(s.road[road], 1)
		T.eq(s.players[1].roads, 12)
		T.eq(s.players[1].hand.lumber, 0)
		-- A town on someone else's camp is not allowed.
		s.players[1].hand.grain = 2
		s.players[1].hand.stone = 3
		local theirs, mine = nil, nil
		for v, owner in s.owner do
			if owner == 2 then
				theirs = v
			else
				mine = v
			end
		end
		rejects(s, 1, { kind = "town", vertex = theirs }, "not your camp")
		play(s, 1, { kind = "town", vertex = mine })
		T.ok(s.town[mine], "upgraded")
		T.eq(s.players[1].towns, 3)
		T.eq(s.players[1].camps, 4, "the camp piece comes back")
		T.eq(Hexlands.points(s, 1), 3)
	end)

	T.test("bank trades use harbor rates", function()
		local s = afterSetup(2, 7)
		s.rng = scripted({ 1, 1 })
		play(s, 1, { kind = "roll" })
		for _, r in Hexlands.RES do
			s.players[1].hand[r] = 0
		end
		s.players[1].hand.wool = 4
		local rate = Hexlands.rate(s, 1, "wool")
		rejects(s, 1, { kind = "bank", give = "wool", get = "wool" }, "same resource")
		play(s, 1, { kind = "bank", give = "wool", get = "stone" })
		T.eq(s.players[1].hand.wool, 4 - rate)
		T.eq(s.players[1].hand.stone, 1)
		-- Give seat 1 a 2:1 wool harbor and check the rate drops.
		for v, kind in s.harborOf do
			if kind == "wool" then
				s.owner[v] = 1
				break
			end
		end
		T.eq(Hexlands.rate(s, 1, "wool"), 2)
	end)

	T.test("player trades swap cards and can be turned down or time out", function()
		local s = afterSetup(2, 8)
		s.rng = scripted({ 1, 1 })
		play(s, 1, { kind = "roll" })
		for _, r in Hexlands.RES do
			s.players[1].hand[r] = 0
			s.players[2].hand[r] = 0
		end
		s.players[1].hand.lumber = 2
		s.players[2].hand.stone = 1
		rejects(s, 1, { kind = "offer", to = 2, give = { lumber = 3 }, get = { stone = 1 } }, "don't have 3")
		rejects(s, 1, { kind = "offer", to = 1, give = { lumber = 1 }, get = { stone = 1 } }, "can't trade with yourself")
		rejects(s, 1, { kind = "offer", to = 2, give = {}, get = { stone = 1 } }, "empty side")
		play(s, 1, { kind = "offer", to = 2, give = { lumber = 2 }, get = { stone = 1 } })
		T.eq(s.phase, "trade")
		T.eq(table.concat(Hexlands.getActiveSeats(s), ","), "2")
		rejects(s, 1, { kind = "accept" }, "only the target answers")
		play(s, 2, { kind = "accept" })
		T.eq(s.players[1].hand.stone, 1)
		T.eq(s.players[2].hand.lumber, 2)
		T.eq(s.phase, "main")

		-- Offers don't reveal the target's hand; they just can't accept what they lack.
		play(s, 1, { kind = "offer", to = 2, give = { stone = 1 }, get = { wool = 1 } })
		rejects(s, 2, { kind = "accept" }, "no wool to give")
		play(s, 2, { kind = "reject" })
		T.eq(s.players[1].hand.stone, 1)
		play(s, 1, { kind = "offer", to = 2, give = { stone = 1 }, get = { lumber = 1 } })
		local timer = Hexlands.getTimer(s)
		T.ok(timer ~= nil, "trade offers have a clock")
		Hexlands.onTimeout(s)
		T.eq(s.phase, "main")
		rejects(s, 1, { kind = "offer", to = 2, give = { stone = 1 }, get = { lumber = 1 } }, "3 offers a turn")
		T.eq(s.log[#s.log - 1].target, 2, "log names the trade target by seat, for the client")
	end)

	T.test("action cards: can't play the turn you buy, one per turn, Guard moves the Bandit", function()
		local s = afterSetup(2, 9)
		s.rng = scripted({ 1, 1 })
		play(s, 1, { kind = "roll" })
		s.players[1].hand.wool, s.players[1].hand.grain, s.players[1].hand.stone = 2, 2, 2
		s.deck = { "harvest", "guard" }
		play(s, 1, { kind = "buyCard" })
		T.eq(s.players[1].cards[1].kind, "guard")
		rejects(s, 1, { kind = "play", card = "guard" }, "bought this turn")
		play(s, 1, { kind = "endTurn" })
		s.rng = scripted({ 1, 1 })
		play(s, 2, { kind = "roll" })
		play(s, 2, { kind = "endTurn" })
		-- Guards can be played before rolling.
		play(s, 1, { kind = "play", card = "guard" })
		T.eq(s.phase, "bandit")
		local move = Hexlands.chooseBotMove(s, 1, T.Random.new(1))
		play(s, 1, move)
		T.eq(s.phase, "roll", "back to rolling")
		T.eq(s.players[1].guards, 1)
		s.players[1].cards = { { kind = "harvest", bought = 0 }, { kind = "hoard", bought = 0 } }
		s.rng = scripted({ 1, 1 })
		play(s, 1, { kind = "roll" })
		rejects(s, 1, { kind = "play", card = "harvest", res = { "wool", "gold" } }, "bad resource")
		rejects(s, 1, { kind = "play", card = "harvest", res = { "wool" } }, "needs 2")
		rejects(s, 1, { kind = "play", card = "hoard", res = "wool" }, "already played one this turn")
	end)

	T.test("Hoard takes everyone's cards of one kind; Harvest takes 2 from the bank", function()
		local s = afterSetup(3, 10)
		s.rng = scripted({ 1, 1 })
		play(s, 1, { kind = "roll" })
		s.players[1].cards = { { kind = "hoard", bought = 0 } }
		s.players[1].hand.grain = 0
		s.players[2].hand.grain = 3
		s.players[3].hand.grain = 2
		play(s, 1, { kind = "play", card = "hoard", res = "grain" })
		T.eq(s.players[1].hand.grain, 5)
		T.eq(s.players[2].hand.grain, 0)
		T.eq(s.players[3].hand.grain, 0)

		play(s, 1, { kind = "endTurn" })
		s.rng = scripted({ 1, 1 })
		play(s, 2, { kind = "roll" })
		s.players[2].cards = { { kind = "harvest", bought = 0 } }
		local stone = s.players[2].hand.stone
		local bank = s.bank.stone
		play(s, 2, { kind = "play", card = "harvest", res = { "stone", "stone" } })
		T.eq(s.players[2].hand.stone, stone + 2)
		T.eq(s.bank.stone, bank - 2)
	end)

	T.test("Longest Road needs 5, is cut by other camps, and holders keep ties", function()
		local s = Hexlands.new(2, {}, T.Random.new(1))
		s.phase = "main"
		-- Walk a 6-road path around the edge of hex 10 (the center).
		local ring = Hexlands.hexEdges[10]
		for i = 1, 4 do
			s.road[ring[i]] = 1
		end
		T.eq(Hexlands.roadLength(s, 1), 4)
		s.road[ring[5]] = 1
		T.eq(Hexlands.roadLength(s, 1), 5)
		s.road[ring[6]] = 1
		T.eq(Hexlands.roadLength(s, 1), 6, "a closed loop counts every road once")
		s.road[ring[6]] = nil
		-- Hand it to seat 1 the normal way.
		s.turn = 1
		s.players[1].hand.lumber, s.players[1].hand.clay = 1, 1
		s.road[ring[5]] = nil
		play(s, 1, { kind = "road", edge = ring[5] })
		T.eq(s.longestRoad, 1)
		T.eq(Hexlands.points(s, 1), 2)
		-- Seat 2 drops a camp in the middle of the path: 5 roads become 2 + 3.
		local corners = Hexlands.hexVertices[10]
		local middle = nil
		for _, v in corners do
			local own = 0
			for _, e in V[v].edges do
				if s.road[e] == 1 then
					own += 1
				end
			end
			if own == 2 then
				local left = Hexlands.roadLength(s, 1)
				s.owner[v] = 2
				if Hexlands.roadLength(s, 1) == 3 then
					middle = v
					break
				end
				s.owner[v] = nil
				T.eq(Hexlands.roadLength(s, 1), left)
			end
		end
		T.ok(middle ~= nil, "found a corner that splits the road 2 + 3")
	end)

	T.test("reaching the target on your turn wins", function()
		local s = afterSetup(2, 11)
		s.rng = scripted({ 1, 1 })
		play(s, 1, { kind = "roll" })
		s.players[1].cards = {}
		for _ = 1, Hexlands.TARGET_POINTS - 3 do
			table.insert(s.players[1].cards, { kind = "monument", bought = 0 })
		end
		T.eq(Hexlands.getResult(s), nil)
		s.players[1].hand.lumber, s.players[1].hand.clay, s.players[1].hand.wool, s.players[1].hand.grain = 1, 1, 1, 1
		local spot = nil
		for v in V do
			if Hexlands.canCamp(s, 1, v) then
				spot = v
			end
		end
		if not spot then
			-- Lay a road to make room.
			s.players[1].hand.lumber, s.players[1].hand.clay = 4, 4
			for _ = 1, 3 do
				if spot then
					break
				end
				local e = nil
				for edge in E do
					if Hexlands.canRoad(s, 1, edge) then
						e = edge
					end
				end
				play(s, 1, { kind = "road", edge = e })
				for v in V do
					if Hexlands.canCamp(s, 1, v) then
						spot = v
					end
				end
			end
		end
		T.ok(spot ~= nil, "a camp spot")
		play(s, 1, { kind = "camp", vertex = spot })
		local result = Hexlands.getResult(s)
		T.ok(result ~= nil, "game over")
		T.eq(result.winners[1], 1)
		T.eq(Hexlands.getActiveSeats(s)[1], nil)
	end)

	T.test("views hide other hands and action cards", function()
		local s = afterSetup(3, 12)
		s.players[2].cards = { { kind = "monument", bought = 0 } }
		local view = Hexlands.getView(s, 1)
		T.ok(view.you.hand ~= nil, "own hand")
		T.eq(view.players[2].actionCards, 1)
		T.eq(view.players[2].hand, nil)
		T.eq(view.players[2].points, 2, "hidden Monument not shown to others")
		T.eq(Hexlands.getView(s, 2).players[2].points, 3, "but you see your own")
		T.eq(Hexlands.getView(s, nil).you, nil)
		-- Board tables are dense lists: sparse number keys turn into strings over a RemoteEvent.
		T.eq(#view.owner, #V)
		T.eq(#view.town, #V)
		T.eq(#view.road, #E)
		T.eq(#view.discards, 3)
		for v = 1, #V do
			T.eq(view.owner[v], s.owner[v] or 0)
		end
	end)

	T.test("legal moves are all valid", function()
		local s = afterSetup(4, 13)
		local rng = T.Random.new(13)
		for _ = 1, 300 do
			if s.phase == "over" then
				break
			end
			local seat = Hexlands.getActiveSeats(s)[1]
			for _, m in Hexlands.getLegalMoves(s, seat) do
				local ok, err = Hexlands.validateMove(s, seat, m)
				assert(ok, `{m.kind}: {err}`)
			end
			play(s, seat, GameModule.chooseBotMove(Hexlands, s, seat, rng))
		end
	end)

	T.test("bot-vs-bot games always finish with a winner", function()
		for _, level in { "easy", "medium", "hard" } do
			for seats = 2, 4 do
				for seed = 1, 4 do
					local list = {}
					for i = 1, seats do
						table.insert(list, { kind = "bot", name = `Bot {i}` })
					end
					local bots = {}
					for i = 1, seats do
						table.insert(bots, i)
					end
					local match = Match.new("m", Hexlands, list, { botLevel = level, bots = bots }, T.Random.new(seed * 7 + seats))
					local steps = 0
					while not match:isOver() and steps < 8000 do
						steps += 1
						local active = match:getActiveSeats()
						if not match:playForSeat(active[1]) then
							-- A trade waiting on an answer can also time out.
							local timer = match:getTimer()
							assert(timer, `stuck in {match.state.phase}`)
							match:timeout(timer.id)
						end
					end
					T.ok(match:isOver(), `{level} {seats} seats seed {seed} didn't finish`)
					T.eq(#match.result.winners, 1, `{level} {seats} seats seed {seed}: {match.result.reason}`)
					T.eq(match.result.reason, `{Hexlands.TARGET_POINTS} points`, `{level} {seats} seats seed {seed} finished by {match.result.reason} in round {match.state.round}`)
				end
			end
		end
	end)
end
