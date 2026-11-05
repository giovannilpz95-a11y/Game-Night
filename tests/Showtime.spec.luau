local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Showtime = require(ReplicatedStorage.Shared.Showtime)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Core = ServerScriptService.Server.Core
local Profile = require(Core.Profile)
local Shop = require(Core.Shop)
local Moves = require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Table3D.Moves)

local function rel(x: number, y: number, z: number, w: number)
	return { x * w, y * w, z * w }
end

return function(T)
	T.test("every pose and celebration is a hub shop item in its slot", function()
		for kind, list in { pose = Showtime.Poses, victory = Showtime.Dances } do
			for _, move in list do
				local item = ShopCatalog.get(move.id)
				T.ok(item ~= nil, `{move.id} is not in the shop`)
				if item then
					T.eq(item.shop, "hub", move.id)
					T.eq(item.slot, Showtime.Slots[kind], move.id)
					T.eq(item.name, move.name, move.id)
					if not item.free then
						T.ok(item.gems ~= nil, `{move.id} needs a Gem price`)
						T.eq(item.universal, (item.gems :: number) * Economy.CoinsPerGem, move.id)
					end
				end
				T.eq(Showtime.kind(move.id), kind)
			end
		end
		for _, item in ShopCatalog.items do
			if item.slot == "pose" or item.slot == "victory" then
				T.ok(Showtime.get(item.id) ~= nil, `{item.id} is not in shared/Showtime`)
			end
		end
	end)

	T.test("there are free defaults, and paid ones to buy", function()
		for _, list in { Showtime.Poses, Showtime.Dances } do
			local free, paid = 0, 0
			for _, move in list do
				if ShopCatalog.isFree(move.id) then
					free += 1
				else
					paid += 1
				end
			end
			T.ok(free >= 2, "at least two free")
			T.ok(paid >= 6, "plenty to buy")
		end
		T.ok(ShopCatalog.isFree(Showtime.Poses[1].id), "the first pose is the free default")
		T.ok(ShopCatalog.isFree(Showtime.Dances[1].id), "the first celebration is the free default")
	end)

	T.test("every move has an animation on the client and every celebration has particles", function()
		for _, move in Showtime.Poses do
			local build = Moves.poses[move.id]
			T.ok(build ~= nil, `no pose in client/Table3D/Moves for {move.id}`)
			if build then
				for _, t in { 0, 0.7, 1.6, 2.3 } do
					T.ok(type(build(t, 1, rel)) == "table", `{move.id} at {t}`)
				end
			end
		end
		for _, move in Showtime.Dances do
			local build = Moves.dances[move.id]
			T.ok(build ~= nil, `no celebration in client/Table3D/Moves for {move.id}`)
			if build then
				for _, t in { 0, 1.3, 2.9, 3.2, 5.4 } do
					T.ok(type(build(t, 1, rel)) == "table", `{move.id} at {t}`)
				end
			end
			T.ok(move.fx ~= nil and Showtime.Fx[move.fx] ~= nil, `{move.id} needs known particles`)
		end
		for id in Moves.poses do
			T.eq(Showtime.kind(id), "pose", id)
		end
		for id in Moves.dances do
			T.eq(Showtime.kind(id), "victory", id)
		end
	end)

	T.test("pick uses what's equipped and owned, else the free default", function()
		local isFree = ShopCatalog.isFree
		T.eq(Showtime.pick("pose", nil, nil, isFree), "pose_wave")
		T.eq(Showtime.pick("victory", nil, nil, isFree), "win_pump")
		T.eq(Showtime.pick("pose", { pose = "pose_flex" }, {}, isFree), "pose_flex", "free ones need no owning")
		T.eq(Showtime.pick("pose", { pose = "pose_bow" }, {}, isFree), "pose_wave", "not owned")
		T.eq(Showtime.pick("pose", { pose = "pose_bow" }, { pose_bow = true }, isFree), "pose_bow")
		T.eq(Showtime.pick("victory", { victory = "pose_bow" }, { pose_bow = true }, isFree), "win_pump", "wrong kind")
		T.eq(Showtime.pick("victory", { victory = 42 }, {}, isFree), "win_pump", "junk")
	end)

	T.test("bots pick from the whole list", function()
		T.eq(Showtime.botPick("pose", function()
			return 1
		end), Showtime.Poses[1].id)
		T.eq(Showtime.botPick("victory", function(n)
			return n
		end), Showtime.Dances[#Showtime.Dances].id)
		T.eq(Showtime.botPick("pose", function()
			return 999
		end), Showtime.Poses[#Showtime.Poses].id, "clamped")
	end)

	T.test("the intro stays short at big tables", function()
		T.eq(Showtime.shotSeconds(2), Showtime.ShotSeconds)
		for seats = 1, 8 do
			T.ok(Showtime.introSeconds(seats) <= Showtime.MaxIntroSeconds + Showtime.IntroTail + 0.001, `{seats} seats`)
			T.ok(Showtime.shotSeconds(seats) >= Showtime.MinShotSeconds, `{seats} seats`)
		end
		T.eq(Showtime.shotStart(1, 4), Showtime.IntroLead)
		T.ok(Showtime.shotStart(4, 4) + Showtime.shotSeconds(4) <= Showtime.introSeconds(4), "last shot fits")
	end)

	T.test("free items can be equipped without buying, and can't be bought", function()
		local data = Profile.new(0)
		T.ok(Shop.toggleEquip(data, "pose_thumbs"))
		T.eq(data.equipped.hub.pose, "pose_thumbs")
		T.eq((Shop.buy(data, "pose_thumbs", "gems", false)), false)
		T.eq((Shop.toggleEquip(data, "win_champion")), false, "not owned")
		data.gems = 1000
		T.ok(Shop.buy(data, "win_champion", "gems", false))
		T.ok(Shop.toggleEquip(data, "win_champion"))
		T.eq(data.equipped.hub.victory, "win_champion")
		T.eq(data.equipped.hub.pose, "pose_thumbs", "separate slots")
		data.coins[Economy.UniversalCoin.key] = 5000
		T.ok(Shop.buy(data, "pose_bow", "universal", false))
	end)
end
