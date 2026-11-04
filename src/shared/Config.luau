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

	-- Saved progress (DataService). Changing the store name starts everyone from zero.
	ProfileStoreName = "Profiles_v1",
	AutosaveSeconds = 60,
	ProfileLockRetries = 6, -- tries to load a profile another server still holds...
	ProfileLockRetryDelay = 5, -- ...this many seconds apart, then asks the player to rejoin
	SaveInStudio = true, -- false = Studio play sessions start fresh and never save

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
