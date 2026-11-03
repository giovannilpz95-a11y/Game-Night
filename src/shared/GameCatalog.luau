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
	status: "ready" | "soon",
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
		status = "ready",
	},
	{
		id = "Chess",
		name = "Chess",
		category = "Strategy",
		description = "The classic game of kings.",
		minSeats = 2,
		maxSeats = 2,
		status = "soon",
	},
	{
		id = "Checkers",
		name = "Checkers",
		category = "Strategy",
		description = "Jump and crown your way to victory.",
		minSeats = 2,
		maxSeats = 2,
		status = "soon",
	},
	{
		id = "FourInARow",
		name = "Four in a Row",
		category = "Quick",
		description = "Drop discs and connect four.",
		minSeats = 2,
		maxSeats = 2,
		status = "soon",
	},
	{
		id = "ColorClash",
		name = "Color Clash",
		category = "Cards",
		description = "Match colors and numbers, empty your hand first.",
		minSeats = 2,
		maxSeats = 8,
		status = "soon",
	},
	{
		id = "SketchGuess",
		name = "Sketch & Guess",
		category = "Party",
		description = "One draws, everyone guesses.",
		minSeats = 3,
		maxSeats = 8,
		status = "soon",
	},
	{
		id = "TriviaNight",
		name = "Trivia Night",
		category = "Party",
		description = "Race to answer questions across categories.",
		minSeats = 1,
		maxSeats = 8,
		status = "soon",
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
