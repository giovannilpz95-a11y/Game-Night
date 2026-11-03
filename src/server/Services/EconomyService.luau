-- Gems, Coins, daily rewards and the shop. The server decides every reward and every
-- purchase; clients only ask. Design: vault "03 Design/Economy.md", tech notes: docs/Economy.md.
--
-- Games don't pay players themselves. Matches run by MatchService pay out automatically
-- (see onMatchFinished). For anything else, call the API below from server code:
--
--   EconomyService.award(player, { coins = 20, coinKey = "party", gems = 0, reason = "Guessed first" })
--   EconomyService.recordMatch(player, { gameId = "TriviaNight", won = true, minutes = 6, moves = 10, humanOpponents = {} })
--   EconomyService.hasPass(player, "vip" | "partyHost")
--   EconomyService.getBalance(player) -> gems, coins table

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")

local Economy = require(ReplicatedStorage.Shared.Economy)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local Net = require(ReplicatedStorage.Shared.Net)
local Profile = require(script.Parent.Parent.Core.Profile)
local Daily = require(script.Parent.Parent.Core.Daily)
local Rewards = require(script.Parent.Parent.Core.Rewards)
local Shop = require(script.Parent.Parent.Core.Shop)
local Looks = require(script.Parent.Parent.Core.Looks)
local DataService = require(script.Parent.DataService)
local AnalyticsService = require(script.Parent.AnalyticsService)

local EconomyService = {}

local passes: { [number]: { [string]: boolean } } = {} -- live pass ownership, checked on join
local walletRemote: RemoteEvent
local rewardRemote: RemoteEvent
local notifyRemote: RemoteEvent

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

local function today(): number
	return Profile.today(os.time())
end

local function readyGames(): { Daily.GameInfo }
	local games = {}
	for _, entry in GameCatalog.entries do
		if entry.status == "ready" then
			table.insert(games, { id = entry.id, name = entry.name })
		end
	end
	return games
end

function EconomyService.hasPass(player: Player, key: string): boolean
	local owned = passes[player.UserId]
	return owned ~= nil and owned[key] == true
end

local function isVip(player: Player): boolean
	return EconomyService.hasPass(player, "vip")
end

local function starterAvailable(data: Profile.Data): (boolean, number)
	local endsAt = data.createdAt + Economy.StarterPack.windowDays * 86400
	return not data.grants.starter and os.time() < endsAt, endsAt
end

-- Sends the player everything the wallet and shop screens need.
function EconomyService.push(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local starter, starterEndsAt = starterAvailable(data)
	local vip = isVip(player)
	walletRemote:FireClient(player, {
		gems = data.gems,
		coins = data.coins,
		owned = data.owned,
		equipped = data.equipped,
		level = data.level,
		xp = data.xp,
		xpNeeded = Economy.xpForLevel(data.level),
		passes = passes[player.UserId] or {},
		vip = vip,
		loginStreak = data.login.streak,
		firstWinDone = data.daily.firstWin,
		challenges = data.daily.challenges,
		starterAvailable = starter,
		starterEndsAt = starterEndsAt,
		lookSlots = Looks.slotCount(data, vip),
		saving = DataService.isPersistent(player),
		studio = RunService:IsStudio(),
	})
end

local function sendReward(player: Player, title: string, lines: { string })
	if #lines > 0 then
		rewardRemote:FireClient(player, { title = title, lines = lines })
	end
end

-- New day: fresh challenges and counters, and the login reward.
local function checkDay(player: Player, data: Profile.Data)
	local day = today()
	Daily.roll(data, day, readyGames(), Random.new())
	local gems, streakDay = Daily.login(data, day, isVip(player))
	if gems > 0 then
		sendReward(player, "Daily reward", { `Day {streakDay} login: +{gems} {Economy.GemsName}` })
		AnalyticsService.dailyLogin(player, data, gems)
	end
end

-- Gives Gems and/or Coins directly. For bonuses inside a game ("guessed the word first").
-- Amounts are whole and positive; VIP gets its +25% on play rewards here too.
function EconomyService.award(player: Player, grant: { coins: number?, coinKey: string?, gems: number?, reason: string? })
	local data = DataService.get(player)
	if not data then
		return
	end
	local before = AnalyticsService.snapshot(data)
	local multiplier = if isVip(player) then 1 + Economy.VipPlayBonus else 1
	local lines = {}
	local coins = math.floor((grant.coins or 0) * multiplier + 0.5)
	if coins > 0 then
		local coinKey = grant.coinKey or Economy.DefaultCoin
		assert(Economy.Coins[coinKey], `Unknown coin "{coinKey}"`)
		Profile.addCoins(data, coinKey, coins)
		table.insert(lines, `+{coins} {Economy.coinName(coinKey)}`)
	end
	local gems = math.floor((grant.gems or 0) * multiplier + 0.5)
	if gems > 0 then
		Profile.addGems(data, gems)
		table.insert(lines, `+{gems} {Economy.GemsName}`)
	end
	sendReward(player, grant.reason or "Reward", lines)
	AnalyticsService.logChange(player, data, before, "Gameplay", grant.reason)
	EconomyService.push(player)
end

-- Pays one player for one finished match. MatchService calls this through onMatchFinished;
-- games that run outside MatchService can call it directly.
function EconomyService.recordMatch(
	player: Player,
	result: { gameId: string, won: boolean, isDraw: boolean?, resigned: boolean?, minutes: number, moves: number, humanOpponents: { number } }
): Rewards.Payout?
	local data = DataService.get(player)
	local entry = GameCatalog.get(result.gameId)
	if not data or not entry then
		return nil
	end
	checkDay(player, data)
	local typical = entry.typicalMinutes or 5
	local payout = Rewards.applyMatch(data, {
		gameId = entry.id,
		coinKey = entry.coin or Economy.DefaultCoin,
		typicalMinutes = typical,
		minMinutes = entry.minMinutes or 0,
		minMoves = entry.minMoves or 0,
		minutes = result.minutes,
		moves = result.moves,
		won = result.won,
		isDraw = result.isDraw == true,
		resigned = result.resigned == true,
		humanOpponents = result.humanOpponents,
		vip = isVip(player),
	})
	sendReward(player, "Rewards", Rewards.describe(payout))
	AnalyticsService.matchPayout(player, data, payout)
	EconomyService.push(player)
	return payout
end

-- Hooked to MatchService: pays every human still at the table.
function EconomyService.onMatchFinished(summary: any)
	if summary.aborted or not summary.result then
		return
	end
	for index, seat in summary.seats do
		if seat.kind ~= "player" or not seat.userId or seat.left then
			continue
		end
		local player = Players:GetPlayerByUserId(seat.userId)
		if not player then
			continue
		end
		local opponents = {}
		for otherIndex, other in summary.seats do
			if otherIndex ~= index and other.userId then
				table.insert(opponents, other.userId)
			end
		end
		EconomyService.recordMatch(player, {
			gameId = summary.gameId,
			won = table.find(summary.result.winners, index) ~= nil,
			isDraw = summary.result.isDraw,
			resigned = summary.result.resignedSeat == index,
			minutes = summary.minutes,
			moves = summary.moves,
			humanOpponents = opponents,
		})
	end
end

function EconomyService.getBalance(player: Player): (number, { [string]: number })
	local data = DataService.get(player)
	if not data then
		return 0, {}
	end
	return data.gems, table.clone(data.coins)
end

-- Robux purchases (PurchaseService) ------------------------------------------------

function EconomyService.setPass(player: Player, key: string, owned: boolean)
	passes[player.UserId] = passes[player.UserId] or {}
	passes[player.UserId][key] = owned
	if key == "vip" then
		player:SetAttribute("VIP", owned)
	end
	EconomyService.push(player)
end

function EconomyService.isStarterAvailable(player: Player): boolean
	local data = DataService.get(player)
	return data ~= nil and (starterAvailable(data))
end

-- Asks Roblox which passes the player owns (before the login reward, so VIP doubles it).
local function checkPasses(player: Player)
	for key, pass in Economy.Passes do
		if pass.gamePassId ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.gamePassId)
			end)
			if ok and owns then
				passes[player.UserId] = passes[player.UserId] or {}
				passes[player.UserId][key] = true
				if key == "vip" then
					player:SetAttribute("VIP", true)
				end
			end
		end
	end
end

-- Client requests ----------------------------------------------------------------

local handlers = {}

function handlers.sync(player: Player, _request: any)
	EconomyService.push(player)
end

function handlers.buy(player: Player, request: any)
	local data = DataService.get(player)
	if not data then
		return
	end
	local before = AnalyticsService.snapshot(data)
	local ok, err = Shop.buy(data, request.itemId, request.currency, isVip(player))
	AnalyticsService.shopBuy(player, data, before, request.itemId, ok)
	if not ok then
		return notify(player, err :: string)
	end
	notify(player, "Bought! Equip it from the shop.")
	EconomyService.push(player)
end

function handlers.equip(player: Player, request: any)
	local data = DataService.get(player)
	if not data then
		return
	end
	local ok, err = Shop.toggleEquip(data, request.itemId)
	if not ok then
		return notify(player, err :: string)
	end
	EconomyService.push(player)
end

-- Studio only: free Gems and Coins so the shop can be tested without Robux.
function handlers.studioGrant(player: Player, _request: any)
	if not RunService:IsStudio() then
		return
	end
	local data = DataService.get(player)
	if not data then
		return
	end
	Profile.addGems(data, 500)
	for coinKey in Economy.Coins do
		Profile.addCoins(data, coinKey, 2000)
	end
	notify(player, "Studio test: +500 Gems and +2000 of every Coin")
	EconomyService.push(player)
end

function EconomyService.handleRequest(player: Player, request: any)
	if type(request) ~= "table" or type(request.action) ~= "string" then
		return
	end
	local handler = handlers[request.action]
	if handler then
		handler(player, request)
	end
end

function EconomyService.init()
	walletRemote = Net.event(Net.Names.WalletState)
	rewardRemote = Net.event(Net.Names.Reward)
	notifyRemote = Net.event(Net.Names.Notify)

	DataService.onLoaded(function(player, data, persistent)
		checkPasses(player)
		checkDay(player, data)
		EconomyService.push(player)
		if not persistent then
			notify(player, "Progress won't save this session. (In Studio: Game Settings > Security > Enable Studio Access to API Services.)")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		passes[player.UserId] = nil
	end)

	-- Catch the day changing while people are playing.
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in Players:GetPlayers() do
				local data = DataService.get(player)
				if data and data.daily.day ~= today() then
					checkDay(player, data)
					EconomyService.push(player)
				end
			end
		end
	end)
end

return EconomyService
