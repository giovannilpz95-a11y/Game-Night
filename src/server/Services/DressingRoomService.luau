-- The Dressing Room: players try on Roblox catalog items, wear the look everywhere in
-- Game Night, save looks, and buy items with Robux. Game Night earns commission on every
-- catalog sale made here. Design: vault "03 Design/Avatar Designer.md", tech: docs/Dressing Room.md.
--
-- The client searches the catalog itself (AvatarEditorService) and only sends asset IDs.
-- The server looks every ID up with GetProductInfo, so a client can't put on anything that
-- isn't a real, wearable catalog item, and it builds and applies the HumanoidDescription.
--
-- Rules we never break: catalog items are bought with Robux only (never Gems or Coins),
-- and a look only changes how you appear inside Game Night until you buy the items.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local DressingRoom = require(ReplicatedStorage.Shared.DressingRoom)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Net = require(ReplicatedStorage.Shared.Net)
local Looks = require(script.Parent.Parent.Core.Looks)
local RateLimiter = require(script.Parent.Parent.Core.RateLimiter)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local TrendingService = require(script.Parent.TrendingService)
local Trending = require(ReplicatedStorage.Shared.Trending)

local DressingRoomService = {}

export type AssetInfo = {
	id: number,
	t: number,
	name: string,
	creator: string,
	price: number?, -- Robux, nil when it can't be bought
	forSale: boolean,
}

local stateRemote: RemoteEvent
local trendingRemote: RemoteEvent
local notifyRemote: RemoteEvent

local assetCache: { [number]: AssetInfo | false } = {} -- false = looked up, not wearable
local owned: { [number]: { [number]: boolean } } = {} -- owned[userId][assetId]
local bases: { [number]: { description: HumanoidDescription, parts: any } } = {}
local applying: { [Player]: boolean } = {}
local dirty: { [Player]: boolean } = {}
local changed: { [Player]: boolean } = {} -- we've dressed them at least once this session

-- GetProductInfo has a server-wide budget, so each player gets a small share of it.
local lookupLimiter = RateLimiter.new(12, 10)
local trendingLimiter = RateLimiter.new(4, 10)

local accessoryEnums: { [string]: Enum.AccessoryType } = {}
for _, item in Enum.AccessoryType:GetEnumItems() do
	accessoryEnums[item.Name] = item
end

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

local function isVip(player: Player): boolean
	return EconomyService.hasPass(player, "vip")
end

-- Asset lookups ---------------------------------------------------------------------

local function assetInfo(assetId: number): AssetInfo?
	local cached = assetCache[assetId]
	if cached ~= nil then
		return cached or nil
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(assetId, Enum.InfoType.Asset)
	end)
	if not ok or type(info) ~= "table" then
		return nil -- not cached: Roblox may just be busy
	end
	local typeId = info.AssetTypeId
	if not DressingRoom.Types[typeId] then
		assetCache[assetId] = false
		return nil
	end
	-- Resale limiteds can't be bought with PromptPurchase, so they're try-on only.
	local resale = info.IsLimited == true or info.IsLimitedUnique == true
	local price = info.PriceInRobux
	local forSale = info.IsForSale == true and not resale and type(price) == "number"
	local result: AssetInfo = {
		id = assetId,
		t = typeId,
		name = tostring(info.Name or "Item"),
		creator = if type(info.Creator) == "table" then tostring(info.Creator.Name or "") else "",
		price = if forSale then price else nil,
		forSale = forSale,
	}
	assetCache[assetId] = result
	return result
end

local function ownsAsset(player: Player, assetId: number): boolean
	local mine = owned[player.UserId]
	if not mine then
		mine = {}
		owned[player.UserId] = mine
	end
	if mine[assetId] ~= nil then
		return mine[assetId]
	end
	local ok, result = pcall(function()
		return MarketplaceService:PlayerOwnsAsset(player, assetId)
	end)
	if not ok then
		return false -- ask again next time
	end
	mine[assetId] = result == true
	return mine[assetId]
end

local function readAssetId(value: any): number?
	if type(value) == "number" and value > 0 and value % 1 == 0 and value < 2 ^ 53 then
		return value
	end
	return nil
end

-- Avatars -----------------------------------------------------------------------------

-- The player's own Roblox avatar: the starting point every look is layered on.
local function getBase(player: Player)
	local cached = bases[player.UserId]
	if cached then
		return cached
	end
	local ok, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(math.max(1, player.UserId))
	end)
	if not ok or not description then
		return nil
	end
	local accessories = {}
	for _, acc in description:GetAccessories(true) do
		table.insert(accessories, {
			id = acc.AssetId,
			accessory = acc.AccessoryType.Name,
			layered = acc.IsLayered == true,
			order = acc.Order or 0,
		})
	end
	local clothing = {}
	for _, key in { "Shirt", "Pants", "GraphicTShirt" } do
		local id = (description :: any)[key]
		if id and id ~= 0 then
			clothing[key] = id
		end
	end
	local base = { description = description, parts = { accessories = accessories, clothing = clothing } }
	bases[player.UserId] = base
	return base
end

local function buildDescription(player: Player, look: Looks.Look?): HumanoidDescription?
	local base = getBase(player)
	if not base then
		return nil
	end
	local description = base.description:Clone()
	if not look then
		return description
	end
	local outfit = Looks.compose(base.parts, look)
	local list = {}
	for _, worn in outfit.accessories do
		local enum = accessoryEnums[worn.accessory]
		if enum then
			table.insert(list, {
				AssetId = worn.id,
				AccessoryType = enum,
				IsLayered = worn.layered,
				Order = if worn.layered then worn.order else nil,
			})
		end
	end
	description:SetAccessories(list, true)
	description.Shirt = outfit.clothing.Shirt or 0
	description.Pants = outfit.clothing.Pants or 0
	description.GraphicTShirt = outfit.clothing.GraphicTShirt or 0
	return description
end

local function currentLook(player: Player): Looks.Look?
	local data = DataService.get(player)
	if not data or data.currentLook == nil then
		return nil
	end
	return Looks.sanitize(data.currentLook)
end

local function applyNow(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or not character:IsDescendantOf(workspace) then
		return
	end
	local look = currentLook(player)
	if not look and not changed[player] then
		return -- still wearing their own avatar
	end
	local description = buildDescription(player, look)
	if not description then
		return notify(player, "Couldn't load your avatar right now. Try again in a moment.")
	end
	local ok, err = pcall(function()
		humanoid:ApplyDescription(description)
	end)
	if ok then
		changed[player] = look ~= nil
	else
		warn(`[GameNight] ApplyDescription failed for {player.Name}: {err}`)
		notify(player, "Something in that look couldn't be worn. Try taking the last item off.")
	end
end

-- Dresses the player's character. Many quick changes collapse into one ApplyDescription.
local function requestApply(player: Player)
	dirty[player] = true
	if applying[player] then
		return
	end
	applying[player] = true
	task.spawn(function()
		while dirty[player] and player.Parent do
			dirty[player] = false
			applyNow(player)
			task.wait(0.25)
		end
		applying[player] = nil
	end)
end

-- State for the client ----------------------------------------------------------------

local function describeItems(player: Player, look: Looks.Look)
	local items = {}
	local unownedTotal, unownedCount, allOwned = 0, 0, true
	for _, item in look.items do
		local info = assetCache[item.id] or nil
		local mine = ownsAsset(player, item.id)
		local typeInfo = DressingRoom.Types[item.t]
		local entry = {
			id = item.id,
			t = item.t,
			kind = if typeInfo then typeInfo.name else "Item",
			name = if info then info.name else "Item",
			creator = if info then info.creator else "",
			price = if info then info.price else nil,
			forSale = info ~= nil and info.forSale,
			owned = mine,
		}
		if not mine then
			allOwned = false
			if entry.forSale then
				unownedTotal += entry.price or 0
				unownedCount += 1
			end
		end
		table.insert(items, entry)
	end
	return items, unownedTotal, unownedCount, allOwned
end

function DressingRoomService.push(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local look = currentLook(player) or Looks.new()
	for _, item in look.items do
		assetInfo(item.id) -- warms the cache after a rejoin; cached lookups are free
	end
	local items, total, count, allOwned = describeItems(player, look)
	local saved = {}
	for i, savedLook in data.looks do
		local clean = Looks.sanitize(savedLook)
		local preview = {}
		for j = 1, math.min(4, #clean.items) do
			preview[j] = clean.items[j].id
		end
		saved[i] = { name = clean.name or `Look {i}`, count = #clean.items, base = clean.base, preview = preview }
	end
	local vip = isVip(player)
	stateRemote:FireClient(player, {
		look = { base = look.base, items = items },
		wearing = data.currentLook ~= nil,
		unownedRobux = total,
		unownedCount = count,
		allOwned = allOwned and #items > 0,
		saved = saved,
		slots = Looks.slotCount(data, vip),
		maxSlots = Economy.MaxLookSlots,
		slotPrice = Looks.slotPrice(vip),
		gems = data.gems,
	})
end

-- Client requests ---------------------------------------------------------------------

local handlers = {}

local function editLook(player: Player, edit: (Looks.Look) -> (boolean, string?))
	local data = DataService.get(player)
	if not data then
		return
	end
	local look = currentLook(player) or Looks.new()
	local ok, err = edit(look)
	if not ok then
		if err then
			notify(player, err)
		end
		return
	end
	look.name = nil
	data.currentLook = if #look.items == 0 and look.base == "mine" then nil else look
	requestApply(player)
	DressingRoomService.push(player)
end

function handlers.sync(player: Player, _request: any)
	DressingRoomService.push(player)
end

function handlers.tryOn(player: Player, request: any)
	local assetId = readAssetId(request.assetId)
	if not assetId then
		return
	end
	if assetCache[assetId] == nil and not lookupLimiter:allow(player.UserId) then
		return notify(player, "Slow down a little, the catalog is catching up")
	end
	local info = assetInfo(assetId)
	if not info then
		return notify(player, "That item can't be tried on here")
	end
	if DressingRoom.Types[info.t].tryOnly then
		return notify(player, "That kind of item comes to the Dressing Room soon")
	end
	editLook(player, function(look)
		local ok, err = Looks.add(look, { id = info.id, t = info.t })
		if ok then
			TrendingService.record(player, info.id, info.t, "tryOn", info.name)
		end
		return ok, err
	end)
end

function handlers.takeOff(player: Player, request: any)
	editLook(player, function(look)
		return Looks.remove(look, request.assetId)
	end)
end

function handlers.setBase(player: Player, request: any)
	if type(request.base) ~= "string" or not DressingRoom.Bases[request.base] then
		return
	end
	editLook(player, function(look)
		look.base = request.base
		return true
	end)
end

-- The Trending tab: what Game Night players wear the most (shared/Trending).
function handlers.trending(player: Player, _request: any)
	if not trendingLimiter:allow(player.UserId) then
		return
	end
	trendingRemote:FireClient(player, { items = Trending.toClient(TrendingService.list()) })
end

function handlers.reset(player: Player, _request: any)
	local data = DataService.get(player)
	if not data then
		return
	end
	data.currentLook = nil
	requestApply(player)
	DressingRoomService.push(player)
end

function handlers.save(player: Player, request: any)
	local data = DataService.get(player)
	if not data then
		return
	end
	local slot = request.slot
	if slot == "new" then
		slot = #data.looks + 1
	end
	local ok, err = Looks.save(data, slot, currentLook(player) or Looks.new(), isVip(player))
	if not ok then
		return notify(player, err :: string)
	end
	notify(player, `Saved as Look {slot}`)
	DressingRoomService.push(player)
end

function handlers.load(player: Player, request: any)
	local data = DataService.get(player)
	local look = data and Looks.get(data, request.slot)
	if not data or not look then
		return
	end
	look.name = nil
	data.currentLook = look
	requestApply(player)
	DressingRoomService.push(player)
end

function handlers.delete(player: Player, request: any)
	local data = DataService.get(player)
	if data and Looks.delete(data, request.slot) then
		DressingRoomService.push(player)
	end
end

function handlers.buySlot(player: Player, _request: any)
	local data = DataService.get(player)
	if not data then
		return
	end
	local ok, err = Looks.buySlot(data, isVip(player))
	if not ok then
		return notify(player, err :: string)
	end
	notify(player, "New look slot unlocked")
	EconomyService.push(player)
	DressingRoomService.push(player)
end

-- Robux: one catalog item.
function handlers.buy(player: Player, request: any)
	local assetId = readAssetId(request.assetId)
	if not assetId then
		return
	end
	if assetCache[assetId] == nil and not lookupLimiter:allow(player.UserId) then
		return
	end
	local info = assetInfo(assetId)
	if not info or not info.forSale then
		return notify(player, "That item isn't for sale right now")
	end
	if ownsAsset(player, assetId) then
		return notify(player, "You already own that one")
	end
	MarketplaceService:PromptPurchase(player, assetId)
end

-- Robux: every item in the current look the player doesn't own yet, in one prompt.
function handlers.buyAll(player: Player, _request: any)
	local look = currentLook(player)
	if not look then
		return
	end
	local toBuy = {}
	for _, item in look.items do
		local info = assetInfo(item.id)
		if info and info.forSale and not ownsAsset(player, item.id) then
			table.insert(toBuy, item.id)
		end
	end
	if #toBuy == 0 then
		return notify(player, "You already own everything for sale in this look")
	end
	if #toBuy == 1 then
		return MarketplaceService:PromptPurchase(player, toBuy[1])
	end
	local lineItems = {}
	for i = 1, math.min(#toBuy, DressingRoom.MaxBulkItems) do
		table.insert(lineItems, { Type = Enum.MarketplaceProductType.AvatarAsset, Id = tostring(toBuy[i]) })
	end
	local ok = pcall(function()
		(MarketplaceService :: any):PromptBulkPurchase(player, lineItems, {})
	end)
	if not ok then
		-- Bulk purchase not available: fall back to one item at a time.
		notify(player, "Buying one item at a time")
		MarketplaceService:PromptPurchase(player, toBuy[1])
	end
end

function DressingRoomService.handleRequest(player: Player, request: any)
	if type(request) ~= "table" or type(request.action) ~= "string" then
		return
	end
	local handler = handlers[request.action]
	if handler then
		handler(player, request)
	end
end

-- Purchases ---------------------------------------------------------------------------

local function recordPurchase(player: Player, assetId: number)
	local mine = owned[player.UserId] or {}
	owned[player.UserId] = mine
	mine[assetId] = true
	local data = DataService.get(player)
	local info = assetCache[assetId]
	if data and info then
		data.catalog.purchases += 1
		data.catalog.robux += info.price or 0
	end
	if info then
		TrendingService.record(player, assetId, info.t, "buy", info.name)
	end
end

local function onPurchaseFinished(player: Player, assetId: number, purchased: boolean)
	if not purchased or not assetCache[assetId] then
		return -- not something the Dressing Room prompted
	end
	recordPurchase(player, assetId)
	local info = assetCache[assetId] :: AssetInfo
	notify(player, `{info.name} is yours! It's in your Roblox inventory now.`)
	DressingRoomService.push(player)
end

-- After a bulk purchase we don't trust the result shape; we just ask Roblox again about
-- every item in the look that wasn't owned before.
local function onBulkPurchaseFinished(player: Player, _status: any, _results: any)
	local look = currentLook(player)
	local mine = owned[player.UserId]
	if not look or not mine then
		return
	end
	local bought = 0
	for _, item in look.items do
		if mine[item.id] == false then
			mine[item.id] = nil
			if ownsAsset(player, item.id) then
				recordPurchase(player, item.id)
				bought += 1
			end
		end
	end
	if bought > 0 then
		notify(player, `{bought} items are yours! They're in your Roblox inventory now.`)
	end
	DressingRoomService.push(player)
end

-- What a player has on when they join (their own avatar and their Game Night look) counts
-- toward Trending, so the tab has something to show from the first day.
local CLOTHING_TYPES = { Shirt = 11, Pants = 12, GraphicTShirt = 2 }
local function countWorn(player: Player)
	local base = getBase(player)
	if not base or not player.Parent then
		return
	end
	for _, acc in base.parts.accessories do
		local t = DressingRoom.TypeByAccessory[acc.accessory]
		if t then
			TrendingService.record(player, acc.id, t, "avatar")
		end
	end
	for key, id in base.parts.clothing do
		local t = CLOTHING_TYPES[key]
		if t then
			TrendingService.record(player, id, t, "avatar")
		end
	end
	local look = currentLook(player)
	if look then
		for _, item in look.items do
			TrendingService.record(player, item.id, item.t, "avatar")
		end
	end
end

function DressingRoomService.init()
	stateRemote = Net.event(Net.Names.DressingRoomState)
	trendingRemote = Net.event(Net.Names.DressingRoomTrending)
	TrendingService.init()
	notifyRemote = Net.event(Net.Names.Notify)

	MarketplaceService.PromptPurchaseFinished:Connect(onPurchaseFinished)
	pcall(function()
		(MarketplaceService :: any).PromptBulkPurchaseFinished:Connect(onBulkPurchaseFinished)
	end)

	-- Looks are worn everywhere in Game Night, so dress the character every time it spawns.
	local function watch(player: Player)
		player.CharacterAppearanceLoaded:Connect(function()
			changed[player] = nil -- a fresh character wears the player's own avatar
			if DataService.get(player) and currentLook(player) then
				requestApply(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	DataService.onLoaded(function(player)
		if currentLook(player) and player:HasAppearanceLoaded() then
			requestApply(player)
		end
		DressingRoomService.push(player)
		task.spawn(countWorn, player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		owned[player.UserId] = nil
		bases[player.UserId] = nil
		applying[player] = nil
		dirty[player] = nil
		changed[player] = nil
	end)
end

return DressingRoomService
