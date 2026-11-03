-- Party Host custom content: word lists for Sketch & Guess and quiz decks for Trivia Night.
-- Pure (no services), shared so the editor can check text before sending it.
--
-- Hosts type plain text. A word list is words separated by commas or new lines. A quiz deck
-- is one question per line, the right answer first, then three wrong ones:
--     What color is the sky? | Blue | Green | Red | Purple
-- The server stores the text the host typed and filters it with TextService every time a
-- match uses it (anything the filter hides is dropped), because others will see it.

local CustomContent = {}

CustomContent.Slots = 3 -- word lists and quiz decks a host can keep, each
CustomContent.MaxNameLength = 24

CustomContent.MinWords = 6
CustomContent.MaxWords = 100
CustomContent.MaxWordLength = 24

CustomContent.MinQuestions = 3
CustomContent.MaxQuestions = 50
CustomContent.MaxQuestionLength = 120
CustomContent.MaxAnswerLength = 40

CustomContent.MaxTextLength = 12000 -- one editor box, before parsing

-- Which kind of content each game can use (GameCatalog `custom` field).
CustomContent.Kinds = {
	words = { name = "Word list", plural = "word lists" },
	quiz = { name = "Quiz deck", plural = "quiz decks" },
}

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
CustomContent.trim = trim

local function squash(s: string): string
	return (string.gsub(trim(s), "%s+", " "))
end

-- A list name: short, one line. Empty means "Word list 1" and so on.
function CustomContent.cleanName(name: any, kind: string, slot: number): string
	local text = if type(name) == "string" then squash(name) else ""
	if text == "" or string.find(text, "#", 1, true) then
		return `{CustomContent.Kinds[kind].name} {slot}`
	end
	if utf8.len(text) == nil then
		return `{CustomContent.Kinds[kind].name} {slot}`
	end
	if #text > CustomContent.MaxNameLength then
		text = string.sub(text, 1, CustomContent.MaxNameLength)
		while utf8.len(text) == nil do
			text = string.sub(text, 1, -2) -- don't cut a character in half
		end
	end
	return text
end

-- Words: letters, spaces, hyphens and apostrophes only, so guessing stays fair (the game
-- compares letters) and nothing like a link or a number sneaks in.
function CustomContent.parseWords(text: any): ({ string }?, string?)
	if type(text) ~= "string" then
		return nil, "Type some words"
	end
	if #text > CustomContent.MaxTextLength then
		return nil, "That's too much text"
	end
	local words, seen = {}, {}
	for piece in string.gmatch(text, "[^,\n]+") do
		local word = string.lower(squash(piece))
		if word ~= "" then
			if #word > CustomContent.MaxWordLength then
				return nil, `"{string.sub(word, 1, 30)}" is too long (most {CustomContent.MaxWordLength} letters)`
			end
			if string.find(word, "[^%a %-']") then
				return nil, `"{word}" can only use letters`
			end
			if not string.find(word, "%a") then
				return nil, "Every word needs letters"
			end
			if not seen[word] then
				seen[word] = true
				table.insert(words, word)
			end
		end
	end
	if #words < CustomContent.MinWords then
		return nil, `Add at least {CustomContent.MinWords} different words`
	end
	if #words > CustomContent.MaxWords then
		return nil, `At most {CustomContent.MaxWords} words in a list`
	end
	return words
end

export type Question = { q: string, a: { string } } -- a[1] is the right answer

function CustomContent.parseDeck(text: any): ({ Question }?, string?)
	if type(text) ~= "string" then
		return nil, "Type some questions"
	end
	if #text > CustomContent.MaxTextLength then
		return nil, "That's too much text"
	end
	local questions = {}
	local lineNumber = 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		lineNumber += 1
		if trim(line) ~= "" then
			local parts = string.split(line, "|")
			if #parts ~= 5 then
				return nil, `Line {lineNumber}: write a question, the right answer, then 3 wrong answers, split by |`
			end
			local q = squash(parts[1])
			if q == "" then
				return nil, `Line {lineNumber}: the question is empty`
			end
			if #q > CustomContent.MaxQuestionLength then
				return nil, `Line {lineNumber}: the question is too long`
			end
			local answers, seen = {}, {}
			for i = 2, 5 do
				local a = squash(parts[i])
				if a == "" then
					return nil, `Line {lineNumber}: an answer is empty`
				end
				if #a > CustomContent.MaxAnswerLength then
					return nil, `Line {lineNumber}: "{string.sub(a, 1, 20)}..." is too long`
				end
				local key = string.lower(a)
				if seen[key] then
					return nil, `Line {lineNumber}: two answers are the same`
				end
				seen[key] = true
				table.insert(answers, a)
			end
			for _, s in { q, table.unpack(answers) } do
				if string.find(s, "#", 1, true) or utf8.len(s) == nil then
					return nil, `Line {lineNumber}: please don't use # or odd characters`
				end
			end
			table.insert(questions, { q = q, a = answers })
		end
	end
	if #questions < CustomContent.MinQuestions then
		return nil, `Add at least {CustomContent.MinQuestions} questions`
	end
	if #questions > CustomContent.MaxQuestions then
		return nil, `At most {CustomContent.MaxQuestions} questions in a deck`
	end
	return questions
end

-- Back to editor text, for showing a saved list again.
function CustomContent.wordsToText(words: { string }): string
	return table.concat(words, ", ")
end

function CustomContent.deckToText(questions: { Question }): string
	local lines = {}
	for _, question in questions do
		table.insert(lines, table.concat({ question.q, table.unpack(question.a) }, " | "))
	end
	return table.concat(lines, "\n")
end

-- Every string in the content, in a fixed order, for the text filter.
function CustomContent.strings(kind: string, content: any): { string }
	local out = {}
	if kind == "words" then
		for _, word in content do
			table.insert(out, word)
		end
	else
		for _, question in content do
			table.insert(out, question.q)
			for _, a in question.a do
				table.insert(out, a)
			end
		end
	end
	return out
end

-- Puts filtered strings back (same order as CustomContent.strings). A string the filter
-- changed at all (hidden words come back as ###) is dropped, and so is any question
-- with a dropped part. Returns the content that's left and how many items were dropped.
function CustomContent.applyFilter(kind: string, content: any, filtered: { string? }): (any, number)
	local function clean(index: number, original: string): boolean
		local result = filtered[index]
		return result ~= nil and result == original
	end
	local out, dropped = {}, 0
	if kind == "words" then
		for i, word in content do
			if clean(i, word) then
				table.insert(out, word)
			else
				dropped += 1
			end
		end
	else
		local index = 0
		for _, question in content do
			local ok = true
			index += 1
			ok = clean(index, question.q) and ok
			for _, a in question.a do
				index += 1
				ok = clean(index, a) and ok
			end
			if ok then
				table.insert(out, { q = question.q, a = table.clone(question.a) })
			else
				dropped += 1
			end
		end
	end
	return out, dropped
end

-- Smallest amount a match needs after filtering.
function CustomContent.minimum(kind: string): number
	return if kind == "words" then CustomContent.MinWords else CustomContent.MinQuestions
end

return CustomContent
