-- Sketch & Guess stamps tables (tools = "stamps"): the launch form with no free-form
-- drawing. Only pre-made stamps, placed, edited, layered and deleted; bots draw stamps.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local SketchGuess = require(ReplicatedStorage.Shared.Games.SketchGuess)
local Doodles = require(ServerScriptService.Server.Data.SketchDoodles)
local Words = require(ServerScriptService.Server.Data.SketchWords)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local Config = require(ReplicatedStorage.Shared.Config)
local Match = require(ServerScriptService.Server.Core.Match)

return function(T)
	local function apply(s, seat, move)
		local ok, err = SketchGuess.validateMove(s, seat, move)
		assert(ok, err)
		SketchGuess.applyMove(s, seat, move)
	end

	-- The server passes its word list and doodles in (they never ship to clients).
	local function stampsDrawing(word: string?)
		local s = SketchGuess.new(4, { bots = { 3, 4 }, rules = { tools = "stamps" }, wordBank = Words, doodles = Doodles }, T.Random.new(4))
		s.choices = { word or "sun", "cat", "dog" }
		apply(s, s.drawer, { kind = "choose", index = 1 })
		return s
	end

	local function stamp(id: string?, x: number?, y: number?): any
		return { kind = "stamp", stamp = id or "circle", color = 4, x = x or 2000, y = y or 1500, w = 400, h = 400, rot = 0 }
	end

	T.test("stamps tables take only stamps: no pen, shapes or fill", function()
		local s = stampsDrawing()
		T.eq(SketchGuess.getView(s, 1).tools, "stamps")
		local d = s.drawer
		local stroke = { kind = "stroke", color = 1, size = 2, points = SketchGuess.encodePoints({ 10, 10, 200, 200 }) }
		local shape = { kind = "shape", shape = "line", color = 1, size = 2, fill = false, points = SketchGuess.encodePoints({ 10, 10, 200, 200 }) }
		local bucket = { kind = "bucket", color = 1, points = SketchGuess.encodePoints({ 10, 10 }) }
		for _, move in { stroke, shape, bucket } do
			local ok, err = SketchGuess.validateMove(s, d, move)
			T.eq(ok, false, move.kind)
			T.ok(string.find(err or "", "Stamps only") ~= nil, err)
		end
		-- And stamps don't work at a pen table.
		local pen = SketchGuess.new(4, { bots = { 3, 4 }, wordBank = Words, doodles = Doodles }, T.Random.new(4))
		pen.choices = { "sun", "cat", "dog" }
		apply(pen, pen.drawer, { kind = "choose", index = 1 })
		T.eq((SketchGuess.validateMove(pen, pen.drawer, stamp())), false)
	end)

	T.test("a stamp is checked field by field", function()
		local s = stampsDrawing()
		local d = s.drawer
		T.ok((SketchGuess.validateMove(s, d, stamp())))
		for _, id in SketchGuess.stamps do
			T.ok((SketchGuess.validateMove(s, d, stamp(id.id))), id.id)
		end
		local function bad(change: { [string]: any }, why: string)
			local move = stamp()
			for k, v in change do
				move[k] = v
			end
			T.eq((SketchGuess.validateMove(s, d, move)), false, why)
		end
		bad({ stamp = "letterA" }, "unknown stamp")
		bad({ stamp = 3 }, "stamp id must be a string")
		bad({ color = 0 }, "color")
		bad({ color = #SketchGuess.palette + 1 }, "color")
		bad({ x = -1 }, "x")
		bad({ y = SketchGuess.resolution + 1 }, "y")
		bad({ x = 10.5 }, "whole numbers only")
		bad({ w = SketchGuess.stampMin - 1 }, "too small")
		bad({ h = SketchGuess.stampMax + 1 }, "too big")
		bad({ rot = 360 }, "rot")
		bad({ rot = -15 }, "rot")
		bad({ rot = 0 / 0 }, "NaN")
		bad({ stamp = "star", w = 400, h = 300 }, "a star can't be stretched")
		T.ok((SketchGuess.validateMove(s, d, { kind = "stamp", stamp = "stick", color = 1, x = 0, y = 0, w = 900, h = 40, rot = 345 })))
		-- Guessers can't stamp.
		local guesser = if d == 1 then 2 else 1
		T.eq((SketchGuess.validateMove(s, guesser, stamp())), false)
	end)

	T.test("stamps are stored with their box and turn, and count toward the cap", function()
		local s = stampsDrawing()
		local d = s.drawer
		apply(s, d, { kind = "stamp", stamp = "triangle", color = 7, x = 100, y = 200, w = 300, h = 400, rot = 30 })
		local stroke = s.strokes[1]
		T.eq(stroke.shape, "stamp")
		T.eq(stroke.stamp, "triangle")
		T.eq(stroke.color, 7)
		T.eq(stroke.rot, 30)
		local x, y, w, h = SketchGuess.stampBox(stroke)
		T.eq(x, 100)
		T.eq(y, 200)
		T.eq(w, 300)
		T.eq(h, 400)
		T.eq(SketchGuess.stampBox({ shape = "line", points = "" }), nil)
		for _ = 2, SketchGuess.maxStamps do
			apply(s, d, stamp())
		end
		T.eq(#s.strokes, SketchGuess.maxStamps)
		local ok, err = SketchGuess.validateMove(s, d, stamp())
		T.eq(ok, false)
		T.ok(string.find(err or "", "most stamps") ~= nil, err)
		T.eq(SketchGuess.getView(s, 1).maxStamps, SketchGuess.maxStamps)
	end)

	T.test("editing, layering and deleting a stamp bump strokeRev", function()
		local s = stampsDrawing()
		local d = s.drawer
		apply(s, d, stamp("circle", 100, 100))
		apply(s, d, stamp("square", 200, 200))
		apply(s, d, stamp("ring", 300, 300))
		local rev = s.strokeRev
		T.eq(SketchGuess.getView(s, 1).strokeRev, rev)

		-- In place: a new spot, size, turn and color, same stamp kind.
		apply(s, d, { kind = "stampEdit", index = 2, color = 9, x = 50, y = 60, w = 500, h = 250, rot = 90 })
		T.eq(s.strokes[2].stamp, "square")
		T.eq(s.strokes[2].color, 9)
		T.eq(s.strokes[2].rot, 90)
		T.eq((SketchGuess.stampBox(s.strokes[2])), 50)
		T.ok(s.strokeRev > rev)

		-- Back and front move it in the list (drawn first = behind).
		apply(s, d, { kind = "stampEdit", index = 3, color = 1, x = 300, y = 300, w = 400, h = 400, rot = 0, layer = "back" })
		T.eq(s.strokes[1].stamp, "ring")
		T.eq(s.strokes[3].stamp, "square")
		apply(s, d, { kind = "stampEdit", index = 1, color = 1, x = 300, y = 300, w = 400, h = 400, rot = 0, layer = "front" })
		T.eq(s.strokes[3].stamp, "ring")
		T.eq(#s.strokes, 3)

		local bad = { kind = "stampEdit", index = 4, color = 1, x = 1, y = 1, w = 400, h = 400, rot = 0 }
		T.eq((SketchGuess.validateMove(s, d, bad)), false, "no stamp 4")
		bad.index = 1
		bad.layer = "middle"
		T.eq((SketchGuess.validateMove(s, d, bad)), false, "bad layer")

		local before = s.pointCount
		rev = s.strokeRev
		apply(s, d, { kind = "stampDelete", index = 1 })
		T.eq(#s.strokes, 2)
		T.eq(s.pointCount, before - 2)
		T.ok(s.strokeRev > rev)
		T.eq((SketchGuess.validateMove(s, d, { kind = "stampDelete", index = 3 })), false)

		rev = s.strokeRev
		apply(s, d, { kind = "undo" })
		T.eq(#s.strokes, 1)
		T.ok(s.strokeRev > rev)
		apply(s, d, { kind = "clear" })
		T.eq(#s.strokes, 0)
		T.eq(s.pointCount, 0)
	end)

	T.test("a stretch-free stamp stays square when edited", function()
		local s = stampsDrawing()
		local d = s.drawer
		apply(s, d, stamp("heart"))
		T.eq((SketchGuess.validateMove(s, d, { kind = "stampEdit", index = 1, color = 4, x = 1, y = 1, w = 500, h = 300, rot = 0 })), false)
		T.ok((SketchGuess.validateMove(s, d, { kind = "stampEdit", index = 1, color = 4, x = 1, y = 1, w = 500, h = 500, rot = 0 })))
	end)

	T.test("every bot doodle draws as legal stamps at a stamps table", function()
		for word in Doodles do
			local s = stampsDrawing(word)
			local moves = SketchGuess.doodleMoves(word, Doodles, true) :: any
			T.ok(#moves <= SketchGuess.maxStamps, `{word}: {#moves} stamps`)
			for _, move in moves do
				T.eq(move.kind, "stamp", word)
				local ok, err = SketchGuess.validateMove(s, s.drawer, move)
				T.ok(ok, `{word}: {err}`)
				SketchGuess.applyMove(s, s.drawer, move)
			end
			-- Same number of pieces as the shape doodle (one per box, oval or line).
			local shapes = 0
			for _, op in Doodles[word] do
				shapes += if op[1] == "l" then #op[2] // 2 - 1 else 1
			end
			T.eq(#moves, shapes, word)
		end
	end)

	T.test("a bot drawer at a stamps table draws its doodle in stamps", function()
		local s = SketchGuess.new(3, { bots = { 2, 3 }, rules = { tools = "stamps" }, wordBank = Words, doodles = Doodles }, T.Random.new(1))
		apply(s, s.drawer, { kind = "giveUp" })
		SketchGuess.onTimeout(s)
		T.eq(s.drawer, 2)
		local rng = T.Random.new(1)
		apply(s, 2, SketchGuess.chooseBotMove(s, 2, rng))
		local planned = #(SketchGuess.doodleMoves(s.word, Doodles, true) :: any)
		for _ = 1, planned do
			local move = SketchGuess.chooseBotMove(s, 2, rng)
			T.eq(move.kind, "stamp")
			apply(s, 2, move)
		end
		T.eq(SketchGuess.chooseBotMove(s, 2, rng), nil, "done: just wait")
		T.eq(#SketchGuess.getLegalMoves(s, 2), 0)
	end)

	T.test("a whole stamps game with bots plays to the end through Match", function()
		local seats = {
			{ kind = "player", userId = 1, name = "A" },
			{ kind = "bot", name = "B" },
			{ kind = "bot", name = "C" },
		}
		local m = Match.new("stamps", SketchGuess, seats, { bots = { 2, 3 }, rules = { tools = "stamps", rounds = 1 }, wordBank = Words, doodles = Doodles }, T.Random.new(9))
		local guard = 0
		while not m:isOver() and guard < 5000 do
			guard += 1
			local moved = false
			for seat = 1, 3 do
				if m:canMove(seat) and m:playForSeat(seat) then
					moved = true
				end
			end
			if not moved then
				local timer = m:getTimer()
				if timer then
					m:timeout(timer.id)
				end
			end
		end
		T.ok(m:isOver(), "finished")
		for _, entry in m.state.gallery do
			for _, stroke in entry.strokes do
				T.eq(stroke.shape, "stamp", "only stamps on a stamps table")
			end
		end
	end)

	T.test("launch build: stamps only and no pen house rule", function()
		T.eq(Config.SketchFreeDraw, false)
		local entry = GameCatalog.get("SketchGuess") :: any
		for _, rule in entry.houseRules do
			T.ok(rule.key ~= "tools", "the Drawing tools rule is hidden")
		end
	end)
end
