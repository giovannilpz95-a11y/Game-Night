-- Badges, weekly leaderboards and the stats profile window.
-- Levels and XP are paid in Core/Rewards; stats are recorded by Core/Stats (through Rewards
-- and AnalyticsService). This service adds what needs Roblox services on top:
--   * badges: checked after every match and stats change, paid once (Economy.BadgeGems),
--     and also awarded as Roblox badges when Badges.list has an id for them,
--   * weekly boards: each player's points are written to an OrderedDataStore per game and
--     week (Core/Weekly), batched once a minute, and the top 10 is read on request,
--   * the stats window: the player's own profile, or another player's in this server.
-- Tech notes: docs/Progression.md.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local BadgeService = game:GetService("BadgeService")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Badges = require(ReplicatedStorage.Shared.Badges)
local StatsCatalog = require(ReplicatedStorage.Shared.StatsCatalog)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Profile = require(script.Parent.Parent.Core.Profile)
local Stats = require(script.Parent.Parent.Core.Stats)
local Weekly = require(script.Parent.Parent.Core.Weekly)
local DataService = require(script.Parent.DataService)
local AnalyticsService = require(script.Parent.AnalyticsService)

local ProgressionService = {}

local FLUSH_SECONDS = 60 -- how often weekly points are written
local BOARD_CACHE_SECONDS = 60 -- how long a fetched top 10 is reused

local economyService: any = nil
local statsRemote: RemoteEvent
local rewardRemote: RemoteEvent

-- Weekly points waiting to be written: pending[userId] = { week, points = { [board] = n } }
-- Only profiles that save get onto the global boards.
local pending: { [number]: { week: number, points: { [string]: number } } } = {}
local boardCache: { [string]: { at: number, rows: { any }, source: string } } = {}
local nameCache: { [number]: string } = {}
local watching: { [number]: boolean } = {} -- opened the stats window this session
local checkQueued: { [number]: boolean } = {}

local function nameOf(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player.DisplayName
	end
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	nameCache[userId] = if ok and type(name) == "string" then name else "Player"
	return nameCache[userId]
end

local function weekInfo(): (number, number)
	local week = Weekly.week(os.time())
	return week, Weekly.endsAt(week)
end

local function profileView(player: Player, data: Profile.Data, private: boolean): any
	Weekly.current(data, os.time()) -- a new week shows 0 points, not last week's
	local view = Stats.view(data, private)
	local week, endsAt = weekInfo()
	view.userId = player.UserId
	view.name = player.DisplayName
	view.xpNeeded = Economy.xpForLevel(data.level)
	view.weekly.week = week
	view.weekly.endsAt = endsAt
	view.mine = private
	return view
end

local function sendProfile(to: Player, of: Player)
	local data = DataService.get(of)
	if not data then
		return
	end
	statsRemote:FireClient(to, { kind = "profile", profile = profileView(of, data, to == of) })
end

-- Badges -------------------------------------------------------------------------------

local function awardRobloxBadge(player: Player, badgeId: number)
	task.spawn(function()
		local ok, err = pcall(BadgeService.AwardBadge, BadgeService, player.UserId, badgeId)
		if not ok then
			warn(`[GameNight] couldn't award Roblox badge {badgeId}: {err}`)
		end
	end)
end

local function checkBadges(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local earned = Badges.newlyEarned(Stats.view(data, false), data.badges)
	if #earned == 0 then
		return
	end
	local before = AnalyticsService.snapshot(data)
	local lines = {}
	local gems = 0
	for _, badge in earned do
		data.badges[badge.id] = os.time()
		gems += Economy.BadgeGems[badge.tier] or 0
		table.insert(lines, `{badge.icon} {badge.name}: {badge.desc}`)
		if badge.roblox and badge.roblox ~= 0 then
			awardRobloxBadge(player, badge.roblox)
		end
	end
	if gems > 0 then
		Profile.addGems(data, gems)
		table.insert(lines, `+{gems} {Economy.GemsName}`)
	end
	rewardRemote:FireClient(player, { title = if #earned == 1 then "Badge unlocked" else "Badges unlocked", lines = lines })
	AnalyticsService.logChange(player, data, before, "Gameplay", "Badge")
	if economyService then
		economyService.push(player)
	end
	if watching[player.UserId] then
		sendProfile(player, player)
	end
end

-- Several stats can change at once (a payout logs Coins and Gems): check once.
local function queueCheck(player: Player)
	if checkQueued[player.UserId] then
		return
	end
	checkQueued[player.UserId] = true
	task.defer(function()
		checkQueued[player.UserId] = nil
		if player.Parent then
			checkBadges(player)
		end
	end)
end

-- Weekly boards ---------------------------------------------------------------------------

local storeCache: { [string]: OrderedDataStore } = {}
local function boardStore(week: number, board: string): OrderedDataStore?
	local name = Weekly.storeName(week, board)
	if storeCache[name] then
		return storeCache[name]
	end
	local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, name)
	if ok then
		storeCache[name] = store
		return store
	end
	return nil
end

local function queuePoints(player: Player, data: Profile.Data, gameId: string)
	-- Studio play tests never reach the live boards (Studio with API access writes to the
	-- real DataStores). The window shows this server's players instead.
	if RunService:IsStudio() or not DataService.isPersistent(player) then
		return
	end
	local weekly = data.weekly
	local entry = pending[player.UserId]
	if not entry or entry.week ~= weekly.week then
		entry = { week = weekly.week, points = {} }
		pending[player.UserId] = entry
	end
	-- Saved totals, not deltas: a retry can never count points twice.
	entry.points[gameId] = weekly.points[gameId] or 0
	entry.points[Weekly.Overall] = weekly.points[Weekly.Overall] or 0
end

local function flushUser(userId: number)
	local entry = pending[userId]
	if not entry then
		return
	end
	pending[userId] = nil
	for board, points in entry.points do
		local store = boardStore(entry.week, board)
		if store then
			local ok, err = pcall(store.SetAsync, store, tostring(userId), math.floor(points))
			if not ok then
				warn(`[GameNight] weekly board {board} save failed: {err}`)
			end
		end
	end
end

local function validBoard(board: any): boolean
	return type(board) == "string" and (board == Weekly.Overall or (StatsCatalog.games[board] ~= nil and GameCatalog.get(board) ~= nil))
end

-- Everyone in this server, for when the DataStore can't be reached (Studio without API
-- access) or is empty.
local function serverRows(board: string): { any }
	local rows = {}
	local week = Weekly.week(os.time())
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data and data.weekly.week == week then
			local points = data.weekly.points[board] or 0
			if points > 0 then
				table.insert(rows, { userId = player.UserId, points = points })
			end
		end
	end
	return Weekly.rank(rows)
end

local function fetchBoard(board: string): ({ any }, string)
	local week = Weekly.week(os.time())
	local key = `{week}:{board}`
	local cached = boardCache[key]
	if cached and os.clock() - cached.at < BOARD_CACHE_SECONDS then
		return cached.rows, cached.source
	end
	local store = boardStore(week, board)
	local rows, source = nil, "global"
	if store then
		local ok, result = pcall(function()
			local page = store:GetSortedAsync(false, Weekly.TopCount, 1):GetCurrentPage()
			local out = {}
			for i, item in page do
				local userId = tonumber(item.key)
				if userId then
					table.insert(out, { rank = i, userId = userId, points = item.value })
				end
			end
			return out
		end)
		if ok then
			rows = result
		end
	end
	if not rows then
		rows, source = serverRows(board), "server"
	end
	for _, row in rows do
		row.name = nameOf(row.userId)
	end
	boardCache[key] = { at = os.clock(), rows = rows, source = source }
	return rows, source
end

-- Client requests -------------------------------------------------------------------------

local handlers = {}

-- { action = "profile", userId = number? } -> your own profile, or someone in this server.
function handlers.profile(player: Player, request: any)
	local target = player
	if request.userId ~= nil then
		if type(request.userId) ~= "number" or request.userId % 1 ~= 0 then
			return
		end
		target = Players:GetPlayerByUserId(request.userId)
		if not target then
			return statsRemote:FireClient(player, { kind = "error", message = "That player isn't in this server" })
		end
	end
	if target == player then
		watching[player.UserId] = true
	end
	sendProfile(player, target)
end

-- { action = "board", board = gameId | "_all" } -> top 10 this week, plus your points.
function handlers.board(player: Player, request: any)
	if not validBoard(request.board) then
		return
	end
	local board = request.board
	local rows, source = fetchBoard(board)
	local data = DataService.get(player)
	local mine = 0
	if data then
		mine = Weekly.current(data, os.time()).points[board] or 0
	end
	local week, endsAt = weekInfo()
	statsRemote:FireClient(player, {
		kind = "board",
		board = board,
		week = week,
		endsAt = endsAt,
		rows = rows,
		you = mine,
		source = source,
	})
end

function ProgressionService.handleRequest(player: Player, request: any)
	if type(request) ~= "table" or type(request.action) ~= "string" then
		return
	end
	local handler = handlers[request.action]
	if handler then
		handler(player, request)
	end
end

function ProgressionService.init(economy: any)
	economyService = economy
	statsRemote = Net.event(Net.Names.StatsState)
	rewardRemote = Net.event(Net.Names.Reward)

	economy.onMatchRecorded(function(player: Player, data: Profile.Data, payout: any, gameId: string)
		if payout.weeklyPoints > 0 then
			queuePoints(player, data, gameId)
			boardCache[`{data.weekly.week}:{gameId}`] = nil
		end
		queueCheck(player)
		if watching[player.UserId] then
			sendProfile(player, player)
		end
	end)
	AnalyticsService.onStatsChanged(queueCheck)
	DataService.onLoaded(function(player)
		queueCheck(player) -- badges for things done before badges existed
	end)

	Players.PlayerRemoving:Connect(function(player)
		watching[player.UserId] = nil
		checkQueued[player.UserId] = nil
		task.spawn(flushUser, player.UserId)
	end)

	task.spawn(function()
		while true do
			task.wait(FLUSH_SECONDS)
			for userId in pending do
				task.spawn(flushUser, userId)
			end
		end
	end)
	-- Shutdown: write what's left, waiting at most 5 seconds. Nothing is ever pending in
	-- Studio (see queuePoints), so Stop doesn't wait here.
	game:BindToClose(function()
		local left = 0
		for userId in pending do
			left += 1
			task.spawn(function()
				flushUser(userId)
				left -= 1
			end)
		end
		local deadline = os.clock() + 5
		while left > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return ProgressionService
