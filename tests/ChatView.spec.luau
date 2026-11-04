local ServerScriptService = game:GetService("ServerScriptService")
local ChatView = require(ServerScriptService.Server.Core.ChatView)

return function(T)
	T.test("parse accepts only known views", function()
		T.eq(ChatView.parse("party"), "party")
		T.eq(ChatView.parse("all"), "all")
		T.eq(ChatView.parse("team"), nil)
		T.eq(ChatView.parse(1), nil)
		T.eq(ChatView.parse(nil), nil)
	end)

	T.test("party view shows only the party", function()
		local members = { 1, 2, 3 }
		T.ok(ChatView.shouldDeliver(2, 1, "party", members), "party member")
		T.eq(ChatView.shouldDeliver(9, 1, "party", members), false, "stranger hidden")
		T.eq(ChatView.shouldDeliver(9, 1, nil, members), false, "party is the default")
		T.ok(ChatView.shouldDeliver(1, 1, "party", members), "own message")
		T.ok(ChatView.shouldDeliver(nil, 1, "party", members), "system message")
	end)

	T.test("all view and solo players see everyone", function()
		T.ok(ChatView.shouldDeliver(9, 1, "all", { 1, 2 }))
		T.ok(ChatView.shouldDeliver(9, 1, "party", { 1 }), "party of one")
		T.ok(ChatView.shouldDeliver(9, 1, "party", nil), "no party")
	end)
end
