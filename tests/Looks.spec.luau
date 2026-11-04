local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DressingRoom = require(ReplicatedStorage.Shared.DressingRoom)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Core = ServerScriptService.Server.Core
local Looks = require(Core.Looks)
local Profile = require(Core.Profile)

local HAT, HAIR, FACE, JACKET, SHIRT_3D, CLASSIC_SHIRT, CLASSIC_PANTS = 8, 41, 42, 67, 65, 11, 12

return function(T)
	local function findWorn(outfit, id)
		for _, worn in outfit.accessories do
			if worn.id == id then
				return worn
			end
		end
		return nil
	end

	T.test("every category only lists known, sellable types", function()
		for _, category in DressingRoom.Categories do
			for _, typeId in category.types do
				local info = DressingRoom.Types[typeId]
				T.ok(info ~= nil, `{category.key} lists unknown type {typeId}`)
				T.ok(not info.tryOnly, `{category.key} lists try-only type {typeId}`)
			end
		end
	end)

	T.test("adding items and taking them off", function()
		local look = Looks.new()
		T.ok(Looks.add(look, { id = 100, t = HAT }))
		T.ok(Looks.add(look, { id = 100, t = HAT }), "adding twice is fine")
		T.eq(#look.items, 1)
		T.ok(Looks.isWearing(look, 100))
		T.ok(Looks.remove(look, 100))
		T.eq(#look.items, 0)
		T.eq(Looks.remove(look, 100), false)
	end)

	T.test("rejects bad items from the client", function()
		local look = Looks.new()
		T.eq((Looks.add(look, { id = 5, t = 999 })), false, "unknown type")
		T.eq((Looks.add(look, { id = -1, t = HAT })), false, "negative id")
		T.eq((Looks.add(look, { id = 1.5, t = HAT })), false, "fractional id")
		T.eq((Looks.add(look, "hat")), false, "not a table")
		T.eq(#look.items, 0)
	end)

	T.test("clothes of the same kind replace each other", function()
		local look = Looks.new()
		Looks.add(look, { id = 1, t = JACKET })
		Looks.add(look, { id = 2, t = JACKET })
		Looks.add(look, { id = 3, t = CLASSIC_SHIRT })
		Looks.add(look, { id = 4, t = CLASSIC_SHIRT })
		T.eq(#look.items, 2)
		T.ok(Looks.isWearing(look, 2) and Looks.isWearing(look, 4))
	end)

	T.test("a third hair replaces the oldest", function()
		local look = Looks.new()
		Looks.add(look, { id = 1, t = HAIR })
		Looks.add(look, { id = 2, t = HAIR })
		Looks.add(look, { id = 3, t = HAIR })
		T.eq(#look.items, 2)
		T.eq(Looks.isWearing(look, 1), false)
	end)

	T.test("accessory limit", function()
		local look = Looks.new()
		for i = 1, DressingRoom.MaxRigidAccessories do
			T.ok(Looks.add(look, { id = i, t = HAT }))
		end
		local ok, err = Looks.add(look, { id = 999, t = FACE })
		T.eq(ok, false)
		T.ok(err ~= nil)
		T.ok(Looks.add(look, { id = 1000, t = JACKET }), "layered clothes don't count")
	end)

	T.test("sanitize drops junk and keeps the limits", function()
		local items = {}
		for i = 1, 40 do
			table.insert(items, { id = i, t = HAT })
		end
		table.insert(items, { id = "x", t = HAT })
		local look = Looks.sanitize({ base = "weird", items = items, name = string.rep("a", 99) })
		T.eq(look.base, "mine")
		T.eq(#look.items, DressingRoom.MaxRigidAccessories)
		T.eq(#(look.name :: string), 30)
		T.eq(#Looks.sanitize(nil).items, 0)
	end)

	T.test("compose layers a look over the player's avatar", function()
		local base = {
			accessories = {
				{ id = 10, accessory = "Hair", layered = false, order = 0 },
				{ id = 11, accessory = "Hat", layered = false, order = 0 },
				{ id = 12, accessory = "Shirt", layered = true, order = 5 },
				{ id = 13, accessory = "Eyebrow", layered = false, order = 0 }, -- a type we don't sell is kept
			},
			clothing = { Shirt = 20, Pants = 21 },
		}
		local look = Looks.new()
		Looks.add(look, { id = 30, t = HAIR })
		Looks.add(look, { id = 31, t = SHIRT_3D })
		Looks.add(look, { id = 32, t = CLASSIC_PANTS })
		local outfit = Looks.compose(base, look)
		T.eq(findWorn(outfit, 10), nil, "own hair replaced")
		T.ok(findWorn(outfit, 11) ~= nil, "own hat kept")
		T.eq(findWorn(outfit, 12), nil, "own layered shirt replaced")
		T.ok(findWorn(outfit, 13) ~= nil)
		T.ok(findWorn(outfit, 30).fromLook)
		T.eq(findWorn(outfit, 31).order, DressingRoom.Types[SHIRT_3D].order)
		T.eq(outfit.clothing.Shirt, 20)
		T.eq(outfit.clothing.Pants, 32)
	end)

	T.test("blank looks drop the avatar's own clothes", function()
		local base = { accessories = { { id = 10, accessory = "Hat", layered = false } }, clothing = { Shirt = 20 } }
		local look = Looks.new()
		look.base = "blank"
		Looks.add(look, { id = 30, t = HAT })
		local outfit = Looks.compose(base, look)
		T.eq(#outfit.accessories, 1)
		T.eq(outfit.clothing.Shirt, nil)
	end)

	T.test("too many accessories: the avatar's own go first", function()
		local base = { accessories = {}, clothing = {} }
		for i = 1, 6 do
			table.insert(base.accessories, { id = i, accessory = "Hat", layered = false })
		end
		local look = Looks.new()
		for i = 1, 6 do
			Looks.add(look, { id = 100 + i, t = FACE })
		end
		local outfit = Looks.compose(base, look)
		T.eq(#outfit.accessories, DressingRoom.MaxRigidAccessories)
		for i = 1, 6 do
			T.ok(findWorn(outfit, 100 + i) ~= nil, "look items stay")
		end
		T.eq(findWorn(outfit, 1), nil, "oldest own accessory removed")
		T.ok(findWorn(outfit, 6) ~= nil)
	end)

	T.test("saving, loading and deleting looks", function()
		local data = Profile.new(0)
		local look = Looks.new()
		T.eq((Looks.save(data, 1, look, false)), false, "empty look")
		Looks.add(look, { id = 1, t = HAT })
		T.ok(Looks.save(data, 1, look, false))
		T.eq((Looks.save(data, 3, look, false)), false, "can't skip a slot")
		T.ok(Looks.save(data, 2, look, false))
		T.ok(Looks.save(data, 3, look, false))
		T.eq((Looks.save(data, 4, look, false)), false, "free slots full")
		T.ok(Looks.save(data, 4, look, true), "VIP has more")
		T.ok(Looks.save(data, 1, look, false), "overwriting is always fine")
		Looks.add(look, { id = 2, t = HAT })
		T.eq(#Looks.get(data, 2).items, 1, "saved looks are copies")
		T.ok(Looks.delete(data, 1))
		T.eq(#data.looks, 3)
		T.eq(data.looks[1].name, "Look 1")
		T.eq(Looks.get(data, 9), nil)
		T.eq(Looks.delete(data, "1"), false)
	end)

	T.test("buying look slots with Gems", function()
		local data = Profile.new(0)
		T.eq((Looks.buySlot(data, false)), false, "no Gems")
		data.gems = 1000
		T.ok(Looks.buySlot(data, false))
		T.eq(data.gems, 1000 - Economy.LookSlotGems)
		T.eq(Looks.slotCount(data, false), Economy.FreeLookSlots + 1)
		T.ok(Looks.slotPrice(true) < Looks.slotPrice(false), "VIP discount")
		data.lookSlots = Economy.MaxLookSlots
		data.gems = 1000
		T.eq((Looks.buySlot(data, true)), false, "capped")
		T.eq(data.gems, 1000)
	end)

	T.test("old saves get the catalog stats", function()
		local data = Profile.reconcile({ gems = 3 }, 0)
		T.eq(data.catalog.purchases, 0)
		T.eq(data.catalog.robux, 0)
	end)
end
