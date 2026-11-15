-- Game Night's achievements: tiered milestones, up to five tiers each (Bronze, Silver, Gold,
-- Platinum, Diamond). Every tier is a badge with a bigger goal and a bigger reward than the
-- one before. There are general achievements (games, wins, streaks, quests, friends...) and
-- achievements for every game (play it, win it, a win streak in it, and the game's own
-- signature stats from StatsCatalog).
--
-- Each achievement reads one number from the stats view (server Core/Stats.view) at `stat`,
-- a path such as "totals.wins" or "games.Chess.extra.checkmates", and earns tier N when the
-- number reaches goals[N]. Shared so the client draws progress with the same rules the
-- server checks. Rewards per tier are in Economy.AchievementRewards; the server pays them
-- in Core/AchievementRewards. Research: vault "05 Research/Quests and Achievements".
--
-- Ids are saved in profiles (data.achievements[id] = { t = tier, at = time }), so never
-- change an id. Names, icons, goals and descriptions can change (lowering a goal just
-- awards the tier the next time stats are checked).
--
-- Roblox badges (shown on the experience page): `roblox = { [tier] = badgeId }`. Only a few
-- highlights get one (Giovanni, 2026-11-15); every tier is an in-game badge either way.

local GameCatalog = require(script.Parent.GameCatalog)
local GameArt = require(script.Parent.GameArt)

export type Achievement = {
	id: string,
	name: string,
	desc: string, -- "{n}" becomes the tier's goal: "Win {n} games"
	icon: string,
	stat: string,
	goals: { number }, -- one per tier, each bigger than the last (1 to 5 tiers)
	gameId: string?, -- nil = general
	hidden: boolean?, -- a secret: shown as ??? until the first tier
	title: string?, -- ShopCatalog title item granted at the top tier
	roblox: { [number]: number }?, -- Roblox badge id per tier (optional)
	group: string?, -- general achievements: which section of the window
}

local Achievements = {}

Achievements.MaxTier = 5
Achievements.TierNames = { "Bronze", "Silver", "Gold", "Platinum", "Diamond" }
Achievements.TierShort = { "I", "II", "III", "IV", "V" }
Achievements.TierColors = {
	Color3.fromRGB(214, 136, 72),
	Color3.fromRGB(205, 212, 226),
	Color3.fromRGB(255, 205, 64),
	Color3.fromRGB(86, 232, 196),
	Color3.fromRGB(150, 205, 255),
}
-- Points per tier (the "trophy score" on your profile). Bigger tiers are worth more.
Achievements.TierPoints = { 10, 20, 40, 80, 150 }
-- A game is "mastered" when every one of its achievements reaches this tier: that pays
-- the game's mastery title (ShopCatalog "mastery_title_<gameId>").
Achievements.MasteryTier = 3

Achievements.Groups = {
	{ key = "play", name = "Playing" },
	{ key = "win", name = "Winning" },
	{ key = "social", name = "Friends" },
	{ key = "habit", name = "Every day" },
	{ key = "wallet", name = "Collecting" },
}

local readyGames: { GameCatalog.Entry } = {}
for _, entry in GameCatalog.entries do
	if entry.status == "ready" then
		table.insert(readyGames, entry)
	end
end
Achievements.AllGames = #readyGames

local list: { Achievement } = {
	-- Playing
	{ id = "matches", group = "play", name = "Regular", desc = "Finish {n} games", icon = "🎲", stat = "totals.matches", goals = { 1, 25, 100, 500, 2000 }, title = "ach_title_lifer" },
	{ id = "minutes", group = "play", name = "Time Flies", desc = "Play for {n} minutes", icon = "⏰", stat = "totals.minutes", goals = { 60, 300, 1440, 6000, 18000 } },
	{ id = "tried", group = "play", name = "Explorer", desc = "Play {n} different games", icon = "🧭", stat = "totals.gamesTried", goals = { 3, 6, 12, 20, #readyGames }, title = "ach_title_explorer" },
	{ id = "level", group = "play", name = "Level Up", desc = "Reach level {n}", icon = "⭐", stat = "level", goals = { 5, 10, 25, 50, 100 } },
	{ id = "mastered", group = "play", name = "Master of Games", desc = "Master {n} games (every achievement of a game at Gold)", icon = "🎓", stat = "totals.mastered", goals = { 1, 3, 6, 12, 20 } },
	-- Winning
	{ id = "wins", group = "win", name = "Winner", desc = "Win {n} games", icon = "🏆", stat = "totals.wins", goals = { 1, 10, 50, 250, 1000 }, title = "ach_title_legend" },
	{ id = "streak", group = "win", name = "Hot Streak", desc = "Win {n} games in a row", icon = "🔥", stat = "totals.bestStreak", goals = { 3, 5, 7, 10, 15 }, title = "ach_title_unstoppable" },
	{ id = "human_wins", group = "win", name = "Table Boss", desc = "Win {n} games against other people", icon = "👑", stat = "totals.humanWins", goals = { 1, 10, 25, 100, 500 }, title = "ach_title_tableboss" },
	{ id = "card_wins", group = "win", name = "Card Shark", desc = "Win {n} card games", icon = "🦈", stat = "totals.winsBy.Cards", goals = { 5, 25, 100, 500, 2000 }, title = "ach_title_cardshark" },
	{ id = "strategy_wins", group = "win", name = "Strategist", desc = "Win {n} strategy games", icon = "🧠", stat = "totals.winsBy.Strategy", goals = { 3, 15, 50, 200, 750 } },
	{ id = "party_plays", group = "win", name = "Life of the Party", desc = "Finish {n} party games", icon = "🥳", stat = "totals.playsBy.Party", goals = { 3, 15, 50, 200, 750 } },
	-- Friends
	{ id = "human_matches", group = "social", name = "Friendly", desc = "Play {n} games with other people", icon = "🤝", stat = "totals.humanMatches", goals = { 1, 10, 50, 250, 1000 } },
	{ id = "invites", group = "social", name = "Party Starter", desc = "{n} people join your party from your invites", icon = "🎉", stat = "social.friendsJoined", goals = { 1, 3, 10, 25, 50 }, title = "ach_title_social" },
	-- Every day
	{ id = "quests", group = "habit", name = "Quest Hunter", desc = "Finish {n} quests", icon = "📜", stat = "totals.questsDone", goals = { 5, 25, 100, 500, 1500 }, title = "ach_title_questmaster" },
	{ id = "sweeps", group = "habit", name = "Clean Sweep", desc = "Finish every daily quest on {n} days", icon = "🧹", stat = "totals.dailySweeps", goals = { 1, 7, 30, 100, 300 } },
	{ id = "login", group = "habit", name = "Regular Visitor", desc = "Log in {n} days in a row", icon = "📅", stat = "totals.bestLoginStreak", goals = { 3, 7, 14, 30, 100 } },
	{ id = "days", group = "habit", name = "Game Nights", desc = "Play on {n} different days", icon = "🌙", stat = "totals.daysPlayed", goals = { 3, 10, 30, 100, 365 } },
	-- Collecting
	{ id = "gems", group = "wallet", name = "Gem Collector", desc = "Earn {n} Gems by playing", icon = "💎", stat = "currency.gemsEarned", goals = { 100, 500, 2000, 5000, 15000 } },
	{ id = "coins", group = "wallet", name = "Coin Hoarder", desc = "Earn {n} Coins", icon = "💰", stat = "currency.coinsEarned", goals = { 1000, 5000, 25000, 100000, 500000 } },
	{ id = "shopper", group = "wallet", name = "Shopper", desc = "Spend {n} Coins in the shops", icon = "🛍", stat = "currency.coinsSpent", goals = { 500, 2500, 10000, 50000, 200000 } },
}

-- Every game gets these three, named after the game (GameCatalog names can change).
local PLAYED_GOALS = { 1, 10, 50, 200, 500 }
local WINS_GOALS = { 1, 10, 50, 150, 500 }
local STREAK_GOALS = { 2, 3, 5, 8, 12 }

-- Each game's signature achievements, from its own stats (StatsCatalog keys). `best` =
-- the stat is a "max" (best single match) or the game's best score.
local signature: { [string]: { any } } = {
	Chess = {
		{ key = "checkmates", name = "Checkmate!", desc = "Checkmate {n} times", icon = "👑", goals = { 1, 10, 25, 100, 250 } },
		{ key = "captures", name = "Piece Taker", desc = "Capture {n} pieces", icon = "🗡", goals = { 25, 100, 500, 2000, 5000 } },
	},
	Checkers = {
		{ key = "kings", name = "King Me", desc = "Crown {n} kings", icon = "🔱", goals = { 1, 10, 50, 200, 500 } },
		{ key = "captures", name = "Jumper", desc = "Capture {n} pieces", icon = "🦘", goals = { 25, 100, 500, 2000, 5000 } },
	},
	ColorClash = {
		{ key = "wilds", name = "Wild Card", desc = "Play {n} wilds", icon = "🌈", goals = { 5, 50, 200, 750, 2000 } },
		{ key = "cards", name = "Card Thrower", desc = "Play {n} cards", icon = "🃏", goals = { 50, 250, 1000, 5000, 15000 } },
	},
	TriviaNight = {
		{ key = "correct", name = "Know-It-All", desc = "Get {n} answers right", icon = "🧠", goals = { 10, 100, 500, 2000, 5000 } },
		{ key = "streak", name = "On a Roll", desc = "Get {n} answers right in a row", icon = "⚡", goals = { 3, 5, 8, 12, 15 }, best = true },
	},
	Werewolf = {
		{ key = "wolfWins", name = "Pack Leader", desc = "Win {n} games as a werewolf", icon = "🐺", goals = { 1, 5, 20, 50, 150 } },
		{ key = "found", name = "Seer's Eye", desc = "Find {n} wolves as the Seer", icon = "🔮", goals = { 1, 10, 30, 100, 250 } },
		{ key = "saves", name = "Guardian", desc = "Save {n} players", icon = "🛡", goals = { 1, 10, 30, 100, 250 } },
	},
	FiveDice = {
		{ key = "bigFives", name = "Big Five", desc = "Roll {n} Big Fives", icon = "🎲", goals = { 1, 10, 50, 150, 400 } },
		{ key = "upperBonus", name = "Top Section", desc = "Earn {n} upper bonuses", icon = "⬆", goals = { 1, 10, 50, 200, 500 } },
		{ key = "bestScore", name = "High Roller", desc = "Score {n} points in one game", icon = "💯", goals = { 150, 200, 250, 300, 350 }, best = true, score = true },
	},
	SeaStrike = {
		{ key = "sunk", name = "Admiral", desc = "Sink {n} ships", icon = "⚓", goals = { 5, 50, 200, 750, 2000 } },
		{ key = "accuracy", name = "Sharpshooter", desc = "Finish a game with {n}% accuracy", icon = "🎯", goals = { 40, 50, 60, 70, 80 }, best = true },
	},
	Whodunit = {
		{ key = "solved", name = "Detective", desc = "Solve {n} cases", icon = "🔍", goals = { 1, 5, 25, 75, 200 } },
	},
	Estates = {
		{ key = "properties", name = "Tycoon", desc = "Own {n} properties at once", icon = "🏠", goals = { 5, 8, 12, 16, 20 }, best = true },
		{ key = "bestScore", name = "Net Worth", desc = "Finish with a net worth of {n}", icon = "💵", goals = { 2000, 4000, 7000, 10000, 15000 }, best = true, score = true },
		{ key = "bankrupt", name = "Back to Zero", desc = "Go bankrupt {n} times", icon = "📉", goals = { 1, 10, 50 }, hidden = true },
	},
	WordTiles = {
		{ key = "words", name = "Wordsmith", desc = "Play {n} words", icon = "🔤", goals = { 10, 100, 500, 2000, 5000 } },
		{ key = "bestWord", name = "Big Word", desc = "Score {n} points with one word", icon = "📖", goals = { 20, 35, 50, 70, 90 }, best = true },
		{ key = "bingos", name = "All In", desc = "Use all your tiles in one play {n} times", icon = "🎯", goals = { 1, 5, 15, 40 }, hidden = true },
	},
	Conquest = {
		{ key = "knockouts", name = "Warlord", desc = "Knock out {n} players", icon = "⚔", goals = { 1, 10, 50, 150, 400 } },
	},
	Hexlands = {
		{ key = "towns", name = "City Planner", desc = "Build {n} towns", icon = "🏘", goals = { 5, 20, 100, 300, 750 } },
		{ key = "roads", name = "Road Builder", desc = "Build {n} roads", icon = "🛤", goals = { 20, 100, 400, 1500, 4000 } },
	},
	Speed = {
		{ key = "cards", name = "Quick Hands", desc = "Play {n} cards", icon = "💨", goals = { 50, 200, 1000, 4000, 10000 } },
	},
	GoFish = {
		{ key = "books", name = "Gone Fishing", desc = "Collect {n} books", icon = "🐟", goals = { 5, 50, 200, 750, 2000 } },
	},
	Hearts = {
		{ key = "moons", name = "Shoot the Moon", desc = "Shoot the moon {n} times", icon = "🌕", goals = { 1, 3, 10, 25 }, hidden = true },
	},
	OldMaid = {
		{ key = "pairs", name = "Matchmaker", desc = "Make {n} pairs", icon = "👯", goals = { 10, 100, 500, 2000, 5000 } },
		{ key = "stuck", name = "Left Holding Her", desc = "Get stuck with the Old Maid {n} times", icon = "👵", goals = { 1, 10, 50 }, hidden = true },
	},
	Snap = {
		{ key = "snaps", name = "Snappy", desc = "Make {n} good snaps", icon = "✋", goals = { 10, 100, 500, 2000, 5000 } },
	},
	GinRummy = {
		{ key = "gins", name = "Gin!", desc = "Go gin {n} times", icon = "✨", goals = { 1, 10, 50, 150, 400 } },
		{ key = "undercuts", name = "Undercut", desc = "Undercut {n} knocks", icon = "✂", goals = { 1, 10, 50 } },
	},
	OhHell = {
		{ key = "exact", name = "Called It", desc = "Make your bid exactly {n} times", icon = "🎯", goals = { 5, 50, 200, 750, 2000 } },
	},
}
Achievements.Signature = signature

for _, entry in readyGames do
	local id = entry.id
	local icon = GameArt.icon(id)
	table.insert(list, { id = `{id}.played`, gameId = id, name = "Regular", desc = "Finish {n} games", icon = icon, stat = `games.{id}.played`, goals = PLAYED_GOALS })
	table.insert(list, { id = `{id}.wins`, gameId = id, name = "Winner", desc = "Win {n} games", icon = "🏆", stat = `games.{id}.wins`, goals = WINS_GOALS })
	table.insert(list, { id = `{id}.winstreak`, gameId = id, name = "Hot Hand", desc = "Win {n} games in a row", icon = "🔥", stat = `games.{id}.bestStreak`, goals = STREAK_GOALS })
	for _, s in signature[id] or {} do
		local stat = if s.score then `games.{id}.bestScore` else `games.{id}.extra.{s.key}`
		table.insert(list, { id = `{id}.{s.key}`, gameId = id, name = s.name, desc = s.desc, icon = s.icon, stat = stat, goals = s.goals, hidden = s.hidden })
	end
end

-- Old one-tier badges (before 2026-11-15): their stat and goal. A profile that earned one
-- gets the matching tiers marked as earned without paying again (Core/AchievementRewards).
Achievements.Legacy = {
	first_game = { "totals.matches", 1 },
	first_win = { "totals.wins", 1 },
	matches_25 = { "totals.matches", 25 },
	matches_100 = { "totals.matches", 100 },
	matches_500 = { "totals.matches", 500 },
	wins_10 = { "totals.wins", 10 },
	wins_50 = { "totals.wins", 50 },
	wins_250 = { "totals.wins", 250 },
	streak_3 = { "totals.bestStreak", 3 },
	streak_7 = { "totals.bestStreak", 7 },
	human_wins_25 = { "totals.humanWins", 25 },
	tried_5 = { "totals.gamesTried", 5 },
	tried_12 = { "totals.gamesTried", 12 },
	hours_5 = { "totals.minutes", 300 },
	hours_24 = { "totals.minutes", 1440 },
	level_5 = { "level", 5 },
	level_10 = { "level", 10 },
	level_25 = { "level", 25 },
	login_7 = { "totals.bestLoginStreak", 7 },
	login_30 = { "totals.bestLoginStreak", 30 },
	humans_10 = { "totals.humanMatches", 10 },
	invite_1 = { "social.friendsJoined", 1 },
	invite_10 = { "social.friendsJoined", 10 },
	gems_100 = { "currency.gemsEarned", 100 },
	coins_5000 = { "currency.coinsEarned", 5000 },
	shopper = { "currency.coinsSpent", 500 },
	ttt_10 = { "games.TicTacToe.wins", 10 },
	fiar_10 = { "games.FourInARow.wins", 10 },
	chess_mate = { "games.Chess.extra.checkmates", 1 },
	chess_mate_25 = { "games.Chess.extra.checkmates", 25 },
	checkers_kings = { "games.Checkers.extra.kings", 10 },
	colorclash_10 = { "games.ColorClash.wins", 10 },
	colorclash_wilds = { "games.ColorClash.extra.wilds", 50 },
	trivia_100 = { "games.TriviaNight.extra.correct", 100 },
	werewolf_alpha = { "games.Werewolf.extra.wolfWins", 5 },
	fivedice_big = { "games.FiveDice.extra.bigFives", 10 },
	seastrike_50 = { "games.SeaStrike.extra.sunk", 50 },
	whodunit_5 = { "games.Whodunit.extra.solved", 5 },
	estates_10 = { "games.Estates.extra.properties", 10 },
	wordtiles_100 = { "games.WordTiles.extra.words", 100 },
	wordtiles_bingo = { "games.WordTiles.extra.bingos", 1 },
	conquest_5 = { "games.Conquest.wins", 5 },
	hexlands_towns = { "games.Hexlands.extra.towns", 20 },
	speed_200 = { "games.Speed.extra.cards", 200 },
	gofish_50 = { "games.GoFish.extra.books", 50 },
	hearts_moon = { "games.Hearts.extra.moons", 1 },
	card_shark = { "totals.winsBy.Cards", 50 },
}

Achievements.list = list

local byId: { [string]: Achievement } = {}
local byGame: { [string]: { Achievement } } = {}
local byStat: { [string]: { Achievement } } = {}
for _, a in list do
	assert(byId[a.id] == nil, `Duplicate achievement {a.id}`)
	byId[a.id] = a
	if a.gameId then
		byGame[a.gameId] = byGame[a.gameId] or {}
		table.insert(byGame[a.gameId], a)
	end
	byStat[a.stat] = byStat[a.stat] or {}
	table.insert(byStat[a.stat], a)
end

function Achievements.get(id: string): Achievement?
	return byId[id]
end

-- A game's achievements, in order (Regular, Winner, Hot Hand, then its own).
function Achievements.forGame(gameId: string): { Achievement }
	return byGame[gameId] or {}
end

function Achievements.general(): { Achievement }
	local out = {}
	for _, a in list do
		if not a.gameId then
			table.insert(out, a)
		end
	end
	return out
end

function Achievements.withStat(stat: string): { Achievement }
	return byStat[stat] or {}
end

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end
Achievements.commas = commas

-- "Win 50 games of Chess" for a tier (the top tier when tier is past the end).
function Achievements.describe(a: Achievement, tier: number): string
	local goal = a.goals[math.clamp(tier, 1, #a.goals)]
	local text = a.desc:gsub("{n}", commas(goal))
	if a.gameId then
		local entry = GameCatalog.get(a.gameId)
		text ..= ` in {if entry then entry.name else a.gameId}`
	end
	return text
end

-- "Chess · Winner" for game achievements, the plain name otherwise.
function Achievements.fullName(a: Achievement): string
	if a.gameId then
		local entry = GameCatalog.get(a.gameId)
		return `{if entry then entry.name else a.gameId} · {a.name}`
	end
	return a.name
end

-- Reads `path` ("games.Chess.extra.checkmates") from a stats view. Missing = 0.
function Achievements.value(view: any, path: string): number
	local node = view
	for part in string.gmatch(path, "[^%.]+") do
		if type(node) ~= "table" then
			return 0
		end
		node = node[part]
	end
	return if type(node) == "number" then node else 0
end

-- The tier the stats reach (0 = none yet).
function Achievements.tierFor(a: Achievement, value: number): number
	local tier = 0
	for i, goal in a.goals do
		if value >= goal then
			tier = i
		else
			break
		end
	end
	return tier
end

-- The tier saved in `earned` (data.achievements or the view's copy).
function Achievements.earnedTier(earned: { [string]: any }?, id: string): number
	local entry = earned and earned[id]
	if type(entry) == "table" and type(entry.t) == "number" then
		return entry.t
	end
	return 0
end

-- Progress toward the next tier: (current value, next goal, next tier). When every tier
-- is earned, next tier is nil and goal is the top goal.
function Achievements.progress(view: any, a: Achievement, earnedTier: number?): (number, number, number?)
	local value = Achievements.value(view, a.stat)
	local tier = earnedTier or Achievements.tierFor(a, value)
	if tier >= #a.goals then
		return value, a.goals[#a.goals], nil
	end
	return value, a.goals[tier + 1], tier + 1
end

export type Earned = { achievement: Achievement, tier: number }

-- Tiers the view reaches that `earned` doesn't have yet, lowest first within each
-- achievement (one entry per tier, so reaching two tiers at once pays both).
function Achievements.newlyEarned(view: any, earned: { [string]: any }): { Earned }
	local out = {}
	for _, a in list do
		local have = Achievements.earnedTier(earned, a.id)
		local reach = Achievements.tierFor(a, Achievements.value(view, a.stat))
		for tier = have + 1, reach do
			table.insert(out, { achievement = a, tier = tier })
		end
	end
	return out
end

-- Trophy score, badges earned and badges in total.
function Achievements.score(earned: { [string]: any }): (number, number, number)
	local points, badges, total = 0, 0, 0
	for _, a in list do
		total += #a.goals
		local tier = Achievements.earnedTier(earned, a.id)
		badges += tier
		for t = 1, tier do
			points += Achievements.TierPoints[t] or 0
		end
	end
	return points, badges, total
end

-- How far into a game's achievements you are: (tiers earned, tiers in total).
function Achievements.gameProgress(earned: { [string]: any }, gameId: string): (number, number)
	local have, total = 0, 0
	for _, a in Achievements.forGame(gameId) do
		total += #a.goals
		have += Achievements.earnedTier(earned, a.id)
	end
	return have, total
end

-- True when every achievement of the game is at MasteryTier or higher (or its top tier
-- when it has fewer tiers).
function Achievements.mastered(earned: { [string]: any }, gameId: string): boolean
	local games = Achievements.forGame(gameId)
	if #games == 0 then
		return false
	end
	for _, a in games do
		if Achievements.earnedTier(earned, a.id) < math.min(Achievements.MasteryTier, #a.goals) then
			return false
		end
	end
	return true
end

function Achievements.masteredCount(earned: { [string]: any }): number
	local count = 0
	for _, entry in readyGames do
		if Achievements.mastered(earned, entry.id) then
			count += 1
		end
	end
	return count
end

-- The title item a game's mastery pays (ShopCatalog).
function Achievements.masteryTitle(gameId: string): string
	return `mastery_title_{gameId}`
end

-- Unlock text for the tier: "Chess · Winner · Gold".
function Achievements.badgeName(a: Achievement, tier: number): string
	return `{Achievements.fullName(a)} · {Achievements.TierNames[tier] or tostring(tier)}`
end

return Achievements
