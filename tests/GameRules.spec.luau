local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local GameRules = require(ReplicatedStorage.Shared.GameRules)
local Tips = require(ServerScriptService.Server.Core.Tips)

-- Lines are read on a phone, mid-game: keep them short.
local MAX_LINE = 200

return function(T)
	T.test("every game in the catalog has rules", function()
		for _, entry in GameCatalog.entries do
			if entry.module then
				T.ok(GameRules.get(entry.id) ~= nil, `{entry.id} has no entry in shared/GameRules.luau`)
			end
		end
	end)

	T.test("rules only name games that exist", function()
		for id in GameRules.rules do
			T.ok(GameCatalog.get(id) ~= nil, `GameRules has "{id}", which isn't in GameCatalog`)
		end
	end)

	T.test("every rules entry has a goal, a short card and a full page", function()
		for id, info in GameRules.rules do
			T.ok(type(info.goal) == "string" and #info.goal > 0 and #info.goal <= MAX_LINE, `{id}: goal`)
			T.ok(#info.card >= 2 and #info.card <= 4, `{id}: the card needs 2-4 lines`)
			for _, line in info.card do
				T.ok(type(line) == "string" and #line > 0 and #line <= MAX_LINE, `{id}: card line too long or empty`)
			end
			T.ok(#info.sections >= 1, `{id}: no sections`)
			for _, section in info.sections do
				T.ok(type(section.title) == "string" and #section.title > 0, `{id}: section without a title`)
				T.ok(#section.lines >= 1, `{id}: section "{section.title}" is empty`)
				for _, line in section.lines do
					T.ok(type(line) == "string" and #line > 0 and #line <= MAX_LINE, `{id}: line too long in "{section.title}"`)
				end
			end
		end
	end)

	T.test("tips: the lobby tour is remembered once", function()
		local state = Tips.new()
		T.eq(Tips.apply(state, { tip = "lobbyTour" }), true)
		T.eq(state.lobbyTour, true)
		T.eq(Tips.apply(state, { tip = "lobbyTour" }), false)
	end)

	T.test("tips: how-to-play cards can be turned off and on per game", function()
		local state = Tips.new()
		T.eq(Tips.apply(state, { tip = "hideCard", gameId = "Chess", hidden = true }), true)
		T.eq(state.hideCard.Chess, true)
		T.eq(Tips.apply(state, { tip = "hideCard", gameId = "Chess", hidden = true }), false)
		T.eq(Tips.apply(state, { tip = "hideCard", gameId = "Chess", hidden = false }), true)
		T.eq(state.hideCard.Chess, nil)
	end)

	T.test("tips: bad requests change nothing", function()
		local state = Tips.new()
		for _, request in {
			"lobbyTour",
			{},
			{ tip = "other" },
			{ tip = "hideCard", gameId = "NotAGame", hidden = true },
			{ tip = "hideCard", gameId = 5, hidden = true },
			{ tip = "hideCard", gameId = "Chess", hidden = "yes" },
			{ tip = "hideCard", gameId = "Chess" },
		} do
			T.eq(Tips.apply(state, request), false)
		end
		T.eq(state.lobbyTour, false)
		T.eq(next(state.hideCard), nil)
	end)
end
