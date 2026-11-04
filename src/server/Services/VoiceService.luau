-- Voice servers: reserved servers where everyone has voice chat, so parties can talk while
-- they play. The party leader presses "Voice servers" in the lobby; this service checks
-- every member can use voice chat, finds (or creates) a voice server with room, and
-- teleports the party there together. "Back to lobby" does the reverse.
--
-- Pieces (details in docs/VoiceServers.md):
--  * MemoryStore SortedMap "GN_VoiceServers_v1": the pool of live voice servers and how full
--    they are (pure logic in Core/VoicePool).
--  * MemoryStore HashMap "GN_PartyTransfer_v1": who is in each travelling party, so the
--    receiving server can rebuild the party without trusting teleport data (Core/PartyTransfer).
--  * Saved data stays consistent because DataService's session lock means only one server
--    owns a profile; we save right before teleporting and the new server waits for the lock.

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local VoiceChatService = game:GetService("VoiceChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local VoicePool = require(script.Parent.Parent.Core.VoicePool)
local PartyTransfer = require(script.Parent.Parent.Core.PartyTransfer)
local DataService = require(script.Parent.DataService)

local VoiceService = {}

local cfg = Config.Voice

local NEEDS_VOICE = "Voice servers are for players with voice chat. Roblox turns voice chat on for accounts that are 13+ and have done the age check (Settings > Privacy on Roblox)."

local partyService: any = nil
local stateRemote: RemoteEvent
local notifyRemote: RemoteEvent

local isVoiceServer = false
local serverKey: string? = nil -- this voice server's pool key, learned from a trusted transfer
local heartbeatRunning = false
local arrived: { [string]: number } = {} -- transfer token -> members that reached this server
local eligibilityCache: { [number]: { value: boolean, at: number } } = {}
local teleporting: { [number]: boolean } = {}
local busyParties: { [string]: boolean } = {}

local poolMap: MemoryStoreSortedMap? = nil
local transferMap: MemoryStoreHashMap? = nil

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

local function voicePlaceId(): number
	return if cfg.PlaceId ~= 0 then cfg.PlaceId else game.PlaceId
end

local function lobbyPlaceId(): number
	return if cfg.LobbyPlaceId ~= 0 then cfg.LobbyPlaceId else game.PlaceId
end

local function capacity(): number
	if cfg.PlaceId == 0 then
		return math.min(cfg.Capacity, Players.MaxPlayers)
	end
	return cfg.Capacity
end

local function detectVoiceServer(): boolean
	if RunService:IsStudio() then
		return cfg.StudioActsAsVoiceServer
	end
	if cfg.PlaceId ~= 0 then
		return game.PlaceId == cfg.PlaceId
	end
	-- Reserved servers (made by this script) have a PrivateServerId but no owner. Paid
	-- private servers have an owner, so they stay normal servers.
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

-- true / false, or nil when Roblox couldn't tell us right now.
local function checkEligible(player: Player): boolean?
	local cached = eligibilityCache[player.UserId]
	if cached and os.clock() - cached.at < cfg.EligibilityCacheSeconds then
		return cached.value
	end
	local ok, result = pcall(VoiceChatService.IsVoiceEnabledForUserIdAsync, VoiceChatService, player.UserId)
	if not ok then
		warn(`[GameNight] voice check failed for {player.Name}: {result}`)
		return nil
	end
	eligibilityCache[player.UserId] = { value = result == true, at = os.clock() }
	return result == true
end

local function sendState(player: Player, extra: { [string]: any }?)
	local state = {
		enabled = cfg.Enabled,
		isVoiceServer = isVoiceServer,
		teleporting = teleporting[player.UserId] == true,
	}
	for key, value in extra or {} do
		state[key] = value
	end
	stateRemote:FireClient(player, state)
end

local function setTeleporting(players: { Player }, value: boolean)
	for _, player in players do
		teleporting[player.UserId] = if value then true else nil
		if player.Parent then
			sendState(player)
		end
	end
end

-- Saves everyone's profile before they leave, so the next server loads fresh data.
local function saveAll(players: { Player })
	local pending = #players
	for _, player in players do
		task.spawn(function()
			pcall(DataService.saveNow, player)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 5
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end

local function teleport(placeId: number, players: { Player }, options: TeleportOptions): (boolean, string?)
	local lastErr = nil
	for attempt = 1, cfg.TeleportRetries do
		local present = {}
		for _, player in players do
			if player.Parent then
				table.insert(present, player)
			end
		end
		if #present == 0 then
			return false, "everyone left"
		end
		local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, placeId, present, options)
		if ok then
			return true
		end
		lastErr = tostring(err)
		task.wait(attempt * 2)
	end
	return false, lastErr
end

local function writeTransfer(token: string, record: PartyTransfer.Record): boolean
	if not transferMap then
		return false
	end
	local ok, err = pcall(function()
		(transferMap :: MemoryStoreHashMap):SetAsync(token, record, cfg.TransferTtlSeconds)
	end)
	if not ok then
		warn(`[GameNight] couldn't save party transfer: {err}`)
	end
	return ok
end

-- Finds a voice server with room for `count` players and holds the seats.
-- Returns the server's key (a new GUID when every server is full).
local function reserveSeats(token: string, count: number): (string, boolean)
	local map = poolMap
	if map then
		for _ = 1, 3 do
			local entries = {}
			local okRange, items = pcall(map.GetRangeAsync, map, Enum.SortDirection.Ascending, 100)
			if not okRange then
				warn(`[GameNight] voice server pool unavailable: {items}`)
				break
			end
			for _, item in items do
				table.insert(entries, { key = item.key, value = item.value })
			end
			local now = os.time()
			local key = VoicePool.choose(entries, count, capacity(), now, cfg.ServerTtlSeconds)
			local isNew = key == nil
			local chosen = key or HttpService:GenerateGUID(false)
			local okUpdate, result = pcall(map.UpdateAsync, map, chosen, function(old)
				return VoicePool.addHold(old, token, count, capacity(), os.time(), cfg.HoldSeconds, isNew)
			end, cfg.ServerTtlSeconds * 2)
			if okUpdate and result ~= nil then
				return chosen, isNew
			end
			-- It filled up (or shut down) between reading and holding: pick again.
		end
	end
	return HttpService:GenerateGUID(false), true
end

local function releaseSeats(key: string, token: string)
	local map = poolMap
	if map then
		pcall(map.UpdateAsync, map, key, function(old)
			return VoicePool.releaseHold(old, token)
		end, cfg.ServerTtlSeconds * 2)
	end
end

local function playersOf(userIds: { number }): { Player }
	local list = {}
	for _, userId in userIds do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			table.insert(list, player)
		end
	end
	return list
end

local function studioBlocked(player: Player): boolean
	if RunService:IsStudio() then
		notify(player, "Teleports don't work in Studio play tests. Publish the game and try it in the Roblox app.")
		return true
	end
	return false
end

local function startHeartbeat()
	if heartbeatRunning or not serverKey or not poolMap then
		return
	end
	heartbeatRunning = true
	local map = poolMap :: MemoryStoreSortedMap
	task.spawn(function()
		while serverKey do
			local key = serverKey :: string
			pcall(map.UpdateAsync, map, key, function(old)
				return VoicePool.heartbeat(old, #Players:GetPlayers(), arrived, os.time())
			end, cfg.ServerTtlSeconds)
			task.wait(cfg.HeartbeatSeconds)
		end
	end)
end

-- An ineligible player reached a voice server (joined a friend, or lost voice access):
-- send them to a normal server with an explanation.
local function sendToLobby(player: Player)
	notify(player, NEEDS_VOICE)
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData(PartyTransfer.teleportData(nil, "voiceDenied"))
	task.wait(3) -- time to read the message
	if not player.Parent then
		return
	end
	local ok = teleport(lobbyPlaceId(), { player }, options)
	if not ok and player.Parent then
		player:Kick(`This is a voice chat server. {NEEDS_VOICE}`)
	end
end

local handlers = {}

function handlers.sync(player: Player, _request: any)
	sendState(player, { eligible = checkEligible(player) })
end

-- Leader: take the party to a voice server.
function handlers.join(player: Player, request: any)
	if not cfg.Enabled then
		return notify(player, "Voice servers are switched off right now")
	end
	if isVoiceServer then
		return notify(player, "You're already in a voice server")
	end
	local party = partyService.getParty(player.UserId)
	if not party then
		return
	end
	if party.leaderId ~= player.UserId then
		return notify(player, "Only the party leader can take the party to a voice server")
	end
	if party.matchId then
		return notify(player, "Finish or leave your game first")
	end
	if busyParties[party.id] then
		return
	end

	-- Everyone must be able to use voice chat. The server asks Roblox; clients can't fake it.
	local eligible = {}
	for _, member in playersOf(party.members) do
		eligible[member.UserId] = checkEligible(member)
	end
	local going, staying = PartyTransfer.splitEligible(party.members, eligible)
	if not table.find(going, player.UserId) then
		return notify(player, NEEDS_VOICE)
	end
	if #staying > 0 and request.force ~= true then
		local names = {}
		for _, member in playersOf(staying) do
			table.insert(names, member.DisplayName)
			notify(member, `{player.DisplayName} wants to go to a voice server, but your account can't use voice chat yet. {NEEDS_VOICE}`)
		end
		return sendState(player, { prompt = { names = names, going = #going } })
	end
	if studioBlocked(player) then
		return
	end

	busyParties[party.id] = true
	local travellers = playersOf(going)
	for _, member in playersOf(staying) do
		partyService.split(member.UserId)
		notify(member, "Your party went to a voice server without you. You can keep playing here.")
	end

	local token = HttpService:GenerateGUID(false)
	local key = reserveSeats(token, #travellers)
	local record = PartyTransfer.newRecord("voice", player.UserId, going, key, os.time())
	writeTransfer(token, record)

	setTeleporting(travellers, true)
	saveAll(travellers)
	local options = Instance.new("TeleportOptions")
	options.ReservedServerId = key
	options:SetTeleportData(PartyTransfer.teleportData(token, nil))
	local ok, err = teleport(voicePlaceId(), travellers, options)
	busyParties[party.id] = nil
	if not ok then
		warn(`[GameNight] voice teleport failed: {err}`)
		releaseSeats(key, token)
		setTeleporting(travellers, false)
		for _, member in travellers do
			if member.Parent then
				notify(member, "Couldn't reach a voice server. Please try again in a moment.")
			end
		end
	end
end

-- In a voice server: the leader takes the party back to a normal server; anyone else goes alone.
function handlers.lobby(player: Player, _request: any)
	if not isVoiceServer then
		return
	end
	local party = partyService.getParty(player.UserId)
	if not party then
		return
	end
	if party.matchId then
		return notify(player, "Finish or leave your game first")
	end
	if busyParties[party.id] or studioBlocked(player) then
		return
	end
	local userIds = if party.leaderId == player.UserId then table.clone(party.members) else { player.UserId }
	if party.leaderId ~= player.UserId then
		partyService.split(player.UserId)
	end
	busyParties[party.id] = true
	local travellers = playersOf(userIds)
	local token = HttpService:GenerateGUID(false)
	writeTransfer(token, PartyTransfer.newRecord("lobby", player.UserId, userIds, nil, os.time()))

	setTeleporting(travellers, true)
	saveAll(travellers)
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData(PartyTransfer.teleportData(token, nil))
	local ok, err = teleport(lobbyPlaceId(), travellers, options)
	busyParties[party.id] = nil
	if not ok then
		warn(`[GameNight] lobby teleport failed: {err}`)
		setTeleporting(travellers, false)
		notify(player, "Couldn't reach the lobby. Please try again in a moment.")
	end
end

function VoiceService.handleRequest(player: Player, request: any)
	if type(request) ~= "table" or type(request.action) ~= "string" then
		return
	end
	local handler = handlers[request.action]
	if handler then
		handler(player, request)
	end
end

function VoiceService.isVoiceServer(): boolean
	return isVoiceServer
end

local function onPlayerAdded(player: Player)
	local okJoin, joinData = pcall(player.GetJoinData, player)
	local token, notice = PartyTransfer.read(if okJoin and type(joinData) == "table" then joinData.TeleportData else nil)

	if isVoiceServer and not RunService:IsStudio() then
		local eligible = checkEligible(player)
		if eligible == nil then
			task.wait(5)
			eligible = checkEligible(player)
		end
		-- If Roblox still can't answer, let them in rather than bounce everyone during an outage.
		if eligible == false then
			task.spawn(sendToLobby, player)
			return
		end
	elseif notice == "voiceDenied" then
		notify(player, NEEDS_VOICE)
	end

	if token and transferMap then
		local okGet, record = pcall((transferMap :: MemoryStoreHashMap).GetAsync, transferMap, token)
		if okGet and PartyTransfer.validate(record, player.UserId, os.time(), cfg.TransferTtlSeconds) then
			if isVoiceServer and record.mode == "voice" and not serverKey and type(record.serverKey) == "string" then
				serverKey = record.serverKey
				startHeartbeat()
			end
			arrived[token] = (arrived[token] or 0) + 1
			if player.Parent then
				partyService.rejoinTransferred(token, record.leaderId, player)
			end
		end
	end

	if player.Parent then
		sendState(player, { eligible = checkEligible(player) })
	end
end

function VoiceService.init(partyServiceRef: any)
	partyService = partyServiceRef
	stateRemote = Net.event(Net.Names.VoiceState)
	notifyRemote = Net.event(Net.Names.Notify)
	isVoiceServer = detectVoiceServer()

	local okPool, pool = pcall(MemoryStoreService.GetSortedMap, MemoryStoreService, "GN_VoiceServers_v1")
	poolMap = if okPool then pool else nil
	local okTransfer, transfer = pcall(MemoryStoreService.GetHashMap, MemoryStoreService, "GN_PartyTransfer_v1")
	transferMap = if okTransfer then transfer else nil

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		eligibilityCache[player.UserId] = nil
		teleporting[player.UserId] = nil
	end)

	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		if teleporting[player.UserId] then
			setTeleporting({ player }, false)
			notify(player, `Teleport failed ({result.Name}). Please try again.`)
			warn(`[GameNight] teleport failed for {player.Name}: {message}`)
		end
	end)

	if isVoiceServer and not RunService:IsStudio() then
		game:BindToClose(function()
			local key = serverKey
			serverKey = nil
			if key and poolMap then
				pcall((poolMap :: MemoryStoreSortedMap).RemoveAsync, poolMap, key)
			end
		end)
	end
end

return VoiceService
