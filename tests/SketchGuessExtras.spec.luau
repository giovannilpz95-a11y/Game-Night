-- Sketch & Guess: the fill bucket, likes, the "got it" chat, the gallery and the newer
-- house rules (word choices, hint letters).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local SketchGuess = require(ReplicatedStorage.Shared.Games.SketchGuess)
local SketchFill = require(ReplicatedStorage.Shared.SketchFill)
local Match = require(ServerScriptService.Server.Core.Match)

return function(T)
	local function apply(s, seat, move)
		local ok, err = SketchGuess.validateMove(s, seat, move)
		assert(ok, err)
		SketchGuess.applyMove(s, seat, move)
	end

	local function drawing(word, options)
		local opts = options or { bots = { 3, 4 } }
		local s = SketchGuess.new(4, opts, T.Random.new(4))
		s.choices = { word, "cat", "dog" }
		apply(s, s.drawer, { kind = "choose", index = 1 })
		return s
	end

	local function guessers(s): { number }
		local list = {}
		for seat = 1, s.seatCount do
			if seat ~= s.drawer then
				table.insert(list, seat)
			end
		end
		return list
	end

	local R = SketchGuess.resolution
	local function pt(x: number, y: number): { number }
		return { math.floor(x * R), math.floor(y * R) }
	end
	local function enc(...): string
		local all = {}
		for _, p in { ... } do
			table.insert(all, p[1])
			table.insert(all, p[2])
		end
		return SketchGuess.encodePoints(all)
	end

	-- Fill bucket --------------------------------------------------------------------

	T.test("a fill stays inside a closed box and doesn't leak out", function()
		local raster = SketchFill.new()
		raster:add({ shape = "rect", color = 1, size = 1, points = enc(pt(0.2, 0.2), pt(0.6, 0.7)) })
		local rects = raster:add({ shape = "bucket", color = 4, size = 1, points = enc(pt(0.4, 0.45)) }) :: any
		T.ok(rects ~= nil and #rects >= 1)
		T.eq(raster:colorAt(pt(0.4, 0.45)[1], pt(0.4, 0.45)[2]), 4, "inside is filled")
		T.eq(raster:colorAt(pt(0.8, 0.8)[1], pt(0.8, 0.8)[2]), 2, "outside stays white")
		-- A box this simple fills with very few Frames (rows merge into rects).
		T.ok(#rects <= 3, `too many rects: {#rects}`)
		-- Filling the same color again does nothing.
		local again = raster:add({ shape = "bucket", color = 4, size = 1, points = enc(pt(0.4, 0.45)) }) :: any
		T.eq(#again, 0)
	end)

	T.test("thin diagonal outlines hold a fill (no gaps between cells)", function()
		local raster = SketchFill.new()
		local a, b, c = pt(0.5, 0.1), pt(0.9, 0.9), pt(0.1, 0.85)
		raster:add({ color = 1, size = 1, points = enc(a, b, c, a) })
		raster:add({ shape = "bucket", color = 7, size = 1, points = enc(pt(0.5, 0.6)) })
		T.eq(raster:colorAt(pt(0.5, 0.6)[1], pt(0.5, 0.6)[2]), 7)
		T.eq(raster:colorAt(pt(0.05, 0.05)[1], pt(0.05, 0.05)[2]), 2, "the fill leaked out of the triangle")
		T.eq(raster:colorAt(pt(0.95, 0.1)[1], pt(0.95, 0.1)[2]), 2)
	end)

	T.test("a fill can recolor a shape, and stops at eraser lines", function()
		local raster = SketchFill.new()
		raster:add({ shape = "ellipse", fill = true, color = 9, size = 1, points = enc(pt(0.1, 0.1), pt(0.5, 0.5)) })
		raster:add({ shape = "bucket", color = 6, size = 1, points = enc(pt(0.3, 0.3)) })
		T.eq(raster:colorAt(pt(0.3, 0.3)[1], pt(0.3, 0.3)[2]), 6, "the oval turned yellow")
		T.eq(raster:colorAt(pt(0.8, 0.8)[1], pt(0.8, 0.8)[2]), 2)
		-- A white (eraser) wall across the canvas splits it in two.
		local wall = SketchFill.new()
		wall:add({ color = 2, size = 2, points = enc(pt(0.5, 0), pt(0.5, 1)) })
		wall:add({ shape = "bucket", color = 4, size = 1, points = enc(pt(0.2, 0.5)) })
		T.eq(wall:colorAt(pt(0.2, 0.5)[1], pt(0.2, 0.5)[2]), 4)
		T.eq(wall:colorAt(pt(0.8, 0.5)[1], pt(0.8, 0.5)[2]), 2)
	end)

	T.test("bucket moves: validated, limited per drawing, undone one at a time", function()
		local s = drawing("tree")
		local d = s.drawer
		T.eq((SketchGuess.validateMove(s, d, { kind = "bucket", color = 99, points = enc(pt(0.5, 0.5)) })), false)
		T.eq((SketchGuess.validateMove(s, d, { kind = "bucket", color = 4, points = "AAAA" .. "AAAA" })), false, "one point only")
		T.eq((SketchGuess.validateMove(s, d, { kind = "bucket", color = 4, points = "!!!!" })), false)
		T.eq((SketchGuess.validateMove(s, guessers(s)[1], { kind = "bucket", color = 4, points = enc(pt(0.5, 0.5)) })), false, "guessers can't fill")
		apply(s, d, { kind = "stroke", color = 1, size = 2, points = enc(pt(0.1, 0.1), pt(0.9, 0.9)) })
		apply(s, d, { kind = "bucket", color = 4, points = enc(pt(0.5, 0.5)) })
		T.eq(s.buckets, 1)
		T.eq(s.strokes[2].shape, "bucket")
		local before = s.pointCount
		apply(s, d, { kind = "undo" })
		T.eq(s.buckets, 0)
		T.eq(s.pointCount, before - 2)
		T.eq(#s.strokes, 1, "undo took the fill, not the line")
		for _ = 1, SketchGuess.getView(s, d).maxBuckets do
			apply(s, d, { kind = "bucket", color = 5, points = enc(pt(0.2, 0.2)) })
		end
		T.eq((SketchGuess.validateMove(s, d, { kind = "bucket", color = 5, points = enc(pt(0.2, 0.2)) })), false, "fill limit")
		apply(s, d, { kind = "clear" })
		T.eq(s.buckets, 0)
	end)

	T.test("shapes-only tables still have the fill bucket", function()
		local s = drawing("tree", { bots = { 3, 4 }, rules = { tools = "shapes" } })
		T.ok((SketchGuess.validateMove(s, s.drawer, { kind = "bucket", color = 4, points = enc(pt(0.5, 0.5)) })))
	end)

	-- Likes and the "got it" chat --------------------------------------------------------

	T.test("guessers can like a drawing once, and change to a dislike", function()
		local s = drawing("tree")
		local g = guessers(s)[1]
		T.eq((SketchGuess.validateMove(s, s.drawer, { kind = "rate", up = true })), false, "not your own drawing")
		T.eq((SketchGuess.validateMove(s, g, { kind = "rate", up = "yes" })), false)
		apply(s, g, { kind = "rate", up = true })
		T.eq((SketchGuess.validateMove(s, g, { kind = "rate", up = true })), false, "only once")
		local view = SketchGuess.getView(s, s.drawer)
		T.eq(view.likes, 1)
		T.eq(view.feed[#view.feed].kind, "like")
		apply(s, g, { kind = "rate", up = false })
		T.eq(SketchGuess.getView(s, g).likes, 0)
		T.eq(SketchGuess.getView(s, g).youLiked, false)
	end)

	T.test("after guessing, chat only reaches the drawer and others who got it", function()
		local s = SketchGuess.new(5, { bots = { 5 } }, T.Random.new(3))
		s.choices = { "pizza", "cat", "dog" }
		apply(s, s.drawer, { kind = "choose", index = 1 })
		local g = guessers(s)
		T.eq((SketchGuess.validateMove(s, g[1], { kind = "chat", text = "hi" })), false, "guess it first")
		apply(s, g[1], { kind = "guess", text = "pizza", shown = "pizza" })
		T.ok(table.find(SketchGuess.getInterruptSeats(s), g[1]) ~= nil, "may chat out of turn")
		apply(s, g[1], { kind = "chat", text = "yum pizza", shown = "yum pizza" })
		local function sees(seat): boolean
			for _, e in SketchGuess.getView(s, seat).feed do
				if e.kind == "chat" then
					return true
				end
			end
			return false
		end
		T.ok(sees(s.drawer))
		T.ok(sees(g[1]))
		T.ok(not sees(g[2]), "a player still guessing saw the chat")
		T.ok(not sees(nil), "spectators don't see it either")
		apply(s, g[2], { kind = "guess", text = "pizza", shown = "pizza" })
		T.ok(sees(g[2]), "once you get it you see it")
	end)

	T.test("everyone but the drawer may still rate at the reveal", function()
		local s = drawing("tree")
		SketchGuess.onTimeout(s)
		SketchGuess.onTimeout(s)
		SketchGuess.onTimeout(s)
		SketchGuess.onTimeout(s)
		T.eq(s.phase, "reveal")
		local seats = SketchGuess.getInterruptSeats(s)
		T.eq(#seats, 3)
		T.ok(table.find(seats, s.drawer) == nil)
		apply(s, seats[1], { kind = "rate", up = true })
		T.eq((SketchGuess.validateMove(s, seats[2], { kind = "chat", text = "hi" })), false, "no chat at the reveal")
	end)

	-- Gallery ---------------------------------------------------------------------------

	T.test("the gallery shows finished drawings, most liked first, and never reported ones", function()
		local s = SketchGuess.new(4, { bots = {}, rules = { rounds = 1 } }, T.Random.new(5))
		local turns = 0
		while s.phase ~= "gallery" and s.phase ~= "done" and turns < 50 do
			turns += 1
			if s.phase == "choose" then
				apply(s, s.drawer, { kind = "choose", index = 1 })
				local d = s.drawer
				apply(s, d, { kind = "stroke", color = 1, size = 2, points = enc(pt(0.1, 0.1), pt(0.2 + 0.1 * s.turnNumber, 0.5)) })
				local g = guessers(s)
				if s.turnNumber == 2 then
					apply(s, g[1], { kind = "rate", up = true })
					apply(s, g[2], { kind = "rate", up = true })
				elseif s.turnNumber == 3 then
					apply(s, g[1], { kind = "report" })
				end
			else
				SketchGuess.onTimeout(s)
			end
		end
		T.eq(s.phase, "gallery")
		T.eq(#SketchGuess.getActiveSeats(s), 0)
		local view = SketchGuess.getView(s, 1)
		T.eq(#view.strokes, 0, "the gallery carries the drawings")
		T.eq(#view.gallery, 3, "four drawings, one reported")
		T.eq(view.gallery[1].turn, 2, "the most liked comes first")
		T.eq(view.gallery[1].likes, 2)
		for _, e in view.gallery do
			T.ok(e.turn ~= 3, "a reported drawing made the gallery")
			T.ok(#e.strokes > 0)
		end
		T.eq(SketchGuess.getResult(s), nil, "not over during the gallery")
		SketchGuess.onTimeout(s)
		T.eq(s.phase, "done")
		T.ok(SketchGuess.getResult(s) ~= nil)
	end)

	T.test("no gallery when nothing was drawn", function()
		local s = SketchGuess.new(3, { bots = {}, rules = { rounds = 1 } }, T.Random.new(6))
		local steps = 0
		while s.phase ~= "done" and steps < 100 do
			steps += 1
			T.ok(s.phase ~= "gallery", "an empty gallery was shown")
			SketchGuess.onTimeout(s)
		end
		T.eq(s.phase, "done")
	end)

	-- House rules -------------------------------------------------------------------------

	T.test("word choices: 1, 3 or 5 words with their difficulty", function()
		for _, count in { 1, 3, 5 } do
			local s = SketchGuess.new(4, { bots = {}, rules = { wordChoices = count } }, T.Random.new(count))
			T.eq(#s.choices, count)
			local view = SketchGuess.getView(s, s.drawer)
			T.eq(#view.choiceLevels, count)
			T.eq(SketchGuess.getView(s, s.drawer % 4 + 1).choiceLevels, nil)
			local seen = {}
			for _, w in s.choices do
				T.ok(not seen[w], "choices repeat")
				seen[w] = true
			end
			T.eq((SketchGuess.validateMove(s, s.drawer, { kind = "choose", index = count + 1 })), false)
		end
		local odd = SketchGuess.new(4, { bots = {}, rules = { wordChoices = 7 } }, T.Random.new(1))
		T.eq(#odd.choices, 3, "unknown counts fall back to 3")
	end)

	T.test("hint letters: none, up to half, or lots", function()
		local function hintsAfter(rule: string?): number
			local s = drawing("butterfly", { bots = { 3, 4 }, rules = { hints = rule, drawSeconds = 120 } })
			for _ = 1, 5 do
				SketchGuess.onTimeout(s)
			end
			local shown = 0
			for _ in s.revealed do
				shown += 1
			end
			return shown
		end
		T.eq(hintsAfter("none"), 0)
		T.eq(hintsAfter(nil), 4, "up to half of 9 letters")
		T.eq(hintsAfter("lots"), 5, "5 timeouts reveal at most 5")
	end)

	T.test("a full match with likes and chat bots still finishes", function()
		local seats = {
			{ kind = "player", userId = 1, name = "Gio" },
			{ kind = "bot", name = "Bot Ava" },
			{ kind = "bot", name = "Bot Milo" },
		}
		local m = Match.new("m", SketchGuess, seats, { botLevel = "hard", bots = { 2, 3 } }, T.Random.new(21))
		local steps, sawGallery = 0, false
		while not m:isOver() and steps < 5000 do
			steps += 1
			local acted = false
			local movers = table.clone(m:getActiveSeats())
			for _, seat in m:getInterruptSeats() do
				table.insert(movers, seat)
			end
			for _, seat in movers do
				if m:isBot(seat) and m:playForSeat(seat) then
					acted = true
				end
			end
			sawGallery = sawGallery or m.state.phase == "gallery"
			if not acted then
				if m.state.phase == "choose" and m.state.drawer == 1 then
					T.ok(m:submitMove(1, { kind = "choose", index = 1 }))
					T.ok(m:submitMove(1, { kind = "shape", shape = "rect", color = 1, size = 2, fill = false, points = enc(pt(0.2, 0.2), pt(0.7, 0.7)) }))
					T.ok(m:submitMove(1, { kind = "bucket", color = 4, points = enc(pt(0.4, 0.4)) }))
				else
					local timer = m:getTimer()
					T.ok(timer ~= nil)
					T.ok(m:timeout(timer.id))
				end
			end
		end
		T.ok(m.result ~= nil, "match should end")
		T.ok(sawGallery, "the gallery showed")
	end)
end
