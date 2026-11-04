-- What the avatars at a table act out. Pure: no Instances, so it's tested in
-- tests/TableActions.spec.luau.
--
-- describe(module, move) turns a game move into a gesture: reach for a cell, move a piece
-- from one square to another, toss a card on the pile, roll the dice, slap, point at a
-- player... The server sends it to every client (server/Services/TableActionService) and
-- each client animates the avatar in that seat (client/Table3D/Avatars).
--
-- Cells use the same Row/Col numbering as the board's Cells folder (see the Table3D
-- handlers), so the hand lands on the right square.

local TableActions = {}

-- Every gesture a client knows how to play.
TableActions.Kinds = {
	-- game actions
	place = true, -- reach out and set a piece down (cell, column or the table's middle)
	move = true, -- pick a piece up at `from`, put it down at `to`
	card = true, -- toss a card onto the middle
	draw = true, -- take a card from the middle into your hand
	dice = true, -- shake and roll
	slap = true, -- slam a hand on the pile
	grab = true, -- snatch something from the middle and hold it up
	point = true, -- point at another player (`seat`) or the middle
	knock = true, -- knock on the table
	pass = true, -- wave it off
	buzz = true, -- hit the buzzer
	think = true, -- hand on chin (bots, while they think)
	-- reactions at the end of a game
	cheer = true,
	groan = true,
	shrug = true,
}

-- The emote wheel. `id` is also the gesture; `icon` shows over the avatar's head.
TableActions.Emotes = {
	{ id = "wave", label = "Wave", icon = "👋" },
	{ id = "cheer", label = "Cheer", icon = "🙌" },
	{ id = "clap", label = "Clap", icon = "👏" },
	{ id = "laugh", label = "Laugh", icon = "😂" },
	{ id = "thumbsUp", label = "Nice!", icon = "👍" },
	{ id = "think", label = "Hmm", icon = "🤔" },
	{ id = "facepalm", label = "Oops", icon = "🤦" },
	{ id = "shrug", label = "Shrug", icon = "🤷" },
}

local emoteById = {}
for _, emote in TableActions.Emotes do
	emoteById[emote.id] = emote
	TableActions.Kinds[emote.id] = true
end

-- Icons shown over the head for the end-of-game reactions.
TableActions.ReactionIcons = { cheer = "🎉", groan = "😩", shrug = "🤝" }

function TableActions.emote(id: any): { id: string, label: string, icon: string }?
	return if type(id) == "string" then emoteById[id] else nil
end

export type Action = {
	kind: string,
	cell: { number }?, -- { row, col } on the board's Cells
	from: { number }?,
	to: { number }?,
	column: number?, -- Four in a Row
	seat: number?, -- match seat to point at / hand things to
}

local function isInt(v: any, lo: number, hi: number): boolean
	return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi
end

local function rc(v: any): { number }?
	if type(v) == "table" and isInt(v[1], 1, 32) and isInt(v[2], 1, 32) then
		return { v[1], v[2] }
	end
	return nil
end

-- Chess squares ("e4") to the 3D board's Row/Col: row 1 is rank 8, col 1 is file a.
local FILES = "abcdefgh"
local function chessCell(name: any): { number }?
	if type(name) ~= "string" or #name ~= 2 then
		return nil
	end
	local file = string.find(FILES, string.sub(name, 1, 1), 1, true)
	local rank = tonumber(string.sub(name, 2, 2))
	if not file or not rank or rank < 1 or rank > 8 then
		return nil
	end
	return { 9 - rank, file }
end

local function simple(kind: string): Action
	return { kind = kind }
end

-- Per-game moves. Anything not listed falls back to the generic table below.
local games: { [string]: (any) -> Action? } = {}

function games.TicTacToe(move)
	if isInt(move.cell, 1, 9) then
		local i = move.cell - 1
		return { kind = "place", cell = { i // 3 + 1, i % 3 + 1 } }
	end
	return nil
end

function games.Chess(move)
	local from, to = chessCell(move.from), chessCell(move.to)
	return if from and to then { kind = "move", from = from, to = to } else nil
end

function games.Checkers(move)
	local from = rc(move.from)
	local path = move.path
	local to = type(path) == "table" and rc(path[#path]) or nil
	return if from and to then { kind = "move", from = from, to = to } else nil
end

function games.FourInARow(move)
	return if isInt(move.column, 1, 16) then { kind = "place", column = move.column } else nil
end

local KINDS: { [string]: { [string]: string } } = {
	ColorClash = { play = "card", draw = "draw" },
	TriviaNight = { answer = "buzz" },
	-- Night picks stay silent and still (a gesture would give a role away).
	Werewolf = { accuse = "point", claim = "point", vote = "point", pass = "pass" },
	SketchGuess = { choose = "point", giveUp = "pass", voteSkip = "pass" }, -- strokes, shapes, guesses and reports: none
	Whodunit = { move = "place", suggest = "point", accuse = "slap", show = "card", ["end"] = "pass" },
	Estates = {
		roll = "dice", buy = "draw", build = "place", sell = "draw", bid = "knock", payJail = "card",
		payDebt = "card", useCard = "card", accept = "thumbsUp", reject = "pass", decline = "pass",
		offer = "point", mortgage = "card", unmortgage = "card", bankrupt = "groan",
	},
	Conquest = { place = "place", attack = "dice", occupy = "place", fortify = "place", trade = "card" },
	Hexlands = {
		roll = "dice", road = "place", camp = "place", town = "place", place = "place", setup = "place",
		bandit = "place", buyCard = "draw", play = "card", bank = "card", offer = "point", accept = "thumbsUp",
		reject = "pass", discard = "card", doneRoads = "pass",
	},
	WordTiles = { place = "place", exchange = "draw" },
	Speed = { play = "card" },
	Spoons = { pass = "card", grab = "grab" },
	GoFish = { ask = "point" },
	War = { flip = "card" },
	Cheat = { play = "card", doubt = "point" },
	President = { play = "card" },
	Hearts = { play = "card", pass = "card" }, -- passing three cards is a card action
	Spades = { play = "card", bid = "knock" },
	ThirtyOne = { draw = "draw", discard = "card", knock = "knock" },
	Palace = { play = "card", blind = "card", pickup = "draw", swap = "card" },
	SlapStack = { flip = "card", slap = "slap" },
	OldMaid = { draw = "draw" },
	Snap = { flip = "card", snap = "slap" },
	GinRummy = { draw = "draw", discard = "card", knock = "knock" },
	OhHell = { play = "card", bid = "knock" },
}

local GENERIC = { play = "card", draw = "draw", roll = "dice", pass = "pass", endTurn = "pass", ["end"] = "pass" }

-- The gesture for `move` in game `module` (GameCatalog entry.module), or nil for moves
-- that shouldn't animate (drawing strokes, typed guesses, unknown shapes).
function TableActions.describe(module: string, move: any): Action?
	if type(move) ~= "table" then
		return nil
	end
	local custom = games[module]
	if custom then
		return custom(move)
	end
	local kind = move.kind
	if type(kind) ~= "string" then
		return nil
	end
	local map = KINDS[module]
	local gesture = (map and map[kind]) or GENERIC[kind]
	if not gesture then
		return nil
	end
	local action = simple(gesture)
	-- Asking someone (Go Fish) points at them.
	if gesture == "point" and isInt(move.target, 1, 8) then
		action.seat = move.target
	end
	return action
end

-- End of game: winners cheer, everyone else groans; a draw is a shrug all round.
-- Returns { [seat] = "cheer" | "groan" | "shrug" }.
function TableActions.reactions(result: any, seatCount: number): { [number]: string }
	local out = {}
	if type(result) ~= "table" then
		return out
	end
	local winners = {}
	for _, seat in result.winners or {} do
		winners[seat] = true
	end
	for seat = 1, seatCount do
		if result.isDraw then
			out[seat] = "shrug"
		else
			out[seat] = if winners[seat] then "cheer" else "groan"
		end
	end
	return out
end

return TableActions
