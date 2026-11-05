-- Trivia Night: quick-fire multiple choice. Everyone answers each question at once.
--
-- Flow (timed phases, see getTimer):
--   question  QUESTION_SECONDS to answer. Ends early once every seat has answered.
--   reveal    the right answer, who got it and the points, for REVEAL_SECONDS.
-- After QUESTIONS questions the highest score wins (ties share the win).
--
-- Scoring: the first correct answer earns 1000, each later one 100 less (never under
-- 500). Answer order is decided by the server, so it can't be faked by a client.
-- A streak of correct answers adds STREAK_BONUS per question in the streak (capped).
--
-- The correct answer is never in a view until the reveal.
--
-- House rules (options.rules): questions = 5..20, answerSeconds = 10 | 15 | 25,
-- speed (default on: earlier right answers score more; off: every right answer is 1000),
-- streaks (default on: the streak bonus), wrongPenalty (a wrong answer costs 250 points).
-- options.customQuestions: a Party Host's quiz deck (already filtered by the server),
-- { { c = category, q = question, a = { right, wrong, wrong, wrong } } }. Used instead of
-- our bank when set.
--
-- Move: { kind = "answer", choice = 1..4 }

local GameModule = require(script.Parent.Parent.GameModule)
local Questions = require(script.Parent.Data.TriviaQuestions)

local TriviaNight = {}

TriviaNight.id = "TriviaNight"
TriviaNight.minSeats = 1
TriviaNight.maxSeats = 8

local QUESTIONS = 10
local QUESTION_SECONDS = 15
local REVEAL_SECONDS = 5
local STREAK_BONUS = 100
local MAX_STREAK_BONUS = 300

TriviaNight.questionCount = QUESTIONS

local BOT_ACCURACY = { easy = 0.4, medium = 0.65, hard = 0.85 }

function TriviaNight.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= 1 and seatCount <= TriviaNight.maxSeats, "Trivia Night needs 1-8 seats")
	local random = rng or Random.new()
	local rules = (options and options.rules) or {}
	local count = if type(rules.questions) == "number" then math.clamp(math.floor(rules.questions), 1, 30) else QUESTIONS
	local seconds = if type(rules.answerSeconds) == "number" then math.clamp(rules.answerSeconds, 5, 60) else QUESTION_SECONDS
	local bank = Questions
	if options and type(options.customQuestions) == "table" and #options.customQuestions > 0 then
		bank = options.customQuestions
	end
	-- Pick distinct questions.
	local pool = {}
	for i = 1, #bank do
		pool[i] = i
	end
	local picked = {}
	for _ = 1, math.min(count, #pool) do
		table.insert(picked, table.remove(pool, random:NextInteger(1, #pool)) :: number)
	end
	local state = {
		seatCount = seatCount,
		rng = random,
		botLevel = (options and options.botLevel) or "medium",
		bank = bank,
		questions = picked,
		answerSeconds = seconds,
		index = 0,
		phase = "question",
		timerId = 0,
		order = {}, -- order[displayed position] = position in the bank's answer list
		correct = 0, -- displayed position of the right answer
		answers = {}, -- [seat] = chosen displayed position
		answeredCount = 0,
		correctCount = 0,
		scores = table.create(seatCount, 0),
		streaks = table.create(seatCount, 0),
		lastPoints = {},
		finished = false,
		speed = rules.speed ~= false,
		streakBonus = rules.streaks ~= false,
		wrongPenalty = rules.wrongPenalty == true,
	}
	TriviaNight._nextQuestion(state)
	return state
end

function TriviaNight._nextQuestion(state)
	state.index += 1
	state.timerId += 1
	if state.index > #state.questions then
		state.phase = "done"
		state.finished = true
		return
	end
	state.phase = "question"
	local order = { 1, 2, 3, 4 }
	for i = 4, 2, -1 do
		local j = state.rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	state.order = order
	state.correct = table.find(order, 1) :: number
	state.answers = {}
	state.answeredCount = 0
	state.correctCount = 0
	state.lastPoints = {}
end

local function currentQuestion(state)
	return state.bank[state.questions[state.index]]
end

local function reveal(state)
	state.phase = "reveal"
	state.timerId += 1
	for seat = 1, state.seatCount do
		if state.answers[seat] ~= state.correct then
			state.streaks[seat] = 0
			-- A wrong answer under the penalty rule keeps its -250; no answer scores 0.
			if not (state.wrongPenalty and state.answers[seat] ~= nil) then
				state.lastPoints[seat] = 0
			end
		end
	end
end

function TriviaNight.getActiveSeats(state): { number }
	if state.phase ~= "question" then
		return {}
	end
	local seats = {}
	for seat = 1, state.seatCount do
		if state.answers[seat] == nil then
			table.insert(seats, seat)
		end
	end
	return seats
end

function TriviaNight.getLegalMoves(state, seat: number): { any }
	if state.phase ~= "question" or state.answers[seat] ~= nil then
		return {}
	end
	return {
		{ kind = "answer", choice = 1 },
		{ kind = "answer", choice = 2 },
		{ kind = "answer", choice = 3 },
		{ kind = "answer", choice = 4 },
	}
end

function TriviaNight.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.phase ~= "question" then
		return false, "Wait for the next question"
	end
	if state.answers[seat] ~= nil then
		return false, "You already answered"
	end
	if type(move) ~= "table" or move.kind ~= "answer" then
		return false, "Bad move"
	end
	local choice = move.choice
	if type(choice) ~= "number" or choice % 1 ~= 0 or choice < 1 or choice > 4 then
		return false, "Pick an answer"
	end
	return true
end

function TriviaNight.applyMove(state, seat: number, move: any)
	state.answers[seat] = move.choice
	state.answeredCount += 1
	if move.choice == state.correct then
		state.correctCount += 1
		state.streaks[seat] += 1
		GameModule.addStat(state, seat, "correct")
		GameModule.maxStat(state, seat, "streak", state.streaks[seat])
		local points = if state.speed == false then 1000 else math.max(500, 1000 - 100 * (state.correctCount - 1))
		if state.streakBonus ~= false then
			points += math.min(MAX_STREAK_BONUS, STREAK_BONUS * (state.streaks[seat] - 1))
		end
		state.scores[seat] += points
		state.lastPoints[seat] = points
	elseif state.wrongPenalty then
		state.streaks[seat] = 0
		state.scores[seat] -= 250
		state.lastPoints[seat] = -250
	end
	if state.answeredCount >= state.seatCount then
		reveal(state)
	end
end

function TriviaNight.getTimer(state): { id: number, seconds: number }?
	if state.phase == "question" then
		return { id = state.timerId, seconds = state.answerSeconds }
	elseif state.phase == "reveal" then
		return { id = state.timerId, seconds = REVEAL_SECONDS }
	end
	return nil
end

function TriviaNight.onTimeout(state)
	if state.phase == "question" then
		reveal(state)
	elseif state.phase == "reveal" then
		TriviaNight._nextQuestion(state)
	end
end

function TriviaNight.getResult(state): GameModule.Result?
	if not state.finished then
		return nil
	end
	local best = -1
	for seat = 1, state.seatCount do
		best = math.max(best, state.scores[seat])
	end
	local winners = {}
	for seat = 1, state.seatCount do
		if state.scores[seat] == best then
			table.insert(winners, seat)
		end
	end
	return { winners = winners, isDraw = false, reason = `Top score: {best} points` }
end

function TriviaNight.getScores(state): { [number]: number }
	return table.clone(state.scores)
end

function TriviaNight.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		local tag = ""
		if state.phase == "question" and state.answers[seat] ~= nil then
			tag = "  ✓ answered"
		elseif state.phase == "reveal" then
			local got = state.lastPoints[seat] or 0
			tag = if state.answers[seat] == state.correct then `  +{got}` elseif got < 0 then `  {got}` else "  +0"
		end
		info[seat] = `{state.scores[seat]} pts{tag}`
	end
	return info
end

-- How the four answers look everywhere (2D buttons and the screen over the table), so
-- "B" is the same color in both.
TriviaNight.ANSWER_LETTERS = { "A", "B", "C", "D" }
TriviaNight.ANSWER_COLORS = {
	Color3.fromRGB(240, 110, 100), -- coral
	Color3.fromRGB(245, 190, 70), -- honey
	Color3.fromRGB(60, 190, 170), -- teal
	Color3.fromRGB(150, 110, 230), -- violet
}

function TriviaNight.getView(state, seat: number?)
	local view: any = {
		phase = state.phase,
		number = math.min(state.index, #state.questions),
		total = #state.questions,
		scores = table.clone(state.scores),
		streak = if seat then state.streaks[seat] else 0,
		answeredCount = state.answeredCount,
	}
	if state.phase == "done" then
		view.status = "Final scores"
		return view
	end
	local q = currentQuestion(state)
	view.category = q.c
	view.question = q.q
	local answers = {}
	for position, original in state.order do
		answers[position] = q.a[original]
	end
	view.answers = answers
	view.yourAnswer = if seat then state.answers[seat] else nil
	-- Who has locked in (not what they picked), so the buzzers at the table can light up.
	local answeredSeats = {}
	for s = 1, state.seatCount do
		if state.answers[s] ~= nil then
			table.insert(answeredSeats, s)
		end
	end
	view.answeredSeats = answeredSeats
	if state.phase == "reveal" then
		view.correct = state.correct
		view.answersBySeat = table.clone(state.answers)
		view.lastPoints = table.clone(state.lastPoints)
		view.status = `Question {view.number} of {view.total}: the answer is in!`
	else
		view.status = `Question {view.number} of {view.total}`
	end
	return view
end

-- Bots answer after a few seconds, right as often as their level allows.
function TriviaNight.getBotDelay(state, _seat: number, rng: Random): number
	local fastest = if state.botLevel == "hard" then 2 elseif state.botLevel == "medium" then 3 else 4
	return rng:NextNumber(fastest, 11)
end

function TriviaNight.chooseBotMove(state, seat: number, rng: Random): any?
	if state.phase ~= "question" or state.answers[seat] ~= nil then
		return nil
	end
	if rng:NextNumber() < (BOT_ACCURACY[state.botLevel] or 0.65) then
		return { kind = "answer", choice = state.correct }
	end
	local wrong = {}
	for choice = 1, 4 do
		if choice ~= state.correct then
			table.insert(wrong, choice)
		end
	end
	return { kind = "answer", choice = wrong[rng:NextInteger(1, #wrong)] }
end

return TriviaNight
