local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Showtime = require(ReplicatedStorage.Shared.Showtime)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Core = ServerScriptService.Server.Core
local Profile = require(Core.Profile)
local Shop = require(Core.Shop)
local Table3D = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Table3D
local Moves = require(Table3D.Moves)
local Dance = require(Table3D.Dance)

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
					if item.season then
						T.ok(item.notForSale == true, `{move.id} is a pass reward, never sold`)
					elseif not item.free then
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

	T.test("every move has well-formed keyframes on the client, and particle colors", function()
		for _, list in { Showtime.Poses, Showtime.Dances } do
			for _, info in list do
				local move = Moves.get(info.id)
				T.ok(move ~= nil, `no keyframes in client/Table3D/Moves for {info.id}`)
				T.ok(info.fx ~= nil and Showtime.Fx[info.fx] ~= nil, `{info.id} needs known particles`)
				if move then
					local last = -1
					for _, key in move.keys do
						T.ok(key.t >= last, `{info.id}: keys out of order at {key.t}`)
						last = key.t
						for name, value in key do
							if name ~= "t" and name ~= "e" then
								T.ok(Dance.Joints[name] ~= nil, `{info.id}: unknown joint {name}`)
								T.ok(type(value) == "table", `{info.id}: {name} needs numbers`)
							end
						end
					end
					T.ok(last <= move.length + 1e-6, `{info.id}: keys past its length`)
					if move.loop then
						T.ok(move.loop[1] < move.loop[2] and move.loop[2] <= move.length + 1e-6, `{info.id}: bad loop`)
					end
					-- Sample it over a whole celebration: numbers stay sane.
					for t = 0, Showtime.VictorySeconds, 0.05 do
						for name, v in Dance.sample(move, t) do
							for i = 1, 4 do
								T.ok(v[i] == v[i] and math.abs(v[i]) <= 400, `{info.id}: {name} at {t}`)
							end
							for i = 5, 7 do
								T.ok(v[i] == v[i] and math.abs(v[i]) <= 3, `{info.id}: {name} moves too far at {t}`)
							end
						end
					end
					for _, cue in move.cues or {} do
						T.ok(cue.t >= 0 and cue.t <= move.length, `{info.id}: cue out of range`)
					end
				end
			end
		end
		for id in Moves.poses do
			T.eq(Showtime.kind(id), "pose", id)
		end
		for id in Moves.dances do
			T.eq(Showtime.kind(id), "victory", id)
		end
	end)

	T.test("poses hit their pose while the camera is on them", function()
		for _, info in Showtime.Poses do
			local move = Moves.get(info.id)
			local strike = 0
			for _, cue in (move and move.cues) or {} do
				strike = math.max(strike, if strike == 0 then cue.t else strike)
			end
			T.ok(strike > 0 and strike < Showtime.MinShotSeconds - 0.3, `{info.id} strikes too late`)
		end
	end)

	T.test("dance engine: eases, loops, mirrors and cues", function()
		T.eq(Dance.ease("lin", 0.5), 0.5)
		T.ok(Dance.ease("back", 0.7) > 1, "back overshoots")
		T.eq(Dance.ease("hold", 0.99), 0)
		local move = {
			length = 1,
			loop = { 0.5, 1 },
			keys = { { t = 0, RS = { 0, 0, 0 } }, { t = 0.5, e = "lin", RS = { 90, 10, 20 } }, { t = 1, e = "lin", RS = { 0, 0, 0 } } },
			cues = { { t = 0.75, sound = "clap" } },
		}
		T.eq(Dance.sample(move, 0.25).RS[1], 45)
		T.eq(Dance.localTime(move, 1.25), 0.75)
		T.eq(Dance.sample(move, 1.25).RS[1], Dance.sample(move, 0.75).RS[1])
		T.eq(#Dance.cuesBetween(move, 0.7, 0.8), 1)
		T.eq(#Dance.cuesBetween(move, 1.2, 1.3), 1, "the loop repeats its cues")
		T.eq(#Dance.cuesBetween(move, 0.8, 1.2), 0)
		local m = Dance.mirror({ t = 0, RS = { 10, 20, 30, 40 }, R = { 0, 5, 6, 0, 0.5, 0, 0 } })
		T.eq(m.LS[1], 10)
		T.eq(m.LS[3], -30)
		T.eq(m.LS[4], -40)
		T.eq(m.RS, nil)
		T.eq(m.R[5], -0.5)
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
