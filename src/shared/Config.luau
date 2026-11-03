-- Tunable numbers for the whole experience. Change values here, not in the services.

local Config = {
	-- Party
	MaxPartySize = 8,
	InviteSeconds = 30, -- how long an invite stays valid

	-- Matches
	MaxSeats = 8, -- hard cap on seats at any table (players + bots)
	BotMoveDelay = 1.2, -- seconds a bot "thinks" before moving
	TurnSeconds = 45, -- a player who takes longer has a bot move for them

	-- Anti-spam: requests allowed per player per window
	RequestsPerWindow = 20,
	RequestWindowSeconds = 2,

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
