-- Every analytics event name, funnel step and custom field in one place, plus the pure
-- helpers that turn game data into event payloads. Pure (no services) so it is unit tested.
-- Services/AnalyticsService sends what this builds to Roblox. Event list: docs/Analytics.md.
--
-- Roblox allows at most three custom fields per event (CustomField01..03), and the
-- dashboards group by their values, so values here are short ids, never player names.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Economy = require(ReplicatedStorage.Shared.Economy)

local AnalyticsEvents = {}

-- Onboarding funnel: logged once per player, by Roblox and by us (per session).
AnalyticsEvents.OnboardingSteps = {
	"Joined", -- profile loaded
	"SawLobby", -- the game picker is on screen (client)
	"PickedGame", -- chose a game (client for the leader; server for everyone at match start)
	"MatchStarted", -- first match started
	"FirstMove", -- made a move
	"MatchFinished", -- first match ended
	"GotReward", -- saw the reward popup (client)
	"SecondMatch", -- started a second match
}

-- Shop funnel: a new session each time the shop opens.
AnalyticsEvents.ShopFunnel = "Shop"
AnalyticsEvents.ShopSteps = {
	"Opened", -- the shop window opened (client)
	"ViewedTab", -- looked at a tab other than the wallet (client)
	"ViewedItem", -- pressed a price button (server, even if the purchase fails)
	"Checkout", -- bought with Coins or Gems, or the Robux prompt was shown
	"RobuxPurchased", -- Roblox confirmed a Robux purchase
}

AnalyticsEvents.Custom = {
	MatchFinished = "MatchFinished", -- value: minutes. game, outcome, lineup
	MatchAbandoned = "MatchAbandoned", -- value: minutes. game, reason
	BotTookSeat = "BotTookSeat", -- value: 1. game, reason
	PartyFormed = "PartyFormed", -- value: party size after someone joined
	InviteSent = "InviteSent", -- value: 1
	InviteAccepted = "InviteAccepted", -- value: 1
	DailyStreak = "DailyStreak", -- value: login streak in days
	FriendArrived = "FriendArrived", -- value: 1. "invite" or "follow"
	JoinRequest = "JoinRequest", -- value: 1. "asked", "accepted" or "declined"
	PassPrompted = "PassPrompted", -- value: 1. pass
}

AnalyticsEvents.ProgressionPath = "AccountLevel"
AnalyticsEvents.GemsCurrency = "Gems"

-- Roblox's Enum.AnalyticsEconomyTransactionType names that we use.
AnalyticsEvents.Transaction = {
	Gameplay = "Gameplay",
	TimedReward = "TimedReward",
	Onboarding = "Onboarding",
	IAP = "IAP",
	Shop = "Shop",
}

-- Which steps a client may report. Everything else is logged by the server.
local CLIENT_ONBOARDING = { SawLobby = true, PickedGame = true, GotReward = true }
local CLIENT_SHOP = { Opened = true, ViewedTab = true }

local function indexOf(list: { string }, name: string): number?
	return table.find(list, name)
end

function AnalyticsEvents.onboardingStep(name: string): number
	return assert(indexOf(AnalyticsEvents.OnboardingSteps, name), `Unknown onboarding step "{name}"`)
end

function AnalyticsEvents.shopStep(name: string): number
	return assert(indexOf(AnalyticsEvents.ShopSteps, name), `Unknown shop step "{name}"`)
end

-- Up to three custom fields; nil values are left out.
function AnalyticsEvents.fields(a: any?, b: any?, c: any?): { [string]: string }?
	local out = {}
	local any = false
	for i, value in { a, b, c } do
		if value ~= nil then
			out[`CustomField0{i}`] = string.sub(tostring(value), 1, 50)
			any = true
		end
	end
	return if any then out else nil
end

-- Shop tabs a client may name: the fixed tabs plus one per coin kind.
function AnalyticsEvents.isShopTab(tab: any): boolean
	if tab == "wallet" or tab == "robux" or tab == "hub" then
		return true
	end
	return type(tab) == "string" and Economy.Coins[tab] ~= nil
end

export type ClientReport = { kind: "onboarding", step: string } | { kind: "shop", step: string, tab: string }

-- Checks what a client sent. Returns nil for anything we don't accept.
function AnalyticsEvents.parseClientReport(report: any): ClientReport?
	if type(report) ~= "table" or type(report.step) ~= "string" then
		return nil
	end
	if report.kind == "onboarding" and CLIENT_ONBOARDING[report.step] then
		return { kind = "onboarding", step = report.step }
	elseif report.kind == "shop" and CLIENT_SHOP[report.step] then
		return { kind = "shop", step = report.step, tab = if AnalyticsEvents.isShopTab(report.tab) then report.tab else "other" }
	end
	return nil
end

-- Match payloads ------------------------------------------------------------------

-- Who sat down when the match started: humans (including ones who left later) and bots.
function AnalyticsEvents.countSeats(seats: { any }): (number, number)
	local humans, bots = 0, 0
	for _, seat in seats do
		if seat.kind == "player" or seat.left then
			humans += 1
		else
			bots += 1
		end
	end
	return humans, bots
end

-- "2h" with no bots, "1h+3b medium" with bots. Few distinct values, so it groups well.
function AnalyticsEvents.lineup(humans: number, bots: number, botLevel: string?): string
	if bots == 0 then
		return `{humans}h`
	end
	return `{humans}h+{bots}b{if botLevel then " " .. botLevel else ""}`
end

function AnalyticsEvents.outcome(result: any?, seatIndex: number): string
	if not result then
		return "none"
	elseif result.isDraw then
		return "draw"
	elseif result.winners and table.find(result.winners, seatIndex) then
		return "won"
	end
	return "lost"
end

-- Minutes rounded to a tenth, so the value stays readable on the dashboard.
function AnalyticsEvents.minutes(minutes: number): number
	return math.floor(minutes * 10 + 0.5) / 10
end

-- Economy payloads ----------------------------------------------------------------

export type Wallet = { gems: number, coins: { [string]: number } }

export type EconomyEntry = {
	flow: "Source" | "Sink",
	currency: string, -- "Gems" or a coin key
	amount: number, -- always positive
	balance: number, -- balance after the change
	transaction: string,
	sku: string?,
}

function AnalyticsEvents.snapshot(data: any): Wallet
	return { gems = data.gems, coins = table.clone(data.coins) }
end

-- One entry per currency that changed between two snapshots. Gems first, then coins by key.
function AnalyticsEvents.walletDiff(before: Wallet, after: Wallet, transaction: string, sku: string?): { EconomyEntry }
	local entries = {}
	local function add(currency: string, old: number, new: number)
		local delta = new - old
		if delta ~= 0 then
			table.insert(entries, {
				flow = if delta > 0 then "Source" else "Sink",
				currency = currency,
				amount = math.abs(delta),
				balance = new,
				transaction = transaction,
				sku = sku,
			})
		end
	end
	add(AnalyticsEvents.GemsCurrency, before.gems, after.gems)
	local keys = {}
	for key in after.coins do
		table.insert(keys, key)
	end
	for key in before.coins do
		if after.coins[key] == nil then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	for _, key in keys do
		add(key, before.coins[key] or 0, after.coins[key] or 0)
	end
	return entries
end

-- What a match payout (Core/Rewards) added, split by source. `data` is the profile after
-- the payout, so each balance matches the order Rewards adds things in: Coins, then the
-- first-win and challenge Gems, then the level-up Gems.
function AnalyticsEvents.payoutEntries(data: any, payout: any): { EconomyEntry }
	local entries = {}
	local tx = AnalyticsEvents.Transaction.Gameplay
	if payout.coins > 0 then
		table.insert(entries, {
			flow = "Source",
			currency = payout.coinKey,
			amount = payout.coins,
			balance = data.coins[payout.coinKey] or 0,
			transaction = tx,
			sku = "MatchPayout",
		})
	end
	local levelGems = 0
	for _, level in payout.levelUps do
		levelGems += Economy.levelUpGems(level)
	end
	local dailyGems = payout.gems - levelGems
	if dailyGems > 0 then
		table.insert(entries, {
			flow = "Source",
			currency = AnalyticsEvents.GemsCurrency,
			amount = dailyGems,
			balance = data.gems - levelGems,
			transaction = tx,
			sku = "FirstWinOrChallenge",
		})
	end
	if levelGems > 0 then
		table.insert(entries, {
			flow = "Source",
			currency = AnalyticsEvents.GemsCurrency,
			amount = levelGems,
			balance = data.gems,
			transaction = tx,
			sku = "LevelUp",
		})
	end
	return entries
end

-- Per-player session state ---------------------------------------------------------

export type Session = {
	onboarding: { [string]: boolean }, -- steps already sent this session
	matchesStarted: number,
	shopSession: string?, -- funnel session id while the shop is open
	shopSteps: { [number]: boolean },
}

function AnalyticsEvents.newSession(): Session
	return { onboarding = {}, matchesStarted = 0, shopSession = nil, shopSteps = {} }
end

-- Returns the step number the first time a step is reached this session, else nil.
function AnalyticsEvents.takeOnboarding(session: Session, name: string): number?
	if session.onboarding[name] then
		return nil
	end
	session.onboarding[name] = true
	return AnalyticsEvents.onboardingStep(name)
end

-- Starts a new shop funnel session with the given id.
function AnalyticsEvents.openShop(session: Session, sessionId: string)
	session.shopSession = sessionId
	table.clear(session.shopSteps)
end

-- Returns (sessionId, step) the first time a step is reached in the current shop session,
-- or nil. Server steps with no open session (e.g. an old client) start one with `newId`.
function AnalyticsEvents.takeShopStep(session: Session, name: string, newId: () -> string): (string?, number?)
	local step = AnalyticsEvents.shopStep(name)
	if not session.shopSession then
		AnalyticsEvents.openShop(session, newId())
	end
	if session.shopSteps[step] then
		return nil, nil
	end
	session.shopSteps[step] = true
	return session.shopSession, step
end

return AnalyticsEvents
