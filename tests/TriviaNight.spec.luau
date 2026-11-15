local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TriviaNight = require(ReplicatedStorage.Shared.Games.TriviaNight)
local Questions = require(ServerScriptService.Server.Data.TriviaQuestions)
local Match = require(ServerScriptService.Server.Core.Match)

return function(T)
	local function apply(s, seat, move)
		local ok, err = TriviaNight.validateMove(s, seat, move)
		assert(ok, err)
		TriviaNight.applyMove(s, seat, move)
	end

	-- Most tests look at questions: the category vote is off for them.
	local function newGame(seats: number, rng: any)
		return TriviaNight.new(seats, { questionBank = Questions, rules = { categoryVote = false } }, rng)
	end

	local function wrongChoice(s): number
		return if s.correct == 1 then 2 else 1
	end

	T.test("the answer stays secret until the reveal", function()
		local s = newGame(3, T.Random.new(1))
		local view = TriviaNight.getView(s, 1)
		T.eq(view.correct, nil)
		T.eq(#view.answers, 4)
		T.eq(view.answers[s.correct], Questions[s.questions[1]].a[1], "correct answer is in the shuffled list")
		apply(s, 1, { kind = "answer", choice = s.correct })
		T.eq(TriviaNight.getView(s, 2).correct, nil, "still secret after someone answers")
		TriviaNight.onTimeout(s)
		T.eq(TriviaNight.getView(s, 2).correct, s.correct)
	end)

	T.test("faster correct answers score more (Kahoot formula); wrong scores nothing", function()
		local s = newGame(3, T.Random.new(2))
		apply(s, 2, { kind = "answer", choice = s.correct, elapsed = 3 })
		apply(s, 3, { kind = "answer", choice = s.correct, elapsed = 12 })
		apply(s, 1, { kind = "answer", choice = wrongChoice(s), elapsed = 1 })
		T.eq(s.scores[2], 900, "3 s of 15 = 900")
		T.eq(s.scores[3], 600, "12 s of 15 = 600")
		T.eq(s.scores[1], 0)
		T.eq(s.phase, "reveal", "everyone answered, so reveal early")
		T.eq(TriviaNight.speedPoints(0.3, 15), 1000, "under half a second is the full 1000")
		T.eq(TriviaNight.speedPoints(15, 15), 500)
		T.eq(TriviaNight.speedPoints(99, 15), 500, "never under 500")
		T.eq(TriviaNight.speedPoints(nil, 15), 1000)
	end)

	T.test("solo: a slow right answer scores less than a quick one", function()
		local s = newGame(1, T.Random.new(2))
		apply(s, 1, { kind = "answer", choice = s.correct, elapsed = 13.5 })
		T.eq(s.scores[1], 550)
	end)

	T.test("Match stamps the server's answer time over the client's", function()
		local seats = { { kind = "player", userId = 1, name = "Gio" }, { kind = "player", userId = 2, name = "Ava" } }
		local m = Match.new("t", TriviaNight, seats, { questionBank = Questions, rules = { categoryVote = false } }, T.Random.new(3))
		local fake = 0
		m.phaseElapsed = function()
			return fake
		end
		fake = 7.5
		local move = { kind = "answer", choice = m.state.correct, elapsed = 0 } -- a cheater claims instant
		T.ok(m:submitMove(1, move))
		T.eq(move.elapsed, 7.5)
		T.eq(m.state.scores[1], 750)
		-- No clock known: the client's value is dropped, never trusted.
		m.phaseElapsed = nil
		local move2 = { kind = "answer", choice = m.state.correct, elapsed = 14 }
		T.ok(m:submitMove(2, move2))
		T.eq(move2.elapsed, nil)
	end)

	T.test("everyone below zero still gives a winner", function()
		local s = TriviaNight.new(2, { questionBank = Questions, rules = { wrongPenalty = true, categoryVote = false, questions = 3 } }, T.Random.new(4))
		for _ = 1, 3 do
			apply(s, 1, { kind = "answer", choice = wrongChoice(s) })
			if s.phase == "question" then
				TriviaNight.onTimeout(s) -- seat 2 doesn't answer: 0 for that question
			end
			TriviaNight.onTimeout(s) -- reveal -> next
		end
		T.eq(s.scores[1], -750)
		T.eq(s.scores[2], 0)
		local result = TriviaNight.getResult(s)
		T.eq(result.winners[1], 2)
		local both = TriviaNight.new(2, { questionBank = Questions, rules = { wrongPenalty = true, categoryVote = false, questions = 2 } }, T.Random.new(5))
		for _ = 1, 2 do
			apply(both, 1, { kind = "answer", choice = wrongChoice(both) })
			apply(both, 2, { kind = "answer", choice = wrongChoice(both) })
			TriviaNight.onTimeout(both)
		end
		local r = TriviaNight.getResult(both)
		T.eq(#r.winners, 2, "both on -500 share the win")
		T.eq(r.reason, "Top score: -500 points")
	end)

	T.test("place and gap: you're 2nd, 100 behind", function()
		local s = newGame(3, T.Random.new(6))
		apply(s, 1, { kind = "answer", choice = s.correct, elapsed = 0 })
		apply(s, 2, { kind = "answer", choice = s.correct, elapsed = 3 })
		apply(s, 3, { kind = "answer", choice = wrongChoice(s) })
		local v2 = TriviaNight.getView(s, 2)
		T.eq(v2.place, 2)
		T.eq(v2.ahead, 1)
		T.eq(v2.gap, 100)
		T.eq(TriviaNight.getView(s, 1).ahead, nil)
		T.eq(TriviaNight.getSeatInfo(s)[3], "3rd · 0 pts  +0")
		T.eq(TriviaNight.ordinal(11), "11th")
		T.eq(TriviaNight.ordinal(22), "22nd")
	end)

	T.test("the answers never ship to clients", function()
		local Shared = ReplicatedStorage.Shared
		T.eq(Shared.Games:FindFirstChild("Data") and Shared.Games.Data:FindFirstChild("TriviaQuestions"), nil, "no bank in ReplicatedStorage")
		local preview = TriviaNight.new(2, { rules = { categoryVote = false } }, T.Random.new(1))
		T.eq(preview.bank, TriviaNight.SAMPLE, "without the server's bank only the sample plays")
	end)

	T.test("streaks add a bonus", function()
		local s = newGame(1, T.Random.new(3))
		apply(s, 1, { kind = "answer", choice = s.correct })
		TriviaNight.onTimeout(s) -- next question
		apply(s, 1, { kind = "answer", choice = s.correct })
		T.eq(s.scores[1], 1000 + 1100)
	end)

	T.test("one answer per question, and junk is rejected", function()
		local s = newGame(2, T.Random.new(4))
		apply(s, 1, { kind = "answer", choice = 2 })
		T.eq((TriviaNight.validateMove(s, 1, { kind = "answer", choice = 3 })), false)
		T.eq((TriviaNight.validateMove(s, 2, { kind = "answer", choice = 5 })), false)
		T.eq((TriviaNight.validateMove(s, 2, { kind = "answer", choice = 1.5 })), false)
		T.eq((TriviaNight.validateMove(s, 2, "x")), false)
		T.eq(#TriviaNight.getActiveSeats(s), 1)
	end)

	T.test("a full solo match against bots ends after 10 questions", function()
		local seats = {
			{ kind = "player", userId = 1, name = "Gio" },
			{ kind = "bot", name = "Bot Ava" },
			{ kind = "bot", name = "Bot Milo" },
		}
		local m = Match.new("t", TriviaNight, seats, { questionBank = Questions, botLevel = "medium", bots = { 2, 3 } }, T.Random.new(5))
		local seen = {}
		local steps = 0
		while not m:isOver() and steps < 500 do
			steps += 1
			local state = m.state
			if state.phase == "question" then
				seen[state.questions[state.index]] = true
				for _, seat in m:getActiveSeats() do
					if m:isBot(seat) then
						T.ok(m:playForSeat(seat))
					end
				end
				-- The player answers first question, then goes quiet (the clock runs out).
				if state.index == 1 and m:isSeatActive(1) then
					T.ok(m:submitMove(1, { kind = "answer", choice = 1 }))
				end
			end
			local timer = m:getTimer()
			if timer then
				m:timeout(timer.id)
			end
		end
		T.ok(m.result ~= nil)
		local count = 0
		for _ in seen do
			count += 1
		end
		T.eq(count, 10, "ten different questions")
	end)

	T.test("category vote: everyone picks, the winner sets the next 3 questions", function()
		local s = TriviaNight.new(3, { questionBank = Questions }, T.Random.new(9))
		T.eq(s.phase, "pick")
		T.eq(#s.offer, 4)
		local view = TriviaNight.getView(s, 1)
		T.eq(#view.answers, 4, "the four categories on the answer buttons")
		T.eq((TriviaNight.validateMove(s, 1, { kind = "answer", choice = 1 })), false)
		T.eq((TriviaNight.validateMove(s, 1, { kind = "pick", choice = 5 })), false)
		apply(s, 1, { kind = "pick", choice = 2 })
		apply(s, 2, { kind = "pick", choice = 2 })
		T.eq(TriviaNight.getView(s, 3).votesBySeat[1], 2, "votes are public")
		local winner = s.offer[2]
		apply(s, 3, { kind = "pick", choice = 1 })
		T.eq(s.phase, "question", "everyone voted")
		for slot = 1, 3 do
			T.eq(Questions[s.questions[slot]].c, winner)
		end
		T.eq(TriviaNight.getView(s, 1).category, winner)
		-- Questions stay distinct.
		local seen = {}
		for _, q in s.questions do
			T.ok(not seen[q], "a question twice")
			seen[q] = true
		end
		-- Questions 4, 7 and 10 open with a vote.
		for _ = 1, 3 do
			TriviaNight.onTimeout(s)
			TriviaNight.onTimeout(s)
		end
		T.eq(s.phase, "pick")
		T.eq(s.index, 4)
		TriviaNight.onTimeout(s) -- nobody voted: a random one of them
		T.eq(s.phase, "question")
	end)

	T.test("question bank is well formed", function()
		T.ok(#Questions >= 100)
		local seen = {}
		for i, q in Questions do
			T.ok(type(q.c) == "string" and type(q.q) == "string", `question {i}`)
			T.eq(#q.a, 4, `question {i} needs 4 answers`)
			T.ok(not seen[q.q], `duplicate question {i}`)
			seen[q.q] = true
			local answers = {}
			for _, a in q.a do
				T.ok(not answers[a], `question {i} repeats an answer`)
				answers[a] = true
			end
		end
	end)
end
