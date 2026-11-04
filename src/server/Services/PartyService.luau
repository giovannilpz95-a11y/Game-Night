-- Parties: invite players in this server, accept/decline, leave, kick.
-- Players stay in their party between games, which is the whole point of Game Night.
-- Party Host leaders can also open their table to friends (private) or to anyone with a
-- 4-digit code (password); those tables show up in everyone's "Find a table" list.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local PartyRegistry = require(script.Parent.Parent.Core.PartyRegistry)
local AnalyticsService = require(script.Parent.AnalyticsService)
local EconomyService = require(script.Parent.EconomyService)

local PartyService = {}

local registry = PartyRegistry.new(Config.MaxPartySize, Config.InviteSeconds)
local matchService: any = nil -- set in init, avoids a require cycle

local partyStateRemote: RemoteEvent
local partyInviteRemote: RemoteEvent
local partyListRemote: RemoteEvent
local notifyRemote: RemoteEvent

local FRIEND_CACHE_SECONDS = 120
local friendCache: { [string]: { at: number, value: boolean } } = {}
local codeRng = Random.new()

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

local function serialize(party: PartyRegistry.Party): any
	local members = {}
	for _, userId in party.members do
		local player = Players:GetPlayerByUserId(userId)
		table.insert(members, {
			userId = userId,
			name = if player then player.DisplayName else "Player",
		})
	end
	return {
		id = party.id,
		leaderId = party.leaderId,
		members = members,
		matchId = party.matchId,
		maxSize = Config.MaxPartySize,
		privacy = party.privacy,
		code = party.code, -- only party members get this payload
	}
end

local function canHost(player: Player): boolean
	return EconomyService.hasPass(player, "partyHost")
end

-- Is `player` a Roblox friend of `otherId`? Cached for a couple of minutes; yields.
local function isFriend(player: Player, otherId: number): boolean
	local key = `{player.UserId}:{otherId}`
	local hit = friendCache[key]
	if hit and os.clock() - hit.at < FRIEND_CACHE_SECONDS then
		return hit.value
	end
	local ok, result = pcall(player.IsFriendsWith, player, otherId)
	local value = ok and result == true
	friendCache[key] = { at = os.clock(), value = value }
	return value
end

local function newCode(): string
	return string.format("%04d", codeRng:NextInteger(0, 9999))
end

-- A private or password table only stays that way while its leader has the pass.
local function effectivePrivacy(party: PartyRegistry.Party): PartyRegistry.Privacy
	local leader = Players:GetPlayerByUserId(party.leaderId)
	if party.privacy ~= "invite" and not (leader and canHost(leader)) then
		return "invite"
	end
	return party.privacy
end

-- Sends fresh party state to everyone whose party changed.
local function flush()
	for _, partyId in registry:takeChanged() do
		local party = registry:getPartyById(partyId)
		if party then
			local payload = serialize(party)
			for _, userId in party.members do
				local player = Players:GetPlayerByUserId(userId)
				if player then
					partyStateRemote:FireClient(player, payload)
				end
			end
		end
	end
end

function PartyService.getParty(userId: number): PartyRegistry.Party?
	return registry:getParty(userId)
end

function PartyService.getPartyById(partyId: string): PartyRegistry.Party?
	return registry:getPartyById(partyId)
end

function PartyService.setMatch(partyId: string, matchId: string?)
	registry:setMatch(partyId, matchId)
	flush()
end

-- Parties rebuilt after a server hop (voice servers): transfer token -> local party id.
local transferParties: { [string]: string } = {}

-- Puts a player who just arrived from another server back with their party.
-- VoiceService has already checked the transfer record lists them.
function PartyService.rejoinTransferred(token: string, leaderId: number, player: Player)
	local partyId = transferParties[token]
	local party = partyId and registry:getPartyById(partyId)
	if party then
		local ok = registry:addMember(party.id, player.UserId)
		if not ok then
			registry:ensureParty(player.UserId)
		end
	else
		-- First of the party to land: their solo party becomes the party.
		party = registry:ensureParty(player.UserId)
		if #party.members > 1 then
			-- Already in someone else's party here; start fresh so we don't merge strangers.
			registry:leave(player.UserId)
			party = registry:ensureParty(player.UserId)
		end
		transferParties[token] = party.id
	end
	if player.UserId == leaderId then
		registry:setLeader(transferParties[token], player.UserId)
	end
	flush()
end

-- Takes a player out of their party into a party of their own (left behind when the rest
-- of the party goes to a voice server).
function PartyService.split(userId: number)
	local party = registry:getParty(userId)
	if party and #party.members > 1 then
		registry:leave(userId)
		flush()
	end
end

local handlers = {}

function handlers.sync(player: Player, _request: any)
	local party = registry:ensureParty(player.UserId)
	partyStateRemote:FireClient(player, serialize(party))
end

function handlers.invite(player: Player, request: any)
	local target = if type(request.userId) == "number" then Players:GetPlayerByUserId(request.userId) else nil
	if not target then
		return notify(player, "That player isn't here")
	end
	local ok, err = registry:invite(player.UserId, target.UserId)
	if not ok then
		return notify(player, err :: string)
	end
	local party = registry:getParty(player.UserId) :: PartyRegistry.Party
	partyInviteRemote:FireClient(target, {
		partyId = party.id,
		fromUserId = player.UserId,
		fromName = player.DisplayName,
		size = #party.members,
		expiresIn = Config.InviteSeconds,
	})
	notify(player, `Invited {target.DisplayName}`)
	AnalyticsService.inviteSent(player)
end

function handlers.accept(player: Player, request: any)
	if type(request.partyId) ~= "string" then
		return
	end
	local ok, err = registry:acceptInvite(player.UserId, request.partyId)
	if not ok then
		return notify(player, err :: string)
	end
	local party = registry:getParty(player.UserId)
	AnalyticsService.inviteAccepted(player, if party then #party.members else 1, if party then party.leaderId else nil)
	flush()
end

-- Leader: { privacy = "invite" | "friends" | "password", newCode = true? }
function handlers.setPrivacy(player: Player, request: any)
	local party = registry:getParty(player.UserId)
	local code = nil
	if request.privacy == "password" then
		-- Keep the code when only re-sending the same setting; a new one on request.
		code = if party and party.code and not request.newCode then party.code else newCode()
	end
	local ok, err = registry:setPrivacy(player.UserId, request.privacy, canHost(player), code)
	if not ok then
		return notify(player, err :: string)
	end
	flush()
end

-- Tables this player could join: password tables, and friends-only tables of their friends.
function handlers.list(player: Player, _request: any)
	local rows = {}
	for _, party in registry:listJoinable(player.UserId) do
		local privacy = effectivePrivacy(party)
		local visible = privacy == "password" or (privacy == "friends" and isFriend(player, party.leaderId))
		if visible then
			local leader = Players:GetPlayerByUserId(party.leaderId)
			table.insert(rows, {
				partyId = party.id,
				leaderName = if leader then leader.DisplayName else "Player",
				size = #party.members,
				maxSize = Config.MaxPartySize,
				privacy = privacy,
				playing = party.matchId ~= nil,
			})
		end
	end
	partyListRemote:FireClient(player, rows)
end

-- { partyId, code? }
function handlers.join(player: Player, request: any)
	local target = if type(request.partyId) == "string" then registry:getPartyById(request.partyId) else nil
	if not target then
		return notify(player, "That table is gone")
	end
	if effectivePrivacy(target) == "invite" then
		return notify(player, "That table is invite only")
	end
	local friend = target.privacy == "friends" and isFriend(player, target.leaderId)
	local code = if type(request.code) == "string" then string.sub(request.code, 1, 8) else nil
	local ok, err = registry:joinTable(player.UserId, target.id, code, friend)
	if not ok then
		return notify(player, err :: string)
	end
	local leader = Players:GetPlayerByUserId(target.leaderId)
	if leader then
		notify(leader, `{player.DisplayName} joined your table`)
	end
	flush()
end

function handlers.decline(player: Player, request: any)
	if type(request.partyId) == "string" then
		registry:declineInvite(player.UserId, request.partyId)
	end
end

function handlers.leave(player: Player, _request: any)
	local party = registry:getParty(player.UserId)
	if party and party.matchId and matchService then
		matchService.leaveMatch(player, "leftParty")
	end
	local ok, err = registry:leave(player.UserId)
	if not ok then
		return notify(player, err :: string)
	end
	flush()
end

function handlers.kick(player: Player, request: any)
	if type(request.userId) ~= "number" then
		return
	end
	local party = registry:getParty(player.UserId)
	local ok, err = registry:kick(player.UserId, request.userId)
	if not ok then
		return notify(player, err :: string)
	end
	local target = Players:GetPlayerByUserId(request.userId)
	if target then
		if party and party.matchId and matchService then
			matchService.leaveMatch(target, "kicked")
		end
		notify(target, "You were removed from the party")
	end
	flush()
end

function PartyService.handleRequest(player: Player, request: any)
	if type(request) ~= "table" or type(request.action) ~= "string" then
		return
	end
	local handler = handlers[request.action]
	if handler then
		handler(player, request)
	end
end

function PartyService.init(matchServiceRef: any)
	matchService = matchServiceRef
	partyStateRemote = Net.event(Net.Names.PartyState)
	partyInviteRemote = Net.event(Net.Names.PartyInvite)
	partyListRemote = Net.event(Net.Names.PartyList)
	notifyRemote = Net.event(Net.Names.Notify)

	local function onPlayerAdded(player: Player)
		registry:ensureParty(player.UserId)
		flush()
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		if matchService then
			matchService.leaveMatch(player, "leftServer")
		end
		registry:removePlayer(player.UserId)
		local prefix = `{player.UserId}:`
		for key in friendCache do
			if string.sub(key, 1, #prefix) == prefix then
				friendCache[key] = nil
			end
		end
		flush()
	end)
end

return PartyService
