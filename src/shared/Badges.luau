-- Game Night's badges: one-time achievements shown in the stats profile. Each one reads a
-- number from the stats view (server Core/Stats.view) and is earned when it reaches `goal`.
-- Shared so the client can draw progress bars with the same rules the server checks.
--
-- `stat` is a path into the view: "totals.wins", "games.Chess.extra.checkmates",
-- "level", "social.friendsJoined", "currency.gemsEarned".
-- tier: 1 bronze, 2 silver, 3 gold. Gems paid per tier are in Economy.BadgeGems.
-- Ids are saved in profiles, so never change one; names and descriptions can change.
--
-- Roblox badges (optional, shown on the experience page): create one in the Creator Hub
-- and paste its id in `roblox`. 0 = in-game badge only.

local GameCatalog = require(script.Parent.GameCatalog)

export type Badge = {
	id: string,
	name: string,
	desc: string,
	icon: string,
	tier: number,
	stat: string,
	goal: number,
	roblox: number?,
	gameId: string?, -- for grouping in the window; nil = general
}

local Badges = {}

local readyGames = 0
for _, entry in GameCatalog.entries do
	if entry.status == "ready" then
		readyGames += 1
	end
end
Badges.AllGames = readyGames

Badges.TierNames = { "Bronze", "Silver", "Gold" }
Badges.TierColors = {
	Color3.fromRGB(205, 127, 50),
	Color3.fromRGB(200, 205, 215),
	Color3.fromRGB(255, 196, 64),
}

Badges.list = {
	-- Getting started
	{ id = "first_game", name = "Welcome In", desc = "Finish your first game", icon = "🎲", tier = 1, stat = "totals.matches", goal = 1, roblox = 0 },
	{ id = "first_win", name = "First Win", desc = "Win a game", icon = "🏆", tier = 1, stat = "totals.wins", goal = 1, roblox = 0 },
	{ id = "matches_25", name = "Regular", desc = "Finish 25 games", icon = "🪑", tier = 1, stat = "totals.matches", goal = 25 },
	{ id = "matches_100", name = "Game Night Fan", desc = "Finish 100 games", icon = "🌙", tier = 2, stat = "totals.matches", goal = 100 },
	{ id = "matches_500", name = "Night Owl", desc = "Finish 500 games", icon = "🦉", tier = 3, stat = "totals.matches", goal = 500 },
	-- Winning
	{ id = "wins_10", name = "Winner", desc = "Win 10 games", icon = "🥉", tier = 1, stat = "totals.wins", goal = 10 },
	{ id = "wins_50", name = "Champion", desc = "Win 50 games", icon = "🥈", tier = 2, stat = "totals.wins", goal = 50 },
	{ id = "wins_250", name = "Legend", desc = "Win 250 games", icon = "🥇", tier = 3, stat = "totals.wins", goal = 250 },
	{ id = "streak_3", name = "Hot Streak", desc = "Win 3 games in a row", icon = "🔥", tier = 1, stat = "totals.bestStreak", goal = 3 },
	{ id = "streak_7", name = "Unstoppable", desc = "Win 7 games in a row", icon = "⚡", tier = 2, stat = "totals.bestStreak", goal = 7 },
	{ id = "human_wins_25", name = "Table Boss", desc = "Win 25 games against other people", icon = "👑", tier = 2, stat = "totals.humanWins", goal = 25 },
	-- Variety and time
	{ id = "tried_5", name = "Explorer", desc = "Play 5 different games", icon = "🧭", tier = 1, stat = "totals.gamesTried", goal = 5 },
	{ id = "tried_12", name = "Game Buff", desc = "Play 12 different games", icon = "🗺", tier = 2, stat = "totals.gamesTried", goal = 12 },
	{ id = "tried_all", name = "Try Everything", desc = "Play every game in Game Night", icon = "🌟", tier = 3, stat = "totals.gamesTried", goal = readyGames },
	{ id = "hours_5", name = "Five Hours In", desc = "Play for 5 hours", icon = "⏰", tier = 1, stat = "totals.minutes", goal = 300 },
	{ id = "hours_24", name = "Marathon", desc = "Play for 24 hours", icon = "🏃", tier = 3, stat = "totals.minutes", goal = 1440 },
	{ id = "level_5", name = "Level 5", desc = "Reach level 5", icon = "⭐", tier = 1, stat = "level", goal = 5 },
	{ id = "level_10", name = "Level 10", desc = "Reach level 10", icon = "🌠", tier = 2, stat = "level", goal = 10 },
	{ id = "level_25", name = "Level 25", desc = "Reach level 25", icon = "💫", tier = 3, stat = "level", goal = 25 },
	{ id = "login_7", name = "Week Streak", desc = "Log in 7 days in a row", icon = "📅", tier = 1, stat = "totals.bestLoginStreak", goal = 7 },
	{ id = "login_30", name = "Monthly Regular", desc = "Log in 30 days in a row", icon = "🗓", tier = 3, stat = "totals.bestLoginStreak", goal = 30 },
	-- Friends
	{ id = "humans_10", name = "Friendly", desc = "Play 10 games with other people", icon = "🤝", tier = 1, stat = "totals.humanMatches", goal = 10 },
	{ id = "invite_1", name = "Party Starter", desc = "Someone joins your party from your invite", icon = "🎉", tier = 1, stat = "social.friendsJoined", goal = 1 },
	{ id = "invite_10", name = "Social Butterfly", desc = "10 people join your party from your invites", icon = "🦋", tier = 2, stat = "social.friendsJoined", goal = 10 },
	-- Wallet
	{ id = "gems_100", name = "Gem Collector", desc = "Earn 100 Gems by playing", icon = "💎", tier = 1, stat = "currency.gemsEarned", goal = 100 },
	{ id = "coins_5000", name = "Coin Hoarder", desc = "Earn 5,000 Coins", icon = "🪙", tier = 2, stat = "currency.coinsEarned", goal = 5000 },
	{ id = "shopper", name = "Shopper", desc = "Spend 500 Coins in the shops", icon = "🛍", tier = 1, stat = "currency.coinsSpent", goal = 500 },
	-- Games
	{ id = "ttt_10", name = "Three in a Row", desc = "Win 10 games of Tic-Tac-Toe", icon = "❌", tier = 1, stat = "games.TicTacToe.wins", goal = 10, gameId = "TicTacToe" },
	{ id = "fiar_10", name = "Four Real", desc = "Win 10 games of Four in a Row", icon = "🔴", tier = 1, stat = "games.FourInARow.wins", goal = 10, gameId = "FourInARow" },
	{ id = "chess_mate", name = "Checkmate!", desc = "Win a chess game by checkmate", icon = "♟", tier = 1, stat = "games.Chess.extra.checkmates", goal = 1, gameId = "Chess" },
	{ id = "chess_mate_25", name = "Grandmaster", desc = "Checkmate 25 times", icon = "♚", tier = 3, stat = "games.Chess.extra.checkmates", goal = 25, gameId = "Chess" },
	{ id = "checkers_kings", name = "King Me", desc = "Crown 10 kings in Checkers", icon = "🔱", tier = 1, stat = "games.Checkers.extra.kings", goal = 10, gameId = "Checkers" },
	{ id = "colorclash_10", name = "Color Master", desc = "Win 10 games of Color Clash", icon = "🌈", tier = 1, stat = "games.ColorClash.wins", goal = 10, gameId = "ColorClash" },
	{ id = "colorclash_wilds", name = "Wild Card", desc = "Play 50 wilds in Color Clash", icon = "🃏", tier = 2, stat = "games.ColorClash.extra.wilds", goal = 50, gameId = "ColorClash" },
	{ id = "trivia_100", name = "Know-It-All", desc = "Get 100 Trivia Night answers right", icon = "🧠", tier = 2, stat = "games.TriviaNight.extra.correct", goal = 100, gameId = "TriviaNight" },
	{ id = "whodunit_5", name = "Detective", desc = "Solve 5 cases in Whodunit", icon = "🔍", tier = 2, stat = "games.Whodunit.extra.solved", goal = 5, gameId = "Whodunit" },
	{ id = "estates_10", name = "Tycoon", desc = "Own 10 properties at once in Property Party", icon = "🏠", tier = 2, stat = "games.Estates.extra.properties", goal = 10, gameId = "Estates" },
	{ id = "wordtiles_100", name = "Wordsmith", desc = "Play 100 words in Word Tiles", icon = "🔤", tier = 2, stat = "games.WordTiles.extra.words", goal = 100, gameId = "WordTiles" },
	{ id = "wordtiles_bingo", name = "All In", desc = "Use all your tiles in one Word Tiles play", icon = "🎯", tier = 2, stat = "games.WordTiles.extra.bingos", goal = 1, gameId = "WordTiles" },
	{ id = "conquest_5", name = "Warlord", desc = "Win 5 games of Conquest Isles", icon = "⚔", tier = 2, stat = "games.Conquest.wins", goal = 5, gameId = "Conquest" },
	{ id = "hexlands_towns", name = "City Planner", desc = "Build 20 towns in Hexlands", icon = "🏘", tier = 2, stat = "games.Hexlands.extra.towns", goal = 20, gameId = "Hexlands" },
	{ id = "speed_200", name = "Quick Hands", desc = "Play 200 cards in Speed", icon = "💨", tier = 1, stat = "games.Speed.extra.cards", goal = 200, gameId = "Speed" },
	{ id = "gofish_50", name = "Gone Fishing", desc = "Collect 50 books in Go Fish", icon = "🐟", tier = 1, stat = "games.GoFish.extra.books", goal = 50, gameId = "GoFish" },
	{ id = "hearts_moon", name = "Shoot the Moon", desc = "Shoot the moon in Hearts", icon = "🌕", tier = 2, stat = "games.Hearts.extra.moons", goal = 1, gameId = "Hearts" },
	{ id = "card_shark", name = "Card Shark", desc = "Win 50 card games", icon = "🦈", tier = 3, stat = "totals.cardWins", goal = 50 },
} :: { Badge }

function Badges.get(id: string): Badge?
	for _, badge in Badges.list do
		if badge.id == id then
			return badge
		end
	end
	return nil
end

-- Reads `path` ("games.Chess.extra.checkmates") from a stats view. Missing = 0.
function Badges.value(view: any, path: string): number
	local node = view
	for part in string.gmatch(path, "[^%.]+") do
		if type(node) ~= "table" then
			return 0
		end
		node = node[part]
	end
	return if type(node) == "number" then node else 0
end

-- How far along a badge is: current (capped at goal), goal.
function Badges.progress(view: any, badge: Badge): (number, number)
	return math.min(Badges.value(view, badge.stat), badge.goal), badge.goal
end

-- Badges whose goal the view reaches but that aren't in `owned` yet.
function Badges.newlyEarned(view: any, owned: { [string]: any }): { Badge }
	local out = {}
	for _, badge in Badges.list do
		if not owned[badge.id] and Badges.value(view, badge.stat) >= badge.goal then
			table.insert(out, badge)
		end
	end
	return out
end

return Badges
