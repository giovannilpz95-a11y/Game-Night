local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ColorClash = require(ReplicatedStorage.Shared.Games.ColorClash)
local Match = require(ServerScriptService.Server.Core.Match)

-- "Last card!" calls, catching, and jump-ins.
return function(T)
	local cards = ColorClash.cards

	local function findAll(pred): { number }
		local out = {}
		for id, card in cards do
			if pred(card) then
				table.insert(out, id)
			end
		end
		return out
	end

	local function setup(seatCount, hands, top, rules)
		local s = ColorClash.new(seatCount, { botLevel = "medium", rules = rules }, T.Random.new(1))
		local used = { [top] = true }
		for seat = 1, seatCount do
			s.hands[seat] = hands[seat] or {}
			for _, id in s.hands[seat] do
				used[id] = true
			end
		end
		s.deck = {}
		for id = 1, #cards do
			if not used[id] then
				table.insert(s.deck, id)
			end
		end
		s.discard = { top }
		s.discardBy = { 0 }
		s.color = cards[top].color
		s.turn = 1
		return s
	end

	local function play(s, seat, move)
		local ok, err = ColorClash.validateMove(s, seat, move)
		assert(ok, err)
		ColorClash.applyMove(s, seat, move)
	end

	local coral5s = findAll(function(c) return c.color == 1 and c.value == 5 end) -- two of them
	local coral9 = findAll(function(c) return c.color == 1 and c.value == 9 end)[1]
	local coral3 = findAll(function(c) return c.color == 1 and c.value == 3 end)[1]
	local teal3 = findAll(function(c) return c.color == 3 and c.value == 3 end)[1]
	local honey8 = findAll(function(c) return c.color == 2 and c.value == 8 end)[1]

	T.test("forgetting to call last card lets the next player catch you", function()
		local s = setup(3, { { coral5s[1], teal3 }, { coral3, honey8 }, { honey8 } }, coral9)
		play(s, 1, { kind = "play", card = coral5s[1] }) -- no call
		T.eq(s.exposed, 1)
		local view = ColorClash.getView(s, 2)
		T.ok(view.canCatch)
		T.eq(ColorClash.validateMove(s, 3, { kind = "catch" }), false) -- not their turn
		play(s, 2, { kind = "catch" })
		T.eq(#s.hands[1], 3)
		T.eq(s.turn, 2) -- still the catcher's turn
		T.eq(s.lastAction.kind, "catch")
	end)

	T.test("calling last card is safe, and the chance passes after a move", function()
		local s = setup(3, { { coral5s[1], teal3 }, { coral3, honey8 }, { honey8 } }, coral9)
		play(s, 1, { kind = "play", card = coral5s[1], call = true })
		T.eq(s.exposed, nil)
		T.ok(s.lastAction.called)
		T.eq(ColorClash.validateMove(s, 2, { kind = "catch" }), false)

		local s2 = setup(3, { { coral5s[1], teal3 }, { coral3, honey8 }, { honey8 } }, coral9)
		play(s2, 1, { kind = "play", card = coral5s[1] })
		play(s2, 2, { kind = "play", card = coral3 }) -- moved on instead of catching
		T.eq(s2.exposed, 2) -- seat 1 is off the hook (and seat 2 just forgot their own call)
	end)

	T.test("the house rule can turn the call off", function()
		local s = setup(2, { { coral5s[1], teal3 }, { coral3 } }, coral9, { lastCard = false })
		play(s, 1, { kind = "play", card = coral5s[1] })
		T.eq(s.exposed, nil)
	end)

	T.test("jump in: an identical card goes down out of turn and play goes on from there", function()
		local s = setup(4, { { coral5s[1], honey8 }, { teal3, honey8 }, { coral5s[2], teal3, coral3 }, { honey8 } }, coral9, { jumpIn = true })
		play(s, 1, { kind = "play", card = coral5s[1] })
		T.eq(s.turn, 2)
		T.eq(#ColorClash.getView(s, 3).jumpIns, 1)
		play(s, 3, { kind = "play", card = coral5s[2] })
		T.ok(s.lastAction.jumpIn)
		T.eq(s.turn, 4) -- next after the jumper
		-- Not identical (same number, other color) can't jump in.
		T.eq(ColorClash.validateMove(s, 2, { kind = "play", card = teal3 }), false)
	end)

	T.test("jump in is off by default and goes through Match out of turn", function()
		local s = setup(3, { { coral5s[1], honey8 }, { teal3 }, { coral5s[2], honey8 } }, coral9)
		play(s, 1, { kind = "play", card = coral5s[1] })
		T.eq(#ColorClash.getJumpIns(s, 3), 0)

		local seats = {
			{ kind = "player", userId = 1, name = "A" },
			{ kind = "player", userId = 2, name = "B" },
			{ kind = "player", userId = 3, name = "C" },
		}
		local m = Match.new("m", ColorClash, seats, { rules = { jumpIn = true } }, T.Random.new(3))
		local st = m.state
		local nines = findAll(function(c) return c.color == 1 and c.value == 9 end)
		for seat = 1, 3 do
			for _, id in nines do
				local i = table.find(st.hands[seat], id)
				if i then
					table.remove(st.hands[seat], i)
				end
			end
		end
		st.discard = { nines[1] }
		st.discardBy = { 0 }
		st.color = 1
		st.turn = 1
		table.insert(st.hands[3], nines[2])
		T.eq(m:submitMove(2, { kind = "draw" }), false) -- still not your turn
		T.ok(m:submitMove(3, { kind = "play", card = nines[2] }))
		T.eq(st.turn, 1) -- 3 players: after seat 3 comes seat 1
	end)
end
