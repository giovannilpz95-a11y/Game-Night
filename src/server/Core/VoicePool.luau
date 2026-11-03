-- Pure bookkeeping for the pool of voice-only servers, so it can be unit tested.
-- VoiceService keeps one entry per voice server in a MemoryStore SortedMap and runs these
-- functions inside UpdateAsync, so two lobbies can't overfill the same server.
--
-- An entry: { players = <count>, holds = { [token] = { count, expires } }, updated = <os.time> }
--  * players: humans in that server, written by the server's heartbeat.
--  * holds: seats saved for parties that are teleporting in right now. A hold shrinks as its
--    party arrives and disappears when it expires, so a failed teleport frees its seats.

local VoicePool = {}

export type Hold = { count: number, expires: number }
export type Entry = { players: number, holds: { [string]: Hold }, updated: number }

local function asEntry(value: any): Entry
	if type(value) ~= "table" then
		return { players = 0, holds = {}, updated = 0 }
	end
	return {
		players = if type(value.players) == "number" then value.players else 0,
		holds = if type(value.holds) == "table" then value.holds else {},
		updated = if type(value.updated) == "number" then value.updated else 0,
	}
end

-- Seats taken plus seats held for parties on their way.
function VoicePool.seatsUsed(value: any, now: number): number
	local entry = asEntry(value)
	local used = entry.players
	for _, hold in entry.holds do
		if type(hold) == "table" and type(hold.count) == "number" and (hold.expires or 0) > now then
			used += hold.count
		end
	end
	return used
end

-- Picks the server for a party of `partySize`: the fullest live server that still has room,
-- so rooms fill up and feel busy instead of spreading everyone thin.
-- `entries` is a list of { key, value }. Returns the key, or nil when a new server is needed.
function VoicePool.choose(entries: { { key: string, value: any } }, partySize: number, capacity: number, now: number, staleSeconds: number): string?
	local bestKey: string? = nil
	local bestUsed = -1
	for _, item in entries do
		local entry = asEntry(item.value)
		if now - entry.updated <= staleSeconds then
			local used = VoicePool.seatsUsed(entry, now)
			if used + partySize <= capacity then
				if used > bestUsed or (used == bestUsed and bestKey ~= nil and item.key < bestKey) then
					bestKey = item.key
					bestUsed = used
				end
			end
		end
	end
	return bestKey
end

-- UpdateAsync body that saves `count` seats for a party. Returns the new entry, or nil when
-- the server filled up in the meantime (the caller then picks again).
-- `isNew` is true for a server the lobby just created, which has no heartbeat yet.
function VoicePool.addHold(value: any, token: string, count: number, capacity: number, now: number, holdSeconds: number, isNew: boolean?): Entry?
	if value == nil and not isNew then
		return nil -- the server shut down (its entry expired)
	end
	local entry = asEntry(value)
	if isNew and value == nil then
		entry.updated = now -- counts as live until its first heartbeat
	end
	if VoicePool.seatsUsed(entry, now) + count > capacity then
		return nil
	end
	entry.holds[token] = { count = count, expires = now + holdSeconds }
	return entry
end

-- Drops a party's hold (its teleport failed).
function VoicePool.releaseHold(value: any, token: string): Entry?
	if value == nil then
		return nil
	end
	local entry = asEntry(value)
	entry.holds[token] = nil
	return entry
end

-- UpdateAsync body for the voice server's heartbeat. `arrived[token]` is how many members of
-- that party have reached this server; their seats now count under `players` instead.
function VoicePool.heartbeat(value: any, players: number, arrived: { [string]: number }, now: number): Entry
	local entry = asEntry(value)
	local holds = {}
	for token, hold in entry.holds do
		if type(hold) == "table" and type(hold.count) == "number" and (hold.expires or 0) > now then
			local left = hold.count - (arrived[token] or 0)
			if left > 0 then
				holds[token] = { count = left, expires = hold.expires }
			end
		end
	end
	return { players = players, holds = holds, updated = now }
end

return VoicePool
