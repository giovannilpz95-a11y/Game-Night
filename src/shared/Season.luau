-- The Game Night Pass: a season of 30 tiers you climb with Stars (⭐) from playing and from
-- daily and weekly quests. Every tier has a premium reward, and about half have a free one.
-- Pure data and math, shared by the server (server/Core/SeasonPass) and the 🎟️ Pass window.
-- Tech notes: docs/Season pass.md. Research: vault "05 Research/Quests and Season Pass".
--
-- Seasons are 4 weeks long and start on a Monday 00:00 UTC, so a season holds exactly four
-- weekly quest sets. Season N uses Season.Tracks[N]; when there's no track written for it
-- yet, the last track runs again (a rerun) so the pass never switches off. Add a new
-- track before each season ends (see docs/Season pass.md).
--
-- Nothing here is random and nothing is sold as a mystery: every reward is listed up front.

local Season = {}

Season.Epoch = 1793577600 -- Monday 2 November 2026 00:00 UTC: Season 1 starts
Season.Days = 28
Season.Tiers = 30
Season.TierStars = 1500 -- Stars for each tier (the same for every tier)

-- Stars (tuned so a player who plays about 45 minutes most days finishes in the season,
-- and a few games a week still reaches the middle of the track)
Season.StarsPerMinute = 10 -- per minute of a rewarded match (paid minutes, like XP)
Season.WinStars = 20 -- extra for a win
Season.BotRate = 0.5 -- bots-only matches give half, like Coins
Season.DailyQuestStars = 200
Season.BonusQuestStars = 200 -- the premium pass's extra daily quest
Season.WeeklyQuestStars = 1000
Season.WeeklyQuests = 5
Season.FinalWeekMultiplier = 2 -- double Stars in the last week, to help everyone finish
Season.VipStarBonus = 0.25 -- VIP's +25% on play applies to match Stars (not quests)
Season.RerollsPerDay = 1 -- swap one daily quest you don't like for another

-- Premium. A developer product (not a game pass), because a game pass can only be owned
-- once forever and the premium pass is bought again each season. It can also be bought
-- with Gems, so a player who earns enough Gems never has to spend Robux.
-- Create it in the Creator Hub and paste the id into `productId` (0 = "Coming soon").
Season.Premium = {
	key = "seasonPremium",
	productId = 0,
	robux = 299,
	gems = 500,
}
-- Skip a tier with Gems (cosmetic progress only; nothing in a match changes).
Season.TierSkipGems = 75
-- A reward item the player already owns pays Universal Coins instead, by its tier.
Season.OwnedRefund = { Common = 100, Rare = 200, Epic = 300, Legendary = 500 }

export type Reward = { gems: number?, universal: number?, item: string? }
export type Track = {
	name: string,
	icon: string,
	blurb: string,
	free: { [number]: Reward },
	premium: { [number]: Reward },
}

local function gems(n: number): Reward
	return { gems = n }
end
local function uni(n: number): Reward
	return { universal = n }
end
local function item(id: string): Reward
	return { item = id }
end

-- Every track's items are hub shop items with `season` set (shared/ShopCatalog), never sold.
Season.Tracks = {
	{
		name = "Opening Night",
		icon = "🎭",
		blurb = "Red carpets, spotlights and a standing ovation.",
		free = {
			[1] = uni(100),
			[3] = gems(10),
			[5] = item("season1_title_opening"),
			[7] = uni(150),
			[9] = gems(10),
			[10] = item("pose_spotlight"),
			[12] = uni(200),
			[14] = gems(15),
			[16] = item("season1_trail_confetti"),
			[18] = uni(250),
			[20] = gems(15),
			[22] = uni(300),
			[24] = gems(20),
			[26] = uni(300),
			[28] = gems(20),
			[30] = item("season1_title_star"),
		},
		premium = {
			[1] = item("season1_chair_velvet"),
			[2] = gems(15),
			[3] = uni(200),
			[4] = gems(15),
			[5] = item("season1_title_headliner"),
			[6] = uni(250),
			[7] = gems(20),
			[8] = uni(250),
			[9] = gems(20),
			[10] = item("pose_redcarpet"),
			[11] = uni(300),
			[12] = gems(20),
			[13] = uni(300),
			[14] = gems(20),
			[15] = item("reactions_premiere"),
			[16] = uni(300),
			[17] = gems(25),
			[18] = uni(350),
			[19] = gems(25),
			[20] = item("season1_nameplate_marquee"),
			[21] = uni(350),
			[22] = gems(25),
			[23] = uni(400),
			[24] = gems(25),
			[25] = item("season1_table_theater"),
			[26] = uni(400),
			[27] = gems(30),
			[28] = uni(500),
			[29] = gems(30),
			[30] = item("win_showstopper"),
		},
	},
} :: { Track }

-- The season number at `now` (1 = the first season; 0 before it starts).
function Season.number(now: number): number
	if now < Season.Epoch then
		return 0
	end
	return (now - Season.Epoch) // (Season.Days * 86400) + 1
end

function Season.startsAt(n: number): number
	return Season.Epoch + (n - 1) * Season.Days * 86400
end

function Season.endsAt(n: number): number
	return Season.startsAt(n + 1)
end

-- The track season `n` uses, and whether it's a rerun of an older one.
function Season.track(n: number): (Track, boolean)
	local count = #Season.Tracks
	if n >= 1 and n <= count then
		return Season.Tracks[n], false
	end
	return Season.Tracks[count], n > count
end

-- Last 7 days of the season: double Stars.
function Season.isFinalWeek(now: number): boolean
	local n = Season.number(now)
	return n >= 1 and Season.endsAt(n) - now <= 7 * 86400
end

-- Tiers reached with `stars` (0..Season.Tiers).
function Season.tierFor(stars: number): number
	return math.clamp(stars // Season.TierStars, 0, Season.Tiers)
end

-- Stars into the next tier, and how many that tier needs.
function Season.progress(stars: number): (number, number)
	if Season.tierFor(stars) >= Season.Tiers then
		return Season.TierStars, Season.TierStars
	end
	return stars % Season.TierStars, Season.TierStars
end

-- Short text for a reward, e.g. "25 Gems", "300 Universal Coins", or the item's name
-- (lookup(itemId) -> name, so this module doesn't need the shop catalog).
function Season.describe(reward: Reward, lookup: ((string) -> string?)?): string
	if reward.gems then
		return `{reward.gems} Gems`
	elseif reward.universal then
		return `{reward.universal} Universal Coins`
	elseif reward.item then
		return (lookup and lookup(reward.item)) or reward.item
	end
	return "?"
end

return Season
