local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local SketchGuess = require(ReplicatedStorage.Shared.Games.SketchGuess)
local Words = require(ReplicatedStorage.Shared.Games.Data.SketchWords)
local Doodles = require(ReplicatedStorage.Shared.Games.Data.SketchDoodles)
local Match = require(ServerScriptService.Server.Core.Match)

return function(T)
	local function apply(s, seat, move)
		local ok, err = SketchGuess.validateMove(s, seat, move)
		assert(ok, err)
		SketchGuess.applyMove(s, seat, move)
	end

	-- A 4-seat game (seats 3 and 4 are bots) with the drawer on a known word.
	local function drawing(word)
		local s = SketchGuess.new(4, { bots = { 3, 4 } }, T.Random.new(4))
		s.choices = { word, "cat", "dog" }
		apply(s, s.drawer, { kind = "choose", index = 1 })
		return s
	end

	local function guesserOf(s): number
		for seat = 1, s.seatCount do
			if seat ~= s.drawer then
				return seat
			end
		end
		error("no guesser")
	end

	T.test("with 3+ players only players draw, and the drawer picks a word", function()
		local s = SketchGuess.new(5, { bots = { 4, 5 } }, T.Random.new(1))
		T.eq(#s.drawers, 3)
		T.eq(s.totalTurns, 6, "three drawers draw twice each")
		T.eq(s.phase, "choose")
		T.eq(#SketchGuess.getActiveSeats(s), 1)
		local view = SketchGuess.getView(s, s.drawer)
		T.eq(#view.choices, 3)
		T.eq(SketchGuess.getView(s, 4).choices, nil, "others don't see the choices")
		apply(s, s.drawer, { kind = "choose", index = 2 })
		T.eq(s.phase, "draw")
		T.eq(#SketchGuess.getActiveSeats(s), 5, "drawer + 4 guessers")
	end)

	T.test("with fewer than 3 players bots join the drawing turns", function()
		local s = SketchGuess.new(4, { bots = { 3, 4 } }, T.Random.new(1))
		T.eq(#s.drawers, 4)
		T.eq(s.totalTurns, 8)
		local solo = SketchGuess.new(3, { bots = { 2, 3 } }, T.Random.new(1))
		T.eq(#solo.drawers, 3)
		T.eq(solo.totalTurns, 6)
	end)

	T.test("the word is hidden from guessers until they get it", function()
		local s = drawing("pizza")
		local g = guesserOf(s)
		T.eq(SketchGuess.getView(s, s.drawer).word, "pizza")
		T.eq(SketchGuess.getView(s, g).word, nil)
		T.eq(SketchGuess.getView(s, g).hint, "_ _ _ _ _")
		apply(s, g, { kind = "guess", text = "  PIZZA! ", shown = "PIZZA!" })
		T.eq(SketchGuess.getView(s, g).word, "pizza")
		T.ok(s.scores[g] > 0)
		T.eq(s.scores[s.drawer], 50)
		-- The correct guess itself never shows up in the feed.
		for _, entry in SketchGuess.getView(s, 3).feed do
			T.ok(not string.find(string.lower(entry.text), "pizza"), "leaked the word")
		end
		T.eq((SketchGuess.validateMove(s, g, { kind = "guess", text = "pizza" })), false, "only once")
	end)

	T.test("other spellings count, near misses get a private hint", function()
		local s = drawing("donut|doughnut")
		T.eq(s.word, "donut")
		local g = guesserOf(s)
		apply(s, g, { kind = "guess", text = "doughnut", shown = "doughnut" })
		T.ok(s.guessed[g])

		local c = drawing("pizza")
		local g2 = guesserOf(c)
		apply(c, g2, { kind = "guess", text = "pizzo", shown = "pizzo" })
		local mine, theirs = 0, 0
		for _, e in SketchGuess.getView(c, g2).feed do
			if e.kind == "close" then
				mine += 1
			end
		end
		for _, e in SketchGuess.getView(c, 3).feed do
			if e.kind == "close" then
				theirs += 1
			end
		end
		T.eq(mine, 1)
		T.eq(theirs, 0)
	end)

	T.test("wrong guesses show only the filtered text", function()
		local s = drawing("pizza")
		local g = guesserOf(s)
		apply(s, g, { kind = "guess", text = "badword", shown = "#######" })
		apply(s, g, { kind = "guess", text = "taco" })
		local feed = SketchGuess.getView(s, 3).feed
		T.eq(feed[#feed - 1].text, "#######")
		T.eq(feed[#feed].text, "(hidden)", "unfiltered text is never shown")
	end)

	T.test("everyone guessing ends the drawing early", function()
		local s = drawing("cat")
		for seat = 1, 4 do
			if seat ~= s.drawer then
				apply(s, seat, { kind = "guess", text = "cat", shown = "cat" })
			end
		end
		T.eq(s.phase, "reveal")
		T.eq(s.scores[s.drawer], 150)
		T.ok(s.guessed[s.drawer] == nil)
	end)

	T.test("timer reveals hints, then the round moves on", function()
		local s = drawing("elephant")
		local g = guesserOf(s)
		local id = SketchGuess.getTimer(s).id
		SketchGuess.onTimeout(s)
		T.ok(SketchGuess.getTimer(s).id ~= id, "new segment, new timer")
		local revealed = 0
		for _ in s.revealed do
			revealed += 1
		end
		T.eq(revealed, 1)
		T.ok(string.find(SketchGuess.getView(s, g).hint, "%a") ~= nil)
		SketchGuess.onTimeout(s)
		SketchGuess.onTimeout(s)
		SketchGuess.onTimeout(s)
		T.eq(s.phase, "reveal")
		local drawer = s.drawer
		SketchGuess.onTimeout(s)
		T.eq(s.phase, "choose")
		T.ok(s.drawer ~= drawer, "next drawer")
	end)

	T.test("strokes: encode, validate, undo a whole line, clear", function()
		local pts = { 0, 0, 4095, 4095, 100, 2000 }
		local encoded = SketchGuess.encodePoints(pts)
		T.eq(#encoded, 12)
		local back = SketchGuess.decodePoints(encoded)
		for i, v in pts do
			T.eq(back[i], v)
		end
		local s = drawing("tree")
		local d = s.drawer
		apply(s, d, { kind = "stroke", color = 1, size = 2, points = encoded })
		apply(s, d, { kind = "stroke", color = 4, size = 1, points = encoded })
		apply(s, d, { kind = "stroke", color = 4, size = 1, points = encoded, cont = true })
		T.eq(#s.strokes, 3)
		apply(s, d, { kind = "undo" })
		T.eq(#s.strokes, 1, "undo removed both chunks of the line")
		T.eq(s.pointCount, 3)
		apply(s, d, { kind = "clear" })
		T.eq(#s.strokes, 0)
		T.eq(s.pointCount, 0)
		-- Junk from the network.
		T.eq((SketchGuess.validateMove(s, d, { kind = "stroke", color = 99, size = 1, points = encoded })), false)
		T.eq((SketchGuess.validateMove(s, d, { kind = "stroke", color = 1, size = 1, points = "!!!!" })), false)
		T.eq((SketchGuess.validateMove(s, d, { kind = "stroke", color = 1, size = 1, points = "AB" })), false)
		T.eq((SketchGuess.validateMove(s, d, { kind = "stroke", color = 1, size = 1, points = string.rep("A", 4 * 65) })), false)
		T.eq((SketchGuess.validateMove(s, guesserOf(s), { kind = "stroke", color = 1, size = 1, points = encoded })), false, "guessers can't draw")
		T.eq((SketchGuess.validateMove(s, guesserOf(s), { kind = "guess", text = string.rep("a", 41) })), false)
		T.eq((SketchGuess.validateMove(s, guesserOf(s), { kind = "guess", text = "!!!" })), false)
	end)

	T.test("a majority of players can vote to skip a drawing", function()
		local s = SketchGuess.new(5, { bots = { 5 } }, T.Random.new(2))
		apply(s, s.drawer, { kind = "choose", index = 1 })
		local voters = {}
		for seat = 1, 4 do
			if seat ~= s.drawer then
				table.insert(voters, seat)
			end
		end
		apply(s, voters[1], { kind = "voteSkip" })
		T.eq(s.phase, "draw")
		T.eq((SketchGuess.validateMove(s, voters[1], { kind = "voteSkip" })), false, "one vote each")
		apply(s, voters[2], { kind = "voteSkip" })
		T.eq(s.phase, "reveal", "2 of 3 players voted")
		T.eq(#s.strokes, 0, "the drawing is wiped")
	end)

	T.test("a bot drawer picks a doodle word and draws it shape by shape", function()
		local s = SketchGuess.new(3, { bots = { 2, 3 } }, T.Random.new(1))
		-- Seat 1 (the player) draws first; skip to the bot's turn.
		apply(s, s.drawer, { kind = "giveUp" })
		SketchGuess.onTimeout(s)
		T.eq(s.drawer, 2)
		for _, entry in s.choices do
			T.ok(Doodles[string.split(entry, "|")[1]] ~= nil, `{entry} has no doodle`)
		end
		local rng = T.Random.new(1)
		apply(s, 2, SketchGuess.chooseBotMove(s, 2, rng))
		T.eq(s.phase, "draw")
		local planned = #SketchGuess.doodleMoves(s.word)
		T.ok(planned >= 2)
		for _ = 1, planned do
			local move = SketchGuess.chooseBotMove(s, 2, rng)
			T.eq(move.kind, "shape")
			apply(s, 2, move)
		end
		T.eq(#s.strokes, planned)
		T.eq(SketchGuess.chooseBotMove(s, 2, rng), nil, "done drawing: just wait")
		T.eq(#SketchGuess.getLegalMoves(s, 2), 0, "and never fall back to giving up")
		T.eq(s.phase, "draw")
		-- Bots draw in shapes only, so they work at a shapes-only table too.
		T.ok(SketchGuess.getView(s, 1).drawerIsBot)
		T.eq((SketchGuess.validateMove(s, 1, { kind = "report" })), false, "bot doodles can't be reported")
	end)

	T.test("a player's seat a bot took over gives up when it has no doodle", function()
		local s = SketchGuess.new(4, { bots = {} }, T.Random.new(5))
		s.choices = { "dragon", "castle", "pirate" }
		local move = SketchGuess.chooseBotMove(s, s.drawer, T.Random.new(1))
		T.eq(move.kind, "giveUp")
		s.choices = { "dragon", "sun", "pirate" }
		move = SketchGuess.chooseBotMove(s, s.drawer, T.Random.new(1))
		T.eq(move.kind, "choose")
		T.eq(move.index, 2)
	end)

	T.test("every doodle is an easy word and draws with legal moves", function()
		local easy = {}
		for _, entry in Words.easy do
			easy[string.split(entry, "|")[1]] = true
		end
		local count = 0
		for word in Doodles do
			count += 1
			T.ok(easy[word], `doodle "{word}" isn't in the easy list`)
			local s = drawing(word)
			for _, move in SketchGuess.doodleMoves(word) :: any do
				local ok, err = SketchGuess.validateMove(s, s.drawer, move)
				T.ok(ok, `{word}: {err}`)
				SketchGuess.applyMove(s, s.drawer, move)
			end
		end
		T.ok(count >= 30, "enough doodles to keep solo games fresh")
		T.eq(SketchGuess.doodleMoves("dragon"), nil)
	end)

	T.test("shapes: lines, boxes and ovals; undo removes one shape", function()
		local s = drawing("tree")
		local d = s.drawer
		local two = SketchGuess.encodePoints({ 100, 100, 2000, 1500 })
		apply(s, d, { kind = "shape", shape = "rect", color = 4, size = 2, fill = true, points = two })
		apply(s, d, { kind = "shape", shape = "ellipse", color = 7, size = 1, fill = false, points = two })
		apply(s, d, { kind = "shape", shape = "line", color = 1, size = 3, points = two })
		T.eq(#s.strokes, 3)
		T.eq(s.strokes[1].shape, "rect")
		T.eq(s.strokes[1].fill, true)
		T.eq(s.strokes[3].fill, false)
		apply(s, d, { kind = "undo" })
		T.eq(#s.strokes, 2)
		T.eq(s.pointCount, 4)
		local function bad(move, why)
			T.eq((SketchGuess.validateMove(s, d, move)), false, why)
		end
		bad({ kind = "shape", shape = "star", color = 1, size = 1, points = two }, "unknown shape")
		bad({ kind = "shape", shape = "rect", color = 1, size = 1, points = SketchGuess.encodePoints({ 1, 2, 3, 4, 5, 6 }) }, "three points")
		bad({ kind = "shape", shape = "rect", color = 1, size = 9, points = two }, "bad size")
		bad({ kind = "shape", shape = "rect", color = 1, size = 1, fill = "yes", points = two }, "bad fill")
		bad({ kind = "shape", shape = "rect", color = 1, size = 1, points = "!!!!!!!!" }, "bad points")
		T.eq((SketchGuess.validateMove(s, guesserOf(s), { kind = "shape", shape = "line", color = 1, size = 1, points = two })), false, "guessers can't draw")
	end)

	T.test("shapes-only tables reject the pen", function()
		local s = SketchGuess.new(4, { bots = {}, rules = { tools = "shapes" } }, T.Random.new(4))
		apply(s, s.drawer, { kind = "choose", index = 1 })
		T.eq(SketchGuess.getView(s, 1).tools, "shapes")
		local pts = SketchGuess.encodePoints({ 0, 0, 100, 100 })
		T.eq((SketchGuess.validateMove(s, s.drawer, { kind = "stroke", color = 1, size = 1, points = pts })), false)
		apply(s, s.drawer, { kind = "shape", shape = "line", color = 1, size = 1, points = pts })
		T.eq(SketchGuess.new(4, { bots = {}, rules = { tools = "bogus" } }, T.Random.new(4)).tools, "all")
	end)

	T.test("a report counts as a skip vote and only the reporter is told", function()
		local s = SketchGuess.new(5, { bots = {} }, T.Random.new(2))
		apply(s, s.drawer, { kind = "choose", index = 1 })
		local others = {}
		for seat = 1, 5 do
			if seat ~= s.drawer then
				table.insert(others, seat)
			end
		end
		apply(s, others[1], { kind = "report" })
		T.ok(SketchGuess.getView(s, others[1]).youReported)
		T.ok(SketchGuess.getView(s, others[1]).youVotedSkip, "a report is a skip vote")
		T.eq((SketchGuess.validateMove(s, others[1], { kind = "report" })), false, "once per drawing")
		local function mentions(seat)
			for _, e in SketchGuess.getView(s, seat).feed do
				if string.find(e.text, "reporting") then
					return true
				end
			end
			return false
		end
		T.ok(mentions(others[1]))
		T.ok(not mentions(others[2]), "nobody else learns who reported")
		T.ok(not mentions(s.drawer))
		-- Voting after reporting doesn't count twice.
		T.eq((SketchGuess.validateMove(s, others[1], { kind = "voteSkip" })), false)
		apply(s, others[2], { kind = "voteSkip" })
		T.eq(s.phase, "draw", "2 of 4")
		apply(s, others[3], { kind = "report" })
		T.eq(s.phase, "reveal", "3 of 4")
	end)

	T.test("a player skipped twice doesn't draw again", function()
		local s = SketchGuess.new(3, { bots = {}, rules = { rounds = 3 } }, T.Random.new(3))
		local target = s.drawer
		local function skipCurrent()
			apply(s, s.drawer, { kind = "choose", index = 1 })
			local voters = {}
			for seat = 1, 3 do
				if seat ~= s.drawer then
					table.insert(voters, seat)
				end
			end
			apply(s, voters[1], { kind = "voteSkip" })
			apply(s, voters[2], { kind = "voteSkip" })
			T.eq(s.phase, "reveal")
		end
		skipCurrent()
		local turns = 0
		while not s.finished and turns < 30 do
			turns += 1
			SketchGuess.onTimeout(s) -- reveal -> next turn
			if s.finished then
				break
			end
			if s.drawer == target then
				T.ok((s.strikes[target] or 0) < 2, "benched players don't get turns")
				skipCurrent()
			else
				apply(s, s.drawer, { kind = "giveUp" })
			end
		end
		T.ok(s.finished)
		T.eq(s.strikes[target], 2)
		T.ok(s.benched[target])
	end)

	T.test("scoring follows the drawing time", function()
		local s = SketchGuess.new(4, { bots = {}, rules = { drawSeconds = 120 } }, T.Random.new(4))
		s.choices = { "cat", "dog", "sun" }
		apply(s, s.drawer, { kind = "choose", index = 1 })
		local g = guesserOf(s)
		apply(s, g, { kind = "guess", text = "cat", shown = "cat" })
		T.eq(s.scores[g], 500, "first guess before any hint")
		for _ = 1, 3 do
			SketchGuess.onTimeout(s)
		end
		local g2 = nil
		for seat = 1, 4 do
			if seat ~= s.drawer and not s.guessed[seat] then
				g2 = seat
				break
			end
		end
		apply(s, g2, { kind = "guess", text = "cat", shown = "cat" })
		T.eq(s.scores[g2], 100 + 100 + 160, "halfway, second")
	end)

	T.test("bots can't guess right on an empty canvas", function()
		local s = SketchGuess.new(3, { botLevel = "hard", bots = { 2, 3 } }, T.Random.new(3))
		apply(s, s.drawer, { kind = "choose", index = 1 })
		s.segment = 3
		local rng = T.Random.new(8)
		for _ = 1, 200 do
			local move = SketchGuess.chooseBotMove(s, 2, rng)
			if move then
				T.ok(not table.find(s.answers, SketchGuess.normalize(move.text)), "guessed a blank canvas")
			end
		end
		-- With a real drawing they do get it sometimes.
		s.pointCount = 400
		local right = 0
		for _ = 1, 200 do
			local move = SketchGuess.chooseBotMove(s, 2, rng)
			if move and table.find(s.answers, SketchGuess.normalize(move.text)) then
				right += 1
			end
		end
		T.ok(right > 0)
	end)

	T.test("the countdown shows the whole drawing, not one hint", function()
		local s = drawing("tree")
		T.eq(SketchGuess.getTimer(s).displaySeconds, 80)
		SketchGuess.onTimeout(s)
		T.eq(SketchGuess.getTimer(s).displaySeconds, 60)
		T.eq(SketchGuess.getTimer(s).seconds, 20)
	end)

	T.test("a solo match with bot drawers finishes and the bots draw", function()
		local seats = {
			{ kind = "player", userId = 1, name = "Gio" },
			{ kind = "bot", name = "Bot Ava" },
			{ kind = "bot", name = "Bot Milo" },
		}
		local m = Match.new("m", SketchGuess, seats, { botLevel = "medium", bots = { 2, 3 } }, T.Random.new(11))
		local steps, mostStrokes = 0, 0
		while not m:isOver() and steps < 5000 do
			steps += 1
			local acted = false
			for _, seat in m:getActiveSeats() do
				if m:isBot(seat) and m:playForSeat(seat) then
					acted = true
				end
			end
			mostStrokes = math.max(mostStrokes, #m.state.strokes)
			if not acted then
				if m.state.phase == "choose" and m.state.drawer == 1 then
					T.ok(m:submitMove(1, { kind = "choose", index = 1 }))
				else
					local timer = m:getTimer()
					T.ok(timer ~= nil)
					T.ok(m:timeout(timer.id))
				end
			end
		end
		T.ok(m.result ~= nil, "match should end")
		T.ok(mostStrokes >= 3, "bots drew something")
	end)

	T.test("a full match with bots and timers ends with a winner", function()
		local seats = {
			{ kind = "player", userId = 1, name = "Gio" },
			{ kind = "bot", name = "Bot Ava" },
			{ kind = "bot", name = "Bot Milo" },
			{ kind = "bot", name = "Bot Juno" },
		}
		local m = Match.new("m", SketchGuess, seats, { botLevel = "hard", bots = { 2, 3, 4 } }, T.Random.new(9))
		local steps = 0
		while not m:isOver() and steps < 2000 do
			steps += 1
			local acted = false
			for _, seat in m:getActiveSeats() do
				if m:isBot(seat) and m:playForSeat(seat) then
					acted = true
				end
			end
			if not acted then
				local timer = m:getTimer()
				if timer then
					T.ok(m:timeout(timer.id))
				else
					-- The human drawer picks a word, then draws a line.
					local state = m.state
					if state.phase == "choose" then
						T.ok(m:submitMove(1, { kind = "choose", index = 1 }))
					end
				end
			end
		end
		T.ok(m.result ~= nil, "match should end")
		T.ok(#m.result.winners >= 1)
		T.eq((m:timeout(0)), false, "stale timers are ignored")
		local scores = m:getScores()
		T.ok(scores[1] ~= nil)
	end)

	T.test("word list has no duplicates and only plain words", function()
		local seen = {}
		for _, list in { Words.easy, Words.medium, Words.hard } do
			for _, entry in list do
				for _, answer in string.split(entry, "|") do
					T.ok(string.match(answer, "^[a-z ]+$") ~= nil, `bad word "{answer}"`)
				end
				local first = string.split(entry, "|")[1]
				T.ok(not seen[first], `duplicate "{first}"`)
				seen[first] = true
			end
		end
	end)
end
