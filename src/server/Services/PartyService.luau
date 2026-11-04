-- Parties: invite players in this server, accept/decline, leave, kick.
-- Players stay in their party between games, which is the whole point of Game Night.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local PartyRegistry = require(script.Parent.Parent.Core.PartyRegistry)

local PartyService = {}

local registry = PartyRegistry.new(Config.MaxPartySize, Config.InviteSeconds)
local matchService: any = nil -- set in init, avoids a require cycle

local partyStateRemote: RemoteEvent
local partyInviteRemote: RemoteEvent
local notifyRemote: RemoteEvent

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
	}
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
end

function handlers.accept(player: Player, request: any)
	if type(request.partyId) ~= "string" then
		return
	end
	local ok, err = registry:acceptInvite(player.UserId, request.partyId)
	if not ok then
		return notify(player, err :: string)
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
		matchService.leaveMatch(player)
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
			matchService.leaveMatch(target)
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
			matchService.leaveMatch(player)
		end
		registry:removePlayer(player.UserId)
		flush()
	end)
end

return PartyService
