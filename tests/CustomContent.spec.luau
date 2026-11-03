local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomContent = require(ReplicatedStorage.Shared.CustomContent)

return function(T)
	T.test("word lists split on commas and new lines, trimmed, lowercased, deduped", function()
		local words = CustomContent.parseWords("Apple, banana\n  ice cream ,cat,dog, APPLE,\n\nfrog, sun") :: { string }
		T.ok(words ~= nil)
		T.eq(#words, 7)
		T.eq(words[1], "apple")
		T.eq(words[3], "ice cream")
	end)

	T.test("word lists need enough words and letters only", function()
		T.eq((CustomContent.parseWords("a, b, c")), nil)
		local words, err = CustomContent.parseWords("one, two, three, four, five, s1x")
		T.eq(words, nil)
		T.ok(string.find(err :: string, "letters") ~= nil)
		T.eq((CustomContent.parseWords("www.site.com, a, b, c, d, e")), nil)
		T.eq((CustomContent.parseWords(42)), nil)
		T.eq((CustomContent.parseWords(string.rep("a", 30) .. ", b, c, d, e, f")), nil)
	end)

	T.test("too many words is refused", function()
		local parts = {}
		for i = 1, CustomContent.MaxWords + 1 do
			local word = ""
			local n = i
			repeat
				word ..= string.char(97 + n % 26)
				n //= 26
			until n == 0
			table.insert(parts, word)
		end
		T.eq((CustomContent.parseWords(table.concat(parts, ","))), nil)
	end)

	local deckText = table.concat({
		"What color is the sky? | Blue | Green | Red | Purple",
		"",
		"How many legs does a spider have? | 8 | 6 | 4 | 10",
		"  Which is a fruit?|Apple|Rock|Shoe|Cloud  ",
	}, "\n")

	T.test("quiz decks: one question per line, right answer first", function()
		local questions = CustomContent.parseDeck(deckText) :: any
		T.ok(questions ~= nil)
		T.eq(#questions, 3)
		T.eq(questions[1].q, "What color is the sky?")
		T.eq(questions[1].a[1], "Blue")
		T.eq(#questions[3].a, 4)
		T.eq(questions[3].a[4], "Cloud")
	end)

	T.test("quiz deck mistakes name the line", function()
		local _, err = CustomContent.parseDeck("Q1? | a | b | c | d\nQ2? | a | b | c\nQ3? | a | b | c | d")
		T.ok(string.find(err :: string, "Line 2") ~= nil, err)
		_, err = CustomContent.parseDeck("Q1? | a | a | c | d\nQ2? | a | b | c | d\nQ3? | a | b | c | d")
		T.ok(string.find(err :: string, "same") ~= nil, err)
		_, err = CustomContent.parseDeck("Q1? | a | b | c | d")
		T.ok(string.find(err :: string, "at least") ~= nil, err)
		_, err = CustomContent.parseDeck("Q1 #? | a | b | c | d\nQ2? | a | b | c | d\nQ3? | a | b | c | d")
		T.ok(err ~= nil)
	end)

	T.test("saved content turns back into editor text", function()
		local questions = CustomContent.parseDeck(deckText) :: any
		local again = CustomContent.parseDeck(CustomContent.deckToText(questions)) :: any
		T.eq(#again, 3)
		T.eq(again[2].a[1], "8")
		local words = CustomContent.parseWords("ant, bee, cat, dog, elk, fox") :: { string }
		T.eq(#(CustomContent.parseWords(CustomContent.wordsToText(words)) :: { string }), 6)
	end)

	T.test("names are cleaned and default to the slot", function()
		T.eq(CustomContent.cleanName("  My   Words ", "words", 1), "My Words")
		T.eq(CustomContent.cleanName("", "quiz", 2), "Quiz deck 2")
		T.eq(CustomContent.cleanName(nil, "words", 3), "Word list 3")
		T.eq(#CustomContent.cleanName(string.rep("x", 80), "words", 1), CustomContent.MaxNameLength)
	end)

	T.test("anything the chat filter touched is dropped", function()
		local words = { "apple", "banana", "cherry" }
		local kept, dropped = CustomContent.applyFilter("words", words, { "apple", "######", nil })
		T.eq(#kept, 1)
		T.eq(kept[1], "apple")
		T.eq(dropped, 2)

		local questions = CustomContent.parseDeck(deckText) :: any
		local strings = CustomContent.strings("quiz", questions)
		T.eq(#strings, 15)
		local filtered = table.clone(strings)
		filtered[7] = "####" -- question 2's text
		local keptQ, droppedQ = CustomContent.applyFilter("quiz", questions, filtered)
		T.eq(#keptQ, 2)
		T.eq(droppedQ, 1)
		T.eq(keptQ[2].q, "Which is a fruit?")
	end)
end
