local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TableActions = require(ReplicatedStorage.Shared.TableActions)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local GameModule = require(ReplicatedStorage.Shared.GameModule)

return function(T)
	T.test("chess moves reach from one square to another on the board's Row/Col", function()
		local a = TableActions.describe("Chess", { from = "e2", to = "e4" }) :: any
		T.eq(a.kind, "move")
		T.eq(a.from[1], 7)
		T.eq(a.from[2], 5)
		T.eq(a.to[1], 5)
		T.eq(a.to[2], 5)
		T.eq(TableActions.describe("Chess", { from = "z9", to = "e4" }), nil)
	end)

	T.test("checkers lands on the last square of a multi-jump", function()
		local a = TableActions.describe("Checkers", { from = { 6, 1 }, path = { { 4, 3 }, { 2, 5 } } }) :: any
		T.eq(a.kind, "move")
		T.eq(a.to[1], 2)
		T.eq(a.to[2], 5)
	end)

	T.test("tic-tac-toe and four in a row place on the right cell", function()
		local a = TableActions.describe("TicTacToe", { cell = 6 }) :: any
		T.eq(a.kind, "place")
		T.eq(a.cell[1], 2)
		T.eq(a.cell[2], 3)
		local b = TableActions.describe("FourInARow", { column = 4 }) :: any
		T.eq(b.column, 4)
	end)

	T.test("card games toss cards, dice games roll, go fish points at who you ask", function()
		T.eq((TableActions.describe("ColorClash", { kind = "play", card = 3 }) :: any).kind, "card")
		T.eq((TableActions.describe("ColorClash", { kind = "draw" }) :: any).kind, "draw")
		T.eq((TableActions.describe("Estates", { kind = "roll" }) :: any).kind, "dice")
		T.eq((TableActions.describe("Conquest", { kind = "attack", from = 1, to = 2 }) :: any).kind, "dice")
		T.eq((TableActions.describe("SlapStack", { kind = "slap" }) :: any).kind, "slap")
		T.eq((TableActions.describe("Spoons", { kind = "grab" }) :: any).kind, "grab")
		local ask = TableActions.describe("GoFish", { kind = "ask", target = 3, rank = 5 }) :: any
		T.eq(ask.kind, "point")
		T.eq(ask.seat, 3)
	end)

	T.test("drawing strokes and junk don't animate", function()
		T.eq(TableActions.describe("SketchGuess", { kind = "stroke", points = {} }), nil)
		T.eq(TableActions.describe("ColorClash", "play"), nil)
		T.eq(TableActions.describe("ColorClash", { kind = 5 }), nil)
		T.eq(TableActions.describe("Chess", { from = {}, to = "e4" }), nil)
		T.eq(TableActions.describe("GoFish", { kind = "ask", target = 99 }).seat, nil)
	end)

	T.test("winners cheer, losers groan, a draw is a shrug", function()
		local r = TableActions.reactions({ winners = { 2 }, isDraw = false }, 3)
		T.eq(r[1], "groan")
		T.eq(r[2], "cheer")
		T.eq(r[3], "groan")
		local d = TableActions.reactions({ winners = {}, isDraw = true }, 2)
		T.eq(d[1], "shrug")
		T.eq(d[2], "shrug")
		T.eq(next(TableActions.reactions(nil, 2)), nil)
	end)

	T.test("only emotes on the wheel are accepted", function()
		T.ok(TableActions.emote("wave") ~= nil)
		T.eq(TableActions.emote("dance"), nil)
		T.eq(TableActions.emote(12), nil)
		for _, emote in TableActions.Emotes do
			T.ok(TableActions.Kinds[emote.id], `{emote.id} has no gesture`)
		end
	end)

	T.test("every ready game's moves turn into gestures the client knows", function()
		local skip = { WordTiles = true } -- its bot needs the full dictionary; covered above
		for _, entry in GameCatalog.entries do
			if (entry.status == "ready" or entry.status == "soon") and entry.module and not skip[entry.module] then
				local rules = require((ReplicatedStorage.Shared.Games :: any)[entry.module]) :: any
				local rng = T.Random.new(3)
				local seats = rules.minSeats
				local bots = {}
				for seat = 1, seats do
					table.insert(bots, seat)
				end
				local state = rules.new(seats, { botLevel = "easy", bots = bots }, rng)
				local animated = 0
				for _ = 1, 80 do
					if rules.getResult(state) then
						break
					end
					local active = rules.getActiveSeats(state)
					if #active == 0 then
						if rules.onTimeout then
							rules.onTimeout(state)
							continue
						end
						break
					end
					local seat = active[1]
					local move = GameModule.chooseBotMove(rules, state, seat, rng)
					if move == nil or not rules.validateMove(state, seat, move) then
						if rules.onTimeout then
							rules.onTimeout(state)
							continue
						end
						break
					end
					local action = TableActions.describe(entry.module, move)
					if action then
						T.ok(TableActions.Kinds[action.kind], `{entry.module}: unknown gesture {action.kind}`)
						animated += 1
					end
					rules.applyMove(state, seat, move)
				end
				T.ok(animated > 0, `{entry.module}: no move was animated`)
			end
		end
	end)
end
