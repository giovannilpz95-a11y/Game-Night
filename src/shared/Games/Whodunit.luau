-- Whodunit: a deduction game for 3-6 seats (the Clue / Cluedo family), with our own
-- mystery, suspects, items and rooms so the theme can be swapped or renamed.
--
-- The mystery: someone swiped the Golden Trophy. One suspect, one item and one room are
-- hidden in the case file; every other card is dealt to the players. First to name all
-- three correctly wins.
--
-- Cards are ids 1..21: suspects 1-6, items 7-12, rooms 13-21. Whodunit.cards[id] says
-- what each one is. Seat N plays suspect N, and that suspect's pawn is the seat's pawn.
--
-- The mansion is a 3x3 grid of rooms (no dice): on your turn walk to a room next to
-- yours, or take a secret passage between opposite corners. You may stay put only if
-- someone's suggestion pulled your pawn into the room since your last turn (or on your
-- first turn).
--
-- A turn:
--   1. move     { kind = "move", room = 1..9 }
--   2. suggest  { kind = "suggest", suspect = 1..6, item = 1..6 }   (the room is where you are)
--               The named suspect's pawn and the item are moved into your room. Going round
--               the table, the first seat holding any of the three cards shows you one in
--               secret. If they hold just one, it's shown for them.
--   3. show     { kind = "show", card = id }   (the seat that must show picks which card)
--   4. after    { kind = "end" }   or accuse.
-- Any time on your turn (except while someone is showing):
--               { kind = "accuse", suspect = 1..6, item = 1..6, room = 1..9 }
--               Right: you win. Wrong: you're out, but you still show cards for others.
-- If everyone is out, nobody wins. After TURN_LIMIT turns the case goes cold (a draw).

local GameModule = require(script.Parent.Parent.GameModule)

local Whodunit = {}

Whodunit.id = "Whodunit"
Whodunit.minSeats = 3
Whodunit.maxSeats = 6

local TURN_LIMIT = 300
local LOG_IN_VIEW = 40

-- Theme data. Swap this table to ship a themed mansion (names only; art is client side).
Whodunit.theme = {
	mystery = "Who swiped the Golden Trophy?",
	suspects = { "Madame Rosette", "Captain Cobalt", "Chef Butterscotch", "Dr. Minty", "Duke Lavender", "Coach Tangerine" },
	items = { "Rubber Chicken", "Grappling Hook", "Butterfly Net", "Giant Magnet", "Umbrella", "Fishing Rod" },
	-- Laid out as a 3x3 grid, left to right, top to bottom.
	rooms = { "Kitchen", "Music Room", "Observatory", "Greenhouse", "Grand Hall", "Arcade", "Pool", "Garage", "Library" },
}

export type Card = { category: "suspect" | "item" | "room", index: number, name: string }

local SUSPECTS, ITEMS, ROOMS = 6, 6, 9
local cards: { Card } = {}
for i, name in Whodunit.theme.suspects do
	cards[i] = { category = "suspect", index = i, name = name }
end
for i, name in Whodunit.theme.items do
	cards[SUSPECTS + i] = { category = "item", index = i, name = name }
end
for i, name in Whodunit.theme.rooms do
	cards[SUSPECTS + ITEMS + i] = { category = "room", index = i, name = name }
end
Whodunit.cards = cards
Whodunit.cardCount = #cards

local function suspectCard(i: number): number
	return i
end
local function itemCard(i: number): number
	return SUSPECTS + i
end
local function roomCard(i: number): number
	return SUSPECTS + ITEMS + i
end
Whodunit.suspectCard = suspectCard
Whodunit.itemCard = itemCard
Whodunit.roomCard = roomCard

local CATEGORY_CARDS = {
	suspect = { 1, 2, 3, 4, 5, 6 },
	item = { 7, 8, 9, 10, 11, 12 },
	room = { 13, 14, 15, 16, 17, 18, 19, 20, 21 },
}
Whodunit.categoryCards = CATEGORY_CARDS

-- Secret passages between opposite corners.
local PASSAGES = { [1] = 9, [9] = 1, [3] = 7, [7] = 3 }
Whodunit.passages = PASSAGES

-- Rooms you can walk to from `room` (grid neighbours plus a secret passage).
local neighbours: { { number } } = {}
for room = 1, ROOMS do
	local row, col = (room - 1) // 3, (room - 1) % 3
	local list = {}
	if row > 0 then
		table.insert(list, room - 3)
	end
	if col > 0 then
		table.insert(list, room - 1)
	end
	if col < 2 then
		table.insert(list, room + 1)
	end
	if row < 2 then
		table.insert(list, room + 3)
	end
	if PASSAGES[room] then
		table.insert(list, PASSAGES[room])
	end
	neighbours[room] = list
end
Whodunit.neighbours = neighbours

-- Where each pawn and item starts.
local SUSPECT_START = { 1, 3, 7, 9, 2, 8 }
local ITEM_START = { 4, 6, 5, 2, 8, 5 }

local function isInt(value: any, lo: number, hi: number): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value >= lo and value <= hi
end

local function shuffle(list: { any }, rng: Random)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

function Whodunit.new(seatCount: number, options: any?, rng: Random?)
	assert(seatCount >= Whodunit.minSeats and seatCount <= Whodunit.maxSeats, "Whodunit needs 3-6 seats")
	local random = rng or Random.new()
	local solution = {
		suspect = random:NextInteger(1, SUSPECTS),
		item = random:NextInteger(1, ITEMS),
		room = random:NextInteger(1, ROOMS),
	}
	local hidden = {
		[suspectCard(solution.suspect)] = true,
		[itemCard(solution.item)] = true,
		[roomCard(solution.room)] = true,
	}
	local deck = {}
	for id = 1, #cards do
		if not hidden[id] then
			table.insert(deck, id)
		end
	end
	shuffle(deck, random)

	-- Deal round the table; with 4 or 5 seats some hands get one more card.
	local hands = {}
	for seat = 1, seatCount do
		hands[seat] = {}
	end
	for i, id in deck do
		table.insert(hands[(i - 1) % seatCount + 1], id)
	end
	for seat = 1, seatCount do
		table.sort(hands[seat])
	end

	local canStay, eliminated = {}, {}
	for seat = 1, seatCount do
		canStay[seat] = true -- the first turn may stay in the start room
		eliminated[seat] = false
	end

	return {
		seatCount = seatCount,
		rng = random,
		botLevel = (options and options.botLevel) or "medium",
		solution = solution,
		hands = hands,
		suspectRoom = table.clone(SUSPECT_START),
		itemRoom = table.clone(ITEM_START),
		canStay = canStay,
		eliminated = eliminated,
		turn = 1,
		phase = "move",
		suggestion = nil, -- the log entry of this turn's suggestion
		log = {}, -- every suggestion: { seat, suspect, item, room, passed = { seat }, shower?, card? }
		accusations = {}, -- { seat, suspect, item, room, correct }
		turns = 0,
		winner = nil,
		over = false,
		reason = nil,
		lastAction = nil,
	}
end

-- Helpers ----------------------------------------------------------------------

local function roomOf(state, seat: number): number
	return state.suspectRoom[seat]
end

local function suggestionCards(entry): { number }
	return { suspectCard(entry.suspect), itemCard(entry.item), roomCard(entry.room) }
end

-- Cards in `seat`'s hand that answer a suggestion.
local function matchingCards(state, seat: number, entry): { number }
	local out = {}
	for _, id in suggestionCards(entry) do
		if table.find(state.hands[seat], id) then
			table.insert(out, id)
		end
	end
	return out
end

local function legalRooms(state, seat: number): { number }
	local here = roomOf(state, seat)
	local out = table.clone(neighbours[here])
	if state.canStay[seat] then
		table.insert(out, 1, here)
	end
	return out
end

local function isOver(state): boolean
	return state.winner ~= nil or state.over
end

local function nextTurn(state)
	state.suggestion = nil
	state.turns += 1
	if state.turns >= TURN_LIMIT then
		state.over = true
		state.reason = "The case went cold"
		return
	end
	local seat = state.turn
	for _ = 1, state.seatCount do
		seat = seat % state.seatCount + 1
		if not state.eliminated[seat] then
			state.turn = seat
			state.phase = "move"
			return
		end
	end
	state.over = true
	state.reason = "Nobody solved the case"
end

local function finishShow(state, card: number)
	state.suggestion.card = card
	state.phase = "after"
	state.lastAction = { kind = "show", seat = state.suggestion.shower, to = state.suggestion.seat }
end

local function canAccuseNow(state, seat: number): boolean
	return not isOver(state) and seat == state.turn and state.phase ~= "show" and not state.eliminated[seat]
end

-- The contract ------------------------------------------------------------------

function Whodunit.getActiveSeats(state): { number }
	if isOver(state) then
		return {}
	end
	if state.phase == "show" then
		return { state.suggestion.shower }
	end
	return { state.turn }
end

function Whodunit.getLegalMoves(state, seat: number): { any }
	local moves = {}
	if isOver(state) then
		return moves
	end
	if state.phase == "show" then
		if seat == state.suggestion.shower then
			for _, id in matchingCards(state, seat, state.suggestion) do
				table.insert(moves, { kind = "show", card = id })
			end
		end
		return moves
	end
	if seat ~= state.turn then
		return moves
	end
	-- Accusations are left out on purpose: a random fallback move must never accuse.
	if state.phase == "move" then
		for _, room in legalRooms(state, seat) do
			table.insert(moves, { kind = "move", room = room })
		end
	elseif state.phase == "suggest" then
		for s = 1, SUSPECTS do
			for i = 1, ITEMS do
				table.insert(moves, { kind = "suggest", suspect = s, item = i })
			end
		end
	elseif state.phase == "after" then
		table.insert(moves, { kind = "end" })
	end
	return moves
end

function Whodunit.validateMove(state, seat: number, move: any): (boolean, string?)
	if isOver(state) then
		return false, "The game is over"
	end
	if type(move) ~= "table" then
		return false, "Bad move"
	end
	local kind = move.kind
	if state.phase == "show" then
		if seat ~= state.suggestion.shower then
			return false, "Someone else is showing a card"
		end
		if kind ~= "show" then
			return false, "Pick a card to show"
		end
		if not isInt(move.card, 1, #cards) then
			return false, "Bad card"
		end
		if not table.find(matchingCards(state, seat, state.suggestion), move.card) then
			return false, "Show one of the suggested cards from your hand"
		end
		return true
	end
	if seat ~= state.turn then
		return false, "It's not your turn"
	end
	if kind == "accuse" then
		if not canAccuseNow(state, seat) then
			return false, "You can't accuse right now"
		end
		if not isInt(move.suspect, 1, SUSPECTS) or not isInt(move.item, 1, ITEMS) or not isInt(move.room, 1, ROOMS) then
			return false, "Pick a suspect, an item and a room"
		end
		return true
	elseif kind == "move" then
		if state.phase ~= "move" then
			return false, "You already moved"
		end
		if not isInt(move.room, 1, ROOMS) then
			return false, "Bad room"
		end
		if not table.find(legalRooms(state, seat), move.room) then
			if move.room == roomOf(state, seat) then
				return false, "You have to leave this room first"
			end
			return false, "You can't reach that room from here"
		end
		return true
	elseif kind == "suggest" then
		if state.phase ~= "suggest" then
			return false, if state.phase == "move" then "Pick a room first" else "You already made a suggestion"
		end
		if not isInt(move.suspect, 1, SUSPECTS) or not isInt(move.item, 1, ITEMS) then
			return false, "Pick a suspect and an item"
		end
		return true
	elseif kind == "end" then
		if state.phase ~= "after" then
			return false, "Make a suggestion first"
		end
		return true
	end
	return false, "Bad move"
end

function Whodunit.applyMove(state, seat: number, move: any)
	local kind = move.kind
	if kind == "show" then
		finishShow(state, move.card)
		return
	elseif kind == "move" then
		state.suspectRoom[seat] = move.room
		state.canStay[seat] = false
		state.phase = "suggest"
		state.lastAction = { kind = "move", seat = seat, room = move.room }
		return
	elseif kind == "end" then
		state.lastAction = { kind = "end", seat = seat }
		nextTurn(state)
		return
	elseif kind == "accuse" then
		local sol = state.solution
		local correct = move.suspect == sol.suspect and move.item == sol.item and move.room == sol.room
		table.insert(state.accusations, {
			seat = seat,
			suspect = move.suspect,
			item = move.item,
			room = move.room,
			correct = correct,
		})
		state.lastAction = { kind = "accuse", seat = seat, correct = correct }
		if correct then
			state.winner = seat
			state.reason = `Solved it: {cards[suspectCard(sol.suspect)].name}, {cards[itemCard(sol.item)].name}, {cards[roomCard(sol.room)].name}`
			return
		end
		state.eliminated[seat] = true
		nextTurn(state)
		return
	end

	-- Suggest.
	local room = roomOf(state, seat)
	local entry = {
		seat = seat,
		suspect = move.suspect,
		item = move.item,
		room = room,
		passed = {},
		shower = nil,
		card = nil,
	}
	table.insert(state.log, entry)
	state.suggestion = entry
	state.canStay[seat] = false

	-- Bring the suspect's pawn and the item into the room.
	if state.suspectRoom[move.suspect] ~= room then
		state.suspectRoom[move.suspect] = room
		if move.suspect <= state.seatCount and move.suspect ~= seat then
			state.canStay[move.suspect] = true
		end
	end
	state.itemRoom[move.item] = room
	state.lastAction = { kind = "suggest", seat = seat }

	for step = 1, state.seatCount - 1 do
		local other = (seat - 1 + step) % state.seatCount + 1
		local matches = matchingCards(state, other, entry)
		if #matches > 0 then
			entry.shower = other
			if #matches == 1 then
				finishShow(state, matches[1])
			else
				state.phase = "show"
			end
			return
		end
		table.insert(entry.passed, other)
	end
	state.phase = "after" -- nobody could disprove it
end

function Whodunit.getResult(state): GameModule.Result?
	if state.winner then
		return { winners = { state.winner }, isDraw = false, reason = state.reason }
	end
	if state.over then
		return { winners = {}, isDraw = true, reason = state.reason }
	end
	return nil
end

-- What one seat may see. The case file, other hands and cards shown between other
-- players stay hidden until the game ends.
local function entryView(entry, seat: number?, over: boolean)
	local privy = over or (seat ~= nil and (seat == entry.seat or seat == entry.shower))
	return {
		seat = entry.seat,
		suspect = entry.suspect,
		item = entry.item,
		room = entry.room,
		passed = table.clone(entry.passed),
		shower = entry.shower,
		card = if privy then entry.card else nil,
	}
end

function Whodunit.getView(state, seat: number?)
	local over = isOver(state)
	local mySeat = if seat and state.hands[seat] then seat else nil
	local log = {}
	for i = math.max(1, #state.log - LOG_IN_VIEW + 1), #state.log do
		table.insert(log, entryView(state.log[i], mySeat, over))
	end
	-- Auto notepad: your own cards and every card shown to you (a list, not a sparse map,
	-- so it survives the remote).
	local notes = {}
	if mySeat then
		for _, id in state.hands[mySeat] do
			table.insert(notes, { card = id, by = mySeat })
		end
		for _, entry in state.log do
			if entry.seat == mySeat and entry.card then
				table.insert(notes, { card = entry.card, by = entry.shower })
			end
		end
	end
	local myTurn = mySeat ~= nil and not over and mySeat == state.turn and state.phase ~= "show"
	local showing = mySeat ~= nil and not over and state.phase == "show" and state.suggestion.shower == mySeat
	local accusations = {}
	for _, a in state.accusations do
		table.insert(accusations, table.clone(a))
	end
	return {
		mystery = Whodunit.theme.mystery,
		phase = if over then "over" else state.phase,
		turn = state.turn,
		seatCount = state.seatCount,
		suspectRoom = table.clone(state.suspectRoom),
		itemRoom = table.clone(state.itemRoom),
		eliminated = table.clone(state.eliminated),
		hand = if mySeat then table.clone(state.hands[mySeat]) else nil,
		notes = notes,
		log = log,
		suggestion = if state.suggestion then entryView(state.suggestion, mySeat, over) else nil,
		accusations = accusations,
		legalRooms = if myTurn and state.phase == "move" then legalRooms(state, mySeat :: number) else {},
		canStay = myTurn and state.phase == "move" and state.canStay[mySeat :: number] == true,
		canAccuse = myTurn and not state.eliminated[mySeat :: number],
		showOptions = if showing then matchingCards(state, mySeat :: number, state.suggestion) else {},
		lastAction = GameModule.copy(state.lastAction),
		solution = if over then GameModule.copy(state.solution) else nil,
		winner = state.winner,
	}
end

function Whodunit.getSeatInfo(state): { [number]: string }
	local info = {}
	for seat = 1, state.seatCount do
		local where = Whodunit.theme.rooms[state.suspectRoom[seat]]
		info[seat] = if state.eliminated[seat] then `{where} · out` else where
	end
	return info
end

function Whodunit.getBotDelay(state, seat: number, rng: Random): number
	if state.phase == "show" or state.phase == "after" then
		return 0.8 + rng:NextNumber() * 0.6
	end
	return 1 + rng:NextNumber() * 0.8
end

-- Deduction (bots; also handy for tests) -------------------------------------------
--
-- possible[card][holder]: could that holder have the card? Holders are seats
-- 1..seatCount plus the case file (seatCount + 1). Uses only what `seat` is allowed to
-- know: its hand, cards shown to it, and the public log.
--   easy:   own hand + cards shown to it
--   medium: + "seat X couldn't disprove"
--   hard:   + hand sizes + "seat X showed someone one of these three"
function Whodunit.deduce(state, seat: number, level: string?)
	level = level or "hard"
	local n = state.seatCount
	local caseFile = n + 1
	local possible = {}
	for id = 1, #cards do
		possible[id] = {}
		for h = 1, caseFile do
			possible[id][h] = true
		end
	end
	local function assign(id: number, holder: number): boolean
		local changed = false
		for h = 1, caseFile do
			if h ~= holder and possible[id][h] then
				possible[id][h] = false
				changed = true
			end
		end
		return changed
	end
	local function holderOf(id: number): number?
		local found = nil
		for h = 1, caseFile do
			if possible[id][h] then
				if found then
					return nil
				end
				found = h
			end
		end
		return found
	end

	local mine = {}
	for _, id in state.hands[seat] do
		mine[id] = true
		assign(id, seat)
	end
	for id = 1, #cards do
		if not mine[id] then
			possible[id][seat] = false
		end
	end
	for _, entry in state.log do
		if entry.seat == seat and entry.card then
			assign(entry.card, entry.shower)
		end
	end
	local clauses = {}
	if level ~= "easy" then
		for _, entry in state.log do
			for _, p in entry.passed do
				for _, id in suggestionCards(entry) do
					possible[id][p] = false
				end
			end
			if level == "hard" and entry.shower and entry.shower ~= seat and not (entry.seat == seat and entry.card) then
				table.insert(clauses, { holder = entry.shower, cards = suggestionCards(entry) })
			end
		end
	end

	local sizes = {}
	for h = 1, n do
		sizes[h] = #state.hands[h] -- public: everyone sees how many cards each hand has
	end

	local changed = true
	while changed do
		changed = false
		-- The case file holds exactly one card of each category.
		for _, list in CATEGORY_CARDS do
			local candidates, known = {}, nil
			for _, id in list do
				if possible[id][caseFile] then
					table.insert(candidates, id)
					if holderOf(id) == caseFile then
						known = id
					end
				end
			end
			if #candidates == 1 and not known then
				known = candidates[1]
				changed = assign(known, caseFile) or changed
			end
			if known then
				for _, id in list do
					if id ~= known and possible[id][caseFile] then
						possible[id][caseFile] = false
						changed = true
					end
				end
			end
		end
		if level == "hard" then
			-- Hand sizes: a full hand holds nothing else; a hand with exactly as many
			-- possible cards as its size holds all of them.
			for h = 1, n do
				local held, maybe = 0, {}
				for id = 1, #cards do
					if possible[id][h] then
						table.insert(maybe, id)
						if holderOf(id) == h then
							held += 1
						end
					end
				end
				if held == sizes[h] and #maybe > held then
					for _, id in maybe do
						if holderOf(id) ~= h then
							possible[id][h] = false
							changed = true
						end
					end
				elseif #maybe == sizes[h] then
					for _, id in maybe do
						if holderOf(id) ~= h then
							changed = assign(id, h) or changed
						end
					end
				end
			end
		end
		for _, clause in clauses do
			local left = {}
			for _, id in clause.cards do
				if possible[id][clause.holder] then
					table.insert(left, id)
				end
			end
			if #left == 1 and holderOf(left[1]) ~= clause.holder then
				changed = assign(left[1], clause.holder) or changed
			end
		end
	end

	local candidates = { suspect = {}, item = {}, room = {} }
	for category, list in CATEGORY_CARDS do
		for _, id in list do
			if possible[id][caseFile] then
				table.insert(candidates[category], id)
			end
		end
	end
	local solved = #candidates.suspect == 1 and #candidates.item == 1 and #candidates.room == 1
	return {
		possible = possible,
		candidates = candidates,
		solved = solved,
		holderOf = holderOf,
	}
end

-- Bots ------------------------------------------------------------------------------

local function pick(list: { any }, rng: Random): any
	return list[rng:NextInteger(1, #list)]
end

-- Steps from `from` to every room (walking + passages).
local function distances(from: number): { number }
	local dist = { [from] = 0 }
	local queue = { from }
	local head = 1
	while queue[head] do
		local room = queue[head]
		head += 1
		for _, nextRoom in neighbours[room] do
			if dist[nextRoom] == nil then
				dist[nextRoom] = dist[room] + 1
				table.insert(queue, nextRoom)
			end
		end
	end
	return dist
end

-- Bots make at least this many suggestions before accusing, even when sure, so a
-- table with humans gets a real game (and long enough to pay rewards).
local MIN_SUGGESTIONS_TO_ACCUSE = { easy = 3, medium = 5, hard = 4 }
Whodunit.minSuggestionsToAccuse = MIN_SUGGESTIONS_TO_ACCUSE

local function suggestionsMade(state, seat: number): number
	local count = 0
	for _, entry in state.log do
		if entry.seat == seat then
			count += 1
		end
	end
	return count
end

local function accusation(know)
	return {
		kind = "accuse",
		suspect = cards[know.candidates.suspect[1]].index,
		item = cards[know.candidates.item[1]].index,
		room = cards[know.candidates.room[1]].index,
	}
end

-- A suspect or item to name: one that might be in the case file. Once a category is
-- solved, hard bots name a card from their own hand instead, so nobody learns from it.
local function chooseNamed(state, seat: number, know, category: string, rng: Random): number
	local candidates = know.candidates[category]
	if #candidates == 1 and state.botLevel == "hard" then
		local own = {}
		for _, id in state.hands[seat] do
			if cards[id].category == category then
				table.insert(own, id)
			end
		end
		if #own > 0 and rng:NextNumber() < 0.7 then
			return cards[pick(own, rng)].index
		end
	end
	if #candidates > 0 then
		return cards[pick(candidates, rng)].index
	end
	return rng:NextInteger(1, if category == "suspect" then SUSPECTS else ITEMS)
end

function Whodunit.chooseBotMove(state, seat: number, rng: Random): any?
	if isOver(state) then
		return nil
	end
	if state.phase == "show" then
		local options = matchingCards(state, seat, state.suggestion)
		if #options == 0 then
			return nil
		end
		if state.botLevel ~= "easy" then
			-- Show a card this player has already seen from us, so they learn nothing new.
			for _, entry in state.log do
				if entry.seat == state.suggestion.seat and entry.shower == seat and entry.card and table.find(options, entry.card) then
					return { kind = "show", card = entry.card }
				end
			end
		end
		return { kind = "show", card = pick(options, rng) }
	end
	if seat ~= state.turn then
		return nil
	end

	local know = Whodunit.deduce(state, seat, state.botLevel)
	local patience = MIN_SUGGESTIONS_TO_ACCUSE[state.botLevel] or 4
	if know.solved and not state.eliminated[seat] and suggestionsMade(state, seat) >= patience then
		return accusation(know)
	end

	if state.phase == "move" then
		local options = legalRooms(state, seat)
		if state.botLevel == "easy" and rng:NextNumber() < 0.5 then
			return { kind = "move", room = pick(options, rng) }
		end
		-- Head for the nearest room that might be the scene.
		local wanted = {}
		for _, id in know.candidates.room do
			wanted[cards[id].index] = true
		end
		local best, bestScore = {}, math.huge
		for _, room in options do
			local dist = distances(room)
			local score = math.huge
			for target in wanted do
				score = math.min(score, dist[target])
			end
			if score < bestScore then
				best, bestScore = { room }, score
			elseif score == bestScore then
				table.insert(best, room)
			end
		end
		return { kind = "move", room = pick(if #best > 0 then best else options, rng) }
	elseif state.phase == "suggest" then
		return {
			kind = "suggest",
			suspect = chooseNamed(state, seat, know, "suspect", rng),
			item = chooseNamed(state, seat, know, "item", rng),
		}
	elseif state.phase == "after" then
		return { kind = "end" }
	end
	return nil
end

-- Stats for the profile (see shared/StatsCatalog.luau).
function Whodunit.getMatchStats(state): { [number]: { [string]: number } }
	local out = {}
	for seat = 1, state.seatCount do
		out[seat] = {
			solved = if state.winner == seat then 1 else 0,
			wrong = if state.eliminated[seat] then 1 else 0,
		}
	end
	return out
end

return Whodunit
