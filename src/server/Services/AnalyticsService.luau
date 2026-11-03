-- Sends Game Night's analytics to Roblox (Creator Hub > Analytics). Server only: clients
-- can report a few UI steps (seeing the lobby, opening the shop) and we check those.
-- Names and payloads live in Core/AnalyticsEvents; the event list is in docs/Analytics.md.
--
-- Other services call the helpers below. Matches are tracked by listening to MatchService
-- (onEvent and onMatchFinished), so game code never calls this.
--
-- Economy events come only from EconomyService and PurchaseService, so they match the
-- profile. In Studio every event is printed to the Output instead of being lost.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local RobloxAnalytics = game:GetService("AnalyticsService")

local Net = require(ReplicatedStorage.Shared.Net)
local AnalyticsEvents = require(script.Parent.Parent.Core.AnalyticsEvents)
local RateLimiter = require(script.Parent.Parent.Core.RateLimiter)
local DataService = require(script.Parent.DataService)

local AnalyticsService = {}

local PRINT_IN_STUDIO = true
local isStudio = RunService:IsStudio()

local sessions: { [number]: AnalyticsEvents.Session } = {}
local matchInfo: { [string]: { botLevel: string?, humans: number, bots: number } } = {}

local function sessionFor(player: Player): AnalyticsEvents.Session
	local session = sessions[player.UserId]
	if not session then
		session = AnalyticsEvents.newSession()
		sessions[player.UserId] = session
	end
	return session
end

local function describe(value: any): string
	if type(value) == "table" then
		local ok, json = pcall(HttpService.JSONEncode, HttpService, value)
		return if ok then json else "{...}"
	end
	return tostring(value)
end

-- Every Roblox call goes through here: never let analytics break the game.
local function send(method: string, player: Player, ...: any)
	if isStudio and PRINT_IN_STUDIO then
		local parts = {}
		for i = 1, select("#", ...) do
			table.insert(parts, describe((select(i, ...))))
		end
		print(`[Analytics] {method} {player.Name}: {table.concat(parts, " ")}`)
	end
	local ok, err = pcall((RobloxAnalytics :: any)[method], RobloxAnalytics, player, ...)
	if not ok then
		warn(`[GameNight] analytics {method} failed: {err}`)
	end
end

-- Generic helpers ------------------------------------------------------------------

function AnalyticsService.onboard(player: Player, stepName: string)
	local step = AnalyticsEvents.takeOnboarding(sessionFor(player), stepName)
	if step then
		send("LogOnboardingFunnelStepEvent", player, step, stepName)
	end
end

function AnalyticsService.custom(player: Player, eventName: string, value: number?, fields: { [string]: string }?)
	send("LogCustomEvent", player, eventName, value or 1, fields)
end

local function shopStep(player: Player, stepName: string, fields: { [string]: string }?)
	local sessionId, step = AnalyticsEvents.takeShopStep(sessionFor(player), stepName, function()
		return HttpService:GenerateGUID(false)
	end)
	if sessionId and step then
		send("LogFunnelStepEvent", player, AnalyticsEvents.ShopFunnel, sessionId, step, stepName, fields)
	end
end

local function economy(player: Player, entry: AnalyticsEvents.EconomyEntry)
	send(
		"LogEconomyEvent",
		player,
		if entry.flow == "Source" then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink,
		entry.currency,
		entry.amount,
		entry.balance,
		entry.transaction,
		entry.sku
	)
end

-- Economy (EconomyService and PurchaseService) ---------------------------------------

-- Take a snapshot before changing a wallet, then call logChange after.
AnalyticsService.snapshot = AnalyticsEvents.snapshot

function AnalyticsService.logChange(player: Player, data: any, before: AnalyticsEvents.Wallet, transaction: string, sku: string?)
	for _, entry in AnalyticsEvents.walletDiff(before, AnalyticsEvents.snapshot(data), transaction, sku) do
		economy(player, entry)
	end
end

-- A match payout from Core/Rewards: Coins and Gems by source, and any level-ups.
function AnalyticsService.matchPayout(player: Player, data: any, payout: any)
	for _, entry in AnalyticsEvents.payoutEntries(data, payout) do
		economy(player, entry)
	end
	for _, level in payout.levelUps do
		send("LogProgressionCompleteEvent", player, AnalyticsEvents.ProgressionPath, level - 1, `Level {level - 1}`)
		send("LogProgressionStartEvent", player, AnalyticsEvents.ProgressionPath, level, `Level {level}`)
	end
end

-- The daily login reward was just paid.
function AnalyticsService.dailyLogin(player: Player, data: any, gems: number)
	economy(player, {
		flow = "Source",
		currency = AnalyticsEvents.GemsCurrency,
		amount = gems,
		balance = data.gems,
		transaction = AnalyticsEvents.Transaction.TimedReward,
		sku = "DailyLogin",
	})
	AnalyticsService.custom(player, AnalyticsEvents.Custom.DailyStreak, data.login.streak)
end

-- A Coins or Gems shop purchase was tried. `before` is the wallet before Shop.buy.
function AnalyticsService.shopBuy(player: Player, data: any, before: AnalyticsEvents.Wallet, itemId: any, ok: boolean)
	local sku = if type(itemId) == "string" then itemId else "unknown"
	shopStep(player, "ViewedItem", AnalyticsEvents.fields(sku))
	if not ok then
		return
	end
	local entries = AnalyticsEvents.walletDiff(before, AnalyticsEvents.snapshot(data), AnalyticsEvents.Transaction.Shop, sku)
	for _, entry in entries do
		economy(player, entry)
	end
	local currency = if entries[1] and entries[1].currency == AnalyticsEvents.GemsCurrency then "Gems" else "Coins"
	shopStep(player, "Checkout", AnalyticsEvents.fields(currency, sku))
end

-- We're about to show a Robux prompt. `passKey` is set for game passes.
function AnalyticsService.robuxPrompt(player: Player, sku: string, passKey: string?)
	shopStep(player, "ViewedItem", AnalyticsEvents.fields(sku))
	shopStep(player, "Checkout", AnalyticsEvents.fields("Robux", sku))
	if passKey then
		AnalyticsService.custom(player, AnalyticsEvents.Custom.PassPrompted, 1, AnalyticsEvents.fields(passKey))
	end
end

-- Roblox confirmed a Robux purchase. `gems` > 0 also logs the Gems it granted.
function AnalyticsService.robuxPurchase(player: Player, sku: string, data: any?, gems: number?)
	if data and gems and gems > 0 then
		economy(player, {
			flow = "Source",
			currency = AnalyticsEvents.GemsCurrency,
			amount = gems,
			balance = data.gems,
			transaction = AnalyticsEvents.Transaction.IAP,
			sku = sku,
		})
	end
	shopStep(player, "RobuxPurchased", AnalyticsEvents.fields(sku))
end

-- Parties (PartyService) -------------------------------------------------------------

function AnalyticsService.inviteSent(player: Player)
	AnalyticsService.custom(player, AnalyticsEvents.Custom.InviteSent, 1)
end

function AnalyticsService.inviteAccepted(player: Player, partySize: number)
	AnalyticsService.custom(player, AnalyticsEvents.Custom.InviteAccepted, 1)
	AnalyticsService.custom(player, AnalyticsEvents.Custom.PartyFormed, partySize)
end

-- Matches (MatchService events) ------------------------------------------------------

local function eachHuman(seats: { any }, callback: (Player, number) -> ())
	for index, seat in seats do
		if seat.kind == "player" and seat.userId and not seat.left then
			local player = Players:GetPlayerByUserId(seat.userId)
			if player then
				callback(player, index)
			end
		end
	end
end

local function onMatchStarted(event: any)
	local humans, bots = AnalyticsEvents.countSeats(event.seats)
	matchInfo[event.matchId] = { botLevel = if bots > 0 then event.botLevel else nil, humans = humans, bots = bots }
	eachHuman(event.seats, function(player)
		local session = sessionFor(player)
		session.matchesStarted += 1
		AnalyticsService.onboard(player, "PickedGame") -- the leader picked for the party
		AnalyticsService.onboard(player, "MatchStarted")
		local data = DataService.get(player)
		if session.matchesStarted >= 2 or (data and data.stats.matches >= 1) then
			AnalyticsService.onboard(player, "SecondMatch")
		end
	end)
end

local function onSeatLeft(event: any)
	local gameId = event.gameId
	local reason = event.reason or "left"
	AnalyticsService.custom(event.player, AnalyticsEvents.Custom.MatchAbandoned, AnalyticsEvents.minutes(event.minutes), AnalyticsEvents.fields(gameId, reason))
	if event.humansLeft > 0 then
		AnalyticsService.custom(event.player, AnalyticsEvents.Custom.BotTookSeat, 1, AnalyticsEvents.fields(gameId, reason))
	end
end

local function onMatchFinished(summary: any)
	local info = matchInfo[summary.matchId]
	matchInfo[summary.matchId] = nil
	local minutes = AnalyticsEvents.minutes(summary.minutes)
	if summary.aborted or not summary.result then
		-- Ended early (leader ended it, or everyone left). Leavers were logged when they left.
		eachHuman(summary.seats, function(player)
			AnalyticsService.custom(player, AnalyticsEvents.Custom.MatchAbandoned, minutes, AnalyticsEvents.fields(summary.gameId, "ended"))
		end)
		return
	end
	local humans, bots = AnalyticsEvents.countSeats(summary.seats)
	local botLevel = nil
	if info then
		humans, bots, botLevel = info.humans, info.bots, info.botLevel
	end
	local lineup = AnalyticsEvents.lineup(humans, bots, botLevel)
	eachHuman(summary.seats, function(player, index)
		local outcome = AnalyticsEvents.outcome(summary.result, index)
		AnalyticsService.custom(player, AnalyticsEvents.Custom.MatchFinished, minutes, AnalyticsEvents.fields(summary.gameId, outcome, lineup))
		AnalyticsService.onboard(player, "MatchFinished")
	end)
end

-- Client reports --------------------------------------------------------------------

local limiter = RateLimiter.new(20, 10)

local function onClientReport(player: Player, raw: any)
	if not limiter:allow(player.UserId) then
		return
	end
	local report = AnalyticsEvents.parseClientReport(raw)
	if not report then
		return
	end
	if report.kind == "onboarding" then
		AnalyticsService.onboard(player, report.step)
	elseif report.step == "Opened" then
		AnalyticsEvents.openShop(sessionFor(player), HttpService:GenerateGUID(false))
		shopStep(player, "Opened", AnalyticsEvents.fields(report.tab))
		if report.tab ~= "wallet" then
			shopStep(player, "ViewedTab", AnalyticsEvents.fields(report.tab))
		end
	elseif report.tab ~= "wallet" then
		shopStep(player, "ViewedTab", AnalyticsEvents.fields(report.tab))
	end
end

function AnalyticsService.init(matchService: any)
	matchService.onEvent(function(name: string, event: any)
		if name == "started" then
			onMatchStarted(event)
		elseif name == "moved" then
			AnalyticsService.onboard(event.player, "FirstMove")
		elseif name == "left" then
			onSeatLeft(event)
		end
	end)
	matchService.onMatchFinished(onMatchFinished)

	DataService.onLoaded(function(player)
		AnalyticsService.onboard(player, "Joined")
	end)

	Net.event(Net.Names.AnalyticsRequest).OnServerEvent:Connect(function(player, report)
		local ok, err = pcall(onClientReport, player, report)
		if not ok then
			warn(`[GameNight] analytics report from {player.Name} failed: {err}`)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		sessions[player.UserId] = nil
		limiter:forget(player.UserId)
	end)
end

return AnalyticsService
