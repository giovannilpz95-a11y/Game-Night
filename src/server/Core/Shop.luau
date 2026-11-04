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

-- Turns Universal Coins into one game's Coins, 1:1. One way: game Coins never turn back.
-- amount must be a whole number the player has.
Shop.MaxConvert = 1000000
function Shop.convertUniversal(data: Profile.Data, toKey: any, amount: any): (boolean, string?)
	if type(toKey) ~= "string" or not Economy.Coins[toKey] then
		return false, "Pick a game's Coins"
	end
	if type(amount) ~= "number" or amount ~= amount or amount < 1 or amount > Shop.MaxConvert or amount ~= math.floor(amount) then
		return false, "Pick an amount"
	end
	local key = Economy.UniversalCoin.key
	if Profile.coins(data, key) < amount then
		return false, `Not enough {Economy.UniversalCoin.name}`
	end
	Profile.addCoins(data, key, -amount)
	Profile.addCoins(data, toKey, amount)
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
	local slots = data.equipped[item.shop] or {}
	data.equipped[item.shop] = slots
	if slots[item.slot] == item.id then
		slots[item.slot] = nil
	else
		slots[item.slot] = item.id
	end
	return true
end

-- Gives items without charging (Starter Pack, rank rewards).
function Shop.grant(data: Profile.Data, itemIds: { string })
	for _, id in itemIds do
		if ShopCatalog.get(id) then
			data.owned[id] = true
		end
	end
end

return Shop
