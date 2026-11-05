-- "Trending" in the Dressing Room: the catalog items Game Night players wear the most.
-- Pure, so tests/Trending.spec.luau can check it. server/Services/TrendingService keeps the
-- tally (per server, then summed across servers in a MemoryStore sorted map) and the client
-- shows the list, then items similar to the top ones, then Popular.
--
-- Scores fade: an item worn today counts twice as much as one worn HALF_LIFE_DAYS ago. To
-- keep that cheap, every new wear adds `weight(now)`, which doubles every half-life, so
-- ranking by the stored total is the same as ranking by a faded score and nothing ever has
-- to be rewritten. Items nobody wears for 45 days expire from the map.

local DressingRoom = require(script.Parent.DressingRoom)

local Trending = {}

Trending.HALF_LIFE_DAYS = 7
Trending.EPOCH = 1793491200 -- 2026-11-01 00:00 UTC, the zero point for `weight`
Trending.TTL_SECONDS = 45 * 24 * 3600 -- MemoryStore's longest expiry
Trending.LIST_SIZE = 100 -- items the server keeps and sends
Trending.FLUSH_LIMIT = 40 -- items one server writes per flush
Trending.SIMILAR_SEEDS = 8 -- top items the client asks "similar items" for

-- How much one player's wear counts. Each kind counts once per player per item per server.
Trending.Kinds = {
	avatar = 1, -- on the player's own Roblox avatar when they join
	tryOn = 1, -- tried on in the Dressing Room
	buy = 3, -- bought here
}

export type Entry = { id: number, t: number, score: number, name: string? }
export type Pending = { [number]: Entry }

-- Only things the Dressing Room can show and put on.
function Trending.eligible(id: any, t: any): boolean
	if type(id) ~= "number" or id <= 0 or id % 1 ~= 0 or id >= 2 ^ 53 then
		return false
	end
	local info = type(t) == "number" and DressingRoom.Types[t]
	return info ~= nil and info ~= false and not info.tryOnly
end

function Trending.weight(now: number): number
	return 2 ^ ((now - Trending.EPOCH) / (Trending.HALF_LIFE_DAYS * 86400))
end

-- Adds one wear to this server's unsent tally. Returns false for items that don't count.
function Trending.add(pending: Pending, id: number, t: number, kind: string, now: number, name: string?): boolean
	local base = Trending.Kinds[kind]
	if not base or not Trending.eligible(id, t) then
		return false
	end
	local entry = pending[id]
	if not entry then
		entry = { id = id, t = t, score = 0 }
		pending[id] = entry
	end
	entry.score += base * Trending.weight(now)
	if type(name) == "string" and name ~= "" then
		entry.name = name
	end
	return true
end

-- Takes up to `limit` of the biggest unsent entries out of `pending`, to write now.
function Trending.takeBatch(pending: Pending, limit: number): { Entry }
	local list = {}
	for _, entry in pending do
		table.insert(list, entry)
	end
	table.sort(list, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.id < b.id
	end)
	local out = {}
	for i = 1, math.min(limit, #list) do
		out[i] = list[i]
		pending[list[i].id] = nil
	end
	return out
end

-- The new value and sort key for one item in the sorted map, from what's there now.
function Trending.combine(old: any, oldScore: any, entry: Entry): (any, number)
	local score = (if type(oldScore) == "number" then oldScore else 0) + entry.score
	local name = entry.name
	if not name and type(old) == "table" and type(old.n) == "string" then
		name = old.n
	end
	return { t = entry.t, n = name }, score
end

-- Reads one item from GetRangeAsync ({ key, value, sortKey }). nil if it's not usable.
function Trending.decode(item: any): Entry?
	if type(item) ~= "table" then
		return nil
	end
	local id = tonumber(item.key)
	local value = item.value
	if not id or type(value) ~= "table" or not Trending.eligible(id, value.t) then
		return nil
	end
	local score = if type(item.sortKey) == "number" then item.sortKey else 0
	return { id = id, t = value.t, score = score, name = if type(value.n) == "string" then value.n else nil }
end

-- Everything Game Night has (the last read of the map) plus what this server hasn't sent
-- yet, best first. `sent` holds wears already written but not yet in the last read.
function Trending.rank(global: { Entry }, pending: Pending, sent: Pending, limit: number): { Entry }
	local merged: { [number]: Entry } = {}
	local function addAll(list: any)
		for _, e in list do
			local have = merged[e.id]
			if have then
				have.score += e.score
				have.name = have.name or e.name
			else
				merged[e.id] = { id = e.id, t = e.t, score = e.score, name = e.name }
			end
		end
	end
	addAll(global)
	addAll(pending)
	addAll(sent)
	local list = {}
	for _, e in merged do
		table.insert(list, e)
	end
	table.sort(list, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.id < b.id
	end)
	local out = {}
	for i = 1, math.min(limit, #list) do
		out[i] = list[i]
	end
	return out
end

-- What the client gets: ids, kinds and names only (scores mean nothing to it).
function Trending.toClient(list: { Entry }): { { id: number, t: number, name: string? } }
	local out = {}
	for i, e in list do
		out[i] = { id = e.id, t = e.t, name = e.name }
	end
	return out
end

-- Reads the server's list on the client, dropping anything malformed.
function Trending.fromServer(payload: any, limit: number?): { { id: number, t: number, name: string? } }
	local out = {}
	if type(payload) ~= "table" or type(payload.items) ~= "table" then
		return out
	end
	local seen = {}
	for _, item in payload.items do
		if type(item) == "table" and Trending.eligible(item.id, item.t) and not seen[item.id] then
			seen[item.id] = true
			table.insert(out, { id = item.id, t = item.t, name = if type(item.name) == "string" then item.name else nil })
			if #out >= (limit or Trending.LIST_SIZE) then
				break
			end
		end
	end
	return out
end

-- One entry of AvatarEditorService:GetBatchItemDetails as a catalog card, or nil.
function Trending.fromDetails(entry: any): { Id: number, Name: string, Price: number?, creator: string? }?
	if type(entry) ~= "table" then
		return nil
	end
	local id = tonumber(entry.Id)
	if not id or id <= 0 then
		return nil
	end
	local price = entry.Price
	if price == nil then
		price = entry.LowestPrice
	end
	if entry.IsOffSale == true then
		price = nil
	end
	return {
		Id = id,
		Name = if type(entry.Name) == "string" then entry.Name else "Item",
		Price = if type(price) == "number" then price else nil,
		creator = if type(entry.CreatorName) == "string" then entry.CreatorName else nil,
	}
end

return Trending
