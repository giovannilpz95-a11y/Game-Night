-- What the stats profile shows for each game, on top of the stats every game gets
-- (played, wins, losses, draws, streaks, time played, fastest win, wins vs people).
--
-- `extra` lists the game's own stats. A game reports them in one of two ways (see
-- GameModule): counters it bumps during play with GameModule.addStat / GameModule.maxStat,
-- or getMatchStats(state) at the end. The server saves only the keys listed here.
--   kind = "sum": added up over every match ("Checkmates")
--   kind = "max": the best single match ("Best word")
--
-- `score` turns the game's getScores into a "best score" stat. lower = true when a low
-- score is better (Hearts). Games without `score` don't save one.
--
-- Labels are what players read; keys are saved in profiles, so never rename a key.

export type StatDef = { key: string, label: string, kind: "sum" | "max" }
export type GameStats = { extra: { StatDef }?, score: { label: string, lower: boolean? }? }

local StatsCatalog = {}

StatsCatalog.MaxValue = 1e7 -- anything a game reports is clamped to 0..MaxValue

StatsCatalog.games = {
	TicTacToe = {},
	FourInARow = {},
	Chess = {
		extra = {
			{ key = "checkmates", label = "Checkmates", kind = "sum" },
			{ key = "captures", label = "Pieces captured", kind = "sum" },
		},
	},
	Checkers = {
		extra = {
			{ key = "captures", label = "Pieces captured", kind = "sum" },
			{ key = "kings", label = "Kings crowned", kind = "sum" },
		},
	},
	ColorClash = {
		extra = {
			{ key = "cards", label = "Cards played", kind = "sum" },
			{ key = "wilds", label = "Wilds played", kind = "sum" },
		},
	},
	SketchGuess = { score = { label = "Best score" } },
	TriviaNight = {
		extra = {
			{ key = "correct", label = "Right answers", kind = "sum" },
			{ key = "streak", label = "Longest answer streak", kind = "max" },
		},
		score = { label = "Best score" },
	},
	Werewolf = {
		extra = {
			{ key = "wolfWins", label = "Wins as a werewolf", kind = "sum" },
			{ key = "found", label = "Wolves found as the Seer", kind = "sum" },
			{ key = "saves", label = "Players saved as the Guardian", kind = "sum" },
			{ key = "survived", label = "Games survived to the end", kind = "sum" },
		},
	},
	Whodunit = {
		extra = {
			{ key = "solved", label = "Cases solved", kind = "sum" },
			{ key = "wrong", label = "Wrong accusations", kind = "sum" },
		},
	},
	Estates = {
		extra = {
			{ key = "properties", label = "Most properties owned", kind = "max" },
			{ key = "bankrupt", label = "Times bankrupt", kind = "sum" },
		},
		score = { label = "Best net worth" },
	},
	WordTiles = {
		extra = {
			{ key = "words", label = "Words played", kind = "sum" },
			{ key = "bestWord", label = "Best word (points)", kind = "max" },
			{ key = "bingos", label = "All-tile plays", kind = "sum" },
		},
		score = { label = "Best score" },
	},
	Conquest = {
		extra = {
			{ key = "knockouts", label = "Players knocked out", kind = "sum" },
		},
		score = { label = "Most territories held" },
	},
	Hexlands = {
		extra = {
			{ key = "roads", label = "Roads built", kind = "sum" },
			{ key = "towns", label = "Towns built", kind = "sum" },
		},
		score = { label = "Most points" },
	},
	Speed = {
		extra = { { key = "cards", label = "Cards played", kind = "sum" } },
	},
	Spoons = {},
	GoFish = {
		extra = { { key = "books", label = "Books collected", kind = "sum" } },
	},
	War = {},
	Cheat = {},
	President = {},
	SlapStack = {},
	Hearts = {
		extra = { { key = "moons", label = "Moons shot", kind = "sum" } },
		score = { label = "Best (lowest) score", lower = true },
	},
	Spades = {},
	ThirtyOne = {},
	Palace = {},
	OldMaid = {
		extra = {
			{ key = "pairs", label = "Pairs made", kind = "sum" },
			{ key = "stuck", label = "Stuck with the Old Maid", kind = "sum" },
		},
	},
	Snap = {
		extra = { { key = "snaps", label = "Good snaps", kind = "sum" } },
	},
	GinRummy = {
		extra = {
			{ key = "gins", label = "Gins", kind = "sum" },
			{ key = "undercuts", label = "Undercuts", kind = "sum" },
		},
		score = { label = "Best score" },
	},
	OhHell = {
		extra = { { key = "exact", label = "Bids made exactly", kind = "sum" } },
		score = { label = "Best score" },
	},
} :: { [string]: GameStats }

function StatsCatalog.get(gameId: string): GameStats
	return StatsCatalog.games[gameId] or {}
end

function StatsCatalog.def(gameId: string, key: string): StatDef?
	for _, def in StatsCatalog.get(gameId).extra or {} do
		if def.key == key then
			return def
		end
	end
	return nil
end

return StatsCatalog
