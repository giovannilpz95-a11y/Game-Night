-- Every game shown in the lobby. A game with status "ready" has a rules module in
-- Shared/Games/<module> and a renderer in the client's Renderers/<module>.
-- "soon" games show as "Coming soon" so players can see what's next.
--
-- `name` is the ONLY place a game's display name is set. The lobby, table header and
-- results all read it from here, so renaming a game means changing just that line.
-- `id` and `module` are internal and should not change once a game ships.

export type Entry = {
	id: string,
	name: string,
	module: string?,
	category: string,
	description: string,
	minSeats: number,
	maxSeats: number,
	turnSeconds: number?, -- per-turn time limit; Config.TurnSeconds if nil
	status: "ready" | "soon",
	-- Economy (see shared/Economy.luau). Rewards are paced by time played, so each game
	-- says how long a match usually takes; shorter or emptier matches pay nothing.
	coin: string?, -- which Coins this game pays; Economy.DefaultCoin if nil
	typicalMinutes: number?, -- usual match length
	minMinutes: number?, -- matches shorter than this pay nothing
	minMoves: number?, -- matches with fewer moves than this pay nothing
	-- Party Host (see shared/HouseRules.luau and shared/CustomContent.luau)
	houseRules: { any }?, -- this game's own house rules; turn games also get the Turn timer
	custom: string?, -- "words" or "quiz": the host's own word lists or quiz decks work here
}

local Toggle = require(script.Parent.HouseRules).Toggle

local entries: { Entry } = {
	{
		id = "TicTacToe",
		name = "Tic-Tac-Toe",
		module = "TicTacToe",
		category = "Quick",
		description = "Get three in a row. A one-minute warm-up.",
		minSeats = 2,
		maxSeats = 2,
		turnSeconds = 20,
		status = "ready",
		coin = "arcade",
		typicalMinutes = 1,
		minMinutes = 0.1,
		minMoves = 5,
		houseRules = {
			{ key = "misere", name = "Upside down", hint = "Making three in a row loses.", choices = Toggle, default = 1 },
		},
	},
	{
		id = "Chess",
		name = "Chess",
		module = "Chess",
		category = "Strategy",
		description = "The classic game of kings.",
		minSeats = 2,
		maxSeats = 2,
		turnSeconds = 60,
		status = "ready",
		coin = "chess",
		typicalMinutes = 15,
		minMinutes = 1,
		minMoves = 10,
		houseRules = {
			{ key = "kingOfTheHill", name = "King of the hill", hint = "Also win by walking your king to one of the four center squares.", choices = Toggle, default = 1 },
		},
	},
	{
		id = "Checkers",
		name = "Checkers",
		module = "Checkers",
		category = "Strategy",
		description = "Jump and crown your way to victory.",
		minSeats = 2,
		maxSeats = 2,
		turnSeconds = 45,
		status = "ready",
		coin = "checkers",
		typicalMinutes = 10,
		minMinutes = 1,
		minMoves = 16,
		houseRules = {
			{ key = "forcedCaptures", name = "Must jump", hint = "Off: jumping is a choice, not a must.", choices = Toggle, default = 2 },
		},
	},
	{
		id = "FourInARow",
		name = "Four in a Row",
		module = "FourInARow",
		category = "Quick",
		description = "Drop discs and line up four.",
		minSeats = 2,
		maxSeats = 2,
		turnSeconds = 20,
		status = "ready",
		coin = "arcade",
		typicalMinutes = 3,
		minMinutes = 0.25,
		minMoves = 7,
	},
	{
		id = "ColorClash",
		name = "Color Clash",
		module = "ColorClash",
		category = "Cards",
		description = "Match colors and numbers, empty your hand first.",
		minSeats = 2,
		maxSeats = 8,
		turnSeconds = 20,
		status = "ready",
		coin = "colorclash",
		typicalMinutes = 8,
		minMinutes = 1,
		minMoves = 10,
		houseRules = {
			{ key = "stacking", name = "Stack draw cards", hint = "Answer a Draw Two or Draw Four with another one.", choices = Toggle, default = 2 },
			{ key = "drawUntilPlayable", name = "Draw until you can play", hint = "Keep drawing until you get a card that fits.", choices = Toggle, default = 1 },
			{
				key = "handSize",
				name = "Starting hand",
				choices = { { label = "5 cards", value = 5 }, { label = "7 cards", value = 7 }, { label = "10 cards", value = 10 } },
				default = 2,
			},
		},
	},
	{
		id = "SketchGuess",
		name = "Sketch & Guess",
		module = "SketchGuess",
		category = "Party",
		description = "One draws, everyone guesses. Best with friends: bots guess but don't draw.",
		minSeats = 3,
		maxSeats = 8,
		status = "ready",
		coin = "party",
		typicalMinutes = 10,
		minMinutes = 2,
		minMoves = 1,
		houseRules = {
			{
				key = "rounds",
				name = "Rounds",
				hint = "How many times each player draws.",
				choices = { { label = "1", value = 1 }, { label = "2", value = 2 }, { label = "3", value = 3 } },
				default = 2,
			},
			{
				key = "drawSeconds",
				name = "Drawing time",
				choices = { { label = "60 s", value = 60 }, { label = "80 s", value = 80 }, { label = "120 s", value = 120 } },
				default = 2,
			},
		},
		custom = "words",
	},
	{
		id = "TriviaNight",
		name = "Trivia Night",
		module = "TriviaNight",
		category = "Party",
		description = "Race to answer questions across categories.",
		minSeats = 1,
		maxSeats = 8,
		status = "ready",
		coin = "party",
		typicalMinutes = 8,
		minMinutes = 1,
		minMoves = 5,
		houseRules = {
			{
				key = "questions",
				name = "Questions",
				choices = { { label = "5", value = 5 }, { label = "10", value = 10 }, { label = "15", value = 15 }, { label = "20", value = 20 } },
				default = 2,
			},
			{
				key = "answerSeconds",
				name = "Time to answer",
				choices = { { label = "10 s", value = 10 }, { label = "15 s", value = 15 }, { label = "25 s", value = 25 } },
				default = 2,
			},
		},
		custom = "quiz",
	},
}

local GameCatalog = {}

GameCatalog.entries = entries

function GameCatalog.get(id: string): Entry?
	for _, entry in entries do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

return GameCatalog
