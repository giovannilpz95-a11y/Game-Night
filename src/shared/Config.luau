-- Tunable numbers for the whole experience. Change values here, not in the services.

local Config = {
	-- Party
	MaxPartySize = 8,
	InviteSeconds = 30, -- how long an invite stays valid

	-- Matches
	MaxSeats = 8, -- hard cap on seats at any table (players + bots)
	BotMoveDelay = 1.2, -- seconds a bot "thinks" before moving
	TurnSeconds = 45, -- a player who takes longer has a bot move for them
	MaxTypedText = 60, -- longest typed guess the server will filter

	-- 3D tables (TableService). Tables tagged "GameTable" in Workspace are used first;
	-- otherwise a template from ReplicatedStorage.Assets (a model whose name has "Square"
	-- or "Round" in it) is placed, or plain tables are built in code at TableOrigin.
	TableTag = "GameTable",
	TableOrigin = Vector3.new(0, 0, -60), -- where code-built tables go if none exist
	TableSpacing = 22,
	-- Code-built / template tables: { zone, shape } in order. Square4 = 4 seats, Round8 = 8.
	DefaultTables = {
		{ zone = "Quick", shape = "Square4" },
		{ zone = "Quick", shape = "Square4" },
		{ zone = "Strategy", shape = "Square4" },
		{ zone = "Strategy", shape = "Square4" },
		{ zone = "Strategy", shape = "Round8" },
		{ zone = "Board", shape = "Round8" },
		{ zone = "Board", shape = "Round8" },
		{ zone = "Word", shape = "Square4" },
		{ zone = "Cards", shape = "Square4" },
		{ zone = "Cards", shape = "Round8" },
		{ zone = "Cards", shape = "Round8" },
		{ zone = "Party", shape = "Round8" },
		{ zone = "Party", shape = "Round8" },
	},
	TableColumns = 5, -- code-built tables are laid out in rows of this many
	BoardSize = 6, -- studs across a square 3D board
	TableHoldSeconds = 4, -- after a match: the final board and bots stay this long
	-- Games with a 3D board on the table (client/Table3D and server/Tables/Boards).
	-- Other games still seat everyone at the table, but play in the 2D view.
	Boards3D = { Chess = true, Checkers = true, FourInARow = true, TicTacToe = true },
	-- Games whose table shows the game in the world (board, cards, a screen) for everyone
	-- to watch, while seated players play in the 2D view ("Table view" to look up).
	TableScenes = {
		ColorClash = true,
		Speed = true,
		Spoons = true,
		War = true,
		GoFish = true,
		Cheat = true,
		President = true,
		SlapStack = true,
		Hearts = true,
		Spades = true,
		ThirtyOne = true,
		Palace = true,
		Estates = true,
		Hexlands = true,
		Conquest = true,
		Whodunit = true,
		WordTiles = true,
		TriviaNight = true,
		SketchGuess = true,
	},

	-- Saved progress (DataService). Changing the store name starts everyone from zero.
	ProfileStoreName = "Profiles_v1",
	AutosaveSeconds = 60,
	ProfileLockRetries = 6, -- tries to load a profile another server still holds...
	ProfileLockRetryDelay = 5, -- ...this many seconds apart, then asks the player to rejoin
	SaveInStudio = true, -- false = Studio play sessions start fresh and never save

	-- Voice servers: reserved servers where everyone can use voice chat (see docs/VoiceServers.md)
	Voice = {
		Enabled = true,
		PlaceId = 0, -- 0 = voice servers are reserved copies of this place; or a second place's id
		LobbyPlaceId = 0, -- 0 = this place. Only set it if you use a second place for voice
		Capacity = 20, -- players per voice server; keep at or under the place's Max Players
		HeartbeatSeconds = 10, -- how often a voice server reports its player count
		ServerTtlSeconds = 45, -- a server that stops reporting this long is skipped
		HoldSeconds = 60, -- seats saved for a party while it teleports in
		TransferTtlSeconds = 300, -- how long a party's transfer record lives
		EligibilityCacheSeconds = 60,
		TeleportRetries = 3,
		StudioActsAsVoiceServer = false, -- true = Studio play tests show the voice server UI
	},
	TeleportLockRetries = 15, -- after a teleport the old server may still be saving...
	TeleportLockRetryDelay = 2, -- ...so retry the profile lock faster than a normal join

	-- Anti-spam: requests allowed per player per window
	RequestsPerWindow = 20,
	RequestWindowSeconds = 2,

	-- Bot difficulty the party leader can pick. Each game decides what these mean.
	BotLevels = { "easy", "medium", "hard" },
	DefaultBotLevel = "medium",

	BotNames = {
		"Bot Ava",
		"Bot Milo",
		"Bot Juno",
		"Bot Rex",
		"Bot Pip",
		"Bot Nova",
		"Bot Ziggy",
		"Bot Luna",
	},
}

return Config
