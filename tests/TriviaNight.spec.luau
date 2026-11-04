local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TriviaNight = require(ReplicatedStorage.Shared.Games.TriviaNight)
local Questions = require(ReplicatedStorage.Shared.Games.Data.TriviaQuestions)
local Match = require(ServerScriptService.Server.Core.Match)

return function(T)
	local function apply(s, seat, move)
		local ok, err = TriviaNight.validateMove(s, seat, move)
		assert(ok, err)
		TriviaNight.applyMove(s, seat, move)
	end

	local function wrongChoice(s): number
		return if s.correct == 1 then 2 else 1
	end

	T.test("the answer stays secret until the reveal", function()
		local s = TriviaNight.new(3, nil, T.Random.new(1))
		local view = TriviaNight.getView(s, 1)
		T.eq(view.correct, nil)
		T.eq(#view.answers, 4)
		T.eq(view.answers[s.correct], Questions[s.questions[1]].a[1], "correct answer is in the shuffled list")
		apply(s, 1, { kind = "answer", choice = s.correct })
		T.eq(TriviaNight.getView(s, 2).correct, nil, "still secret after someone answers")
		TriviaNight.onTimeout(s)
		T.eq(TriviaNight.getView(s, 2).correct, s.correct)
	end)

	T.test("faster correct answers score more; wrong scores nothing", function()
		local s = TriviaNight.new(3, nil, T.Random.new(2))
		apply(s, 2, { kind = "answer", choice = s.correct })
		apply(s, 3, { kind = "answer", choice = s.correct })
		apply(s, 1, { kind = "answer", choice = wrongChoice(s) })
		T.eq(s.scores[2], 1000)
		T.eq(s.scores[3], 900)
		T.eq(s.scores[1], 0)
		T.eq(s.phase, "reveal", "everyone answered, so reveal early")
	end)

	T.test("streaks add a bonus", function()
		local s = TriviaNight.new(1, nil, T.Random.new(3))
		apply(s, 1, { kind = "answer", choice = s.correct })
		TriviaNight.onTimeout(s) -- next question
		apply(s, 1, { kind = "answer", choice = s.correct })
		T.eq(s.scores[1], 1000 + 1100)
	end)

	T.test("one answer per question, and junk is rejected", function()
		local s = TriviaNight.new(2, nil, T.Random.new(4))
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
		local m = Match.new("t", TriviaNight, seats, { botLevel = "medium", bots = { 2, 3 } }, T.Random.new(5))
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
