-- Friends: who brought a player here (invite or "Go to their server"), the "Join X's
-- table?" prompt when they arrive, following a friend to another Game Night server, and
-- the friend invite rewards (Core/Referrals has the rules).
--
-- Joining a friend's table in this server is a party action (PartyService "joinFriend").
-- The friends list in another server comes from the client (Player:GetFriendsOnline only
-- works there); the server re-checks everything before it teleports anyone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local TeleportService = game:GetService("TeleportService")

local Economy = require(ReplicatedStorage.Shared.Economy)
local Net = require(ReplicatedStorage.Shared.Net)
local Profile = require(script.Parent.Parent.Core.Profile)
local Referrals = require(script.Parent.Parent.Core.Referrals)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local AnalyticsService = require(script.Parent.AnalyticsService)

local FriendService = {}

local PENDING_STORE = "GN_FriendRewards_v1" -- inviter rewards waiting for the inviter's server
local TOPIC = "GN_FriendReward_v1" -- "inviter X has a reward waiting"

local partyService: any = nil
local promptRemote: RemoteEvent
local notifyRemote: RemoteEvent

-- How each player got here, from their join data: { friendId, invited }.
local arrivals: { [number]: { friendId: number, invited: boolean } } = {}
-- The "Join X's table?" prompt, kept until the client asks for it (it may not be listening
-- yet when the player joins).
local pendingPrompt: { [number]: any } = {}
local following: { [number]: boolean } = {} -- players we're teleporting to a friend

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

local function today(): number
	return Profile.today(os.time())
end

local function pendingStore(): DataStore?
	local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, PENDING_STORE)
	return if ok then store else nil
end

-- Inviter rewards ---------------------------------------------------------------------

-- Pays an inviter who is in this server for one friend.
local function payInviter(inviter: Player, friendId: number, friendName: string?)
	local data = DataService.get(inviter)
	if not data then
		return false
	end
	local before = AnalyticsService.snapshot(data)
	local gems, why = Referrals.payInviter(data, friendId, today())
	if gems > 0 then
		local who = friendName or "A friend you invited"
		EconomyService.sendReward(inviter, "Friend reward", { `{who} played their first game: +{gems} {Economy.GemsName}` })
		AnalyticsService.logChange(inviter, data, before, "Onboarding", "FriendInvite")
		EconomyService.push(inviter)
	elseif why == "daily limit" then
		notify(inviter, `Friend rewards are capped at {Economy.FriendInvitesPerDay} a day. More tomorrow!`)
	end
	return true
end

-- Claims every reward stored for this player while they were somewhere else.
local claiming: { [number]: boolean } = {}
local function claimPending(player: Player)
	if claiming[player.UserId] or not DataService.get(player) then
		return
	end
	local store = pendingStore()
	if not store then
		return
	end
	claiming[player.UserId] = true
	local taken: { number } = {}
	local ok = pcall(function()
		store:UpdateAsync(`inv_{player.UserId}`, function(old)
			taken = Referrals.cleanPending(old)
			if #taken == 0 then
				return nil -- nothing to take: don't write
			end
			return {}
		end)
	end)
	claiming[player.UserId] = nil
	if ok then
		for _, friendId in taken do
			payInviter(player, friendId, nil)
		end
	end
end

-- The invited friend finished their first rewarded game: welcome Gems for them, and the
-- inviter's reward here or in whichever server they're in (or the next one they join).
local function onRewardedMatch(player: Player, data: Profile.Data)
	local before = AnalyticsService.snapshot(data)
	local inviterId, welcome = Referrals.onRewardedMatch(data)
	if not inviterId then
		return
	end
	EconomyService.sendReward(player, "Welcome bonus", { `+{welcome} {Economy.GemsName} for playing with a friend` })
	AnalyticsService.logChange(player, data, before, "Onboarding", "FriendWelcome")
	EconomyService.push(player)

	local inviter = Players:GetPlayerByUserId(inviterId)
	if inviter and payInviter(inviter, player.UserId, player.DisplayName) then
		return
	end
	local store = pendingStore()
	if not store then
		return
	end
	local stored = pcall(function()
		store:UpdateAsync(`inv_{inviterId}`, function(old)
			return Referrals.addPending(old, player.UserId)
		end)
	end)
	if stored then
		pcall(MessagingService.PublishAsync, MessagingService, TOPIC, { inviterId = inviterId })
	end
end

-- Arrivals --------------------------------------------------------------------------

local function sendPrompt(player: Player)
	local prompt = pendingPrompt[player.UserId]
	if not prompt then
		return
	end
	local friend = Players:GetPlayerByUserId(prompt.userId)
	if not friend then
		pendingPrompt[player.UserId] = nil
		return
	end
	local party = partyService.getParty(player.UserId)
	local friendParty = partyService.getParty(friend.UserId)
	if party and friendParty and party.id == friendParty.id then
		pendingPrompt[player.UserId] = nil -- already together
		return
	end
	promptRemote:FireClient(player, prompt)
	pendingPrompt[player.UserId] = nil
end

-- Reads (once) who brought this player here from their join data.
local function readArrival(player: Player): { friendId: number, invited: boolean }?
	if arrivals[player.UserId] then
		return arrivals[player.UserId]
	end
	local ok, joinData = pcall(player.GetJoinData, player)
	if not ok or type(joinData) ~= "table" then
		return nil
	end
	local inviterId = Referrals.inviterFromJoinData(joinData, player.UserId)
	local followId = Referrals.followFromTeleportData(joinData.TeleportData, player.UserId)
	local friendId = inviterId or followId
	if not friendId then
		return nil
	end
	local arrival = { friendId = friendId, invited = inviterId ~= nil }
	arrivals[player.UserId] = arrival
	return arrival
end

local function onPlayerAdded(player: Player)
	local arrival = readArrival(player)
	if not arrival then
		return
	end
	local friendId = arrival.friendId
	local invited = arrival.invited
	partyService.setArrival(player.UserId, friendId, invited)
	AnalyticsService.friendArrived(player, if invited then "invite" else "follow")

	local friend = Players:GetPlayerByUserId(friendId)
	if friend then
		pendingPrompt[player.UserId] = {
			kind = "friendHere",
			userId = friend.UserId,
			name = friend.DisplayName,
			invited = invited,
		}
		notify(friend, if invited then `{player.DisplayName} joined from your invite!` else `{player.DisplayName} followed you here`)
		sendPrompt(player) -- in case their client is already listening
	end
end

-- New players who came through an invite are remembered for the reward, but only when the
-- inviter is a Roblox friend (share links reach strangers too).
local function onLoaded(player: Player, data: Profile.Data)
	task.spawn(claimPending, player)
	local arrival = readArrival(player)
	if arrival and arrival.invited and Referrals.isNewPlayer(data) and partyService.isFriend(player, arrival.friendId) then
		Referrals.recordArrival(data, arrival.friendId)
	end
end

-- Requests ----------------------------------------------------------------------------

local handlers = {}

function handlers.sync(player: Player, _request: any)
	sendPrompt(player)
end

-- { userId }: go to the Game Night server a friend is in.
function handlers.follow(player: Player, request: any)
	local friendId = request.userId
	if type(friendId) ~= "number" or friendId <= 0 or friendId == player.UserId or following[player.UserId] then
		return
	end
	if Players:GetPlayerByUserId(friendId) then
		return notify(player, "They're in this server. Use Join instead.")
	end
	if not partyService.isFriend(player, friendId) then
		return notify(player, "You can only follow your Roblox friends")
	end
	local ok, found, _err, placeId, jobId = pcall(TeleportService.GetPlayerPlaceInstanceAsync, TeleportService, friendId)
	if not ok or not found or placeId ~= game.PlaceId or type(jobId) ~= "string" or jobId == "" then
		return notify(player, "Can't reach their server right now")
	end
	if jobId == game.JobId then
		return notify(player, "They're in this server")
	end
	local options = Instance.new("TeleportOptions")
	options.ServerInstanceId = jobId
	options:SetTeleportData({ gn = { follow = friendId } })
	following[player.UserId] = true
	notify(player, "Going to your friend's server...")
	local okTeleport = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player }, options)
	if not okTeleport then
		following[player.UserId] = nil
		notify(player, "Couldn't go to their server. It may be full.")
	end
end

function FriendService.handleRequest(player: Player, request: any)
	if type(request) ~= "table" or type(request.action) ~= "string" then
		return
	end
	local handler = handlers[request.action]
	if handler then
		handler(player, request)
	end
end

function FriendService.init(partyServiceRef: any)
	partyService = partyServiceRef
	promptRemote = Net.event(Net.Names.FriendPrompt)
	notifyRemote = Net.event(Net.Names.Notify)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		arrivals[player.UserId] = nil
		pendingPrompt[player.UserId] = nil
		following[player.UserId] = nil
	end)

	DataService.onLoaded(onLoaded)
	EconomyService.onRewardedMatch(onRewardedMatch)

	TeleportService.TeleportInitFailed:Connect(function(player, result)
		if following[player.UserId] then
			following[player.UserId] = nil
			notify(player, `Couldn't go to their server ({result.Name}). It may be full.`)
		end
	end)

	-- Rewards stored for someone who's here now.
	task.spawn(function()
		pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC, function(message)
			local payload = message.Data
			local inviterId = type(payload) == "table" and payload.inviterId
			local inviter = type(inviterId) == "number" and Players:GetPlayerByUserId(inviterId)
			if inviter then
				claimPending(inviter)
			end
		end)
	end)
end

return FriendService
