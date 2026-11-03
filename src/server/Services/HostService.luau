-- Party Host tools: saving word lists (Sketch & Guess) and quiz decks (Trivia Night), and
-- getting them ready for a match. Parsing and limits live in shared/CustomContent.luau.
--
-- Hosts' text is saved as typed and filtered with TextService (for everyone in the
-- server) each time a match uses it, so the filter's current rules always apply. Anything
-- the filter changes is dropped, never shown with ###.
--
--   HostService.isHost(player) -> boolean
--   HostService.prepare(player, "words" | "quiz", slot) -> (content?, errorMessage?) -- yields

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local Players = game:GetService("Players")

local Net = require(ReplicatedStorage.Shared.Net)
local CustomContent = require(ReplicatedStorage.Shared.CustomContent)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local HostService = {}

local FILTER_CHUNK = 1500 -- characters per TextService call when filtering a whole list
local CACHE_SECONDS = 600 -- reuse a filtered list for this long, unless it's edited

local hostStateRemote: RemoteEvent
local notifyRemote: RemoteEvent

-- [userId] = { ["words:1"] = { version, at, content } }
local cache: { [number]: { [string]: { version: number, at: number, content: any } } } = {}
local versions: { [number]: { [string]: number } } = {} -- bumped on every save/delete

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

function HostService.isHost(player: Player): boolean
	return EconomyService.hasPass(player, "partyHost")
end

local function store(data: any, kind: string): { [string]: any }
	return if kind == "words" then data.custom.words else data.custom.decks
end

local function validSlot(slot: any): string?
	if type(slot) == "number" and slot % 1 == 0 and slot >= 1 and slot <= CustomContent.Slots then
		return tostring(slot)
	end
	return nil
end

-- What the editor and the game picker need: names and text of every saved list.
function HostService.push(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local payload = { words = {}, quiz = {} }
	for slot = 1, CustomContent.Slots do
		local w = data.custom.words[tostring(slot)]
		if w then
			table.insert(payload.words, { slot = slot, name = w.name, count = #w.words, text = CustomContent.wordsToText(w.words) })
		end
		local d = data.custom.decks[tostring(slot)]
		if d then
			table.insert(payload.quiz, { slot = slot, name = d.name, count = #d.questions, text = CustomContent.deckToText(d.questions) })
		end
	end
	hostStateRemote:FireClient(player, payload)
end

local function bump(player: Player, kind: string, slot: string)
	versions[player.UserId] = versions[player.UserId] or {}
	local key = `{kind}:{slot}`
	versions[player.UserId][key] = (versions[player.UserId][key] or 0) + 1
end

-- Filters many strings with as few TextService calls as we can: strings are joined with
-- new lines and filtered in chunks. If a chunk doesn't come back with the same number
-- of lines, its strings are filtered one by one. nil = couldn't be filtered (dropped).
local function filterStrings(strings: { string }, fromUserId: number): { string? }
	local out: { string? } = {}
	local function filterOne(text: string): string?
		local result: string? = nil
		local ok = pcall(function()
			local filterResult = TextService:FilterStringAsync(text, fromUserId, Enum.TextFilterContext.PublicChat)
			result = filterResult:GetNonChatStringForBroadcastAsync()
		end)
		return if ok then result else nil
	end

	local i = 1
	while i <= #strings do
		local first, length = i, 0
		while i <= #strings and (i == first or length + #strings[i] + 1 <= FILTER_CHUNK) do
			length += #strings[i] + 1
			i += 1
		end
		local chunk = table.move(strings, first, i - 1, 1, {})
		local joined = filterOne(table.concat(chunk, "\n"))
		local lines = if joined then string.split(joined, "\n") else nil
		if lines and #lines == #chunk then
			for k, line in lines do
				out[first + k - 1] = line
			end
		else
			for k, text in chunk do
				out[first + k - 1] = filterOne(text)
			end
		end
	end
	return out
end

-- Gets a saved list ready for a match: filtered, with anything the filter touched removed.
function HostService.prepare(player: Player, kind: string, slot: any): (any?, string?)
	local key = validSlot(slot)
	local data = DataService.get(player)
	if not key or not data or not CustomContent.Kinds[kind] then
		return nil, "Pick one of your lists"
	end
	local saved = store(data, kind)[key]
	if not saved then
		return nil, `That {string.lower(CustomContent.Kinds[kind].name)} is empty`
	end

	local cacheKey = `{kind}:{key}`
	local version = (versions[player.UserId] or {})[cacheKey] or 0
	local mine = cache[player.UserId]
	local hit = mine and mine[cacheKey]
	if hit and hit.version == version and os.clock() - hit.at < CACHE_SECONDS then
		return hit.content
	end

	local content = if kind == "words" then saved.words else saved.questions
	local strings = CustomContent.strings(kind, content)
	table.insert(strings, 1, saved.name)
	local filtered = filterStrings(strings, player.UserId)
	local filteredName = table.remove(filtered, 1)
	local kept, dropped = CustomContent.applyFilter(kind, content, filtered)
	if #kept < CustomContent.minimum(kind) then
		return nil, `Not enough of "{if filteredName == saved.name then saved.name else "your list"}" got past the chat filter. Edit it in Host tools.`
	end
	if kind == "quiz" then
		local category = if filteredName == saved.name then saved.name else "Host's deck"
		for _, question in kept do
			question.c = category
		end
	end
	if dropped > 0 then
		notify(player, `{dropped} item(s) from your list were hidden by the chat filter and left out`)
	end
	if player.Parent then
		cache[player.UserId] = cache[player.UserId] or {}
		cache[player.UserId][cacheKey] = { version = version, at = os.clock(), content = kept }
	end
	return kept
end

-- Client requests ----------------------------------------------------------------

local handlers = {}

function handlers.sync(player: Player, _request: any)
	HostService.push(player)
end

function handlers.save(player: Player, request: any)
	if not HostService.isHost(player) then
		return notify(player, "Word lists and quiz decks come with the Party Host pass")
	end
	local data = DataService.get(player)
	local kind = request.kind
	local slot = validSlot(request.slot)
	if not data or not slot or (kind ~= "words" and kind ~= "quiz") then
		return
	end
	local name = CustomContent.cleanName(request.name, kind, tonumber(slot) :: number)
	if kind == "words" then
		local words, err = CustomContent.parseWords(request.text)
		if not words then
			return notify(player, err :: string)
		end
		data.custom.words[slot] = { name = name, words = words }
		notify(player, `Saved "{name}" ({#words} words)`)
	else
		local questions, err = CustomContent.parseDeck(request.text)
		if not questions then
			return notify(player, err :: string)
		end
		data.custom.decks[slot] = { name = name, questions = questions }
		notify(player, `Saved "{name}" ({#questions} questions)`)
	end
	bump(player, kind, slot)
	HostService.push(player)
end

function handlers.delete(player: Player, request: any)
	local data = DataService.get(player)
	local kind = request.kind
	local slot = validSlot(request.slot)
	if not data or not slot or (kind ~= "words" and kind ~= "quiz") then
		return
	end
	store(data, kind)[slot] = nil
	bump(player, kind, slot)
	HostService.push(player)
end

function HostService.handleRequest(player: Player, request: any)
	if type(request) ~= "table" or type(request.action) ~= "string" then
		return
	end
	local handler = handlers[request.action]
	if handler then
		handler(player, request)
	end
end

function HostService.init()
	hostStateRemote = Net.event(Net.Names.HostState)
	notifyRemote = Net.event(Net.Names.Notify)
	DataService.onLoaded(function(player)
		HostService.push(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		cache[player.UserId] = nil
		versions[player.UserId] = nil
	end)
end

return HostService
