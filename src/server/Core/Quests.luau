-- Daily and weekly quests: what each kind counts, and the pools they're picked from.
-- Pure: the list of games, the day/week and the Random are passed in. Daily.luau makes the
-- day's three quests; SeasonPass.luau makes the weekly ones and the pass's bonus quest.
--
-- Kinds (a quest can also be limited to one game, one category, or games with people):
--   play     finish N games
--   win      win N games
--   minutes  play N minutes (rewarded minutes, like XP)
--   variety  play N different games
--   react    send N reactions at a table
--   stat     add up one of a game's own stats (StatsCatalog), e.g. "Capture 6 pieces in Chess"
--   streak   win N games in a row (a loss starts it again, a draw keeps it)
--
-- Only matches that pay rewards count (not resigned, not too short), so quests can't be
-- farmed with instant resigns.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Season = require(ReplicatedStorage.Shared.Season)
local Profile = require(script.Parent.Profile)

local Quests = {}

export type GameInfo = { id: string, name: string, category: string? }

export type Event = {
	kind: "match" | "react",
	gameId: string?,
	category: string?,
	won: boolean?,
	minutes: number?,
	vsHumans: boolean?,
	isDraw: boolean?,
	extra: { [string]: any }?, -- the game's own stats for this seat (StatsCatalog keys)
}

-- Each game's own quests: one for a daily slot and one for a weekly slot. `stat` quests
-- count a StatsCatalog "sum" stat the game reports; games without one use wins or games.
-- "{game}" becomes the game's name. Games not listed get Quests.DefaultGoals.
export type GoalSpec = { kind: string, target: number, text: string, stat: string? }
Quests.DefaultGoals = {
	daily = { kind = "win", target = 1, text = "Win a game of {game}" },
	weekly = { kind = "win", target = 4, text = "Win 4 games of {game}" },
}
Quests.GameGoals = {
	Chess = {
		daily = { kind = "stat", stat = "captures", target = 6, text = "Capture 6 pieces in {game}" },
		weekly = { kind = "stat", stat = "checkmates", target = 2, text = "Checkmate twice in {game}" },
	},
	Checkers = {
		daily = { kind = "stat", stat = "captures", target = 6, text = "Capture 6 pieces in {game}" },
		weekly = { kind = "stat", stat = "kings", target = 4, text = "Crown 4 kings in {game}" },
	},
	ColorClash = {
		daily = { kind = "stat", stat = "wilds", target = 3, text = "Play 3 wilds in {game}" },
		weekly = { kind = "stat", stat = "cards", target = 60, text = "Play 60 cards in {game}" },
	},
	TriviaNight = {
		daily = { kind = "stat", stat = "correct", target = 8, text = "Get 8 answers right in {game}" },
		weekly = { kind = "stat", stat = "correct", target = 40, text = "Get 40 answers right in {game}" },
	},
	Werewolf = {
		daily = { kind = "play", target = 2, text = "Play 2 games of {game}" },
		weekly = { kind = "stat", stat = "survived", target = 3, text = "Survive to the end of 3 games of {game}" },
	},
	FiveDice = {
		daily = { kind = "stat", stat = "bigFives", target = 1, text = "Roll a Big Five in {game}" },
		weekly = { kind = "stat", stat = "upperBonus", target = 2, text = "Earn 2 upper bonuses in {game}" },
	},
	SeaStrike = {
		daily = { kind = "stat", stat = "sunk", target = 5, text = "Sink 5 ships in {game}" },
		weekly = { kind = "stat", stat = "hits", target = 60, text = "Land 60 hits in {game}" },
	},
	Whodunit = {
		daily = { kind = "play", target = 1, text = "Play a game of {game}" },
		weekly = { kind = "stat", stat = "solved", target = 2, text = "Solve 2 cases in {game}" },
	},
	WordTiles = {
		daily = { kind = "stat", stat = "words", target = 8, text = "Play 8 words in {game}" },
		weekly = { kind = "stat", stat = "words", target = 40, text = "Play 40 words in {game}" },
	},
	Conquest = {
		daily = { kind = "play", target = 1, text = "Play a game of {game}" },
		weekly = { kind = "stat", stat = "knockouts", target = 3, text = "Knock out 3 players in {game}" },
	},
	Hexlands = {
		daily = { kind = "stat", stat = "roads", target = 6, text = "Build 6 roads in {game}" },
		weekly = { kind = "stat", stat = "towns", target = 6, text = "Build 6 towns in {game}" },
	},
	Speed = {
		daily = { kind = "stat", stat = "cards", target = 40, text = "Play 40 cards in {game}" },
		weekly = { kind = "stat", stat = "cards", target = 200, text = "Play 200 cards in {game}" },
	},
	GoFish = {
		daily = { kind = "stat", stat = "books", target = 5, text = "Collect 5 books in {game}" },
		weekly = { kind = "stat", stat = "books", target = 25, text = "Collect 25 books in {game}" },
	},
	OldMaid = {
		daily = { kind = "stat", stat = "pairs", target = 10, text = "Make 10 pairs in {game}" },
		weekly = { kind = "stat", stat = "pairs", target = 50, text = "Make 50 pairs in {game}" },
	},
	Snap = {
		daily = { kind = "stat", stat = "snaps", target = 8, text = "Make 8 good snaps in {game}" },
		weekly = { kind = "stat", stat = "snaps", target = 40, text = "Make 40 good snaps in {game}" },
	},
	GinRummy = {
		daily = { kind = "play", target = 2, text = "Play 2 games of {game}" },
		weekly = { kind = "stat", stat = "gins", target = 2, text = "Go gin twice in {game}" },
	},
	OhHell = {
		daily = { kind = "stat", stat = "exact", target = 5, text = "Make your bid exactly 5 times in {game}" },
		weekly = { kind = "stat", stat = "exact", target = 25, text = "Make your bid exactly 25 times in {game}" },
	},
	TicTacToe = {
		daily = { kind = "streak", target = 2, text = "Win 2 games of {game} in a row" },
		weekly = { kind = "win", target = 6, text = "Win 6 games of {game}" },
	},
	FourInARow = {
		daily = { kind = "streak", target = 2, text = "Win 2 games of {game} in a row" },
		weekly = { kind = "win", target = 5, text = "Win 5 games of {game}" },
	},
}

-- How a category reads in a quest ("Finish 3 card games").
Quests.CategoryWords = {
	Cards = "card games",
	Strategy = "strategy games",
	Board = "board games",
	Party = "party games",
	Quick = "quick games",
	Word = "word games",
}

local function matches(quest: Profile.Challenge, event: Event): boolean
	if quest.gameId ~= nil and quest.gameId ~= event.gameId then
		return false
	end
	if quest.category ~= nil and quest.category ~= event.category then
		return false
	end
	if quest.humans and not event.vsHumans then
		return false
	end
	return true
end

-- Counts one event toward a list of quests. Returns the quests it completed.
function Quests.progress(list: { Profile.Challenge }, event: Event): { Profile.Challenge }
	local completed = {}
	for _, quest in list do
		if quest.done then
			continue
		end
		local add = 0
		if event.kind == "react" then
			add = if quest.kind == "react" then 1 else 0
		elseif event.kind == "match" and matches(quest, event) then
			if quest.kind == "streak" then
				if event.won then
					add = 1
				elseif not event.isDraw then
					quest.progress = 0
				end
			elseif quest.kind == "stat" then
				local value = if type(event.extra) == "table" and quest.stat then event.extra[quest.stat] else nil
				if type(value) == "number" and value == value and value > 0 and value < math.huge then
					add = math.floor(value)
				end
			elseif quest.kind == "play" then
				add = 1
			elseif quest.kind == "win" then
				add = if event.won then 1 else 0
			elseif quest.kind == "minutes" then
				add = math.max(0, math.floor((event.minutes or 0) + 0.5))
			elseif quest.kind == "variety" and event.gameId then
				quest.seen = quest.seen or {}
				local seen = quest.seen :: { [string]: boolean }
				if not seen[event.gameId] then
					seen[event.gameId] = true
					add = 1
				end
			end
		end
		if add > 0 then
			quest.progress = math.min(quest.target, quest.progress + add)
			if quest.progress >= quest.target then
				quest.done = true
				table.insert(completed, quest)
			end
		end
	end
	return completed
end

local function make(id: string, kind: string, target: number, text: string, extra: { [string]: any }?): Profile.Challenge
	local quest: any = { id = id, kind = kind, target = target, progress = 0, done = false, text = text }
	for key, value in extra or {} do
		quest[key] = value
	end
	return quest
end
Quests.make = make

-- Categories that have at least `need` ready games, so a category quest is doable.
local function categories(games: { GameInfo }): { string }
	local count: { [string]: number } = {}
	for _, info in games do
		if info.category and Quests.CategoryWords[info.category] then
			count[info.category] = (count[info.category] or 0) + 1
		end
	end
	local out = {}
	for category in count do
		table.insert(out, category)
	end
	table.sort(out)
	return out
end

local function pick<T>(list: { T }, rng: Random): T
	return list[rng:NextInteger(1, #list)]
end

-- A game's own quest for a daily or weekly slot ("daily" | "weekly"). `prefix` keeps ids
-- apart: "goal_" daily, "wgoal_" weekly.
function Quests.gameGoal(info: GameInfo, slot: string, prefix: string): Profile.Challenge
	local goals = Quests.GameGoals[info.id] or Quests.DefaultGoals
	local spec: GoalSpec = goals[slot] or Quests.DefaultGoals[slot]
	return make(`{prefix}{info.id}`, spec.kind, spec.target, (spec.text:gsub("{game}", info.name)), { gameId = info.id, stat = spec.stat })
end

-- Small daily quests: the pass's bonus quest and what a reroll swaps in.
function Quests.smallPool(games: { GameInfo }, rng: Random): { Profile.Challenge }
	local pool = {
		make("d_minutes15", "minutes", 15, "Play for 15 minutes"),
		make("d_people1", "play", 1, "Finish a game with another person", { humans = true }),
		make("d_win2", "win", 2, "Win 2 games"),
		make("d_react5", "react", 5, "Send 5 reactions at a table"),
		make("d_variety2", "variety", 2, "Play 2 different games"),
		make("d_streak2", "streak", 2, "Win 2 games in a row"),
	}
	local cats = categories(games)
	if #cats > 0 then
		local category = pick(cats, rng)
		table.insert(pool, make(`d_cat_{category}`, "play", 2, `Finish 2 {Quests.CategoryWords[category]}`, { category = category }))
	end
	return pool
end

-- One quest for a reroll or the bonus slot: a random one from the small pool whose id
-- isn't already in `taken`. Nil if every one is taken.
function Quests.pickSmall(games: { GameInfo }, rng: Random, taken: { [string]: boolean }): Profile.Challenge?
	local options = {}
	for _, quest in Quests.smallPool(games, rng) do
		if not taken[quest.id] then
			table.insert(options, quest)
		end
	end
	if #options == 0 then
		return nil
	end
	return pick(options, rng)
end

-- The week's quests (Season.WeeklyQuests of them): one of each theme so a week always
-- mixes playing a lot, winning, people, variety and time. `seasonal` is the season
-- track's themed quests (Season.Track.weekly): they join their theme's options, and one
-- theme each week is always a themed quest.
function Quests.makeWeekly(games: { GameInfo }, rng: Random, seasonal: { Season.QuestSpec }?): { Profile.Challenge }
	local themes: { { Profile.Challenge } } = {
		{ make("w_play15", "play", 15, "Finish 15 games") },
		{
			make("w_win5", "win", 5, "Win 5 games"),
			make("w_winpeople3", "win", 3, "Win 3 games with other people", { humans = true }),
			make("w_streak3", "streak", 3, "Win 3 games in a row"),
		},
		{
			make("w_people5", "play", 5, "Finish 5 games with other people", { humans = true }),
			make("w_react20", "react", 20, "Send 20 reactions at a table"),
		},
		{ make("w_variety4", "variety", 4, "Play 4 different games") },
		{ make("w_minutes60", "minutes", 60, "Play for 60 minutes") },
	}
	local cats = categories(games)
	if #cats > 0 then
		local category = pick(cats, rng)
		table.insert(themes[4], make(`w_cat_{category}`, "play", 5, `Finish 5 {Quests.CategoryWords[category]}`, { category = category }))
	end
	if #games > 0 then
		table.insert(themes[4], Quests.gameGoal(pick(games, rng), "weekly", "wgoal_"))
	end
	local themed: { [number]: { Profile.Challenge } } = {}
	local themedSlots = {}
	for _, spec in seasonal or {} do
		if not themes[spec.theme] or (spec.category and not table.find(cats, spec.category)) then
			continue
		end
		if not themed[spec.theme] then
			themed[spec.theme] = {}
			table.insert(themedSlots, spec.theme)
		end
		table.insert(themed[spec.theme], make(spec.id, spec.kind, spec.target, spec.text, { category = spec.category, humans = spec.humans }))
	end
	table.sort(themedSlots)
	local forced = if #themedSlots > 0 then pick(themedSlots, rng) else nil
	local out = {}
	for index, options in themes do
		if themed[index] then
			if index == forced then
				options = themed[index]
			else
				options = table.clone(options)
				table.move(themed[index], 1, #themed[index], #options + 1, options)
			end
		end
		local quest = pick(options, rng)
		quest.stars = Season.WeeklyQuestStars
		quest.xp = Season.WeeklyQuestXp
		table.insert(out, quest)
		if #out >= Season.WeeklyQuests then
			break
		end
	end
	return out
end

return Quests
