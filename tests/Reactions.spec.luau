local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Reactions = require(ReplicatedStorage.Shared.Reactions)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Core = ServerScriptService.Server.Core
local Profile = require(Core.Profile)
local Shop = require(Core.Shop)

return function(T)
	T.test("the three free reactions are the mad, laughing-crying and sad faces", function()
		T.eq(#Reactions.free, 3)
		T.eq(Reactions.get("mad").icon, "😡")
		T.eq(Reactions.get("mad").style, "steam")
		T.eq(Reactions.get("laughCry").icon, "😂")
		T.eq(Reactions.get("sad").style, "tear")
		for _, id in Reactions.free do
			T.ok(Reactions.canUse(id, nil), `{id} is free`)
		end
	end)

	T.test("every reaction has a known animation and something to show", function()
		for _, reaction in Reactions.list do
			T.ok(Reactions.Styles[reaction.style], `{reaction.id} has unknown style {reaction.style}`)
			if reaction.style == "text" then
				T.ok(type(reaction.text) == "string" and #reaction.text > 0, `{reaction.id} needs text`)
				T.ok(#reaction.text <= 14, `{reaction.id} is too long for the bubble`)
			else
				T.ok(type(reaction.icon) == "string", `{reaction.id} needs an icon`)
			end
			T.ok(#reaction.label > 0, `{reaction.id} needs a label`)
		end
	end)

	T.test("packs are shop items in the reactions slot and fill one wheel page", function()
		local seen = {}
		for _, pack in Reactions.packs do
			local item = ShopCatalog.get(pack.id)
			T.ok(item, `{pack.id} isn't in ShopCatalog`)
			T.eq(item.slot, "reactions")
			T.ok(not item.notForSale, `{pack.id} must be buyable`)
			T.ok(item.gems ~= nil or item.coins ~= nil, `{pack.id} needs a price`)
			T.ok(#pack.reactions >= 1 and #pack.reactions <= Reactions.PerPage, `{pack.id} has {#pack.reactions} reactions`)
			seen[pack.id] = true
		end
		for _, item in ShopCatalog.items do
			if item.slot == "reactions" then
				T.ok(seen[item.id], `{item.id} is in the shop but not in shared/Reactions`)
			end
		end
	end)

	T.test("pack reactions need the pack; bad ids never pass", function()
		T.eq(Reactions.canUse("party", nil), false)
		T.eq(Reactions.canUse("party", {}), false)
		T.eq(Reactions.canUse("party", { reactions_party = true }), true)
		T.eq(Reactions.canUse("party", { reactions_drama = true }), false)
		T.eq(Reactions.canUse("nope", { reactions_party = true }), false)
		T.eq(Reactions.canUse(42, nil), false)
		T.eq(Reactions.canUse(nil, nil), false)
	end)

	T.test("the wheel shows the free page first, then owned packs in shop order", function()
		local pages = Reactions.pages(nil)
		T.eq(#pages, 1)
		T.eq(pages[1].id, "free")
		T.eq(#pages[1].reactions, 3)
		pages = Reactions.pages({ reactions_talk = true, reactions_party = true, hub_comfy_chair = true })
		T.eq(#pages, 3)
		T.eq(pages[2].id, "reactions_party")
		T.eq(pages[3].id, "reactions_talk")
		T.eq(Reactions.missingPacks(nil), #Reactions.packs)
		T.eq(Reactions.missingPacks({ reactions_talk = true }), #Reactions.packs - 1)
	end)

	T.test("packs buy with Gems (or Card Coins for Card Sharp) and can't be equipped", function()
		local data = Profile.new(0)
		data.gems = 1000
		T.ok(Shop.buy(data, "reactions_party", "gems", false))
		T.eq(data.gems, 1000 - 150)
		T.ok(data.owned.reactions_party)
		T.eq((Shop.buy(data, "reactions_party", "gems", false)), false, "already owned")
		T.eq((Shop.toggleEquip(data, "reactions_party")), false, "nothing to equip")
		T.eq((Shop.buy(data, "reactions_drama", "coins", false)), false, "hub packs aren't sold for Coins")

		data.coins.cards = 1500
		T.ok(Shop.buy(data, "reactions_cards", "coins", false))
		T.eq(data.coins.cards, 0)
		T.ok(Reactions.canUse("snap", data.owned))
	end)

	T.test("the Robux bundle has every Gem pack and grants only what's missing", function()
		local hubPacks = {}
		for _, pack in Reactions.packs do
			if ShopCatalog.get(pack.id).shop == "hub" then
				hubPacks[pack.id] = true
			end
		end
		local count = 0
		for _, id in Economy.ReactionBundle.items do
			T.ok(hubPacks[id], `{id} in the bundle isn't a Gem pack`)
			count += 1
		end
		local total = 0
		for _ in hubPacks do
			total += 1
		end
		T.eq(count, total)

		local data = Profile.new(0)
		data.owned.reactions_party = true
		T.eq(Shop.missing(data, Economy.ReactionBundle.items), total - 1)
		T.eq(Shop.grant(data, Economy.ReactionBundle.items), total - 1)
		T.eq(Shop.missing(data, Economy.ReactionBundle.items), 0)

		local saved = Economy.ReactionBundle.productId
		Economy.ReactionBundle.productId = 987654
		local kind, product = Economy.productById(987654)
		Economy.ReactionBundle.productId = saved
		T.eq(kind, "reactions")
		T.eq(product.key, "reactionsAll")
	end)
end
