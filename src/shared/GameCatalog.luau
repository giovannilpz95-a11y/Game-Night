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
		description = "Get three in a row. You only keep 3 marks, so the oldest vanishes and there are no ties.",
		minSeats = 2,
		maxSeats = 2,
		turnSeconds = 20,
		status = "ready",
		coin = "arcade",
		typicalMinutes = 2, -- infinite style: about 17 moves on average
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
		-- Off for launch (Giovanni, 2026-11-04). The game is built and tested; set this to
		-- "ready" to turn it back on.
		-- Held from launch: freehand drawing counts as "free-form user creation", which
		-- Roblox limits to 16+ for the whole experience. See docs/Launch.md.
		status = "soon",
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
	{
		id = "Whodunit",
		name = "Whodunit",
		module = "Whodunit",
		category = "Strategy",
		description = "Someone swiped the Golden Trophy. Find who, with what, and where.",
		minSeats = 3,
		maxSeats = 6,
		turnSeconds = 45,
		status = "ready",
		coin = "whodunit",
		typicalMinutes = 10,
		minMinutes = 1,
		minMoves = 8,
	},
	{
		id = "Estates",
		name = "Property Party",
		module = "Estates",
		category = "Board",
		description = "Buy streets, build hotels, trade deals and bankrupt your friends.",
		minSeats = 2,
		maxSeats = 8,
		turnSeconds = 25,
		status = "ready",
		coin = "property",
		typicalMinutes = 25,
		minMinutes = 3,
		minMoves = 30,
	},
	{
		id = "WordTiles",
		name = "Word Tiles",
		module = "WordTiles",
		category = "Word",
		description = "Build crossing words from your letter tiles. Big words on bright squares score big.",
		minSeats = 2,
		maxSeats = 4,
		turnSeconds = 90,
		status = "ready",
		coin = "wordtiles",
		typicalMinutes = 15,
		minMinutes = 0.5, -- bot turns are quick, so gate on moves rather than time
		minMoves = 12,
	},
	{
		id = "Conquest",
		name = "Conquest Isles",
		module = "Conquest",
		category = "Strategy",
		description = "Roll dice, take territories and hold whole regions to rule the Shattered Isles.",
		minSeats = 2,
		maxSeats = 6,
		status = "ready", -- turns are timed by the game itself (Conquest.TURN_SECONDS)
		coin = "conquest",
		typicalMinutes = 20,
		minMinutes = 3,
		minMoves = 30,
		houseRules = {
			{
				key = "turnLength",
				name = "Turn length",
				hint = "Time for a whole turn: reinforce, attack and fortify.",
				choices = { { label = "60 s", value = 60 }, { label = "90 s", value = 90 }, { label = "150 s", value = 150 } },
				default = 2,
			},
		},
	},
	{
		id = "Hexlands",
		name = "Hexlands",
		module = "Hexlands",
		category = "Board",
		description = "Settle a hex island: roll for resources, build roads and towns, trade with friends.",
		minSeats = 2,
		maxSeats = 4,
		turnSeconds = 45,
		status = "ready",
		coin = "hexlands",
		typicalMinutes = 20,
		minMinutes = 1, -- a finished game always lasts longer than this; moves are the real gate
		minMoves = 40,
	},
	{
		id = "Speed",
		name = "Speed",
		module = "Speed",
		category = "Cards",
		description = "No turns, just hands. Race to play every card first.",
		minSeats = 2,
		maxSeats = 2,
		turnSeconds = 15,
		status = "ready",
		coin = "cards",
		typicalMinutes = 4,
		minMinutes = 0.5,
		minMoves = 10,
	},
	{
		id = "Spoons",
		name = "Spoons",
		module = "Spoons",
		category = "Cards",
		description = "Pass cards, make four of a kind, grab a spoon before they're gone!",
		minSeats = 3,
		maxSeats = 8,
		status = "ready",
		coin = "cards",
		typicalMinutes = 6,
		minMinutes = 1,
		minMoves = 15,
		houseRules = {
			{
				key = "passSeconds",
				name = "Passing speed",
				hint = "How long everyone gets to pass a card each round.",
				choices = { { label = "Fast (5 s)", value = 5 }, { label = "Normal (8 s)", value = 8 }, { label = "Slow (12 s)", value = 12 } },
				default = 2,
			},
		},
	},
	{
		id = "GoFish",
		name = "Go Fish",
		module = "GoFish",
		category = "Cards",
		description = "Ask for cards, collect sets of four. Got any 7s?",
		minSeats = 2,
		maxSeats = 6,
		turnSeconds = 20,
		status = "ready",
		coin = "cards",
		typicalMinutes = 6,
		minMinutes = 1,
		minMoves = 10,
	},
	{
		id = "War",
		name = "War",
		module = "War",
		category = "Cards",
		description = "Flip, compare, and battle for the whole deck.",
		minSeats = 2,
		maxSeats = 4,
		turnSeconds = 10,
		status = "ready",
		coin = "cards",
		typicalMinutes = 4,
		minMinutes = 1,
		minMoves = 20,
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
