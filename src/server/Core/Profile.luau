-- A player's saved data: wallet, owned items, stats, daily progress and purchase receipts.
-- Pure (no services) so it can be unit tested. DataService loads and saves it.
--
-- Everything here must survive a DataStore round trip (JSON): only strings, numbers,
-- booleans and tables, and dictionaries keyed by strings (user ids become strings).

local Profile = {}

Profile.Version = 1
Profile.MaxReceipts = 100 -- most recent Robux purchase IDs kept for "grant once"

export type Challenge = {
	id: string,
	kind: "play" | "win",
	gameId: string?, -- nil = any game
	target: number,
	progress: number,
	done: boolean,
	text: string,
}

export type Daily = {
	day: number, -- UTC day number these counters belong to
	firstWin: boolean,
	botMatches: number,
	winsVs: { [string]: number }, -- wins against each human today (anti win-trading)
	challenges: { Challenge },
}

export type Data = {
	version: number,
	createdAt: number, -- os.time() of the first join
	gems: number,
	coins: { [string]: number },
	owned: { [string]: boolean },
	equipped: { [string]: { [string]: string } }, -- equipped[shop][slot] = itemId
	xp: number,
	level: number,
	winStreak: { [string]: number }, -- per coin key
	stats: {
		matches: number,
		wins: number,
		minutes: number,
		games: { [string]: { played: number, wins: number } },
	},
	login: { lastDay: number, streak: number },
	daily: Daily,
	receipts: { string },
	grants: { [string]: boolean }, -- one-time grants already given (e.g. starter)
	-- Dressing Room (see vault "03 Design/Avatar Designer.md")
	looks: { any },
	lookSlots: number, -- extra slots bought with Gems, on top of the free ones
	currentLook: any?,
	-- Party Host word lists and quiz decks, keyed by slot ("1".."3"). Stored as the host
	-- typed them; filtered every time a match uses them. See shared/CustomContent.luau.
	custom: {
		words: { [string]: { name: string, words: { string } } },
		decks: { [string]: { name: string, questions: { { q: string, a: { string } } } } },
	},
}

local function newDaily(day: number): Daily
	return { day = day, firstWin = false, botMatches = 0, winsVs = {}, challenges = {} }
end
Profile.newDaily = newDaily

function Profile.new(now: number): Data
	return {
		version = Profile.Version,
		createdAt = now,
		gems = 0,
		coins = {},
		owned = {},
		equipped = {},
		xp = 0,
		level = 1,
		winStreak = {},
		stats = { matches = 0, wins = 0, minutes = 0, games = {} },
		login = { lastDay = 0, streak = 0 },
		daily = newDaily(0),
		receipts = {},
		grants = {},
		looks = {},
		lookSlots = 0,
		currentLook = nil,
		custom = { words = {}, decks = {} },
	}
end

local function fill(target: any, defaults: any)
	for key, value in defaults do
		if target[key] == nil then
			target[key] = value
		elseif type(value) == "table" and type(target[key]) == "table" and next(value) ~= nil then
			fill(target[key], value)
		end
	end
end

-- Brings saved data up to date: adds fields that newer code expects. Never removes data.
function Profile.reconcile(data: any, now: number): Data
	if type(data) ~= "table" then
		return Profile.new(now)
	end
	fill(data, Profile.new(now))
	data.version = Profile.Version
	return data
end

function Profile.today(now: number): number
	return math.floor(now / 86400)
end

-- Gem and coin balances are always whole and never negative.
function Profile.addGems(data: Data, amount: number)
	data.gems = math.max(0, data.gems + math.floor(amount))
end

function Profile.addCoins(data: Data, coinKey: string, amount: number)
	data.coins[coinKey] = math.max(0, (data.coins[coinKey] or 0) + math.floor(amount))
end

function Profile.coins(data: Data, coinKey: string): number
	return data.coins[coinKey] or 0
end

function Profile.hasReceipt(data: Data, purchaseId: string): boolean
	return table.find(data.receipts, purchaseId) ~= nil
end

function Profile.addReceipt(data: Data, purchaseId: string)
	table.insert(data.receipts, purchaseId)
	while #data.receipts > Profile.MaxReceipts do
		table.remove(data.receipts, 1)
	end
end

return Profile
