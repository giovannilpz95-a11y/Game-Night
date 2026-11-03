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
}

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
