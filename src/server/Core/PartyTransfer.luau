-- Moving a party between servers (lobby <-> voice servers) without losing who's in it.
-- Pure, so it can be unit tested.
--
-- The sending server writes a transfer record to MemoryStore under a random token, and puts
-- only that token in the teleport data. Teleport data passes through the player's client, so
-- it can't be trusted: the receiving server reads the record (which only servers can write)
-- and checks the arriving player is on it before putting them back in the party.

local PartyTransfer = {}

export type Mode = "voice" | "lobby"
export type Record = {
	mode: Mode,
	leaderId: number,
	members: { number },
	serverKey: string?, -- the voice server's pool key (mode "voice" only)
	created: number,
}

local MAX_TOKEN_LENGTH = 64

function PartyTransfer.newRecord(mode: Mode, leaderId: number, members: { number }, serverKey: string?, now: number): Record
	local copy = table.clone(members)
	if not table.find(copy, leaderId) then
		table.insert(copy, 1, leaderId)
	end
	return {
		mode = mode,
		leaderId = leaderId,
		members = copy,
		serverKey = serverKey,
		created = now,
	}
end

-- What goes in TeleportOptions:SetTeleportData. `notice` is a cosmetic message key only.
function PartyTransfer.teleportData(token: string?, notice: string?): any
	return { gn = { token = token, notice = notice } }
end

-- Reads our part of a player's teleport data. Never errors on junk.
function PartyTransfer.read(teleportData: any): (string?, string?)
	if type(teleportData) ~= "table" or type(teleportData.gn) ~= "table" then
		return nil, nil
	end
	local token = teleportData.gn.token
	local notice = teleportData.gn.notice
	if type(token) ~= "string" or #token == 0 or #token > MAX_TOKEN_LENGTH then
		token = nil
	end
	if type(notice) ~= "string" or #notice > 32 then
		notice = nil
	end
	return token, notice
end

-- True when `record` is a real, fresh transfer that includes `userId`.
function PartyTransfer.validate(record: any, userId: number, now: number, ttl: number): boolean
	if type(record) ~= "table" or type(record.members) ~= "table" then
		return false
	end
	if record.mode ~= "voice" and record.mode ~= "lobby" then
		return false
	end
	if type(record.created) ~= "number" or now - record.created > ttl then
		return false
	end
	return table.find(record.members, userId) ~= nil
end

-- Splits party members into those who can use voice chat and those who can't.
-- `eligible[userId]` is the server's answer; nil (unknown) counts as not eligible.
function PartyTransfer.splitEligible(members: { number }, eligible: { [number]: boolean? }): ({ number }, { number })
	local yes, no = {}, {}
	for _, userId in members do
		if eligible[userId] == true then
			table.insert(yes, userId)
		else
			table.insert(no, userId)
		end
	end
	return yes, no
end

return PartyTransfer
