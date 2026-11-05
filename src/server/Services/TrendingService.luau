-- The Dressing Room's Trending tab: what Game Night players wear the most, across every
-- server. The math lives in shared/Trending (pure, tested); this file does the storage.
--
-- Each server counts wears in memory (one per player per item per kind), then once a
-- minute adds its biggest counts into the MemoryStore sorted map "GN_Trending_v1" (key =
-- asset id, value = { t, n }, sort key = faded score). Every two minutes it reads the top
-- of the map back. If MemoryStore isn't available (an unpublished place in Studio), the
-- list is just this server's own counts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MemoryStoreService = game:GetService("MemoryStoreService")

local Trending = require(ReplicatedStorage.Shared.Trending)

local TrendingService = {}

local MAP_NAME = "GN_Trending_v1"
local FLUSH_SECONDS = 60
local REFRESH_SECONDS = 120

local map: MemoryStoreSortedMap? = nil
local pending: Trending.Pending = {} -- counted here, not written yet
local sent: Trending.Pending = {} -- written, but not in the last read yet
local global: { Trending.Entry } = {}
local counted: { [number]: { [string]: boolean } } = {} -- counted[userId]["kind:id"]
local started = false

-- One player wearing (or trying on, or buying) one item. Counts once per player, item and
-- kind for as long as they're in this server.
function TrendingService.record(player: Player, id: number, t: number, kind: string, name: string?)
	local mine = counted[player.UserId]
	if not mine then
		mine = {}
		counted[player.UserId] = mine
	end
	local key = `{kind}:{id}`
	if mine[key] then
		return
	end
	if Trending.add(pending, id, t, kind, os.time(), name) then
		mine[key] = true
	end
end

function TrendingService.list(): { Trending.Entry }
	return Trending.rank(global, pending, sent, Trending.LIST_SIZE)
end

local function flush()
	local m = map
	if not m then
		return
	end
	for _, entry in Trending.takeBatch(pending, Trending.FLUSH_LIMIT) do
		local ok = pcall(m.UpdateAsync, m, tostring(entry.id), function(old, oldScore)
			return Trending.combine(old, oldScore, entry)
		end, Trending.TTL_SECONDS)
		if ok then
			local have = sent[entry.id]
			if have then
				have.score += entry.score
			else
				sent[entry.id] = entry
			end
		else
			-- Put it back for the next try.
			local have = pending[entry.id]
			if have then
				have.score += entry.score
			else
				pending[entry.id] = entry
			end
		end
	end
end

local function refresh()
	local m = map
	if not m then
		return
	end
	local ok, items = pcall(m.GetRangeAsync, m, Enum.SortDirection.Descending, Trending.LIST_SIZE)
	if not ok or type(items) ~= "table" then
		return
	end
	local list = {}
	for _, item in items do
		local entry = Trending.decode(item)
		if entry then
			table.insert(list, entry)
		end
	end
	global = list
	sent = {} -- everything written before this read is in it now
end

function TrendingService.init()
	if started then
		return
	end
	started = true
	local ok, result = pcall(function()
		return MemoryStoreService:GetSortedMap(MAP_NAME)
	end)
	map = if ok then result else nil
	task.spawn(refresh)
	task.spawn(function()
		while true do
			task.wait(FLUSH_SECONDS)
			flush()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(REFRESH_SECONDS)
			refresh()
		end
	end)
	game:BindToClose(function()
		flush()
	end)
	Players.PlayerRemoving:Connect(function(player)
		counted[player.UserId] = nil
	end)
end

return TrendingService
