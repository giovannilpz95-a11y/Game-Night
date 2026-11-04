--[[
	A compact letter trie for word games: "is this a word?" and walking letter by letter
	(the Word Tiles bot uses that to find every word it can play). Pure Luau, no services.

	Nodes live in three buffers so a dictionary of ~170,000 words takes about 3.5 MB.
	Node 1 is the root; 0 means "no node". Letters are 1..26 (a..z). Children of a node are a
	linked list in alphabetical order: firstChild(node), then nextSibling(child).

	Build one with:
	  WordTrie.fromEncoded(text)  -- the front-coded format made by tools/build-word-list.mjs
	  WordTrie.fromWords(list)    -- a plain list of words (tests, custom word lists)
]]

local WordTrie = {}
WordTrie.__index = WordTrie

local TERMINAL = 32 -- bit 5 of the letter byte

export type Trie = typeof(setmetatable(
	{} :: {
		letters: buffer, -- u8 per node: letter (1..26) + TERMINAL
		first: buffer, -- u32 per node: first child
		nextSib: buffer, -- u32 per node: next sibling
		count: number, -- nodes in use
		words: number,
	},
	WordTrie
))

local function grow(old: buffer, bytes: number): buffer
	local new = buffer.create(bytes)
	buffer.copy(new, 0, old, 0, math.min(buffer.len(old), bytes))
	return new
end

-- Decodes the front-coded word list: each word is an uppercase letter saying how many
-- letters it shares with the previous word (A = 0), then the rest of it in lowercase.
-- Words must be sorted and unique, which the encoding guarantees. Other characters
-- (newlines) are skipped.
function WordTrie.fromEncoded(text: string): Trie
	local capacity = math.max(64, #text + 2)
	local letters = buffer.create(capacity)
	local first = buffer.create(capacity * 4)
	local nextSib = buffer.create(capacity * 4)
	local lastChild = buffer.create(capacity * 4) -- only needed while building
	local count = 1 -- the root
	local words = 0

	-- path[d] = node for the first d letters of the current word (path[0] = root)
	local path = { [0] = 1 }
	local depth = 0
	local started = false

	local function addChild(parent: number, letter: number): number
		count += 1
		if count >= capacity then
			capacity *= 2
			letters = grow(letters, capacity)
			first = grow(first, capacity * 4)
			nextSib = grow(nextSib, capacity * 4)
			lastChild = grow(lastChild, capacity * 4)
		end
		local node = count
		buffer.writeu8(letters, node, letter)
		buffer.writeu32(first, node * 4, 0)
		buffer.writeu32(nextSib, node * 4, 0)
		buffer.writeu32(lastChild, node * 4, 0)
		local last = buffer.readu32(lastChild, parent * 4)
		if last == 0 then
			buffer.writeu32(first, parent * 4, node)
		else
			buffer.writeu32(nextSib, last * 4, node)
		end
		buffer.writeu32(lastChild, parent * 4, node)
		return node
	end

	local function endWord()
		if started and depth > 0 then
			local node = path[depth]
			buffer.writeu8(letters, node, bit32.bor(buffer.readu8(letters, node), TERMINAL))
			words += 1
		end
	end

	for i = 1, #text do
		local b = string.byte(text, i)
		if b >= 65 and b <= 90 then -- A-Z: a new word sharing (b - 65) letters
			endWord()
			started = true
			depth = b - 65
		elseif b >= 97 and b <= 122 then -- a-z
			local node = addChild(path[depth], b - 96)
			depth += 1
			path[depth] = node
		end
	end
	endWord()

	return setmetatable({
		letters = grow(letters, count + 1),
		first = grow(first, (count + 1) * 4),
		nextSib = grow(nextSib, (count + 1) * 4),
		count = count,
		words = words,
	}, WordTrie)
end

-- Builds from a plain list. Words are lowercased; anything that isn't a-z is skipped.
function WordTrie.fromWords(list: { string }): Trie
	local seen = {}
	local clean = {}
	for _, word in list do
		local w = string.lower(word)
		if #w >= 1 and not string.find(w, "[^a-z]") and not seen[w] then
			seen[w] = true
			table.insert(clean, w)
		end
	end
	table.sort(clean)
	local parts = table.create(#clean)
	local previous = ""
	for _, w in clean do
		local shared = 0
		while shared < #previous and shared < #w and string.byte(previous, shared + 1) == string.byte(w, shared + 1) do
			shared += 1
		end
		table.insert(parts, string.char(65 + math.min(shared, 25)) .. string.sub(w, shared + 1))
		previous = w
	end
	return WordTrie.fromEncoded(table.concat(parts))
end

WordTrie.ROOT = 1

function WordTrie.firstChild(self: Trie, node: number): number
	return buffer.readu32(self.first, node * 4)
end

function WordTrie.nextSibling(self: Trie, node: number): number
	return buffer.readu32(self.nextSib, node * 4)
end

-- 1..26
function WordTrie.letterOf(self: Trie, node: number): number
	return bit32.band(buffer.readu8(self.letters, node), 31)
end

function WordTrie.isTerminal(self: Trie, node: number): boolean
	return bit32.band(buffer.readu8(self.letters, node), TERMINAL) ~= 0
end

-- The child for `letter` (1..26), or 0.
function WordTrie.child(self: Trie, node: number, letter: number): number
	local child = buffer.readu32(self.first, node * 4)
	while child ~= 0 do
		local l = bit32.band(buffer.readu8(self.letters, child), 31)
		if l == letter then
			return child
		elseif l > letter then
			return 0 -- children are sorted
		end
		child = buffer.readu32(self.nextSib, child * 4)
	end
	return 0
end

-- Walks a lowercase string from `node`. Returns 0 if it falls off the trie.
function WordTrie.walk(self: Trie, node: number, letters: string): number
	for i = 1, #letters do
		if node == 0 then
			return 0
		end
		node = self:child(node, string.byte(letters, i) - 96)
	end
	return node
end

-- Is `word` (any case) in the list?
function WordTrie.has(self: Trie, word: string): boolean
	local w = string.lower(word)
	if #w == 0 or string.find(w, "[^a-z]") then
		return false
	end
	local node = self:walk(WordTrie.ROOT, w)
	return node ~= 0 and self:isTerminal(node)
end

return WordTrie
