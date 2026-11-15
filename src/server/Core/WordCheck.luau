-- The live "is it a word?" check for Word Tiles (like the red/green word in Words With
-- Friends and Scrabble GO): the client sends the words its laid-out tiles make, before
-- Play. Pure, so it's testable; Services/WordCheckService wires it to the remote.
--
-- Request: { id = number, words = { string } }. Reply: { id = id, valid = { boolean } }
-- in the same order, or nil when the request is junk.

local WordCheck = {}

WordCheck.MAX_WORDS = 8 -- one play makes at most 1 main word + 7 crossing words
WordCheck.MAX_LENGTH = 15

function WordCheck.answer(request: any, isWord: (string) -> boolean): any?
	if type(request) ~= "table" or type(request.words) ~= "table" then
		return nil
	end
	local id = request.id
	if type(id) ~= "number" or id ~= id or id % 1 ~= 0 or math.abs(id) > 2 ^ 31 then
		return nil
	end
	local count = #request.words
	if count < 1 or count > WordCheck.MAX_WORDS then
		return nil
	end
	local valid = {}
	for i = 1, count do
		local word = request.words[i]
		if type(word) ~= "string" or #word < 2 or #word > WordCheck.MAX_LENGTH or not string.match(word, "^%a+$") then
			return nil
		end
		valid[i] = isWord(string.lower(word))
	end
	return { id = id, valid = valid }
end

return WordCheck
