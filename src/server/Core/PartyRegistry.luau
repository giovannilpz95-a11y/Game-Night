-- Pure party bookkeeping (no Roblox services), so it can be unit tested.
-- Every player is always in exactly one party; a player alone is a party of one.
-- PartyService wraps this with remotes and broadcasts.

local PartyRegistry = {}
PartyRegistry.__index = PartyRegistry

export type Party = {
	id: string,
	leaderId: number,
	members: { number }, -- userIds, in join order
	matchId: string?,
}

export type Registry = typeof(setmetatable(
	{} :: {
		maxSize: number,
		inviteSeconds: number,
		clock: () -> number,
		nextId: number,
		parties: { [string]: Party },
		partyOf: { [number]: string },
		invites: { [number]: { [string]: number } }, -- invitee -> partyId -> expiresAt
		changed: { [string]: boolean },
	},
	PartyRegistry
))

function PartyRegistry.new(maxSize: number, inviteSeconds: number, clock: (() -> number)?): Registry
	local self = setmetatable({
		maxSize = maxSize,
		inviteSeconds = inviteSeconds,
		clock = clock or os.clock,
		nextId = 0,
		parties = {},
		partyOf = {},
		invites = {},
		changed = {},
	}, PartyRegistry)
	return self
end

function PartyRegistry._markChanged(self: Registry, partyId: string)
	self.changed[partyId] = true
end

-- Returns the ids of parties that changed since the last call, then forgets them.
-- Ids of deleted parties are included; getPartyById returns nil for those.
function PartyRegistry.takeChanged(self: Registry): { string }
	local ids = {}
	for id in self.changed do
		table.insert(ids, id)
	end
	table.clear(self.changed)
	table.sort(ids)
	return ids
end

function PartyRegistry._newParty(self: Registry, leaderId: number): Party
	self.nextId += 1
	local party: Party = {
		id = `P{self.nextId}`,
		leaderId = leaderId,
		members = { leaderId },
		matchId = nil,
	}
	self.parties[party.id] = party
	self.partyOf[leaderId] = party.id
	self:_markChanged(party.id)
	return party
end

-- Takes userId out of its current party (deleting or re-leading it) without giving it a new one.
function PartyRegistry._detach(self: Registry, userId: number)
	local partyId = self.partyOf[userId]
	if not partyId then
		return
	end
	local party = self.parties[partyId]
	self.partyOf[userId] = nil
	if not party then
		return
	end
	local index = table.find(party.members, userId)
	if index then
		table.remove(party.members, index)
	end
	if #party.members == 0 then
		self.parties[partyId] = nil
		-- Nobody can join a party that no longer exists.
		for _, byParty in self.invites do
			byParty[partyId] = nil
		end
	elseif party.leaderId == userId then
		party.leaderId = party.members[1]
	end
	self:_markChanged(partyId)
end

function PartyRegistry.ensureParty(self: Registry, userId: number): Party
	local partyId = self.partyOf[userId]
	if partyId and self.parties[partyId] then
		return self.parties[partyId]
	end
	return self:_newParty(userId)
end

function PartyRegistry.getParty(self: Registry, userId: number): Party?
	local partyId = self.partyOf[userId]
	return if partyId then self.parties[partyId] else nil
end

function PartyRegistry.getPartyById(self: Registry, partyId: string): Party?
	return self.parties[partyId]
end

function PartyRegistry.invite(self: Registry, fromId: number, toId: number): (boolean, string?)
	if fromId == toId then
		return false, "You can't invite yourself"
	end
	local party = self:getParty(fromId)
	if not party then
		return false, "You're not in a party"
	end
	if party.leaderId ~= fromId then
		return false, "Only the party leader can invite"
	end
	if not self.partyOf[toId] then
		return false, "That player isn't here"
	end
	if table.find(party.members, toId) then
		return false, "They're already in your party"
	end
	if #party.members >= self.maxSize then
		return false, "Your party is full"
	end
	self.invites[toId] = self.invites[toId] or {}
	self.invites[toId][party.id] = self.clock() + self.inviteSeconds
	return true
end

function PartyRegistry.hasInvite(self: Registry, userId: number, partyId: string): boolean
	local byParty = self.invites[userId]
	local expiresAt = byParty and byParty[partyId]
	return expiresAt ~= nil and expiresAt > self.clock()
end

function PartyRegistry.declineInvite(self: Registry, userId: number, partyId: string)
	local byParty = self.invites[userId]
	if byParty then
		byParty[partyId] = nil
	end
end

function PartyRegistry.acceptInvite(self: Registry, userId: number, partyId: string): (boolean, string?)
	if not self:hasInvite(userId, partyId) then
		return false, "That invite has expired"
	end
	self:declineInvite(userId, partyId)
	local target = self.parties[partyId]
	if not target then
		return false, "That party no longer exists"
	end
	if #target.members >= self.maxSize then
		return false, "That party is full"
	end
	if target.matchId then
		return false, "That party is in the middle of a game"
	end
	local current = self:getParty(userId)
	if current and current.matchId then
		return false, "Finish or leave your current game first"
	end
	self:_detach(userId)
	table.insert(target.members, userId)
	self.partyOf[userId] = target.id
	self:_markChanged(target.id)
	return true
end

-- Leave your party and go back to a party of one.
function PartyRegistry.leave(self: Registry, userId: number): (boolean, string?)
	local party = self:getParty(userId)
	if not party then
		return false, "You're not in a party"
	end
	if #party.members == 1 then
		return false, "You're already on your own"
	end
	self:_detach(userId)
	self:_newParty(userId)
	return true
end

function PartyRegistry.kick(self: Registry, leaderId: number, targetId: number): (boolean, string?)
	local party = self:getParty(leaderId)
	if not party or party.leaderId ~= leaderId then
		return false, "Only the party leader can remove players"
	end
	if leaderId == targetId then
		return false, "Use Leave instead"
	end
	if not table.find(party.members, targetId) then
		return false, "They're not in your party"
	end
	self:_detach(targetId)
	self:_newParty(targetId)
	return true
end

-- Puts a player straight into a party, no invite needed. Only for parties that arrive from
-- another server together (see PartyTransfer); the server has already checked the roster.
function PartyRegistry.addMember(self: Registry, partyId: string, userId: number): (boolean, string?)
	local target = self.parties[partyId]
	if not target then
		return false, "That party no longer exists"
	end
	if table.find(target.members, userId) then
		return true
	end
	if #target.members >= self.maxSize then
		return false, "That party is full"
	end
	self:_detach(userId)
	table.insert(target.members, userId)
	self.partyOf[userId] = target.id
	self:_markChanged(target.id)
	return true
end

-- Hands the crown to a member (used when the original leader arrives after the others).
function PartyRegistry.setLeader(self: Registry, partyId: string, userId: number): boolean
	local party = self.parties[partyId]
	if not party or not table.find(party.members, userId) then
		return false
	end
	if party.leaderId ~= userId then
		party.leaderId = userId
		self:_markChanged(partyId)
	end
	return true
end

-- The player left the server.
function PartyRegistry.removePlayer(self: Registry, userId: number)
	self:_detach(userId)
	self.invites[userId] = nil
end

function PartyRegistry.setMatch(self: Registry, partyId: string, matchId: string?)
	local party = self.parties[partyId]
	if party then
		party.matchId = matchId
		self:_markChanged(partyId)
	end
end

return PartyRegistry
