-- Prices, buying and equipping shop items. Pure so it is unit tested.
-- Coins can only be spent in their own shop. Gems can pay for any item that has a Gem price.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Economy = require(ReplicatedStorage.Shared.Economy)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local Profile = require(script.Parent.Profile)

local Shop = {}

-- Coin price, or nil if the item can't be bought with Coins.
function Shop.coinPrice(item: ShopCatalog.Item): number?
	if item.notForSale or item.shop == "hub" then
		return nil
	end
	return item.coins
end

-- Gem price after the VIP discount, or nil if the item can't be bought with Gems.
function Shop.gemPrice(item: ShopCatalog.Item, vip: boolean): number?
	if item.notForSale or item.earnedOnly then
		return nil
	end
	local gems = item.gems
	if gems == nil and item.coins then
		gems = math.ceil(item.coins / Economy.CoinsPerGem)
	end
	if gems == nil then
		return nil
	end
	if vip then
		gems = math.ceil(gems * (1 - Economy.VipGemDiscount))
	end
	return gems
end

function Shop.buy(data: Profile.Data, itemId: any, currency: any, vip: boolean): (boolean, string?)
	local item = if type(itemId) == "string" then ShopCatalog.get(itemId) else nil
	if not item then
		return false, "That item isn't in the shop"
	end
	if data.owned[item.id] then
		return false, "You already own that"
	end
	if currency == "coins" then
		local price = Shop.coinPrice(item)
		if not price then
			return false, "That item can't be bought with Coins"
		end
		if Profile.coins(data, item.shop) < price then
			return false, `Not enough {Economy.coinName(item.shop)}`
		end
		Profile.addCoins(data, item.shop, -price)
	elseif currency == "gems" then
		local price = Shop.gemPrice(item, vip)
		if not price then
			return false, "That item can't be bought with Gems"
		end
		if data.gems < price then
			return false, "Not enough Gems"
		end
		Profile.addGems(data, -price)
	else
		return false, "Pick Coins or Gems"
	end
	data.owned[item.id] = true
	return true
end

-- Equips an owned item in its slot, or unequips it if it is already equipped.
function Shop.toggleEquip(data: Profile.Data, itemId: any): (boolean, string?)
	local item = if type(itemId) == "string" then ShopCatalog.get(itemId) else nil
	if not item then
		return false, "That item isn't in the shop"
	end
	if not data.owned[item.id] then
		return false, "You don't own that yet"
	end
	if item.slot == "reactions" then
		return false, "Reaction packs are always on your reaction wheel"
	end
	local slots = data.equipped[item.shop] or {}
	data.equipped[item.shop] = slots
	if slots[item.slot] == item.id then
		slots[item.slot] = nil
	else
		slots[item.slot] = item.id
	end
	return true
end

-- How many of `itemIds` the player doesn't own yet.
function Shop.missing(data: Profile.Data, itemIds: { string }): number
	local count = 0
	for _, id in itemIds do
		if not data.owned[id] then
			count += 1
		end
	end
	return count
end

-- Gives items without charging (Starter Pack, reaction bundle, rank rewards). Returns
-- how many were new.
function Shop.grant(data: Profile.Data, itemIds: { string }): number
	local added = 0
	for _, id in itemIds do
		if ShopCatalog.get(id) and not data.owned[id] then
			data.owned[id] = true
			added += 1
		end
	end
	return added
end

return Shop
