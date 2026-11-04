-- Pure party bookkeeping (no Roblox services), so it can be unit tested.
-- Every player is always in exactly one party; a player alone is a party of one.
-- PartyService wraps this with remotes and broadcasts.
--
-- Table privacy (Party Host perk): every party starts "invite" (only invited players join).
-- A leader with the Party Host pass can make it "friends" (private: the leader's Roblox
-- friends can join from the table list without an invite) or "password" (listed with a
-- lock; anyone with the 4-digit code can join). When the leader changes it goes back to
-- "invite", because the new leader may not have the pass.

local PartyRegistry = {}
PartyRegistry.__index = PartyRegistry

export type Party = {
	id: string,
	leaderId: number,
	members: { number }, -- userIds, in join order
	matchId: string?,
	privacy: Privacy,
	code: string?, -- the 4-digit code for "password" tables
}

export type Privacy = "invite" | "friends" | "password"

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
		codeFails: { [number]: { count: number, resetAt: number } }, -- wrong codes per player
		requests: { [string]: { [number]: number } }, -- partyId -> asker -> expiresAt ("Ask to join")
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
		codeFails = {},
		requests = {},
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
		privacy = "invite",
		code = nil,
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
		self.requests[partyId] = nil
	elseif party.leaderId == userId then
		party.leaderId = party.members[1]
		party.privacy = "invite"
		party.code = nil
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
	return self:_moveInto(userId, target)
end

-- Last checks, then moves userId out of their party and into target.
function PartyRegistry._moveInto(self: Registry, userId: number, target: Party): (boolean, string?)
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

PartyRegistry.Privacies = { "invite", "friends", "password" }
PartyRegistry.CodeTries = 5 -- wrong codes allowed...
PartyRegistry.CodeTrySeconds = 60 -- ...per this many seconds

-- Leader only. Anything but "invite" needs the Party Host pass (canHost). For "password"
-- the caller passes a fresh 4-digit code (the service picks it at random).
function PartyRegistry.setPrivacy(self: Registry, leaderId: number, privacy: any, canHost: boolean, code: string?): (boolean, string?)
	local party = self:getParty(leaderId)
	if not party or party.leaderId ~= leaderId then
		return false, "Only the party leader can change the table"
	end
	if not table.find(PartyRegistry.Privacies, privacy) then
		return false, "Unknown table setting"
	end
	if privacy ~= "invite" and not canHost then
		return false, "Private and password tables come with the Party Host pass"
	end
	if privacy == "password" and (type(code) ~= "string" or not string.match(code, "^%d%d%d%d$")) then
		return false, "Bad code"
	end
	party.privacy = privacy
	party.code = if privacy == "password" then code else nil
	self:_markChanged(party.id)
	return true
end

-- Parties userId could join from the table list: not their own, not invite-only.
-- (Friends-only tables are filtered by the service, which can ask Roblox about friends.)
function PartyRegistry.listJoinable(self: Registry, userId: number): { Party }
	local mine = self.partyOf[userId]
	local out = {}
	for id, party in self.parties do
		if id ~= mine and party.privacy ~= "invite" then
			table.insert(out, party)
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

-- Join a table from the list. isFriend: is userId a Roblox friend of the leader?
function PartyRegistry.joinTable(self: Registry, userId: number, partyId: any, code: any, isFriend: boolean): (boolean, string?)
	local target = if type(partyId) == "string" then self.parties[partyId] else nil
	if not target then
		return false, "That table is gone"
	end
	if table.find(target.members, userId) then
		return false, "You're already at that table"
	end
	if target.privacy == "invite" then
		return false, "That table is invite only"
	elseif target.privacy == "friends" then
		if not isFriend then
			return false, "Only the host's friends can join that table"
		end
	elseif target.privacy == "password" then
		local now = self.clock()
		local fails = self.codeFails[userId]
		if fails and now >= fails.resetAt then
			fails = nil
			self.codeFails[userId] = nil
		end
		if fails and fails.count >= PartyRegistry.CodeTries then
			return false, "Too many wrong codes. Try again in a minute."
		end
		if type(code) ~= "string" or code ~= target.code then
			fails = fails or { count = 0, resetAt = now + PartyRegistry.CodeTrySeconds }
			fails.count += 1
			self.codeFails[userId] = fails
			return false, "Wrong code"
		end
	end
	return self:_moveInto(userId, target)
end

-- "Ask to join": a friend of someone at the table asks the leader to let them in. The
-- service checks the friendship; this keeps the request until the leader answers or it
-- expires (same time as an invite). Returns the leader's user id to ask.
function PartyRegistry.requestJoin(self: Registry, userId: number, partyId: any): (boolean, string?, number?)
	local target = if type(partyId) == "string" then self.parties[partyId] else nil
	if not target then
		return false, "That table is gone"
	end
	if table.find(target.members, userId) then
		return false, "You're already at that table"
	end
	if #target.members >= self.maxSize then
		return false, "That table is full"
	end
	if target.matchId then
		return false, "They're in a game right now. Try again when it ends."
	end
	local byUser = self.requests[target.id] or {}
	self.requests[target.id] = byUser
	local now = self.clock()
	if byUser[userId] and byUser[userId] > now then
		return false, "You already asked. Waiting for the leader."
	end
	byUser[userId] = now + self.inviteSeconds
	return true, nil, target.leaderId
end

function PartyRegistry.hasRequest(self: Registry, partyId: string, userId: number): boolean
	local byUser = self.requests[partyId]
	local expiresAt = byUser and byUser[userId]
	return expiresAt ~= nil and expiresAt > self.clock()
end

-- The leader lets an asker in (accept) or says no. Either way the request is used up.
function PartyRegistry.answerJoin(self: Registry, leaderId: number, userId: number, accept: boolean): (boolean, string?)
	local party = self:getParty(leaderId)
	if not party or party.leaderId ~= leaderId then
		return false, "Only the party leader can answer"
	end
	if not self:hasRequest(party.id, userId) then
		return false, "That request has expired"
	end
	self.requests[party.id][userId] = nil
	if not accept then
		return true
	end
	if not self.partyOf[userId] then
		return false, "They left"
	end
	return self:_moveInto(userId, party)
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
	self.codeFails[userId] = nil
	for _, byUser in self.requests do
		byUser[userId] = nil
	end
end

function PartyRegistry.setMatch(self: Registry, partyId: string, matchId: string?)
	local party = self.parties[partyId]
	if party then
		party.matchId = matchId
		self:_markChanged(partyId)
	end
end

return PartyRegistry
