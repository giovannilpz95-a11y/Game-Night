-- Every number in the Gems and Coins economy, in one place. Tune here, not in the services.
-- Design: vault "03 Design/Economy.md". Rule we never break: sell looks, never wins.
--
-- Gems are the universal currency and the only thing sold for Robux.
-- Coins are earned only by playing, one kind per game (or shared, like Arcade Coins),
-- and spent only in that game's shop. Gems can pay for coin items (1 Gem = 10 Coins),
-- but Coins never turn into Gems.

local Economy = {}

-- Coin kinds. A game picks its kind with `coin = "<key>"` in GameCatalog.
-- `name` is the only place a coin's display name is set.
Economy.Coins = {
	arcade = { name = "Arcade Coins", color = Color3.fromRGB(255, 159, 64), order = 1 },
	chess = { name = "Chess Coins", color = Color3.fromRGB(230, 230, 240), order = 2 },
	checkers = { name = "Checkers Coins", color = Color3.fromRGB(235, 87, 87), order = 3 },
	colorclash = { name = "Color Clash Coins", color = Color3.fromRGB(54, 162, 235), order = 4 },
	party = { name = "Party Coins", color = Color3.fromRGB(153, 102, 255), order = 5 },
	hexlands = { name = "Hexlands Coins", color = Color3.fromRGB(196, 140, 72), order = 10 },
}
Economy.DefaultCoin = "arcade"

Economy.GemsName = "Gems"
Economy.CoinsPerGem = 10 -- a 500-coin item also costs 50 Gems

-- Coins from matches (target: about 300 an hour of active play in any game)
Economy.CoinsPerMinute = 5
Economy.MaxMinutesFactor = 1.5 -- pay for at most 1.5x a game's typical length
Economy.WinBonus = 0.5 -- +50% for a win
Economy.StreakBonusPerWin = 0.1 -- +10% for each win in a row after the first...
Economy.StreakBonusMax = 0.5 -- ...up to +50%
Economy.BotRate = 0.5 -- matches with no other human pay half
Economy.BotMatchesPerDay = 20 -- after this many bot matches a day, they pay nothing
Economy.WinsVsSameHumanPerDay = 3 -- anti win-trading: later wins vs the same person pay nothing
Economy.CoinMultipliers = {} -- events, e.g. { colorclash = 2 } for a launch week

-- Gems (target: about 25 a day for an active free player)
Economy.DailyLoginGems = { 5, 5, 5, 5, 5, 5, 20 } -- day 7 of a streak pays 20, then it repeats
Economy.FirstWinGems = 5
Economy.ChallengeGems = 5
Economy.ChallengesPerDay = 3

-- Account level: XP from time played, Gems on each level-up
Economy.XpPerMinute = 10
function Economy.xpForLevel(level: number): number
	return 100 + 50 * (level - 1) -- XP needed to go from `level` to `level + 1`
end
function Economy.levelUpGems(newLevel: number): number
	return math.min(25, 10 + (newLevel - 2))
end

-- VIP perks that touch numbers
Economy.VipPlayBonus = 0.25 -- +25% Gems and Coins from play
Economy.VipDailyLoginMultiplier = 2
Economy.VipGemDiscount = 0.10 -- 10% off Gem prices

-- Dressing Room saved looks
Economy.FreeLookSlots = 3
Economy.VipLookSlots = 20

-- Robux products. Create them in the Creator Hub (Monetization > Developer Products / Passes)
-- and paste each ID here. An ID of 0 means "not set up yet" and the shop greys it out.
Economy.GemPacks = {
	{ key = "gems50", productId = 0, robux = 49, gems = 50 },
	{ key = "gems110", productId = 0, robux = 99, gems = 110, bonus = "+10%" },
	{ key = "gems300", productId = 0, robux = 249, gems = 300, bonus = "+20%" },
	{ key = "gems650", productId = 0, robux = 499, gems = 650, bonus = "+30%" },
	{ key = "gems1400", productId = 0, robux = 999, gems = 1400, bonus = "+40%" },
}

-- Starter Pack: a developer product so we can limit it to a player's first days.
Economy.StarterPack = {
	key = "starter",
	productId = 0,
	robux = 79,
	gems = 300,
	items = { "hub_cozy_cabin", "hub_nameplate_cozy" },
	windowDays = 3,
}

-- Game passes (one-time)
Economy.Passes = {
	vip = {
		name = "VIP",
		gamePassId = 0,
		robux = 399,
		perks = {
			"+25% Gems and Coins from play",
			"Double daily login Gems",
			"10% off Gem prices",
			"VIP chat tag",
			"20 saved looks in the Dressing Room",
		},
	},
	partyHost = {
		name = "Party Host",
		gamePassId = 0,
		robux = 199,
		perks = {
			"Private and password tables",
			"House rules for every game",
			"Custom word lists and quiz decks",
		},
	},
}

function Economy.coinName(coinKey: string): string
	local coin = Economy.Coins[coinKey]
	return if coin then coin.name else "Coins"
end

-- Finds what a Robux purchase was for: ("gems", pack) or ("starter", pack) or nil.
function Economy.productById(productId: number): (string?, any)
	if productId == 0 then
		return nil, nil
	end
	for _, pack in Economy.GemPacks do
		if pack.productId == productId then
			return "gems", pack
		end
	end
	if Economy.StarterPack.productId == productId then
		return "starter", Economy.StarterPack
	end
	return nil, nil
end

function Economy.passByGamePassId(gamePassId: number): string?
	if gamePassId == 0 then
		return nil
	end
	for key, pass in Economy.Passes do
		if pass.gamePassId == gamePassId then
			return key
		end
	end
	return nil
end

return Economy
