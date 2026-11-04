-- "For you" in the Dressing Room: picks items like the ones a player is wearing.
-- Pure, so tests/Recommendations.spec.luau can check it. The client does the Roblox calls:
--
-- 1. `seeds` picks which worn items to ask about: what you tried on here first (newest
--    first), then your own avatar's items, one of each kind before any second of a kind.
-- 2. For each seed, AvatarEditorService:GetRecommendedAssetsAsync(type, id) returns the
--    catalog's "similar items" for it (the same list the Roblox website shows).
-- 3. `merge` ranks everything: items several seeds agree on go first, then items near the
--    top of a list, with a bonus for creators you already wear. Items you have on are left out.
-- 4. When the seeds run out, the client searches the catalog by `topCreators`.

local Recommendations = {}

Recommendations.SEEDS_PER_BATCH = 4
Recommendations.MAX_SEEDS = 12
Recommendations.CREATOR_BONUS = 0.35

export type Seed = { id: number, t: number }
export type Pick = { Id: number, Name: string?, Price: number?, creator: string?, [string]: any }

-- `tried` is the Dressing Room look in the order items went on (newest last), `own` the
-- player's own avatar items. Only types in `allowed` (AssetTypeId -> anything) count.
function Recommendations.seeds(tried: { Seed }, own: { Seed }, allowed: { [number]: any }, max: number?): { Seed }
	local limit = max or Recommendations.MAX_SEEDS
	local ordered: { Seed } = {}
	for i = #tried, 1, -1 do
		table.insert(ordered, tried[i])
	end
	for _, item in own do
		table.insert(ordered, item)
	end
	local seen: { [number]: boolean } = {}
	local usedType: { [number]: boolean } = {}
	local first, later = {}, {}
	for _, item in ordered do
		if type(item.id) == "number" and item.id > 0 and allowed[item.t] ~= nil and not seen[item.id] then
			seen[item.id] = true
			if usedType[item.t] then
				table.insert(later, item)
			else
				usedType[item.t] = true
				table.insert(first, item)
			end
		end
	end
	local out = {}
	for _, list in { first, later } do
		for _, item in list do
			if #out < limit then
				table.insert(out, item)
			end
		end
	end
	return out
end

-- The creators that show up most in a look, most first (ties keep look order).
function Recommendations.topCreators(items: { { creator: string? } }, n: number): { string }
	local counts: { [string]: number } = {}
	local order: { string } = {}
	for _, item in items do
		local name = item.creator
		if type(name) == "string" and name ~= "" then
			if not counts[name] then
				counts[name] = 0
				table.insert(order, name)
			end
			counts[name] += 1
		end
	end
	local index = {}
	for i, name in order do
		index[name] = i
	end
	table.sort(order, function(a, b)
		if counts[a] ~= counts[b] then
			return counts[a] > counts[b]
		end
		return index[a] < index[b]
	end)
	local out = {}
	for i = 1, math.min(n, #order) do
		out[i] = order[i]
	end
	return out
end

-- Ranks picks from several "similar items" lists. `exclude` holds ids to leave out (worn
-- or already shown), `creators` the names worth a bonus. Returns at most `limit` picks.
function Recommendations.merge(lists: { { Pick } }, exclude: { [number]: boolean }, creators: { string }, limit: number): { Pick }
	local favorite: { [string]: boolean } = {}
	for _, name in creators do
		favorite[name] = true
	end
	local score: { [number]: number } = {}
	local firstSeen: { [number]: number } = {}
	local pick: { [number]: Pick } = {}
	local seenCount = 0
	for _, list in lists do
		local n = #list
		local inThisList: { [number]: boolean } = {}
		for rank, item in list do
			local id = item.Id
			if type(id) == "number" and not exclude[id] and not inThisList[id] then
				inThisList[id] = true
				if not pick[id] then
					pick[id] = item
					seenCount += 1
					firstSeen[id] = seenCount
					score[id] = 0
					if item.creator and favorite[item.creator] then
						score[id] += Recommendations.CREATOR_BONUS
					end
				end
				-- 1 for agreeing at all, up to 0.5 more for ranking high in that list.
				score[id] += 1 + 0.5 * (1 - (rank - 1) / math.max(n, 1))
			end
		end
	end
	local ids = {}
	for id in pick do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		if math.abs(score[a] - score[b]) > 1e-9 then
			return score[a] > score[b]
		end
		return firstSeen[a] < firstSeen[b]
	end)
	local out = {}
	for i = 1, math.min(limit, #ids) do
		out[i] = pick[ids[i]]
	end
	return out
end

-- Reads one entry of GetRecommendedAssetsAsync into the shape the catalog grid uses.
-- Returns nil for things we can't sell or try on (resale limiteds, missing ids).
function Recommendations.fromRoblox(entry: any): Pick?
	if type(entry) ~= "table" then
		return nil
	end
	local item = if type(entry.Item) == "table" then entry.Item else {}
	local product = if type(entry.Product) == "table" then entry.Product else {}
	local creator = if type(entry.Creator) == "table" then entry.Creator else {}
	local id = tonumber(item.AssetId or item.Id)
	if not id or id <= 0 then
		return nil
	end
	if product.IsLimited or product.IsLimitedUnique or product.IsResellable then
		return nil
	end
	local price = tonumber(product.PriceInRobux or item.Price)
	local forSale = product.IsForSale ~= false
	if product.IsFree then
		price = 0
	end
	return {
		Id = id,
		Name = if type(item.Name) == "string" then item.Name else "Item",
		Price = if forSale then price else nil,
		creator = if type(creator.Name) == "string" then creator.Name else nil,
		ItemType = "Asset",
	}
end

return Recommendations
