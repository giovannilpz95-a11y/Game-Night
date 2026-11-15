local ServerScriptService = game:GetService("ServerScriptService")
local WordCheck = require(ServerScriptService.Server.Core.WordCheck)

return function(T)
	local words = { cat = true, qi = true }
	local function isWord(w: string): boolean
		return words[w] == true
	end

	T.test("answers each word in order, any case", function()
		local reply = WordCheck.answer({ id = 7, words = { "CAT", "xqz", "Qi" } }, isWord)
		T.eq(reply.id, 7)
		T.eq(reply.valid[1], true)
		T.eq(reply.valid[2], false)
		T.eq(reply.valid[3], true)
	end)

	T.test("junk requests get no answer", function()
		for _, bad in {
			"cat",
			{ id = 1 },
			{ id = 0 / 0, words = { "cat" } },
			{ id = 1.5, words = { "cat" } },
			{ id = 1, words = {} },
			{ id = 1, words = { "a" } },
			{ id = 1, words = { "c4t" } },
			{ id = 1, words = { string.rep("a", 16) } },
			{ id = 1, words = { "cat", "cat", "cat", "cat", "cat", "cat", "cat", "cat", "cat" } },
			{ id = 1, words = { 5 } },
		} do
			T.eq(WordCheck.answer(bad, isWord), nil)
		end
	end)
end
