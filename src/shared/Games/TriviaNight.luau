-- Trivia Night: quick-fire multiple choice. Everyone answers each question at once.
--
-- Flow (timed phases, see getTimer):
--   question  QUESTION_SECONDS to answer. Ends early once every seat has answered.
--   reveal    the right answer, who got it and the points, for REVEAL_SECONDS.
--   pick      (the categoryVote rule, on by default) before every ROUND questions,
--             everyone votes for one of up to four categories; the next ROUND questions
--             come from the winner (ties: a random one of them). PICK_SECONDS, or until
--             everyone has voted. Skipped when the deck has only one category.
-- After QUESTIONS questions the highest score wins. A tie goes to whoever took the least
-- total time over their right answers; only a true tie shares the win.
--
-- Questions have 2 to 4 answers (True/False ones keep True first) and a difficulty
-- (d = 1 easy, 2 medium, 3 hard; missing = 1). A game ramps up: the first third of the
-- questions come easy, the middle medium, the last third hard, as far as the bank
-- allows. Bots get harder questions wrong more often.
--
-- Scoring (Kahoot style): a correct answer earns 1000 x (1 - (time taken / timer) / 2),
-- so 500 to 1000 by its own speed (under half a second is the full 1000). The answer
-- time is stamped by the server (elapsedField), so a client can't fake it.
-- A streak of correct answers adds STREAK_BONUS per question in the streak (capped).
--
-- The correct answer is never in a view until the reveal, and the question bank is
-- server-only: the server passes it in options.questionBank (ServerScriptService Data),
-- so clients never get the answers. Without it (picker previews, tests) a tiny sample
-- bank is used.
--
-- House rules (options.rules): questions = 5..20, answerSeconds = 10 | 15 | 25,
-- speed (default on: earlier right answers score more; off: every right answer is 1000),
-- streaks (default on: the streak bonus), wrongPenalty (a wrong answer costs 250 points),
-- categoryVote = true | false.
-- options.customQuestions: a Party Host's quiz deck (already filtered by the server),
-- { { c = category, q = question, a = { right, wrong, wrong, wrong } } }. Used instead of
-- our bank when set.
--
-- Scores in views are held back while a question is open (each seat's points for it
-- show at the reveal), so nobody learns who got it right from the seat list.
--
-- Moves: { kind = "answer", choice = 1..#answers }   { kind = "pick", choice = 1..#offer }
-- (`elapsed` on an answer is set by the server; anything a client sends is overwritten.)

local GameModule = require(script.Parent.Parent.GameModule)

-- Only for previews and tests: real matches always get the server's bank.
local SAMPLE = {
	{ c = "Science", q = "What is H2O better known as?", a = { "Water", "Salt", "Hydrogen", "Sugar" } },
	{ c = "Animals", q = "How many legs does a spider have?", a = { "8", "6", "10", "4" } },
	{ c = "Geography", q = "Which is the largest ocean?", a = { "Pacific", "Atlantic", "Indian", "Arctic" } },
	{ c = "Food", q = "Which fruit is dried to make raisins?", a = { "Grapes", "Plums", "Apples", "Figs" } },
	{ c = "Sports", q = "How many players does a soccer team have on the field?", a = { "11", "9", "7", "12" } },
	{ c = "Music", q = "How many strings does a standard guitar have?", a = { "6", "4", "5", "8" } },
}

local TriviaNight = {}

TriviaNight.id = "TriviaNight"
TriviaNight.minSeats = 1
TriviaNight.maxSeats = 8

local QUESTIONS = 10
local QUESTION_SECONDS = 15
local REVEAL_SECONDS = 5
local STREAK_BONUS = 100
local MAX_STREAK_BONUS = 300
local PICK_SECONDS = 8
local ROUND = 3 -- questions per category vote

TriviaNight.questionCount = QUESTIONS
TriviaNight.elapsedField = "elapsed"
-- MatchService remembers the questions each server asked lately and passes them back as
-- options.recent (a set of bank numbers), so regulars don't get repeats.
TriviaNight.recentField = "questions"
TriviaNight.SAMPLE = SAMPLE

-- Kahoot's formula: 1000 for an instant answer, 500 for one on the buzzer.
function TriviaNight.speedPoints(elapsed: number?, seconds: number): number
	local t = if type(elapsed) == "number" and elapsed == elapsed then elapsed else 0
	if t < 0.5 then
		return 1000
	end
	local share = math.clamp(t / math.max(seconds, 1), 0, 1)
	return math.floor(1000 * (1 - share / 2) + 0.5)
end

local BOT_ACCURACY = { easy = 0.4, medium = 0.65, hard = 0.85 }
local BOT_HARDER = 0.12 -- bots' accuracy drops this much per difficulty step

local function difficultyOf(q: any): number
	local d = q and q.d
	return if type(d) == "number" and d >= 1 and d <= 3 then math.floor(d) else 1
end
TriviaNight.difficultyOf = difficultyOf

-- The difficulty question `slot` of `total` aims for: easy, then medium, then hard.
local function targetDifficulty(slot: number, total: number): number
	if total <= 2 then
		return 1
	end
	return math.clamp(math.floor((slot - 1) * 3 / total) + 1, 1, 3)
end
TriviaNight.targetDifficulty = targetDifficulty

-- Take one of `candidates` (bank indexes) for `slot`, nearest the slot's difficulty.
local function takeFor(bank: { any }, candidates: { number }, slot: number, total: number, rng: Random): number?
	if #candidates == 0 then
		return nil
	end
	local want = targetDifficulty(slot, total)
	local best, bestGap = {}, math.huge
	for i, index in candidates do
		local gap = math.abs(difficultyOf(bank[index]) - want)
		if gap < bestGap then
			best, bestGap = { i }, gap
		elseif gap == bestGap then
			table.insert(best, i)
		end
	end
	local at = best[rng:NextInteger(1, #best)]
	return table.remove(candidates, at)
end

function TriviaNight.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= 1 and seatCount <= TriviaNight.maxSeats, "Trivia Night needs 1-8 seats")
	local random = rng or Random.new()
	local rules = (options and options.rules) or {}
	local count = if type(rules.questions) == "number" then math.clamp(math.floor(rules.questions), 1, 30) else QUESTIONS
	local seconds = if type(rules.answerSeconds) == "number" then math.clamp(rules.answerSeconds, 5, 60) else QUESTION_SECONDS
	local bank = SAMPLE
	if options and type(options.questionBank) == "table" and #options.questionBank > 0 then
		bank = options.questionBank
	end
	if options and type(options.customQuestions) == "table" and #options.customQuestions > 0 then
		bank = options.customQuestions
	end
	-- Pick distinct questions, easy first and harder later, skipping ones this server
	-- asked lately while there are plenty of others.
	local recent = if options and type(options.recent) == "table" and bank ~= SAMPLE then options.recent else {}
	local pool = {}
	for i = 1, #bank do
		if not recent[i] then
			table.insert(pool, i)
		end
	end
	if #pool < count * 3 then
		pool = {}
		for i = 1, #bank do
			pool[i] = i
		end
	end
	local total = math.min(count, #pool)
	local picked = {}
	for slot = 1, total do
		table.insert(picked, takeFor(bank, pool, slot, total, random) :: number)
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
		rightTime = table.create(seatCount, 0), -- seconds spent on right answers (tie-break)
		streaks = table.create(seatCount, 0),
		lastPoints = {},
		finished = false,
		categoryVote = rules.categoryVote ~= false,
		offer = nil, -- the categories up for the vote
		votes = {}, -- [seat] = position in offer
		pickedCategory = nil, -- the category the last vote chose
		speed = rules.speed ~= false,
		streakBonus = rules.streaks ~= false,
		wrongPenalty = rules.wrongPenalty == true,
	}
	TriviaNight._nextQuestion(state)
	return state
end

local function categoryOf(q: any): string
	return if type(q.c) == "string" and q.c ~= "" then q.c else "Mixed"
end

-- Categories that still have questions nobody has seen this game, in bank order.
local function openCategories(state): { string }
	local used = {}
	for i = 1, state.index - 1 do
		used[state.questions[i]] = true
	end
	local out, seen = {}, {}
	for i, q in state.bank do
		local c = categoryOf(q)
		if not used[i] and not seen[c] then
			seen[c] = true
			table.insert(out, c)
		end
	end
	return out
end

local function isTrueFalse(q: any): boolean
	local a = q.a
	return #a == 2 and ((a[1] == "True" and a[2] == "False") or (a[1] == "False" and a[2] == "True"))
end
TriviaNight.isTrueFalse = isTrueFalse

local function startQuestion(state)
	state.phase = "question"
	local q = state.bank[state.questions[state.index]]
	local n = math.clamp(#q.a, 2, 4)
	local order = {}
	for i = 1, n do
		order[i] = i
	end
	if isTrueFalse(q) then
		-- True on the left, always.
		order = if q.a[1] == "True" then { 1, 2 } else { 2, 1 }
	else
		for i = n, 2, -1 do
			local j = state.rng:NextInteger(1, i)
			order[i], order[j] = order[j], order[i]
		end
	end
	state.order = order
	state.correct = table.find(order, 1) :: number
	state.answers = {}
	state.answeredCount = 0
	state.correctCount = 0
	state.lastPoints = {}
end

-- The vote is in: the next ROUND questions come from `category` (as many as it has left).
local function useCategory(state, category: string)
	state.pickedCategory = category
	local used = {}
	for i = 1, state.index - 1 do
		used[state.questions[i]] = true
	end
	local fresh = {}
	for i, q in state.bank do
		if not used[i] and categoryOf(q) == category then
			table.insert(fresh, i)
		end
	end
	for slot = state.index, math.min(#state.questions, state.index + ROUND - 1) do
		if #fresh == 0 then
			break
		end
		local pick = takeFor(state.bank, fresh, slot, #state.questions, state.rng) :: number
		-- Swap it in, keeping every question in the game distinct.
		local at = table.find(state.questions, pick)
		if at and at > slot then
			state.questions[at] = state.questions[slot]
		elseif at then
			continue
		end
		state.questions[slot] = pick
	end
end

local function resolvePick(state)
	local tally = {}
	for _, choice in state.votes do
		tally[choice] = (tally[choice] or 0) + 1
	end
	local best, top = 0, {}
	for choice = 1, #state.offer do
		local n = tally[choice] or 0
		if n > best then
			best, top = n, { choice }
		elseif n == best then
			table.insert(top, choice)
		end
	end
	local choice = top[state.rng:NextInteger(1, #top)]
	useCategory(state, state.offer[choice])
	state.offer = nil
	state.votes = {}
	state.timerId += 1
	startQuestion(state)
end

function TriviaNight._nextQuestion(state)
	state.index += 1
	state.timerId += 1
	if state.index > #state.questions then
		state.phase = "done"
		state.finished = true
		return
	end
	-- A vote opens every ROUND questions, but not for a single last question.
	if state.categoryVote and (state.index - 1) % ROUND == 0 and #state.questions - state.index >= 1 then
		local open = openCategories(state)
		if #open >= 2 then
			-- Up to four of them, at random.
			local offer = {}
			while #offer < 4 and #open > 0 do
				table.insert(offer, table.remove(open, state.rng:NextInteger(1, #open)))
			end
			state.phase = "pick"
			state.offer = offer
			state.votes = {}
			return
		end
	end
	startQuestion(state)
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
	if state.phase == "pick" then
		local seats = {}
		for seat = 1, state.seatCount do
			if state.votes[seat] == nil then
				table.insert(seats, seat)
			end
		end
		return seats
	end
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
	if state.phase == "pick" then
		local moves = {}
		if state.votes[seat] == nil then
			for choice = 1, #state.offer do
				table.insert(moves, { kind = "pick", choice = choice })
			end
		end
		return moves
	end
	if state.phase ~= "question" or state.answers[seat] ~= nil then
		return {}
	end
	local moves = {}
	for choice = 1, #state.order do
		table.insert(moves, { kind = "answer", choice = choice })
	end
	return moves
end

function TriviaNight.validateMove(state, seat: number, move: any): (boolean, string?)
	if state.phase == "pick" then
		if type(move) ~= "table" or move.kind ~= "pick" then
			return false, "Vote for a category"
		end
		if state.votes[seat] ~= nil then
			return false, "You already voted"
		end
		local choice = move.choice
		if type(choice) ~= "number" or choice % 1 ~= 0 or choice < 1 or choice > #state.offer then
			return false, "Pick a category"
		end
		return true
	end
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
	if type(choice) ~= "number" or choice % 1 ~= 0 or choice < 1 or choice > #state.order then
		return false, "Pick an answer"
	end
	return true
end

function TriviaNight.applyMove(state, seat: number, move: any)
	if state.phase == "pick" then
		state.votes[seat] = move.choice
		local all = true
		for s = 1, state.seatCount do
			if state.votes[s] == nil then
				all = false
				break
			end
		end
		if all then
			resolvePick(state)
		end
		return
	end
	state.answers[seat] = move.choice
	state.answeredCount += 1
	if move.choice == state.correct then
		state.correctCount += 1
		state.streaks[seat] += 1
		GameModule.addStat(state, seat, "correct")
		GameModule.maxStat(state, seat, "streak", state.streaks[seat])
		local points = if state.speed == false then 1000 else TriviaNight.speedPoints(move.elapsed, state.answerSeconds)
		if state.streakBonus ~= false then
			points += math.min(MAX_STREAK_BONUS, STREAK_BONUS * (state.streaks[seat] - 1))
		end
		state.scores[seat] += points
		state.lastPoints[seat] = points
		if type(move.elapsed) == "number" then
			state.rightTime[seat] += math.max(0, move.elapsed)
		end
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
	elseif state.phase == "pick" then
		return { id = state.timerId, seconds = PICK_SECONDS }
	elseif state.phase == "reveal" then
		return { id = state.timerId, seconds = REVEAL_SECONDS }
	end
	return nil
end

function TriviaNight.onTimeout(state)
	if state.phase == "pick" then
		resolvePick(state)
	elseif state.phase == "question" then
		reveal(state)
	elseif state.phase == "reveal" then
		TriviaNight._nextQuestion(state)
	end
end

function TriviaNight.getResult(state): GameModule.Result?
	if not state.finished then
		return nil
	end
	local best = -math.huge
	for seat = 1, state.seatCount do
		best = math.max(best, state.scores[seat])
	end
	-- Everyone by score (then speed, then seat), for the result card.
	local ranking = {}
	for seat = 1, state.seatCount do
		ranking[seat] = seat
	end
	table.sort(ranking, function(a, b)
		if state.scores[a] ~= state.scores[b] then
			return state.scores[a] > state.scores[b]
		elseif state.rightTime[a] ~= state.rightTime[b] then
			return state.rightTime[a] < state.rightTime[b]
		end
		return a < b
	end)
	local tied = {}
	for seat = 1, state.seatCount do
		if state.scores[seat] == best then
			table.insert(tied, seat)
		end
	end
	if #tied == 1 then
		return { winners = tied, isDraw = false, reason = `Top score: {best} points`, ranking = ranking }
	end
	-- A tie on points: the quickest over their right answers wins.
	local fastest = math.huge
	for _, seat in tied do
		fastest = math.min(fastest, state.rightTime[seat])
	end
	local winners = {}
	for _, seat in tied do
		if state.rightTime[seat] == fastest then
			table.insert(winners, seat)
		end
	end
	if #winners < #tied then
		return { winners = winners, isDraw = false, reason = `Tied on {best} points: won on speed`, ranking = ranking }
	end
	return { winners = winners, isDraw = false, reason = `Top score: {best} points`, ranking = ranking }
end

function TriviaNight.getScores(state): { [number]: number }
	return table.clone(state.scores)
end

local function ordinal(n: number): string
	local tens = n % 100
	local suffix = if tens >= 11 and tens <= 13 then "th" elseif n % 10 == 1 then "st" elseif n % 10 == 2 then "nd" elseif n % 10 == 3 then "rd" else "th"
	return `{n}{suffix}`
end
TriviaNight.ordinal = ordinal

-- The score everyone may see: while a question is open, without its points yet.
local function shownScore(state, seat: number): number
	if state.phase == "question" then
		return state.scores[seat] - (state.lastPoints[seat] or 0)
	end
	return state.scores[seat]
end

-- Place on the scoreboard (ties share a place: 1st, 1st, 3rd).
local function placeOf(state, seat: number): number
	local place = 1
	local mine = shownScore(state, seat)
	for other = 1, state.seatCount do
		if shownScore(state, other) > mine then
			place += 1
		end
	end
	return place
end

function TriviaNight.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		local tag = ""
		if state.phase == "pick" and state.votes[seat] ~= nil then
			tag = "  ✓ voted"
		elseif state.phase == "question" and state.answers[seat] ~= nil then
			tag = "  ✓ answered"
		elseif state.phase == "reveal" then
			local got = state.lastPoints[seat] or 0
			tag = if state.answers[seat] == state.correct then `  +{got}` elseif got < 0 then `  {got}` else "  +0"
		end
		-- Your place shows from the first reveal on (before that everyone is tied at 0).
		local ranked = state.seatCount > 1 and (state.index > 1 or state.phase == "reveal")
		local place = if ranked then `{ordinal(placeOf(state, seat))} · ` else ""
		info[seat] = `{place}{shownScore(state, seat)} pts{tag}`
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
		scores = {},
		streak = if seat then state.streaks[seat] else 0,
		timerSeconds = (TriviaNight.getTimer(state) or { seconds = 0 }).seconds, -- this phase's length
		answeredCount = state.answeredCount,
	}
	for s = 1, state.seatCount do
		view.scores[s] = shownScore(state, s)
	end
	if state.phase == "done" then
		view.status = "Final scores"
		return view
	end
	if state.phase == "pick" then
		-- The vote reuses the four answer buttons: one category each. Votes are public.
		view.category = "Category vote"
		view.question = `Vote for the next {math.min(ROUND, view.total - view.number + 1)} questions!`
		view.answers = table.clone(state.offer)
		view.yourAnswer = if seat then state.votes[seat] else nil
		view.votesBySeat = table.clone(state.votes)
		local voted = {}
		for s = 1, state.seatCount do
			if state.votes[s] ~= nil then
				table.insert(voted, s)
			end
		end
		view.answeredSeats = voted
		view.answeredCount = #voted
		view.status = "Pick a category"
		return view
	end
	local q = currentQuestion(state)
	view.category = q.c
	view.pickedCategory = state.pickedCategory
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
	if seat and state.seatCount > 1 then
		-- "You're 2nd, 300 behind Ava": your place and the gap to the seat just ahead.
		view.place = placeOf(state, seat)
		local ahead, gap = nil, math.huge
		for other = 1, state.seatCount do
			local diff = shownScore(state, other) - shownScore(state, seat)
			if diff > 0 and diff < gap then
				ahead, gap = other, diff
			end
		end
		view.ahead = ahead
		view.gap = if ahead then gap else nil
	end
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
	if state.phase == "pick" then
		return rng:NextNumber(1.5, 5)
	end
	-- Scaled to the answer clock, and always in before it runs out.
	local seconds = state.answerSeconds
	local fastest = (if state.botLevel == "hard" then 2 elseif state.botLevel == "medium" then 3 else 4) * seconds / 15
	return rng:NextNumber(fastest, math.max(fastest + 0.5, math.min(seconds * 0.73, seconds - 1)))
end

function TriviaNight.chooseBotMove(state, seat: number, rng: Random): any?
	if state.phase == "pick" then
		if state.votes[seat] ~= nil then
			return nil
		end
		return { kind = "pick", choice = rng:NextInteger(1, #state.offer) }
	end
	if state.phase ~= "question" or state.answers[seat] ~= nil then
		return nil
	end
	local d = difficultyOf(currentQuestion(state))
	local accuracy = (BOT_ACCURACY[state.botLevel] or 0.65) - (d - 1) * BOT_HARDER
	if rng:NextNumber() < accuracy then
		return { kind = "answer", choice = state.correct }
	end
	local wrong = {}
	for choice = 1, #state.order do
		if choice ~= state.correct then
			table.insert(wrong, choice)
		end
	end
	return { kind = "answer", choice = wrong[rng:NextInteger(1, #wrong)] }
end

return TriviaNight
