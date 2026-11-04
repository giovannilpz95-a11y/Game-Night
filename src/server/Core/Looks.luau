-- Dressing Room looks: building a look, layering it over a player's own avatar, and saved
-- look slots. Pure (no services) so it is unit tested; DressingRoomService does the Roblox side.
--
-- A look is { base = "mine" | "blank", items = { { id = assetId, t = assetTypeId } } }.
-- Saved looks add a `name`. Everything is JSON-safe for the DataStore.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DressingRoom = require(ReplicatedStorage.Shared.DressingRoom)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Profile = require(script.Parent.Profile)

local Looks = {}

export type Item = { id: number, t: number }
export type Look = { base: string, items: { Item }, name: string? }

-- One accessory on a finished avatar, ready to become a HumanoidDescription entry.
export type Worn = { id: number, accessory: string, layered: boolean, order: number, fromLook: boolean }
export type Outfit = { accessories: { Worn }, clothing: { [string]: number } }

local function isAssetId(value: any): boolean
	return type(value) == "number" and value > 0 and value % 1 == 0 and value < 2 ^ 53
end

function Looks.new(): Look
	return { base = "mine", items = {} }
end

-- A clean copy of one item, or nil if it isn't a type the Dressing Room handles.
function Looks.cleanItem(item: any): Item?
	if type(item) ~= "table" or not isAssetId(item.id) or type(item.t) ~= "number" then
		return nil
	end
	if not DressingRoom.Types[item.t] then
		return nil
	end
	return { id = item.id, t = item.t }
end

local function count(look: Look, predicate: (Item, DressingRoom.ItemType) -> boolean): number
	local n = 0
	for _, item in look.items do
		if predicate(item, DressingRoom.Types[item.t]) then
			n += 1
		end
	end
	return n
end

local function isRigid(_item: Item, info: DressingRoom.ItemType): boolean
	return info.accessory ~= nil and not info.layered
end

function Looks.isWearing(look: Look, assetId: number): boolean
	for _, item in look.items do
		if item.id == assetId then
			return true
		end
	end
	return false
end

-- Puts an item on. Clothes of the same kind (one shirt, one jacket...) replace each other;
-- a third hair replaces the oldest one. Returns false and a message if the look is full.
function Looks.add(look: Look, rawItem: any): (boolean, string?)
	local item = Looks.cleanItem(rawItem)
	if not item then
		return false, "That item can't be tried on here"
	end
	if Looks.isWearing(look, item.id) then
		return true
	end
	local info = DressingRoom.Types[item.t]
	local exclusive = info.clothing ~= nil or info.layered == true
	if exclusive then
		for i = #look.items, 1, -1 do
			if look.items[i].t == item.t then
				table.remove(look.items, i)
			end
		end
	elseif info.accessory == "Hair" and count(look, function(it)
		return it.t == item.t
	end) >= DressingRoom.MaxHair then
		for i, existing in look.items do
			if existing.t == item.t then
				table.remove(look.items, i)
				break
			end
		end
	elseif isRigid(item, info) and count(look, isRigid) >= DressingRoom.MaxRigidAccessories then
		return false, `You can wear {DressingRoom.MaxRigidAccessories} accessories at once. Take one off first.`
	end
	if #look.items >= DressingRoom.MaxItems then
		return false, "Your look is full. Take something off first."
	end
	table.insert(look.items, item)
	return true
end

function Looks.remove(look: Look, assetId: any): boolean
	for i, item in look.items do
		if item.id == assetId then
			table.remove(look.items, i)
			return true
		end
	end
	return false
end

-- A clean copy of any look (from the client or an old save): bad items are dropped and
-- the limits are applied again.
function Looks.sanitize(raw: any): Look
	local look = Looks.new()
	if type(raw) ~= "table" then
		return look
	end
	if type(raw.base) == "string" and DressingRoom.Bases[raw.base] then
		look.base = raw.base
	end
	if type(raw.items) == "table" then
		for i, item in raw.items do
			if type(i) == "number" and i <= DressingRoom.MaxItems * 2 then
				Looks.add(look, item)
			end
		end
	end
	if type(raw.name) == "string" then
		look.name = string.sub(raw.name, 1, 30)
	end
	return look
end

function Looks.copy(look: Look): Look
	local out = { base = look.base, items = table.create(#look.items), name = look.name }
	for i, item in look.items do
		out.items[i] = { id = item.id, t = item.t }
	end
	return out
end

-- Layers a look over the player's own avatar. `base` is what their avatar wears now:
-- accessories (with Roblox's AccessoryType names) and classic clothing IDs.
-- "blank" looks start from nothing; "mine" looks replace only what they need to:
-- a shirt replaces the shirt, layered clothes replace the same kind, hair replaces hair,
-- and if there are too many accessories the avatar's own go first.
function Looks.compose(base: { accessories: { any }, clothing: { [string]: number } }, look: Look): Outfit
	local accessories: { Worn } = {}
	local clothing: { [string]: number } = {}
	if look.base ~= "blank" then
		for _, acc in base.accessories do
			table.insert(accessories, {
				id = acc.id,
				accessory = acc.accessory,
				layered = acc.layered == true,
				order = acc.order or 0,
				fromLook = false,
			})
		end
		for key, id in base.clothing do
			clothing[key] = id
		end
	end

	local function dropBase(predicate: (Worn) -> boolean)
		for i = #accessories, 1, -1 do
			local worn = accessories[i]
			if not worn.fromLook and predicate(worn) then
				table.remove(accessories, i)
			end
		end
	end

	for _, item in look.items do
		local info = DressingRoom.Types[item.t]
		if not info then
			continue
		end
		if info.clothing then
			clothing[info.clothing] = item.id
			continue
		end
		local accessory = info.accessory :: string
		if info.layered or accessory == "Hair" then
			dropBase(function(worn)
				return worn.accessory == accessory
			end)
		end
		table.insert(accessories, {
			id = item.id,
			accessory = accessory,
			layered = info.layered == true,
			order = info.order or 0,
			fromLook = true,
		})
	end

	-- Too many rigid accessories: take the avatar's own off first, oldest first.
	local rigid = 0
	for _, worn in accessories do
		if not worn.layered then
			rigid += 1
		end
	end
	local i = 1
	while rigid > DressingRoom.MaxRigidAccessories and i <= #accessories do
		local worn = accessories[i]
		if not worn.layered and not worn.fromLook then
			table.remove(accessories, i)
			rigid -= 1
		else
			i += 1
		end
	end

	return { accessories = accessories, clothing = clothing }
end

-- Saved look slots ------------------------------------------------------------------

function Looks.slotCount(data: Profile.Data, vip: boolean): number
	local free = if vip then Economy.VipLookSlots else Economy.FreeLookSlots
	return math.min(Economy.MaxLookSlots, free + data.lookSlots)
end

function Looks.slotPrice(vip: boolean): number
	local gems = Economy.LookSlotGems
	if vip then
		gems = math.ceil(gems * (1 - Economy.VipGemDiscount))
	end
	return gems
end

-- Buys one more saved look slot with Gems.
function Looks.buySlot(data: Profile.Data, vip: boolean): (boolean, string?)
	if Looks.slotCount(data, vip) >= Economy.MaxLookSlots then
		return false, "You have the most look slots already"
	end
	local price = Looks.slotPrice(vip)
	if data.gems < price then
		return false, "Not enough Gems"
	end
	Profile.addGems(data, -price)
	data.lookSlots += 1
	return true
end

local function isSlot(slot: any): boolean
	return type(slot) == "number" and slot >= 1 and slot % 1 == 0
end

-- Saves a look into a slot: an existing one (overwrite) or the next free one.
function Looks.save(data: Profile.Data, slot: any, look: Look, vip: boolean): (boolean, string?)
	if #look.items == 0 and look.base == "mine" then
		return false, "Try something on first"
	end
	if not isSlot(slot) or slot > #data.looks + 1 then
		return false, "Pick a look slot"
	end
	if slot > #data.looks and slot > Looks.slotCount(data, vip) then
		return false, "All your look slots are full. Get another slot or overwrite a look."
	end
	local saved = Looks.copy(look)
	saved.name = `Look {slot}`
	data.looks[slot] = saved
	return true
end

function Looks.get(data: Profile.Data, slot: any): Look?
	if not isSlot(slot) or not data.looks[slot] then
		return nil
	end
	return Looks.sanitize(data.looks[slot])
end

function Looks.delete(data: Profile.Data, slot: any): boolean
	if not isSlot(slot) or not data.looks[slot] then
		return false
	end
	table.remove(data.looks, slot)
	for i, look in data.looks do
		look.name = `Look {i}`
	end
	return true
end

return Looks
