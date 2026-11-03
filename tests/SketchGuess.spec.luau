local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local SketchGuess = require(ReplicatedStorage.Shared.Games.SketchGuess)
local Words = require(ReplicatedStorage.Shared.Games.Data.SketchWords)
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

	T.test("only players draw, and the drawer picks a word", function()
		local s = SketchGuess.new(4, { bots = { 3, 4 } }, T.Random.new(1))
		T.eq(#s.drawers, 2)
		T.eq(s.totalTurns, 6, "two drawers draw three times each")
		T.eq(s.phase, "choose")
		T.eq(#SketchGuess.getActiveSeats(s), 1)
		local view = SketchGuess.getView(s, s.drawer)
		T.eq(#view.choices, 3)
		T.eq(SketchGuess.getView(s, 3).choices, nil, "others don't see the choices")
		apply(s, s.drawer, { kind = "choose", index = 2 })
		T.eq(s.phase, "draw")
		T.eq(#SketchGuess.getActiveSeats(s), 4, "drawer + 3 guessers")
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

	T.test("a bot drawer gives up its turn", function()
		local s = SketchGuess.new(3, { bots = { 2, 3 } }, T.Random.new(1))
		local move = SketchGuess.chooseBotMove(s, s.drawer, T.Random.new(1))
		T.eq(move.kind, "giveUp")
		apply(s, s.drawer, move)
		T.eq(s.phase, "reveal")
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
